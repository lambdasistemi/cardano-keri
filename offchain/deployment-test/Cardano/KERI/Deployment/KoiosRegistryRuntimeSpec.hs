{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.KoiosRegistryRuntimeSpec
Description : the Koios instance of the registry runtime routes every call to its own part and says what the handoff and the settlement came to

The instance is assembled from parts: the reads, a signer, a handoff, a
settlement and a report. Each field of the runtime must reach its own part and
no other, a handoff that may have reached the provider must reach the command
as an exception whose text is the handoff's own report, and a transaction is
observed under the signed bytes that were handed over. The instance built from
an access is run over a loopback stand-in for the service: its token is a file
this test writes and is sent by the transport, never shown. Expected bytes and
ids are obtained from the ledger at run time; nothing here reads a real token.
-}
module Cardano.KERI.Deployment.KoiosRegistryRuntimeSpec (spec) where

import Cardano.Crypto.DSIGN (SignKeyDSIGN, genKeyDSIGN)
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.Deployment.KoiosRegistryRuntime (
    KoiosAccess (..),
    KoiosParts (..),
    KoiosStartFailure (..),
    koiosRegistryRuntime,
    openKoiosRuntime,
 )
import Cardano.KERI.Deployment.KoiosRuntime (KoiosFailure (..), KoiosReads (..))
import Cardano.KERI.Deployment.KoiosSettlement (Refusal (..), Settlement (..), Unsettlement (..), renderUnsettlement)
import Cardano.KERI.Deployment.KoiosStandIn (Reply (..), Seen (..), answering, withStandIn)
import Cardano.KERI.Deployment.KoiosSubmission (Handoff (..), HandoffFailure (..), HandoffResult (..), renderHandoff)
import Cardano.KERI.Deployment.NodeSocketRuntime (KeySource (..))
import Cardano.KERI.Deployment.RegistryChain (Observation (..), RegistryRuntime (..), ValidityEnd (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (walletAddress)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (AccountAddress (..), AccountId (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Api.PParams (ppTxFeeFixedL)
import Cardano.Ledger.Api.Tx (mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, mkBasicTxBody)
import Cardano.Ledger.Api.Tx.Out (mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (..), TxIx (..))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams, emptyPParams, eraProtVerHigh)
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult, SlotNo (..))
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Control.Exception (SomeException, try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Lens.Micro ((&), (.~))
import Singular.Provider.Koios.Client (FailureReason (..))
import Singular.Registry.Confirmation (ConfirmationFailure (..))
import Singular.Registry.Signing (SignedTx, signTx, signedTx)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "the Koios instance of the registry runtime" $ do
    routingSpec
    handoffSpec
    settlementSpec
    openedSpec

-- ---------------------------------------------------------------------
-- Material, obtained from the ledger
-- ---------------------------------------------------------------------

testKey :: SignKeyDSIGN Ed25519DSIGN
testKey = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 9))

-- | A transaction signed once; the fee tells two of them apart.
signedWithFee :: Integer -> SignedTx
signedWithFee fee =
    signTx testKey (mkBasicTx (mkBasicTxBody & feeTxBodyL .~ Coin fee) :: ConwayTx)

firstTx, secondTx :: ConwayTx
firstTx = signedTx (signedWithFee 170_000)
secondTx = signedTx (signedWithFee 180_000)

bytesOf :: ConwayTx -> BS.ByteString
bytesOf = serialize' (eraProtVerHigh @ConwayEra)

txIdOfByte :: Int -> TxId
txIdOfByte b = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 (fromIntegral b)))))

-- | What the parts did, in order.
type Log = IORef [String]

noted :: Log -> String -> IO ()
noted ref label = modifyIORef' ref (<> [label])

-- ---------------------------------------------------------------------
-- A runtime over scripted parts
-- ---------------------------------------------------------------------

