{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.Deployment.KoiosRegistryRuntime
Description : The Koios instance of 'RegistryRuntime'

The registry runtime over Koios. Its reads are "Cardano.KERI.Deployment.KoiosRuntime",
its handoff is "Cardano.KERI.Deployment.KoiosSubmission", its settlement is
"Cardano.KERI.Deployment.KoiosSettlement"; this module assembles them and adds
nothing of its own to what they decide.

A transaction the handoff may have delivered is told to the command as an
exception whose text is the handoff's own report: a refusal that came after an
unanswered attempt is not "not on chain", because the first attempt may have
arrived. A transaction is observed under the signed bytes that were handed
over, which the instance remembers by id.
-}
module Cardano.KERI.Deployment.KoiosRegistryRuntime (
    KoiosAccess (..),
    KoiosStartFailure (..),
    renderKoiosStartFailure,
    KoiosParts (..),
    koiosRegistryRuntime,
    openKoiosRuntime,
    KoiosOpened (..),
    openKoios,
    HandoffUncertain (..),
    ObservationFailed (..),
) where

import Cardano.KERI.Deployment.KoiosRuntime (KoiosReads (..), koiosReads, wholeAnswers)
import Cardano.KERI.Deployment.KoiosSettlement (
    Refusal,
    Settlement (..),
    koiosSettlement,
    renderUnsettlement,
 )
import Cardano.KERI.Deployment.KoiosSubmission (Handoff (..), HandoffResult (..), renderHandoff, submitHandoff)
import Cardano.KERI.Deployment.NodeSocketRuntime (KeySource, keySourceEnvelope)
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), TransactionUnconfirmed (..), ValidityEnd (..), tryNode)
import Cardano.KERI.Deployment.RegistryWindow (koiosValidityEnd, resolveTimeSource)
import Cardano.KERI.Deployment.SingularFunding (singularFundingRules)
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionRuntime (..),
    TransactionSigningError,
    renderTransactionId,
    signWithPaymentKey,
    transactionId,
 )
import Cardano.Ledger.Api.Tx (addrTxWitsL, witsTxL)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.TxIn (TxId)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Control.Exception (Exception, throwIO)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import Lens.Micro ((^.))
import Singular.Provider.Koios.Client (FailureReason (..), Koios (..), defaultClientConfig)
import Singular.Provider.Koios.Http (HttpConfig (..), defaultHttpConfig, newHttpTransport)
import Singular.Provider.Koios.Provider (koiosProvider)
import Singular.Provider.Koios.Runtime (newIORuntime)
import Singular.Registry.Confirmation (newIOConfirmationRuntime)
import Singular.Registry.Evidence (NoWitness)
import Singular.Registry.LedgerProvider (AcquireFailure, Acquisition (..), LedgerProvider (..), Network (..), ReadFailure (..), Session)
import Singular.Registry.NetworkTime (NetworkTimeFailure (..), validateNetworkTime)
import Singular.Registry.Signing (SignedTx, assembleSigned)
import Singular.Registry.TimeSource (TimeSource (..))

-- | How a command reaches Koios and who pays.
data KoiosAccess = KoiosAccess
    { koiosUrl :: !Text
    , koiosTokenFile :: !(Maybe FilePath)
    , koiosNetworkMagic :: !Int
    , koiosFundingAddress :: !Text
    , koiosSigningKey :: !KeySource
    , koiosNetworkTime :: !(Maybe FilePath)
    }
    deriving stock (Show, Eq)

-- | Why the instance could not be built, before any request.
data KoiosStartFailure
    = -- | the network has no pinned network time
      NetworkNotPinned !Int
    | -- | the token file cannot be read: what the transport said
      TokenUnreadable !Text
    | -- | the pinned network time cannot be loaded or does not validate
      TimeSourceUnreadable !Text
    deriving stock (Eq, Show)

renderKoiosStartFailure :: KoiosStartFailure -> String
renderKoiosStartFailure = \case
    NetworkNotPinned magic ->
        "koios-network-not-pinned: network magic "
            <> show magic
            <> " has no pinned network time; Koios is used on preprod, network magic 1"
    TokenUnreadable message -> "koios-token-file-unreadable: " <> T.unpack message
    TimeSourceUnreadable message -> "koios-time-unreadable: " <> T.unpack message

-- | What the instance is assembled from.
data KoiosParts = KoiosParts
    { partReads :: !KoiosReads
    , partSign :: ConwayTx -> IO (Either TransactionSigningError ConwayTx)
    , partHandoff :: SignedTx -> IO Handoff
    , partSettle :: ConwayTx -> IO (Either Refusal Settlement)
    , partReport :: Handoff -> IO ()
    -- ^ told of every handoff, whatever came of it
    , partClock :: IO Integer
    -- ^ the machine's clock in POSIX milliseconds
    , partWindow :: IO ValidityEnd
    -- ^ the validity end of a transaction built now, read once for each build
    }

-- | A handoff that may have reached the provider; its text is the handoff's report.
newtype HandoffUncertain = HandoffUncertain Text

instance Show HandoffUncertain where
    show (HandoffUncertain text) = T.unpack text

instance Exception HandoffUncertain

-- | Why a transaction was not observed to settle.
data ObservationFailed
    = -- | no transaction of this id was handed over by this run
      TransactionNotHandedOver !TxId
    | -- | the settlement does not wait for this transaction
      SettlementRefused !Refusal

instance Show ObservationFailed where
    show = \case
        TransactionNotHandedOver txId ->
            "transaction-not-handed-over: " <> T.unpack (renderTransactionId txId) <> " was not handed to the provider by this run"
        SettlementRefused refusal -> "settlement-refused: " <> show refusal

