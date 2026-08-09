{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.ChainQuery.Settlement
Description : Post-submit settlement observation (#257 DAT-257-SETTLEMENT)

Settlement is a separate temporal capability (INV-257-SETTLEMENT): its
signature is not a 'Cardano.KERI.ChainQuery.Program.ChainQuery' operation,
polling may be sequential, and it makes no snapshot-consistency claim. It is
absent from the free operation functor (DATA-INV-257-05).

'observeSettlement's retry loop is moved verbatim (matching semantics
exactly, including "a zero-second timeout still performs one real probe")
from the former @Cardano.KERI.Deployment.Registration.awaitAsset@, now
provider-neutral: the probe itself is injected via 'SettlementObserver'.
-}
module Cardano.KERI.ChainQuery.Settlement (
    SettlementTarget (..),
    SettlementTimeoutPolicy (..),
    SettlementObserver (..),
    SettlementObservation (..),
    SettlementError (..),
    observeSettlement,
) where

import Cardano.KERI.ChainQuery.Types (ChainAsset (..), ChainAssetUtxo (..))
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Text (Text)
import Data.Time.Clock (diffUTCTime, getCurrentTime)

-- | The exact asset identity a settlement observation must match.
data SettlementTarget = SettlementTarget
    { settlementPolicy :: !Text
    , settlementAssetName :: !Text
    , settlementTxId :: !Text
    , settlementAddress :: !Text
    }
    deriving stock (Show, Eq)

-- | Poll cadence and deadline for one settlement observation.
data SettlementTimeoutPolicy = SettlementTimeoutPolicy
    { settlementTimeoutSeconds :: !Int
    , settlementPollDelayMicros :: !Int
    }
    deriving stock (Show, Eq)

{- | A provider-specific one-shot probe (DAT-257-SETTLEMENT: "provider-specific
construction"). Injected by the caller; 'observeSettlement' itself is
provider-neutral and knows nothing about how the probe is constructed.
-}
newtype SettlementObserver effect = SettlementObserver
    { probeSettlement :: Text -> Text -> effect [ChainAssetUtxo]
    }

-- | The exact matched output that satisfied a settlement target.
newtype SettlementObservation = SettlementObservation
    { settlementObservedUtxo :: ChainAssetUtxo
    }
    deriving stock (Show, Eq)

-- | The exact asset identity that was not observed before the deadline.
newtype SettlementError
    = SettlementTimeout SettlementTarget
    deriving stock (Show, Eq)

{- | Poll a settlement probe until it matches the target or the timeout
policy's deadline elapses. A zero-second timeout still performs one real
probe before returning the typed timeout.
-}
observeSettlement ::
    SettlementObserver IO ->
    SettlementTarget ->
    SettlementTimeoutPolicy ->
    IO (Either SettlementError SettlementObservation)
observeSettlement observer target policy = do
    started <- getCurrentTime
    let loop = do
            queried <-
                try (probeSettlement observer (settlementPolicy target) (settlementAssetName target))
            case queried of
                Right utxos ->
                    case filter matches utxos of
                        match : _ -> pure (Right (SettlementObservation match))
                        [] -> retry started
                Left (_ :: SomeException) -> retry started
        matches utxo =
            chainAssetTxId utxo == settlementTxId target
                && chainAssetAddress utxo == settlementAddress target
                && any matchesAsset (chainAssetList utxo)
        matchesAsset asset =
            chainAssetPolicy asset == settlementPolicy target
                && chainAssetName asset == settlementAssetName target
                && chainAssetQuantity asset == 1
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt >= fromIntegral (settlementTimeoutSeconds policy)
                then pure (Left (SettlementTimeout target))
                else threadDelay (settlementPollDelayMicros policy) >> loop
    loop
