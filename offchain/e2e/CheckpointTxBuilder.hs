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
    observerEnforcementStakeRegistrationSetup,
    observerLifecycleStakeRegistrationSetup,
    pendingHashProofRegisterArmClaimScenario,
    rejectionIsOldCostPlominBoundary,
    rejectionReachedProductionScript,
    responseBoundaryCases,
    boundaryCasesCoverDeadline,
    productionRegisterScenario,
    assertStockMaxTxSize,
    verifyThreeProgramDeploymentShapes,
    buildArmTx,
    buildAdvanceTx,
    buildClaimTx,
    buildThawTx,
    buildCloseTx,
) where

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
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppCostModelsL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..), costModelsValid, getCostModelParams)
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
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
    vldtTxBodyL,
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
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Cardano.Node.Client.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
 )
import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
    withDevnet,
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
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
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
    , envEnforcementScript :: !(Script ConwayEra)
    , envEnforcementBytes :: !SBS.ShortByteString
    , envEnforcementHash :: !ScriptHash
    , envHashProofScript :: !(Script ConwayEra)
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
    withinSecs 300 "checkpoint withDevnet" $
        withDevnet $ \lsq ltxs -> do
            -- R2 stock-cap boundary FIRST: query the live node for production
            -- maxTxSize = 16384 before any blueprint application. Any non-
            -- stock override fails here with the observed value; this must
            -- not be masked by a stale fixed-output blueprint lookup.
            assertLiveStockMaxTxSize (mkN2CProvider lsq)
            env <- mkCheckpointEnv blueprintPath lsq ltxs
            -- A-004 three-program deployment boundary: both observer hashes
            -- distinct, and one signed reference-script creation shape each
            -- for checkpoint and both observers within the stock cap. This
            -- supersedes the old single-checkpoint 23,124-byte monolith
            -- budget for the family-split architecture.
            verifyThreeProgramDeploymentShapes env
            prepareWallet env
            -- Both observers' script stake credentials must be registered
            -- before any evidence-bearing lifecycle transaction: the
            -- checkpoint ran-check requires the zero-lovelace withdrawal, and
            -- the ledger requires the reward account to be registered.
            lifecycleRegistrationTxId <- observerLifecycleStakeRegistrationSetup env
            dbg ("observer_lifecycle stake credential registered: " <> show lifecycleRegistrationTxId)
            enforcementRegistrationTxId <- observerEnforcementStakeRegistrationSetup env
            dbg ("observer_enforcement stake credential registered: " <> show enforcementRegistrationTxId)
            action env

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
            (fail "checkpoint compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint." blueprint)
    lifecycleCode <-
        maybe
            (fail "observer_lifecycle compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint_observer.observer_lifecycle." blueprint)
    enforcementCode <-
        maybe
            (fail "observer_enforcement compiled code not found in production blueprint")
            pure
            (extractCompiledCode "checkpoint_observer.observer_enforcement." blueprint)
    let hashProofScript = mkCageScript hashProofCode
        hashProofHash = computeScriptHash hashProofCode
        hashProofPolicy = PolicyID hashProofHash
        -- A-004 family split: apply the lifecycle observer first (version,
        -- hash-proof policy, D_reg) and derive its hash; apply the enforcement
        -- observer (version) and derive its hash; then apply the checkpoint
        -- with both hashes (version, lifecycle hash, enforcement hash, D_reg,
        -- freeze bond, freeze window). Neither observer hash becomes an AID
        -- policy or role hash; one checkpoint h remains the identity/policy/
        -- role hash.
        appliedLifecycle =
            applyLifecycleParams
                checkpointVersion
                (policyBytes hashProofPolicy)
                registrationBond
                lifecycleCode
        lifecycleScript = mkCageScript appliedLifecycle
        lifecycleHash = computeScriptHash appliedLifecycle
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
            , envEnforcementScript = enforcementScript
            , envEnforcementBytes = appliedEnforcement
            , envEnforcementHash = enforcementHash
            , envHashProofScript = hashProofScript
            , envHashProofHash = hashProofHash
            , envHashProofPolicy = hashProofPolicy
            , envProvider = mkN2CProvider lsq
            , envSubmitter = mkN2CSubmitter ltxs
            , envOwner = genesisAddr
            }

productionMaxTxBytes :: Int
productionMaxTxBytes = 16_384

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
                    .~ computeScriptIntegrity PlutusV3 params redeemers
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
to be registered. Must run before the first Register/Advance lifecycle use.
-}
observerLifecycleStakeRegistrationSetup :: CheckpointEnv -> IO TxId
observerLifecycleStakeRegistrationSetup env =
    registerObserverStakeCredential
        (envLifecycleHash env)
        (envLifecycleScript env)
        "observer_lifecycle stake-credential registration"
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

