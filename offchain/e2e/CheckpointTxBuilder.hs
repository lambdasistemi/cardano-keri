{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : CheckpointTxBuilder
Description : Production-shaped #114 checkpoint transactions for withDevnet

Loads the tracked-source Aiken blueprint, applies the production checkpoint
validator's six deployment parameters in order, and builds real Conway
transactions for Register, Arm, Advance, Claim, Thaw, and Close.

The pinned devnet's 251-entry Plutus V3 model cannot price the Plomin builtins
used by the real hash-proof policy.  This boundary therefore executes and
asserts that exact mint failure, while retaining only compile-checked pending
coverage for the positive Register -> Arm -> Claim chain.  Advance and Close
remain real production-script staging rejections.
-}
module CheckpointTxBuilder (
    CheckpointEnv,
    CheckpointInput (..),
    RejectionEvidence,
    BoundaryCases,
    stagedCheckpointDevnet,
    advanceRejection,
    closeRejection,
    hashProofMintOldCostRejection,
    observerAdvanceStakeRegistrationSetup,
    observerEnforcementStakeRegistrationSetup,
    observerLifecycleStakeRegistrationSetup,
    pendingHashProofRegisterArmClaimScenario,
    pv11CompatibilityAndNonObserverCaptureScenario,
    rejectionIsOldCostPlominBoundary,
    rejectionReachedProductionScript,
    responseBoundaryCases,
    boundaryCasesCoverDeadline,
    productionRegisterScenario,
    registerTransactionShapeRegression,
    assertStockMaxTxSize,
    mkCheckpointEnvWith,
    RegistrationFixture (..),
    ValidityPlan (..),
    currentValidity,
    currentValidityIn,
    dummyAdvanceEvidence,
    checkpointScriptOf,
    checkpointOwnerOf,
    checkpointProviderOf,
    checkpointEnforcementHashOf,
    checkpointEnforcementScriptOf,
    withCheckpointPhase1Snapshot,
    bodyRewardState,
    checkpointAppliedBytesOf,
    freezeWindow,
    roleAddress,
    scriptExUnits,
    checkpointHashProofPolicyOf,
    checkpointLifecycleScriptOf,
    checkpointHashProofScriptOf,
    loadLifecycleFixture,
    deployReferenceScriptForCapture,
    stageCheckpointInput,
    buildHashProofMintTx,
    buildRegisterTx,
    buildRegisterTxWith,
    submitTwoPassRegister,
    buildTwoPassFinalRegister,
    buildTwoPassFinalRegisterIn,
    deterministicMargin,
    submitUnchangedCapture,
    evaluateAndSubmitPositiveCapture,
    registerEvaluationPurposes,
    submitSettling,
    expectProductionScriptRejection,
    expectOldCostHashProofRejection,
    verifyFiveProgramDeploymentShapes,
    buildArmTx,
    buildArmTxIn,
    buildCurrentArmTx,
    buildAdvanceTx,
    buildClaimTx,
    buildClaimAfterWait,
    buildThawTx,
    buildCurrentAdvanceTx,
    buildCurrentCloseTx,
) where

import CageTxBuilder (
    Phase1Input (..),
    Phase1RewardState (..),
    Pv11GuardParams,
    loadPv11GuardParams,
    phase1Accepted,
    pv11MaxTxExUnits,
    renderPhase1,
    runPhase1,
 )
import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    ArmedDatum (..),
    Inclusivity (..),
    RawBound (..),
    Role (..),
    claimAtOrAfterDeadline,
    responseBeforeDeadline,
    roleHash,
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceEvidenceData,
    asPlcData,
    enforcementEvidenceData,
    registerObserverRedeemerData,
    registrationEvidenceData,
 )
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppCostModelsL, ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..), costModelsValid, getCostModelParams)
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (
    Redeemers (..),
    TxDats (..),
 )
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (mkBasicTx, txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    certsTxBodyL,
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
    mkBasicTxOut,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    Globals (..),
    Inject (..),
    Network (Testnet),
    ProtVer (..),
    StrictMaybe (SJust),
    TxIx (..),
 )
import Cardano.Ledger.Binary (serialize)
import Cardano.Ledger.Coin (Coin (..), unCoin)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Conway.TxCert (ConwayDelegCert (..), ConwayTxCert (..))
import Cardano.Ledger.Core (
    Script,
    bodyTxL,
    eraProtVerLow,
    ppKeyDepositL,
    ppMaxTxSizeL,
    ppProtocolVersionL,
 )
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..), extractHash)
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.E2E.Setup (
    DevnetConfig (devnetTargetPV),
    TargetPV (PV11),
    addKeyWitness,
    assertPV11Enacted,
    defaultDevnetConfig,
    genesisAddr,
    genesisSignKey,
    withDevnetConfig,
 )
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.N2C.Provider (
    mkN2CProvider,
    withAcquiredN2CProviderAndGlobals,
 )
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
    SlotNo (..),
 )
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (..))
import Cardano.Node.Client.Validity (ValidityChoice (AutoLongest))
import Cardano.Slotting.EpochInfo.API (EpochInfo (..))
import Cardano.Slotting.Time (RelativeTime (..), getSystemStart)
import Cardano.Tx.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
 )
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, displayException, throwIO, try)
import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecodeFileStrict, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.List (elemIndex, find, isInfixOf, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Ord (Down (..))
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Data.Word (Word32, Word8)
import Lens.Micro ((&), (.~), (^.))
import Paths_cardano_keri (getDataFileName)
import PlutusCore qualified as PLC
import PlutusCore.Data (Data (..))
import PlutusCore.Data qualified as PLC
import PlutusLedgerApi.V3 (serialiseUPLC, uncheckedDeserialiseUPLC)
import System.Environment (lookupEnv)
import System.IO (
    BufferMode (LineBuffering),
    hPutStrLn,
    hSetBuffering,
    stderr,
    stdout,
 )
import System.Timeout (timeout)
import UntypedPlutusCore (Program (..), applyProgram)
import UntypedPlutusCore qualified as UPLC

import Cardano.KERI.AID.E2E.Datum (extractDatum, mkInlineDatum)
import Cardano.KERI.AID.E2E.Script (
    computeScriptHash,
    extractCompiledCode,
    loadBlueprint,
    mkCageScript,
 )

data CheckpointEnv = CheckpointEnv
    { envCheckpointScript :: !(Script ConwayEra)
    , envCheckpointBytes :: !SBS.ShortByteString
    , envCheckpointHash :: !ScriptHash
    , envCheckpointPolicy :: !PolicyID
    , envLifecycleScript :: !(Script ConwayEra)
    , envLifecycleBytes :: !SBS.ShortByteString
    , envLifecycleHash :: !ScriptHash
    , envAdvanceScript :: !(Script ConwayEra)
    , envAdvanceBytes :: !SBS.ShortByteString
    , envAdvanceHash :: !ScriptHash
    , envEnforcementScript :: !(Script ConwayEra)
    , envEnforcementBytes :: !SBS.ShortByteString
    , envEnforcementHash :: !ScriptHash
    , envHashProofScript :: !(Script ConwayEra)
    , envHashProofBytes :: !SBS.ShortByteString
    , envHashProofHash :: !ScriptHash
    , envHashProofPolicy :: !PolicyID
    , envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envOwner :: !Addr
    , envGuard :: !Pv11GuardParams
    , envWithPhase1Snapshot ::
        forall a. (Globals -> Provider IO -> IO a) -> IO a
    {- ^ The ONE acquisition/ownership boundary (A-065), mirroring
    'CageTxBuilder.CageEnv'. Resolve, balance, build, evaluate, the
    successor-deadline coordinate and the ledger-native Phase-1 guard all
    run inside this callback against the SAME provider and the SAME
    'Globals'; submission and settlement polling run after it.
    -}
    }

data CheckpointInput = CheckpointInput
    { checkpointUtxo :: !(TxIn, TxOut ConwayEra)
    , checkpointDatum :: !CheckpointDatumV1
    }

data RejectionEvidence = RejectionEvidence
    { rejectionLabel :: !String
    , rejectionTxId :: !TxId
    , rejectionDiagnostic :: !String
    , rejectionIsPhase2 :: !Bool
    , rejectionCostModelEntries :: !Int
    }
    deriving stock (Show)

data ValidityPlan = ValidityPlan
    { lowerSlot :: !SlotNo
    , upperSlot :: !SlotNo
    , lowerPosixMs :: !Integer
    , upperPosixMs :: !Integer
    }
    deriving stock (Show, Eq)

data BoundaryCases = BoundaryCases
    { armUpper :: !ValidityPlan
    , hardDeadlineMs :: !Integer
    , justBeforeResponse :: !ValidityPlan
    , exactDeadlineClaim :: !ValidityPlan
    , afterDeadlineClaim :: !ValidityPlan
    }
    deriving stock (Show, Eq)

checkpointVersion :: Integer
checkpointVersion = 0

checkpointMinAda :: Integer
checkpointMinAda = 2_000_000

registrationBond :: Integer
registrationBond = 1_000_000_000

freezeBond :: Integer
freezeBond = 5_000_000

freezeWindow :: Integer
freezeWindow = 10_000

scriptFee :: Integer
scriptFee = 3_000_000

scriptExUnits :: ExUnits
scriptExUnits = ExUnits 12_000_000 7_000_000_000

hashProofExUnits :: ExUnits
hashProofExUnits = ExUnits 14_000_000 10_000_000_000

hashProofBurnExUnits :: ExUnits
hashProofBurnExUnits = ExUnits 500_000 500_000_000

evaluationTimeoutSeconds :: Int
evaluationTimeoutSeconds = 120

pollAttempts :: Int
pollAttempts = 40

stagedCheckpointDevnet :: (CheckpointEnv -> IO ()) -> IO ()
stagedCheckpointDevnet action = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    blueprintPath <-
        lookupEnv "KERI_CHECKPOINT_BLUEPRINT"
            >>= maybe
                ( lookupEnv "KERI_CAGE_BLUEPRINT"
                    >>= maybe
                        (fail "KERI_CHECKPOINT_BLUEPRINT not set")
                        pure
                )
                pure
    withinSecs 300 "checkpoint withDevnet"
        $ withDevnetConfig
            defaultDevnetConfig{devnetTargetPV = PV11}
        $ \lsq ltxs -> do
            let provider = mkN2CProvider lsq
            dbg "checkpoint devnet target=PV11"
            -- Fail at the live boundary before loading/applying a blueprint:
            -- plain withDevnet defaults to PV10 in this pinned dependency.
            assertPV11Enacted provider
            assertLivePV11Boundary provider
            -- R2 stock-cap boundary FIRST: query the live node for production
            -- maxTxSize = 16384 before any blueprint application. Any non-
            -- stock override fails here with the observed value; this must
            -- not be masked by a stale fixed-output blueprint lookup.
            assertLiveStockMaxTxSize provider
            env <- mkCheckpointEnv blueprintPath lsq ltxs
            -- A-053 53A five-program deployment boundary: three observer hashes
            -- pairwise distinct, and one signed reference-script creation
            -- shape each for checkpoint and all three observers within the
            -- stock cap.
            verifyFiveProgramDeploymentShapes env
            prepareWallet env
            -- All three observers' script stake credentials must be registered
            -- before any evidence-bearing lifecycle transaction: the
            -- checkpoint ran-check requires the zero-lovelace withdrawal, and
            -- the ledger requires the reward account to be registered.
            -- observer_advance is the fourth program's registration surface
            -- (witness, ConwayCertifying, collateral, prepareWallet split,
            -- pollOutput settlement — same choreography as the other two).
            lifecycleRegistrationTxId <- observerLifecycleStakeRegistrationSetup env
            dbg ("observer_lifecycle stake credential registered: " <> show lifecycleRegistrationTxId)
            advanceRegistrationTxId <- observerAdvanceStakeRegistrationSetup env
            dbg ("observer_advance stake credential registered: " <> show advanceRegistrationTxId)
            enforcementRegistrationTxId <- observerEnforcementStakeRegistrationSetup env
            dbg ("observer_enforcement stake credential registered: " <> show enforcementRegistrationTxId)
            action env

mkCheckpointEnv :: FilePath -> LSQChannel -> LTxSChannel -> IO CheckpointEnv
mkCheckpointEnv blueprintPath lsq ltxs =
    mkCheckpointEnvWith
        blueprintPath
        (mkN2CProvider lsq)
        (mkN2CSubmitter ltxs)
        (withAcquiredN2CProviderAndGlobals lsq)

{- | Build the checkpoint environment against caller-supplied node seams.

Pure refactor of mkCheckpointEnv: identical script loading and parameter
application, with the provider and submitter injected so an offline review can
exercise the submission seams without a node. No guard, submission, or
validation behaviour is added here.
-}
mkCheckpointEnvWith ::
    FilePath ->
    Provider IO ->
    Submitter IO ->
    (forall a. (Globals -> Provider IO -> IO a) -> IO a) ->
    IO CheckpointEnv
mkCheckpointEnvWith blueprintPath provider submitter withSnapshot = do
    guardParams <- loadPv11GuardParams
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    hashProofCode <-
        maybe
            (fail "hash_proof compiled code not found in production blueprint")
            pure
            (extractCompiledCode "hash_proof." blueprint)
    checkpointCode <-
        maybe
            (fail "checkpoint compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint." blueprint)
    lifecycleCode <-
        maybe
            (fail "observer_lifecycle compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint_observer.observer_lifecycle." blueprint)
    advanceCode <-
        maybe
            (fail "observer_advance compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint_observer.observer_advance." blueprint)
    enforcementCode <-
        maybe
            (fail "observer_enforcement compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint_observer.observer_enforcement." blueprint)
    let hashProofScript = mkCageScript hashProofCode
        hashProofHash = computeScriptHash hashProofCode
        hashProofPolicy = PolicyID hashProofHash
        -- A-016 program application: lifecycle (version, hash-proof, D_reg),
        -- advance (version), enforcement (version); then checkpoint
        -- (version, lifecycle hash, advance hash, enforcement hash, D_reg,
        -- freeze bond, freeze window). One checkpoint h remains identity.
        appliedLifecycle =
            applyLifecycleParams
                checkpointVersion
                (policyBytes hashProofPolicy)
                registrationBond
                lifecycleCode
        lifecycleScript = mkCageScript appliedLifecycle
        lifecycleHash = computeScriptHash appliedLifecycle
        appliedAdvance =
            applyAdvanceParams
                checkpointVersion
                advanceCode
        advanceScript = mkCageScript appliedAdvance
        advanceHash = computeScriptHash appliedAdvance
        appliedEnforcement =
            applyEnforcementParams
                checkpointVersion
                enforcementCode
        enforcementScript = mkCageScript appliedEnforcement
        enforcementHash = computeScriptHash appliedEnforcement
        appliedCheckpoint =
            applyCheckpointParams
                checkpointVersion
                (policyBytes (PolicyID lifecycleHash))
                (policyBytes (PolicyID advanceHash))
                (policyBytes (PolicyID enforcementHash))
                registrationBond
                freezeBond
                freezeWindow
                checkpointCode
        checkpointScript = mkCageScript appliedCheckpoint
        checkpointHash = computeScriptHash appliedCheckpoint
        checkpointPolicy = PolicyID checkpointHash
    dbg ("checkpoint script hash: " <> show checkpointHash)
    dbg ("observer_lifecycle script hash: " <> show lifecycleHash)
    dbg ("observer_advance script hash: " <> show advanceHash)
    dbg ("observer_enforcement script hash: " <> show enforcementHash)
    dbg ("hash-proof script hash: " <> show hashProofHash)
    pure
        CheckpointEnv
            { envCheckpointScript = checkpointScript
            , envCheckpointBytes = appliedCheckpoint
            , envCheckpointHash = checkpointHash
            , envCheckpointPolicy = checkpointPolicy
            , envLifecycleScript = lifecycleScript
            , envLifecycleBytes = appliedLifecycle
            , envLifecycleHash = lifecycleHash
            , envAdvanceScript = advanceScript
            , envAdvanceBytes = appliedAdvance
            , envAdvanceHash = advanceHash
            , envEnforcementScript = enforcementScript
            , envEnforcementBytes = appliedEnforcement
            , envEnforcementHash = enforcementHash
            , envHashProofScript = hashProofScript
            , envHashProofBytes = hashProofCode
            , envHashProofHash = hashProofHash
            , envHashProofPolicy = hashProofPolicy
            , envProvider = provider
            , envSubmitter = submitter
            , envOwner = genesisAddr
            , envGuard = guardParams
            , envWithPhase1Snapshot = withSnapshot
            }

productionMaxTxBytes :: Int
productionMaxTxBytes = 16_384

productionPV11MaxTxExUnits :: ExUnits
productionPV11MaxTxExUnits = ExUnits 16_500_000 10_000_000_000

{- | Audit the complete observed PV11 execution boundary after the pinned
'assertPV11Enacted' has enforced protocol major 11 and the 350-entry V3
model. The transaction ex-unit maximum is checked separately because the
pinned assertion does not include it.
-}
assertLivePV11Boundary :: Provider IO -> IO ()
assertLivePV11Boundary provider = do
    params <-
        withinSecs 30 "query live PV11 protocol boundary" $
            queryProtocolParams provider
    let ProtVer major minor = params ^. ppProtocolVersionL
        v3Entries =
            maybe 0 (length . getCostModelParams) $
                Map.lookup PlutusV3 (costModelsValid (params ^. ppCostModelsL))
        observedExUnits = params ^. ppMaxTxExUnitsL
    dbg $
        "live PV11 boundary protocol="
            <> show major
            <> "."
            <> show minor
            <> " plutusV3-cost-model-entries="
            <> show v3Entries
            <> " maxTxExUnits="
            <> show observedExUnits
    unless (observedExUnits == productionPV11MaxTxExUnits) $
        fail $
            "checkpoint devnet maxTxExUnits is "
                <> show observedExUnits
                <> ", expected PV11 "
                <> show productionPV11MaxTxExUnits

{- | Prove the running checkpoint devnet exposes stock production
'maxTxSize = 16384' via a live protocol-parameter query.  This is the R2
stock-cap boundary: any non-stock override must fail here with the observed
value, not via a unit shim.
-}
assertStockMaxTxSize :: CheckpointEnv -> IO ()
assertStockMaxTxSize env = assertLiveStockMaxTxSize (envProvider env)

-- | Live-node stock-cap check against a provider (usable before blueprint load).
assertLiveStockMaxTxSize :: Provider IO -> IO ()
assertLiveStockMaxTxSize provider = do
    params <-
        withinSecs 30 "query live stock maxTxSize" $
            queryProtocolParams provider
    let observed = fromIntegral (params ^. ppMaxTxSizeL) :: Int
    dbg ("live protocol maxTxSize=" <> show observed)
    unless (observed == productionMaxTxBytes) $
        fail $
            "checkpoint devnet maxTxSize is "
                <> show observed
                <> ", expected stock "
                <> show productionMaxTxBytes

{- | Register the applied observer's script stake credential on the devnet.

The withdraw-0 coupling only validates if the observer's script stake
credential is registered on-chain: the checkpoint ran-check requires the
zero-lovelace withdrawal, and the ledger requires the reward account to be
registered. This builds, signs, and submits a genuine Conway stake-registration
certificate for the observer's script credential (paying the protocol key
deposit) and returns the confirmed transaction id. It MUST run before any
evidence-bearing lifecycle transaction; it is genuine setup behavior, not a
marker or getter.
-}

