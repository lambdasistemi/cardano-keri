{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CheckpointE2ESpec
Description : Live-node boundary for the #114 permissionless checkpoint lifecycle

Exercises the production, six-parameter checkpoint validator against a real
@cardano-node@ devnet.  The pinned old-cost model rejects the real hash-proof
mint before Register can settle, so the positive Register -> Arm -> Claim
chain is explicitly compile-checked as `PENDING(blocked-on=#190)`. Advance
and Close remain deliberately closed until #115 and #117 respectively; their
real redeemers reach the production validator and reject from independent
tokenless staging inputs.
-}
module CheckpointE2ESpec (spec) where

import Test.Hspec

import CheckpointTxBuilder (
    CheckpointEnv,
    RejectionEvidence,
    advanceRejection,
    closeRejection,
    hashProofMintOldCostRejection,
    pendingHashProofRegisterArmClaimScenario,
    rejectionIsOldCostPlominBoundary,
    rejectionReachedProductionScript,
    stagedCheckpointDevnet,
 )

spec :: Spec
spec = describe "#114 permissionless checkpoint boundary" $ do
    around stagedCheckpointDevnet $ do
        it
            "settled-on-devnet: rejects hash-proof mint at the 251-entry old-cost Plomin boundary"
            (assertOldCostPlominRejection hashProofMintOldCostRejection)
        it
            "settled-on-devnet: rejects Advance at the production validator"
            (assertProductionScriptRejection advanceRejection)
        it
            "settled-on-devnet: rejects Close at the production validator"
            (assertProductionScriptRejection closeRejection)
    it
        "PENDING(blocked-on=#190): hash-proof mint -> permissionless Register with D_reg+B escrow -> Arm -> Claim"
        (pendingHashProofRegisterArmClaimScenario `seq` pendingWith "blocked-on=#190")

assertProductionScriptRejection ::
    (CheckpointEnv -> IO RejectionEvidence) -> CheckpointEnv -> IO ()
assertProductionScriptRejection action env = do
    evidence <- action env
    evidence `shouldSatisfy` rejectionReachedProductionScript

assertOldCostPlominRejection ::
    (CheckpointEnv -> IO RejectionEvidence) -> CheckpointEnv -> IO ()
assertOldCostPlominRejection action env = do
    evidence <- action env
    evidence `shouldSatisfy` rejectionIsOldCostPlominBoundary
