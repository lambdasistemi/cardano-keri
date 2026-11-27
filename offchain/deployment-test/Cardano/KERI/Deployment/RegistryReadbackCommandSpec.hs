{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReadbackCommandSpec
Description : @ckeri checkpoint@ and @ckeri status@ read the rebuilt registry by the identifier as signed

The arguments go through the production parser and the production dispatcher,
with the provider replaced by the transactions the builders wrote. The first
control is the command as it was: a basic-prefix identifier is refused as
malformed on the first deployment's route, which stays on its pinned codecs. The
registry mode is chosen by the release identity, the reference record and the
blueprint; it prints the stored identifier and ordered keys and the references
that tie them to the booking, or names the link that could not be followed.
-}
module Cardano.KERI.Deployment.RegistryReadbackCommandSpec (spec) where

import Cardano.KERI.AID.Application (OutputReference (..))
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.CLI (Instructions, runInstructionsWith)
import Cardano.KERI.ChainQuery.ReleaseIdentity (encodeReleaseIdentity)
import Cardano.KERI.Deployment.RegistryBookingCommand (KoiosReadOpener)
import Cardano.KERI.Deployment.RegistryBookingShapeSpec (Scenario (..))
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryDeploy (releaseIdentityOf)
import Cardano.KERI.Deployment.RegistryFiles (
    ReferenceRecord (..),
    ScriptReference (..),
    encodeReferenceRecord,
 )
import Cardano.KERI.Deployment.RegistryReadback (Acquirer (..))
import Cardano.KERI.Deployment.RegistryReadbackSpec (
    World (..),
    honest,
    providerOf,
    rows,
    shownBy,
    worldOf,
 )
