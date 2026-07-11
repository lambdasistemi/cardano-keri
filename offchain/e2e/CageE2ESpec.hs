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
import Control.Monad (unless, when)
import Data.ByteString.Char8 qualified as B8
import Data.List (find, intercalate, isInfixOf, minimumBy)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Ord (comparing)
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
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Coin (unCoin)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut)
import Cardano.Ledger.Plutus.ExUnits (exUnitsMem, exUnitsSteps)
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Lens.Micro ((^.))

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
spec = do
    -- The numerical batch sweep (a measurement, not a behaviour assertion) is
    -- opt-in via @KERI_CAGE_SWEEP=1@ so the default smoke stays fast; when set,
    -- @KERI_CAGE_SWEEP_OUT@ names the artifact file it (re)generates. Each batch
    -- size runs in its OWN fresh @withDevnet@ (a pristine genesis wallet),
    -- reusing the proven single-cycle path — no cross-cycle wallet churn.
    sweep <- runIO (lookupEnv "KERI_CAGE_SWEEP")
    around withCageDevnet $
        describe "#99 cage withDevnet Phase-2 smoke" $ do
            it
                "settles a hardened Modify on a real cardano-node"
                cageModifySettles
            it
                "settles a batch Modify carrying non-zero-depth value proofs"
                (cageBatchModifySettles 2)
            case sweep of
                Nothing -> pure ()
                Just _ ->
                    mapM_
                        ( \(ix, (n, expect)) ->
                            it
                                ( "sweeps batch size "
                                    <> show n
                                    <> " at declared proof depth"
                                )
                                (cageSweepOne (ix == (0 :: Int)) n expect)
                        )
                        (zip [0 ..] sweepSchedule)

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

{- | Bounded poll collecting ALL @n@ request outputs of a batch requests tx
(its outputs @0 .. n-1@), so the subsequent batch @Modify@ can spend every
one. Returns fewer than @n@ only if the bound is exhausted.
-}
pollRequestBatch ::
    Provider IO ->
    CageEnv ->
    TxId ->
    Int ->
    IO [(TxIn, TxOut ConwayEra)]
pollRequestBatch prov env txId n = go pollAttempts
  where
    candidates =
        [TxIn txId (TxIx (fromIntegral i)) | i <- [0 .. n - 1]]
    go k
        | k <= 0 = pure []
        | otherwise = do
            found <-
                withinSecs 30 "queryUTxOByTxIn(requests)" $
                    queryUTxOByTxIn prov (Set.fromList candidates)
            let reqs =
                    filter (isRequestOutput env . snd) (Map.toList found)
            if length reqs >= n
                then pure reqs
                else threadDelay 1_000_000 >> go (k - 1)

