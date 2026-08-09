{- |
Module      : Cardano.KERI.ChainQuery.RegistrationWiringSpec
Description : #257 RED — registration's current-state reads flow through the algebra

Proves RQ-257-08 (registration obtains its current-state inputs through one
selected algebra interpreter) and DATA-INV-257-04 (every
'Cardano.KERI.ChainQuery.Registration.RegistrationSnapshot' value belongs to
the same program result; no ambient query fills a missing field). The board
read is conditional exactly as today's preflight ("skip the board read when
no witnesses are declared"); this proof shows that branch is still
expressed inside the one composed program, not as a second query outside it.
-}
module Cardano.KERI.ChainQuery.RegistrationWiringSpec (spec) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    runChainQuery,
 )
import Cardano.KERI.ChainQuery.Registration (
    RegistrationQueryRequest (..),
    RegistrationSnapshot (..),
    registrationSnapshotProgram,
    runRegistrationSnapshot,
 )
import Cardano.KERI.ChainQuery.Types (
    BoardLocator (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainReference (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    QuerySnapshot (..),
    QuerySource (SourceKoios, SourceLocal),
    SnapshotConsistency (AtomicLocal, LegacySequential),
 )
import Codec.Binary.Bech32 qualified as Bech32
import Control.Monad (forM_)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.Registration (#257 S257-3)" $ do
    it "composes checkpoint + board + references + payer + watermark in one program (RQ-257-08)" $ do
        callLog <- newIORef []
        let interpreter = loggingInterpreter callLog
            request =
                RegistrationQueryRequest
                    { registrationQueryCheckpointLocator = testCheckpointLocator
                    , registrationQueryAid = testAid
                    , registrationQueryBoardLocator = Just testBoardLocator
                    , registrationQueryReferenceHashes = [canonicalHashHex 0x02, canonicalHashHex 0x03]
                    , registrationQueryPayerAddresses = [canonicalAddress 0x04]
                    }
        result <- runChainQuery interpreter (registrationSnapshotProgram request)
        case result of
            Right (Right RegistrationSnapshot{}) -> pure ()
            other -> fail ("expected a resolved RegistrationSnapshot, got " <> show other)
        calls <- readIORef callLog
        reverse calls
            `shouldBe` [ "currentCheckpoint"
                       , "boardCatalog"
                       , "referenceScripts"
                       , "payerUtxos"
                       , "storeWatermark"
                       ]

    it "skips the board read inside the same program when no board locator is requested (DATA-INV-257-04)" $ do
        callLog <- newIORef []
        let interpreter = loggingInterpreter callLog
            request =
                RegistrationQueryRequest
                    { registrationQueryCheckpointLocator = testCheckpointLocator
                    , registrationQueryAid = testAid
                    , registrationQueryBoardLocator = Nothing
                    , registrationQueryReferenceHashes = [canonicalHashHex 0x02]
                    , registrationQueryPayerAddresses = [canonicalAddress 0x04]
                    }
        _ <- runChainQuery interpreter (registrationSnapshotProgram request)
        calls <- readIORef callLog
        reverse calls `shouldBe` ["currentCheckpoint", "referenceScripts", "payerUtxos", "storeWatermark"]

    it "runRegistrationSnapshot exposes the real interpreter's own non-degenerate source/consistency/watermark for both local and Koios shapes (INV-257-CONSISTENCY, DATA-INV-257-03)"
        $ forM_
            [ (SourceLocal, AtomicLocal, Populated (ChainWatermark 42 "aaaa"))
            , (SourceKoios, LegacySequential, Populated (ChainWatermark 99 "bbbb"))
            ]
        $ \(source, consistency, watermark) -> do
            callLog <- newIORef []
            let interpreter =
                    loggingInterpreterWith
                        callLog
                        (\_ -> loggedCall callLog "referenceScripts" (pure []))
                        (pure (Right watermark))
                        source
                        consistency
                request =
                    RegistrationQueryRequest
                        { registrationQueryCheckpointLocator = testCheckpointLocator
                        , registrationQueryAid = testAid
                        , registrationQueryBoardLocator = Nothing
                        , registrationQueryReferenceHashes = []
                        , registrationQueryPayerAddresses = []
                        }
            result <- runRegistrationSnapshot interpreter request
            case result of
                Right envelope -> do
                    snapshotSource envelope `shouldBe` source
                    snapshotConsistency envelope `shouldBe` consistency
                    snapshotWatermark envelope `shouldBe` watermark
                Left err -> fail ("expected a resolved envelope, got " <> show err)

    it "propagates a candidate-resolution failure closed, never a partial snapshot" $ do
        callLog <- newIORef []
        let interpreter =
                loggingInterpreterWith
                    callLog
                    (\_ -> pure (Left (DecodingFailure "reference-script hash mismatch")))
                    (loggedCall callLog "storeWatermark" (pure Cold))
                    SourceKoios
                    LegacySequential
            request =
                RegistrationQueryRequest
                    { registrationQueryCheckpointLocator = testCheckpointLocator
                    , registrationQueryAid = testAid
                    , registrationQueryBoardLocator = Nothing
                    , registrationQueryReferenceHashes = [canonicalHashHex 0x02]
                    , registrationQueryPayerAddresses = [canonicalAddress 0x04]
                    }
        result <- runChainQuery interpreter (registrationSnapshotProgram request)
        case result of
            Left (DecodingFailure _) -> pure ()
            Right (Left (DecodingFailure _)) -> pure ()
            other -> fail ("expected a closed DecodingFailure, got " <> show other)

    it "the public entry point reads the watermark exactly once on success and never after an earlier operation's rejection (NOTE-021, DATA-INV-257-04/RQ-257-08)" $ do
        -- Success: exactly one "storeWatermark" call, not two -- the
        -- historical defect was registrationSnapshotProgram's own watermark
        -- read PLUS a second one appended afterwards by a generic snapshot
        -- wrapper that did not know about this program's inner Either.
        successLog <- newIORef []
        successResult <- runRegistrationSnapshot (loggingInterpreter successLog) successRequest
        case successResult of
            Right _ -> pure ()
            Left err -> fail ("expected a resolved envelope, got " <> show err)
        successCalls <- readIORef successLog
        length (filter (== "storeWatermark") successCalls) `shouldBe` 1

        -- Rejection: an interpreter-level failure on an EARLIER operation
        -- (referenceScripts) must stop every later action, including the
        -- watermark read -- no query/watermark action before or after a
        -- structural rejection.
        rejectionLog <- newIORef []
        let rejectingInterpreter =
                loggingInterpreterWith
                    rejectionLog
                    ( \_ -> do
                        modifyIORef' rejectionLog ("referenceScripts" :)
                        pure (Left (DecodingFailure "boom"))
                    )
                    (loggedCall rejectionLog "storeWatermark" (pure Cold))
                    SourceKoios
                    LegacySequential
        rejectionResult <-
            runRegistrationSnapshot
                rejectingInterpreter
                successRequest{registrationQueryReferenceHashes = [canonicalHashHex 0x02]}
        case rejectionResult of
            Left (DecodingFailure _) -> pure ()
            other -> fail ("expected a closed DecodingFailure, got " <> show other)
        rejectionCalls <- readIORef rejectionLog
        ("storeWatermark" `elem` rejectionCalls) `shouldBe` False

    it "performs no payer or watermark effect after a returned reference candidate fails closed (A-006, DATA-INV-257-04/RQ-257-08)" $ do
        -- Submission 6 rejected an invalid ARGUMENT before any later effect,
        -- but deferred every pure conversion to the end of the program, so a
        -- malformed RETURNED row was only detected after the payer and
        -- watermark reads had already been performed. Each acquisition is now
        -- converted immediately, so a fail-closed row stops those later
        -- effects exactly as an invalid argument does.
        callLog <- newIORef []
        let interpreter =
                loggingInterpreterWith
                    callLog
                    ( \_ -> do
                        modifyIORef' callLog ("referenceScripts" :)
                        pure (Right [malformedReference])
                    )
                    (loggedCall callLog "storeWatermark" (pure Cold))
                    SourceKoios
                    LegacySequential
        result <-
            runRegistrationSnapshot
                interpreter
                successRequest
                    { registrationQueryReferenceHashes = [canonicalHashHex 0x02]
                    , registrationQueryPayerAddresses = [canonicalAddress 0x04]
                    }
        case result of
            Left (DecodingFailure _) -> pure ()
            other -> fail ("expected a closed DecodingFailure, got " <> show other)
        calls <- reverse <$> readIORef callLog
        calls `shouldBe` ["currentCheckpoint", "referenceScripts"]
  where
    successRequest =
        RegistrationQueryRequest
            { registrationQueryCheckpointLocator = testCheckpointLocator
            , registrationQueryAid = testAid
            , registrationQueryBoardLocator = Nothing
            , registrationQueryReferenceHashes = []
            , registrationQueryPayerAddresses = []
            }

{- | A reference row whose transaction id cannot be decoded, so
'Cardano.KERI.ChainQuery.LedgerOutput.chainReferenceToLedgerOutput' fails
closed on it. Its script hash IS canonical, so the row is only rejectable
after it has been returned -- which is exactly the ordering A-006 constrains.
-}
malformedReference :: ChainReference
malformedReference =
    ChainReference
        { chainReferenceScriptHash = canonicalHashHex 0x02
        , chainReferenceOutput =
            ChainAssetUtxo
                { chainAssetTxId = "not-a-transaction-id"
                , chainAssetIndex = 0
                , chainAssetAddress = canonicalAddress 0x04
                , chainAssetLovelace = 1
                , chainAssetList = []
                , chainAssetInlineDatum = Nothing
                , chainAssetReferenceScript = Nothing
                }
        }

{- | A canonical AID and every locator\/hash\/address fixture this file
composes, so each operation actually reaches the interpreter under test
rather than being rejected structurally before interpretation
(DATA-INV-257-01).
-}
testAid :: Text
testAid = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

testCheckpointLocator :: CheckpointLocator
testCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = canonicalHashHex 0x00
        , checkpointLocatorAddress = canonicalAddress 0x00
        }

testBoardLocator :: BoardLocator
testBoardLocator =
    BoardLocator
        { boardLocatorPolicyId = canonicalHashHex 0x01
        , boardLocatorAddress = canonicalAddress 0x01
        }

canonicalHashHex :: Word8 -> Text
canonicalHashHex byte = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 byte))

