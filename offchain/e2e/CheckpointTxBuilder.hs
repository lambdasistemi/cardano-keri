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
    productionRegisterAdvanceScenario,
    productionRegisterConvictScenario,
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
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
    advancePredicate,
 )
import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    BountyAction (..),
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
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (EnforcementEvidence (..))
import Cardano.KERI.AID.Checkpoint.Entitlement (
    EntitledEnforcementPlan (..),
    enforcementEvidenceDigest,
    prepareEntitledEnforcement,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Inclusivity (..),
    RawBound (..),
    Role (..),
    roleHash,
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
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceObserverRedeemerData,
    advanceSpendRedeemerData,
    asPlcData,
    convictBurnRedeemerData,
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    registerObserverRedeemerData,
 )
import Cardano.KERI.AID.E2E.Datum (extractDatum, mkInlineDatum)
import Cardano.KERI.AID.E2E.Script (
    ScriptArtifact (..),
    applyCommitmentParams,
    computeScriptHash,
    deriveCommitmentFamily,
    deriveV1Scripts,
    extractCompiledCodeExact,
    loadBlueprint,
    mkCageScript,
    scriptHashBytes,
    v1CommitmentParameters,
    v1FreezeBond,
    v1RegistrationBond,
 )
import Cardano.KERI.AID.Migration.Types (OutputRef (..))
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
import Control.Exception (finally)
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
import Data.Functor ((<&>))
import Data.List (elemIndex, find, isInfixOf, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe)
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
    , envProvider :: !(Provider IO)
    , envSubmitter :: !(Submitter IO)
    , envOwner :: !Addr
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

checkpointMinAda :: Integer
checkpointMinAda = 2_000_000

registrationBond :: Integer
registrationBond = v1RegistrationBond

freezeBond :: Integer
freezeBond = v1FreezeBond

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
    env <- mkCheckpointEnv blueprintPath lsq ltxs
    verifyRegisterScriptSizes env
    prepareWallet env
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
    action
        env
            { envAdvanceReference = Just advanceRef
            , envEnforcementReference = Just enforcementRef
            , envEntitlementReference = Just entitlementRef
            , envCommitmentReference = Just commitmentRef
            }

mkCheckpointEnv :: FilePath -> LSQChannel -> LTxSChannel -> IO CheckpointEnv
mkCheckpointEnv blueprintPath lsq ltxs = do
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    artifacts <- either fail pure (deriveV1Scripts blueprint)
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
    -- #339: re-derived from the applied advance program after the version 2
    -- checkpoint datum work, not reused from #254 S254-E (14_876). The shared
    -- key-material verdict that datum_well_formed now delegates to moves the
    -- checkpoint, observer-advance and observer-lifecycle programs; the
    -- version 2 constructor of the datum sum moves only observer-migration,
    -- through its version-sum reads. Transitive compiled drift; the 16_133
    -- ceiling is unchanged.
    unless (SBS.length (envAdvanceBytes env) == 14_867) $
        fail
            ( "observer_advance applied program changed from 14,867 bytes: "
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

productionRegisterScenarioUsingReferences ::
    CheckpointEnv ->
    [(TxIn, TxOut ConwayEra)] ->
    RegistrationFixture ->
    IO (CheckpointInput, (TxIn, TxOut ConwayEra))
productionRegisterScenarioUsingReferences env referenceUtxos fixture = do
    checkpointRef <-
        requireJust
            "checkpoint_register reference is absent"
            (listToMaybe referenceUtxos)
    proofTx <- withinSecs 90 "build hash-proof mint" (buildHashProofMintTx env fixture)
    proofTxId <- submitSettling env "hash-proof mint" proofTx
    proofUtxo <-
        pollOutput
            (envProvider env)
            proofTxId
            [0, 1]
            (hasAsset (envHashProofPolicy env) (rfProofName fixture))
            >>= requireJust "hash-proof output did not settle"
    registerTxId <-
        submitTwoPassRegister
            env
            "checkpoint Register"
            referenceUtxos
            fixture
            proofUtxo
    let checkpointName = deriveAidAssetName (cdCesrAid (rfDatum fixture))
    registered <-
        pollOutput
            (envProvider env)
            registerTxId
            [0, 1]
            (hasAsset (envCheckpointPolicy env) checkpointName)
            >>= requireJust "registered checkpoint output did not settle"
    assertActiveCheckpoint env fixture registered
    pure
        ( CheckpointInput
            { checkpointUtxo = registered
            , checkpointDatum = rfDatum fixture
            }
        , checkpointRef
        )

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
            (hasAsset (envCheckpointPolicy env) (deriveAidAssetName (cdCesrAid created)))
            >>= requireJust "Advance successor did not settle"
    unless
        (snd successor ^. addrTxOutL == roleAddress env Active)
        (fail "Advance successor is not at the ACTIVE address")
    unless
        (snd successor ^. valueTxOutL == snd (checkpointUtxo registered) ^. valueTxOutL)
        (fail "Advance did not preserve the complete registered value")
    case extractDatum (snd successor) of
        Just (V1 datum)
            | datum == created -> pure ()
        _ -> fail "Advance successor does not carry the exact rotated V1 datum"
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
                    ConvictEntitlement
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
            ConvictEntitlement
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
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (rsCreated firstRotation)))
            )
            >>= requireJust ("Convict " <> row <> " first Advance did not settle")
    let firstAdvanced =
            CheckpointInput
                { checkpointUtxo = firstAdvancedUtxo
                , checkpointDatum = rsCreated firstRotation
                }
        recordedEvidence =
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
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (rsCreated recordedRotation)))
            )
            >>= requireJust ("Convict " <> row <> " ACTIVE source did not settle")
    unless
        (snd advancedUtxo ^. addrTxOutL == roleAddress env Active)
        (fail ("Convict " <> row <> " source is not ACTIVE"))
    case extractDatum (snd advancedUtxo) of
        Just (V1 datum)
            | datum == rsCreated recordedRotation -> pure ()
        _ -> fail ("Convict " <> row <> " source datum is not the conflict tip")
    pure
        CheckpointInput
            { checkpointUtxo = advancedUtxo
            , checkpointDatum = rsCreated recordedRotation
            }

