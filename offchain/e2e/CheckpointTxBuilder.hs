{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : CheckpointTxBuilder
Description : Production-shaped #114 checkpoint transactions for withDevnet

Loads the tracked-source Aiken blueprint, applies the production checkpoint
validator's deployment parameters in order, and builds real Conway
transactions for Register, Advance and Convict.

The pinned devnet's 251-entry Plutus V3 model cannot price the Plomin builtins
used by the real hash-proof policy.  This boundary therefore executes and
asserts that exact mint failure.  Advance remains a real production-script
staging rejection.
-}
module CheckpointTxBuilder (
    CheckpointEnv (..),
    CheckpointInput (..),
    RejectionEvidence,
    stagedCheckpointDevnet,
    stagedCheckpointDevnetSocket,
    advanceRejection,
    hashProofMintOldCostRejection,
    rejectionIsOldCostPlominBoundary,
    rejectionReachedProductionScript,
    productionRegisterScenario,
    registryJourney,
    productionRegisterAdvanceScenario,
    productionRegisterConvictScenario,
    productionRegisterFreezeScenario,
    productionRegisterFreezeThenDepositScenario,
    productionRegisterTopUpScenario,
    productionFrozenTopUpScenario,
    buildAdvanceTx,
) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Application (
    Action (..),
    ApplicationParameters (..),
    Change (..),
    Credential (..),
    HeldDatum (..),
    OutputReference (..),
    PlutusAddress (..),
    RegistrationData (..),
    RegistryIdentity (..),
    SpendAction (..),
    StateMint (..),
    actionData,
    activeLeaf,
    activeTokenName,
    configurationTokenName,
    heldDatumData,
    registrationApprovalName,
    spendActionData,
    stateDatumData,
    stateMintData,
    stateSpendData,
    stateTokenName,
    unstakedAddress,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
    advancePredicate,
 )
import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    BountyCommitment (..),
    BountyCommitmentPlan (..),
    BountyMint (..),
    BountyScope (..),
    BountySpend (..),
    CommitmentFamily (..),
    CommitmentParameters (..),
    CommitmentPayout (..),
    ResolvedCommitment (..),
    SlotRange (..),
    atOrAfter,
    atOrBefore,
    prepareBountyCommitment,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyStateView (..),
    checkpointDatumToData,
    convictedOf,
    keyMaterialOf,
    liveOfKeyState,
    rotatedLive,
 )
import Cardano.KERI.AID.Checkpoint.Deposit (
    BondOption (..),
    DepositFacts (..),
    DepositInput (..),
    DepositIntent (..),
    DepositParams (..),
    DepositRefusal,
    depositIntentPreimage,
    depositVerdict,
    requiredIntent,
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Entitlement (
    EntitledEnforcementPlan (..),
    enforcementEvidenceDigest,
    prepareEntitledEnforcement,
 )
import Cardano.KERI.AID.Checkpoint.Freeze (
    FreezeEvidence (..),
    FreezeParams (..),
    FreezeSettlement (..),
    freezeSettlement,
    frozenLive,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Inclusivity (..),
    RawBound (..),
    Role (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (
    SpentCheckpoint (..),
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.TopUp (
    TopUpParams (..),
    TopUpSettlement (..),
    markedLive,
    topUpSettlement,
 )
import Cardano.KERI.AID.Checkpoint.Value (
    RotationSettlement (..),
    checkpointMinAda,
    heldValue,
    rotationSettlement,
    withValue,
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceObserverRedeemerData,
    advanceSpendRedeemerData,
    asPlcData,
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
    registerObserverRedeemerData,
    topUpSpendRedeemerData,
 )
import Cardano.KERI.AID.E2E.Datum (extractDatum, mkInlineDatum, rawInlineData)
import Cardano.KERI.AID.E2E.DevnetTerms (devnetTerms)
import Cardano.KERI.AID.E2E.FoldGuard (FoldRefusal (..), foldRefusal)
import Cardano.KERI.AID.E2E.MpfProof (prove)
import Cardano.KERI.AID.E2E.MpfTrie qualified as Registry
import Cardano.KERI.AID.E2E.Rejection (consumedInputAlone)
import Cardano.KERI.AID.E2E.Script (
    ScriptArtifact (..),
    applyCommitmentParams,
    computeScriptHash,
    deriveCommitmentFamily,
    extractCompiledCodeExact,
    loadBlueprint,
    mkCageScript,
    observerArtifacts,
    scriptHashBytes,
    v1CommitmentParameters,
    v1FreezeBond,
    v1Premium,
    v1RegistrationBond,
 )
import Cardano.KERI.AID.Migration.Types (OutputRef (..))
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
    registryInitialFloor,
 )
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
    serialiseAddr,
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppCostModelsL, ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..), costModelsValid, getCostModelParams)
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
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
    reqSignerHashesTxBodyL,
    treasuryDonationTxBodyL,
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
    Inject (..),
    Network (Testnet),
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
import Cardano.Node.Client.E2E.Devnet (withCardanoNode)
import Cardano.Node.Client.E2E.Governance (enactPV11Transition)
import Cardano.Node.Client.E2E.Setup (
    DevnetConfig (devnetTargetPV),
    TargetPV (PV11),
    addKeyWitness,
    assertPV11Enacted,
    defaultDevnetConfig,
    devnetMagic,
    genesisAddr,
    genesisDir,
    genesisSignKey,
    keyHashFromSignKey,
    mkSignKey,
    withDevnetConfig,
 )
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
    SlotNo (..),
 )
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (..))
import Cardano.Tx.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
 )
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel)
import Control.Exception (finally, throwIO, try)
import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecodeFileStrict, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.Functor ((<&>))
import Data.List (elemIndex, find, isInfixOf, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Ord (Down (..))
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word32, Word8)
import Lens.Micro ((&), (.~), (^.))
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import PlutusCore.Data qualified as PLC
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))
import System.IO (
    BufferMode (LineBuffering),
    hPutStrLn,
    hSetBuffering,
    stderr,
    stdout,
 )
import System.Timeout (timeout)

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
    , envAdvanceReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envEnforcementScript :: !(Script ConwayEra)
    , envEnforcementBytes :: !SBS.ShortByteString
    , envEnforcementHash :: !ScriptHash
    , envEnforcementReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envEntitlementScript :: !(Script ConwayEra)
    , envEntitlementBytes :: !SBS.ShortByteString
    , envEntitlementHash :: !ScriptHash
    , envEntitlementReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envCommitmentFamily :: !CommitmentFamily
    {- ^ #280 DM-280-ENV: the applied #271 family both enforcement observers
    were parameterised with, retained so a settlement cannot be planned
    against any other reservation program.
    -}
    , envCommitmentScript :: !(Script ConwayEra)
    , envCommitmentBytes :: !SBS.ShortByteString
    , envCommitmentHash :: !ScriptHash
    , envCommitmentPolicy :: !PolicyID
    , envCommitmentReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envHashProofScript :: !(Script ConwayEra)
    , envHashProofBytes :: !SBS.ShortByteString
    , envHashProofHash :: !ScriptHash
    , envHashProofPolicy :: !PolicyID
    , envRegistry :: !RegistryScripts
    -- ^ the registry the run is built on, and the scripts derived for it
    , envTerms :: !RegistryTerms
    , envApplicationScript :: !(Script ConwayEra)
    , envApplicationHash :: !ScriptHash
    , envStateScript :: !(Script ConwayEra)
    , envStateHash :: !ScriptHash
    , envTemplateOutput :: !(Maybe (TxIn, TxOut ConwayEra))
    , envApplicationReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envStateReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envConfiguration :: !(Maybe (TxIn, TxOut ConwayEra))
    -- ^ the registry's configuration record, once its genesis has settled
    , envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envOwner :: !Addr
    }

