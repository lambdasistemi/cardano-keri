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
    pendingHashProofRegisterArmClaimScenario,
    rejectionIsOldCostPlominBoundary,
    rejectionReachedProductionScript,
    responseBoundaryCases,
    boundaryCasesCoverDeadline,
    productionRegisterScenario,
    productionRegisterAdvanceScenario,
    productionRegisterCloseScenario,
    productionRegisterConvictScenario,
    productionRegisterFreezeScenario,
    productionRegisterSeizeScenario,
    buildArmTx,
    buildAdvanceTx,
    buildClaimTx,
    buildThawTx,
    buildCloseTx,
) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
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
    reconstructAdvanceMessage,
 )
import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    CloseContext (..),
    CloseEvidence (..),
    FullAddress (..),
    closePredicate,
    closeSpendRedeemerData,
    reconstructCloseMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    canonicalCbor,
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
    claimFreezeSpendRedeemerData,
    convictBurnRedeemerData,
    convictObserverRedeemerData,
    convictSpendRedeemerData,
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
    registerObserverRedeemerData,
    responseAdvanceObserverRedeemerData,
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
import Data.Word (Word32)
import Lens.Micro ((&), (.~), (^.))
import Paths_cardano_keri (getDataFileName)
import PlutusCore qualified as PLC
import PlutusCore.Data (Data (..))
import PlutusCore.Data qualified as PLC
import PlutusLedgerApi.V3 (serialiseUPLC, uncheckedDeserialiseUPLC)
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
    , envAdvanceReference :: !(Maybe (TxIn, TxOut ConwayEra))
    , envEnforcementScript :: !(Script ConwayEra)
    , envEnforcementBytes :: !SBS.ShortByteString
    , envEnforcementHash :: !ScriptHash
    , envEnforcementReference :: !(Maybe (TxIn, TxOut ConwayEra))
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

data ConvictSource
    = ConvictFromActive
    | ConvictFromArmed !ByteString
    | ConvictFromFrozen

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
    assertPinnedPv11Fixture
    withinSecs 300 "checkpoint withDevnet"
        $ withDevnetConfig
            defaultDevnetConfig{devnetTargetPV = PV11}
        $ \lsq ltxs -> do
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
            action
                env
                    { envAdvanceReference = Just advanceRef
                    , envEnforcementReference = Just enforcementRef
                    }

