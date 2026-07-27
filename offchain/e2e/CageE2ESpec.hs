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
import Control.Exception (SomeException, displayException, try)
import Control.Monad (unless, when)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as B8
import Data.List (find, intercalate, isInfixOf, isSuffixOf, minimumBy)
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
import Cardano.Ledger.Alonzo.PParams (ppCostModelsL, ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.Scripts (costModelsValid, getCostModelParams)
import Cardano.Ledger.Api.PParams (unCoinPerByte)
import Cardano.Ledger.Api.Tx (txIdTx)
import Cardano.Ledger.Api.Tx.Body (collateralInputsTxBodyL, inputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (
    Inject (..),
    ProtVer (..),
    TxIx (..),
    getVersion,
 )
import Cardano.Ledger.Coin (Coin (..), unCoin)
import Cardano.Ledger.Compactible (fromCompact)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (
    TxOut,
    bodyTxL,
    ppMaxTxSizeL,
    ppProtocolVersionL,
    ppTxFeeFixedL,
    ppTxFeePerByteL,
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..), exUnitsMem, exUnitsSteps)
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Lens.Micro ((^.))

import Cardano.Node.Client.E2E.Setup (
    DevnetConfig (devnetTargetPV),
    TargetPV (PV11),
    addKeyWitness,
    assertPV11Enacted,
    defaultDevnetConfig,
    genesisAddr,
    genesisSignKey,
    keyHashFromSignKey,
    withDevnetConfig,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
    SlotNo (..),
 )
import Cardano.Node.Client.Submitter (SubmitResult (..), Submitter (..))

import CageTxBuilder

spec :: Spec
spec = do
    offlineBatchedPv11CaptureContract
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

-- ---------------------------------------------------------------------------
-- Offline batched PV11 capture contract (RED 2 + RED 3)
-- ---------------------------------------------------------------------------

{- | Offline proof of the real Conway Phase-1 guard.

Every example here is OFFLINE: no provider, socket, node, devnet, network,
signing, or submission. Candidates are real Conway transactions handed to the
pinned real ledger rule via 'runPhase1'; the ledger's own failure constructors
are asserted, never a weaker predicate.

Guard-parameter provenance (A-048 ruling 48A): protocol major, the 350-entry
PlutusV3 cost model, and the maximum transaction execution units come from the
committed real-mainnet PV11 fixture; every other Phase-1 field comes from the
SAME pinned node-clients revision's DEVNET GENESIS. Assertions decided by a
genesis-sourced field (@MaxTxSizeUTxO@, @FeeTooSmallUTxO@) rest on the pinned
devnet genesis value and are NOT mainnet-authoritative.
-}
offlineBatchedPv11CaptureContract :: Spec
offlineBatchedPv11CaptureContract = do
    describe "offline batched PV11 capture contract" builderSeamsAreGuarded
    describe "offline batched PV11 capture contract" remainingCageSeamsAreGuarded
    describe "offline batched PV11 capture contract" realCageShapeAndAcceptance
    describe "offline batched PV11 capture contract" $
        beforeAll loadPv11GuardParams $ do
            describe "committed real-PV11 fixture is the guard input" $ do
                it "resolves the committed fixture path and hash" $ \guard -> do
                    pv11FixtureFile guard
                        `shouldSatisfy` isSuffixOf "pparams-pv11-mainnet.json"
                    pv11FixtureSha256 guard
                        `shouldBe` "2ff234b5b50ae9dc17355ffaedfadd9bbc2e166df6c8b0505004eecabd1be026"
                it "decodes protocol major exactly 11 from the fixture" $ \guard ->
                    pv11ProtocolMajor guard `shouldBe` 11
                it "decodes exactly 350 PlutusV3 cost-model entries from the fixture" $ \guard ->
                    pv11V3CostModelEntries guard `shouldBe` 350
                it "decodes maxTxExUnits exactly 16,500,000 / 10,000,000,000" $ \guard ->
                    pv11MaxTxExUnits guard `shouldBe` ExUnits 16_500_000 10_000_000_000
                it "each composed field matches its ACTUAL decoded source (A-048 48A)" $ \guard -> do
                    -- Decode both sources independently here, then compare the
                    -- COMPOSED parameters field-by-field against whichever
                    -- source is authoritative. This follows the real decoded
                    -- values rather than a self-authored label list.
                    genesisDir <-
                        lookupEnv "E2E_GENESIS_DIR"
                            >>= maybe (fail "E2E_GENESIS_DIR not set") pure
                    fixtureJson <- decodeJsonAt (pv11FixtureFile guard)
                    shelleyJson <- decodeJsonAt (genesisDir <> "/shelley-genesis.json")
                    let composed = pv11ComposedParams guard
                        ProtVer major minor = composed ^. ppProtocolVersionL
                    -- FIXTURE wins for exactly these three.
                    (getVersion major :: Integer)
                        `shouldBe` jsonIntAt fixtureJson ["protocolVersion", "major"]
                    composed ^. ppMaxTxExUnitsL
                        `shouldBe` ExUnits
                            (fromInteger (jsonIntAt fixtureJson ["maxTxExecutionUnits", "memory"]))
                            (fromInteger (jsonIntAt fixtureJson ["maxTxExecutionUnits", "steps"]))
                    pv11V3CostModelEntries guard `shouldBe` 350
                    -- GENESIS wins for everything else, minor included.
                    toInteger minor
                        `shouldBe` jsonIntAt shelleyJson ["protocolParams", "protocolVersion", "minor"]
                    toInteger (composed ^. ppMaxTxSizeL)
                        `shouldBe` jsonIntAt shelleyJson ["protocolParams", "maxTxSize"]
                    unCoin (fromCompact (unCoinPerByte (composed ^. ppTxFeePerByteL)))
                        `shouldBe` jsonIntAt shelleyJson ["protocolParams", "minFeeA"]
                    unCoin (composed ^. ppTxFeeFixedL)
                        `shouldBe` jsonIntAt shelleyJson ["protocolParams", "minFeeB"]
                    pv11ProtocolMinor guard
                        `shouldBe` jsonIntAt shelleyJson ["protocolParams", "protocolVersion", "minor"]

            describe "real ledger rule decides admissibility" $ do
                it
                    "aggregate-over-limit three-purpose Register yields exact ExUnitsTooBigUTxO"
                    $ \guard -> do
                        verdict <- judge guard NoRewardState overLimitRegisterTx
                        renderPhase1 verdict
                            `shouldSatisfy` isInfixOf "ExUnitsTooBigUTxO"
                        phase1Accepted verdict `shouldBe` False
                it
                    "declared three-purpose aggregate 24,500,000 / 14,500,000,000 exceeds the PV11 maximum"
                    $ \guard -> do
                        let ExUnits maxMem maxSteps = pv11MaxTxExUnits guard
                        aggregateMem `shouldBe` 24_500_000
                        aggregateSteps `shouldBe` 14_500_000_000
                        (aggregateMem > maxMem) `shouldBe` True
                        (aggregateSteps > maxSteps) `shouldBe` True
                it "script-integrity mutation yields the exact ledger integrity failure" $ \guard -> do
                    verdict <- judge guard NoRewardState mutatedIntegrityTx
                    renderPhase1 verdict
                        `shouldSatisfy` isInfixOf "ScriptIntegrityHashMismatch"
                    phase1Accepted verdict `shouldBe` False
                it "zero-fee mutation yields the exact ledger fee failure" $ \guard -> do
                    verdict <- judge guard NoRewardState zeroFeeTx
                    renderPhase1 verdict
                        `shouldSatisfy` isInfixOf "FeeTooSmallUTxO"
                    phase1Accepted verdict `shouldBe` False
                it "a mixed witness-plus-structural result names the COMPLETE structural set exactly" $ \guard -> do
                    verdict <- judgeResolved guard NoRewardState overLimitRegisterTx
                    structuralNames verdict `shouldBe` expectedOverLimitStructural
                    phase1Accepted verdict `shouldBe` False
                it "an unsigned but structurally valid candidate is accepted on witness-only failures" $ \guard -> do
                    verdict <- judge guard NoRewardState witnessOnlyTx
                    renderPhase1 verdict
                        `shouldSatisfy` isInfixOf "MissingVKeyWitnessesUTXOW"
                    phase1Structural verdict `shouldBe` []
                    phase1Accepted verdict `shouldBe` True

            describe "downstream sentinels stay zero on structural rejection" $
                it "never evaluates, signs, or submits a structurally rejected candidate" $ \guard -> do
                    sentinels <- newPhase1Sentinels
                    verdict <- judge guard NoRewardState overLimitRegisterTx
                    when (phase1Accepted verdict) $ do
                        countEvaluation sentinels
                        countSigning sentinels
                        countSubmission sentinels
                    readPhase1Sentinels sentinels `shouldReturn` (0, 0, 0)

            describe "reward-state modelling does not blind the guard" $ do
                it "1: plain validatePhase1 reports the withdrawal-account false positive (ConwayWithdrawalsMissingAccounts)" $ \guard -> do
                    verdict <- judge guard NoRewardState withdrawalTx
                    renderPhase1 verdict
                        `shouldSatisfy` isInfixOf "ConwayWithdrawalsMissingAccounts"
                it "2: seeding exactly the body's withdrawal accounts removes only that false positive" $ \guard -> do
                    verdict <- judge guard seededObserverAccount withdrawalTx
                    renderPhase1 verdict
                        `shouldNotSatisfy` isInfixOf "ConwayWithdrawalsMissingAccounts"
                it "3: ExUnitsTooBigUTxO remains visible through the same seeded call" $ \guard -> do
                    verdict <- judge guard seededObserverAccount overLimitWithdrawalTx
                    renderPhase1 verdict
                        `shouldSatisfy` isInfixOf "ExUnitsTooBigUTxO"
                    phase1Accepted verdict `shouldBe` False

            describe "intentional Cage negative sweep is proved offline" $
                mapM_
                    ( \(n, needles) ->
                        it
                            ( "batch size "
                                <> show n
                                <> " is rejected by the real guard naming "
                                <> intercalate " + " needles
                            )
                            $ \guard -> do
                                sentinels <- newPhase1Sentinels
                                let candidate = oversizedCageModifyTx n
                                verdict <-
                                    judgeResolved guard NoRewardState candidate
                                let rendered = renderPhase1 verdict
                                mapM_
                                    (\needle -> rendered `shouldSatisfy` isInfixOf needle)
                                    needles
                                -- Complete normal+collateral resolved set, so
                                -- no unresolved-input noise can appear.
                                structuralNames verdict
                                    `shouldNotSatisfy` elem "BadInputsUTxO"
                                phase1Accepted verdict `shouldBe` False
                                readPhase1Sentinels sentinels `shouldReturn` (0, 0, 0)
                    )
                    offlineCageNegatives

{- | The builder-integration contract: the guard must be REACHED by the real
builder seams, not merely available to a spec.

This is the behaviour the slice adds. Until 'buildModifyTx' consults the real
Phase-1 guard before returning a candidate, it hands back an inadmissible
transaction and these examples fail — which is the point of running them
first.
-}

{- | The four remaining Cage builder return seams.

Each example drives its builder to a GENUINE structural failure using only
legitimate inputs — a change output below the pinned genesis min-UTxO floor,
collateral below the pinned genesis collateral percentage, or a request batch
past the pinned genesis maximum transaction size. None of these seams consults
the real guard yet, so each returns the inadmissible candidate and the example
fails. That is the missing wiring this RED exists to expose.
-}
remainingCageSeamsAreGuarded :: Spec
remainingCageSeamsAreGuarded =
    describe "remaining builder return seams reach the real guard" $ do
        it "buildSplitTx refuses a candidate whose change falls below min-UTxO" $ do
            env <- offlineEnvWith [(0xaa, 31_000_000)]
            expectGuardRejection "OutputTooSmallUTxO" $
                buildSplitTx env offlineOwnerAddr
        it "buildRequestTx refuses a candidate whose change falls below min-UTxO" $ do
            env <- offlineEnvWith [(0xaa, 5_900_000)]
            expectGuardRejection "OutputTooSmallUTxO" $
                buildRequestTx env offlineOwnerKeyHash offlineOwnerAddr "offline-cage-token"
        it "buildMintTx refuses a candidate whose change falls below min-UTxO" $ do
            env <- offlineEnvWith [(0xaa, 3_400_000), (0xbb, 500_000_000)]
            wallet <- queryUTxOs (envProvider env) offlineOwnerAddr
            seedUtxo <-
                maybe (fail "offline mint seed missing") pure (listToMaybe wallet)
            expectGuardRejection "OutputTooSmallUTxO" $
                buildMintTx env offlineOwnerKeyHash offlineOwnerAddr seedUtxo
        it "buildRequestsTx refuses a batch past the maximum transaction size" $ do
            env <- offlineEnvWith [(0xaa, 5_000_000_000)]
            expectGuardRejection "MaxTxSizeUTxO" $
                buildRequestsTx
                    env
                    offlineOwnerKeyHash
                    offlineOwnerAddr
                    "offline-cage-token"
                    400

{- | Build an offline cage environment whose wallet is exactly the supplied
@(seed byte, lovelace)@ pairs.
-}
offlineEnvWith :: [(Int, Integer)] -> IO CageEnv
offlineEnvWith entries = do
    guardParams <- loadPv11GuardParams
    blueprint <-
        lookupEnv "KERI_CAGE_BLUEPRINT"
            >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
    offlineCageEnv blueprint guardParams (offlineWalletOf entries)

{- | Assert a builder seam rejects at the real guard, naming the exact ledger
failure. Fails loudly when the seam instead returns a candidate — which is the
current, unwired behaviour.
-}
expectGuardRejection :: String -> IO a -> Expectation
expectGuardRejection needle action = do
    outcome <- tryAny action
    case outcome of
        Right _ ->
            expectationFailure
                ( "builder returned an inadmissible candidate instead of "
                    <> "rejecting it at the guard with "
                    <> needle
                )
        Left err -> displayException err `shouldSatisfy` isInfixOf needle

builderSeamsAreGuarded :: Spec
builderSeamsAreGuarded =
    describe "builder return seams reach the real guard" $
        mapM_
            ( \n ->
                it
                    ( "buildModifyTx refuses to return the inadmissible n="
                        <> show n
                        <> " candidate"
                    )
                    $ do
                        guardParams <- loadPv11GuardParams
                        blueprint <-
                            lookupEnv "KERI_CAGE_BLUEPRINT"
                                >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
                        submittedAt <- currentOfflinePosixMs
                        env0 <- offlineCageEnv blueprint guardParams []
                        let (wallet, stateUtxo, reqUtxos) =
                                offlineModifyFixtures env0 n submittedAt
                        env <- offlineCageEnv blueprint guardParams wallet
                        outcome <-
                            try
                                ( buildModifyTx
                                    env
                                    offlineOwnerKeyHash
                                    offlineOwnerAddr
                                    stateUtxo
                                    reqUtxos
                                ) ::
                                IO (Either SomeException (ConwayTx, ByteString, [(String, ExUnits)]))
                        case outcome of
                            Right _ ->
                                expectationFailure
                                    ( "buildModifyTx returned an inadmissible n="
                                        <> show n
                                        <> " candidate instead of rejecting it at the guard"
                                    )
                            Left err ->
                                displayException err
                                    `shouldSatisfy` isInfixOf "ExUnitsTooBigUTxO"
            )
            [5 :: Int, 8, 16, 24, 44]

{- | The intentional over-limit rows converted from the live @KERI_CAGE_SWEEP@.

Failure types are preserved exactly in kind, not merely in spirit: the same
constructors the node assertions named.
-}
offlineCageNegatives :: [(Int, [String])]
offlineCageNegatives =
    [ (5, ["ExUnitsTooBigUTxO"])
    , (8, ["ExUnitsTooBigUTxO"])
    , (16, ["ExUnitsTooBigUTxO"])
    , (24, ["ExUnitsTooBigUTxO"])
    , (44, ["ExUnitsTooBigUTxO", "MaxTxSizeUTxO"])
    ]

{- | Resolve EVERY input the candidate spends, so no unrelated
unresolved-input failure can appear in the structural partition (A-050 50D
item 6).
-}
judgeResolved ::
    Pv11GuardParams -> Phase1RewardState -> ConwayTx -> IO Phase1Verdict
judgeResolved guard rewardState tx =
    judgeThrough guard rewardState (resolveAllInputs tx) tx

-- | The exact constructor names of a verdict's structural partition.
structuralNames :: Phase1Verdict -> [String]
structuralNames = map classifyFailure . phase1Structural

-- | Name the specific ledger failure carried by a structural entry.
classifyFailure :: (Show a) => a -> String
classifyFailure failure =
    case filter (`isInfixOf` rendered) knownLedgerFailures of
        (name : _) -> name
        [] -> takeWhile (\c -> c /= ' ' && c /= '(') rendered
  where
    rendered = show failure

-- | The ledger failure constructors these REDs discriminate between.
knownLedgerFailures :: [String]
knownLedgerFailures =
    [ "ExUnitsTooBigUTxO"
    , "MaxTxSizeUTxO"
    , "FeeTooSmallUTxO"
    , "OutputTooSmallUTxO"
    , "ValueNotConservedUTxO"
    , "ScriptIntegrityHashMismatch"
    , "BadInputsUTxO"
    , "InsufficientCollateral"
    , "ExtraRedeemers"
    , "MissingScriptWitnessesUTXOW"
    , "ConwayWithdrawalsMissingAccounts"
    ]

judge ::
    Pv11GuardParams -> Phase1RewardState -> ConwayTx -> IO Phase1Verdict
judge guard rewardState =
    judgeThrough guard rewardState offlineUtxos

{- | Run the real guard through the ONE offline acquisition callback
(A-069 69A point 5).

Both the 'Globals' and the slot come from that callback: the 'Globals' is the
one the callback owns, and the slot is the callback PROVIDER's own acquired
ledger tip. No fixture is loaded at a guard call site, no slot constant is
invented there, and no 'Globals' is synthesized or reconstructed — which is
the whole ownership point A-065 exists to enforce.
-}
judgeThrough ::
    Pv11GuardParams ->
    Phase1RewardState ->
    [(TxIn, TxOut ConwayEra)] ->
    ConwayTx ->
    IO Phase1Verdict
judgeThrough guard rewardState resolved tx = do
    env <- offlineGuardEnv guard
    envWithPhase1Snapshot env $ \globals provider -> do
        snapshot <- queryLedgerSnapshot provider
        pure $
            runPhase1
                Phase1Input
                    { p1Globals = globals
                    , p1Slot = ledgerTipSlot snapshot
                    , p1Params = guard
                    , p1ResolvedInputs = resolved
                    }
                rewardState
                tx

{- | The offline 'CageEnv' whose installed callback these pure-ledger guard
examples borrow. Only the acquisition seam is used; no builder runs.
-}
offlineGuardEnv :: Pv11GuardParams -> IO CageEnv
offlineGuardEnv guard = do
    blueprint <-
        lookupEnv "KERI_CAGE_BLUEPRINT"
            >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
    offlineCageEnv blueprint guard []

type DevnetEnv = (CageEnv, Addr)

{- | Bracket a real cardano-node devnet and construct the cage environment
from the flake-provided immutable blueprint path (@KERI_CAGE_BLUEPRINT@).
-}
withCageDevnet :: (DevnetEnv -> IO ()) -> IO ()
withCageDevnet action = do
    bp <-
        lookupEnv "KERI_CAGE_BLUEPRINT"
            >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
    withDevnetConfig defaultDevnetConfig{devnetTargetPV = PV11} $ \lsq ltxs -> do
        assertCageLivePV11GuardPairing (mkN2CProvider lsq)
        env <- mkCageEnv bp lsq ltxs
        action (env, genesisAddr)

{- | Fail at the live boundary before 'mkCageEnv' loads or applies the Cage
blueprint unless the node and the real guard compose the same PV11 PlutusV3
language view.
-}
assertCageLivePV11GuardPairing :: Provider IO -> IO ()
assertCageLivePV11GuardPairing provider = do
    assertPV11Enacted provider
    liveParams <- queryProtocolParams provider
    guard <- loadPv11GuardParams
    let v3Model params =
            Map.lookup PlutusV3 (costModelsValid (params ^. ppCostModelsL))
        liveV3 = v3Model liveParams
        guardV3 = v3Model (pv11ComposedParams guard)
        liveEntries = maybe 0 (length . getCostModelParams) liveV3
    unless (liveEntries == 350 && liveV3 == guardV3) $
        fail $
            "Cage live/guard PV11 pairing mismatch: live PlutusV3 entries="
                <> show liveEntries
                <> ", guard entries="
                <> show (pv11V3CostModelEntries guard)

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

-- | Wall-clock POSIX milliseconds; used only to stamp offline request datums.

{- | The offline fixtures' submission timestamp, taken from the ONE canonical
downstream coordinate rather than a wall clock (A-069 69A points 3 and 5), so
the request deadlines these fixtures carry live in the same coordinate the
builder and the guard use.
-}
currentOfflinePosixMs :: IO Integer
currentOfflinePosixMs = pure (syntheticSlotStartMs offlineFixtureNowSlot)

-- | The tip slot the offline fixtures treat as "now", inside ..199@.
offlineFixtureNowSlot :: SlotNo
offlineFixtureNowSlot = SlotNo 100

-- | 'try' specialised to 'SomeException' so callers need no annotation.
tryAny :: IO a -> IO (Either SomeException a)
tryAny = try

{- | A-050 50D items 3 and 4: the real Cage builder shape at n=24, and a
genuinely signed accepted case.
-}
realCageShapeAndAcceptance :: Spec
realCageShapeAndAcceptance =
    describe "real Cage shape and real-rule acceptance" $ do
        it "real buildModifyTx at n=24 names both ExUnitsTooBigUTxO and MaxTxSizeUTxO" $ do
            guardParams <- loadPv11GuardParams
            blueprint <-
                lookupEnv "KERI_CAGE_BLUEPRINT"
                    >>= maybe (fail "KERI_CAGE_BLUEPRINT not set") pure
            submittedAt <- currentOfflinePosixMs
            env0 <- offlineCageEnv blueprint guardParams []
            let (wallet, stateUtxo, reqUtxos) =
                    offlineModifyFixtures env0 24 submittedAt
            env <- offlineCageEnv blueprint guardParams wallet
            outcome <-
                tryAny
                    ( buildModifyTx
                        env
                        offlineOwnerKeyHash
                        offlineOwnerAddr
                        stateUtxo
                        reqUtxos
                    )
            case outcome of
                Right _ ->
                    expectationFailure
                        "real n=24 Modify was returned instead of rejected"
                Left err -> do
                    let rendered = displayException err
                    rendered `shouldSatisfy` isInfixOf "ExUnitsTooBigUTxO"
                    rendered `shouldSatisfy` isInfixOf "MaxTxSizeUTxO"
        it "a genuinely signed structurally valid candidate is accepted as Right ()" $ do
            guardParams <- loadPv11GuardParams
            verdict <-
                judgeThrough
                    guardParams
                    NoRewardState
                    genesisResolvedUtxos
                    signedAdmissibleTx
            renderPhase1 verdict `shouldBe` "Phase1Accepted"
            phase1Accepted verdict `shouldBe` True

{- | Every resolved input the candidate spends, including collateral, so the
structural partition carries no unresolved-input noise.
-}
resolveAllInputs :: ConwayTx -> [(TxIn, TxOut ConwayEra)]
resolveAllInputs tx =
    [ (txIn, mkBasicTxOut offlineOwnerAddr (inject (Coin 1_000_000_000)))
    | txIn <- Set.toList spent
    ]
  where
    spent =
        Set.union
            (tx ^. bodyTxL . inputsTxBodyL)
            (tx ^. bodyTxL . collateralInputsTxBodyL)

{- | The COMPLETE expected structural partition for the aggregate-over-limit
Register candidate, compared exactly rather than merely non-empty.
-}
expectedOverLimitStructural :: [String]
expectedOverLimitStructural =
    [ "ValueNotConservedUTxO"
    , "ExUnitsTooBigUTxO"
    , "ScriptIntegrityHashMismatch"
    , "ExtraRedeemers"
    ]

-- | Decode a committed JSON file for independent provenance comparison.
decodeJsonAt :: FilePath -> IO Aeson.Value
decodeJsonAt path =
    Aeson.eitherDecodeFileStrict path
        >>= either (\err -> fail (path <> ": " <> err)) pure

-- | Read an integer at a JSON path, failing loudly if absent.
jsonIntAt :: Aeson.Value -> [Key.Key] -> Integer
jsonIntAt value path = go value path
  where
    go (Aeson.Number n) [] = truncate n
    go (Aeson.Object fields) (k : rest) =
        case KeyMap.lookup k fields of
            Just v -> go v rest
            Nothing -> error ("jsonIntAt: missing " <> show k)
    go _ _ = error ("jsonIntAt: bad path " <> show path)
