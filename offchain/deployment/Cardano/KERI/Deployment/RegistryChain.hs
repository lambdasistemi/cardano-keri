{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryChain
Description : What booking and folding read of the chain, and how they refuse

A registry is deployed by @ckeri registry deploy@, a registration is booked by
@ckeri registry register@ and later folded by @ckeri registry fold@. All three
reach the chain only through a 'RegistryRuntime': the outputs at an address, the
outputs under some references, whether a reward credential is registered, the
tip and the time of a slot, and the means to evaluate, sign, submit and observe
a transaction. Nothing here opens a follower store or a manifest of the first
deployment.

Every refusal says where it was made: by the command before any transaction, by
the node's evaluation of a transaction, or by the ledger.
-}
module Cardano.KERI.Deployment.RegistryChain (
    -- * The chain
    RegistryRuntime (..),
    TransactionUnconfirmed (..),
    ValidityEnd (..),

    -- * The registry
    Loaded (..),
    deriveDeployment,
    loadDeployment,
    findStateOutput,
    termsOfIdentity,
    feeOf,
    exportKey,
    txInOfReference,

    -- * Time
    Observation (..),
    bookingWindow,
    foldWindow,
    returnWindow,

    -- * Refusals
    Boundary (..),
    renderBoundary,
    Refusal (..),
    SubmitError (..),
    submitBoundary,
    Attempt (..),
    AttemptStatus (..),
    failureOfAttempt,

    -- * Reading the node
    tryNode,
    NodeConnectionEnded (..),
    whileConnected,

    -- * Transactions
    transactBudgeted,
    transactPlain,
    transactBuilt,

    -- * Measured budgets
    withMargin,
    addUnits,
    withinUnits,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (OutputReference (..), stateTokenName)
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..), liveOfKeyState)
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.RefusalAt (renderEvaluationFailure)
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord (..), ScriptReference (..))
import Cardano.KERI.Deployment.RegistryTransactions (
    Budgets,
    BuiltTransaction,
    Payer (..),
    RegistryDeployment (..),
    RegistryReferences (..),
    RegistryTransactionError,
    ValidityPlan (..),
    stateAddress,
    statePolicyId,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint,
    CheckpointTerms (..),
    ScriptArtifact (..),
    scriptHashBytes,
 )
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), transactionId)
import Cardano.Ledger.Address (AccountAddress, Addr)
import Cardano.Ledger.Alonzo.PParams (ppMaxTxExUnitsL)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (Network (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (SlotNo (..))
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Control.Concurrent.Async (race)
import Control.Exception (Exception, SomeAsyncException, SomeException, fromException, throwIO, try)
import Control.Monad (forM_, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.Functor ((<&>))
import Data.List (find)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Conc (STM, atomically, retry)
import Lens.Micro ((^.))

{- | A transaction handed over that was not seen to settle before its deadline: its identifier and what the
observation said. It says nothing of whether the transaction is on the chain: it may still be included.
-}
data TransactionUnconfirmed = TransactionUnconfirmed !TxId !Text

instance Show TransactionUnconfirmed where
    show (TransactionUnconfirmed _ said) = T.unpack said

instance Exception TransactionUnconfirmed

-- | How booking and folding reach the chain.
data RegistryRuntime = RegistryRuntime
    { rtNetwork :: !Network
    , rtUtxosAt :: Addr -> IO [(TxIn, TxOut ConwayEra)]
    -- ^ the outputs the node holds at an address now
    , rtOutputs :: Set TxIn -> IO (Map TxIn (TxOut ConwayEra))
    -- ^ the outputs the node holds unspent under these references
    , rtRewardRegistered :: AccountAddress -> IO Bool
    -- ^ whether the node holds this reward account registered
    , rtTransactions :: !(TransactionRuntime IO)
    , rtObserve :: IO Observation
    -- ^ the tip, the clock and the forecast horizon, each read once, for one decision
    , rtNowMs :: IO Integer
    -- ^ the machine's clock now, in POSIX milliseconds (time left, as a transaction is about to leave)
    , rtValidityEnd :: IO ValidityEnd
    -- ^ the upper slot a transaction built now carries, read once for each build
    }

{- | The validity end of a transaction about to be built.

@EndNotSet@: the runtime asks for none (the node settles by what it observes). @EndAt@: the finite, exclusive
upper slot. @NoUsableWindow@: the interval from the tip is too short, so nothing is built.
-}
data ValidityEnd = EndNotSet | EndAt !SlotNo | NoUsableWindow
    deriving stock (Eq, Show)

-- | A registry the files name, with what its transactions read by reference.
data Loaded = Loaded
    { loadedDeployment :: !RegistryDeployment
    , loadedReferences :: !RegistryReferences
    , loadedFoldReferences :: ![(TxIn, TxOut ConwayEra)]
    -- ^ what a fold reads by reference besides the registry's own scripts: the hash-proof policy
    }

-- | Where a refusal was made.
data Boundary
    = -- | by the command, before any transaction
      Command
    | -- | by the node's evaluation of a transaction, before it is submitted
      NodeEvaluation
    | -- | by the ledger, when the transaction was submitted
      Ledger
    | -- | not a refusal: the transaction may or may not have landed
      Unsettled
    deriving stock (Eq, Show)

renderBoundary :: Boundary -> String
renderBoundary = \case
    Command -> "the command, before any transaction"
    NodeEvaluation -> "the node's evaluation of the transaction"
    Ledger -> "the ledger"
    Unsettled -> "no one: the transaction may or may not have landed"

-- | What the command refuses, by name, before any transaction.
data Refusal
    = DeploymentDisagrees !String
    | ReferenceOutputsMissing ![TxIn]
    | AlreadyRegistered !ByteString
    | BookingWidthBelowSlotLength !Integer !Integer
    | StaleOrUnavailableRegistryState !(Maybe ByteString)
    | RegistryHoldsKey !ByteString
    | -- | the chain establishes that no whole slot is left before the deadline: the deadline
      DeadlineReached !Integer
    | -- | no whole slot fits between now and the deadline: not retryable, and not a deadline that passed
      NoFoldSlotRemains !Integer
    | -- | the node's forecast shows no slot to book in: the clock read
      NoBookingIntervalYet !Integer
    | -- | no validity interval can be formed yet, though the chain does not say the deadline passed: the deadline and the clock read
      NoIntervalYet !Integer !Integer
    | -- | the clock reads the deadline as passed and the chain's tip does not: the clock, the deadline and the instant the tip's slot starts
      TimeEvidenceConflicts !Integer !Integer !Integer
    | -- | neither the chain nor the clock has reached the deadline: the deadline, the instant the tip's slot starts and the clock read
      DeadlineNotReached !Integer !Integer !Integer
    | -- | the deadline is reached and the node's forecast shows no slot after the tip to return in: the instant the tip's slot starts
      NoReturnSlotYet !Integer
    | -- | the request's refund address is not an address of this network
      RequestRefundUnreadable !TxIn
    | RequestUnavailable !TxIn
    | RequestIsNotARegistration !TxIn
    | RequestHasNoApproval !TxIn
    | RequestIsForAnotherRegistry !TxIn
    deriving stock (Eq, Show)

-- | Why a transaction did not land.
data SubmitError
    = BuildRefused !RegistryTransactionError
    | EvaluationFailed !String
    | PurposesDiffer !String
    | BudgetExceeded !String
    | SigningRefused !String
    | -- | the node refused the handoff, with its reason; it is not on chain
      SubmissionRefused !TxId !ByteString
    | -- | signed, and the command knows it was never handed to the node
      NotHandedOver !TxId !String
    | -- | the handoff began and its outcome is unknown: the node may or may not have received it
      HandoffUnconfirmed !TxId !String
    | -- | the node accepted the handoff and the transaction was not seen to settle
      NotObserved !TxId !String
    | -- | the node accepted it and this command saw it settle; the command was cut short after that
      SettledReportInterrupted !ConwayTx !String
    | NodeFailed !String
    deriving stock (Eq, Show)

-- | What the command knows of a transaction it signed, as it happens: its id, and how far it got.
data Attempt = Attempt
    { attemptId :: !TxId
    , attemptStatus :: !AttemptStatus
    }
    deriving stock (Eq, Show)

data AttemptStatus
    = -- | signed, about to be handed to the node: the handoff did not begin
      NotHandedToNode
    | -- | the handoff began, its outcome is unknown: the node may or may not have received it
      HandoffUnknown
    | -- | the node refused it, with its reason
      RefusedByNode !ByteString
    | -- | the node accepted the handoff
      AcceptedByNode
    | {- | the node accepted it and this command saw it settle: the transaction itself, from which its
      receipt (id, outputs, fee) is read
      -}
      SettledOnChain !ConwayTx
    deriving stock (Eq, Show)

{- | A failure that reached the command anywhere after a transaction was signed, said in the terms
of how far that transaction got. Without a signed transaction it is a failed read.
-}
failureOfAttempt :: Maybe Attempt -> String -> SubmitError
failureOfAttempt = \case
    Nothing -> NodeFailed
    Just (Attempt txId status) -> case status of
        NotHandedToNode -> NotHandedOver txId
        HandoffUnknown -> HandoffUnconfirmed txId
        RefusedByNode reason -> const (SubmissionRefused txId reason)
        AcceptedByNode -> NotObserved txId
        SettledOnChain settled -> SettledReportInterrupted settled

submitBoundary :: SubmitError -> Boundary
submitBoundary = \case
    BuildRefused _ -> Command
    SigningRefused _ -> Command
    EvaluationFailed _ -> NodeEvaluation
    PurposesDiffer _ -> NodeEvaluation
    BudgetExceeded _ -> NodeEvaluation
    SubmissionRefused _ _ -> Ledger
    NotHandedOver _ _ -> Unsettled
    HandoffUnconfirmed _ _ -> Unsettled
    NotObserved _ _ -> Unsettled
    SettledReportInterrupted _ _ -> Unsettled
    NodeFailed _ -> Unsettled

-- | The terms the identity carries.
termsOfIdentity :: ReleaseIdentity -> RegistryTerms
termsOfIdentity identity =
    RegistryTerms
        { registryCheckpointTerms =
            CheckpointTerms
                { termsNetwork = riNetwork identity
                , termsDeposit = riDeposit identity
                , termsFreezeBond = riFreezeBond identity
                , termsPremium = riPremium identity
                }
        , registryParameters = riApplicationParameters identity
        , registryMinimumAda = riMinimumAda identity
        , registryTerminationCarrier = riTerminationCarrier identity
        }

deriveDeployment :: Blueprint -> ReleaseIdentity -> Either Refusal RegistryDeployment
deriveDeployment blueprint identity = do
    scripts <-
        first (DeploymentDisagrees . ("the scripts cannot be derived from the identity: " <>)) $
            deriveRegistryScripts stateTemplate terms (riSeed identity) blueprint
    let release = riRelease identity
        application = scriptHashBytes (artifactScriptHash (scriptsApplication scripts))
        disagreements =
            [ name
            | (name, derived, named) <-
                [ ("application-policy", application, rlApplicationPolicy release)
                , ("application-credential", application, rlApplicationCredential release)
                , ("state-program", scriptsStateHash scripts, rlStateProgram release)
                , ("state-policy", scriptsStateHash scripts, rlStatePolicy release)
                , ("checkpoint-validator", scriptHashBytes (artifactScriptHash (scriptsCheckpoint scripts)), riCheckpointValidator identity)
                ]
            , derived /= named
            ]
    unless (null disagreements) $
        Left (DeploymentDisagrees ("the blueprint derives other scripts than the identity names: " <> unwords disagreements))
    pure (RegistryDeployment (if riNetwork identity == 0 then Testnet else Mainnet) terms scripts)
  where
    terms = termsOfIdentity identity

loadDeployment ::
    RegistryRuntime ->
    Blueprint ->
    ReleaseIdentity ->
    ReferenceRecord ->
    IO (Either Refusal Loaded)
loadDeployment rt blueprint identity record =
    case deriveDeployment blueprint identity of
        Left refusal -> pure (Left refusal)
        Right deployment -> do
            let named =
                    [ txInOfReference (scriptOutput (recordApplication record))
                    , txInOfReference (scriptOutput (recordState record))
                    , txInOfReference (recordConfiguration record)
                    , txInOfReference (scriptOutput (recordAttestation record))
                    , txInOfReference (scriptOutput (recordHashProof record))
                    ]
            found <- rtOutputs rt (Set.fromList named)
            let missing = [ref | ref <- named, not (Map.member ref found)]
                pick ref = (,) ref <$> Map.lookup ref found
            pure $ case traverse pick named of
                Just [application, state, configuration, attestation, hashProof]
                    | null missing ->
                        Right
                            Loaded
                                { loadedDeployment = deployment
                                , loadedReferences =
                                    RegistryReferences
                                        { referenceApplication = application
                                        , referenceState = state
                                        , referenceConfiguration = configuration
                                        , referenceAttestation = attestation
                                        , referenceHashProof = hashProof
                                        }
                                , loadedFoldReferences = [hashProof]
                                }
                _ -> Left (ReferenceOutputsMissing missing)

-- | The input an output reference of a record names.
txInOfReference :: OutputReference -> TxIn
txInOfReference (OutputReference transaction index) =
    TxIn
        (TxId (unsafeMakeSafeHash (fromMaybe (error "txInOfReference: not a transaction id") (hashFromBytes transaction))))
        (TxIx (fromInteger index))

findStateOutput :: RegistryRuntime -> RegistryDeployment -> IO (Maybe (TxIn, TxOut ConwayEra))
findStateOutput rt deployment = do
    candidates <- rtUtxosAt rt (stateAddress deployment)
    pure (find (holdsStateToken . snd) candidates)
  where
    policy = statePolicyId deployment
    name = AssetName (SBS.toShort (stateTokenName (scriptsSeed (deploymentScripts deployment))))
    holdsStateToken out = case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) -> (Map.lookup policy assets >>= Map.lookup name) == Just 1

-- ---------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------

{- | What one decision is made from: the tip's slot and when it starts, how long a slot
lasts, one reading of the machine's clock and the last slot the node can convert now. A
decision reads the tip, the clock and the horizon once, here; every instant it needs is
worked out from these.
-}
data Observation = Observation
    { obsTipSlot :: !SlotNo
    , obsTipStartMs :: !Integer
    , obsSlotLengthMs :: !Integer
    , obsClockMs :: !Integer
    , obsHorizonSlot :: !SlotNo
    }
    deriving stock (Eq, Show)

{- | The interval of a booking: from the tip's slot, as many whole slots as fit in the
width and in the node's horizon. Nothing when not one slot does.
-}
bookingWindow :: Observation -> Integer -> Maybe ValidityPlan
bookingWindow obs width
    | slotLength <= 0 || slots < 1 = Nothing
    | otherwise =
        Just
            ValidityPlan
                { lowerSlot = tip
                , upperSlot = tip + fromInteger slots
                , lowerPosixMs = obsTipStartMs obs
                , upperPosixMs = obsTipStartMs obs + slots * slotLength
                }
  where
    tip = obsTipSlot obs
    slotLength = obsSlotLengthMs obs
    slots = min (width `div` slotLength) (toInteger (unSlotNo (obsHorizonSlot obs)) - toInteger (unSlotNo tip))

{- | The interval of a fold, decided from one observation, or the row that refuses it.
The interval is whole slots from the one the clock is in, ending by the deadline
(its upper bound excluded), no wider than the width and inside the horizon. The chain
alone says the deadline is reached (the tip's slot starts at or after it); the clock
alone cannot, and where it reads the deadline as passed and the tip does not, that is a
conflict, named and not decided.
-}
foldWindow :: Observation -> Integer -> Integer -> Either Refusal ValidityPlan
foldWindow obs width deadline
    | tipStart >= deadline = Left (DeadlineReached deadline)
    | clock >= deadline = Left (TimeEvidenceConflicts clock deadline tipStart)
    | slotLength <= 0 || width < slotLength = Left (BookingWidthBelowSlotLength width slotLength)
    | whole < 1 = Left (NoFoldSlotRemains deadline)
    | ahead < 1 = Left (NoIntervalYet deadline clock)
    | otherwise =
        Right
            ValidityPlan
                { lowerSlot = clockSlot
                , upperSlot = clockSlot + fromInteger slots
                , lowerPosixMs = lower
                , upperPosixMs = lower + slots * slotLength
                }
  where
    tip = obsTipSlot obs
    tipStart = obsTipStartMs obs
    clock = obsClockMs obs
    slotLength = obsSlotLengthMs obs
    -- the slot the clock is in, and when it starts
    behind = (clock - tipStart) `div` slotLength
    clockSlot = SlotNo (fromInteger (toInteger (unSlotNo tip) + behind))
    lower = tipStart + behind * slotLength
    -- whole slots from there to the deadline, and to the end of what the node can convert
    whole = (deadline - lower) `div` slotLength
    ahead = toInteger (unSlotNo (obsHorizonSlot obs)) - toInteger (unSlotNo clockSlot)
    slots = minimum [width `div` slotLength, whole, ahead]

{- | The interval of a return, decided from one observation, or the row that refuses it.
The interval starts at the slot the tip is in, and only the chain can say the deadline is
reached (that slot starts at or after it); the clock alone cannot, and where it reads the
deadline as passed and the tip does not, that is a conflict, named and not decided.
-}
returnWindow :: Observation -> Integer -> Integer -> Either Refusal ValidityPlan
returnWindow obs width deadline
    | tipStart < deadline =
        Left
            ( if clock >= deadline
                then TimeEvidenceConflicts clock deadline tipStart
                else DeadlineNotReached deadline tipStart clock
            )
    | slotLength <= 0 || width < slotLength = Left (BookingWidthBelowSlotLength width slotLength)
    | slots < 1 = Left (NoReturnSlotYet tipStart)
    | otherwise =
        Right
            ValidityPlan
                { lowerSlot = tip
                , upperSlot = tip + fromInteger slots
                , lowerPosixMs = tipStart
                , upperPosixMs = tipStart + slots * slotLength
                }
  where
    tip = obsTipSlot obs
    tipStart = obsTipStartMs obs
    clock = obsClockMs obs
    slotLength = obsSlotLengthMs obs
    slots = min (width `div` slotLength) (toInteger (unSlotNo (obsHorizonSlot obs)) - toInteger (unSlotNo tip))

-- ---------------------------------------------------------------------
-- Transactions
-- ---------------------------------------------------------------------

type Step a = ExceptT SubmitError IO a

node :: IO a -> Step a
node action = ExceptT (tryNode action <&> first (NodeFailed . show))

{- | Run a call of the node and give its failure as a value: a connection that ended, a query
that timed out, a refusal. A cancellation (the process being interrupted, a thread killed) is
not a failed call and passes through.
-}
tryNode :: IO a -> IO (Either SomeException a)
tryNode action =
    try action >>= \case
        Left failure
            | Just (cancellation :: SomeAsyncException) <- fromException failure -> throwIO cancellation
        outcome -> pure outcome

{- | A call of the node over a connection that ended. It says whether the call was made at
all: a call refused because the connection had ended before it began never reached the node.
-}
data NodeConnectionEnded = NodeConnectionEnded
    { endedBeforeCall :: !Bool
    , endedBecause :: !String
    }

instance Show NodeConnectionEnded where
    show ended = "the node connection ended: " <> endedBecause ended

instance Exception NodeConnectionEnded

-- | Sign, submit and observe a transaction: it is not submitted twice.
settle :: RegistryRuntime -> (Attempt -> IO ()) -> ConwayTx -> Step ConwayTx
settle rt onAttempt tx = do
    let transactions = rtTransactions rt
    signed <- node (trSign transactions tx) >>= either (throwE . SigningRefused . show) pure
    let txId = transactionId signed
    let announce = liftIO . onAttempt . Attempt txId
    -- signed, about to be handed over: the handoff has not begun
    announce NotHandedToNode
    -- from here the node may have received it, whatever happens next: what the command knows is
    -- written before the handoff begins and again as soon as the node answers
    submitted <- liftIO $ do
        onAttempt (Attempt txId HandoffUnknown)
        outcome <- tryNode (trSubmit transactions signed)
        case outcome of
            Right (Rejected reason) -> onAttempt (Attempt txId (RefusedByNode reason))
            Right (Submitted _) -> onAttempt (Attempt txId AcceptedByNode)
            Left failure
                | neverMade failure -> onAttempt (Attempt txId NotHandedToNode) >> throwIO failure
                | otherwise -> pure ()
        pure outcome
    case submitted of
        Left failure -> throwE (HandoffUnconfirmed txId (show failure))
        Right (Rejected reason) -> throwE (SubmissionRefused txId reason)
        Right (Submitted _) -> pure ()
    observed <- liftIO $ do
        outcome <- tryNode (trObserve transactions txId)
        either (const (pure ())) (const (onAttempt (Attempt txId (SettledOnChain signed)))) outcome
        pure outcome
    either (throwE . NotObserved txId . show) pure observed
    pure signed
  where
    -- the connection had ended before the handoff was made: the node was never asked
    neverMade failure = maybe False endedBeforeCall (fromException failure)

transactBudgeted ::
    RegistryRuntime ->
    Addr ->
    (Attempt -> IO ()) ->
    (PParams ConwayEra -> Payer -> Budgets -> Either RegistryTransactionError BuiltTransaction) ->
    IO (Either SubmitError ConwayTx)
transactBudgeted rt payerAddress onAttempt build = runExceptT $ do
    let transactions = rtTransactions rt
    params <- node (trQueryProtocolParams transactions)
    funds <- node (rtUtxosAt rt payerAddress)
    let built budgets = either (throwE . BuildRefused) pure (build params (Payer payerAddress funds) budgets)
    (discovery, expected) <- built Map.empty
    signedDiscovery <- node (trSign transactions discovery) >>= either (throwE . SigningRefused . show) pure
    evaluated <- node (trEvaluate transactions signedDiscovery)
    unless (Map.keysSet evaluated == expected) $
        throwE (PurposesDiffer (show (Map.keysSet evaluated)))
    measured <-
        Map.traverseWithKey
            (\purpose outcome -> either (throwE . EvaluationFailed . renderEvaluationFailure purpose) pure outcome)
            evaluated
    let budgets = Map.map withMargin measured
        total = foldr addUnits (ExUnits 0 0) (Map.elems budgets)
    unless (withinUnits total (params ^. ppMaxTxExUnitsL)) $
        throwE (BudgetExceeded (show total))
    (final, finalExpected) <- built budgets
    when (finalExpected /= expected) $
        throwE (PurposesDiffer "the purposes changed under the measured budgets")
    settle rt onAttempt final

transactPlain ::
    RegistryRuntime ->
    Addr ->
    (Attempt -> IO ()) ->
    (PParams ConwayEra -> Payer -> Either RegistryTransactionError ConwayTx) ->
    IO (Either SubmitError ConwayTx)
transactPlain rt payerAddress onAttempt build = runExceptT $ do
    params <- node (trQueryProtocolParams (rtTransactions rt))
    funds <- node (rtUtxosAt rt payerAddress)
    tx <- either (throwE . BuildRefused) pure (build params (Payer payerAddress funds))
    settle rt onAttempt tx

-- | A measured budget with the margin a transaction declares above it.
withMargin :: ExUnits -> ExUnits
withMargin (ExUnits memory steps) = ExUnits (bump memory) (bump steps)
  where
    bump value = value + max 1 ((value + 9) `div` 10)

addUnits :: ExUnits -> ExUnits -> ExUnits
addUnits (ExUnits a b) (ExUnits c d) = ExUnits (a + c) (b + d)

withinUnits :: ExUnits -> ExUnits -> Bool
withinUnits (ExUnits memory steps) (ExUnits limitMemory limitSteps) =
    memory <= limitMemory && steps <= limitSteps

-- | The fee a transaction pays, in lovelace.
feeOf :: ConwayTx -> Integer
feeOf tx = let Coin fee = tx ^. bodyTxL . feeTxBodyL in fee

{- | The key an export registers under: the identifier the registration datum
carries, as the registry's key set and the active token name spell it.
-}
exportKey :: InceptionExport -> ByteString
exportKey export = case liveOfKeyState "" 0 (inceptionDatum export) of
    Live{lvAid} -> lvAid
    TerminationPending{} -> error "exportKey: an inception is live"

{- | The runtime, every call of which returns once the node's connection has ended. The status
says whether the node client's thread is still running ('Nothing') or has ended, and why.
A call begun after the end fails at once without being made; a call under way when the end
comes fails then, whatever the node was to answer. Nothing is delivered to the thread that
makes the calls: the end is the failure of the call that needed the connection.

The time a call takes to return after the end is not one figure; it is named for its path.

* A call begun after the end, and a query that has not acquired ledger state or a submission
  under way when it comes: they return when this function sees the end, measured in tens of
  microseconds; nothing in the pinned node client bounds them, the wait in this function does.
* A query that has acquired ledger state before the end: the call is cancelled, and the node
  client then runs its best-effort release of that state, which gives up after its own release
  timeout, one second in the pinned client. The call returns within that second plus the time
  to schedule the threads; the tests allow half a second for it (1.5 s in all). Where the
  client's own liveness signal reaches the call first, it returns at once.
-}
whileConnected :: STM (Maybe SomeException) -> RegistryRuntime -> RegistryRuntime
whileConnected status runtime =
    runtime
        { rtUtxosAt = bounded . rtUtxosAt runtime
        , rtOutputs = bounded . rtOutputs runtime
        , rtRewardRegistered = bounded . rtRewardRegistered runtime
        , rtObserve = bounded (rtObserve runtime)
        , rtTransactions =
            transactions
                { trQueryProtocolParams = bounded (trQueryProtocolParams transactions)
                , trEvaluate = bounded . trEvaluate transactions
                , trSubmit = bounded . trSubmit transactions
                , trObserve = bounded . trObserve transactions
                }
        }
  where
    transactions = rtTransactions runtime
    bounded call = do
        gone <- atomically status
        forM_ gone (throwIO . NodeConnectionEnded True . show)
        race (atomically (status >>= maybe retry pure)) call
            >>= either (throwIO . NodeConnectionEnded False . show) pure

{- | Sign, hand over and observe a transaction that was built elsewhere, balanced and evaluated: the
steps after the build of 'transactBudgeted', with the same attempt reports and the same stops.
-}
transactBuilt :: RegistryRuntime -> (Attempt -> IO ()) -> ConwayTx -> IO (Either SubmitError ConwayTx)
transactBuilt rt onAttempt = runExceptT . settle rt onAttempt