{- | Batch settlement assertion (S9b). Mint -> open @batch@ distinct
namespaced value-write requests in one tx -> build a single @Modify@ that
spends all of them (one @Contribute@ each) and inserts them into the value
trie. For @batch >= 2@ the 2nd+ inserts require NON-ZERO-DEPTH MPF
inclusion proofs (@excluding(k_i, proof) == root(T_{i-1})@); a builder that
emits empty proofs is rejected at the node's Phase-2 MPF verification and
the continuing-state output never settles, so this assertion fails until
non-zero-depth proof generation is implemented.
-}
cageBatchModifySettles :: Int -> DevnetEnv -> IO ()
cageBatchModifySettles batch (env, addr) = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    let sk = genesisSignKey
        kh = keyHashFromSignKey sk
        prov = envProvider env

    dbg "awaiting genesis wallet funds (bounded)"
    _ <- awaitFunds prov addr
    dbg "splitting the genesis UTxO into disjoint wallet UTxOs"
    splitTx <- withinSecs 60 "buildSplitTx" (buildSplitTx env addr)
    _ <- withinSecs 60 "submit split" (submitLocal env "split" sk splitTx)
    dbg "awaiting >=4 wallet UTxOs after split"
    walletUtxos <- awaitWalletCount prov addr 4
    seedUtxo <- requireJust "seed UTxO" (listToMaybe walletUtxos)
    dbg ("seed UTxO = " <> show (fst seedUtxo))

    dbg "building mint tx"
    mintTx <- withinSecs 150 "buildMintTx" (buildMintTx env kh addr seedUtxo)
    dbg "submitting mint tx"
    mintTxId <- withinSecs 60 "submit mint" (submitLocal env "mint" sk mintTx)
    dbg ("mint settled as " <> show mintTxId <> "; polling state UTxO")
    stateUtxo <-
        pollOutput prov mintTxId [0, 1] (hasThreadToken env)
            >>= requireJust "mint state UTxO never settled"

    tokenName <-
        requireJust
            "thread-token asset name"
            (threadTokenName env (snd stateUtxo))
    dbg ("building batch requests tx (" <> show batch <> " requests)")
    reqsTx <-
        withinSecs 60 "buildRequestsTx" $
            buildRequestsTx env kh addr tokenName batch
    dbg "submitting batch requests tx"
    reqsTxId <-
        withinSecs 60 "submit requests" (submitLocal env "requests" sk reqsTx)
    dbg ("requests settled as " <> show reqsTxId <> "; polling request UTxOs")
    reqUtxos <- pollRequestBatch prov env reqsTxId batch
    when (length reqUtxos < batch) $
        failWith $
            "only "
                <> show (length reqUtxos)
                <> "/"
                <> show batch
                <> " request UTxOs settled"

    dbg "building batch Modify tx (non-zero-depth value proofs)"
    (modTx, expectedRoot, exUnits) <-
        withinSecs 90 "buildModifyTx" $
            buildModifyTx env kh addr stateUtxo reqUtxos
    let modTxId = txIdTx modTx
    dbg ("submitting batch Modify tx; expected tx id " <> show modTxId)
    submitResult <-
        withinSecs 60 "submit Modify" $
            submitTx (envSubmitter env) (addKeyWitness sk modTx)
    dbg ("batch Modify submit result: " <> renderSubmit submitResult)
    dbg "polling for batch Modify continuing-state settlement (bounded)"

    settled <-
        pollOutput prov modTxId [0] (hasThreadToken env)
    (_, contOut) <-
        maybe
            ( failWith $
                "batch Modify did not settle: continuing-state output "
                    <> show modTxId
                    <> "#0 never appeared within "
                    <> show pollAttempts
                    <> " polls (Phase-2 MPF verification rejects empty "
                    <> "proofs for the 2nd+ insert). Submit result: "
                    <> renderSubmit submitResult
            )
            pure
            settled

    settledRoot <-
        requireJust "continuing-state root" (stateRootOf env contOut)
    settledRoot `shouldBe` expectedRoot

    putStrLn $ "SETTLED batch Modify tx id: " <> show modTxId
    mapM_
        ( \(purpose, eu) ->
            putStrLn $ "  exunits[" <> purpose <> "] = " <> show eu
        )
        exUnits

{- | The expected node outcome for a scheduled batch size — asserted so a
harness or boundary regression fails the example loudly (Q-002/A-002 §1)
instead of being silently recorded as the boundary.
-}
data SweepExpect
    = -- | The @Modify@ must pass Phase-1 and SETTLE on-chain (Phase-2 pass).
      ExpSettle
    | {- | The @Modify@ must be REJECTED, its raw diagnostic containing every
      listed limit substring (e.g. @["ExUnitsTooBigUTxO"]@).
      -}
      ExpReject [String]

-- | Batch sizes probed by the sweep, each with its ASSERTED expected outcome.
sweepSchedule :: [(Int, SweepExpect)]
sweepSchedule =
    [ (1, ExpSettle)
    , (2, ExpSettle)
    , (3, ExpSettle)
    , (4, ExpSettle)
    , (5, ExpReject ["ExUnitsTooBigUTxO"])
    , (8, ExpReject ["ExUnitsTooBigUTxO"])
    , (16, ExpReject ["ExUnitsTooBigUTxO"])
    , (24, ExpReject ["ExUnitsTooBigUTxO", "MaxTxSizeUTxO"])
    , (44, ExpReject ["ExUnitsTooBigUTxO", "MaxTxSizeUTxO"])
    ]

