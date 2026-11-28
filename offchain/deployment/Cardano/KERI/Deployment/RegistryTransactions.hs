{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryTransactions
Description : The transactions that create a registry and register an identity in it

The transactions of the registry's application, as pure builders a command can
call on any network with any funded wallet: publish the state template and the
two reference scripts, create the registry's configuration and state
('createConfiguration'), book a registration ('bookRegistrations'), premint the
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
    FundingRules (..),
    ValidityPlan (..),
    Budgets,
    BuiltTransaction,
    RegistryTransactionError (..),

    -- * What a registration is
    Booking (..),
    registrationRecord,
    registeredFacts,
    ledgerAddressOf,
    approval,
    holdsExactlyApproval,
    requestLovelace,
    deliveredHolding,
    inceptionProofName,

    -- * Transactions
    publishTemplate,
    publishTemplateAndSeed,
    publishReferenceScript,
    endOnly,
    createConfiguration,
    balanced,
    Funding (..),
    BookedRequest (..),
    bookRegistrations,
    burnAttestations,
    returnRequestsBurning,
    mintHashProof,
    FoldPlan (..),
    foldRegistration,
    returnRequests,
    AttestedReferences (..),
    CheckpointMove (..),
    advanceAttested,
    freezeAttested,
    premiumOutputMinimum,

    -- * The names a deployment fixes
    applicationPolicyId,
    attestationPolicyId,
    attestationName,
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
    isFundable,
    isPlainFunding,
    plutusAddressOf,
    scriptExUnits,
    hashProofBurnExUnits,
    hashProofBurnRedeemer,
) where

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
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
import Cardano.KERI.AID.Checkpoint.AdvanceAttestation (
    advanceAttestationName,
    advanceEnvelopeData,
    changeIssueData,
    datumFrozen,
    factIssueData,
    signedFactForAdvance,
    signedFactForFreeze,
    signedFactName,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyStateView (..),
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Deposit (BondOption (..))
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceAttestedSpendRedeemerData,
    asPlcData,
    bookingAttestationBurnData,
    bookingAttestationIssueData,
    bookingAttestationName,
    freezeAttestedSpendRedeemerData,
 )
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum, rawInlineData)
import Cardano.KERI.AID.E2E.FoldGuard (FoldRefusal (..), foldRefusal)
import Cardano.KERI.AID.E2E.MpfProof (prove)
import Cardano.KERI.AID.E2E.MpfTrie qualified as Trie
import Cardano.KERI.Deployment.AdvanceAttestationScripts (AdvanceAttestation (..))
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
 )
import Cardano.KERI.Deployment.Script (
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    computeScriptHash,
    mkCageScript,
    scriptHashBytes,
 )
import Cardano.Ledger.Address (
    Addr (..),
    serialiseAddr,
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxBody (scriptIntegrityHashTxBodyL)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..), TxDats (..))
import Cardano.Ledger.Api.Scripts.Data qualified as Ledger
import Cardano.Ledger.Api.Tx (bodyTxL, mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    treasuryDonationTxBodyL,
    vldtTxBodyL,
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
    Network (Testnet),
    StrictMaybe (SJust, SNothing),
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
    BalanceError (..),
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
    spendingIndex,
 )
import Control.Applicative ((<|>))
import Control.Monad (forM_, unless, when)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Short qualified as SBS
import Data.Either (lefts, rights)
import Data.Foldable (toList)
import Data.List (elemIndex, sortOn, tails)
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
    , deploymentPolicies :: !(Maybe AdvanceAttestation)
    -- ^ the two policies of the attested generation, whose checkpoint requires their change attestation; absent in the deployed generation
    }

-- | The outputs a registry's transactions read by reference, once its genesis has settled.
data RegistryReferences = RegistryReferences
    { referenceApplication :: !(TxIn, TxOut ConwayEra)
    -- ^ the application script, published
    , referenceState :: !(TxIn, TxOut ConwayEra)
    -- ^ the state script, published
    , referenceConfiguration :: !(TxIn, TxOut ConwayEra)
    -- ^ the registry's configuration record
    , referenceAttestation :: !(TxIn, TxOut ConwayEra)
    -- ^ the booking attestation policy, published
    , referenceHashProof :: !(TxIn, TxOut ConwayEra)
    -- ^ the hash-proof policy, published
    }

