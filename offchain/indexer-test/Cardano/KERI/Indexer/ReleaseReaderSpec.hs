{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.ReleaseReaderSpec
Description : The reader configured by a release identity, beside the manifest mode (#353)

Checks that a reader process configured by a release identity file follows the
release's checkpoint validator, plus the funding and board addresses, and
answers the classified checkpoints; that it takes exactly one of the two
configurations; and that, over the same kind of store holding an output of
each generation, each mode reads only its own.
-}
module Cardano.KERI.Indexer.ReleaseReaderSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..), KeyMaterial (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.ChainQuery.ReleaseIdentity (encodeReleaseIdentity)
import Cardano.KERI.Indexer.App (
    ReaderConfiguration (..),
    ReaderSettings (..),
    readerConfiguration,
    runReaderAppWith,
 )
import Cardano.KERI.Indexer.Codecs (checkpointAddressOf)
import Cardano.KERI.Indexer.Config (IndexerConfig (..))
import Cardano.KERI.Indexer.Follower (mkReleaseChainSyncConfig)
import Cardano.KERI.Indexer.FollowerSpec (baseConfig)
import Cardano.KERI.Indexer.ReleaseFixtures
import Cardano.Ledger.Address (Addr, decodeAddr)
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (..))
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig (..),
    FollowerHandle (..),
    InterestSet (..),
    Readiness (..),
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel)
import Control.Exception (finally, try)
import Control.Monad (forever)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BSL
import Data.IORef (modifyIORef, newIORef, readIORef, writeIORef)
import Data.List (isInfixOf)
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import Network.HTTP.Types (statusCode)
import Network.Wai (Application, defaultRequest)
import Network.Wai.Test (SResponse (..), request, runSession, setPath)
import OptEnvConf qualified as Opt
import OptEnvConf.Args qualified as OptArgs
import OptEnvConf.Capability qualified as OptCapability
import OptEnvConf.EnvMap qualified as OptEnv
import OptEnvConf.Run qualified as OptRun
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (IOMode (..), hClose, hFlush, stderr, withFile)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldContain, shouldSatisfy)

rawA, rawB :: ByteString
rawA = BS.replicate 32 0x31
rawB = BS.replicate 32 0x32

boardAddress :: Indexer.Address
boardAddress = Indexer.Address (BS.replicate 29 0x21)

fundingAddress :: Indexer.Address
fundingAddress = Indexer.Address (BS.replicate 29 0x22)

config :: IndexerConfig
config = baseConfig{icFundingAddrs = [fundingAddress], icBoardAddr = Just boardAddress}

