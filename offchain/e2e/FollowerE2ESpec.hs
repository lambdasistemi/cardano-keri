{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : FollowerE2ESpec
Description : SC-1 live composition smoke for #175 (the follower library)

Proves the one live boundary #175 owns: devnet up, a real checkpoint
registration posted through the shared
'CheckpointTxBuilder.stagedCheckpointDevnetSocket' bring-up, the production
follower ('Cardano.KERI.Indexer.Follower.mkChainSyncConfig' +
'Cardano.Node.Client.UTxOIndexer.Follower.withChainSyncFollower') started
from a configured non-Origin point over the real N2C node socket, and the
registered datum read back from the follower's own store via
'Cardano.KERI.Indexer.Reads.checkpointForAid'. No Koios, no mocks, no
node-DB snapshot/restore, no N2C recorder/intersector: rollback exactness is
SC-2's property over the upstream store, not re-proved here (see
@docs/user/follower.md@ and @chain-follower#29@).
-}
module FollowerE2ESpec (spec) where

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
import Cardano.KERI.Indexer.Config (IndexerConfig (..))
import Cardano.KERI.Indexer.Follower (mkChainSyncConfig)
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
    checkpointForAid,
 )
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Node.Client.N2C.Trace (nullN2CTracer)
import Cardano.Node.Client.Provider (LedgerSnapshot (..), queryLedgerSnapshot)
import Cardano.Node.Client.Types (BlockPoint)
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig,
    FollowerHandle (..),
    withChainSyncFollower,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle,
    withRocksDBIndexer,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import CheckpointTxBuilder (
    CheckpointEnv (..),
    CheckpointInput (..),
    productionRegisterScenario,
    stagedCheckpointDevnetSocket,
 )
import Codec.Binary.Bech32 (
    dataPartFromBytes,
    encodeLenient,
    humanReadablePartFromText,
 )
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (link)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Text qualified as Text
import Ouroboros.Consensus.HardFork.Combinator.AcrossEras (OneEraHash (..))
import Ouroboros.Network.Block (Point (..), SlotNo (..))
import Ouroboros.Network.Point (WithOrigin (..))
import Ouroboros.Network.Point qualified as Network.Point
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.Timeout (timeout)
import Test.Hspec (Spec, describe, it)

spec :: Spec
spec =
    describe "#175 follower live leg" $
        it
            "SC-1: the production follower indexes a real checkpoint registration \
            \from a configured start point over a real N2C socket"
            liveComposition

liveComposition :: IO ()
liveComposition =
    stagedCheckpointDevnetSocket $ \sock env -> do
        -- The follower must be proved to start from a configured, non-Origin
        -- point rather than genesis: snapshot the tip strictly before the
        -- registration is posted, so the follower has to catch up over the
        -- gap and observe the registration transaction itself.
        preSnapshot <-
            withinSecs 30 "pre-registration tip snapshot" $
                queryLedgerSnapshot (envProvider env)
        startPoint <-
            case followerStartPoint (ledgerChainPoint preSnapshot) of
                Just point -> pure point
                Nothing -> fail "SC-1: pre-registration tip is Origin; cannot start from a concrete point"
        putLine $ "SC1_START_POINT " <> show startPoint

        checkpointInput <-
            withinSecs 300 "register a real checkpoint" $
                productionRegisterScenario env
        let datum = checkpointDatum checkpointInput
            aid = cdCesrAid datum
        putLine $ "SC1_REGISTERED aid=" <> show aid

        let storeDir = takeDirectory sock </> "follower-store"
        createDirectoryIfMissing True storeDir
        let followerConfig = mkFollowerIndexerConfig sock startPoint storeDir
            manifest = mkFollowerManifest env
            chainSyncConfig = mkChainSyncConfig followerConfig manifest

        putLine "SC1_FOLLOWER_STARTING"
        withRocksDBIndexer storeDir $ \handle ->
            withFollowerRunning chainSyncConfig handle $ do
                let view =
                        CheckpointView
                            { cvHandle = handle
                            , cvAddress = checkpointAddrBytes env
                            , cvPolicy = envCheckpointPolicy env
                            }
                found <- waitForCheckpoint "SC-1 follower read" view aid
                let matched = crDatum found == datum
                putLine $
                    "SC1_CHECKPOINT_FOUND aid="
                        <> show aid
                        <> " datum-match="
                        <> show matched
                unless matched $
                    fail
                        "SC-1: follower returned a datum that does not match the registered datum"
        putLine "SC1_FOLLOWER_STOPPED"

-- ---------------------------------------------------------------------------
-- Production follower bring-up (the module this smoke exists to prove)
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
    (Indexer.SlotNo, Indexer.BlockHash) ->
    FilePath ->
    IndexerConfig
mkFollowerIndexerConfig sock startPoint storeDir =
    IndexerConfig
        { icSocketPath = sock
        , icNetworkMagic = 42
        , icByronEpochSlots = 42
        , icSecurityParamK = 100
        , icStartPoint = Just startPoint
        , icStorePath = storeDir
        , icFundingAddrs = []
        , icBoardAddr = Nothing
        }

{- | Convert the LSQ-acquired 'LedgerSnapshot' chain point into the
@(SlotNo, BlockHash)@ pair 'IndexerConfig' and 'ChainSyncConfig' expect.
'Nothing' at Origin: SC-1 requires a concrete non-Origin start point.
-}
followerStartPoint ::
    BlockPoint -> Maybe (Indexer.SlotNo, Indexer.BlockHash)
followerStartPoint (Point Origin) = Nothing
followerStartPoint (Point (At (Network.Point.Block (SlotNo slot) blockHash))) =
    Just
        ( Indexer.SlotNo slot
        , Indexer.BlockHash (SBS.fromShort (getOneEraHash blockHash))
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
                { checkpointAddressBech32 = encodeAddressBech32 (checkpointAddrBytes env)
                , checkpointPolicyId = "test-policy"
                }
        , manifestPublishedAt = "2026-07-31T00:00:00Z"
        , manifestScripts = []
        }

checkpointAddr :: CheckpointEnv -> Addr
checkpointAddr env =
    Addr
        Testnet
        (ScriptHashObj (envCheckpointHash env))
        StakeRefNull

checkpointAddrBytes :: CheckpointEnv -> Indexer.Address
checkpointAddrBytes env =
    Indexer.Address (serialiseAddr (checkpointAddr env))

encodeAddressBech32 :: Indexer.Address -> Text.Text
encodeAddressBech32 (Indexer.Address bytes) =
    case humanReadablePartFromText "addr_test" of
        Left err -> error $ "encodeAddressBech32: invalid HRP: " <> show err
        Right hrp -> encodeLenient hrp (dataPartFromBytes bytes)

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

withinSecs :: Int -> String -> IO a -> IO a
withinSecs seconds label action =
    timeout (seconds * 1_000_000) action
        >>= maybe (fail (label <> ": timed out")) pure

putLine :: String -> IO ()
putLine = putStrLn
