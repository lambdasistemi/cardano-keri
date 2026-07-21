{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : CheckpointTxBuilder
Description : Production-shaped #116 checkpoint transactions for withDevnet

Loads the tracked-source Aiken blueprint, applies the production checkpoint
validator's six deployment parameters in order, and builds real Conway
transactions for Register, Arm, Advance, Claim, Thaw, and Close.

At the #116 staging revision Register is closed, so a checkpoint token with
production lineage cannot exist.  The running Register smoke dispatches the
closest explicit negative to the checkpoint policy alone; the complete Tx-A
and two-policy Register builders remain compiled for #114.  Advance and Close
fund a correctly addressed, inline-datum, reserve-sized ACTIVE output without
a checkpoint token.  Every running case asserts only Phase-2 rejection and no
staged input is used to claim a positive lifecycle transition.
-}
module CheckpointTxBuilder (
    CheckpointEnv,
    CheckpointInput (..),
    RejectionEvidence,
    BoundaryCases,
    stagedCheckpointDevnet,
    registerRejection,
    advanceRejection,
    closeRejection,
    rejectionReachedProductionScript,
    responseBoundaryCases,
    boundaryCasesCoverDeadline,
    productionRegisterScenario,
    buildArmTx,
    buildAdvanceTx,
    buildClaimTx,
    buildThawTx,
    buildCloseTx,
    armResponseBeforeDeadlineScenario,
    armClaimThawScenario,
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
import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
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
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    RegistrationEvidence (..),
    proofTokenName,
    registrationMessage,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (mkBasicTx, txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
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
import Cardano.Ledger.Core (Script, eraProtVerLow)
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
import Control.Monad (unless)
import Data.Aeson (Value (..), eitherDecodeFileStrict)
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

import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.AID.E2E.Script (
    computeScriptHash,
    extractCompiledCode,
    loadBlueprint,
    mkCageScript,
 )

type SignKey = SignKeyDSIGN Ed25519DSIGN

data CheckpointEnv = CheckpointEnv
    { envCheckpointScript :: !(Script ConwayEra)
    , envCheckpointBytes :: !SBS.ShortByteString
    , envCheckpointHash :: !ScriptHash
    , envCheckpointPolicy :: !PolicyID
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

checkpointNetworkId :: Integer
checkpointNetworkId = 0

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
    dbg "=== NON-DEPLOYABLE UNDER THE PRODUCTION 16384-BYTE CAP ==="
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
            env <- mkCheckpointEnv blueprintPath lsq ltxs
            verifyCheckpointSizeBudget env
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
    let hashProofScript = mkCageScript hashProofCode
        hashProofHash = computeScriptHash hashProofCode
        hashProofPolicy = PolicyID hashProofHash
        appliedCheckpoint =
            applyCheckpointParams
                checkpointVersion
                (policyBytes hashProofPolicy)
                checkpointNetworkId
                registrationBond
                freezeBond
                freezeWindow
                checkpointCode
        checkpointScript = mkCageScript appliedCheckpoint
        checkpointHash = computeScriptHash appliedCheckpoint
        checkpointPolicy = PolicyID checkpointHash
    dbg ("checkpoint script hash: " <> show checkpointHash)
    dbg ("hash-proof script hash: " <> show hashProofHash)
    pure
        CheckpointEnv
            { envCheckpointScript = checkpointScript
            , envCheckpointBytes = appliedCheckpoint
            , envCheckpointHash = checkpointHash
            , envCheckpointPolicy = checkpointPolicy
            , envHashProofScript = hashProofScript
            , envHashProofHash = hashProofHash
            , envHashProofPolicy = hashProofPolicy
            , envProvider = mkN2CProvider lsq
            , envSubmitter = mkN2CSubmitter ltxs
            , envOwner = genesisAddr
            }

{- | Measure the exact signed reference-script creation transaction shape and
keep the production 16 KiB deployability boundary visible even though the
A-015 semantic devnet raises only its transaction-size limit.
-}
verifyCheckpointSizeBudget :: CheckpointEnv -> IO ()
verifyCheckpointSizeBudget env = do
    params <-
        withinSecs 30 "query checkpoint size-budget parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query checkpoint size-budget wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    seed <- requireJust "checkpoint size budget: no wallet UTxO" (largestFirst wallet)
    let referenceOut =
            mkBasicTxOut (envOwner env) (inject (Coin 100_000_000))
                & referenceScriptTxOutL .~ SJust (envCheckpointScript env)
        skeleton =
            mkBasicTx
                (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton referenceOut)
    balanced <-
        either
            (fail . ("checkpoint size budget: balance failed: " <>) . show)
            (pure . balancedTx)
            (balanceTx params [seed] [] (envOwner env) skeleton)
    let signed = addKeyWitness genesisSignKey balanced
        programBytes = SBS.length (envCheckpointBytes env)
        creationTxBytes = fromIntegral (BSL.length (serialize (eraProtVerLow @ConwayEra) signed))
        framingOverhead = creationTxBytes - programBytes
        deployableBudget = productionMaxTxBytes - framingOverhead
        overBudgetBy = programBytes - deployableBudget
        observed =
            ( programBytes
            , creationTxBytes
            , framingOverhead
            , deployableBudget
            , overBudgetBy
            )
    dbg $
        "checkpoint deployability: applied-program="
            <> show programBytes
            <> " creation-tx="
            <> show creationTxBytes
            <> " framing-overhead="
            <> show framingOverhead
            <> " deployable-budget="
            <> show deployableBudget
            <> " over-budget-by="
            <> show overBudgetBy
    unless (observed == expectedCheckpointSizeBudget) $
        fail $
            "checkpoint deployability budget drift: expected "
                <> show expectedCheckpointSizeBudget
                <> "; observed "
                <> show observed

productionMaxTxBytes :: Int
productionMaxTxBytes = 16_384

-- Applied program, signed creation transaction, framing overhead, deployable
-- program budget, and current overage. This is the standing mark-ready gate
-- established by A-015; update only from a fresh real-shape measurement.
expectedCheckpointSizeBudget :: (Int, Int, Int, Int, Int)
expectedCheckpointSizeBudget = (19_565, 19_816, 251, 16_133, 3_432)

applyCheckpointParams ::
    Integer ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCheckpointParams version proofPolicy network dReg bond window code =
    serialiseUPLC $
        uncheckedDeserialiseUPLC code
            `applyDataArg` I version
            `applyDataArg` B proofPolicy
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

registerRejection :: CheckpointEnv -> IO RejectionEvidence
registerRejection env = do
    prepareWallet env
    fixture <- loadRegistrationFixture env
    registerTx <-
        withinSecs 90 "build staged checkpoint Register" $
            buildStagedRegisterTx env fixture
    expectProductionScriptRejection env "Register" registerTx

{- | Complete Tx-A plus two-policy Register path retained for #114.  R6 only
compiles this path because the production checkpoint Register branch is
deliberately closed at the current staged head.
-}
productionRegisterScenario :: CheckpointEnv -> IO CheckpointInput
productionRegisterScenario env = do
    prepareWallet env
    fixture <- loadRegistrationFixture env
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
    pure CheckpointInput{checkpointUtxo = registered, checkpointDatum = rfDatum fixture}

advanceRejection :: CheckpointEnv -> IO RejectionEvidence
advanceRejection env = do
    prepareWallet env
    fixture <- loadRegistrationFixture env
    staged <- stageCheckpointInput env (rfDatum fixture)
    boundary <- responseBoundaryCases env
    tx <-
        buildAdvanceTx
            env
            staged
            (rfDatum fixture)
            dummyAdvanceEvidence
            (justBeforeResponse boundary)
            False
    expectProductionScriptRejection env "Advance" tx

closeRejection :: CheckpointEnv -> IO RejectionEvidence
closeRejection env = do
    prepareWallet env
    fixture <- loadRegistrationFixture env
    staged <- stageCheckpointInput env (rfDatum fixture)
    tx <- buildCloseTx env staged (currentValidity env)
    expectProductionScriptRejection env "Close" tx

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
                                    }

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

loadRegistrationFixture :: CheckpointEnv -> IO RegistrationFixture
loadRegistrationFixture env = do
    path <- getDataFileName "test/keri-fixtures/fixtures/registration.json"
    value <- eitherDecodeFileStrict path >>= either fail pure
    scenario <- either fail pure (atKey "reg_2key" value)
    event <- either fail pure (atKey "event" scenario)
    ked <- either fail pure (atKey "ked" event)
    offsets <- either fail pure (atKey "offsets" scenario)
    seeds <- either fail pure (atKey "signer_seeds" scenario >>= atKey "current")
    raw <- either fail pure (textAt "raw_hex" event >>= decodeHex)
    aid <- either fail pure (textAt "pre" event >>= digestRaw)
    currentKeys <- either fail pure (textArrayAt "k" ked >>= traverse verkeyRaw)
    nextKeys <- either fail pure (textArrayAt "n" ked >>= traverse digestRaw)
    witnesses <- either fail pure (textArrayAt "b" ked >>= traverse verkeyRaw)
    currentThreshold <- either fail pure (thresholdAt "kt" ked)
    nextThreshold <- either fail pure (thresholdAt "nt" ked)
    toad <- either fail pure (hexIntegerAt "bt" ked)
    offT <- either fail pure (integerAt "t" offsets)
    offI <- either fail pure (integerAt "i" offsets)
    offS <- either fail pure (integerAt "s" offsets)
    offK <- either fail pure (integerArrayAt "k" offsets)
    offKt <- either fail pure (integerAt "kt" offsets)
    offN <- either fail pure (integerArrayAt "n" offsets)
    offNt <- either fail pure (integerAt "nt" offsets)
    offB <- either fail pure (integerArrayAt "b" offsets)
    offBt <- either fail pure (integerAt "bt" offsets)
    offD <- either fail pure (eventSaidOffset event)
    signerSeeds <- either fail pure (arrayValues seeds >>= traverse seedFromValue)
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
        context =
            DeploymentContext
                { dcNetworkId = checkpointNetworkId
                , dcCheckpointPolicyId = policyBytes (envCheckpointPolicy env)
                , dcMinAda = checkpointMinAda
                , dcDReg = registrationBond
                }
        preimage = canonicalCbor (registrationMessage context datum)
        signatures =
            [ (index, rawSerialiseSigDSIGN (signDSIGN () preimage signer))
            | (index, signer) <- zip [0 ..] signerSeeds
            ]
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

eventSaidOffset :: Value -> Either String Integer
eventSaidOffset event = do
    raw <- textAt "raw_hex" event >>= decodeHex
    said <- textAt "said" event
    let needle = Text.encodeUtf8 said
    maybe
        (Left "event SAID not found in raw serialization")
        (Right . fromIntegral)
        (findSubsequence needle raw)

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

{- | Closest explicit #116 Register negative.  It carries the real Register
evidence and ACTIVE output and executes only the exact applied checkpoint
policy.  It deliberately has no settled hash-proof input/burn lineage;
successful Tx-A plus the full two-policy transaction below belongs to #114.
-}
buildStagedRegisterTx ::
    CheckpointEnv -> RegistrationFixture -> IO ConwayTx
buildStagedRegisterTx env fixture = do
    params <-
        withinSecs 30 "query staged Register protocol parameters" $
            queryProtocolParams (envProvider env)
    wallet <-
        withinSecs 30 "query staged Register wallet" $
            queryUTxOs (envProvider env) (envOwner env)
    (seed, collateral) <- pickDisjoint wallet []
    let (seedIn, _) = seed
        collateralIn = fst collateral
        checkpointName =
            AssetName $
                SBS.toShort $
                    deriveAidAssetName (cdCesrAid (rfDatum fixture))
        minted =
            MultiAsset $
                Map.singleton
                    (envCheckpointPolicy env)
                    (Map.singleton checkpointName 1)
        stateValue =
            MaryValue
                (Coin (checkpointMinAda + registrationBond + freezeBond))
                minted
        stateOut =
            mkBasicTxOut (roleAddress env Active) stateValue
                & datumTxOutL .~ mkInlineDatum (asPlcData (V1 (rfDatum fixture)))
        redeemers =
            Redeemers $
                Map.singleton
                    (ConwayMinting (AsIx 0))
                    ( ledgerData (registerRedeemerData (rfEvidence fixture))
                    , scriptExUnits
                    )
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton seedIn
                & outputsTxBodyL .~ StrictSeq.singleton stateOut
                & mintTxBodyL .~ minted
                & collateralInputsTxBodyL .~ Set.singleton collateralIn
                & scriptIntegrityHashTxBodyL
                    .~ computeScriptIntegrity PlutusV3 params redeemers
        tx =
            mkBasicTx body
                & witsTxL . scriptTxWitsL
                    .~ Map.singleton (envCheckpointHash env) (envCheckpointScript env)
                & witsTxL . rdmrsTxWitsL .~ redeemers
    either
        (fail . ("buildStagedRegisterTx: balance failed: " <>) . show)
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
        "manual ACTIVE checkpoint input has no production token lineage; only rejection is asserted"
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

armResponseBeforeDeadlineScenario :: CheckpointEnv -> IO ()
armResponseBeforeDeadlineScenario env = do
    fixture <- loadRegistrationFixture env
    boundaries <- responseBoundaryCases env
    let _builders =
            ( buildArmTx
            , buildAdvanceTx
            , rfDatum fixture
            , armUpper boundaries
            , justBeforeResponse boundaries
            )
    _builders `seq` pure ()

armClaimThawScenario :: CheckpointEnv -> IO ()
armClaimThawScenario env = do
    fixture <- loadRegistrationFixture env
    boundaries <- responseBoundaryCases env
    let _builders =
            ( buildArmTx
            , buildClaimTx
            , buildThawTx
            , rfDatum fixture
            , exactDeadlineClaim boundaries
            , afterDeadlineClaim boundaries
            )
    _builders `seq` pure ()

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
atKey key (Object object) =
    maybe (Left (Text.unpack key <> " missing")) Right $
        KeyMap.lookup (Key.fromText key) object
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

seedFromValue :: Value -> Either String SignKey
seedFromValue value = do
    seed <- textAt "seed_hex" value >>= decodeHex
    pure (genKeyDSIGN (mkSeedFromBytes seed))

findSubsequence :: ByteString -> ByteString -> Maybe Int
findSubsequence needle haystack =
    find
        (\offset -> needle `BS.isPrefixOf` BS.drop offset haystack)
        [0 .. BS.length haystack - BS.length needle]
