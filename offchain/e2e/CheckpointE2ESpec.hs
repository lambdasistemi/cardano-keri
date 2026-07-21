{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CheckpointE2ESpec
Description : Live-node staging boundary for the #116 checkpoint lifecycle

Exercises the production, six-parameter checkpoint validator against a real
@cardano-node@ devnet.  The #116 staging revision deliberately keeps
Register, Advance, and Close closed, so those submissions must reach the
production script and be rejected there.  The two complete freeze scenarios
remain named and compile-checked until #114 opens Register and #115 opens
Advance.
-}
module CheckpointE2ESpec (spec) where

import Test.Hspec

import CheckpointTxBuilder (
    CheckpointEnv,
    RejectionEvidence,
    advanceRejection,
    armClaimThawScenario,
    armResponseBeforeDeadlineScenario,
    boundaryCasesCoverDeadline,
    closeRejection,
    productionRegisterScenario,
    registerRejection,
    rejectionReachedProductionScript,
    responseBoundaryCases,
    stagedCheckpointDevnet,
 )

spec :: Spec
spec = describe "#116 checkpoint staging" $ do
    around stagedCheckpointDevnet $ do
        it
            "rejects a staged Register dispatch at the production checkpoint policy"
            (assertProductionScriptRejection registerRejection)
        it
            "rejects Advance against the real applied validator"
            $ \env -> do
                boundaries <- responseBoundaryCases env
                boundaries `shouldSatisfy` boundaryCasesCoverDeadline
                assertProductionScriptRejection advanceRejection env
        it
            "rejects Close against the real applied validator"
            (assertProductionScriptRejection closeRejection)
    it "Arm -> response-before-deadline (pending #114/#115)" $ do
        productionRegisterScenario `seq`
            armResponseBeforeDeadlineScenario `seq`
                pendingWith "#114 Register is closed and #115 Advance is closed"
    it "Arm -> Claim-at/after-deadline -> Thaw (pending #114/#115)" $ do
        armClaimThawScenario `seq`
            pendingWith "#114 Register is closed and #115 Advance is closed"

assertProductionScriptRejection ::
    (CheckpointEnv -> IO RejectionEvidence) -> CheckpointEnv -> IO ()
assertProductionScriptRejection action env = do
    evidence <- action env
    evidence `shouldSatisfy` rejectionReachedProductionScript