data CheckpointInput = CheckpointInput
    { checkpointUtxo :: !(TxIn, TxOut ConwayEra)
    , checkpointDatum :: !KeyStateView
    -- ^ the key state of the output's datum
    , checkpointFacts :: !CheckpointDatumV2
    -- ^ the version 2 datum the output carries, as read from the chain
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

registrationBond :: Integer
registrationBond = v1RegistrationBond

freezeBond :: Integer
freezeBond = v1FreezeBond

premium :: Integer
premium = v1Premium

{- | The pool a registration funds beyond its deposit and bond: enough for
the premium of one rotation and a remainder the conviction refunds.
-}
initialPool :: Integer
initialPool = premium + 1_000_000

scriptFee :: Integer
scriptFee = 3_000_000

scriptExUnits :: ExUnits
scriptExUnits = ExUnits 12_000_000 7_000_000_000

hashProofExUnits :: ExUnits
hashProofExUnits = ExUnits 14_000_000 10_000_000_000

hashProofBurnExUnits :: ExUnits
hashProofBurnExUnits = ExUnits 500_000 500_000_000

pollAttempts :: Int
pollAttempts = 40

stagedCheckpointDevnet :: (CheckpointEnv -> IO ()) -> IO ()
stagedCheckpointDevnet action = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    blueprintPath <- resolveBlueprintPath
    assertPinnedPv11Fixture
    withinSecs 300 "checkpoint withDevnet"
        $ withDevnetConfig
            defaultDevnetConfig{devnetTargetPV = PV11}
        $ \lsq ltxs -> setupCheckpointEnv blueprintPath lsq ltxs action

{- | Like 'stagedCheckpointDevnet' but also hands the caller the devnet's real
N2C socket path, needed by a consumer that brings its own client up against
the same node (#175's live follower composition smoke).

Uses the plain, non-restartable 'withCardanoNode' bracket — the same PV11 +
N2C bring-up 'withDevnetConfig' performs internally, just with the socket
exposed. No restart, pause, or signal capability is exposed: the retained
SC-1 leg needs none of it.
-}
stagedCheckpointDevnetSocket ::
    (FilePath -> CheckpointEnv -> IO a) -> IO a
stagedCheckpointDevnetSocket action = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    blueprintPath <- resolveBlueprintPath
    assertPinnedPv11Fixture
    gDir <- genesisDir
    withinSecs 300 "follower withDevnet+socket" $
        withCardanoNode gDir $
            \sock _startMs -> do
                lsq <- newLSQChannel 16
                ltxs <- newLTxSChannel 16
                client <- async $ runNodeClient devnetMagic sock lsq ltxs
                ( do
                        enactPV11Transition lsq ltxs
                        setupCheckpointEnv blueprintPath lsq ltxs (action sock)
                    )
                    `finally` cancel client

resolveBlueprintPath :: IO FilePath
resolveBlueprintPath =
    lookupEnv "KERI_CHECKPOINT_BLUEPRINT"
        >>= maybe
            ( lookupEnv "KERI_CAGE_BLUEPRINT"
                >>= maybe
                    (fail "KERI_CHECKPOINT_BLUEPRINT not set")
                    pure
            )
            pure

setupCheckpointEnv ::
    FilePath -> LSQChannel -> LTxSChannel -> (CheckpointEnv -> IO a) -> IO a
setupCheckpointEnv blueprintPath lsq ltxs action = do
    let provider = mkN2CProvider lsq
    assertPV11Enacted provider
    assertLivePv11Boundary provider
    prepareWallet provider (mkN2CSubmitter ltxs) genesisAddr
    seedUtxos <-
        withinSecs 30 "query the registry seed" $
            queryUTxOs provider (seedAddress genesisAddr)
    seed <- requireJust "the registry seed output is absent" (listToMaybe seedUtxos)
    env <- mkCheckpointEnv blueprintPath lsq ltxs (fst seed)
    verifyRegisterScriptSizes env
    _ <- registerLifecycleStakeCredential env
    advanceRef <-
        deployReferenceScript
            env
            "observer_advance reference deployment"
            (envAdvanceScript env)
    _ <- registerAdvanceStakeCredential env advanceRef
    enforcementRef <-
        deployReferenceScript
            env
            "observer_enforcement reference deployment"
            (envEnforcementScript env)
    _ <- registerEnforcementStakeCredential env enforcementRef
    entitlementRef <-
        deployReferenceScript
            env
            "observer_entitlement reference deployment"
            (envEntitlementScript env)
    _ <- registerEntitlementStakeCredential env entitlementRef
    -- #280: the commitment program is a spend-and-mint validator, so it needs a
    -- published reference script but no stake credential of its own.
    commitmentRef <-
        deployReferenceScript
            env
            "bounty_commitment reference deployment"
            (envCommitmentScript env)
    genesisRegistry
        env
            { envAdvanceReference = Just advanceRef
            , envEnforcementReference = Just enforcementRef
            , envEntitlementReference = Just entitlementRef
            , envCommitmentReference = Just commitmentRef
            }
        >>= action

mkCheckpointEnv :: FilePath -> LSQChannel -> LTxSChannel -> TxIn -> IO CheckpointEnv
mkCheckpointEnv blueprintPath lsq ltxs seed = do
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    registry <-
        either
            fail
            pure
            (deriveRegistryScripts stateTemplate devnetTerms (outputReferenceOf' seed) blueprint)
    let artifacts = observerArtifacts (scriptsObservers registry) <> [scriptsCheckpoint registry]
    hashProof <- requireArtifact "hash-proof" artifacts
    lifecycle <- requireArtifact "observer-lifecycle" artifacts
    advance <- requireArtifact "observer-advance" artifacts
    enforcement <- requireArtifact "observer-enforcement" artifacts
    entitlement <- requireArtifact "observer-entitlement" artifacts
    checkpoint <- requireArtifact "checkpoint-register" artifacts
    commitmentProgram <-
        requireJust
            "bounty_commitment compiled code is absent from the production blueprint"
            (extractCompiledCodeExact commitmentValidatorTitle blueprint)
    commitmentFamily <- either fail pure (deriveCommitmentFamily blueprint)
    let hashProofCode = artifactProgram hashProof
        hashProofScript = mkCageScript hashProofCode
        hashProofHash = artifactScriptHash hashProof
        hashProofPolicy = PolicyID hashProofHash
        appliedLifecycle = artifactProgram lifecycle
        lifecycleScript = mkCageScript appliedLifecycle
        lifecycleHash = artifactScriptHash lifecycle
        appliedAdvance = artifactProgram advance
        advanceScript = mkCageScript appliedAdvance
        advanceHash = artifactScriptHash advance
        appliedEnforcement = artifactProgram enforcement
        enforcementScript = mkCageScript appliedEnforcement
        enforcementHash = artifactScriptHash enforcement
        appliedEntitlement = artifactProgram entitlement
        entitlementScript = mkCageScript appliedEntitlement
        entitlementHash = artifactScriptHash entitlement
        appliedCheckpoint = artifactProgram checkpoint
        checkpointScript = mkCageScript appliedCheckpoint
        checkpointHash = artifactScriptHash checkpoint
        checkpointPolicy = PolicyID checkpointHash
        appliedCommitment =
            applyCommitmentParams v1CommitmentParameters commitmentProgram
        commitmentScript = mkCageScript appliedCommitment
        commitmentScriptHash = computeScriptHash appliedCommitment
        commitmentPolicy = PolicyID commitmentScriptHash
    -- #280 DM-280-ENV: the family the enforcement and entitlement observers
    -- were applied to must be the family of the program this environment is
    -- about to deploy, open and spend.  Re-deriving the applied program here
    -- and comparing hashes is what makes that an observation rather than an
    -- assumption; a different applied magnitude yields a different hash and
    -- stops the run before any reservation exists.
    unless (cfPolicy commitmentFamily == scriptHashBytes commitmentScriptHash) $
        fail
            ( "applied #271 commitment program is not the family pinned into\
              \ the observers: family="
                <> show (cfPolicy commitmentFamily)
                <> " applied="
                <> show (scriptHashBytes commitmentScriptHash)
            )
    dbg ("checkpoint_register script hash: " <> show checkpointHash)
    dbg ("bounty_commitment script hash: " <> show commitmentScriptHash)
    dbg ("observer_lifecycle script hash: " <> show lifecycleHash)
    dbg ("observer_advance script hash: " <> show advanceHash)
    dbg ("observer_enforcement script hash: " <> show enforcementHash)
    dbg ("observer_entitlement script hash: " <> show entitlementHash)
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
            , envAdvanceReference = Nothing
            , envEnforcementScript = enforcementScript
            , envEnforcementBytes = appliedEnforcement
            , envEnforcementHash = enforcementHash
            , envEnforcementReference = Nothing
            , envEntitlementScript = entitlementScript
            , envEntitlementBytes = appliedEntitlement
            , envEntitlementHash = entitlementHash
            , envEntitlementReference = Nothing
            , envCommitmentFamily = commitmentFamily
            , envCommitmentScript = commitmentScript
            , envCommitmentBytes = appliedCommitment
            , envCommitmentHash = commitmentScriptHash
            , envCommitmentPolicy = commitmentPolicy
            , envCommitmentReference = Nothing
            , envHashProofScript = hashProofScript
            , envHashProofBytes = hashProofCode
            , envHashProofHash = hashProofHash
            , envHashProofPolicy = hashProofPolicy
            , envRegistry = registry
            , envTerms = devnetTerms
            , envApplicationScript = mkCageScript (artifactProgram (scriptsApplication registry))
            , envApplicationHash = artifactScriptHash (scriptsApplication registry)
            , envStateScript = mkCageScript (scriptsStateProgram registry)
            , envStateHash = computeScriptHash (scriptsStateProgram registry)
            , envTemplateOutput = Nothing
            , envApplicationReference = Nothing
            , envStateReference = Nothing
            , envConfiguration = Nothing
            , envProvider = mkN2CProvider lsq
            , envSubmitter = mkN2CSubmitter ltxs
            , envOwner = genesisAddr
            }

requireArtifact :: Text -> [ScriptArtifact] -> IO ScriptArtifact
requireArtifact name artifacts =
    case filter ((== name) . artifactName) artifacts of
        [artifact] -> pure artifact
        _ -> fail ("V1 artifact not found uniquely: " <> Text.unpack name)

{- | Prove the Register programs and the Advance observer fit both the applied
program budget and signed reference-script creation transactions.
-}
verifyRegisterScriptSizes :: CheckpointEnv -> IO ()
verifyRegisterScriptSizes env = do
    params <-
        withinSecs 30 "query Register script-size parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Register script-size wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    seed <- requireJust "Register script-size check: no wallet UTxO" (largestFirst wallet)
    let measure label script programBytes = do
            unless (programBytes <= productionMaxReferenceProgramBytes) $
                fail
                    ( label
                        <> " program exceeds applied 16,133-byte budget: "
                        <> show programBytes
                    )
            let output =
                    mkBasicTxOut (envOwner env) (inject (Coin 100_000_000))
                        & referenceScriptTxOutL .~ SJust script
                skeleton =
                    mkBasicTx
                        (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton output)
            balanced <-
                either
                    (fail . ((label <> ": balance failed: ") <>) . show)
                    (pure . balancedTx)
                    (balanceTx params [seed] [] (envOwner env) skeleton)
            let signed = addKeyWitness genesisSignKey balanced
                txBytes =
                    fromIntegral
                        (BSL.length (serialize (eraProtVerLow @ConwayEra) signed))
            dbg (label <> " program=" <> show programBytes <> " signed-tx=" <> show txBytes)
            unless (txBytes <= productionMaxTxBytes) $
                fail (label <> " exceeds stock maxTxSize: " <> show txBytes)
    measure "checkpoint_register reference script" (envCheckpointScript env) (SBS.length (envCheckpointBytes env))
    measure "observer_lifecycle reference script" (envLifecycleScript env) (SBS.length (envLifecycleBytes env))
    measure "observer_advance reference script" (envAdvanceScript env) (SBS.length (envAdvanceBytes env))
    measure "observer_enforcement reference script" (envEnforcementScript env) (SBS.length (envEnforcementBytes env))
    measure "observer_entitlement reference script" (envEntitlementScript env) (SBS.length (envEntitlementBytes env))
    measure "hash_proof reference script" (envHashProofScript env) (SBS.length (envHashProofBytes env))
    measure "bounty_commitment reference script" (envCommitmentScript env) (SBS.length (envCommitmentBytes env))
    -- #339: re-derived from the applied advance program once it reads the
    -- version 2 datum (14_695 before), not reused from the previous pin. The
    -- 16_133 ceiling is unchanged. Re-derived again after the version 1
    -- datum constructor left the shared datum type (15_778 before). Re-derived
    -- once more when the observer also hosts the freeze verdict (15_625 before),
    -- and when the live datum gained its ninth field (15_665 before).
    unless (SBS.length (envAdvanceBytes env) == 15_710) $
        fail
            ( "observer_advance applied program changed from 15,710 bytes: "
                <> show (SBS.length (envAdvanceBytes env))
            )

productionMaxReferenceProgramBytes :: Int
productionMaxReferenceProgramBytes = 16_133

productionMaxTxBytes :: Int
productionMaxTxBytes = 16_384

productionPv11MaxTxExUnits :: ExUnits
productionPv11MaxTxExUnits = ExUnits 16_500_000 10_000_000_000

assertLivePv11Boundary :: Provider IO -> IO ()
assertLivePv11Boundary provider = do
    params <- withinSecs 30 "query live PV11 parameters" (queryProtocolParams provider)
    let observedExUnits = params ^. ppMaxTxExUnitsL
        observedMaxTxSize = fromIntegral (params ^. ppMaxTxSizeL)
        v3Entries =
            maybe 0 (length . getCostModelParams) $
                Map.lookup PlutusV3 (costModelsValid (params ^. ppCostModelsL))
    unless (observedExUnits == productionPv11MaxTxExUnits) $
        fail ("live PV11 maxTxExUnits mismatch: " <> show observedExUnits)
    unless (observedMaxTxSize == productionMaxTxBytes) $
        fail ("live PV11 maxTxSize mismatch: " <> show observedMaxTxSize)
    unless (v3Entries == 350) $
        fail ("live PV11 PlutusV3 cost model has " <> show v3Entries <> " entries")

{- | Load the committed nodeclients PV11 pparams fixture before booting. Only
the three fields the fixture actually carries are claimed here.
-}
assertPinnedPv11Fixture :: IO ()
assertPinnedPv11Fixture = do
    fixtureGenesisDir <-
        lookupEnv "E2E_GENESIS_DIR"
            >>= maybe (fail "E2E_GENESIS_DIR not set") pure
    let path =
            takeDirectory fixtureGenesisDir
                </> "fixtures"
                </> "pparams-pv11-mainnet.json"
    value <- eitherDecodeFileStrict path >>= either fail pure
    protocol <- either fail pure (atKey "protocolVersion" value)
    execution <- either fail pure (atKey "maxTxExecutionUnits" value)
    models <- either fail pure (atKey "costModels" value)
    major <- either fail pure (integerAt "major" protocol)
    memory <- either fail pure (integerAt "memory" execution)
    steps <- either fail pure (integerAt "steps" execution)
    v3 <- either fail pure (atKey "PlutusV3" models)
    entries <- either fail (pure . length) (arrayValues v3)
    unless
        ( major == 11
            && memory == 16_500_000
            && steps == 10_000_000_000
            && entries == 350
        )
        (fail ("PV11 pparams fixture mismatch: " <> show (major, memory, steps, entries)))
    dbg ("loaded PV11 pparams fixture: " <> path)

policyBytes :: PolicyID -> ByteString
policyBytes (PolicyID (ScriptHash hash)) = hashToBytes hash

registerLifecycleStakeCredential :: CheckpointEnv -> IO TxId
registerLifecycleStakeCredential env =
    registerObserverStakeCredential
        env
        (envLifecycleHash env)
        (envLifecycleScript env)
        Nothing
        "observer_lifecycle"

registerAdvanceStakeCredential ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    IO TxId
registerAdvanceStakeCredential env advanceRef =
    registerObserverStakeCredential
        env
        (envAdvanceHash env)
        (envAdvanceScript env)
        (Just advanceRef)
        "observer_advance"

registerEnforcementStakeCredential ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    IO TxId
registerEnforcementStakeCredential env enforcementRef =
    registerObserverStakeCredential
        env
        (envEnforcementHash env)
        (envEnforcementScript env)
        (Just enforcementRef)
        "observer_enforcement"

registerEntitlementStakeCredential ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    IO TxId
registerEntitlementStakeCredential env entitlementRef =
    registerObserverStakeCredential
        env
        (envEntitlementHash env)
        (envEntitlementScript env)
        (Just entitlementRef)
        "observer_entitlement"

registerObserverStakeCredential ::
    CheckpointEnv ->
    ScriptHash ->
    Script ConwayEra ->
    Maybe (TxIn, TxOut ConwayEra) ->
    String ->
    IO TxId
registerObserverStakeCredential env observerHash observerScript reference label = do
    params <-
        withinSecs 30 ("query " <> label <> " registration parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 ("query " <> label <> " registration wallet") $
            queryUTxOs (envProvider env) (envOwner env)
    let referenceUtxos = maybe [] pure reference
    (seed, collateral) <- pickDisjoint wallet (map fst referenceUtxos)
    let keyDeposit = params ^. ppKeyDepositL
        certificate =
            ConwayTxCertDeleg
                (ConwayRegCert (ScriptHashObj observerHash) (SJust keyDeposit))
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwayCertifying (AsIx 0))
                    (ledgerData (I 0), scriptExUnits)
        body =
            mkBasicTxBody
                & certsTxBodyL .~ StrictSeq.singleton certificate
                & collateralInputsTxBodyL .~ Set.singleton (fst collateral)
                & referenceInputsTxBodyL
                    .~ Set.fromList (map fst referenceUtxos)
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
        skeleton =
            mkBasicTx body
                & witsTxL . scriptTxWitsL
                    .~ maybe
                        (Map.singleton observerHash observerScript)
                        (const Map.empty)
                        reference
                & witsTxL . rdmrsTxWitsL .~ redeemers
    balanced <-
        either
            (fail . ((label <> " registration balance failed: ") <>) . show)
            (pure . balancedTx)
            ( balanceTxWith
                params
                [seed]
                (CollateralUtxos [collateral])
                referenceUtxos
                (envOwner env)
                Nothing
                skeleton
            )
    txId <- submitSettling env (label <> " registration") balanced
    _ <-
        pollOutput
            (envProvider env)
            txId
            [0, 1]
            (const True)
            >>= requireJust (label <> " registration did not settle")
    pure txId

roleAddress :: CheckpointEnv -> Role -> Addr
roleAddress env Active =
    Addr Testnet (ScriptHashObj (envCheckpointHash env)) StakeRefNull

deployReferenceScript ::
    CheckpointEnv ->
    String ->
    Script ConwayEra ->
    IO (TxIn, TxOut ConwayEra)
deployReferenceScript env label script = do
    params <-
        withinSecs 30 (label <> ": query parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 (label <> ": query wallet") $
            queryUTxOs (envProvider env) (envOwner env)
    seed <- requireJust (label <> ": no wallet UTxO") (largestFirst wallet)
    let output =
            mkBasicTxOut (envOwner env) (inject (Coin 100_000_000))
                & referenceScriptTxOutL .~ SJust script
        skeleton =
            mkBasicTx
                (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton output)
    balanced <-
        either
            (fail . ((label <> ": balance failed: ") <>) . show)
            (pure . balancedTx)
            (balanceTx params [seed] [] (envOwner env) skeleton)
    txId <- submitSettling env label balanced
    pollOutput
        (envProvider env)
        txId
        [0]
        ((== SJust script) . (^. referenceScriptTxOutL))
        >>= requireJust (label <> ": reference script did not settle")

productionRegisterScenario :: CheckpointEnv -> IO CheckpointInput
productionRegisterScenario env = do
    (fixture, _) <- loadLifecycleFixture
    productionRegisterScenarioWith env fixture

productionRegisterScenarioWith :: CheckpointEnv -> RegistrationFixture -> IO CheckpointInput
productionRegisterScenarioWith env fixture =
    fst <$> productionRegisterScenarioWithReference env fixture

productionRegisterScenarioWithReference ::
    CheckpointEnv ->
    RegistrationFixture ->
    IO (CheckpointInput, (TxIn, TxOut ConwayEra))
productionRegisterScenarioWithReference env fixture = do
    referenceUtxos <- deployRegisterReferences env
    productionRegisterScenarioUsingReferences env referenceUtxos fixture

deployRegisterReferences ::
    CheckpointEnv ->
    IO [(TxIn, TxOut ConwayEra)]
deployRegisterReferences env = do
    checkpointRef <-
        deployReferenceScript
            env
            "checkpoint_register reference deployment"
            (envCheckpointScript env)
    lifecycleRef <-
        deployReferenceScript
            env
            "observer_lifecycle reference deployment"
            (envLifecycleScript env)
    hashProofRef <-
        deployReferenceScript
            env
            "hash_proof reference deployment"
            (envHashProofScript env)
    pure [checkpointRef, lifecycleRef, hashProofRef]

productionRegisterAdvanceScenario :: CheckpointEnv -> IO ()
productionRegisterAdvanceScenario env = do
    fixture <- loadRotateStoryFixture
    (registered, checkpointRef) <-
        productionRegisterScenarioWithReference env (rsRegistration fixture)
    advanceRef <-
        requireJust
            "observer_advance reference was not deployed during setup"
            (envAdvanceReference env)
    let honest =
            signedRotateEvidence
                env
                registered
                fixture
                (rsRotationSigners fixture)
                (aeWitReceipts (rsUnsignedEvidence fixture))
        stolen =
            signedRotateEvidence
                env
                registered
                fixture
                (rsCurrentSigners fixture)
                (aeWitReceipts (rsUnsignedEvidence fixture))
        belowThreshold = honest{aeCtrlSigs = take 1 (aeCtrlSigs honest)}
        underWitnessed =
            honest{aeWitReceipts = take 1 (aeWitReceipts honest)}
        spent = rotateSpentCheckpoint env registered
        created = rsCreated fixture
    case advancePredicate spent created honest of
        Left predicateError ->
            fail
                ( "checkpoint Advance: signed evidence failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    sequence_
        [ rejectRotateEvidence
            env
            checkpointRef
            advanceRef
            registered
            created
            "Advance stolen-current"
            stolen
        , rejectRotateEvidence
            env
            checkpointRef
            advanceRef
            registered
            created
            "Advance below-successor-threshold"
            belowThreshold
        , rejectRotateEvidence
            env
            checkpointRef
            advanceRef
            registered
            created
            "Advance under-witnessed"
            underWitnessed
        ]
    advanceTxId <-
        submitTwoPassAdvance
            env
            "checkpoint Advance"
            checkpointRef
            advanceRef
            registered
            created
            honest
    successor <-
        pollOutput
            (envProvider env)
            advanceTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "Advance successor did not settle"
    unless
        (snd successor ^. addrTxOutL == roleAddress env Active)
        (fail "Advance successor is not at the ACTIVE address")
    _ <- settledAdvance env "Advance" registered created advanceTxId successor
    remaining <-
        withinSecs 30 "query advanced checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst (checkpointUtxo registered)))
    unless (Map.null remaining) $
        fail "Advance left the registered checkpoint input unspent"
    dbg
        ( "Advance settled; tx id="
            <> show advanceTxId
            <> "; successor="
            <> show (fst successor)
        )

{- | A freeze, end to end: register with a pool that covers the premium, advance
once (the premium leaves the pool, which drops below it), then present the
controller's own next witnessed rotation as a freeze. The refusals are the
freeze's evidence premises, each judged by the production script; the accepted
freeze settles a frozen datum on the old keys and pays the bond.
-}
productionRegisterFreezeScenario :: CheckpointEnv -> IO ()
productionRegisterFreezeScenario env = do
    fixture <- loadConvictStoryFixture
    let laterRotation = fsResponseRotation fixture
    (checkpointRef, advanceRef, advanced) <-
        advanceOnceForRotationStory env fixture
    let created = rsCreated laterRotation
        honest =
            signedRotateEvidence
                env
                advanced
                laterRotation
                (rsRotationSigners laterRotation)
                (aeWitReceipts (rsUnsignedEvidence laterRotation))
        stolen =
            signedRotateEvidence
                env
                advanced
                laterRotation
                (rsCurrentSigners laterRotation)
                (aeWitReceipts (rsUnsignedEvidence laterRotation))
        belowThreshold = honest{aeCtrlSigs = take 1 (aeCtrlSigs honest)}
        underWitnessed = honest{aeWitReceipts = take 1 (aeWitReceipts honest)}
        rejected label evidence =
            rejectRotation
                (freezeOp created evidence)
                env
                checkpointRef
                advanceRef
                advanced
                created
                label
    case advancePredicate (rotateSpentCheckpoint env advanced) created honest of
        Left predicateError ->
            fail
                ( "checkpoint Freeze: signed evidence failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    sequence_
        [ rejected "Freeze stolen-current" stolen
        , rejected "Freeze below-successor-threshold" belowThreshold
        , rejected "Freeze under-witnessed" underWitnessed
        ]
    freezeTxId <-
        submitTwoPassRotation
            (freezeOp created honest)
            env
            "checkpoint Freeze"
            checkpointRef
            advanceRef
            advanced
            created
            Nothing
    frozenUtxo <-
        pollOutput
            (envProvider env)
            freezeTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "Freeze successor did not settle"
    settledFreeze env "Freeze" advanced freezeTxId frozenUtxo
    remaining <-
        withinSecs 30 "query frozen checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst (checkpointUtxo advanced)))
    unless (Map.null remaining) $
        fail "Freeze left the advanced checkpoint input unspent"
    dbg ("Freeze settled; tx id=" <> show freezeTxId)

{- | Register the story's identity and land its first rotation with the keep
option: the shared start of the freeze and the deposit journeys, which leaves
the pool below the premium. Returns the checkpoint and observer references and
the settled advanced checkpoint.
-}
advanceOnceForRotationStory ::
    CheckpointEnv ->
    ConvictStoryFixture ->
    IO ((TxIn, TxOut ConwayEra), (TxIn, TxOut ConwayEra), CheckpointInput)
advanceOnceForRotationStory env fixture = do
    let firstRotation = fsFirstRotation fixture
    (registered, checkpointRef) <-
        productionRegisterScenarioWithReference env (rsRegistration firstRotation)
    advanceRef <-
        requireJust
            "observer_advance reference was not deployed during setup"
            (envAdvanceReference env)
    let firstEvidence =
            signedRotateEvidence
                env
                registered
                firstRotation
                (rsRotationSigners firstRotation)
                (aeWitReceipts (rsUnsignedEvidence firstRotation))
    firstAdvanceTxId <-
        submitTwoPassAdvance
            env
            "Freeze setup Advance"
            checkpointRef
            advanceRef
            registered
            (rsCreated firstRotation)
            firstEvidence
    firstAdvancedUtxo <-
        pollOutput
            (envProvider env)
            firstAdvanceTxId
            [0, 1]
            (holdsCheckpointToken env (rsCreated firstRotation))
            >>= requireJust "Freeze setup Advance did not settle"
    advanced <-
        settledAdvance
            env
            "Freeze setup Advance"
            registered
            (rsCreated firstRotation)
            firstAdvanceTxId
            firstAdvancedUtxo
    pure (checkpointRef, advanceRef, advanced)

{- | What a settled freeze left: the successor at the ACTIVE address carrying
the exact frozen datum on the old keys and the minimum ADA, the deposit and the
pool, and the hunter output carrying the freeze bond.
-}
settledFreeze ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    TxId ->
    (TxIn, TxOut ConwayEra) ->
    IO ()
settledFreeze env row before freezeTxId utxo = do
    settlement <-
        requireJust
            (row <> ": the frozen checkpoint was not freezable")
            ( freezeSettlement
                freezeParams
                (checkpointFacts before)
                (unCoin (snd (checkpointUtxo before) ^. coinTxOutL))
            )
    expected <-
        requireJust
            (row <> ": the frozen checkpoint was not live")
            (frozenLive (checkpointFacts before))
    unless
        (snd utxo ^. addrTxOutL == roleAddress env Active)
        (fail (row <> ": successor is not at the ACTIVE address"))
    case extractDatum (snd utxo) of
        Just (V2 facts)
            | facts == expected -> pure ()
        _ -> fail (row <> ": successor does not carry the exact frozen version 2 datum")
    unless
        (unCoin (snd utxo ^. coinTxOutL) == fsSuccessorLovelace settlement)
        (fail (row <> ": successor lovelace is not the minimum ADA, the deposit and the pool"))
    let hunterRef = TxIn freezeTxId (TxIx (fromIntegral premiumOutputIndex))
    hunter <-
        withinSecs 30 (row <> ": query hunter output") $
            queryUTxOByTxIn (envProvider env) (Set.singleton hunterRef)
    case Map.lookup hunterRef hunter of
        Just out
            | unCoin (out ^. coinTxOutL) >= fsHunterPaid settlement -> pure ()
        _ -> fail (row <> ": the hunter output is missing or short of the bond")

productionRegisterConvictScenario :: CheckpointEnv -> IO ()
productionRegisterConvictScenario env = do
    fixture <- loadConvictStoryFixture
    references <- deployRegisterReferences env
    checkpointRef <-
        requireJust "Convict checkpoint reference is absent" (listToMaybe references)
    advanceRef <-
        requireJust
            "observer_advance reference was not deployed during setup"
            (envAdvanceReference env)
    enforcementRef <-
        requireJust
            "observer_enforcement reference was not deployed during setup"
            (envEnforcementReference env)
    let convictor = beneficiaryPkh storyConvictor
        conflict = fsConflictEvidence fixture
        unwitnessed = conflict{eneWitSigs = take 1 (eneWitSigs conflict)}
        recorded = fsRecordedEvidence fixture
    -- #280: a conviction settles only against the convictor's own matured
    -- reservation, opened over the exact evidence it reveals.
    active <-
        prepareConvictActive
            env
            references
            checkpointRef
            advanceRef
            "ACTIVE"
            fixture
    mapM_
        ( \(row, payload, nonceLabel) -> do
            plan <-
                prepareLiveEntitlement
                    env
                    (checkpointUtxo active)
                    payload
                    convictor
                    (commitmentNonce nonceLabel)
            rejectConvictEvidence
                env
                checkpointRef
                enforcementRef
                active
                convictor
                row
                plan
        )
        [ ("Convict unwitnessed conflict", unwitnessed, "151-unwitnessed")
        ,
            ( "Convict generated recorded no-conflict event"
            , recorded
            , "151-recorded-no-conflict"
            )
        ]
    activePlan <-
        prepareLiveEntitlement
            env
            (checkpointUtxo active)
            conflict
            convictor
            (commitmentNonce "151-active-conflict")
    activeTxId <-
        submitTwoPassConvict
            env
            "checkpoint Convict ACTIVE"
            checkpointRef
            enforcementRef
            active
            convictor
            activePlan
    assertConvictSettlement
        env
        "ACTIVE"
        active
        convictor
        activeTxId

prepareConvictActive ::
    CheckpointEnv ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    String ->
    ConvictStoryFixture ->
    IO CheckpointInput
prepareConvictActive env references checkpointRef advanceRef row fixture = do
    let firstRotation = fsFirstRotation fixture
        recordedRotation = fsResponseRotation fixture
    (registered, _) <-
        productionRegisterScenarioUsingReferences
            env
            references
            (rsRegistration firstRotation)
    let firstEvidence =
            signedRotateEvidence
                env
                registered
                firstRotation
                (rsRotationSigners firstRotation)
                (aeWitReceipts (rsUnsignedEvidence firstRotation))
    case advancePredicate
        (rotateSpentCheckpoint env registered)
        (rsCreated firstRotation)
        firstEvidence of
        Left predicateError ->
            fail
                ( "Convict "
                    <> row
                    <> " setup first Advance failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    firstAdvanceTxId <-
        submitTwoPassAdvance
            env
            ("Convict " <> row <> " setup first Advance")
            checkpointRef
            advanceRef
            registered
            (rsCreated firstRotation)
            firstEvidence
    firstAdvancedUtxo <-
        pollOutput
            (envProvider env)
            firstAdvanceTxId
            [0, 1]
            (holdsCheckpointToken env (rsCreated firstRotation))
            >>= requireJust ("Convict " <> row <> " first Advance did not settle")
    firstAdvanced <-
        settledAdvance
            env
            ("Convict " <> row <> " setup first Advance")
            registered
            (rsCreated firstRotation)
            firstAdvanceTxId
            firstAdvancedUtxo
    let recordedEvidence =
            signedRotateEvidence
                env
                firstAdvanced
                recordedRotation
                (rsRotationSigners recordedRotation)
                (aeWitReceipts (rsUnsignedEvidence recordedRotation))
    case advancePredicate
        (rotateSpentCheckpoint env firstAdvanced)
        (rsCreated recordedRotation)
        recordedEvidence of
        Left predicateError ->
            fail
                ( "Convict "
                    <> row
                    <> " setup recorded Advance failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    recordedAdvanceTxId <-
        submitTwoPassAdvance
            env
            ("Convict " <> row <> " setup recorded Advance")
            checkpointRef
            advanceRef
            firstAdvanced
            (rsCreated recordedRotation)
            recordedEvidence
    advancedUtxo <-
        pollOutput
            (envProvider env)
            recordedAdvanceTxId
            [0, 1]
            (holdsCheckpointToken env (rsCreated recordedRotation))
            >>= requireJust ("Convict " <> row <> " ACTIVE source did not settle")
    settledAdvance
        env
        ("Convict " <> row <> " ACTIVE source")
        firstAdvanced
        (rsCreated recordedRotation)
        recordedAdvanceTxId
        advancedUtxo

advanceRejection :: CheckpointEnv -> IO RejectionEvidence
advanceRejection env = do
    prepareWallet (envProvider env) (envSubmitter env) (envOwner env)
    (fixture, _) <- loadLifecycleFixture
    staged <- stageCheckpointInput env (rfDatum fixture)
    validity <- currentValidity env
    tx <-
        buildAdvanceTx
            env
            staged
            (checkpointDatum staged)
            validity
    expectProductionScriptRejection env "Advance" tx

hashProofMintOldCostRejection :: CheckpointEnv -> IO RejectionEvidence
hashProofMintOldCostRejection env = do
    prepareWallet (envProvider env) (envSubmitter env) (envOwner env)
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
    tx <- withinSecs 90 "build old-cost hash-proof mint" (buildHashProofMintTx env (ownerParty env) fixture)
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

{- | Split the genesis wallet into the small outputs the transactions pick from,
the registry's seed output, and the funds of the party that folds.
-}
prepareWallet :: Provider IO -> Submitter IO -> Addr -> IO ()
prepareWallet provider submitter owner = do
    _ <- awaitWalletCount provider owner 1
    splitTx <- withinSecs 60 "build checkpoint wallet split" (buildSplitTx provider owner)
    _ <- submitWith submitter genesisSignKey "checkpoint wallet split" splitTx
    _ <- awaitWalletCount provider owner 5
    pure ()

buildSplitTx :: Provider IO -> Addr -> IO ConwayTx
buildSplitTx provider owner = do
    params <- withinSecs 30 "query protocol parameters" (queryProtocolParams provider)
    wallet <- withinSecs 30 "query wallet for split" (queryUTxOs provider owner)
    input <- requireJust "buildSplitTx: no wallet UTxO" (listToMaybe wallet)
    let small = mkBasicTxOut owner (inject (Coin 20_000_000))
        seedOut = mkBasicTxOut (seedAddress owner) (inject (Coin 20_000_000))
        folderOut = mkBasicTxOut folderAddress (inject (Coin 100_000_000))
        body =
            mkBasicTxBody
                & outputsTxBodyL
                    .~ StrictSeq.fromList
                        [small, small, small, small, seedOut, folderOut, folderOut, folderOut, folderOut]
    either
        (fail . ("buildSplitTx: balance failed: " <>) . show)
        (pure . balancedTx)
        (balanceTx params [input] [] owner (mkBasicTx body))

data RegistrationFixture = RegistrationFixture
    { rfDatum :: !KeyStateView
    , rfEvidence :: !RegistrationEvidence
    , rfRaw :: !ByteString
    , rfAid :: !ByteString
    , rfOffI :: !Integer
    , rfOffD :: !Integer
    , rfProofName :: !ByteString
    }

data RotateStoryFixture = RotateStoryFixture
    { rsRegistration :: !RegistrationFixture
    , rsCreated :: !KeyStateView
    , rsUnsignedEvidence :: !AdvanceEvidence
    , rsRotationSigners :: ![SignKeyDSIGN Ed25519DSIGN]
    , rsCurrentSigners :: ![SignKeyDSIGN Ed25519DSIGN]
    }

data ConvictStoryFixture = ConvictStoryFixture
    { fsFirstRotation :: !RotateStoryFixture
    , fsConflictEvidence :: !EnforcementEvidence
    , fsRecordedEvidence :: !EnforcementEvidence
    , fsResponseRotation :: !RotateStoryFixture
    }

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

loadRotateStoryFixture :: IO RotateStoryFixture
loadRotateStoryFixture = do
    path <- getDataFileName "test/keri-fixtures/fixtures/advance.json"
    root <- eitherDecodeFileStrict path >>= either fail pure
    family <- either fail pure (atKey "adv_wit_2key" root)
    inception <- either fail pure (atKey "icp" family)
    inceptionWithOffsets <- either fail pure (withDerivedOffsets inception)
    inceptionSignatures <-
        either fail pure (indexedSignaturesAt "icp_sigs" family)
    seeds <- either fail pure (atKey "signer_seeds" family)
    outgoingWitnessSigners <-
        either fail pure (signersAt "witness_outgoing" seeds)
    inceptionRaw <-
        either fail pure (textAt "raw_hex" inception >>= decodeHex)
    let inceptionReceipts =
            indexedSignaturesOver inceptionRaw outgoingWitnessSigners
    registration <-
        either fail pure $
            registrationFixtureFrom
                inceptionWithOffsets
                inceptionSignatures
                inceptionReceipts
    rotation <- either fail pure (atKey "rot" family)
    rotationKed <- either fail pure (atKey "ked" rotation)
    offsets <- either fail pure (atKey "offsets" family)
    raw <- either fail pure (textAt "raw_hex" rotation >>= decodeHex)
    currentKeys <-
        either fail pure $
            textArrayAt "k" rotationKed >>= traverse verkeyRaw
    nextKeys <-
        either fail pure $
            textArrayAt "n" rotationKed >>= traverse digestRaw
    oldWitnesses <-
        either fail pure $
            atKey "ked" inception
                >>= textArrayAt "b"
                >>= traverse verkeyRaw
    cuts <-
        either fail pure $
            textArrayAt "br" rotationKed >>= traverse verkeyRaw
    adds <-
        either fail pure $
            textArrayAt "ba" rotationKed >>= traverse verkeyRaw
    currentThreshold <- either fail pure (thresholdAt "kt" rotationKed)
    nextThreshold <- either fail pure (thresholdAt "nt" rotationKed)
    toad <- either fail pure (hexIntegerAt "bt" rotationKed)
    nativeSn <- either fail pure (hexIntegerAt "s" rotationKed)
    rotationSigners <-
        either fail pure (signersAt "rotation_current" seeds)
    currentSigners <-
        either fail pure (signersAt "inception_current" seeds)
    witnessReceipts <-
        either fail pure (indexedSignaturesAt "rot_witness_receipts" family)
    let created =
            KeyStateView
                { cdCesrAid = cdCesrAid (rfDatum registration)
                , cdCurKeys = currentKeys
                , cdCurThreshold = currentThreshold
                , cdNextKeys = nextKeys
                , cdNextThreshold = nextThreshold
                , cdWitnesses = filter (`notElem` cuts) oldWitnesses <> adds
                , cdToad = toad
                , cdSeq = cdSeq (rfDatum registration) + 1
                , cdNativeSn = nativeSn
                }
        unsignedEvidence =
            AdvanceEvidence
                { aeEventBytes = raw
                , aeOffT = fromInteger (offset "t" offsets)
                , aeOffI = fromInteger (offset "i" offsets)
                , aeOffS = fromInteger (offset "s" offsets)
                , aeOffK = map fromInteger (offsetsAt "k" offsets)
                , aeOffKt = fromInteger (offset "kt" offsets)
                , aeOffN = map fromInteger (offsetsAt "n" offsets)
                , aeOffNt = fromInteger (offset "nt" offsets)
                , aeOffBr = map fromInteger (offsetsAt "br" offsets)
                , aeOffBa = map fromInteger (offsetsAt "ba" offsets)
                , aeOffBt = fromInteger (offset "bt" offsets)
                , aeWitCut = cuts
                , aeWitAdd = adds
                , aeCtrlSigs = []
                , aeWitReceipts = witnessReceipts
                }
    pure
        RotateStoryFixture
            { rsRegistration = registration
            , rsCreated = created
            , rsUnsignedEvidence = unsignedEvidence
            , rsRotationSigners = rotationSigners
            , rsCurrentSigners = currentSigners
            }
  where
    signersAt key value =
        atKey key value
            >>= arrayValues
            >>= traverse
                ( \entry ->
                    textAt "seed_hex" entry
                        >>= decodeHex
                        <&> genKeyDSIGN . mkSeedFromBytes
                )
    offset key value =
        either
            (error . ("loadRotateStoryFixture: " <>))
            id
            (integerAt key value)
    offsetsAt key value =
        either
            (error . ("loadRotateStoryFixture: " <>))
            id
            (integerArrayAt key value)

loadConvictStoryFixture :: IO ConvictStoryFixture
loadConvictStoryFixture = do
    path <- getDataFileName "test/keri-fixtures/fixtures/freeze_story.json"
    root <- eitherDecodeFileStrict path >>= either fail pure
    inception <- either fail pure (atKey "icp" root)
    inceptionWithOffsets <- either fail pure (withDerivedOffsets inception)
    inceptionSignatures <- either fail pure (indexedSignaturesAt "icp_sigs" root)
    inceptionReceipts <-
        either fail pure (indexedSignaturesAt "icp_witness_receipts" root)
    registration <-
        either fail pure $
            registrationFixtureFrom
                inceptionWithOffsets
                inceptionSignatures
                inceptionReceipts
    seeds <- either fail pure (atKey "signer_seeds" root)
    inceptionSigners <-
        either fail pure (seedSignersAt "inception_current" seeds)
    firstSigners <-
        either fail pure (seedSignersAt "rotation_1_current" seeds)
    responseSigners <-
        either fail pure (seedSignersAt "rotation_2_current" seeds)
    firstRecord <- either fail pure (atKey "rot_1" root)
    first <-
        either fail pure $
            rotateStoryFrom
                registration
                (rfDatum registration)
                firstRecord
                firstSigners
                inceptionSigners
    conflictRecord <- either fail pure (atKey "rot_2_conflict" root)
    conflictEvent <- either fail pure (atKey "event" conflictRecord)
    conflictWithOffsets <- either fail pure (withDerivedOffsets conflictEvent)
    conflictSignatures <-
        either fail pure (indexedSignaturesAt "controller_sigs" conflictRecord)
    conflictReceipts <-
        either fail pure (indexedSignaturesAt "witness_receipts" conflictRecord)
    unsignedConflict <-
        either fail pure $
            enforcementEvidenceFrom conflictWithOffsets conflictSignatures
    let conflictEvidence = unsignedConflict{eneWitSigs = conflictReceipts}
    responseRecord <- either fail pure (atKey "rot_2_recorded" root)
    responseEvent <- either fail pure (atKey "event" responseRecord)
    responseWithOffsets <- either fail pure (withDerivedOffsets responseEvent)
    responseControllerSignatures <-
        either fail pure (indexedSignaturesAt "controller_sigs" responseRecord)
    responseReceipts <-
        either fail pure (indexedSignaturesAt "witness_receipts" responseRecord)
    unsignedRecorded <-
        either fail pure $
            enforcementEvidenceFrom
                responseWithOffsets
                responseControllerSignatures
    let recordedEvidence =
            unsignedRecorded{eneWitSigs = responseReceipts}
    response <-
        either fail pure $
            rotateStoryFrom
                registration
                (rsCreated first)
                responseRecord
                responseSigners
                firstSigners
    pure
        ConvictStoryFixture
            { fsFirstRotation = first
            , fsConflictEvidence = conflictEvidence
            , fsRecordedEvidence = recordedEvidence
            , fsResponseRotation = response
            }

rotateStoryFrom ::
    RegistrationFixture ->
    KeyStateView ->
    Value ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    Either String RotateStoryFixture
rotateStoryFrom registration prior record rotationSigners currentSigners = do
    event <- atKey "event" record
    ked <- atKey "ked" event
    offsets <- atKey "offsets" event
    raw <- textAt "raw_hex" event >>= decodeHex
    currentKeys <- textArrayAt "k" ked >>= traverse verkeyRaw
    nextKeys <- textArrayAt "n" ked >>= traverse digestRaw
    cuts <- textArrayAt "br" ked >>= traverse verkeyRaw
    adds <- textArrayAt "ba" ked >>= traverse verkeyRaw
    currentThreshold <- thresholdAt "kt" ked
    nextThreshold <- thresholdAt "nt" ked
    toad <- hexIntegerAt "bt" ked
    nativeSn <- hexIntegerAt "s" ked
    witnessReceipts <- indexedSignaturesAt "witness_receipts" record
    let created =
            KeyStateView
                { cdCesrAid = cdCesrAid prior
                , cdCurKeys = currentKeys
                , cdCurThreshold = currentThreshold
                , cdNextKeys = nextKeys
                , cdNextThreshold = nextThreshold
                , cdWitnesses =
                    filter (`notElem` cuts) (cdWitnesses prior) <> adds
                , cdToad = toad
                , cdSeq = cdSeq prior + 1
                , cdNativeSn = nativeSn
                }
        unsignedEvidence =
            AdvanceEvidence
                { aeEventBytes = raw
                , aeOffT = intOffset "t" offsets
                , aeOffI = intOffset "i" offsets
                , aeOffS = intOffset "s" offsets
                , aeOffK = intOffsets "k" offsets
                , aeOffKt = intOffset "kt" offsets
                , aeOffN = intOffsets "n" offsets
                , aeOffNt = intOffset "nt" offsets
                , aeOffBr = intOffsets "br" offsets
                , aeOffBa = intOffsets "ba" offsets
                , aeOffBt = intOffset "bt" offsets
                , aeWitCut = cuts
                , aeWitAdd = adds
                , aeCtrlSigs = []
                , aeWitReceipts = witnessReceipts
                }
    pure
        RotateStoryFixture
            { rsRegistration = registration
            , rsCreated = created
            , rsUnsignedEvidence = unsignedEvidence
            , rsRotationSigners = rotationSigners
            , rsCurrentSigners = currentSigners
            }
  where
    intOffset key value =
        fromInteger $
            either
                (error . ("rotateStoryFrom: " <>))
                id
                (integerAt key value)
    intOffsets key value =
        map fromInteger $
            either
                (error . ("rotateStoryFrom: " <>))
                id
                (integerArrayAt key value)

seedSignersAt ::
    Text ->
    Value ->
    Either String [SignKeyDSIGN Ed25519DSIGN]
seedSignersAt key value =
    atKey key value
        >>= arrayValues
        >>= traverse
            ( \entry ->
                textAt "seed_hex" entry
                    >>= decodeHex
                    <&> genKeyDSIGN . mkSeedFromBytes
            )

indexedSignaturesOver ::
    ByteString ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    [(Int, ByteString)]
indexedSignaturesOver message signers =
    [ (index, rawSerialiseSigDSIGN (signDSIGN () message signer))
    | (index, signer) <- zip [0 ..] signers
    ]

rotateSpentCheckpoint ::
    CheckpointEnv ->
    CheckpointInput ->
    SpentCheckpoint
rotateSpentCheckpoint env input =
    case fst (checkpointUtxo input) of
        TxIn (TxId safeHash) (TxIx outputIndex) ->
            SpentCheckpoint
                { scNetworkId = 0
                , scPolicyId = policyBytes (envCheckpointPolicy env)
                , scAidAssetName =
                    deriveAidAssetName (cdCesrAid (checkpointDatum input))
                , scTxid = hashToBytes (extractHash safeHash)
                , scIndex = fromIntegral outputIndex
                , scCesrAid = cdCesrAid (checkpointDatum input)
                , scWitnesses = cdWitnesses (checkpointDatum input)
                , scNextKeys = cdNextKeys (checkpointDatum input)
                , scNextThreshold = cdNextThreshold (checkpointDatum input)
                , scSeq = cdSeq (checkpointDatum input)
                , scNativeSn = cdNativeSn (checkpointDatum input)
                }

{- | #219: 'aeCtrlSigs' sign the KERI event's own bytes directly, not a
reconstructed Cardano-domain message preimage.
-}
signedRotateEvidence ::
    CheckpointEnv ->
    CheckpointInput ->
    RotateStoryFixture ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    [(Int, ByteString)] ->
    AdvanceEvidence
signedRotateEvidence _env _input fixture signers receipts =
    unsigned
        { aeCtrlSigs = indexedSignaturesOver (aeEventBytes unsigned) signers
        , aeWitReceipts = receipts
        }
  where
    unsigned = rsUnsignedEvidence fixture

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
            KeyStateView
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
    CheckpointEnv -> Party -> RegistrationFixture -> IO ConwayTx
buildHashProofMintTx env party fixture = do
    unless (blake3Hash (saidBlank fixture) == rfAid fixture) $
        fail "registration fixture does not satisfy the production hash-proof SAID binding"
    params <- withinSecs 30 "query hash-proof protocol parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query hash-proof wallet" (queryUTxOs (envProvider env) (partyAddr party))
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
                (partyAddr party)
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
            (partyAddr party)
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

{- | The datum a registration writes: the fixture's key state born at the end of
the validity interval, refunding the registering wallet.
-}
registeredFacts :: CheckpointEnv -> RegistrationFixture -> ValidityPlan -> CheckpointDatumV2
registeredFacts env fixture validity =
    liveOfKeyState (serialiseAddr (envOwner env)) (upperPosixMs validity) (rfDatum fixture)

{- | What differs between the transactions that present a rotation to the
rotation observer: an Advance writes the rotated datum and pays the premium, a
Freeze writes the frozen datum and pays the freeze bond.
-}
data RotationOp = RotationOp
    { roSettle ::
        CheckpointInput ->
        KeyStateView ->
        IO (CheckpointDatumV2, Integer, Integer)
    {- ^ the successor datum, the lovelace it holds, and the lovelace the
    second output receives (none when zero)
    -}
    , roSpendRedeemer :: PLC.Data
    , roObserverRedeemer :: ByteString -> ByteString -> Integer -> PLC.Data
    -- ^ from the checkpoint policy and the spent output
    }

-- | The Advance of a checkpoint on this rotation evidence.
advanceOp :: AdvanceEvidence -> RotationOp
advanceOp evidence =
    RotationOp
        { roSettle = \input successor -> do
            settlement <-
                requireJust
                    "Advance: the checkpoint is not a live output holding its floor"
                    ( rotationSettlement
                        checkpointMinAda
                        registrationBond
                        freezeBond
                        premium
                        (checkpointFacts input)
                        (unCoin (snd (checkpointUtxo input) ^. coinTxOutL))
                    )
            successorFacts <-
                requireJust
                    "Advance: the checkpoint is not live"
                    (rotatedLive (checkpointFacts input) successor)
            pure
                ( successorFacts
                , heldValue
                    checkpointMinAda
                    registrationBond
                    freezeBond
                    successorFacts
                    (settlementPoolAfter settlement)
                , settlementPaid settlement
                )
        , roSpendRedeemer = advanceSpendRedeemerData premiumOutputIndex Keep
        , roObserverRedeemer = \policy txid index ->
            advanceObserverRedeemerData policy txid index evidence
        }

-- | The Freeze of a checkpoint on this rotated key state and its evidence.
freezeOp :: KeyStateView -> AdvanceEvidence -> RotationOp
freezeOp rotated evidence =
    RotationOp
        { roSettle = \input _ -> do
            let facts = checkpointFacts input
            settlement <-
                requireJust
                    "Freeze: the checkpoint cannot be frozen"
                    ( freezeSettlement
                        freezeParams
                        facts
                        (unCoin (snd (checkpointUtxo input) ^. coinTxOutL))
                    )
            successorFacts <-
                requireJust "Freeze: the checkpoint is not live" (frozenLive facts)
            pure
                ( successorFacts
                , fsSuccessorLovelace settlement
                , fsHunterPaid settlement
                )
        , roSpendRedeemer = freezeSpendRedeemerData premiumOutputIndex
        , roObserverRedeemer = \policy txid index ->
            freezeObserverRedeemerData
                policy
                txid
                index
                FreezeEvidence
                    { feRotatedKeys = keyMaterialOf rotated
                    , feRotatedSn = cdNativeSn rotated
                    , feRotation = evidence
                    }
        }

{- | The Deposit of a frozen checkpoint on this rotation evidence, with the
signatures of the rotation's new keys over the deposit intent: the rotated
datum unfrozen, holding the minimum ADA, the deposit, the freeze bond and the
pool that is left after the premium.
-}
depositOp :: AdvanceEvidence -> [(Int, ByteString)] -> RotationOp
depositOp evidence signatures =
    RotationOp
        { roSettle = \input successor -> do
            settlement <-
                requireJust
                    "Deposit: the checkpoint is not a live output holding its floor"
                    ( rotationSettlement
                        checkpointMinAda
                        registrationBond
                        freezeBond
                        premium
                        (checkpointFacts input)
                        (unCoin (snd (checkpointUtxo input) ^. coinTxOutL))
                    )
            rotated <-
                requireJust
                    "Deposit: the checkpoint is not live"
                    (rotatedLive (checkpointFacts input) successor)
            let successorFacts = case rotated of
                    live@Live{} -> live{lvFrozen = False}
                    other -> other
            pure
                ( successorFacts
                , heldValue
                    checkpointMinAda
                    registrationBond
                    freezeBond
                    successorFacts
                    (settlementPoolAfter settlement)
                , settlementPaid settlement
                )
        , roSpendRedeemer = advanceSpendRedeemerData premiumOutputIndex (Deposit signatures)
        , roObserverRedeemer = \policy txid index ->
            advanceObserverRedeemerData policy txid index evidence
        }

freezeParams :: FreezeParams
freezeParams =
    FreezeParams
        { fpMinAda = checkpointMinAda
        , fpDeposit = registrationBond
        , fpBond = freezeBond
        , fpPremium = premium
        }

buildRotationTxWith ::
    RotationOp ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    KeyStateView ->
    Maybe ValidityPlan ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildRotationTxWith op budgets env checkpointRef advanceRef input successor validity = do
    params <-
        withinSecs 30 "query Advance protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Advance wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef, fst advanceRef]
    (successorFacts, successorLovelace, payeeLovelace) <-
        roSettle op input successor
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        spendPurpose = ConwaySpending (AsIx stateIndex)
        rewardPurpose = ConwayRewarding (AsIx 0)
        expected = Set.fromList [spendPurpose, rewardPurpose]
        observerRedeemerData =
            roObserverRedeemer
                op
                (policyBytes (envCheckpointPolicy env))
                spentTxIdBytes
                spentIndex
        stateOut =
            mkStateOutput
                env
                Active
                ( withLovelace
                    successorLovelace
                    (snd (checkpointUtxo input) ^. valueTxOutL)
                )
                (asPlcData (V2 successorFacts))
        -- The premium or bond payee is the second output.
        premiumOuts =
            [ mkBasicTxOut (envOwner env) (inject (Coin payeeLovelace))
            | payeeLovelace > 0
            ]
        -- What the successor and the payee hold beyond the spent output comes
        -- from the fee input: nothing for an Advance or a Freeze, the freeze
        -- bond for a deposit on a frozen checkpoint.
        inflow =
            successorLovelace
                + payeeLovelace
                - unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (-(scriptFee + inflow)) (feeOut ^. valueTxOutL))
        redeemers =
            Redeemers $
                Map.fromList
                    [
                        ( spendPurpose
                        ,
                            ( ledgerData (roSpendRedeemer op)
                            , Map.findWithDefault
                                advanceSpendExUnits
                                spendPurpose
                                budgets
                            )
                        )
                    ,
                        ( rewardPurpose
                        ,
                            ( ledgerData observerRedeemerData
                            , Map.findWithDefault
                                scriptExUnits
                                rewardPurpose
                                budgets
                            )
                        )
                    ]
        baseBody =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList ([stateOut] <> premiumOuts <> [changeOut])
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
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & referenceInputsTxBodyL
                    .~ Set.fromList [fst checkpointRef, fst advanceRef]
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
        body =
            maybe
                baseBody
                ( \plan ->
                    baseBody
                        & vldtTxBodyL
                            .~ ValidityInterval
                                (SJust (lowerSlot plan))
                                (SJust (upperSlot plan))
                )
                validity
    pure
        ( mkBasicTx body
            & witsTxL . rdmrsTxWitsL .~ redeemers
        , expected
        )
  where
    stateIn = fst (checkpointUtxo input)
    (spentTxIdBytes, spentIndex) =
        case stateIn of
            TxIn (TxId safeHash) (TxIx outputIndex) ->
                ( hashToBytes (extractHash safeHash)
                , fromIntegral outputIndex
                )

advanceSpendExUnits :: ExUnits
advanceSpendExUnits = ExUnits 2_000_000 1_000_000_000

buildConvictStoryTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    EntitledEnforcementPlan ->
    ValidityPlan ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildConvictStoryTxWith budgets env checkpointRef enforcementRef reservation input convictor plan validity = do
    entitlementRef <-
        requireJust
            "observer_entitlement reference was not deployed during setup"
            (envEntitlementReference env)
    commitmentRef <-
        requireJust
            "bounty_commitment reference was not deployed during setup"
            (envCommitmentReference env)
    unless (eepBountyPayee plan == convictor) $
        fail "Convict envelope does not name the convictor this settlement pays"
    unless (cpoIndex (eepRefund plan) == settlementRefundIndex) $
        fail "Convict reservation refund is not planned at the settlement index"
    params <-
        withinSecs 30 "query Convict protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Convict wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint
            wallet
            [ stateIn
            , reservationIn
            , fst checkpointRef
            , fst enforcementRef
            , fst entitlementRef
            , fst commitmentRef
            ]
    pendingFacts <-
        requireJust
            "Convict: the checkpoint is not live"
            (convictedOf (checkpointFacts input))
    _ <-
        requireJust
            "Convict: the checkpoint holds less than its floor"
            ( withValue
                checkpointMinAda
                registrationBond
                freezeBond
                (checkpointFacts input)
                (unCoin (snd (checkpointUtxo input) ^. coinTxOutL))
            )
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, reservationIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        spendPurpose = ConwaySpending (AsIx stateIndex)
        revealPurpose =
            ConwaySpending (AsIx (spendingIndex reservationIn allInputs))
        (withdrawalMap, enforcementPurpose, entitlementPurpose) =
            observerWithdrawals env
        expected =
            Set.fromList
                [ retirePurpose
                , spendPurpose
                , revealPurpose
                , enforcementPurpose
                , entitlementPurpose
                ]
        markerName = AssetName (SBS.toShort (fst (eepBurn plan)))
        minted =
            MultiAsset $
                Map.singleton
                    (envCommitmentPolicy env)
                    (Map.singleton markerName (snd (eepBurn plan)))
        retirePurpose =
            ConwayMinting (AsIx (mintingIndex (envCommitmentPolicy env) minted))
        -- #280: the deposit refund sits at output zero for every settlement
        -- shape, so the payouts the register indexes shift one place along.
        refundOut =
            mkBasicTxOut
                (keyAddress (cpoRecipientPkh (eepRefund plan)))
                (inject (Coin (cpoLovelace (eepRefund plan))))
        convictorOutputIndex = 1
        -- What the pending termination and the convictor do not take: the
        -- bond (unless frozen) and the pool.
        refundLovelace =
            unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
                - checkpointMinAda
                - registrationBond
        -- The pending termination keeps the token at the checkpoint address and
        -- holds the minimum ADA; the convictor receives the deposit; the bond
        -- and the pool go to the refund address the datum committed.
        pendingOut =
            mkStateOutput
                env
                Active
                ( MaryValue
                    (Coin checkpointMinAda)
                    (let MaryValue _ assets = snd (checkpointUtxo input) ^. valueTxOutL in assets)
                )
                (asPlcData (V2 pendingFacts))
        convictorOut =
            mkBasicTxOut
                (keyAddress convictor)
                (inject (Coin registrationBond))
        refundToOut =
            mkBasicTxOut
                (envOwner env)
                (inject (Coin refundLovelace))
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (-scriptFee) (feeOut ^. valueTxOutL))
        outputs = [refundOut, convictorOut, pendingOut, refundToOut, changeOut]
        observerRedeemer =
            ledgerData
                ( convictObserverRedeemerData
                    (policyBytes (envCheckpointPolicy env))
                    spentTxIdBytes
                    spentIndex
                    (eepProof plan)
                )
        redeemers =
            Redeemers $
                Map.fromList
                    [
                        ( retirePurpose
                        ,
                            ( ledgerData (asPlcData Retire)
                            , Map.findWithDefault
                                commitmentExUnits
                                retirePurpose
                                budgets
                            )
                        )
                    ,
                        ( spendPurpose
                        ,
                            ( ledgerData
                                ( convictSpendRedeemerData
                                    convictor
                                    convictorOutputIndex
                                )
                            , Map.findWithDefault
                                (ExUnits 2_000_000 1_200_000_000)
                                spendPurpose
                                budgets
                            )
                        )
                    ,
                        ( revealPurpose
                        ,
                            ( ledgerData (asPlcData (Reveal (eepReveal plan)))
                            , Map.findWithDefault
                                commitmentExUnits
                                revealPurpose
                                budgets
                            )
                        )
                    ,
                        ( enforcementPurpose
                        ,
                            ( observerRedeemer
                            , Map.findWithDefault
                                (ExUnits 13_000_000 8_000_000_000)
                                enforcementPurpose
                                budgets
                            )
                        )
                    ,
                        ( entitlementPurpose
                        ,
                            ( observerRedeemer
                            , Map.findWithDefault
                                (ExUnits 13_000_000 8_000_000_000)
                                entitlementPurpose
                                budgets
                            )
                        )
                    ]
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList outputs
                & feeTxBodyL .~ Coin scriptFee
                & mintTxBodyL .~ minted
                & withdrawalsTxBodyL .~ Withdrawals withdrawalMap
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & referenceInputsTxBodyL
                    .~ Set.fromList
                        [ fst checkpointRef
                        , fst enforcementRef
                        , fst entitlementRef
                        , fst commitmentRef
                        ]
                & reqSignerHashesTxBodyL
                    .~ Set.fromList
                        (map requiredSignerHash (eepRequiredSigners plan))
                & vldtTxBodyL
                    .~ ValidityInterval
                        (SJust (lowerSlot validity))
                        (SJust (upperSlot validity))
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
    pure
        ( mkBasicTx body
            & witsTxL . rdmrsTxWitsL .~ redeemers
        , expected
        )
  where
    stateIn = fst (checkpointUtxo input)
    reservationIn = fst reservation
    (spentTxIdBytes, spentIndex) =
        case stateIn of
            TxIn (TxId safeHash) (TxIx outputIndex) ->
                ( hashToBytes (extractHash safeHash)
                , fromIntegral outputIndex
                )

rejectConvictEvidence ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    String ->
    EntitledEnforcementPlan ->
    IO ()
rejectConvictEvidence env checkpointRef enforcementRef input convictor label plan = do
    (reservation, resolved) <- liveReservation env label plan
    validity <- entitledSettlementValidity env label resolved
    payeeKey <- beneficiarySignKey label (eepBountyPayee plan)
    (candidate, expected) <-
        withinSecs 90 (label <> ": build evaluation-only candidate") $
            buildConvictStoryTxWith
                Map.empty
                env
                checkpointRef
                enforcementRef
                reservation
                input
                convictor
                plan
                validity
    observed <-
        withinSecs 120 (label <> ": evaluate without submission") $
            evaluateTx
                (envProvider env)
                (addKeyWitness payeeKey (addKeyWitness genesisSignKey candidate))
    unless (Map.keysSet observed == expected) $
        fail
            ( label
                <> ": unexpected evaluator purpose set: "
                <> show (Map.keysSet observed)
            )
    assertEnforcementAttribution env label observed
    dbg
        ( label
            <> " rejected by evaluation without submission; tx id="
            <> show (txIdTx candidate)
            <> "; outcomes="
            <> show observed
        )

{- | A negative evidence row must fail where it claims to.

Each such row opens its own reservation over its own evidence digest, so the
entitlement observer has to ACCEPT it and the enforcement observer has to
REJECT it.  Asserting both halves keeps the row attributable: otherwise a
reservation bound to the wrong digest would reject the transaction for a reason
the row never meant to exercise, and the story would still look green.
-}
assertEnforcementAttribution ::
    CheckpointEnv ->
    String ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) (Either a b) ->
    IO ()
assertEnforcementAttribution env label observed = do
    let (_, enforcementPurpose, entitlementPurpose) = observerWithdrawals env
        outcome purpose =
            case Map.lookup purpose observed of
                Just (Right _) -> Just True
                Just (Left _) -> Just False
                Nothing -> Nothing
    unless (outcome entitlementPurpose == Just True) $
        fail
            ( label
                <> ": the entitlement observer did not accept this row's own\
                   \ matured reservation, so its rejection is not attributable\
                   \ to the evidence under test"
            )
    unless (outcome enforcementPurpose == Just False) $
        fail
            ( label
                <> ": the enforcement observer did not reject this evidence"
            )

submitTwoPassConvict ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    EntitledEnforcementPlan ->
    IO TxId
submitTwoPassConvict env label checkpointRef enforcementRef input convictor plan = do
    (reservation, resolved) <- liveReservation env label plan
    validity <- entitledSettlementValidity env label resolved
    payeeKey <- beneficiarySignKey label (eepBountyPayee plan)
    let sign = addKeyWitness payeeKey . addKeyWitness genesisSignKey
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildConvictStoryTxWith
                Map.empty
                env
                checkpointRef
                enforcementRef
                reservation
                input
                convictor
                plan
                validity
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (sign discovery)
    discoveryUnits <-
        requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    (final, finalExpected) <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildConvictStoryTxWith
                finalBudgets
                env
                checkpointRef
                enforcementRef
                reservation
                input
                convictor
                plan
                validity
    unless (finalExpected == expected) $
        fail (label <> ": final purpose set changed after budget binding")
    let signedFinal = sign final
        finalBytes = serialize (eraProtVerLow @ConwayEra) signedFinal
    finalObserved <-
        withinSecs 120 (label <> ": evaluate final binding") $
            evaluateTx (envProvider env) signedFinal
    finalUnits <-
        requireExactAllRight (label <> ": final") expected finalObserved
    mapM_
        ( \(purpose, observed) ->
            let declared = Map.findWithDefault (ExUnits 0 0) purpose finalBudgets
             in unless (withinDeclared observed declared) $
                    fail
                        ( label
                            <> ": observed units exceed final declaration for "
                            <> show purpose
                        )
        )
        (Map.toList finalUnits)
    params <-
        withinSecs 30 (label <> ": query final maximum") $
            queryProtocolParams (envProvider env)
    let aggregate = foldr addExUnits (ExUnits 0 0) (Map.elems finalBudgets)
        maximumUnits = params ^. ppMaxTxExUnitsL
    unless (withinDeclared aggregate maximumUnits) $
        fail
            ( label
                <> ": aggregate declared exunits exceed ppMaxTxExUnits: "
                <> show aggregate
            )
    dbg
        ( label
            <> ": source-input="
            <> show (fst (checkpointUtxo input))
            <> "; two-pass final bytes="
            <> show (BSL.length finalBytes)
            <> "; observed="
            <> show finalUnits
            <> "; declared="
            <> show finalBudgets
        )
    result <-
        withinSecs 60 ("submit unchanged " <> label) $
            submitTx (envSubmitter env) signedFinal
    case result of
        Submitted txId -> pure txId
        Rejected reason -> fail (label <> " rejected: " <> B8.unpack reason)

rejectRotateEvidence ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    KeyStateView ->
    String ->
    AdvanceEvidence ->
    IO ()
rejectRotateEvidence env checkpointRef advanceRef input successor label evidence =
    rejectRotation (advanceOp evidence) env checkpointRef advanceRef input successor label

rejectRotation ::
    RotationOp ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    KeyStateView ->
    String ->
    IO ()
rejectRotation op env checkpointRef advanceRef input successor label = do
    (candidate, _) <-
        withinSecs 90 (label <> ": build applied candidate") $
            buildRotationTxWith
                op
                Map.empty
                env
                checkpointRef
                advanceRef
                input
                successor
                Nothing
    _ <- expectProductionScriptRejection env label candidate
    pure ()

submitTwoPassAdvance ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    KeyStateView ->
    AdvanceEvidence ->
    IO TxId
submitTwoPassAdvance env label checkpointRef advanceRef input successor evidence =
    submitTwoPassRotation
        (advanceOp evidence)
        env
        label
        checkpointRef
        advanceRef
        input
        successor
        Nothing

submitTwoPassRotation ::
    RotationOp ->
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    KeyStateView ->
    Maybe ValidityPlan ->
    IO TxId
submitTwoPassRotation op env label checkpointRef advanceRef input successor validity =
    submitTwoPassWith env label $ \budgets ->
        buildRotationTxWith
            op
            budgets
            env
            checkpointRef
            advanceRef
            input
            successor
            validity

{- | Build a transaction twice: once with no execution budget to discover the
units each script needs, once with those units and a margin declared; submit
the second unchanged. The builder is given the budgets by purpose.
-}
submitTwoPassWith ::
    CheckpointEnv ->
    String ->
    ( Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
      IO (ConwayTx, Set.Set (ConwayPlutusPurpose AsIx ConwayEra))
    ) ->
    IO TxId
submitTwoPassWith env = submitTwoPassBy (ownerParty env) env

submitTwoPassBy ::
    Party ->
    CheckpointEnv ->
    String ->
    ( Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
      IO (ConwayTx, Set.Set (ConwayPlutusPurpose AsIx ConwayEra))
    ) ->
    IO TxId
submitTwoPassBy party env label build = do
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            build Map.empty
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness (partyKey party) discovery)
    discoveryUnits <-
        requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    (final, finalExpected) <-
        withinSecs 90 (label <> ": rebuild final binding") $
            build finalBudgets
    unless (finalExpected == expected) $
        fail (label <> ": final purpose set changed after budget binding")
    let signedFinal = addKeyWitness (partyKey party) final
        finalBytes = serialize (eraProtVerLow @ConwayEra) signedFinal
    finalObserved <-
        withinSecs 120 (label <> ": evaluate final binding") $
            evaluateTx (envProvider env) signedFinal
    finalUnits <-
        requireExactAllRight (label <> ": final") expected finalObserved
    mapM_
        ( \(purpose, observed) ->
            let declared = Map.findWithDefault (ExUnits 0 0) purpose finalBudgets
             in unless (withinDeclared observed declared) $
                    fail
                        ( label
                            <> ": observed units exceed final declaration for "
                            <> show purpose
                        )
        )
        (Map.toList finalUnits)
    params <-
        withinSecs 30 (label <> ": query final maximum") $
            queryProtocolParams (envProvider env)
    let aggregate = foldr addExUnits (ExUnits 0 0) (Map.elems finalBudgets)
        maximumUnits = params ^. ppMaxTxExUnitsL
    unless (withinDeclared aggregate maximumUnits) $
        fail
            ( label
                <> ": aggregate declared exunits exceed ppMaxTxExUnits: "
                <> show aggregate
            )
    dbg
        ( label
            <> ": two-pass final bytes="
            <> show (BSL.length finalBytes)
            <> " observed="
            <> show finalUnits
            <> " declared="
            <> show finalBudgets
        )
    result <-
        withinSecs 60 ("submit unchanged " <> label) $
            submitTx (envSubmitter env) signedFinal
    case result of
        Submitted txId -> pure txId
        Rejected reason -> fail (label <> " rejected: " <> B8.unpack reason)

deterministicMargin :: ExUnits -> ExUnits
deterministicMargin (ExUnits memory steps) =
    ExUnits (bump memory) (bump steps)
  where
    bump value = value + max 1 ((value + 9) `div` 10)

addExUnits :: ExUnits -> ExUnits -> ExUnits
addExUnits (ExUnits memoryA stepsA) (ExUnits memoryB stepsB) =
    ExUnits (memoryA + memoryB) (stepsA + stepsB)

withinDeclared :: ExUnits -> ExUnits -> Bool
withinDeclared (ExUnits memory steps) (ExUnits declaredMemory declaredSteps) =
    memory <= declaredMemory && steps <= declaredSteps

requireExactAllRight ::
    (Show failure) =>
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
                <> ": unexpected evaluator purpose set: "
                <> show (Map.keysSet observed)
            )
    Map.traverseWithKey
        ( \purpose outcome -> case outcome of
            Right units -> pure units
            Left failure ->
                fail
                    ( label
                        <> ": failed purpose "
                        <> show purpose
                        <> ": "
                        <> show failure
                    )
        )
        observed

{- | The old-cost devnet cannot create the hash-proof input required for a
real Register.  This deliberately tokenless output is therefore used only for
the independent Advance negative staging check below; it is never a
substitute for the blocked positive Register lineage.
-}
stageCheckpointInput ::
    CheckpointEnv -> KeyStateView -> IO CheckpointInput
stageCheckpointInput env datum = do
    let facts = liveOfKeyState (serialiseAddr (envOwner env)) 0 datum
    params <- withinSecs 30 "query staging protocol parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query staging wallet" (queryUTxOs (envProvider env) (envOwner env))
    feeUtxo <- requireJust "stageCheckpointInput: no wallet UTxO" (largestFirst wallet)
    let stagedOut =
            mkBasicTxOut
                (roleAddress env Active)
                (inject (Coin (checkpointMinAda + registrationBond + freezeBond)))
                & datumTxOutL .~ mkInlineDatum (asPlcData (V2 facts))
        tx = mkBasicTx (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton stagedOut)
    balanced <-
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
        "manual ACTIVE checkpoint input has no production token lineage; only Advance rejection is asserted"
    pure
        CheckpointInput
            { checkpointUtxo = utxo
            , checkpointDatum = datum
            , checkpointFacts = facts
            }

buildAdvanceTx ::
    CheckpointEnv ->
    CheckpointInput ->
    KeyStateView ->
    ValidityPlan ->
    IO ConwayTx
buildAdvanceTx env input successor validity = do
    successorFacts <-
        requireJust
            "Advance: the checkpoint is not live"
            (rotatedLive (checkpointFacts input) successor)
    buildCheckpointSpend
        env
        input
        (advanceSpendRedeemerData premiumOutputIndex Keep)
        validity
        [ mkStateOutput
            env
            Active
            (snd (checkpointUtxo input) ^. valueTxOutL)
            (asPlcData (V2 successorFacts))
        ]
        0

buildCheckpointSpend ::
    CheckpointEnv ->
    CheckpointInput ->
    PLC.Data ->
    ValidityPlan ->
    [TxOut ConwayEra] ->
    Integer ->
    IO ConwayTx
buildCheckpointSpend env input redeemerData validity outputs walletContribution = do
    params <- withinSecs 30 "query checkpoint spend parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query checkpoint spend wallet" (queryUTxOs (envProvider env) (envOwner env))
    (feeUtxo, collateralUtxo) <- pickDisjoint wallet [stateIn]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        feeChange = unCoin (feeOut ^. coinTxOutL) - scriptFee - walletContribution
        changeOut = mkBasicTxOut (envOwner env) (inject (Coin feeChange))
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwaySpending (AsIx stateIndex))
                    (ledgerData redeemerData, scriptExUnits)
        interval = ValidityInterval (SJust (lowerSlot validity)) (SJust (upperSlot validity))
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList (outputs <> [changeOut])
                & feeTxBodyL .~ Coin scriptFee
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & vldtTxBodyL .~ interval
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ Map.singleton (envCheckpointHash env) (envCheckpointScript env)
            & witsTxL . rdmrsTxWitsL .~ redeemers
  where
    stateIn = fst (checkpointUtxo input)

mkStateOutput ::
    CheckpointEnv -> Role -> MaryValue -> PLC.Data -> TxOut ConwayEra
mkStateOutput env role value datum =
    mkBasicTxOut (roleAddress env role) value
        & datumTxOutL .~ mkInlineDatum datum

-- | The index of the output that receives the premium.
premiumOutputIndex :: Integer
premiumOutputIndex = 1

-- | The value with its lovelace replaced.
withLovelace :: Integer -> MaryValue -> MaryValue
withLovelace lovelace (MaryValue _ assets) = MaryValue (Coin lovelace) assets

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

currentValidity :: CheckpointEnv -> IO ValidityPlan
currentValidity env = do
    snapshot <-
        withinSecs 30 "query current validity tip" $
            queryLedgerSnapshot (envProvider env)
    let lower = ledgerTipSlot snapshot
        upper = SlotNo (unSlotNo lower + 20)
    lowerMs <- slotStartPosixMs env lower
    upperMs <- slotStartPosixMs env upper
    pure
        ValidityPlan
            { lowerSlot = lower
            , upperSlot = upper
            , lowerPosixMs = lowerMs
            , upperPosixMs = upperMs
            }

assertConvictSettlement ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    ByteString ->
    TxId ->
    IO ()
assertConvictSettlement env row input convictor convictTxId = do
    let outputIndexes = [0, 1, 2, 3]
        outputRefs =
            Set.fromList
                [ TxIn convictTxId (TxIx (fromIntegral outputIndex))
                | outputIndex <- outputIndexes
                ]
        aidName = checkpointToken env (checkpointDatum input)
        sourceCoin = unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
    pending <-
        requireJust
            ("Convict " <> row <> " source is not live")
            (convictedOf (checkpointFacts input))
    _ <-
        pollOutput
            (envProvider env)
            convictTxId
            outputIndexes
            (isExactKeyPayout convictor registrationBond)
            >>= requireJust ("Convict " <> row <> " payout did not settle")
    outputs <-
        withinSecs 30 ("query Convict " <> row <> " outputs") $
            queryUTxOByTxIn (envProvider env) outputRefs
    unless (Map.keysSet outputs == outputRefs) $
        fail
            ( "Convict "
                <> row
                <> " settlement query did not return every output: "
                <> show (Map.keysSet outputs)
            )
    let outputAt index =
            requireJust
                ("Convict " <> row <> " output index " <> show index <> " is absent")
                (Map.lookup (TxIn convictTxId (TxIx index)) outputs)
    -- #280: output zero is the reservation's deposit refund, so the convictor
    -- payout, the pending termination and the refund sit after it.  Asserting
    -- the refund from settled chain state is what proves the reveal returned
    -- exactly the applied deposit to exactly the committed beneficiary.
    refundOut <- outputAt 0
    unless
        ( isExactKeyPayout
            convictor
            (cpCommitDeposit (cfParameters (envCommitmentFamily env)))
            refundOut
        )
        ( fail
            ( "Convict "
                <> row
                <> " output 0 is not the exact reservation deposit refund"
            )
        )
    convictorOut <- outputAt 1
    unless
        (isExactKeyPayout convictor registrationBond convictorOut)
        (fail ("Convict " <> row <> " output 1 is not the exact convictor payout"))
    -- The token stays: the pending termination holds the minimum ADA, the
    -- AID token and the datum the Lean conviction writes.
    pendingOut <- outputAt 2
    unless
        ( pendingOut ^. addrTxOutL == roleAddress env Active
            && hasAsset (statePolicyId env) aidName pendingOut
            && unCoin (pendingOut ^. coinTxOutL) == checkpointMinAda
        )
        (fail ("Convict " <> row <> " output 2 is not the pending termination holding the token"))
    case extractDatum pendingOut of
        Just (V2 facts)
            | facts == pending -> pure ()
        _ -> fail ("Convict " <> row <> " pending output does not carry the termination pending datum")
    -- The bond (unless frozen) and the pool go to the committed refund
    -- address, with no token.
    refundToOut <- outputAt 3
    unless
        ( refundToOut ^. addrTxOutL == envOwner env
            && not (hasAsset (statePolicyId env) aidName refundToOut)
            && unCoin (refundToOut ^. coinTxOutL)
                == sourceCoin - checkpointMinAda - registrationBond
        )
        (fail ("Convict " <> row <> " output 3 is not the refund of the bond and the pool"))
    remaining <-
        withinSecs 30 ("query Convict " <> row <> " source input") $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst (checkpointUtxo input)))
    unless (Map.null remaining) $
        fail ("Convict " <> row <> " left its source input unspent")
    dbg
        ( "Convict "
            <> row
            <> " settled; tx id="
            <> show convictTxId
            <> "; source-input="
            <> show (fst (checkpointUtxo input))
            <> "; convictor-output=1:"
            <> show registrationBond
            <> "; pending-output=2; refund-output=3:"
            <> show (sourceCoin - checkpointMinAda - registrationBond)
        )

