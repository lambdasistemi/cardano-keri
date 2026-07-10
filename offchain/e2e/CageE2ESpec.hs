{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CageE2ESpec
Description : Live-boundary withDevnet Phase-2 smoke for the hardened #99 cage

Starts a real @cardano-node@ devnet (cardano-node-clients' @devnet@
sublibrary, 'withDevnet'), mints a hardened #99 cage thread token, opens a
value-write request, then builds a @Modify@ transaction and SUBMITS it,
asserting it SETTLES on-chain.

Settlement is proven by a BOUNDED POLL (NOTE-006), not a fixed sleep: for
each tx we compute its 'TxId' locally and poll @queryUTxOByTxIn@ for a
CONCRETE output of THAT tx until it appears or the retry bound is
exhausted. The Modify's continuing-state / advanced value-trie root check
is bound to the Modify tx's own output — so a Modify that never lands (a
Phase-2 rejection) fails at the exhausted settlement poll, carrying the
real node diagnostic. The tx id and per-redeemer execution units are the
recorded settlement evidence.
-}
module CageE2ESpec (spec) where

import Control.Concurrent (threadDelay)
import Data.ByteString.Char8 qualified as B8
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Set qualified as Set
import System.Environment (lookupEnv)
import System.IO (
    BufferMode (LineBuffering),
    hPutStrLn,
    hSetBuffering,
    stderr,
    stdout,
 )
import System.Timeout (timeout)
import Test.Hspec

import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx (txIdTx)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut)
import Cardano.Ledger.TxIn (TxId, TxIn (..))

import Cardano.Node.Client.E2E.Setup (
    addKeyWitness,
    genesisAddr,
    genesisSignKey,
    keyHashFromSignKey,
    withDevnet,
 )
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (..))

import CageTxBuilder

spec :: Spec
spec =
    around withCageDevnet $
        describe "#99 cage withDevnet Phase-2 smoke" $
            it
                "settles a hardened Modify on a real cardano-node"
                cageModifySettles

type DevnetEnv = (CageEnv, Addr)

{- | Bracket a real cardano-node devnet and construct the cage environment
from the flake-provided immutable blueprint path (@KERI_CAGE_BLUEPRINT@).
-}
withCageDevnet :: (DevnetEnv -> IO ()) -> IO ()
withCageDevnet action = do
    bp <-
        lookupEnv "KERI_CAGE_BLUEPRINT"
            >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
    withDevnet $ \lsq ltxs -> do
        env <- mkCageEnv bp lsq ltxs
        action (env, genesisAddr)

requireJust :: String -> Maybe a -> IO a
requireJust msg = maybe (fail msg) pure

-- | Retry budget for settlement polling: ~40 slots at ~1s block time.
pollAttempts :: Int
pollAttempts = 40

{- | Bounded settlement poll: look for the first output of @txId@ (over the
candidate indices) that satisfies @accept@, retrying until it appears or
the bound is exhausted. No unconditional sleep — returns as soon as the
node reports the output. Returns 'Nothing' on exhaustion.
-}
pollOutput ::
    Provider IO ->
    TxId ->
    [Integer] ->
    (TxOut ConwayEra -> Bool) ->
    IO (Maybe (TxIn, TxOut ConwayEra))
pollOutput prov txId indices accept = go pollAttempts
  where
    candidates = [TxIn txId (TxIx (fromInteger i)) | i <- indices]
    go n
        | n <= 0 = pure Nothing
        | otherwise = do
            found <-
                withinSecs 30 "queryUTxOByTxIn" $
                    queryUTxOByTxIn prov (Set.fromList candidates)
            case find (accept . snd) (Map.toList found) of
                Just hit -> pure (Just hit)
                Nothing -> threadDelay 1_000_000 >> go (n - 1)

{- | Progress diagnostic on stderr so the run's position is always visible
(a stall before submission is then distinguishable from a Phase-2 result).
-}
dbg :: String -> IO ()
dbg = hPutStrLn stderr . ("[e2e] " <>)

{- | Bound a node interaction so a never-returning query/await fails loudly
instead of hanging the whole smoke.
-}
withinSecs :: Int -> String -> IO a -> IO a
withinSecs secs label act =
    timeout (secs * 1_000_000) act
        >>= maybe
            (failWith (label <> ": timed out after " <> show secs <> "s"))
            pure

{- | Await the genesis wallet becoming funded/queryable, bounded, so a slow
devnet warm-up does not hang the seed query.
-}
awaitFunds :: Provider IO -> Addr -> IO [(TxIn, TxOut ConwayEra)]
awaitFunds prov addr = awaitWalletCount prov addr 1

-- | Await the wallet holding at least @n@ UTxOs (bounded), returning them.
awaitWalletCount ::
    Provider IO -> Addr -> Int -> IO [(TxIn, TxOut ConwayEra)]
awaitWalletCount prov addr n = go (40 :: Int)
  where
    go k
        | k <= 0 =
            failWith ("wallet never reached " <> show n <> " UTxOs")
        | otherwise = do
            us <- withinSecs 30 "queryUTxOs(wallet)" (queryUTxOs prov addr)
            if length us >= n
                then pure us
                else threadDelay 1_000_000 >> go (k - 1)