{- | One sweep data point (opt-in via @KERI_CAGE_SWEEP=1@), run on a PRISTINE
genesis wallet in its own @withDevnet@. Mints a fresh cage state, opens @n@
namespaced value-write requests, and submits ONE @Modify@ carrying the real
per-insert MPF proofs (insert 1 is depth 0 / empty; inserts 2..n are
depth > 0). It ASSERTS the scheduled @expect@ (settle / reject-with-limit),
then appends an evidence row — node result, actual per-insert proof depths,
declared per-redeemer aggregate ex-units, classification, and the FULL raw
node rejection diagnostic — to the @KERI_CAGE_SWEEP_OUT@ artifact. @firstRow@
(re)writes the artifact header (with the cage script hash) first.
-}
cageSweepOne :: Bool -> Int -> SweepExpect -> DevnetEnv -> IO ()
cageSweepOne firstRow n expect (env, addr) = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering
    out <-
        lookupEnv "KERI_CAGE_SWEEP_OUT"
            >>= maybe (fail "KERI_CAGE_SWEEP_OUT not set") pure
    let sk = genesisSignKey
        kh = keyHashFromSignKey sk
        prov = envProvider env
    dbg ("sweep: probing batch size " <> show n)
    _ <- awaitFunds prov addr
    splitTx <- withinSecs 60 "buildSplitTx" (buildSplitTx env addr)
    _ <- withinSecs 60 "submit split" (submitLocal env "split" sk splitTx)
    walletUtxos <- awaitWalletCount prov addr 4
    -- Seed the mint with the SMALLEST wallet UTxO (a ~10-ada split output on the
    -- pristine wallet), leaving the large change UTxO to fund the N-request tx
    -- (which picks the max) — so large batches do not starve the request tx.
    let seedUtxo =
            minimumBy (comparing (unCoin . (^. coinTxOutL) . snd)) walletUtxos
    mintTx <- withinSecs 150 "buildMintTx" (buildMintTx env kh addr seedUtxo)
    mintTxId <- withinSecs 60 "submit mint" (submitLocal env "mint" sk mintTx)
    stateUtxo <-
        pollOutput prov mintTxId [0, 1] (hasThreadToken env)
            >>= requireJust "sweep: mint state UTxO never settled"
    tokenName <-
        requireJust
            "sweep: thread-token asset name"
            (threadTokenName env (snd stateUtxo))
    reqsTx <-
        withinSecs 90 "buildRequestsTx" $
            buildRequestsTx env kh addr tokenName n
    reqsTxId <-
        withinSecs 60 "submit requests" (submitLocal env "requests" sk reqsTx)
    reqUtxos <- pollRequestBatch prov env reqsTxId n
    reqUtxos `shouldSatisfy` ((>= n) . length)
    (modTx, _root, declared) <-
        withinSecs 120 "buildModifyTx" $
            buildModifyTx env kh addr stateUtxo reqUtxos
    let modTxId = txIdTx modTx
        memAgg = sum [fromIntegral (exUnitsMem eu) | (_, eu) <- declared]
        cpuAgg = sum [fromIntegral (exUnitsSteps eu) | (_, eu) <- declared]
        depths = valueProofDepths n
    res <-
        withinSecs 60 "submit Modify" $
            submitTx (envSubmitter env) (addKeyWitness sk modTx)
    -- Outcome: Right settled tx id, or Left the FULL raw node diagnostic.
    outcome <- case res of
        Rejected reason -> do
            dbg
                ( "sweep: batch "
                    <> show n
                    <> " REJECT raw diagnostic: "
                    <> B8.unpack reason
                )
            pure (Left (B8.unpack reason))
        Submitted _ -> do
            settled <- pollOutput prov modTxId [0] (hasThreadToken env)
            pure $ case settled of
                Just _ -> Right modTxId
                Nothing ->
                    Left "submitted but the continuing state never settled"
    -- ASSERT the scheduled expectation (A-002 §1): a spurious/harness reject or
    -- a boundary shift fails the example rather than passing as the boundary.
    case (expect, outcome) of
        (ExpSettle, Right _) -> pure ()
        (ExpSettle, Left raw) ->
            failWith ("batch " <> show n <> ": expected SETTLE, got: " <> raw)
        (ExpReject _, Right t) ->
            failWith
                ( "batch "
                    <> show n
                    <> ": expected Phase-1 REJECT, but it SETTLED "
                    <> show t
                )
        (ExpReject needles, Left raw) ->
            mapM_
                ( \needle ->
                    unless (needle `isInfixOf` raw) $
                        failWith
                            ( "batch "
                                <> show n
                                <> ": reject missing expected "
                                <> needle
                                <> ": "
                                <> raw
                            )
                )
                needles
    let (nodeResult, classification, rawDiag) = case outcome of
            Right t -> ("settled " <> show t, "—", "—")
            Left raw -> ("rejected", classifyReject raw, oneLine raw)
    when firstRow (writeFile out (sweepHeader (show (envScriptHash env))))
    appendFile
        out
        (sweepRow n nodeResult depths memAgg cpuAgg classification rawDiag)
    dbg
        ( "sweep: batch "
            <> show n
            <> " "
            <> nodeResult
            <> " depths="
            <> show depths
            <> " (agg mem "
            <> show memAgg
            <> " / cpu "
            <> show cpuAgg
            <> ") "
            <> classification
        )