isExactKeyPayout :: ByteString -> Integer -> TxOut ConwayEra -> Bool
isExactKeyPayout recipient amount output =
    output ^. addrTxOutL == keyAddress recipient
        && case output ^. valueTxOutL of
            MaryValue (Coin lovelace) (MultiAsset assets) ->
                lovelace == amount && Map.null assets

slotStartPosixMs :: CheckpointEnv -> SlotNo -> IO Integer
slotStartPosixMs env target = do
    now <- round . (* 1000) <$> getPOSIXTime
    let lo0 = now - 5_000
        -- The pinned genesis declares StandardSafeZone 30 at slotLength 0.1s,
        -- so the node forecasts exactly 3,000 ms past its tip: a +3,000 probe
        -- sat ON that boundary and lost that race by one millisecond. Two
        -- seconds leaves ten slots of margin against the declared safe zone.
        hi0 = now + 2_000
        provider = envProvider env
        slotAt ms = withinSecs 10 "node POSIX-to-slot conversion" (posixMsToSlot provider ms)
    loSlot <- slotAt lo0
    hiSlot <- slotAt hi0
    unless (loSlot <= target && target <= hiSlot) $
        fail
            ( "slotStartPosixMs: target "
                <> show target
                <> " outside node-derived bracket "
                <> show (loSlot, hiSlot)
            )
    search slotAt lo0 hi0
  where
    search slotAt lo hi
        | lo + 1 >= hi = pure hi
        | otherwise = do
            let mid = (lo + hi) `div` 2
            slot <- slotAt mid
            if slot < target
                then search slotAt mid hi
                else search slotAt lo mid

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
submitSettling env = submitSettlingBy env (ownerParty env)