advanceRejection :: CheckpointEnv -> IO RejectionEvidence
advanceRejection env = do
    prepareWallet env
    (fixture, _) <- loadLifecycleFixture
    staged <- stageCheckpointInput env (rfDatum fixture)
    validity <- currentValidity env
    tx <-
        buildAdvanceTx
            env
            staged
            (checkpointDatum staged)
            dummyAdvanceEvidence
            validity
    expectProductionScriptRejection env "Advance" tx

hashProofMintOldCostRejection :: CheckpointEnv -> IO RejectionEvidence
hashProofMintOldCostRejection env = do
    prepareWallet env
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

data RotateStoryFixture = RotateStoryFixture
    { rsRegistration :: !RegistrationFixture
    , rsCreated :: !CheckpointDatumV1
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

data RegisterScriptPlan = RegisterScriptPlan
    { rspWithdrawals :: !Withdrawals
    , rspRedeemers :: !(Redeemers ConwayEra)
    }

registerScriptPlan ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    ScriptHash ->
    PolicyID ->
    RegistrationEvidence ->
    Word32 ->
    Word32 ->
    RegisterScriptPlan
registerScriptPlan budgets lifecycleHash checkpointPolicy evidence checkpointIx hashProofIx =
    RegisterScriptPlan
        { rspWithdrawals =
            Withdrawals $
                Map.singleton
                    (AccountAddress Testnet (AccountId (ScriptHashObj lifecycleHash)))
                    (Coin 0)
        , rspRedeemers =
            Redeemers $
                Map.fromList
                    [
                        ( ConwayMinting (AsIx checkpointIx)
                        ,
                            ( ledgerData registerRedeemerData
                            , budgetFor
                                (ConwayMinting (AsIx checkpointIx))
                                scriptExUnits
                            )
                        )
                    ,
                        ( ConwayMinting (AsIx hashProofIx)
                        ,
                            ( ledgerData hashProofBurnRedeemerData
                            , budgetFor
                                (ConwayMinting (AsIx hashProofIx))
                                hashProofBurnExUnits
                            )
                        )
                    ,
                        ( ConwayRewarding (AsIx 0)
                        ,
                            ( ledgerData
                                ( registerObserverRedeemerData
                                    (policyBytes checkpointPolicy)
                                    evidence
                                )
                            , budgetFor (ConwayRewarding (AsIx 0)) scriptExUnits
                            )
                        )
                    ]
        }
  where
    budgetFor purpose fallback = Map.findWithDefault fallback purpose budgets

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
            CheckpointDatumV1
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
    CheckpointDatumV1 ->
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
            CheckpointDatumV1
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
    params <- withinSecs 30 "query hash-proof protocol parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query hash-proof wallet" (queryUTxOs (envProvider env) (envOwner env))
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

buildRegisterTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    [(TxIn, TxOut ConwayEra)] ->
    CheckpointEnv ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildRegisterTxWith budgets referenceUtxos env fixture proofUtxo = do
    params <- withinSecs 30 "query Register protocol parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query Register wallet" (queryUTxOs (envProvider env) (envOwner env))
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
                (envLifecycleHash env)
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
                & referenceInputsTxBodyL .~ Set.fromList (map fst referenceUtxos)
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity
                        (Set.singleton PlutusV3)
                        params
                        (rspRedeemers plan)
                        (TxDats mempty)
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ (if null referenceUtxos then scriptWitnesses else Map.empty)
            & witsTxL . rdmrsTxWitsL .~ rspRedeemers plan

submitTwoPassRegister ::
    CheckpointEnv ->
    String ->
    [(TxIn, TxOut ConwayEra)] ->
    RegistrationFixture ->
    (TxIn, TxOut ConwayEra) ->
    IO TxId
submitTwoPassRegister env label referenceUtxos fixture proofUtxo = do
    let expected = registerEvaluationPurposes env
    discovery <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildRegisterTxWith Map.empty referenceUtxos env fixture proofUtxo
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness genesisSignKey discovery)
    discoveryUnits <- requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    final <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildRegisterTxWith finalBudgets referenceUtxos env fixture proofUtxo
    let signedFinal = addKeyWitness genesisSignKey final
        finalBytes = serialize (eraProtVerLow @ConwayEra) signedFinal
    finalObserved <-
        withinSecs 120 (label <> ": evaluate final binding") $
            evaluateTx (envProvider env) signedFinal
    finalUnits <- requireExactAllRight (label <> ": final") expected finalObserved
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
    params <- withinSecs 30 (label <> ": query final maximum") (queryProtocolParams (envProvider env))
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
            <> " budgets="
            <> show finalBudgets
        )
    result <-
        withinSecs 60 ("submit unchanged " <> label) $
            submitTx (envSubmitter env) signedFinal
    case result of
        Submitted txId -> pure txId
        Rejected reason -> fail (label <> " rejected: " <> B8.unpack reason)

buildRotateStoryTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    Maybe ValidityPlan ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildRotateStoryTxWith budgets env checkpointRef advanceRef input successor evidence validity = do
    params <-
        withinSecs 30 "query Advance protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Advance wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef, fst advanceRef]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        spendPurpose = ConwaySpending (AsIx stateIndex)
        rewardPurpose = ConwayRewarding (AsIx 0)
        expected = Set.fromList [spendPurpose, rewardPurpose]
        observerRedeemerData =
            advanceObserverRedeemerData
                (policyBytes (envCheckpointPolicy env))
                spentTxIdBytes
                spentIndex
                evidence
        stateOut =
            mkStateOutput
                env
                Active
                (snd (checkpointUtxo input) ^. valueTxOutL)
                (asPlcData (V1 successor))
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (-scriptFee) (feeOut ^. valueTxOutL))
        redeemers =
            Redeemers $
                Map.fromList
                    [
                        ( spendPurpose
                        ,
                            ( ledgerData advanceSpendRedeemerData
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
                & outputsTxBodyL .~ StrictSeq.fromList [stateOut, changeOut]
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
                [ mintPurpose
                , retirePurpose
                , spendPurpose
                , revealPurpose
                , enforcementPurpose
                , entitlementPurpose
                ]
        checkpointName =
            AssetName $
                SBS.toShort $
                    deriveAidAssetName (cdCesrAid (checkpointDatum input))
        markerName = AssetName (SBS.toShort (fst (eepBurn plan)))
        minted =
            MultiAsset $
                Map.fromList
                    [
                        ( envCheckpointPolicy env
                        , Map.singleton checkpointName (-1)
                        )
                    ,
                        ( envCommitmentPolicy env
                        , Map.singleton markerName (snd (eepBurn plan))
                        )
                    ]
        mintPurpose =
            ConwayMinting (AsIx (mintingIndex (envCheckpointPolicy env) minted))
        retirePurpose =
            ConwayMinting (AsIx (mintingIndex (envCommitmentPolicy env) minted))
        -- #280: the deposit refund sits at output zero for every settlement
        -- shape, so the payouts the register indexes shift one place along.
        refundOut =
            mkBasicTxOut
                (keyAddress (cpoRecipientPkh (eepRefund plan)))
                (inject (Coin (cpoLovelace (eepRefund plan))))
        protected = checkpointMinAda + registrationBond + freezeBond
        convictorOutputIndex = 1
        sourceCoin = unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
        surplus = sourceCoin - protected
        convictorOut =
            mkBasicTxOut
                (keyAddress convictor)
                (inject (Coin protected))
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (surplus - scriptFee) (feeOut ^. valueTxOutL))
        outputs = [refundOut, convictorOut, changeOut]
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
                        ( mintPurpose
                        ,
                            ( ledgerData (convictBurnRedeemerData spentTxIdBytes spentIndex)
                            , Map.findWithDefault
                                (ExUnits 1_500_000 800_000_000)
                                mintPurpose
                                budgets
                            )
                        )
                    ,
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
    unless (surplus >= 0) $
        fail
            ( "Convict source is below its protected reserve: source="
                <> show sourceCoin
                <> " protected="
                <> show protected
            )
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
    CheckpointDatumV1 ->
    String ->
    AdvanceEvidence ->
    IO ()
rejectRotateEvidence env checkpointRef advanceRef input successor label evidence = do
    (candidate, _) <-
        withinSecs 90 (label <> ": build applied candidate") $
            buildRotateStoryTxWith
                Map.empty
                env
                checkpointRef
                advanceRef
                input
                successor
                evidence
                Nothing
    _ <- expectProductionScriptRejection env label candidate
    pure ()

submitTwoPassAdvance ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    IO TxId
submitTwoPassAdvance env label checkpointRef advanceRef input successor evidence = do
    submitTwoPassAdvanceWithValidity
        env
        label
        checkpointRef
        advanceRef
        input
        successor
        evidence
        Nothing

submitTwoPassAdvanceWithValidity ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    Maybe ValidityPlan ->
    IO TxId
submitTwoPassAdvanceWithValidity env label checkpointRef advanceRef input successor evidence validity = do
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildRotateStoryTxWith
                Map.empty
                env
                checkpointRef
                advanceRef
                input
                successor
                evidence
                validity
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness genesisSignKey discovery)
    discoveryUnits <-
        requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    (final, finalExpected) <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildRotateStoryTxWith
                finalBudgets
                env
                checkpointRef
                advanceRef
                input
                successor
                evidence
                validity
    unless (finalExpected == expected) $
        fail (label <> ": final purpose set changed after budget binding")
    let signedFinal = addKeyWitness genesisSignKey final
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
                (error "registerEvaluationPurposes: missing policy")
                (elemIndex policy policies)

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
    CheckpointEnv -> CheckpointDatumV1 -> IO CheckpointInput
stageCheckpointInput env datum = do
    params <- withinSecs 30 "query staging protocol parameters" (queryProtocolParams (envProvider env))
    wallet <- withinSecs 30 "query staging wallet" (queryUTxOs (envProvider env) (envOwner env))
    feeUtxo <- requireJust "stageCheckpointInput: no wallet UTxO" (largestFirst wallet)
    let stagedOut =
            mkBasicTxOut
                (roleAddress env Active)
                (inject (Coin (checkpointMinAda + registrationBond + freezeBond)))
                & datumTxOutL .~ mkInlineDatum (asPlcData (V1 datum))
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
    pure CheckpointInput{checkpointUtxo = utxo, checkpointDatum = datum}

buildAdvanceTx ::
    CheckpointEnv ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    ValidityPlan ->
    IO ConwayTx
buildAdvanceTx env input successor evidence validity =
    buildCheckpointSpend
        env
        input
        (advanceRedeemerData evidence)
        validity
        [ mkStateOutput
            env
            Active
            (snd (checkpointUtxo input) ^. valueTxOutL)
            (asPlcData (V1 successor))
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

assertConvictSettlement ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    ByteString ->
    TxId ->
    IO ()
assertConvictSettlement env row input convictor convictTxId = do
    let outputIndexes = [0, 1, 2]
        outputRefs =
            Set.fromList
                [ TxIn convictTxId (TxIx (fromIntegral outputIndex))
                | outputIndex <- outputIndexes
                ]
        aidName = deriveAidAssetName (cdCesrAid (checkpointDatum input))
        protected = checkpointMinAda + registrationBond + freezeBond
    _ <-
        pollOutput
            (envProvider env)
            convictTxId
            outputIndexes
            (isExactKeyPayout convictor protected)
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
    -- #280: output zero is the reservation's deposit refund, so the convictor
    -- and hunter payouts the register indexes sit one place along.  Asserting
    -- the refund from settled chain state is what proves the reveal returned
    -- exactly the applied deposit to exactly the committed beneficiary.
    refundOut <-
        requireJust
            ("Convict " <> row <> " output index 0 is absent")
            (Map.lookup (TxIn convictTxId (TxIx 0)) outputs)
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
    convictorOut <-
        requireJust
            ("Convict " <> row <> " output index 1 is absent")
            (Map.lookup (TxIn convictTxId (TxIx 1)) outputs)
    unless
        (isExactKeyPayout convictor protected convictorOut)
        (fail ("Convict " <> row <> " output 1 is not the exact convictor payout"))
    unless
        (unCoin (convictorOut ^. coinTxOutL) == protected)
        (fail ("Convict " <> row <> " protected payout amount is wrong"))
    when
        (any (hasAsset (envCheckpointPolicy env) aidName) (Map.elems outputs))
        (fail ("Convict " <> row <> " left the burned AID token in an output"))
    let roleAddresses = [roleAddress env Active]
    unless
        (all ((`notElem` roleAddresses) . (^. addrTxOutL)) (Map.elems outputs))
        (fail ("Convict " <> row <> " created a checkpoint-role successor"))
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
            <> show protected
            <> "; aid-token-absent=true; checkpoint-successor-absent=true"
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

registerRedeemerData :: PLC.Data
registerRedeemerData = Constr 0 []

advanceRedeemerData :: AdvanceEvidence -> PLC.Data
advanceRedeemerData evidence = Constr 0 [advanceEvidenceData evidence]

advanceEvidenceData :: AdvanceEvidence -> PLC.Data
advanceEvidenceData AdvanceEvidence{..} =
    Constr
        0
        [ B aeEventBytes
        , I (fromIntegral aeOffT)
        , I (fromIntegral aeOffI)
        , I (fromIntegral aeOffS)
        , intListData aeOffK
        , I (fromIntegral aeOffKt)
        , intListData aeOffN
        , I (fromIntegral aeOffNt)
        , intListData aeOffBr
        , intListData aeOffBa
        , I (fromIntegral aeOffBt)
        , List (map B aeWitCut)
        , List (map B aeWitAdd)
        , signatureListData aeCtrlSigs
        , signatureListData aeWitReceipts
        ]

intListData :: (Integral a) => [a] -> PLC.Data
intListData = List . map (I . fromIntegral)

signatureListData :: [(Int, ByteString)] -> PLC.Data
signatureListData =
    List . map (\(index, signature) -> Constr 0 [I (fromIntegral index), B signature])

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
    let upperMs = lowerMs + 25 * slotLengthMs
        validity =
            ValidityPlan
                { lowerSlot = lower
                , upperSlot = upper
                , lowerPosixMs = lowerMs
                , upperPosixMs = upperMs
                }
        range = declaredSlotRange validity
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
    BountyAction ->
    EnforcementEvidence ->
    ByteString ->
    ByteString ->
    IO ResolvedCommitment
openLiveReservation env label checkpointInput action evidence payee nonce = do
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
                action
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
    BountyAction ->
    EnforcementEvidence ->
    ByteString ->
    ByteString ->
    IO EntitledEnforcementPlan
prepareLiveEntitlement env checkpointInput action evidence payee nonce = do
    resolved <-
        openLiveReservation env label checkpointInput action evidence payee nonce
    validity <- entitledSettlementValidity env label resolved
    plan <-
        either
            (fail . ((label <> ": reveal could not be planned: ") <>) . show)
            pure
            ( prepareEntitledEnforcement
                (envCommitmentFamily env)
                resolved
                action
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
    label = "live " <> show action