{- | The settlement assertion. Mint -> Request -> Modify; each tx settles
via a bounded poll on its own output. The Modify must produce a continuing
state UTxO (its output 0) carrying the advanced value-trie root.
-}
cageModifySettles :: DevnetEnv -> IO ()
cageModifySettles (env, addr) = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    let sk = genesisSignKey
        kh = keyHashFromSignKey sk
        prov = envProvider env

    -- Wallet prep: the genesis wallet has ONE UTxO, but the script txs need
    -- disjoint regular + collateral inputs. Fan it out into several ada-only
    -- UTxOs (no scripts, so no collateral needed here), settle, then use a
    -- fresh post-split seed.
    dbg "awaiting genesis wallet funds (bounded)"
    _ <- awaitFunds prov addr
    dbg "splitting the genesis UTxO into disjoint wallet UTxOs"
    splitTx <- withinSecs 60 "buildSplitTx" (buildSplitTx env addr)
    _ <- withinSecs 60 "submit split" (submitLocal env "split" sk splitTx)
    dbg "awaiting >=4 wallet UTxOs after split"
    walletUtxos <- awaitWalletCount prov addr 4
    seedUtxo <- requireJust "seed UTxO" (listToMaybe walletUtxos)
    dbg ("seed UTxO = " <> show (fst seedUtxo))

    -- Mint the cage thread token; settle via a bounded poll on its output
    -- carrying the thread token.
    dbg "building mint tx"
    mintTx <- withinSecs 150 "buildMintTx" (buildMintTx env kh addr seedUtxo)
    dbg "submitting mint tx"
    mintTxId <- withinSecs 60 "submit mint" (submitLocal env "mint" sk mintTx)
    dbg ("mint settled as " <> show mintTxId <> "; polling state UTxO")
    stateUtxo <-
        pollOutput prov mintTxId [0, 1] (hasThreadToken env)
            >>= requireJust "mint state UTxO never settled"

    -- Open a value-write request at the cage script (for the just-minted
    -- thread token); settle via poll.
    tokenName <-
        requireJust
            "thread-token asset name"
            (threadTokenName env (snd stateUtxo))
    dbg "building request tx"
    reqTx <- withinSecs 60 "buildRequestTx" (buildRequestTx env kh addr tokenName)
    dbg "submitting request tx"
    reqTxId <- withinSecs 60 "submit request" (submitLocal env "request" sk reqTx)
    dbg ("request settled as " <> show reqTxId <> "; polling request UTxO")
    reqUtxo <-
        pollOutput prov reqTxId [0, 1] (isRequestOutput env)
            >>= requireJust "request UTxO never settled"

    -- Build the hardened Modify. Compute its txId locally, submit, and then
    -- BIND settlement to that tx's continuing-state output (index 0).
    dbg "building Modify tx (owner-authorized value-write)"
    (modTx, expectedRoot, exUnits) <-
        withinSecs 90 "buildModifyTx" (buildModifyTx env kh addr stateUtxo [reqUtxo])
    let modTxId = txIdTx modTx
    dbg ("submitting Modify tx; expected tx id " <> show modTxId)
    submitResult <-
        withinSecs 60 "submit Modify" $
            submitTx (envSubmitter env) (addKeyWitness sk modTx)
    dbg ("Modify submit result: " <> renderSubmit submitResult)
    dbg "polling for Modify continuing-state settlement (bounded)"

    settled <-
        pollOutput prov modTxId [0] (hasThreadToken env)
    (_, contOut) <-
        maybe
            ( failWith $
                "Modify did not settle: continuing-state output "
                    <> show modTxId
                    <> "#0 never appeared within "
                    <> show pollAttempts
                    <> " polls. Submit result: "
                    <> renderSubmit submitResult
            )
            pure
            settled

    settledRoot <-
        requireJust "continuing-state root" (stateRootOf env contOut)
    settledRoot `shouldBe` expectedRoot

    -- Settlement evidence (NOTE-016): tx id + per-redeemer exunits.
    putStrLn $ "SETTLED Modify tx id: " <> show modTxId
    mapM_
        ( \(purpose, eu) ->
            putStrLn $ "  exunits[" <> purpose <> "] = " <> show eu
        )
        exUnits

{- | Submit a signed tx, requiring the node to accept it into the mempool,
and return its 'TxId'. Used for the mint/request setup txs.
-}
submitLocal :: CageEnv -> String -> SignKey -> ConwayTx -> IO TxId
submitLocal env label sk tx = do
    result <- submitTx (envSubmitter env) (addKeyWitness sk tx)
    case result of
        Submitted t -> pure t
        Rejected reason ->
            failWith (label <> " tx rejected: " <> B8.unpack reason)

renderSubmit :: SubmitResult -> String
renderSubmit (Submitted t) = "Submitted " <> show t
renderSubmit (Rejected reason) = "Rejected " <> B8.unpack reason

-- | Abort the running example with a message (unreachable continuation).
failWith :: String -> IO a
failWith msg = expectationFailure msg >> fail "unreachable"