submitSettlingBy :: CheckpointEnv -> Party -> String -> ConwayTx -> IO TxId
submitSettlingBy env party = submitWith (envSubmitter env) (partyKey party)

submitWith ::
    Submitter IO ->
    SignKeyDSIGN Ed25519DSIGN ->
    String ->
    ConwayTx ->
    IO TxId
submitWith submitter key label tx = do
    result <-
        withinSecs 60 ("submit " <> label) $
            submitTx submitter (addKeyWitness key tx)
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

{- | #280: a story beneficiary the harness can actually witness.

Both @validate_commitment_open@ and @validate_commitment_reveal@ require
@list.has(tx.extra_signatories, payee_pkh)@, so a convictor
is a real Ed25519 key pair here rather than a constant byte pattern: without
the signing key no reservation could be opened over it and none could be
revealed.
-}
data Beneficiary = Beneficiary
    { beneficiaryKey :: !(SignKeyDSIGN Ed25519DSIGN)
    , beneficiaryPkh :: !ByteString
    }

beneficiaryFromSeed :: Word8 -> Beneficiary
beneficiaryFromSeed tag =
    Beneficiary
        { beneficiaryKey = key
        , beneficiaryPkh = case keyHashFromSignKey key of
            KeyHash hash -> hashToBytes hash
        }
  where
    key = mkSignKey (BS.replicate 32 tag)

