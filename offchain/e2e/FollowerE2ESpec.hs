{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : FollowerE2ESpec
Description : Live socket indexing and fork rollback proof for #175 slice 6

Proves two live boundaries over a real restartable PV11 devnet:

1. SC-1: the production follower, started through 'mkChainSyncConfig' from a
   concrete non-Origin point over the real N2C socket and a real RocksDB
   store, indexes a real checkpoint registration and answers
   'checkpointForAid' with the exact AID and datum.

2. Live fork drill: reuses the shallow snapshot/restore mechanism proved in
   @.llm/175-fork-spike/Main.hs@.  After settling the checkpoint on chain A,
   the node database is restored to a pre-checkpoint snapshot P; a recorder
   observes a real ROLL_BACKWARD to the exact point P and then chain-B
   ROLL_FORWARD events; the chain-A checkpoint is proved absent by a full
   store scan of the same RocksDB store the production follower wrote.

Database-restore stop signalling is confined to 'stopNodeForDbRestoreMode'
(see its Haddock for the #197 marker).
-}
module FollowerE2ESpec (spec) where

import Cardano.Chain.Slotting (EpochSlots (..))
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    SourceInfo (..),
 )
import Cardano.KERI.Indexer.Codecs (CheckpointRecord (..))
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
 )
import Cardano.KERI.Indexer.Follower (
    mkChainSyncConfig,
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
    checkpointForAid,
    liveCheckpoints,
 )
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Node.Client.N2C.ChainSync (
    Fetched (..),
    HeaderPoint,
    mkChainSyncN2C,
    runChainSyncN2C,
 )
import Cardano.Node.Client.N2C.Trace (nullN2CTracer)
import Cardano.Node.Client.Provider (
    LedgerSnapshot (..),
    Provider (..),
 )