-- | Collapse a raw diagnostic to a single artifact-table-cell-safe line.
oneLine :: String -> String
oneLine = map (\c -> if c == '\n' || c == '|' then ' ' else c)

{- | Classify a node rejection into ALL binding limits it reports, tagged
Phase-1 (structural: ex-units / tx size / fee / collateral) vs Phase-2
(script evaluation). The full raw diagnostic is recorded alongside.
-}
classifyReject :: String -> String
classifyReject r = case tags of
    [] -> "reject (see raw diagnostic)"
    _ -> intercalate " + " tags
  where
    has needle = needle `isInfixOf` r
    tags =
        ["Phase-1 ExUnitsTooBigUTxO" | has "ExUnitsTooBigUTxO"]
            ++ ["Phase-1 MaxTxSizeUTxO" | has "MaxTxSizeUTxO"]
            ++ ["Phase-1 FeeTooSmallUTxO" | has "FeeTooSmallUTxO"]
            ++ ["Phase-1 InsufficientCollateral" | has "InsufficientCollateral"]
            ++ [ "Phase-2 PlutusFailure"
               | has "FailedUnexpectedly" || has "PlutusFailure"
               ]

{- | Artifact preamble (regenerated each sweep run), stamped with the cage
script hash for the consistency check and durable provenance.
-}
sweepHeader :: String -> String
sweepHeader scriptHash =
    unlines
        [ "# S9b live batch sweep — #99 cage Modify tx-limit boundary"
        , ""
        , "Generated by the flake-owned `nix run .#e2e-sweep` (opt-in"
        , "`KERI_CAGE_SWEEP=1` `cageSweepOne` in `offchain/e2e/CageE2ESpec.hs`)"
        , "against a real `cardano-node` devnet via `withDevnet`. Each row submits"
        , "one `Modify` spending a freshly minted cage state plus N namespaced"
        , "value-write requests inserted into an EMPTY value trie, carrying the"
        , "real per-insert MPF proofs from `Cardano.KERI.AID.E2E.MpfProof.prove`."
        , ""
        , "Cage script hash: " <> scriptHash
        , ""
        , "Declared per-redeemer budgets (DECLARED, not measured; conservative"
        , "over-estimates — client `evalTxExUnits` hangs on this script): Modify"
        , "8,000,000 mem / 4,000,000,000 CPU; each Contribute 3,000,000 mem /"
        , "1,500,000,000 CPU. So the aggregate is `8,000,000 + 3,000,000*N` mem /"
        , "`4,000,000,000 + 1,500,000,000*N` CPU."
        , ""
        , "`proof depths (1..N)` is the ACTUAL MPF proof step count per insert:"
        , "insert 1 is 0 (an empty proof into the empty trie — the S9a zero-depth"
        , "case); inserts 2..N are > 0 (genuine non-zero-depth Branch/Fork/Leaf"
        , "proofs). Every reject preserves the full raw ledger diagnostic."
        , ""
        , "| batch N | node result | proof depths (1..N) | declared agg mem"
            <> " | declared agg CPU | classification | raw node diagnostic |"
        , "|--------:|:------------|:--------------------|-----------------:"
            <> "|-----------------:|:---------------|:--------------------|"
        ]

-- | One artifact evidence row.
sweepRow ::
    Int -> String -> [Int] -> Integer -> Integer -> String -> String -> String
sweepRow n nodeResult depths memAgg cpuAgg classification rawDiag =
    "| "
        <> show n
        <> " | "
        <> nodeResult
        <> " | "
        <> show depths
        <> " | "
        <> show memAgg
        <> " | "
        <> show cpuAgg
        <> " | "
        <> classification
        <> " | "
        <> rawDiag
        <> " |\n"

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