-- | Shared genuine Conway script-stake-credential registration for one observer.
registerObserverStakeCredential ::
    ScriptHash -> Script ConwayEra -> String -> CheckpointEnv -> IO TxId
registerObserverStakeCredential observerHash observerScript label env = do
    params <-
        withinSecs 30 "query observer-registration protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query observer-registration wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (seed, collateral) <- pickDisjoint wallet []
    let keyDeposit = params ^. ppKeyDepositL
        regCert =
            ConwayTxCertDeleg
                (ConwayRegCert (ScriptHashObj observerHash) (SJust keyDeposit))
        -- ConwayCertifying AsIx 0: the sole certificate in certsTxBodyL.
        -- Minimal unit redeemer (I 0) matches the publish handler's unused
        -- Data argument; scriptExUnits is the in-file script ceiling.
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwayCertifying (AsIx 0))
                    (ledgerData (I 0), scriptExUnits)
        body =
            mkBasicTxBody
                & certsTxBodyL .~ StrictSeq.singleton regCert
                & collateralInputsTxBodyL .~ Set.singleton (fst collateral)
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
        skeleton =
            mkBasicTx body
                & witsTxL . scriptTxWitsL
                    .~ Map.singleton observerHash observerScript
                & witsTxL . rdmrsTxWitsL .~ redeemers
    balanced <-
        either
            (fail . (\e -> label <> ": balance failed: " <> show e))
            (pure . balancedTx)
            ( balanceTxWith
                params
                [seed]
                (CollateralUtxos [collateral])
                []
                (envOwner env)
                Nothing
                skeleton
            )
    registrationTxId <- submitSettling env label balanced
    _ <-
        pollOutput
            (envProvider env)
            registrationTxId
            [0, 1]
            (const True)
            >>= requireJust (label <> " output did not settle")
    pure registrationTxId

{- | Register the applied observer_lifecycle script stake credential on the
devnet. Genuine setup behavior: the checkpoint ran-check requires the
zero-lovelace lifecycle withdrawal, and the ledger requires the reward account
to be registered. Must run before the first Register use.
-}
observerLifecycleStakeRegistrationSetup :: CheckpointEnv -> IO TxId
observerLifecycleStakeRegistrationSetup env =
    registerObserverStakeCredential
        (envLifecycleHash env)
        (envLifecycleScript env)
        "observer_lifecycle stake-credential registration"
        env

{- | Register the applied observer_advance script stake credential on the
devnet. Fourth-program registration surface (A-016): same witness,
ConwayCertifying (AsIx 0) redeemer, collateral, prepareWallet funding, and
pollOutput settlement barrier as the other observers. Must run before the
first Advance use.
-}
observerAdvanceStakeRegistrationSetup :: CheckpointEnv -> IO TxId
observerAdvanceStakeRegistrationSetup env =
    registerObserverStakeCredential
        (envAdvanceHash env)
        (envAdvanceScript env)
        "observer_advance stake-credential registration"
        env

{- | Register the applied observer_enforcement script stake credential on the
devnet. Genuine setup behavior: the checkpoint ran-check requires the
zero-lovelace enforcement withdrawal, and the ledger requires the reward
account to be registered. Must run before the first Freeze/Convict use.
-}
observerEnforcementStakeRegistrationSetup :: CheckpointEnv -> IO TxId
observerEnforcementStakeRegistrationSetup env =
    registerObserverStakeCredential
        (envEnforcementHash env)
        (envEnforcementScript env)
        "observer_enforcement stake-credential registration"
        env

{- | Staged-devnet boundary (A-016, extended by A-053 53A): assert the three
observer hashes are pairwise distinct, then construct and sign one
reference-script creation shape for the checkpoint, each observer, AND the
hash-proof program, failing if any signed shape exceeds the stock 16,384-byte
transaction cap.

FIVE programs are measured, not four: A-052 requires Register to deliver
checkpoint, observer_lifecycle, and hash-proof by reference input, and
hash-proof had no deployment in the original four. Real boundary measurement,
not a getter.
-}
verifyFiveProgramDeploymentShapes :: CheckpointEnv -> IO ()
verifyFiveProgramDeploymentShapes env = do
    when (envLifecycleHash env == envEnforcementHash env) $
        fail "observer_lifecycle and observer_enforcement hashes are not distinct"
    when (envLifecycleHash env == envAdvanceHash env) $
        fail "observer_lifecycle and observer_advance hashes are not distinct"
    when (envAdvanceHash env == envEnforcementHash env) $
        fail "observer_advance and observer_enforcement hashes are not distinct"
    params <-
        withinSecs 30 "query five-program deployment parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query five-program deployment wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    seed <- requireJust "five-program deployment: no wallet UTxO" (largestFirst wallet)
    let measureShape label script programBytes = do
            let referenceOut =
                    mkBasicTxOut (envOwner env) (inject (Coin 100_000_000))
                        & referenceScriptTxOutL .~ SJust script
                skeleton =
                    mkBasicTx
                        (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton referenceOut)
            balanced <-
                either
                    (fail . (\e -> label <> ": balance failed: " <> show e))
                    (pure . balancedTx)
                    (balanceTx params [seed] [] (envOwner env) skeleton)
            let signed = addKeyWitness genesisSignKey balanced
                creationTxBytes = fromIntegral (BSL.length (serialize (eraProtVerLow @ConwayEra) signed))
            dbg (label <> ": program=" <> show programBytes <> " signed-creation-tx=" <> show creationTxBytes)
            when (creationTxBytes > productionMaxTxBytes) $
                fail (label <> ": signed reference-script creation shape " <> show creationTxBytes <> " exceeds stock " <> show productionMaxTxBytes)
    measureShape "checkpoint reference-script" (envCheckpointScript env) (SBS.length (envCheckpointBytes env))
    measureShape "observer_lifecycle reference-script" (envLifecycleScript env) (SBS.length (envLifecycleBytes env))
    measureShape "observer_advance reference-script" (envAdvanceScript env) (SBS.length (envAdvanceBytes env))
    measureShape "observer_enforcement reference-script" (envEnforcementScript env) (SBS.length (envEnforcementBytes env))
    measureShape "hash-proof reference-script" (envHashProofScript env) (SBS.length (envHashProofBytes env))

applyCheckpointParams ::
    Integer ->
    ByteString ->
    ByteString ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCheckpointParams version lifecycleHash advanceHash enforcementHash dReg bond window code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
            `applyDataArg` B lifecycleHash
            `applyDataArg` B advanceHash
            `applyDataArg` B enforcementHash
            `applyDataArg` I dReg
            `applyDataArg` I bond
            `applyDataArg` I window
  where
    applyDataArg program dat =
        let Program _ versionTag _ = program
            argument =
                Program
                    ()
                    versionTag
                    (UPLC.Constant () (PLC.Some (PLC.ValueOf PLC.DefaultUniData dat)))
         in either
                (error . ("applyCheckpointParams: " <>) . show)
                id
                (applyProgram program argument)

applyLifecycleParams ::
    Integer ->
    ByteString ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyLifecycleParams version proofPolicy dReg code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
            `applyDataArg` B proofPolicy
            `applyDataArg` I dReg
  where
    applyDataArg program dat =
        let Program _ versionTag _ = program
            argument =
                Program
                    ()
                    versionTag
                    (UPLC.Constant () (PLC.Some (PLC.ValueOf PLC.DefaultUniData dat)))
         in either
                (error . ("applyLifecycleParams: " <>) . show)
                id
                (applyProgram program argument)

applyAdvanceParams ::
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyAdvanceParams version code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
  where
    applyDataArg program dat =
        let Program _ versionTag _ = program
            argument =
                Program
                    ()
                    versionTag
                    (UPLC.Constant () (PLC.Some (PLC.ValueOf PLC.DefaultUniData dat)))
         in either
                (error . ("applyAdvanceParams: " <>) . show)
                id
                (applyProgram program argument)

applyEnforcementParams ::
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyEnforcementParams version code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
  where
    applyDataArg program dat =
        let Program _ versionTag _ = program
            argument =
                Program
                    ()
                    versionTag
                    (UPLC.Constant () (PLC.Some (PLC.ValueOf PLC.DefaultUniData dat)))
         in either
                (error . ("applyEnforcementParams: " <>) . show)
                id
                (applyProgram program argument)

policyBytes :: PolicyID -> ByteString
policyBytes (PolicyID (ScriptHash hash)) = hashToBytes hash

-- | The checkpoint address a lifecycle 'Role' output is locked at.
roleAddress :: CheckpointEnv -> Role -> Addr
roleAddress env Active =
    Addr Testnet (ScriptHashObj (envCheckpointHash env)) StakeRefNull
roleAddress env role =
    Addr
        Testnet
        (ScriptHashObj (envCheckpointHash env))
        (StakeRefBase (ScriptHashObj marker))
  where
    markerBytes =
        fromMaybe (error "roleAddress: ACTIVE has no role marker") $
            roleHash (policyBytes (envCheckpointPolicy env)) role
    marker =
        ScriptHash $
            fromMaybe
                (error "roleAddress: role hash is not 28 bytes")
                (hashFromBytes markerBytes)

productionRegisterScenario :: CheckpointEnv -> IO CheckpointInput
productionRegisterScenario env = do
    (fixture, _) <- loadLifecycleFixture
    productionRegisterScenarioWith env fixture

productionRegisterScenarioWith :: CheckpointEnv -> RegistrationFixture -> IO CheckpointInput
productionRegisterScenarioWith env fixture = do
    proofTx <- withinSecs 90 "build hash-proof mint" (buildHashProofMintTx env fixture)
    proofTxId <- submitSettling env "hash-proof mint" proofTx
    proofUtxo <-
        pollOutput
            (envProvider env)
            proofTxId
            [0, 1]
            (hasAsset (envHashProofPolicy env) (rfProofName fixture))
            >>= requireJust "hash-proof output did not settle"
    registerTx <-
        withinSecs 90 "build checkpoint Register" $
            buildRegisterTx env fixture proofUtxo
    registerTxId <- submitSettling env "checkpoint Register" registerTx
    let checkpointName = deriveAidAssetName (cdCesrAid (rfDatum fixture))
    registered <-
        pollOutput
            (envProvider env)
            registerTxId
            [0, 1]
            (hasAsset (envCheckpointPolicy env) checkpointName)
            >>= requireJust "registered checkpoint output did not settle"
    assertActiveCheckpoint env fixture registered
    pure CheckpointInput{checkpointUtxo = registered, checkpointDatum = rfDatum fixture}

{- | This is deliberately not run on the old-cost devnet.  Referencing this
scenario from the authorized PENDING row type-checks the real hash-proof mint,
permissionless Register with @D_reg+B@, Arm, and Claim builders without
claiming settlement before cardano-node-clients#190 supplies Plomin pricing.
-}
pendingHashProofRegisterArmClaimScenario :: CheckpointEnv -> IO ()
pendingHashProofRegisterArmClaimScenario env = do
    (fixture, armEvidence) <- loadLifecycleFixture
    -- A-070 70.1A: Arm delivers the enforcement observer by reference input,
    -- so this scenario deploys that reference before Arming.
    enforcementRef <-
        deployReferenceScriptForCapture
            env
            "enforcement reference-script creation"
            (envEnforcementScript env)
    registered <- productionRegisterScenarioWith env fixture
    let hunter = BS.replicate 28 0x42
    (armValidity, armTx) <-
        withinSecs 90 "build checkpoint Arm" $
            buildCurrentArmTx env enforcementRef registered armEvidence hunter
    let deadline = upperPosixMs armValidity + freezeWindow
    armTxId <- submitUnchangedCapture env "checkpoint Arm" armTx
    armed <-
        pollOutput
            (envProvider env)
            armTxId
            [0, 1]
            (hasAsset (envCheckpointPolicy env) (deriveAidAssetName (cdCesrAid (rfDatum fixture))))
            >>= requireJust "ARMED checkpoint output did not settle"
    assertArmedCheckpoint env registered hunter deadline armValidity armed
    boundaries <- responseBoundaryCasesForArm env armValidity
    unless
        (boundaryCasesCoverDeadline boundaries)
        (fail "node-derived deadline plans do not cover before/exact/after boundary")
    claimTx <-
        withinSecs 90 "build checkpoint Claim" $
            buildClaimAfterWait
                env
                CheckpointInput{checkpointUtxo = armed, checkpointDatum = rfDatum fixture}
                hunter
                deadline
    claimTxId <- submitSettling env "checkpoint Claim" claimTx
    assertClaimSettlement env fixture hunter armed claimTxId