{- | Staged-devnet boundary (A-004): assert the two observer hashes are
distinct, then construct and sign one reference-script creation shape for the
checkpoint and each observer, failing if any signed shape exceeds the stock
16,384-byte transaction cap. This is a real boundary measurement, not a getter
or marker.
-}
verifyThreeProgramDeploymentShapes :: CheckpointEnv -> IO ()
verifyThreeProgramDeploymentShapes env = do
    when (envLifecycleHash env == envEnforcementHash env) $
        fail "observer_lifecycle and observer_enforcement hashes are not distinct"
    params <-
        withinSecs 30 "query three-program deployment parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query three-program deployment wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    seed <- requireJust "three-program deployment: no wallet UTxO" (largestFirst wallet)
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
    measureShape "observer_enforcement reference-script" (envEnforcementScript env) (SBS.length (envEnforcementBytes env))

applyCheckpointParams ::
    Integer ->
    ByteString ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCheckpointParams version lifecycleHash enforcementHash dReg bond window code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
            `applyDataArg` B lifecycleHash
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
    assertClaimSettlement env fixture hunter armed claimTxId

advanceRejection :: CheckpointEnv -> IO RejectionEvidence
advanceRejection env = do
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
    (fixture, _) <- loadLifecycleFixture
    staged <- stageCheckpointInput env (rfDatum fixture)
    tx <- buildCloseTx env staged (currentValidity env)
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
                    .~ computeScriptIntegrity PlutusV3 params redeemers
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
buildRegisterTx env fixture proofUtxo = do
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
            AsIx $
                fromIntegral $
                    fromMaybe
                        (error "buildRegisterTx: policy missing from mint order")
                        (elemIndex policy policies)
        redeemers =
            Redeemers $
                Map.fromList
                    [
                        ( ConwayMinting (mintIndex (envCheckpointPolicy env))
                        ,
                            ( ledgerData (registerRedeemerData (rfEvidence fixture))
                            , scriptExUnits
                            )
                        )
                    ,
                        ( ConwayMinting (mintIndex (envHashProofPolicy env))
                        , (ledgerData hashProofBurnRedeemerData, hashProofBurnExUnits)
                        )
                    ]
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allInputs
                & outputsTxBodyL .~ StrictSeq.fromList [stateOut, changeOut]
                & feeTxBodyL .~ Coin scriptFee
                & mintTxBodyL .~ minted
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity PlutusV3 params redeemers
    pure $
        mkBasicTx body
            & witsTxL . scriptTxWitsL
                .~ Map.fromList
                    [ (envCheckpointHash env, envCheckpointScript env)
                    , (envHashProofHash env, envHashProofScript env)
                    ]
            & witsTxL . rdmrsTxWitsL .~ redeemers

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
                    .~ computeScriptIntegrity PlutusV3 params redeemers
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
    provider = envProvider env
    go remaining
        | remaining <= 0 = fail "node did not reach the Claim deadline before polling timed out"
        | otherwise = do
            lower <- withinSecs 30 "query node Claim lower slot" (posixMsCeilSlot provider deadline)
            snapshot <- withinSecs 30 "query node Claim tip" (queryLedgerSnapshot provider)
            if ledgerTipSlot snapshot < lower
                then threadDelay 1_000_000 >> go (remaining - 1)
                else do
                    lowerMs <- slotStartPosixMs env lower
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

slotStartPosixMs :: CheckpointEnv -> SlotNo -> IO Integer
slotStartPosixMs env target = do
    now <- round . (* 1000) <$> getPOSIXTime
    let lo0 = now - 5_000
        hi0 = now + 30_000
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

registerRedeemerData :: RegistrationEvidence -> PLC.Data
registerRedeemerData evidence = Constr 0 [registrationEvidenceData evidence]

advanceRedeemerData :: AdvanceEvidence -> PLC.Data
advanceRedeemerData evidence = Constr 0 [advanceEvidenceData evidence]

freezeRedeemerData :: EnforcementEvidence -> ByteString -> PLC.Data
freezeRedeemerData evidence hunter =
    Constr 1 [enforcementEvidenceData evidence, B hunter]

claimRedeemerData :: Integer -> PLC.Data
claimRedeemerData outputIndex = Constr 2 [I outputIndex]

closeRedeemerData :: PLC.Data
closeRedeemerData = Constr 4 []

registrationEvidenceData :: RegistrationEvidence -> PLC.Data
registrationEvidenceData RegistrationEvidence{..} =
    Constr
        0
        [ B reEventBytes
        , I (fromIntegral reOffT)
        , I (fromIntegral reOffI)
        , I (fromIntegral reOffS)
        , intListData reOffK
        , I (fromIntegral reOffKt)
        , intListData reOffN
        , I (fromIntegral reOffNt)
        , intListData reOffB
        , I (fromIntegral reOffBt)
        , signatureListData reCtrlSigs
        , signatureListData reWitReceipts
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

asPlcData :: (ToData a) => a -> PLC.Data
asPlcData value = let BuiltinData dat = toBuiltinData value in dat

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