-- | The convictor every live enforcement story pays.
storyConvictor :: Beneficiary
storyConvictor = beneficiaryFromSeed 0x51

beneficiarySignKey :: String -> ByteString -> IO (SignKeyDSIGN Ed25519DSIGN)
beneficiarySignKey label payee =
    case filter ((== payee) . beneficiaryPkh) [storyConvictor] of
        [beneficiary] -> pure (beneficiaryKey beneficiary)
        _ ->
            fail
                ( label
                    <> ": no harness signing key for beneficiary "
                    <> show payee
                )

{- | The exact output index every entitled settlement refunds the deposit at.
Fixing it at zero keeps the refund index from becoming a per-shape argument
of the reveal.
-}
settlementRefundIndex :: Integer
settlementRefundIndex = 0

-- | Declared ex-unit ceiling for the two commitment-program legs.
commitmentExUnits :: ExUnits
commitmentExUnits = ExUnits 2_000_000 1_500_000_000

-- | The blueprint title of the #271 commitment program.
commitmentValidatorTitle :: Text
commitmentValidatorTitle = "bounty_commitment.bounty_commitment.spend"

{- | The two paired observer withdrawal accounts and their reward purposes.

Shared by the Convict builder and by the negative rows, so a row
asserting "the enforcement observer is the leg that rejected this evidence"
names the very purpose the builder declared, rather than a re-derivation that
could drift away from it.
-}
observerWithdrawals ::
    CheckpointEnv ->
    ( Map.Map AccountAddress Coin
    , ConwayPlutusPurpose AsIx ConwayEra
    , ConwayPlutusPurpose AsIx ConwayEra
    )
observerWithdrawals env =
    (withdrawalMap, purposeOf enforcementAccount, purposeOf entitlementAccount)
  where
    enforcementAccount =
        AccountAddress
            Testnet
            (AccountId (ScriptHashObj (envEnforcementHash env)))
    entitlementAccount =
        AccountAddress
            Testnet
            (AccountId (ScriptHashObj (envEntitlementHash env)))
    withdrawalMap =
        Map.fromList
            [(enforcementAccount, Coin 0), (entitlementAccount, Coin 0)]
    purposeOf account =
        ConwayRewarding . AsIx . fromIntegral $
            fromMaybe
                (error "paired observer account missing from withdrawals")
                (elemIndex account (Map.keys withdrawalMap))

-- | The enterprise address the applied commitment program holds reservations at.
commitmentAddress :: CheckpointEnv -> Addr
commitmentAddress env =
    Addr Testnet (ScriptHashObj (envCommitmentHash env)) StakeRefNull

-- | One distinct hidden nonce per reservation, at the mandated 32-byte width.
commitmentNonce :: String -> ByteString
commitmentNonce label =
    blake3Hash (B8.pack ("cardano-keri/#280/reservation/" <> label))

outputRefOf :: TxIn -> OutputRef
outputRefOf (TxIn (TxId safeHash) (TxIx index)) =
    OutputRef
        { orTransactionId = hashToBytes (extractHash safeHash)
        , orOutputIndex = fromIntegral index
        }

requiredSignerHash :: ByteString -> KeyHash r
requiredSignerHash bytes =
    KeyHash $
        fromMaybe
            (error "requiredSignerHash: key hash is not 28 bytes")
            (hashFromBytes bytes)

{- | The minting-purpose index of one policy in a transaction's mint map.

Ledger minting purposes are indexed by the policy's position in the sorted mint
map, so a Convict burning both the checkpoint token and the commitment marker
cannot keep the hard-coded zero the single-policy shape used.
-}
mintingIndex :: PolicyID -> MultiAsset -> Word32
mintingIndex policy (MultiAsset assets) =
    case elemIndex policy (Map.keys assets) of
        Just index -> fromIntegral index
        Nothing -> error "mintingIndex: policy absent from the mint map"

{- | The Plutus reading of a declared ledger validity interval.

@Cardano.Ledger.Conway.TxInfo.transValidityInterval@ maps
@ValidityInterval (SJust lo) (SJust hi)@ to the POSIX-millisecond interval whose
lower bound is INCLUSIVE at the start of @lo@ and whose upper bound is STRICT at
the start of @hi@.  Every #271 magnitude — @commit_upper@, @eligible_after@ and
@expires_at@ — is therefore in milliseconds.  A wrong inclusivity makes the
opening fail on chain against
@scope.commit_upper == raw_upper(tx.validity_range)@ rather than silently
mis-age the reservation.
-}
declaredSlotRange :: ValidityPlan -> SlotRange
declaredSlotRange validity =
    SlotRange
        { srLowerBound = Finite (lowerPosixMs validity) Inclusive
        , srUpperBound = Finite (upperPosixMs validity) Exclusive
        }

{- | The declared window of a commitment opening.

Ten slots is long enough for the opening to be included and short enough that
the derived eligibility instant — one millisecond past this endpoint — arrives
a second later, well inside the applied release lifetime.
-}
openingValidity :: CheckpointEnv -> IO ValidityPlan
openingValidity env = do
    snapshot <-
        withinSecs 30 "query commitment opening tip" $
            queryLedgerSnapshot (envProvider env)
    let lower = ledgerTipSlot snapshot
        upper = SlotNo (unSlotNo lower + 10)
    lowerMs <- slotStartPosixMs env lower
    upperMs <- slotStartPosixMs env upper
    pure
        ValidityPlan
            { lowerSlot = lower
            , upperSlot = upper
            , lowerPosixMs = lowerMs
            , upperPosixMs = upperMs
            }

{- | Read one reservation out of chain state, exactly as @own_commitment@ reads
it.  Nothing here is synthesized: a caller can only describe an output the node
returned.
-}
resolveCommitmentOutput ::
    CheckpointEnv -> (TxIn, TxOut ConwayEra) -> IO ResolvedCommitment
resolveCommitmentOutput env (ref, output) = do
    datum <-
        requireJust
            "resolved reservation output carries no inline commitment datum"
            (extractDatum output)
    policy <-
        case output ^. addrTxOutL of
            Addr _ (ScriptHashObj hash) _ -> pure (scriptHashBytes hash)
            _ -> fail "resolved reservation output is not at a script credential"
    let MaryValue (Coin lovelace) (MultiAsset assets) = output ^. valueTxOutL
        marker = AssetName (SBS.toShort (bcMarker datum))
        ownAssets = Map.findWithDefault Map.empty (envCommitmentPolicy env) assets
        countOther entryPolicy names accumulated
            | entryPolicy == envCommitmentPolicy env =
                accumulated + Map.size (Map.delete marker names)
            | otherwise = accumulated + Map.size names
        others = Map.foldrWithKey countOther (0 :: Int) assets
    pure
        ResolvedCommitment
            { rcRef = outputRefOf ref
            , rcPolicy = policy
            , rcDatum = datum
            , rcLovelace = lovelace
            , rcMarkerQuantity = Map.findWithDefault 0 marker ownAssets
            , rcHoldsOtherAssets = others > 0
            }

{- | Re-read the reservation a prepared reveal names, from chain state.

This is the live half of @INV-280-LIVE-OPEN@: a settlement is built only out of
an output the node still returns at the deployed commitment credential, so no
reveal can be paired with an entitlement that only ever existed in memory.
-}
liveReservation ::
    CheckpointEnv ->
    String ->
    EntitledEnforcementPlan ->
    IO ((TxIn, TxOut ConwayEra), ResolvedCommitment)
liveReservation env label plan = do
    utxos <-
        withinSecs 30 (label <> ": query live reservations") $
            queryUTxOs (envProvider env) (commitmentAddress env)
    entry <-
        requireJust
            (label <> ": the opened reservation is no longer on chain")
            (find ((== eepCommitmentRef plan) . outputRefOf . fst) utxos)
    resolved <- resolveCommitmentOutput env entry
    pure (entry, resolved)

{- | Poll the node until it reaches the reservation's stored eligibility instant.
Bounded, and every retry re-queries the node.
-}
awaitCommitmentMaturity :: CheckpointEnv -> String -> Integer -> IO ()
awaitCommitmentMaturity env label eligibleAfter = do
    target <-
        withinSecs 30 (label <> ": convert the eligibility instant") $
            posixMsCeilSlot (envProvider env) eligibleAfter
    go (pollAttempts * 2) target
  where
    go remaining target
        | remaining <= 0 =
            fail
                ( label
                    <> ": the node did not reach the reservation eligibility slot "
                    <> show target
                )
        | otherwise = do
            snapshot <-
                withinSecs 30 (label <> ": query maturity tip") $
                    queryLedgerSnapshot (envProvider env)
            if ledgerTipSlot snapshot >= target
                then pure ()
                else threadDelay 100_000 >> go (remaining - 1) target

{- | The exact interval an entitled settlement declares.

It waits for maturity and then proves, through the component's own raw-range
predicates, that the interval it is about to declare is wholly at or after the
reservation's stored eligibility instant and wholly at or before its stored
expiry — @INV-280-MATURE@ enforced at the transaction that actually settles,
not merely at planning time.
-}
entitledSettlementValidity ::
    CheckpointEnv -> String -> ResolvedCommitment -> IO ValidityPlan
entitledSettlementValidity env label resolved = do
    let scope = bcScope (rcDatum resolved)
    awaitCommitmentMaturity env label (bsEligibleAfter scope)
    validity <- tipValidity env label
    let range = declaredSlotRange validity
    unless (atOrAfter range (bsEligibleAfter scope)) $
        fail
            ( label
                <> ": the declared settlement interval is not wholly at or\
                   \ after the stored eligibility instant "
                <> show (bsEligibleAfter scope)
            )
    unless (atOrBefore range (bsExpiresAt scope)) $
        fail
            ( label
                <> ": the declared settlement interval is not wholly at or\
                   \ before the stored expiry "
                <> show (bsExpiresAt scope)
            )
    pure validity

{- | A validity interval from the ledger tip to 25 slots ahead, inside the
node's forecast.
-}
tipValidity :: CheckpointEnv -> String -> IO ValidityPlan
tipValidity env label = do
    snapshot <-
        withinSecs 30 (label <> ": query settlement tip") $
            queryLedgerSnapshot (envProvider env)
    let lower = ledgerTipSlot snapshot
        upper = SlotNo (unSlotNo lower + 25)
    lowerMs <- slotStartPosixMs env lower
    -- Both conversions sit AT the tip and the endpoint is derived from the
    -- era's own slot length: 25 slots is inside the node's forecast but
    -- outside the reduced search bracket above.
    nextMs <- slotStartPosixMs env (SlotNo (unSlotNo lower + 1))
    let slotLengthMs = nextMs - lowerMs
    unless (slotLengthMs > 0) $
        fail (label <> ": the node reported a non-positive slot length")
    pure
        ValidityPlan
            { lowerSlot = lower
            , upperSlot = upper
            , lowerPosixMs = lowerMs
            , upperPosixMs = lowerMs + 25 * slotLengthMs
            }

{- | Submit one authentic #271 opening and resolve the output it created.

Everything the transaction carries comes from 'prepareBountyCommitment': the
marker derived from the consumed seed, the inline datum, the exact deposit and
the beneficiary's creation-time consent.  The declared opening window is what
the program stores as @commit_upper@, from which the applied parameters derive
eligibility and expiry — so this harness cannot choose a maturity boundary.
-}
openLiveReservation ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    EnforcementEvidence ->
    ByteString ->
    ByteString ->
    IO ResolvedCommitment