instance Exception ObservationFailed

-- | The runtime over parts.
koiosRegistryRuntime :: KoiosParts -> IO RegistryRuntime
koiosRegistryRuntime parts = do
    handed <- newIORef Map.empty
    let reads' = partReads parts
        submit tx = do
            let signed = assembleSigned tx (Set.toList (tx ^. witsTxL . addrTxWitsL))
                txId = transactionId tx
            modifyIORef' handed (Map.insert txId tx)
            handoff <- partHandoff parts signed
            -- what the provider answered is decided here, from the handoff alone: a report that cannot be
            -- written (a character the terminal cannot take, a closed pipe) does not change it
            _ <- tryNode (partReport parts handoff)
            case handoffResult handoff of
                Accepted -> pure (Submitted txId)
                Refused text | handoffAttempts handoff == 1 -> pure (Rejected (TE.encodeUtf8 text))
                _ -> throwIO (HandoffUncertain (renderHandoff handoff))
        observe txId =
            readIORef handed >>= \known -> case Map.lookup txId known of
                Nothing -> throwIO (TransactionNotHandedOver txId)
                Just tx ->
                    partSettle parts tx >>= \case
                        Right Settled -> pure ()
                        Right (NotSettled unsettlement) ->
                            throwIO
                                ( TransactionUnconfirmed
                                    txId
                                    ( renderUnsettlement unsettlement
                                        <> "; the wait ends two minutes after the transaction's validity end and its last poll may run a few seconds after that"
                                    )
                                )
                        Left refusal -> throwIO (SettlementRefused refusal)
    pure
        RegistryRuntime
            { rtNetwork = Testnet
            , rtUtxosAt = readUtxosAt reads'
            , rtOutputs = readOutputs reads'
            , rtRewardRegistered = readRewardRegistered reads'
            , rtTransactions =
                TransactionRuntime
                    { trQueryProtocolParams = readProtocolParameters reads'
                    , trEvaluate = readEvaluation reads'
                    , trSign = partSign parts
                    , trSubmit = submit
                    , trObserve = observe
                    }
            , rtObserve = readObservation reads'
            , rtNowMs = partClock parts
            , rtValidityEnd = partWindow parts
            , rtFunding = singularFundingRules
            }

{- | The instance over the live transport of an access: its token read by the
transport from the file, the pinned network time of its network, the signing key
read when something is signed. Nothing is sent before it is built, and a
network without pinned time or a token file that cannot be read stops it first.
-}
openKoiosRuntime :: (Handoff -> IO ()) -> KoiosAccess -> IO (Either KoiosStartFailure RegistryRuntime)
openKoiosRuntime report access = fmap openedRuntime <$> openKoios report access

{- | The registry runtime of an access and the way to read the chain through Singular's own session: what a
command that builds with Singular's fold needs beside the runtime that signs, hands over and observes.
-}
data KoiosOpened = KoiosOpened
    { openedRuntime :: !RegistryRuntime
    , openedAcquire :: forall a. (Session NoWitness IO -> IO a) -> IO (Either AcquireFailure a)
    -- ^ a session of the latest chain state, for the length of the action
    }

-- | The runtime and the session acquirer over the live transport of an access.
openKoios :: (Handoff -> IO ()) -> KoiosAccess -> IO (Either KoiosStartFailure KoiosOpened)
openKoios report access = do
    let magic = fromIntegral (koiosNetworkMagic access)
    pinned <- resolveTimeSource magic (koiosNetworkTime access)
    case pinned of
        Left (NetworkTimeRefusal (UnknownTimeNetwork _)) -> pure (Left (NetworkNotPinned (koiosNetworkMagic access)))
        Left failure -> pure (Left (TimeSourceUnreadable (T.pack (show failure))))
        Right source@(TimeSource manifest genesis eras) ->
            case validateNetworkTime magic manifest genesis eras of
                Left failure -> pure (Left (TimeSourceUnreadable (T.pack (show failure))))
                Right time -> do
                    transport <-
                        newHttpTransport
                            (defaultHttpConfig (koiosUrl access)){httpTokenFile = koiosTokenFile access}
                    case transport of
                        Left (TokenFileUnreadable path message) -> pure (Left (TokenUnreadable (T.pack path <> ": " <> message)))
                        Left other -> pure (Left (TokenUnreadable (T.pack (show other))))
                        Right live -> do
                            let client = Koios defaultClientConfig live
                            confirmation <- newIOConfirmationRuntime
                            providerRuntime <- newIORuntime mempty (\_ -> pure ())
                            let provider = koiosProvider providerRuntime (Network magic) (pure (Right source)) client{koiosTransport = wholeAnswers (koiosTransport client)}
                            runtime <-
                                koiosRegistryRuntime
                                    KoiosParts
                                        { partReads = koiosReads client time clock
                                        , partSign = \tx ->
                                            keySourceEnvelope (koiosSigningKey access)
                                                >>= either (ioError . userError) (\envelope -> pure (signWithPaymentKey envelope tx))
                                        , partHandoff = submitHandoff client
                                        , partSettle = koiosSettlement client time (pure (Right source)) (Network magic) confirmation
                                        , partReport = report
                                        , partClock = clock
                                        , partWindow = koiosValidityEnd client (pure (Right source)) (Network magic)
                                        }
                            pure
                                (Right KoiosOpened{openedRuntime = runtime, openedAcquire = acquire provider (Latest (Network magic))})
  where
    clock = (\t -> floor (t * 1_000)) <$> getPOSIXTime