mkCheckpointEnv :: FilePath -> LSQChannel -> LTxSChannel -> IO CheckpointEnv
mkCheckpointEnv blueprintPath lsq ltxs = do
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    hashProofCode <-
        maybe
            (fail "hash_proof compiled code not found in production blueprint")
            pure
            (extractCompiledCode "hash_proof." blueprint)
    checkpointCode <-
        maybe
            (fail "checkpoint_register compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint_register.checkpoint_register." blueprint)
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
            applyAdvanceParams
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
                0
                registrationBond
                freezeBond
                freezeWindow
                checkpointCode
        checkpointScript = mkCageScript appliedCheckpoint
        checkpointHash = computeScriptHash appliedCheckpoint
        checkpointPolicy = PolicyID checkpointHash
    dbg ("checkpoint_register script hash: " <> show checkpointHash)
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
            , envAdvanceReference = Nothing
            , envEnforcementScript = enforcementScript
            , envEnforcementBytes = appliedEnforcement
            , envEnforcementHash = enforcementHash
            , envEnforcementReference = Nothing
            , envHashProofScript = hashProofScript
            , envHashProofBytes = hashProofCode
            , envHashProofHash = hashProofHash
            , envHashProofPolicy = hashProofPolicy
            , envProvider = mkN2CProvider lsq
            , envSubmitter = mkN2CSubmitter ltxs
            , envOwner = genesisAddr
            }

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
    measure "hash_proof reference script" (envHashProofScript env) (SBS.length (envHashProofBytes env))
    unless (SBS.length (envAdvanceBytes env) == 16_130) $
        fail
            ( "observer_advance applied program changed from 16,130 bytes: "
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
    genesisDir <-
        lookupEnv "E2E_GENESIS_DIR"
            >>= maybe (fail "E2E_GENESIS_DIR not set") pure
    let path =
            takeDirectory genesisDir
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

applyCheckpointParams ::
    Integer ->
    ByteString ->
    ByteString ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCheckpointParams version lifecycleHash advanceHash enforcementHash network dReg bond window code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
            `applyDataArg` B lifecycleHash
            `applyDataArg` B advanceHash
            `applyDataArg` B enforcementHash
            `applyDataArg` I network
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

productionRegisterFreezeScenario :: CheckpointEnv -> IO ()
productionRegisterFreezeScenario env = do
    fixture <- loadFreezeStoryFixture
    let firstFixture = fsFirstRotation fixture
        responseFixture = fsResponseRotation fixture
        secondResponseFixture = fsSecondResponseRotation fixture
        hunter = BS.replicate 28 0x42
    (registered, checkpointRef) <-
        productionRegisterScenarioWithReference
            env
            (rsRegistration firstFixture)
    advanceRef <-
        requireJust
            "observer_advance reference was not deployed during setup"
            (envAdvanceReference env)
    enforcementRef <-
        requireJust
            "observer_enforcement reference was not deployed during setup"
            (envEnforcementReference env)
    let firstEvidence =
            signedRotateEvidence
                env
                registered
                firstFixture
                (rsRotationSigners firstFixture)
                (aeWitReceipts (rsUnsignedEvidence firstFixture))
    case advancePredicate
        (rotateSpentCheckpoint env registered)
        (rsCreated firstFixture)
        firstEvidence of
        Left predicateError ->
            fail
                ( "checkpoint first Advance: signed evidence failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    firstAdvanceTxId <-
        submitTwoPassAdvance
            env
            "checkpoint first Advance"
            checkpointRef
            advanceRef
            registered
            (rsCreated firstFixture)
            firstEvidence
    advancedUtxo <-
        pollOutput
            (envProvider env)
            firstAdvanceTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (rsCreated firstFixture)))
            )
            >>= requireJust "first Advance successor did not settle"
    let advanced =
            CheckpointInput
                { checkpointUtxo = advancedUtxo
                , checkpointDatum = rsCreated firstFixture
                }
        honestFreeze = fsFreezeEvidence fixture
        invalidFork =
            honestFreeze
                { eneRevealedKeys = drop 1 (eneRevealedKeys honestFreeze)
                }
        belowControllerThreshold =
            honestFreeze{eneCtrlSigs = take 1 (eneCtrlSigs honestFreeze)}
        underWitnessed =
            honestFreeze{eneWitSigs = take 1 (eneWitSigs honestFreeze)}
    sequence_
        [ rejectFreezeEvidence
            env
            checkpointRef
            enforcementRef
            advanced
            hunter
            "Freeze invalid contested rotation"
            invalidFork
        , rejectFreezeEvidence
            env
            checkpointRef
            enforcementRef
            advanced
            hunter
            "Freeze below controller threshold"
            belowControllerThreshold
        , rejectFreezeEvidence
            env
            checkpointRef
            enforcementRef
            advanced
            hunter
            "Freeze under-witnessed"
            underWitnessed
        ]
    freezeValidity <- currentValidity env
    let deadline = upperPosixMs freezeValidity + freezeWindow
    freezeTxId <-
        submitTwoPassFreeze
            env
            "checkpoint Freeze"
            checkpointRef
            enforcementRef
            advanced
            honestFreeze
            hunter
            freezeValidity
    armedUtxo <-
        pollOutput
            (envProvider env)
            freezeTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (checkpointDatum advanced)))
            )
            >>= requireJust "Freeze ARMED output did not settle"
    assertArmedCheckpoint
        env
        advanced
        hunter
        deadline
        freezeValidity
        armedUtxo
    let armed =
            CheckpointInput
                { checkpointUtxo = armedUtxo
                , checkpointDatum = checkpointDatum advanced
                }
        responseEvidence =
            signedRotateEvidence
                env
                armed
                responseFixture
                (rsRotationSigners responseFixture)
                (aeWitReceipts (rsUnsignedEvidence responseFixture))
    case advancePredicate
        (rotateSpentCheckpoint env armed)
        (rsCreated responseFixture)
        responseEvidence of
        Left predicateError ->
            fail
                ( "checkpoint response Advance: signed evidence failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    responseValidity <- currentValidity env
    unless
        (upperPosixMs responseValidity < deadline)
        (fail "response Advance validity is not wholly before the stored Freeze deadline")
    responseTxId <-
        submitTwoPassAdvanceWithValidity
            env
            "checkpoint response Advance"
            checkpointRef
            advanceRef
            armed
            (rsCreated responseFixture)
            responseEvidence
            (Just responseValidity)
    responseUtxo <-
        pollOutput
            (envProvider env)
            responseTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (rsCreated responseFixture)))
            )
            >>= requireJust "response Advance successor did not settle"
    unless
        (snd responseUtxo ^. addrTxOutL == roleAddress env Active)
        (fail "response Advance successor is not at the ACTIVE address")
    unless
        (snd responseUtxo ^. valueTxOutL == snd armedUtxo ^. valueTxOutL)
        (fail "response Advance did not preserve the bond and complete checkpoint value")
    case extractDatum (snd responseUtxo) of
        Just (V1 datum)
            | datum == rsCreated responseFixture -> pure ()
        _ -> fail "response Advance successor does not carry the exact honest sibling datum"
    remaining <-
        withinSecs 30 "query response-advanced checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst armedUtxo))
    unless (Map.null remaining) $
        fail "response Advance left the ARMED checkpoint input unspent"
    let responded =
            CheckpointInput
                { checkpointUtxo = responseUtxo
                , checkpointDatum = rsCreated responseFixture
                }
        secondFreezeEvidence = fsSecondFreezeEvidence fixture
    rejectFreezeEvidence
        env
        checkpointRef
        enforcementRef
        responded
        hunter
        "Freeze stale evidence replay"
        honestFreeze
    secondFreezeValidity <- currentValidity env
    let secondDeadline = upperPosixMs secondFreezeValidity + freezeWindow
    secondFreezeTxId <-
        submitTwoPassFreeze
            env
            "checkpoint second Freeze"
            checkpointRef
            enforcementRef
            responded
            secondFreezeEvidence
            hunter
            secondFreezeValidity
    secondArmedUtxo <-
        pollOutput
            (envProvider env)
            secondFreezeTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (checkpointDatum responded)))
            )
            >>= requireJust "second Freeze ARMED output did not settle"
    assertArmedCheckpoint
        env
        responded
        hunter
        secondDeadline
        secondFreezeValidity
        secondArmedUtxo
    let secondArmed =
            CheckpointInput
                { checkpointUtxo = secondArmedUtxo
                , checkpointDatum = checkpointDatum responded
                }
        secondResponseEvidence =
            signedRotateEvidence
                env
                secondArmed
                secondResponseFixture
                (rsRotationSigners secondResponseFixture)
                (aeWitReceipts (rsUnsignedEvidence secondResponseFixture))
    case advancePredicate
        (rotateSpentCheckpoint env secondArmed)
        (rsCreated secondResponseFixture)
        secondResponseEvidence of
        Left predicateError ->
            fail
                ( "checkpoint second response Advance: signed evidence failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    secondResponseValidity <- currentValidity env
    unless
        (upperPosixMs secondResponseValidity < secondDeadline)
        (fail "second response Advance validity is not wholly before the stored Freeze deadline")
    secondResponseTxId <-
        submitTwoPassAdvanceWithValidity
            env
            "checkpoint second response Advance"
            checkpointRef
            advanceRef
            secondArmed
            (rsCreated secondResponseFixture)
            secondResponseEvidence
            (Just secondResponseValidity)
    secondResponseUtxo <-
        pollOutput
            (envProvider env)
            secondResponseTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (rsCreated secondResponseFixture)))
            )
            >>= requireJust "second response Advance successor did not settle"
    unless
        (snd secondResponseUtxo ^. addrTxOutL == roleAddress env Active)
        (fail "second response Advance successor is not at the ACTIVE address")
    unless
        (snd secondResponseUtxo ^. valueTxOutL == snd secondArmedUtxo ^. valueTxOutL)
        (fail "second response Advance did not preserve the bond and complete checkpoint value")
    case extractDatum (snd secondResponseUtxo) of
        Just (V1 datum)
            | datum == rsCreated secondResponseFixture -> pure ()
        _ ->
            fail
                "second response Advance successor does not carry the exact honest sibling datum"
    secondRemaining <-
        withinSecs 30 "query second response-advanced checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst secondArmedUtxo))
    unless (Map.null secondRemaining) $
        fail "second response Advance left the ARMED checkpoint input unspent"
    dbg
        ( "Freeze story settled; register="
            <> show (fst (checkpointUtxo registered))
            <> "; first-advance="
            <> show firstAdvanceTxId
            <> "; freeze="
            <> show freezeTxId
            <> "; response-advance="
            <> show responseTxId
            <> "; stale-freeze-replay=rejected"
            <> "; second-freeze="
            <> show secondFreezeTxId
            <> "; second-response-advance="
            <> show secondResponseTxId
            <> "; deadline="
            <> show deadline
            <> "; second-deadline="
            <> show secondDeadline
        )