import Cardano.Node.Client.Types (BlockPoint)
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig (..),
    FollowerHandle (..),
    withChainSyncFollower,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    withRocksDBIndexer,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address (..),
    BlockHash (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import ChainFollower (
    Follower (..),
    Intersector (..),
    ProgressOrRewind (..),
 )
import CheckpointTxBuilder (
    CheckpointEnv (..),
    CheckpointInput (..),
    productionRegisterScenario,
    stagedCheckpointFollowerDevnet,
 )
import Codec.Binary.Bech32 (
    dataPartFromBytes,
    encodeLenient,
    humanReadablePartFromText,
 )
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (Async, async, cancel, link)
import Control.Concurrent.MVar (
    MVar,
    newEmptyMVar,
    readMVar,
    tryPutMVar,
 )
import Control.Exception (finally)
import Control.Monad (unless, void)
import Control.Tracer (nullTracer)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Coerce (coerce)
import Data.IORef (
    IORef,
    modifyIORef',
    newIORef,
    readIORef,
    writeIORef,
 )
import Data.List (isPrefixOf)
import Data.Maybe (listToMaybe)
import Data.Text qualified as Text
import Data.Word (Word64)
import Ouroboros.Consensus.HardFork.Combinator.AcrossEras (
    OneEraHash (..),
 )
import Ouroboros.Network.Block (
    Point (..),
    SlotNo (..),
 )
import Ouroboros.Network.Magic (NetworkMagic (..))
import Ouroboros.Network.Point (WithOrigin (..))
import Ouroboros.Network.Point qualified as Network.Point
import System.Directory (
    createDirectoryIfMissing,
    removePathForcibly,
 )
import System.Environment (getEnv, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)
import System.Posix.Signals (
    sigCONT,
    sigSTOP,
    sigTERM,
    signalProcess,
 )
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Test.Hspec (
    Spec,
    describe,
    it,
 )

spec :: Spec
spec =
    describe "#175 follower live leg" $
        it "#175 live follower indexes and removes a checkpoint across a real fork" $
            stagedCheckpointFollowerDevnet $ \sock restart stage -> do
                assertPrivateTmpInvariant sock
                control <- lookupEnv "KERI_S6_CONTROL"
                case control of
                    Just "midway" -> midwayException sock
                    Just "noop-stop" -> noopStopControl sock
                    _ -> stage $ \env -> healthyForkDrill sock restart env

-- ---------------------------------------------------------------------------
-- Private TMP invariant
-- ---------------------------------------------------------------------------

assertPrivateTmpInvariant :: FilePath -> IO ()
assertPrivateTmpInvariant sock = do
    expectedRoot <- getEnv "KERI_S6_EXPECTED_TMP_ROOT"
    let nodeDir = takeDirectory sock
    unless (expectedRoot `isPrefixOf` nodeDir) $
        fail $
            "S6-PRIVATE-ROOT: node directory "
                <> nodeDir
                <> " is not under the expected independent root "
                <> expectedRoot

-- ---------------------------------------------------------------------------
-- Negative controls (live node only; no checkpoint staging)
-- ---------------------------------------------------------------------------

midwayException :: FilePath -> IO ()
midwayException sock = do
    putLine "S6-MIDWAY-EXCEPTION: deliberate mid-way failure with live node"
    pid <- singleNodePid sock
    putLine $ "S6-MIDWAY-LIVE-PID=" <> show pid
    fail "S6-MIDWAY-EXCEPTION"

noopStopControl :: FilePath -> IO ()
noopStopControl sock = do
    putLine "S6-NOOP-STOP: invoking stop seam with no-op signal"
    stopNodeForDbRestoreMode NoopStopSignal sock
    putLine "S6-NOOP-STOP-REACHED-DB-MUTATION"
    fail "S6-NOOP-STOP: reached DB mutation after no-op stop"

-- ---------------------------------------------------------------------------
-- Healthy fork drill
-- ---------------------------------------------------------------------------

healthyForkDrill :: FilePath -> IO () -> CheckpointEnv -> IO ()
healthyForkDrill sock restart env = do
    let nodeDir = takeDirectory sock
        dbDir = nodeDir </> "db"
        snapshotDir = nodeDir </> "db-snapshot-p"

    -- A-009: seed Chain-A at the full LSQ chain point after shared PV11
    -- staging so the recorder does not replay the entire backlog (proved
    -- shallow-snapshot shape). Reject Origin with a named failure.
    lsqSnapshot <- queryLedgerSnapshot (envProvider env)
    let seedPoint =
            blockPointToHeaderPoint (ledgerChainPoint lsqSnapshot)
    case seedPoint of
        Point Origin ->
            fail "CHAIN_A_SEED: ledgerChainPoint is Origin"
        _ ->
            putLine $ "CHAIN_A_SEED " <> renderPoint seedPoint

    -- Chain-A recorder must end before the DB-restore stop: a linked N2C
    -- async still attached to the dying socket raises ExceptionInLinkedThread
    -- (BearerClosed) and aborts the fork proof mid-wait.
    (observedP, chainAPoints, aid, storeDir, manifest) <-
        withRecorderSync "A" sock [seedPoint, Point Origin] $ \chainA _chainASync -> do
            intersection <- waitForIntersection "chain A" chainA
            unless (intersection == seedPoint) $
                fail $
                    "chain A: intersection "
                        <> renderPoint intersection
                        <> " does not equal seed "
                        <> renderPoint seedPoint
            putLine "CHAIN_A_INTERSECTED"

            -- Before SIGSTOP: processed HeaderPoint slot must equal the
            -- latest advertised tip SlotNo (no chain-sync replay lag).
            prePausePoint <-
                waitForProcessedEqualsAdvertised
                    "chain A pre-pause"
                    chainA
            prePauseTipSlot <- requireAdvertisedTip chainA
            putLine $
                "SNAPSHOT_CAUGHT_UP_PRE_PAUSE observed-p="
                    <> renderPoint prePausePoint
                    <> " advertised-slot="
                    <> show (unSlotNo prePauseTipSlot)
            putLine $
                "SNAPSHOT_PAUSE_REQUESTED after-observed="
                    <> renderPoint prePausePoint
            pauseNode sock
            observedP <-
                ( do
                    -- DIRECTION-003 quiet window, extended (A-009): both the
                    -- full processed point and advertised tip slot must stay
                    -- equal and unchanged while the node is paused.
                    point <-
                        waitForQuiescentTip "snapshot P" chainA
                    quietTipSlot <- requireAdvertisedTip chainA
                    putLine $
                        "SNAPSHOT_P_TIP_CAUGHT_UP observed-p="
                            <> renderPoint point
                            <> " advertised-slot="
                            <> show (unSlotNo quietTipSlot)
                    putLine $
                        "SNAPSHOT_P_QUIESCENT observed-p="
                            <> renderPoint point
                    callProcessSync "sync" []
                    removePathForcibly snapshotDir
                    copyTree dbDir snapshotDir
                    pure point
                )
                    `finally` resumeNode sock
            putLine $ "SNAPSHOT_COPIED observed-p=" <> renderPoint observedP

            -- After SIGCONT, require a concrete Chain-A roll-forward strictly
            -- past exact P before any reference deployment (A-008 option 1).
            -- Uses the already-linked recorder only; named timeout if forge
            -- path is not live.
            postResumeTip <-
                waitForForwardPast
                    "chain A post-resume"
                    chainA
                    observedP
            putLine $
                "POST_RESUME_CHAIN_A_PROGRESS past-p="
                    <> renderPoint observedP
                    <> " observed="
                    <> renderPoint postResumeTip

            checkpointInput <- productionRegisterScenario env
            let datum = checkpointDatum checkpointInput
                aid = cdCesrAid datum
            putLine $ "REGISTER_SETTLED aid=" <> show aid

            storeRoot <- getEnv "KERI_S6_EXPECTED_TMP_ROOT"
            let storeDir = storeRoot </> "follower-store"
            createDirectoryIfMissing True storeDir
            let followerConfig =
                    mkFollowerIndexerConfig sock observedP storeDir
                manifest = mkFollowerManifest env
                chainSyncConfig =
                    mkChainSyncConfig followerConfig manifest
            assertNonOriginStart observedP chainSyncConfig

            putLine "FOLLOWER_STARTING"
            withRocksDBIndexer storeDir $ \handle ->
                withFollowerRunning chainSyncConfig handle $ do
                    let view =
                            CheckpointView
                                { cvHandle = handle
                                , cvAddress = checkpointAddrBytes env
                                , cvPolicy = envCheckpointPolicy env
                                }
                    found <-
                        waitForCheckpoint "SC-1 follower read" view aid
                    putLine $
                        "SC1_CHECKPOINT_FOUND aid="
                            <> show aid
                            <> " datum-match="
                            <> show (crDatum found == datum)
                    unless (crDatum found == datum) $
                        fail
                            "SC-1: follower returned a datum that does not match the registered datum"
            putLine "FOLLOWER_STOPPED"

            points <- readIORef (recorderPoints chainA)
            pure (observedP, points, aid, storeDir, manifest)

    stopNodeForDbRestore sock
    removePathForcibly dbDir
    copyTree snapshotDir dbDir
    putLine "DB_RESTORED_FROM_SNAPSHOT"
    restart
    putLine "CHAIN_B_NODE_RESTARTED"

    let chainBStarts = take 500 chainAPoints <> [Point Origin]
        viewFor handle =
            CheckpointView
                { cvHandle = handle
                , cvAddress = checkpointAddrBytes env
                , cvPolicy = envCheckpointPolicy env
                }
    -- Chain-B recorder must end before the final stop: a linked N2C async
    -- still attached when stopNodeForDbRestore runs raises the same
    -- ExceptionInLinkedThread (BearerClosed) seen on chain A.
    withRecorderSync "B" sock chainBStarts $ \chainB _chainBSync -> do
        chainBIntersection <- waitForIntersection "chain B" chainB
        putLine $ "CHAIN_B_INTERSECTION " <> renderPoint chainBIntersection

        rollbackPoint <- waitForRollback "chain B" chainB observedP
        putLine $ "CHAIN_B_ROLL_BACKWARD " <> renderPoint rollbackPoint

        chainBTip <- waitForForwardPast "chain B" chainB rollbackPoint
        putLine $ "CHAIN_B_ROLL_FORWARD " <> renderPoint chainBTip

        let chainBConfig =
                mkFollowerIndexerConfig sock chainBIntersection storeDir
            chainBCsConfig = mkChainSyncConfig chainBConfig manifest
        withRocksDBIndexer storeDir $ \handleB ->
            withFollowerRunning chainBCsConfig handleB $ do
                threadDelay 3_000_000
                allCheckpoints <- liveCheckpoints (viewFor handleB)
                let chainAAbsent =
                        all ((/= aid) . crAid) allCheckpoints
                putLine $
                    "CHAIN_A_CHECKPOINT_ABSENT="
                        <> show chainAAbsent
                        <> " total-live="
                        <> show (length allCheckpoints)
                unless chainAAbsent $
                    fail
                        "fork drill: chain-A checkpoint is still present in the follower store"

    stopNodeForDbRestore sock
    putLine "FORK_DRILL_COMPLETE"

assertNonOriginStart :: HeaderPoint -> ChainSyncConfig -> IO ()
assertNonOriginStart observedP cfg = do
    let expected = headerPointToConfig observedP
    case (expected, csStartPoint cfg) of
        (Just want, Just got)
            | want == got ->
                putLine $
                    "SC1_START_POINT non-origin slot="
                        <> show (fst got)
                        <> " hash="
                        <> show (snd got)
        (Just want, Just got) ->
            fail $
                "SC-1: csStartPoint mismatch: want "
                    <> show want
                    <> " got "
                    <> show got
        (Just _, Nothing) ->
            fail "SC-1: csStartPoint is Origin/Nothing; expected concrete non-Origin point"
        (Nothing, _) ->
            fail "SC-1: observed P was Origin; cannot start from a concrete point"

-- ---------------------------------------------------------------------------
-- #197 workaround: ONE named stop function (sole SIGTERM site)
-- ---------------------------------------------------------------------------

data StopMode
    = RealStopSignal
    | NoopStopSignal

stopNodeForDbRestore :: FilePath -> IO ()
stopNodeForDbRestore = stopNodeForDbRestoreMode RealStopSignal

{- | Stop the node and return only after the process is absent.

workaround-for=lambdasistemi/cardano-node-clients#197: the pinned upstream
'withRestartableCardanoNode' exposes atomic restart, not a stop/mutate/start
split.  This is the single function that sends the stop signal for database
restore.  Real and no-op modes both enter this seam; only 'RealStopSignal'
issues SIGTERM.  No other function in this module sends SIGTERM.

The function returns only after the separately named 'assertNodeDown'
assertion passes.  A no-op signal fails at that assertion, loudly, before any
database mutation.
-}
stopNodeForDbRestoreMode :: StopMode -> FilePath -> IO ()
stopNodeForDbRestoreMode mode sock = do
    pid <- singleNodePid sock
    case mode of
        RealStopSignal -> do
            putLine $ "NODE_SIGTERM pid=" <> show pid
            signalProcess sigTERM (fromIntegral pid)
        NoopStopSignal ->
            putLine $ "NODE_NOOP_SIGNAL pid=" <> show pid
    assertNodeDown sock

{- | Assert that no cardano-node process remains for this socket.

This is the separately named down assertion required by the #197 workaround
guard conditions.  It must pass before any database delete or copy.
-}
assertNodeDown :: FilePath -> IO ()
assertNodeDown sock = waitGone (300 :: Int)
  where
    waitGone 0 =
        fail "S6-NODE-STILL-RUNNING: cardano-node did not exit after SIGTERM"
    waitGone attempts = do
        remaining <- findNodePids sock
        if null remaining
            then putLine "NODE_EXITED"
            else threadDelay 100_000 >> waitGone (attempts - 1)

-- ---------------------------------------------------------------------------
-- Node signalling helpers (not the #197 stop seam)
-- ---------------------------------------------------------------------------

pauseNode :: FilePath -> IO ()
pauseNode sock = do
    pid <- singleNodePid sock
    putLine $ "NODE_SIGSTOP pid=" <> show pid
    signalProcess sigSTOP (fromIntegral pid)
    threadDelay 100_000
    putLine "NODE_PAUSED"

resumeNode :: FilePath -> IO ()
resumeNode sock = do
    pid <- singleNodePid sock
    putLine $ "NODE_SIGCONT pid=" <> show pid
    signalProcess sigCONT (fromIntegral pid)
    putLine "NODE_RESUMED"

singleNodePid :: FilePath -> IO Int
singleNodePid sock = do
    pids <- findNodePids sock
    case pids of
        [one] -> pure one
        [] -> fail $ "no cardano-node process found for socket " <> sock
        many ->
            fail $
                "multiple cardano-node processes found for socket "
                    <> sock
                    <> ": "
                    <> show many

findNodePids :: FilePath -> IO [Int]
findNodePids sock = do
    let patternText =
            "cardano-node run.*--socket-path "
                <> sock
    (exitCode, output, _stderrText) <-
        readProcessWithExitCode
            "pgrep"
            ["-f", "--", patternText]
            ""
    case exitCode of
        ExitSuccess ->
            traverse
                ( maybe
                    (fail $ "invalid pgrep pid output: " <> output)
                    pure
                    . readMaybeInt
                )
                (words output)
        ExitFailure 1 -> pure []
        ExitFailure code ->
            fail $ "pgrep failed with exit " <> show code

readMaybeInt :: String -> Maybe Int
readMaybeInt s =
    case reads s of
        [(n, "")] -> Just n
        _ -> Nothing

-- ---------------------------------------------------------------------------
-- N2C chain-sync recorder (reused from fork spike)
-- ---------------------------------------------------------------------------

data Recorder = Recorder
    { recorderPoints :: IORef [HeaderPoint]
    , -- | Latest advertised chain-sync tip 'SlotNo' from 'rollForward'.
      recorderAdvertisedTip :: IORef (Maybe SlotNo)
    , recorderIntersection :: MVar HeaderPoint
    , recorderRollbacks :: IORef [HeaderPoint]
    }

newRecorder :: IO Recorder
newRecorder =
    Recorder
        <$> newIORef []
        <*> newIORef Nothing
        <*> newEmptyMVar
        <*> newIORef []

withRecorderSync ::
    String ->
    FilePath ->
    [HeaderPoint] ->
    (Recorder -> Async () -> IO a) ->
    IO a
withRecorderSync label sock startingPoints action = do
    recorder <- newRecorder
    syncAsync <- startSync label sock recorder startingPoints
    link syncAsync
    action recorder syncAsync `finally` cancel syncAsync

startSync ::
    String ->
    FilePath ->
    Recorder ->
    [HeaderPoint] ->
    IO (Async ())
startSync label sock recorder startingPoints =
    async $ do
        outcome <-
            runChainSyncN2C
                (EpochSlots 42)
                (NetworkMagic 42)
                sock
                ( mkChainSyncN2C
                    nullTracer
                    nullTracer
                    (mkIntersector label recorder)
                    startingPoints
                )
        putLine $ label <> " CHAIN_SYNC_EXIT " <> show outcome
        case outcome of
            Right () -> pure ()
            Left err ->
                fail $
                    label
                        <> " chain-sync transport failed: "
                        <> show err

mkIntersector ::
    String ->
    Recorder ->
    Intersector HeaderPoint SlotNo Fetched
mkIntersector label recorder = self
  where
    self =
        Intersector
            { intersectFound = \point -> do
                putLine $ label <> " INTERSECT_FOUND " <> renderPoint point
                void $ tryPutMVar (recorderIntersection recorder) point
                pure follower
            , intersectNotFound = do
                putLine $ label <> " INTERSECT_NOT_FOUND"
                pure (self, [Point Origin])
            }
    follower =
        Follower
            { rollForward = \fetched tip -> do
                let point = fetchedPoint fetched
                modifyIORef' (recorderPoints recorder) (point :)
                writeIORef (recorderAdvertisedTip recorder) (Just tip)
                putLine $ label <> " ROLL_FORWARD " <> renderPoint point
                pure follower
            , rollBackward = \point -> do
                modifyIORef' (recorderRollbacks recorder) (point :)
                putLine $ label <> " ROLL_BACKWARD " <> renderPoint point
                pure $ Progress follower
            }

waitForIntersection :: String -> Recorder -> IO HeaderPoint
waitForIntersection label recorder = do
    result <- timeout 60_000_000 $ readMVar (recorderIntersection recorder)
    case result of
        Just point -> pure point
        Nothing -> fail $ label <> ": timed out waiting for intersection"

requireAdvertisedTip :: Recorder -> IO SlotNo
requireAdvertisedTip recorder = do
    mTip <- readIORef (recorderAdvertisedTip recorder)
    case mTip of
        Just tip -> pure tip
        Nothing ->
            fail "recorder has no advertised tip SlotNo yet"

-- | Bounded wait: newest processed point's slot equals latest advertised tip.
--
-- Proves there is no chain-sync replay lag before 'pauseNode' (A-009). Does
-- not alone authorize binding P: the paused quiet window still runs.
waitForProcessedEqualsAdvertised ::
    String ->
    Recorder ->
    IO HeaderPoint
waitForProcessedEqualsAdvertised label recorder = loop (600 :: Int)
  where
    loop 0 =
        fail $
            label
                <> ": timed out waiting for processed point slot "
                <> "to equal advertised tip slot"
    loop attempts = do
        points <- readIORef (recorderPoints recorder)
        mAdv <- readIORef (recorderAdvertisedTip recorder)
        case (listToMaybe points, mAdv) of
            (Just point, Just tipSlot)
                | SlotNo (pointSlot point) == tipSlot ->
                    pure point
            _ ->
                threadDelay 100_000 >> loop (attempts - 1)

-- | Wait until processed point and advertised tip stay equal and unchanged.
--
-- After 'pauseNode', already-delivered chain-sync messages may still arrive.
-- DIRECTION-003 required a quiet processed tip; A-009 also requires the
-- advertised tip 'SlotNo' to match that point's slot across the same quiet
-- window. The bound full 'HeaderPoint' is exact P (not slot-only).
waitForQuiescentTip :: String -> Recorder -> IO HeaderPoint
waitForQuiescentTip label recorder = loop (60 :: Int)
  where
    quietWindowUs = 500_000
    loop 0 =
        fail $
            label
                <> ": timed out waiting for quiescent tip "
                <> "(processed point and advertised tip slot did not remain "
                <> "equal and unchanged for "
                <> show (quietWindowUs `div` 1000)
                <> " ms)"
    loop attempts = do
        before <- sampleCaughtUp
        case before of
            Nothing ->
                threadDelay 100_000 >> loop (attempts - 1)
            Just (point0, tip0) -> do
                threadDelay quietWindowUs
                after <- sampleCaughtUp
                case after of
                    Just (point1, tip1)
                        | point1 == point0
                        , tip1 == tip0 ->
                            pure point0
                    _ ->
                        loop (attempts - 1)
    sampleCaughtUp = do
        points <- readIORef (recorderPoints recorder)
        mAdv <- readIORef (recorderAdvertisedTip recorder)
        pure $ case (listToMaybe points, mAdv) of
            (Just point, Just tipSlot)
                | SlotNo (pointSlot point) == tipSlot ->
                    Just (point, tipSlot)
            _ -> Nothing

-- | Coerce an LSQ 'BlockPoint' to a chain-sync 'HeaderPoint' (same hash).
--
-- Matches the private coerce used inside cardano-node-clients chain-sync.
blockPointToHeaderPoint :: BlockPoint -> HeaderPoint
blockPointToHeaderPoint = coerce

waitForRollback :: String -> Recorder -> HeaderPoint -> IO HeaderPoint
waitForRollback label recorder expectedP = loop (600 :: Int)
  where
    loop 0 =
        fail $
            label
                <> ": timed out waiting for ROLL_BACKWARD to exact P "
                <> renderPoint expectedP
    loop attempts = do
        rollbacks <- readIORef (recorderRollbacks recorder)
        case listToMaybe (filter (== expectedP) rollbacks) of
            Just point -> pure point
            Nothing -> threadDelay 100_000 >> loop (attempts - 1)

waitForForwardPast :: String -> Recorder -> HeaderPoint -> IO HeaderPoint
waitForForwardPast label recorder afterPoint = loop (600 :: Int)
  where
    loop 0 =
        fail $
            label
                <> ": timed out waiting for ROLL_FORWARD past "
                <> renderPoint afterPoint
    loop attempts = do
        points <- readIORef (recorderPoints recorder)
        case listToMaybe (filter (\p -> pointSlot p > pointSlot afterPoint) points) of
            Just point -> pure point
            Nothing -> threadDelay 100_000 >> loop (attempts - 1)

-- ---------------------------------------------------------------------------
-- Production follower bring-up
-- ---------------------------------------------------------------------------

withFollowerRunning :: ChainSyncConfig -> IndexerHandle -> IO a -> IO a
withFollowerRunning config handle action =
    withChainSyncFollower nullN2CTracer config handle $ \fh -> do
        link (fhAsync fh)
        action

waitForCheckpoint ::
    String ->
    CheckpointView ->
    BS.ByteString ->
    IO CheckpointRecord
waitForCheckpoint label view aid = loop (600 :: Int)
  where
    loop 0 = fail $ label <> ": timed out waiting for checkpoint"
    loop attempts = do
        result <- checkpointForAid view aid
        case result of
            Just record -> pure record
            Nothing -> threadDelay 100_000 >> loop (attempts - 1)

-- ---------------------------------------------------------------------------
-- Follower configuration
-- ---------------------------------------------------------------------------

mkFollowerIndexerConfig ::
    FilePath ->
    HeaderPoint ->
    FilePath ->
    IndexerConfig
mkFollowerIndexerConfig sock startPoint storeDir =
    IndexerConfig
        { icSocketPath = sock
        , icNetworkMagic = 42
        , icByronEpochSlots = 42
        , icSecurityParamK = 100
        , icStartPoint = headerPointToConfig startPoint
        , icStorePath = storeDir
        , icFundingAddrs = []
        , icBoardAddr = Nothing
        }

headerPointToConfig ::
    HeaderPoint ->
    Maybe (Indexer.SlotNo, Indexer.BlockHash)
headerPointToConfig (Point Origin) = Nothing
headerPointToConfig
    (Point (At (Network.Point.Block (SlotNo slot) blockHash))) =
        Just
            ( Indexer.SlotNo slot
            , BlockHash (SBS.fromShort (getOneEraHash blockHash))
            )

mkFollowerManifest :: CheckpointEnv -> Manifest
mkFollowerManifest env =
    Manifest
        { manifestSchemaVersion = "test-schema"
        , manifestNetwork = NetworkInfo "testnet" 42
        , manifestSource = SourceInfo "test-repository" "test-commit"
        , manifestBlueprint = BlueprintInfo "test-blueprint"
        , manifestParameters =
            DeploymentParameters
                { parameterCheckpointVersion = 1
                , parameterNetworkDiscriminator = 0
                , parameterRegistrationBond = 1
                , parameterFreezeBond = 1
                , parameterFreezeWindow = 1
                }
        , manifestCheckpoint =
            CheckpointInfo
                { checkpointAddressBech32 =
                    encodeAddressBech32 (checkpointAddrBytes env)
                , checkpointPolicyId = "test-policy"
                }
        , manifestPublishedAt = "2026-07-30T00:00:00Z"
        , manifestScripts = []
        }

checkpointAddr :: CheckpointEnv -> Addr
checkpointAddr env =
    Addr
        Testnet
        (ScriptHashObj (envCheckpointHash env))
        StakeRefNull

checkpointAddrBytes :: CheckpointEnv -> Address
checkpointAddrBytes env =
    Address (serialiseAddr (checkpointAddr env))

encodeAddressBech32 :: Address -> Text.Text
encodeAddressBech32 (Address bytes) =
    case humanReadablePartFromText "addr_test" of
        Left err ->
            error $ "encodeAddressBech32: invalid HRP: " <> show err
        Right hrp ->
            encodeLenient hrp (dataPartFromBytes bytes)

-- ---------------------------------------------------------------------------
-- Filesystem helpers (reused from fork spike)
-- ---------------------------------------------------------------------------

copyTree :: FilePath -> FilePath -> IO ()
copyTree source target = do
    putLine $ "COPY_TREE " <> source <> " -> " <> target
    callProcessSync "cp" ["-a", source, target]

callProcessSync :: String -> [String] -> IO ()
callProcessSync cmd args = do
    (exitCode, _out, errText) <- readProcessWithExitCode cmd args ""
    case exitCode of
        ExitSuccess -> pure ()
        ExitFailure code ->
            fail $
                cmd
                    <> " failed with exit "
                    <> show code
                    <> ": "
                    <> errText

-- ---------------------------------------------------------------------------
-- Point rendering
-- ---------------------------------------------------------------------------

renderPoint :: HeaderPoint -> String
renderPoint (Point Origin) = "origin"
renderPoint
    (Point (At (Network.Point.Block (SlotNo slot) blockHash))) =
        show slot <> " " <> show blockHash

pointSlot :: HeaderPoint -> Word64
pointSlot (Point Origin) = 0
pointSlot
    (Point (At (Network.Point.Block (SlotNo slot) _blockHash))) =
        slot

putLine :: String -> IO ()
putLine message = do
    putStrLn message
    hFlush stdout
