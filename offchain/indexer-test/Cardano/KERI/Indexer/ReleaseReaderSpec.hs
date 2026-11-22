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
import Control.Monad (forever)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BSL
import Data.IORef (modifyIORef, newIORef, readIORef, writeIORef)
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Network.HTTP.Types (statusCode)
import Network.Wai (Application, defaultRequest)
import Network.Wai.Test (SResponse (..), request, runSession, setPath)
import OptEnvConf qualified as Opt
import OptEnvConf.Args qualified as OptArgs
import OptEnvConf.Capability qualified as OptCapability
import OptEnvConf.EnvMap qualified as OptEnv
import OptEnvConf.Run qualified as OptRun
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldContain)

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
        let settings m r = ReaderSettings config m r 8080
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
                            (ReaderSettings config{icStorePath = dir </> path} manifest release 8080)
                capture "manifest" "s1" (Just manifestPath) Nothing
                capture "release" "s2" Nothing (Just releasePath)
                interest <- readIORef seen
                lookup "release" interest
                    `shouldBe` Just (IndexAddressSet (Set.fromList [checkpointAddressOf testRelease, fundingAddress, boardAddress]))
                lookup "manifest" interest `shouldBe` Just (IndexAddressSet (Set.fromList [manifestAddress, fundingAddress, boardAddress]))
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
        (ReaderSettings config{icStorePath = dir </> name} manifest release 8080)
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
        (ReaderSettings config{icStorePath = dir </> name} manifest release 8080)
    readIORef answers