openLiveReservation env label checkpointInput evidence payee nonce = do
    commitmentRef <-
        requireJust
            "bounty_commitment reference was not deployed during setup"
            (envCommitmentReference env)
    payeeKey <- beneficiarySignKey label payee
    params <-
        withinSecs 30 (label <> ": query opening parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 (label <> ": query opening wallet") $
            queryUTxOs (envProvider env) (envOwner env)
    (seed, collateral) <-
        pickDisjoint wallet [fst commitmentRef, fst checkpointInput]
    opening <- openingValidity env
    let family = envCommitmentFamily env
    plan <-
        either
            (fail . ((label <> ": opening could not be planned: ") <>) . show)
            pure
            ( prepareBountyCommitment
                (cfParameters family)
                (cfPolicy family)
                (outputRefOf (fst seed))
                (declaredSlotRange opening)
                (policyBytes (envCheckpointPolicy env))
                (outputRefOf (fst checkpointInput))
                (enforcementEvidenceDigest evidence)
                payee
                nonce
            )
    let (marker, quantity) = bcplMint plan
        markerName = AssetName (SBS.toShort marker)
        minted =
            MultiAsset $
                Map.singleton
                    (envCommitmentPolicy env)
                    (Map.singleton markerName quantity)
        commitmentOut =
            mkBasicTxOut
                (commitmentAddress env)
                (MaryValue (Coin (bcplScriptOutputLovelace plan)) minted)
                & datumTxOutL .~ mkInlineDatum (asPlcData (bcplDatum plan))
        redeemers =
            Redeemers $
                Map.singleton
                    ( ConwayMinting
                        (AsIx (mintingIndex (envCommitmentPolicy env) minted))
                    )
                    ( ledgerData (asPlcData (bcplMintRedeemer plan))
                    , commitmentExUnits
                    )
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton (fst seed)
                & outputsTxBodyL .~ StrictSeq.singleton commitmentOut
                & mintTxBodyL .~ minted
                & collateralInputsTxBodyL .~ Set.singleton (fst collateral)
                & referenceInputsTxBodyL .~ Set.singleton (fst commitmentRef)
                & reqSignerHashesTxBodyL
                    .~ Set.fromList
                        (map requiredSignerHash (bcplRequiredSigners plan))
                & vldtTxBodyL
                    .~ ValidityInterval
                        (SJust (lowerSlot opening))
                        (SJust (upperSlot opening))
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
        skeleton = mkBasicTx body & witsTxL . rdmrsTxWitsL .~ redeemers
    balanced <-
        either
            (fail . ((label <> ": opening balance failed: ") <>) . show)
            (pure . balancedTx)
            ( balanceTxWith
                params
                [seed]
                (CollateralUtxos [collateral])
                [commitmentRef]
                (envOwner env)
                Nothing
                skeleton
            )
    txId <- submitSettling env label (addKeyWitness payeeKey balanced)
    settled <-
        pollOutput
            (envProvider env)
            txId
            [0, 1]
            (hasAsset (envCommitmentPolicy env) marker)
            >>= requireJust (label <> ": the opening did not settle")
    resolveCommitmentOutput env settled

{- | @FN-280-PREPARE-LIVE-ENTITLEMENT@ — open, resolve, mature, and reveal.

The reservation is opened in its own strictly earlier transaction, observed
back from chain state, and only then turned into a reveal plan by the
production builder.  The digest is derived from the COMPLETE actual evidence
rather than supplied, so a row that varies its evidence necessarily varies its
reservation: no envelope here can be re-pointed at another row's commitment,
and no negative row fails on an entitlement mismatch it never meant to test.
-}
prepareLiveEntitlement ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    EnforcementEvidence ->
    ByteString ->
    ByteString ->
    IO EntitledEnforcementPlan
prepareLiveEntitlement env checkpointInput evidence payee nonce = do
    resolved <-
        openLiveReservation env label checkpointInput evidence payee nonce
    validity <- entitledSettlementValidity env label resolved
    plan <-
        either
            (fail . ((label <> ": reveal could not be planned: ") <>) . show)
            pure
            ( prepareEntitledEnforcement
                (envCommitmentFamily env)
                resolved
                evidence
                (outputRefOf (fst checkpointInput))
                nonce
                settlementRefundIndex
                (declaredSlotRange validity)
            )
    dbg
        ( label
            <> " matured: reservation="
            <> show (eepCommitmentRef plan)
            <> "; checkpoint="
            <> show (fst checkpointInput)
            <> "; payee="
            <> show (eepBountyPayee plan)
        )
    pure plan
  where
    label = "live conviction"

{- | The checkpoint input an Advance settled. The successor carries the rotated
version 2 datum and exactly the lovelace the Lean @heldValue@ gives it once the
premium left the pool, and the premium reached the output the redeemer names.
-}
settledAdvance ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    KeyStateView ->
    TxId ->
    (TxIn, TxOut ConwayEra) ->
    IO CheckpointInput
settledAdvance env row before created advanceTxId utxo = do
    settlement <-
        requireJust
            (row <> ": the advanced checkpoint was not a live output holding its floor")
            ( rotationSettlement
                checkpointMinAda
                registrationBond
                freezeBond
                premium
                (checkpointFacts before)
                (unCoin (snd (checkpointUtxo before) ^. coinTxOutL))
            )
    expected <-
        requireJust
            (row <> ": the advanced checkpoint was not live")
            (rotatedLive (checkpointFacts before) created)
    unless
        (snd utxo ^. addrTxOutL == roleAddress env Active)
        (fail (row <> ": successor is not at the ACTIVE address"))
    case extractDatum (snd utxo) of
        Just (V2 facts)
            | facts == expected -> pure ()
        _ -> fail (row <> ": successor does not carry the exact rotated version 2 datum")
    unless
        ( unCoin (snd utxo ^. coinTxOutL)
            == heldValue
                checkpointMinAda
                registrationBond
                freezeBond
                expected
                (settlementPoolAfter settlement)
        )
        (fail (row <> ": successor lovelace is not the held value after the premium"))
    when (settlementPaid settlement > 0) $ do
        let payeeRef = TxIn advanceTxId (TxIx (fromIntegral premiumOutputIndex))
        payee <-
            withinSecs 30 (row <> ": query premium output") $
                queryUTxOByTxIn (envProvider env) (Set.singleton payeeRef)
        case Map.lookup payeeRef payee of
            Just out
                | unCoin (out ^. coinTxOutL) >= settlementPaid settlement -> pure ()
            _ -> fail (row <> ": the premium output is missing or short")
    pure
        CheckpointInput
            { checkpointUtxo = utxo
            , checkpointDatum = created
            , checkpointFacts = expected
            }

{- | #345: the connected journey register, advance, freeze, then the deposit
rotation that restores the bond and makes the checkpoint consumable again.

The controller's later witnessed rotation is first presented by a hunter as a
freeze, which leaves the datum on the old keys and sets the frozen flag. The
same rotation then lands as a deposit, signed over the deposit intent of the
frozen output by the rotation's new keys. The refusals are judged by the
production scripts: an intent that names another amount, an intent for another
output, signatures by the spent keys, and one signature below the threshold.
The accepted deposit settles the rotated datum unfrozen on the new keys,
holding the minimum ADA, the deposit, the bond and the pool.

"Consumable again" is what the deposit decides: the settled datum is neither
frozen nor poisoned, where the frozen output was not. The maturity window is a
consumer's parameter over the unchanged birth slot, and no consumer transaction
is run against the output.
-}
productionRegisterFreezeThenDepositScenario :: CheckpointEnv -> IO ()
productionRegisterFreezeThenDepositScenario env = do
    fixture <- loadConvictStoryFixture
    let laterRotation = fsResponseRotation fixture
        created = rsCreated laterRotation
    (checkpointRef, advanceRef, advanced) <-
        advanceOnceForRotationStory env fixture
    let honest =
            signedRotateEvidence
                env
                advanced
                laterRotation
                (rsRotationSigners laterRotation)
                (aeWitReceipts (rsUnsignedEvidence laterRotation))
    freezeTxId <-
        submitTwoPassRotation
            (freezeOp created honest)
            env
            "checkpoint Freeze (deposit journey)"
            checkpointRef
            advanceRef
            advanced
            created
            Nothing
    frozenUtxo <-
        pollOutput
            (envProvider env)
            freezeTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "Freeze successor did not settle"
    settledFreeze env "Freeze" advanced freezeTxId frozenUtxo
    frozenFacts <-
        requireJust
            "the advanced checkpoint was not freezable"
            (frozenLive (checkpointFacts advanced))
    let frozen =
            CheckpointInput
                { checkpointUtxo = frozenUtxo
                , checkpointDatum = checkpointDatum advanced
                , checkpointFacts = frozenFacts
                }
    when (notFrozenNorPoisoned frozenFacts) $
        fail "the frozen checkpoint is already consumable"
    let (spentTx, spentIx) = spentOutputBytes frozen
        intentAt (txBytes, ix) deposit =
            fmap
                (\intent -> depositIntentPreimage intent{diDeposit = deposit})
                ( requiredIntent
                    freezeBond
                    DepositFacts
                        { dfNetworkId = 0
                        , dfPolicy = policyBytes (envCheckpointPolicy env)
                        , dfTxId = txBytes
                        , dfOutputIndex = ix
                        }
                    frozenFacts
                    (cdNativeSn created)
                )
        intentFor ref deposit =
            requireJust "the frozen checkpoint has no deposit intent" (intentAt ref deposit)
        newKeys = rsRotationSigners laterRotation
    required <- intentFor (spentTx, spentIx) freezeBond
    namesNothing <- intentFor (spentTx, spentIx) 0
    otherOutput <- intentFor (spentTx, spentIx + 1) freezeBond
    let good = indexedSignaturesOver required newKeys
        rejected label signatures =
            rejectRotation
                (depositOp honest signatures)
                env
                checkpointRef
                advanceRef
                frozen
                created
                label
    -- The Haskell verdict accepts the deposit the production scripts are about
    -- to judge, and refuses the one that names another amount.
    depositVerdictOf env frozen created honest good
        >>= either (fail . ("the Haskell verdict refuses the honest deposit: " <>) . show) pure
    depositVerdictOf env frozen created honest (indexedSignaturesOver namesNothing newKeys)
        >>= either (const (pure ())) (const (fail "the Haskell verdict accepts a deposit that names another amount"))
    sequence_
        [ rejected "Deposit names another amount" (indexedSignaturesOver namesNothing newKeys)
        , rejected "Deposit signed for another output" (indexedSignaturesOver otherOutput newKeys)
        , rejected
            "Deposit signed by the spent keys"
            (indexedSignaturesOver required (rsCurrentSigners laterRotation))
        , rejected "Deposit below the threshold" (take 1 good)
        ]
    depositTxId <-
        submitTwoPassRotation
            (depositOp honest good)
            env
            "checkpoint Deposit"
            checkpointRef
            advanceRef
            frozen
            created
            Nothing
    depositUtxo <-
        pollOutput
            (envProvider env)
            depositTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "Deposit successor did not settle"
    settledDeposit env "Deposit" frozen created depositUtxo
    remaining <-
        withinSecs 30 "query the frozen checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst (checkpointUtxo frozen)))
    unless (Map.null remaining) $
        fail "Deposit left the frozen checkpoint input unspent"
    dbg ("Deposit settled; tx id=" <> show depositTxId)

-- | Neither frozen nor poisoned: what a deposit decides of a live checkpoint.
notFrozenNorPoisoned :: CheckpointDatumV2 -> Bool
notFrozenNorPoisoned = \case
    Live{lvFrozen = False, lvPoisoned = False} -> True
    _ -> False

-- | The transaction id and output index of the spent output, as bytes and an integer.
spentOutputBytes :: CheckpointInput -> (ByteString, Integer)
spentOutputBytes input = case fst (checkpointUtxo input) of
    TxIn (TxId safeHash) (TxIx outputIndex) ->
        (hashToBytes (extractHash safeHash), fromIntegral outputIndex)

{- | The Haskell verdict of the deposit the journey is about to submit, from
the chain's own view of the frozen output and what the deposit settles.
-}
depositVerdictOf ::
    CheckpointEnv ->
    CheckpointInput ->
    KeyStateView ->
    AdvanceEvidence ->
    [(Int, ByteString)] ->
    IO (Either DepositRefusal ())
depositVerdictOf env input successor evidence signatures = do
    (successorFacts, successorLovelace, payee) <-
        roSettle (depositOp evidence signatures) input successor
    let (spentTx, spentIx) = spentOutputBytes input
    pure $
        depositVerdict
            DepositParams
                { dpNetworkId = 0
                , dpMinAda = checkpointMinAda
                , dpDeposit = registrationBond
                , dpBond = freezeBond
                , dpPremium = premium
                }
            DepositInput
                { dnPolicy = policyBytes (envCheckpointPolicy env)
                , dnSpentTxId = spentTx
                , dnSpentIndex = spentIx
                , dnSpentDatum = checkpointFacts input
                , dnSpentLovelace = unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
                , dnSuccessorDatum = successorFacts
                , dnSuccessorLovelace = successorLovelace
                , dnPayeeLovelace = if payee > 0 then Just payee else Nothing
                , dnMinted = False
                , dnSignatures = signatures
                , dnRotation = evidence
                }

{- | What a settled deposit left: the successor at the ACTIVE address carrying
the exact rotated datum unfrozen on the new keys, holding the minimum ADA, the
deposit, the freeze bond and the pool, and not frozen where the spent output was.
-}
settledDeposit ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    KeyStateView ->
    (TxIn, TxOut ConwayEra) ->
    IO ()
settledDeposit env row before created utxo = do
    settlement <-
        requireJust
            (row <> ": the frozen checkpoint was not a live output holding its floor")
            ( rotationSettlement
                checkpointMinAda
                registrationBond
                freezeBond
                premium
                (checkpointFacts before)
                (unCoin (snd (checkpointUtxo before) ^. coinTxOutL))
            )
    rotated <-
        requireJust
            (row <> ": the frozen checkpoint was not live")
            (rotatedLive (checkpointFacts before) created)
    let expected = case rotated of
            live@Live{} -> live{lvFrozen = False}
            other -> other
    unless
        (snd utxo ^. addrTxOutL == roleAddress env Active)
        (fail (row <> ": successor is not at the ACTIVE address"))
    case extractDatum (snd utxo) of
        Just (V2 facts)
            | facts == expected -> pure ()
        _ -> fail (row <> ": successor does not carry the exact rotated, unfrozen version 2 datum")
    unless
        (notFrozenNorPoisoned expected)
        (fail (row <> ": the settled checkpoint is still frozen or poisoned"))
    unless
        ( unCoin (snd utxo ^. coinTxOutL)
            == heldValue
                checkpointMinAda
                registrationBond
                freezeBond
                expected
                (settlementPoolAfter settlement)
        )
        (fail (row <> ": successor lovelace is not the minimum ADA, the deposit, the bond and the pool"))

-- ---------------------------------------------------------------------------
-- The bounded top-up (#346, #522)
-- ---------------------------------------------------------------------------

topUpParams :: TopUpParams
topUpParams =
    TopUpParams
        { tuMinAda = checkpointMinAda
        , tuDeposit = registrationBond
        , tuBond = freezeBond
        , tuPremium = premium
        }

{- | What a top-up of this checkpoint by this amount writes and holds, by the
Haskell model of the Lean's @topUp@: the marked datum and the lovelace of the
successor. 'fail' when the model refuses.
-}
topUpOf :: CheckpointInput -> Integer -> IO (CheckpointDatumV2, Integer)
topUpOf input amount = do
    settlement <-
        requireJust
            "TopUp: the checkpoint cannot be topped up by this amount"
            ( topUpSettlement
                topUpParams
                (checkpointFacts input)
                (unCoin (snd (checkpointUtxo input) ^. coinTxOutL))
                amount
            )
    facts <-
        requireJust
            "TopUp: the checkpoint is not live or was topped up since its last rotation"
            (markedLive (checkpointFacts input))
    pure (facts, tsSuccessorLovelace settlement)

{- | A top-up transaction: the checkpoint output is spent with the TopUp
redeemer and a successor that holds @successorLovelace@; the wallet funds the
difference. The successor datum is a parameter so a refusal can be built from
the same shape. There is no observer, no withdrawal and no validity range.
-}
buildTopUpTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    Integer ->
    CheckpointDatumV2 ->
    Integer ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildTopUpTxWith budgets env checkpointRef input amount successorFacts successorLovelace = do
    params <-
        withinSecs 30 "query TopUp protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query TopUp wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        spendPurpose = ConwaySpending (AsIx (spendingIndex stateIn allInputs))
        expected = Set.singleton spendPurpose
        stateOut =
            mkStateOutput
                env
                Active
                ( withLovelace
                    successorLovelace
                    (snd (checkpointUtxo input) ^. valueTxOutL)
                )
                (asPlcData (V2 successorFacts))
        inflow =
            successorLovelace
                - unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (-(scriptFee + inflow)) (feeOut ^. valueTxOutL))
        redeemers =
            Redeemers $
                Map.singleton
                    spendPurpose
                    ( ledgerData (topUpSpendRedeemerData amount)
                    , Map.findWithDefault advanceSpendExUnits spendPurpose budgets
                    )
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList [stateOut, changeOut]
                & feeTxBodyL .~ Coin scriptFee
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & referenceInputsTxBodyL .~ Set.singleton (fst checkpointRef)
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        redeemers
                        (TxDats mempty)
    pure
        ( mkBasicTx body
            & witsTxL . rdmrsTxWitsL .~ redeemers
        , expected
        )
  where
    stateIn = fst (checkpointUtxo input)

-- | Submit the honest top-up of a checkpoint by an amount.
submitTwoPassTopUp ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    Integer ->
    IO TxId
submitTwoPassTopUp env label checkpointRef input amount = do
    (facts, lovelace) <- topUpOf input amount
    submitTwoPassWith env label $ \budgets ->
        buildTopUpTxWith budgets env checkpointRef input amount facts lovelace

{- | A top-up the production script must refuse, judged by the node: the
successor datum and lovelace are given, so the refusal is the transaction's
own and not the model's.
-}
rejectTopUp ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    Integer ->
    CheckpointDatumV2 ->
    Integer ->
    IO ()
rejectTopUp env label checkpointRef input amount facts lovelace = do
    (candidate, _) <-
        withinSecs 90 (label <> ": build applied candidate") $
            buildTopUpTxWith Map.empty env checkpointRef input amount facts lovelace
    _ <- expectProductionScriptRejection env label candidate
    pure ()

{- | The two datums are the same bytes but for the top-up mark, field 7 of the
live datum: the mark is the only field that moved.
-}
sameButMark :: PLC.Data -> PLC.Data -> Bool
sameButMark (PLC.Constr 1 [PLC.Constr 0 before]) (PLC.Constr 1 [PLC.Constr 0 after]) =
    length before == 9
        && length after == 9
        && [f | (i, f) <- zip [0 :: Int ..] before, i /= 7]
            == [f | (i, f) <- zip [0 :: Int ..] after, i /= 7]
        && (before !! 7, after !! 7) == (PLC.Constr 0 [], PLC.Constr 1 [])
sameButMark _ _ = False

{- | What a settled top-up left: the successor at the ACTIVE address carrying
the datum of the spent output with the top-up mark set and nothing else
changed, holding exactly the amount more.
-}
settledTopUp ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    Integer ->
    (TxIn, TxOut ConwayEra) ->
    IO CheckpointInput
settledTopUp env row before amount utxo = do
    (expected, expectedLovelace) <- topUpOf before amount
    unless
        (snd utxo ^. addrTxOutL == roleAddress env Active)
        (fail (row <> ": successor is not at the ACTIVE address"))
    onChain <- case extractDatum (snd utxo) of
        Just datum@(V2 facts)
            | facts == expected -> pure datum
        _ -> fail (row <> ": successor does not carry the marked version 2 datum")
    unless
        (sameButMark (checkpointDatumToData (V2 (checkpointFacts before))) (checkpointDatumToData onChain))
        (fail (row <> ": the successor datum differs from the spent one in more than the top-up mark"))
    unless
        ( unCoin (snd utxo ^. coinTxOutL)
            == unCoin (snd (checkpointUtxo before) ^. coinTxOutL) + amount
        )
        (fail (row <> ": the successor did not grow by exactly the amount"))
    unless
        (unCoin (snd utxo ^. coinTxOutL) == expectedLovelace)
        (fail (row <> ": successor lovelace is not the held value of the grown pool"))
    pure
        CheckpointInput
            { checkpointUtxo = utxo
            , checkpointDatum = checkpointDatum before
            , checkpointFacts = expected
            }

{- | #346, #522: register with a first pool that covers the premium, top it up by
one premium, and try a second top-up in the same key state.

The refusals are judged by the production script: an amount one lovelace below
the premium, and a successor holding one lovelace more than the amount. The
accepted top-up settles the registered datum with only the mark set, holding
exactly the amount more. The second top-up of the marked output, which the
Lean refuses, is refused by the node.
-}
productionRegisterTopUpScenario :: CheckpointEnv -> IO ()
productionRegisterTopUpScenario env = do
    (fixture, _) <- loadLifecycleFixture
    (registered, checkpointRef) <-
        productionRegisterScenarioWithReference env fixture
    let amount = premium
        lovelaceBefore = unCoin (snd (checkpointUtxo registered) ^. coinTxOutL)
    unless (initialPool >= premium) $
        fail "the registration's first pool does not cover the premium"
    marked <-
        requireJust
            "TopUp: the registered checkpoint was not live"
            (markedLive (checkpointFacts registered))
    sequence_
        [ rejectTopUp
            env
            "TopUp below the premium"
            checkpointRef
            registered
            (premium - 1)
            marked
            (lovelaceBefore + premium - 1)
        , rejectTopUp
            env
            "TopUp whose successor holds one lovelace too many"
            checkpointRef
            registered
            amount
            marked
            (lovelaceBefore + amount + 1)
        , rejectTopUp
            env
            "TopUp that leaves the mark clear"
            checkpointRef
            registered
            amount
            (checkpointFacts registered)
            (lovelaceBefore + amount)
        ]
    topUpTxId <-
        submitTwoPassTopUp env "checkpoint TopUp" checkpointRef registered amount
    successor <-
        pollOutput
            (envProvider env)
            topUpTxId
            [0, 1]
            (holdsCheckpointToken env (checkpointDatum registered))
            >>= requireJust "TopUp successor did not settle"
    toppedUp <- settledTopUp env "TopUp" registered amount successor
    remaining <-
        withinSecs 30 "query the spent registered checkpoint" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst (checkpointUtxo registered)))
    unless (Map.null remaining) $
        fail "TopUp left the registered checkpoint input unspent"
    -- A second top-up in the same key state: the Lean refuses it, so the node does.
    rejectTopUp
        env
        "second TopUp in the same key state"
        checkpointRef
        toppedUp
        amount
        (checkpointFacts toppedUp)
        (unCoin (snd (checkpointUtxo toppedUp) ^. coinTxOutL) + amount)
    dbg ("TopUp settled; tx id=" <> show topUpTxId)

