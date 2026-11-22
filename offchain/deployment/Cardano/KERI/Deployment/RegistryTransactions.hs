{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryTransactions
Description : The transactions that create a registry and register an identity in it

The transactions of the registry's application, as pure builders a command can
call on any network with any funded wallet: publish the state template and the
two reference scripts, create the registry's configuration and state
('createConfiguration'), book a registration ('bookRegistration'), premint the
hash proof the fold burns ('mintHashProof'), fold a booked request into the
registry ('foldRegistration') and return an unfolded one after its deadline
('returnRequests').

Nothing here talks to a node or holds a key. A builder is given the network,
the current protocol parameters, the party that pays (its address and the
outputs that fund it) and the registry's terms, and returns an unsigned
transaction; the caller evaluates, signs and submits it. Every fee is the
ledger's minimum for the transaction and the protocol parameters it is built
under, for one signature of the paying party.
-}
module Cardano.KERI.Deployment.RegistryTransactions (
    -- * What a transaction is built against
    RegistryDeployment (..),
    RegistryReferences (..),
    Payer (..),
    ValidityPlan (..),
    Budgets,
    BuiltTransaction,
    RegistryTransactionError (..),

    -- * What a registration is
    Booking (..),
    registrationRecord,
    registeredFacts,
    approval,
    requestLovelace,
    deliveredHolding,
    inceptionProofName,

    -- * Transactions
    publishTemplate,
    publishReferenceScript,
    createConfiguration,
    bookRegistration,
    mintHashProof,
    FoldPlan (..),
    foldRegistration,
    returnRequests,

    -- * The names a deployment fixes
    applicationPolicyId,
    statePolicyId,
    applicationAddress,
    stateAddress,
    checkpointAddress,

    -- * The registry's keys
    emptyRoot,
    registryRootOf,
    registryProof,

    -- * Shared with the builders of other transactions
    redeemerMap,
    tokenValue,
    mintingIndex,
    outputReferenceOf,
    plutusAddressOf,
    scriptExUnits,
    hashProofBurnExUnits,
) where

import Cardano.Crypto.Hash (hashToBytes)
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
    terminalLeaf,
    unstakedAddress,
 )
import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyStateView (..),
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    asPlcData,
    registerObserverRedeemerData,
 )
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum, rawInlineData)
import Cardano.KERI.AID.E2E.FoldGuard (FoldRefusal (..), foldRefusal)
import Cardano.KERI.AID.E2E.MpfProof (prove)
import Cardano.KERI.AID.E2E.MpfTrie qualified as Trie
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
 )
import Cardano.KERI.Deployment.Script (
    Observers (..),
    ScriptArtifact (..),
    computeScriptHash,
    mkCageScript,
    scriptHashBytes,
 )
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
    serialiseAddr,
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (ppCollateralPercentageL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    treasuryDonationTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    coinTxOutL,
    datumTxOutL,
    getMinCoinTxOut,
    mkBasicTxOut,
    referenceScriptTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    Inject (..),
    Network,
    StrictMaybe (SJust),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..), unCoin)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams, Script, ppMaxTxSizeL, sizeTxF)
import Cardano.Ledger.Credential (
    Credential (..),
    StakeReference (..),
 )
import Cardano.Ledger.Hashes (ScriptHash (..), extractHash)
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
    filterMultiAsset,
    mapMaybeMultiAsset,
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (SlotNo)
import Cardano.Tx.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    FeeLoopError (..),
    balanceFeeLoop,
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
    spendingIndex,
 )
