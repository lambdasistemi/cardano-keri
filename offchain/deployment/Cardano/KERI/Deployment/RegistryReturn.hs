{- |
Module      : Cardano.KERI.Deployment.RegistryReturn
Description : Return a booked request after its deadline: the refund address is paid everything but the tip

Anyone holding a booking output reference can return a request whose deadline the chain has
reached: the refund address the request's own datum names receives the request's lovelace less
the registry's minimum tip, and the wallet that pays the transaction keeps the tip. Nothing about
the refund is an input of the command. After the transaction is signed it never retries: it
stops and says how far the transaction got.
-}
module Cardano.KERI.Deployment.RegistryReturn (
    ReturnInput (..),
    ReturnEvent (..),
    ReturnCause (..),
    ReturnStopped (..),
    ReturnDone (..),
    returnBookedRequest,
) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), RegistrationData (..))
import Cardano.KERI.AID.Release (ReleaseIdentity)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    AttemptStatus (..),
    Loaded (..),
    Refusal (..),
    RegistryRuntime (..),
    SubmitError,
    feeOf,
    loadDeployment,
    returnWindow,
    termsOfIdentity,
    transactBudgeted,
    tryNode,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord)
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.RegistryTransactions (
    Booking (..),
    RegistryDeployment (..),
    ValidityPlan,
    holdsExactlyApproval,
    ledgerAddressOf,
    returnRequests,
 )
import Cardano.KERI.Deployment.Script (Blueprint)
import Cardano.KERI.Deployment.TransactionRuntime (transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (unCoin)
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Control.Exception (Exception, SomeAsyncException, SomeException, catch, fromException, throwIO)
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE, withExceptT)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Lens.Micro ((^.))

-- | What a return is given.
data ReturnInput = ReturnInput
    { returnBlueprint :: !Blueprint
    , returnIdentity :: !ReleaseIdentity
    , returnRecord :: !ReferenceRecord
    , returnRequestOutput :: !TxIn
    , returnPayerAddress :: !Addr
    -- ^ pays the transaction and keeps the tip
    }

-- | What a return reports, in the order it happens.
data ReturnEvent
    = -- | the request is a booked request of this registry, its deadline is reached, and this is what the return pays
      ReturnPlanned
        { plannedRequest :: !TxIn
        , plannedRefundAddress :: !Addr
        , plannedRefundLovelace :: !Integer
        , plannedTipLovelace :: !Integer
        , plannedPlan :: !ValidityPlan
        , plannedDeadline :: !Integer
        }
    | -- | the return is signed and about to be handed to the node: its id; this alone claims no submission
      ReturnHandingOff
        { handingOffTransaction :: !TxId
        }
    | -- | the return settled
      ReturnSettled
        { settledTransaction :: !TxId
        , settledRefundOutput :: !TxIn
        , settledFee :: !Integer
        }
    deriving stock (Eq, Show)

-- | Why a return stopped.
data ReturnCause
    = ReturnRefused !Refusal
    | -- | a read of the node failed: nothing was submitted by the stage that failed
      ReturnNodeFailed !String
    | -- | an event could not be reported (written to the person running the command): the node had no part in it
      ReturnReportFailed !String
    | ReturnTransaction !SubmitError
    deriving stock (Eq, Show)

-- | A return that stopped, with how far its transaction got when one was signed.
data ReturnStopped = ReturnStopped
    { returnCause :: !ReturnCause
    , returnAttempt :: !(Maybe Attempt)
    }
    deriving stock (Eq, Show)

-- | A return that settled.
data ReturnDone = ReturnDone
    { doneReturn :: !TxId
    , doneRefundOutput :: !TxIn
    , doneRefundLovelace :: !Integer
    , doneFee :: !Integer
    }
    deriving stock (Eq, Show)

-- | The report of an event could not be written: raised inside the run, and turned into the cause of the stop.
newtype ReportWriteFailed = ReportWriteFailed String
    deriving stock (Show)

instance Exception ReportWriteFailed

returnBookedRequest ::
    RegistryRuntime ->
    (ReturnEvent -> IO ()) ->
    ReturnInput ->
    IO (Either ReturnStopped ReturnDone)
