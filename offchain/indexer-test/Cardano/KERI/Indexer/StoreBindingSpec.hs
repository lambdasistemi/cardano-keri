{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.Indexer.StoreBindingSpec
Description : A store serves one configuration (#353)

The checks run against real stores of the index (the database the service and
the commands open), because the decision is made inside that opening, under the
database's own lock. A store records, when a release-identity reader first
opens it, the whole release identity it serves (and a fresh store opened under
the manifest records that it is one); any other opening is refused, naming both
configurations, before it follows, serves or queries. An existing manifest
store, which has no record, keeps opening under a manifest and writes nothing.
-}
module Cardano.KERI.Indexer.StoreBindingSpec (spec, holdStoreOpen) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), OutputReference (..), RegistryIdentity (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..), registryIdentityOf)
import Cardano.KERI.ChainQuery.ReleaseIdentity (encodeReleaseIdentity)
import Cardano.KERI.Indexer.App (ReaderSettings (..), runReaderAppWith)
import Cardano.KERI.Indexer.ChainQuery (LocalSettings (..), withLocalQueryScope)
import Cardano.KERI.Indexer.Config (IndexerConfig (..))
import Cardano.KERI.Indexer.FollowerSpec (baseConfig)
import Cardano.KERI.Indexer.ReleaseFixtures (testRelease, writeManifest)
import Cardano.KERI.Indexer.StoreBinding (
    Configuration (..),
    RecordedConfiguration (..),
    StoreBindingError (..),
    StoreModeMismatch (..),
    createStoreForRelease,
    decideLegacyOpenStore,
    decideManifestOpen,
    decideReleaseOpen,
    observeStoreDirectory,
    parseRecord,
    renderStoreBindingError,
    storeRecordPath,
 )
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withRocksDBIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, concurrently, wait)
import Control.Exception (IOException, SomeException, finally, throwIO, try)
import Control.Monad (void, when)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.IORef (IORef, modifyIORef, newIORef, readIORef, writeIORef)
import Data.List (isInfixOf, isSuffixOf)
import Database.KV.Transaction (RunTransaction)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.Directory (
    Permissions,
    createDirectoryIfMissing,
    createFileLink,
    doesFileExist,
    getPermissions,
    setPermissions,
    writable,
 )
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hClose, hFlush, hGetLine, stderr, stdout)
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.Files (createNamedPipe)
import System.Posix.IO (OpenFileFlags (..), OpenMode (..), defaultFileFlags, fdToHandle, openFd)
import System.Process (CreateProcess (..), StdStream (CreatePipe), createProcess, proc, waitForProcess)
import Test.Hspec (Expectation, Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

-- | Open the store at a path as a process would, decide under a configuration, and close it.
openUnder :: FilePath -> Configuration -> IO (Either StoreBindingError ())
openUnder = openThen (pure ())

-- | Open and decide as a process does; when the decision lets the opener proceed, run the action while holding the store.
openThen :: IO () -> FilePath -> Configuration -> IO (Either StoreBindingError ())
openThen whileHolding store = \case
    ManifestConfiguration -> do
        before <- observeStoreDirectory store
        withRocksDBIndexerRunner store $ \handle runner ->
            decideManifestOpen store before handle runner >>= proceed
    ReleaseConfiguration release -> do
        _created <- createStoreForRelease store release
        withRocksDBIndexerRunner store $ \_ _ -> decideReleaseOpen store release >>= proceed
  where
    proceed decided = when (decided == Right ()) whileHolding >> pure decided

-- | Put a row in the store, as a follower of the manifest mode would have.
indexSomething :: FilePath -> IO ()
indexSomething store =
    withRocksDBIndexerRunner store $ \handle _ ->
        applyAtSlot
            handle
            (Indexer.SlotNo 7)
            (Indexer.BlockHash (BS.replicate 32 0x07))
            [UtxoCreate (Indexer.TxIn (BS.replicate 32 1) 0) (Indexer.Address (BS.replicate 29 0x61)) (Indexer.TxOut "row")]

recordBytes :: FilePath -> IO (Maybe ByteString)
recordBytes store = do
    present <- doesFileExist (storeRecordPath store)
    if present then Just <$> BS.readFile (storeRecordPath store) else pure Nothing

recordedOn :: FilePath -> IO (Maybe RecordedConfiguration)
recordedOn store = (>>= parseRecord) <$> recordBytes store

recordedOf :: Configuration -> RecordedConfiguration
recordedOf ManifestConfiguration = RecordedManifest
recordedOf (ReleaseConfiguration release) = RecordedRelease release

otherRelease :: ReleaseIdentity
otherRelease = testRelease{riSeed = OutputReference (BS.replicate 32 0x65) 4}

-- | Releases that differ from 'testRelease' in exactly one field, with its name.
labelled :: [(String, ReleaseIdentity)]
labelled =
    [ ("seed", testRelease{riSeed = OutputReference (BS.replicate 32 0x65) 4})
    , ("network", testRelease{riNetwork = 1})
    , ("application policy", testRelease{riRelease = (riRelease testRelease){rlApplicationPolicy = BS.replicate 28 0x01}})
    , ("application credential", testRelease{riRelease = (riRelease testRelease){rlApplicationCredential = BS.replicate 28 0x02}})
    , ("state program", testRelease{riRelease = (riRelease testRelease){rlStateProgram = BS.replicate 28 0x03}})
    , ("state policy", testRelease{riRelease = (riRelease testRelease){rlStatePolicy = BS.replicate 28 0x04}})
    , ("checkpoint validator", testRelease{riCheckpointValidator = BS.replicate 28 0x05})
    , ("deposit", testRelease{riDeposit = riDeposit testRelease + 1})
    , ("freeze bond", testRelease{riFreezeBond = riFreezeBond testRelease + 1})
    , ("premium", testRelease{riPremium = riPremium testRelease + 1})
    , ("minimum ada", testRelease{riMinimumAda = riMinimumAda testRelease + 1})
    , ("termination carrier", testRelease{riTerminationCarrier = riTerminationCarrier testRelease + 1})
    , ("application parameters", testRelease{riApplicationParameters = (riApplicationParameters testRelease){processTime = 1}})
    ]

variations :: [ReleaseIdentity]
variations = map snd labelled

-- | The registry of an identity as the message names it: policy and name, in hexadecimal.
registryText :: ReleaseIdentity -> String
registryText ri =
    let RegistryIdentity policy name = registryIdentityOf ri
     in hexText policy <> "/" <> hexText name
  where
    hexText = BC.unpack . convertToBase Base16

-- | What the refusal of a recorded identity under another must name: both registries and the one field.
namesDifference :: String -> ReleaseIdentity -> String -> Expectation
namesDifference field other message = do
    message `shouldSatisfy` (registryText testRelease `isInfixOf`)
    message `shouldSatisfy` (registryText other `isInfixOf`)
    message `shouldSatisfy` (("(differs in: " <> field <> ")") `isInfixOf`)

spec :: Spec
spec = describe "Cardano.KERI.Indexer.StoreBinding" $ do
    describe "a fresh store" $ do
        it "records the manifest, or the whole release identity, and the same configuration opens it again unchanged" $
            withSystemTempDirectory "binding" $ \dir ->
                mapM_
                    ( \(name, configuration) -> do
                        let store = dir </> name
                        openUnder store configuration >>= (`shouldBe` Right ())
                        recordedOn store >>= (`shouldBe` Just (recordedOf configuration))
                        before <- recordBytes store
                        openUnder store configuration >>= (`shouldBe` Right ())
                        recordBytes store >>= (`shouldBe` before)
                    )
                    [("manifest", ManifestConfiguration), ("release", ReleaseConfiguration testRelease)]
        it "is not a store whose opening crashed before the record: it already held a database, so a release opener refuses it and the manifest mode keeps it" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "crashed"
                crashed <- try @IOException (withRocksDBIndexerRunner store (\_ _ -> throwIO (userError "crash after open") :: IO ()))
                crashed `shouldSatisfy` either (const True) (const False)
                recordedOn store >>= (`shouldBe` Nothing)
                openUnder store (ReleaseConfiguration testRelease)
                    >>= (`shouldBe` Left (ManifestStoreOpenedByRelease testRelease))
                openUnder store ManifestConfiguration >>= (`shouldBe` Right ())
                recordedOn store >>= (`shouldBe` Nothing)
        it "is not an empty store a version 1 command created and released: a release opener refuses it, and the version 1 mode reopens it" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "empty-v1"
                    legacyOpening = withRocksDBIndexerRunner store (\_ _ -> decideLegacyOpenStore store)
                legacyOpening >>= (`shouldBe` Right ())
                recordedOn store >>= (`shouldBe` Nothing)
                openUnder store (ReleaseConfiguration testRelease)
                    >>= (`shouldBe` Left (ManifestStoreOpenedByRelease testRelease))
                recordedOn store >>= (`shouldBe` Nothing)
                legacyOpening >>= (`shouldBe` Right ())
                openUnder store ManifestConfiguration >>= (`shouldBe` Right ())
                recordedOn store >>= (`shouldBe` Nothing)
    describe "a store that records a release identity" $ do
        it "is refused under the manifest and under every release identity differing in one field, naming both, and keeps its record" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "registry"
                openUnder store (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                before <- recordBytes store
                openUnder store ManifestConfiguration
                    >>= (`shouldBe` Left (RegistryStoreOpenedByManifest testRelease))
                mapM_
                    ( \(field, other) -> do
                        refused <- openUnder store (ReleaseConfiguration other)
                        refused `shouldBe` Left (RegistryStoreOpenedByOtherRelease testRelease other)
                        either (namesDifference field other . renderStoreBindingError) (const (expectationFailure "not refused")) refused
                    )
                    labelled
                recordBytes store >>= (`shouldBe` before)
    describe "a store of the manifest mode" $ do
        it "recorded when created is refused under a release identity" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "manifest"
                openUnder store ManifestConfiguration >>= (`shouldBe` Right ())
                mapM_
                    ( \release ->
                        openUnder store (ReleaseConfiguration release)
                            >>= (`shouldBe` Left (ManifestStoreOpenedByRelease release))
                    )
                    (testRelease : variations)
        it "that predates records opens under the manifest and writes nothing, and is refused under a release identity" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "existing"
                indexSomething store
                openUnder store ManifestConfiguration >>= (`shouldBe` Right ())
                recordBytes store >>= (`shouldBe` Nothing)
                openUnder store (ReleaseConfiguration testRelease)
                    >>= (`shouldBe` Left (ManifestStoreOpenedByRelease testRelease))
                recordBytes store >>= (`shouldBe` Nothing)
        it "in a read-only parent still opens under the manifest" $
            withSystemTempDirectory "binding" $ \dir -> do
                let parent = dir </> "parent"
                    store = parent </> "existing"
                createDirectoryIfMissing True parent
                indexSomething store
                original <- getPermissions parent
                setPermissions parent (readOnly original)
                writableAnyway <- try @IOException (BS.writeFile (parent </> "probe") "x")
                -- (a process that may write anyway, such as root, cannot show the difference)
                result <- openUnder store ManifestConfiguration
                setPermissions parent original
                result `shouldBe` Right ()
                recordBytes store >>= (`shouldBe` Nothing)
                when (either (const False) (const True) writableAnyway) (pure ())
    describe "a record that cannot be read" $
        it "refuses the store under either configuration, and is left as it is" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "damaged"
                openUnder store (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                BS.writeFile (storeRecordPath store) "garbage"
                r1 <- openUnder store ManifestConfiguration
                r2 <- openUnder store (ReleaseConfiguration testRelease)
                r1 `shouldSatisfy` isUnreadable
                r2 `shouldSatisfy` isUnreadable
                recordBytes store >>= (`shouldBe` Just "garbage")
    describe "two openers racing on one fresh store" $ do
        it "let at most one proceed, and the record is the one that proceeded's" $
            withSystemTempDirectory "binding" $ \dir ->
                mapM_
                    ( \(trial, other) -> do
                        let store = dir </> ("race" <> show (trial :: Int))
                            racer configuration = do
                                outcome <- try @SomeException (openThen (threadDelay 40000) store configuration)
                                pure (either (const False) (== Right ()) outcome, configuration)
                        ((firstProceeded, firstConfiguration), (secondProceeded, secondConfiguration)) <-
                            concurrently (racer (ReleaseConfiguration testRelease)) (racer other)
                        -- at most one proceeds; contention on the database's lock may turn both away
                        when (firstProceeded && secondProceeded) $
                            expectationFailure ("both proceeded: trial " <> show trial <> ", other " <> describeConfiguration other)
                        recorded <- recordedOn store
                        when (firstProceeded || secondProceeded) $
                            recorded `shouldBe` Just (recordedOf (if firstProceeded then firstConfiguration else secondConfiguration))
                    )
                    (zip [1 ..] [o | o <- [ReleaseConfiguration otherRelease, ManifestConfiguration], _ <- [1 :: Int .. 6]])
        it "reach the same record by a symlink path as by the real path: refused or accepted as the record says, and turned away while another process holds the store" $
            withSystemTempDirectory "binding" $ \dir -> do
                let real = dir </> "real"
                    link = dir </> "link"
                openUnder real (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                createFileLink real link
                openUnder link (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                openUnder link (ReleaseConfiguration otherRelease)
                    >>= (`shouldBe` Left (RegistryStoreOpenedByOtherRelease testRelease otherRelease))
                openUnder link ManifestConfiguration
                    >>= (`shouldBe` Left (RegistryStoreOpenedByManifest testRelease))
                -- the exclusion between processes is the database's lock, which a symlink path reaches too
                held real $ do
                    busy <- try @SomeException (openUnder link (ReleaseConfiguration testRelease))
                    either (\e -> show e `shouldSatisfy` lockFailure) (const (expectationFailure "opened a held store")) busy
    describe "a version 1 operation" $ do
        it "is refused on a store that records a release identity, passes a manifest store and a store with no record, and writes nothing" $
            withSystemTempDirectory "binding" $ \dir -> do
                let registry = dir </> "registry"
                    manifest = dir </> "manifest"
                    legacy = dir </> "legacy"
                openUnder registry (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                openUnder manifest ManifestConfiguration >>= (`shouldBe` Right ())
                indexSomething legacy
                decideLegacyOpenStore registry >>= (`shouldBe` Left (RegistryStoreOpenedByManifest testRelease))
                decideLegacyOpenStore manifest >>= (`shouldBe` Right ())
                decideLegacyOpenStore legacy >>= (`shouldBe` Right ())
                decideLegacyOpenStore (dir </> "missing") >>= (`shouldBe` Right ())
                recordBytes legacy >>= (`shouldBe` Nothing)
        it "asked of the local write interpreter's scope answers the mode mismatch before the action runs" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "registry"
                openUnder store (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                ran <- newIORef False
                result <-
                    try @StoreModeMismatch $
                        withLocalQueryScope (LocalSettings store Nothing Nothing) $ \_ ->
                            writeIORef ran True
                result `shouldBe` Left (StoreModeMismatch (RegistryStoreOpenedByManifest testRelease))
                readIORef ran >>= (`shouldBe` False)
    describe "the registry service and a version 1 command on one path" $ do
        it "refuses a store a version 1 command created and released before the service started, even empty, and the command reopens it" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "v1"
                legacyCommand store >>= (`shouldBe` Right ())
                (proceeded, outcome, text) <- startRegistry withRocksDBIndexerRunner dir store testRelease
                outcome `shouldBe` Left (show (ExitFailure 1))
                text `shouldSatisfy` ("mode mismatch" `isInfixOf`)
                proceeded `shouldBe` False
                recordBytes store >>= (`shouldBe` Nothing)
                legacyCommand store >>= (`shouldBe` Right ())
        it "(later hook) has the registry service create the store first, so a version 1 command that opens it between the service's create-only open and its ordinary open is refused, and the service proceeds" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "fresh"
                writeIORef intervening []
                (proceeded, outcome, _) <- startRegistry interleavedOpener dir store testRelease
                outcome `shouldBe` Right ()
                proceeded `shouldBe` True
                readIORef intervening >>= (`shouldBe` [Left (StoreModeMismatch (RegistryStoreOpenedByManifest testRelease))])
                recordedOn store >>= (`shouldBe` Just (RecordedRelease testRelease))
        it "lets a version 1 command open and close the path after the service started and before its create-only open: the service refuses, writes no record, and the command reopens the store" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "fresh"
                    pipe = dir </> "release-input"
                createNamedPipe pipe 0o600
                -- keep a writer on the pipe, so the service waits for its input instead of reading end of file
                writer <- openFd pipe ReadWrite defaultFileFlags{nonBlock = True} >>= fdToHandle
                proceeded <- newIORef False
                -- the service has started and waits for its release identity input
                service <-
                    async $
                        captureStderr $
                            runReaderAppWith
                                withRocksDBIndexerRunner
                                (\_ _ _ _ -> writeIORef proceeded True)
                                (\_ _ -> pure ())
                                (ReaderSettings baseConfig{icStorePath = store, icBoardAddr = Just (Indexer.Address (BS.replicate 29 0x21))} Nothing (Just pipe) 8080)
                threadDelay 300000
                legacyCommand store >>= (`shouldBe` Right ())
                BS.hPut writer (encodeReleaseIdentity testRelease)
                hClose writer
                (outcome, text) <- wait service
                either (\e -> show e `shouldBe` show (ExitFailure 1)) (const (expectationFailure "the service proceeded")) outcome
                text `shouldSatisfy` ("mode mismatch" `isInfixOf`)
                readIORef proceeded >>= (`shouldBe` False)
                recordBytes store >>= (`shouldBe` Nothing)
                legacyCommand store >>= (`shouldBe` Right ())
        it "(control) a surviving record without its database is not replaced by another release: the service refuses before any writer runs, and the first record's bytes survive" $
            withSystemTempDirectory "binding" $ \dir -> do
                let kept = dir </> "kept"
                    other = dir </> "partial"
                openUnder kept (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                Just recordA <- recordBytes kept
                createDirectoryIfMissing True other
                BS.writeFile (storeRecordPath other) recordA
                (reached, _, _) <- startRegistry withRocksDBIndexerRunner dir other otherRelease
                reached `shouldBe` False
                recordBytes other >>= (`shouldBe` Just recordA)
        it "starts on a fresh path, restarts under the same release, and refuses another release" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "fresh"
                (first', firstOutcome, _) <- startRegistry withRocksDBIndexerRunner dir store testRelease
                (second', secondOutcome, _) <- startRegistry withRocksDBIndexerRunner dir store testRelease
                (third', thirdOutcome, text) <- startRegistry withRocksDBIndexerRunner dir store otherRelease
                (firstOutcome, secondOutcome) `shouldBe` (Right (), Right ())
                (first', second', third') `shouldBe` (True, True, False)
                thirdOutcome `shouldBe` Left (show (ExitFailure 1))
                text `shouldSatisfy` ("(differs in: seed)" `isInfixOf`)
    describe "the first open of a store" $
        it "answers the database's own lock failure when the store is held, and the existing-database result only when it is idle, whatever the path says" $
            withSystemTempDirectory "binding" $ \dir ->
                mapM_
                    ( \name -> do
                        let store = dir </> name
                        openUnder store (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                        -- idle and existing: the create-only open reports that the database exists
                        createStoreForRelease store testRelease >>= (`shouldBe` False)
                        -- held by another process: the contention failure of the first open itself
                        held store $ do
                            busy <- try @SomeException (createStoreForRelease store testRelease)
                            either (\e -> show e `shouldSatisfy` lockFailure) (\created -> expectationFailure ("answered " <> show created <> " for a held store")) busy
                        createStoreForRelease store testRelease >>= (`shouldBe` False)
                    )
                    ["exists-store", "(error_if_exists is true)", "store (error_if_exists is true)", "exists (error_if_exists is true)"]
    describe "a store held by another process" $ do
        it "answers the database's lock failure to a version 1 command, and names the mismatch once the store is idle" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "registry"
                openUnder store (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                held store $ do
                    busy <- try @SomeException (withLocalQueryScope (LocalSettings store Nothing Nothing) (\_ -> pure ()))
                    either (\e -> show e `shouldSatisfy` lockFailure) (const (expectationFailure "opened a held store")) busy
                idle <- try @StoreModeMismatch (withLocalQueryScope (LocalSettings store Nothing Nothing) (\_ -> pure ()))
                idle `shouldBe` Left (StoreModeMismatch (RegistryStoreOpenedByManifest testRelease))
        it "answers the database's lock failure to a registry reader of a version 1 store, and names the mismatch once the store is idle" $
            withSystemTempDirectory "binding" $ \dir -> do
                let store = dir </> "existing"
                indexSomething store
                releasePath <- writeReleaseFile dir
                let start =
                        captureStderr $
                            runReaderAppWith
                                withRocksDBIndexerRunner
                                (\_ _ _ _ -> pure ())
                                (\_ _ -> pure ())
                                (ReaderSettings baseConfig{icStorePath = store, icBoardAddr = Just (Indexer.Address (BS.replicate 29 0x21))} Nothing (Just releasePath) 8080)
                held store $ do
                    (busy, stderrText) <- start
                    case busy of
                        Left e -> show e `shouldSatisfy` lockFailure
                        Right () -> expectationFailure "opened a held store"
                    stderrText `shouldSatisfy` (not . isInfixOf "mode mismatch")
                (idle, message) <- start
                either (\e -> show e `shouldBe` show (ExitFailure 1)) (const (expectationFailure "not refused")) idle
                message `shouldSatisfy` ("mode mismatch" `isInfixOf`)
    describe "the messages" $
        it "name the recorded and the requested configuration in every refusal" $ do
            let message = renderStoreBindingError
            message (RegistryStoreOpenedByManifest testRelease) `shouldSatisfy` (registryText testRelease `isInfixOf`)
            message (RegistryStoreOpenedByManifest testRelease) `shouldSatisfy` ("manifest" `isInfixOf`)
            message (ManifestStoreOpenedByRelease testRelease) `shouldSatisfy` (registryText testRelease `isInfixOf`)
            message (ManifestStoreOpenedByRelease testRelease) `shouldSatisfy` ("manifest" `isInfixOf`)
    describe "runReaderAppWith" $
        it "refuses a store of the other configuration before it follows or serves, naming both configurations" $
            withSystemTempDirectory "binding" $ \dir -> do
                let registry = dir </> "registry"
                    existing = dir </> "existing"
                openUnder registry (ReleaseConfiguration testRelease) >>= (`shouldBe` Right ())
                indexSomething existing
                manifestPath <- writeManifest dir
                varied <-
                    mapM
                        ( \(field, other) -> do
                            let path = dir </> (field <> ".json")
                            BS.writeFile path (encodeReleaseIdentity other)
                            pure (field, other, path)
                        )
                        labelled
                releasePath <- writeRelease dir
                let startups =
                        [ (registry, Just manifestPath, Nothing, [registryText testRelease, "manifest"])
                        , (existing, Nothing, Just releasePath, [registryText testRelease, "manifest"])
                        ]
                            <> [ (registry, Nothing, Just path, [registryText testRelease, registryText other, "(differs in: " <> field <> ")"])
                               | (field, other, path) <- varied
                               ]
                mapM_
                    ( \(store, manifest, release, expected) -> do
                        proceeded <- newIORef False
                        before <- recordBytes store
                        (outcome, stderrText) <-
                            captureStderr $
                                runReaderAppWith
                                    withRocksDBIndexerRunner
                                    (\_ _ _ _ -> writeIORef proceeded True)
                                    (\_ _ -> writeIORef proceeded True)
                                    (ReaderSettings baseConfig{icStorePath = store, icBoardAddr = Just (Indexer.Address (BS.replicate 29 0x21))} manifest release 8080)
                        case outcome of
                            Left e | show e == show (ExitFailure 1) -> pure ()
                            other -> expectationFailure ("expected exit 1, got " <> show other)
                        mapM_ (\needle -> stderrText `shouldSatisfy` (needle `isInfixOf`)) expected
                        readIORef proceeded >>= (`shouldBe` False)
                        recordBytes store >>= (`shouldBe` before)
                    )
                    startups
  where
    isUnreadable (Left (StoreRecordUnreadable _)) = True
    isUnreadable _ = False
    readOnly :: Permissions -> Permissions
    readOnly p = p{writable = False}
    writeRelease dir = do
        let p = dir </> "release.json"
        BS.writeFile p (encodeReleaseIdentity testRelease)
        pure p

-- | Run an action and return its outcome with what it wrote to standard error.
captureStderr :: IO a -> IO (Either SomeException a, String)
captureStderr action =
    withSystemTempFile "stderr" $ \path handle -> do
        saved <- hDuplicate stderr
        hDuplicateTo handle stderr
        outcome <- try @SomeException action
        hFlush stderr
        hDuplicateTo saved stderr
        hClose saved
        hClose handle
        text <- readFile path
        length text `seq` pure (outcome, text)

-- | Open the store and hold it until standard input ends: the body of the holder process.
holdStoreOpen :: FilePath -> IO ()
holdStoreOpen path =
    withRocksDBIndexerRunner path $ \_ _ -> do
        putStrLn "held"
        hFlush stdout
        _ <- getContents >>= \rest -> length rest `seq` pure ()
        pure ()

-- | Run an action while ANOTHER PROCESS (this test executable in holder mode) holds the database of the store open.
held :: FilePath -> IO a -> IO a
held store action = do
    executable <- getExecutablePath
    (Just input, Just output, _, holder) <-
        createProcess (proc executable ["--hold-store", store]){std_in = CreatePipe, std_out = CreatePipe}
    ready <- hGetLine output
    ready `shouldBe` "held"
    action `finally` (hClose input >> void (waitForProcess holder))

{- | The text of the database's own lock failure when the store is held by another process.
| The RocksDB open error of a database another process holds: it names the lock file and ends with the system's reason.
-}
lockFailure :: String -> Bool
lockFailure shown =
    "IO error: While lock file: " `isInfixOf` shown
        && "/LOCK: Resource temporarily unavailable)" `isSuffixOf` shown

writeReleaseFile :: FilePath -> IO FilePath
writeReleaseFile dir = do
    let path = dir </> "held-release.json"
    BS.writeFile path (encodeReleaseIdentity testRelease)
    pure path

-- | A version 1 command as the local write interpreter runs it: it opens the store and closes it.
legacyCommand :: FilePath -> IO (Either StoreModeMismatch ())
legacyCommand store = try (withLocalQueryScope (LocalSettings store Nothing Nothing) (\_ -> pure ()))

-- | The opener of the service, preceded by a version 1 command that opens and closes the path.
interleavedOpener :: FilePath -> (forall cf op. IndexerHandle -> RunTransaction IO cf Cols op -> IO a) -> IO a
interleavedOpener path k = do
    between <- legacyCommand path
    modifyIORef intervening (between :)
    withRocksDBIndexerRunner path k

{-# NOINLINE intervening #-}
intervening :: IORef [Either StoreModeMismatch ()]
intervening = unsafePerformIO (newIORef [])

{- | Start the registry service of a release on a store path, with a follower that
only notes it was reached; return whether it proceeded, how it ended and what it wrote to standard error.
-}
startRegistry ::
    (forall a. FilePath -> (forall cf op. IndexerHandle -> RunTransaction IO cf Cols op -> IO a) -> IO a) ->
    FilePath ->
    FilePath ->
    ReleaseIdentity ->
    IO (Bool, Either String (), String)
startRegistry opener dir store release = do
    proceeded <- newIORef False
    let path = dir </> ("release-" <> show (riSeed release) <> ".json")
    BS.writeFile path (encodeReleaseIdentity release)
    (outcome, text) <-
        captureStderr $
            runReaderAppWith
                opener
                (\_ _ _ _ -> writeIORef proceeded True)
                (\_ _ -> pure ())
                (ReaderSettings baseConfig{icStorePath = store, icBoardAddr = Just (Indexer.Address (BS.replicate 29 0x21))} Nothing (Just path) 8080)
    reached <- readIORef proceeded
    pure (reached, either (Left . show) Right outcome, text)

describeConfiguration :: Configuration -> String
describeConfiguration ManifestConfiguration = "manifest"
describeConfiguration (ReleaseConfiguration _) = "release"