{- | PV11 compatibility capture for the FIVE reference-script deployments and
the positive hash-proof mint -> Register -> Arm -> Claim lineage.

A-053 53A: five reference creations (checkpoint, observer_lifecycle,
observer_advance, observer_enforcement, hash-proof) and THIRTEEN submitted
one-boot candidates — one wallet split, three observer registrations, five
reference-script creations, and the four-transaction positive chain. Register
references checkpoint, observer_lifecycle, and hash-proof; observer_advance
and observer_enforcement remain deployed and unconsumed by Register.

Every transaction is signed before evaluation, then that exact binding is
submitted unchanged. Reference-script creation has no script purpose and must
therefore evaluate to an empty map; every positive-chain transaction must
produce a non-empty map containing only successful per-purpose measurements.
-}
pv11CompatibilityAndNonObserverCaptureScenario :: CheckpointEnv -> IO ()
pv11CompatibilityAndNonObserverCaptureScenario env = do
    checkpointRef <-
        deployReferenceScriptForCapture
            env
            "checkpoint reference-script creation"
            (envCheckpointScript env)
    lifecycleRef <-
        deployReferenceScriptForCapture
            env
            "lifecycle reference-script creation"
            (envLifecycleScript env)
    _advanceRef <-
        deployReferenceScriptForCapture
            env
            "advance reference-script creation"
            (envAdvanceScript env)
    -- A-070 70.1A: this deployed reference is now CARRIED, not discarded.
    -- Arm delivers the enforcement observer through exactly this output.
    enforcementRef <-
        deployReferenceScriptForCapture
            env
            "enforcement reference-script creation"
            (envEnforcementScript env)
    hashProofRef <-
        deployReferenceScriptForCapture
            env
            "hash-proof reference-script creation"
            (envHashProofScript env)
    let registerReferences = [checkpointRef, lifecycleRef, hashProofRef]

    (fixture, armEvidence) <- loadLifecycleFixture
    proofTx <-
        addKeyWitness genesisSignKey
            <$> withinSecs 90 "build PV11 hash-proof mint" (buildHashProofMintTx env fixture)
    proofTxId <-
        evaluateAndSubmitPositiveCapture
            env
            "PV11 hash-proof mint"
            [("hash-proof mint", hashProofExUnits)]
            proofTx
    proofUtxo <-
        pollOutput
            (envProvider env)
            proofTxId
            [0, 1]
            (hasAsset (envHashProofPolicy env) (rfProofName fixture))
            >>= requireJust "PV11 hash-proof output did not settle"
    dbg ("PV11 hash-proof settlement proof=" <> show (fst proofUtxo))

    -- A-046 3A: the Register candidate goes through the two-pass final binding.
    registerTxId <-
        submitTwoPassRegister
            env
            "PV11 checkpoint Register"
            registerReferences
            fixture
            proofUtxo
    let checkpointName = deriveAidAssetName (cdCesrAid (rfDatum fixture))
    registered <-
        pollOutput
            (envProvider env)
            registerTxId
            [0, 1]
            (hasAsset (envCheckpointPolicy env) checkpointName)
            >>= requireJust "PV11 registered checkpoint output did not settle"
    assertActiveCheckpoint env fixture registered
    dbg ("PV11 Register settlement proof=" <> show (fst registered))
    let registeredInput =
            CheckpointInput
                { checkpointUtxo = registered
                , checkpointDatum = rfDatum fixture
                }

    let hunter = BS.replicate 28 0x42
    (armValidity, armSignedFinal) <-
        withinSecs
            90
            "build PV11 checkpoint Arm"
            (buildCurrentArmTx env enforcementRef registeredInput armEvidence hunter)
    -- B5: the builder already returned the exact SIGNED final object; it is
    -- evaluated and submitted unchanged, never re-signed into new bytes.
    let armTx = armSignedFinal
        deadline = upperPosixMs armValidity + freezeWindow
    armTxId <-
        evaluateAndSubmitPositiveCapture
            env
            "PV11 checkpoint Arm"
            [("checkpoint Arm spend", scriptExUnits)]
            armTx
    armed <-
        pollOutput
            (envProvider env)
            armTxId
            [0, 1]
            (hasAsset (envCheckpointPolicy env) checkpointName)
            >>= requireJust "PV11 ARMED checkpoint output did not settle"
    assertArmedCheckpoint env registeredInput hunter deadline armValidity armed
    dbg ("PV11 Arm settlement proof=" <> show (fst armed))

    boundaries <- responseBoundaryCasesForArm env armValidity
    unless
        (boundaryCasesCoverDeadline boundaries)
        (fail "PV11 node-derived deadline plans do not cover before/exact/after boundary")
    claimTx <-
        addKeyWitness genesisSignKey
            <$> withinSecs
                90
                "build PV11 checkpoint Claim"
                ( buildClaimAfterWait
                    env
                    CheckpointInput
                        { checkpointUtxo = armed
                        , checkpointDatum = rfDatum fixture
                        }
                    hunter
                    deadline
                )
    claimTxId <-
        evaluateAndSubmitPositiveCapture
            env
            "PV11 checkpoint Claim"
            [("checkpoint Claim spend", scriptExUnits)]
            claimTx
    assertClaimSettlement env fixture hunter armed claimTxId
    dbg ("PV11 Claim settlement proof=txid " <> show claimTxId)

    -- A-046 informational observer rows. These run ONLY here, after the
    -- binding Claim has settled and its txid is anchored above: a
    -- positive-chain failure aborts before this point and therefore
    -- suppresses both rows. Seven-valid is the BINDING measurement and runs
    -- first; partial 3-of-7 is SUPPORTING and runs second. Neither is
    -- submitted, and neither can abort the run.
    runInformationalObserverRow
        env
        "GLEIF-root seven-valid-signature worst-case Advance with witness cut/add"
        "adv_wit_7key_full"
    runInformationalObserverRow
        env
        "GLEIF-root partial 3-of-7 reveal with witness cut/add"
        "adv_wit_7key"

deployReferenceScriptForCapture ::
    CheckpointEnv ->
    String ->
    Script ConwayEra ->
    IO (TxIn, TxOut ConwayEra)
deployReferenceScriptForCapture env label script = do
    -- A-070 70.2A point 3: the COMPLETE preparation pipeline — resolve,
    -- balance, build, final guard, evaluation — runs inside ONE acquisition
    -- against that acquisition's own provider and 'Globals'. Only the
    -- immutable prepared object leaves; submission and settlement polling are
    -- separate downstream actions with their own guards.
    (tx, serializedBytes) <-
        envWithPhase1Snapshot env $ \globals provider -> do
            params <-
                withinSecs 30 (label <> ": query protocol parameters") $
                    queryProtocolParams provider
            wallet <-
                withinSecs 30 (label <> ": query wallet") $
                    queryUTxOs provider (envOwner env)
            seed <-
                requireJust (label <> ": no wallet UTxO") (largestFirst wallet)
            let referenceOut =
                    mkBasicTxOut (envOwner env) (inject (Coin 100_000_000))
                        & referenceScriptTxOutL .~ SJust script
                skeleton =
                    mkBasicTx
                        ( mkBasicTxBody
                            & outputsTxBodyL .~ StrictSeq.singleton referenceOut
                        )
            balanced <-
                either
                    ( fail
                        . (\failure -> label <> ": balance failed: " <> show failure)
                    )
                    (pure . balancedTx)
                    (balanceTx params [seed] [] (envOwner env) skeleton)
            let prepared = addKeyWitness genesisSignKey balanced
                bytes = BSL.length (serialize (eraProtVerLow @ConwayEra) prepared)
            -- REVIEW-023 finding 5: an ORDINARY final candidate is guarded
            -- BEFORE any evaluation, signing, or submission. Register's
            -- discovery/final sequence is the only approved exception.
            guardBeforeSubmitIn
                globals
                provider
                env
                ("reference-script creation " <> label)
                prepared
            observed <-
                withinSecs evaluationTimeoutSeconds (label <> ": evaluateTx") $
                    evaluateTx provider prepared
            dbg (label <> ": evaluated map=" <> show observed)
            unless (Map.null observed) $
                fail
                    ( label
                        <> ": expected an empty evaluateTx map, observed "
                        <> show observed
                    )
            pure (prepared, bytes)
    txId <- submitUnchangedCapture env label tx
    settled <-
        pollOutput
            (envProvider env)
            txId
            [0]
            ((== SJust script) . (^. referenceScriptTxOutL))
            >>= requireJust (label <> ": reference-script output did not settle")
    dbg
        ( label
            <> ": txid="
            <> show txId
            <> " serialized-bytes="
            <> show serializedBytes
            <> " settlement-proof="
            <> show (fst settled)
        )
    pure settled

evaluateAndSubmitPositiveCapture ::
    CheckpointEnv ->
    String ->
    [(String, ExUnits)] ->
    ConwayTx ->
    IO TxId
evaluateAndSubmitPositiveCapture env label declaredCeilings =
    evaluateAndSubmitPositiveCaptureWithPurposes
        env
        label
        declaredCeilings
        Set.empty

evaluateAndSubmitPositiveCaptureWithPurposes ::
    CheckpointEnv ->
    String ->
    [(String, ExUnits)] ->
    Set.Set (ConwayPlutusPurpose AsIx ConwayEra) ->
    ConwayTx ->
    IO TxId
evaluateAndSubmitPositiveCaptureWithPurposes env label declaredCeilings expectedPurposes tx = do
    -- A-070 70.2A point 3: the external pre-evaluation guard and the external
    -- evaluation are ONE action under ONE acquisition. Submission below is a
    -- separate downstream action with its own pre-submit guard.
    observed <- envWithPhase1Snapshot env $ \globals provider -> do
        -- REVIEW-023 finding 5: ordinary positive candidates are guarded
        -- before evaluation/signing/submission.
        guardBeforeSubmitIn globals provider env ("positive capture " <> label) tx
        withinSecs evaluationTimeoutSeconds (label <> ": evaluateTx") $
            evaluateTx provider tx
    dbg (label <> ": evaluated purpose-to-ExUnits map=" <> show observed)
    when (Map.null observed) $
        fail (label <> ": expected a non-empty evaluateTx map")
    case sequenceA observed of
        Left failure ->
            fail (label <> ": evaluateTx reported script failure: " <> show failure)
        Right _ -> pure ()
    -- REVIEW-023 finding 3: EXACT purpose-set equality, not a subset check.
    -- Missing, extra, duplicate, or unattributed purposes must fail.
    unless
        (Set.null expectedPurposes || expectedPurposes == Map.keysSet observed)
        ( fail $
            label
                <> ": evaluateTx purpose set is not exactly the expected set: expected "
                <> show expectedPurposes
                <> ", observed "
                <> show (Map.keysSet observed)
        )
    mapM_
        ( \(ceilingLabel, declaredCeiling) ->
            dbg
                ( label
                    <> ": declared ceiling "
                    <> ceilingLabel
                    <> "="
                    <> show declaredCeiling
                )
        )
        declaredCeilings
    submitUnchangedCapture env label tx

registerEvaluationPurposes ::
    CheckpointEnv ->
    Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
registerEvaluationPurposes env =
    Set.fromList
        [ ConwayMinting (AsIx (mintIndex (envCheckpointPolicy env)))
        , ConwayMinting (AsIx (mintIndex (envHashProofPolicy env)))
        , ConwayRewarding (AsIx 0)
        ]
  where
    policies = sort [envCheckpointPolicy env, envHashProofPolicy env]
    mintIndex policy =
        fromIntegral $
            fromMaybe
                (error "registerEvaluationPurposes: policy missing from mint order")
                (elemIndex policy policies)

submitUnchangedCapture :: CheckpointEnv -> String -> ConwayTx -> IO TxId
submitUnchangedCapture env label tx = do
    guardBeforeSubmit env ("submitUnchangedCapture " <> label) tx
    result <-
        withinSecs 60 ("submit unchanged " <> label) $
            submitTx (envSubmitter env) tx
    case result of
        Submitted txId -> do
            dbg (label <> ": submitted unchanged txid=" <> show txId)
            pure txId
        Rejected reason -> fail (label <> " rejected: " <> B8.unpack reason)

advanceRejection :: CheckpointEnv -> IO RejectionEvidence
advanceRejection env = do
    (fixture, _) <- loadLifecycleFixture
    staged <- stageCheckpointInput env (rfDatum fixture)
    tx <-
        buildCurrentAdvanceTx
            env
            staged
            (checkpointDatum staged)
            dummyAdvanceEvidence
            False
    expectProductionScriptRejection env "Advance" tx

closeRejection :: CheckpointEnv -> IO RejectionEvidence
closeRejection env = do
    (fixture, _) <- loadLifecycleFixture
    staged <- stageCheckpointInput env (rfDatum fixture)
    tx <- buildCurrentCloseTx env staged
    expectProductionScriptRejection env "Close" tx

hashProofMintOldCostRejection :: CheckpointEnv -> IO RejectionEvidence
hashProofMintOldCostRejection env = do
    (fixture, _) <- loadLifecycleFixture
    costModelEntries <- pinnedPlutusV3CostModelEntries env
    unless
        (costModelEntries == oldCostModelEntries)
        ( fail
            ( "hash-proof old-cost boundary requires the pinned "
                <> show oldCostModelEntries
                <> "-entry Plutus V3 model, observed "
                <> show costModelEntries
            )
        )
    tx <- withinSecs 90 "build old-cost hash-proof mint" (buildHashProofMintTx env fixture)
    expectOldCostHashProofRejection env costModelEntries tx

rejectionIsOldCostPlominBoundary :: RejectionEvidence -> Bool
rejectionIsOldCostPlominBoundary RejectionEvidence{rejectionDiagnostic, rejectionCostModelEntries} =
    rejectionCostModelEntries == oldCostModelEntries
        && all (`isInfixOf` rejectionDiagnostic) oldCostFailureMarkers

oldCostModelEntries :: Int
oldCostModelEntries = 251

{- | Plomin extends the V3 cost model beyond the 251 entries baked into the
old devnet genesis.  The exact CEK overspend below is the node-visible failure
of trying to evaluate the BLAKE3 policy against that incomplete model.
-}
oldCostFailureMarkers :: [String]
oldCostFailureMarkers =
    [ "CekError"
    , "overspending the budget"
    , "protocol version is: Version 10"
    , "MintingScript"
    ]

pinnedPlutusV3CostModelEntries :: CheckpointEnv -> IO Int
pinnedPlutusV3CostModelEntries env = do
    params <- withinSecs 30 "query pinned Plutus V3 cost model" (queryProtocolParams (envProvider env))
    pure $
        maybe 0 (length . getCostModelParams) $
            Map.lookup PlutusV3 (costModelsValid (params ^. ppCostModelsL))

rejectionReachedProductionScript :: RejectionEvidence -> Bool
rejectionReachedProductionScript = rejectionIsPhase2

expectProductionScriptRejection ::
    CheckpointEnv -> String -> ConwayTx -> IO RejectionEvidence
expectProductionScriptRejection env label tx = do
    guardBeforeSubmit env ("expectProductionScriptRejection " <> label) tx
    let txId = txIdTx tx
    result <-
        withinSecs 60 ("submit " <> label) $
            submitTx (envSubmitter env) (addKeyWitness genesisSignKey tx)
    case result of
        Submitted submitted ->
            fail $
                label
                    <> " staging transaction unexpectedly submitted as "
                    <> show submitted
        Rejected raw -> do
            let diagnostic = B8.unpack raw
                phase1 = any (`isInfixOf` diagnostic) phase1Markers
                phase2 = any (`isInfixOf` diagnostic) phase2Markers
            dbg
                ( label
                    <> " rejected; tx id="
                    <> show txId
                    <> "; diagnostic="
                    <> oneLine diagnostic
                )
            if phase1
                then fail (label <> " failed at Phase-1: " <> diagnostic)
                else
                    if not phase2
                        then fail (label <> " rejection was not recognisably Phase-2: " <> diagnostic)
                        else
                            pure
                                RejectionEvidence
                                    { rejectionLabel = label
                                    , rejectionTxId = txId
                                    , rejectionDiagnostic = diagnostic
                                    , rejectionIsPhase2 = True
                                    , rejectionCostModelEntries = 0
                                    }

expectOldCostHashProofRejection ::
    CheckpointEnv -> Int -> ConwayTx -> IO RejectionEvidence
expectOldCostHashProofRejection env costModelEntries tx = do
    guardBeforeSubmit env "expectOldCostHashProofRejection" tx
    let txId = txIdTx tx
    result <-
        withinSecs 60 "submit old-cost hash-proof mint" $
            submitTx (envSubmitter env) (addKeyWitness genesisSignKey tx)
    case result of
        Submitted submitted ->
            fail $
                "old-cost hash-proof mint unexpectedly submitted as "
                    <> show submitted
        Rejected raw -> do
            let diagnostic = B8.unpack raw
                evidence =
                    RejectionEvidence
                        { rejectionLabel = "hash-proof mint"
                        , rejectionTxId = txId
                        , rejectionDiagnostic = diagnostic
                        , rejectionIsPhase2 = False
                        , rejectionCostModelEntries = costModelEntries
                        }
            dbg $
                "hash-proof mint rejected at old-cost boundary; tx id="
                    <> show txId
                    <> "; model entries="
                    <> show costModelEntries
                    <> "; diagnostic="
                    <> oneLine diagnostic
            unless
                (rejectionIsOldCostPlominBoundary evidence)
                (fail ("hash-proof mint was not the exact old-cost Plomin boundary: " <> diagnostic))
            pure evidence

phase1Markers :: [String]
phase1Markers =
    [ "BadInputsUTxO"
    , "FeeTooSmallUTxO"
    , "InsufficientCollateral"
    , "OutsideValidityIntervalUTxO"
    , "PPViewHashesDontMatch"
    , "MissingRedeemers"
    , "ValueNotConservedUTxO"
    , "OutputTooSmallUTxO"
    , "ExUnitsTooBigUTxO"
    , "MaxTxSizeUTxO"
    ]

phase2Markers :: [String]
phase2Markers =
    [ "FailedUnexpectedly"
    , "PlutusFailure"
    , "ValidationTagMismatch"
    , "ScriptWitnessNotValidatingUTXOW"
    ]

prepareWallet :: CheckpointEnv -> IO ()
prepareWallet env = do
    _ <- awaitWalletCount (envProvider env) (envOwner env) 1
    splitTx <- withinSecs 60 "build checkpoint wallet split" (buildSplitTx env)
    _ <- submitSettling env "checkpoint wallet split" splitTx
    _ <- awaitWalletCount (envProvider env) (envOwner env) 5
    pure ()

buildSplitTx :: CheckpointEnv -> IO ConwayTx
buildSplitTx env = do
    params <- withinSecs 30 "query protocol parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query wallet for split" (queryUTxOs (envProvider env) (envOwner env))
    input <- requireJust "buildSplitTx: no wallet UTxO" (listToMaybe wallet)
    let small = mkBasicTxOut (envOwner env) (inject (Coin 20_000_000))
        body =
            mkBasicTxBody
                & outputsTxBodyL .~ StrictSeq.fromList [small, small, small, small]
    either
        (fail . ("buildSplitTx: balance failed: " <>) . show)
        (pure . balancedTx)
        (balanceTx params [input] [] (envOwner env) (mkBasicTx body))

data RegistrationFixture = RegistrationFixture
    { rfDatum :: !CheckpointDatumV1
    , rfEvidence :: !RegistrationEvidence
    , rfRaw :: !ByteString
    , rfAid :: !ByteString
    , rfOffI :: !Integer
    , rfOffD :: !Integer
    , rfProofName :: !ByteString
    }