productionRegisterConvictScenario :: CheckpointEnv -> IO ()
productionRegisterConvictScenario env = do
    fixture <- loadFreezeStoryFixture
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
    let hunter = BS.replicate 28 0x42
        convictor = BS.replicate 28 0x51
        conflict = fsFreezeEvidence fixture
        freezeTrigger = fsSecondFreezeEvidence fixture
        unwitnessed = conflict{eneWitSigs = take 1 (eneWitSigs conflict)}
        recorded = fsRecordedEvidence fixture
    active <-
        prepareConvictActive
            env
            references
            checkpointRef
            advanceRef
            "ACTIVE"
            fixture
    rejectConvictEvidence
        env
        checkpointRef
        enforcementRef
        active
        ConvictFromActive
        convictor
        "Convict unwitnessed conflict"
        unwitnessed
    rejectConvictEvidence
        env
        checkpointRef
        enforcementRef
        active
        ConvictFromActive
        convictor
        "Convict generated recorded no-conflict event"
        recorded
    activeTxId <-
        submitTwoPassConvict
            env
            "checkpoint Convict ACTIVE"
            checkpointRef
            enforcementRef
            active
            ConvictFromActive
            convictor
            conflict
    assertConvictSettlement
        env
        "ACTIVE"
        active
        ConvictFromActive
        convictor
        activeTxId

    armedActive <-
        prepareConvictActive
            env
            references
            checkpointRef
            advanceRef
            "ARMED"
            fixture
    armedValidity <- currentValidity env
    armedTxId <-
        submitTwoPassFreeze
            env
            "Convict ARMED setup Freeze"
            checkpointRef
            enforcementRef
            armedActive
            freezeTrigger
            hunter
            armedValidity
    armedUtxo <-
        pollOutput
            (envProvider env)
            armedTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (checkpointDatum armedActive)))
            )
            >>= requireJust "Convict ARMED source did not settle"
    let deadline = upperPosixMs armedValidity + freezeWindow
        armed =
            CheckpointInput
                { checkpointUtxo = armedUtxo
                , checkpointDatum = checkpointDatum armedActive
                }
        armedSource = ConvictFromArmed hunter
    assertArmedCheckpoint env armedActive hunter deadline armedValidity armedUtxo
    armedConvictTxId <-
        submitTwoPassConvict
            env
            "checkpoint Convict ARMED"
            checkpointRef
            enforcementRef
            armed
            armedSource
            convictor
            conflict
    assertConvictSettlement
        env
        "ARMED"
        armed
        armedSource
        convictor
        armedConvictTxId

    frozenActive <-
        prepareConvictActive
            env
            references
            checkpointRef
            advanceRef
            "FROZEN"
            fixture
    frozenArmValidity <- currentValidity env
    frozenArmTxId <-
        submitTwoPassFreeze
            env
            "Convict FROZEN setup Freeze"
            checkpointRef
            enforcementRef
            frozenActive
            freezeTrigger
            hunter
            frozenArmValidity
    frozenArmedUtxo <-
        pollOutput
            (envProvider env)
            frozenArmTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (checkpointDatum frozenActive)))
            )
            >>= requireJust "Convict FROZEN setup ARMED output did not settle"
    let frozenDeadline = upperPosixMs frozenArmValidity + freezeWindow
        frozenArmed =
            CheckpointInput
                { checkpointUtxo = frozenArmedUtxo
                , checkpointDatum = checkpointDatum frozenActive
                }
    assertArmedCheckpoint
        env
        frozenActive
        hunter
        frozenDeadline
        frozenArmValidity
        frozenArmedUtxo
    claimValidity <- awaitClaimValidity env frozenDeadline
    claimTxId <-
        submitTwoPassClaim
            env
            "Convict FROZEN setup ClaimFreeze"
            checkpointRef
            frozenArmed
            hunter
            claimValidity
    frozenUtxo <-
        assertClaimSettlement
            env
            (checkpointDatum frozenArmed)
            hunter
            frozenArmedUtxo
            claimTxId
    let frozen =
            CheckpointInput
                { checkpointUtxo = frozenUtxo
                , checkpointDatum = checkpointDatum frozenArmed
                }
    frozenConvictTxId <-
        submitTwoPassConvict
            env
            "checkpoint Convict FROZEN"
            checkpointRef
            enforcementRef
            frozen
            ConvictFromFrozen
            convictor
            conflict
    assertConvictSettlement
        env
        "FROZEN"
        frozen
        ConvictFromFrozen
        convictor
        frozenConvictTxId

prepareConvictActive ::
    CheckpointEnv ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    String ->
    FreezeStoryFixture ->
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

productionRegisterSeizeScenario :: CheckpointEnv -> IO ()
productionRegisterSeizeScenario env = do
    fixture <- loadFreezeStoryFixture
    let firstFixture = fsFirstRotation fixture
        thawFixture = fsResponseRotation fixture
        hunter = BS.replicate 28 0x42
        wrongHunter = BS.replicate 28 0x43
    (registered, checkpointRef) <-
        productionRegisterScenarioWithReference
            env
            (rsRegistration firstFixture)
    advanceRef <-
        requireJust
            "observer_advance reference was not deployed during setup"
            (envAdvanceReference env)
    enforcementRef <-
        requireJust
            "observer_enforcement reference was not deployed during setup"
            (envEnforcementReference env)
    let firstEvidence =
            signedRotateEvidence
                env
                registered
                firstFixture
                (rsRotationSigners firstFixture)
                (aeWitReceipts (rsUnsignedEvidence firstFixture))
    case advancePredicate
        (rotateSpentCheckpoint env registered)
        (rsCreated firstFixture)
        firstEvidence of
        Left predicateError ->
            fail
                ( "seize-delay first Advance failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    firstAdvanceTxId <-
        submitTwoPassAdvance
            env
            "seize-delay first Advance"
            checkpointRef
            advanceRef
            registered
            (rsCreated firstFixture)
            firstEvidence
    advancedUtxo <-
        pollOutput
            (envProvider env)
            firstAdvanceTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (rsCreated firstFixture)))
            )
            >>= requireJust "seize-delay first Advance successor did not settle"
    let advanced =
            CheckpointInput
                { checkpointUtxo = advancedUtxo
                , checkpointDatum = rsCreated firstFixture
                }
        freezeEvidence = fsFreezeEvidence fixture
    freezeValidity <- currentValidity env
    let deadline = upperPosixMs freezeValidity + freezeWindow
    freezeTxId <-
        submitTwoPassFreeze
            env
            "seize-delay Freeze"
            checkpointRef
            enforcementRef
            advanced
            freezeEvidence
            hunter
            freezeValidity
    armedUtxo <-
        pollOutput
            (envProvider env)
            freezeTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid (checkpointDatum advanced)))
            )
            >>= requireJust "seize-delay ARMED output did not settle"
    assertArmedCheckpoint
        env
        advanced
        hunter
        deadline
        freezeValidity
        armedUtxo
    let armed =
            CheckpointInput
                { checkpointUtxo = armedUtxo
                , checkpointDatum = checkpointDatum advanced
                }
    earlyValidity <- currentValidity env
    unless
        (lowerPosixMs earlyValidity < deadline)
        (fail "seize-delay live early-claim window already elapsed")
    rejectClaim
        env
        checkpointRef
        armed
        hunter
        earlyValidity
        "seize-delay early ClaimFreeze"
    claimValidity <- awaitClaimValidity env deadline
    rejectClaim
        env
        checkpointRef
        armed
        wrongHunter
        claimValidity
        "seize-delay wrong-hunter ClaimFreeze"
    claimTxId <-
        submitTwoPassClaim
            env
            "seize-delay ClaimFreeze"
            checkpointRef
            armed
            hunter
            claimValidity
    frozenUtxo <-
        assertClaimSettlement
            env
            (checkpointDatum armed)
            hunter
            armedUtxo
            claimTxId
    let frozen =
            CheckpointInput
                { checkpointUtxo = frozenUtxo
                , checkpointDatum = checkpointDatum armed
                }
        thawEvidence =
            signedRotateEvidence
                env
                frozen
                thawFixture
                (rsRotationSigners thawFixture)
                (aeWitReceipts (rsUnsignedEvidence thawFixture))
        thawSuccessor = rsCreated thawFixture
    case advancePredicate
        (rotateSpentCheckpoint env frozen)
        thawSuccessor
        thawEvidence of
        Left predicateError ->
            fail
                ( "seize-delay thaw Advance failed the pure predicate: "
                    <> show predicateError
                )
        Right () -> pure ()
    thawTxId <-
        submitTwoPassAdvance
            env
            "seize-delay thaw Advance"
            checkpointRef
            advanceRef
            frozen
            thawSuccessor
            thawEvidence
    thawedUtxo <-
        pollOutput
            (envProvider env)
            thawTxId
            [0, 1]
            ( hasAsset
                (envCheckpointPolicy env)
                (deriveAidAssetName (cdCesrAid thawSuccessor))
            )
            >>= requireJust "seize-delay thaw successor did not settle"
    unless
        (snd thawedUtxo ^. addrTxOutL == roleAddress env Active)
        (fail "seize-delay thaw successor is not ACTIVE")
    unless
        ( snd thawedUtxo ^. valueTxOutL
            == addLovelace freezeBond (snd frozenUtxo ^. valueTxOutL)
        )
        (fail "seize-delay thaw did not re-post exactly B")
    case extractDatum (snd thawedUtxo) of
        Just (V1 datum)
            | datum == thawSuccessor -> pure ()
        _ -> fail "seize-delay thaw successor does not carry the real next datum"
    remaining <-
        withinSecs 30 "query seize-delay FROZEN checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst frozenUtxo))
    unless (Map.null remaining) $
        fail "seize-delay thaw left the FROZEN checkpoint input unspent"
    dbg
        ( "Seize-delay story settled; register="
            <> show (fst (checkpointUtxo registered))
            <> "; first-advance="
            <> show firstAdvanceTxId
            <> "; freeze="
            <> show freezeTxId
            <> "; early-claim=rejected"
            <> "; wrong-hunter=rejected"
            <> "; claim="
            <> show claimTxId
            <> "; thaw-advance="
            <> show thawTxId
            <> "; hunter-payout="
            <> show freezeBond
            <> "; frozen-reserve="
            <> show (checkpointMinAda + registrationBond)
            <> "; thaw-repost="
            <> show freezeBond
        )

