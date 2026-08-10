{- |
Module      : Cardano.KERI.ChainQuery.ProgramSpec
Description : #257 RED — operation surface and free-monad composition

Proves RQ-257-01 (the operation functor contains exactly the six current
snapshot reads), RQ-257-02 (programs are provider-neutral and compose with
ordinary 'Monad' syntax), and INV-257-PROVIDER (a program short-circuits on
the first error and never invokes a later operation — no fallback).
-}
module Cardano.KERI.ChainQuery.ProgramSpec (spec) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    runChainQuery,
 )
import Cardano.KERI.ChainQuery.Program (
    boardCatalog,
    currentCheckpoint,
    liveCheckpoints,
    payerUtxos,
    referenceScripts,
    storeWatermark,
 )
import Cardano.KERI.ChainQuery.Types (
    BoardEntry,
    BoardLocator (..),
    ChainAssetUtxo,
    ChainQueryError (..),
    ChainReference,
    CheckpointLocator (..),
    ColdOr (Cold),
    QuerySource (SourceLocal),
    SnapshotConsistency (AtomicLocal),
 )
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.Program" $ do
    it "composes all six operations in the declared order (RQ-257-01/02)" $ do
        callLog <- newIORef []
        let interpreter = loggingInterpreter callLog
            program = do
                _ <- currentCheckpoint testCheckpointLocator testAid
                _ <- liveCheckpoints testCheckpointLocator
                _ <- referenceScripts [canonicalHashHex 0x02, canonicalHashHex 0x03]
                _ <- boardCatalog testBoardLocator
                _ <- payerUtxos [canonicalAddress 0x04]
                storeWatermark
        result <- runChainQuery interpreter program
        result `shouldBe` Right Cold
        calls <- readIORef callLog
        reverse calls
            `shouldBe` [ "currentCheckpoint"
                       , "liveCheckpoints"
                       , "referenceScripts"
                       , "boardCatalog"
                       , "payerUtxos"
                       , "storeWatermark"
                       ]

    it "threads a pure computation between operations without an extra call" $ do
        callLog <- newIORef []
        let interpreter = loggingInterpreter callLog
            program = do
                checkpoints <- liveCheckpoints testCheckpointLocator
                let doubled = length checkpoints * 2 + 1
                _ <- payerUtxos (replicate doubled (canonicalAddress 0x05))
                storeWatermark
        _ <- runChainQuery interpreter program
        calls <- readIORef callLog
        reverse calls `shouldBe` ["liveCheckpoints", "payerUtxos", "storeWatermark"]

    it "short-circuits on the first error and never invokes a later operation (INV-257-PROVIDER)" $ do
        callLog <- newIORef []
        let interpreter =
                loggingInterpreterWith callLog $ \hashes -> do
                    modifyIORef' callLog ("referenceScripts" :)
                    pure (Left (ProviderFailure ("boom: " <> T.pack (show hashes))))
            program = do
                _ <- currentCheckpoint testCheckpointLocator testAid
                _ <- referenceScripts [canonicalHashHex 0x02]
                boardCatalog testBoardLocator
        result <- runChainQuery interpreter program
        case result of
            Left (ProviderFailure _) -> pure ()
            other -> fail ("expected ProviderFailure, got " <> show other)
        calls <- readIORef callLog
        reverse calls `shouldBe` ["currentCheckpoint", "referenceScripts"]

    exactOutputOperation

    boardOutputsOperation

{- | \#262 RQ-262-03\/DATA-INV-262-01: a concrete locator is validated the
moment the operation is BUILT, so an invalid one never becomes an operation
node and no interpreter -- local or Koios -- is ever given the chance to
answer it.

This is the layer at which that claim can actually fail, and the only one.
Against a real store an invalid locator simply matches no row, so a lazily
validating implementation looks identical; only a logging interpreter can
distinguish "rejected before dispatch" from "dispatched and found nothing".
The instrument is therefore the call log, and every example below reads it.
-}
exactOutputOperation :: Spec
exactOutputOperation =
    describe
        "#262 outputAt -- exact-output operation, RED against the closed \
        \test-local stand-in"
        $ do
            it "dispatches exactly one operation for a valid locator, in program order" $ do
                callLog <- newIORef []
                result <-
                    capExactOutput
                        redAlgebraCapabilities
                        (loggingInterpreter callLog)
                        validTxIdHex
                        3
                case result of
                    Right _ -> pure ()
                    Left err -> fail ("expected the operation to resolve, got " <> show err)
                calls <- readIORef callLog
                reverse calls `shouldBe` ["outputAt"]

            it "never reaches the interpreter for an invalid locator (DATA-INV-262-01)" $
                mapM_ rejectsWithoutDispatch invalidExactLocators

{- | Every shape a concrete exact-output locator can be wrong in. Upper-case
hex is included deliberately: it decodes to 32 bytes, so a validity check
written as "decodes to 32 bytes" admits an identity no canonical stored row
can ever equal.
-}
invalidExactLocators :: [(String, Text, Int)]
invalidExactLocators =
    [ ("a non-hexadecimal transaction id", T.replicate 64 "z", 0)
    , ("a short transaction id", T.replicate 62 "9", 0)
    , ("a long transaction id", T.replicate 66 "9", 0)
    , ("an upper-case transaction id", T.toUpper validTxIdHex, 0)
    , ("an empty transaction id", "", 0)
    , ("a negative output index", validTxIdHex, -1)
    , ("an output index outside the ledger range", validTxIdHex, 65536)
    ]