returnBookedRequest rt report input = do
    attemptRef <- newIORef Nothing
    -- a failed call of the node, anywhere in the run, ends the return as a stop that says how far its
    -- transaction got; a cancellation passes
    ran <- tryNode (runExceptT (run attemptRef))
    attempt <- readIORef attemptRef
    pure $ case ran of
        Right (Right done) -> Right done
        Right (Left cause) -> Left (ReturnStopped cause attempt)
        -- what failed is said: the report of an event is not a read of the node
        Left failure
            | Just (ReportWriteFailed message) <- fromException failure -> Left (ReturnStopped (ReturnReportFailed message) attempt)
            | otherwise -> Left (ReturnStopped (ReturnNodeFailed (show failure)) attempt)
  where
    -- a failure to write the report of an event is not a failure of the node: it ends the run as the report's
    reporting event =
        report event `catch` \(failure :: SomeException) -> case fromException failure of
            Just (cancellation :: SomeAsyncException) -> throwIO cancellation
            Nothing -> throwIO (ReportWriteFailed (show failure))
    requestRef = returnRequestOutput input
    payer = returnPayerAddress input
    refuse = throwE . ReturnRefused

    run attemptRef = do
        loaded <-
            liftIO (loadDeployment rt (returnBlueprint input) (returnIdentity input) (returnRecord input))
                >>= either refuse pure
        let deployment = loadedDeployment loaded
            terms = termsOfIdentity (returnIdentity input)
            width = bookingWidth (registryParameters terms)
        -- the request: an unspent registration of this registry that still holds its approval
        found <- liftIO (rtOutputs rt (Set.singleton requestRef))
        requestOut <- maybe (refuse (RequestUnavailable requestRef)) pure (Map.lookup requestRef found)
        booked <- maybe (refuse (RequestIsNotARegistration requestRef)) pure (registrationOfOutput requestOut)
        unless (holdsExactlyApproval deployment booked requestOut) $
            refuse (RequestHasNoApproval requestRef)
        when (requestRegistry booked /= scriptsRegistry (deploymentScripts deployment)) $
            refuse (RequestIsForAnotherRegistry requestRef)
        -- the refund goes to the address the request names, never to a guess
        refundTo <-
            maybe (refuse (RequestRefundUnreadable requestRef)) pure (ledgerAddressOf (rtNetwork rt) (requestRefundAddress booked))
        -- one observation decides the interval
        observed <- liftIO (rtObserve rt)
        let deadline = requestProcessDeadline booked
        plan <- either refuse pure (returnWindow observed width deadline)
        let tip = minimumTip (registryParameters terms)
            refund = unCoin (requestOut ^. coinTxOutL) - tip
        liftIO . reporting $
            ReturnPlanned
                { plannedRequest = requestRef
                , plannedRefundAddress = refundTo
                , plannedRefundLovelace = refund
                , plannedTipLovelace = tip
                , plannedPlan = plan
                , plannedDeadline = deadline
                }
        returned <-
            withExceptT ReturnTransaction . ExceptT $
                transactBudgeted rt payer (followed attemptRef) $ \params funds budgets ->
                    returnRequests
                        params
                        deployment
                        (loadedReferences loaded)
                        funds
                        Booking{bookingOutput = (requestRef, requestOut), bookingRecord = booked, bookingValidity = plan}
                        plan
                        refundTo
                        budgets
        let returnId = transactionId returned
            refundOutput = TxIn returnId (TxIx 0)
        liftIO . reporting $ ReturnSettled{settledTransaction = returnId, settledRefundOutput = refundOutput, settledFee = feeOf returned}
        pure
            ReturnDone
                { doneReturn = returnId
                , doneRefundOutput = refundOutput
                , doneRefundLovelace = refund
                , doneFee = feeOf returned
                }

    -- a signed transaction is announced to the person running the command once, before it is handed over
    followed attemptRef attempt = do
        prior <- readIORef attemptRef
        writeIORef attemptRef (Just attempt)
        case attempt of
            Attempt txId NotHandedToNode | fmap attemptId prior /= Just txId -> reporting (ReturnHandingOff txId)
            _ -> pure ()
