{- |
Module      : Cardano.KERI.Deployment.RegistryRegister
Description : Book a registration in a registry that @ckeri registry deploy@ created

The controller's @kli export@ names the identity; the booking commits the
request's record over a validity interval no wider than the registry's booking
width, starting at the node's tip. Before it pays, it looks at what the chain
alone shows for this registry: an active token of the identity at the
checkpoint validator's address.
-}
module Cardano.KERI.Deployment.RegistryRegister (
    RegisterRequest (..),
    RegisterEvent (..),
    RegisterFailure (..),
    Registered (..),
    registerRegistration,
) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), RegistrationData (..), activeTokenName)
import Cardano.KERI.AID.Release (ReleaseIdentity)
import Cardano.KERI.Deployment.KEL (InceptionExport)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), RegistryTerms (..), registryInitialFloor)
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    AttemptStatus (..),
    Loaded (..),
    Observation (..),
    Refusal (..),
    RegistryRuntime (..),
    SubmitError (..),
    bookingWindow,
    exportKey,
    failureOfAttempt,
    feeOf,
    loadDeployment,
    termsOfIdentity,
    transactBudgeted,
    transactPlain,
    tryNode,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord)
import Cardano.KERI.Deployment.RegistryTransactions (
    BookedRequest (..),
    RegistryDeployment (..),
    ValidityPlan,
    bookRegistrations,
    checkpointAddress,
    mintHashProof,
    registrationRecord,
    statePolicyId,
 )
import Cardano.KERI.Deployment.Script (Blueprint, Observers (..), ScriptArtifact (..))
import Cardano.KERI.Deployment.TransactionRuntime (transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Control.Exception (Exception, SomeAsyncException, fromException, throwIO, try)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE, withExceptT)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Lens.Micro ((^.))

-- | What a booking is given.
data RegisterRequest = RegisterRequest
    { registerBlueprint :: !Blueprint
    , registerIdentity :: !ReleaseIdentity
    , registerRecord :: !ReferenceRecord
    , registerExport :: !InceptionExport
    , registerPayer :: !Addr
    -- ^ pays the booking, and is the refund address and the controller of the request
    , registerDeposit :: !(Maybe Integer)
    -- ^ the deposit the request commits; the registry's initial floor when absent
    }

-- | What a booking reports, in the order it happens.
data RegisterEvent
    = -- | the hash proof of the inception is preminted and settled: the transaction, the output that holds the proof and the fee
      PremintSettledForBooking
        { eventTransaction :: !TxId
        , eventProof :: !TxIn
        , eventFee :: !Integer
        }
    | -- | before anything is built: the interval and the deadline it gives
      BookingWindow
        { eventPlan :: !ValidityPlan
        , eventDeadline :: !Integer
        }
    | -- | the booking is signed and about to be submitted, with the time left to its deadline then
      BookingSubmitting
        { eventTransaction :: !TxId
        , eventTimeLeftMs :: !Integer
        }
    | -- | the booking settled
      BookingSettled
        { eventTransaction :: !TxId
        , eventOutput :: !TxIn
        , eventFee :: !Integer
        }
    deriving stock (Eq, Show)

data RegisterFailure
    = RegisterRefused !Refusal
    | -- | a stop before the premint settled, or of the premint itself: nothing of the booking left
      RegisterTransaction !SubmitError
    | -- | a stop after the premint settled: the transaction and the output that holds the proof, and the stop
      RegisterAfterPremint !TxId !TxIn !SubmitError
    | -- | a refusal of the command after the premint settled: the premint and its proof output, and the refusal
      RegisterRefusedAfterPremint !TxId !TxIn !Refusal
    | -- | the command stopped after the premint settled and before the booking was built (its report failed): the premint, its proof output and what failed
      RegisterStoppedAfterPremint !TxId !TxIn !String
    deriving stock (Eq, Show)

-- | A booking that settled.
data Registered = Registered
    { registeredPremint :: !TxId
    -- ^ the transaction that preminted the hash proof the booking burns
    , registeredTransaction :: !TxId
    , registeredOutput :: !TxIn
    , registeredRecord :: !RegistrationData
    , registeredPlan :: !ValidityPlan
    }
    deriving stock (Eq, Show)

registerRegistration ::
    RegistryRuntime ->
    (RegisterEvent -> IO ()) ->
    RegisterRequest ->
    IO (Either RegisterFailure Registered)
registerRegistration rt report request = do
    attemptRef <- newIORef Nothing
    premintRef <- newIORef Nothing
    -- a failed call of the node, anywhere in the run, ends the booking as a failure that says how far
    -- the run got
    ran <- tryNode (booking attemptRef premintRef rt (reporting report) request)
    premint <- readIORef premintRef
    case ran of
        Right result -> pure (afterPremint premint result)
        Left failure -> do
            attempt <- readIORef attemptRef
            pure $ case (premint, attempt, fromException failure) of
                -- the report failed before any booking was signed: the premint is all that settled
                (Just (premintId, proofIn), Nothing, Just (ReportFailed message)) ->
                    Left (RegisterStoppedAfterPremint premintId proofIn message)
                _ -> afterPremint premint (Left (RegisterTransaction (failureOfAttempt attempt (show failure))))
  where
    -- once the premint has settled, a stop of the run says so
    afterPremint (Just (premintId, proofIn)) (Left (RegisterTransaction failure)) =
        Left (RegisterAfterPremint premintId proofIn failure)
    afterPremint (Just (premintId, proofIn)) (Left (RegisterRefused refusal)) =
        Left (RegisterRefusedAfterPremint premintId proofIn refusal)
    afterPremint _ result = result