{- | #346, #522: a frozen checkpoint (its pool below the premium, frozen by the
freeze path) is topped up to a pool that covers the premium; the controller's
own rotation then lands with the keep option: it pays one premium from the
pool, stays frozen and clears the mark.
-}
productionFrozenTopUpScenario :: CheckpointEnv -> IO ()
productionFrozenTopUpScenario env = do
    fixture <- loadConvictStoryFixture
    let laterRotation = fsResponseRotation fixture
        created = rsCreated laterRotation
    (checkpointRef, advanceRef, advanced) <-
        advanceOnceForRotationStory env fixture
    let honest =
            signedRotateEvidence
                env
                advanced
                laterRotation
                (rsRotationSigners laterRotation)
                (aeWitReceipts (rsUnsignedEvidence laterRotation))
    freezeTxId <-
        submitTwoPassRotation
            (freezeOp created honest)
            env
            "checkpoint Freeze (top-up journey)"
            checkpointRef
            advanceRef
            advanced
            created
            Nothing
    frozenUtxo <-
        pollOutput
            (envProvider env)
            freezeTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "Freeze successor did not settle"
    settledFreeze env "Freeze" advanced freezeTxId frozenUtxo
    frozenFacts <-
        requireJust
            "the advanced checkpoint was not freezable"
            (frozenLive (checkpointFacts advanced))
    let frozen =
            CheckpointInput
                { checkpointUtxo = frozenUtxo
                , checkpointDatum = checkpointDatum advanced
                , checkpointFacts = frozenFacts
                }
        frozenPool =
            unCoin (snd frozenUtxo ^. coinTxOutL)
                - (checkpointMinAda + registrationBond)
    unless (frozenPool < premium) $
        fail "the frozen checkpoint's pool already covers the premium"
    topUpTxId <-
        submitTwoPassTopUp env "checkpoint TopUp (frozen)" checkpointRef frozen premium
    toppedUtxo <-
        pollOutput
            (envProvider env)
            topUpTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "TopUp of the frozen checkpoint did not settle"
    topped <- settledTopUp env "TopUp (frozen)" frozen premium toppedUtxo
    let toppedPool =
            unCoin (snd toppedUtxo ^. coinTxOutL)
                - (checkpointMinAda + registrationBond)
    unless (toppedPool >= premium) $
        fail "the topped-up pool does not cover the premium"
    -- The controller's rotation, with the keep option: one premium leaves the
    -- pool, the checkpoint stays frozen, the mark is clear.
    advanceTxId <-
        submitTwoPassRotation
            (advanceOp honest)
            env
            "checkpoint Advance (topped-up frozen)"
            checkpointRef
            advanceRef
            topped
            created
            Nothing
    rotatedUtxo <-
        pollOutput
            (envProvider env)
            advanceTxId
            [0, 1]
            (holdsCheckpointToken env created)
            >>= requireJust "Advance of the topped-up frozen checkpoint did not settle"
    rotated <-
        settledAdvance env "Advance (topped-up frozen)" topped created advanceTxId rotatedUtxo
    case checkpointFacts rotated of
        Live{lvFrozen = True, lvToppedUp = False} -> pure ()
        other -> fail ("the rotated checkpoint must stay frozen with the mark clear: " <> show other)
    unless
        ( unCoin (snd rotatedUtxo ^. coinTxOutL) - (checkpointMinAda + registrationBond)
            == toppedPool - premium
        )
        (fail "the rotation did not pay exactly one premium from the pool")
    dbg ("Frozen TopUp then Advance settled; tx id=" <> show advanceTxId)

-- ---------------------------------------------------------------------
-- The registry: genesis, booking, fold and return
-- ---------------------------------------------------------------------

{- | Who signs and pays a transaction: an address and the key that controls it.
The identity owner books, a different party folds.
-}
data Party = Party
    { partyAddr :: !Addr
    , partyKey :: !(SignKeyDSIGN Ed25519DSIGN)
    }

-- | The wallet the node's genesis funds: the identity owner.
ownerParty :: CheckpointEnv -> Party
ownerParty env = Party (envOwner env) genesisSignKey

-- | The key of the party that folds requests into the registry.
folderKey :: SignKeyDSIGN Ed25519DSIGN
folderKey = mkSignKey (BS.replicate 32 0x66)

folderAddress :: Addr
folderAddress =
    Addr Testnet (KeyHashObj (keyHashFromSignKey folderKey)) StakeRefNull

-- | The party that folds.
folderParty :: Party
folderParty = Party folderAddress folderKey

{- | The address that holds the seed of a registry: the wallet's payment
credential with a stake credential, so no wallet query that lists the wallet
by its plain address sees it, and none spends it.
-}
seedAddress :: Addr -> Addr
seedAddress (Addr network payment _) =
    Addr
        network
        payment
        ( StakeRefBase
            ( ScriptHashObj
                ( ScriptHash
                    ( fromMaybe
                        (error "seedAddress: filler is not a hash")
                        (hashFromBytes (BS.replicate 28 0x5e))
                    )
                )
            )
        )
seedAddress other = other

-- | The deposit a request commits: the fold's floor and the pool beyond it.
requestDeposit' :: CheckpointEnv -> Integer
requestDeposit' env =
    registryInitialFloor (envTerms env) + (initialPool - premium)

-- | The lovelace a booked request holds: the deposit, the cost and the tip.
requestLovelace :: CheckpointEnv -> Integer
requestLovelace env =
    requestDeposit' env
        + registrationCost (registryParameters (envTerms env))
        + minimumTip (registryParameters (envTerms env))

applicationPolicy :: CheckpointEnv -> PolicyID
applicationPolicy = PolicyID . envApplicationHash

statePolicyId :: CheckpointEnv -> PolicyID
statePolicyId = PolicyID . envStateHash

applicationAddress :: CheckpointEnv -> Addr
applicationAddress env =
    Addr Testnet (ScriptHashObj (envApplicationHash env)) StakeRefNull

stateAddress :: CheckpointEnv -> Addr
stateAddress env =
    Addr Testnet (ScriptHashObj (envStateHash env)) StakeRefNull

registryIdentity :: CheckpointEnv -> RegistryIdentity
registryIdentity = scriptsRegistry . envRegistry

registrySeed :: CheckpointEnv -> OutputReference
registrySeed = scriptsSeed . envRegistry

-- | The ledger reference as the registry's wire reference.
outputReferenceOf' :: TxIn -> OutputReference
outputReferenceOf' (TxIn (TxId safeHash) (TxIx outputIndex)) =
    OutputReference
        (hashToBytes (extractHash safeHash))
        (fromIntegral outputIndex)

-- | The Plutus address of a ledger address with a key or script payment credential.
plutusAddressOf :: Addr -> PlutusAddress
plutusAddressOf (Addr _ payment stake) =
    PlutusAddress (credentialOf payment) (stakeOf stake)
  where
    credentialOf = \case
        KeyHashObj (KeyHash hash) -> KeyCredential (hashToBytes hash)
        ScriptHashObj (ScriptHash hash) -> ScriptCredential (hashToBytes hash)
    stakeOf = \case
        StakeRefNull -> Nothing
        _ -> error "plutusAddressOf: only addresses without a stake part are used"
plutusAddressOf _ = error "plutusAddressOf: a Byron address has no Plutus address"

-- | A token of the registry's state policy held once by the output.
holdsRegistryToken :: CheckpointEnv -> ByteString -> TxOut ConwayEra -> Bool
holdsRegistryToken env = hasAsset (statePolicyId env)

-- | The active token of a key state's AID: the representative asset of the checkpoint.
checkpointToken :: CheckpointEnv -> KeyStateView -> ByteString
checkpointToken env view =
    activeTokenName (registryIdentity env) (liveAid (liveOfKeyState "" 0 view))
  where
    liveAid = \case
        Live{lvAid} -> lvAid
        TerminationPending{} -> error "checkpointToken: a key state is live"

-- | Whether the output holds the checkpoint of the AID: its active token.
holdsCheckpointToken :: CheckpointEnv -> KeyStateView -> TxOut ConwayEra -> Bool
holdsCheckpointToken env view = holdsRegistryToken env (checkpointToken env view)

-- | The ledger value of one token.
tokenValue :: PolicyID -> ByteString -> Integer -> MultiAsset
tokenValue policy name quantity =
    MultiAsset $
        Map.singleton policy (Map.singleton (AssetName (SBS.toShort name)) quantity)

{- | Publish the template of the state script: an output whose inline datum is
the template bytes, referenced by the genesis transaction.
-}
publishTemplate :: CheckpointEnv -> IO (TxIn, TxOut ConwayEra)
publishTemplate env = do
    let label = "state template publication"
        template = scriptsTemplate (envRegistry env)
    params <-
        withinSecs 30 (label <> ": query parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 (label <> ": query wallet") $
            queryUTxOs (envProvider env) (envOwner env)
    seed <- requireJust (label <> ": no wallet UTxO") (largestFirst wallet)
    let output =
            mkBasicTxOut (envOwner env) (inject (Coin 100_000_000))
                & datumTxOutL .~ mkInlineDatum (B template)
        skeleton =
            mkBasicTx
                (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton output)
    balanced <-
        either
            (fail . ((label <> ": balance failed: ") <>) . show)
            (pure . balancedTx)
            (balanceTx params [seed] [] (envOwner env) skeleton)
    txId <- submitSettling env label balanced
    pollOutput (envProvider env) txId [0] ((== mkInlineDatum (B template)) . (^. datumTxOutL))
        >>= requireJust (label <> ": the template did not settle")

{- | The genesis of the registry: spend the seed, mint the state token into an
empty state and the configuration token into the configuration record, with the
template and the two scripts by reference.
-}
genesisRegistry :: CheckpointEnv -> IO CheckpointEnv
genesisRegistry env = do
    let label = "registry genesis"
    templateOut <- publishTemplate env
    applicationRef <-
        deployReferenceScript
            env
            "keri_application reference deployment"
            (envApplicationScript env)
    stateRef <-
        deployReferenceScript
            env
            "singular_state reference deployment"
            (envStateScript env)
    wallet <-
        withinSecs 30 (label <> ": query wallet") $
            queryUTxOs (envProvider env) (envOwner env)
    seedUtxo <-
        withinSecs 30 (label <> ": query seed") (queryUTxOs (envProvider env) (seedAddress (envOwner env)))
            >>= requireJust (label <> ": the seed output is absent") . listToMaybe
    (collateral, _) <- pickDisjoint wallet []
    let seedIn = fst seedUtxo
        collateralIn = fst collateral
        refs = [fst templateOut, fst applicationRef, fst stateRef]
        stateName = stateTokenName (registrySeed env)
        configName = configurationTokenName (registryIdentity env)
        stateMinted = tokenValue (statePolicyId env) stateName 1
        configMinted = tokenValue (applicationPolicy env) configName 1
        minted = stateMinted <> configMinted
        stateOut =
            mkBasicTxOut
                (stateAddress env)
                (MaryValue (Coin recordLovelace) stateMinted)
                & datumTxOutL .~ mkInlineDatum (stateDatumData emptyRoot)
        configOut parameters =
            mkBasicTxOut
                (applicationAddress env)
                (MaryValue (Coin recordLovelace) configMinted)
                & datumTxOutL
                    .~ mkInlineDatum
                        ( heldDatumData
                            ( Configuration
                                parameters
                                (ScriptCredential (scriptHashBytes (envCheckpointHash env)))
                            )
                        )
        changeCoin = unCoin (snd seedUtxo ^. coinTxOutL) - 2 * recordLovelace - genesisFee
        changeOut = mkBasicTxOut (envOwner env) (inject (Coin changeCoin))
        inputs = Set.singleton seedIn
        stateIx = fromIntegral (mintingIndex (statePolicyId env) minted)
        appIx = fromIntegral (mintingIndex (applicationPolicy env) minted)
        build parameters budgets = do
            params <-
                withinSecs 30 (label <> ": query parameters") $
                    queryProtocolParams (envProvider env)
            let purposes =
                    [ (ConwayMinting (AsIx stateIx), stateMintData (Genesis (registrySeed env)), scriptExUnits)
                    ,
                        ( ConwayMinting (AsIx appIx)
                        , List [actionData (CreateConfiguration (registryIdentity env) (registrySeed env) 1)]
                        , scriptExUnits
                        )
                    ]
                redeemers = redeemerMap budgets purposes
                body =
                    mkBasicTxBody
                        & inputsTxBodyL .~ inputs
                        & outputsTxBodyL .~ StrictSeq.fromList [stateOut, configOut parameters, changeOut]
                        & feeTxBodyL .~ Coin genesisFee
                        & mintTxBodyL .~ minted
                        & collateralInputsTxBodyL .~ Set.singleton collateralIn
                        & referenceInputsTxBodyL .~ Set.fromList refs
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) params redeemers (TxDats mempty)
            pure
                ( mkBasicTx body & witsTxL . rdmrsTxWitsL .~ redeemers
                , Set.fromList [purpose | (purpose, _, _) <- purposes]
                )
    let terms = registryParameters (envTerms env)
    -- the same genesis with one fact changed, a negative registration cost, is refused
    refusal <- fst <$> build terms{registrationCost = -1} Map.empty
    refusedAt env "genesis with a negative registration cost" (ownerParty env) (ConwayMinting (AsIx appIx)) refusal
    txId <- submitTwoPassBy (ownerParty env) env label (build terms)
    stateUtxo <-
        pollOutput (envProvider env) txId [0] (holdsRegistryToken env stateName)
            >>= requireJust (label <> ": the state output did not settle")
    configUtxo <-
        pollOutput (envProvider env) txId [1] (hasAsset (applicationPolicy env) configName)
            >>= requireJust (label <> ": the configuration record did not settle")
    dbg (label <> ": state " <> show (fst stateUtxo) <> " configuration " <> show (fst configUtxo))
    dbg
        ( label
            <> ": registry identity: state policy "
            <> hexOf (registryStatePolicy (registryIdentity env))
            <> " name "
            <> hexOf (registryName (registryIdentity env))
            <> " checkpoint validator "
            <> hexOf (scriptHashBytes (envCheckpointHash env))
            <> " application "
            <> hexOf (scriptHashBytes (envApplicationHash env))
            <> " genesis transaction "
            <> show txId
        )
    pure
        env
            { envTemplateOutput = Just templateOut
            , envApplicationReference = Just applicationRef
            , envStateReference = Just stateRef
            , envConfiguration = Just configUtxo
            }
  where
    recordLovelace = 3_000_000
    genesisFee = 3_000_000

-- | The redeemers of a set of purposes, each with its budget or the fallback.
redeemerMap ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    [(ConwayPlutusPurpose AsIx ConwayEra, PLC.Data, ExUnits)] ->
    Redeemers ConwayEra
redeemerMap budgets purposes =
    Redeemers $
        Map.fromList
            [ (purpose, (ledgerData redeemer, Map.findWithDefault fallback purpose budgets))
            | (purpose, redeemer, fallback) <- purposes
            ]

-- | Bytes as lowercase hexadecimal text, for the lines a run prints.
hexOf :: ByteString -> String
hexOf = B8.unpack . convertToBase Base16

-- | The registry's empty root.
emptyRoot :: ByteString
emptyRoot = BS.replicate 32 0

-- | A booked request: its output and the record it carries.
data Booking = Booking
    { bookingOutput :: !(TxIn, TxOut ConwayEra)
    , bookingRecord :: !RegistrationData
    , bookingValidity :: !ValidityPlan
    }

{- | The record a request commits for a registration fixture, booked over the
validity interval: the identity's initial live datum born at the interval's
upper bound, the deposit, and the deadline the registry's processing time gives.
-}
registrationRecord ::
    CheckpointEnv -> RegistrationFixture -> ValidityPlan -> RegistrationData
registrationRecord env fixture validity =
    RegistrationData
        { requestRegistry = registryIdentity env
        , requestKey = key
        , requestController = ownerKeyHash
        , requestRefundAddress = plutusAddressOf (envOwner env)
        , requestHoldingAddress =
            unstakedAddress (ScriptCredential (scriptHashBytes (envCheckpointHash env)))
        , requestInitialDatum = asPlcData (V2 facts)
        , requestDeposit = requestDeposit' env
        , requestBookedAt = upperPosixMs validity
        , requestProcessDeadline = upperPosixMs validity + processTime parameters
        , requestReclaimEnd = upperPosixMs validity + processTime parameters
        }
  where
    parameters = registryParameters (envTerms env)
    facts = registeredFacts env fixture validity
    key = case facts of
        Live{lvAid} -> lvAid
        TerminationPending{} -> error "registrationRecord: a fixture is live"
    ownerKeyHash = case plutusAddressOf (envOwner env) of
        PlutusAddress (KeyCredential hash) _ -> hash
        _ -> error "registrationRecord: the owner holds a key"

-- | The approval token of a request.
approvalOf :: RegistrationData -> ByteString
approvalOf record =
    registrationApprovalName
        (requestRegistry record)
        (requestKey record)
        (requestHoldingAddress record)
        (requestInitialDatum record)
        (requestDeposit record)

-- | A reference input holding the configuration record.
configurationOf :: CheckpointEnv -> IO (TxIn, TxOut ConwayEra)
configurationOf env =
    requireJust "the registry's configuration record is absent" (envConfiguration env)

applicationReferenceOf :: CheckpointEnv -> IO (TxIn, TxOut ConwayEra)
applicationReferenceOf env =
    requireJust "the application reference script is absent" (envApplicationReference env)

stateReferenceOf :: CheckpointEnv -> IO (TxIn, TxOut ConwayEra)
stateReferenceOf env =
    requireJust "the state reference script is absent" (envStateReference env)

{- | Book a registration: the identity owner pays the request, which holds the
deposit, the registration cost and the tip, and the application mints its
approval.
-}
bookRegistration :: CheckpointEnv -> RegistrationFixture -> IO Booking
bookRegistration env fixture = do
    let label = "registration booking"
    validity <- tipValidity env label
    let record = registrationRecord env fixture validity
        approval = approvalOf record
    txId <- submitTwoPassBy (ownerParty env) env label (bookingTx env record validity 0)
    booked <-
        pollOutput (envProvider env) txId [0] (hasAsset (applicationPolicy env) approval)
            >>= requireJust (label <> ": the request did not settle")
    pure Booking{bookingOutput = booked, bookingRecord = record, bookingValidity = validity}

{- | The booking transaction of a request over a validity interval. The request holds
the lovelace the registry requires, moved by the given difference: zero is the
booking the application accepts.
-}
bookingTx ::
    CheckpointEnv ->
    RegistrationData ->
    ValidityPlan ->
    Integer ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    IO (ConwayTx, Set.Set (ConwayPlutusPurpose AsIx ConwayEra))
