{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryLegacyRecordCommandSpec
Description : the commands read the files of a registry of the earlier development form and refuse it by name, before building anything

The files are the genuine pair of a local-chain deployment of the earlier development form: its
version 1 reference-output record and its release identity. Each command reads them at its
own entry point, and each then refuses, in plain words and by name, before a provider is opened
and with nothing spent: the registry's application depends on a program this version does not
use, so this version cannot build transactions for it and the registry must be deployed again
with this version. The same commands over a record this version wrote go on to ask for a
provider. No second derivation or transaction path exists for the earlier form.
-}
module Cardano.KERI.Deployment.RegistryLegacyRecordCommandSpec (spec) where

import Cardano.KERI.Deployment.NodeSocketRuntime (RegistryOpener)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryFiles (writeDeploymentFiles)
import Cardano.KERI.Deployment.RegistryProvider (ProviderChoice (..))
import Cardano.KERI.Deployment.RegistrySnapshot (Snapshot (..), encodeSnapshot)
import Control.Exception (SomeException, fromException, try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Paths_cardano_keri (getDataFileName)
import System.Directory (copyFile, createDirectory, withCurrentDirectory)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

-- | The files of the genuine version 1 deployment, copied where a command reads them.
withLegacyFiles :: (FilePath -> FilePath -> FilePath -> IO a) -> IO a
withLegacyFiles use =
    withSystemTempDirectory "registry-legacy" $ \scratch -> do
        record <- getDataFileName "deployment-test/fixtures/registry-v1/reference-outputs.json"
        identity <- getDataFileName "deployment-test/fixtures/registry-v1/release-identity.json"
        let work = scratch </> "work"
        createDirectory work
        copyFile record (scratch </> "reference-outputs.json")
        copyFile identity (scratch </> "release-identity.json")
        use work (scratch </> "release-identity.json") (scratch </> "reference-outputs.json")

-- | What a command did over some files: its exit, its two outputs and how many times it opened a provider.
data Ran = Ran
    { ranCode :: ExitCode
    , ranOut :: String
    , ranErr :: String
    , ranOpened :: Int
    }

{- | Run a command over files with an opener that only counts, and refuses to give a provider: a command
that asks for one has got past the files.
-}
counting :: (RegistryOpener -> IO ()) -> FilePath -> IO Ran
counting command work = do
    opened <- newIORef (0 :: Int)
    let opener :: RegistryOpener
        opener _ _ = modifyIORef' opened (+ 1) >> fail "the provider was opened"
    ((outcome, out), err) <-
        capturing stderr (capturing stdout (withCurrentDirectory work (try @SomeException (command opener))))
    count <- readIORef opened
    pure Ran{ranCode = either exitOf (const ExitSuccess) outcome, ranOut = out, ranErr = err, ranOpened = count}
  where
    exitOf failure = fromMaybe (ExitFailure 1) (fromException failure)

provider :: ProviderChoice
provider = ProviderChoice (Just "no-node.socket") Nothing Nothing Nothing

requestOf :: Text
requestOf = T.replicate 32 "ab" <> "#0"

registerOver :: FilePath -> FilePath -> FilePath -> IO Ran
registerOver work identity record = do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    export <- getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
    counting
        ( \opener ->
            runRegistryRegisterWith opener $
                RegistryRegisterSettings
                    { rgNetworkMagic = 42
                    , rgBlueprint = blueprint
                    , rgProvider = provider
                    , rgFundingAddress = "addr_test1unused"
                    , rgSigningKeyFile = Just "no-key.skey"
                    , rgVault = Nothing
                    , rgPassphraseFd = Nothing
                    , rgTimeoutSeconds = 5
                    , rgReleaseIdentity = identity
                    , rgReferenceRecord = record
                    , rgKliExport = export
                    , rgDeposit = Nothing
                    }
        )
        work

returnOver :: FilePath -> FilePath -> FilePath -> IO Ran
returnOver work identity record = do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    counting
        ( \opener ->
            runRegistryReturnWith opener $
                RegistryReturnSettings
                    { rnNetworkMagic = 42
                    , rnBlueprint = blueprint
                    , rnProvider = provider
                    , rnFundingAddress = "addr_test1unused"
                    , rnSigningKeyFile = Just "no-key.skey"
                    , rnVault = Nothing
                    , rnPassphraseFd = Nothing
                    , rnTimeoutSeconds = 5
                    , rnReleaseIdentity = identity
                    , rnReferenceRecord = record
                    , rnRequest = requestOf
                    }
        )
        work

foldOver :: FilePath -> FilePath -> FilePath -> IO Ran
foldOver work identity record = do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    let snapshot = work </> "snapshot.json"
    BS.writeFile snapshot (encodeSnapshot (Snapshot "the legacy spec" [] []))
    counting
        ( \opener ->
            runRegistryFoldWith opener $
                RegistryFoldSettings
                    { rfNetworkMagic = 42
                    , rfBlueprint = blueprint
                    , rfProvider = provider
                    , rfFundingAddress = "addr_test1unused"
                    , rfSigningKeyFile = Just "no-key.skey"
                    , rfVault = Nothing
                    , rfPassphraseFd = Nothing
                    , rfTimeoutSeconds = 5
                    , rfReleaseIdentity = identity
                    , rfReferenceRecord = record
                    , rfRequest = requestOf
                    , rfSnapshot = snapshot
                    , rfSnapshotOut = Nothing
                    }
        )
        work

zeroLine :: String
zeroLine = "nothing was submitted; nothing was spent"

spec :: Spec
spec = describe "#559 the commands over the files of a registry of the earlier development form" $ do
    forM_ commands $ \(operation, run) -> do
        it (operation <> " reads the genuine version 1 pair and refuses before building anything, in plain words, by name") $
            withLegacyFiles $ \work identity record -> do
                ran <- run work identity record
                ranCode ran `shouldBe` ExitFailure 1
                ranErr ran `shouldSatisfy` ("registry-predates-attestation" `isInfixOf`)
                -- what is true, and what to do: not the earlier release, which no release ever shipped
                ranErr ran `shouldSatisfy` ("deployed again with this version" `isInfixOf`)
                ranErr ran `shouldSatisfy` ("cannot build transactions for it" `isInfixOf`)
                ranErr ran `shouldSatisfy` (not . ("earlier release" `isInfixOf`))
                ranErr ran `shouldSatisfy` (zeroLine `isInfixOf`)
                -- the read is not what refused: both files decoded; and nothing was handed to a provider
                ranErr ran `shouldSatisfy` (not . ("deployment-files-invalid" `isInfixOf`))
                ranOpened ran `shouldBe` 0
        it (operation <> " proceeds over a registry deployed by this version: it asks for the provider the version 1 pair never reaches") $ do
            world <- newWorld 1_000
            withSystemTempDirectory "registry-current" $ \scratch -> do
                let work = scratch </> "work"
                    identityFile = scratch </> "release-identity.json"
                    recordFile = scratch </> "reference-outputs.json"
                createDirectory work
                written <- writeDeploymentFiles identityFile recordFile (deployedIdentity (worldDeployed world)) (deployedRecord (worldDeployed world))
                either (fail . show) pure written
                ran <- run work identityFile recordFile
                if ranOpened ran == 1 then pure () else expectationFailure ("the provider was not asked for; the command said: " <> ranErr ran)
                ranErr ran `shouldSatisfy` (not . ("registry-predates-attestation" `isInfixOf`))
                ranErr ran `shouldSatisfy` (not . ("deployment-files-invalid" `isInfixOf`))
  where
    commands = [("register", registerOver), ("return", returnOver), ("fold", foldOver)]
