{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CheckpointE2ESpec
Description : Live-node boundary for the #114 permissionless checkpoint lifecycle

Exercises the production, six-parameter checkpoint validator against a real
@cardano-node@ devnet. The PV11 compatibility capture measures four
reference-script creations and the positive hash-proof mint -> Register ->
Arm -> Claim chain without invoking the deferred advance-observer path.
Advance and Close remain deliberately closed until #115 and #117
respectively; their real redeemers reach the production validator and reject
from independent tokenless staging inputs.
-}
module CheckpointE2ESpec (spec) where

import Control.Exception (SomeException, catch, displayException, try)
import Control.Monad (unless, void, when)
import Data.Foldable (toList)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32, Word64)
import System.Environment (lookupEnv)
import Test.Hspec

import CageTxBuilder (
    OfflineSeams (..),
    Phase1Input (..),
    Phase1RewardState (..),
    Phase1Verdict,
    Pv11GuardParams,
    SyntheticDevnetCoordinate (..),
    defaultOfflineSeams,
    globalsCeilSlot,
    globalsFloorSlot,
    loadPv11GuardParams,
    offlinePhase1Snapshot,
    offlineProviderWith,
    offlineWalletOf,
    phase1Structural,
    pv11MaxTxExUnits,
    renderPhase1,
    runPhase1,
    syntheticCeilSlot,
    syntheticCoordinateProvider,
    syntheticDevnetCoordinate,
    syntheticDevnetGlobalsFixture,
    syntheticFloorSlot,
    syntheticHorizonSlot,
    syntheticSlotStartMs,
 )
import Cardano.Crypto.Hash (
    Hash,
    hashToBytes,
    hashToStringAsHex,
    hashWith,
 )