data RegisterScriptPlan = RegisterScriptPlan
    { rspCheckpointRedeemer :: !PLC.Data
    , rspWithdrawals :: !Withdrawals
    , rspLifecycleRedeemer :: !(Maybe PLC.Data)
    , rspRedeemers :: !(Redeemers ConwayEra)
    , rspWitnessHashes :: !(Set.Set ScriptHash)
    , rspIntegrityLanguages :: !(Set.Set Language)
    , rspIntegrityDatums :: !(TxDats ConwayEra)
    }

registerScriptPlan ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    ScriptHash ->
    ScriptHash ->
    ScriptHash ->
    PolicyID ->
    RegistrationEvidence ->
    Word32 ->
    Word32 ->
    RegisterScriptPlan
registerScriptPlan budgets checkpointHash lifecycleHash hashProofHash checkpointPolicy evidence checkpointIx hashProofIx =
    RegisterScriptPlan
        { rspCheckpointRedeemer = checkpointRedeemer
        , rspWithdrawals =
            Withdrawals $
                Map.singleton
                    (AccountAddress Testnet (AccountId (ScriptHashObj lifecycleHash)))
                    (Coin 0)
        , rspLifecycleRedeemer = Just lifecycleRedeemer
        , rspRedeemers = redeemers
        , rspWitnessHashes = Set.fromList [checkpointHash, lifecycleHash, hashProofHash]
        , rspIntegrityLanguages = Set.singleton PlutusV3
        , rspIntegrityDatums = TxDats mempty
        }
  where
    checkpointRedeemer = registerRedeemerData evidence
    lifecycleRedeemer =
        registerObserverRedeemerData (policyBytes checkpointPolicy) evidence
    budgetFor purpose fallback = Map.findWithDefault fallback purpose budgets
    redeemers =
        Redeemers $
            Map.fromList
                [
                    ( ConwayMinting (AsIx checkpointIx)
                    ,
                        ( ledgerData checkpointRedeemer
                        , budgetFor (ConwayMinting (AsIx checkpointIx)) scriptExUnits
                        )
                    )
                ,
                    ( ConwayMinting (AsIx hashProofIx)
                    ,
                        ( ledgerData hashProofBurnRedeemerData
                        , budgetFor (ConwayMinting (AsIx hashProofIx)) hashProofBurnExUnits
                        )
                    )
                ,
                    ( ConwayRewarding (AsIx 0)
                    ,
                        ( ledgerData lifecycleRedeemer
                        , budgetFor (ConwayRewarding (AsIx 0)) scriptExUnits
                        )
                    )
                ]

{- | Local-only contract for the Register transaction shape. Assertions are
ordered so the legacy evidence-bearing mint redeemer is RED-1 and, after that
single correction, the absent lifecycle withdrawal is RED-2.
-}
registerTransactionShapeRegression :: IO ()
registerTransactionShapeRegression = do
    (fixture, _) <- loadLifecycleFixture
    let checkpointHash = regressionScriptHash 0x11
        lifecycleHash = regressionScriptHash 0x22
        hashProofHash = regressionScriptHash 0x33
        checkpointPolicy = PolicyID checkpointHash
        checkpointIx = 0
        hashProofIx = 1
        plan =
            registerScriptPlan
                Map.empty
                checkpointHash
                lifecycleHash
                hashProofHash
                checkpointPolicy
                (rfEvidence fixture)
                checkpointIx
                hashProofIx
        expectedWithdrawals =
            Withdrawals $
                Map.singleton
                    (AccountAddress Testnet (AccountId (ScriptHashObj lifecycleHash)))
                    (Coin 0)
        expectedPurposes =
            Set.fromList
                [ ConwayMinting (AsIx checkpointIx)
                , ConwayMinting (AsIx hashProofIx)
                , ConwayRewarding (AsIx 0)
                ]
    unless
        (rspCheckpointRedeemer plan == Constr 0 [])
        (fail "Register shape assertion 1: checkpoint Minting redeemer is not bare Constr 0 []")
    putStrLn "Register shape assertion 1: PASS"
    unless
        (rspWithdrawals plan == expectedWithdrawals)
        (fail "Register shape assertion 2: lifecycle zero-lovelace withdrawal is absent")
    putStrLn "Register shape assertion 2: PASS"
    unless
        ( ( rspLifecycleRedeemer plan
                >>= decodeRegisterObserverEnvelope
          )
            == Just
                ( 0
                , policyBytes checkpointPolicy
                , registrationEvidenceData (rfEvidence fixture)
                )
        )
        (fail "Register shape assertion 3: lifecycle ObserverEnvelope claim or RegistrationEvidence payload is wrong")
    putStrLn "Register shape assertion 3: PASS"
    let Redeemers redeemerMap = rspRedeemers plan
        TxDats datums = rspIntegrityDatums plan
        expectedObserverRedeemer =
            ledgerData $
                registerObserverRedeemerData
                    (policyBytes checkpointPolicy)
                    (rfEvidence fixture)
    unless
        ( Set.member lifecycleHash (rspWitnessHashes plan)
            && Map.keysSet redeemerMap == expectedPurposes
            && Map.lookup
                (ConwayRewarding (AsIx 0))
                redeemerMap
                == Just (expectedObserverRedeemer, scriptExUnits)
            && rspIntegrityLanguages plan == Set.singleton PlutusV3
            && Map.null datums
        )
        (fail "Register shape assertion 4: lifecycle witness or complete computeScriptIntegrity inputs are wrong")
    putStrLn "Register shape assertion 4: PASS"

regressionScriptHash :: Word8 -> ScriptHash
regressionScriptHash byte =
    ScriptHash $
        fromMaybe
            (error "regressionScriptHash: expected 28-byte script hash")
            (hashFromBytes (BS.replicate 28 byte))

decodeRegisterObserverEnvelope ::
    PLC.Data -> Maybe (Integer, ByteString, PLC.Data)
decodeRegisterObserverEnvelope = \case
    Constr
        0
        [ Constr 0 [I action, B checkpointPolicy, Constr 1 []]
            , payload
            ] ->
            Just (action, checkpointPolicy, payload)
    _ -> Nothing

{- | Use one committed KEL lineage for both the permissionless inception and
the later signed rotation that Arms it.  That keeps the live test on the real
Register output instead of manufacturing a checkpoint-shaped input.
-}
loadLifecycleFixture :: IO (RegistrationFixture, EnforcementEvidence)
loadLifecycleFixture = do
    path <- getDataFileName "test/keri-fixtures/fixtures/honest_2key.json"
    value <- eitherDecodeFileStrict path >>= either fail pure
    inception <- either fail pure (atKey "icp" value)
    inceptionSignatures <- either fail pure (indexedSignaturesAt "icp_sigs" value)
    rotation <- either fail pure (atKey "rot" value)
    rotationSignatures <- either fail pure (indexedSignaturesAt "rot_sigs" value)
    inceptionWithOffsets <- either fail pure (withDerivedOffsets inception)
    rotationWithOffsets <- either fail pure (withDerivedOffsets rotation)
    registration <- either fail pure (registrationFixtureFrom inceptionWithOffsets inceptionSignatures [])
    armEvidence <- either fail pure (enforcementEvidenceFrom rotationWithOffsets rotationSignatures)
    pure (registration, armEvidence)

registrationFixtureFrom ::
    Value -> [(Int, ByteString)] -> [(Int, ByteString)] -> Either String RegistrationFixture
registrationFixtureFrom event signatures receipts = do
    ked <- atKey "ked" event
    offsets <- atKey "offsets" event
    raw <- textAt "raw_hex" event >>= decodeHex
    aid <- textAt "pre" event >>= digestRaw
    currentKeys <- textArrayAt "k" ked >>= traverse verkeyRaw
    nextKeys <- textArrayAt "n" ked >>= traverse digestRaw
    witnesses <- textArrayAt "b" ked >>= traverse verkeyRaw
    currentThreshold <- thresholdAt "kt" ked
    nextThreshold <- thresholdAt "nt" ked
    toad <- hexIntegerAt "bt" ked
    offT <- integerAt "t" offsets
    offI <- integerAt "i" offsets
    offS <- integerAt "s" offsets
    offK <- integerArrayAt "k" offsets
    offKt <- integerAt "kt" offsets
    offN <- integerArrayAt "n" offsets
    offNt <- integerAt "nt" offsets
    offB <- integerArrayAt "b" offsets
    offBt <- integerAt "bt" offsets
    offD <- eventSaidOffset event
    let datum =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = currentKeys
                , cdCurThreshold = currentThreshold
                , cdNextKeys = nextKeys
                , cdNextThreshold = nextThreshold
                , cdWitnesses = witnesses
                , cdToad = toad
                , cdSeq = 0
                , cdNativeSn = 0
                }
        evidence =
            RegistrationEvidence
                { reEventBytes = raw
                , reOffT = fromInteger offT
                , reOffI = fromInteger offI
                , reOffS = fromInteger offS
                , reOffK = map fromInteger offK
                , reOffKt = fromInteger offKt
                , reOffN = map fromInteger offN
                , reOffNt = fromInteger offNt
                , reOffB = map fromInteger offB
                , reOffBt = fromInteger offBt
                , reCtrlSigs = signatures
                , reWitReceipts = receipts
                }
    pure
        RegistrationFixture
            { rfDatum = datum
            , rfEvidence = evidence
            , rfRaw = raw
            , rfAid = aid
            , rfOffI = offI
            , rfOffD = offD
            , rfProofName = proofTokenName raw aid
            }

enforcementEvidenceFrom :: Value -> [(Int, ByteString)] -> Either String EnforcementEvidence
enforcementEvidenceFrom event signatures = do
    ked <- atKey "ked" event
    offsets <- atKey "offsets" event
    raw <- textAt "raw_hex" event >>= decodeHex
    said <- textAt "said" event >>= digestRaw
    currentKeys <- textArrayAt "k" ked >>= traverse verkeyRaw
    nextKeys <- textArrayAt "n" ked >>= traverse digestRaw
    currentThreshold <- thresholdAt "kt" ked
    nextThreshold <- thresholdAt "nt" ked
    toad <- hexIntegerAt "bt" ked
    nativeSn <- hexIntegerAt "s" ked
    (EnforcementEvidence raw . fromInteger <$> integerAt "t" offsets)
        <*> (fromInteger <$> integerAt "i" offsets)
        <*> (fromInteger <$> integerAt "s" offsets)
        <*> (fromInteger <$> integerAt "d" offsets)
        <*> (map fromInteger <$> integerArrayAt "k" offsets)
        <*> (fromInteger <$> integerAt "kt" offsets)
        <*> (map fromInteger <$> integerArrayAt "n" offsets)
        <*> (fromInteger <$> integerAt "nt" offsets)
        <*> (fromInteger <$> integerAt "bt" offsets)
        <*> pure nativeSn
        <*> pure said
        <*> pure currentKeys
        <*> pure nextKeys
        <*> pure currentThreshold
        <*> pure nextThreshold
        <*> pure toad
        <*> pure signatures
        <*> pure []

eventSaidOffset :: Value -> Either String Integer
eventSaidOffset event = do
    raw <- textAt "raw_hex" event >>= decodeHex
    said <- textAt "said" event
    let needle = Text.encodeUtf8 said
    maybe
        (Left "event SAID not found in raw serialization")
        (Right . fromIntegral)
        (findSubsequence needle raw)

{- | The long-lived #116 enforcement fixtures intentionally preserve their
original raw KERI events without an offsets envelope.  Re-derive the exact
locations from those raw event bytes for this E2E-only wire builder; values are
still checked against the event's KED before they are used as redeemer fields.
-}
withDerivedOffsets :: Value -> Either String Value
withDerivedOffsets event@(Object fields) = do
    ked <- atKey "ked" event
    raw <- textAt "raw_hex" event >>= decodeHex
    aid <- textAt "pre" event
    said <- textAt "said" event
    eventType <- textAt "t" ked
    sequenceNo <- textAt "s" ked
    currentKeys <- textArrayAt "k" ked
    currentThreshold <- textAt "kt" ked
    nextKeys <- textArrayAt "n" ked
    nextThreshold <- textAt "nt" ked
    witnesses <- textArrayAt "b" ked
    toad <- textAt "bt" ked
    let scalar = fieldValueOffset raw
        array field = traverse (arrayValueOffset raw field)
    offsets <-
        object
            <$> sequence
                [ ("t" .=) <$> scalar "t" eventType
                , ("i" .=) <$> scalar "i" aid
                , ("s" .=) <$> scalar "s" sequenceNo
                , ("d" .=) <$> scalar "d" said
                , ("k" .=) <$> array "k" currentKeys
                , ("kt" .=) <$> scalar "kt" currentThreshold
                , ("n" .=) <$> array "n" nextKeys
                , ("nt" .=) <$> scalar "nt" nextThreshold
                , ("b" .=) <$> array "b" witnesses
                , ("bt" .=) <$> scalar "bt" toad
                ]
    pure (Object (KeyMap.insert (Key.fromText "offsets") offsets fields))
withDerivedOffsets _ = Left "event is not an object"

fieldValueOffset :: ByteString -> Text -> Text -> Either String Integer
fieldValueOffset raw field value = do
    let prefix = Text.encodeUtf8 ("\"" <> field <> "\":\"")
        needle = Text.encodeUtf8 value
    start <- maybe (Left (Text.unpack field <> " field not found")) Right (findSubsequence prefix raw)
    let offset = start + BS.length prefix
    if needle `BS.isPrefixOf` BS.drop offset raw
        then Right (fromIntegral offset)
        else Left (Text.unpack field <> " value does not match raw event")

arrayValueOffset :: ByteString -> Text -> Text -> Either String Integer
arrayValueOffset raw field value = do
    let prefix = Text.encodeUtf8 ("\"" <> field <> "\":[")
        needle = Text.encodeUtf8 value
    start <- maybe (Left (Text.unpack field <> " array not found")) Right (findSubsequence prefix raw)
    offset <- maybe (Left (Text.unpack field <> " array value not found")) Right (findSubsequence needle (BS.drop start raw))
    pure (fromIntegral (start + offset))

buildHashProofMintTx ::
    CheckpointEnv -> RegistrationFixture -> IO ConwayTx
buildHashProofMintTx env fixture = do
    unless (blake3Hash (saidBlank fixture) == rfAid fixture) $
        fail "registration fixture does not satisfy the production hash-proof SAID binding"
    -- A-070 70.2A point 3: one acquisition covers the whole preparation.
    envWithPhase1Snapshot env $ \_globals provider -> do
        params <- withinSecs 30 "query hash-proof protocol parameters" (queryProtocolParams provider)
        wallet <- withinSecs 30 "query hash-proof wallet" (queryUTxOs provider (envOwner env))
        (seed, collateral) <- pickDisjoint wallet []
        let (seedIn, _) = seed
            collateralIn = fst collateral
            assetName = AssetName (SBS.toShort (rfProofName fixture))
            minted =
                MultiAsset $
                    Map.singleton
                        (envHashProofPolicy env)
                        (Map.singleton assetName 1)
            proofOut =
                mkBasicTxOut
                    (envOwner env)
                    (MaryValue (Coin 5_000_000) minted)
            redeemers =
                Redeemers $
                    Map.singleton
                        (ConwayMinting (AsIx 0))
                        ( ledgerData (hashProofRedeemerData fixture)
                        , hashProofExUnits
                        )
            body =
                mkBasicTxBody
                    & inputsTxBodyL .~ Set.singleton seedIn
                    & outputsTxBodyL .~ StrictSeq.singleton proofOut
                    & mintTxBodyL .~ minted
                    & collateralInputsTxBodyL .~ Set.singleton collateralIn
                    & scriptIntegrityHashTxBodyL
                        .~ computeScriptIntegrity
                            (Set.singleton PlutusV3)
                            params
                            redeemers
                            (TxDats mempty)
            tx =
                mkBasicTx body
                    & witsTxL . scriptTxWitsL
                        .~ Map.singleton (envHashProofHash env) (envHashProofScript env)
                    & witsTxL . rdmrsTxWitsL .~ redeemers
        either
            (fail . ("buildHashProofMintTx: balance failed: " <>) . show)
            (pure . balancedTx)
            ( balanceTxWith
                params
                [seed]
                (CollateralUtxos [collateral])
                []
                (envOwner env)
                Nothing
                tx
            )

saidBlank :: RegistrationFixture -> ByteString
saidBlank fixture =
    BS.take offD raw
        <> B8.replicate 44 '#'
        <> BS.take (offI - offD - 44) (BS.drop (offD + 44) raw)
        <> B8.replicate 44 '#'
        <> BS.drop (offI + 44) raw
  where
    raw = rfRaw fixture
    offI = fromInteger (rfOffI fixture)
    offD = fromInteger (rfOffD fixture)

buildRegisterTx ::
    CheckpointEnv ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildRegisterTx = buildRegisterTxWith Map.empty []

{- | Build the Register candidate with caller-supplied per-purpose budgets.

An empty map keeps the original declared ceilings, which is the discovery
binding; a populated map produces the rebuilt final binding. Integrity is
recomputed from the exact redeemers, datums, and Plutus V3 language set of
whichever binding is produced.
-}
buildRegisterTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    [(TxIn, TxOut ConwayEra)] ->
    CheckpointEnv ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildRegisterTxWith budgets referenceUtxos env fixture proofUtxo =
    envWithPhase1Snapshot env $ \_globals provider ->
        buildRegisterTxWithIn provider budgets referenceUtxos env fixture proofUtxo