productionRegisterCloseScenario :: CheckpointEnv -> IO ()
productionRegisterCloseScenario env = do
    closeFixture <- loadCloseStoryFixture
    let fixture = csRegistration closeFixture
    (registered, checkpointRef) <-
        productionRegisterScenarioWithReference env fixture
    let evidence =
            signedCloseEvidence
                env
                registered
                (csCurrentSigners closeFixture)
    case closePredicate (closeContext env registered) evidence of
        Left closeError ->
            fail
                ( "checkpoint Close: signed evidence failed the pure predicate: "
                    <> show closeError
                )
        Right () -> pure ()
    closeTxId <-
        submitTwoPassClose
            env
            "checkpoint Close"
            checkpointRef
            registered
            evidence
    let checkpointName =
            deriveAidAssetName (cdCesrAid (checkpointDatum registered))
        expectedRefund =
            snd (checkpointUtxo registered) ^. coinTxOutL
    refund <-
        pollOutput
            (envProvider env)
            closeTxId
            [0]
            ( \output ->
                output ^. addrTxOutL == envOwner env
                    && output ^. coinTxOutL == expectedRefund
                    && not
                        ( hasAsset
                            (envCheckpointPolicy env)
                            checkpointName
                            output
                        )
            )
            >>= requireJust "Close controller refund did not settle"
    remaining <-
        withinSecs 30 "query closed checkpoint input" $
            queryUTxOByTxIn
                (envProvider env)
                (Set.singleton (fst (checkpointUtxo registered)))
    unless (Map.null remaining) $
        fail "Close left the registered checkpoint input unspent"
    dbg
        ( "Close settled; tx id="
            <> show closeTxId
            <> "; refund="
            <> show (fst refund)
        )

{- | This is deliberately not run on the old-cost devnet.  Referencing this
scenario from the authorized PENDING row type-checks the real hash-proof mint,
permissionless Register with @D_reg+B@, Arm, and Claim builders without
claiming settlement before cardano-node-clients#190 supplies Plomin pricing.
-}
pendingHashProofRegisterArmClaimScenario :: CheckpointEnv -> IO ()
pendingHashProofRegisterArmClaimScenario env = do
    (fixture, armEvidence) <- loadLifecycleFixture
    registered <- productionRegisterScenarioWith env fixture
    boundaries <- responseBoundaryCases env
    unless
        (boundaryCasesCoverDeadline boundaries)
        (fail "node-derived deadline plans do not cover before/exact/after boundary")
    let hunter = BS.replicate 28 0x42
        armValidity = armUpper boundaries
        deadline = hardDeadlineMs boundaries
    armTx <-
        withinSecs 90 "build checkpoint Arm" $
            buildArmTx env registered armEvidence hunter armValidity
    armTxId <- submitSettling env "checkpoint Arm" armTx
    armed <-
        pollOutput
            (envProvider env)
            armTxId
            [0, 1]
            (hasAsset (envCheckpointPolicy env) (deriveAidAssetName (cdCesrAid (rfDatum fixture))))
            >>= requireJust "ARMED checkpoint output did not settle"
    assertArmedCheckpoint env registered hunter deadline armValidity armed
    claimValidity <- awaitClaimValidity env deadline
    claimTx <-
        withinSecs 90 "build checkpoint Claim" $
            buildClaimTx
                env
                CheckpointInput{checkpointUtxo = armed, checkpointDatum = rfDatum fixture}
                hunter
                claimValidity
    claimTxId <- submitSettling env "checkpoint Claim" claimTx
    _ <-
        assertClaimSettlement
            env
            (rfDatum fixture)
            hunter
            armed
            claimTxId
    pure ()

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
            False
    expectProductionScriptRejection env "Advance" tx

closeRejection :: CheckpointEnv -> IO RejectionEvidence
closeRejection env = do
    prepareWallet env
    (fixture, _) <- loadLifecycleFixture
    staged <- stageCheckpointInput env (rfDatum fixture)
    tx <- buildCloseTx env staged (currentValidity env)
    expectProductionScriptRejection env "Close" tx

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

data CloseStoryFixture = CloseStoryFixture
    { csRegistration :: !RegistrationFixture
    , csCurrentSigners :: ![SignKeyDSIGN Ed25519DSIGN]
    }

data RotateStoryFixture = RotateStoryFixture
    { rsRegistration :: !RegistrationFixture
    , rsCreated :: !CheckpointDatumV1
    , rsUnsignedEvidence :: !AdvanceEvidence
    , rsRotationSigners :: ![SignKeyDSIGN Ed25519DSIGN]
    , rsCurrentSigners :: ![SignKeyDSIGN Ed25519DSIGN]
    }

