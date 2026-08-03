{- |
Module      : Cardano.KERI.CLI.Backend.ContractSpec
Description : #177 Slice 1 T177-S1-2 common adapter contract (RED)

Exercises the one common seam ('runBackendStatus'/'renderStatusView') every
backend feeds, using a fake 'QueryBackend' — the adapter-specific tests
('LocalSpec'/'EndpointSpec'/'KoiosSpec') prove each real adapter maps onto
this same contract.
-}
module Cardano.KERI.CLI.Backend.ContractSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.CLI.Backend (
    BackendError (..),
    CheckpointFields (..),
    CheckpointListItem (..),
    CheckpointListView (..),
    CheckpointView (..),
    Freshness (..),
    PayerUtxoFields (..),
    PayerView (..),
    QueryBackend (..),
    StatusView (..),
    WatchabilityFields (..),
    renderCheckpointListView,
    renderCheckpointView,
    renderPayerView,
    renderStatusView,
    runBackendCheckpointByAid,
    runBackendListCheckpoints,
    runBackendPayerUtxos,
    runBackendStatus,
 )
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "runBackendStatus / renderStatusView common contract (T177-S1-2)" $ do
    it "a successful answer round-trips through the one common StatusView" $ do
        result <- runBackendStatus (fakeBackend "koios" (pure . Right . sampleView)) sampleAid
        result `shouldBe` Right (sampleView sampleAid)

    it "the rendered text carries the source label and no adapter-specific format" $
        renderStatusView (sampleView sampleAid)
            `shouldSatisfy` (\text -> "source koios" `T.isInfixOf` text && "as_of_slot 100" `T.isInfixOf` text)

    it "a malformed upstream payload is a closed MalformedResponse error, not a partial answer" $ do
        result <-
            runBackendStatus
                (fakeBackend "endpoint" (\_ -> pure (Left (MalformedResponse "mismatched echoed aid"))))
                sampleAid
        result `shouldBe` Left (MalformedResponse "mismatched echoed aid")

    it "an unsupported capability is a named closed error, not a silent empty answer" $ do
        result <-
            runBackendStatus
                (fakeBackend "endpoint" (\_ -> pure (Left (UnsupportedCapability "board catalog listing"))))
                sampleAid
        result `shouldBe` Left (UnsupportedCapability "board catalog listing")

    it "an upstream-unavailable failure is closed, never a stale/partial answer" $ do
        result <-
            runBackendStatus
                (fakeBackend "koios" (\_ -> pure (Left (UpstreamUnavailable "connection refused"))))
                sampleAid
        result `shouldBe` Left (UpstreamUnavailable "connection refused")

    it "checkpoint listing dispatches exactly qbListCheckpoints" $ do
        calls <- newIORef []
        result <- runBackendListCheckpoints (recordingBackend calls)
        result `shouldSatisfy` isUnsupported "fake list"
        readIORef calls >>= (`shouldBe` ["list"])

    it "checkpoint-by-AID dispatches exactly qbCheckpointByAid" $ do
        calls <- newIORef []
        result <- runBackendCheckpointByAid (recordingBackend calls) sampleAid
        result `shouldSatisfy` isUnsupported "fake checkpoint"
        readIORef calls >>= (`shouldBe` ["checkpoint"])

    it "payer UTxOs dispatch exactly qbPayerUtxos" $ do
        calls <- newIORef []
        result <- runBackendPayerUtxos (recordingBackend calls) sampleAddress
        result `shouldSatisfy` isUnsupported "fake payer"
        readIORef calls >>= (`shouldBe` ["payer"])

    it "checkpoint-by-AID rejects an invalid AID before invoking the selected backend" $ do
        calls <- newIORef []
        result <- runBackendCheckpointByAid (recordingBackend calls) "not-an-aid"
        result `shouldSatisfy` isMalformed
        readIORef calls >>= (`shouldBe` [])

    it "payer UTxOs reject an invalid address before invoking the selected backend" $ do
        calls <- newIORef []
        result <- runBackendPayerUtxos (recordingBackend calls) "not-an-address"
        result `shouldSatisfy` isMalformed
        readIORef calls >>= (`shouldBe` [])

    it "renders checkpoint lists through the common source/freshness envelope" $
        renderCheckpointListView
            CheckpointListView
                { clvSource = "local"
                , clvFreshness = Freshness (Just 100) Nothing
                , clvCheckpoints = [CheckpointListItem sampleAid sampleCheckpoint]
                }
            `shouldBe` "source local as_of_slot 100 tip_lag_slots unknown\ncount 1\naid EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA state ACTIVE seq 1 native 1 keys 1-of-1 witnesses 0 (toad 0) tx aa#0"

    it "renders checkpoint-by-AID through the common source/freshness envelope" $
        renderCheckpointView
            CheckpointView
                { cvSource = "endpoint"
                , cvFreshness = Freshness (Just 100) (Just 2)
                , cvAid = sampleAid
                , cvCheckpoint = Just sampleCheckpoint
                }
            `shouldBe` "source endpoint as_of_slot 100 tip_lag_slots 2\naid EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA state ACTIVE seq 1 native 1 keys 1-of-1 witnesses 0 (toad 0) tx aa#0"

    it "renders payer UTxOs through the common source/freshness envelope" $
        renderPayerView
            PayerView
                { pvSource = "koios"
                , pvFreshness = Freshness (Just 100) (Just 3)
                , pvAddress = sampleAddress
                , pvUtxos = [PayerUtxoFields "bb" 1]
                }
            `shouldBe` "source koios as_of_slot 100 tip_lag_slots 3\naddress addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d count 1\ntx bb#1"

