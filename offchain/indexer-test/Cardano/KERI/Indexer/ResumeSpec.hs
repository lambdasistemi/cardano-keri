{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.ResumeSpec (spec) where

import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    SourceInfo (..),
 )
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
 )
import Cardano.KERI.Indexer.Follower (
    mkChainSyncConfig,
 )
import Cardano.Node.Client.N2C.ChainSync (
    HeaderPoint,
 )
import Cardano.Node.Client.N2C.Trace (
    nullN2CTracer,
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig (..),
    coldBootResumePoints,
    withChainSyncFollowerUsing,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerFollowerState,
    IndexerHandle (..),
    withInMemoryIndexer,
    withRocksDBIndexer,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    BlockHash (..),
    SlotNo (..),
 )
import ChainFollower.Rollbacks.Types (
    RollbackPoint (..),
 )
import Control.Concurrent.MVar (
    newEmptyMVar,
    putMVar,
    takeMVar,
 )
import Control.Monad (
    foldM,
 )
import Data.ByteString qualified as BS
import Data.IORef (
    newIORef,
    readIORef,
    writeIORef,
 )
import Data.Maybe (
    listToMaybe,
 )
import Data.Text (
    Text,
 )
import Data.Word (
    Word64,
 )
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Point qualified as Network.Point
import System.IO.Temp (
    withSystemTempDirectory,
 )
import System.Timeout (
    timeout,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotContain,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "resume regression guard" $ do
        it "offers persisted resume candidates newest-first" $
            withInMemoryIndexer $ \handle -> do
                seedFollowingBlocks handle seededPoints
                persisted <- persistedFollowingNewestFirst handle
                captured <- captureResumeCandidates resumeConfig handle

                length captured
                    `shouldSatisfy` (>= 3)
                slotsOf captured
                    `shouldSatisfy` strictlyDescending
                listToMaybe captured
                    `shouldBe` fmap
                        (headerPointFor resumeConfig)
                        (listToMaybe persisted)
                captured
                    `shouldSatisfy` all
                        (`elem` fmap (headerPointFor resumeConfig) persisted)

        it "restarts from the persisted point instead of start or Origin" $
            withSystemTempDirectory "cardano-keri-resume" $ \root -> do
                let coldPath = root <> "/cold"
                    warmPath = root <> "/warm"
                    configured = coldBootResumePoints resumeConfig
                    origin =
                        coldBootResumePoints
                            resumeConfig{csStartPoint = Nothing}

                cold <-
                    withRocksDBIndexer coldPath $
                        captureResumeCandidates resumeConfig
                cold `shouldBe` configured

                persisted <-
                    withRocksDBIndexer warmPath $ \handle -> do
                        seedFollowingBlocks handle seededPoints
                        persistedFollowingNewestFirst handle

                warm <-
                    withRocksDBIndexer warmPath $
                        captureResumeCandidates resumeConfig
                listToMaybe warm
                    `shouldBe` fmap
                        (headerPointFor resumeConfig)
                        (listToMaybe persisted)
                warm `shouldNotContain` configured
                warm `shouldNotContain` origin

captureResumeCandidates ::
    ChainSyncConfig ->
    IndexerHandle ->
    IO [HeaderPoint]
captureResumeCandidates config handle = do
    capturedRef <- newIORef []
    called <- newEmptyMVar
    let runner
            _epochSlots
            _networkMagic
            _socketPath
            _blockTracer
            _tipTracer
            _intersector
            candidates = do
                writeIORef capturedRef candidates
                putMVar called ()
                pure (Right ())
    withChainSyncFollowerUsing
        runner
        nullN2CTracer
        config
        handle
        $ \_follower -> do
            invoked <- timeout 5_000_000 (takeMVar called)
            case invoked of
                Nothing ->
                    fail
                        "ResumeSpec: timed out waiting for the chain-sync runner\
                        \ to receive resume candidates"
                Just () -> readIORef capturedRef

seedFollowingBlocks ::
    IndexerHandle ->
    [(SlotNo, BlockHash)] ->
    IO ()
seedFollowingBlocks handle points = do
    initial <- newFollowerState handle False
    _final <- foldM (seedFollowingBlock handle) initial points
    pure ()

seedFollowingBlock ::
    IndexerHandle ->
    IndexerFollowerState ->
    (SlotNo, BlockHash) ->
    IO IndexerFollowerState
seedFollowingBlock handle state (slot, blockHash) = do
    (next, processed) <-
        processFollowerBlock
            handle
            state
            100
            True
            slot
            blockHash
            []
    if processed
        then pure next
        else fail $ "ResumeSpec: follower declined seeded slot " <> show slot

persistedFollowingNewestFirst ::
    IndexerHandle ->
    IO [(SlotNo, BlockHash)]
persistedFollowingNewestFirst handle = do
    history <- getRollbackHistory handle
    pure . reverse $
        [ (slot, blockHash)
        | (slot, RollbackPoint{rpMeta = Just blockHash}) <- history
        ]

headerPointFor ::
    ChainSyncConfig ->
    (SlotNo, BlockHash) ->
    HeaderPoint
headerPointFor config point =
    case coldBootResumePoints config{csStartPoint = Just point} of
        [headerPoint] -> headerPoint
        unexpected ->
            error $
                "ResumeSpec: one configured point produced "
                    <> show (length unexpected)
                    <> " cold-boot candidates"

slotsOf :: [HeaderPoint] -> [Network.SlotNo]
slotsOf = fmap $ \case
    Network.Point (Network.Point.At (Network.Point.Block slot _hash)) -> slot
    Network.Point Network.Point.Origin ->
        error "ResumeSpec: warm resume candidates unexpectedly contained Origin"

strictlyDescending :: (Ord a) => [a] -> Bool
strictlyDescending values =
    and $ zipWith (>) values (drop 1 values)

seededPoints :: [(SlotNo, BlockHash)]
seededPoints =
    [ (SlotNo slot, taggedBlockHash slot)
    | slot <- [100, 110 .. 190]
    ]

taggedBlockHash :: Word64 -> BlockHash
taggedBlockHash slot =
    BlockHash (BS.replicate 32 . fromIntegral $ slot `div` 10)

resumeConfig :: ChainSyncConfig
resumeConfig =
    mkChainSyncConfig
        IndexerConfig
            { icSocketPath = "unused-resume-test.socket"
            , icNetworkMagic = 42
            , icByronEpochSlots = 21_600
            , icSecurityParamK = 100
            , icStartPoint =
                Just
                    ( SlotNo 10
                    , BlockHash (BS.replicate 32 0xEE)
                    )
            , icStorePath = "unused-resume-test-store"
            , icFundingAddrs = []
            , icBoardAddr = Nothing
            }
        testManifest

testManifest :: Manifest
testManifest =
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
                { checkpointAddressBech32 = testCheckpointAddress
                , checkpointPolicyId = "test-policy"
                }
        , manifestPublishedAt = "2026-07-30T00:00:00Z"
        , manifestScripts = []
        }

testCheckpointAddress :: Text
testCheckpointAddress =
    "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
