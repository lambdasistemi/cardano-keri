{- |
Module      : Cardano.KERI.CLI.Backend.ConfigSpec
Description : #177 Slice 1 T177-S1-1 backend selection precedence/rejection (RED)
-}
module Cardano.KERI.CLI.Backend.ConfigSpec (spec) where

import Cardano.KERI.CLI.Backend (
    Backend (..),
    BackendError (..),
    BackendSettings (..),
    SelectedBackend (..),
    backendSettingsParser,
    selectBackend,
 )
import OptEnvConf.Args qualified as OptArgs
import OptEnvConf.Capability qualified as OptCapability
import OptEnvConf.EnvMap qualified as OptEnv
import OptEnvConf.Run qualified as OptRun
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
    selectBackendSpec
    parserSpec

selectBackendSpec :: Spec
selectBackendSpec = describe "selectBackend (T177-S1-1)" $ do
    it "explicit local with --store selects the local store" $
        selectBackend (baseSettings{backendExplicit = Just BackendLocal, backendStorePath = Just "/tmp/store"})
            `shouldBe` Right (SelectedLocal "/tmp/store")

    it "explicit local without --store is rejected" $
        selectBackend (baseSettings{backendExplicit = Just BackendLocal})
            `shouldSatisfy` isConfigError

    it "explicit local with --endpoint is rejected (cross-backend flag)" $
        selectBackend
            ( baseSettings
                { backendExplicit = Just BackendLocal
                , backendStorePath = Just "/tmp/store"
                , backendEndpointUrl = Just "https://ckeri.dev.plutimus.com"
                }
            )
            `shouldSatisfy` isConfigError

    it "explicit endpoint with --endpoint selects the endpoint" $
        selectBackend
            ( baseSettings
                { backendExplicit = Just BackendEndpoint
                , backendEndpointUrl = Just "https://ckeri.dev.plutimus.com"
                }
            )
            `shouldBe` Right (SelectedEndpoint "https://ckeri.dev.plutimus.com")

    it "explicit endpoint without --endpoint is rejected" $
        selectBackend (baseSettings{backendExplicit = Just BackendEndpoint})
            `shouldSatisfy` isConfigError

    it "explicit endpoint with --store is rejected (cross-backend flag)" $
        selectBackend
            ( baseSettings
                { backendExplicit = Just BackendEndpoint
                , backendEndpointUrl = Just "https://ckeri.dev.plutimus.com"
                , backendStorePath = Just "/tmp/store"
                }
            )
            `shouldSatisfy` isConfigError

    it "--endpoint URL with no explicit backend is the endpoint shorthand" $
        selectBackend (baseSettings{backendEndpointUrl = Just "https://ckeri.dev.plutimus.com"})
            `shouldBe` Right (SelectedEndpoint "https://ckeri.dev.plutimus.com")

    it "endpoint shorthand with --store is rejected (cross-backend flag)" $
        selectBackend
            ( baseSettings
                { backendEndpointUrl = Just "https://ckeri.dev.plutimus.com"
                , backendStorePath = Just "/tmp/store"
                }
            )
            `shouldSatisfy` isConfigError

    it "explicit koios with neither --endpoint nor --store selects koios" $
        selectBackend (baseSettings{backendExplicit = Just BackendKoios})
            `shouldBe` Right (SelectedKoios (backendKoiosUrl baseSettings) Nothing)

    it "explicit koios with --endpoint is rejected (cross-backend flag)" $
        selectBackend
            ( baseSettings
                { backendExplicit = Just BackendKoios
                , backendEndpointUrl = Just "https://ckeri.dev.plutimus.com"
                }
            )
            `shouldSatisfy` isConfigError

    it "explicit koios with --store is rejected (cross-backend flag)" $
        selectBackend (baseSettings{backendExplicit = Just BackendKoios, backendStorePath = Just "/tmp/store"})
            `shouldSatisfy` isConfigError

    it "with neither explicit backend nor --endpoint, the default is koios" $
        selectBackend baseSettings
            `shouldBe` Right (SelectedKoios (backendKoiosUrl baseSettings) Nothing)

    it "--store alone with no explicit backend and no --endpoint is rejected, not silently local" $
        selectBackend (baseSettings{backendStorePath = Just "/tmp/store"})
            `shouldSatisfy` isConfigError

parserSpec :: Spec
parserSpec = describe "backendSettingsParser (T177-S1-1)" $ do
    it "parses --aid, --backend, and --store from argv" $ do
        parsed <-
            parseBackendSettings
                [ "--aid"
                , "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                , "--backend"
                , "local"
                , "--store"
                , "/tmp/argv-store"
                ]
                []
        backendAid parsed `shouldBe` "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        backendExplicit parsed `shouldBe` Just BackendLocal
        backendStorePath parsed `shouldBe` Just "/tmp/argv-store"

    it "parses CKERI_AID, CKERI_BACKEND, and CKERI_ENDPOINT from the environment" $ do
        parsed <-
            parseBackendSettings
                []
                [ ("CKERI_AID", "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                , ("CKERI_BACKEND", "endpoint")
                , ("CKERI_ENDPOINT", "https://ckeri.dev.plutimus.com")
                ]
        backendAid parsed `shouldBe` "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        backendExplicit parsed `shouldBe` Just BackendEndpoint
        backendEndpointUrl parsed `shouldBe` Just "https://ckeri.dev.plutimus.com"

    it "an argv --endpoint overrides the environment's --endpoint (option precedence)" $ do
        parsed <-
            parseBackendSettings
                ["--aid", "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "--endpoint", "https://argv.example"]
                [("CKERI_ENDPOINT", "https://env.example")]
        backendEndpointUrl parsed `shouldBe` Just "https://argv.example"

    it "with neither --backend nor --endpoint given, backendExplicit/backendEndpointUrl are both absent" $ do
        parsed <-
            parseBackendSettings
                ["--aid", "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]
                []
        backendExplicit parsed `shouldBe` Nothing
        backendEndpointUrl parsed `shouldBe` Nothing

    it "defaults koios-url when none is given" $ do
        parsed <-
            parseBackendSettings
                ["--aid", "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]
                []
        backendKoiosUrl parsed `shouldBe` "https://preprod.koios.rest/api/v1"

isConfigError :: Either BackendError a -> Bool
isConfigError (Left (ConfigError _)) = True
isConfigError _ = False

parseBackendSettings :: [String] -> [(String, String)] -> IO BackendSettings
parseBackendSettings args environment = do
    result <-
        OptRun.runParserOn
            OptCapability.allCapabilities
            Nothing
            backendSettingsParser
            (OptArgs.parseArgs args)
            (OptEnv.parse environment)
            Nothing
    case result of
        Left errors -> do
            expectationFailure (show errors)
            error "ConfigSpec: unreachable after parser failure"
        Right settings -> pure settings

baseSettings :: BackendSettings
baseSettings =
    BackendSettings
        { backendAid = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        , backendExplicit = Nothing
        , backendEndpointUrl = Nothing
        , backendStorePath = Nothing
        , backendManifest = "deploy/preprod/m1-manifest.json"
        , backendBoardManifest = "deploy/preprod/board-manifest.json"
        , backendKoiosUrl = "https://preprod.koios.rest/api/v1"
        , backendKoiosToken = Nothing
        }
