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
    BackendCommonSettings (..),
    BackendSettings (..),
    CheckpointListView (..),
    CheckpointSettings (..),
    CheckpointView (..),
    ListSettings (..),
    PayerSettings (..),
    PayerView (..),
    QueryBackend (..),
    backendCommonSettings,
    backendSettingsParser,
    checkpointSettingsParser,
    listSettingsParser,
    payerSettingsParser,
    renderBackendError,
    renderCheckpointListView,
    renderCheckpointView,
    renderPayerView,
    renderStatusView,
    resolveBackend,
    runBackendCheckpointByAid,
    runBackendListCheckpoints,
    runBackendPayerUtxos,
    runBackendStatus,
    selectCommonBackend,
 )
import Cardano.KERI.CLI.Backend.Endpoint (mkEndpointBackend)
import Cardano.KERI.CLI.Backend.Koios (mkKoiosBackend)
import Cardano.KERI.CLI.Backend.Local (openLocalBackend)
import Cardano.KERI.Deployment.CLI (
    AdvanceSettings,
    BoardInstructions (..),
    CloseSettings,
    DeploySettings,
    RegisterSettings,
    advanceSettingsParser,
    boardPostSettingsParser,
    boardRetireSettingsParser,
    boardUpdateSettingsParser,
    closeSettingsParser,
    deploySettingsParser,
    deploySettingsParserWithOut,
    registerSettingsParser,
    runAdvance,
    runBoard,
    runClose,
    runDeploy,
    runRegister,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardManifest,
    readEndpointBoardManifest,
 )
import Cardano.KERI.Deployment.Manifest (Manifest, readManifest)
import Cardano.KERI.Deployment.Verify (
    BoardListSettings,
    VerifySettings,
    boardListSettingsParser,
    runBoardList,
    runVerify,
    verifySettingsParser,
 )
import Control.Exception (IOException, try)
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
    | List !ListSettings
    | Checkpoint !CheckpointSettings
    | Payer !PayerSettings
    | Board !BoardCommand

{- | #240: this repository's own combined board command sum -- the write
four ("Cardano.KERI.Deployment.CLI") and the read-only \"list\"
("Cardano.KERI.Deployment.Verify") were one type before this ticket
(EDGE-240-04 now forbids that: 'BoardListSettings' carries a Koios token,
so write-composition cannot type it, let alone dispatch it). Composed here,
exactly as the top-level 'Instructions'\/'Opt.HasParser' block just above
already composes the top-level command list from several modules' leaf
parsers/runners -- this is the same composition, one level deeper, not a
new mechanism.
-}
data BoardCommand
    = BoardWrite !BoardInstructions
    | BoardList !BoardListSettings

runBoardCommand :: BoardCommand -> IO ()
runBoardCommand = \case
    BoardWrite instructions -> runBoard instructions
    BoardList settings -> runBoardList settings

boardCommandParser :: Opt.Parser BoardCommand
boardCommandParser =
    Opt.commands
        [ Opt.command
            "deploy"
            "Publish the frozen endpoint-board reference script"
            ( BoardWrite . BoardDeploy
                <$> Opt.subConfig
                    "deploy"
                    (deploySettingsParserWithOut "deploy/preprod/board-manifest.json")
            )
        , Opt.command
            "list"
            "List the exact verified current endpoint catalog"
            (BoardList <$> Opt.subConfig "list" boardListSettingsParser)
        , Opt.command
            "post"
            "Post one witness-signed endpoint record"
            (BoardWrite . BoardPost <$> Opt.subConfig "post" boardPostSettingsParser)
        , Opt.command
            "update"
            "Spend and recreate one owned endpoint record"
            (BoardWrite . BoardUpdate <$> Opt.subConfig "update" boardUpdateSettingsParser)
        , Opt.command
            "retire"
            "Burn one owned marker and refund its complete deposit"
            (BoardWrite . BoardRetire <$> Opt.subConfig "retire" boardRetireSettingsParser)
        ]

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
                    "list"
                    "List live checkpoints from a selected backend"
                    (List <$> Opt.subConfig "list" listSettingsParser)
                , Opt.command
                    "checkpoint"
                    "Report one checkpoint from a selected backend"
                    (Checkpoint <$> Opt.subConfig "checkpoint" checkpointSettingsParser)
                , Opt.command
                    "payer"
                    "List current payer UTxOs from a selected backend"
                    (Payer <$> Opt.subConfig "payer" payerSettingsParser)
                , Opt.command
                    "board"
                    "Operate the current on-chain endpoint catalog"
                    (Board <$> Opt.subConfig "board" boardCommandParser)
                ]

