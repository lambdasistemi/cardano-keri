{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Indexer.StoreBinding
Description : Which configuration a store serves (#353)

A store of the index serves one configuration: a version 1 manifest, or one
release identity. Every opener first opens the database as it always did; the
database's own lock, held for as long as the opener has it open, is the only
exclusion. Inside that opening, before it follows, serves or queries, the
opener reads the record file inside the store directory:

* a record that matches the configuration: proceed; one that does not: refuse;
* no record, the store directory held no database before this opener opened it
  (missing or empty, observed immediately before the opening) and the database
  is empty: a fresh store, so the configuration is recorded (a temporary file in
  the store directory, then a rename) and the opener proceeds;
* no record and a store that already held a database, empty or not: a store of
  the manifest mode under its original configuration. A manifest opener proceeds
  exactly as it always did and writes nothing; a release opener refuses, and
  never binds it.

A refusal names both configurations, and a version 1 operation asked of a store
that records a release identity is refused the same way. A crash between opening
the database and writing the record leaves a store that already held a database
and has no record: the manifest mode's, which a release opener refuses. Nothing in this module reads or writes the record except
inside such an opening.
-}
module Cardano.KERI.Indexer.StoreBinding (
    Configuration (..),
    RecordedConfiguration (..),
    StoreBindingError (..),
    StoreModeMismatch (..),
    Before (..),
    createStoreForRelease,
    decideManifestOpen,
    decideReleaseOpen,
    observeStoreDirectory,
    decideLegacyOpenStore,
    parseRecord,
    renderStoreBindingError,
    storeRecordPath,
) where

import Cardano.KERI.AID.Application (RegistryIdentity (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..), registryIdentityOf)
import Cardano.KERI.ChainQuery.ReleaseIdentity (
    decodeReleaseIdentity,
    encodeReleaseIdentity,
 )
import Cardano.KERI.Indexer.Query.Tx (scanAllTx)
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Indexer (IndexerHandle (..))
import Control.Exception (Exception, IOException, SomeException, throwIO, try)
import Control.Monad (when)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Default.Class (def)
import Data.List (intercalate, isSuffixOf)
import Data.Maybe (fromMaybe)
import Database.KV.Transaction (RunTransaction (..))
import Database.RocksDB (Config (..), withDBCF)
import System.Directory (
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
    renameFile,
 )
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)

-- | The configuration a process opens a store under.
data Configuration
    = ManifestConfiguration
    | ReleaseConfiguration !ReleaseIdentity

-- | What a store records about the configuration it serves.
data RecordedConfiguration
    = RecordedManifest
    | -- | the whole release identity
      RecordedRelease !ReleaseIdentity
    deriving stock (Eq, Show)

-- | Why a store is not opened.
data StoreBindingError
    = -- | the store records this release identity; it was opened under the manifest
      RegistryStoreOpenedByManifest !ReleaseIdentity
    | -- | the store serves a manifest; it was opened under this release identity
      ManifestStoreOpenedByRelease !ReleaseIdentity
    | -- | the store records the first release identity; it was opened under the second
      RegistryStoreOpenedByOtherRelease !ReleaseIdentity !ReleaseIdentity
    | -- | the record of the store at this path cannot be read
      StoreRecordUnreadable !FilePath
    deriving stock (Eq, Show)

