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
    tryNode,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord)
import Cardano.KERI.Deployment.RegistryTransactions (
    RegistryDeployment (..),
    ValidityPlan,
    bookRegistration,
    checkpointAddress,
    registrationRecord,
    statePolicyId,
 )
import Cardano.KERI.Deployment.Script (Blueprint)
import Cardano.KERI.Deployment.TransactionRuntime (transactionId)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx.Out (TxOut, valueTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE, withExceptT)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
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
    = -- | before anything is built: the interval and the deadline it gives
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
    | RegisterTransaction !SubmitError
    deriving stock (Eq, Show)

-- | A booking that settled.
data Registered = Registered
    { registeredTransaction :: !TxId
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
    -- a failed call of the node, anywhere in the run, ends the booking as a failure that says how far
    -- the booking got
    ran <- tryNode (booking attemptRef rt report request)
    case ran of
        Right result -> pure result
        Left failure -> do
            attempt <- readIORef attemptRef
            pure (Left (RegisterTransaction (failureOfAttempt attempt (show failure))))

booking ::
    IORef (Maybe Attempt) ->
    RegistryRuntime ->
    (RegisterEvent -> IO ()) ->
    RegisterRequest ->
    IO (Either RegisterFailure Registered)
booking attemptRef rt report request = runExceptT $ do
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
    observed <- reading (rtObserve rt)
    plan <- case bookingWindow observed width of
        Just plan -> pure plan
        Nothing
            | width < obsSlotLengthMs observed ->
                throwE (RegisterRefused (BookingWidthBelowSlotLength width (obsSlotLengthMs observed)))
            | otherwise -> throwE (RegisterRefused (NoBookingIntervalYet (obsClockMs observed)))
    let record = registrationRecord deployment refund deposit export plan
    let deadline = requestProcessDeadline record
    liftIO . report $ BookingWindow{eventPlan = plan, eventDeadline = deadline}
    booked <-
        withExceptT RegisterTransaction . ExceptT $
            transactBudgeted rt refund (followed deadline) $ \params payer budgets ->
                bookRegistration params deployment (loadedReferences loaded) payer record plan 0 budgets
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
            { registeredTransaction = txId
            , registeredOutput = output
            , registeredRecord = record
            , registeredPlan = plan
            }
  where
    -- a read of the node that fails is a failure of the booking, not an escape; a cancellation passes
    reading action = withExceptT (RegisterTransaction . NodeFailed . show) (ExceptT (tryNode action))
    -- the clock is read when the transaction is about to leave, after it was built,
    -- evaluated and signed: that is the time the controller has left
    followed deadline attempt = do
        prior <- readIORef attemptRef
        writeIORef attemptRef (Just attempt)
        case attempt of
            Attempt txId NotHandedToNode | fmap attemptId prior /= Just txId -> do
                now <- rtNowMs rt
                report BookingSubmitting{eventTransaction = txId, eventTimeLeftMs = deadline - now}
            _ -> pure ()

-- | Whether an output holds the active token of a key in the registry.
holdsActive :: RegistryDeployment -> ByteString -> TxOut ConwayEra -> Bool
holdsActive deployment key out = case out ^. valueTxOutL of
    MaryValue _ (MultiAsset assets) ->
        (Map.lookup (statePolicyId deployment) assets >>= Map.lookup name) == Just 1
  where
    name = AssetName (SBS.toShort (activeTokenName (scriptsRegistry (deploymentScripts deployment)) key))
