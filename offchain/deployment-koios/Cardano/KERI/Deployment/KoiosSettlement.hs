{- |
Module      : Cardano.KERI.Deployment.KoiosSettlement
Description : A transaction handed over has settled when its first output is visible

Settlement over the Koios ledger provider, decided as public Singular decides
it: a transaction has settled when a poll sees its first output under its exact
reference, read in its own acquisition. The polling is bounded by Singular's
window: the transaction's validity end plus two minutes, with a few seconds of
margin in the bound, so the last poll may run a few seconds after the end of
the window and a poll that sees the output then still settles. One read of
inclusion is not settlement, and none is made. A wait that ends without the
output, or a read inside it that cannot be completed, leaves the transaction
not known to have settled, and nothing is built, signed or resent. The result
names the end of the window as the time after which to look again. Nothing
calls this yet.
-}
module Cardano.KERI.Deployment.KoiosSettlement (
    Settlement (..),
    Refusal (..),
    Unsettlement (..),
    settleTransaction,
    koiosSettlement,
    renderUnsettlement,
) where

import Cardano.KERI.Deployment.KoiosRuntime (wholeAnswers)
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Api.Tx (bodyTxL, txIdTx)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL, vldtTxBodyL)
import Cardano.Ledger.BaseTypes (StrictMaybe (..))
import Cardano.Ledger.TxIn (TxId)
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.Text (Text)
import Data.Text qualified as T
import Lens.Micro ((^.))
import Singular.Provider.Koios.Client (Koios (..))
import Singular.Provider.Koios.Provider (koiosProvider)
import Singular.Provider.Koios.Runtime (newIORuntime)
import Singular.Provider.Koios.Wire qualified as Wire
import Singular.Registry.Confirmation (
    ConfirmationFailure (..),
    ConfirmationRuntime,
    confirmTransaction,
 )
import Singular.Registry.LedgerProvider (
    LedgerProvider,
    Network,
    ReadFailure,
 )
import Singular.Registry.NetworkTime (NetworkTime, NetworkTimeFailure, slotStartMs)
import Singular.Registry.TimeSource (TimeSource)
import Singular.Registry.Wait (WaitFailure (..))

-- | Why a transaction is not known to have settled.
data Unsettlement = Unsettlement
    { unsettledTransaction :: !TxId
    , unsettledBy :: !ConfirmationFailure
    -- ^ Singular's reason: the wait ended, or the read that stopped
    , unsettledDeadlineMs :: !Integer
    {- ^ the end of the window, in POSIX milliseconds: the validity end plus two
    minutes, the time after which to look again; computed from the transaction
    alone, whatever was read
    -}
    , unsettledBoundSeconds :: !(Maybe Int)
    -- ^ the bound in seconds, only when Singular's wait failure carries it
    }
    deriving stock (Show)

-- | The two results of a settlement.
data Settlement
    = -- | a poll saw the first output under its exact reference
      Settled
    | -- | the wait ended without it, or a read inside it could not be completed
      NotSettled !Unsettlement
    deriving stock (Show)

-- | A transaction this settlement does not wait for, refused before any read.
data Refusal
    = -- | no output to see, as Singular names it
      TransactionWithoutOutput !ConfirmationFailure
    | -- | no validity end, so no window: the registry builders always set one
      TransactionWithoutValidityEnd !TxId
    | -- | the validity end lies beyond the pinned network time, so it has no instant
      TransactionValidityEndOutOfTime !TxId !NetworkTimeFailure
    deriving stock (Show)

{- | Wait for the first output of a transaction to be visible under its exact
reference. A transaction without outputs, without a validity end, or whose
validity end the pinned network time cannot place, is refused by name, before
any read.

The end of the window is computed from the transaction alone: the start of the
slot its validity ends in, under the network time given, plus the two minutes
of the window. It needs no read, so no read can fail or fall back to another
instant, and every unsettled result carries it. Singular's confirmation makes
the reads it makes and no others.
-}
settleTransaction ::
    (Monad m) =>
    NetworkTime ->
    ConfirmationRuntime m ->
    LedgerProvider w m ->
    Network ->
    ConwayTx ->
    m (Either Refusal Settlement)
settleTransaction time runtime provider network tx
    | null (tx ^. bodyTxL . outputsTxBodyL) = pure (Left (TransactionWithoutOutput (ConfirmationNoOutput identity)))
    | otherwise = case invalidHereafter (tx ^. bodyTxL . vldtTxBodyL) of
        SNothing -> pure (Left (TransactionWithoutValidityEnd identity))
        SJust upper -> case slotStartMs time upper of
            Left failure -> pure (Left (TransactionValidityEndOutOfTime identity failure))
            Right start -> do
                confirmed <- confirmTransaction runtime provider network tx
                pure . Right $ case confirmed of
                    Right () -> Settled
                    Left failure ->
                        NotSettled
                            Unsettlement
                                { unsettledTransaction = identity
                                , unsettledBy = failure
                                , unsettledDeadlineMs = start + 120_000
                                , unsettledBoundSeconds = case failure of
                                    ConfirmationWaitFailure waited -> Just (waitBound waited)
                                    _ -> Nothing
                                }
  where
    identity = txIdTx tx

{- | The settlement over a Koios client: every read is Singular's Koios
provider's, and an answer the service marks as partial is refused as one.
-}
koiosSettlement ::
    Koios IO ->
    NetworkTime ->
    IO (Either ReadFailure TimeSource) ->
    Network ->
    ConfirmationRuntime IO ->
    ConwayTx ->
    IO (Either Refusal Settlement)
koiosSettlement client time loadSource network runtime tx = do
    providerRuntime <- newIORuntime mempty (\_ -> pure ())
    let whole = client{koiosTransport = wholeAnswers (koiosTransport client)}
    settleTransaction time runtime (koiosProvider providerRuntime network loadSource whole) network tx

{- | What a command says of a transaction not known to have settled: it may or
may not have reached the provider, and the end of the window is the time after
which to look again.
-}
renderUnsettlement :: Unsettlement -> Text
renderUnsettlement unsettlement =
    Wire.txIdHex (unsettledTransaction unsettlement)
        <> " may or may not have reached the provider; check it before spending again"
        <> lookAgain (unsettledDeadlineMs unsettlement)
        <> maybe "" bounded (unsettledBoundSeconds unsettlement)
  where
    lookAgain deadline = ", and look again after " <> T.pack (show deadline) <> " ms since the epoch"
    bounded seconds = " (the wait was bounded at " <> T.pack (show seconds) <> " s)"