{- | How the outputs that seed, fund and collateralise a transaction are chosen. The two functions are Singular's own
('adaOnlyOut' and 'selectFunding' of its publication builder), handed in by the caller that already depends on Singular:
this library takes no edge to Singular's package, which the write composition may not reach.
-}
data FundingRules = FundingRules
    { ruleAdaOnly :: TxOut ConwayEra -> Bool
    -- ^ whether an output holds lovelace alone and no reference script
    , ruleSelect :: Maybe TxIn -> [(TxIn, TxOut ConwayEra)] -> Either String (TxIn, TxOut ConwayEra)
    -- ^ the output a transaction is funded and collateralised from: the one chosen, or the largest of lovelace alone
    }

-- | Who pays a transaction: the address that receives the change, the outputs that fund it and how they are chosen.
data Payer = Payer
    { payerAddress :: !Addr
    , payerFunds :: ![(TxIn, TxOut ConwayEra)]
    , payerRules :: !FundingRules
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
    | -- | a booking of no request
      NothingToBook
    | -- | the output given as the hash proof of a request does not hold the one token the request's inception names
      ProofIsNotTheInceptions !TxIn
    | -- | two requests of one transaction name the exact same output as their hash proof: one output is spent once
      ProofOutputReused !TxIn
    | -- | a burn of no attestation
      NothingToBurn
    | -- | the deployment is of the deployed generation: it has no policies to mint the attestation of a checkpoint move
      NotAnAttestedDeployment
    | -- | the move cannot be built from what it was given: the spent output holds no live checkpoint datum, the successor is none, or the evidence does not carry the fact
      CheckpointMoveRefused !String
    deriving stock (Eq, Show)

{- | One request a booking transaction books: the record it commits, the inception it is booked for and the output of the
earlier premint that holds the hash proof of that inception.
-}
data BookedRequest = BookedRequest
    { bookedRecord :: !RegistrationData
    , bookedInception :: !InceptionExport
    , bookedProof :: !(TxIn, TxOut ConwayEra)
    }

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

-- | The policy of the booking attestation the application is applied to.
attestationPolicyId :: RegistryDeployment -> PolicyID
attestationPolicyId = PolicyID . artifactScriptHash . scriptsAttestation . deploymentScripts

-- | The name of the attestation of the request booked at the given zero-based output index of a transaction.
attestationName :: RegistryDeployment -> Integer -> RegistrationData -> ByteString
attestationName deployment position record =
    bookingAttestationName
        (scriptHashBytes (applicationHash deployment))
        position
        (requestInitialDatum record)
        (requestDeposit record)

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

-- | Whether an output holds exactly the approval token the booking of a request minted, and nothing else but lovelace.
holdsExactlyApproval :: RegistryDeployment -> RegistrationData -> TxOut ConwayEra -> Bool
holdsExactlyApproval deployment record out = case out ^. valueTxOutL of
    MaryValue _ assets -> assets == tokenValue (applicationPolicyId deployment) (approval record) 1

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

{- | The validity of a transaction that has only an end: from the start of the chain, until the exclusive upper slot,
if it has one.
-}
endOnly :: Maybe SlotNo -> ValidityInterval
endOnly = ValidityInterval SNothing . maybe SNothing SJust

{- | Publish the template of the state script: an output holding the given
lovelace whose inline datum is the template bytes, referenced by the genesis.
-}
publishTemplate ::
    -- | the exclusive upper slot of the transaction
    Maybe SlotNo ->
    PParams ConwayEra ->
    Payer ->
    -- | the lovelace of the published output
    Coin ->
    ByteString ->
    Either RegistryTransactionError ConwayTx
publishTemplate end parameters payer lovelace template =
    publishOutput
        end
        parameters
        payer
        ( mkBasicTxOut (payerAddress payer) (inject lovelace)
            & datumTxOutL .~ mkInlineDatum (B template)
        )

-- | Publish a script as a reference script of an output holding the given lovelace.
publishReferenceScript ::
    -- | the exclusive upper slot of the transaction
    Maybe SlotNo ->
    PParams ConwayEra ->
    Payer ->
    -- | the lovelace of the published output
    Coin ->
    Script ConwayEra ->
    Either RegistryTransactionError ConwayTx
publishReferenceScript end parameters payer lovelace script =
    publishOutput
        end
        parameters
        payer
        ( mkBasicTxOut (payerAddress payer) (inject lovelace)
            & referenceScriptTxOutL .~ SJust script
        )

publishOutput ::
    Maybe SlotNo ->
    PParams ConwayEra ->
    Payer ->
    TxOut ConwayEra ->
    Either RegistryTransactionError ConwayTx
publishOutput end parameters payer output = publishOutputs end parameters payer [output]

{- | The publication of the template that also creates the output the registry will be created
from, for a wallet that holds one output of lovelace alone: it is the output after the
template's, so the wallet keeps the change to pay for the rest, as public Singular's chained
seed does. The seed holds the given lovelace.
-}
publishTemplateAndSeed ::
    -- | the exclusive upper slot of the transaction
    Maybe SlotNo ->
    PParams ConwayEra ->
    Payer ->
    -- | the lovelace of the published output
    Coin ->
    -- | the lovelace of the seed
    Coin ->
    ByteString ->
    Either RegistryTransactionError ConwayTx
publishTemplateAndSeed end parameters payer lovelace seedLovelace template =
    publishOutputs
        end
        parameters
        payer
        [ mkBasicTxOut (payerAddress payer) (inject lovelace)
            & datumTxOutL .~ mkInlineDatum (B template)
        , mkBasicTxOut (payerAddress payer) (inject seedLovelace)
        ]

publishOutputs ::
    Maybe SlotNo ->
    PParams ConwayEra ->
    Payer ->
    [TxOut ConwayEra] ->
    Either RegistryTransactionError ConwayTx
publishOutputs end parameters payer outputs =
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
            ( mkBasicTxBody
                & outputsTxBodyL .~ StrictSeq.fromList outputs
                & vldtTxBodyL .~ endOnly end
            )

{- | The genesis of the registry: spend the seed, mint the state token into an
empty state and the configuration token into the configuration record, with the
template and the two scripts by reference. The seed is the output the
registry's identity is derived from: any other is refused. The payer's outputs
fund what the seed does not cover and one of them is the collateral.
-}
createConfiguration ::
    -- | the exclusive upper slot of the transaction
    Maybe SlotNo ->
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
createConfiguration end parameters deployment references payer seedUtxo configured budgets = do
    when (outputReferenceOf (fst seedUtxo) /= seedOf deployment) $
        Left SeedIsNotTheRegistrys
    firstFunded budgets (fundings (payerRules payer) [fst seedUtxo] (payerFunds payer)) attempt
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
                        & vldtTxBodyL .~ endOnly end
                        & referenceInputsTxBodyL .~ Set.fromList (map fst references)
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)

