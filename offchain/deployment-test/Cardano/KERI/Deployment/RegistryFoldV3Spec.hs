{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFoldV3Spec
Description : the fold of a booked request is one transaction that supplies no evidence, no proof and no withdrawal

The booking attested the inception, so the fold needs nothing from its folder but chain data, the
registry's configuration and its wallet: it does not premint a hash proof, spends none, withdraws
from no observer and shows no inception. Read from what the chain accepted.
-}
module Cardano.KERI.Deployment.RegistryFoldV3Spec (spec) where

import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (noFaults)
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.Ledger.Address (Withdrawals (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (mintTxBodyL, withdrawalsTxBodyL)
import Cardano.Ledger.Mary.Value (MultiAsset (..))
import Control.Monad (void)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))
import Test.Hspec

spec :: Spec
spec = describe "#559 the fold of a booked request supplies no evidence" $ around_ withinOneMinute $ do
    it "is one transaction: the approval burned and the active token minted, no proof burned, no withdrawal" $ do
        world <- newWorld 1_000
        export <- loadExport "kli-export-single.cesr"
        (request, _) <- bookDirectly world export
        base <- length <$> accepted world
        sent0 <- submissionsMade world
        outcome <-
            foldBookedRequest
                (runtimeOf noFaults world)
                (\_ -> pure ())
                FoldInput
                    { foldBlueprint = worldBlueprint world
                    , foldIdentity = deployedIdentity (worldDeployed world)
                    , foldRecord = deployedRecord (worldDeployed world)
                    , foldRequestOutput = request
                    , foldSnapshot = Snapshot "the follower" [] []
                    , foldPayerAddress = folderAddress
                    }
        void (either (fail . show) pure outcome)
        transactions <- accepted world
        -- the fold alone: no premint of a hash proof precedes it
        length transactions `shouldBe` base + 1
        submissionsMade world >>= (`shouldBe` (sent0 + 1))
        case drop base transactions of
            [foldTx] -> do
                let MultiAsset minted = foldTx ^. bodyTxL . mintTxBodyL
                    Withdrawals withdrawn = foldTx ^. bodyTxL . withdrawalsTxBodyL
                -- the approval of the application and the active token of the state script: two policies
                Map.size minted `shouldBe` 2
                Map.null withdrawn `shouldBe` True
            other -> expectationFailure ("not one fold: " <> show (length other))
    it "reports no premint: the events are the snapshot, the fold's handoff and its settlement" $ do
        world <- newWorld 1_000
        export <- loadExport "kli-export-single.cesr"
        (request, _) <- bookDirectly world export
        seen <- newIORef []
        outcome <-
            foldBookedRequest
                (runtimeOf noFaults world)
                (\event -> modifyIORef' seen (event :))
                FoldInput
                    { foldBlueprint = worldBlueprint world
                    , foldIdentity = deployedIdentity (worldDeployed world)
                    , foldRecord = deployedRecord (worldDeployed world)
                    , foldRequestOutput = request
                    , foldSnapshot = Snapshot "the follower" [] []
                    , foldPayerAddress = folderAddress
                    }
        void (either (fail . show) pure outcome)
        events <- reverse <$> readIORef seen
        -- the snapshot check, the handoff of the fold and its settlement: nothing of a premint
        case events of
            [SnapshotChecked{}, FoldHandingOff{}, FoldSettled{}] -> pure ()
            other -> expectationFailure ("not the events of one fold: " <> show other)