data FreezeStoryFixture = FreezeStoryFixture
    { fsFirstRotation :: !RotateStoryFixture
    , fsFreezeEvidence :: !EnforcementEvidence
    , fsRecordedEvidence :: !EnforcementEvidence
    , fsResponseRotation :: !RotateStoryFixture
    , fsSecondFreezeEvidence :: !EnforcementEvidence
    , fsSecondResponseRotation :: !RotateStoryFixture
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

loadFreezeStoryFixture :: IO FreezeStoryFixture
loadFreezeStoryFixture = do
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
    secondResponseSigners <-
        either fail pure (seedSignersAt "rotation_3_current" seeds)
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
    unsignedFreeze <-
        either fail pure $
            enforcementEvidenceFrom conflictWithOffsets conflictSignatures
    let freezeEvidence = unsignedFreeze{eneWitSigs = conflictReceipts}
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
    secondConflictRecord <- either fail pure (atKey "rot_3_conflict" root)
    secondConflictEvent <- either fail pure (atKey "event" secondConflictRecord)
    secondConflictWithOffsets <-
        either fail pure (withDerivedOffsets secondConflictEvent)
    secondConflictSignatures <-
        either fail pure (indexedSignaturesAt "controller_sigs" secondConflictRecord)
    secondConflictReceipts <-
        either fail pure (indexedSignaturesAt "witness_receipts" secondConflictRecord)
    unsignedSecondFreeze <-
        either fail pure $
            enforcementEvidenceFrom
                secondConflictWithOffsets
                secondConflictSignatures
    let secondFreezeEvidence =
            unsignedSecondFreeze{eneWitSigs = secondConflictReceipts}
    secondResponseRecord <- either fail pure (atKey "rot_3_recorded" root)
    secondResponse <-
        either fail pure $
            rotateStoryFrom
                registration
                (rsCreated response)
                secondResponseRecord
                secondResponseSigners
                responseSigners
    pure
        FreezeStoryFixture
            { fsFirstRotation = first
            , fsFreezeEvidence = freezeEvidence
            , fsRecordedEvidence = recordedEvidence
            , fsResponseRotation = response
            , fsSecondFreezeEvidence = secondFreezeEvidence
            , fsSecondResponseRotation = secondResponse
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

signedRotateEvidence ::
    CheckpointEnv ->
    CheckpointInput ->
    RotateStoryFixture ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    [(Int, ByteString)] ->
    AdvanceEvidence
signedRotateEvidence env input fixture signers receipts =
    unsigned
        { aeCtrlSigs = indexedSignaturesOver preimage signers
        , aeWitReceipts = receipts
        }
  where
    unsigned = rsUnsignedEvidence fixture
    message =
        reconstructAdvanceMessage
            (rotateSpentCheckpoint env input)
            (rsCreated fixture)
            (aeWitCut unsigned)
            (aeWitAdd unsigned)
    preimage = canonicalCbor message

loadCloseStoryFixture :: IO CloseStoryFixture
loadCloseStoryFixture = do
    path <- getDataFileName "test/keri-fixtures/fixtures/registration.json"
    root <- eitherDecodeFileStrict path >>= either fail pure
    family <- either fail pure (atKey "reg_2key" root)
    event <- either fail pure (atKey "event" family)
    offsets <- either fail pure (atKey "offsets" family)
    eventWithOffsets <-
        case event of
            Object fields ->
                pure (Object (KeyMap.insert (Key.fromText "offsets") offsets fields))
            _ -> fail "reg_2key.event is not an object"
    signatures <- either fail pure (indexedSignaturesAt "event_sigs" family)
    registration <-
        either fail pure $
            registrationFixtureFrom eventWithOffsets signatures []
    signerSeeds <-
        either fail pure $
            atKey "signer_seeds" family
                >>= atKey "current"
                >>= arrayValues
                >>= traverse
                    ( \entry ->
                        (textAt "seed_hex" entry >>= decodeHex)
                            <&> genKeyDSIGN . mkSeedFromBytes
                    )
    let observedKeys =
            map
                (rawSerialiseVerKeyDSIGN . deriveVerKeyDSIGN)
                signerSeeds
    unless (observedKeys == cdCurKeys (rfDatum registration)) $
        fail "reg_2key signer seeds do not reproduce the registered controller keys"
    pure
        CloseStoryFixture
            { csRegistration = registration
            , csCurrentSigners = signerSeeds
            }

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

signedCloseEvidence ::
    CheckpointEnv ->
    CheckpointInput ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    CloseEvidence
signedCloseEvidence env input signers = evidence
  where
    context = closeContext env input
    unsigned =
        CloseEvidence
            { ceRefundAddress = ownerFullAddress env
            , ceCtrlSigs = []
            }
    preimage = canonicalCbor (reconstructCloseMessage context unsigned)
    evidence =
        unsigned
            { ceCtrlSigs =
                [ (index, rawSerialiseSigDSIGN (signDSIGN () preimage signer))
                | (index, signer) <- zip [0 ..] signers
                ]
            }

closeContext :: CheckpointEnv -> CheckpointInput -> CloseContext
closeContext env input =
    case fst (checkpointUtxo input) of
        TxIn (TxId safeHash) (TxIx outputIndex) ->
            CloseContext
                { ccNetworkId = 0
                , ccCheckpointPolicyId = policyBytes (envCheckpointPolicy env)
                , ccSpentTxid = hashToBytes (extractHash safeHash)
                , ccSpentIndex = fromIntegral outputIndex
                , ccOld = checkpointDatum input
                }

ownerFullAddress :: CheckpointEnv -> FullAddress
ownerFullAddress env =
    case envOwner env of
        Addr _ (KeyHashObj (KeyHash paymentHash)) StakeRefNull ->
            FullAddress
                { faPaymentCredential =
                    VerificationKeyCredential (hashToBytes paymentHash)
                , faStakeCredential = Nothing
                }
        _ -> error "Close story requires an enterprise key owner address"

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
        inputAddress = snd (checkpointUtxo input) ^. addrTxOutL
        repostBond = inputAddress == roleAddress env Frozen
        observerRedeemerData
            | inputAddress == roleAddress env Armed =
                responseAdvanceObserverRedeemerData
                    (policyBytes (envCheckpointPolicy env))
                    spentTxIdBytes
                    spentIndex
                    evidence
            | otherwise =
                advanceObserverRedeemerData
                    (policyBytes (envCheckpointPolicy env))
                    spentTxIdBytes
                    spentIndex
                    evidence
        stateOut =
            mkStateOutput
                env
                Active
                ( addLovelace
                    (if repostBond then freezeBond else 0)
                    (snd (checkpointUtxo input) ^. valueTxOutL)
                )
                (asPlcData (V1 successor))
        changeOut =
            mkBasicTxOut
                (envOwner env)
                ( addLovelace
                    (-scriptFee - if repostBond then freezeBond else 0)
                    (feeOut ^. valueTxOutL)
                )
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

buildFreezeStoryTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    ValidityPlan ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildFreezeStoryTxWith budgets env checkpointRef enforcementRef input evidence hunter validity = do
    params <-
        withinSecs 30 "query Freeze protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Freeze wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef, fst enforcementRef]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        spendPurpose = ConwaySpending (AsIx stateIndex)
        rewardPurpose = ConwayRewarding (AsIx 0)
        expected = Set.fromList [spendPurpose, rewardPurpose]
        armedDatum =
            ArmedV1
                { adCheckpoint = checkpointDatum input
                , adHunterPkh = hunter
                , adDeadline = upperPosixMs validity + freezeWindow
                }
        stateOut =
            mkStateOutput
                env
                Armed
                (snd (checkpointUtxo input) ^. valueTxOutL)
                (asPlcData armedDatum)
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
                            ( ledgerData (freezeSpendRedeemerData hunter)
                            , Map.findWithDefault
                                advanceSpendExUnits
                                spendPurpose
                                budgets
                            )
                        )
                    ,
                        ( rewardPurpose
                        ,
                            ( ledgerData
                                ( freezeObserverRedeemerData
                                    (policyBytes (envCheckpointPolicy env))
                                    spentTxIdBytes
                                    spentIndex
                                    evidence
                                )
                            , Map.findWithDefault
                                scriptExUnits
                                rewardPurpose
                                budgets
                            )
                        )
                    ]
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList [stateOut, changeOut]
                & feeTxBodyL .~ Coin scriptFee
                & withdrawalsTxBodyL
                    .~ Withdrawals
                        ( Map.singleton
                            ( AccountAddress
                                Testnet
                                (AccountId (ScriptHashObj (envEnforcementHash env)))
                            )
                            (Coin 0)
                        )
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & referenceInputsTxBodyL
                    .~ Set.fromList [fst checkpointRef, fst enforcementRef]
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
    (spentTxIdBytes, spentIndex) =
        case stateIn of
            TxIn (TxId safeHash) (TxIx outputIndex) ->
                ( hashToBytes (extractHash safeHash)
                , fromIntegral outputIndex
                )