{- | The booking transaction of requests over a validity interval: it spends and burns the
hash proof each request's earlier premint left, mints each approval and the attestation
of each request (named for the real position of its output), and returns the attestations
in the ordinary change. Each request holds the lovelace the registry requires, moved by
the given difference: zero is the booking the application accepts.
-}
bookRegistrations ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    Payer ->
    [BookedRequest] ->
    ValidityPlan ->
    -- | the lovelace each request holds beyond 'requestLovelace'
    Integer ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
bookRegistrations parameters deployment references payer requests validity difference budgets = do
    when (null requests) $ Left NothingToBook
    case [ref | (ref : later) <- tails (map (fst . bookedProof) requests), ref `elem` later] of
        reused : _ -> Left (ProofOutputReused reused)
        [] -> pure ()
    forM_ requests $ \request ->
        unless (holdsProof request) $
            Left (ProofIsNotTheInceptions (fst (bookedProof request)))
    firstFunded budgets (fundings (payerRules payer) (map (fst . bookedProof) requests) (payerFunds payer)) attempt
  where
    indexed = zip [0 ..] requests
    hashProofPolicy = PolicyID (artifactScriptHash (hashProofArtifact deployment))
    holdsProof request =
        assetsOf (snd (bookedProof request))
            == tokenValue hashProofPolicy (inceptionProofName (bookedInception request)) 1
                <> remainder (bookedProof request)
    -- what else the proof output holds is not the booking's concern
    remainder (_, out) =
        filterMultiAsset (\policy _ _ -> policy /= hashProofPolicy) (assetsOf out)
    minted =
        foldMap
            ( \(position, BookedRequest{bookedRecord = record, bookedInception = export}) ->
                tokenValue (applicationPolicyId deployment) (approval record) 1
                    <> tokenValue (attestationPolicyId deployment) (attestationName deployment position record) 1
                    <> tokenValue hashProofPolicy (inceptionProofName export) (-1)
            )
            indexed
    requestOut BookedRequest{bookedRecord = record} =
        mkBasicTxOut
            (applicationAddress deployment)
            ( MaryValue
                (Coin (requestLovelace (parametersOf deployment) record + difference))
                (tokenValue (applicationPolicyId deployment) (approval record) 1)
            )
            & datumTxOutL .~ mkInlineDatum (heldDatumData (Registration record))
    resolved =
        [ referenceConfiguration references
        , referenceApplication references
        , referenceAttestation references
        , referenceHashProof references
        ]
    attempt chosen funding = do
        let mintIx policy = fromIntegral (mintingIndex policy minted)
            purposes =
                [
                    ( ConwayMinting (AsIx (mintIx (applicationPolicyId deployment)))
                    , List [actionData (BookRegistration position) | (position, _) <- indexed]
                    , scriptExUnits
                    )
                ,
                    ( ConwayMinting (AsIx (mintIx (attestationPolicyId deployment)))
                    , bookingAttestationIssueData
                        (scriptHashBytes (applicationHash deployment))
                        [ (position, inceptionEvidence (bookedInception request))
                        | (position, request) <- indexed
                        ]
                    , scriptExUnits
                    )
                ,
                    ( ConwayMinting (AsIx (mintIx hashProofPolicy))
                    , hashProofBurnRedeemer
                    , hashProofBurnExUnits
                    )
                ]
            redeemers = redeemerMap chosen purposes
        built <-
            balanced
                parameters
                resolved
                (map bookedProof requests <> fundingInputs funding)
                (map requestOut requests)
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