spec :: Spec
spec = describe "the reader configured by a release identity" $ do
    describe "mkReleaseChainSyncConfig" $
        it "follows the release's checkpoint validator, the funding and the board addresses, and nothing else" $
            mapM_
                ( \ri -> case csInterestSet (mkReleaseChainSyncConfig config ri) of
                    IndexAddressSet addresses ->
                        addresses
                            `shouldBe` Set.fromList [checkpointAddressOf ri, fundingAddress, boardAddress]
                    _ -> expectationFailure "expected an address interest set"
                )
                [testRelease, otherRegistry, testRelease{riNetwork = 1}]
    describe "readerConfiguration" $ do
        let settings m r = ReaderSettings config m r 8080 Nothing
        it "takes the manifest alone, or the release identity alone" $ do
            readerConfiguration (settings (Just "m.json") Nothing) `shouldBe` Right (ReaderManifest "m.json")
            readerConfiguration (settings Nothing (Just "r.json")) `shouldBe` Right (ReaderRelease "r.json")
        it "refuses both and neither, naming the choice" $
            mapM_
                ( \s -> case readerConfiguration s of
                    Left message -> do
                        message `shouldContain` "--manifest-path"
                        message `shouldContain` "--release-identity-path"
                    Right c -> expectationFailure ("accepted " <> show c)
                )
                [settings (Just "m.json") (Just "r.json"), settings Nothing Nothing]
    describe "settings parser" $ do
        it "parses the release identity path from argv and from its environment variable" $ do
            fromArgv <- parseSettings (base <> ["--release-identity-path", "/tmp/r.json"]) []
            rdReleasePath fromArgv `shouldBe` Just "/tmp/r.json"
            rdManifestPath fromArgv `shouldBe` Nothing
            fromEnv <- parseSettings base [("CKERI_RELEASE_IDENTITY_PATH", "/tmp/e.json")]
            rdReleasePath fromEnv `shouldBe` Just "/tmp/e.json"
        it "still parses the manifest path as before" $ do
            parsed <- parseSettings (base <> ["--manifest-path", "/tmp/m.json"]) []
            rdManifestPath parsed `shouldBe` Just "/tmp/m.json"
            rdReleasePath parsed `shouldBe` Nothing
    describe "the two modes over the same kind of store" $ do
        it "each mode answers its own generation's output and not the other's" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                manifestPath <- writeManifest dir
                releasePath <- writeRelease dir
                let seeded = [legacyCreate, registryCreate]
                [manifestA, manifestB] <- serveOne dir "manifest" (Just manifestPath) Nothing seeded [aidText rawA, aidText rawB]
                [releaseA, releaseB] <- serveOne dir "release" Nothing (Just releasePath) seeded [aidText rawA, aidText rawB]
                -- the manifest mode finds the version 1 checkpoint of AID A only
                manifestA `shouldContain` hexOfTx 1
                manifestB `shouldContain` "\"checkpoint\":null"
                -- the release mode finds the registry checkpoint of AID B only
                releaseB `shouldContain` hexOfTx 2
                releaseA `shouldContain` "\"checkpoint\":null"
        it "serves a pending termination as no checkpoint" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                releasePath <- writeRelease dir
                [answer] <-
                    serveOne
                        dir
                        "release"
                        Nothing
                        (Just releasePath)
                        [UtxoCreate (txInAt 3) (checkpointAddressOf testRelease) (pendingOutput testRelease rawA (riMinimumAda testRelease))]
                        [aidText rawA]
                answer `shouldContain` "\"checkpoint\":null"
        it "answers watchability from the classified holdings: a live checkpoint's witnesses against the board, and not present for a pending termination or no checkpoint" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                releasePath <- writeRelease dir
                let witnesses = [BS.replicate 32 0x91, BS.replicate 32 0x92, BS.replicate 32 0x93]
                    keys = (lvKeys (liveFacts rawB)){kmWitnesses = witnesses}
                    live = liveShaped keys (5, 2, 1) rawB
                    seeded =
                        [ UtxoCreate (txInAt 2) (checkpointAddressOf testRelease) (liveOutputWith testRelease live rawB 0)
                        , UtxoCreate (txInAt 3) (checkpointAddressOf testRelease) (pendingOutput testRelease rawA (riMinimumAda testRelease))
                        ]
                answers <- servedAnswers dir "release" Nothing (Just releasePath) seeded ["/watchability/" <> aidText rawB, "/watchability/" <> aidText rawA, "/watchability/" <> aidText (BS.replicate 32 0x77), "/board", "/ready"]
                map fst answers `shouldBe` [200, 200, 200, 200, 200]
                let body n = snd (answers !! n)
                body 0 `shouldContain` "\"checkpoint_present\":true"
                body 0 `shouldContain` "\"witnesses_declared\":3"
                body 0 `shouldContain` "\"witnesses_listed\":0"
                body 1 `shouldContain` "\"checkpoint_present\":false"
                body 2 `shouldContain` "\"checkpoint_present\":false"
        it "follows the release's validator in release mode and the manifest's address in manifest mode" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                manifestPath <- writeManifest dir
                releasePath <- writeRelease dir
                seen <- newIORef ([] :: [(String, InterestSet)])
                let capture mode path manifest release =
                        runReaderAppWith
                            (\_ act -> withInMemoryIndexerRunner act)
                            (\_ cfg _ k -> modifyIORef seen ((mode, csInterestSet cfg) :) >> readyHandle k)
                            (\_ _ -> pure ())
                            (ReaderSettings config{icStorePath = dir </> path} manifest release 8080 (Just "1000000"))
                capture "manifest" "s1" (Just manifestPath) Nothing
                capture "release" "s2" Nothing (Just releasePath)
                interest <- readIORef seen
                lookup "release" interest
                    `shouldBe` Just (IndexAddressSet (Set.fromList [checkpointAddressOf testRelease, fundingAddress, boardAddress]))
                lookup "manifest" interest `shouldBe` Just (IndexAddressSet (Set.fromList [manifestAddress, fundingAddress, boardAddress]))
    describe "the ceiling of the identity read, a setting of the registry service" $ do
        it "is read from the command line or from CKERI_MAX_TIP_LAG_SLOTS, the command line first, and is the ceiling the identity answers carry" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                releasePath <- writeRelease dir
                mapM_
                    ( \(name, extra, environment, expected) -> do
                        (started, _) <- startReader dir name (["--release-identity-path", releasePath] <> extra) environment ["/identity/" <> aidText rawA]
                        case started of
                            Served [(code, body)] -> do
                                (name, code) `shouldBe` (name, 200)
                                body `shouldContain` ("\"max_tip_lag_slots\":" <> expected)
                            other -> expectationFailure (name <> ": " <> show other)
                    )
                    [ ("flag", ["--max-tip-lag-slots", "17"], [], "17")
                    , ("environment", [], [("CKERI_MAX_TIP_LAG_SLOTS", "400")], "400")
                    , ("flag beats environment", ["--max-tip-lag-slots", "0"], [("CKERI_MAX_TIP_LAG_SLOTS", "400")], "0")
                    ]
        it "must be given: without it the release mode exits non-zero naming the setting, before the store is created or opened and before the follower starts" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                releasePath <- writeRelease dir
                (started, effects) <- startReader dir "absent" ["--release-identity-path", releasePath] [] ["/ready"]
                started `shouldSatisfy` refusedNaming ["--max-tip-lag-slots", "CKERI_MAX_TIP_LAG_SLOTS"]
                effects `shouldBe` Effects{opened = False, followed = False, storeCreated = False}
        it "must be a non-negative whole number: every other value, from the flag or from the environment, is refused by name before the store is created or opened" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                releasePath <- writeRelease dir
                mapM_
                    ( \(n, value) ->
                        mapM_
                            ( \(source, extra, environment) -> do
                                (started, effects) <- startReader dir ("bad-" <> show n <> source) (["--release-identity-path", releasePath] <> extra) environment ["/ready"]
                                (value, source, started) `shouldSatisfy` (\(_, _, s) -> refusedNaming ["--max-tip-lag-slots"] s)
                                (value, source, effects) `shouldBe` (value, source, Effects{opened = False, followed = False, storeCreated = False})
                            )
                            [("-flag", ["--max-tip-lag-slots=" <> value], []), ("-env", [], [("CKERI_MAX_TIP_LAG_SLOTS", value)])]
                    )
                    (zip [0 :: Int ..] ["", "abc", "-1", "1.5", "1e3", " 17", "17 ", "0x11", "+5", "17 slots"])
        it "accepts zero and other whole numbers, and starts the follower and serves" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                releasePath <- writeRelease dir
                mapM_
                    ( \(n, value) -> do
                        (started, effects) <- startReader dir ("good-" <> show n) ["--release-identity-path", releasePath, "--max-tip-lag-slots", value] [] ["/ready"]
                        started `shouldSatisfy` (\case Served [(200, _)] -> True; _ -> False)
                        effects `shouldBe` Effects{opened = True, followed = True, storeCreated = True}
                    )
                    (zip [0 :: Int ..] ["0", "1", "17", "400", "100000000000000000000"])
        it "is not read by the manifest mode: every value of the flag and of the variable, absent, valid or malformed, leaves the service answering exactly as without it" $
            withSystemTempDirectory "release-reader" $ \dir -> do
                manifestPath <- writeManifest dir
                let paths = ["/ready", "/checkpoint/" <> aidText rawA, "/board", "/watchability/" <> aidText rawA]
                    arguments = ["--manifest-path", manifestPath]
                (baseline, _) <- startReader dir "manifest-base" arguments [] paths
                case baseline of
                    Served answers -> map fst answers `shouldBe` [200, 200, 200, 200]
                    other -> expectationFailure ("the manifest mode did not serve: " <> show other)
                mapM_
                    ( \(n, extra, environment) -> do
                        (started, effects) <- startReader dir ("manifest-" <> show n) (arguments <> extra) environment paths
                        (extra, environment, started) `shouldSatisfy` (\(_, _, s) -> s == baseline)
                        effects `shouldBe` Effects{opened = True, followed = True, storeCreated = True}
                    )
                    [ (n, extra, environment)
                    | (n, (extra, environment)) <-
                        zip
                            [0 :: Int ..]
                            [ (["--max-tip-lag-slots", "17"], [])
                            , (["--max-tip-lag-slots", "garbage"], [])
                            , (["--max-tip-lag-slots=-1"], [])
                            , ([], [("CKERI_MAX_TIP_LAG_SLOTS", "400")])
                            , ([], [("CKERI_MAX_TIP_LAG_SLOTS", "garbage")])
                            , ([], [("CKERI_MAX_TIP_LAG_SLOTS", "")])
                            ]
                    ]
  where
    base =
        [ "--node-socket"
        , "/tmp/n.socket"
        , "--network-magic"
        , "1"
        , "--byron-epoch-slots"
        , "21600"
        , "--security-param-k"
        , "2160"
        , "--store-path"
        , "/tmp/store"
        , "--board-address"
        , "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
        ]
    parseSettings args environment = do
        result <-
            OptRun.runParserOn
                OptCapability.allCapabilities
                Nothing
                (Opt.settingsParser :: Opt.Parser ReaderSettings)
                (OptArgs.parseArgs args)
                (OptEnv.parse environment)
                Nothing
        either (\e -> expectationFailure (show e) >> error "parse") pure result