fakeBackend :: Text -> (Text -> IO (Either BackendError StatusView)) -> QueryBackend
fakeBackend label status =
    QueryBackend
        { qbSourceLabel = label
        , qbStatus = status
        , qbBoardByWitness = \_ -> pure (Left (UnsupportedCapability "board-by-witness not exercised here"))
        , qbListCheckpoints = pure (Left (UnsupportedCapability "checkpoint listing not exercised here"))
        , qbCheckpointByAid = \_ -> pure (Left (UnsupportedCapability "checkpoint-by-AID not exercised here"))
        , qbPayerUtxos = \_ -> pure (Left (UnsupportedCapability "payer UTxOs not exercised here"))
        }

recordingBackend :: IORef [Text] -> QueryBackend
recordingBackend calls =
    QueryBackend
        { qbSourceLabel = "fake-selected"
        , qbStatus = \_ -> record "status" "fake status"
        , qbBoardByWitness = \_ -> record "board" "fake board"
        , qbListCheckpoints = record "list" "fake list"
        , qbCheckpointByAid = \_ -> record "checkpoint" "fake checkpoint"
        , qbPayerUtxos = \_ -> record "payer" "fake payer"
        }
  where
    record operation capability = do
        modifyIORef' calls (<> [operation])
        pure (Left (UnsupportedCapability capability))

isUnsupported :: Text -> Either BackendError a -> Bool
isUnsupported expected (Left (UnsupportedCapability actual)) = actual == expected
isUnsupported _ _ = False

isMalformed :: Either BackendError a -> Bool
isMalformed (Left (MalformedResponse _)) = True
isMalformed _ = False

sampleAid :: Text
sampleAid = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

sampleAddress :: Text
sampleAddress = "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d"

sampleCheckpoint :: CheckpointFields
sampleCheckpoint =
    CheckpointFields
        { cfTxId = "aa"
        , cfOutputIndex = 0
        , cfSequence = 1
        , cfNativeSequence = 1
        , cfCurrentKeys = ["Dxxxx"]
        , cfCurrentThreshold = Unweighted 1
        , cfWitnesses = []
        , cfWitnessThreshold = 0
        }

sampleView :: Text -> StatusView
sampleView aid =
    StatusView
        { svSource = "koios"
        , svFreshness = Freshness (Just 100) (Just 0)
        , svAid = aid
        , svCheckpoint = Just sampleCheckpoint
        , svWatchability =
            WatchabilityFields
                { wfCheckpointPresent = True
                , wfWitnessesDeclared = 0
                , wfWitnessesListed = 0
                , wfMissingWitnesses = []
                }
        }