{- | The burn of attestations the payer holds: nothing is minted, no evidence is shown and
the attestation policy's Burn redeemer is the only redeemer.
-}
burnAttestations ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    Payer ->
    -- | the outputs that hold the attestations to burn
    [(TxIn, TxOut ConwayEra)] ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
burnAttestations parameters deployment references payer held budgets = do
    when (Map.null burning) $ Left NothingToBurn
    firstFunded budgets (fundings (payerRules payer) (map fst held) (payerFunds payer)) attempt
  where
    policy = attestationPolicyId deployment
    burning = attestationsHeld deployment held
    minted =
        MultiAsset . Map.singleton policy $
            Map.map negate burning
    resolved = [referenceAttestation references]
    purposes = [(ConwayMinting (AsIx 0), bookingAttestationBurnData, scriptExUnits)]
    attempt chosen funding = do
        let redeemers = redeemerMap chosen purposes
        built <-
            balanced
                parameters
                resolved
                (held <> fundingInputs funding)
                []
                (payerAddress payer)
                funding
                ( mkBasicTx
                    ( mkBasicTxBody
                        & mintTxBodyL .~ minted
                        & referenceInputsTxBodyL .~ Set.fromList (map fst resolved)
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)

{- | The hash-proof mint of an inception, paid to a party: the evidence the fold
burns, valid over the given interval. The inception must hash to its own identifier
at the offsets it carries.
-}
mintHashProof ::
    PParams ConwayEra ->
    RegistryDeployment ->
    Payer ->
    InceptionExport ->
    ValidityPlan ->
    Either RegistryTransactionError ConwayTx
mintHashProof parameters deployment payer export validity = do
    if blake3Hash saidBlank == aid
        then Right ()
        else Left InceptionDoesNotBindItsIdentifier
    firstFunded Map.empty (fundings (payerRules payer) [] (payerFunds payer)) (const attempt)
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
                            & vldtTxBodyL .~ validityOf validity
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

{- | The fold of a booked request into the registry by a party: the state script inserts
the key, the application burns the approval and the holding is delivered to the
checkpoint address with the committed datum and exactly the committed deposit. The
fold shows no evidence, spends no hash proof and withdraws nothing: the booking
has already attested the inception.
-}
data FoldPlan = FoldPlan
    { foldRequest :: !(TxIn, TxOut ConwayEra)
    -- ^ the booked request the fold spends
    , foldBooked :: !RegistrationData
    -- ^ the record the request holds
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
    firstFunded budgets (fundings (payerRules (foldPayer plan)) [] (payerFunds (foldPayer plan))) attempt
  where
    (requestIn, _) = foldRequest plan
    record = foldBooked plan
    (stateIn, stateOutBefore) = foldState plan
    key = requestKey record
    active = activeTokenName (registryOf deployment) key
    minted =
        tokenValue (applicationPolicyId deployment) (approval record) (-1)
            <> tokenValue (statePolicyId deployment) active 1
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

    attempt chosen funding = do
        let spent =
                [foldRequest plan, foldState plan]
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
returnRequests parameters deployment references payer booking validity refundTo =
    returnRequestsBurning parameters deployment references payer booking validity refundTo []

{- | The return of a booked request, composed with the controller's burn of the attestations
the payer holds: the return as it is, and the attestation policy's Burn redeemer beside the
application's, each at its own place among the minting purposes. With nothing held the
return is 'returnRequests'; held outputs that carry no attestation are no burn.
-}
returnRequestsBurning ::
    PParams ConwayEra ->
    RegistryDeployment ->
    RegistryReferences ->
    Payer ->
    Booking ->
    ValidityPlan ->
    -- | where the refund goes
    Addr ->
    -- | the outputs that hold the attestations to burn
    [(TxIn, TxOut ConwayEra)] ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
returnRequestsBurning parameters deployment references payer booking validity refundTo held budgets = do
    when (not (null held) && Map.null burning) $ Left NothingToBurn
    firstFunded budgets (fundings (payerRules payer) (map fst held) (payerFunds payer)) attempt
  where
    Booking{bookingOutput = (requestIn, requestOut), bookingRecord = record} = booking
    tip = minimumTip (parametersOf deployment)
    burning = attestationsHeld deployment held
    minted =
        tokenValue (applicationPolicyId deployment) (approval record) (-1)
            <> if Map.null burning then mempty else MultiAsset (Map.singleton (attestationPolicyId deployment) (Map.map negate burning))
    mintPurpose policy = ConwayMinting (AsIx (mintingIndex policy minted))
    refundOut = mkBasicTxOut refundTo (inject (Coin (unCoin (requestOut ^. coinTxOutL) - tip)))
    resolved =
        [referenceConfiguration references, referenceApplication references]
            <> [referenceAttestation references | not (null held)]
    attempt chosen funding = do
        let spent = bookingOutput booking : held <> fundingInputs funding
            inputs = Set.fromList (map fst spent)
            purposes =
                [
                    ( ConwaySpending (AsIx (spendingIndex requestIn inputs))
                    , spendActionData ReturnRegistration
                    , scriptExUnits
                    )
                , (mintPurpose (applicationPolicyId deployment), List [], scriptExUnits)
                ]
                    <> [(mintPurpose (attestationPolicyId deployment), bookingAttestationBurnData, scriptExUnits) | not (null held)]
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
-- The checkpoint's moves of the attested generation
-- ---------------------------------------------------------------------

-- | The published scripts a move of the attested generation reads by reference.
data AttestedReferences = AttestedReferences
    { attestedCheckpointScript :: !(TxIn, TxOut ConwayEra)
    -- ^ the checkpoint validator, published
    , attestedFactScript :: !(TxIn, TxOut ConwayEra)
    -- ^ the fact policy, published
    , attestedChangeScript :: !(TxIn, TxOut ConwayEra)
    -- ^ the change policy, published
    }

-- | What a move of a checkpoint is given besides the payer: the output it spends, its successor and its evidence.
data CheckpointMove = CheckpointMove
    { moveSpent :: !(TxIn, TxOut ConwayEra)
    -- ^ the checkpoint output spent, its datum inline
    , moveSuccessor :: !PLC.Data
    -- ^ the datum the successor carries: the rotated state of an advance, the spent datum frozen for a freeze
    , movePayload :: !PLC.Data
    -- ^ the evidence: an @AdvanceEvidence@ for an advance, a @FreezeEvidence@ for a freeze
    , movePayee :: !Addr
    -- ^ who receives what leaves the checkpoint: the premium of an advance, the bond of a freeze
    }

{- | An advance of a checkpoint of the attested generation, a rotation or a depositing rotation: the
checkpoint spent with the successor at the first output and the premium, when the pool covers it, at the
second; the change attestation of the claim and the fact attestation of the signed fact minted, each under its
own policy by reference, with no withdrawal and no certificate.
-}
advanceAttested ::
    PParams ConwayEra ->
    RegistryDeployment ->
    AttestedReferences ->
    Payer ->
    CheckpointMove ->
    BondOption ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
advanceAttested parameters deployment references payer move bond =
    checkpointMove parameters deployment references payer move (Left bond)

{- | A freeze of a checkpoint of the attested generation: the same, with the bond to the hunter at the second
output and the frozen successor at the first.
-}
freezeAttested ::
    PParams ConwayEra ->
    RegistryDeployment ->
    AttestedReferences ->
    Payer ->
    CheckpointMove ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
freezeAttested parameters deployment references payer move =
    checkpointMove parameters deployment references payer move (Right ())

checkpointMove ::
    PParams ConwayEra ->
    RegistryDeployment ->
    AttestedReferences ->
    Payer ->
    CheckpointMove ->
    Either BondOption () ->
    Budgets ->
    Either RegistryTransactionError BuiltTransaction
checkpointMove parameters deployment references payer move kind budgets = do
    policies <- maybe (Left NotAnAttestedDeployment) Right (deploymentPolicies deployment)
    spentDatum <- maybe (Left (CheckpointMoveRefused "the spent output holds no inline datum")) Right (rawInlineData spentOut)
    frozenBefore <- maybe (Left (CheckpointMoveRefused "the spent output holds no live checkpoint datum")) Right (datumFrozen spentDatum)
    frozenAfter <- maybe (Left (CheckpointMoveRefused "the successor is no live checkpoint datum")) Right (datumFrozen (moveSuccessor move))
    fact <-
        maybe
            (Left (CheckpointMoveRefused "the evidence does not carry the signed fact of the move"))
            Right
            ( case kind of
                Left _ -> signedFactForAdvance spentDatum (moveSuccessor move) (movePayload move)
                Right () -> signedFactForFreeze spentDatum (movePayload move)
            )
    factName <- maybe (Left (CheckpointMoveRefused "the signed fact does not have the shape of the fact policy's record")) Right (signedFactName fact)
    let floorOf frozen = registryMinimumAda terms + termsDeposit checkpointTerms + (if frozen then 0 else termsFreezeBond checkpointTerms)
        pool = coinOf spentOut - floorOf frozenBefore
        premium = termsPremium checkpointTerms
        (payeeAmount, successorLovelace) = case kind of
            Left _
                | pool >= premium -> (Just premium, floorOf frozenAfter + pool - premium)
                | otherwise -> (Nothing, floorOf frozenAfter + pool)
            Right () -> (Just (termsFreezeBond checkpointTerms), floorOf frozenAfter + pool)
        action = either (const 1) (const 2) kind
        checkpointPolicy = scriptHashBytes (artifactScriptHash (scriptsCheckpoint (deploymentScripts deployment)))
        change = advanceAttestationName action checkpointPolicy spentReference 0
        envelope = advanceEnvelopeData action checkpointPolicy spentReference (movePayload move)
        changePolicy = PolicyID (artifactScriptHash (attestationChange policies))
        factPolicy = PolicyID (artifactScriptHash (attestationFact policies))
        minted = tokenValue changePolicy change 1 <> tokenValue factPolicy factName 1
        successorOut =
            mkBasicTxOut (checkpointAddress deployment) (MaryValue (Coin successorLovelace) (assetsOf spentOut))
                & datumTxOutL .~ mkInlineDatum (moveSuccessor move)
        -- the recipient is paid exactly what the checkpoint is debited, the premium or the freeze bond: nothing of it
        -- comes from the payer
        payeeOuts = [mkBasicTxOut (movePayee move) (inject (Coin amount)) | Just amount <- [payeeAmount]]
        resolved = [attestedCheckpointScript references, attestedFactScript references, attestedChangeScript references]
        spendRedeemer = case kind of
            Left bond -> advanceAttestedSpendRedeemerData 1 bond 0
            Right () -> freezeAttestedSpendRedeemerData 1 0
    unless (successorLovelace >= 0 && pool >= 0) $
        Left (CheckpointMoveRefused "the spent output holds less than the checkpoint's floor")
    -- a payment the ledger would refuse is no payment: it is never made up from the payer's funds
    forM_ payeeAmount $ \amount ->
        let least = outputMinimum parameters (movePayee move)
         in when (amount < least) $
                Left
                    ( CheckpointMoveRefused
                        ( "the payment of "
                            <> show amount
                            <> " lovelace is below the "
                            <> show least
                            <> " lovelace the ledger asks of the output that pays it"
                        )
                    )
    firstFunded budgets (fundings (payerRules payer) [spentIn] (payerFunds payer)) $ \chosen funding -> do
        let spent = moveSpent move : fundingInputs funding
            inputs = Set.fromList (map fst spent)
            mintIx policy = fromIntegral (mintingIndex policy minted)
            purposes =
                [ (ConwaySpending (AsIx (spendingIndex spentIn inputs)), spendRedeemer, scriptExUnits)
                , (ConwayMinting (AsIx (mintIx changePolicy)), changeIssueData [(envelope, 0)], scriptExUnits)
                , (ConwayMinting (AsIx (mintIx factPolicy)), factIssueData [fact], scriptExUnits)
                ]
            redeemers = redeemerMap chosen purposes
        built <-
            balanced
                parameters
                resolved
                spent
                (successorOut : payeeOuts)
                (payerAddress payer)
                funding
                ( mkBasicTx
                    ( mkBasicTxBody
                        & mintTxBodyL .~ minted
                        & referenceInputsTxBodyL .~ Set.fromList (map fst resolved)
                        & scriptIntegrityHashTxBodyL
                            .~ computeScriptIntegrity (Set.singleton PlutusV3) parameters redeemers (TxDats mempty)
                    )
                    & witsTxL . rdmrsTxWitsL .~ redeemers
                )
        pure (built, purposeSet purposes)
  where
    (spentIn, spentOut) = moveSpent move
    terms = deploymentTerms deployment
    checkpointTerms = registryCheckpointTerms terms
    spentReference = let OutputReference txid index = outputReferenceOf spentIn in (txid, index)

{- | The least lovelace a premium of the registry can be: the ledger's minimum for the output that pays it, as large
as an address of a payee can make it (a base address of two script credentials, holding lovelace alone), and never
less than one lovelace, since a premium of nothing pays nothing also where the ledger asks nothing of an output. A
deployment whose premium is below it cannot pay a premium output from the premium alone, and is refused.
-}
premiumOutputMinimum :: PParams ConwayEra -> Integer
premiumOutputMinimum parameters = max 1 (outputMinimum parameters largestPayee)
  where
    largestPayee = Addr Testnet (ScriptHashObj payeeScript) (StakeRefBase (ScriptHashObj payeeScript))
    payeeScript = ScriptHash (fromMaybe (error "28 bytes form a script hash") (hashFromBytes (BS.replicate 28 0)))

{- | The lovelace the ledger asks of an output at an address that holds lovelace alone, found again for the size the
minimum itself makes the output.
-}
outputMinimum :: PParams ConwayEra -> Addr -> Integer
outputMinimum parameters address = settle (settle (settle 0))
  where
    settle coin = max coin (unCoin (getMinCoinTxOut parameters (mkBasicTxOut address (inject (Coin coin)) :: TxOut ConwayEra)))

-- | The attestations the outputs hold, by name: what a burn of them burns.
attestationsHeld :: RegistryDeployment -> [(TxIn, TxOut ConwayEra)] -> Map.Map AssetName Integer
attestationsHeld deployment held =
    Map.unionsWith
        (+)
        [ names
        | (_, out) <- held
        , let MultiAsset assets = assetsOf out
        , Just names <- [Map.lookup (attestationPolicyId deployment) assets]
        ]

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

{- | The ledger address a request's refund address stands for on a network, when it is one: a
payment credential and an optional stake credential, each a hash of the length a ledger credential has.
-}
ledgerAddressOf :: Network -> PlutusAddress -> Maybe Addr
ledgerAddressOf network (PlutusAddress payment stake) =
    Addr network <$> credentialOf payment <*> stakeOf stake
  where
    credentialOf = \case
        KeyCredential hash -> KeyHashObj . KeyHash <$> hashFromBytes hash
        ScriptCredential hash -> ScriptHashObj . ScriptHash <$> hashFromBytes hash
    stakeOf = \case
        Nothing -> Just StakeRefNull
        Just credential -> StakeRefBase <$> credentialOf credential

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

{- | Whether an output may fund a transaction or be its collateral: it carries no
reference script and no datum. A wallet that has deployed before holds its
reference outputs at its own address, and spending one destroys it.
-}
isFundable :: TxOut ConwayEra -> Bool
isFundable out =
    out ^. referenceScriptTxOutL == SNothing
        && out ^. datumTxOutL == Ledger.NoDatum

{- | Whether an output may be the seed, the funding or the collateral: Singular's 'adaOnlyOut', which tests native assets and a
reference script, and no datum, which Singular does not test and a published template carries.
-}
isPlainFunding :: FundingRules -> TxOut ConwayEra -> Bool
isPlainFunding rules out = ruleAdaOnly rules out && out ^. datumTxOutL == Ledger.NoDatum

hasAssets :: TxOut ConwayEra -> Bool
hasAssets = (/= mempty) . assetsOf

{- | The outputs that fund a transaction: the ones that pay its fee and the change, one of
which is its collateral, as in public Singular: a transaction is funded and collateralised from
the same ada-only output of the wallet.
-}
data Funding = Funding
    { fundingInputs :: ![(TxIn, TxOut ConwayEra)]
    , fundingCollateral :: !(TxIn, TxOut ConwayEra)
    }

{- | The outputs of a payer in the order they are spent: those without native
assets first, each group largest first.
-}
spendOrder :: [(TxIn, TxOut ConwayEra)] -> [(TxIn, TxOut ConwayEra)]
spendOrder = sortOn (\(_, out) -> (hasAssets out, Down (coinOf out))) . filter (isFundable . snd)

-- | The first outputs of the spending order, as many as the given count and every more.
spendingSets :: Int -> [(TxIn, TxOut ConwayEra)] -> [[(TxIn, TxOut ConwayEra)]]
spendingSets least funds =
    [take count ordered | count <- [least .. length ordered]]
  where
    ordered = spendOrder funds

{- | What a payer's outputs can fund, best first: the outputs of the spending order, one more at a
time and without a limit on their number, the first of them alone when it covers the transaction.
The collateral is the one of them that Singular's 'selectFunding' chooses: the largest output of
lovelace alone among those spent, so that one output of lovelace alone is the whole wallet
needed. The outputs excluded are spent by the transaction already.
-}
fundings :: FundingRules -> [TxIn] -> [(TxIn, TxOut ConwayEra)] -> [Funding]
fundings rules excluded funds =
    [ Funding inputs collateral
    | inputs <- spendingSets 1 (filter ((`notElem` excluded) . fst) funds)
    , Right collateral <- [ruleSelect rules Nothing (filter (isPlainFunding rules . snd) inputs)]
    ]

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
    result <-
        first balanceRefused $
            balanceTxWith parameters spent (CollateralUtxos []) resolved changeAddress Nothing withOutputs
    let tx = balancedTx result
    case reverse (toList (tx ^. bodyTxL . outputsTxBodyL)) of
        change : _
            | change ^. coinTxOutL < getMinCoinTxOut parameters change -> Left (FeeRefused insufficient)
        _ -> pure ()
    let size = fromIntegral (tx ^. sizeTxF) + signatureAllowance
        limit = fromIntegral (parameters ^. ppMaxTxSizeL)
    when (size > limit) $
        Left (TransactionTooLarge size limit)
    pure tx
  where
    -- the public builder takes the inputs, adds the change, prices the fee with the reference scripts resolved, takes
    -- the donation out of the change and, at the fee it ends with, declares the total collateral and returns the rest
    -- of the collateral input to the payer
    withOutputs =
        template
            & bodyTxL . outputsTxBodyL .~ StrictSeq.fromList (fixed <> tokenOutputs)
            & bodyTxL . collateralInputsTxBodyL .~ Set.singleton (fst (fundingCollateral funding))
    -- what the transaction leaves of the tokens its inputs hold and it mints: an output of its own, so that the change holds
    -- lovelace alone, as the change of public Singular's builders does and the payer's next transaction needs
    leftover =
        filterMultiAsset
            (\_ _ quantity -> quantity > 0)
            ( foldMap (assetsOf . snd) spent
                <> (template ^. bodyTxL . mintTxBodyL)
                <> mapMaybeMultiAsset (\_ _ quantity -> Just (negate quantity)) (foldMap assetsOf fixed)
            )
    tokenOutputs
        | leftover == mempty = []
        | otherwise = [carrying]
    carrying =
        let probe = mkBasicTxOut changeAddress (MaryValue (Coin 0) leftover)
            atFirst = getMinCoinTxOut parameters probe
            atSecond = getMinCoinTxOut parameters (probe & coinTxOutL .~ atFirst)
         in probe & coinTxOutL .~ max atFirst atSecond
    insufficient = "the outputs that fund the transaction do not hold its payments, its fee and a change output"
    balanceRefused = \case
        InsufficientFee{} -> FeeRefused insufficient
        FeeNotConverged -> FeeRefused "the fee did not settle"
        CollateralShortfall{} -> NotEnoughFunds "the collateral does not cover the fee"

-- | The name of the hash-proof token of an inception: the hash of its event and its identifier.
inceptionProofName :: InceptionExport -> ByteString
inceptionProofName export =
    proofTokenName
        (reEventBytes (inceptionEvidence export))
        (cdCesrAid (inceptionDatum export))

-- | The bytes one signature of the payer adds to a transaction, with headroom.
signatureAllowance :: Integer
signatureAllowance = 128
