{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFold
Description : Fold a booked registration into the registry, with a snapshot supplied by a named party

Any party can fold a booked request: the registry's own signatures and the
controller's export are what the transactions check. This command-side flow
adds what it can see before it pays: the snapshot it is given must be the
registry state the chain holds, the key must not be held, and the fold must
still fit before the request's deadline. After the first transaction it never
retries: it stops and says what landed.
-}
module Cardano.KERI.Deployment.RegistryFold (
    FoldInput (..),
    FoldEvent (..),
    Attempt (..),
    AttemptStatus (..),
    FoldCause (..),
    FoldStage (..),
    FoldStopped (..),
    FoldDone (..),
    foldBookedRequest,
    stoppedFold,
    stoppedPremintAttempt,
) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), RegistrationData (..), stateDatumData)
import Cardano.KERI.AID.E2E.Datum (rawInlineData)
import Cardano.KERI.AID.Release (ReleaseIdentity)
import Cardano.KERI.Deployment.KEL (InceptionExport)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    AttemptStatus (..),
    Loaded (..),
    Refusal (..),
    RegistryRuntime (..),
    SubmitError (..),
    exportKey,
    feeOf,
    findStateOutput,
    foldWindow,
    loadDeployment,
    termsOfIdentity,
    transactBudgeted,
    transactPlain,
    tryNode,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord)
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), snapshotHolds, snapshotRoot)
import Cardano.KERI.Deployment.RegistryTransactions (
    FoldPlan (..),
    Payer (..),
    RegistryDeployment (..),
    applicationPolicyId,
    approval,
    foldRegistration,
    mintHashProof,
    tokenValue,
 )