sentinelParameters :: PParams ConwayEra
sentinelParameters = emptyPParams & ppTxFeeFixedL .~ Coin 123_456

sentinelObservation :: Observation
sentinelObservation =
    Observation
        { obsTipSlot = SlotNo 7_001
        , obsTipStartMs = 1_700_000_007_000
        , obsSlotLengthMs = 1_000
        , obsClockMs = 1_700_000_007_250
        , obsHorizonSlot = SlotNo 9_000
        }

reference :: Int -> Integer -> TxIn
reference b ix = TxIn (txIdOfByte b) (TxIx (fromInteger ix))

sentinelEvaluation :: EvaluateTxResult ConwayEra
sentinelEvaluation = Map.fromList [(ConwaySpending (AsIx 3), Right (ExUnits 5 6))]

-- | Parts that note which one was called, and answer a sentinel of their own.
scripted :: Log -> Handoff -> Settlement -> KoiosParts
scripted ref handoff settlement =
    KoiosParts
        { partReads =
            KoiosReads
                { readUtxosAt = \address -> do
                    noted ref "reads:utxos-at"
                    pure [(reference 1 0, mkBasicTxOut address (MaryValue (Coin 11_000_000) (MultiAsset Map.empty)))]
                , readOutputs = \wanted -> do
                    noted ref ("reads:outputs " <> show (Set.size wanted))
                    pure (Map.fromList [(r, mkBasicTxOut walletAddress (MaryValue (Coin 3_000_000) (MultiAsset Map.empty))) | r <- Set.toList wanted])
                , readProtocolParameters = noted ref "reads:parameters" >> pure sentinelParameters
                , readObservation = noted ref "reads:observation" >> pure sentinelObservation
                , readEvaluation = \_ -> noted ref "reads:evaluation" >> pure sentinelEvaluation
                , readRewardRegistered = \_ -> noted ref "reads:reward" >> pure True
                }
        , partSign = \tx -> noted ref "sign" >> pure (Right tx)
        , partHandoff = \_ -> noted ref "handoff" >> pure handoff
        , partSettle = \tx -> noted ref ("settle " <> show (transactionId tx)) >> pure (Right settlement)
        , partReport = \_ -> noted ref "report"
        , partClock = noted ref "clock" >> pure 1_700_000_009_000
        , partWindow = pure EndNotSet
        }

routingSpec :: Spec
routingSpec = describe "every field of the runtime" $ do
    it "reaches the part that reads it and no other, and answers what that part answered" $ do
        ref <- newIORef []
        runtime <- koiosRegistryRuntime (scripted ref (Handoff (transactionId firstTx) 1 Accepted) Settled)
        rtNetwork runtime `shouldBe` Testnet
        found <- rtUtxosAt runtime walletAddress
        map fst found `shouldBe` [reference 1 0]
        readIORef ref >>= (`shouldBe` ["reads:utxos-at"])
        writeIORef ref []
        held <- rtOutputs runtime (Set.fromList [reference 2 0, reference 3 1])
        Map.keys held `shouldBe` [reference 2 0, reference 3 1]
        readIORef ref >>= (`shouldBe` ["reads:outputs 2"])
        writeIORef ref []
        registered <- rtRewardRegistered runtime (AccountAddress Testnet (AccountId (ScriptHashObj (ScriptHash (fromJust (hashFromBytes (BS.replicate 28 4)))))))
        registered `shouldBe` True
        readIORef ref >>= (`shouldBe` ["reads:reward"])
        writeIORef ref []
        observed <- rtObserve runtime
        observed `shouldBe` sentinelObservation
        readIORef ref >>= (`shouldBe` ["reads:observation"])
        writeIORef ref []
        now <- rtNowMs runtime
        now `shouldBe` 1_700_000_009_000
        readIORef ref >>= (`shouldBe` ["clock"])
        writeIORef ref []
        parameters <- trQueryProtocolParams (rtTransactions runtime)
        parameters `shouldBe` sentinelParameters
        readIORef ref >>= (`shouldBe` ["reads:parameters"])
        writeIORef ref []
        evaluated <- trEvaluate (rtTransactions runtime) firstTx
        Map.keys evaluated `shouldBe` Map.keys sentinelEvaluation
        readIORef ref >>= (`shouldBe` ["reads:evaluation"])
        writeIORef ref []
        signed <- trSign (rtTransactions runtime) firstTx
        signed `shouldBe` Right firstTx
        readIORef ref >>= (`shouldBe` ["sign"])

