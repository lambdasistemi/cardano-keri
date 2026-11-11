{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CheckpointE2ESpec
Description : Live-node boundary for the registry journey and the checkpoint stories

Exercises registration as book, fold and return, then the checkpoint validator's
arms over checkpoints a fold delivered, against a protocol-11 @cardano-node@
devnet.
-}
module CheckpointE2ESpec (spec) where

import Test.Hspec

import CheckpointTxBuilder (
    productionFrozenTopUpScenario,
    productionRegisterAdvanceScenario,
    productionRegisterConvictScenario,
    productionRegisterFreezeScenario,
    productionRegisterFreezeThenDepositScenario,
    productionRegisterTopUpScenario,
    registryJourney,
    stagedCheckpointDevnet,
    terminationJourney,
 )

spec :: Spec
spec = describe "#136 register a small identity end to end" $ do
    around stagedCheckpointDevnet $ do
        it
            "books a registration, folds it with another party into a checkpoint holding the deposit, refuses a late fold and a return to another address, and returns an unfolded request after its deadline"
            registryJourney

    around stagedCheckpointDevnet $ do
        it
            "#350 books the termination of a convicted identity with a third party's fee, folds it with another party, reads the terminal key back, and refuses each clause's violation, a second booking and a registration of the terminal key"
            terminationJourney

    around stagedCheckpointDevnet $ do
        it
            "#142 settles a fold then a genuine witnessed two-key Advance"
            productionRegisterAdvanceScenario

    around stagedCheckpointDevnet $ do
        it
            "#151 convicts an ACTIVE checkpoint"
            productionRegisterConvictScenario

    around stagedCheckpointDevnet $ do
        it
            "#345 freezes a checkpoint whose pool is below the premium on the controller's own next witnessed rotation"
            productionRegisterFreezeScenario

    around stagedCheckpointDevnet $ do
        it
            "#345 restores the bond of a frozen checkpoint with the controller's deposit rotation, refuses a deposit whose intent names another amount, and the checkpoint is consumable again"
            productionRegisterFreezeThenDepositScenario

    around stagedCheckpointDevnet $ do
        it
            "#522 tops a delivered checkpoint up by one premium, writes only the mark and refuses a second top-up in the same key state"
            productionRegisterTopUpScenario

    around stagedCheckpointDevnet $ do
        it
            "#522 tops a frozen checkpoint up to cover the premium, then the controller's keep rotation pays it, stays frozen and clears the mark"
            productionFrozenTopUpScenario