{- | 'buildRegisterTxWith' for a caller already inside the acquisition, so the
two-pass sequence prepares both bindings under ONE acquisition.
-}
buildRegisterTxWithIn ::
    Provider IO ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    [(TxIn, TxOut ConwayEra)] ->
    CheckpointEnv ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildRegisterTxWithIn provider budgets referenceUtxos env fixture proofUtxo = do
    params <- withinSecs 30 "query Register protocol parameters" (queryProtocolParams provider)
    wallet <- withinSecs 30 "query Register wallet" (queryUTxOs provider (envOwner env))
    (feeUtxo, collateralUtxo) <- pickDisjoint wallet [fst proofUtxo]
    let (proofIn, proofOut) = proofUtxo
        (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        checkpointName =
            AssetName $
                SBS.toShort $
                    deriveAidAssetName (cdCesrAid (rfDatum fixture))
        proofName = AssetName (SBS.toShort (rfProofName fixture))
        minted =
            MultiAsset $
                Map.fromList
                    [ (envCheckpointPolicy env, Map.singleton checkpointName 1)
                    , (envHashProofPolicy env, Map.singleton proofName (-1))
                    ]
        stateValue =
            MaryValue
                (Coin (checkpointMinAda + registrationBond + freezeBond))
                ( MultiAsset $
                    Map.singleton
                        (envCheckpointPolicy env)
                        (Map.singleton checkpointName 1)
                )
        stateOut =
            mkBasicTxOut (roleAddress env Active) stateValue
                & datumTxOutL .~ mkInlineDatum (asPlcData (V1 (rfDatum fixture)))
        availableCoin = unCoin (proofOut ^. coinTxOutL) + unCoin (feeOut ^. coinTxOutL)
        changeCoin =
            availableCoin
                - checkpointMinAda
                - registrationBond
                - freezeBond
                - scriptFee
        changeOut = mkBasicTxOut (envOwner env) (inject (Coin changeCoin))
        allInputs = Set.fromList [proofIn, feeIn]
        policies = sort [envCheckpointPolicy env, envHashProofPolicy env]
        mintIndex policy =
            fromIntegral $
                fromMaybe
                    (error "buildRegisterTx: policy missing from mint order")
                    (elemIndex policy policies)
        plan =
            registerScriptPlan
                budgets
                (envCheckpointHash env)
                (envLifecycleHash env)
                (envHashProofHash env)
                (envCheckpointPolicy env)
                (rfEvidence fixture)
                (mintIndex (envCheckpointPolicy env))
                (mintIndex (envHashProofPolicy env))
        scriptWitnesses =
            Map.fromList
                [ (envCheckpointHash env, envCheckpointScript env)
                , (envLifecycleHash env, envLifecycleScript env)
                , (envHashProofHash env, envHashProofScript env)
                ]
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList [stateOut, changeOut]
                & feeTxBodyL .~ Coin scriptFee
                & mintTxBodyL .~ minted
                & withdrawalsTxBodyL .~ rspWithdrawals plan
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                -- A-052 52A: the three applied validators are delivered by
                -- REFERENCE INPUT. Checkpoint 7,632 + lifecycle 6,752 bytes
                -- alone exceed the genesis-backed 16,384 maximum, so inline
                -- delivery can never fit. Integrity is recomputed over the
                -- exact redeemers, datums, and Plutus V3 language-view set for
                -- this shape.
                & referenceInputsTxBodyL .~ Set.fromList (map fst referenceUtxos)
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (rspIntegrityLanguages plan)
                        params
                        (rspRedeemers plan)
                        (rspIntegrityDatums plan)
    unless
        (null referenceUtxos || Map.keysSet scriptWitnesses == rspWitnessHashes plan)
        (fail "buildRegisterTx: Register script witnesses do not match the inspected plan")
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ (if null referenceUtxos then scriptWitnesses else Map.empty)
            & witsTxL . rdmrsTxWitsL .~ rspRedeemers plan

{- | The old-cost devnet cannot create the hash-proof input required for a
real Register.  This deliberately tokenless output is therefore used only for
the independent Advance/Close negative staging checks below; it is never a
substitute for the blocked positive Register lineage.
-}
stageCheckpointInput ::
    CheckpointEnv -> CheckpointDatumV1 -> IO CheckpointInput
stageCheckpointInput env datum = do
    -- A-070 70.2A point 3: one acquisition covers the whole preparation.
    balanced <- envWithPhase1Snapshot env $ \_globals provider -> do
        params <- withinSecs 30 "query staging protocol parameters" (queryProtocolParams provider)
        wallet <- withinSecs 30 "query staging wallet" (queryUTxOs provider (envOwner env))
        feeUtxo <- requireJust "stageCheckpointInput: no wallet UTxO" (largestFirst wallet)
        let stagedOut =
                mkBasicTxOut
                    (roleAddress env Active)
                    (inject (Coin (checkpointMinAda + registrationBond + freezeBond)))
                    & datumTxOutL .~ mkInlineDatum (asPlcData (V1 datum))
            tx = mkBasicTx (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton stagedOut)
        either
            (fail . ("stageCheckpointInput: balance failed: " <>) . show)
            (pure . balancedTx)
            (balanceTx params [feeUtxo] [] (envOwner env) tx)
    txId <- submitSettling env "manual checkpoint staging input" balanced
    utxo <-
        pollOutput
            (envProvider env)
            txId
            [0]
            (const True)
            >>= requireJust "manual checkpoint staging input did not settle"
    dbg
        "manual ACTIVE checkpoint input has no production token lineage; only Advance/Close rejection is asserted"
    pure CheckpointInput{checkpointUtxo = utxo, checkpointDatum = datum}

{- | The complete pure Arm script plan (A-063 correction contract).

Exactly the inseparable integrity inputs the coupled checkpoint/enforcement
pair requires, assembled together so no partial fix can go green:

1. the checkpoint Spending redeemer is the BARE @Freeze@,
   @Constr 1 [B hunter_pkh]@ — the evidence rides the observer, not the
   spend;
2. the enforcement observer's script credential is withdrawn at exactly
   @Coin 0@, and nothing else is withdrawn;
3. the Rewarding redeemer is the exact Freeze @ObserverEnvelope@: the
   @observe_freeze@ action, the applied checkpoint hash as
   @checkpoint_policy@, @Some own_ref@ naming the spent checkpoint input,
   and the unchanged 'EnforcementEvidence' payload;
4. the enforcement observer script is a required witness;
5. the V3 language set, BOTH redeemers, and the (empty) datum witnesses are
   the exact 'computeScriptIntegrity' inputs.

The successor deadline is NOT part of this pure plan: it is a coordinate
question, answered in 'buildArmTx' from the acquired snapshot 'Globals'.
-}
data ArmScriptPlan = ArmScriptPlan
    { aspCheckpointRedeemer :: !PLC.Data
    , aspWithdrawals :: !Withdrawals
    , aspObserverRedeemer :: !PLC.Data
    , aspRedeemers :: !(Redeemers ConwayEra)
    , aspWitnessHashes :: !(Set.Set ScriptHash)
    , aspIntegrityLanguages :: !(Set.Set Language)
    , aspIntegrityDatums :: !(TxDats ConwayEra)
    }

armScriptPlan ::
    -- | applied checkpoint hash (the observer claim's @checkpoint_policy@)
    ScriptHash ->
    -- | applied enforcement observer hash
    ScriptHash ->
    -- | the spent checkpoint input, named as @Some own_ref@
    TxIn ->
    EnforcementEvidence ->
    -- | hunter payment-key hash
    ByteString ->
    -- | measured per-purpose declarations; empty on the discovery pass
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    -- | the checkpoint input's index in the body's ordered input set
    Word32 ->
    ArmScriptPlan
armScriptPlan
    checkpointHash
    enforcementHash
    ownRef
    evidence
    hunter
    budgets
    checkpointIx =
        ArmScriptPlan
            { aspCheckpointRedeemer = checkpointRedeemer
            , aspWithdrawals =
                Withdrawals $
                    Map.singleton
                        ( AccountAddress
                            Testnet
                            (AccountId (ScriptHashObj enforcementHash))
                        )
                        (Coin 0)
            , aspObserverRedeemer = observerRedeemer
            , aspRedeemers = redeemers
            , aspWitnessHashes =
                Set.fromList [checkpointHash, enforcementHash]
            , aspIntegrityLanguages = Set.singleton PlutusV3
            , aspIntegrityDatums = TxDats mempty
            }
      where
        checkpointRedeemer = freezeRedeemerData hunter
        observerRedeemer =
            freezeObserverRedeemerData
                (policyBytes (PolicyID checkpointHash))
                ownRef
                evidence
        budgetFor purpose =
            Map.findWithDefault (ExUnits 0 0) purpose budgets
        redeemers =
            Redeemers $
                Map.fromList
                    [
                        ( ConwaySpending (AsIx checkpointIx)
                        ,
                            ( ledgerData checkpointRedeemer
                            , budgetFor (ConwaySpending (AsIx checkpointIx))
                            )
                        )
                    ,
                        ( ConwayRewarding (AsIx 0)
                        ,
                            ( ledgerData observerRedeemer
                            , budgetFor (ConwayRewarding (AsIx 0))
                            )
                        )
                    ]

{- | The enforcement observer's @ObserverEnvelope@ for the @Freeze@ claim.

The sibling @Register@ spelling is
'Cardano.KERI.AID.Checkpoint.Wire.registerObserverRedeemerData'; this one
differs in exactly the two places the Aiken claim differs — the action tag is
@observe_freeze@ (2) rather than @observe_register@ (0), and @own_ref@ is
@Some@ of the spent checkpoint input rather than @None@ — so it is spelled
here rather than reusing an encoder whose claim shape does not apply.
-}
freezeObserverRedeemerData ::
    ByteString -> TxIn -> EnforcementEvidence -> PLC.Data
freezeObserverRedeemerData checkpointPolicy ownRef evidence =
    Constr
        0
        [ Constr
            0
            [ I observeFreezeAction
            , B checkpointPolicy
            , Constr 0 [outputReferenceData ownRef]
            ]
        , enforcementEvidenceData evidence
        ]

{- | The frozen Aiken action position for @ObserveFreeze@
(@cardano_keri/checkpoint/observer.observe_freeze@).
-}
observeFreezeAction :: Integer
observeFreezeAction = 2

-- | The Aiken @OutputReference@ spelling of a ledger 'TxIn'.
outputReferenceData :: TxIn -> PLC.Data
outputReferenceData (TxIn (TxId txId) (TxIx index)) =
    Constr 0 [B (hashToBytes (extractHash txId)), I (toInteger index)]

{- | Build the production Arm candidate from the one pure 'armScriptPlan'.

The successor deadline is derived through the SAME acquired coordinate the
rest of the candidate is built under: the snapshot 'Globals' translate the
body's own serialized validity upper SLOT to POSIX milliseconds, which is
exactly the endpoint the validator reads out of the ScriptContext's
@validity_range@. No literal margin, no wall clock, no builder-private time
source, and no caller-supplied POSIX field participates.
-}
buildArmTx ::
    CheckpointEnv ->
    -- | the EXACT deployed enforcement observer reference output
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    ValidityPlan ->
    IO ConwayTx
buildArmTx env enforcementRef input evidence hunter validity =
    envWithPhase1Snapshot env $ \globals provider ->
        buildArmTxIn
            globals
            provider
            env
            enforcementRef
            input
            evidence
            hunter
            validity

{- | 'buildArmTx' for a caller already holding the acquired snapshot.

A-070 70.2A point 2: Arm gets the SAME binding two-pass treatment
'buildTwoPassFinalRegister' gives Register, and for the same reason — the old
fixed @scriptExUnits@ ceiling on each of the two purposes was a placeholder,
never a measurement, and merely summing two of them already exceeds PV11.

The complete sequence runs inside the caller's single acquisition:

1. build a discovery binding declaring nothing;
2. evaluate it and require an exact all-@Right@ result for exactly the
   Spending-plus-Rewarding purpose set;
3. derive per-purpose declarations by the same deterministic margin Register
   uses — never a guessed split;
4. rebuild the final binding, which recomputes the script-integrity hash over
   those exact redeemers and datums;
5. re-evaluate the EXACT final bytes and require every observed axis to sit
   within its declared axis;
6. prove the aggregate against the real PV11 maximum; and
7. run the ledger-native final guard.

Only the immutable final transaction leaves.
-}
buildArmTxIn ::
    Globals ->
    Provider IO ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    ValidityPlan ->
    IO ConwayTx
buildArmTxIn
    globals
    provider
    env
    enforcementRef
    input
    evidence
    hunter
    validity = do
        upperMs <- slotStartPosixMsFromGlobals globals (upperSlot validity)
        let deadline = upperMs + freezeWindow
            label = "checkpoint Arm"
            armWith budgets =
                buildCheckpointSpendIn
                    provider
                    env
                    input
                    (armSpendPlan env enforcementRef input evidence hunter budgets)
                    validity
                    [ mkStateOutput
                        env
                        Armed
                        (snd (checkpointUtxo input) ^. valueTxOutL)
                        ( asPlcData
                            ArmedV1
                                { adCheckpoint = checkpointDatum input
                                , adHunterPkh = hunter
                                , adDeadline = deadline
                                }
                        )
                    ]
        -- B5: prove the SUPPLIED enforcement reference is the one the provider
        -- actually resolves, inside this acquisition, before it is used.
        resolvedRefs <-
            queryUTxOByTxIn provider (Set.singleton (fst enforcementRef))
        case Map.toList resolvedRefs of
            [(resolvedIn, resolvedOut)]
                | resolvedIn == fst enforcementRef
                , resolvedOut == snd enforcementRef
                , (resolvedOut ^. referenceScriptTxOutL)
                    == SJust (envEnforcementScript env) ->
                    pure ()
            other ->
                fail
                    ( label
                        <> ": the supplied enforcement reference is not the \
                           \unique resolved output carrying the applied \
                           \enforcement script: "
                        <> show (map fst other)
                    )
        discovery <- armWith Map.empty
        discoveryObserved <-
            withinSecs
                evaluationTimeoutSeconds
                (label <> ": evaluate discovery")
                (evaluateTx provider (addKeyWitness genesisSignKey discovery))
        discoveryUnits <-
            requireExactAllRight
                (label <> ": discovery")
                (armEvaluationPurposes env input discovery)
                discoveryObserved
        let finalBudgets = Map.map deterministicMargin discoveryUnits
        dbg (label <> ": discovery observed=" <> show discoveryUnits)
        dbg (label <> ": final declared=" <> show finalBudgets)
        final <- armWith finalBudgets
        let signedFinal = addKeyWitness genesisSignKey final
        finalObserved <-
            withinSecs
                evaluationTimeoutSeconds
                (label <> ": re-evaluate final")
                (evaluateTx provider signedFinal)
        finalUnits <-
            requireExactAllRight
                (label <> ": final")
                (armEvaluationPurposes env input final)
                finalObserved
        mapM_
            ( \(purpose, observedUnits) -> do
                let declared =
                        Map.findWithDefault (ExUnits 0 0) purpose finalBudgets
                unless (withinDeclared observedUnits declared) $
                    fail
                        ( label
                            <> ": observed units exceed the declared axis for "
                            <> show purpose
                            <> ": observed "
                            <> show observedUnits
                            <> ", declared "
                            <> show declared
                        )
            )
            (Map.toList finalUnits)
        let aggregate = foldr addExUnits (ExUnits 0 0) (Map.elems finalBudgets)
            maximumUnits = pv11MaxTxExUnits (envGuard env)
        unless (withinDeclared aggregate maximumUnits) $
            fail
                ( label
                    <> ": aggregate declared units "
                    <> show aggregate
                    <> " exceed the maximum "
                    <> show maximumUnits
                )
        dbg (label <> ": aggregate declared=" <> show aggregate)
        -- B5: ONE exact final byte sequence. The object that was
        -- re-evaluated is the object that is guarded, the object returned,
        -- and the object eventually submitted unchanged — exactly the
        -- discipline 'buildTwoPassFinalRegister' already follows. Guarding or
        -- returning the unsigned body would make those different serialized
        -- objects.
        armReferenceShapeIn env enforcementRef signedFinal
        guardBeforeSubmitIn
            globals
            provider
            env
            (label <> " final binding")
            signedFinal
        pure signedFinal

{- | Prove the exact final Arm object carries the A-070 70.1A topology: the
singleton enforcement reference input, and ONLY the checkpoint inline.
-}
armReferenceShapeIn ::
    CheckpointEnv -> (TxIn, TxOut ConwayEra) -> ConwayTx -> IO ()
armReferenceShapeIn env enforcementRef tx = do
    unless (references == Set.singleton (fst enforcementRef)) $
        fail
            ( "checkpoint Arm: reference inputs are not exactly the one \
              \enforcement reference: "
                <> show (Set.toList references)
            )
    unless (Map.keysSet witnessed == Set.singleton (envCheckpointHash env)) $
        fail
            ( "checkpoint Arm: inline script witnesses are not exactly the \
              \checkpoint: "
                <> show (Map.keys witnessed)
            )
  where
    references = tx ^. bodyTxL . referenceInputsTxBodyL
    witnessed = tx ^. witsTxL . scriptTxWitsL

{- | The exact purpose set an Arm candidate must evaluate: the checkpoint
Spending purpose at the checkpoint input's own ordered index, plus the single
enforcement Rewarding purpose.
-}
armEvaluationPurposes ::
    CheckpointEnv ->
    CheckpointInput ->
    ConwayTx ->
    Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
armEvaluationPurposes _env input candidate =
    Set.fromList
        [ ConwaySpending
            (AsIx (spendingIndex (fst (checkpointUtxo input)) inputs))
        , ConwayRewarding (AsIx 0)
        ]
  where
    inputs = candidate ^. bodyTxL . inputsTxBodyL

{- | The Arm plan for one candidate, as a function of the checkpoint input's
position in the body's ordered input set.
-}
armPlanOf ::
    CheckpointEnv ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    Word32 ->
    ArmScriptPlan
armPlanOf env input =
    armScriptPlan
        (envCheckpointHash env)
        (envEnforcementHash env)
        (fst (checkpointUtxo input))

{- | POSIX milliseconds at a slot's start, read from an acquired 'Globals'.

This is the coordinate the ledger itself uses to translate the body's
validity interval into the @POSIXTimeRange@ a Plutus V3 ScriptContext
carries, so a deadline derived through it agrees with what the validator
sees. A slot outside the coordinate's horizon is a loud failure, never an
extrapolation.
-}
slotStartPosixMsFromGlobals :: Globals -> SlotNo -> IO Integer
slotStartPosixMsFromGlobals globals slot =
    case epochInfoSlotToRelativeTime_ (epochInfo globals) slot of
        Right (RelativeTime seconds) ->
            pure (systemStartMs + round (seconds * 1000))
        Left err ->
            fail
                ( "slotStartPosixMsFromGlobals: the acquired coordinate \
                  \refused slot "
                    <> show (unSlotNo slot)
                    <> ": "
                    <> Text.unpack err
                )
  where
    systemStartMs =
        round
            ( 1000
                * utcTimeToPOSIXSeconds
                    (getSystemStart (systemStart globals))
            )

buildCurrentArmTx ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    IO (ValidityPlan, ConwayTx)
buildCurrentArmTx env enforcementRef input evidence hunter =
    envWithPhase1Snapshot env $ \globals provider -> do
        validity <- currentArmValidityIn globals provider
        tx <-
            buildArmTxIn
                globals
                provider
                env
                enforcementRef
                input
                evidence
                hunter
                validity
        pure (validity, tx)

buildAdvanceTx ::
    CheckpointEnv ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    ValidityPlan ->
    Bool ->
    IO ConwayTx
buildAdvanceTx env input successor evidence validity repostBond =
    envWithPhase1Snapshot env $ \_globals provider ->
        buildAdvanceTxIn
            provider
            env
            input
            successor
            evidence
            validity
            repostBond

{- | Ordinary Advance, current plan and candidate under ONE acquisition
(A-070 / NOTE-062 B2): the final validity plan is derived and translated by
the SAME acquired callback that then constructs, resolves and balances the
candidate. There is no 'currentValidity' followed by an independent build
acquisition.
-}
buildCurrentAdvanceTx ::
    CheckpointEnv ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    Bool ->
    IO ConwayTx
buildCurrentAdvanceTx env input successor evidence repostBond =
    envWithPhase1Snapshot env $ \globals provider -> do
        validity <- currentValidityIn globals provider
        buildAdvanceTxIn provider env input successor evidence validity repostBond

-- | 'buildAdvanceTx' for a caller already inside the acquisition.
buildAdvanceTxIn ::
    Provider IO ->
    CheckpointEnv ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    ValidityPlan ->
    Bool ->
    IO ConwayTx
buildAdvanceTxIn provider env input successor evidence validity repostBond =
    buildCheckpointSpendIn
        provider
        env
        input
        (bareSpendPlan env (advanceRedeemerData evidence))
        validity
        [ mkStateOutput
            env
            Active
            (addLovelace (if repostBond then freezeBond else 0) inputValue)
            (asPlcData (V1 successor))
        ]
  where
    inputValue = snd (checkpointUtxo input) ^. valueTxOutL

buildClaimTx ::
    CheckpointEnv ->
    CheckpointInput ->
    ByteString ->
    ValidityPlan ->
    IO ConwayTx
buildClaimTx env input hunter validity =
    buildCheckpointSpend
        env
        input
        (claimRedeemerData 0)
        validity
        [ mkBasicTxOut (keyAddress hunter) (inject (Coin freezeBond))
        , mkStateOutput
            env
            Frozen
            (addLovelace (-freezeBond) inputValue)
            (asPlcData (V1 (checkpointDatum input)))
        ]
  where
    inputValue = snd (checkpointUtxo input) ^. valueTxOutL

buildThawTx ::
    CheckpointEnv ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    ValidityPlan ->
    IO ConwayTx
buildThawTx env input successor evidence validity =
    buildAdvanceTx env input successor evidence validity True

{- | Ordinary Close, validity and candidate under ONE acquisition
(A-070 / NOTE-062 B2).
-}
buildCurrentCloseTx :: CheckpointEnv -> CheckpointInput -> IO ConwayTx
buildCurrentCloseTx env input =
    envWithPhase1Snapshot env $ \globals provider -> do
        validity <- currentValidityIn globals provider
        buildCheckpointSpendIn
            provider
            env
            input
            (bareSpendPlan env closeRedeemerData)
            validity
            [mkBasicTxOut (envOwner env) (snd (checkpointUtxo input) ^. valueTxOutL)]

{- | Everything a checkpoint spend contributes beyond its body skeleton.

Most spends are bare: one Spending redeemer, the checkpoint witness, no
withdrawal ('bareSpendPlan'). Arm is the coupled one — it also carries the
enforcement observer's zero withdrawal, its Rewarding redeemer and its
witness ('armSpendPlan') — and the script-integrity hash is recomputed over
whichever of the two the caller supplies.
-}
data CheckpointSpendPlan = CheckpointSpendPlan
    { cspWithdrawals :: !Withdrawals
    , cspRedeemers :: !(Redeemers ConwayEra)
    , cspWitnesses :: !(Map.Map ScriptHash (Script ConwayEra))
    , cspReferenceInputs :: !(Set.Set TxIn)
    , cspIntegrityLanguages :: !(Set.Set Language)
    , cspIntegrityDatums :: !(TxDats ConwayEra)
    }

{- | The unchanged plan for every non-Arm checkpoint spend: exactly one
Spending redeemer, the checkpoint witness, and no withdrawal.
-}
bareSpendPlan ::
    CheckpointEnv -> PLC.Data -> Word32 -> CheckpointSpendPlan
bareSpendPlan env redeemerData stateIndex =
    CheckpointSpendPlan
        { cspWithdrawals = Withdrawals Map.empty
        , cspRedeemers =
            Redeemers $
                Map.singleton
                    (ConwaySpending (AsIx stateIndex))
                    (ledgerData redeemerData, scriptExUnits)
        , cspWitnesses =
            Map.singleton (envCheckpointHash env) (envCheckpointScript env)
        , cspReferenceInputs = Set.empty
        , cspIntegrityLanguages = Set.singleton PlutusV3
        , cspIntegrityDatums = TxDats mempty
        }

{- | The coupled Arm plan, projected from the pure 'armScriptPlan'.

A-070 decision 70.1A: the enforcement observer is delivered by REFERENCE
INPUT, not as an inline witness. Its applied program is 14,392 bytes against
a 6,931-byte excess over the stock @maxTxSize@, so removing exactly that one
inline witness is the smallest topology that can fit — the same rule A-052
applied to Register, and applied here in the same direction rather than
opportunistically widened. The checkpoint program (7,381 bytes) STAYS INLINE.

Everything the coupling asserts is preserved unchanged: the exact Rewarding
purpose, the exact zero withdrawal, the exact @ObserverEnvelope@ and its full
'EnforcementEvidence'. Only the delivery mechanism of the observer's code
changes, which is exactly what A-063 permits ("witness or reference input").
-}
armSpendPlan ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    Word32 ->
    CheckpointSpendPlan
armSpendPlan env enforcementRef input evidence hunter budgets stateIndex =
    CheckpointSpendPlan
        { cspWithdrawals = aspWithdrawals plan
        , cspRedeemers = aspRedeemers plan
        , cspWitnesses =
            Map.singleton (envCheckpointHash env) (envCheckpointScript env)
        , cspReferenceInputs = Set.singleton (fst enforcementRef)
        , cspIntegrityLanguages = aspIntegrityLanguages plan
        , cspIntegrityDatums = aspIntegrityDatums plan
        }
  where
    plan = armPlanOf env input evidence hunter budgets stateIndex

buildCheckpointSpend ::
    CheckpointEnv ->
    CheckpointInput ->
    PLC.Data ->
    ValidityPlan ->
    [TxOut ConwayEra] ->
    IO ConwayTx
buildCheckpointSpend env input redeemerData validity outputs =
    envWithPhase1Snapshot env $ \_globals provider ->
        buildCheckpointSpendIn
            provider
            env
            input
            (bareSpendPlan env redeemerData)
            validity
            outputs

{- | 'buildCheckpointSpend' for a caller already inside the acquisition,
parameterized by the spend plan its state index selects.
-}
buildCheckpointSpendIn ::
    Provider IO ->
    CheckpointEnv ->
    CheckpointInput ->
    (Word32 -> CheckpointSpendPlan) ->
    ValidityPlan ->
    [TxOut ConwayEra] ->
    IO ConwayTx
buildCheckpointSpendIn
    provider
    env
    input
    planFor
    validity
    outputs = do
        params <-
            withinSecs
                30
                "query checkpoint spend parameters"
                (queryProtocolParams provider)
        wallet <-
            withinSecs
                30
                "query checkpoint spend wallet"
                (queryUTxOs provider (envOwner env))
        (feeUtxo, collateralUtxo) <- pickDisjoint wallet [stateIn]
        let (feeIn, _feeOut) = feeUtxo
            collateralIn = fst collateralUtxo
            allInputs = Set.fromList [stateIn, feeIn]
            stateIndex = spendingIndex stateIn allInputs
            plan = planFor stateIndex
            redeemers = cspRedeemers plan
            interval =
                ValidityInterval
                    (SJust (lowerSlot validity))
                    (SJust (upperSlot validity))
            -- A-070 70.2A / verdict B5: the body is completed FIRST — final
            -- topology (reference inputs), final measured budgets, witnesses,
            -- redeemers, datums and the integrity hash — and carries NO fee
            -- and NO change output yet.
            body =
                mkBasicTxBody
                    & inputsTxBodyL .~ allInputs
                    & outputsTxBodyL .~ StrictSeq.fromList outputs
                    & collateralInputsTxBodyL .~ Set.singleton collateralIn
                    & vldtTxBodyL .~ interval
                    & withdrawalsTxBodyL .~ cspWithdrawals plan
                    & referenceInputsTxBodyL .~ cspReferenceInputs plan
                    & scriptIntegrityHashTxBodyL
                        .~ computeScriptIntegrity
                            (cspIntegrityLanguages plan)
                            params
                            redeemers
                            (cspIntegrityDatums plan)
            skeleton =
                mkBasicTx body
                    & witsTxL . scriptTxWitsL .~ cspWitnesses plan
                    & witsTxL . rdmrsTxWitsL .~ redeemers
        -- The reference outputs are resolved through this acquisition so the
        -- balancer can charge their reference-script bytes; the fee therefore
        -- follows the FINAL binding instead of an unrelated constant.
        referenceUtxos <-
            queryUTxOByTxIn provider (cspReferenceInputs plan)
        either
            (fail . ("buildCheckpointSpendIn: balance failed: " <>) . show)
            (pure . balancedTx)
            ( balanceTxWith
                params
                [(stateIn, snd (checkpointUtxo input)), feeUtxo]
                (CollateralUtxos [collateralUtxo])
                (Map.toList referenceUtxos)
                (envOwner env)
                Nothing
                skeleton
            )
      where
        stateIn = fst (checkpointUtxo input)

mkStateOutput ::
    CheckpointEnv -> Role -> MaryValue -> PLC.Data -> TxOut ConwayEra
mkStateOutput env role value datum =
    mkBasicTxOut (roleAddress env role) value
        & datumTxOutL .~ mkInlineDatum datum

addLovelace :: Integer -> MaryValue -> MaryValue
addLovelace amount (MaryValue (Coin lovelace) assets) =
    MaryValue (Coin (lovelace + amount)) assets

keyAddress :: ByteString -> Addr
keyAddress bytes =
    Addr
        Testnet
        ( KeyHashObj $
            KeyHash $
                fromMaybe
                    (error "keyAddress: key hash is not 28 bytes")
                    (hashFromBytes bytes)
        )
        StakeRefNull

responseBoundaryCases :: CheckpointEnv -> IO BoundaryCases
responseBoundaryCases env =
    withinSecs 120 "checkpoint deadline boundary conversion" $
        envWithPhase1Snapshot env $ \globals provider -> do
            armPlan <- currentArmValidityIn globals provider
            responseBoundaryCasesForArmIn globals provider armPlan

{- | 'currentArmValidity' for a caller already inside the acquisition
(A-070 70.2A point 3): the tip comes from the callback PROVIDER and both
endpoints are translated by the callback 'Globals', so the window and the
candidate built from it share one coordinate by construction.
-}
currentArmValidityIn :: Globals -> Provider IO -> IO ValidityPlan
currentArmValidityIn globals provider = do
    snapshot <- queryLedgerSnapshot provider
    let SlotNo tip = ledgerTipSlot snapshot
        armLowerSlot = SlotNo (if tip > 2 then tip - 2 else 0)
        armUpperSlot = SlotNo (tip + 6)
    armLowerMs <- slotStartPosixMsFromGlobals globals armLowerSlot
    armUpperMs <- slotStartPosixMsFromGlobals globals armUpperSlot
    pure
        ValidityPlan
            { lowerSlot = armLowerSlot
            , upperSlot = armUpperSlot
            , lowerPosixMs = armLowerMs
            , upperPosixMs = armUpperMs
            }

responseBoundaryCasesForArm :: CheckpointEnv -> ValidityPlan -> IO BoundaryCases
responseBoundaryCasesForArm env armPlan =
    envWithPhase1Snapshot env $ \globals provider ->
        responseBoundaryCasesForArmIn globals provider armPlan

{- | 'responseBoundaryCasesForArm' for a caller already inside the acquisition.
Every endpoint is translated by the callback 'Globals' and every slot lookup
goes through the callback provider, so the boundary plans share the
candidate's coordinate.
-}
responseBoundaryCasesForArmIn ::
    Globals -> Provider IO -> ValidityPlan -> IO BoundaryCases
responseBoundaryCasesForArmIn globals provider armPlan = do
    let armLowerSlot = lowerSlot armPlan
        armLowerMs = lowerPosixMs armPlan
        armUpperSlot = upperSlot armPlan
        armUpperMs = upperPosixMs armPlan
        SlotNo upper = armUpperSlot
    nextSlotMs <- slotStartPosixMsFromGlobals globals (SlotNo (upper + 1))
    let slotLengthMs = nextSlotMs - armUpperMs
        deadline = armUpperMs + freezeWindow
    unless (slotLengthMs > 0) (fail "node reported a non-positive slot length")
    beforeUpper <-
        fixedTargetSlot
            "response immediately-before upper bound"
            posixMsToSlot
            provider
            (deadline - 1)
    exact <-
        fixedTargetSlot
            "response exact-deadline boundary"
            posixMsToSlot
            provider
            deadline
    afterLower <-
        fixedTargetSlot
            "response immediately-after lower bound"
            posixMsCeilSlot
            provider
            (deadline + 1)
    beforeMs <- slotStartPosixMsFromGlobals globals beforeUpper
    exactMs <- slotStartPosixMsFromGlobals globals exact
    afterMs <- slotStartPosixMsFromGlobals globals afterLower
    let mkPlan lo loMs hi hiMs =
            ValidityPlan
                { lowerSlot = lo
                , upperSlot = hi
                , lowerPosixMs = loMs
                , upperPosixMs = hiMs
                }
        beforePlan = mkPlan armLowerSlot armLowerMs beforeUpper beforeMs
        exactPlan = mkPlan exact exactMs (SlotNo (unSlotNo exact + 20)) (exactMs + 20 * slotLengthMs)
        afterPlan = mkPlan afterLower afterMs (SlotNo (unSlotNo afterLower + 20)) (afterMs + 20 * slotLengthMs)
    pure
        BoundaryCases
            { armUpper = armPlan
            , hardDeadlineMs = deadline
            , justBeforeResponse = beforePlan
            , exactDeadlineClaim = exactPlan
            , afterDeadlineClaim = afterPlan
            }

boundaryCasesCoverDeadline :: BoundaryCases -> Bool
boundaryCasesCoverDeadline cases =
    responseBeforeDeadline
        (hardDeadlineMs cases)
        (Just (Finite (upperPosixMs (justBeforeResponse cases)) Inclusive))
        && claimAtOrAfterDeadline
            (hardDeadlineMs cases)
            (Just (Finite (lowerPosixMs (exactDeadlineClaim cases)) Inclusive))
        && claimAtOrAfterDeadline
            (hardDeadlineMs cases)
            (Just (Finite (lowerPosixMs (afterDeadlineClaim cases)) Inclusive))
        && lowerPosixMs (exactDeadlineClaim cases) == hardDeadlineMs cases
        && lowerPosixMs (afterDeadlineClaim cases) > hardDeadlineMs cases

currentValidity :: CheckpointEnv -> IO ValidityPlan
currentValidity env = envWithPhase1Snapshot env currentValidityIn

-- | 'currentValidity' for a caller already inside the acquisition.
currentValidityIn :: Globals -> Provider IO -> IO ValidityPlan
currentValidityIn globals provider = do
    snapshot <-
        withinSecs 30 "query current validity tip" $
            queryLedgerSnapshot provider
    horizon <-
        withinSecs 30 "query current validity horizon" $
            queryUpperBoundSlot provider AutoLongest
                >>= either
                    (fail . ("currentValidity: no translatable upper horizon: " <>) . show)
                    pure
    let lower = ledgerTipSlot snapshot
        upper = min (SlotNo (unSlotNo lower + 20)) horizon
    unless (lower < upper) $
        fail $
            "currentValidity: no safe interval at provider horizon: "
                <> show (lower, horizon)
    lowerMs <- slotStartPosixMsFromGlobals globals lower
    upperMs <- slotStartPosixMsFromGlobals globals upper
    pure
        ValidityPlan
            { lowerSlot = lower
            , upperSlot = upper
            , lowerPosixMs = lowerMs
            , upperPosixMs = upperMs
            }

fixedTargetSlot ::
    String ->
    (Provider IO -> Integer -> IO SlotNo) ->
    Provider IO ->
    Integer ->
    IO SlotNo
fixedTargetSlot label convert provider target = go pollAttempts
  where
    go remaining
        | remaining <= 0 =
            fail
                ( "checkpoint fixed-target horizon timeout"
                    <> " ("
                    <> label
                    <> ", target="
                    <> show target
                    <> ")"
                )
        | otherwise = do
            converted <- try @SomeException (withinSecs 30 label (convert provider target))
            case converted of
                Right slot -> pure slot
                Left err
                    | "PastHorizon" `isInfixOf` displayException err -> do
                        _ <- queryUpperBoundSlot provider AutoLongest
                        threadDelay 1_000_000
                        go (remaining - 1)
                    | otherwise -> throwIO err

assertActiveCheckpoint ::
    CheckpointEnv -> RegistrationFixture -> (TxIn, TxOut ConwayEra) -> IO ()
assertActiveCheckpoint env fixture (_, output) = do
    unless
        (output ^. addrTxOutL == roleAddress env Active)
        (fail "registered checkpoint output is not at the production ACTIVE role address")
    unless
        (hasAsset (envCheckpointPolicy env) (deriveAidAssetName (cdCesrAid (rfDatum fixture))) output)
        (fail "registered checkpoint output does not retain its production AID token")
    unless
        (unCoin (output ^. coinTxOutL) >= checkpointMinAda + registrationBond + freezeBond)
        (fail "registered checkpoint output is short of checkpoint_min_ada + D_reg + B")
    case extractDatum output of
        Just (V1 datum)
            | datum == rfDatum fixture -> pure ()
        _ -> fail "registered checkpoint output does not carry the production V1 datum lineage"

assertArmedCheckpoint ::
    CheckpointEnv ->
    CheckpointInput ->
    ByteString ->
    Integer ->
    ValidityPlan ->
    (TxIn, TxOut ConwayEra) ->
    IO ()
assertArmedCheckpoint env input hunter deadline armValidity (_, output) = do
    unless
        (output ^. addrTxOutL == roleAddress env Armed)
        (fail "Arm did not create an ARMED role-0x02 output")
    unless
        (output ^. valueTxOutL == snd (checkpointUtxo input) ^. valueTxOutL)
        (fail "Arm did not preserve the registered token and reserve custody")
    unless
        (deadline == upperPosixMs armValidity + freezeWindow)
        (fail "Arm deadline is not arm upper bound plus W_freeze")
    case extractDatum output of
        Just
            ArmedV1
                { adCheckpoint = armedCheckpoint
                , adHunterPkh = armedHunter
                , adDeadline = armedDeadline
                }
                | armedCheckpoint == checkpointDatum input
                    && armedHunter == hunter
                    && armedDeadline == deadline ->
                    pure ()
        _ -> fail "Arm output does not carry the exact ArmedV1 checkpoint/hunter/deadline wrapper"

assertClaimSettlement ::
    CheckpointEnv ->
    RegistrationFixture ->
    ByteString ->
    (TxIn, TxOut ConwayEra) ->
    TxId ->
    IO ()
assertClaimSettlement env fixture hunter armed claimTxId = do
    payout <-
        pollOutput
            (envProvider env)
            claimTxId
            [0, 1, 2]
            (isExactHunterPayout hunter)
            >>= requireJust "Claim hunter payout did not settle"
    frozen <-
        pollOutput
            (envProvider env)
            claimTxId
            [0, 1, 2]
            (isFrozenCheckpoint env fixture)
            >>= requireJust "Claim FROZEN checkpoint output did not settle"
    unless
        (isExactHunterPayout hunter (snd payout))
        (fail "Claim hunter payout is not exactly B at the named hunter key")
    unless
        (snd frozen ^. valueTxOutL == addLovelace (-freezeBond) (snd armed ^. valueTxOutL))
        (fail "Claim FROZEN checkpoint does not retain the remaining reserve and AID token")

isExactHunterPayout :: ByteString -> TxOut ConwayEra -> Bool
isExactHunterPayout hunter output =
    output ^. addrTxOutL == keyAddress hunter
        && case output ^. valueTxOutL of
            MaryValue (Coin lovelace) (MultiAsset assets) -> lovelace == freezeBond && Map.null assets

isFrozenCheckpoint :: CheckpointEnv -> RegistrationFixture -> TxOut ConwayEra -> Bool
isFrozenCheckpoint env fixture output =
    output ^. addrTxOutL == roleAddress env Frozen
        && hasAsset (envCheckpointPolicy env) (deriveAidAssetName (cdCesrAid (rfDatum fixture))) output
        && case extractDatum output of
            Just (V1 datum) -> datum == rfDatum fixture
            _ -> False

dummyAdvanceEvidence :: AdvanceEvidence
dummyAdvanceEvidence =
    AdvanceEvidence
        { aeEventBytes = "{}"
        , aeOffT = 0
        , aeOffI = 0
        , aeOffS = 0
        , aeOffK = []
        , aeOffKt = 0
        , aeOffN = []
        , aeOffNt = 0
        , aeOffBr = []
        , aeOffBa = []
        , aeOffBt = 0
        , aeWitCut = []
        , aeWitAdd = []
        , aeCtrlSigs = []
        , aeWitReceipts = []
        }

hashProofRedeemerData :: RegistrationFixture -> PLC.Data
hashProofRedeemerData fixture =
    Constr
        0
        [ B (rfRaw fixture)
        , B (rfAid fixture)
        , I (rfOffI fixture)
        , I (rfOffD fixture)
        ]

hashProofBurnRedeemerData :: PLC.Data
hashProofBurnRedeemerData = Constr 0 [B "", B "", I 0, I 0]

registerRedeemerData :: RegistrationEvidence -> PLC.Data
registerRedeemerData _evidence = Constr 0 []

advanceRedeemerData :: AdvanceEvidence -> PLC.Data
advanceRedeemerData evidence = Constr 0 [advanceEvidenceData evidence]

{- | The BARE @Freeze@ spend redeemer: @Constr 1 [B hunter_pkh]@.

The checkpoint's @Freeze@ constructor retains only the hunter; the
'EnforcementEvidence' travels on the enforcement observer's Rewarding
redeemer ('freezeObserverRedeemerData'), which is the only place the
validator decodes it.
-}
freezeRedeemerData :: ByteString -> PLC.Data
freezeRedeemerData hunter = Constr 1 [B hunter]

claimRedeemerData :: Integer -> PLC.Data
claimRedeemerData outputIndex = Constr 2 [I outputIndex]

closeRedeemerData :: PLC.Data
closeRedeemerData = Constr 4 []

ledgerData :: PLC.Data -> Ledger.Data ConwayEra
ledgerData = Ledger.Data

pickDisjoint ::
    [(TxIn, TxOut ConwayEra)] ->
    [TxIn] ->
    IO ((TxIn, TxOut ConwayEra), (TxIn, TxOut ConwayEra))
pickDisjoint wallet excluded =
    case sortByCoin (filter ((`notElem` excluded) . fst) wallet) of
        (first : second : _) -> pure (first, second)
        _ -> fail "need two disjoint wallet UTxOs (fee/seed and collateral)"

largestFirst :: [(TxIn, TxOut ConwayEra)] -> Maybe (TxIn, TxOut ConwayEra)
largestFirst = listToMaybe . sortByCoin

sortByCoin :: [(TxIn, TxOut ConwayEra)] -> [(TxIn, TxOut ConwayEra)]
sortByCoin = sortOn (Down . unCoin . (^. coinTxOutL) . snd)

spendingIndex :: TxIn -> Set.Set TxIn -> Word32
spendingIndex needle inputs = go 0 (Set.toAscList inputs)
  where
    go _ [] = error "spendingIndex: input missing"
    go index (candidate : rest)
        | candidate == needle = index
        | otherwise = go (index + 1) rest

submitSettling :: CheckpointEnv -> String -> ConwayTx -> IO TxId
submitSettling env label tx = do
    guardBeforeSubmit env ("submitSettling " <> label) tx
    result <-
        withinSecs 60 ("submit " <> label) $
            submitTx (envSubmitter env) (addKeyWitness genesisSignKey tx)
    case result of
        Submitted txId -> pure txId
        Rejected reason -> fail (label <> " rejected: " <> B8.unpack reason)

awaitWalletCount :: Provider IO -> Addr -> Int -> IO [(TxIn, TxOut ConwayEra)]
awaitWalletCount provider address count = go pollAttempts
  where
    go remaining
        | remaining <= 0 = fail "wallet UTxO poll timed out"
        | otherwise = do
            utxos <- withinSecs 30 "query wallet UTxOs" (queryUTxOs provider address)
            if length utxos >= count
                then pure utxos
                else threadDelay 1_000_000 >> go (remaining - 1)

pollOutput ::
    Provider IO ->
    TxId ->
    [Integer] ->
    (TxOut ConwayEra -> Bool) ->
    IO (Maybe (TxIn, TxOut ConwayEra))
pollOutput provider txId indices accepts = go pollAttempts
  where
    candidates = [TxIn txId (TxIx (fromInteger index)) | index <- indices]
    go remaining
        | remaining <= 0 = pure Nothing
        | otherwise = do
            found <-
                withinSecs 30 "query submitted transaction output" $
                    queryUTxOByTxIn provider (Set.fromList candidates)
            case find (accepts . snd) (Map.toList found) of
                Just output -> pure (Just output)
                Nothing -> threadDelay 1_000_000 >> go (remaining - 1)

hasAsset :: PolicyID -> ByteString -> TxOut ConwayEra -> Bool
hasAsset policy name output =
    case output ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            ( Map.lookup policy assets
                >>= Map.lookup (AssetName (SBS.toShort name))
            )
                == Just 1

requireJust :: String -> Maybe a -> IO a
requireJust message = maybe (fail message) pure

withinSecs :: Int -> String -> IO a -> IO a
withinSecs seconds label action =
    timeout (seconds * 1_000_000) action
        >>= maybe (fail (label <> ": timed out")) pure

dbg :: String -> IO ()
dbg = hPutStrLn stderr . ("[checkpoint-e2e] " <>)

oneLine :: String -> String
oneLine = take 480 . map (\character -> if character == '\n' then ' ' else character)

atKey :: Text -> Value -> Either String Value
atKey key (Object objectValue) =
    maybe (Left (Text.unpack key <> " missing")) Right $
        KeyMap.lookup (Key.fromText key) objectValue
atKey key _ = Left (Text.unpack key <> ": parent is not an object")

textAt :: Text -> Value -> Either String Text
textAt key value =
    atKey key value >>= \case
        String textValue -> Right textValue
        _ -> Left (Text.unpack key <> " is not text")

integerAt :: Text -> Value -> Either String Integer
integerAt key value =
    atKey key value >>= \case
        Number number -> Right (truncate number)
        _ -> Left (Text.unpack key <> " is not an integer")

textArrayAt :: Text -> Value -> Either String [Text]
textArrayAt key value = atKey key value >>= arrayValues >>= traverse asText
  where
    asText (String textValue) = Right textValue
    asText _ = Left (Text.unpack key <> " contains a non-text value")

integerArrayAt :: Text -> Value -> Either String [Integer]
integerArrayAt key value = atKey key value >>= arrayValues >>= traverse asInteger
  where
    asInteger (Number number) = Right (truncate number)
    asInteger _ = Left (Text.unpack key <> " contains a non-integer value")

arrayValues :: Value -> Either String [Value]
arrayValues (Array values) = Right (toList values)
arrayValues _ = Left "expected an array"

thresholdAt :: Text -> Value -> Either String Threshold
thresholdAt key value =
    textAt key value >>= \textValue ->
        case reads (Text.unpack textValue) of
            [(threshold, "")] -> Right (Unweighted threshold)
            _ -> Left (Text.unpack key <> " is not an unweighted threshold")

hexIntegerAt :: Text -> Value -> Either String Integer
hexIntegerAt key value =
    textAt key value >>= \textValue ->
        case reads ("0x" <> Text.unpack textValue) of
            [(integer, "")] -> Right integer
            _ -> Left (Text.unpack key <> " is not hexadecimal")

decodeHex :: Text -> Either String ByteString
decodeHex = convertFromBase Base16 . Text.encodeUtf8

digestRaw :: Text -> Either String ByteString
digestRaw textValue =
    parseFull textValue >>= \case
        SelfAddressing raw -> Right raw
        _ -> Left (Text.unpack textValue <> ": not a self-addressing digest")

verkeyRaw :: Text -> Either String ByteString
verkeyRaw textValue =
    parseFull textValue >>= \case
        Ed25519PublicKey raw -> Right raw
        _ -> Left (Text.unpack textValue <> ": not an Ed25519 public key")

parseFull :: Text -> Either String Primitive
parseFull textValue =
    case parsePrimitive (Text.encodeUtf8 textValue) of
        Right (primitive, rest)
            | BS.null rest -> Right primitive
            | otherwise -> Left (Text.unpack textValue <> ": trailing CESR bytes")
        Left err -> Left (Text.unpack textValue <> ": " <> err)

indexedSignaturesAt :: Text -> Value -> Either String [(Int, ByteString)]
indexedSignaturesAt key value =
    atKey key value >>= arrayValues >>= traverse indexedSignature

indexedSignature :: Value -> Either String (Int, ByteString)
indexedSignature value = do
    index <- fromInteger <$> integerAt "index" value
    signature <- textAt "sig_hex" value >>= decodeHex
    pure (index, signature)

findSubsequence :: ByteString -> ByteString -> Maybe Int
findSubsequence needle haystack =
    find
        (\offset -> needle `BS.isPrefixOf` BS.drop offset haystack)
        [0 .. BS.length haystack - BS.length needle]

-- | The applied production checkpoint script held by the environment.
checkpointScriptOf :: CheckpointEnv -> Script ConwayEra
checkpointScriptOf = envCheckpointScript

-- | The genesis owner address held by the environment.
checkpointOwnerOf :: CheckpointEnv -> Addr
checkpointOwnerOf = envOwner

-- | The applied hash-proof policy id held by the environment.
checkpointHashProofPolicyOf :: CheckpointEnv -> PolicyID
checkpointHashProofPolicyOf = envHashProofPolicy

-- | The provider seam held by the environment.
checkpointProviderOf :: CheckpointEnv -> Provider IO
checkpointProviderOf = envProvider

-- | The enforcement observer script hash, for shape observations.
checkpointEnforcementHashOf :: CheckpointEnv -> ScriptHash
checkpointEnforcementHashOf = envEnforcementHash

-- | The enforcement observer script, for shape observations.
checkpointEnforcementScriptOf :: CheckpointEnv -> Script ConwayEra
checkpointEnforcementScriptOf = envEnforcementScript

{- | The APPLIED checkpoint validator's exact bytes — the deployed program,
after parameter application — for replay evidence.
-}
checkpointAppliedBytesOf :: CheckpointEnv -> SBS.ShortByteString
checkpointAppliedBytesOf = envCheckpointBytes

{- | Enter this environment's ONE acquisition boundary.

The public spelling of 'envWithPhase1Snapshot' for callers outside this
module: everything whose provenance must match the candidate — resolve,
build, evaluate, deadline coordinate, Phase-1 guard — runs inside, and
neither the snapshot 'Globals' nor the snapshot 'Provider' escapes it.
-}

{- HLINT ignore withCheckpointPhase1Snapshot "Eta reduce" -}

-- Not eta-reducible: the record field is rank-N, so the point-free form
-- needs impredicative instantiation that GHC rejects here.
withCheckpointPhase1Snapshot ::
    CheckpointEnv -> (Globals -> Provider IO -> IO a) -> IO a
withCheckpointPhase1Snapshot env callback =
    envWithPhase1Snapshot env callback

{- | Run the real Conway Phase-1 guard on the exact final object a submission
exit is about to send, resolving its complete normal-plus-collateral input set
through the provider. Structural failures reject here, before the submission
seam, carrying the ledger's own failure constructors.
-}
guardBeforeSubmit :: CheckpointEnv -> String -> ConwayTx -> IO ()
guardBeforeSubmit env label tx =
    envWithPhase1Snapshot env $ \globals provider ->
        guardBeforeSubmitIn globals provider env label tx

{- | 'guardBeforeSubmit' for a caller ALREADY inside the acquisition.

The snapshot 'Globals' and snapshot 'Provider' are supplied explicitly, so
the resolution and the guard use exactly the coordinate the candidate was
built under and nothing re-acquires inside an open callback.
-}

{- | The reward state a candidate must be validated under, derived from the
body's OWN withdrawals (A-047 1A, shared by A-070 70.2A point 5).

Plain validation is the default; a body carrying withdrawals is validated
with EXACTLY its own withdrawal accounts at their known balances. This is the
one shared derivation — the production submit guard and any direct
"does it fit" assertion use it, so neither can silently validate the
corrected Arm body under the wrong reward state. It never filters or waives
the @ConwayWithdrawalsMissingAccounts@ class; it only stops manufacturing a
false instance of it.
-}
bodyRewardState :: ConwayTx -> Phase1RewardState
bodyRewardState tx
    | Map.null withdrawalAccounts = NoRewardState
    | otherwise = SeededRewardAccounts withdrawalAccounts
  where
    withdrawalAccounts =
        unWithdrawals (tx ^. bodyTxL . withdrawalsTxBodyL)

guardBeforeSubmitIn ::
    Globals -> Provider IO -> CheckpointEnv -> String -> ConwayTx -> IO ()
guardBeforeSubmitIn globals provider env label tx = do
    resolved <-
        queryUTxOByTxIn
            provider
            -- A-052: resolved REFERENCE inputs are carried through the guard
            -- too, so a wrong reference set is a real structural failure.
            ( Set.unions
                [ tx ^. bodyTxL . inputsTxBodyL
                , tx ^. bodyTxL . collateralInputsTxBodyL
                , tx ^. bodyTxL . referenceInputsTxBodyL
                ]
            )
    snapshot <- queryLedgerSnapshot provider
    let rewardState = bodyRewardState tx
        verdict =
            runPhase1
                Phase1Input
                    { p1Globals = globals
                    , p1Slot = ledgerTipSlot snapshot
                    , p1Params = envGuard env
                    , p1ResolvedInputs = Map.toList resolved
                    }
                rewardState
                tx
    unless (phase1Accepted verdict) $
        fail
            ( label
                <> ": Phase-1 guard rejected the candidate: "
                <> renderPhase1 verdict
            )

{- | A-046 ruling 3A: the two-pass final Register binding.

Observable sequence, with no guessed budget split and no second hand-rolled
aggregate gate:

1. evaluate the intentionally aggregate-inadmissible DISCOVERY binding and
   require the exact expected purpose set, all @Right@;
2. derive each purpose's final memory and CPU independently from the observed
   usage plus a deterministic margin;
3. rebuild from the original semantic candidate with those exact budgets,
   recomputing integrity over the exact final redeemers, datums, and Plutus V3
   language set;
4. re-evaluate that exact final binding, require the same exact purpose set
   all-@Right@, each observed axis within its declared axis, and the aggregate
   declared units within @ppMaxTxExUnits@;
5. run the real state-aware Phase-1 guard; and
6. submit that exact final object unchanged.

The discovery binding is evaluator-only: it is never guard-certified, signed,
or submitted.
-}
submitTwoPassRegister ::
    CheckpointEnv ->
    String ->
    [(TxIn, TxOut ConwayEra)] ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO TxId
submitTwoPassRegister env label referenceUtxos fixture proofUtxo = do
    signedFinal <-
        buildTwoPassFinalRegister env label referenceUtxos fixture proofUtxo
    submitUnchangedCapture env label signedFinal

{- | Steps 1-5 of the two-pass sequence: discovery evaluation, deterministic
rebinding, exact final re-evaluation, per-axis and aggregate proofs, and the
real state-aware guard. Returns the exact final signed object to submit
unchanged.
-}
buildTwoPassFinalRegister ::
    CheckpointEnv ->
    String ->
    [(TxIn, TxOut ConwayEra)] ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildTwoPassFinalRegister env label referenceUtxos fixture proofUtxo =
    -- A-070 70.2A point 3: BOTH passes, the exact-final re-evaluation and the
    -- final guard all run inside ONE acquisition.
    envWithPhase1Snapshot env $ \globals provider ->
        buildTwoPassFinalRegisterIn globals provider env label referenceUtxos fixture proofUtxo

{- | 'buildTwoPassFinalRegister' for a caller already inside the acquisition,
so a longer chain (Register -> Arm -> replay) stays under ONE acquisition.
-}
buildTwoPassFinalRegisterIn ::
    Globals ->
    Provider IO ->
    CheckpointEnv ->
    String ->
    [(TxIn, TxOut ConwayEra)] ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildTwoPassFinalRegisterIn globals provider env label referenceUtxos fixture proofUtxo = do
    let expectedPurposes = registerEvaluationPurposes env
    discovery <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildRegisterTxWithIn provider Map.empty referenceUtxos env fixture proofUtxo
    discoveryObserved <-
        withinSecs evaluationTimeoutSeconds (label <> ": evaluate discovery") $
            evaluateTx provider (addKeyWitness genesisSignKey discovery)
    discoveryUnits <-
        requireExactAllRight
            (label <> ": discovery")
            expectedPurposes
            discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    dbg (label <> ": discovery observed=" <> show discoveryUnits)
    dbg (label <> ": final declared=" <> show finalBudgets)
    final <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildRegisterTxWithIn provider finalBudgets referenceUtxos env fixture proofUtxo
    let signedFinal = addKeyWitness genesisSignKey final
    finalObserved <-
        withinSecs evaluationTimeoutSeconds (label <> ": re-evaluate final") $
            evaluateTx provider signedFinal
    finalUnits <-
        requireExactAllRight
            (label <> ": final")
            expectedPurposes
            finalObserved
    -- Each observed axis must sit within its declared axis.
    mapM_
        ( \(purpose, observedUnits) -> do
            let declared =
                    Map.findWithDefault (ExUnits 0 0) purpose finalBudgets
            unless (withinDeclared observedUnits declared) $
                fail
                    ( label
                        <> ": observed units exceed the declared axis for "
                        <> show purpose
                        <> ": observed "
                        <> show observedUnits
                        <> ", declared "
                        <> show declared
                    )
        )
        (Map.toList finalUnits)
    -- The aggregate declared units must sit within the real PV11 maximum.
    let aggregate = foldr addExUnits (ExUnits 0 0) (Map.elems finalBudgets)
        maximumUnits = pv11MaxTxExUnits (envGuard env)
    unless (withinDeclared aggregate maximumUnits) $
        fail
            ( label
                <> ": aggregate declared units "
                <> show aggregate
                <> " exceed the maximum "
                <> show maximumUnits
            )
    dbg (label <> ": aggregate declared=" <> show aggregate)
    guardBeforeSubmitIn globals provider env (label <> " final binding") signedFinal
    pure signedFinal

{- | Deterministic per-axis margin: observed usage plus ten percent, rounded
upward, with a minimum margin of one on each axis.
-}
deterministicMargin :: ExUnits -> ExUnits
deterministicMargin (ExUnits mem steps) =
    ExUnits (bump mem) (bump steps)
  where
    bump value = value + max 1 ((value + 9) `div` 10)

addExUnits :: ExUnits -> ExUnits -> ExUnits
addExUnits (ExUnits m1 s1) (ExUnits m2 s2) = ExUnits (m1 + m2) (s1 + s2)

withinDeclared :: ExUnits -> ExUnits -> Bool
withinDeclared (ExUnits m s) (ExUnits dm ds) = m <= dm && s <= ds

{- | Require an evaluation map whose key set is EXACTLY the expected purpose
set and whose every entry is @Right@. Missing, extra, duplicate, or
unattributed purposes fail.
-}
requireExactAllRight ::
    String ->
    Set.Set (ConwayPlutusPurpose AsIx ConwayEra) ->
    Map.Map
        (ConwayPlutusPurpose AsIx ConwayEra)
        (Either failure ExUnits) ->
    IO (Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits)
requireExactAllRight label expected observed = do
    unless (Map.keysSet observed == expected) $
        fail
            ( label
                <> ": purpose set is not exactly the expected set: expected "
                <> show expected
                <> ", observed "
                <> show (Map.keysSet observed)
            )
    Map.traverseWithKey
        ( \purpose outcome -> case outcome of
            Right units -> pure units
            Left _ ->
                fail
                    ( label
                        <> ": purpose "
                        <> show purpose
                        <> " did not evaluate successfully"
                    )
        )
        observed

-- | The applied observer_lifecycle script held by the environment.
checkpointLifecycleScriptOf :: CheckpointEnv -> Script ConwayEra
checkpointLifecycleScriptOf = envLifecycleScript

-- | The applied hash-proof script held by the environment.
checkpointHashProofScriptOf :: CheckpointEnv -> Script ConwayEra
checkpointHashProofScriptOf = envHashProofScript

-- ---------------------------------------------------------------------------
-- A-046 informational observer rows (REVIEW-023 finding 6)
-- ---------------------------------------------------------------------------

{- | The observer-only measurement ceiling for an informational row.

This is NOT the transaction maximum: the row measures the attributed observer
Rewarding purpose alone, never a combined transaction fit.
-}
observerOnlyCeiling :: ExUnits
observerOnlyCeiling = ExUnits 14_000_000 10_000_000_000

{- | Load one committed @advance.json@ row as real 'AdvanceEvidence'.

Every field comes from the committed keripy oracle: exact raw rotation bytes,
the row's own offsets, its witness cut/add verkeys, its indexed controller
signatures, and its incoming-indexed witness receipts. Nothing is invented,
defaulted, or weakened.
-}
loadAdvanceObserverEvidence :: Text -> IO AdvanceEvidence
loadAdvanceObserverEvidence rowKey = do
    path <- getDataFileName "test/keri-fixtures/fixtures/advance.json"
    value <- eitherDecodeFileStrict path >>= either fail pure
    row <- either fail pure (atKey rowKey value)
    rot <- either fail pure (atKey "rot" row)
    ked <- either fail pure (atKey "ked" rot)
    offsets <- either fail pure (atKey "offsets" row)
    raw <- either fail pure (textAt "raw_hex" rot >>= decodeHex)
    witCut <- either fail pure (textArrayAt "br" ked >>= traverse verkeyRaw)
    witAdd <- either fail pure (textArrayAt "ba" ked >>= traverse verkeyRaw)
    ctrlSigs <- either fail pure (indexedSignaturesAt "rot_sigs" row)
    receipts <- either fail pure (indexedSignaturesAt "rot_witness_receipts" row)
    let scalar key = either fail (pure . fromInteger) (integerAt key offsets)
        vector key =
            either fail (pure . map fromInteger) (integerArrayAt key offsets)
    AdvanceEvidence raw
        <$> scalar "t"
        <*> scalar "i"
        <*> scalar "s"
        <*> vector "k"
        <*> scalar "kt"
        <*> vector "n"
        <*> scalar "nt"
        <*> vector "br"
        <*> vector "ba"
        <*> scalar "bt"
        <*> pure witCut
        <*> pure witAdd
        <*> pure ctrlSigs
        <*> pure receipts

{- | Build the synthetic tokenless observer-cost candidate for one row.

A withdraw-zero against the applied @observer_advance@ reward account carrying
the row's real Advance evidence as its Rewarding redeemer. It is EVALUATED
ONLY and is never signed or submitted.
-}
buildObserverCostCandidate ::
    CheckpointEnv -> AdvanceEvidence -> IO ConwayTx
buildObserverCostCandidate env evidence = do
    params <-
        withinSecs 30 "observer row: query protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "observer row: query wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <- pickDisjoint wallet []
    let redeemers =
            Redeemers $
                Map.singleton
                    (ConwayRewarding (AsIx 0))
                    (ledgerData (advanceRedeemerData evidence), observerOnlyCeiling)
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton (fst feeUtxo)
                & collateralInputsTxBodyL .~ Set.singleton (fst collateralUtxo)
                & feeTxBodyL .~ Coin scriptFee
                & withdrawalsTxBodyL
                    .~ Withdrawals
                        ( Map.singleton
                            ( AccountAddress
                                Testnet
                                (AccountId (ScriptHashObj (envAdvanceHash env)))
                            )
                            (Coin 0)
                        )
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ Map.singleton (envAdvanceHash env) (envAdvanceScript env)
            & witsTxL . rdmrsTxWitsL .~ redeemers

{- | Run one informational observer-cost row.

Structured, visible, and NON-BINDING: every failure, script @Left@, missing or
unattributed purpose, and ceiling overrun is reported and returns normally, so
a completed positive chain is never erased and the run never aborts. The row
is evaluated only and never submitted.
-}
runInformationalObserverRow :: CheckpointEnv -> String -> Text -> IO ()
runInformationalObserverRow env rowLabel rowKey = do
    dbg (rowLabel <> ": synthetic tokenless observer-cost row")
    dbg (rowLabel <> ": evaluated only, not submitted")
    dbg (rowLabel <> ": observer-only")
    dbg
        ( rowLabel
            <> ": no production Advance transaction-fit or settlement claim"
        )
    dbg
        ( rowLabel
            <> ": no claim that the 1083-byte fixture passes the hash-proof"
            <> " registration policy"
        )
    outcome <- try $ do
        evidence <- loadAdvanceObserverEvidence rowKey
        candidate <- buildObserverCostCandidate env evidence
        observed <-
            withinSecs evaluationTimeoutSeconds (rowLabel <> ": evaluateTx") $
                evaluateTx (envProvider env) candidate
        case Map.lookup (ConwayRewarding (AsIx 0)) observed of
            Nothing ->
                pure
                    ( rowLabel
                        <> ": no attributed observer Rewarding result; observed "
                        <> show (Map.keysSet observed)
                    )
            Just (Left failure) ->
                pure (rowLabel <> ": observer Rewarding failed: " <> show failure)
            Just (Right units) ->
                pure
                    ( rowLabel
                        <> ": attributed observer Rewarding="
                        <> show units
                        <> " against observer-only ceiling "
                        <> show observerOnlyCeiling
                        <> ( if withinDeclared units observerOnlyCeiling
                                then " (within ceiling)"
                                else " (OVERRUN, informational only)"
                           )
                    )
    dbg $ case (outcome :: Either SomeException String) of
        Right reported -> reported
        Left err ->
            rowLabel
                <> ": informational row failed, non-binding: "
                <> displayException err

{- | Ordinary Claim: bounded WAIT outside the acquisition, then ONE acquisition
that rechecks its own acquired tip, derives and translates the final plan, and
constructs/resolves/balances the candidate (A-070 / NOTE-062 B2).

Only the immutable candidate leaves. The wait deliberately stays outside so a
long poll never holds the acquisition.
-}
buildClaimAfterWait ::
    CheckpointEnv ->
    CheckpointInput ->
    ByteString ->
    -- | the stored on-chain deadline
    Integer ->
    IO ConwayTx
buildClaimAfterWait env input hunter deadline = do
    lower <-
        fixedTargetSlot
            "claim lower bound"
            posixMsCeilSlot
            (envProvider env)
            deadline
    waitFor lower pollAttempts
  where
    waitFor lower remaining
        | remaining <= 0 =
            fail "node did not reach the Claim deadline before polling timed out"
        | otherwise = do
            snapshot <-
                withinSecs
                    30
                    "query node Claim tip"
                    (queryLedgerSnapshot (envProvider env))
            if ledgerTipSlot snapshot < lower
                then threadDelay 1_000_000 >> waitFor lower (remaining - 1)
                else envWithPhase1Snapshot env $ \globals provider -> do
                    -- Recheck the tip through THIS acquisition's provider, so
                    -- the plan and the candidate share one coordinate.
                    acquired <- queryLedgerSnapshot provider
                    unless (ledgerTipSlot acquired >= lower) $
                        fail
                            ( "buildClaimAfterWait: acquired tip "
                                <> show (ledgerTipSlot acquired)
                                <> " is before the Claim lower bound "
                                <> show lower
                            )
                    lowerMs <- slotStartPosixMsFromGlobals globals lower
                    let upper = SlotNo (unSlotNo lower + 20)
                    upperMs <- slotStartPosixMsFromGlobals globals upper
                    unless
                        ( claimAtOrAfterDeadline
                            deadline
                            (Just (Finite lowerMs Inclusive))
                        )
                        (fail "node-derived Claim lower bound is before the stored deadline")
                    buildCheckpointSpendIn
                        provider
                        env
                        input
                        (bareSpendPlan env (claimRedeemerData 0))
                        ValidityPlan
                            { lowerSlot = lower
                            , upperSlot = upper
                            , lowerPosixMs = lowerMs
                            , upperPosixMs = upperMs
                            }
                        [ mkBasicTxOut (keyAddress hunter) (inject (Coin freezeBond))
                        , mkStateOutput
                            env
                            Frozen
                            (addLovelace (-freezeBond) (snd (checkpointUtxo input) ^. valueTxOutL))
                            (asPlcData (V1 (checkpointDatum input)))
                        ]
