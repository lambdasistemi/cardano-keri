{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReplaySpec
Description : the registry's state is rebuilt from the public history of its state token, and a fold that cannot rebuild it stops before it spends

The history is the one a test chain accepted: the deployment's own transactions, two
real folds of two identities and, for the terminal edge, one test-built terminating fold.
Each transaction is served with its inputs and references resolved, as a provider's history
read serves it. This is a component check: it shows what the replay returns and what the
caller does with a refusal. It is not the installed command on a local chain, and the
terminating fold is not the installed fold.
-}
module Cardano.KERI.Deployment.RegistryReplaySpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes, hashToBytes)
import Cardano.KERI.AID.Application (
    RegistryIdentity (..),
    activeTokenName,
    stateTokenName,
 )
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.E2E.Datum (rawInlineData)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.Deployment.RecordedHistory
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), txInOfReference)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (noFaults, walletOutputs)
import Cardano.KERI.Deployment.RegistryFold
import Cardano.KERI.Deployment.RegistryReplay
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..))
import Cardano.KERI.Deployment.RegistryTransactions (registryRootOf)
import Cardano.Ledger.Api.Tx (bodyTxL, txIdTx)
import Cardano.Ledger.Api.Tx.Body (mintTxBodyL, outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut, addrTxOutL, coinTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.TxInfo (transAddr)
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Lens.Micro ((^.))
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.V3 qualified as PV3
import Singular.Registry.Evidence (NoWitness)
import Singular.Registry.Ledger (Root (..))
import Singular.Registry.LedgerProvider (Asset, HistoryBlock, HistoryFailure (..), ReadFailure (..), Session)
import Singular.Registry.TrieState (Incomplete (..), Mismatch (..), Parting (..), Staleness (..), TrieFailure (..))
import Singular.State.Preimage qualified as Singular
import Singular.State.Records (Change (..))
import Test.Hspec

-- | What was live before the first transaction of the world.
initialLive :: Map TxIn (TxOut ConwayEra)
initialLive = Map.fromList (walletOutputs <> folderOutputs)

stateAsset :: World -> Asset
stateAsset world =
    ( PolicyID (ScriptHash (fromJust (hashFromBytes (registryStatePolicy (registryOf world)))))
    , AssetName (SBS.toShort (registryName (registryOf world)))
    )

seedOf :: World -> TxIn
seedOf = txInOfReference . riSeed . deployedIdentity . worldDeployed

-- | A registry with two identities booked and the first one folded by the installed builder.
data Scene = Scene
    { sceneWorld :: World
    , sceneFirstRequest :: TxIn
    , sceneSecondRequest :: TxIn
    , sceneFirstKey :: ByteString
    , sceneSecondKey :: ByteString
    }

inputOf :: World -> TxIn -> Snapshot -> FoldInput
inputOf world request snapshot =
    FoldInput
        { foldBlueprint = worldBlueprint world
        , foldIdentity = deployedIdentity (worldDeployed world)
        , foldRecord = deployedRecord (worldDeployed world)
        , foldRequestOutput = request
        , foldSnapshot = snapshot
        , foldPayerAddress = folderAddress
        }

emptySnapshot :: Snapshot
emptySnapshot = Snapshot "an empty registry" [] []

booked :: IO Scene
booked = do
    world <- newWorld 1_000
    single <- loadExport "kli-export-single.cesr"
    multi <- loadExport "kli-export-2-of-5.cesr"
    (r1, _) <- bookDirectly world single
    (r2, _) <- bookDirectly world multi
    pure (Scene world r1 r2 (keyOf single) (keyOf multi))

-- | The first identity folded by the installed builder, on the snapshot of the empty registry.
withFirstFolded :: IO Scene
withFirstFolded = do
    scene <- booked
    let world = sceneWorld scene
    outcome <- foldBookedRequest (runtimeOf noFaults world) (const (pure ())) (inputOf world (sceneFirstRequest scene) emptySnapshot)
    _ <- either (fail . show) pure outcome
    pure scene

-- | Both folded, one after the other, each on the snapshot the first fold left.
withBothFolded :: IO Scene
withBothFolded = do
    scene <- booked
    foldBoth scene
    pure scene

-- | Fold the two booked requests by the installed builder.
foldBoth :: Scene -> IO ()
foldBoth scene = do
    let world = sceneWorld scene
        runtime = runtimeOf noFaults world
    first' <- foldBookedRequest runtime (const (pure ())) (inputOf world (sceneFirstRequest scene) emptySnapshot)
    done <- either (fail . show) pure first'
    second' <- foldBookedRequest runtime (const (pure ())) (inputOf world (sceneSecondRequest scene) (doneSnapshot done))
    _ <- either (fail . show) pure second'
    pure ()

historyOf :: World -> IO [ConwayTx]
historyOf = accepted

blocksOf :: [ConwayTx] -> [HistoryBlock]
blocksOf = recordedBlocks initialLive

rootOfOutput :: TxOut ConwayEra -> ByteString
rootOfOutput out = case rawInlineData out of
    Just (Constr 0 [B root]) -> root
    other -> error ("not a state datum: " <> show other)

-- | The state-token transactions of the history, in order: the genesis, then each fold.
stateTransactions :: World -> [ConwayTx] -> [ConwayTx]
stateTransactions world = filter (touchesToken (stateAsset world))

replaying :: World -> Session NoWitness IO -> TxIn -> ByteString -> IO (Either ReplayStop RegistryState)
replaying world session = replayRegistryState session (singularIdentityOf (registryOf world))

spec :: Spec
spec = describe "#558 the registry's state rebuilt from the public history of its state token" $ do
    describe "registrations" $ do
        it "rebuilds the root, the ordered genesis and folds, the seed and both active keys of a registry two identities were folded into" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            Just (live, liveOut) <- stateOutputOf world
            let onChain = rootOfOutput liveOut
                touching = stateTransactions world txs
            replayed <- replaying world (recordedSession (blocksOf txs)) live onChain
            state <- either (fail . renderReplayStop) pure replayed
            -- the root is the one the chain holds and the one our own trie computes, each read apart
            replayRoot state `shouldBe` onChain
            replayRoot state `shouldBe` registryRootOf [sceneFirstKey scene, sceneSecondKey scene] []
            -- the genesis, then each fold, in chain order
            map txIdTx touching `shouldBe` (replayGenesis state : replayFolds state)
            length (replayFolds state) `shouldBe` 2
            replayOutput state `shouldBe` live
            -- both keys are active, none terminal
            replayActive state `shouldMatchList` [sceneFirstKey scene, sceneSecondKey scene]
            replayTerminal state `shouldBe` []

    describe "a terminal edge (replay recognition only: the terminating fold is built by the test, not the installed fold)" $ do
        let terminated = do
                scene <- withBothFolded
                let world = sceneWorld scene
                Just (stateIn, stateOut) <- stateOutputOf world
                let root' = registryRootOf [sceneSecondKey scene] [sceneFirstKey scene]
                    ending = terminatingFold (seedOf world) (stateIn, stateOut) (sceneFirstRequest scene) (sceneFirstKey scene) root'
                prior <- historyOf world
                pure (scene, prior, ending, root')
        it "classifies the terminated key terminal and the other active, and rebuilds the root of both" $ do
            (scene, prior, ending, root') <- terminated
            let world = sceneWorld scene
                live = TxIn (txIdTx ending) (TxIx 0)
            replayed <- replaying world (recordedSession (blocksOf (prior <> [ending]))) live root'
            state <- either (fail . renderReplayStop) pure replayed
            replayRoot state `shouldBe` root'
            replayTerminal state `shouldBe` [sceneFirstKey scene]
            replayActive state `shouldBe` [sceneSecondKey scene]
            length (replayFolds state) `shouldBe` 3
        it "control: the same history without the terminating transaction keeps that key active" $ do
            (scene, prior, _, _) <- terminated
            let world = sceneWorld scene
            Just (live, liveOut) <- stateOutputOf world
            replayed <- replaying world (recordedSession (blocksOf prior)) live (rootOfOutput liveOut)
            state <- either (fail . renderReplayStop) pure replayed
            replayTerminal state `shouldBe` []
            replayActive state `shouldMatchList` [sceneFirstKey scene, sceneSecondKey scene]
        it "control: the edge kind is bound: a registration where the history terminates does not chain" $ do
            (scene, prior, ending, root') <- terminated
            let world = sceneWorld scene
                registers = withFoldRedeemer (map (\case Terminate r k p -> Register r k 0 0 p; other -> other)) ending
                live = TxIn (txIdTx registers) (TxIx 0)
            replayed <- replaying world (recordedSession (blocksOf (prior <> [registers]))) live root'
            case replayed of
                Left (ReplayStop (RootDoesNotChain who (Just at) (RootsPart _ (Root recorded)))) -> do
                    who `shouldBe` singularIdentityOf (registryOf world)
                    at `shouldBe` txIdTx registers
                    recorded `shouldBe` root'
                other -> expectationFailure ("not the root comparison: " <> show other)

    describe "a history that is partial, inconsistent or refused stops with its own reason" $ do
        let liveOf world = do
                Just (live, liveOut) <- stateOutputOf world
                pure (live, rootOfOutput liveOut)
            registryOfWorld = singularIdentityOf . registryOf
            provider why = ProviderHistoryFailure (HistoryReadFailure (BackendReadFailure why))
            stopped :: Either ReplayStop RegistryState -> IO TrieFailure
            stopped = \case
                Left (ReplayStop failure) -> pure failure
                Right state -> expectationFailure ("the replay did not stop: " <> show state) >> fail "no stop"
        it "a stream that fails after a successful prefix keeps the provider's cause" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (live, root) <- liveOf world
            replayed <- replaying world (streamFailingAfter 2 "a later page failed" (blocksOf txs)) live root
            stopped replayed >>= (`shouldBe` HistoryIncomplete (registryOfWorld world) Nothing (provider "a later page failed"))
        it "a first read that fails keeps the provider's cause" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            (live, root) <- liveOf world
            replayed <- replaying world (failingSession "the provider is down") live root
            stopped replayed >>= (`shouldBe` HistoryIncomplete (registryOfWorld world) Nothing (provider "the provider is down"))
        it "a history without the genesis has no transaction that mints the token" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (live, root) <- liveOf world
            (genesis, _) <- genesisAndFolds world txs
            replayed <- replaying world (recordedSession (blocksOf (filter (/= genesis) txs))) live root
            stopped replayed >>= (`shouldBe` HistoryIncomplete (registryOfWorld world) Nothing MissingTransaction)
        it "a history missing the middle fold stops at the fold after it, outside the lineage" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (live, root) <- liveOf world
            (_, [firstFold, secondFold]) <- genesisAndFolds world txs
            replayed <- replaying world (recordedSession (blocksOf (filter (/= firstFold) txs))) live root
            stopped replayed >>= (`shouldBe` HistoryIncomplete (registryOfWorld world) (Just (txIdTx secondFold)) OutsideLineage)
        it "a fold whose redeemer disagrees with the root it wrote does not chain, at that fold, against the recorded root" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (live, root) <- liveOf world
            (_, [_, secondFold]) <- genesisAndFolds world txs
            let altered = withFoldRedeemer (map (\c -> c{changeKey = BS.replicate 44 0x41})) secondFold
                served = map (\tx -> if tx == secondFold then altered else tx) txs
            txIdTx altered `shouldBe` txIdTx secondFold
            replayed <- replaying world (recordedSession (blocksOf served)) live root
            stopped replayed >>= \case
                RootDoesNotChain who (Just at) (RootsPart rebuilt (Root recorded)) -> do
                    who `shouldBe` registryOfWorld world
                    at `shouldBe` txIdTx secondFold
                    recorded `shouldBe` root
                    rebuilt `shouldNotBe` Root root
                other -> expectationFailure ("not the root comparison: " <> show other)
        it "a root other than the rebuilt one for the selected output is stale, naming both" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (live, root) <- liveOf world
            let claimed = registryRootOf [sceneFirstKey scene] []
            replayed <- replaying world (recordedSession (blocksOf txs)) live claimed
            stopped replayed >>= (`shouldBe` StaleState (registryOfWorld world) Nothing (StaleRoot (Root claimed) (Root root)))
        it "positive control: an earlier output of the lineage with its own root is a valid selection of the pinned replay" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (_, [firstFold, _]) <- genesisAndFolds world txs
            replayed <- replaying world (recordedSession (blocksOf txs)) (stateRefOf world firstFold) (registryRootOf [sceneFirstKey scene] [])
            state <- either (fail . renderReplayStop) pure replayed
            replayActive state `shouldBe` [sceneFirstKey scene]
            length (replayFolds state) `shouldBe` 1
        it "coherent material of another registry, delivered despite the policy asked for, reaches no genesis: nothing mints the token selected" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
                other = (registryOf world){registryStatePolicy = BS.replicate 28 0x07}
            txs <- historyOf world
            (live, root) <- liveOf world
            let otherBlocks = blocksOf (stateTransactions world txs)
            (session, delivered) <- deliveringRegardless otherBlocks
            replayed <- replayRegistryState session (singularIdentityOf other) live root
            -- the otherBlocks blocks were delivered to the replay: genesis and both folds, not an empty stream
            delivered >>= (`shouldBe` length otherBlocks)
            length otherBlocks `shouldBe` 3
            stopped replayed >>= (`shouldBe` HistoryIncomplete (singularIdentityOf other) Nothing MissingTransaction)

    describe "the fold takes the replayed state, and stops before it spends when the replay does" $ do
        let attempt world session request = do
                (counted, readsMade) <- countingHistory session
                events <- newIORef []
                sent0 <- submissionsMade world
                outcome <- foldFromHistory counted (runtimeOf noFaults world) (\e -> modifyIORef' events (e :)) (inputOf world request emptySnapshot)
                sent1 <- submissionsMade world
                seen <- reverse <$> readIORef events
                reads' <- readsMade
                pure (outcome, seen, sent1 - sent0, reads')
            refusedWith expected world session request = do
                (outcome, seen, submitted, reads') <- attempt world session request
                -- the replay read the history before it refused, and nothing was handed over
                reads' `shouldSatisfy` (>= 1)
                case outcome of
                    Left (HistoryRefused (ReplayStop failure)) -> failure `shouldBe` expected
                    other -> expectationFailure ("not refused by the replay: " <> show other)
                [() | FoldHandingOff{} <- seen] `shouldBe` []
                [() | FoldSettled{} <- seen] `shouldBe` []
                submitted `shouldBe` 0
            who = singularIdentityOf . registryOf
        it "folds the second identity on the state rebuilt from history: history read, one handoff, one submission, settlement, both keys active" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (outcome, seen, submitted, reads') <- attempt world (recordedSession (blocksOf txs)) (sceneSecondRequest scene)
            done <- either (fail . show) pure outcome
            reads' `shouldSatisfy` (>= 1)
            [() | FoldHandingOff{} <- seen] `shouldBe` [()]
            [() | FoldSettled{} <- seen] `shouldBe` [()]
            submitted `shouldBe` 1
            snapshotActive (doneSnapshot done) `shouldMatchList` [sceneFirstKey scene, sceneSecondKey scene]
        it "stops before any handoff when the provider fails after a prefix, with the provider's cause" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
            txs <- historyOf world
            refusedWith
                (HistoryIncomplete (who world) Nothing (ProviderHistoryFailure (HistoryReadFailure (BackendReadFailure "a later page failed"))))
                world
                (streamFailingAfter 1 "a later page failed" (blocksOf txs))
                (sceneSecondRequest scene)
        it "stops before any handoff when the history lacks its genesis" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (genesis, _) <- genesisAndFolds world txs
            refusedWith (HistoryIncomplete (who world) Nothing MissingTransaction) world (recordedSession (blocksOf (filter (/= genesis) txs))) (sceneSecondRequest scene)
        it "stops before any handoff when the provider's first read fails, with its cause" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
            refusedWith
                (HistoryIncomplete (who world) Nothing (ProviderHistoryFailure (HistoryReadFailure (BackendReadFailure "the provider is down"))))
                world
                (failingSession "the provider is down")
                (sceneSecondRequest scene)
        it "stops before any handoff when a fold in the middle of the history is missing" $ do
            scene <- withBothFolded
            let world = sceneWorld scene
            single <- loadExport "kli-export-single.cesr"
            (third, _) <- bookDirectly world single
            txs <- historyOf world
            (_, [firstFold, secondFold]) <- genesisAndFolds world txs
            refusedWith
                (HistoryIncomplete (who world) (Just (txIdTx secondFold)) OutsideLineage)
                world
                (recordedSession (blocksOf (filter (/= firstFold) txs)))
                third
        it "stops before any handoff when the root the node reports for its state output is not the one the history rebuilds" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
                claimed = registryRootOf [sceneSecondKey scene] []
                rebuilt = registryRootOf [sceneFirstKey scene] []
            txs <- historyOf world
            setRegistryRoot world [sceneSecondKey scene] []
            Just (_, liveOut) <- stateOutputOf world
            rootOfOutput liveOut `shouldBe` claimed
            refusedWith
                (StaleState (who world) Nothing (StaleRoot (Root claimed) (Root rebuilt)))
                world
                (recordedSession (blocksOf txs))
                (sceneSecondRequest scene)
        it "stops before any handoff when a fold's redeemer disagrees with its root" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
            txs <- historyOf world
            Just (_, liveOut) <- stateOutputOf world
            (_, [firstFold]) <- genesisAndFolds world txs
            let altered = withFoldRedeemer (map (\c -> c{changeKey = BS.replicate 44 0x41})) firstFold
            (outcome, seen, submitted, reads') <-
                attempt world (recordedSession (blocksOf (map (\tx -> if tx == firstFold then altered else tx) txs))) (sceneSecondRequest scene)
            reads' `shouldSatisfy` (>= 1)
            case outcome of
                Left (HistoryRefused (ReplayStop (RootDoesNotChain w (Just at) (RootsPart _ (Root recorded))))) -> do
                    w `shouldBe` who world
                    at `shouldBe` txIdTx firstFold
                    recorded `shouldBe` rootOfOutput liveOut
                other -> expectationFailure ("not the root comparison: " <> show other)
            seen `shouldBe` []
            submitted `shouldBe` 0
        it "stops before any handoff when the history stops short of the live state the node reports on its own" $ do
            scene <- withFirstFolded
            let world = sceneWorld scene
            txs <- historyOf world
            (_, [firstFold]) <- genesisAndFolds world txs
            -- the node's live output, read apart from the history the replay is given
            Just (live, _) <- stateOutputOf world
            live `shouldBe` stateRefOf world firstFold
            let TxIn selected _ = live
            refusedWith (WrongRegistry (who world) (Just selected) SelectionNotState) world (recordedSession (blocksOf (filter (/= firstFold) txs))) (sceneSecondRequest scene)

    describe "the names the replay and our builders agree on (each side derived apart)" $ do
        it "the state token, the active tokens and the registration approvals are the same assets in Singular's derivation and in the transactions" $ do
            scene <- booked
            let world = sceneWorld scene
                runtime = runtimeOf noFaults world
                registry = registryOf world
                singular = singularIdentityOf registry
                singularName (AssetName n) = SBS.fromShort n
                appPolicy = applicationPolicyOf world
                requestRefs = [sceneFirstRequest scene, sceneSecondRequest scene]
            -- the booking outputs, observed before the folds spend them, and the mints that made them
            observed <- rtOutputs runtime (Set.fromList requestRefs)
            Map.keys observed `shouldMatchList` requestRefs
            bookingTxs <- accepted world
            let minted = [(n, q) | tx <- bookingTxs, (n, q) <- mintedUnder appPolicy tx, q > 0]
            foldBoth scene
            -- the state token: Singular's name of the seed against ours against the asset the deployment minted
            singularName (Singular.stateTokenName (seedOf world)) `shouldBe` stateTokenName (riSeed (deployedIdentity (worldDeployed world)))
            singularName (Singular.stateTokenName (seedOf world)) `shouldBe` registryName registry
            Just (_, stateOut) <- stateOutputOf world
            heldNames (registryStatePolicy registry) stateOut `shouldBe` [(registryName registry, 1)]
            -- the active token of each key, and the approval the booking minted, against the holding the fold delivered
            forM_ (zip requestRefs [sceneFirstKey scene, sceneSecondKey scene]) $ \(ref, key) -> do
                singularName (Singular.activeTokenName singular key) `shouldBe` activeTokenName registry key
                held <- checkpointHolding world key
                case held of
                    [(_, holding)] -> do
                        heldNames (registryStatePolicy registry) holding `shouldBe` [(activeTokenName registry key, 1)]
                        let datum = fromJust (rawInlineData holding)
                            Coin deposit = holding ^. coinTxOutL
                            preimage = Singular.registrationPreimage key singular (fromJust (transAddr (holding ^. addrTxOutL))) (Singular.initialDatumHash datum) (PV3.Lovelace deposit)
                            derived = singularName (Singular.approvalName preimage)
                        -- the booked output exists, holds exactly one approval, and it is the one derived apart
                        out <- maybe (fail ("the booking output " <> show ref <> " was not observed")) pure (Map.lookup ref observed)
                        heldNames appPolicy out `shouldBe` [(derived, 1)]
                        -- and the booking's actual mint carries that name with quantity one
                        filter ((== derived) . fst) minted `shouldBe` [(derived, 1)]
                    other -> expectationFailure ("expected one holding, found " <> show (length other))

-- | The names and quantities of the tokens an output holds under a policy.
heldNames :: ByteString -> TxOut ConwayEra -> [(ByteString, Integer)]
heldNames policy out = case out ^. valueTxOutL of
    MaryValue _ (MultiAsset assets) ->
        [ (SBS.fromShort n, q)
        | (PolicyID (ScriptHash h), names) <- Map.toList assets
        , hashBytes h == policy
        , (AssetName n, q) <- Map.toList names
        ]
  where
    hashBytes = hashToBytes

applicationPolicyOf :: World -> ByteString
applicationPolicyOf = rlApplicationPolicy . riRelease . deployedIdentity . worldDeployed

-- | The genesis, then each fold, of the state token's history.
genesisAndFolds :: World -> [ConwayTx] -> IO (ConwayTx, [ConwayTx])
genesisAndFolds world txs = case stateTransactions world txs of
    genesis : folds -> pure (genesis, folds)
    [] -> fail "the history holds no transaction of the state token"

-- | The output of a transaction that holds the registry's state token.
stateRefOf :: World -> ConwayTx -> TxIn
stateRefOf world tx =
    case [ TxIn (txIdTx tx) (TxIx ix)
         | (ix, out) <- zip [0 ..] (toList (tx ^. bodyTxL . outputsTxBodyL))
         , holdsToken (registryStatePolicy registry) (registryName registry) out
         ] of
        [held] -> held
        other -> error ("expected one state output, found " <> show (length other))
  where
    registry = registryOf world

-- | The names and quantities a transaction mints or burns under a policy.
mintedUnder :: ByteString -> ConwayTx -> [(ByteString, Integer)]
mintedUnder policy tx = case tx ^. bodyTxL . mintTxBodyL of
    MultiAsset assets ->
        [ (SBS.fromShort n, q)
        | (PolicyID (ScriptHash h), names) <- Map.toList assets
        , hashToBytes h == policy
        , (AssetName n, q) <- Map.toList names
        ]
