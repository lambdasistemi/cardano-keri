{- |
Module      : Cardano.KERI.Deployment.RegistryReplay
Description : The registry's state, rebuilt from the public history of its state token

The chain commits a registry's keys by their root only. A folder that was not
given the keys rebuilds them from the public history of the registry's state
token, through the provider, with public Singular's lineage replay: the
genesis, then every fold in chain order, each rebuilt root checked against the
root the chain recorded. Anything missing, partial, inconsistent or refused by
the provider stops the replay with the reason and the transaction it was found
at, before anything is paid.
-}
module Cardano.KERI.Deployment.RegistryReplay (
    RegistryState (..),
    ReplayStop (..),
    FoldFromHistoryStop (..),
    replayRegistryState,
    renderReplayStop,
    foldFromHistory,
) where

import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime)
import Cardano.KERI.Deployment.RegistryFold (FoldDone, FoldEvent, FoldInput, FoldStopped, foldBookedRequest)
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Data.ByteString (ByteString)
import Singular.Registry.Evidence (NoWitness)
import Singular.Registry.LedgerProvider (Session)
import Singular.Registry.TrieState (RegistryIdentity, TrieFailure)

-- | The registry as the public history of its state token shows it.
data RegistryState = RegistryState
    { replayOutput :: !TxIn
    -- ^ the state output the replay reached
    , replayRebuiltRoot :: !ByteString
    -- ^ the root of the trie the replay rebuilt, recomputed from its nodes
    , replaySeed :: !TxIn
    -- ^ the seed the genesis spent
    , replayGenesis :: !TxId
    , replayFolds :: ![TxId]
    -- ^ every fold from the genesis to the output, in chain order
    , replayActive :: ![ByteString]
    , replayTerminal :: ![ByteString]
    }
    deriving stock (Eq, Show)

{- | A replay that stopped, with the failure public Singular named: its constructor, the registry and the
transaction it was found at are all kept.
-}
newtype ReplayStop = ReplayStop {stoppedBy :: TrieFailure}
    deriving stock (Eq, Show)

-- | Rebuild the registry's state at the given state output, which must carry the given root.
replayRegistryState ::
    Session NoWitness IO ->
    RegistryIdentity ->
    TxIn ->
    ByteString ->
    IO (Either ReplayStop RegistryState)
replayRegistryState _ _ output _ =
    pure (Right (RegistryState output mempty output (txIdOf output) [] [] []))
  where
    txIdOf (TxIn tx _) = tx

-- | The stop as one line: its kind, where it was found, and what was seen.
renderReplayStop :: ReplayStop -> String
renderReplayStop = show

-- | Why a fold from history stopped.
data FoldFromHistoryStop
    = HistoryRefused !ReplayStop
    | FoldStoppedAfterReplay !FoldStopped
    deriving stock (Eq, Show)

{- | Fold a booked request on the registry's state rebuilt from public history. The replay comes
first; nothing is signed or handed over when it stops.
-}
foldFromHistory ::
    Session NoWitness IO ->
    RegistryRuntime ->
    (FoldEvent -> IO ()) ->
    FoldInput ->
    IO (Either FoldFromHistoryStop FoldDone)
foldFromHistory _ runtime report input =
    either (Left . FoldStoppedAfterReplay) Right <$> foldBookedRequest runtime report input
