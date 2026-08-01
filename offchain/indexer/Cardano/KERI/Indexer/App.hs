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
    QuerySettings (..),
    runQueryAppWith,
    runQueryApp,
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
import Cardano.KERI.Indexer.Query.Server (
    mkQueryApplication,
 )
import Cardano.KERI.Indexer.Query.Tx (
    QueryHandle (..),
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
import Cardano.Node.Client.UTxOIndexer.Columns (
    Cols,
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig,
    FollowerHandle (..),
    withChainSyncFollower,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle,
    withRocksDBIndexer,
    withRocksDBIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
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
import Database.KV.Transaction (
    RunTransaction,
 )
import Network.Wai (
    Application,
 )
import Network.Wai.Handler.Warp qualified as Warp
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

{- | 'FollowerSettings' plus the query service's own opt-env-conf listen
port (FR-9: @--port@\/@CKERI_PORT@, default 8080). FR-9 also requires
@ckeri-query@ to treat @--board-address@\/@CKERI_BOARD_ADDRESS@ as
mandatory even though the general follower keeps it optional; since
'Cardano.KERI.Indexer.Config.IndexerConfig' is outside this slice's
writable fence, that requirement is enforced at runtime in
'runQueryAppWith' rather than by re-declaring the option here.
-}
data QuerySettings = QuerySettings
    { qsFollower :: !FollowerSettings
    , qsPort :: !Int
    }
    deriving stock (Eq, Show)

instance Opt.HasParser QuerySettings where
    settingsParser = do
        qsFollower <- Opt.settingsParser
        qsPort <-
            Opt.setting
                [ Opt.reader Opt.auto
                , Opt.option
                , Opt.long "port"
                , Opt.env "CKERI_PORT"
                , Opt.value (8080 :: Int)
                , Opt.metavar "PORT"
                , Opt.help "HTTP listen port"
                ]
        pure QuerySettings{..}

{- | The injectable query composition, parameterized the same way
'runFollowerAppWith' is: the indexer-plus-transaction-runner opener, the
follower bring-up function, and the HTTP-serving action are all parameters
so tests can substitute an in-memory indexer, an injectable chain-sync
runner, and a non-binding HTTP stand-in. FR-1: one
'withRocksDBIndexerRunner' opens the one store and exposes the one
transaction runner the HTTP layer and the chain-sync follower share; the
follower's async is 'link'ed before the HTTP action starts serving, so a
follower failure takes the whole process down instead of leaving a stale
server answering from a store nothing is updating any more.
-}
runQueryAppWith ::
    (forall a. FilePath -> (forall cf op. IndexerHandle -> RunTransaction IO cf Cols op -> IO a) -> IO a) ->
    (Tracer IO N2CEvent -> ChainSyncConfig -> IndexerHandle -> (FollowerHandle -> IO ()) -> IO ()) ->
    (Int -> Application -> IO ()) ->
    QuerySettings ->
    IO ()
runQueryAppWith withIndexerRunner withFollower serveApp settings = do
    let follower = qsFollower settings
    manifest <- loadManifestOrDie (fsManifestPath follower)
    let chainSyncConfig = mkChainSyncConfig (fsIndexer follower) manifest
    boardAddress <- requireBoardAddress (icBoardAddr (fsIndexer follower))
    withIndexerRunner (icStorePath (fsIndexer follower)) $ \handle runner ->
        case mkCheckpointView handle manifest of
            Left err -> dieQueryConcisely err
            Right view ->
                withFollower nullN2CTracer chainSyncConfig handle $ \fh -> do
                    link (fhAsync fh)
                    let queryHandle =
                            QueryHandle
                                { qhRunner = runner
                                , qhCheckpointAddress = cvAddress view
                                , qhCheckpointPolicy = cvPolicy view
                                , qhBoardAddress = boardAddress
                                , qhReadiness = fhReadiness fh
                                }
                    serveApp (qsPort settings) (mkQueryApplication queryHandle)

requireBoardAddress :: Maybe Address -> IO Address
requireBoardAddress (Just addr) = pure addr
requireBoardAddress Nothing =
    dieQueryConcisely
        "--board-address / CKERI_BOARD_ADDRESS is required for ckeri-query"

dieQueryConcisely :: String -> IO a
dieQueryConcisely message = do
    hPutStrLn stderr ("ckeri-query: " <> message)
    exitFailure

-- | Production wiring: real RocksDB store+runner, real chain-sync follower, real Warp.
runQueryApp :: QuerySettings -> IO ()
runQueryApp =
    runQueryAppWith withRocksDBIndexerRunner withChainSyncFollower Warp.run
