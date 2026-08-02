{-# LANGUAGE ApplicativeDo #-}

{- |
Module      : Cardano.KERI.CLI
Description : Production @ckeri@ command composition

The top-level 'Instructions' parser/dispatcher. Six commands
(@deploy@\/@manifest verify@\/@register@\/@advance@\/@close@\/@board@) are
unchanged, reusing "Cardano.KERI.Deployment.CLI"'s existing settings/parsers/
runners; only @status@ is new, routed through the #177 backend seam
("Cardano.KERI.CLI.Backend") via the same 'resolveBackend' dispatch table
'Cardano.KERI.CLI.Backend.DispatchSpec' exercises.
-}
module Cardano.KERI.CLI (
    Instructions (..),
    runInstructions,
) where

import Cardano.KERI.CLI.Backend (
    BackendSettings (..),
    backendSettingsParser,
    renderBackendError,
    renderStatusView,
    resolveBackend,
    runBackendStatus,
    selectBackend,
 )
import Cardano.KERI.CLI.Backend.Endpoint (mkEndpointBackend)
import Cardano.KERI.CLI.Backend.Koios (mkKoiosBackend)
import Cardano.KERI.CLI.Backend.Local (openLocalBackend)
import Cardano.KERI.Deployment.CLI (
    AdvanceSettings,
    BoardInstructions,
    CloseSettings,
    DeploySettings,
    RegisterSettings,
    VerifySettings,
    advanceSettingsParser,
    boardInstructionsParser,
    closeSettingsParser,
    deploySettingsParser,
    registerSettingsParser,
    runAdvance,
    runBoard,
    runClose,
    runDeploy,
    runRegister,
    runVerify,
    verifySettingsParser,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardManifest,
    readEndpointBoardManifest,
 )
import Cardano.KERI.Deployment.Manifest (Manifest, readManifest)
import Data.Text qualified as T
import OptEnvConf qualified as Opt
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

data Instructions
    = Deploy !DeploySettings
    | ManifestVerify !VerifySettings
    | Register !RegisterSettings
    | Advance !AdvanceSettings
    | Close !CloseSettings
    | Status !BackendSettings
    | Board !BoardInstructions

instance Opt.HasParser Instructions where
    settingsParser =
        Opt.withYamlConfig
            ( Opt.optional $
                Opt.filePathSetting
                    [ Opt.option
                    , Opt.long "config-file"
                    , Opt.env "CKERI_CONFIG_FILE"
                    , Opt.help "Path to the ckeri YAML configuration file"
                    ]
            )
            $ Opt.commands
                [ Opt.command
                    "deploy"
                    "Publish the M1 V1 reference scripts"
                    (Deploy <$> Opt.subConfig "deploy" deploySettingsParser)
                , Opt.command
                    "manifest"
                    "Operate on a release manifest"
                    ( Opt.commands
                        [ Opt.command
                            "verify"
                            "Rebuild and verify source, hashes, and live references"
                            ( ManifestVerify
                                <$> Opt.subConfig
                                    "manifest"
                                    (Opt.subConfig "verify" verifySettingsParser)
                            )
                        ]
                    )
                , Opt.command
                    "register"
                    "Register a kli inception KEL on preprod"
                    (Register <$> Opt.subConfig "register" registerSettingsParser)
                , Opt.command
                    "advance"
                    "Advance a live checkpoint from a witnessed kli rotation"
                    (Advance <$> Opt.subConfig "advance" advanceSettingsParser)
                , Opt.command
                    "close"
                    "Close a live checkpoint and refund its complete escrow"
                    (Close <$> Opt.subConfig "close" closeSettingsParser)
                , Opt.command
                    "status"
                    "Report an AID's checkpoint from a selected backend"
                    (Status <$> Opt.subConfig "status" backendSettingsParser)
                , Opt.command
                    "board"
                    "Operate the current on-chain endpoint catalog"
                    (Board <$> Opt.subConfig "board" boardInstructionsParser)
                ]

runInstructions :: Instructions -> IO ()
runInstructions = \case
    Deploy settings -> runDeploy settings
    ManifestVerify settings -> runVerify settings
    Register settings -> runRegister settings
    Advance settings -> runAdvance settings
    Close settings -> runClose settings
    Status settings -> runBackendStatusCLI settings
    Board instructions -> runBoard instructions

{- | Select exactly one backend (FR-5) and render its answer or its closed
error. Checkpoint\/board manifest loading is deferred into the local\/Koios
constructor closures alone: the installed @--endpoint@ shortcut needs
neither file and must not require a checkout to run (NOTE-032).
-}
runBackendStatusCLI :: BackendSettings -> IO ()
runBackendStatusCLI settings =
    case selectBackend settings of
        Left err -> dieConcisely (T.unpack (renderBackendError err))
        Right selected -> do
            backend <-
                resolveBackend
                    ( \store -> do
                        (manifest, boardManifest) <- loadManifests settings
                        openLocalBackend manifest boardManifest store
                    )
                    (pure . mkEndpointBackend)
                    ( \url token -> do
                        (manifest, boardManifest) <- loadManifests settings
                        pure (mkKoiosBackend manifest boardManifest url token)
                    )
                    selected
            result <- runBackendStatus backend (backendAid settings)
            case result of
                Left err -> dieConcisely (T.unpack (renderBackendError err))
                Right view -> putStrLn (T.unpack (renderStatusView view))

-- | Read and validate both manifests, dying concisely on either failure.
loadManifests :: BackendSettings -> IO (Manifest, EndpointBoardManifest)
loadManifests settings = do
    manifest <- readManifest (backendManifest settings) >>= either dieConcisely pure
    boardManifest <-
        readEndpointBoardManifest (backendBoardManifest settings)
            >>= either dieConcisely pure
    pure (manifest, boardManifest)

dieConcisely :: String -> IO a
dieConcisely message = do
    hPutStrLn stderr ("ckeri: " <> message)
    exitFailure
