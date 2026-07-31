{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.AppSpec (spec) where

import Cardano.Crypto.Hash.Class (
    hashFromBytes,
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
    writeManifestAtomic,
 )
import Cardano.KERI.Indexer.App (
    FollowerSettings (..),
    ManifestOutcome (..),
    loadManifestResult,
    mkCheckpointView,
    runFollowerAppWith,
 )
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
    decodeAddress,
 )
import Cardano.KERI.Indexer.FollowerSpec (
    baseConfig,
    m1Manifest,
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
 )
import Cardano.Ledger.Hashes (
    ScriptHash (..),
 )
import Cardano.Ledger.Mary.Value (
    PolicyID (..),
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncRunner,
    withChainSyncFollower,
    withChainSyncFollowerUsing,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    withInMemoryIndexer,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
 )
import Control.Concurrent (threadDelay)
import Control.Exception (
    SomeException,
    throwIO,
    try,
 )
import Control.Monad (forever)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS8
import OptEnvConf qualified as Opt
import OptEnvConf.Args qualified as OptArgs
import OptEnvConf.Capability qualified as OptCapability
import OptEnvConf.EnvMap qualified as OptEnv
import OptEnvConf.Run qualified as OptRun
import System.Exit (
    ExitCode (..),
 )
import System.IO (
    hClose,
 )
import System.IO.Temp (
    withSystemTempFile,
 )
import System.Timeout (
    timeout,
 )
