{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CheckpointE2ESpec
Description : Live-node boundary for story #136 Register-small

Exercises the register-only checkpoint policy, lifecycle observer, and
hash-proof policy against a protocol-11 @cardano-node@ devnet.
-}
module CheckpointE2ESpec (spec) where

import Control.Monad (void)
import Test.Hspec

import CheckpointTxBuilder (
    productionRegisterAdvanceScenario,
    productionRegisterConvictScenario,
    productionRegisterFreezeScenario,
    productionRegisterFreezeThenDepositScenario,
    productionRegisterScenario,
    stagedCheckpointDevnet,
 )

spec :: Spec
spec = describe "#136 register a small identity end to end" $ do
    around stagedCheckpointDevnet $ do
        it
            "settles hash-proof premint then Register with D_reg+B escrow"
            (void . productionRegisterScenario)

    around stagedCheckpointDevnet $ do
        it
            "#142 settles Register then a genuine witnessed two-key Advance"
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