-- | A report of the run that failed: not a failure of the node, and not of a transaction.
newtype ReportFailed = ReportFailed String

instance Show ReportFailed where
    show (ReportFailed message) = message

instance Exception ReportFailed

-- | The report of the run, whose failure is named as such: a cancellation passes through.
reporting :: (RegisterEvent -> IO ()) -> RegisterEvent -> IO ()
reporting report event =
    try (report event) >>= \case
        Left failure
            | Just (cancellation :: SomeAsyncException) <- fromException failure -> throwIO cancellation
            | otherwise -> throwIO (ReportFailed (show failure))
        Right () -> pure ()

booking ::
    IORef (Maybe Attempt) ->
    IORef (Maybe (TxId, TxIn)) ->
    RegistryRuntime ->
    (RegisterEvent -> IO ()) ->
    RegisterRequest ->
    IO (Either RegisterFailure Registered)
booking attemptRef premintRef rt report request = runExceptT $ do
    let identity = registerIdentity request
        export = registerExport request
        refund = registerPayer request
        key = exportKey export
    loaded <- reading (loadDeployment rt (registerBlueprint request) identity (registerRecord request)) >>= either (throwE . RegisterRefused) pure
    let deployment = loadedDeployment loaded
        terms = termsOfIdentity identity
        floorDeposit = registryInitialFloor terms
        deposit = fromMaybe floorDeposit (registerDeposit request)
        width = bookingWidth (registryParameters terms)
    -- what the chain alone shows: the key's active token at the checkpoint validator's address
    held <- reading (rtUtxosAt rt (checkpointAddress deployment))
    when (any (holdsActive deployment key . snd) held) $
        throwE (RegisterRefused (AlreadyRegistered key))
    -- the premint of the hash proof the booking spends and burns: its own interval, from the tip
    preminted <- windowFrom width
    premintTx <-
        withExceptT RegisterTransaction . ExceptT $
            transactPlain rt refund (recordAttempt (\_ _ -> pure ())) $ \params funds ->
                mintHashProof params deployment funds export preminted
    proofIn <-
        maybe
            (throwE (RegisterTransaction (NodeFailed "the premint made no hash-proof output")))
            pure
            (proofOutput deployment premintTx)
    let premintId = transactionId premintTx
    liftIO (writeIORef premintRef (Just (premintId, fst proofIn)))
    -- the booking's own attempts start here: the premint's settled attempt is not one of them
    liftIO (writeIORef attemptRef Nothing)
    liftIO . report $ PremintSettledForBooking premintId (fst proofIn) (feeOf premintTx)
    -- the booking's own interval, from the tip as it is after the premint
    plan <- windowFrom width
    let record = registrationRecord deployment refund deposit export plan
    let deadline = requestProcessDeadline record
    liftIO . report $ BookingWindow{eventPlan = plan, eventDeadline = deadline}
    booked <-
        withExceptT RegisterTransaction . ExceptT $
            transactBudgeted rt refund (recordAttempt (followed deadline)) $ \params payer budgets ->
                bookRegistrations params deployment (loadedReferences loaded) payer [BookedRequest record export proofIn] plan 0 budgets
    let txId = transactionId booked
        output = TxIn txId (TxIx 0)
    liftIO . report $
        BookingSettled
            { eventTransaction = txId
            , eventOutput = output
            , eventFee = feeOf booked
            }
    pure
        Registered
            { registeredPremint = premintId
            , registeredTransaction = txId
            , registeredOutput = output
            , registeredRecord = record
            , registeredPlan = plan
            }
  where
    -- a read of the node that fails is a failure of the run, not an escape; a cancellation passes
    reading action = withExceptT (RegisterTransaction . NodeFailed . show) (ExceptT (tryNode action))
    -- an interval from the tip, no wider than the booking width: the refusals are the command's
    windowFrom width = do
        observed <- reading (rtObserve rt)
        case bookingWindow observed width of
            Just plan -> pure plan
            Nothing
                | width < obsSlotLengthMs observed ->
                    throwE (RegisterRefused (BookingWidthBelowSlotLength width (obsSlotLengthMs observed)))
                | otherwise -> throwE (RegisterRefused (NoBookingIntervalYet (obsClockMs observed)))
    recordAttempt next attempt = do
        prior <- readIORef attemptRef
        writeIORef attemptRef (Just attempt)
        next prior attempt
    -- the clock is read when the transaction is about to leave, after it was built,
    -- evaluated and signed: that is the time the controller has left
    followed deadline prior attempt = case attempt of
        Attempt txId NotHandedToNode | fmap attemptId prior /= Just txId -> do
            now <- rtNowMs rt
            report BookingSubmitting{eventTransaction = txId, eventTimeLeftMs = deadline - now}
        _ -> pure ()
    proofOutput deployment tx =
        find
            (holdsHashProof deployment . snd)
            [ (TxIn (transactionId tx) (TxIx ix), out)
            | (ix, out) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
            ]
    holdsHashProof deployment out = case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            Map.member (PolicyID (artifactScriptHash (observerHashProof (scriptsObservers (deploymentScripts deployment))))) assets

-- | Whether an output holds the active token of a key in the registry.
holdsActive :: RegistryDeployment -> ByteString -> TxOut ConwayEra -> Bool
holdsActive deployment key out = case out ^. valueTxOutL of
    MaryValue _ (MultiAsset assets) ->
        (Map.lookup (statePolicyId deployment) assets >>= Map.lookup name) == Just 1
  where
    name = AssetName (SBS.toShort (activeTokenName (scriptsRegistry (deploymentScripts deployment)) key))