{- | A version 1 operation was asked of a store that serves a release identity
(thrown by the local write interpreter's scope).
-}
newtype StoreModeMismatch = StoreModeMismatch StoreBindingError
    deriving stock (Eq, Show)

instance Exception StoreModeMismatch

-- | The file that holds the record of the store at this path.
storeRecordPath :: FilePath -> FilePath
storeRecordPath store = store </> "keri-store-configuration.json"

-- | The configuration a record file's bytes record.
parseRecord :: ByteString -> Maybe RecordedConfiguration
parseRecord bytes = Aeson.decodeStrict bytes >>= fromValue
  where
    fromValue (Object o) =
        case KeyMap.lookup "configuration" o of
            Just (String "manifest") -> Just RecordedManifest
            Just (String "release") -> do
                identity <- KeyMap.lookup "release_identity" o
                either (const Nothing) (Just . RecordedRelease) $
                    decodeReleaseIdentity (BL.toStrict (Aeson.encode identity))
            _ -> Nothing
    fromValue _ = Nothing

recordOf :: Configuration -> ByteString
recordOf =
    BL.toStrict . Aeson.encode . \case
        ManifestConfiguration -> object ["configuration" .= ("manifest" :: String)]
        ReleaseConfiguration release ->
            object
                [ "configuration" .= ("release" :: String)
                , "release_identity" .= embedded release
                ]
  where
    embedded release = fromMaybe Null (Aeson.decodeStrict (encodeReleaseIdentity release) :: Maybe Value)

-- | What the store directory holds, read inside an opening of the database.
data Found
    = NoRecord
    | Record !RecordedConfiguration
    | Unreadable

readFound :: FilePath -> IO Found
readFound store = do
    present <- doesFileExist (storeRecordPath store)
    if not present
        then pure NoRecord
        else do
            contents <- try @IOException (BS.readFile (storeRecordPath store))
            pure $ case contents of
                Left _ -> Unreadable
                Right bytes -> maybe Unreadable Record (parseRecord bytes)

-- | What the store directory held before an opener opened the database.
data Before
    = -- | the directory is missing or empty
      NoDatabaseYet
    | -- | the directory holds files: a database was created here before
      HeldDatabase
    deriving stock (Eq, Show)

{- | Observe the store directory, immediately before opening the database in it.
The observation says nothing about the record; it tells a store never opened
from one that was, even if nothing was indexed in it.
-}
observeStoreDirectory :: FilePath -> IO Before
observeStoreDirectory store = do
    exists <- doesDirectoryExist store
    if not exists
        then pure NoDatabaseYet
        else do
            entries <- listDirectory store
            pure (if null entries then NoDatabaseYet else HeldDatabase)

-- | No rows and no resume point: nothing has been indexed in this database.
databaseIsEmpty :: IndexerHandle -> RunTransaction IO cf Cols op -> IO Bool
databaseIsEmpty handle runner = do
    points <- getResumePoints handle
    rows <- runTransaction runner scanAllTx
    pure (null points && null rows)

{- | Decide, inside an opening of the database at this store path, whether the
manifest mode may use the store, recording it when the store is fresh: no record,
the directory held no database before the opening and the database is empty.
Any other store without a record is the manifest mode's as it always was.
-}
decideManifestOpen ::
    FilePath ->
    Before ->
    IndexerHandle ->
    RunTransaction IO cf Cols op ->
    IO (Either StoreBindingError ())
decideManifestOpen store before handle runner =
    readFound store >>= \case
        Unreadable -> pure (Left (StoreRecordUnreadable (storeRecordPath store)))
        Record RecordedManifest -> pure (Right ())
        Record (RecordedRelease recorded) -> pure (Left (RegistryStoreOpenedByManifest recorded))
        NoRecord -> do
            empty <- databaseIsEmpty handle runner
            when (before == NoDatabaseYet && empty) (writeRecord store ManifestConfiguration)
            pure (Right ())

{- | Decide, inside an opening of the database at this store path, whether a
release identity may use it. The store must carry the record of this very
release identity, written by the opener that created the database
('createStoreForRelease'): an existing database without a record is a store of
the manifest mode, even when it is empty, and is refused.
-}
decideReleaseOpen :: FilePath -> ReleaseIdentity -> IO (Either StoreBindingError ())
decideReleaseOpen store release =
    readFound store >>= \case
        Unreadable -> refuse (StoreRecordUnreadable (storeRecordPath store))
        Record RecordedManifest -> refuse (ManifestStoreOpenedByRelease release)
        Record (RecordedRelease recorded)
            | recorded == release -> pure (Right ())
            | otherwise -> refuse (RegistryStoreOpenedByOtherRelease recorded release)
        NoRecord -> refuse (ManifestStoreOpenedByRelease release)
  where
    refuse = pure . Left

{- | Create the database of the store at this path, if it does not exist, and
record the release identity while still holding the handle of that creation.
The database is created with create-if-missing and error-if-exists, so the
store knows whether this call created it: 'True' when it did (and the record
is written), 'False' when a database already existed (nothing is written).
The column families are those the indexer opens with. A store held by another
process answers the database's lock failure.
-}
createStoreForRelease :: FilePath -> ReleaseIdentity -> IO Bool
createStoreForRelease store release = do
    outcome <-
        try @SomeException $
            withDBCF
                store
                def{createIfMissing = True, errorIfExists = True}
                [(name, def) | name <- indexerColumnFamilies]
                -- a failure to write the record is the writer's own, whatever it says
                (\_ -> try @SomeException (writeRecord store (ReleaseConfiguration release)))
    case outcome of
        Right (Right ()) -> pure True
        Right (Left writeFailure) -> throwIO writeFailure
        Left err
            | errorIfExistsResult err -> pure False
            | otherwise -> throwIO err
  where
    -- Only the create-only open's own result for an existing database: the binding
    -- renders a failure of the open as "<operation>: <status>: <path>: <reason>"
    -- with the system's or the database's reason last, so the reason is the tail of
    -- the message and the store path, which comes before it, cannot be mistaken for
    -- it. The lock, permission and every other failure of the open propagate unchanged.
    errorIfExistsResult err = "exists (error_if_exists is true))" `isSuffixOf` show err

-- | The column families of the indexer's database, as the pinned indexer opens it.
indexerColumnFamilies :: [String]
indexerColumnFamilies =
    [ "utxo-indexer.txin"
    , "utxo-indexer.address"
    , "utxo-indexer.observation"
    , "utxo-indexer.rollback"
    ]

{- | The same for a version 1 operation, which writes no record: refused when
the store records a release identity.
-}
decideLegacyOpenStore :: FilePath -> IO (Either StoreBindingError ())
decideLegacyOpenStore store =
    readFound store >>= \case
        Unreadable -> pure (Left (StoreRecordUnreadable (storeRecordPath store)))
        Record (RecordedRelease recorded) -> pure (Left (RegistryStoreOpenedByManifest recorded))
        _ -> pure (Right ())

{- | Record the configuration of a fresh store: written whole to a temporary
file in the store directory, then renamed, so a crash leaves no record or a
whole one.
-}
writeRecord :: FilePath -> Configuration -> IO ()
writeRecord store configuration = do
    createDirectoryIfMissing True store
    (temporary, handle) <- openTempFile store "keri-store-configuration.new"
    BS.hPut handle (recordOf configuration)
    hClose handle
    renameFile temporary (storeRecordPath store)

-- | The refusal as a line naming both configurations.
renderStoreBindingError :: StoreBindingError -> String
renderStoreBindingError = \case
    RegistryStoreOpenedByManifest recorded ->
        mismatch
            ("serves the release identity of registry " <> registry recorded)
            "a version 1 manifest"
    ManifestStoreOpenedByRelease release ->
        mismatch
            "serves a version 1 manifest"
            ("the release identity of registry " <> registry release)
    RegistryStoreOpenedByOtherRelease recorded release ->
        mismatch
            ("serves the release identity of registry " <> registry recorded)
            ( "another release identity, of registry "
                <> registry release
                <> " (differs in: "
                <> intercalate ", " (differingFields recorded release)
                <> ")"
            )
    StoreRecordUnreadable path ->
        "mode mismatch: the record of the store configuration at "
            <> path
            <> " cannot be read; the store is a version 1 manifest store or serves one release identity"
  where
    mismatch served requested =
        "mode mismatch: this store "
            <> served
            <> " and cannot be opened under "
            <> requested
            <> "; a store serves one configuration, a version 1 manifest or one release identity"
    registry release =
        let RegistryIdentity policy name = registryIdentityOf release
         in hex policy <> "/" <> hex name
    hex = BC.unpack . convertToBase Base16

-- | The fields in which two release identities differ, by name.
differingFields :: ReleaseIdentity -> ReleaseIdentity -> [String]
differingFields a b =
    [ name
    | (name, differs) <-
        [ ("network", riNetwork a /= riNetwork b)
        , ("application policy", rlApplicationPolicy (riRelease a) /= rlApplicationPolicy (riRelease b))
        , ("application credential", rlApplicationCredential (riRelease a) /= rlApplicationCredential (riRelease b))
        , ("state program", rlStateProgram (riRelease a) /= rlStateProgram (riRelease b))
        , ("state policy", rlStatePolicy (riRelease a) /= rlStatePolicy (riRelease b))
        , ("seed", riSeed a /= riSeed b)
        , ("checkpoint validator", riCheckpointValidator a /= riCheckpointValidator b)
        , ("deposit", riDeposit a /= riDeposit b)
        , ("freeze bond", riFreezeBond a /= riFreezeBond b)
        , ("premium", riPremium a /= riPremium b)
        , ("minimum ada", riMinimumAda a /= riMinimumAda b)
        , ("termination carrier", riTerminationCarrier a /= riTerminationCarrier b)
        , ("application parameters", riApplicationParameters a /= riApplicationParameters b)
        ]
    , differs
    ]