hexOfTx :: Int -> String
hexOfTx n = concat (replicate 32 (let h = "0123456789abcdef" in [h !! (n `div` 16), h !! (n `mod` 16)]))

writeRelease :: FilePath -> IO FilePath
writeRelease dir = do
    let path = dir </> "release.json"
    BS.writeFile path (encodeReleaseIdentity testRelease)
    pure path

-- | A version 1 checkpoint of AID A under the manifest's policy and address.
legacyCreate :: UtxoOp
legacyCreate =
    UtxoCreate
        (txInAt 1)
        manifestAddress
        ( outputAt
            (fromJust (decodeAddr (Indexer.unAddress manifestAddress) :: Maybe Addr))
            5_000_000
            [(manifestPolicyBytes, deriveAidAssetName rawA, 1)]
            (Just (datumOf (liveFacts rawA)))
        )
  where
    manifestPolicyBytes = BS.pack (map fromIntegral [0x0c, 0x16, 0xc1, 0x2c, 0xe8, 0xca, 0x60, 0x87, 0x2c, 0xad, 0xd5, 0x45, 0xd1, 0x28, 0x2f, 0x07, 0xdc, 0x93, 0xb5, 0xd2, 0x2a, 0x13, 0x4e, 0x44, 0x25, 0x35, 0x57, 0x34 :: Int])

