{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.NodeSocketRuntime
Description : The node-socket instance of 'RegistryRuntime'

This is the node-socket instance of 'RegistryRuntime': the one place that
reaches the chain through a cardano-node's socket for @ckeri registry deploy@,
@ckeri registry register@ and @ckeri registry fold@. It is unsupported for
users; the local test chain journeys run through it.

The client of the node is opened linked to the calling thread ('Linked'), as
@registry deploy@ does, or not linked ('Unlinked'), as @registry register@ and
@registry fold@ do: then nothing is delivered to the thread when the connection
ends, and each call of the node that needs it fails and says so.
-}
module Cardano.KERI.Deployment.NodeSocketRuntime (
    NodeAccess (..),
    KeySource (..),
    keySourceEnvelope,
    RegistryOpener,
    Connection (..),
    withNodeRuntime,
    observeFrom,
) where

import Cardano.KERI.Deployment.LiveRuntime (
    LiveConfig (..),
    LiveContext (..),
    rewardAccountRegistered,
    withLiveContext,
    withLiveContextEnvelope,
    withUnlinkedLiveContext,
    withUnlinkedLiveContextEnvelope,
 )
import Cardano.KERI.Deployment.RegistryChain (Observation (..), RegistryRuntime (..), whileConnected)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..))
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.BaseTypes (Network (Testnet), TxIx (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
    SlotNo (..),
    posixMsToSlotH,
    queryLedgerSnapshotH,
 )
import Control.Concurrent (threadDelay)
import Control.Exception (ErrorCall (..), IOException, catchJust, try)
import Control.Monad (unless, when)
import Data.Aeson (Value, eitherDecodeFileStrict')
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (getPOSIXTime)

{- | Where the signing key comes from: a key file the live context reads, or the
envelope of a key that was already opened. The envelope is never shown.
-}
data KeySource
    = KeyFile !FilePath
    | KeyEnvelope !Value
    deriving stock (Eq)

instance Show KeySource where
    showsPrec precedence = \case
        KeyFile path -> showParen (precedence > 10) (showString "KeyFile " . showsPrec 11 path)
        KeyEnvelope _ -> showString "KeyEnvelope <signing key>"

-- | How a command reaches the node and who pays.
data NodeAccess = NodeAccess
    { naNetworkMagic :: !Int
    , naNodeSocket :: !FilePath
    , naFundingAddress :: !Text
    , naSigningKey :: !KeySource
    , naTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

{- | The envelope of the key a source names: what a key file holds, read as the
live context reads it, or the opened envelope itself.
-}
keySourceEnvelope :: KeySource -> IO (Either String Value)
keySourceEnvelope = \case
    KeyEnvelope envelope -> pure (Right envelope)
    KeyFile path ->
        either (Left . show) id <$> try @IOException (eitherDecodeFileStrict' path)

-- | How the commands reach the node: the runtime and the paying address.
type RegistryOpener = NodeAccess -> ((RegistryRuntime, Addr) -> IO ()) -> IO ()

-- | Whether the node client's thread is linked to the thread that makes the calls.
data Connection = Linked | Unlinked

{- | The runtime over the node's socket, and the address that pays, for the
duration of an action. The connection is opened and closed around it.
-}
withNodeRuntime :: Connection -> NodeAccess -> ((RegistryRuntime, Addr) -> IO a) -> IO a
withNodeRuntime connection access use = case naSigningKey access of
    KeyEnvelope envelope -> case connection of
        Linked -> withLiveContextEnvelope envelope (config "") (\_ -> pure ()) $ \context ->
            use (runtimeOf context, liveFundingAddress context)
        Unlinked -> withUnlinkedLiveContextEnvelope envelope (config "") (\_ -> pure ()) $ \context status ->
            use (whileConnected status (runtimeOf context), liveFundingAddress context)
    KeyFile path -> case connection of
        Linked -> withLiveContext (config path) (\_ -> pure ()) $ \context ->
            use (runtimeOf context, liveFundingAddress context)
        Unlinked -> withUnlinkedLiveContext (config path) (\_ -> pure ()) $ \context status ->
            use (whileConnected status (runtimeOf context), liveFundingAddress context)
  where
    config path =
        LiveConfig
            { liveNetworkMagic = naNetworkMagic access
            , liveNodeSocket = naNodeSocket access
            , liveSigningKeyFile = path
            , liveFundingAddressText = naFundingAddress access
            , liveTimeoutSeconds = naTimeoutSeconds access
            }
    runtimeOf context =
        let provider = liveProvider context
            transactions = liveTransactionRuntime context
         in RegistryRuntime
                { rtNetwork = Testnet
                , rtUtxosAt = queryUTxOs provider
                , rtOutputs = queryUTxOByTxIn provider
                , rtRewardRegistered = rewardAccountRegistered context
                , rtTransactions = transactions{trObserve = awaitFirstOutput provider (naTimeoutSeconds access)}
                , rtObserve = observeNode provider
                , rtNowMs = clockMs
                }

-- | A transaction has settled when the node reports its first output unspent.
awaitFirstOutput :: Provider IO -> Int -> TxId -> IO ()
awaitFirstOutput provider timeoutSeconds txId = do
    started <- getCurrentTime
    let first = TxIn txId (TxIx 0)
        loop = do
            found <- queryUTxOByTxIn provider (Set.singleton first)
            unless (Map.member first found) $ do
                now <- getCurrentTime
                when (diffUTCTime now started >= fromIntegral timeoutSeconds) $
                    fail
                        ( "transaction not seen settled within "
                            <> show timeoutSeconds
                            <> " seconds"
                        )
                threadDelay 1_000_000
                loop
    loop

{- | One observation of the node, taken from one acquisition of its state: the tip, the
forecast horizon and every slot start come from the same chain point, and the machine's
clock is read once, before. The horizon is the slot of the latest instant the node's
interpreter converts, found by conversions in the same acquisition; the clock is compared
with it by arithmetic, so a clock beyond the forecast is an observation like another.
-}
observeNode :: Provider IO -> IO Observation
observeNode provider = do
    clock <- clockMs
    withAcquired provider $ \acquired ->
        observeFrom (ledgerTipSlot <$> queryLedgerSnapshotH acquired) (posixMsToSlotH acquired) clock

clockMs :: IO Integer
clockMs = (\t -> floor (t * 1_000)) <$> getPOSIXTime

{- | An observation from the three things one acquisition gives: the tip, the node's
conversion of an instant to a slot (it raises for an instant past its forecast), and one
reading of the clock. The tip is read once. An instant the node cannot convert is
treated as past its forecast.
-}
observeFrom :: IO SlotNo -> (Integer -> IO SlotNo) -> Integer -> IO Observation
observeFrom readTip toSlot clock = do
    tip <- readTip
    latest <- latestConvertible
    horizon <- toSlot latest
    when (horizon < tip) $
        fail ("the node's forecast ends at slot " <> show horizon <> ", before its tip, slot " <> show tip)
    when (tip < 2) $
        fail ("the node's tip is slot " <> show tip <> ": a slot length cannot be measured before slot 2")
    tipStart <- startOf latest tip
    before <- startOf tipStart (tip - 1)
    pure
        Observation
            { obsTipSlot = tip
            , obsTipStartMs = tipStart
            , obsSlotLengthMs = tipStart - before
            , obsClockMs = clock
            , obsHorizonSlot = horizon
            }
  where
    -- only the pin's own refusal of an instant past its forecast is a forecast: it is a plain
    -- error call "posixMsToSlot: <PastHorizon ...>" (N2C/Provider.hs). A timeout, a lost
    -- connection, a cancellation or any other failure is a failed read and leaves the observation.
    convertible instant =
        catchJust
            (\(ErrorCall message) -> if "posixMsToSlot: " `isPrefixOf` message then Just () else Nothing)
            (Just <$> toSlot instant)
            (\() -> pure Nothing)
    limit = 40_000_000_000
    -- the latest instant that converts: found from the clock, upwards or downwards
    latestConvertible =
        convertible clock >>= \case
            Just _ -> gallopUp clock 1_000
            Nothing -> gallopDown clock 1_000
    gallopUp good step
        | step > limit = pure good
        | otherwise =
            convertible (good + step) >>= \case
                Just _ -> gallopUp (good + step) (step * 2)
                Nothing -> boundary good (good + step)
    gallopDown bad step
        | step > limit = fail "the node converts no instant to a slot"
        | otherwise =
            convertible (bad - step) >>= \case
                Just _ -> boundary (bad - step) bad
                Nothing -> gallopDown (bad - step) (step * 2)
    -- the last convertible instant between one that converts and one that does not
    boundary good bad
        | bad - good <= 1 = pure good
        | otherwise = do
            let middle = (good + bad) `div` 2
            convertible middle >>= \case
                Just _ -> boundary middle bad
                Nothing -> boundary good middle
    -- the instant a slot starts: the first instant that is in it, below an instant known to be in or after it
    startOf upper slot = do
        slotAtUpper <- toSlot upper
        when (slotAtUpper < slot) $ fail ("slot " <> show slot <> " is after the instant asked from")
        lower <- searchDown upper slot 1_000
        search lower upper slot
    -- an instant the node cannot convert, before its system start, is before every slot
    below slot instant = maybe True (< slot) <$> convertible instant
    searchDown from slot step
        | step >= from = pure 0
        | otherwise = do
            isBelow <- below slot (from - step)
            if isBelow then pure (from - step) else searchDown from slot (step * 2)
    search lo hi slot
        | lo + 1 >= hi = pure hi
        | otherwise = do
            let middle = (lo + hi) `div` 2
            isBelow <- below slot middle
            if isBelow then search middle hi slot else search lo middle slot