import Cardano.KERI.Deployment.Script (Blueprint, Observers (..), ScriptArtifact (..))
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (valueTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Control.Monad (forM_, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE, withExceptT)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.Functor ((<&>))
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Lens.Micro ((^.))
import PlutusCore.Data (Data (..))

-- | What a fold is given.
data FoldInput = FoldInput
    { foldBlueprint :: !Blueprint
    , foldIdentity :: !ReleaseIdentity
    , foldRecord :: !ReferenceRecord
    , foldExport :: !InceptionExport
    , foldRequestOutput :: !TxIn
    , foldSnapshot :: !Snapshot
    , foldPayerAddress :: !Addr
    }

-- | What a fold reports, in the order it happens.
data FoldEvent
    = -- | the snapshot is the registry state the chain holds
      SnapshotChecked
        { eventSupplier :: !Text
        , eventRoot :: !ByteString
        }
    | -- | a fold is signed and about to be handed to the node: its id; this alone claims no submission
      FoldHandingOff
        { eventTransaction :: !TxId
        }
    | -- | the premint is signed and about to be handed to the node: its id; this alone claims no submission
      PremintHandingOff
        { eventTransaction :: !TxId
        }
    | -- | the hash-proof premint settled
      PremintSettled
        { eventTransaction :: !TxId
        , eventProof :: !TxIn
        , eventFee :: !Integer
        }
    | -- | the fold settled
      FoldSettled
        { eventTransaction :: !TxId
        , eventHolding :: !TxIn
        , eventFee :: !Integer
        }
    deriving stock (Eq, Show)

-- | The two places a fold reads the node to decide: before the premint, and after it settled.
data FoldStage = BeforePremint | AfterPremint
    deriving stock (Eq, Show)

-- | Why a fold stopped.
data FoldCause
    = FoldRefused !Refusal
    | -- | after the premint settled, the interval for the fold could not be formed: only the premint was spent
      FoldWindowAfterPremint !Refusal
    | -- | the registry state moved after the snapshot was checked
      RegistryMoved
    | -- | a read of the node failed, at this stage: nothing was submitted by the stage that failed
      FoldNodeFailed !FoldStage !String
    | FoldTransaction !SubmitError
    deriving stock (Eq, Show)

-- | A fold that stopped, with what it had done and what the node last confirmed.
data FoldStopped = FoldStopped
    { stoppedCause :: !FoldCause
    , stoppedPremint :: !(Maybe (TxId, TxIn))
    -- ^ the premint and the proof output it made
    , stoppedPremintFee :: !(Maybe Integer)
    -- ^ what the premint paid, in lovelace, when it settled
    , stoppedPremintHandoff :: !(Maybe Attempt)
    -- ^ the premint it signed, and how far it got
    , stoppedFoldAttempt :: !(Maybe Attempt)
    -- ^ the fold it signed, and how far it got
    , stoppedConfirmed :: !(Maybe (TxIn, Maybe ByteString))
    -- ^ the registry state output the node last confirmed, and the root it holds
    }
    deriving stock (Eq, Show)

-- | The fold, when one was signed.
stoppedFold :: FoldStopped -> Maybe TxId
stoppedFold = fmap attemptId . stoppedFoldAttempt

-- | The premint, when it was signed, settled or not.
stoppedPremintAttempt :: FoldStopped -> Maybe TxId
stoppedPremintAttempt = fmap attemptId . stoppedPremintHandoff

-- | A fold that settled.
data FoldDone = FoldDone
    { doneSnapshot :: !Snapshot
    -- ^ the registry as it stands after the fold, for the next folder to check again
    , donePremint :: !TxId
    , doneFold :: !TxId
    , doneHolding :: !TxIn
    }
    deriving stock (Eq, Show)

foldBookedRequest ::
    RegistryRuntime ->
    (FoldEvent -> IO ()) ->
    FoldInput ->
    IO (Either FoldStopped FoldDone)
foldBookedRequest rt report input = do
    premintRef <- newIORef Nothing
    foldRef <- newIORef Nothing
    seenRef <- newIORef Nothing
    attemptRef <- newIORef Nothing
    feeRef <- newIORef Nothing
    -- a failed call of the node, anywhere in the run, ends the fold as a stop that says how far each
    -- transaction got
    ran <- tryNode (runExceptT (run premintRef foldRef seenRef attemptRef feeRef))
    outcome <- case ran of
        Right result -> pure result
        Left failure -> do
            settled <- readIORef premintRef
            pure (Left (FoldNodeFailed (maybe BeforePremint (const AfterPremint) settled) (show failure)))
    case outcome of
        Right done -> pure (Right done)
        Left cause -> do
            premint <- readIORef premintRef
            foldAttempt <- readIORef foldRef
            -- the registry state the fold last read, which is the state the node last confirmed to it
            seen <- readIORef seenRef
            attempt <- readIORef attemptRef
            fee <- readIORef feeRef
            pure (Left (FoldStopped cause premint fee attempt foldAttempt seen))
  where
    export = foldExport input
    key = exportKey export
    snapshot = foldSnapshot input
    payer = foldPayerAddress input
    refuse = throwE . FoldRefused

    -- a signed transaction is announced to the person running the command once, before it is handed over
    announce prior event = \case
        Attempt txId NotHandedToNode | fmap attemptId prior /= Just txId -> report (event txId)
        _ -> pure ()

    rootOf out =
        rawInlineData out >>= \case
            Constr 0 [B root] -> Just root
            _ -> Nothing

    stateDatum = stateDatumData (snapshotRoot snapshot)

    run premintRef foldRef seenRef attemptRef feeRef = do
        loaded <-
            node BeforePremint (loadDeployment rt (foldBlueprint input) (foldIdentity input) (foldRecord input))
                >>= either refuse pure
        let deployment = loadedDeployment loaded
            terms = termsOfIdentity (foldIdentity input)
            width = bookingWidth (registryParameters terms)
        -- the request: an unspent registration of this registry, for the export's key
        found <- node BeforePremint (rtOutputs rt (Set.singleton (foldRequestOutput input)))
        requestOut <- maybe (refuse (RequestUnavailable (foldRequestOutput input))) pure (Map.lookup (foldRequestOutput input) found)
        record <- maybe (refuse (RequestIsNotARegistration (foldRequestOutput input))) pure (registrationOfOutput requestOut)
        unless (holdsExactlyApproval deployment record requestOut) $
            refuse (RequestHasNoApproval (foldRequestOutput input))
        when (requestRegistry record /= scriptsRegistry (deploymentScripts deployment)) $
            refuse (RequestIsForAnotherRegistry (foldRequestOutput input))
        when (requestKey record /= key) $
            refuse (RequestIsForAnotherKey (requestKey record) key)
        -- the snapshot is the registry state the chain holds
        (stateIn, stateOut) <-
            node BeforePremint (findStateOutput rt deployment) >>= maybe (refuse (StaleOrUnavailableRegistryState Nothing)) pure
        liftIO (writeIORef seenRef (Just (stateIn, rootOf stateOut)))
        when (rawInlineData stateOut /= Just stateDatum) $
            refuse (StaleOrUnavailableRegistryState (rootOf stateOut))
        liftIO . report $ SnapshotChecked (snapshotSuppliedBy snapshot) (snapshotRoot snapshot)
        when (snapshotHolds snapshot key) $ refuse (RegistryHoldsKey key)
        let deadline = requestProcessDeadline record
        planned <- window BeforePremint rt width deadline >>= either refuse pure
        -- the premint: the hash proof the fold burns. When it is seen to settle, its receipt is
        -- recorded in the same step as its disposition
        let recordPremint attempt = do
                prior <- readIORef attemptRef
                writeIORef attemptRef (Just attempt)
                case attempt of
                    Attempt _ (SettledOnChain settled) ->
                        forM_ (proofOutput deployment settled) $ \(proofRef, _) -> do
                            writeIORef premintRef (Just (transactionId settled, proofRef))
                            writeIORef feeRef (Just (feeOf settled))
                    _ -> announce prior PremintHandingOff attempt
        premintTx <-
            withExceptT FoldTransaction . ExceptT $
                transactPlain rt payer recordPremint $ \params funds ->
                    mintHashProof params deployment funds export planned
        let premintId = transactionId premintTx
        proofIn <- maybe (throwE (FoldTransaction (NodeFailed "the premint made no hash-proof output"))) pure (proofOutput deployment premintTx)
        liftIO . report $ PremintSettled premintId (fst proofIn) (feeOf premintTx)
        -- the registry as it stands now must still be the one that was checked
        (movedIn, movedOut) <-
            node AfterPremint (findStateOutput rt deployment) >>= maybe (throwE RegistryMoved) pure
        liftIO (writeIORef seenRef (Just (movedIn, rootOf movedOut)))
        when (movedIn /= stateIn || rawInlineData movedOut /= Just stateDatum) $
            throwE RegistryMoved
        foldWindow' <- window AfterPremint rt width deadline >>= either (throwE . FoldWindowAfterPremint) pure
        let plan =
                FoldPlan
                    { foldRequest = (foldRequestOutput input, requestOut)
                    , foldBooked = record
                    , foldInception = export
                    , foldProof = proofIn
                    , foldReferences = loadedFoldReferences loaded
                    , foldRegistered = snapshotActive snapshot
                    , foldTerminated = snapshotTerminal snapshot
                    , foldState = (movedIn, movedOut)
                    , foldValidity = foldWindow'
                    , foldPayer = Payer payer []
                    }
        foldTx <-
            withExceptT FoldTransaction . ExceptT $
                transactBudgeted rt payer (\attempt -> readIORef foldRef >>= \prior -> writeIORef foldRef (Just attempt) >> announce prior FoldHandingOff attempt) $ \params funds budgets ->
                    foldRegistration params deployment (loadedReferences loaded) plan{foldPayer = funds} budgets
        let foldId = transactionId foldTx
            holding = TxIn foldId (TxIx 0)
        liftIO . report $ FoldSettled foldId holding (feeOf foldTx)
        pure
            FoldDone
                { doneSnapshot =
                    snapshot
                        { snapshotSuppliedBy = "the fold of " <> renderTransactionId premintId <> " and " <> renderTransactionId foldId
                        , snapshotActive = snapshotActive snapshot <> [key]
                        }
                , donePremint = premintId
                , doneFold = foldId
                , doneHolding = holding
                }

    -- a validity interval from the tip, no wider than the booking width, ending by the deadline
    {- A validity interval from the tip, no wider than the booking width, ending by the deadline.
    The chain decides that the deadline passed (no whole slot left after its tip); the clock is
    the machine's own and decides nothing about the deadline: it says only that an interval the
    chain allows is already in the past, which is named for what it is. -}
    -- one observation per decision: the tip, the clock and the horizon are read once, here
    window stage runtime width deadline = do
        observed <- node stage (rtObserve runtime)
        pure (foldWindow observed width deadline)

    -- a read of the node that fails is a stop, not an escape
    node stage action = ExceptT (tryNode action <&> first (FoldNodeFailed stage . show))

    holdsExactlyApproval deployment record out = case out ^. valueTxOutL of
        MaryValue _ assets -> assets == tokenValue (applicationPolicyId deployment) (approval record) 1

    proofOutput deployment tx =
        find
            (holdsPolicy (PolicyID (artifactScriptHash (observerHashProof (scriptsObservers (deploymentScripts deployment))))) . snd)
            [ (TxIn (transactionId tx) (TxIx ix), out)
            | (ix, out) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
            ]

    holdsPolicy policy out = case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) -> Map.member policy assets