import Cardano.KERI.Deployment.RegistryTransactions (RegistryDeployment (..))
import Control.Exception (try)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Either (fromLeft)
import Data.List (isInfixOf, isPrefixOf)
import OptEnvConf qualified as Opt
import OptEnvConf.Args (parseArgs)
import OptEnvConf.Capability (allCapabilities)
import OptEnvConf.EnvMap qualified as EnvMap
import OptEnvConf.Run (runParserOn)
import Singular.Registry.Evidence (NoWitness)
import Singular.Registry.LedgerProvider (Session)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "ckeri checkpoint and ckeri status over the rebuilt registry" $ do
    describe "the command as it was: the first deployment, on its pinned codecs" $
        mapM_
            ( \aid -> it ("refuses " <> aid <> " as not an E-code identifier") $ do
                (outcome, _, err) <- runWith unreached ["checkpoint", "--aid", aid, "--endpoint", "http://127.0.0.1:9"]
                outcome `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("AID must be one 44-character KERI E-code identifier" `isInfixOf`)
            )
            ["BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTw", "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"]
    describe "the rebuilt registry, chosen by the release identity, the reference record and the blueprint" $
        mapM_
            ( \(name, aid, keys, said) ->
                mapM_
                    ( \command -> it (command <> " " <> show name) $ do
                        w <- worldOf name
                        (outcome, out, _) <-
                            withFiles w $ \arguments ->
                                runWith (stub (honest w)) ([command, "--aid", B8.unpack aid] <> arguments)
                        outcome `shouldBe` ExitSuccess
                        let linesOf = lines out
                        linesOf `shouldSatisfy` (("identifier: " <> B8.unpack aid) `elem`)
                        [l | l <- linesOf, "current-key: " `isPrefixOf` l] `shouldBe` ["current-key: " <> B8.unpack k | k <- keys]
                        linesOf `shouldSatisfy` any ("checkpoint-output: " `isPrefixOf`)
                        linesOf `shouldSatisfy` any ("fold-transaction: " `isPrefixOf`)
                        linesOf `shouldSatisfy` any ("pending-output: " `isPrefixOf`)
                        linesOf `shouldSatisfy` any ("booking-transaction: " `isPrefixOf`)
                        linesOf `shouldSatisfy` ("booking-output-index: 0" `elem`)
                        linesOf `shouldSatisfy` (("inception-digest: " <> B8.unpack said) `elem`)
                        linesOf `shouldSatisfy` ("links: complete" `elem`)
                    )
                    ["checkpoint", "status"]
            )
            rows
    describe "both entry points reach the same reader" $
        it "prints the same lines for status and checkpoint" $ do
            w <- worldOf "reference:I01"
            let aid = "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            (_, viaCheckpoint, _) <- withFiles w $ \arguments -> runWith (stub (honest w)) (["checkpoint", "--aid", aid] <> arguments)
            (_, viaStatus, _) <- withFiles w $ \arguments -> runWith (stub (honest w)) (["status", "--aid", aid] <> arguments)
            viaStatus `shouldBe` viaCheckpoint
    describe "a link the provider cannot show" $
        it "returns the stored state marked not linked, names the link, and prints no digest" $ do
            w <- worldOf "reference:I01"
            let aid = "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            (outcome, out, _) <-
                withFiles w $ \arguments ->
                    runWith
                        (stub (providerOf [wHolding w] (shownBy w [wFold w] [wFold w])))
                        (["checkpoint", "--aid", aid] <> arguments)
            outcome `shouldBe` ExitSuccess
            let linesOf = lines out
            linesOf `shouldSatisfy` (("identifier: " <> aid) `elem`)
            linesOf `shouldSatisfy` (("current-key: " <> aid) `elem`)
            linesOf `shouldSatisfy` ("links: not linked" `elem`)
            linesOf `shouldSatisfy` ("failed-link: booking-transaction" `elem`)
            linesOf `shouldSatisfy` ("inception-digest: not established" `elem`)
            out `shouldSatisfy` (not . ("EFdfRKDdnvl3KoYGilKKR8p_ukC4sKLuf8YMJDPT9_8c" `isInfixOf`))
    describe "refusals" $ do
        it "refuses a registry file setting without the other two" $ do
            (outcome, _, err) <- runWith unreached ["checkpoint", "--aid", "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ", "--release-identity", "identity.json"]
            outcome `shouldBe` ExitFailure 1
            err `shouldSatisfy` ("registry-files-incomplete" `isInfixOf`)
        it "refuses the first deployment's backends beside the rebuilt registry" $ do
            w <- worldOf "reference:I01"
            (outcome, _, err) <-
                withFiles w $ \arguments ->
                    runWith unreached (["checkpoint", "--aid", "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ", "--endpoint", "http://127.0.0.1:9"] <> arguments)
            outcome `shouldBe` ExitFailure 1
            err `shouldSatisfy` ("registry-read-needs-the-provider" `isInfixOf`)
        it "refuses an identifier that is not one complete qualified identifier" $ do
            w <- worldOf "reference:I01"
            (outcome, _, err) <- withFiles w $ \arguments -> runWith (stub (honest w)) (["checkpoint", "--aid", "not-an-identifier"] <> arguments)
            outcome `shouldBe` ExitFailure 1
            err `shouldSatisfy` ("aid-invalid" `isInfixOf`)

-- | The opener a command is given: the session of a stub, in place of Koios.
stub :: Session NoWitness IO -> KoiosReadOpener
stub session _ use = use (Acquirer (\act -> Right <$> act session))

-- | An opener that must not be reached.
unreached :: KoiosReadOpener
unreached _ _ = fail "the provider was reached"

{- | Run the production parser and the production dispatcher on arguments, with no
environment and no configuration file: the exit, what was printed, and what was
printed as an error.
-}
runWith :: KoiosReadOpener -> [String] -> IO (ExitCode, String, String)
runWith opener args = do
    parsed <-
        runParserOn
            allCapabilities
            Nothing
            (Opt.settingsParser :: Opt.Parser Instructions)
            (parseArgs args)
            EnvMap.empty
            Nothing
    instructions <- case parsed of
        Right instructions -> pure instructions
        Left failure -> expectationFailure ("the arguments did not parse: " <> show failure) >> fail "no parse"
    ((outcome, out), err) <-
        capturing stderr . capturing stdout $
            fromLeft ExitSuccess <$> (try (runInstructionsWith opener instructions) :: IO (Either ExitCode ()))
    pure (outcome, out, err)

{- | The release identity, the reference record and the blueprint the command is given for the
registry of a world, written to a directory that is removed after.
-}
withFiles :: World -> ([String] -> IO a) -> IO a
withFiles w use = do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    let registry = scRegistry (wScenario w)
        identity = releaseIdentityOf (deploymentTerms registry) (deploymentScripts registry)
        hashOf = BS.replicate 28
        reference n = ScriptReference (OutputReference (BS.replicate 32 n) 0) (hashOf n)
        applicationPolicy = rlApplicationPolicy (riRelease identity)
        record =
            ReferenceRecord
                { recordNetwork = riNetwork identity
                , recordTemplate = OutputReference (BS.replicate 32 0x61) 0
                , recordApplication = ScriptReference (OutputReference (BS.replicate 32 0x62) 0) applicationPolicy
                , recordState = ScriptReference (OutputReference (BS.replicate 32 0x63) 0) (rlStatePolicy (riRelease identity))
                , recordAttestation = reference 0x64
                , recordHashProof = reference 0x65
                , recordCheckpoint = ScriptReference (OutputReference (BS.replicate 32 0x66) 0) (riCheckpointValidator identity)
                , recordConfiguration = OutputReference (BS.replicate 32 0x67) 1
                , recordRegistryState = OutputReference (BS.replicate 32 0x68) 0
                , recordGenesis = BS.replicate 32 0x69
                }
    withSystemTempDirectory "readback-command" $ \directory -> do
        let identityPath = directory </> "release-identity.json"
            recordPath = directory </> "reference-record.json"
        BS.writeFile identityPath (encodeReleaseIdentity identity)
        BS.writeFile recordPath (encodeReferenceRecord record)
        use
            [ "--koios-url"
            , "http://provider.invalid/api/v1"
            , "--release-identity"
            , identityPath
            , "--reference-record"
            , recordPath
            , "--blueprint"
            , blueprint
            ]