canonicalAddress :: Word8 -> Text
canonicalAddress byte = Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes (BS.replicate 28 byte))

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

{- | Log one call and answer it successfully. Top level so the parameterised
builder below and its call sites can share it (NOTE-025: 'ChainQueryInterpreter'
is abstract, so a test double is assembled, never record-updated).
-}
loggedCall :: IORef [String] -> String -> IO a -> IO (Either ChainQueryError a)
loggedCall callLog name answer = do
    modifyIORef' callLog (name :)
    Right <$> answer

{- | An interpreter that logs every call it receives (in reverse-call order)
and answers every operation with an empty/absent value, with the reference
operation, watermark, source, and consistency supplied by the caller. This
replaces the record updates the tests used before the interpreter type became
abstract.
-}
loggingInterpreterWith ::
    IORef [String] ->
    ([Text] -> IO (Either ChainQueryError [ChainReference])) ->
    IO (Either ChainQueryError (ColdOr ChainWatermark)) ->
    QuerySource ->
    SnapshotConsistency ->
    ChainQueryInterpreter IO
loggingInterpreterWith callLog referenceScriptsOp =
    chainQueryInterpreter
        (\_ _ -> loggedCall callLog "currentCheckpoint" (pure Nothing))
        (\_ -> loggedCall callLog "liveCheckpoints" (pure []))
        referenceScriptsOp
        (\_ -> loggedCall callLog "boardCatalog" (pure []))
        (\_ -> loggedCall callLog "payerUtxos" (pure []))

-- | The default logging double: every operation empty\/absent, cold watermark.
loggingInterpreter :: IORef [String] -> ChainQueryInterpreter IO
loggingInterpreter callLog =
    loggingInterpreterWith
        callLog
        (\_ -> loggedCall callLog "referenceScripts" (pure []))
        (loggedCall callLog "storeWatermark" (pure Cold))
        SourceKoios
        LegacySequential