rejectFreezeEvidence ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    String ->
    EnforcementEvidence ->
    IO ()
rejectFreezeEvidence env checkpointRef enforcementRef input hunter label evidence = do
    validity <- currentValidity env
    (candidate, _) <-
        withinSecs 90 (label <> ": build applied candidate") $
            buildFreezeStoryTxWith
                Map.empty
                env
                checkpointRef
                enforcementRef
                input
                evidence
                hunter
                validity
    _ <- expectProductionScriptRejection env label candidate
    pure ()

submitTwoPassFreeze ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    ValidityPlan ->
    IO TxId
submitTwoPassFreeze env label checkpointRef enforcementRef input evidence hunter validity = do
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildFreezeStoryTxWith
                Map.empty
                env
                checkpointRef
                enforcementRef
                input
                evidence
                hunter
                validity
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness genesisSignKey discovery)
    discoveryUnits <-
        requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    (final, finalExpected) <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildFreezeStoryTxWith
                finalBudgets
                env
                checkpointRef
                enforcementRef
                input
                evidence
                hunter
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

buildConvictStoryTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ConvictSource ->
    ByteString ->
    EnforcementEvidence ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildConvictStoryTxWith budgets env checkpointRef enforcementRef input source convictor evidence = do
    params <-
        withinSecs 30 "query Convict protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Convict wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef, fst enforcementRef]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        mintPurpose = ConwayMinting (AsIx 0)
        spendPurpose = ConwaySpending (AsIx stateIndex)
        rewardPurpose = ConwayRewarding (AsIx 0)
        expected = Set.fromList [mintPurpose, spendPurpose, rewardPurpose]
        checkpointName =
            AssetName $
                SBS.toShort $
                    deriveAidAssetName (cdCesrAid (checkpointDatum input))
        minted =
            MultiAsset $
                Map.singleton
                    (envCheckpointPolicy env)
                    (Map.singleton checkpointName (-1))
        (protected, hunterPayouts, hunterOutputIndex) =
            case source of
                ConvictFromActive ->
                    (checkpointMinAda + registrationBond + freezeBond, [], 0)
                ConvictFromArmed hunter ->
                    ( checkpointMinAda + registrationBond
                    , [mkBasicTxOut (keyAddress hunter) (inject (Coin freezeBond))]
                    , 1
                    )
                ConvictFromFrozen ->
                    (checkpointMinAda + registrationBond, [], 0)
        sourceCoin = unCoin (snd (checkpointUtxo input) ^. coinTxOutL)
        surplus = sourceCoin - protected - if null hunterPayouts then 0 else freezeBond
        convictorOut =
            mkBasicTxOut
                (keyAddress convictor)
                (inject (Coin protected))
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (surplus - scriptFee) (feeOut ^. valueTxOutL))
        outputs = convictorOut : hunterPayouts <> [changeOut]
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
                        ( spendPurpose
                        ,
                            ( ledgerData
                                ( convictSpendRedeemerData
                                    convictor
                                    0
                                    hunterOutputIndex
                                )
                            , Map.findWithDefault
                                (ExUnits 2_000_000 1_200_000_000)
                                spendPurpose
                                budgets
                            )
                        )
                    ,
                        ( rewardPurpose
                        ,
                            ( ledgerData
                                ( convictObserverRedeemerData
                                    (policyBytes (envCheckpointPolicy env))
                                    spentTxIdBytes
                                    spentIndex
                                    evidence
                                )
                            , Map.findWithDefault
                                (ExUnits 13_000_000 8_000_000_000)
                                rewardPurpose
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
                & withdrawalsTxBodyL
                    .~ Withdrawals
                        ( Map.singleton
                            ( AccountAddress
                                Testnet
                                (AccountId (ScriptHashObj (envEnforcementHash env)))
                            )
                            (Coin 0)
                        )
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & referenceInputsTxBodyL
                    .~ Set.fromList [fst checkpointRef, fst enforcementRef]
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
    ConvictSource ->
    ByteString ->
    String ->
    EnforcementEvidence ->
    IO ()
rejectConvictEvidence env checkpointRef enforcementRef input source convictor label evidence = do
    (candidate, expected) <-
        withinSecs 90 (label <> ": build evaluation-only candidate") $
            buildConvictStoryTxWith
                Map.empty
                env
                checkpointRef
                enforcementRef
                input
                source
                convictor
                evidence
    observed <-
        withinSecs 120 (label <> ": evaluate without submission") $
            evaluateTx
                (envProvider env)
                (addKeyWitness genesisSignKey candidate)
    unless (Map.keysSet observed == expected) $
        fail
            ( label
                <> ": unexpected evaluator purpose set: "
                <> show (Map.keysSet observed)
            )
    unless (any isLeft (Map.elems observed)) $
        fail (label <> ": invalid evidence unexpectedly evaluated successfully")
    dbg
        ( label
            <> " rejected by evaluation without submission; tx id="
            <> show (txIdTx candidate)
            <> "; outcomes="
            <> show observed
        )
  where
    isLeft result =
        case result of
            Left _ -> True
            Right _ -> False

submitTwoPassConvict ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ConvictSource ->
    ByteString ->
    EnforcementEvidence ->
    IO TxId
submitTwoPassConvict env label checkpointRef enforcementRef input source convictor evidence = do
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildConvictStoryTxWith
                Map.empty
                env
                checkpointRef
                enforcementRef
                input
                source
                convictor
                evidence
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness genesisSignKey discovery)
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
                input
                source
                convictor
                evidence
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

buildClaimStoryTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    ValidityPlan ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildClaimStoryTxWith budgets env checkpointRef input payoutHunter validity = do
    params <-
        withinSecs 30 "query ClaimFreeze protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query ClaimFreeze wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        spendPurpose = ConwaySpending (AsIx stateIndex)
        expected = Set.singleton spendPurpose
        payoutOut =
            mkBasicTxOut
                (keyAddress payoutHunter)
                (inject (Coin freezeBond))
        stateOut =
            mkStateOutput
                env
                Frozen
                ( addLovelace
                    (-freezeBond)
                    (snd (checkpointUtxo input) ^. valueTxOutL)
                )
                (asPlcData (V1 (checkpointDatum input)))
        changeOut =
            mkBasicTxOut
                (envOwner env)
                (addLovelace (-scriptFee) (feeOut ^. valueTxOutL))
        redeemers =
            Redeemers $
                Map.singleton
                    spendPurpose
                    ( ledgerData (claimFreezeSpendRedeemerData 0)
                    , Map.findWithDefault
                        advanceSpendExUnits
                        spendPurpose
                        budgets
                    )
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL
                    .~ StrictSeq.fromList [payoutOut, stateOut, changeOut]
                & feeTxBodyL .~ Coin scriptFee
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & referenceInputsTxBodyL .~ Set.singleton (fst checkpointRef)
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

rejectClaim ::
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    ValidityPlan ->
    String ->
    IO ()
rejectClaim env checkpointRef input payoutHunter validity label = do
    (candidate, _) <-
        withinSecs 90 (label <> ": build applied candidate") $
            buildClaimStoryTxWith
                Map.empty
                env
                checkpointRef
                input
                payoutHunter
                validity
    _ <- expectProductionScriptRejection env label candidate
    pure ()

submitTwoPassClaim ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    ByteString ->
    ValidityPlan ->
    IO TxId
submitTwoPassClaim env label checkpointRef input hunter validity = do
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildClaimStoryTxWith
                Map.empty
                env
                checkpointRef
                input
                hunter
                validity
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness genesisSignKey discovery)
    discoveryUnits <-
        requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    (final, finalExpected) <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildClaimStoryTxWith
                finalBudgets
                env
                checkpointRef
                input
                hunter
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