bookingTx env record validity difference budgets = do
    let label = "registration booking"
        approval = approvalOf record
        minted = tokenValue (applicationPolicy env) approval 1
        held = requestLovelace env + difference
        requestOut =
            mkBasicTxOut
                (applicationAddress env)
                (MaryValue (Coin held) minted)
                & datumTxOutL .~ mkInlineDatum (heldDatumData (Registration record))
    applicationRef <- applicationReferenceOf env
    configuration <- configurationOf env
    params <-
        withinSecs 30 (label <> ": query parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 (label <> ": query wallet") $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateral) <- pickDisjoint wallet []
    let (feeIn, feeOut) = feeUtxo
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (inject (Coin (unCoin (feeOut ^. coinTxOutL) - held - simpleFee)))
        purposes =
            [
                ( ConwayMinting (AsIx 0)
                , List [actionData (BookRegistration 0)]
                , scriptExUnits
                )
            ]
        redeemers = redeemerMap budgets purposes
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton feeIn
                & outputsTxBodyL .~ StrictSeq.fromList [requestOut, changeOut]
                & feeTxBodyL .~ Coin simpleFee
                & mintTxBodyL .~ minted
                & collateralInputsTxBodyL .~ Set.singleton (fst collateral)
                & referenceInputsTxBodyL
                    .~ Set.fromList [fst configuration, fst applicationRef]
                & vldtTxBodyL
                    .~ ValidityInterval (SJust (lowerSlot validity)) (SJust (upperSlot validity))
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity (Set.singleton PlutusV3) params redeemers (TxDats mempty)
    pure
        ( mkBasicTx body & witsTxL . rdmrsTxWitsL .~ redeemers
        , Set.fromList [purpose | (purpose, _, _) <- purposes]
        )

simpleFee :: Integer
simpleFee = 3_000_000

foldFee :: Integer
foldFee = 4_000_000

{- | The fold of a booked request into the registry by a party: the registration
observer attests the inception, the state script inserts the key, the
application burns the approval and the holding is delivered to the checkpoint
address.
-}
data FoldPlan = FoldPlan
    { foldBooking :: !Booking
    , foldFixture :: !RegistrationFixture
    , foldProof :: !(TxIn, TxOut ConwayEra)
    -- ^ the hash-proof output the fold burns
    , foldReferences :: ![(TxIn, TxOut ConwayEra)]
    -- ^ the references of the lifecycle observer and the hash-proof policy
    , foldRegistered :: ![ByteString]
    -- ^ the keys the registry already holds
    , foldState :: !(Maybe (TxIn, TxOut ConwayEra))
    -- ^ the registry state output the fold spends; the chain's current one when absent
    , foldValidity :: !ValidityPlan
    , foldParty :: !Party
    }

buildFoldTx ::
    CheckpointEnv ->
    FoldPlan ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    IO (ConwayTx, Set.Set (ConwayPlutusPurpose AsIx ConwayEra))
buildFoldTx env plan budgets = do
    let label = "registration fold"
        Booking{bookingOutput = (requestIn, requestOut), bookingRecord = record} = foldBooking plan
        party = foldParty plan
        fixture = foldFixture plan
        (proofIn, proofOut) = foldProof plan
        key = requestKey record
        active = activeTokenName (registryIdentity env) key
        approval = approvalOf record
        proofName = rfProofName fixture
    params <-
        withinSecs 30 (label <> ": query parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 (label <> ": query wallet") $
            queryUTxOs (envProvider env) (partyAddr party)
    stateUtxo <- maybe (currentState env) pure (foldState plan)
    foldGuard (foldRegistered plan) key (snd stateUtxo)
    (feeUtxo, collateral) <- pickDisjoint wallet [proofIn]
    applicationRef <- applicationReferenceOf env
    stateRef <- stateReferenceOf env
    configuration <- configurationOf env
    let (stateIn, stateOutBefore) = stateUtxo
        (feeIn, feeOut) = feeUtxo
        minted =
            tokenValue (applicationPolicy env) approval (-1)
                <> tokenValue (statePolicyId env) active 1
                <> tokenValue (envHashProofPolicy env) proofName (-1)
        holding =
            mkBasicTxOut
                (roleAddress env Active)
                (MaryValue (Coin (requestDeposit record)) (tokenValue (statePolicyId env) active 1))
                & datumTxOutL .~ mkInlineDatum (requestInitialDatum record)
        stateOut =
            mkBasicTxOut
                (stateAddress env)
                ( MaryValue
                    (stateOutBefore ^. coinTxOutL)
                    (tokenValue (statePolicyId env) (stateTokenName (registrySeed env)) 1)
                )
                & datumTxOutL .~ mkInlineDatum (stateDatumData newRoot)
        cost = registrationCost (registryParameters (envTerms env))
        (proofSteps, newRoot) = registryProof (foldRegistered plan) key
        changeCoin =
            unCoin (requestOut ^. coinTxOutL)
                + unCoin (feeOut ^. coinTxOutL)
                + unCoin (proofOut ^. coinTxOutL)
                - requestDeposit record
                - cost
                - foldFee
        changeOut = mkBasicTxOut (partyAddr party) (inject (Coin changeCoin))
        inputs = Set.fromList [requestIn, stateIn, feeIn, proofIn]
        mintIx policy = fromIntegral (mintingIndex policy minted)
        references = foldReferences plan
        purposes =
            [
                ( ConwaySpending (AsIx (spendingIndex requestIn inputs))
                , spendActionData (FoldRegistration 0)
                , scriptExUnits
                )
            ,
                ( ConwaySpending (AsIx (spendingIndex stateIn inputs))
                , stateSpendData
                    (registrySeed env)
                    [ Register
                        { changeRequest = outputReferenceOf' requestIn
                        , changeKey = key
                        , changeHolding = 0
                        , changeDeposit = requestDeposit record
                        , changeProof = proofSteps
                        }
                    ]
                , scriptExUnits
                )
            , (ConwayMinting (AsIx (mintIx (applicationPolicy env))), List [], scriptExUnits)
            , (ConwayMinting (AsIx (mintIx (statePolicyId env))), stateMintData Folded, scriptExUnits)
            ,
                ( ConwayMinting (AsIx (mintIx (envHashProofPolicy env)))
                , hashProofBurnRedeemerData
                , hashProofBurnExUnits
                )
            ,
                ( ConwayRewarding (AsIx 0)
                , registerObserverRedeemerData
                    (policyBytes (envCheckpointPolicy env))
                    (rfEvidence fixture)
                , scriptExUnits
                )
            ]
        redeemers = redeemerMap budgets purposes
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ inputs
                & outputsTxBodyL .~ StrictSeq.fromList [holding, stateOut, changeOut]
                & feeTxBodyL .~ Coin foldFee
                & mintTxBodyL .~ minted
                & withdrawalsTxBodyL
                    .~ Withdrawals
                        ( Map.singleton
                            (AccountAddress Testnet (AccountId (ScriptHashObj (envLifecycleHash env))))
                            (Coin 0)
                        )
                & treasuryDonationTxBodyL .~ Coin cost
                & collateralInputsTxBodyL .~ Set.singleton (fst collateral)
                & referenceInputsTxBodyL
                    .~ Set.fromList
                        (fst configuration : fst applicationRef : fst stateRef : map fst references)
                & vldtTxBodyL
                    .~ ValidityInterval
                        (SJust (lowerSlot (foldValidity plan)))
                        (SJust (upperSlot (foldValidity plan)))
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity (Set.singleton PlutusV3) params redeemers (TxDats mempty)
    pure
        ( mkBasicTx body & witsTxL . rdmrsTxWitsL .~ redeemers
        , Set.fromList [purpose | (purpose, _, _) <- purposes]
        )

{- | What the builder checks before it computes anything for a fold: the request's
key is not one the registry holds, and the keys it was given are the registry
the chain holds (their root is the state output's datum). Either failure is
thrown as a 'FoldRefusal' and no transaction is built.
-}
foldGuard :: [ByteString] -> ByteString -> TxOut ConwayEra -> IO ()
foldGuard registered key stateOut = do
    mapM_ throwIO (foldRefusal registered key)
    when (rawInlineData stateOut /= Just (stateDatumData (registryRoot registered))) $
        throwIO KeysAreNotTheRegistry

-- | The root of a registry holding exactly the given keys.
registryRoot :: [ByteString] -> ByteString
registryRoot [] = emptyRoot
registryRoot registered =
    Registry.rootOf (Registry.build [(held, activeLeaf) | held <- registered])

{- | The proof that a key is absent from the registry that holds the keys, and
the root after it is inserted: the registry binds every key to the active leaf.
-}
registryProof :: [ByteString] -> ByteString -> ([PLC.Data], ByteString)
registryProof registered key =
    ( map asPlcData (prove tree key)
    , Registry.rootOf tree
    )
  where
    tree = Registry.build [(held, activeLeaf) | held <- registered <> [key]]

-- | The state output of the registry, as the chain holds it now.
currentState :: CheckpointEnv -> IO (TxIn, TxOut ConwayEra)
currentState env = do
    outputs <-
        withinSecs 30 "query the registry state" $
            queryUTxOs (envProvider env) (stateAddress env)
    requireJust
        "the registry state output is absent"
        ( find
            ( holdsRegistryToken
                env
                (stateTokenName (registrySeed env))
                . snd
            )
            outputs
        )

{- | The hash-proof mint of a registration fixture, paid to a party: the
evidence the fold burns.
-}
mintHashProof :: CheckpointEnv -> Party -> RegistrationFixture -> IO (TxIn, TxOut ConwayEra)
mintHashProof env party fixture = do
    proofTx <-
        withinSecs 90 "build hash-proof mint" (buildHashProofMintTx env party fixture)
    proofTxId <- submitSettlingBy env party "hash-proof mint" proofTx
    pollOutput
        (envProvider env)
        proofTxId
        [0, 1]
        (hasAsset (envHashProofPolicy env) (rfProofName fixture))
        >>= requireJust "hash-proof output did not settle"

-- | Fold a booked request into the registry; the party pays and signs.
foldRegistration ::
    CheckpointEnv ->
    [(TxIn, TxOut ConwayEra)] ->
    Party ->
    RegistrationFixture ->
    Booking ->
    (TxIn, TxOut ConwayEra) ->
    IO (TxId, ValidityPlan)
foldRegistration env references party fixture booking proof = do
    validity <- tipValidity env "registration fold"
    let plan =
            FoldPlan
                { foldBooking = booking
                , foldFixture = fixture
                , foldProof = proof
                , foldReferences = references
                , foldRegistered = []
                , foldState = Nothing
                , foldValidity = validity
                , foldParty = party
                }
    txId <- submitTwoPassBy party env "registration fold" (buildFoldTx env plan)
    pure (txId, validity)

{- | The return of a booked request after its deadline: the refund address is
paid everything but the tip, and the returner keeps the tip.
-}
buildReturnTx ::
    CheckpointEnv ->
    Party ->
    Booking ->
    ValidityPlan ->
    Addr ->
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    IO (ConwayTx, Set.Set (ConwayPlutusPurpose AsIx ConwayEra))
buildReturnTx env party booking validity refundTo budgets = do
    let label = "registration return"
        Booking{bookingOutput = (requestIn, requestOut), bookingRecord = record} = booking
        tip = minimumTip (registryParameters (envTerms env))
        approval = approvalOf record
        minted = tokenValue (applicationPolicy env) approval (-1)
    params <-
        withinSecs 30 (label <> ": query parameters") $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 (label <> ": query wallet") $
            queryUTxOs (envProvider env) (partyAddr party)
    (feeUtxo, collateral) <- pickDisjoint wallet []
    applicationRef <- applicationReferenceOf env
    configuration <- configurationOf env
    let (feeIn, feeOut) = feeUtxo
        refund = unCoin (requestOut ^. coinTxOutL) - tip
        refundOut = mkBasicTxOut refundTo (inject (Coin refund))
        changeCoin = unCoin (feeOut ^. coinTxOutL) + tip - simpleFee
        changeOut = mkBasicTxOut (partyAddr party) (inject (Coin changeCoin))
        inputs = Set.fromList [requestIn, feeIn]
        purposes =
            [
                ( ConwaySpending (AsIx (spendingIndex requestIn inputs))
                , spendActionData ReturnRegistration
                , scriptExUnits
                )
            , (ConwayMinting (AsIx 0), List [], scriptExUnits)
            ]
        redeemers = redeemerMap budgets purposes
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ inputs
                & outputsTxBodyL .~ StrictSeq.fromList [refundOut, changeOut]
                & feeTxBodyL .~ Coin simpleFee
                & mintTxBodyL .~ minted
                & collateralInputsTxBodyL .~ Set.singleton (fst collateral)
                & referenceInputsTxBodyL
                    .~ Set.fromList [fst configuration, fst applicationRef]
                & vldtTxBodyL
                    .~ ValidityInterval (SJust (lowerSlot validity)) (SJust (upperSlot validity))
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity (Set.singleton PlutusV3) params redeemers (TxDats mempty)
    pure
        ( mkBasicTx body & witsTxL . rdmrsTxWitsL .~ redeemers
        , Set.fromList [purpose | (purpose, _, _) <- purposes]
        )

{- | Whether the node's evaluation of a transaction fails in the script of the
purpose and in no other way: the refusal of the application, not a setup
failure.
-}
refusedAt ::
    CheckpointEnv ->
    String ->
    Party ->
    ConwayPlutusPurpose AsIx ConwayEra ->
    ConwayTx ->
    IO ()
refusedAt env label party purpose tx = do
    observed <-
        withinSecs 120 (label <> ": evaluate") $
            evaluateTx (envProvider env) (addKeyWitness (partyKey party) tx)
    case Map.lookup purpose observed of
        Just (Left failure) ->
            dbg (label <> ": refused as expected: " <> oneLine (show failure))
        Just (Right units) ->
            fail (label <> ": the validator accepted a transaction that must be refused: " <> show units)
        Nothing ->
            fail (label <> ": the evaluation did not cover " <> show purpose)

-- | The spend purpose of a booked request in a transaction that spends it.
requestSpendPurpose ::
    Booking -> ConwayTx -> ConwayPlutusPurpose AsIx ConwayEra
requestSpendPurpose booking tx =
    ConwaySpending
        ( AsIx
            ( spendingIndex
                (fst (bookingOutput booking))
                (tx ^. bodyTxL . inputsTxBodyL)
            )
        )

{- | The journey of identities through the registry. The first books, a
different party folds, and the checkpoint stands at the validator's address
holding its deposit and the active token, with the registry's root moved. A
second identity books and is not folded: the same fold is accepted inside its
window and refused after the deadline, a return that pays another address is
refused, and the return to the refund address is accepted and pays everything
but the tip.
-}
registryJourney :: CheckpointEnv -> IO ()
registryJourney env = do
    (fixture, _) <- loadLifecycleFixture
    other <- rsRegistration <$> loadRotateStoryFixture
    references <- deployRegisterReferences env
    shortValidity <- tipValidity env "booking one lovelace short"
    (shortTx, _) <-
        bookingTx env (registrationRecord env fixture shortValidity) shortValidity (-1) Map.empty
    refusedAt env "booking one lovelace short" (ownerParty env) (ConwayMinting (AsIx 0)) shortTx
    (checkpoint, _) <- productionRegisterScenarioUsingReferences env references fixture
    let (checkpointIn, checkpointOut) = checkpointUtxo checkpoint
        key = checkpointKey env fixture
    unless (holdsCheckpointToken env (checkpointDatum checkpoint) checkpointOut) $
        fail "the delivered checkpoint does not hold the active token of its AID"
    unless (checkpointOut ^. addrTxOutL == roleAddress env Active) $
        fail "the delivered checkpoint is not at the checkpoint validator's address"
    unless (unCoin (checkpointOut ^. coinTxOutL) == requestDeposit' env) $
        fail "the delivered checkpoint does not hold the committed deposit"
    unless (extractDatum checkpointOut == Just (V2 (checkpointFacts checkpoint))) $
        fail "the delivered checkpoint does not carry the initial datum of the request"
    (_, stateAfter) <- currentState env
    unless (rawInlineData stateAfter == Just (stateDatumData (snd (registryProof [] key)))) $
        fail "the registry's root is not the root of the one registered key"
    dbg ("delivered checkpoint " <> show checkpointIn)
    -- a second identity, booked and left unfolded
    second <- bookRegistration env other
    proof <- mintHashProof env folderParty other
    let foldOf validity =
            buildFoldTx
                env
                FoldPlan
                    { foldBooking = second
                    , foldFixture = other
                    , foldProof = proof
                    , foldReferences = drop 1 references
                    , foldRegistered = [key]
                    , foldState = Nothing
                    , foldValidity = validity
                    , foldParty = folderParty
                    }
                Map.empty
        deadline = requestProcessDeadline (bookingRecord second)
    inWindow <- tipValidity env "second fold inside its window"
    (controlTx, controlPurposes) <- foldOf inWindow
    controlObserved <-
        withinSecs 120 "second fold inside its window: evaluate" $
            evaluateTx (envProvider env) (addKeyWitness (partyKey folderParty) controlTx)
    _ <- requireExactAllRight "second fold inside its window" controlPurposes controlObserved
    awaitChainTime env "second request deadline" deadline
    late <- tipValidity env "second fold after its deadline"
    (lateTx, _) <- foldOf late
    refusedAt env "fold after the deadline" folderParty (requestSpendPurpose second lateTx) lateTx
    returnValidity <- tipValidity env "registration return"
    unless (lowerPosixMs returnValidity >= deadline) $
        fail "the return interval does not start at the deadline"
    (strayTx, _) <-
        buildReturnTx env folderParty second returnValidity folderAddress Map.empty
    refusedAt
        env
        "return paying another address"
        folderParty
        (requestSpendPurpose second strayTx)
        strayTx
    returnTxId <-
        submitTwoPassBy
            folderParty
            env
            "registration return"
            (buildReturnTx env folderParty second returnValidity (envOwner env))
    refunded <-
        pollOutput
            (envProvider env)
            returnTxId
            [0]
            ( \out ->
                out ^. addrTxOutL == envOwner env
                    && unCoin (out ^. coinTxOutL)
                        == requestLovelace env - minimumTip (registryParameters (envTerms env))
            )
    unless (isJust refunded) $
        fail "the return did not pay the refund address everything but the tip"
    duplicateRegistrationJourney env references (checkpointUtxo checkpoint) key other

{- | A second registration of a registered AID cannot be folded. A new identity
is booked twice and the registry, which holds one key, is the state both folds
are built against. The second fold is accepted by the scripts when built; the
first is submitted and lands, delivering the booking's initial state although
the fold came later; the second, submitted after that, is refused by the ledger
because the registry state output it spends is consumed; and a fold of the same
booking built afterwards is refused by the builder. No refusal touches a
checkpoint or the registry's root.
-}
duplicateRegistrationJourney ::
    CheckpointEnv ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    ByteString ->
    RegistrationFixture ->
    IO ()
duplicateRegistrationJourney env references (heldIn, heldOut) heldKey fixture = do
    let newKey = checkpointKey env fixture
        secondParty = ownerParty env
        planFor booking proof party registered state validity =
            FoldPlan
                { foldBooking = booking
                , foldFixture = fixture
                , foldProof = proof
                , foldReferences = drop 1 references
                , foldRegistered = registered
                , foldState = state
                , foldValidity = validity
                , foldParty = party
                }
    firstBooking <- bookRegistration env fixture
    secondBooking <- bookRegistration env fixture
    firstProof <- mintHashProof env folderParty fixture
    secondProof <- mintHashProof env secondParty fixture
    preFold <- currentState env
    let secondPlan = planFor secondBooking secondProof secondParty
        secondFold registered state validity = buildFoldTx env (secondPlan registered state validity)
    -- the second fold, built against the registry as it stands, is accepted by the scripts
    built <- tipValidity env "second fold, built before the first lands"
    (beforeTx, beforePurposes) <- secondFold [heldKey] (Just preFold) built Map.empty
    beforeObserved <-
        withinSecs 120 "second fold, built before the first lands: evaluate" $
            evaluateTx (envProvider env) (addKeyWitness (partyKey secondParty) beforeTx)
    beforeUnits <-
        requireExactAllRight "second fold, built before the first lands" beforePurposes beforeObserved
    -- the first fold, for a new key, lands
    firstValidity <- tipValidity env "first fold"
    firstTxId <-
        submitTwoPassBy
            folderParty
            env
            "first fold"
            (buildFoldTx env (planFor firstBooking firstProof folderParty [heldKey] Nothing firstValidity))
    (deliveredIn, deliveredOut) <-
        pollOutput (envProvider env) firstTxId [0] (holdsCheckpointToken env (rfDatum fixture))
            >>= requireJust "the delivered checkpoint of the first fold did not settle"
    dbg ("registration fold transaction " <> show firstTxId <> " (new key)")
    unless (extractDatum deliveredOut == Just (V2 (registeredFacts env fixture (bookingValidity firstBooking)))) $
        fail "the delivered checkpoint does not carry the booking's initial state"
    unless (upperPosixMs (bookingValidity firstBooking) < lowerPosixMs firstValidity) $
        fail "the first fold did not come after its booking"
    (_, stateAfter) <- currentState env
    let rootAfter = stateDatumData (registryRoot [heldKey, newKey])
        unchangedAfter what = do
            -- both checkpoints and the registry's root are as the first fold left them
            held <-
                withinSecs 30 "query the checkpoints" $
                    queryUTxOByTxIn (envProvider env) (Set.fromList [heldIn, deliveredIn])
            unless
                ( Map.lookup heldIn held == Just heldOut
                    && Map.lookup deliveredIn held == Just deliveredOut
                )
                $ fail ("a checkpoint changed after " <> what)
            (_, stateNow) <- currentState env
            unless (rawInlineData stateNow == Just rootAfter) $
                fail ("the registry's root changed after " <> what)
    unless (rawInlineData stateAfter == Just rootAfter) $
        fail "the registry's root is not the root of its two keys"
    -- the second fold, built against the state the first consumed, is refused by the ledger
    retry <- tipValidity env "second fold, submitted after the first landed"
    (retryTx, _) <-
        secondFold [heldKey] (Just preFold) retry (Map.map deterministicMargin beforeUnits)
    refused <-
        withinSecs 60 "submit the second fold" $
            submitTx (envSubmitter env) (addKeyWitness (partyKey secondParty) retryTx)
    case refused of
        Submitted _ -> fail "the ledger accepted a second fold against a consumed registry state"
        Rejected reason -> do
            dbg ("second fold refused: " <> oneLine (B8.unpack reason))
            unless (consumedInputAlone (show (fst preFold)) (B8.unpack reason)) $
                fail "the second fold was refused, but not for the consumed registry state alone"
    unchangedAfter "the ledger's refusal of the second fold"
    -- the second fold built honestly now is refused by the builder
    now <- tipValidity env "second fold, built after the first landed"
    asBuilt <- try (secondFold [heldKey, newKey] Nothing now Map.empty)
    case asBuilt of
        Left (KeyAlreadyRegistered refusedKey)
            | refusedKey == newKey -> pure ()
        Left refusal -> fail ("the builder refused for another reason: " <> show refusal)
        Right _ -> fail "the builder built a fold for a registered key"
    unchangedAfter "the builder's refusal of a registered key"
    staleList <- try (secondFold [heldKey] Nothing now Map.empty)
    case staleList of
        Left KeysAreNotTheRegistry -> pure ()
        Left refusal -> fail ("the builder refused for another reason: " <> show refusal)
        Right _ -> fail "the builder trusted keys that are not the registry"
    unchangedAfter "the builder's refusal of keys that are not the registry"

{- | Wait until the start of the ledger tip's slot is at or after an instant,
which may be farther away than the node's forecast reaches.
-}
awaitChainTime :: CheckpointEnv -> String -> Integer -> IO ()
awaitChainTime env label instant = go (pollAttempts * 8)
  where
    go remaining
        | remaining <= 0 = fail (label <> ": the chain did not reach " <> show instant)
        | otherwise = do
            snapshot <-
                withinSecs 30 (label <> ": query the tip") $
                    queryLedgerSnapshot (envProvider env)
            now <- slotStartPosixMs env (ledgerTipSlot snapshot)
            if now >= instant
                then pure ()
                else threadDelay 1_000_000 >> go (remaining - 1 :: Int)

-- | The key a registration fixture registers: the AID's qualified text.
checkpointKey :: CheckpointEnv -> RegistrationFixture -> ByteString
checkpointKey env fixture =
    case registeredFacts env fixture (ValidityPlan (SlotNo 0) (SlotNo 0) 0 0) of
        Live{lvAid} -> lvAid
        TerminationPending{} -> error "checkpointKey: a fixture is live"

-- | Book a registration, mint its proof, and fold it with the other party.
productionRegisterScenarioUsingReferences ::
    CheckpointEnv ->
    [(TxIn, TxOut ConwayEra)] ->
    RegistrationFixture ->
    IO (CheckpointInput, (TxIn, TxOut ConwayEra))
productionRegisterScenarioUsingReferences env references fixture = do
    checkpointRef <- requireJust "checkpoint_register reference is absent" (listToMaybe references)
    proof <- mintHashProof env folderParty fixture
    booking <- bookRegistration env fixture
    (foldTxId, validity) <-
        foldRegistration env (drop 1 references) folderParty fixture booking proof
    let facts = registeredFacts env fixture (bookingValidity booking)
    delivered <-
        pollOutput
            (envProvider env)
            foldTxId
            [0]
            (holdsCheckpointToken env (rfDatum fixture))
            >>= requireJust "the delivered checkpoint did not settle"
    dbg ("registration fold transaction " <> show foldTxId)
    dbg ("fold validity " <> show validity)
    pure
        ( CheckpointInput
            { checkpointUtxo = delivered
            , checkpointDatum = rfDatum fixture
            , checkpointFacts = facts
            }
        , checkpointRef
        )
