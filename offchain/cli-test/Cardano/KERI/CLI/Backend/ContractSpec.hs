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
    Freshness (..),
    QueryBackend (..),
    StatusView (..),
    WatchabilityFields (..),
    renderStatusView,
    runBackendStatus,
 )
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

fakeBackend :: Text -> (Text -> IO (Either BackendError StatusView)) -> QueryBackend
fakeBackend label status =
    QueryBackend
        { qbSourceLabel = label
        , qbStatus = status
        , qbBoardByWitness = \_ -> pure (Left (UnsupportedCapability "board-by-witness not exercised here"))
        }

sampleAid :: Text
sampleAid = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

sampleView :: Text -> StatusView
sampleView aid =
    StatusView
        { svSource = "koios"
        , svFreshness = Freshness (Just 100) (Just 0)
        , svAid = aid
        , svCheckpoint =
            Just
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
        , svWatchability =
            WatchabilityFields
                { wfCheckpointPresent = True
                , wfWitnessesDeclared = 0
                , wfWitnessesListed = 0
                , wfMissingWitnesses = []
                }
        }