rejectsWithoutDispatch :: (String, Text, Int) -> IO ()
rejectsWithoutDispatch (label, txIdHex, index) = do
    callLog <- newIORef []
    result <-
        capExactOutput
            redAlgebraCapabilities
            (loggingInterpreter callLog)
            txIdHex
            index
    case result of
        Left (InvalidLocator _) -> pure ()
        other ->
            fail
                ("expected " <> label <> " to be rejected as an invalid locator, got " <> show other)
    calls <- readIORef callLog
    calls `shouldBe` []

{- | \#262 RQ-262-02\/DATA-INV-262-05: the board\/output operation is one
dispatch like every other, and a failing interpreter answer short-circuits
the program rather than falling through to another operation or another
provider.
-}
boardOutputsOperation :: Spec
boardOutputsOperation =
    describe
        "#262 boardCatalogWithOutputs -- board/output operation, RED against \
        \the closed test-local stand-in"
        $ do
            it "dispatches exactly one operation for a valid locator" $ do
                callLog <- newIORef []
                result <-
                    capBoardOutputs
                        redAlgebraCapabilities
                        (loggingInterpreter callLog)
                        (canonicalHashHex 0x01)
                        (canonicalAddress 0x01)
                case result of
                    Right _ -> pure ()
                    Left err -> fail ("expected the operation to resolve, got " <> show err)
                calls <- readIORef callLog
                reverse calls `shouldBe` ["boardCatalogWithOutputs"]

            it "never reaches the interpreter for an invalid board locator" $ do
                callLog <- newIORef []
                result <-
                    capBoardOutputs
                        redAlgebraCapabilities
                        (loggingInterpreter callLog)
                        "not-a-policy-id"
                        (canonicalAddress 0x01)
                case result of
                    Left (InvalidLocator _) -> pure ()
                    other -> fail ("expected an InvalidLocator, got " <> show other)
                calls <- readIORef callLog
                calls `shouldBe` []

{- | The two \#262 operations as one test-local adapter, taking the locator's
own PIECES rather than a locator value so the field types are identical
before and after implementation: RED closes them with a stand-in, GREEN
eta-expands them onto the real smart constructors, and no property body
above changes between the two.
-}
data AlgebraCapabilities = AlgebraCapabilities
    { capExactOutput ::
        ChainQueryInterpreter IO ->
        Text ->
        Int ->
        IO (Either ChainQueryError ChainAssetUtxo)
    , capBoardOutputs ::
        ChainQueryInterpreter IO ->
        Text ->
        Text ->
        IO (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])
    }

redAlgebraCapabilities :: AlgebraCapabilities
redAlgebraCapabilities =
    AlgebraCapabilities
        { capExactOutput = \_interpreter _txIdHex _index -> pure (Left notInTheAlgebraYet)
        , capBoardOutputs = \_interpreter _policyId _address -> pure (Left notInTheAlgebraYet)
        }

notInTheAlgebraYet :: ChainQueryError
notInTheAlgebraYet =
    UnsupportedOperation
        "the provider-neutral algebra has no exact-output or board/output operation yet"

-- | A canonical lower-case 32-byte transaction id.
validTxIdHex :: Text
validTxIdHex = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 32 0x91))

{- | A well-formed 44-character KERI E-code identifier, and genuinely
canonical hex\/bech32 locator\/address\/hash fixtures -- so every operation
in this file's programs actually reaches the interpreter under test
(DATA-INV-257-01's structural, eager validation rejects a non-canonical
argument before any interpreter is ever invoked, at either provider).
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

{- | An interpreter that logs every call it receives (in reverse-call order)
and answers every operation with an empty/cold, always-succeeding value.
-}
loggedCall :: IORef [String] -> String -> IO a -> IO (Either ChainQueryError a)
loggedCall callLog name answer = do
    modifyIORef' callLog (name :)
    Right <$> answer

loggingInterpreterWith ::
    IORef [String] ->
    ([Text] -> IO (Either ChainQueryError [ChainReference])) ->
    ChainQueryInterpreter IO
loggingInterpreterWith callLog referenceScriptsOp =
    chainQueryInterpreter
        (\_ _ -> loggedCall callLog "currentCheckpoint" (pure Nothing))
        (\_ -> loggedCall callLog "liveCheckpoints" (pure []))
        referenceScriptsOp
        (\_ -> loggedCall callLog "boardCatalog" (pure []))
        (\_ -> loggedCall callLog "payerUtxos" (pure []))
        (loggedCall callLog "storeWatermark" (pure Cold))
        SourceLocal
        AtomicLocal

loggingInterpreter :: IORef [String] -> ChainQueryInterpreter IO
loggingInterpreter callLog =
    loggingInterpreterWith callLog (\_ -> loggedCall callLog "referenceScripts" (pure []))