import Cardano.Crypto.Hash.SHA256 (SHA256)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (V1),
    CheckpointDatumV1,
    cdCesrAid,
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence)
import Cardano.KERI.AID.Checkpoint.FreezeBond (ArmedDatum (..), Role (Armed))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData, enforcementEvidenceData)
import Cardano.KERI.AID.E2E.Datum (extractDatum, mkInlineDatum)
import Cardano.Ledger.Address (AccountAddress (..), AccountId (..), Addr (..), Withdrawals (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppCollateralPercentageL)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (collectPlutusScriptsWithContext)
import Cardano.Ledger.Alonzo.Scripts (
    AlonzoScript (PlutusScript),
    AsIx (..),
    plutusScriptLanguage,
 )
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    collateralReturnTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    totalCollateralTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    datumTxOutL,
    mkBasicTxOut,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (datsTxWitsL, rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    Globals (..),
    Inject (..),
    Network (Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Binary (decCBOR, decodeFullAnnotator, serialize)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams, Script, bodyTxL, eraProtVerLow, hashScript)
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (DataHash, ScriptHash (..), extractHash)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.Data (Datum (Datum), binaryDataToData, getPlutusData)
import Cardano.Ledger.Plutus.Evaluate (
    PlutusWithContext (..),
    ScriptFailure (..),
    ScriptResult (..),
    runPlutusScriptWithLogs,
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..), exUnitsMem, exUnitsSteps)
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.State (UTxO (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (
    EvaluateTxResult,
    LedgerSnapshot (ledgerTipSlot),
    Provider (..),
    SlotNo (..),
 )
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (..))
import Cardano.Slotting.EpochInfo.API (EpochInfo (..))
import Cardano.Slotting.Slot (EpochNo (..), EpochSize (..))
import Cardano.Slotting.Time (RelativeTime (..))
import Cardano.Tx.Balance (computeScriptIntegrity)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Lens.Micro ((%~), (&), (.~), (^.))
import Numeric.Natural (Natural)
import PlutusCore.Data (Data (..))
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (fromBuiltinData)

import CheckpointTxBuilder (
    CheckpointEnv,
    CheckpointInput (..),
    RegistrationFixture,
    RejectionEvidence,
    ValidityPlan (..),
    advanceRejection,
    assertStockMaxTxSize,
    bodyRewardState,
    boundaryCasesCoverDeadline,
    buildAdvanceTx,
    buildArmTx,
    buildArmTxIn,
    buildClaimTx,
    buildCurrentArmTx,
    buildHashProofMintTx,
    buildRegisterTx,
    buildTwoPassFinalRegister,
    buildTwoPassFinalRegisterIn,
    checkpointAppliedBytesOf,
    checkpointEnforcementHashOf,
    checkpointEnforcementScriptOf,
    checkpointHashProofPolicyOf,
    checkpointHashProofScriptOf,
    checkpointLifecycleScriptOf,
    checkpointOwnerOf,
    checkpointProviderOf,
    checkpointScriptOf,
    closeRejection,
    currentValidity,
    currentValidityIn,
    deployReferenceScriptForCapture,
    deterministicMargin,
    dummyAdvanceEvidence,
    evaluateAndSubmitPositiveCapture,
    expectOldCostHashProofRejection,
    expectProductionScriptRejection,
    freezeWindow,
    loadLifecycleFixture,
    mkCheckpointEnvWith,
    observerAdvanceStakeRegistrationSetup,
    observerEnforcementStakeRegistrationSetup,
    observerLifecycleStakeRegistrationSetup,
    pendingHashProofRegisterArmClaimScenario,
    pv11CompatibilityAndNonObserverCaptureScenario,
    registerTransactionShapeRegression,
    rejectionReachedProductionScript,
    responseBoundaryCases,
    rfDatum,
    rfProofName,
    roleAddress,
    stageCheckpointInput,
    stagedCheckpointDevnet,
    submitTwoPassRegister,
    submitUnchangedCapture,
    verifyFiveProgramDeploymentShapes,
    withCheckpointPhase1Snapshot,
 )

spec :: Spec
spec = do
    checkpointRoutesReachTheGuard
    twoPassObservableOutcomes
    armAndClaimFitEvidence
    armValidityAcrossAdvancingTip
    syntheticCoordinateIdentity
    armShapeAndCoordinateRed
    describe "#114 permissionless checkpoint boundary" $ do
        it
            "local-only: Register transaction shape carries bare command and lifecycle observer coupling"
            registerTransactionShapeRegression
        around stagedCheckpointDevnet $ do
            it
                "settled-on-devnet: live protocol parameters use stock maxTxSize = 16384"
                assertStockMaxTxSize
            it
                "applies checkpoint plus three observers and hash-proof, derives three distinct observer hashes, and constructs all five signed reference-script creation shapes at the stock cap"
                verifyFiveProgramDeploymentShapes
            it
                "settled-on-devnet: PV11 compatibility and non-observer capture"
                pv11CompatibilityAndNonObserverCaptureScenario
            it
                "settled-on-devnet: rejects Advance at the production validator"
                (assertProductionScriptRejection advanceRejection)
            it
                "settled-on-devnet: rejects Close at the production validator"
                (assertProductionScriptRejection closeRejection)
        it
            "PENDING(blocked-on=#190): hash-proof mint -> permissionless Register with D_reg+B escrow -> Arm -> Claim"
            (pendingHashProofRegisterArmClaimScenario `seq` pendingWith "blocked-on=#190")
        it
            "PENDING(harness-cannot-express-unregistered-observer-withdrawal): zero-withdrawal forward to unregistered observer_lifecycle credential fails"
            (observerLifecycleStakeRegistrationSetup `seq` pendingWith "harness-cannot-express-unregistered-observer-withdrawal")
        it
            "PENDING(harness-cannot-express-unregistered-observer-withdrawal): zero-withdrawal forward to unregistered observer_advance credential fails"
            (observerAdvanceStakeRegistrationSetup `seq` pendingWith "harness-cannot-express-unregistered-observer-withdrawal")
        it
            "PENDING(harness-cannot-express-unregistered-observer-withdrawal): zero-withdrawal forward to unregistered observer_enforcement credential fails"
            (observerEnforcementStakeRegistrationSetup `seq` pendingWith "harness-cannot-express-unregistered-observer-withdrawal")

{- | A-060 advancing-tip RED. Every candidate is built by the real Arm builder
and traverses the real pre-evaluation guard, evaluator seam, pre-submit guard,
and unchanged submission seam. The provider records the boundary anchor and
both real guard tips, while its evaluator advances the same ledger-tip source
before returning.
-}
armValidityAcrossAdvancingTip :: Spec
armValidityAcrossAdvancingTip =
    describe "Arm validity remains open across horizon and evaluation latency" $ do
        it "contains the advanced first-guard tip and reaches the evaluator without OutsideValidityIntervalUTxO" $ do
            seam <- newAdvancingArmSeam KeepEvaluationTip
            (_, validity, candidate) <- advancingArmCandidate seam
            outcome <-
                tryAnyCheckpoint $
                    evaluateAndSubmitPositiveCapture
                        (armSeamEnv seam)
                        "offline advancing-tip Arm"
                        []
                        candidate
            case outcome of
                Left err ->
                    expectationFailure $
                        "first real Arm guard did not reach evaluation: "
                            <> displayException err
                Right _ -> pure ()
            events <- readIORef (armSeamEvents seam)
            -- Named boundaries, not query counts.
            anchor <- requireEventSlot events "build anchor" isBuildAnchor
            guard1 <-
                requireEventSlot
                    events
                    "external pre-evaluation guard"
                    isExternalPreEvaluationGuard
            guard2 <-
                requireEventSlot
                    events
                    "external pre-submit guard"
                    isExternalPreSubmitGuard
            prep <-
                requireEventSlot
                    events
                    "final preparation guard"
                    isFinalPreparationGuard
            -- anchor < guard1, and the final preparation guard precedes the
            -- external boundary in the recorded order.
            (anchor < guard1) `shouldBe` True
            eventIndex events isFinalPreparationGuard
                `shouldSatisfy` (< eventIndex events isExternalEvaluation)
            prep `shouldBe` armFirstGuardTip
            -- Both guards lie inside the candidate's half-open interval.
            validity `shouldSatisfy` (`containsSlot` guard1)
            validity `shouldSatisfy` (`containsSlot` guard2)
            -- Exactly one external evaluation, over the exact candidate bytes.
            externalEvaluationBytes events
                `shouldBe` [serializedTxBytes candidate]
        it "keeps the exact evaluated bytes open at the second guard and submits only those unchanged bytes" $ do
            seam <- newAdvancingArmSeam (AdvanceEvaluationBy 1)
            (_, validity, candidate) <- advancingArmCandidate seam
            outcome <-
                tryAnyCheckpoint $
                    evaluateAndSubmitPositiveCapture
                        (armSeamEnv seam)
                        "offline advancing-tip Arm"
                        []
                        candidate
            case outcome of
                Left err ->
                    expectationFailure $
                        "exact evaluated Arm bytes expired before the second real guard: "
                            <> displayException err
                Right _ -> pure ()
            events <- readIORef (armSeamEvents seam)
            anchor <- requireEventSlot events "build anchor" isBuildAnchor
            guard1 <-
                requireEventSlot
                    events
                    "external pre-evaluation guard"
                    isExternalPreEvaluationGuard
            guard2 <-
                requireEventSlot
                    events
                    "external pre-submit guard"
                    isExternalPreSubmitGuard
            -- anchor < guard1 < guard2: the single advance happened at the
            -- external evaluation boundary between the two guards.
            (anchor < guard1) `shouldBe` True
            (guard1 < guard2) `shouldBe` True
            guard2 `shouldBe` armSecondGuardTip
            validity `shouldSatisfy` (`containsSlot` guard1)
            validity `shouldSatisfy` (`containsSlot` guard2)
            -- The exact bytes survive preparation, external evaluation and
            -- submission unchanged.
            externalEvaluationBytes events
                `shouldBe` [serializedTxBytes candidate]
            externalSubmissionBytes events
                `shouldBe` [serializedTxBytes candidate]
        it "names OutsideValidityIntervalUTxO after evaluation advances beyond the upper bound and captures no submission or settlement" $ do
            seam <- newAdvancingArmSeam AdvanceEvaluationBeyondUpper
            (_, _, candidate) <- advancingArmCandidate seam
            outcome <-
                tryAnyCheckpoint $
                    evaluateAndSubmitPositiveCapture
                        (armSeamEnv seam)
                        "offline stale-after-evaluation Arm"
                        []
                        candidate
            case outcome of
                Left err ->
                    displayException err
                        `shouldSatisfy` isInfixOf "OutsideValidityIntervalUTxO"
                Right _ ->
                    expectationFailure "a stale post-evaluation Arm candidate was accepted"
            events <- readIORef (armSeamEvents seam)
            -- Preparation and the external pre-evaluation guard both ACCEPT.
            _ <-
                requireEventSlot
                    events
                    "final preparation guard"
                    isFinalPreparationGuard
            _ <-
                requireEventSlot
                    events
                    "external pre-evaluation guard"
                    isExternalPreEvaluationGuard
            -- Exactly ONE external evaluation, over the exact candidate bytes.
            -- The raw evaluator count is incidental: the authorized two-pass
            -- preparation legitimately evaluates twice more.
            externalEvaluationBytes events
                `shouldBe` [serializedTxBytes candidate]
            -- The external pre-submit boundary was REACHED, and rejected with
            -- OutsideValidityIntervalUTxO as asserted above.
            any isExternalPreSubmitGuard events `shouldBe` True
            -- Zero submission and zero settlement after the rejecting guard.
            externalSubmissionBytes events `shouldBe` []
            readIORef (armSeamSubmitted seam) `shouldReturn` []
            readIORef (armSeamSettled seam) `shouldReturn` []
        it "stores the Armed deadline as the final upper POSIX time plus exactly 10,000 ms" $ do
            seam <- newAdvancingArmSeam KeepEvaluationTip
            (fixture, validity, candidate) <- advancingArmCandidate seam
            case toList (candidate ^. bodyTxL . outputsTxBodyL) of
                (armedOutput : _) ->
                    armedOutput ^. datumTxOutL
                        `shouldBe` mkInlineDatum
                            ( asPlcData
                                ArmedV1
                                    { adCheckpoint = rfDatum fixture
                                    , adHunterPkh = offlineHunter
                                    , adDeadline = upperPosixMs validity + 10_000
                                    }
                            )
                [] -> expectationFailure "real Arm candidate has no Armed output"
        it "retains the before, exact, and after deadline business outcomes" $ do
            seam <- newAdvancingArmSeam KeepEvaluationTip
            boundaries <- responseBoundaryCases (armSeamEnv seam)
            boundaries `shouldSatisfy` boundaryCasesCoverDeadline

assertProductionScriptRejection ::
    (CheckpointEnv -> IO RejectionEvidence) -> CheckpointEnv -> IO ()
assertProductionScriptRejection action env = do
    evidence <- action env
    evidence `shouldSatisfy` rejectionReachedProductionScript

-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Offline Checkpoint route contract (RED, A-050 ruling 50D)
-- ---------------------------------------------------------------------------

{- | Drive the REAL Checkpoint builder/orchestration routes to all four
concrete @submitTx@ exits through the offline 'Provider' seam.

No synthetic transaction is injected into a submit helper: every candidate is
produced by the real builder or route that selects that exit, from a wallet
whose values make the resulting final object genuinely inadmissible under the
pinned real PV11 guard parameters. Each example freezes the exact final
candidate and its resolved-input set, then requires the route to reject BEFORE
reaching the submission seam.

Per A-050 (50D) these pin observable behaviour only. No margin formula,
discovery-binding type, entry-point name, rebuild function, return shape, or
internal arithmetic is named or required.
-}
checkpointRoutesReachTheGuard :: Spec
checkpointRoutesReachTheGuard =
    describe "offline batched PV11 capture contract" $
        describe "Checkpoint routes reach the real guard before submitting" $ do
            it "reference-script creation route rejects before submitUnchangedCapture" $ do
                seam <- newCheckpointSeam [(0xaa, 100_900_000)]
                runRoute seam "OutputTooSmallUTxO" $ \env ->
                    void $
                        deployReferenceScriptForCapture
                            env
                            "offline reference-script creation"
                            (checkpointScriptOf env)
            it "manual staging route rejects before submitSettling" $ do
                seam <- newCheckpointSeam [(0xaa, 1_008_000_000)]
                runRoute seam "OutputTooSmallUTxO" $ \env -> do
                    (fixture, _) <- loadLifecycleFixture
                    void $ stageCheckpointInput env (rfDatum fixture)
            it "hash-proof mint route rejects before expectOldCostHashProofRejection" $ do
                seam <-
                    newStagedSeam [(0xaa, 7_500_000), (0xbb, 4_000_000)]
                runRoute seam "OutputTooSmallUTxO" $ \env -> do
                    (fixture, _) <- loadLifecycleFixture
                    candidate <- buildHashProofMintTx env fixture
                    void $ expectOldCostHashProofRejection env oldCostEntries candidate
            it "Advance staging route rejects before expectProductionScriptRejection" $ do
                seam <-
                    newStagedSeam [(0xaa, 3_800_000), (0xbb, 500_000_000)]
                -- The intentionally constructed real failure on this candidate
                -- is InsufficientCollateral (REVIEW-023 finding 2).
                -- A-071 71A: the ordinary production candidate is now legitimately
                -- admissible under the derived fee, so the boundary is proved
                -- by ONE authorized collateral-axis mutation of that genuine
                -- production-built and production-balanced candidate.
                guardParams <- loadPv11GuardParams
                runRoute seam "InsufficientCollateral" $ \env ->
                    withCollateralNegativeAdvance seam $ \negative provider -> do
                        -- Freeze the COMPLETE row proof before the guard
                        -- rejects. runPhase1 is pure, so collecting the
                        -- partition adds no downstream call.
                        snapshot <- queryLedgerSnapshot provider
                        let partition =
                                checkpointStructuralNames
                                    ( runPhase1
                                        Phase1Input
                                            { p1Globals = cnGlobals negative
                                            , p1Slot = ledgerTipSlot snapshot
                                            , p1Params = guardParams
                                            , p1ResolvedInputs = cnResolved negative
                                            }
                                        (bodyRewardState (cnCandidate negative))
                                        (cnCandidate negative)
                                    )
                        evidence <-
                            collectA071RowEvidence
                                seam
                                provider
                                negative
                                "ordinary-advance-route-row"
                                "real guard rejects naming InsufficientCollateral"
                                partition
                        assertA071RowEvidence evidence
                        void $
                            expectProductionScriptRejection
                                env
                                "offline Advance (production-built, one authorized collateral-axis mutation)"
                                (cnCandidate negative)

{- | Observable two-pass outcomes (A-050 50D item 2).

These pin OUTCOMES only. No margin formula, discovery-binding type, entry-point
name, rebuild function, return shape, or internal arithmetic is named.
-}

{- | REVIEW-024 finding 2: real Arm and Claim final candidates must be proved
to fit, not asserted to fit.

Each is constructed through the real builder with complete resolved regular,
collateral, and reference inputs, then handed to the real Phase-1 guard. The
guard must report no @ and no other structural failure. Their
current inline shapes are retained only because this evidence says they fit.
-}
armAndClaimFitEvidence :: Spec
armAndClaimFitEvidence =
    describe "offline batched PV11 capture contract" $
        describe "real Arm and Claim final candidates fit the stock cap" $ do
            it "the real final Arm candidate has no MaxTxSizeUTxO and no structural failure" $
                assertCandidateFits "Arm" $ \env fixture armEvidence -> do
                    validity <- currentValidity env
                    buildArmTx
                        env
                        (offlineEnforcementReference env)
                        (offlineStagedCheckpoint env (rfDatum fixture))
                        armEvidence
                        offlineHunter
                        validity
            it "the real final Advance candidate has EXACTLY [InsufficientCollateral] and none of the three fixture artifacts" $ do
                seam <- newStagedSeam [(0xaa, 3_800_000), (0xbb, 500_000_000)]
                guardParams <- loadPv11GuardParams
                -- A-072 72A correction 4: NO nested acquisition. The outer
                -- candidate-owning provider does the snapshot and resolver
                -- work, and the structural guard uses that same acquisition's
                -- Globals.
                withCollateralNegativeAdvance seam $ \negative provider -> do
                    snapshot <- queryLedgerSnapshot provider
                    let verdict =
                            runPhase1
                                Phase1Input
                                    { p1Globals = cnGlobals negative
                                    , p1Slot = ledgerTipSlot snapshot
                                    , p1Params = guardParams
                                    , p1ResolvedInputs = cnResolved negative
                                    }
                                (bodyRewardState (cnCandidate negative))
                                (cnCandidate negative)
                    let partition = checkpointStructuralNames verdict
                    -- The COMPLETE A-071 row proof is frozen, then the
                    -- singleton partition is asserted exactly.
                    evidence <-
                        collectA071RowEvidence
                            seam
                            provider
                            negative
                            "structural-partition-row"
                            "guard partition is exactly [InsufficientCollateral]"
                            partition
                    assertA071RowEvidence evidence
                    partition `shouldBe` ["InsufficientCollateral"]
            it "the real final Claim candidate has no MaxTxSizeUTxO and no structural failure" $
                assertCandidateFits "Claim" $ \env fixture _ -> do
                    validity <- currentValidity env
                    buildClaimTx
                        env
                        (offlineStagedCheckpoint env (rfDatum fixture))
                        offlineHunter
                        validity

-- | The hunter key hash the offline Arm/Claim candidates pay out to.
offlineHunter :: BS.ByteString
offlineHunter = BS.replicate 28 0x42

{- | Build a real final candidate through the offline seam and require the real
Phase-1 guard to accept it with no size or other structural failure.
-}

{- | A-065 D1/D2/D3: observable behavior RED against the CURRENT production
Arm candidate.

Every example builds the real candidate through the real production
'buildArmTx' on the existing offline seam and then observes the resulting
transaction. Nothing here names a guessed plan, rebuild, environment field or
`p1Globals` API — the observations are of the serialized candidate only.

Under operator ruling Q-015 option (c) the executed applied-validator END is
NOT a RED acceptance condition; it is a binding GREEN obligation, recorded in
'deferredEndObligation' below. The partial-fix ladder is preserved here as
observable SHAPE evidence.
-}
armShapeAndCoordinateRed :: Spec
armShapeAndCoordinateRed =
    describe "offline batched PV11 capture contract" $
        describe "A-065 production Arm shape and coordinate (D1/D2/D3)" $ do
            it "D1: the Arm Spending redeemer is exactly bare Freeze Constr 1 [B hunter]" $ do
                withProductionArmCandidate $ \arm _globals _provider ->
                    spendingRedeemerOf (acTx arm)
                        `shouldBe` Just (Constr 1 [B offlineHunter])

            it "D2a: withdrawals are exactly the enforcement script credential at Coin 0" $ do
                withProductionArmCandidate $ \arm _globals _provider ->
                    acTx arm
                        ^. bodyTxL
                            . withdrawalsTxBodyL
                        `shouldBe` expectedEnforcementWithdrawal (acEnv arm)

            it "D2b: the Rewarding purpose carries the exact Freeze ObserverEnvelope with witness and V3 integrity membership" $ do
                withProductionArmCandidate $ \arm _globals provider -> do
                    params <- queryProtocolParams provider
                    observed <- observeObserverContractIn provider arm params (acTx arm)
                    -- One complete record: an absent Rewarding redeemer cannot
                    -- stop the witness, purpose, language, datum and integrity
                    -- axes from being observed and reported.
                    observed `shouldBe` expectedObserverContract arm (acTx arm)

            it "D3: the Armed deadline equals the serialized validity upper plus freezeWindow under the callback-owned coordinate" $ do
                -- A-070 70.2A point 6 / verdict B4: the expected coordinate is
                -- the CANDIDATE'S OWN callback coordinate, observed inside the
                -- very callback that built it.
                withProductionArmCandidate $ \arm globals _provider -> do
                    decoded <- decodedCandidate (acTx arm)
                    upperMs <- serializedUpperPosixMs globals decoded
                    armed <- uniqueArmedDatum arm decoded
                    adDeadline armed `shouldBe` upperMs + freezeWindow

            it "ladder: unchanged production satisfies D1+D2+D3, and each single test-only regression is independently detected" $ do
                -- Same callback-owned coordinate rule as D3 above.
                withProductionArmCandidate $ \arm globals provider -> do
                    params <- queryProtocolParams provider
                    rung0 <- armShapeVerdict provider arm params globals (acTx arm)
                    rung1 <-
                        armShapeVerdict provider arm params globals $
                            regressD1 arm params (acTx arm)
                    rung2 <-
                        armShapeVerdict provider arm params globals $
                            regressD2 arm params (acTx arm)
                    rung3 <-
                        armShapeVerdict provider arm params globals $
                            regressD3 arm (acTx arm)
                    -- The RED ladder walked partial FIXES up from a broken
                    -- production and could only hold while production was broken.
                    -- Its diagnostic content is retained by inverting it: the
                    -- corrected production is rung 0, and each rung below re-breaks
                    -- exactly ONE axis. Because every regression is applied to the
                    -- SAME corrected candidate, an axis that silently stopped being
                    -- observed would show up as a rung that refuses to go False —
                    -- so this still refutes a partial fix, and additionally proves
                    -- the three axes are independent rather than merely ordered.
                    rung0 `shouldBe` ArmShape True True True
                    rung1 `shouldBe` ArmShape False True True
                    rung2 `shouldBe` ArmShape True False True
                    rung3 `shouldBe` ArmShape True True False

            it "END: the applied checkpoint validator accepts the exact production-plan context offline" $ do
                withEndArmReplay $ \report -> do
                    -- The frozen evidence identifies the exact applied
                    -- validator and the exact context these bytes were
                    -- evaluated against.
                    putStrLn (renderReplayEvidence report)
                    (deferredEndObligation, replayVerdict report)
                        `shouldBe` (deferredEndObligation, "Passes")

{- | Operator ruling Q-015 option (c): the executed applied-validator END moves
to GREEN, where the corrected production builder can produce the exact
context. It is recorded here so the deferral stays visible in the test source
rather than only in a handoff.
-}
deferredEndObligation :: String
deferredEndObligation =
    "GREEN obligation (Q-015 option c): apply the deployed checkpoint \
    \validator to the fully corrected production-shape context and require \
    \unit. Not a RED acceptance condition."

{- | B2: prove the bounded synthetic coordinate, not merely define it.

The provider side ('syntheticCoordinateProvider') and the fixture 'Globals'
side ('globalsFloorSlot' / 'globalsCeilSlot', which interrogate the decoded
canonical fixture's own 'EpochInfo') are separate code paths. Agreement across
the whole exercised interval is therefore evidence, and both must fail at the
first slot past the horizon.
-}
syntheticCoordinateIdentity :: Spec
syntheticCoordinateIdentity =
    describe "offline batched PV11 capture contract" $
        describe "A-065 downstream-owned bounded synthetic coordinate" $ do
            it "provider and Globals floor/ceiling agree for every slot 0..199" $ do
                globals <- syntheticDevnetGlobalsFixture
                let bounded =
                        [0 .. unSlotNo (syntheticHorizon syntheticDevnetCoordinate)]
                mapM_ (assertSlotIdentity globals . SlotNo) bounded
            it "the decoded canonical fixture carries the named synthetic coordinate" $ do
                globals <- syntheticDevnetGlobalsFixture
                -- Sourced from the decoded fixture, not from constants.
                epochInfoSlotToRelativeTime_ (epochInfo globals) (SlotNo 10)
                    `shouldBe` Right (RelativeTime 1)
                epochInfoSize_ (epochInfo globals) (EpochNo 0)
                    `shouldBe` Right (EpochSize 100)
                epochInfoEpoch_ (epochInfo globals) (SlotNo 0)
                    `shouldBe` Right (syntheticConwayStart syntheticDevnetCoordinate)
                systemStart globals
                    `shouldBe` syntheticSystemStart syntheticDevnetCoordinate
            it "both sides fail at slot 200, the first past the bounded horizon" $ do
                globals <- syntheticDevnetGlobalsFixture
                let beyondMs = syntheticSlotStartMs syntheticHorizonSlot
                -- Globals side: a named bounded-horizon failure.
                globalsFloorSlot globals beyondMs
                    `shouldSatisfy` isLeft
                globalsCeilSlot globals beyondMs
                    `shouldSatisfy` isLeft
                epochInfoSlotToRelativeTime_
                    (epochInfo globals)
                    syntheticHorizonSlot
                    `shouldSatisfy` isBoundedHorizonFailure
                -- Provider side: the same refusal, not a clamp.
                syntheticFloorSlot beyondMs `shouldSatisfy` isLeft
                syntheticCeilSlot beyondMs `shouldSatisfy` isLeft
                providerFloorThrows beyondMs `shouldReturn` True
                providerCeilThrows beyondMs `shouldReturn` True

{- | One slot's complete provider/'Globals' floor AND ceiling identity, at the
exact slot start and at a non-boundary midpoint inside the slot.

At an exact start both sides floor and ceil to the slot itself. Inside the
slot both sides still floor to the slot, and both must ceil to the NEXT slot —
except inside the horizon slot, where the next slot has no coordinate and both
ceiling paths must fail at the bounded horizon rather than clamp.
-}
assertSlotIdentity :: Globals -> SlotNo -> Expectation
assertSlotIdentity globals slot = do
    let startMs = syntheticSlotStartMs slot
        midMs = startMs + 50
        next = SlotNo (unSlotNo slot + 1)
    providerFloor <- posixMsToSlot syntheticCoordinateProvider startMs
    providerCeil <- posixMsCeilSlot syntheticCoordinateProvider startMs
    (slot, providerFloor) `shouldBe` (slot, slot)
    (slot, providerCeil) `shouldBe` (slot, slot)
    (slot, globalsFloorSlot globals startMs) `shouldBe` (slot, Right slot)
    (slot, globalsCeilSlot globals startMs) `shouldBe` (slot, Right slot)
    -- Inside the slot the floor stays put on both sides.
    providerMidFloor <- posixMsToSlot syntheticCoordinateProvider midMs
    (slot, providerMidFloor) `shouldBe` (slot, slot)
    (slot, globalsFloorSlot globals midMs) `shouldBe` (slot, Right slot)
    -- Inside the slot the ceiling advances on both sides, or fails at the
    -- bounded horizon when the next slot is past it.
    if slot < syntheticHorizon syntheticDevnetCoordinate
        then do
            providerMidCeil <- posixMsCeilSlot syntheticCoordinateProvider midMs
            (slot, providerMidCeil) `shouldBe` (slot, next)
            (slot, globalsCeilSlot globals midMs) `shouldBe` (slot, Right next)
        else do
            (slot, syntheticCeilSlot midMs)
                `shouldSatisfy` (isBoundedHorizonFailure . snd)
            (slot, globalsCeilSlot globals midMs)
                `shouldSatisfy` (isBoundedHorizonFailure . snd)
            providerCeilThrows midMs `shouldReturn` True

{- | The real production Arm candidate together with the exact objects it was
built from.

The expected observer contract is derived from these same real objects — the
staged checkpoint 'TxIn', its datum, and the live 'EnforcementEvidence' — so
no assertion below falls back on a wildcard.
-}
data ArmCandidate = ArmCandidate
    { acEnv :: CheckpointEnv
    , acInput :: CheckpointInput
    , acEvidence :: EnforcementEvidence
    , acTx :: ConwayTx
    , acResolved :: [(TxIn, TxOut ConwayEra)]
    }

-- | The real production Arm candidate, built offline through the real builder.

{- | Run an observation over the production Arm candidate INSIDE the one outer
acquisition that built it (A-070 70.2A points 5-6, verdict B4).

The candidate is constructed with 'buildArmTxIn' under this callback, and the
observation receives that same callback's 'Globals' and 'Provider'. Every
candidate-owned observation — D3's coordinate, the ladder, the exact
enforcement-reference identity, and the applied-validator replay — is
therefore made against the coordinate the candidate was actually built under,
rather than against a value obtained by reacquiring or reloading afterwards.
Only immutable observation records leave.
-}
withProductionArmCandidate ::
    (ArmCandidate -> Globals -> Provider IO -> IO a) -> IO a
withProductionArmCandidate observe = do
    seam <- newStagedSeam armWalletEntries
    let env = seamEnvOf seam
    (fixture, armEvidence) <- loadLifecycleFixture
    let input = offlineStagedCheckpoint env (rfDatum fixture)
    withCheckpointPhase1Snapshot env $ \globals provider -> do
        candidate <-
            buildArmTxIn
                globals
                provider
                env
                (offlineEnforcementReference env)
                input
                armEvidence
                offlineHunter
                boundedArmValidity
        observe
            ArmCandidate
                { acEnv = env
                , acInput = input
                , acEvidence = armEvidence
                , acTx = candidate
                , acResolved = seamExpectedResolved seam
                }
            globals
            provider

-- | The wallet both offline Arm candidates are funded from.
armWalletEntries :: [(Int, Integer)]
armWalletEntries = [(0xaa, 2_000_000_000), (0xbb, 2_000_000_000)]

{- | The Arm candidate used for the executed applied-validator END.

It differs from 'productionArmCandidate' in the INPUT only, and only where
the input has to be faithful for a validator to run at all: the staged
checkpoint output carries the one own-policy AID token at quantity one, which
is what a real @Register@ settles and what the checkpoint's
@classify_spend_input@ requires of a live ACTIVE input. The existing
tokenless staging fixture is left untouched — it faithfully reproduces
production @stageCheckpointInput@, which is deliberately tokenless, and the
shape examples above continue to use it.

The candidate itself is still produced by the REAL 'buildArmTx' and is not
touched afterwards.
-}

{- | Build the AUTHORITATIVE production chain and replay END, all inside ONE
outer acquisition (A-070 70.2A points 4 and 7; verdict B3 and the last B4
piece).

Sequence, none of which reacquires:

1. the exact FINAL two-pass Register binding via 'buildTwoPassFinalRegisterIn'
   — the authoritative object, not the empty-budget discovery spelling;
2. its uniquely identified ACTIVE token-bearing output, registered with the
   seam resolver so this same acquisition can resolve it;
3. the Arm candidate via 'buildArmTxIn' over that exact output; and
4. the applied-validator replay via 'appliedCheckpointReplayIn'.

Only the immutable replay record leaves.
-}
withEndArmReplay :: (ReplayReport -> IO a) -> IO a
withEndArmReplay observe = do
    bootstrap <- newCheckpointSeam armWalletEntries
    (fixture, armEvidence) <- loadLifecycleFixture
    let bootstrapEnv = seamEnvOf bootstrap
        proofPair = offlineProofUtxo bootstrapEnv fixture
        references = offlineRegisterReferences bootstrapEnv
        enforcementRef = offlineEnforcementReference bootstrapEnv
    seam <-
        newCheckpointSeamWith
            armWalletEntries
            (proofPair : enforcementRef : references)
    let env = seamEnvOf seam
    withCheckpointPhase1Snapshot env $ \globals provider -> do
        registerTx <-
            buildTwoPassFinalRegisterIn
                globals
                provider
                env
                "END authoritative Register"
                references
                fixture
                proofPair
        activeOutput <- registerActiveOutput env fixture registerTx
        modifyIORef' (seamResolvedRef seam) (activeOutput :)
        let input =
                CheckpointInput
                    { checkpointUtxo = activeOutput
                    , checkpointDatum = rfDatum fixture
                    }
        candidate <-
            buildArmTxIn
                globals
                provider
                env
                (offlineEnforcementReference env)
                input
                armEvidence
                offlineHunter
                boundedArmValidity
        resolved <- readIORef (seamResolvedRef seam)
        report <-
            appliedCheckpointReplayIn
                globals
                provider
                env
                candidate
                (offlineWalletOf armWalletEntries <> resolved)
        observe report

{- | The UNIQUE ACTIVE token-bearing output of the real Register candidate,
returned as a resolved @(TxIn, TxOut)@ (A-070 70.2A point 4).

This replaces the previous test-authored staged input. The output is
identified from the production candidate itself:

* its 'TxIn' is Register's OWN transaction id at the output's own index, so
  the lineage is Register's, not a fixture's;
* its address is the checkpoint ACTIVE role address;
* its own-policy token map is exactly the AID token, at quantity one, whose
  name is DERIVED from the inline datum's AID; and
* its inline datum decodes to the exact @V1@ checkpoint datum.

Zero matches and more than one match are both rejected, so the identification
cannot silently pick the wrong output.
-}
registerActiveOutput ::
    CheckpointEnv ->
    RegistrationFixture ->
    ConwayTx ->
    IO (TxIn, TxOut ConwayEra)
registerActiveOutput env fixture registerTx =
    case matches of
        [one] -> pure one
        other ->
            fail
                ( "registerActiveOutput: expected exactly one ACTIVE \
                  \token-bearing output in the real Register candidate, got "
                    <> show (length other)
                )
  where
    registerTxId = txIdTx registerTx
    aidName =
        AssetName (SBS.toShort (deriveAidAssetName (cdCesrAid (rfDatum fixture))))
    checkpointPolicy = PolicyID (hashScript (checkpointScriptOf env))
    matches =
        [ (TxIn registerTxId (TxIx index), out)
        | (index, out) <-
            zip [0 ..] (toList (registerTx ^. bodyTxL . outputsTxBodyL))
        , out ^. addrTxOutL == offlineActiveRoleAddress env
        , ownPolicyTokens out == Map.singleton aidName 1
        , case extractDatum out of
            Just (V1 datum) -> datum == rfDatum fixture
            _ -> False
        ]
    ownPolicyTokens out =
        case out ^. valueTxOutL of
            MaryValue _ (MultiAsset assets) ->
                Map.findWithDefault Map.empty checkpointPolicy assets

-- | The staged checkpoint input the candidate spends.
armOwnRef :: ArmCandidate -> TxIn
armOwnRef = fst . checkpointUtxo . acInput

{- | A validity plan whose SLOTS lie inside the bounded synthetic interval, so
the serialized upper bound has a coordinate in the fixture at all.

Its POSIX fields carry the millisecond values the current offline provider
coordinate yields for those slots (one-second slots, origin zero) — that is,
exactly what the production path computes today. The slot fields and the POSIX
fields therefore sit in DIFFERENT coordinates, which is precisely the D3
defect A-063 isolated: the successor deadline is derived from the POSIX field
while the validator reads the serialized slot.
-}
boundedArmValidity :: ValidityPlan
boundedArmValidity =
    ValidityPlan
        { lowerSlot = SlotNo 100
        , upperSlot = SlotNo 150
        , lowerPosixMs = 100_000
        , upperPosixMs = 150_000
        }

-- | The candidate's single Spending redeemer, as raw 'PLC.Data'.
spendingRedeemerOf :: ConwayTx -> Maybe PLC.Data
spendingRedeemerOf candidate =
    case [d | (ConwaySpending _, (d, _)) <- Map.toList redeemerMap] of
        [d] -> Just (unLedgerData d)
        _ -> Nothing
  where
    Redeemers redeemerMap = candidate ^. witsTxL . rdmrsTxWitsL

unLedgerData :: Ledger.Data ConwayEra -> PLC.Data
unLedgerData (Ledger.Data d) = d

-- | The withdrawal set the enforcement observer coupling requires.
expectedEnforcementWithdrawal :: CheckpointEnv -> Withdrawals
expectedEnforcementWithdrawal env =
    Withdrawals $
        Map.singleton
            ( AccountAddress
                Testnet
                (AccountId (ScriptHashObj (checkpointEnforcementHashOf env)))
            )
            (Coin 0)

{- | The frozen Aiken action position for @ObserveFreeze@
(@observer.observe_freeze@).
-}
observeFreezeAction :: Integer
observeFreezeAction = 2

{- | The applied checkpoint hash, which is the observer claim's
@checkpoint_policy@.
-}
checkpointPolicyBytes :: CheckpointEnv -> BS.ByteString
checkpointPolicyBytes env =
    case hashScript (checkpointScriptOf env) of
        ScriptHash hash -> hashToBytes hash

-- | The Aiken @OutputReference@ spelling of a ledger 'TxIn'.
outputReferenceData :: TxIn -> PLC.Data
outputReferenceData (TxIn (TxId txId) (TxIx index)) =
    Constr 0 [B (hashToBytes (extractHash txId)), I (toInteger index)]

{- | The EXACT Freeze @ObserverEnvelope@ the enforcement observer requires:
the @ObserveFreeze@ action, the applied checkpoint hash as
@checkpoint_policy@, @Some own_ref@ naming the actual spent checkpoint input,
and the unchanged live 'EnforcementEvidence' as the payload.

This is a test-only expectation; it is not a production encoder.
-}
expectedFreezeObserverEnvelope :: ArmCandidate -> PLC.Data
expectedFreezeObserverEnvelope arm =
    Constr
        0
        [ Constr
            0
            [ I observeFreezeAction
            , B (checkpointPolicyBytes (acEnv arm))
            , Constr 0 [outputReferenceData (armOwnRef arm)]
            ]
        , enforcementEvidenceData (acEvidence arm)
        ]

{- | One complete observation record of the enforcement-observer coupling and
of every 'computeScriptIntegrity' input.

All axes are computed independently and compared as a whole, so an absent or
wrong Rewarding redeemer cannot prevent the witness, purpose-map, language,
datum-witness and body-integrity results from being observed.
-}
data ObserverContract = ObserverContract
    { ocRewardingRedeemer :: Maybe (PLC.Data, ExUnits)
    , ocEnforcementScriptObserved :: Bool
    , ocPurposes :: Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
    , ocLanguages :: Set.Set Language
    , ocDatumWitnesses :: Map.Map DataHash (Ledger.Data ConwayEra)
    , ocIntegrityHashMatches :: Bool
    }
    deriving stock (Eq, Show)

-- | Observe the complete enforcement-observer contract of one transaction.
observeObserverContractIn ::
    Provider IO ->
    ArmCandidate ->
    PParams ConwayEra ->
    ConwayTx ->
    IO ObserverContract
observeObserverContractIn provider arm params tx = do
    -- Verdict B4: the reference-script observation resolves through the
    -- ACQUISITION-OWNED provider, not through a post-construction lookup.
    referenced <- referencedEnforcementScriptIn provider (acEnv arm) tx
    pure
        ObserverContract
            { ocRewardingRedeemer =
                fmap (first unLedgerData) rewarding
            , ocEnforcementScriptObserved =
                Map.lookup (checkpointEnforcementHashOf env) witnessed
                    == Just (checkpointEnforcementScriptOf env)
                    || referenced
            , ocPurposes = Map.keysSet redeemerMap
            , ocLanguages = scriptLanguages witnessed
            , ocDatumWitnesses = datums
            , ocIntegrityHashMatches =
                (tx ^. bodyTxL . scriptIntegrityHashTxBodyL)
                    == computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        (tx ^. witsTxL . rdmrsTxWitsL)
                        (tx ^. witsTxL . datsTxWitsL)
            }
  where
    env = acEnv arm
    witnessed = tx ^. witsTxL . scriptTxWitsL
    Redeemers redeemerMap = tx ^. witsTxL . rdmrsTxWitsL
    TxDats datums = tx ^. witsTxL . datsTxWitsL
    rewarding = Map.lookup (ConwayRewarding (AsIx 0)) redeemerMap

{- | The complete contract the corrected Arm candidate must satisfy: the exact
Freeze envelope at the observer's budget, the exact enforcement script
observed, the exact two-purpose map, the V3 language set, an empty datum
witness set, and a body integrity hash recomputed over exactly those inputs.
-}
expectedObserverContract :: ArmCandidate -> ConwayTx -> ObserverContract
expectedObserverContract arm tx =
    ObserverContract
        { ocRewardingRedeemer =
            -- A-070 70.2A point 2: the observer purpose must carry a MEASURED
            -- two-pass declaration, not the old placeholder ceiling. The
            -- expectation is derived independently here, by applying the same
            -- deterministic margin to the units the offline evaluation seam
            -- reports, so it is not a restatement of whatever the builder
            -- happened to declare.
            Just
                ( expectedFreezeObserverEnvelope arm
                , deterministicMargin offlineObservedUnits
                )
        , ocEnforcementScriptObserved = True
        , ocPurposes =
            Set.fromList
                [ ConwaySpending (AsIx (checkpointSpendingIndex arm tx))
                , ConwayRewarding (AsIx 0)
                ]
        , ocLanguages = Set.singleton PlutusV3
        , ocDatumWitnesses = Map.empty
        , ocIntegrityHashMatches = True
        }

{- | The Spending index the checkpoint input actually occupies in the
candidate's own ordered input set.
-}
checkpointSpendingIndex :: ArmCandidate -> ConwayTx -> Word32
checkpointSpendingIndex arm tx =
    fromIntegral $
        Set.findIndex (armOwnRef arm) (tx ^. bodyTxL . inputsTxBodyL)

{- | Whether a reference input of the transaction actually carries the exact
enforcement observer script, which is the allowed alternative to witnessing
it directly.
-}
referencedEnforcementScriptIn ::
    Provider IO -> CheckpointEnv -> ConwayTx -> IO Bool
referencedEnforcementScriptIn provider env tx
    | Set.null references = pure False
    | otherwise = do
        resolved <- queryUTxOByTxIn provider references
        pure $ any carriesEnforcement (Map.elems resolved)
  where
    references = tx ^. bodyTxL . referenceInputsTxBodyL
    carriesEnforcement out =
        (out ^. referenceScriptTxOutL)
            == SJust (checkpointEnforcementScriptOf env)

-- | The Plutus languages the witnessed scripts actually belong to.
scriptLanguages :: Map.Map ScriptHash (Script ConwayEra) -> Set.Set Language
scriptLanguages =
    Set.fromList . mapMaybe languageOf . Map.elems
  where
    languageOf = \case
        PlutusScript plutus -> Just (plutusScriptLanguage plutus)
        _ -> Nothing

{- | The candidate's own frozen serialization, decoded back with the ledger
codec at the Conway-era protocol version.

Both D3 observations are made on THIS decoded object, so the assertion is
about the bytes a node would see rather than about the in-memory builder
result.
-}
decodedCandidate :: ConwayTx -> IO ConwayTx
decodedCandidate candidate =
    case decodeFullAnnotator
        (eraProtVerLow @ConwayEra)
        "A-065 serialized Arm candidate"
        decCBOR
        (serializedTxBytes candidate) of
        Right decoded -> pure decoded
        Left err -> fail ("decodedCandidate: " <> show err)

{- | Whether an output sits at the Armed role address AND carries this
candidate's exact 'ArmedDatum' lineage: the spent checkpoint's own datum and
the hunter the candidate Armed for. A generic three-field decoy datum, or an
Armed-shaped datum from another lineage, is not a match.
-}
isArmedLineageOutput :: ArmCandidate -> TxOut ConwayEra -> Bool
isArmedLineageOutput arm out =
    out ^. addrTxOutL == roleAddress (acEnv arm) Armed
        && maybe False armedLineage (inlineArmedDatum out)
  where
    armedLineage armed =
        adCheckpoint armed == checkpointDatum (acInput arm)
            && adHunterPkh armed == offlineHunter

-- | The output's inline datum decoded through the real 'ArmedDatum' decoder.
inlineArmedDatum :: TxOut ConwayEra -> Maybe ArmedDatum
inlineArmedDatum out =
    case out ^. datumTxOutL of
        Datum binaryData ->
            fromBuiltinData
                (BuiltinData (getPlutusData (binaryDataToData binaryData)))
        _ -> Nothing

{- | The UNIQUE Armed output's decoded datum. Zero matches and more than one
match are both rejected.
-}
uniqueArmedDatumOf :: ArmCandidate -> ConwayTx -> Maybe ArmedDatum
uniqueArmedDatumOf arm tx =
    case matches of
        [armed] -> Just armed
        _ -> Nothing
  where
    matches =
        [ armed
        | out <- toList (tx ^. bodyTxL . outputsTxBodyL)
        , isArmedLineageOutput arm out
        , Just armed <- [inlineArmedDatum out]
        ]

-- | 'uniqueArmedDatumOf' as a loud failure rather than a silent 'Nothing'.
uniqueArmedDatum :: ArmCandidate -> ConwayTx -> IO ArmedDatum
uniqueArmedDatum arm tx =
    maybe
        ( fail
            "uniqueArmedDatum: the transaction does not carry exactly one \
            \Armed role output at this checkpoint lineage"
        )
        pure
        (uniqueArmedDatumOf arm tx)

{- | The transaction's OWN serialized validity upper bound, translated to
POSIX milliseconds through the complete fixture 'Globals' coordinate.

This is the D3 observation: the deadline the builder encoded is compared
against the coordinate the serialized context actually carries, not against
the builder's own private time source.
-}
serializedUpperPosixMs :: Globals -> ConwayTx -> IO Integer
serializedUpperPosixMs globals candidate =
    case candidate ^. bodyTxL . vldtTxBodyL of
        ValidityInterval _ (SJust upper) ->
            case epochInfoSlotToRelativeTime_ (epochInfo globals) upper of
                Right (RelativeTime seconds) ->
                    pure (syntheticSlotStartMs (SlotNo 0) + round (seconds * 1000))
                Left err ->
                    fail
                        ( "serializedUpperPosixMs: fixture coordinate refused the \
                          \serialized upper bound: "
                            <> T.unpack err
                        )
        _ -> fail "serializedUpperPosixMs: candidate has no validity upper bound"

-- | The three ordered D1/D2/D3 shape observations for one candidate.
data ArmShape = ArmShape
    { shapeD1 :: Bool
    , shapeD2 :: Bool
    , shapeD3 :: Bool
    }
    deriving stock (Eq, Show)

{- | The D1/D2/D3 verdict, using the SAME exact contracts the individual
examples assert: D2 is the exact withdrawal plus the complete
'ObserverContract' record, and D3 is read from the transaction's own decoded
serialization.
-}
armShapeVerdict ::
    Provider IO ->
    ArmCandidate ->
    PParams ConwayEra ->
    Globals ->
    ConwayTx ->
    IO ArmShape
armShapeVerdict provider arm params globals tx = do
    decoded <- decodedCandidate tx
    upperMs <- serializedUpperPosixMs globals decoded
    observed <- observeObserverContractIn provider arm params tx
    pure
        ArmShape
            { shapeD1 =
                spendingRedeemerOf tx == Just (Constr 1 [B offlineHunter])
            , shapeD2 =
                (tx ^. bodyTxL . withdrawalsTxBodyL)
                    == expectedEnforcementWithdrawal (acEnv arm)
                    && observed == expectedObserverContract arm tx
            , shapeD3 =
                fmap adDeadline (uniqueArmedDatumOf arm decoded)
                    == Just (upperMs + freezeWindow)
            }

{- | Recompute the body script-integrity hash over a transaction's own
redeemer and datum witnesses, so a test-only witness correction does not leave
a stale hash behind and mask the axis under test.
-}
reintegrate :: PParams ConwayEra -> ConwayTx -> ConwayTx
reintegrate params tx =
    tx
        & bodyTxL
            . scriptIntegrityHashTxBodyL
            .~ computeScriptIntegrity
                (Set.singleton PlutusV3)
                params
                (tx ^. witsTxL . rdmrsTxWitsL)
                (tx ^. witsTxL . datsTxWitsL)

{- | Diagnostic, TEST-ONLY REGRESSION of D1 alone: put the legacy two-field
Freeze redeemer back. No production code is changed, and no other axis is
touched — the withdrawal, observer redeemer, witness and deadline all stay
exactly as production built them.
-}
regressD1 :: ArmCandidate -> PParams ConwayEra -> ConwayTx -> ConwayTx
regressD1 arm params candidate =
    reintegrate params $
        candidate
            & witsTxL
                . rdmrsTxWitsL
                .~ Redeemers (Map.mapWithKey legacy redeemerMap)
  where
    Redeemers redeemerMap = candidate ^. witsTxL . rdmrsTxWitsL
    legacy (ConwaySpending _) (_, units) =
        ( Ledger.Data
            ( Constr
                1
                [ enforcementEvidenceData (acEvidence arm)
                , B offlineHunter
                ]
            )
        , units
        )
    legacy _ entry = entry

{- | Diagnostic, TEST-ONLY REGRESSION of the complete D2 observer coupling:
remove the enforcement withdrawal, its Rewarding redeemer and its script
witness together, and recompute the integrity hash so the axis under test is
the coupling itself rather than a stale hash.
-}
regressD2 :: ArmCandidate -> PParams ConwayEra -> ConwayTx -> ConwayTx
regressD2 arm params candidate =
    reintegrate params $
        candidate
            & bodyTxL
                . withdrawalsTxBodyL
                .~ Withdrawals Map.empty
            & witsTxL
                . scriptTxWitsL
                %~ Map.delete (checkpointEnforcementHashOf (acEnv arm))
            & witsTxL
                . rdmrsTxWitsL
                %~ dropObserverRedeemer
  where
    dropObserverRedeemer (Redeemers m) =
        Redeemers (Map.delete (ConwayRewarding (AsIx 0)) m)

{- | Diagnostic, TEST-ONLY REGRESSION of D3 alone: move the successor deadline
off the coordinate the serialized validity upper actually carries, leaving
every other axis exactly as production built it.
-}
regressD3 :: ArmCandidate -> ConwayTx -> ConwayTx
regressD3 arm candidate =
    case uniqueArmedDatumOf arm candidate of
        Nothing -> candidate
        Just armed ->
            realignUniqueArmedOutput arm (adDeadline armed + 1) candidate

{- | Rewrite the deadline of EXACTLY the unique Armed-role output at this
candidate's checkpoint lineage, leaving every other output untouched. Without
such a unique output the transaction is returned unchanged, so the D3 axis
fails loudly rather than being rewritten by a wildcard.
-}
realignUniqueArmedOutput :: ArmCandidate -> Integer -> ConwayTx -> ConwayTx
realignUniqueArmedOutput arm deadline tx =
    case uniqueArmedDatumOf arm tx of
        Nothing -> tx
        Just armed ->
            tx & bodyTxL . outputsTxBodyL %~ fmap (realign armed)
  where
    realign armed out
        | isArmedLineageOutput arm out =
            out
                & datumTxOutL
                    .~ mkInlineDatum (asPlcData armed{adDeadline = deadline})
        | otherwise = out

-- ---------------------------------------------------------------------------
-- A-063 RED-END: the applied checkpoint validator, executed offline
-- ---------------------------------------------------------------------------

{- | The result of running the DEPLOYED, APPLIED checkpoint validator against
the exact production-plan context.

Everything a reader needs to re-derive the run independently is carried here:
which script (by its on-chain hash and its applied byte length), which
context (by the serialized transaction the context was translated from), the
budget the interpreter actually consumed, and the verdict.
-}
data ReplayReport = ReplayReport
    { replayScriptHash :: !ScriptHash
    , replayScriptBytes :: !Int
    , replayContextTxId :: !TxId
    , replayContextBytes :: !Int
    , replayVerdict :: !String
    , replayLogs :: ![Text]
    }

{- | RED-END (A-063 step 5, deferred to GREEN by operator ruling Q-015 option
(c)): translate the EXACT corrected production Arm candidate into its Plutus
V3 ScriptContext and run the applied checkpoint validator on it.

The context is produced by the ledger's own translation
('collectPlutusScriptsWithContext') from the real candidate, the real
resolved UTxO and the real protocol parameters, under the SAME acquired
coordinate the builder used — so this is the context a node would build, not
a test-authored one. Nothing about the transaction is corrected, patched or
substituted between building it and evaluating it.
-}
appliedCheckpointReplayIn ::
    Globals ->
    Provider IO ->
    CheckpointEnv ->
    ConwayTx ->
    [(TxIn, TxOut ConwayEra)] ->
    IO ReplayReport
appliedCheckpointReplayIn globals provider env candidate resolvedInputs = do
    params <- queryProtocolParams provider
    let utxo = UTxO (Map.fromList resolvedInputs)
    contexts <-
        either
            (fail . ("appliedCheckpointReplay: " <>) . show)
            pure
            ( collectPlutusScriptsWithContext
                (epochInfo globals)
                (systemStart globals)
                params
                candidate
                utxo
            )
    pwc <-
        case filter ((== checkpointHash) . pwcScriptHash) contexts of
            [one] -> pure one
            other ->
                fail
                    ( "appliedCheckpointReplay: expected exactly one \
                      \checkpoint script context, got "
                        <> show (length other)
                    )
    let (logs, result) = runPlutusScriptWithLogs pwc
    pure
        ReplayReport
            { replayScriptHash = checkpointHash
            , replayScriptBytes =
                SBS.length (checkpointAppliedBytesOf env)
            , replayContextTxId = txIdTx candidate
            , replayContextBytes =
                fromIntegral (BSL.length (serializedTxBytes candidate))
            , replayVerdict = case result of
                Passes _ -> "Passes"
                Fails _ failures ->
                    "Fails "
                        <> show (fmap scriptFailureMessage (toList failures))
            , replayLogs = logs
            }
  where
    checkpointHash = hashScript (checkpointScriptOf env)

-- | The frozen, human-readable identification of one applied-validator run.
renderReplayEvidence :: ReplayReport -> String
renderReplayEvidence report =
    unlines
        [ "A065-END applied-validator replay"
        , "  applied-checkpoint-script-hash: "
            <> show (replayScriptHash report)
        , "  applied-checkpoint-script-bytes: "
            <> show (replayScriptBytes report)
        , "  production-context-tx-id: " <> show (replayContextTxId report)
        , "  production-context-tx-bytes: "
            <> show (replayContextBytes report)
        , "  verdict: " <> replayVerdict report
        , "  interpreter-logs: " <> show (replayLogs report)
        ]

-- ---------------------------------------------------------------------------
-- A-071 71A: the authorized single-axis collateral-boundary negative
-- ---------------------------------------------------------------------------

{- | Everything the A-071 contract requires frozen about one negative.

The object under test is a GENUINE production-built, production-balanced
candidate with EXACTLY ONE named axis mutated: its collateral input is
replaced by a fully resolved ADA-only key UTxO worth exactly @r - 1@, one
lovelace below the ledger's own collateral requirement. The production fee
and every non-collateral field are preserved byte-for-byte. It is a mutated
candidate and is labelled as one; it is not a synthetic transaction.
-}
data CollateralNegative = CollateralNegative
    { cnFee :: !Integer
    -- ^ @f@: the production candidate's exact derived final fee.
    , cnPercent :: !Integer
    -- ^ @p@: collateral percentage, read from the same acquired parameters.
    , cnRequired :: !Integer
    -- ^ @r = ceil(f * p / 100)@, by the ledger's own rule — never a literal.
    , cnSuppliedLovelace :: !Integer
    -- ^ @r - 1@: the mutated collateral's exact resolved lovelace.
    , cnBaselineResolved :: !(TxIn, TxOut ConwayEra)
    , cnNegativeResolved :: !(TxIn, TxOut ConwayEra)
    , cnFeeUnchanged :: !Bool
    , cnOnlyCollateralAxis :: !Bool
    , cnCandidate :: !ConwayTx
    , cnResolved :: ![(TxIn, TxOut ConwayEra)]
    , cnGlobals :: !Globals
    }

{- | @r = ceil(f * p / 100)@ using the ledger's collateral rule.

The percentage comes from the acquired protocol parameters, so nothing here
is a guessed constant.
-}
collateralRequired :: PParams ConwayEra -> Integer -> Integer
collateralRequired params fee =
    (fee * percent + 99) `div` 100
  where
    percent = fromIntegral (params ^. ppCollateralPercentageL)

{- | Build the production Advance candidate, then derive its ONE authorized
collateral-boundary mutation (A-071 71A).
-}
withCollateralNegativeAdvance ::
    CheckpointSeam -> (CollateralNegative -> Provider IO -> IO a) -> IO a
withCollateralNegativeAdvance seam observe = do
    (fixture, _) <- loadLifecycleFixture
    let env = seamEnvOf seam
    withCheckpointPhase1Snapshot env $ \_globals provider -> do
        params <- queryProtocolParams provider
        validity <- currentValidityIn _globals provider
        baseline <-
            buildAdvanceTx
                env
                (offlineStagedCheckpoint env (rfDatum fixture))
                (rfDatum fixture)
                dummyAdvanceEvidence
                validity
                False
        let fee = unCoin (baseline ^. bodyTxL . feeTxBodyL)
            percent = fromIntegral (params ^. ppCollateralPercentageL)
            required = collateralRequired params fee
            supplied = required - 1
            baselineCollateral =
                case Set.toList (baseline ^. bodyTxL . collateralInputsTxBodyL) of
                    [one] -> one
                    other ->
                        error
                            ( "withCollateralNegativeAdvance: expected exactly \
                              \one production collateral input, got "
                                <> show other
                            )
            (negativeIn, negativeOutBase) =
                referenceOutput 0xf1 (checkpointScriptOf env)
            negativeOut =
                mkBasicTxOut (offlineWalletAddr negativeOutBase) (inject (Coin supplied))
            -- The ONLY mutation: the collateral axis. Fee, inputs, outputs,
            -- withdrawals, references, redeemers, datums, witnesses and the
            -- integrity hash are the production candidate's own bytes.
            -- The collateral AXIS as a whole: the input and its own bookkeeping
            -- fields must describe the same collateral, otherwise the body is
            -- internally inconsistent and the ledger reports a SECOND,
            -- unrelated failure instead of the boundary under test.
            mutated =
                baseline
                    & bodyTxL
                        . collateralInputsTxBodyL
                        .~ Set.singleton negativeIn
                    & bodyTxL
                        . totalCollateralTxBodyL
                        .~ SJust (Coin supplied)
                    & bodyTxL
                        . collateralReturnTxBodyL
                        .~ SNothing
        -- Resolve the BASELINE collateral through the same provider view, so
        -- both collateral identities are frozen as resolved (TxIn, TxOut)
        -- facts rather than bare references.
        baselineResolvedMap <-
            queryUTxOByTxIn provider (Set.singleton baselineCollateral)
        baselineCollateralOut <-
            case Map.lookup baselineCollateral baselineResolvedMap of
                Just out -> pure out
                Nothing ->
                    fail
                        ( "withCollateralNegativeAdvance: the production \
                          \collateral input did not resolve: "
                            <> show baselineCollateral
                        )
        -- Register the mutated collateral so the REAL unchanged guard resolves
        -- it through the seam's own provider view.
        modifyIORef' (seamResolvedRef seam) ((negativeIn, negativeOut) :)
        flip observe provider $
            CollateralNegative
                { cnFee = fee
                , cnPercent = percent
                , cnRequired = required
                , cnSuppliedLovelace = supplied
                , cnBaselineResolved = (baselineCollateral, baselineCollateralOut)
                , cnNegativeResolved = (negativeIn, negativeOut)
                , cnFeeUnchanged =
                    (mutated ^. bodyTxL . feeTxBodyL)
                        == (baseline ^. bodyTxL . feeTxBodyL)
                , cnOnlyCollateralAxis = onlyCollateralAxisDiffers baseline mutated
                , cnCandidate = mutated
                , cnResolved =
                    (negativeIn, negativeOut) : seamExpectedResolved seam
                , cnGlobals = _globals
                }

-- | The owner address of an offline wallet output.
offlineWalletAddr :: TxOut ConwayEra -> Addr
offlineWalletAddr out = out ^. addrTxOutL

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

isBoundedHorizonFailure :: Either Text a -> Bool
isBoundedHorizonFailure (Left message) =
    "past the bounded horizon" `T.isInfixOf` message
isBoundedHorizonFailure _ = False

providerFloorThrows :: Integer -> IO Bool
providerFloorThrows ms =
    (posixMsToSlot syntheticCoordinateProvider ms >> pure False)
        `catch` \(_ :: SomeException) -> pure True

providerCeilThrows :: Integer -> IO Bool
providerCeilThrows ms =
    (posixMsCeilSlot syntheticCoordinateProvider ms >> pure False)
        `catch` \(_ :: SomeException) -> pure True

assertCandidateFits ::
    String ->
    (CheckpointEnv -> RegistrationFixture -> EnforcementEvidence -> IO ConwayTx) ->
    Expectation
assertCandidateFits label build = do
    seam <- newStagedSeam [(0xaa, 2_000_000_000), (0xbb, 2_000_000_000)]
    guardParams <- loadPv11GuardParams
    let env = seamEnvOf seam
    (fixture, armEvidence) <- loadLifecycleFixture
    candidate <- build env fixture armEvidence
    assertAllInputsResolve seam candidate
    -- Use the provider's own tip, exactly as the production guard does, so a
    -- real validity interval is judged against the real current slot.
    withCheckpointPhase1Snapshot env $ \globals provider -> do
        snapshot <- queryLedgerSnapshot provider
        let verdict =
                runPhase1
                    Phase1Input
                        { p1Globals = globals
                        , p1Slot = ledgerTipSlot snapshot
                        , p1Params = guardParams
                        , p1ResolvedInputs = seamExpectedResolved seam
                        }
                    -- A-070 70.2A point 5: the SAME derivation production
                    -- uses, so the corrected body's enforcement withdrawal is
                    -- seeded exactly as the real guard seeds it.
                    (bodyRewardState candidate)
                    candidate
            rendered = renderPhase1 verdict
        rendered `shouldNotSatisfy` isInfixOf "MaxTxSizeUTxO"
        (label, phase1Structural verdict) `shouldBe` (label, [])

twoPassObservableOutcomes :: Spec
twoPassObservableOutcomes =
    describe "offline batched PV11 capture contract" $
        describe "two-pass observable outcomes" $ do
            it "the exact final Register object declares aggregate exunits within ppMaxTxExUnits" $ do
                (seam, discovery) <- newRegisterSeam
                guardParams <- loadPv11GuardParams
                assertAllInputsResolve seam discovery
                assertNoBadInputs seam guardParams discovery
                (fixture, _) <- loadLifecycleFixture
                -- The FINAL binding is what must fit; the discovery binding is
                -- intentionally over the limit.
                let env = seamEnvOf seam
                final <-
                    buildTwoPassFinalRegister
                        env
                        "offline final Register"
                        (offlineRegisterReferences env)
                        fixture
                        (offlineProofUtxo env fixture)
                let ExUnits maxMem maxSteps = pv11MaxTxExUnits guardParams
                    (mem, steps) = declaredAggregate final
                (mem, steps) `shouldSatisfy` (\(m, s) -> m <= maxMem && s <= maxSteps)
            it "an aggregate-over-limit candidate is rejected before submission naming ExUnitsTooBigUTxO" $ do
                (seam, candidate) <- newRegisterSeam
                runRoute seam "ExUnitsTooBigUTxO" $ \env ->
                    void $ submitUnchangedCapture env "offline Register" candidate
            it "the exact submitted BYTES equal the exact evaluated BYTES on the real Register binding" $ do
                (seam, candidate) <- newRegisterSeam
                let env = seamEnvOf seam
                assertAllInputsResolve seam candidate
                (fixture, _) <- loadLifecycleFixture
                _ <-
                    tryAnyCheckpoint $
                        submitTwoPassRegister
                            env
                            "offline Register two-pass"
                            (offlineRegisterReferences env)
                            fixture
                            (offlineProofUtxo env fixture)
                evaluated <- readIORef (seamEvaluated seam)
                submitted <- readIORef (seamSubmitted seam)
                -- Complete serialized transaction bytes, not TxId: a TxId
                -- commits to the body only, so witness-set or auxiliary-data
                -- drift under an unchanged body hash must still fail here.
                -- REVIEW-023 finding 4: compare the one submitted object against
                -- the FINAL re-evaluated binding only. The discovery binding is
                -- intentionally different and must not be compared.
                length submitted `shouldBe` 1
                case reverse evaluated of
                    (finalEvaluated : _) ->
                        map serializedTxBytes submitted
                            `shouldBe` [serializedTxBytes finalEvaluated]
                    [] -> expectationFailure "no evaluation was captured"
                mapM_ (assertAllInputsResolve seam) submitted

-- | The declared aggregate execution units of a candidate's redeemer set.
declaredAggregate :: ConwayTx -> (Natural, Natural)
declaredAggregate tx =
    ( sum [exUnitsMem eu | (_, eu) <- entries]
    , sum [exUnitsSteps eu | (_, eu) <- entries]
    )
  where
    Redeemers redeemerMap = tx ^. witsTxL . rdmrsTxWitsL
    entries = Map.elems redeemerMap

-- | The pinned old-cost Plutus V3 model size the hash-proof exit asserts.
oldCostEntries :: Int
oldCostEntries = 251

{- | One offline Checkpoint seam: the composed PV11 guard parameters, a wallet,
a recording submitter, and a recording evaluator. Recording is what makes
"the guard stopped it" and "submitted bytes equal evaluated bytes" observable.
-}
data CheckpointSeam = CheckpointSeam
    { seamEnvOf :: CheckpointEnv
    , seamSubmitted :: IORef [ConwayTx]
    , seamEvaluated :: IORef [ConwayTx]
    , seamExpectedResolved :: [(TxIn, TxOut ConwayEra)]
    , seamResolvedRef :: IORef [(TxIn, TxOut ConwayEra)]
    {- ^ The live resolver state. An output PRODUCED inside an acquisition
    (notably the real Register candidate's ACTIVE output) is added here so
    the same acquisition can resolve it, without a second seam.
    -}
    }

data ArmEvaluationAdvance
    = KeepEvaluationTip
    | AdvanceEvaluationBy Word64
    | AdvanceEvaluationBeyondUpper

{- | The seam phase (A-070/NOTE-058 B1).

The authorized two-pass Arm preparation evaluates TWICE internally. Those
preparation evaluations are not the external latency boundary this seam
models, so the tip advances at the EXTERNAL evaluation only.
-}
data ArmSeamPhase
    = PreparationPhase
    | ExternalPhase
    deriving stock (Eq, Show)

{- | A NAMED boundary event (A-070 / NOTE-058 B1).

The contract is about which boundary was reached, at which acquired slot,
and over which exact candidate bytes — never about how many provider queries
happened to occur.
-}
data ArmBoundaryEvent
    = BuildAnchor SlotNo
    | FinalPreparationGuard SlotNo
    | ExternalPreEvaluationGuard SlotNo
    | ExternalEvaluation SlotNo BSL.ByteString
    | ExternalPreSubmitGuard SlotNo
    | ExternalSubmission BSL.ByteString
    deriving stock (Eq, Show)

-- | The acquired slot a guard/evaluation boundary observed, if it has one.
eventSlot :: ArmBoundaryEvent -> Maybe SlotNo
eventSlot = \case
    BuildAnchor slot -> Just slot
    FinalPreparationGuard slot -> Just slot
    ExternalPreEvaluationGuard slot -> Just slot
    ExternalEvaluation slot _ -> Just slot
    ExternalPreSubmitGuard slot -> Just slot
    ExternalSubmission _ -> Nothing

data AdvancingArmSeam = AdvancingArmSeam
    { armSeamEnv :: CheckpointEnv
    , armSeamPhase :: IORef ArmSeamPhase
    , armSeamEvents :: IORef [ArmBoundaryEvent]
    , armSeamSnapshots :: IORef [SlotNo]
    , armSeamEvaluated :: IORef [ConwayTx]
    , armSeamSubmitted :: IORef [ConwayTx]
    , armSeamSettled :: IORef [ConwayTx]
    }

{- | The advancing seam's anchor tip, rebased into the ONE canonical
downstream coordinate (A-069 69A point 3).

Every observable this seam exists to pin is a RELATION, not a magnitude:
@anchor < first guard < second guard@, the Arm window open at both guards,
the beyond-upper counterfactual failing, and the stored deadline equal to the
final upper POSIX time plus exactly @freezeWindow@. All of them survive the
rebase; only the legacy slot-one-million bookkeeping does not. The anchor is
low enough that the advanced horizon below still lands inside @0..199@, so
slot @200@ keeps failing exactly as the frozen RED requires.
-}
armAnchorTip :: SlotNo
armAnchorTip = SlotNo 20

armFirstGuardTip :: SlotNo
armFirstGuardTip = SlotNo (unSlotNo armAnchorTip + 4)

armSecondGuardTip :: SlotNo
armSecondGuardTip = SlotNo (unSlotNo armFirstGuardTip + 1)

{- | The seam's initial forecast horizon: ahead of both guard tips and of the
Arm upper bound, and inside the canonical horizon.
-}
armInitialHorizon :: SlotNo
armInitialHorizon = SlotNo (unSlotNo armAnchorTip + 50)

{- | The horizon after the node forecast advances. Strictly beyond
'armInitialHorizon' — the observable — while remaining translatable inside
the canonical @0..199@ coordinate.
-}
armAdvancedHorizon :: SlotNo
armAdvancedHorizon = SlotNo (unSlotNo armAnchorTip + 170)

newAdvancingArmSeam :: ArmEvaluationAdvance -> IO AdvancingArmSeam
newAdvancingArmSeam evaluationAdvance = do
    let wallet = [(0xaa, 2_000_000_000), (0xbb, 2_000_000_000)]
    bootstrap <- newCheckpointSeam wallet
    (fixture, _) <- loadLifecycleFixture
    let stagedPair = offlineStagedUtxo (seamEnvOf bootstrap) (rfDatum fixture)
        enforcementRefPair = offlineEnforcementReference (seamEnvOf bootstrap)
        resolvedPairs = stagedPair : enforcementRefPair : walletPairs
        walletPairs = offlineWalletOf wallet
    submitted <- newIORef []
    evaluated <- newIORef []
    settled <- newIORef []
    snapshots <- newIORef []
    phaseRef <- newIORef PreparationPhase
    eventsRef <- newIORef []
    externalEvaluatedRef <- newIORef False
    tip <- newIORef armAnchorTip
    horizon <- newIORef armInitialHorizon
    horizonQueries <- newIORef (0 :: Int)
    guardParams <- loadPv11GuardParams
    blueprint <-
        lookupEnv "KERI_CHECKPOINT_BLUEPRINT"
            >>= maybe
                ( lookupEnv "KERI_CAGE_BLUEPRINT"
                    >>= maybe (fail "KERI_CHECKPOINT_BLUEPRINT not set") pure
                )
                pure
    -- A-069 69A points 3 and 5: the seam's POSIX origin is the canonical
    -- coordinate's own system start, NOT a wall clock. A reconstructed origin
    -- is exactly the provenance A-065 forbids, and it is what made this seam
    -- disagree with the callback 'Globals'.
    let slotFloor = syntheticFloorSlot
        slotCeil = syntheticCeilSlot
        bounded convert ms = do
            currentHorizon <- readIORef horizon
            case convert ms of
                Left err -> fail ("advancing Arm seam: " <> T.unpack err)
                Right converted
                    | converted <= currentHorizon -> pure converted
                    | otherwise -> fail "advancing Arm seam: PastHorizon"
        seams =
            defaultOfflineSeams
                { seamEvaluate = \tx -> do
                    modifyIORef' evaluated (<> [tx])
                    -- B1: advance ONLY at the external evaluation boundary;
                    -- the two internal preparation evaluations do not model
                    -- node latency and must not move the tip.
                    phase <- readIORef phaseRef
                    when (phase == ExternalPhase) $ do
                        currentTip <- readIORef tip
                        modifyIORef'
                            eventsRef
                            (<> [ExternalEvaluation currentTip (serializedTxBytes tx)])
                        writeIORef externalEvaluatedRef True
                    case (if phase == ExternalPhase then evaluationAdvance else KeepEvaluationTip) of
                        KeepEvaluationTip -> pure ()
                        AdvanceEvaluationBy amount ->
                            modifyIORef' tip $ \(SlotNo current) ->
                                SlotNo (current + amount)
                        AdvanceEvaluationBeyondUpper ->
                            writeIORef tip (upperValiditySlotOf tx)
                    pure (evaluatedPurposesFor tx)
                , seamResolve =
                    pure . Map.restrictKeys (Map.fromList resolvedPairs)
                }
        baseProvider =
            offlineProviderWith seams guardParams walletPairs
        advancingProvider =
            baseProvider
                { queryLedgerSnapshot = do
                    snapshot <- queryLedgerSnapshot baseProvider
                    seenSnapshots <- readIORef snapshots
                    case seenSnapshots of
                        [] -> pure ()
                        _ -> do
                            currentTip <- readIORef tip
                            when (currentTip == armAnchorTip) $
                                writeIORef tip armFirstGuardTip
                    currentTip <- readIORef tip
                    modifyIORef' snapshots (<> [currentTip])
                    -- Name the boundary this snapshot belongs to.
                    phase <- readIORef phaseRef
                    externalEvaluated <- readIORef externalEvaluatedRef
                    priorEvents <- readIORef eventsRef
                    let named
                            | phase == PreparationPhase
                            , null priorEvents =
                                BuildAnchor currentTip
                            | phase == PreparationPhase = FinalPreparationGuard currentTip
                            | externalEvaluated = ExternalPreSubmitGuard currentTip
                            | otherwise = ExternalPreEvaluationGuard currentTip
                    modifyIORef' eventsRef (<> [named])
                    pure snapshot{ledgerTipSlot = currentTip}
                , posixMsToSlot = bounded slotFloor
                , posixMsCeilSlot = bounded slotCeil
                , queryUpperBoundSlot = \_ -> do
                    modifyIORef' horizonQueries (+ 1)
                    queryNo <- readIORef horizonQueries
                    if queryNo >= 4
                        then do
                            writeIORef horizon armAdvancedHorizon
                            writeIORef tip armFirstGuardTip
                            pure (Right armAdvancedHorizon)
                        else Right <$> readIORef horizon
                }
    env <-
        mkCheckpointEnvWith
            blueprint
            advancingProvider
            ( Submitter
                { submitTx = \tx -> do
                    modifyIORef' submitted (<> [tx])
                    modifyIORef' settled (<> [tx])
                    modifyIORef'
                        eventsRef
                        (<> [ExternalSubmission (serializedTxBytes tx)])
                    pure (Submitted (txIdTx tx))
                }
            )
            (offlinePhase1Snapshot advancingProvider)
    pure
        AdvancingArmSeam
            { armSeamEnv = env
            , armSeamPhase = phaseRef
            , armSeamEvents = eventsRef
            , armSeamSnapshots = snapshots
            , armSeamEvaluated = evaluated
            , armSeamSubmitted = submitted
            , armSeamSettled = settled
            }

advancingArmCandidate ::
    AdvancingArmSeam ->
    IO (RegistrationFixture, ValidityPlan, ConwayTx)
advancingArmCandidate seam = do
    (fixture, armEvidence) <- loadLifecycleFixture
    (validity, candidate) <-
        buildCurrentArmTx
            (armSeamEnv seam)
            (offlineEnforcementReference (armSeamEnv seam))
            (offlineStagedCheckpoint (armSeamEnv seam) (rfDatum fixture))
            armEvidence
            offlineHunter
    -- Preparation (discovery + exact-final evaluation + final preparation
    -- guard) is complete; everything after this is the EXTERNAL boundary.
    writeIORef (armSeamPhase seam) ExternalPhase
    pure (fixture, validity, candidate)

containsSlot :: ValidityPlan -> SlotNo -> Bool
containsSlot validity slot =
    lowerSlot validity <= slot && slot < upperSlot validity

upperValiditySlotOf :: ConwayTx -> SlotNo
upperValiditySlotOf tx =
    case tx ^. bodyTxL . vldtTxBodyL of
        ValidityInterval _ (SJust upper) -> upper
        _ -> error "Arm candidate has no finite upper validity bound"

newCheckpointSeam :: [(Int, Integer)] -> IO CheckpointSeam
newCheckpointSeam walletEntries = newCheckpointSeamWith walletEntries []

{- | As 'newCheckpointSeam', but the offline Provider also RESOLVES the given
synthesized inputs (the staged Checkpoint UTxO and the hash-proof UTxO), so a
captured candidate carries no unresolved-input noise.
-}
newCheckpointSeamWith ::
    [(Int, Integer)] -> [(TxIn, TxOut ConwayEra)] -> IO CheckpointSeam
newCheckpointSeamWith walletEntries extraResolved = do
    submitted <- newIORef []
    evaluated <- newIORef []
    resolvedRef <- newIORef extraResolved
    guardParams <- loadPv11GuardParams
    blueprint <-
        lookupEnv "KERI_CHECKPOINT_BLUEPRINT"
            >>= maybe
                ( lookupEnv "KERI_CAGE_BLUEPRINT"
                    >>= maybe (fail "KERI_CHECKPOINT_BLUEPRINT not set") pure
                )
                pure
    let seams =
            defaultOfflineSeams
                { seamEvaluate = \tx -> do
                    modifyIORef' evaluated (<> [tx])
                    pure (evaluatedPurposesFor tx)
                , seamResolve = \wanted -> do
                    live <- readIORef resolvedRef
                    pure (Map.restrictKeys (Map.fromList live) wanted)
                }
        offlineSeamProvider =
            offlineProviderWith seams guardParams (offlineWalletOf walletEntries)
    env <-
        mkCheckpointEnvWith
            blueprint
            offlineSeamProvider
            ( Submitter
                { submitTx = \tx -> do
                    modifyIORef' submitted (<> [tx])
                    pure (Rejected "offline: submission seam reached")
                }
            )
            (offlinePhase1Snapshot offlineSeamProvider)
    pure
        CheckpointSeam
            { seamEnvOf = env
            , seamSubmitted = submitted
            , seamEvaluated = evaluated
            , seamExpectedResolved = offlineWalletOf walletEntries <> extraResolved
            , seamResolvedRef = resolvedRef
            }

{- | Run one real route and require it to reject at the guard, naming the exact
ledger failure, without any submission attempt.
-}
runRoute :: CheckpointSeam -> String -> (CheckpointEnv -> IO ()) -> Expectation
runRoute seam needle route = do
    outcome <- tryAnyCheckpoint (route (seamEnvOf seam))
    submitted <- readIORef (seamSubmitted seam)
    -- Per captured candidate: EVERY normal and collateral input must resolve
    -- through the offline Provider, so no BadInputsUTxO noise can appear.
    mapM_ (assertAllInputsResolve seam) submitted
    -- REVIEW-024 finding 1: a structurally rejected ORDINARY route must reach
    -- neither the evaluator nor the submitter. Asserting the evaluator capture
    -- is empty pins guard-BEFORE-evaluation as a regression; without it the
    -- example would still pass with the guard moved below evaluateTx.
    evaluatedCaptures <- readIORef (seamEvaluated seam)
    unless (null evaluatedCaptures) $
        expectationFailure
            ( "route evaluated "
                <> show (length evaluatedCaptures)
                <> " candidate(s) before the guard rejected it; the ordinary"
                <> " guard must run BEFORE evaluation"
            )
    unless (null submitted) $
        expectationFailure
            ( "route reached submitTx with "
                <> show (length submitted)
                <> " candidate(s) instead of rejecting structurally "
                <> "inadmissible final bytes at the guard; expected "
                <> needle
            )
    case outcome of
        Right () ->
            expectationFailure "route accepted structurally inadmissible final bytes"
        Left err -> displayException err `shouldSatisfy` isInfixOf needle

tryAnyCheckpoint :: IO a -> IO (Either SomeException a)
tryAnyCheckpoint = try

{- | A frozen resolved checkpoint input for the Advance route: the exact
staged UTxO the real 'buildAdvanceTx' spends. Only the INPUT is synthesized;
the candidate itself is produced by the real builder.
-}
offlineStagedCheckpoint ::
    CheckpointEnv -> CheckpointDatumV1 -> CheckpointInput
offlineStagedCheckpoint env datum =
    CheckpointInput
        { checkpointUtxo = offlineStagedUtxo env datum
        , checkpointDatum = datum
        }

-- | The staged Checkpoint UTxO, resolved through the offline Provider.

{- | The offline staged checkpoint output, reproducing EVERY ledger-relevant
part of what production 'stageCheckpointInput' settles: the checkpoint ACTIVE
script credential, the same lovelace, and the same inline @V1@ datum encoding.

Script requirement follows the address and datum witnessing follows the datum
representation, so a fixture missing either mis-attributes real ledger failures
to the code under test (standard 9).
-}
offlineStagedUtxo ::
    CheckpointEnv -> CheckpointDatumV1 -> (TxIn, TxOut ConwayEra)
offlineStagedUtxo env datum =
    ( stagedIn
    , mkBasicTxOut (offlineActiveRoleAddress env) (inject (Coin stagedLovelace))
        & datumTxOutL .~ mkInlineDatum (asPlcData (V1 datum))
    )
  where
    stagedIn =
        case offlineWalletOf [(0xcc, stagedLovelace)] of
            ((txIn, _) : _) -> txIn
            [] -> error "offlineStagedUtxo: empty wallet"

-- | @checkpoint_min_ada + D_reg + B@, matching production staging.
stagedLovelace :: Integer
stagedLovelace = 1_007_000_000

-- | The production checkpoint ACTIVE role address for the applied validator.
offlineActiveRoleAddress :: CheckpointEnv -> Addr
offlineActiveRoleAddress env =
    Addr
        Testnet
        (ScriptHashObj (hashScript (checkpointScriptOf env)))
        StakeRefNull

{- | The frozen resolved hash-proof UTxO the real Register builder spends.
Only the INPUT is synthesized; the Register candidate is produced by the real
'buildRegisterTx'.
-}
offlineProofUtxo ::
    CheckpointEnv -> RegistrationFixture -> (TxIn, TxOut ConwayEra)
offlineProofUtxo env fixture =
    ( offlineProofTxIn
    , mkBasicTxOut
        (checkpointOwnerOf env)
        ( MaryValue
            (Coin 5_000_000)
            ( MultiAsset
                ( Map.singleton
                    (checkpointHashProofPolicyOf env)
                    (Map.singleton proofName 1)
                )
            )
        )
    )
  where
    proofName = AssetName (SBS.toShort (rfProofName fixture))

-- | The transaction input the hash-proof UTxO occupies.
offlineProofTxIn :: TxIn
offlineProofTxIn =
    case offlineWalletOf [(0xdd, 5_000_000)] of
        ((txIn, _) : _) -> txIn
        [] -> error "offlineProofTxIn: empty wallet"

-- | The complete serialized Conway transaction bytes, witnesses included.
serializedTxBytes :: ConwayTx -> BSL.ByteString
serializedTxBytes = serialize (eraProtVerLow @ConwayEra)

{- | A non-empty all-successful evaluation map keyed by the candidate's own
declared redeemer purposes. Harness observation only: it reports what the
candidate declares and prescribes no production evaluation API.
-}
evaluatedPurposesFor :: ConwayTx -> EvaluateTxResult ConwayEra
evaluatedPurposesFor tx = Map.map (const (Right offlineObservedUnits)) redeemerMap
  where
    Redeemers redeemerMap = tx ^. witsTxL . rdmrsTxWitsL

{- | Harness-supplied OBSERVED per-purpose usage for the offline evaluator seam.

Plutus cannot run offline, so the seam reports a fixed plausible observed usage
rather than a real measurement. It is deliberately well under the declared
discovery ceilings so the two-pass rebinding has something to shrink to; it is
NOT a measurement and no report may quote it as one.
-}
offlineObservedUnits :: ExUnits
offlineObservedUnits = ExUnits 4_000_000 2_500_000_000

{- | Every normal and collateral input a candidate spends. Used to prove the
offline Provider resolves the complete set.
-}
spentInputsOf :: ConwayTx -> Set.Set TxIn
spentInputsOf tx =
    Set.unions
        [ tx ^. bodyTxL . inputsTxBodyL
        , tx ^. bodyTxL . collateralInputsTxBodyL
        , tx ^. bodyTxL . referenceInputsTxBodyL
        ]

{- | Assert the offline Provider resolves every normal and collateral input
the captured candidate spends.
-}
assertAllInputsResolve :: CheckpointSeam -> ConwayTx -> Expectation
assertAllInputsResolve seam tx = do
    let spent = spentInputsOf tx
        expected =
            Map.restrictKeys (Map.fromList (seamExpectedResolved seam)) spent
    resolved <- queryUTxOByTxIn (checkpointProviderOf (seamEnvOf seam)) spent
    resolved `shouldBe` expected
    Map.keysSet resolved `shouldBe` spent

{- | A Register seam whose offline Provider resolves the EXACT token-bearing
hash-proof pair handed to 'buildRegisterTx'.

Built in two steps because the proof output's policy id is derived from the
applied blueprint: a bootstrap environment yields the policy, then the real
seam is constructed with that exact pair in the resolver state.
-}
newRegisterSeam :: IO (CheckpointSeam, ConwayTx)
newRegisterSeam = do
    let wallet = [(0xaa, 2_000_000_000), (0xbb, 2_000_000_000)]
    bootstrap <- newCheckpointSeam wallet
    (fixture, _) <- loadLifecycleFixture
    let proofPair = offlineProofUtxo (seamEnvOf bootstrap) fixture
        references = offlineRegisterReferences (seamEnvOf bootstrap)
    seam <- newCheckpointSeamWith wallet (proofPair : references)
    candidate <- buildRegisterTx (seamEnvOf seam) fixture proofPair
    pure (seam, candidate)

{- | The candidate's intended structural verdict must not contain
@BadInputsUTxO@ once every spent input resolves.
-}
assertNoBadInputs :: CheckpointSeam -> Pv11GuardParams -> ConwayTx -> Expectation
assertNoBadInputs seam guardParams tx =
    withCheckpointPhase1Snapshot (seamEnvOf seam) $ \globals provider -> do
        snapshot <- queryLedgerSnapshot provider
        let verdict =
                runPhase1
                    Phase1Input
                        { p1Globals = globals
                        , p1Slot = ledgerTipSlot snapshot
                        , p1Params = guardParams
                        , p1ResolvedInputs = seamExpectedResolved seam
                        }
                    NoRewardState
                    tx
        renderPhase1 verdict `shouldNotSatisfy` isInfixOf "BadInputsUTxO"

{- | The three deployed reference-script outputs Register consumes by reference
input: checkpoint, observer_lifecycle, and hash-proof. Each output genuinely
carries its applied validator, so a wrong reference set surfaces as a real
structural failure rather than being worked around.
-}
offlineRegisterReferences :: CheckpointEnv -> [(TxIn, TxOut ConwayEra)]
offlineRegisterReferences env =
    [ referenceOutput 0xe1 (checkpointScriptOf env)
    , referenceOutput 0xe2 (checkpointLifecycleScriptOf env)
    , referenceOutput 0xe3 (checkpointHashProofScriptOf env)
    ]

{- | The offline stand-in for the deployed enforcement observer reference
output Arm now consumes (A-070 70.1A).

It genuinely carries the applied enforcement observer script, so a wrong
reference set surfaces as a real ledger failure rather than being worked
around, and the offline fixtures resolve it exactly as the live capture
resolves its deployed reference.
-}
offlineEnforcementReference :: CheckpointEnv -> (TxIn, TxOut ConwayEra)
offlineEnforcementReference env =
    referenceOutput 0xe4 (checkpointEnforcementScriptOf env)

referenceOutput :: Int -> Script ConwayEra -> (TxIn, TxOut ConwayEra)
referenceOutput seedByte script =
    case offlineWalletOf [(seedByte, 100_000_000)] of
        ((txIn, out) : _) ->
            (txIn, out & referenceScriptTxOutL .~ SJust script)
        [] -> error "referenceOutput: empty wallet"

{- | A seam whose offline Provider resolves the production-shaped staged
checkpoint output.

Built in two steps because the ACTIVE role address derives from the applied
checkpoint validator: a bootstrap environment yields that script, then the real
seam is constructed with the exact resolved staged pair.
-}
newStagedSeam :: [(Int, Integer)] -> IO CheckpointSeam
newStagedSeam walletEntries = do
    bootstrap <- newCheckpointSeam walletEntries
    (fixture, _) <- loadLifecycleFixture
    let env = seamEnvOf bootstrap
        staged = offlineStagedUtxo env (rfDatum fixture)
    -- A-070 70.1A: the enforcement reference Arm consumes must RESOLVE
    -- offline, so a wrong reference set is a real ledger failure.
    newCheckpointSeamWith
        walletEntries
        [staged, offlineEnforcementReference env]

{- | The specific ledger failure constructor names carried by a verdict's
complete structural partition, so an assertion can compare the WHOLE set
rather than substring-matching one member.
-}
checkpointStructuralNames :: Phase1Verdict -> [String]
checkpointStructuralNames = map nameOf . phase1Structural
  where
    nameOf failure =
        case filter (`isInfixOf` show failure) checkpointKnownFailures of
            (name : _) -> name
            [] -> takeWhile (\c -> c /= ' ' && c /= '(') (show failure)

-- | Ledger failure constructors these Checkpoint assertions discriminate.
checkpointKnownFailures :: [String]
checkpointKnownFailures =
    [ "MaxTxSizeUTxO"
    , "InsufficientCollateral"
    , "ScriptIntegrityHashMismatch"
    , "ExtraneousScriptWitnessesUTXOW"
    , "ExtraRedeemers"
    , "OutputTooSmallUTxO"
    , "ValueNotConservedUTxO"
    , "BadInputsUTxO"
    ]

-- | The slot a uniquely-occurring named boundary event observed.
requireEventSlot ::
    [ArmBoundaryEvent] ->
    String ->
    (ArmBoundaryEvent -> Bool) ->
    IO SlotNo
requireEventSlot events name isWanted =
    case [slot | event <- events, isWanted event, Just slot <- [eventSlot event]] of
        [slot] -> pure slot
        other ->
            fail
                ( "expected exactly one "
                    <> name
                    <> " boundary event, observed "
                    <> show (length other)
                    <> " in "
                    <> show events
                )

-- | Position of the first matching named event, for ordering relations.
eventIndex :: [ArmBoundaryEvent] -> (ArmBoundaryEvent -> Bool) -> Int
eventIndex events isWanted =
    case [index | (index, event) <- zip [0 ..] events, isWanted event] of
        (index : _) -> index
        [] -> maxBound

externalEvaluationBytes :: [ArmBoundaryEvent] -> [BSL.ByteString]
externalEvaluationBytes events =
    [bytes | ExternalEvaluation _ bytes <- events]

externalSubmissionBytes :: [ArmBoundaryEvent] -> [BSL.ByteString]
externalSubmissionBytes events = [bytes | ExternalSubmission bytes <- events]

isBuildAnchor :: ArmBoundaryEvent -> Bool
isBuildAnchor = \case BuildAnchor{} -> True; _ -> False

isFinalPreparationGuard :: ArmBoundaryEvent -> Bool
isFinalPreparationGuard = \case FinalPreparationGuard{} -> True; _ -> False

isExternalPreEvaluationGuard :: ArmBoundaryEvent -> Bool
isExternalPreEvaluationGuard = \case
    ExternalPreEvaluationGuard{} -> True
    _ -> False

isExternalEvaluation :: ArmBoundaryEvent -> Bool
isExternalEvaluation = \case ExternalEvaluation{} -> True; _ -> False

isExternalPreSubmitGuard :: ArmBoundaryEvent -> Bool
isExternalPreSubmitGuard = \case ExternalPreSubmitGuard{} -> True; _ -> False

-- ---------------------------------------------------------------------------
-- A-071 complete per-row observable evidence (NOTE-058 / NOTE-064)
-- ---------------------------------------------------------------------------

{- | The COMPLETE frozen proof for one A-071 collateral-boundary negative row.

NOTE-058 requires the whole observable set, not a partial number list: both
resolved collateral outputs, proof that the named collateral axis is the only
mutation and the fee is unchanged, the three exact input sets, FULL resolver
map equality over their union including every value, an exact-byte digest of
the guarded transaction, the complete structural partition, the downstream
zero facts, and the row label with its outcome.

A-072 (72A) fixes what "the downstream zero facts" means here: there are
exactly TWO separately fireable hard zero observations — evaluator calls and
submitter calls — plus ONE derived settlement fact. This rejection route owns
no settlement surface, so zero settlement is derived from those two hard
observations rather than captured by a counter that could never fire.
-}
data A071RowEvidence = A071RowEvidence
    { reRowLabel :: !String
    , reOutcome :: !String
    , reFee :: !Integer
    , rePercent :: !Integer
    , reRequired :: !Integer
    , reSupplied :: !Integer
    , reBaselineCollateral :: !(TxIn, TxOut ConwayEra)
    , reNegativeCollateral :: !(TxIn, TxOut ConwayEra)
    , reFeeUnchanged :: !Bool
    , reOnlyCollateralAxisMutated :: !Bool
    , reNormalInputs :: !(Set.Set TxIn)
    , reCollateralInputs :: !(Set.Set TxIn)
    , reReferenceInputs :: !(Set.Set TxIn)
    , reResolvedExpected :: !(Map.Map TxIn (TxOut ConwayEra))
    , reResolvedActual :: !(Map.Map TxIn (TxOut ConwayEra))
    , reResolverFullMapEqual :: !Bool
    {- ^ FULL map equality including every 'TxOut' value, never a keys-only
    or domain-only predicate.
    -}
    , reTotalCollateral :: !(StrictMaybe Coin)
    , reCollateralReturn :: !(StrictMaybe (TxOut ConwayEra))
    , reTxId :: !TxId
    , reByteLength :: !Int
    , reByteDigest :: !String
    , rePartition :: ![String]
    , reEvaluatorCalls :: !Int
    , reSubmitterCalls :: !Int
    , reSettlementNote :: !String
    {- ^ A-072 72A: this rejection route owns no settlement surface, so zero
    settlement is DERIVED from the two hard observables rather than
    separately fired. An unreachable counter would be a fiction.
    -}
    }

{- | Collect the complete A-071 row evidence inside the acquisition that owns
the candidate, then assert the TWO hard zero captures (evaluator and
submitter calls), the ONE derived settlement fact, and FULL resolver map
equality including every value (A-072 72A).
-}
collectA071RowEvidence ::
    CheckpointSeam ->
    Provider IO ->
    CollateralNegative ->
    String ->
    String ->
    [String] ->
    IO A071RowEvidence
collectA071RowEvidence seam provider negative label outcome partition = do
    let candidate = cnCandidate negative
        body = candidate ^. bodyTxL
        normalIns = body ^. inputsTxBodyL
        collateralIns = body ^. collateralInputsTxBodyL
        referenceIns = body ^. referenceInputsTxBodyL
        spentUnion = Set.unions [normalIns, collateralIns, referenceIns]
        bytes = serializedTxBytes candidate
    actualResolved <- queryUTxOByTxIn provider spentUnion
    let expectedResolved =
            Map.restrictKeys (Map.fromList (cnResolved negative)) spentUnion
    evaluatorCalls <- length <$> readIORef (seamEvaluated seam)
    submitterCalls <- length <$> readIORef (seamSubmitted seam)
    pure
        A071RowEvidence
            { reRowLabel = label
            , reOutcome = outcome
            , reFee = cnFee negative
            , rePercent = cnPercent negative
            , reRequired = cnRequired negative
            , reSupplied = cnSuppliedLovelace negative
            , reBaselineCollateral = cnBaselineResolved negative
            , reNegativeCollateral = cnNegativeResolved negative
            , reFeeUnchanged = cnFeeUnchanged negative
            , reOnlyCollateralAxisMutated = cnOnlyCollateralAxis negative
            , reNormalInputs = normalIns
            , reCollateralInputs = collateralIns
            , reReferenceInputs = referenceIns
            , reResolvedExpected = expectedResolved
            , reResolvedActual = actualResolved
            , reResolverFullMapEqual = actualResolved == expectedResolved
            , reTotalCollateral = body ^. totalCollateralTxBodyL
            , reCollateralReturn = body ^. collateralReturnTxBodyL
            , reTxId = txIdTx candidate
            , reByteLength = fromIntegral (BSL.length bytes)
            , reByteDigest =
                hashToStringAsHex
                    (hashWith id (BSL.toStrict bytes) :: Hash SHA256 BS.ByteString)
            , rePartition = partition
            , reEvaluatorCalls = evaluatorCalls
            , reSubmitterCalls = submitterCalls
            , reSettlementNote = derivedSettlementRecord
            }

-- | Freeze and assert one complete A-071 row record.
assertA071RowEvidence :: A071RowEvidence -> Expectation
assertA071RowEvidence evidence = do
    putStrLn (renderA071RowEvidence evidence)
    -- The named collateral axis is the ONLY mutation and the fee is unchanged.
    reFeeUnchanged evidence `shouldBe` True
    reOnlyCollateralAxisMutated evidence `shouldBe` True
    -- Boundary arithmetic by the ledger's own rule.
    reSupplied evidence `shouldBe` reRequired evidence - 1
    reRequired evidence
        `shouldBe` (reFee evidence * rePercent evidence + 99) `div` 100
    fst (reNegativeCollateral evidence)
        `shouldNotBe` fst (reBaselineCollateral evidence)
    -- FULL resolver map equality, values included.
    reResolvedActual evidence `shouldBe` reResolvedExpected evidence
    reResolverFullMapEqual evidence `shouldBe` True
    -- Exact collateral bookkeeping on the final negative body.
    reTotalCollateral evidence
        `shouldBe` SJust (Coin (reRequired evidence - 1))
    reCollateralReturn evidence `shouldBe` SNothing
    -- Two separately fireable hard zero observations, then the one derived
    -- settlement fact (A-072 72A): this route owns no settlement surface.
    reEvaluatorCalls evidence `shouldBe` 0
    reSubmitterCalls evidence `shouldBe` 0
    reSettlementNote evidence `shouldBe` derivedSettlementRecord

-- | The frozen transcript form of one complete A-071 row record.
renderA071RowEvidence :: A071RowEvidence -> String
renderA071RowEvidence evidence =
    unlines
        [ "A071-ROW-EVIDENCE " <> reRowLabel evidence
        , "  outcome: " <> reOutcome evidence
        , "  production-final-fee-f: " <> show (reFee evidence)
        , "  collateral-percentage-p: " <> show (rePercent evidence)
        , "  formula: r = ceil(f * p / 100)"
        , "  required-r: " <> show (reRequired evidence)
        , "  mutated-collateral-lovelace-r-minus-1: "
            <> show (reSupplied evidence)
        , "  fee-unchanged-vs-baseline: " <> show (reFeeUnchanged evidence)
        , "  only-collateral-axis-mutated: "
            <> show (reOnlyCollateralAxisMutated evidence)
        , "  baseline-collateral-resolved: "
            <> show (reBaselineCollateral evidence)
        , "  negative-collateral-resolved: "
            <> show (reNegativeCollateral evidence)
        , "  normal-input-set: " <> show (Set.toList (reNormalInputs evidence))
        , "  collateral-input-set: "
            <> show (Set.toList (reCollateralInputs evidence))
        , "  reference-input-set: "
            <> show (Set.toList (reReferenceInputs evidence))
        , "  resolver-expected: "
            <> show (Map.toList (reResolvedExpected evidence))
        , "  resolver-actual: "
            <> show (Map.toList (reResolvedActual evidence))
        , "  resolver-full-map-equal-values-included: "
            <> show (reResolverFullMapEqual evidence)
        , "  total-collateral: " <> show (reTotalCollateral evidence)
        , "  collateral-return: " <> show (reCollateralReturn evidence)
        , "  guarded-tx-id: " <> show (reTxId evidence)
        , "  guarded-tx-byte-length: " <> show (reByteLength evidence)
        , "  guarded-tx-sha256: " <> reByteDigest evidence
        , "  complete-structural-partition: " <> show (rePartition evidence)
        , "  evaluator-calls: " <> show (reEvaluatorCalls evidence)
        , "  submitter-calls: " <> show (reSubmitterCalls evidence)
        , "  " <> reSettlementNote evidence
        ]

{- | Whether the mutated candidate differs from the production baseline ONLY
in the named composite collateral axis: collateral inputs, total collateral,
and collateral return. Every other body field and the whole witness set must
be byte-identical.
-}
onlyCollateralAxisDiffers :: ConwayTx -> ConwayTx -> Bool
onlyCollateralAxisDiffers baseline mutated =
    normalisedBaseline == normalisedMutated
        && (baseline ^. witsTxL) == (mutated ^. witsTxL)
  where
    normalise tx =
        tx
            & bodyTxL . collateralInputsTxBodyL .~ Set.empty
            & bodyTxL . totalCollateralTxBodyL .~ SNothing
            & bodyTxL . collateralReturnTxBodyL .~ SNothing
    normalisedBaseline = serializedTxBytes (normalise baseline)
    normalisedMutated = serializedTxBytes (normalise mutated)

{- | The A-072 72A honest settlement record for the two offline A-071 rows.

The guard rejects before @submitTx@ is reached, and on this seam a
@Submitted@ result is itself a failure, so there is no settlement boundary
this route owns. Zero settlement is therefore DERIVED from the two hard
observables — zero evaluator calls and zero submitter calls — rather than
fired by a counter that could never be incremented. Live
Register -> Arm -> Claim settlement remains the real orchestration proof.
-}
derivedSettlementRecord :: String
derivedSettlementRecord =
    "settlement-not-independently-observable-offline: guard rejects before \
    \submitTx; this route owns no settlement/poll boundary; zero settlement \
    \is derived from zero evaluator and zero submitter calls"
