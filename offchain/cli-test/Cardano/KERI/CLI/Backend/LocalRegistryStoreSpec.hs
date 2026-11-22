{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.CLI.Backend.LocalRegistryStoreSpec
Description : The local status backend over a store that records a release identity (#353)

The version 1 reads of the local backend (status, the list of checkpoints, the
checkpoint of an AID, the payer's outputs) answer one named refusal, before
they query, when the store records a release identity; over a store with no
record they answer as before.
-}
module Cardano.KERI.CLI.Backend.LocalRegistryStoreSpec (spec) where

import Cardano.KERI.AID.Application (ApplicationParameters (..), OutputReference (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.CLI.Backend (BackendError (..), QueryBackend (..))
import Cardano.KERI.CLI.Backend.Local (openLocalBackend)
import Cardano.KERI.Deployment.EndpointBoardManifest (readEndpointBoardManifest)
import Cardano.KERI.Deployment.Manifest (CheckpointInfo (..), Manifest (..), readManifest)
import Cardano.KERI.Indexer.StoreBinding (createStoreForRelease, storeRecordPath)
import Data.ByteString qualified as BS
import Data.List (isInfixOf)
import Data.Text qualified as T
import Paths_cardano_keri (getDataFileName)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

release :: ReleaseIdentity
release =
    ReleaseIdentity
        { riNetwork = 0
        , riRelease = Release (BS.replicate 28 1) (BS.replicate 28 2) (BS.replicate 28 3) (BS.replicate 28 4)
        , riSeed = OutputReference (BS.replicate 32 5) 0
        , riCheckpointValidator = BS.replicate 28 6
        , riDeposit = 8_000_000
        , riFreezeBond = 2_000_000
        , riPremium = 500_000
        , riMinimumAda = 2_000_000
        , riTerminationCarrier = 1_500_000
        , riApplicationParameters = ApplicationParameters 1_000_000 500_000 90_000 5_000
        }

isMismatch :: Either BackendError a -> Bool
isMismatch (Left (ConfigError message)) = "mode mismatch" `isInfixOf` T.unpack message
isMismatch _ = False

spec :: Spec
spec = describe "the local backend and a store that records a release identity" $ do
    it "refuses every version 1 read with the mode mismatch before querying, leaving the store's record unchanged" $
        withSystemTempDirectory "backend-registry" $ \dir -> do
            (manifest, backend) <- openBackend
            let store = dir </> "registry"
            createStoreForRelease store release >>= (`shouldBe` True)
            before <- BS.readFile (storeRecordPath store)
            registryBackend <- backend store
            qbStatus registryBackend (T.pack "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P") >>= (`shouldSatisfy` isMismatch)
            qbListCheckpoints registryBackend >>= (`shouldSatisfy` isMismatch)
            qbCheckpointByAid registryBackend (T.pack "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P") >>= (`shouldSatisfy` isMismatch)
            qbPayerUtxos registryBackend (checkpointAddressBech32 (manifestCheckpoint manifest)) >>= (`shouldSatisfy` isMismatch)
            BS.readFile (storeRecordPath store) >>= (`shouldBe` before)
    it "answers as before over a store with no record" $
        withSystemTempDirectory "backend-registry" $ \dir -> do
            (_, backend) <- openBackend
            plain <- backend (dir </> "manifest-store")
            result <- qbListCheckpoints plain
            case result of
                Right (_, items) -> length items `shouldBe` 0
                Left e -> expectationFailure ("expected an empty list, got " <> show e)
  where
    openBackend = do
        manifest <- getDataFileName "deployment-test/fixtures/register-preflight-m1-manifest.json" >>= readManifest >>= either fail pure
        board <- getDataFileName "deployment-test/fixtures/register-preflight-board-manifest.json" >>= readEndpointBoardManifest >>= either fail pure
        pure (manifest, openLocalBackend manifest board)
