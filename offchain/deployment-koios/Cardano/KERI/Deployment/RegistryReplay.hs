{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReplay
Description : The registry's state, rebuilt from the public history of its state token

The chain commits a registry's keys by their root only. A folder that was not
given the keys rebuilds them from the public history of the registry's state
token, through the provider, with public Singular's lineage replay: the
genesis, then every fold in chain order, each rebuilt root checked against the
root the chain recorded. Anything missing, partial, inconsistent or refused by
the provider stops the replay with the failure Singular names, the registry and
the transaction it was found at, before anything is paid.
-}
module Cardano.KERI.Deployment.RegistryReplay (
    RegistryState (..),
    ReplayStop (..),
    FoldFromHistoryStop (..),
    replayRegistryState,
    renderReplayStop,
    singularIdentity,
    foldFromHistory,
) where

import Cardano.KERI.AID.Application qualified as KERI
import Cardano.KERI.Deployment.Registry (RegistryScripts (..))
import Cardano.KERI.Deployment.RegistryChain (Loaded (..), Refusal (..), RegistryRuntime, findStateOutput, loadDeployment, tryNode)
import Cardano.KERI.Deployment.RegistryFold (FoldCause (..), FoldDone, FoldEvent, FoldInput (..), FoldStopped (..), foldBookedRequest)
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.KERI.Deployment.RegistryTransactions (RegistryDeployment (..))
import Cardano.Ledger.Mary.Value (AssetName (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Singular.Registry.Evidence (NoWitness)
import Singular.Registry.Ledger (Root (..))
import Singular.Registry.LedgerProvider (Session (..))
import Singular.Registry.TrieState (
    Incomplete (..),
    Leaf (..),
    PublicLineage (..),
    RegistryIdentity (..),
    StatePoint (..),
    StatePolicyId (..),
    TrieFailure (..),
    TrieSelection (..),
    TrieState (..),
    leafAt,
    trieLineage,
    trieRoot,
 )
import Singular.State.Assemble (inlineDatumOf)
import Singular.State.Lineage (registryTrieState)
import Singular.State.Records (decodeStateDatum)

-- | The registry as the public history of its state token shows it.
data RegistryState = RegistryState
    { replayOutput :: !TxIn
    -- ^ the state output the replay reached
    , replayRoot :: !ByteString
    -- ^ the root of the registry's trie, which Singular's replay rebuilt from the history and checked against the root asked for
    , replayGenesis :: !TxId
    , replayFolds :: ![TxId]
    -- ^ every fold from the genesis to the output, in chain order
    , replayActive :: ![ByteString]
    , replayTerminal :: ![ByteString]
    }
    deriving stock (Eq, Show)

{- | A replay that stopped, with the failure public Singular named: its constructor, the
registry and the transaction it was found at are all kept.
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
replayRegistryState session identity output root =
    withTrieState (registryTrieState session) selection classify >>= \case
        Left failure -> pure (Left (ReplayStop failure))
        Right (Left failure) -> pure (Left (ReplayStop failure))
        Right (Right state) -> pure (Right state)
  where
    -- the keys and the lineage are Singular's own, read from the snapshot its replay serves; each key's leaf is Singular's
    classify snapshot = case trieLineage snapshot of
        Nothing -> pure (Left (HistoryIncomplete identity Nothing MissingTransaction))
        Just lineage -> do
            leaves <- traverse (\key -> fmap ((,) key) <$> leafAt snapshot key) (lineageKeys lineage)
            pure $ case sequence leaves of
                Left failure -> Left failure
                Right classified ->
                    Right
                        RegistryState
                            { replayOutput = output
                            , replayRoot = let Root verified = trieRoot snapshot in verified
                            , replayGenesis = lineageCreate lineage
                            , replayFolds = lineageFolds lineage
                            , replayActive = [key | (key, Active) <- classified]
                            , replayTerminal = [key | (key, Terminal) <- classified]
                            }
    selection =
        TrieSelection
            { trieSelectionIdentity = identity
            , trieSelectionPoint = StatePoint (sessionId session) (sessionBinding session) output
            , trieSelectionRoot = Root root
            }

-- | The stop as one line, as Singular's failure shows it.
renderReplayStop :: ReplayStop -> String
renderReplayStop (ReplayStop failure) = show failure

-- | Why a fold from history stopped.
data FoldFromHistoryStop
    = -- | the replay stopped; nothing was signed or handed over
      HistoryRefused !ReplayStop
    | FoldStoppedAfterReplay !FoldStopped
    deriving stock (Eq, Show)

{- | Fold a booked request on the registry's state rebuilt from public history, in place of a
supplied file. The live state output and its root are read from the node, the history through the
session; the replay runs first, and nothing is signed or handed over when it stops. The fold then
checks again, as it always did, that the state it builds on is the one the chain holds.
-}
foldFromHistory ::
    Session NoWitness IO ->
    RegistryRuntime ->
    (FoldEvent -> IO ()) ->
    FoldInput ->
    IO (Either FoldFromHistoryStop FoldDone)
foldFromHistory session runtime report input =
    tryNode (loadDeployment runtime (foldBlueprint input) (foldIdentity input) (foldRecord input)) >>= \case
        Left failure -> stopped (FoldNodeFailed (show failure))
        Right (Left refusal) -> stopped (FoldRefused refusal)
        Right (Right loaded) -> do
            let deployment = loadedDeployment loaded
            tryNode (findStateOutput runtime deployment) >>= \case
                Left failure -> stopped (FoldNodeFailed (show failure))
                Right Nothing -> stopped (FoldRefused (StaleOrUnavailableRegistryState Nothing))
                Right (Just (stateIn, stateOut)) -> case inlineDatumOf stateOut >>= decodeStateDatum of
                    Nothing -> stopped (FoldRefused (StaleOrUnavailableRegistryState Nothing))
                    Just root ->
                        replayRegistryState session (singularIdentity (scriptsRegistry (deploymentScripts deployment))) stateIn root >>= \case
                            Left stop -> pure (Left (HistoryRefused stop))
                            Right state ->
                                either (Left . FoldStoppedAfterReplay) Right
                                    <$> foldBookedRequest runtime report input{foldSnapshot = snapshotOf state}
  where
    stopped cause = pure (Left (FoldStoppedAfterReplay (FoldStopped cause Nothing Nothing)))
    snapshotOf state =
        Snapshot
            { snapshotSuppliedBy = "the replay of the state token's public history"
            , snapshotActive = replayActive state
            , snapshotTerminal = replayTerminal state
            }

-- | The registry as Singular names it.
singularIdentity :: KERI.RegistryIdentity -> RegistryIdentity
singularIdentity (KERI.RegistryIdentity policy name) =
    RegistryIdentity (StatePolicyId policy) (AssetName (SBS.toShort name))
