{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFold
Description : Fold a booked registration into the registry, with a snapshot supplied by a named party

Any party can fold a booked request: the registry's own signatures are what the transaction checks: the booking attested the
inception, so the folder supplies nothing but chain data and its wallet. This command-side flow
adds what it can see before it pays: the snapshot it is given must be the
registry state the chain holds, the key must not be held, and the fold must
still fit before the request's deadline. It sends one transaction and never
retries: it stops and says how far that transaction got.
-}
module Cardano.KERI.Deployment.RegistryFold (
    FoldInput (..),
    FoldEvent (..),
    Attempt (..),
    AttemptStatus (..),
    FoldCause (..),
    FoldStopped (..),
    FoldDone (..),
    foldBookedRequest,
    stoppedFold,
) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), RegistrationData (..), stateDatumData)
import Cardano.KERI.AID.E2E.Datum (rawInlineData)
import Cardano.KERI.AID.Release (ReleaseIdentity)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    AttemptStatus (..),
    Loaded (..),
    Refusal (..),
    RegistryRuntime (..),
    SubmitError (..),
    feeOf,
    findStateOutput,
    foldWindow,
    loadDeployment,
    termsOfIdentity,
    transactBudgeted,
    tryNode,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord)
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), snapshotHolds, snapshotRoot)
import Cardano.KERI.Deployment.RegistryTransactions (
    FoldPlan (..),
    Payer (..),
    RegistryDeployment (..),
    foldRegistration,
    holdsExactlyApproval,
 )
import Cardano.KERI.Deployment.Script (Blueprint)
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE, withExceptT)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Functor ((<&>))
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import PlutusCore.Data (Data (..))

-- | What a fold is given.
data FoldInput = FoldInput
    { foldBlueprint :: !Blueprint
    , foldIdentity :: !ReleaseIdentity
    , foldRecord :: !ReferenceRecord
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
    | -- | the fold settled
      FoldSettled
        { eventTransaction :: !TxId
        , eventHolding :: !TxIn
        , eventFee :: !Integer
        }
    deriving stock (Eq, Show)

-- | Why a fold stopped.
data FoldCause
    = FoldRefused !Refusal
    | -- | a call of the node failed: the attempt, when one was signed, says how far the fold got
      FoldNodeFailed !String
    | FoldTransaction !SubmitError
    deriving stock (Eq, Show)

-- | A fold that stopped, with what it had done and what the node last confirmed.
data FoldStopped = FoldStopped
    { stoppedCause :: !FoldCause
    , stoppedFoldAttempt :: !(Maybe Attempt)
    -- ^ the fold it signed, and how far it got
    , stoppedConfirmed :: !(Maybe (TxIn, Maybe ByteString))
    -- ^ the registry state output the node last confirmed, and the root it holds
    }
    deriving stock (Eq, Show)

-- | The fold, when one was signed.
stoppedFold :: FoldStopped -> Maybe TxId
stoppedFold = fmap attemptId . stoppedFoldAttempt

-- | A fold that settled.
data FoldDone = FoldDone
    { doneSnapshot :: !Snapshot
    -- ^ the registry as it stands after the fold, for the next folder to check again
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
    foldRef <- newIORef Nothing
    seenRef <- newIORef Nothing
    -- a failed call of the node, anywhere in the run, ends the fold as a stop that says how far the
    -- transaction got
    ran <- tryNode (runExceptT (run foldRef seenRef))
    outcome <- case ran of
        Right result -> pure result
        Left failure -> pure (Left (FoldNodeFailed (show failure)))
    case outcome of
        Right done -> pure (Right done)
        Left cause -> do
            foldAttempt <- readIORef foldRef
            -- the registry state the fold last read, which is the state the node last confirmed to it
            seen <- readIORef seenRef
            pure (Left (FoldStopped cause foldAttempt seen))
  where
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

    run foldRef seenRef = do
        loaded <-
            node (loadDeployment rt (foldBlueprint input) (foldIdentity input) (foldRecord input))
                >>= either refuse pure
        let deployment = loadedDeployment loaded
            terms = termsOfIdentity (foldIdentity input)
            width = bookingWidth (registryParameters terms)
        -- the request: an unspent registration of this registry, whose key the booking attested
        found <- node (rtOutputs rt (Set.singleton (foldRequestOutput input)))
        requestOut <- maybe (refuse (RequestUnavailable (foldRequestOutput input))) pure (Map.lookup (foldRequestOutput input) found)
        record <- maybe (refuse (RequestIsNotARegistration (foldRequestOutput input))) pure (registrationOfOutput requestOut)
        unless (holdsExactlyApproval deployment record requestOut) $
            refuse (RequestHasNoApproval (foldRequestOutput input))
        when (requestRegistry record /= scriptsRegistry (deploymentScripts deployment)) $
            refuse (RequestIsForAnotherRegistry (foldRequestOutput input))
        let key = requestKey record
        -- the snapshot is the registry state the chain holds
        (stateIn, stateOut) <-
            node (findStateOutput rt deployment) >>= maybe (refuse (StaleOrUnavailableRegistryState Nothing)) pure
        liftIO (writeIORef seenRef (Just (stateIn, rootOf stateOut)))
        when (rawInlineData stateOut /= Just stateDatum) $
            refuse (StaleOrUnavailableRegistryState (rootOf stateOut))
        liftIO . report $ SnapshotChecked (snapshotSuppliedBy snapshot) (snapshotRoot snapshot)
        when (snapshotHolds snapshot key) $ refuse (RegistryHoldsKey key)
        planned <- window rt width (requestProcessDeadline record) >>= either refuse pure
        let plan =
                FoldPlan
                    { foldRequest = (foldRequestOutput input, requestOut)
                    , foldBooked = record
                    , foldRegistered = snapshotActive snapshot
                    , foldTerminated = snapshotTerminal snapshot
                    , foldState = (stateIn, stateOut)
                    , foldValidity = planned
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
                        { snapshotSuppliedBy = "the fold of " <> renderTransactionId foldId
                        , snapshotActive = snapshotActive snapshot <> [key]
                        }
                , doneFold = foldId
                , doneHolding = holding
                }

    {- A validity interval from the tip, no wider than the booking width, ending by the deadline.
    The chain decides that the deadline passed (no whole slot left after its tip); the clock is
    the machine's own and decides nothing about the deadline: it says only that an interval the
    chain allows is already in the past, which is named for what it is.
    One observation per decision: the tip, the clock and the horizon are read once, here. -}
    window runtime width deadline = do
        observed <- node (rtObserve runtime)
        pure (foldWindow observed width deadline)

    -- a read of the node that fails is a stop, not an escape
    node action = ExceptT (tryNode action <&> first (FoldNodeFailed . show))