buildCloseStoryTxWith ::
    Map.Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    CheckpointEnv ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    CloseEvidence ->
    IO
        ( ConwayTx
        , Set.Set (ConwayPlutusPurpose AsIx ConwayEra)
        )
buildCloseStoryTxWith budgets env checkpointRef input evidence = do
    params <-
        withinSecs 30 "query Close protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query Close wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (feeUtxo, collateralUtxo) <-
        pickDisjoint wallet [stateIn, fst checkpointRef]
    let (feeIn, feeOut) = feeUtxo
        collateralIn = fst collateralUtxo
        allInputs = Set.fromList [stateIn, feeIn]
        stateIndex = spendingIndex stateIn allInputs
        mintPurpose = ConwayMinting (AsIx 0)
        spendPurpose = ConwaySpending (AsIx stateIndex)
        expected = Set.fromList [mintPurpose, spendPurpose]
        checkpointName =
            AssetName $
                SBS.toShort $
                    deriveAidAssetName (cdCesrAid (checkpointDatum input))
        minted =
            MultiAsset $
                Map.singleton
                    (envCheckpointPolicy env)
                    (Map.singleton checkpointName (-1))
        refundValue =
            removeAsset
                (envCheckpointPolicy env)
                checkpointName
                (snd (checkpointUtxo input) ^. valueTxOutL)
        refundOut = mkBasicTxOut (envOwner env) refundValue
        changeOut =
            mkBasicTxOut
                (keyAddress (BS.replicate 28 0x71))
                (addLovelace (-scriptFee) (feeOut ^. valueTxOutL))
        redeemers =
            Redeemers $
                Map.fromList
                    [
                        ( mintPurpose
                        ,
                            ( ledgerData (closeBurnRedeemerData stateIn)
                            , Map.findWithDefault scriptExUnits mintPurpose budgets
                            )
                        )
                    ,
                        ( spendPurpose
                        ,
                            ( ledgerData (closeSpendRedeemerData evidence)
                            , Map.findWithDefault scriptExUnits spendPurpose budgets
                            )
                        )
                    ]
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList [refundOut, changeOut]
                & feeTxBodyL .~ Coin scriptFee
                & mintTxBodyL .~ minted
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

submitTwoPassClose ::
    CheckpointEnv ->
    String ->
    (TxIn, TxOut ConwayEra) ->
    CheckpointInput ->
    CloseEvidence ->
    IO TxId
submitTwoPassClose env label checkpointRef input evidence = do
    (discovery, expected) <-
        withinSecs 90 (label <> ": build discovery binding") $
            buildCloseStoryTxWith Map.empty env checkpointRef input evidence
    discoveryObserved <-
        withinSecs 120 (label <> ": evaluate discovery binding") $
            evaluateTx (envProvider env) (addKeyWitness genesisSignKey discovery)
    discoveryUnits <-
        requireExactAllRight (label <> ": discovery") expected discoveryObserved
    let finalBudgets = Map.map deterministicMargin discoveryUnits
    (final, finalExpected) <-
        withinSecs 90 (label <> ": rebuild final binding") $
            buildCloseStoryTxWith finalBudgets env checkpointRef input evidence
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
            <> " budgets="
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
the independent Advance/Close negative staging checks below; it is never a
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
        "manual ACTIVE checkpoint input has no production token lineage; only Advance/Close rejection is asserted"
    pure CheckpointInput{checkpointUtxo = utxo, checkpointDatum = datum}

buildArmTx ::
    CheckpointEnv ->
    CheckpointInput ->
    EnforcementEvidence ->
    ByteString ->
    ValidityPlan ->
    IO ConwayTx
buildArmTx env input evidence hunter validity =
    buildCheckpointSpend
        env
        input
        (freezeRedeemerData evidence hunter)
        validity
        [ mkStateOutput
            env
            Armed
            (snd (checkpointUtxo input) ^. valueTxOutL)
            ( asPlcData
                ArmedV1
                    { adCheckpoint = checkpointDatum input
                    , adHunterPkh = hunter
                    , adDeadline = upperPosixMs validity + freezeWindow
                    }
            )
        ]
        0

buildAdvanceTx ::
    CheckpointEnv ->
    CheckpointInput ->
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    ValidityPlan ->
    Bool ->
    IO ConwayTx
buildAdvanceTx env input successor evidence validity repostBond =
    buildCheckpointSpend
        env
        input
        (advanceRedeemerData evidence)
        validity
        [ mkStateOutput
            env
            Active
            (addLovelace (if repostBond then freezeBond else 0) inputValue)
            (asPlcData (V1 successor))
        ]
        (if repostBond then freezeBond else 0)
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
        0
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

buildCloseTx ::
    CheckpointEnv -> CheckpointInput -> IO ValidityPlan -> IO ConwayTx
buildCloseTx env input validityAction = do
    validity <- validityAction
    buildCheckpointSpend
        env
        input
        closeRedeemerData
        validity
        [mkBasicTxOut (envOwner env) (snd (checkpointUtxo input) ^. valueTxOutL)]
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

removeAsset :: PolicyID -> AssetName -> MaryValue -> MaryValue
removeAsset policy name (MaryValue coin (MultiAsset policies)) =
    MaryValue coin (MultiAsset (Map.update removeName policy policies))
  where
    removeName names =
        let remaining = Map.delete name names
         in if Map.null remaining then Nothing else Just remaining

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
responseBoundaryCases env = withinSecs 120 "checkpoint deadline boundary conversion" $ do
    snapshot <- queryLedgerSnapshot (envProvider env)
    let SlotNo tip = ledgerTipSlot snapshot
        armLowerSlot = SlotNo (if tip > 2 then tip - 2 else 0)
        armUpperSlot = SlotNo (tip + 5)
    armLowerMs <- slotStartPosixMs env armLowerSlot
    armUpperMs <- slotStartPosixMs env armUpperSlot
    nextSlotMs <- slotStartPosixMs env (SlotNo (tip + 6))
    let slotLengthMs = nextSlotMs - armUpperMs
        deadline = armUpperMs + freezeWindow
    unless (slotLengthMs > 0) (fail "node reported a non-positive slot length")
    beforeUpper <- posixMsToSlot (envProvider env) (deadline - 1)
    exact <- posixMsToSlot (envProvider env) deadline
    afterLower <- posixMsCeilSlot (envProvider env) (deadline + 1)
    beforeMs <- slotStartPosixMs env beforeUpper
    exactMs <- slotStartPosixMs env exact
    afterMs <- slotStartPosixMs env afterLower
    let mkPlan lo loMs hi hiMs =
            ValidityPlan
                { lowerSlot = lo
                , upperSlot = hi
                , lowerPosixMs = loMs
                , upperPosixMs = hiMs
                }
        armPlan = mkPlan armLowerSlot armLowerMs armUpperSlot armUpperMs
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