runInstructions :: Instructions -> IO ()
runInstructions = \case
    Deploy settings -> runDeploy settings
    ManifestVerify settings -> runVerify settings
    Register settings -> runRegister settings
    Advance settings -> runAdvance settings
    Close settings -> runClose settings
    Status settings -> runBackendStatusCLI settings
    List settings -> runBackendListCLI settings
    Checkpoint settings -> runBackendCheckpointCLI settings
    Payer settings -> runBackendPayerCLI settings
    Board command -> runBoardCommand command

{- | Select exactly one backend (FR-5) and render its answer or its closed
error. Checkpoint\/board manifest loading is deferred into the local\/Koios
constructor closures alone: the installed @--endpoint@ shortcut needs
neither file and must not require a checkout to run (NOTE-032).
-}
runBackendStatusCLI :: BackendSettings -> IO ()
runBackendStatusCLI settings = do
    backend <- resolveConfiguredBackend (backendCommonSettings settings)
    result <- runBackendStatus backend (backendAid settings)
    case result of
        Left err -> dieConcisely (T.unpack (renderBackendError err))
        Right view -> putStrLn (T.unpack (renderStatusView view))

runBackendListCLI :: ListSettings -> IO ()
runBackendListCLI (ListSettings settings) = do
    backend <- resolveConfiguredBackend settings
    result <- runBackendListCheckpoints backend
    case result of
        Left err -> dieConcisely (T.unpack (renderBackendError err))
        Right (freshness, checkpoints) ->
            putStrLn $
                T.unpack $
                    renderCheckpointListView
                        CheckpointListView
                            { clvSource = qbSourceLabel backend
                            , clvFreshness = freshness
                            , clvCheckpoints = checkpoints
                            }

runBackendCheckpointCLI :: CheckpointSettings -> IO ()
runBackendCheckpointCLI (CheckpointSettings aid settings) = do
    backend <- resolveConfiguredBackend settings
    result <- runBackendCheckpointByAid backend aid
    case result of
        Left err -> dieConcisely (T.unpack (renderBackendError err))
        Right (freshness, checkpoint) ->
            putStrLn $
                T.unpack $
                    renderCheckpointView
                        CheckpointView
                            { cvSource = qbSourceLabel backend
                            , cvFreshness = freshness
                            , cvAid = aid
                            , cvCheckpoint = checkpoint
                            }

runBackendPayerCLI :: PayerSettings -> IO ()
runBackendPayerCLI (PayerSettings address settings) = do
    backend <- resolveConfiguredBackend settings
    result <- runBackendPayerUtxos backend address
    case result of
        Left err -> dieConcisely (T.unpack (renderBackendError err))
        Right (freshness, utxos) ->
            putStrLn $
                T.unpack $
                    renderPayerView
                        PayerView
                            { pvSource = qbSourceLabel backend
                            , pvFreshness = freshness
                            , pvAddress = address
                            , pvUtxos = utxos
                            }

resolveConfiguredBackend :: BackendCommonSettings -> IO QueryBackend
resolveConfiguredBackend settings =
    case selectCommonBackend settings of
        Left err -> dieConcisely (T.unpack (renderBackendError err))
        Right selected ->
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

-- | Read and validate both manifests, dying concisely on either failure.
loadManifests :: BackendCommonSettings -> IO (Manifest, EndpointBoardManifest)
loadManifests settings = do
    manifest <-
        loadConfiguredManifest
            "--manifest"
            (commonBackendManifest settings)
            readManifest
    boardManifest <-
        loadConfiguredManifest
            "--board-manifest"
            (commonBackendBoardManifest settings)
            readEndpointBoardManifest
    pure (manifest, boardManifest)

loadConfiguredManifest ::
    String ->
    FilePath ->
    (FilePath -> IO (Either String manifest)) ->
    IO manifest
loadConfiguredManifest option path readConfiguredManifest = do
    result <- try @IOException (readConfiguredManifest path)
    case result of
        Left _ ->
            dieConcisely $
                "cannot open "
                    <> option
                    <> " path "
                    <> path
                    <> "; pass "
                    <> option
                    <> " with a readable path"
        Right decoded -> either dieConcisely pure decoded

dieConcisely :: String -> IO a
dieConcisely message = do
    hPutStrLn stderr ("ckeri: " <> message)
    exitFailure