import Control.Applicative ((<|>))
import Control.Monad (when)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Short qualified as SBS
import Data.Either (lefts, rights)
import Data.List (elemIndex, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Word (Word32)
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data (Data (..))
import PlutusCore.Data qualified as PLC

-- | The registry a transaction is built against: the chain it runs on and what it is derived from.
data RegistryDeployment = RegistryDeployment
    { deploymentNetwork :: !Network
    , deploymentTerms :: !RegistryTerms
    , deploymentScripts :: !RegistryScripts
    }

-- | The outputs a registry's transactions read by reference, once its genesis has settled.
data RegistryReferences = RegistryReferences
    { referenceApplication :: !(TxIn, TxOut ConwayEra)
    -- ^ the application script, published
    , referenceState :: !(TxIn, TxOut ConwayEra)
    -- ^ the state script, published
    , referenceConfiguration :: !(TxIn, TxOut ConwayEra)
    -- ^ the registry's configuration record
    }

-- | Who pays a transaction: the address that receives the change and the outputs that fund it.
data Payer = Payer
    { payerAddress :: !Addr
    , payerFunds :: ![(TxIn, TxOut ConwayEra)]
    }

-- | A validity interval: the slots the transaction declares and the instants they stand for.
data ValidityPlan = ValidityPlan
    { lowerSlot :: !SlotNo
    , upperSlot :: !SlotNo
    , lowerPosixMs :: !Integer
    , upperPosixMs :: !Integer
    }
    deriving stock (Show, Eq)

{- | The execution units a caller measured for the purposes of a transaction.
A purpose without an entry is declared at a placeholder budget, which is what
a caller evaluates the transaction under to measure it.
-}
type Budgets = Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits

-- | An unsigned transaction and the script purposes it carries.
type BuiltTransaction = (ConwayTx, Set (ConwayPlutusPurpose AsIx ConwayEra))

-- | Why a builder built nothing.
data RegistryTransactionError
    = -- | the payer's outputs do not hold the fee input and the collateral the transaction needs
      NotEnoughFunds !String
    | -- | the ledger's balancing refused the transaction
      BalanceRefused !String
    | -- | the fee does not settle, or the payer's outputs do not cover it
      FeeRefused !String
    | -- | a fold the registry would refuse, found before anything is built
      FoldRefused !FoldRefusal
    | -- | the inception does not hash to its own identifier at the offsets given
      InceptionDoesNotBindItsIdentifier
    | -- | the genesis was given a seed other than the one its registry is derived from
      SeedIsNotTheRegistrys
    | -- | the transaction, with the outputs that fund it, exceeds the largest size a transaction may have: its size and that limit
      TransactionTooLarge !Integer !Integer
    deriving stock (Eq, Show)

-- | A booked request: its output and the record it carries.
data Booking = Booking
    { bookingOutput :: !(TxIn, TxOut ConwayEra)
    , bookingRecord :: !RegistrationData
    , bookingValidity :: !ValidityPlan
    }

-- ---------------------------------------------------------------------
-- The names a deployment fixes
-- ---------------------------------------------------------------------

applicationHash :: RegistryDeployment -> ScriptHash
applicationHash = artifactScriptHash . scriptsApplication . deploymentScripts

stateHash :: RegistryDeployment -> ScriptHash
stateHash = computeScriptHash . scriptsStateProgram . deploymentScripts

checkpointHash :: RegistryDeployment -> ScriptHash
checkpointHash = artifactScriptHash . scriptsCheckpoint . deploymentScripts

lifecycleHash :: RegistryDeployment -> ScriptHash
lifecycleHash =
    artifactScriptHash . observerLifecycle . scriptsObservers . deploymentScripts

hashProofArtifact :: RegistryDeployment -> ScriptArtifact
hashProofArtifact = observerHashProof . scriptsObservers . deploymentScripts

registryOf :: RegistryDeployment -> RegistryIdentity
registryOf = scriptsRegistry . deploymentScripts

seedOf :: RegistryDeployment -> OutputReference
seedOf = scriptsSeed . deploymentScripts

parametersOf :: RegistryDeployment -> ApplicationParameters
parametersOf = registryParameters . deploymentTerms

scriptAddress :: RegistryDeployment -> ScriptHash -> Addr
scriptAddress deployment hash =
    Addr (deploymentNetwork deployment) (ScriptHashObj hash) StakeRefNull

-- | The policy of the registry's application.
applicationPolicyId :: RegistryDeployment -> PolicyID
applicationPolicyId = PolicyID . applicationHash

-- | The policy of the registry's state script.
statePolicyId :: RegistryDeployment -> PolicyID
statePolicyId = PolicyID . stateHash

-- | Where the configuration record and the requests are held.
applicationAddress :: RegistryDeployment -> Addr
applicationAddress deployment = scriptAddress deployment (applicationHash deployment)

-- | Where the registry's state is held.
stateAddress :: RegistryDeployment -> Addr
stateAddress deployment = scriptAddress deployment (stateHash deployment)

-- | Where a fold delivers a checkpoint: the checkpoint validator's address.
checkpointAddress :: RegistryDeployment -> Addr
checkpointAddress deployment = scriptAddress deployment (checkpointHash deployment)

-- ---------------------------------------------------------------------
-- What a registration is
-- ---------------------------------------------------------------------

{- | The record a request commits for an identity, booked over a validity
interval: the identity's initial live datum born at the interval's upper bound,
the deposit, and the deadline the registry's processing time gives. The refund
address is also the controller of the request.
-}
registrationRecord ::
    RegistryDeployment ->
    -- | the refund address and the controller
    Addr ->
    -- | the deposit the request commits
    Integer ->
    InceptionExport ->
    ValidityPlan ->
    RegistrationData
registrationRecord deployment refund deposit export validity =
    RegistrationData
        { requestRegistry = registryOf deployment
        , requestKey = key
        , requestController = controller
        , requestRefundAddress = plutusAddressOf refund
        , requestHoldingAddress =
            unstakedAddress (ScriptCredential (scriptHashBytes (checkpointHash deployment)))
        , requestInitialDatum = asPlcData (V2 facts)
        , requestDeposit = deposit
        , requestBookedAt = upperPosixMs validity
        , requestProcessDeadline = deadline
        , requestReclaimEnd = deadline
        }
  where
    deadline = upperPosixMs validity + processTime (parametersOf deployment)
    facts = registeredFacts refund export validity
    key = case facts of
        Live{lvAid} -> lvAid
        TerminationPending{} -> error "registrationRecord: an inception is live"
    controller = case plutusAddressOf refund of
        PlutusAddress (KeyCredential hash) _ -> hash
        _ -> error "registrationRecord: the refund address is held by a key"

{- | The datum a registration writes: the inception's key state born at the end
of the validity interval, refunding the given address.
-}
registeredFacts :: Addr -> InceptionExport -> ValidityPlan -> CheckpointDatumV2
registeredFacts refund export validity =
    liveOfKeyState (serialiseAddr refund) (upperPosixMs validity) (inceptionDatum export)

-- | The approval token name of a request.
approval :: RegistrationData -> ByteString
approval record =
    registrationApprovalName
        (requestRegistry record)
        (requestKey record)
        (requestHoldingAddress record)
        (requestInitialDatum record)
        (requestDeposit record)

-- | The lovelace a booked request holds: the deposit, the registration cost and the minimum tip.
requestLovelace :: ApplicationParameters -> RegistrationData -> Integer
requestLovelace parameters record =
    requestDeposit record + registrationCost parameters + minimumTip parameters

{- | The holding a fold delivers: the committed deposit and the active token of
the request's key at the checkpoint validator's address, carrying the
committed initial datum.
-}
deliveredHolding :: RegistryDeployment -> RegistrationData -> TxOut ConwayEra
deliveredHolding deployment record =
    mkBasicTxOut
        (checkpointAddress deployment)
        ( MaryValue
            (Coin (requestDeposit record))
            (tokenValue (statePolicyId deployment) active 1)
        )
        & datumTxOutL .~ mkInlineDatum (requestInitialDatum record)
  where
    active = activeTokenName (requestRegistry record) (requestKey record)

-- ---------------------------------------------------------------------
-- Transactions
-- ---------------------------------------------------------------------

{- | Publish the template of the state script: an output holding the given
lovelace whose inline datum is the template bytes, referenced by the genesis.
-}
publishTemplate ::
    PParams ConwayEra ->
    Payer ->
    -- | the lovelace of the published output
    Coin ->
    ByteString ->
    Either RegistryTransactionError ConwayTx
publishTemplate parameters payer lovelace template =
    publishOutput
        parameters
        payer
        ( mkBasicTxOut (payerAddress payer) (inject lovelace)
            & datumTxOutL .~ mkInlineDatum (B template)
        )

-- | Publish a script as a reference script of an output holding the given lovelace.
publishReferenceScript ::
    PParams ConwayEra ->
    Payer ->
    -- | the lovelace of the published output
    Coin ->
    Script ConwayEra ->
    Either RegistryTransactionError ConwayTx
publishReferenceScript parameters payer lovelace script =
    publishOutput
        parameters
        payer
        ( mkBasicTxOut (payerAddress payer) (inject lovelace)
            & referenceScriptTxOutL .~ SJust script
        )

publishOutput ::
    PParams ConwayEra ->
    Payer ->
    TxOut ConwayEra ->
    Either RegistryTransactionError ConwayTx
publishOutput parameters payer output =
    firstSuccess
        [ balancedTx
            <$> first
                (BalanceRefused . show)
                (balanceTx parameters inputs [] (payerAddress payer) skeleton)
        | inputs <- spendingSets 1 (payerFunds payer)
        ]
  where
    skeleton =
        mkBasicTx
            (mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton output)

{- | The genesis of the registry: spend the seed, mint the state token into an
empty state and the configuration token into the configuration record, with the
template and the two scripts by reference. The seed is the output the
registry's identity is derived from: any other is refused. The payer's outputs
fund what the seed does not cover and one of them is the collateral.
-}
createConfiguration ::
    PParams ConwayEra ->
    RegistryDeployment ->
    -- | the template and the two reference scripts the genesis reads
    [(TxIn, TxOut ConwayEra)] ->
    Payer ->
    -- | the seed output
    (TxIn, TxOut ConwayEra) ->
    -- | the parameters the configuration record holds
    ApplicationParameters ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
createConfiguration parameters deployment references payer seedUtxo configured budgets = do
    when (outputReferenceOf (fst seedUtxo) /= seedOf deployment) $
        Left SeedIsNotTheRegistrys
    firstFunded budgets (fundings [fst seedUtxo] (payerFunds payer)) attempt
  where
    stateName = stateTokenName (seedOf deployment)
    configName = configurationTokenName (registryOf deployment)
    stateMinted = tokenValue (statePolicyId deployment) stateName 1
    configMinted = tokenValue (applicationPolicyId deployment) configName 1
    minted = stateMinted <> configMinted
    stateOut =
        mkBasicTxOut
            (stateAddress deployment)
            (MaryValue (Coin recordLovelace) stateMinted)
            & datumTxOutL .~ mkInlineDatum (stateDatumData emptyRoot)
    configOut =
        mkBasicTxOut
            (applicationAddress deployment)
            (MaryValue (Coin recordLovelace) configMinted)
            & datumTxOutL
                .~ mkInlineDatum
                    ( heldDatumData
                        ( Configuration
                            configured
                            (ScriptCredential (scriptHashBytes (checkpointHash deployment)))
                        )
                    )
    stateIx = fromIntegral (mintingIndex (statePolicyId deployment) minted)
    appIx = fromIntegral (mintingIndex (applicationPolicyId deployment) minted)
    purposes =
        [ (ConwayMinting (AsIx stateIx), stateMintData (Genesis (seedOf deployment)), scriptExUnits)
        ,
            ( ConwayMinting (AsIx appIx)
            , List [actionData (CreateConfiguration (registryOf deployment) (seedOf deployment) 1)]
            , scriptExUnits
            )
        ]
    attempt chosen funding = do
        let redeemers = redeemerMap chosen purposes
            spent = seedUtxo : fundingInputs funding
        built <-
            balanced
                parameters
                references
                spent
                [stateOut, configOut]
                (payerAddress payer)
                funding
                ( mkBasicTx
                    ( mkBasicTxBody
                        & mintTxBodyL .~ minted
                        & referenceInputsTxBodyL .~ Set.fromList (map fst references)
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)

{- | The booking transaction of a request over a validity interval. The request
holds the lovelace the registry requires, moved by the given difference: zero
is the booking the application accepts.
-}
bookRegistration ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    Payer ->
    RegistrationData ->
    ValidityPlan ->
    -- | the lovelace the request holds beyond 'requestLovelace'
    Integer ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
bookRegistration parameters deployment references payer record validity difference budgets =
    firstFunded budgets (fundings [] (payerFunds payer)) attempt
  where
    minted = tokenValue (applicationPolicyId deployment) (approval record) 1
    held = requestLovelace (parametersOf deployment) record + difference
    requestOut =
        mkBasicTxOut
            (applicationAddress deployment)
            (MaryValue (Coin held) minted)
            & datumTxOutL .~ mkInlineDatum (heldDatumData (Registration record))
    purposes =
        [(ConwayMinting (AsIx 0), List [actionData (BookRegistration 0)], scriptExUnits)]
    resolved = [referenceConfiguration references, referenceApplication references]
    attempt chosen funding = do
        let redeemers = redeemerMap chosen purposes
        built <-
            balanced
                parameters
                resolved
                (fundingInputs funding)
                [requestOut]
                (payerAddress payer)
                funding
                ( mkBasicTx
                    ( mkBasicTxBody
                        & mintTxBodyL .~ minted
                        & referenceInputsTxBodyL .~ Set.fromList (map fst resolved)
                        & vldtTxBodyL .~ validityOf validity
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)

{- | The hash-proof mint of an inception, paid to a party: the evidence the fold
burns. The inception must hash to its own identifier at the offsets it carries.
-}
mintHashProof ::
    PParams ConwayEra ->
    RegistryDeployment ->
    Payer ->
    InceptionExport ->
    Either RegistryTransactionError ConwayTx
mintHashProof parameters deployment payer export = do
    if blake3Hash saidBlank == aid
        then Right ()
        else Left InceptionDoesNotBindItsIdentifier
    firstFunded Map.empty (fundings [] (payerFunds payer)) (const attempt)
  where
    artifact = hashProofArtifact deployment
    policy = PolicyID (artifactScriptHash artifact)
    minted = MultiAsset (Map.singleton policy (Map.singleton proofName 1))
    proofOut = mkBasicTxOut (payerAddress payer) (MaryValue (Coin hashProofLovelace) minted)
    redeemers =
        Redeemers $
            Map.singleton
                (ConwayMinting (AsIx 0))
                (Ledger.Data hashProofRedeemer, hashProofExUnits)
    evidence = inceptionEvidence export
    raw = reEventBytes evidence
    aid = cdCesrAid (inceptionDatum export)
    offI = reOffI evidence
    offD = inceptionDigestOffset export
    proofName = AssetName (SBS.toShort (inceptionProofName export))
    hashProofRedeemer =
        Constr 0 [B raw, B aid, I (fromIntegral offI), I (fromIntegral offD)]
    saidBlank =
        BS.take offD raw
            <> B8.replicate 44 '#'
            <> BS.take (offI - offD - 44) (BS.drop (offD + 44) raw)
            <> B8.replicate 44 '#'
            <> BS.drop (offI + 44) raw
    attempt funding =
        balancedTx
            <$> first
                (BalanceRefused . show)
                ( balanceTxWith
                    parameters
                    (fundingInputs funding)
                    (CollateralUtxos [fundingCollateral funding])
                    []
                    (payerAddress payer)
                    Nothing
                    ( mkBasicTx
                        ( mkBasicTxBody
                            & inputsTxBodyL .~ Set.fromList (map fst (fundingInputs funding))
                            & outputsTxBodyL .~ StrictSeq.singleton proofOut
                            & mintTxBodyL .~ minted
                            & collateralInputsTxBodyL .~ Set.singleton (fst (fundingCollateral funding))
                            & scriptIntegrityHashTxBodyL
                                .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                        )
                        & witsTxL . scriptTxWitsL
                            .~ Map.singleton
                                (artifactScriptHash artifact)
                                (mkCageScript (artifactProgram artifact))
                        & witsTxL . rdmrsTxWitsL .~ redeemers
                    )
                )

{- | The fold of a booked request into the registry by a party: the registration
observer attests the inception, the state script inserts the key, the
application burns the approval and the holding is delivered to the checkpoint
address.
-}
data FoldPlan = FoldPlan
    { foldBooking :: !Booking
    , foldInception :: !InceptionExport
    , foldProof :: !(TxIn, TxOut ConwayEra)
    -- ^ the hash-proof output the fold burns
    , foldReferences :: ![(TxIn, TxOut ConwayEra)]
    -- ^ the references of the lifecycle observer and the hash-proof policy
    , foldRegistered :: ![ByteString]
    -- ^ the keys the registry already holds as active
    , foldTerminated :: ![ByteString]
    -- ^ the keys the registry holds as terminal, as the caller recorded them
    , foldState :: !(TxIn, TxOut ConwayEra)
    -- ^ the registry state output the fold spends
    , foldValidity :: !ValidityPlan
    , foldPayer :: !Payer
    }

{- | Fold a booked request into the registry. Nothing is computed for a request
whose key the registry holds, or when the keys given are not the registry the
state output holds: the refusal is returned by name.
-}
foldRegistration ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    FoldPlan ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
foldRegistration parameters deployment references plan budgets = do
    foldGuard (foldRegistered plan) (foldTerminated plan) key (snd (foldState plan))
    firstFunded budgets (fundings [proofIn] (payerFunds (foldPayer plan))) attempt
  where
    Booking{bookingOutput = (requestIn, _), bookingRecord = record} = foldBooking plan
    (proofIn, _) = foldProof plan
    (stateIn, stateOutBefore) = foldState plan
    key = requestKey record
    proofName = inceptionProofName (foldInception plan)
    hashProofPolicy = PolicyID (artifactScriptHash (hashProofArtifact deployment))
    active = activeTokenName (registryOf deployment) key
    minted =
        tokenValue (applicationPolicyId deployment) (approval record) (-1)
            <> tokenValue (statePolicyId deployment) active 1
            <> tokenValue hashProofPolicy proofName (-1)
    stateOut =
        mkBasicTxOut
            (stateAddress deployment)
            ( MaryValue
                (stateOutBefore ^. coinTxOutL)
                (tokenValue (statePolicyId deployment) (stateTokenName (seedOf deployment)) 1)
            )
            & datumTxOutL .~ mkInlineDatum (stateDatumData newRoot)
    cost = registrationCost (parametersOf deployment)
    (proofSteps, newRoot) = registryProof (foldRegistered plan) (foldTerminated plan) key
    resolved =
        [ referenceConfiguration references
        , referenceApplication references
        , referenceState references
        ]
            <> foldReferences plan
    attempt chosen funding = do
        let spent =
                [bookingOutput (foldBooking plan), foldState plan, foldProof plan]
                    <> fundingInputs funding
            inputs = Set.fromList (map fst spent)
            mintIx policy = fromIntegral (mintingIndex policy minted)
            purposes =
                [
                    ( ConwaySpending (AsIx (spendingIndex requestIn inputs))
                    , spendActionData (FoldRegistration 0)
                    , scriptExUnits
                    )
                ,
                    ( ConwaySpending (AsIx (spendingIndex stateIn inputs))
                    , stateSpendData
                        (seedOf deployment)
                        [ Register
                            { changeRequest = outputReferenceOf requestIn
                            , changeKey = key
                            , changeHolding = 0
                            , changeDeposit = requestDeposit record
                            , changeProof = proofSteps
                            }
                        ]
                    , scriptExUnits
                    )
                , (ConwayMinting (AsIx (mintIx (applicationPolicyId deployment))), List [], scriptExUnits)
                , (ConwayMinting (AsIx (mintIx (statePolicyId deployment))), stateMintData Folded, scriptExUnits)
                ,
                    ( ConwayMinting (AsIx (mintIx hashProofPolicy))
                    , hashProofBurnRedeemer
                    , hashProofBurnExUnits
                    )
                ,
                    ( ConwayRewarding (AsIx 0)
                    , registerObserverRedeemerData
                        (scriptHashBytes (checkpointHash deployment))
                        (inceptionEvidence (foldInception plan))
                    , scriptExUnits
                    )
                ]
            redeemers = redeemerMap chosen purposes
        built <-
            balanced
                parameters
                resolved
                spent
                [deliveredHolding deployment record, stateOut]
                (payerAddress (foldPayer plan))
                funding
                ( mkBasicTx
                    ( mkBasicTxBody
                        & mintTxBodyL .~ minted
                        & withdrawalsTxBodyL
                            .~ Withdrawals
                                ( Map.singleton
                                    ( AccountAddress
                                        (deploymentNetwork deployment)
                                        (AccountId (ScriptHashObj (lifecycleHash deployment)))
                                    )
                                    (Coin 0)
                                )
                        & treasuryDonationTxBodyL .~ Coin cost
                        & referenceInputsTxBodyL .~ Set.fromList (map fst resolved)
                        & vldtTxBodyL .~ validityOf (foldValidity plan)
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)

{- | What the builder checks before it computes anything for a fold: the
request's key is not one the registry holds, and the keys it was given are
the registry the chain holds (their root is the state output's datum).
-}
foldGuard ::
    [ByteString] ->
    [ByteString] ->
    ByteString ->
    TxOut ConwayEra ->
    Either RegistryTransactionError ()
foldGuard registered terminated key stateOut =
    case foldRefusal registered terminated key of
        Just refusal -> Left (FoldRefused refusal)
        Nothing
            | rawInlineData stateOut /= Just (stateDatumData (registryRootOf registered terminated)) ->
                Left (FoldRefused KeysAreNotTheRegistry)
            | otherwise -> Right ()

{- | The return of a booked request after its deadline: the refund address is
paid everything but the tip, and the returner keeps the tip.
-}
returnRequests ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    Payer ->
    Booking ->
    ValidityPlan ->
    -- | where the refund goes
    Addr ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
returnRequests parameters deployment references payer booking validity refundTo budgets =
    firstFunded budgets (fundings [] (payerFunds payer)) attempt
  where
    Booking{bookingOutput = (requestIn, requestOut), bookingRecord = record} = booking
    tip = minimumTip (parametersOf deployment)
    minted = tokenValue (applicationPolicyId deployment) (approval record) (-1)
    refundOut = mkBasicTxOut refundTo (inject (Coin (unCoin (requestOut ^. coinTxOutL) - tip)))
    resolved = [referenceConfiguration references, referenceApplication references]
    attempt chosen funding = do
        let spent = bookingOutput booking : fundingInputs funding
            inputs = Set.fromList (map fst spent)
            purposes =
                [
                    ( ConwaySpending (AsIx (spendingIndex requestIn inputs))
                    , spendActionData ReturnRegistration
                    , scriptExUnits
                    )
                , (ConwayMinting (AsIx 0), List [], scriptExUnits)
                ]
            redeemers = redeemerMap chosen purposes
        built <-
            balanced
                parameters
                resolved
                spent
                [refundOut]
                (payerAddress payer)
                funding
                ( mkBasicTx
                    ( mkBasicTxBody
                        & mintTxBodyL .~ minted
                        & referenceInputsTxBodyL .~ Set.fromList (map fst resolved)
                        & vldtTxBodyL .~ validityOf validity
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)

-- ---------------------------------------------------------------------
-- The registry's keys
-- ---------------------------------------------------------------------

-- | The registry's empty root.
emptyRoot :: ByteString
emptyRoot = BS.replicate 32 0

-- | The root of a registry holding the given active and terminal keys.
registryRootOf :: [ByteString] -> [ByteString] -> ByteString
registryRootOf [] [] = emptyRoot
registryRootOf active terminated =
    Trie.rootOf
        ( Trie.build
            ([(held, activeLeaf) | held <- active] <> [(held, terminalLeaf) | held <- terminated])
        )

{- | The proof that a key is absent from the registry that holds the keys, and
the root after it is inserted: the registry binds every key to the active leaf.
-}
registryProof :: [ByteString] -> [ByteString] -> ByteString -> ([PLC.Data], ByteString)
registryProof registered terminated key =
    ( map asPlcData (prove tree key)
    , Trie.rootOf tree
    )
  where
    tree =
        Trie.build
            ( [(held, activeLeaf) | held <- registered <> [key]]
                <> [(held, terminalLeaf) | held <- terminated]
            )

-- ---------------------------------------------------------------------
-- Shared with the builders of other transactions
-- ---------------------------------------------------------------------

-- | The lovelace each record of the genesis holds.
recordLovelace :: Integer
recordLovelace = 3_000_000

-- | The lovelace of a hash-proof output.
hashProofLovelace :: Integer
hashProofLovelace = 5_000_000

{- | The budget a purpose is declared at until a caller has measured it: the
transactions are evaluated under it to find what each purpose needs.
-}
scriptExUnits :: ExUnits
scriptExUnits = ExUnits 12_000_000 7_000_000_000

hashProofExUnits :: ExUnits
hashProofExUnits = ExUnits 14_000_000 10_000_000_000

-- | The budget of the hash-proof burn, which does no hashing.
hashProofBurnExUnits :: ExUnits
hashProofBurnExUnits = ExUnits 500_000 500_000_000

hashProofBurnRedeemer :: PLC.Data
hashProofBurnRedeemer = Constr 0 [B "", B "", I 0, I 0]

-- | The redeemers of a set of purposes, each with its budget or the fallback.
redeemerMap ::
    Map (ConwayPlutusPurpose AsIx ConwayEra) ExUnits ->
    [(ConwayPlutusPurpose AsIx ConwayEra, PLC.Data, ExUnits)] ->
    Redeemers ConwayEra
redeemerMap budgets purposes =
    Redeemers $
        Map.fromList
            [ (purpose, (Ledger.Data redeemer, Map.findWithDefault fallback purpose budgets))
            | (purpose, redeemer, fallback) <- purposes
            ]

purposeSet ::
    [(ConwayPlutusPurpose AsIx ConwayEra, PLC.Data, ExUnits)] ->
    Set (ConwayPlutusPurpose AsIx ConwayEra)
purposeSet purposes = Set.fromList [purpose | (purpose, _, _) <- purposes]

-- | The ledger value of one token.
tokenValue :: PolicyID -> ByteString -> Integer -> MultiAsset
tokenValue policy name quantity =
    MultiAsset $
        Map.singleton policy (Map.singleton (AssetName (SBS.toShort name)) quantity)

{- | The minting-purpose index of one policy in a transaction's mint map.

Ledger minting purposes are indexed by the policy's position in the sorted mint
map.
-}
mintingIndex :: PolicyID -> MultiAsset -> Word32
mintingIndex policy (MultiAsset assets) =
    case elemIndex policy (Map.keys assets) of
        Just index -> fromIntegral index
        Nothing -> error "mintingIndex: policy absent from the mint map"

-- | The ledger reference as the registry's wire reference.
outputReferenceOf :: TxIn -> OutputReference
outputReferenceOf (TxIn (TxId safeHash) (TxIx outputIndex)) =
    OutputReference
        (hashToBytes (extractHash safeHash))
        (fromIntegral outputIndex)

{- | The Plutus address of a ledger address with a key or script payment
credential, with no stake part or a stake credential.
-}
plutusAddressOf :: Addr -> PlutusAddress
plutusAddressOf (Addr _ payment stake) =
    PlutusAddress (credentialOf payment) (stakeOf stake)
  where
    credentialOf = \case
        KeyHashObj (KeyHash hash) -> KeyCredential (hashToBytes hash)
        ScriptHashObj (ScriptHash hash) -> ScriptCredential (hashToBytes hash)
    stakeOf = \case
        StakeRefNull -> Nothing
        StakeRefBase credential -> Just (credentialOf credential)
        StakeRefPtr _ -> error "plutusAddressOf: a pointer stake part has no Plutus address"
plutusAddressOf _ = error "plutusAddressOf: a Byron address has no Plutus address"

-- ---------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------

validityOf :: ValidityPlan -> ValidityInterval
validityOf validity =
    ValidityInterval (SJust (lowerSlot validity)) (SJust (upperSlot validity))

coinOf :: TxOut ConwayEra -> Integer
coinOf out = unCoin (out ^. coinTxOutL)

assetsOf :: TxOut ConwayEra -> MultiAsset
assetsOf out = let MaryValue _ assets = out ^. valueTxOutL in assets

hasAssets :: TxOut ConwayEra -> Bool
hasAssets = (/= mempty) . assetsOf

{- | The outputs that fund a transaction: the ones that pay its fee and the
change, and the one that is its collateral.
-}
data Funding = Funding
    { fundingInputs :: ![(TxIn, TxOut ConwayEra)]
    , fundingCollateral :: !(TxIn, TxOut ConwayEra)
    }

{- | The outputs of a payer in the order they are spent: those without native
assets first, each group largest first.
-}
spendOrder :: [(TxIn, TxOut ConwayEra)] -> [(TxIn, TxOut ConwayEra)]
spendOrder = sortOn (\(_, out) -> (hasAssets out, Down (coinOf out)))

-- | The first outputs of the spending order, as many as the given count and every more.
spendingSets :: Int -> [(TxIn, TxOut ConwayEra)] -> [[(TxIn, TxOut ConwayEra)]]
spendingSets least funds =
    [take count ordered | count <- [least .. length ordered]]
  where
    ordered = spendOrder funds

{- | What a payer's outputs can fund, best first: a collateral without native
assets, the smallest first, and for each every other output that pays the fee,
in the spending order, one more at a time and without a limit on their number.
The outputs excluded are spent by the transaction already.
-}
fundings :: [TxIn] -> [(TxIn, TxOut ConwayEra)] -> [Funding]
fundings excluded funds =
    [ Funding inputs collateral
    | collateral <- sortOn (coinOf . snd) (filter (not . hasAssets . snd) usable)
    , inputs <- spendingSets 0 (filter ((/= fst collateral) . fst) usable)
    ]
  where
    usable = filter ((`notElem` excluded) . fst) funds

-- | The first attempt that builds, or the failure of the first attempt.
firstSuccess :: [Either RegistryTransactionError a] -> Either RegistryTransactionError a
firstSuccess attempts = case rights attempts of
    built : _ -> Right built
    [] -> case lefts attempts of
        failure : _ -> Left failure
        [] -> Left (NotEnoughFunds "the payer has no output to spend")

{- | Build on the first funding that builds when the transaction is declared at
the placeholder budgets, and on exactly that funding under the budgets given:
the outputs a transaction spends do not depend on the units a caller measured,
so the purposes it carries are the same whatever the budgets.
-}
firstFunded ::
    Budgets ->
    [Funding] ->
    (Budgets -> Funding -> Either RegistryTransactionError a) ->
    Either RegistryTransactionError a
firstFunded budgets candidates attempt = do
    chosen <- choose Nothing candidates
    attempt budgets chosen
  where
    choose failure [] =
        Left (fromMaybe (NotEnoughFunds "the payer has no output to spend") failure)
    choose failure (candidate : rest) = case attempt Map.empty candidate of
        Right _ -> Right candidate
        Left tooLarge@(TransactionTooLarge _ _) -> Left tooLarge
        Left other -> choose (failure <|> Just other) rest

{- | The transaction with its inputs, its fixed outputs, a change output and the
ledger's minimum fee: the change takes the lovelace and the native assets the
inputs hold and the outputs, the donation and the fee do not. The collateral
must cover its share of the fee, and the change must hold its own minimum.
-}
balanced ::
    PParams ConwayEra ->
    -- | the outputs read by reference, whose scripts the fee pays for
    [(TxIn, TxOut ConwayEra)] ->
    -- | what the transaction spends
    [(TxIn, TxOut ConwayEra)] ->
    -- | what it pays besides the change
    [TxOut ConwayEra] ->
    -- | where the change goes
    Addr ->
    Funding ->
    -- | the transaction without inputs, outputs and fee
    ConwayTx ->
    Either RegistryTransactionError ConwayTx
balanced parameters resolved spent fixed changeAddress funding template = do
    tx <- first feeRefused (balanceFeeLoop parameters outputsFor 1 resolved withInputs)
    let Coin fee = tx ^. bodyTxL . feeTxBodyL
        percentage = fromIntegral (parameters ^. ppCollateralPercentageL)
    when (coinOf (snd (fundingCollateral funding)) * 100 < fee * percentage) $
        Left (NotEnoughFunds "the collateral does not cover the fee")
    let size = fromIntegral (tx ^. sizeTxF) + signatureAllowance
        limit = fromIntegral (parameters ^. ppMaxTxSizeL)
    when (size > limit) $
        Left (TransactionTooLarge size limit)
    pure tx
  where
    withInputs =
        template
            & bodyTxL . inputsTxBodyL .~ Set.fromList (map fst spent)
            & bodyTxL . collateralInputsTxBodyL .~ Set.singleton (fst (fundingCollateral funding))
    minted = template ^. bodyTxL . mintTxBodyL
    Coin donation = template ^. bodyTxL . treasuryDonationTxBodyL
    unspent =
        filterMultiAsset
            (\_ _ quantity -> quantity > 0)
            ( foldMap (assetsOf . snd) spent
                <> minted
                <> mapMaybeMultiAsset (\_ _ quantity -> Just (negate quantity)) (foldMap assetsOf fixed)
            )
    outputsFor (Coin fee)
        | change < 0 = Left insufficient
        | change < unCoin (getMinCoinTxOut parameters changeOut) = Left insufficient
        | otherwise = Right (StrictSeq.fromList (fixed <> [changeOut]))
      where
        change =
            sum (map (coinOf . snd) spent)
                - sum (map coinOf fixed)
                - donation
                - fee
        changeOut = mkBasicTxOut changeAddress (MaryValue (Coin change) unspent)
        insufficient = "the outputs that fund the transaction do not hold its payments, its fee and a change output"

feeRefused :: FeeLoopError -> RegistryTransactionError
feeRefused = \case
    FeeDidNotConverge -> FeeRefused "the fee did not settle"
    OutputError message -> FeeRefused message

-- | The name of the hash-proof token of an inception: the hash of its event and its identifier.
inceptionProofName :: InceptionExport -> ByteString
inceptionProofName export =
    proofTokenName
        (reEventBytes (inceptionEvidence export))
        (cdCesrAid (inceptionDatum export))

-- | The bytes one signature of the payer adds to a transaction, with headroom.
signatureAllowance :: Integer
signatureAllowance = 128