-- ---------------------------------------------------------------------
-- The handoff
-- ---------------------------------------------------------------------

-- | Hand one transaction over and say what the runtime gave back or threw, with what the parts did.
handedOver :: Handoff -> IO (Either String (Either BS.ByteString TxId), [String])
handedOver handoff = do
    ref <- newIORef []
    runtime <- koiosRegistryRuntime (scripted ref handoff Settled)
    outcome <- try @SomeException (trSubmit (rtTransactions runtime) firstTx)
    performed <- readIORef ref
    pure (either (Left . show) (Right . summary) outcome, performed)

-- | What a submission came to: the refusal text, or the id it was submitted under.
summary :: SubmitResult -> Either BS.ByteString TxId
summary = \case
    Submitted submitted -> Right submitted
    Rejected reason -> Left reason

handoffSpec :: Spec
handoffSpec = describe "the handoff" $ do
    let txId = transactionId firstTx
    it "is given the signed transaction as its own serialization, and an accepted one is submitted under its id" $ do
        seen <- newIORef []
        ref <- newIORef []
        let parts = (scripted ref (Handoff txId 1 Accepted) Settled){partHandoff = \signed -> modifyIORef' seen (<> [signedTx signed]) >> pure (Handoff txId 1 Accepted)}
        runtime <- koiosRegistryRuntime parts
        outcome <- trSubmit (rtTransactions runtime) firstTx
        summary outcome `shouldBe` Right txId
        handed <- readIORef seen
        map bytesOf handed `shouldBe` [bytesOf firstTx]

    it "reports every handoff it makes, the accepted one too, before it answers" $ do
        (_, performed) <- handedOver (Handoff txId 3 Accepted)
        performed `shouldBe` ["handoff", "report"]

    it "is a refusal, with the provider's text, when the first attempt was refused" $ do
        (outcome, _) <- handedOver (Handoff txId 1 (Refused "BadInputsUTxO"))
        outcome `shouldBe` Right (Left (B8.pack "BadInputsUTxO"))

    it "is not a refusal when an earlier attempt got no answer: it may have been delivered, so the command is told so" $ do
        let handoff = Handoff txId 2 (Refused "BadInputsUTxO")
        (outcome, performed) <- handedOver handoff
        outcome `shouldBe` Left (T.unpack (renderHandoff handoff))
        T.unpack (renderHandoff handoff) `shouldSatisfy` ("an earlier attempt got no answer: may or may not have reached the provider; check it before spending again" `isInfixOf`)
        performed `shouldBe` ["handoff", "report"]

    it "decides what it answers from the handoff alone: a report that cannot be written changes nothing"
        $ forM_
            [ (Handoff txId 1 Accepted, Right (Right txId))
            , (Handoff txId 1 (Refused "BadInputsUTxO"), Right (Left (B8.pack "BadInputsUTxO")))
            , (Handoff txId 2 (Refused "BadInputsUTxO"), Left (T.unpack (renderHandoff (Handoff txId 2 (Refused "BadInputsUTxO")))))
            , (Handoff txId 3 NoAnswer, Left (T.unpack (renderHandoff (Handoff txId 3 NoAnswer))))
            ]
        $ \(handoff, expected) -> do
            ref <- newIORef []
            runtime <- koiosRegistryRuntime ((scripted ref handoff Settled){partReport = \_ -> ioError (userError "cannot encode character")})
            outcome <- try @SomeException (trSubmit (rtTransactions runtime) firstTx)
            either (Left . show) (Right . summary) outcome `shouldBe` expected

    it "is told as unknown, with the attempts, when no attempt was answered" $
        forM_ [1, 3, 5] $ \attempts -> do
            let handoff = Handoff txId attempts NoAnswer
            (outcome, _) <- handedOver handoff
            outcome `shouldBe` Left (T.unpack (renderHandoff handoff))
            T.unpack (renderHandoff handoff)
                `shouldSatisfy` ((show attempts <> " attempt") `isInfixOf`)

    it "is told as unknown when the provider answered something that is neither an acceptance nor a refusal"
        $ forM_
            [ Handoff txId 1 (Failed (AnsweredUnusably (ServerFailing 500 "internal error")))
            , Handoff txId 1 (Failed (AcceptedAnotherTransaction (txIdOfByte 9)))
            ]
        $ \handoff -> do
            (outcome, _) <- handedOver handoff
            outcome `shouldBe` Left (T.unpack (renderHandoff handoff))

-- ---------------------------------------------------------------------
-- The settlement
-- ---------------------------------------------------------------------

observedAfter :: Settlement -> [ConwayTx] -> TxId -> IO (Either String (), [String])
observedAfter settlement handed wanted = do
    ref <- newIORef []
    runtime <- koiosRegistryRuntime (scripted ref (Handoff (transactionId firstTx) 1 Accepted) settlement)
    forM_ handed $ \tx -> trSubmit (rtTransactions runtime) tx
    writeIORef ref []
    outcome <- try @SomeException (trObserve (rtTransactions runtime) wanted)
    performed <- readIORef ref
    pure (either (Left . show) Right outcome, performed)

settlementSpec :: Spec
settlementSpec = describe "the settlement of a transaction handed over" $ do
    let first = transactionId firstTx
        second = transactionId secondTx
        unsettled =
            Unsettlement
                { unsettledTransaction = first
                , unsettledBy = ConfirmationNoOutput first
                , unsettledDeadlineMs = 1_700_000_120_000
                , unsettledBoundSeconds = Just 150
                }
    it "is read of the transaction as it was handed over, the first of two, whichever was handed over last" $ do
        (outcome, performed) <- observedAfter Settled [firstTx, secondTx] first
        outcome `shouldBe` Right ()
        performed `shouldBe` ["settle " <> show first]
        (other, performedOther) <- observedAfter Settled [firstTx, secondTx] second
        other `shouldBe` Right ()
        performedOther `shouldBe` ["settle " <> show second]

    it "ends in the report of the settlement, the time to look again at, and the bound as it is" $ do
        (outcome, _) <- observedAfter (NotSettled unsettled) [firstTx] first
        case outcome of
            Left message -> do
                message `shouldSatisfy` (T.unpack (renderUnsettlement unsettled) `isInfixOf`)
                message `shouldSatisfy` ("look again after 1700000120000 ms since the epoch" `isInfixOf`)
                message `shouldSatisfy` ("may or may not have reached the provider; check it before spending again" `isInfixOf`)
                message `shouldSatisfy` ("may run a few seconds after" `isInfixOf`)
            Right () -> expectationFailure "an unsettled transaction was observed"

    it "is refused by name when the settlement refuses the transaction" $ do
        let refusal = TransactionWithoutValidityEnd first
        ref <- newIORef []
        runtime <- koiosRegistryRuntime ((scripted ref (Handoff first 1 Accepted) Settled){partSettle = \_ -> pure (Left refusal)})
        _ <- trSubmit (rtTransactions runtime) firstTx
        outcome <- try @SomeException (trObserve (rtTransactions runtime) first)
        either show (const "observed") outcome `shouldSatisfy` ("TransactionWithoutValidityEnd" `isInfixOf`)

    it "is refused by name, and nothing is read, for a transaction that was never handed over" $ do
        (outcome, performed) <- observedAfter Settled [firstTx] second
        performed `shouldBe` []
        case outcome of
            Left message -> message `shouldSatisfy` (T.unpack (renderTransactionId second) `isInfixOf`)
            Right () -> expectationFailure "a transaction never handed over was observed"

-- ---------------------------------------------------------------------
-- The instance built from an access, over a loopback stand-in
-- ---------------------------------------------------------------------

-- | An answer of no rows that states its total, as the service does.
emptyPage :: Reply
emptyPage = Reply 0 200 [("Content-Range", "*/0")] "[]" False

accessAt :: Text -> Maybe FilePath -> KoiosAccess
accessAt url token =
    KoiosAccess
        { koiosUrl = url
        , koiosTokenFile = token
        , koiosNetworkMagic = 1
        , koiosFundingAddress = "addr_test1unused"
        , koiosSigningKey = KeyFile "no-key.skey"
        , koiosNetworkTime = Nothing
        }

openedSpec :: Spec
openedSpec = describe "the instance built from an access" $ do
    it "reads over the transport with the token the transport reads from its file, and shows it nowhere" $
        withSystemTempDirectory "koios-registry-runtime" $ \scratch ->
            withStandIn (\_ _ -> emptyPage) $ \url seen -> do
                let tokenFile = scratch <> "/token"
                    token = "test-token-0123456789abcdef-0123456789abcdef"
                    access = accessAt url (Just tokenFile)
                writeFile tokenFile (token <> "\n")
                opened <- openKoiosRuntime (\_ -> pure ()) access
                runtime <- either (fail . show) pure opened
                found <- rtUtxosAt runtime walletAddress
                found `shouldBe` []
                requests <- seen
                length requests `shouldSatisfy` (>= 1)
                [lookup "authorization" (seenHeaders request) | request <- requests]
                    `shouldBe` replicate (length requests) (Just (T.pack ("Bearer " <> token)))
                show access `shouldSatisfy` (not . (token `isInfixOf`))

    it "is refused by name, before any request, for a network whose time is not pinned" $
        withStandIn (\_ _ -> answering 200 "[]") $ \url seen -> do
            opened <- openKoiosRuntime (\_ -> pure ()) ((accessAt url Nothing){koiosNetworkMagic = 42})
            case opened of
                Left (NetworkNotPinned 42) -> pure ()
                Left other -> expectationFailure ("another refusal: " <> show other)
                Right _ -> expectationFailure "the instance was built for a network whose time is not pinned"
            requests <- seen
            length requests `shouldBe` 0

    it "is refused by name, before any request, when the token file cannot be read" $
        withSystemTempDirectory "koios-registry-runtime" $ \scratch ->
            withStandIn (\_ _ -> answering 200 "[]") $ \url seen -> do
                opened <- openKoiosRuntime (\_ -> pure ()) (accessAt url (Just (scratch <> "/no-token-here")))
                case opened of
                    Left (TokenUnreadable message) -> T.unpack message `shouldSatisfy` ("no-token-here" `isInfixOf`)
                    Left other -> expectationFailure ("another refusal: " <> show other)
                    Right _ -> expectationFailure "the instance was built without its token"
                requests <- seen
                length requests `shouldBe` 0

    it "reads an answer the service marks as partial as a named failure, not as a whole one" $
        withStandIn (\_ _ -> answering 206 "[]") $ \url _ -> do
            runtime <- openKoiosRuntime (\_ -> pure ()) (accessAt url Nothing) >>= either (fail . show) pure
            outcome <- try @KoiosFailure (rtUtxosAt runtime walletAddress)
            case outcome of
                Left (KoiosCallFailed _) -> pure ()
                Left other -> expectationFailure ("another failure: " <> show other)
                Right found -> expectationFailure ("a partial answer was read as whole: " <> show (length found))