{- | Poll the node until it has reached a slot whose start is at or after the
stored on-chain deadline.  The wait is bounded and every retry re-queries the
node; it is deliberately not a wall-clock sleep.
-}
awaitClaimValidity :: CheckpointEnv -> Integer -> IO ValidityPlan
awaitClaimValidity env deadline = go pollAttempts
  where
    go remaining
        | remaining <= 0 = fail "node did not reach the Claim deadline before polling timed out"
        | otherwise = do
            snapshot <-
                withinSecs 30 "query node Claim tip" $
                    queryLedgerSnapshot (envProvider env)
            let lower = ledgerTipSlot snapshot
            lowerMs <- slotStartPosixMs env lower
            if lowerMs < deadline
                then threadDelay 1_000_000 >> go (remaining - 1)
                else do
                    let upper = SlotNo (unSlotNo lower + 20)
                    upperMs <- slotStartPosixMs env upper
                    unless
                        ( claimAtOrAfterDeadline
                            deadline
                            (Just (Finite lowerMs Inclusive))
                        )
                        (fail "node-derived Claim lower bound is before the stored deadline")
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
    CheckpointDatumV1 ->
    ByteString ->
    (TxIn, TxOut ConwayEra) ->
    TxId ->
    IO (TxIn, TxOut ConwayEra)
assertClaimSettlement env expectedDatum hunter armed claimTxId = do
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
            (isFrozenCheckpoint env expectedDatum)
            >>= requireJust "Claim FROZEN checkpoint output did not settle"
    unless
        (isExactHunterPayout hunter (snd payout))
        (fail "Claim hunter payout is not exactly B at the named hunter key")
    unless
        (snd frozen ^. valueTxOutL == addLovelace (-freezeBond) (snd armed ^. valueTxOutL))
        (fail "Claim FROZEN checkpoint does not retain the remaining reserve and AID token")
    pure frozen

assertConvictSettlement ::
    CheckpointEnv ->
    String ->
    CheckpointInput ->
    ConvictSource ->
    ByteString ->
    TxId ->
    IO ()
assertConvictSettlement env row input source convictor convictTxId = do
    let outputIndexes =
            case source of
                ConvictFromArmed _ -> [0, 1, 2]
                _ -> [0, 1]
        outputRefs =
            Set.fromList
                [ TxIn convictTxId (TxIx (fromIntegral outputIndex))
                | outputIndex <- outputIndexes
                ]
        aidName = deriveAidAssetName (cdCesrAid (checkpointDatum input))
        protected =
            case source of
                ConvictFromActive ->
                    checkpointMinAda + registrationBond + freezeBond
                ConvictFromArmed _ ->
                    checkpointMinAda + registrationBond
                ConvictFromFrozen ->
                    checkpointMinAda + registrationBond
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
    convictorOut <-
        requireJust
            ("Convict " <> row <> " output index 0 is absent")
            (Map.lookup (TxIn convictTxId (TxIx 0)) outputs)
    unless
        (isExactKeyPayout convictor protected convictorOut)
        (fail ("Convict " <> row <> " output 0 is not the exact convictor payout"))
    unless
        (unCoin (convictorOut ^. coinTxOutL) == protected)
        (fail ("Convict " <> row <> " protected payout amount is wrong"))
    case source of
        ConvictFromArmed hunter -> do
            hunterOut <-
                requireJust
                    "Convict ARMED output index 1 is absent"
                    (Map.lookup (TxIn convictTxId (TxIx 1)) outputs)
            unless
                (isExactHunterPayout hunter hunterOut)
                (fail "Convict ARMED output 1 is not the exact hunter payout B")
        _ -> pure ()
    when
        (any (hasAsset (envCheckpointPolicy env) aidName) (Map.elems outputs))
        (fail ("Convict " <> row <> " left the burned AID token in an output"))
    let roleAddresses =
            [ roleAddress env Active
            , roleAddress env Armed
            , roleAddress env Frozen
            ]
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
            <> "; convictor-output=0:"
            <> show protected
            <> case source of
                ConvictFromArmed hunter ->
                    "; hunter-output=1:"
                        <> show freezeBond
                        <> "@"
                        <> show hunter
                _ -> ""
            <> "; aid-token-absent=true; checkpoint-successor-absent=true"
        )

isExactHunterPayout :: ByteString -> TxOut ConwayEra -> Bool
isExactHunterPayout hunter =
    isExactKeyPayout hunter freezeBond

isExactKeyPayout :: ByteString -> Integer -> TxOut ConwayEra -> Bool
isExactKeyPayout recipient amount output =
    output ^. addrTxOutL == keyAddress recipient
        && case output ^. valueTxOutL of
            MaryValue (Coin lovelace) (MultiAsset assets) ->
                lovelace == amount && Map.null assets

isFrozenCheckpoint :: CheckpointEnv -> CheckpointDatumV1 -> TxOut ConwayEra -> Bool
isFrozenCheckpoint env expectedDatum output =
    output ^. addrTxOutL == roleAddress env Frozen
        && hasAsset (envCheckpointPolicy env) (deriveAidAssetName (cdCesrAid expectedDatum)) output
        && case extractDatum output of
            Just (V1 datum) -> datum == expectedDatum
            _ -> False

slotStartPosixMs :: CheckpointEnv -> SlotNo -> IO Integer
slotStartPosixMs env target = do
    now <- round . (* 1000) <$> getPOSIXTime
    let lo0 = now - 5_000
        -- Every caller asks for a near-tip slot. A three-second upper bracket
        -- stays inside the PV11 devnet forecast where the old +30s probe
        -- crossed the horizon before the Freeze story could build.
        hi0 = now + 3_000
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

freezeRedeemerData :: EnforcementEvidence -> ByteString -> PLC.Data
freezeRedeemerData evidence hunter =
    Constr 1 [enforcementEvidenceData evidence, B hunter]

claimRedeemerData :: Integer -> PLC.Data
claimRedeemerData outputIndex = Constr 2 [I outputIndex]

closeRedeemerData :: PLC.Data
closeRedeemerData = Constr 4 []

closeBurnRedeemerData :: TxIn -> PLC.Data
closeBurnRedeemerData (TxIn (TxId safeHash) (TxIx outputIndex)) =
    Constr
        1
        [ Constr
            0
            [ B (hashToBytes (extractHash safeHash))
            , I (fromIntegral outputIndex)
            ]
        ]

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

enforcementEvidenceData :: EnforcementEvidence -> PLC.Data
enforcementEvidenceData EnforcementEvidence{..} =
    Constr
        0
        [ B eneEventBytes
        , I (fromIntegral eneOffT)
        , I (fromIntegral eneOffI)
        , I (fromIntegral eneOffS)
        , I (fromIntegral eneOffD)
        , intListData eneOffK
        , I (fromIntegral eneOffKt)
        , intListData eneOffN
        , I (fromIntegral eneOffNt)
        , I (fromIntegral eneOffBt)
        , I eneNativeSn
        , B eneSaid
        , List (map B eneRevealedKeys)
        , List (map B eneNextKeys)
        , asPlcData eneCurThreshold
        , asPlcData eneNextThreshold
        , I eneToad
        , signatureListData eneCtrlSigs
        , signatureListData eneWitSigs
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
