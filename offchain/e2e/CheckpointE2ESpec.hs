{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CheckpointE2ESpec
Description : Live-node boundary for the registry journey and the checkpoint stories

Exercises registration as book, fold and return, then the checkpoint validator's
arms over checkpoints a fold delivered, against a protocol-11 @cardano-node@
devnet. The freeze-then-deposit and the termination journeys run in
'ConsumerE2ESpec', each with the consumer example reading the checkpoint at its
stages.
-}
module CheckpointE2ESpec (spec) where

import Test.Hspec

import CheckpointTxBuilder (
    bookingSettlementsJourney,
    productionFrozenTopUpScenario,
    productionRegisterAdvanceScenario,
    productionRegisterConvictScenario,
    productionRegisterFreezeScenario,
    productionRegisterTopUpScenario,
    registryJourney,
    stagedCheckpointDevnet,
 )

spec :: Spec
spec = describe "#136 register a small identity end to end" $ do
    around stagedCheckpointDevnet $ do
        it
            "books a registration, folds it with another party into a checkpoint holding the deposit, refuses a late fold and a return to another address, and returns an unfolded request after its deadline, composing the return with the burn of its attestation"
            registryJourney

    around stagedCheckpointDevnet $ do
        it
            "#559 settles one booking and one transaction of two bookings, each reported with its signed identifier, serialized size and the units each redeemer used"
            bookingSettlementsJourney

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
            "#522 tops a delivered checkpoint up by one premium, writes only the mark and refuses a second top-up in the same key state"
            productionRegisterTopUpScenario

    around stagedCheckpointDevnet $ do
        it
            "#522 tops a frozen checkpoint up to cover the premium, then the controller's keep rotation pays it, stays frozen and clears the mark"
            productionFrozenTopUpScenario