import Test.Hspec (
    Expectation,
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldContain,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "#188 runnable follower app composition" $ do
    manifestLoadSpec
    checkpointViewSpec
    settingsParserSpec
    lifetimeSpec

-- ---------------------------------------------------------------------------
-- manifest loading

manifestLoadSpec :: Spec
manifestLoadSpec =
    describe "loadManifestResult" $ do
        it "reports a concise failure for a missing manifest file" $ do
            outcome <- loadManifestResult "/nonexistent-188-dir/manifest.json"
            case outcome of
                ManifestLoadFailed message -> message `shouldSatisfy` (not . null)
                ManifestLoaded manifest ->
                    expectationFailure $
                        "expected a missing-file failure, got " <> show manifest

        it "reports a concise failure for malformed manifest JSON" $
            withSystemTempFile "bad-manifest-188.json" $ \path handle -> do
                BS8.hPutStr handle "not json"
                hClose handle
                outcome <- loadManifestResult path
                case outcome of
                    ManifestLoadFailed message -> message `shouldSatisfy` (not . null)
                    ManifestLoaded manifest ->
                        expectationFailure $
                            "expected a malformed-JSON failure, got " <> show manifest

        it "loads a valid manifest" $
            withTempManifestFile m1Manifest $ \path -> do
                outcome <- loadManifestResult path
                outcome `shouldBe` ManifestLoaded m1Manifest

-- ---------------------------------------------------------------------------
-- checkpoint view construction

checkpointViewSpec :: Spec
checkpointViewSpec =
    describe "mkCheckpointView" $ do
        it "builds a view from a valid manifest checkpoint address and policy" $
            withInMemoryIndexer $ \handle ->
                case mkCheckpointView handle validManifest of
                    Left err -> expectationFailure err
                    Right view -> do
                        cvAddress view `shouldBe` decodeExpectedAddress
                        cvPolicy view `shouldBe` expectedPolicy

        it "rejects an invalid bech32 checkpoint address" $
            withInMemoryIndexer $ \handle ->
                assertRejected (mkCheckpointView handle invalidAddressManifest)

        it "rejects invalid policy hex" $
            withInMemoryIndexer $ \handle ->
                assertRejected (mkCheckpointView handle invalidPolicyManifest)

-- ---------------------------------------------------------------------------
-- combined settings parser (IndexerConfig + manifest path)

settingsParserSpec :: Spec
settingsParserSpec =
    describe "FollowerSettings parser" $ do
        it "parses the combined follower settings including manifest path from argv" $ do
            parsed <-
                parseFollowerSettings
                    [ "--node-socket"
                    , "/tmp/argv-node.socket"
                    , "--network-magic"
                    , "314159"
                    , "--byron-epoch-slots"
                    , "21600"
                    , "--security-param-k"
                    , "901"
                    , "--store-path"
                    , "/tmp/argv-indexer"
                    , "--manifest-path"
                    , "/tmp/argv-manifest.json"
                    ]
                    []
            fsManifestPath parsed `shouldBe` "/tmp/argv-manifest.json"
            icSocketPath (fsIndexer parsed) `shouldBe` "/tmp/argv-node.socket"

        it "parses the manifest path from its environment variable" $ do
            parsed <-
                parseFollowerSettings
                    []
                    [ ("CKERI_NODE_SOCKET", "/tmp/env-node.socket")
                    , ("CKERI_NETWORK_MAGIC", "271828")
                    , ("CKERI_BYRON_EPOCH_SLOTS", "21601")
                    , ("CKERI_SECURITY_PARAM_K", "902")
                    , ("CKERI_STORE_PATH", "/tmp/env-indexer")
                    , ("CKERI_MANIFEST_PATH", "/tmp/env-manifest.json")
                    ]
            fsManifestPath parsed `shouldBe` "/tmp/env-manifest.json"

-- ---------------------------------------------------------------------------
-- process lifetime: rejection-before-prompt, async failure propagation

lifetimeSpec :: Spec
lifetimeSpec =
    describe "runFollowerAppWith lifetime" $ do
        it "fails before opening the prompt when the manifest path is invalid" $ do
            let settings = FollowerSettings baseConfig "/nonexistent-188-dir/manifest.json"
            outcome <-
                try @ExitCode $
                    runFollowerAppWith
                        (\_path action -> withInMemoryIndexer action)
                        withChainSyncFollower
                        (\_qa _fh -> expectationFailure "must not reach the interactive shell")
                        settings
            case outcome of
                Left (ExitFailure code) -> code `shouldBe` 1
                Left ExitSuccess -> expectationFailure "expected ExitFailure, got ExitSuccess"
                Right () -> expectationFailure "expected a concise ExitFailure before any interaction"

        it "propagates a follower async failure instead of hanging the shell" $
            withTempManifestFile validManifest $ \manifestPath -> do
                let settings = FollowerSettings baseConfig manifestPath
                result <-
                    timeout (5 * 1_000_000) $
                        try @SomeException $
                            runFollowerAppWith
                                (\_path action -> withInMemoryIndexer action)
                                (withChainSyncFollowerUsing throwingRunner)
                                (\_qa _fh -> forever (threadDelay maxBound))
                                settings
                case result of
                    Nothing ->
                        expectationFailure
                            "runFollowerAppWith hung instead of propagating the follower failure"
                    Just (Left err) ->
                        show err `shouldContain` "#188 injected follower failure"
                    Just (Right ()) ->
                        expectationFailure
                            "runFollowerAppWith returned normally despite an injected follower failure"

{- | 'CheckpointView' has no 'Show' instance upstream, so match explicitly
rather than reach for 'shouldSatisfy isLeft' (which needs one).
-}
assertRejected :: Either String CheckpointView -> Expectation
assertRejected (Left _) = pure ()
assertRejected (Right _) = expectationFailure "expected a rejection (Left), got Right"

throwingRunner :: ChainSyncRunner
throwingRunner _ _ _ _ _ _ _ = throwIO (userError "#188 injected follower failure")

-- ---------------------------------------------------------------------------
-- Helpers

{- | 'm1Manifest' with a valid 28-byte-hex checkpoint policy (its own
placeholder "test-policy" is deliberately invalid hex for #175's needs).
-}
validManifest :: Manifest
validManifest =
    m1Manifest
        { manifestCheckpoint =
            (manifestCheckpoint m1Manifest)
                { checkpointPolicyId =
                    "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
                }
        }

invalidAddressManifest :: Manifest
invalidAddressManifest =
    validManifest
        { manifestCheckpoint =
            (manifestCheckpoint validManifest){checkpointAddressBech32 = "not-a-real-address"}
        }

invalidPolicyManifest :: Manifest
invalidPolicyManifest =
    validManifest
        { manifestCheckpoint =
            (manifestCheckpoint validManifest){checkpointPolicyId = "zz-not-hex"}
        }

decodeExpectedAddress :: Address
decodeExpectedAddress =
    either
        (\err -> error ("AppSpec: invalid address fixture: " <> err))
        id
        (decodeAddress (checkpointAddressBech32 (manifestCheckpoint validManifest)))

expectedPolicy :: PolicyID
expectedPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (hexBytesOrError "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734") of
                Just h -> h
                Nothing -> error "AppSpec: invalid policy hash width"

hexBytesOrError :: String -> BS.ByteString
hexBytesOrError hex =
    case Base16.decode (BS8.pack hex) of
        Right bytes -> bytes
        Left err -> error ("AppSpec: invalid hex fixture: " <> err)

withTempManifestFile :: Manifest -> (FilePath -> IO a) -> IO a
withTempManifestFile manifest action =
    withSystemTempFile "m1-manifest-188.json" $ \path handle -> do
        hClose handle
        writeManifestAtomic path manifest
        action path

parseFollowerSettings :: [String] -> [(String, String)] -> IO FollowerSettings
parseFollowerSettings args environment = do
    result <-
        OptRun.runParserOn
            OptCapability.allCapabilities
            Nothing
            (Opt.settingsParser :: Opt.Parser FollowerSettings)
            (OptArgs.parseArgs args)
            (OptEnv.parse environment)
            Nothing
    case result of
        Left errors -> do
            expectationFailure (show errors)
            error "AppSpec: unreachable after parser failure"
        Right settings -> pure settings
