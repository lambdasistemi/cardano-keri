{-# LANGUAGE ApplicativeDo #-}

{- |
Module      : Cardano.KERI.Indexer.App
Description : Composition root for the standalone runnable follower

Combines the existing 'Cardano.KERI.Indexer.Config.IndexerConfig' opt-env-conf
surface with a required deployment manifest path, loads the manifest, builds
the checkpoint read view and chain-sync configuration via
'Cardano.KERI.Indexer.Follower.mkChainSyncConfig', and runs the one-process
lifetime: 'Cardano.Node.Client.UTxOIndexer.Indexer.withRocksDBIndexer' owns the
store, 'Cardano.Node.Client.UTxOIndexer.Follower.withChainSyncFollower' runs
as its linked async, and 'Cardano.KERI.Indexer.Shell.runShell' stays in the
foreground on the same handle. 'runFollowerAppWith' parameterizes the indexer
opener, the follower bring-up function, and the interactive action so the
async-failure/lifetime seam is testable without a live node or RocksDB.
-}
module Cardano.KERI.Indexer.App (
    FollowerSettings (..),
    ManifestOutcome (..),
    loadManifestResult,
    loadManifestOrDie,
    mkCheckpointView,
    decodePolicyId,
    runFollowerAppWith,
    runFollowerApp,
) where

import Cardano.Crypto.Hash.Class (
    hashFromBytes,
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
    readManifest,
 )
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
    decodeAddress,
 )
import Cardano.KERI.Indexer.Follower (
    mkChainSyncConfig,
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
 )
import Cardano.KERI.Indexer.Shell (
    QueryAction,
    localQueryAction,
    runShell,
 )
import Cardano.Ledger.Hashes (
    ScriptHash (..),
 )
import Cardano.Ledger.Mary.Value (
    PolicyID (..),
 )
import Cardano.Node.Client.N2C.Trace (
    N2CEvent,
    nullN2CTracer,
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig,
    FollowerHandle (..),
    withChainSyncFollower,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle,
    withRocksDBIndexer,
 )
import Control.Concurrent.Async (
    link,
 )
import Control.Exception (
    IOException,
    try,
 )
import Control.Tracer (
    Tracer,
 )
import Data.Bifunctor (
    first,
 )
import Data.ByteString.Base16 qualified as Base16
import Data.Text (
    Text,
 )
import Data.Text.Encoding qualified as TE
import OptEnvConf qualified as Opt
import System.Exit (
    exitFailure,
 )
import System.IO (
    hPutStrLn,
    stderr,
 )

-- | 'IndexerConfig' plus the deployment manifest path #188 additionally needs.
data FollowerSettings = FollowerSettings
    { fsIndexer :: !IndexerConfig
    , fsManifestPath :: !FilePath
    }
    deriving stock (Eq, Show)

instance Opt.HasParser FollowerSettings where
    settingsParser = do
        fsIndexer <- Opt.settingsParser :: Opt.Parser IndexerConfig
        fsManifestPath <-
            Opt.setting
                [ Opt.reader Opt.str
                , Opt.option
                , Opt.long "manifest-path"
                , Opt.env "CKERI_MANIFEST_PATH"
                , Opt.metavar "PATH"
                , Opt.help "Deployment manifest JSON path"
                ]
        pure FollowerSettings{..}

-- | The outcome of attempting to load and parse the deployment manifest.
data ManifestOutcome
    = ManifestLoaded !Manifest
    | ManifestLoadFailed !String
    deriving stock (Eq, Show)

{- | Read and parse the manifest at the given path, turning a missing file or
invalid JSON/schema into a 'ManifestLoadFailed' rather than an uncaught
exception.
-}
loadManifestResult :: FilePath -> IO ManifestOutcome
loadManifestResult path = do
    outcome <- try @IOException (readManifest path)
    pure $ case outcome of
        Left ioerr ->
            ManifestLoadFailed ("cannot read manifest " <> path <> ": " <> show ioerr)
        Right (Left err) ->
            ManifestLoadFailed ("invalid manifest at " <> path <> ": " <> err)
        Right (Right manifest) -> ManifestLoaded manifest

-- | Load the manifest, or print a concise error and exit non-zero.
loadManifestOrDie :: FilePath -> IO Manifest
loadManifestOrDie path = do
    outcome <- loadManifestResult path
    case outcome of
        ManifestLoaded manifest -> pure manifest
        ManifestLoadFailed message -> dieConcisely message

dieConcisely :: String -> IO a
dieConcisely message = do
    hPutStrLn stderr ("ckeri-follower: " <> message)
    exitFailure

{- | Build the checkpoint read view from the manifest's checkpoint address and
policy, rejecting an invalid bech32 address or policy hex.
-}
mkCheckpointView :: IndexerHandle -> Manifest -> Either String CheckpointView
mkCheckpointView handle manifest = do
    address <- decodeAddress (checkpointAddressBech32 checkpoint)
    policy <- decodePolicyId (checkpointPolicyId checkpoint)
    Right CheckpointView{cvHandle = handle, cvAddress = address, cvPolicy = policy}
  where
    checkpoint = manifestCheckpoint manifest

-- | Decode a manifest's hex checkpoint policy id into a ledger 'PolicyID'.
decodePolicyId :: Text -> Either String PolicyID
decodePolicyId hex = do
    bytes <- first ("invalid policy id hex: " <>) (Base16.decode (TE.encodeUtf8 hex))
    case hashFromBytes bytes of
        Just h -> Right (PolicyID (ScriptHash h))
        Nothing -> Left "policy id must decode to exactly 28 bytes"

{- | The injectable composition: the indexer opener, the follower bring-up
function, and the interactive action are all parameters so tests can
substitute an in-memory indexer, an injectable 'Cardano.Node.Client.N2C.ChainSync.ChainSyncRunner',
and a non-terminal interactive stand-in.
-}
runFollowerAppWith ::
    (forall a. FilePath -> (IndexerHandle -> IO a) -> IO a) ->
    (Tracer IO N2CEvent -> ChainSyncConfig -> IndexerHandle -> (FollowerHandle -> IO ()) -> IO ()) ->
    (QueryAction -> FollowerHandle -> IO ()) ->
    FollowerSettings ->
    IO ()
runFollowerAppWith withIndexer withFollower runInteractive settings = do
    manifest <- loadManifestOrDie (fsManifestPath settings)
    let chainSyncConfig = mkChainSyncConfig (fsIndexer settings) manifest
    withIndexer (icStorePath (fsIndexer settings)) $ \handle ->
        case mkCheckpointView handle manifest of
            Left err -> dieConcisely err
            Right view ->
                withFollower nullN2CTracer chainSyncConfig handle $ \fh -> do
                    link (fhAsync fh)
                    runInteractive (localQueryAction view fh) fh

-- | Production wiring: real RocksDB store, real chain-sync follower, real shell.
runFollowerApp :: FollowerSettings -> IO ()
runFollowerApp =
    runFollowerAppWith withRocksDBIndexer withChainSyncFollower (\qa _fh -> runShell qa)
