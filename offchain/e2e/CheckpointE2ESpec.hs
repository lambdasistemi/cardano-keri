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
    productionRegisterCloseScenario,
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
            "#143 settles Register then controller-authorized Close refund"
            productionRegisterCloseScenario