-- | A checkpoint of AID B in the registry of the test release.
registryCreate :: UtxoOp
registryCreate =
    UtxoCreate (txInAt 2) (checkpointAddressOf testRelease) (liveOutput testRelease rawB False 0)

ready :: Readiness
ready =
    Readiness
        { rProcessedSlot = Just (Indexer.SlotNo 100)
        , rTipSlot = Just (Indexer.SlotNo 100)
        , rUpstream = UpstreamConnected
        , rUpdatedAt = UTCTime (fromGregorian 2026 1 1) 0
        }

readyHandle :: (FollowerHandle -> IO ()) -> IO ()
readyHandle k = do
    a <- async (forever (threadDelay maxBound))
    k FollowerHandle{fhReadiness = pure ready, fhAsync = a}
    cancel a

{- | Run the reader process in one mode over a fresh store holding these
outputs; inside the process, ask its HTTP application for the checkpoint of
each AID and return the bodies.
-}
serveOne ::
    FilePath ->
    FilePath ->
    Maybe FilePath ->
    Maybe FilePath ->
    [UtxoOp] ->
    [ByteString] ->
    IO [String]
serveOne dir name manifest release ops aids = do
    bodies <- newIORef []
    runReaderAppWith
        (\_ act -> withInMemoryIndexerRunner act)
        ( \_ _ handle k -> do
            applyAtSlot handle (Indexer.SlotNo 100) (Indexer.BlockHash (BS.replicate 32 0x0c)) ops
            readyHandle k
        )
        ( \_ application -> do
            answers <- mapM (answerWith application) aids
            writeIORef bodies answers
        )
        (ReaderSettings config{icStorePath = dir </> name} manifest release 8080 (Just "1000000"))
    readIORef bodies
  where
    answerWith :: Application -> ByteString -> IO String
    answerWith application aid = do
        response <- runSession (request (setPath defaultRequest ("/checkpoint/" <> aid))) application
        pure (BC.unpack (BSL.toStrict (simpleBody response)))

-- | The status code and body of the reader's answer to each GET path, over a store holding these outputs.
servedAnswers :: FilePath -> FilePath -> Maybe FilePath -> Maybe FilePath -> [UtxoOp] -> [ByteString] -> IO [(Int, String)]
servedAnswers dir name manifest release ops paths = do
    answers <- newIORef []
    runReaderAppWith
        (\_ act -> withInMemoryIndexerRunner act)
        ( \_ _ handle k -> do
            applyAtSlot handle (Indexer.SlotNo 100) (Indexer.BlockHash (BS.replicate 32 0x0c)) ops
            readyHandle k
        )
        ( \_ application -> do
            responses <- mapM (\path -> runSession (request (setPath defaultRequest path)) application) paths
            writeIORef answers [(statusCode (simpleStatus r), BC.unpack (BSL.toStrict (simpleBody r))) | r <- responses]
        )
        (ReaderSettings config{icStorePath = dir </> name} manifest release 8080 (Just "1000000"))
    readIORef answers

-- ---------------------------------------------------------------------------
-- Starting the reader process under settings parsed from arguments and the environment

-- | What starting the reader came to: it refused (the exit status and what it said), or served and answered these paths.
data Start = Refused Int String | Served [(Int, String)]
    deriving stock (Eq, Show)

-- | What the start did before it refused or served: opened a store runner, started the follower, created the store directory.
data Effects = Effects {opened :: Bool, followed :: Bool, storeCreated :: Bool}
    deriving stock (Eq, Show)

-- | A refusal with a non-zero status whose message names each of these settings.
refusedNaming :: [String] -> Start -> Bool
refusedNaming names = \case
    Refused code said -> code /= 0 && all (`isInfixOf` said) names
    Served _ -> False

readerArguments :: FilePath -> [String]
readerArguments store =
    [ "--node-socket"
    , "/tmp/n.socket"
    , "--network-magic"
    , "1"
    , "--byron-epoch-slots"
    , "21600"
    , "--security-param-k"
    , "2160"
    , "--store-path"
    , store
    , "--board-address"
    , "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
    ]

{- | Parse the reader's settings from these arguments and environment variables with the production
parser, then start the reader in-process over a store at @dir/name@ with a node that is ready, and ask
its application these paths.
-}
startReader :: FilePath -> FilePath -> [String] -> [(String, String)] -> [ByteString] -> IO (Start, Effects)
startReader dir name extra environment paths = do
    let store = dir </> name
    parsed <-
        OptRun.runParserOn
            OptCapability.allCapabilities
            Nothing
            (Opt.settingsParser :: Opt.Parser ReaderSettings)
            (OptArgs.parseArgs (readerArguments store <> extra))
            (OptEnv.parse environment)
            Nothing
    settings <- either (\e -> expectationFailure ("the settings did not parse: " <> show e) >> fail "parse") pure parsed
    openedRef <- newIORef False
    followedRef <- newIORef False
    answersRef <- newIORef []
    (outcome, said) <-
        capturingStderr dir $
            try @ExitCode $
                runReaderAppWith
                    (\_ act -> writeIORef openedRef True >> withInMemoryIndexerRunner act)
                    ( \_ _ handle k -> do
                        writeIORef followedRef True
                        applyAtSlot handle (Indexer.SlotNo 100) (Indexer.BlockHash (BS.replicate 32 0x0c)) []
                        readyHandle k
                    )
                    ( \_ application -> do
                        responses <- mapM (\path -> runSession (request (setPath defaultRequest path)) application) paths
                        writeIORef answersRef [(statusCode (simpleStatus r), BC.unpack (BSL.toStrict (simpleBody r))) | r <- responses]
                    )
                    settings
    effects <- Effects <$> readIORef openedRef <*> readIORef followedRef <*> doesDirectoryExist store
    answered <- readIORef answersRef
    pure
        ( case outcome of
            Left ExitSuccess -> Refused 0 said
            Left (ExitFailure code) -> Refused code said
            Right () -> Served answered
        , effects
        )

-- | Run an action with the standard error of the process written to a file, and read it back.
capturingStderr :: FilePath -> IO a -> IO (a, String)
capturingStderr dir action = do
    let path = dir </> "stderr-capture"
    saved <- hDuplicate stderr
    result <- withFile path WriteMode $ \handle -> do
        hFlush stderr
        hDuplicateTo handle stderr
        action `finally` (hFlush stderr >> hDuplicateTo saved stderr)
    hClose saved
    said <- readFile path
    length said `seq` pure (result, said)
