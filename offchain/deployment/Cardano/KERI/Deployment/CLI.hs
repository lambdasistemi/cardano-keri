{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.CLI
Description : opt-env-conf command surface and execution for ckeri
-}
module Cardano.KERI.Deployment.CLI (
    Instructions (..),
    DeploySettings (..),
    VerifySettings (..),
    RegisterSettings (..),
    RegisterRuntime (..),
    AdvanceSettings (..),
    CloseSettings (..),
    BoardInstructions (..),
    BoardListSettings (..),
    BoardPostSettings (..),
    BoardUpdateSettings (..),
    BoardRetireSettings (..),
    registerPreflight,
    runInstructions,

    -- * Reused by "Cardano.KERI.CLI" to compose the top-level command list
    deploySettingsParser,
    verifySettingsParser,
    registerSettingsParser,
    advanceSettingsParser,
    closeSettingsParser,
    boardInstructionsParser,
    runDeploy,
    runVerify,
    runRegister,
    runRegisterWith,
    runAdvance,
    runClose,
    runBoard,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Close (CloseEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.Deployment.Advance (
    AdvancePackage (..),
    AdvanceSigningFiles (..),
    attachControllerSignatures,
    mkAdvancePackage,
    writeAdvanceSigningPackage,
 )
import Cardano.KERI.Deployment.AdvanceTransaction qualified as AdvanceTx
import Cardano.KERI.Deployment.ChainIndex (
    ChainAssetUtxo (..),
    KoiosToken (..),
    matchesReference,
    queryAssetUtxos,
    queryReferenceScripts,
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    queryActiveCheckpoint,
 )
import Cardano.KERI.Deployment.Close (
    ClosePackage (..),
    CloseSigningFiles (..),
    attachCloseControllerSignatures,
    mkClosePackage,
    writeCloseSigningPackage,
 )
import Cardano.KERI.Deployment.CloseTransaction qualified as CloseTx
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    EndpointRecord (..),
    missingBoardWitnesses,
    parseEndpointRecord,
    parseWitnessKey,
    queryBoardCatalog,
    renderBoardCatalog,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    mkEndpointBoardManifest,
    readEndpointBoardManifest,
    writeEndpointBoardManifestAtomic,
 )
import Cardano.KERI.Deployment.EndpointBoardTransaction qualified as BoardTx
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    RotationExport (..),
    parseInceptionExport,
    parseIndexedSignatureLines,
    parseRotationExport,
 )
import Cardano.KERI.Deployment.LiveRuntime (
    LiveConfig (..),
    LiveContext (..),
    decodePaymentAddress,
    indexedFundingUtxos,
    resolveBoardReference,
    resolveManifestReferences,
    resolveOutput,
    rewardAccountForScript,
    rewardAccountRegistered,
    transactionSettled,
    withLiveContext,
 )
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
    SourceInfo (..),
    blueprintSha256,
    manifestValidationErrors,
    mkManifest,
    readManifest,
    writeManifestAtomic,
 )
import Cardano.KERI.Deployment.Publisher (
    PublishConfig (..),
    publishScripts,
 )
import Cardano.KERI.Deployment.Registration (
    RegistrationPlan (..),
    awaitAsset,
    mkRegistrationPlan,
    premintOne,
    registerOne,
 )
import Cardano.KERI.Deployment.Registration qualified as Registration
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    deriveBoardScript,
    deriveV1Scripts,
    loadBlueprint,
 )
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId)
import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Char (isHexDigit)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import OptEnvConf qualified as Opt
import System.Directory (doesDirectoryExist)

data Instructions
    = Deploy DeploySettings
    | ManifestVerify VerifySettings
    | Register RegisterSettings
    | Advance AdvanceSettings
    | Close CloseSettings
    | Board BoardInstructions
    deriving stock (Show, Eq)

data BoardInstructions
    = BoardDeploy DeploySettings
    | BoardList BoardListSettings
    | BoardPost BoardPostSettings
    | BoardUpdate BoardUpdateSettings
    | BoardRetire BoardRetireSettings
    deriving stock (Show, Eq)

data DeploySettings = DeploySettings
    { deployNetwork :: Text
    , deployNetworkMagic :: Int
    , deployBlueprint :: FilePath
    , deployNodeSocket :: FilePath
    , deployFundingAddress :: Text
    , deploySigningKeyFile :: FilePath
    , deploySourceRepo :: FilePath
    , deploySourceRepositoryUrl :: Text
    , deploySourceCommit :: Maybe Text
    , deployOut :: FilePath
    , deployReferenceLovelace :: Integer
    , deployKoiosUrl :: Text
    , deployKoiosToken :: Maybe KoiosToken
    , deployTimeoutSeconds :: Int
    }
    deriving stock (Show, Eq)

data VerifySettings = VerifySettings
    { verifyManifest :: FilePath
    , verifyBlueprint :: FilePath
    , verifySourceRepo :: FilePath
    , verifyKoiosUrl :: Text
    , verifyKoiosToken :: Maybe KoiosToken
    }
    deriving stock (Show, Eq)

data RegisterSettings = RegisterSettings
    { registerNetwork :: Text
    , registerNetworkMagic :: Int
    , registerKel :: FilePath
    , registerPayer :: FilePath
    , registerNodeSocket :: FilePath
    , registerFundingAddress :: Text
    , registerManifest :: FilePath
    , registerBoardManifest :: FilePath
    , registerKoiosUrl :: Text
    , registerKoiosToken :: Maybe KoiosToken
    , registerTimeoutSeconds :: Int
    , registerAllowUnlistedWitnesses :: Bool
    , registerAllowExistingCheckpoint :: Bool
    , registerEscrowLovelace :: Integer
    }
    deriving stock (Show, Eq)

{- | Effects used by the register preflight and live transaction boundary.
Keeping them explicit makes the required read-before-submit order observable
without requiring unit tests to open a node connection.
-}
data RegisterRuntime = RegisterRuntime
    { registerReadKel :: FilePath -> IO BS.ByteString
    , registerReadManifest :: FilePath -> IO (Either String Manifest)
    , registerQueryAssets ::
        Text ->
        Maybe KoiosToken ->
        Text ->
        Text ->
        IO [ChainAssetUtxo]
    , registerReadBoardManifest ::
        FilePath ->
        IO (Either String EndpointBoardManifest)
    , registerQueryBoard ::
        Text ->
        Maybe KoiosToken ->
        Text ->
        Text ->
        IO [BoardEntry]
    , registerWriteLine :: String -> IO ()
    , registerSubmit ::
        RegisterSettings ->
        Manifest ->
        RegistrationPlan ->
        IO ()
    }

data AdvanceSettings = AdvanceSettings
    { advanceNetwork :: Text
    , advanceNetworkMagic :: Int
    , advanceConfiguredAid :: Text
    , advanceKel :: FilePath
    , advanceSigningPackage :: Maybe FilePath
    , advanceControllerSignatures :: Maybe FilePath
    , advancePayer :: Maybe FilePath
    , advanceNodeSocket :: Maybe FilePath
    , advanceFundingAddress :: Maybe Text
    , advanceManifest :: FilePath
    , advanceKoiosUrl :: Text
    , advanceKoiosToken :: Maybe KoiosToken
    , advanceTimeoutSeconds :: Int
    , advanceValidatorTestUnderSigned :: Bool
    , advanceValidatorTestUnderWitnessed :: Bool
    , advanceValidatorTestStale :: Bool
    }
    deriving stock (Show, Eq)

data CloseSettings = CloseSettings
    { closeNetwork :: Text
    , closeNetworkMagic :: Int
    , closeConfiguredAid :: Text
    , closeKel :: FilePath
    , closeTo :: Text
    , closeSigningPackage :: Maybe FilePath
    , closeControllerSignatures :: Maybe FilePath
    , closePayer :: Maybe FilePath
    , closeNodeSocket :: Maybe FilePath
    , closeFundingAddress :: Maybe Text
    , closeChangeAddress :: Maybe Text
    , closeManifest :: FilePath
    , closeKoiosUrl :: Text
    , closeKoiosToken :: Maybe KoiosToken
    , closeTimeoutSeconds :: Int
    , closeValidatorTestNonController :: Bool
    }
    deriving stock (Show, Eq)

data BoardListSettings = BoardListSettings
    { boardListManifest :: !FilePath
    , boardListKoiosUrl :: !Text
    , boardListKoiosToken :: !(Maybe KoiosToken)
    }
    deriving stock (Show, Eq)

data BoardTransactionSettings = BoardTransactionSettings
    { boardTransactionNetwork :: !Text
    , boardTransactionNetworkMagic :: !Int
    , boardTransactionPayer :: !FilePath
    , boardTransactionNodeSocket :: !FilePath
    , boardTransactionFundingAddress :: !Text
    , boardTransactionChangeAddress :: !(Maybe Text)
    , boardTransactionManifest :: !FilePath
    , boardTransactionKoiosUrl :: !Text
    , boardTransactionKoiosToken :: !(Maybe KoiosToken)
    , boardTransactionTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

data BoardPostSettings = BoardPostSettings
    { boardPostEndpointRecord :: !FilePath
    , boardPostDepositLovelace :: !Integer
    , boardPostTransaction :: !BoardTransactionSettings
    }
    deriving stock (Show, Eq)

data BoardUpdateSettings = BoardUpdateSettings
    { boardUpdateEndpointRecord :: !FilePath
    , boardUpdateOutReference :: !(Maybe Text)
    , boardUpdateTransaction :: !BoardTransactionSettings
    }
    deriving stock (Show, Eq)

data BoardRetireSettings = BoardRetireSettings
    { boardRetireWitness :: !Text
    , boardRetireOutReference :: !(Maybe Text)
    , boardRetireTo :: !Text
    , boardRetireTransaction :: !BoardTransactionSettings
    }
    deriving stock (Show, Eq)

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
                    "board"
                    "Operate the current on-chain endpoint catalog"
                    (Board <$> Opt.subConfig "board" boardInstructionsParser)
                ]

deploySettingsParser :: Opt.Parser DeploySettings
deploySettingsParser =
    deploySettingsParserWithOut "deploy/preprod/m1-manifest.json"

deploySettingsParserWithOut :: FilePath -> Opt.Parser DeploySettings
deploySettingsParserWithOut defaultOut = do
    deployNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    deployNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    deployBlueprint <-
        stringSetting
            "blueprint"
            "CKERI_BLUEPRINT"
            "blueprint"
            "Immutable Aiken plutus.json"
            Nothing
    deployNodeSocket <-
        stringSetting
            "node-socket"
            "CKERI_NODE_SOCKET"
            "node-socket"
            "Cardano node socket"
            Nothing
    deployFundingAddress <-
        textSetting
            "funding-address"
            "CKERI_FUNDING_ADDRESS"
            "funding-address"
            "Bech32 payment address funding publication"
            Nothing
    deploySigningKeyFile <-
        stringSetting
            "signing-key-file"
            "CKERI_SIGNING_KEY_FILE"
            "signing-key-file"
            "Cardano payment signing-key envelope"
            Nothing
    deploySourceRepo <-
        stringSetting
            "source-repo"
            "CKERI_SOURCE_REPO"
            "source-repo"
            "Checkout used for source provenance"
            (Just ".")
    deploySourceRepositoryUrl <-
        textSetting
            "source-repository-url"
            "CKERI_SOURCE_REPOSITORY_URL"
            "source-repository-url"
            "Repository URL recorded in the manifest"
            (Just "https://github.com/lambdasistemi/cardano-keri")
    deploySourceCommit <-
        Opt.optional $
            textSetting
                "source-commit"
                "CKERI_SOURCE_COMMIT"
                "source-commit"
                "Source commit (defaults to the checkout HEAD)"
                Nothing
    deployOut <-
        stringSetting
            "out"
            "CKERI_OUT"
            "out"
            "Output manifest path"
            (Just defaultOut)
    deployReferenceLovelace <-
        integerSetting
            "reference-lovelace"
            "CKERI_REFERENCE_LOVELACE"
            "reference-lovelace"
            "Lovelace held in each reference-script output"
            (Just 100_000_000)
    deployKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    deployKoiosToken <- optionalKoiosTokenParser
    deployTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout per script"
            (Just 600)
    pure DeploySettings{..}

verifySettingsParser :: Opt.Parser VerifySettings
verifySettingsParser = do
    verifyManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "Release manifest to verify"
            (Just "deploy/preprod/m1-manifest.json")
    verifyBlueprint <-
        stringSetting
            "blueprint"
            "CKERI_BLUEPRINT"
            "blueprint"
            "Immutable Aiken plutus.json"
            Nothing
    verifySourceRepo <-
        stringSetting
            "source-repo"
            "CKERI_SOURCE_REPO"
            "source-repo"
            "Checkout used for source provenance"
            (Just ".")
    verifyKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    verifyKoiosToken <- optionalKoiosTokenParser
    pure VerifySettings{..}

registerSettingsParser :: Opt.Parser RegisterSettings
registerSettingsParser = do
    registerNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    registerNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    registerKel <-
        stringSetting
            "kel"
            "CKERI_KEL"
            "kel"
            "Binary-safe path to a kli export stream"
            Nothing
    registerPayer <-
        stringSetting
            "payer"
            "CKERI_PAYER"
            "payer"
            "Cardano payment signing-key file"
            Nothing
    registerNodeSocket <-
        stringSetting
            "node-socket"
            "CKERI_NODE_SOCKET"
            "node-socket"
            "Cardano node socket"
            Nothing
    registerFundingAddress <-
        textSetting
            "funding-address"
            "CKERI_FUNDING_ADDRESS"
            "funding-address"
            "Bech32 payment address funding registration"
            Nothing
    registerManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    registerBoardManifest <-
        stringSetting
            "board-manifest"
            "CKERI_BOARD_MANIFEST"
            "board-manifest"
            "Endpoint-board preprod deployment manifest"
            (Just "deploy/preprod/board-manifest.json")
    registerKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    registerKoiosToken <- optionalKoiosTokenParser
    registerTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout per transaction"
            (Just 600)
    registerAllowUnlistedWitnesses <-
        Opt.yesNoSwitch
            [ Opt.long "allow-unlisted-witnesses"
            , Opt.env "CKERI_ALLOW_UNLISTED_WITNESSES"
            , Opt.conf "allow-unlisted-witnesses"
            , Opt.help
                "Acknowledge that declared witnesses lack a board record check"
            , Opt.value False
            ]
    registerAllowExistingCheckpoint <-
        Opt.yesNoSwitch
            [ Opt.long "allow-existing-checkpoint"
            , Opt.env "CKERI_ALLOW_EXISTING_CHECKPOINT"
            , Opt.conf "allow-existing-checkpoint"
            , Opt.help
                "Acknowledge sovereign repeat registration of a live AID"
            , Opt.value False
            ]
    registerEscrowLovelace <-
        integerSetting
            "escrow-lovelace"
            "CKERI_ESCROW_LOVELACE"
            "escrow-lovelace"
            "ACTIVE output lovelace (acceptance-only underfunding override)"
            (Just 1_007_000_000)
    pure RegisterSettings{..}

advanceSettingsParser :: Opt.Parser AdvanceSettings
advanceSettingsParser = do
    advanceNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    advanceNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    advanceConfiguredAid <-
        textSetting
            "aid"
            "CKERI_AID"
            "aid"
            "44-character KERI E-code identifier"
            Nothing
    advanceKel <-
        stringSetting
            "kel"
            "CKERI_KEL"
            "kel"
            "Binary-safe path to a witnessed kli rotation export"
            Nothing
    advanceSigningPackage <-
        Opt.optional $
            stringSetting
                "signing-package"
                "CKERI_SIGNING_PACKAGE"
                "signing-package"
                "Directory receiving the binary AdvanceMessage package"
                Nothing
    advanceControllerSignatures <-
        Opt.optional $
            stringSetting
                "controller-signatures"
                "CKERI_CONTROLLER_SIGNATURES"
                "controller-signatures"
                "Bare indexed CESR signatures over advance-message.cbor"
                Nothing
    advancePayer <-
        Opt.optional $
            stringSetting
                "payer"
                "CKERI_PAYER"
                "payer"
                "Cardano payment signing-key file"
                Nothing
    advanceNodeSocket <-
        Opt.optional $
            stringSetting
                "node-socket"
                "CKERI_NODE_SOCKET"
                "node-socket"
                "Cardano node socket"
                Nothing
    advanceFundingAddress <-
        Opt.optional $
            textSetting
                "funding-address"
                "CKERI_FUNDING_ADDRESS"
                "funding-address"
                "Bech32 payment address funding the advance"
                Nothing
    advanceManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    advanceKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    advanceKoiosToken <- optionalKoiosTokenParser
    advanceTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout"
            (Just 600)
    advanceValidatorTestUnderSigned <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-under-signed"
            , Opt.env "CKERI_VALIDATOR_TEST_UNDER_SIGNED"
            , Opt.conf "validator-test-under-signed"
            , Opt.help
                "ACCEPTANCE ONLY: send one signature to real script evaluation"
            , Opt.value False
            ]
    advanceValidatorTestUnderWitnessed <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-under-witnessed"
            , Opt.env "CKERI_VALIDATOR_TEST_UNDER_WITNESSED"
            , Opt.conf "validator-test-under-witnessed"
            , Opt.help
                "ACCEPTANCE ONLY: send one witness receipt to real script evaluation"
            , Opt.value False
            ]
    advanceValidatorTestStale <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-stale"
            , Opt.env "CKERI_VALIDATOR_TEST_STALE"
            , Opt.conf "validator-test-stale"
            , Opt.help
                "ACCEPTANCE ONLY: replay the rotation against current live state"
            , Opt.value False
            ]
    pure AdvanceSettings{..}

closeSettingsParser :: Opt.Parser CloseSettings
closeSettingsParser = do
    closeNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    closeNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    closeConfiguredAid <-
        textSetting
            "aid"
            "CKERI_AID"
            "aid"
            "44-character KERI E-code identifier"
            Nothing
    closeKel <-
        stringSetting
            "kel"
            "CKERI_KEL"
            "kel"
            "Binary-safe path to the controller's kli inception export"
            Nothing
    closeTo <-
        textSetting
            "to"
            "CKERI_TO"
            "to"
            "Preprod payment address receiving the complete escrow"
            Nothing
    closeSigningPackage <-
        Opt.optional $
            stringSetting
                "signing-package"
                "CKERI_SIGNING_PACKAGE"
                "signing-package"
                "Directory receiving the binary CloseMessage package"
                Nothing
    closeControllerSignatures <-
        Opt.optional $
            stringSetting
                "controller-signatures"
                "CKERI_CONTROLLER_SIGNATURES"
                "controller-signatures"
                "Bare indexed CESR signatures over close-message.cbor"
                Nothing
    closePayer <-
        Opt.optional $
            stringSetting
                "payer"
                "CKERI_PAYER"
                "payer"
                "Cardano payment signing-key file"
                Nothing
    closeNodeSocket <-
        Opt.optional $
            stringSetting
                "node-socket"
                "CKERI_NODE_SOCKET"
                "node-socket"
                "Cardano node socket"
                Nothing
    closeFundingAddress <-
        Opt.optional $
            textSetting
                "funding-address"
                "CKERI_FUNDING_ADDRESS"
                "funding-address"
                "Bech32 payment address funding the close fee"
                Nothing
    closeChangeAddress <-
        Opt.optional $
            textSetting
                "change-address"
                "CKERI_CHANGE_ADDRESS"
                "change-address"
                "Fee change address, distinct from the exact refund target"
                Nothing
    closeManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    closeKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    closeKoiosToken <- optionalKoiosTokenParser
    closeTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout"
            (Just 600)
    closeValidatorTestNonController <-
        Opt.yesNoSwitch
            [ Opt.long "validator-test-non-controller"
            , Opt.env "CKERI_VALIDATOR_TEST_NON_CONTROLLER"
            , Opt.conf "validator-test-non-controller"
            , Opt.help
                "ACCEPTANCE ONLY: bypass local signature proof and reach the validator"
            , Opt.value False
            ]
    pure CloseSettings{..}

boardInstructionsParser :: Opt.Parser BoardInstructions
boardInstructionsParser =
    Opt.commands
        [ Opt.command
            "deploy"
            "Publish the frozen endpoint-board reference script"
            ( BoardDeploy
                <$> Opt.subConfig
                    "deploy"
                    ( deploySettingsParserWithOut
                        "deploy/preprod/board-manifest.json"
                    )
            )
        , Opt.command
            "list"
            "List the exact verified current endpoint catalog"
            ( BoardList
                <$> Opt.subConfig "list" boardListSettingsParser
            )
        , Opt.command
            "post"
            "Post one witness-signed endpoint record"
            ( BoardPost
                <$> Opt.subConfig "post" boardPostSettingsParser
            )
        , Opt.command
            "update"
            "Spend and recreate one owned endpoint record"
            ( BoardUpdate
                <$> Opt.subConfig "update" boardUpdateSettingsParser
            )
        , Opt.command
            "retire"
            "Burn one owned marker and refund its complete deposit"
            ( BoardRetire
                <$> Opt.subConfig "retire" boardRetireSettingsParser
            )
        ]

boardListSettingsParser :: Opt.Parser BoardListSettings
boardListSettingsParser = do
    boardListManifest <-
        stringSetting
            "board-manifest"
            "CKERI_BOARD_MANIFEST"
            "board-manifest"
            "Endpoint-board preprod deployment manifest"
            (Just "deploy/preprod/board-manifest.json")
    boardListKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    boardListKoiosToken <- optionalKoiosTokenParser
    pure BoardListSettings{..}

boardTransactionSettingsParser :: Opt.Parser BoardTransactionSettings
boardTransactionSettingsParser = do
    boardTransactionNetwork <-
        textSetting
            "network"
            "CKERI_NETWORK"
            "network"
            "Cardano network name"
            (Just "preprod")
    boardTransactionNetworkMagic <-
        intSetting
            "network-magic"
            "CKERI_NETWORK_MAGIC"
            "network-magic"
            "Cardano testnet network magic"
            (Just 1)
    boardTransactionPayer <-
        stringSetting
            "payer"
            "CKERI_PAYER"
            "payer"
            "Cardano payment signing-key file for the board owner"
            Nothing
    boardTransactionNodeSocket <-
        stringSetting
            "node-socket"
            "CKERI_NODE_SOCKET"
            "node-socket"
            "Cardano node socket"
            Nothing
    boardTransactionFundingAddress <-
        textSetting
            "funding-address"
            "CKERI_FUNDING_ADDRESS"
            "funding-address"
            "Bech32 payment address funding and owning the board record"
            Nothing
    boardTransactionChangeAddress <-
        Opt.optional $
            textSetting
                "change-address"
                "CKERI_CHANGE_ADDRESS"
                "change-address"
                "Fee change address (must differ from an identical retire target)"
                Nothing
    boardTransactionManifest <-
        stringSetting
            "board-manifest"
            "CKERI_BOARD_MANIFEST"
            "board-manifest"
            "Endpoint-board preprod deployment manifest"
            (Just "deploy/preprod/board-manifest.json")
    boardTransactionKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    boardTransactionKoiosToken <- optionalKoiosTokenParser
    boardTransactionTimeoutSeconds <-
        intSetting
            "timeout-seconds"
            "CKERI_TIMEOUT_SECONDS"
            "timeout-seconds"
            "Settlement timeout"
            (Just 600)
    pure BoardTransactionSettings{..}

boardPostSettingsParser :: Opt.Parser BoardPostSettings
boardPostSettingsParser = do
    boardPostEndpointRecord <-
        stringSetting
            "endpoint-record"
            "CKERI_ENDPOINT_RECORD"
            "endpoint-record"
            "Binary-safe path to a witness-signed KERI OOBI stream"
            Nothing
    boardPostDepositLovelace <-
        integerSetting
            "deposit-lovelace"
            "CKERI_BOARD_DEPOSIT_LOVELACE"
            "deposit-lovelace"
            "Exact lovelace deposit carried by the record"
            (Just 4_000_000)
    boardPostTransaction <- boardTransactionSettingsParser
    pure BoardPostSettings{..}

boardUpdateSettingsParser :: Opt.Parser BoardUpdateSettings
boardUpdateSettingsParser = do
    boardUpdateEndpointRecord <-
        stringSetting
            "endpoint-record"
            "CKERI_ENDPOINT_RECORD"
            "endpoint-record"
            "Binary-safe path to the replacement witness-signed KERI OOBI stream"
            Nothing
    boardUpdateOutReference <-
        Opt.optional $
            textSetting
                "board-out-ref"
                "CKERI_BOARD_OUT_REF"
                "board-out-ref"
                "Exact TXID#INDEX to select when duplicate records exist"
                Nothing
    boardUpdateTransaction <- boardTransactionSettingsParser
    pure BoardUpdateSettings{..}

boardRetireSettingsParser :: Opt.Parser BoardRetireSettings
boardRetireSettingsParser = do
    boardRetireWitness <-
        textSetting
            "witness"
            "CKERI_WITNESS"
            "witness"
            "44-character KERI B-code witness identifier"
            Nothing
    boardRetireOutReference <-
        Opt.optional $
            textSetting
                "board-out-ref"
                "CKERI_BOARD_OUT_REF"
                "board-out-ref"
                "Exact TXID#INDEX to select when duplicate records exist"
                Nothing
    boardRetireTo <-
        textSetting
            "to"
            "CKERI_TO"
            "to"
            "Preprod payment address receiving the complete board deposit"
            Nothing
    boardRetireTransaction <- boardTransactionSettingsParser
    pure BoardRetireSettings{..}

optionalKoiosTokenParser :: Opt.Parser (Maybe KoiosToken)
optionalKoiosTokenParser =
    Opt.optional $
        KoiosToken
            <$> textSetting
                "koios-token"
                "KOIOS_TOKEN"
                "koios-token"
                "Optional Koios bearer token"
                Nothing

stringSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe String ->
    Opt.Parser String
stringSetting optionName environmentName configName description defaultValue =
    withMaybeDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

textSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe Text ->
    Opt.Parser Text
textSetting optionName environmentName configName description defaultValue =
    T.pack
        <$> stringSetting
            optionName
            environmentName
            configName
            description
            (T.unpack <$> defaultValue)

intSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe Int ->
    Opt.Parser Int
intSetting optionName environmentName configName description defaultValue =
    withMaybeDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

integerSetting ::
    String ->
    String ->
    String ->
    String ->
    Maybe Integer ->
    Opt.Parser Integer
integerSetting optionName environmentName configName description defaultValue =
    withMaybeDefault defaultValue $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long optionName
            , Opt.env environmentName
            , Opt.conf configName
            , Opt.metavar "VALUE"
            , Opt.help description
            ]

withMaybeDefault :: (Show a) => Maybe a -> Opt.Parser a -> Opt.Parser a
withMaybeDefault defaultValue parser =
    maybe parser (`Opt.withDefault` parser) defaultValue

runInstructions :: Instructions -> IO ()
runInstructions = \case
    Deploy settings -> runDeploy settings
    ManifestVerify settings -> runVerify settings
    Register settings -> runRegister settings
    Advance settings -> runAdvance settings
    Close settings -> runClose settings
    Board instructions -> runBoard instructions

runBoard :: BoardInstructions -> IO ()
runBoard = \case
    BoardDeploy settings -> runBoardDeploy settings
    BoardList settings -> runBoardList settings
    BoardPost settings -> runBoardPost settings
    BoardUpdate settings -> runBoardUpdate settings
    BoardRetire settings -> runBoardRetire settings

runBoardDeploy :: DeploySettings -> IO ()
runBoardDeploy settings = do
    unless
        (deployNetwork settings == "preprod" && deployNetworkMagic settings == 1)
        (fail "M1 endpoint-board deployment supports only preprod network magic 1")
    when (deployReferenceLovelace settings <= 0) $
        fail "reference-lovelace must be positive"
    when (deployTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    blueprint <-
        loadBlueprint (deployBlueprint settings) >>= either fail pure
    artifact <- either fail pure (deriveBoardScript blueprint)
    digest <- blueprintSha256 (deployBlueprint settings)
    commit <- resolveSourceCommit settings
    verifySourceTree (deploySourceRepo settings) commit
    references <-
        withLiveContext (deployLiveConfig settings) $ \context ->
            publishArtifactsLive settings context [artifact]
    reference <-
        case references of
            [("endpoint-board", settled)] -> pure settled
            _ ->
                fail
                    "publisher did not return exactly the endpoint-board reference"
    publishedAt <- publicationTimestamp
    manifest <-
        either fail pure $
            mkEndpointBoardManifest
                (deploySourceRepositoryUrl settings)
                commit
                digest
                publishedAt
                artifact
                reference
    writeEndpointBoardManifestAtomic (deployOut settings) manifest
    putStrLn ("board manifest: " <> deployOut settings)

runBoardList :: BoardListSettings -> IO ()
runBoardList settings = do
    manifest <-
        readEndpointBoardManifest (boardListManifest settings)
            >>= either fail pure
    let info = endpointBoardManifestInfo manifest
    entries <-
        queryBoardCatalog
            (boardListKoiosUrl settings)
            (boardListKoiosToken settings)
            (endpointBoardPolicyId info)
            (endpointBoardAddress info)
    putStrLn ("board records: " <> show (length entries))
    putStr (T.unpack $ renderBoardCatalog entries)

runBoardPost :: BoardPostSettings -> IO ()
runBoardPost settings = do
    let transaction = boardPostTransaction settings
    validateBoardTransactionSettings transaction
    endpointBytes <- BS.readFile (boardPostEndpointRecord settings)
    record <- either fail pure (parseEndpointRecord endpointBytes)
    manifest <- readBoardTransactionManifest transaction
    plan <-
        either fail pure $
            BoardTx.mkBoardPostPlan
                manifest
                (boardTransactionFundingAddress transaction)
                (boardPostDepositLovelace settings)
                record
    withBoardContext transaction manifest $ \context config -> do
        funding <- indexedFundingUtxos context
        result <-
            BoardTx.runBoardPostTransaction config plan funding
                >>= either (fail . show) pure
        putStrLn $
            "board txid: "
                <> T.unpack
                    (renderTransactionId $ BoardTx.boardResultTxId result)
                <> " deposit: "
                <> show (boardPostDepositLovelace settings `div` 1_000_000)
                <> " tADA"

runBoardUpdate :: BoardUpdateSettings -> IO ()
runBoardUpdate settings = do
    let transaction = boardUpdateTransaction settings
    validateBoardTransactionSettings transaction
    endpointBytes <- BS.readFile (boardUpdateEndpointRecord settings)
    record <- either fail pure (parseEndpointRecord endpointBytes)
    manifest <- readBoardTransactionManifest transaction
    entries <- queryBoardTransactionCatalog transaction manifest
    entry <-
        either fail pure $
            BoardTx.selectBoardEntry
                (boardUpdateOutReference settings)
                (endpointWitnessKey record)
                entries
    plan <-
        either fail pure $
            BoardTx.mkBoardUpdatePlan
                manifest
                (boardTransactionFundingAddress transaction)
                entry
                record
    withBoardContext transaction manifest $ \context config -> do
        funding <- indexedFundingUtxos context
        boardInput <-
            resolveOutput context (boardTxId entry) (boardIndex entry)
        result <-
            BoardTx.runBoardUpdateTransaction config plan funding boardInput
                >>= either (fail . show) pure
        putStrLn $
            "board update txid: "
                <> T.unpack
                    (renderTransactionId $ BoardTx.boardResultTxId result)
        putStrLn $
            "replaced: "
                <> T.unpack (BoardTx.boardUpdateSpentReference plan)

runBoardRetire :: BoardRetireSettings -> IO ()
runBoardRetire settings = do
    let transaction = boardRetireTransaction settings
    validateBoardTransactionSettings transaction
    witness <- either fail pure (parseWitnessKey $ boardRetireWitness settings)
    manifest <- readBoardTransactionManifest transaction
    entries <- queryBoardTransactionCatalog transaction manifest
    entry <-
        either fail pure $
            BoardTx.selectBoardEntry
                (boardRetireOutReference settings)
                witness
                entries
    plan <-
        either fail pure $
            BoardTx.mkBoardRetirePlan
                manifest
                (boardTransactionFundingAddress transaction)
                (boardRetireTo settings)
                entry
    withBoardContext transaction manifest $ \context config -> do
        funding <- indexedFundingUtxos context
        boardInput <-
            resolveOutput context (boardTxId entry) (boardIndex entry)
        result <-
            BoardTx.runBoardRetireTransaction config plan funding boardInput
                >>= either (fail . show) pure
        putStrLn $
            "board retire txid: "
                <> T.unpack
                    (renderTransactionId $ BoardTx.boardResultTxId result)
        putStrLn $
            "refunded: "
                <> show
                    (BoardTx.boardRetireRefundLovelace plan `div` 1_000_000)
                <> " tADA to "
                <> T.unpack (boardRetireTo settings)

validateBoardTransactionSettings :: BoardTransactionSettings -> IO ()
validateBoardTransactionSettings settings = do
    unless
        ( boardTransactionNetwork settings == "preprod"
            && boardTransactionNetworkMagic settings == 1
        )
        (fail "M1 endpoint-board transactions support only preprod network magic 1")
    when (boardTransactionTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"

readBoardTransactionManifest ::
    BoardTransactionSettings ->
    IO EndpointBoardManifest
readBoardTransactionManifest settings =
    readEndpointBoardManifest (boardTransactionManifest settings)
        >>= either fail pure

queryBoardTransactionCatalog ::
    BoardTransactionSettings ->
    EndpointBoardManifest ->
    IO [BoardEntry]
queryBoardTransactionCatalog settings manifest =
    let info = endpointBoardManifestInfo manifest
     in queryBoardCatalog
            (boardTransactionKoiosUrl settings)
            (boardTransactionKoiosToken settings)
            (endpointBoardPolicyId info)
            (endpointBoardAddress info)

withBoardContext ::
    BoardTransactionSettings ->
    EndpointBoardManifest ->
    (LiveContext -> BoardTx.BoardConfig -> IO a) ->
    IO a
withBoardContext settings manifest action =
    withLiveContext (boardLiveConfig settings) $ \context -> do
        references <- resolveBoardReference context manifest
        changeAddress <-
            either fail pure $
                decodePaymentAddress $
                    fromMaybe
                        (boardTransactionFundingAddress settings)
                        (boardTransactionChangeAddress settings)
        action
            context
            BoardTx.BoardConfig
                { BoardTx.boardRuntime = liveTransactionRuntime context
                , BoardTx.boardReferenceUtxos = references
                , BoardTx.boardFundingAddress = liveFundingAddress context
                , BoardTx.boardChangeAddress = changeAddress
                }

deployLiveConfig :: DeploySettings -> LiveConfig
deployLiveConfig settings =
    LiveConfig
        { liveNetworkMagic = deployNetworkMagic settings
        , liveNodeSocket = deployNodeSocket settings
        , liveSigningKeyFile = deploySigningKeyFile settings
        , liveFundingAddressText = deployFundingAddress settings
        , liveKoiosUrl = deployKoiosUrl settings
        , liveKoiosToken = deployKoiosToken settings
        , liveTimeoutSeconds = deployTimeoutSeconds settings
        }

registerLiveConfig :: RegisterSettings -> LiveConfig
registerLiveConfig settings =
    LiveConfig
        { liveNetworkMagic = registerNetworkMagic settings
        , liveNodeSocket = registerNodeSocket settings
        , liveSigningKeyFile = registerPayer settings
        , liveFundingAddressText = registerFundingAddress settings
        , liveKoiosUrl = registerKoiosUrl settings
        , liveKoiosToken = registerKoiosToken settings
        , liveTimeoutSeconds = registerTimeoutSeconds settings
        }

advanceLiveConfig ::
    AdvanceSettings ->
    FilePath ->
    FilePath ->
    Text ->
    LiveConfig
advanceLiveConfig settings payer nodeSocket fundingAddress =
    LiveConfig
        { liveNetworkMagic = advanceNetworkMagic settings
        , liveNodeSocket = nodeSocket
        , liveSigningKeyFile = payer
        , liveFundingAddressText = fundingAddress
        , liveKoiosUrl = advanceKoiosUrl settings
        , liveKoiosToken = advanceKoiosToken settings
        , liveTimeoutSeconds = advanceTimeoutSeconds settings
        }

closeLiveConfig ::
    CloseSettings ->
    FilePath ->
    FilePath ->
    Text ->
    LiveConfig
closeLiveConfig settings payer nodeSocket fundingAddress =
    LiveConfig
        { liveNetworkMagic = closeNetworkMagic settings
        , liveNodeSocket = nodeSocket
        , liveSigningKeyFile = payer
        , liveFundingAddressText = fundingAddress
        , liveKoiosUrl = closeKoiosUrl settings
        , liveKoiosToken = closeKoiosToken settings
        , liveTimeoutSeconds = closeTimeoutSeconds settings
        }

boardLiveConfig :: BoardTransactionSettings -> LiveConfig
boardLiveConfig settings =
    LiveConfig
        { liveNetworkMagic = boardTransactionNetworkMagic settings
        , liveNodeSocket = boardTransactionNodeSocket settings
        , liveSigningKeyFile = boardTransactionPayer settings
        , liveFundingAddressText = boardTransactionFundingAddress settings
        , liveKoiosUrl = boardTransactionKoiosUrl settings
        , liveKoiosToken = boardTransactionKoiosToken settings
        , liveTimeoutSeconds = boardTransactionTimeoutSeconds settings
        }

publishArtifactsLive ::
    DeploySettings ->
    LiveContext ->
    [ScriptArtifact] ->
    IO [(Text, Reference)]
publishArtifactsLive settings context = traverse publishArtifact
  where
    publishArtifact artifact = do
        funding <- indexedFundingUtxos context
        published <-
            publishScripts
                PublishConfig
                    { publishRuntime = liveTransactionRuntime context
                    , publishInputUtxos = funding
                    , publishFundingAddress = liveFundingAddress context
                    , publishReferenceLovelace =
                        deployReferenceLovelace settings
                    , publishQueryReferences = \scriptHash ->
                        queryReferenceScripts
                            (deployKoiosUrl settings)
                            (deployKoiosToken settings)
                            [scriptHash]
                    , publishTimeoutSeconds =
                        deployTimeoutSeconds settings
                    }
                [artifact]
        case published of
            [reference] -> pure reference
            _ -> fail "single-artifact publisher returned an impossible cardinality"

resolveSourceCommit :: DeploySettings -> IO Text
resolveSourceCommit settings =
    case deploySourceCommit settings of
        Nothing ->
            fail
                "--source-commit is required; production composition does not inspect Git through a subprocess"
        Just commit -> pure (T.toLower commit)

publicationTimestamp :: IO Text
publicationTimestamp =
    T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
        <$> getCurrentTime

registerPreflight ::
    Text ->
    Int ->
    Bool ->
    Bool ->
    Int ->
    [BoardEntry] ->
    InceptionExport ->
    Either String ()
registerPreflight network networkMagic allowUnlisted allowExisting existingCount catalog inception = do
    unless (network == "preprod" && networkMagic == 1) $
        Left "M1 V1 registration supports only preprod network magic 1"
    when (existingCount < 0) $
        Left "checkpoint discovery count cannot be negative"
    when (not allowExisting && existingCount == 1) $
        Left "checkpoint already registered; refusing before premint"
    when (not allowExisting && existingCount > 1) $
        Left "checkpoint discovery is ambiguous; refusing before premint"
    let witnesses = cdWitnesses (inceptionDatum inception)
        missing = missingBoardWitnesses witnesses catalog
    when (not allowUnlisted && not (null missing)) $
        Left $
            show (length missing)
                <> "/"
                <> show (length witnesses)
                <> " declared witnesses are absent from the verified board; pass \
                   \--allow-unlisted-witnesses to acknowledge reduced watchability"

runRegister :: RegisterSettings -> IO ()
runRegister = runRegisterWith productionRegisterRuntime

-- | Execute every read-only preflight effect in order, then submit live.
runRegisterWith :: RegisterRuntime -> RegisterSettings -> IO ()
runRegisterWith runtime settings = do
    when (registerTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    kel <- registerReadKel runtime (registerKel settings)
    inception <- either fail pure (parseInceptionExport kel)
    manifest <-
        registerReadManifest runtime (registerManifest settings)
            >>= either fail pure
    plan <-
        either
            fail
            pure
            (mkRegistrationPlan manifest (registerEscrowLovelace settings) inception)
    existing <-
        registerQueryAssets
            runtime
            (registerKoiosUrl settings)
            (registerKoiosToken settings)
            (planCheckpointPolicy plan)
            (planCheckpointName plan)
    let witnesses = cdWitnesses (inceptionDatum inception)
    catalog <-
        if null witnesses
            then pure []
            else do
                boardManifest <-
                    registerReadBoardManifest
                        runtime
                        (registerBoardManifest settings)
                        >>= either fail pure
                let boardInfo = endpointBoardManifestInfo boardManifest
                registerQueryBoard
                    runtime
                    (registerKoiosUrl settings)
                    (registerKoiosToken settings)
                    (endpointBoardPolicyId boardInfo)
                    (endpointBoardAddress boardInfo)
    either
        fail
        pure
        ( registerPreflight
            (registerNetwork settings)
            (registerNetworkMagic settings)
            (registerAllowUnlistedWitnesses settings)
            (registerAllowExistingCheckpoint settings)
            (length existing)
            catalog
            inception
        )
    let missing = missingBoardWitnesses witnesses catalog
    when
        ( registerAllowUnlistedWitnesses settings
            && not (null missing)
        )
        ( registerWriteLine runtime $
            "warning: "
                <> show (length missing)
                <> "/"
                <> show (length witnesses)
                <> " declared witnesses are absent from the verified board; \
                   \accepting reduced public watchability"
        )
    when
        (registerAllowExistingCheckpoint settings && not (null existing))
        ( registerWriteLine
            runtime
            "warning: sovereign repeat registration creates another fully \
            \funded checkpoint copy; the benign residual is intentional"
        )
    registerSubmit runtime settings manifest plan

productionRegisterRuntime :: RegisterRuntime
productionRegisterRuntime =
    RegisterRuntime
        { registerReadKel = BS.readFile
        , registerReadManifest = readManifest
        , registerQueryAssets = queryAssetUtxos
        , registerReadBoardManifest = readEndpointBoardManifest
        , registerQueryBoard = queryBoardCatalog
        , registerWriteLine = putStrLn
        , registerSubmit = submitRegistration
        }

submitRegistration ::
    RegisterSettings ->
    Manifest ->
    RegistrationPlan ->
    IO ()
submitRegistration settings manifest plan =
    withLiveContext (registerLiveConfig settings) $ \context -> do
        references <- resolveManifestReferences context manifest
        lifecycleAccount <-
            either fail pure $
                rewardAccountForScript "observer-lifecycle" manifest
        lifecycleRegistered <-
            rewardAccountRegistered context lifecycleAccount
        let config =
                Registration.RegisterConfig
                    { Registration.registerRuntime =
                        liveTransactionRuntime context
                    , Registration.registerReferenceUtxos = references
                    , Registration.registerFundingAddress =
                        liveFundingAddress context
                    , Registration.registerLifecycleRewardAccount =
                        lifecycleAccount
                    , Registration.registerQueryAsset =
                        queryAssetUtxos
                            (registerKoiosUrl settings)
                            (registerKoiosToken settings)
                    , Registration.registerTimeoutSeconds =
                        registerTimeoutSeconds settings
                    , Registration.registerPollDelayMicros = 2_000_000
                    }
        premintFunding <- indexedFundingUtxos context
        premintTxId <-
            premintOne config plan premintFunding (not lifecycleRegistered)
                >>= either (fail . show) pure
        proof <-
            awaitAsset
                (Registration.registerQueryAsset config)
                (Registration.registerPollDelayMicros config)
                (Registration.registerTimeoutSeconds config)
                (planProofPolicy plan)
                (planProofName plan)
                (renderTransactionId premintTxId)
                (registerFundingAddress settings)
                >>= either (fail . show) pure
        proofInput <-
            resolveOutput
                context
                (chainAssetTxId proof)
                (chainAssetIndex proof)
        registerFunding <- indexedFundingUtxos context
        registerTxId <-
            registerOne config plan registerFunding proofInput
                >>= either (fail . show) pure
        _ <-
            awaitAsset
                (Registration.registerQueryAsset config)
                (Registration.registerPollDelayMicros config)
                (Registration.registerTimeoutSeconds config)
                (planCheckpointPolicy plan)
                (planCheckpointName plan)
                (renderTransactionId registerTxId)
                (planCheckpointAddress plan)
                >>= either (fail . show) pure
        putStrLn $
            "premint txid: "
                <> T.unpack (renderTransactionId premintTxId)
        putStrLn $
            "register txid: "
                <> T.unpack (renderTransactionId registerTxId)
        putStrLn $
            "escrow: "
                <> show (registerEscrowLovelace settings `div` 1_000_000)
                <> " tADA (min 2 + D 1000 + B 5)"

runAdvance :: AdvanceSettings -> IO ()
runAdvance settings = do
    unless
        (advanceNetwork settings == "preprod" && advanceNetworkMagic settings == 1)
        (fail "M1 V1 advance supports only preprod network magic 1")
    unless
        ( T.length (advanceConfiguredAid settings) == 44
            && "E" `T.isPrefixOf` advanceConfiguredAid settings
        )
        (fail "AID must be one 44-character KERI E-code identifier")
    when (advanceTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    let negativeCount =
            length $
                filter
                    id
                    [ advanceValidatorTestUnderSigned settings
                    , advanceValidatorTestUnderWitnessed settings
                    , advanceValidatorTestStale settings
                    ]
    when (negativeCount > 1) $
        fail "choose at most one validator-test mode"
    kel <- BS.readFile (advanceKel settings)
    rotation <- either fail pure (parseRotationExport kel)
    unless (advanceConfiguredAid settings == rotationAid rotation) $
        fail "configured AID does not match the kli rotation export"
    manifest <-
        readManifest (advanceManifest settings) >>= either fail pure
    active <-
        queryActiveCheckpoint
            (advanceKoiosUrl settings)
            (advanceKoiosToken settings)
            manifest
            (advanceConfiguredAid settings)
    package <-
        either fail pure (mkAdvancePackage manifest active rotation)
    case ( advanceSigningPackage settings
         , advanceControllerSignatures settings
         ) of
        (Just directory, Nothing) -> do
            when (negativeCount /= 0) $
                fail "validator-test modes apply only when submitting"
            files <- writeAdvanceSigningPackage directory package
            putStrLn $
                "signing package: "
                    <> advancePreimageFile files
            putStrLn $
                "preimage sha256: "
                    <> T.unpack (advancePackageSha256 package)
            putStrLn $
                "spent checkpoint: "
                    <> T.unpack (advanceSpentReference package)
        (Nothing, Just signatureFile) ->
            submitAdvance settings manifest active package signatureFile
        _ ->
            fail
                "choose exactly one of --signing-package DIR or \
                \--controller-signatures FILE"

submitAdvance ::
    AdvanceSettings ->
    Manifest ->
    ActiveCheckpoint ->
    AdvancePackage ->
    FilePath ->
    IO ()
submitAdvance settings manifest active package signatureFile = do
    payer <-
        requireAdvanceSetting "--payer" (advancePayer settings)
    nodeSocket <-
        requireAdvanceSetting "--node-socket" (advanceNodeSocket settings)
    fundingAddress <-
        requireAdvanceSetting "--funding-address" (advanceFundingAddress settings)
    signatureBytes <- BS.readFile signatureFile
    signatures <-
        either fail pure (parseIndexedSignatureLines signatureBytes)
    submittedPackage <-
        prepareSubmittedPackage settings active signatures package
    plan <- either fail pure (AdvanceTx.mkAdvancePlan manifest submittedPackage)
    withLiveContext
        ( advanceLiveConfig
            settings
            payer
            nodeSocket
            fundingAddress
        )
        $ \context -> do
            references <- resolveManifestReferences context manifest
            observerAccount <-
                either fail pure $
                    rewardAccountForScript "observer-advance" manifest
            observerRegistered <-
                rewardAccountRegistered context observerAccount
            activeInput <-
                resolveOutput
                    context
                    (activeCheckpointTxId active)
                    (activeCheckpointIndex active)
            funding <- indexedFundingUtxos context
            result <-
                AdvanceTx.runAdvanceTransaction
                    AdvanceTx.AdvanceConfig
                        { AdvanceTx.advanceRuntime =
                            liveTransactionRuntime context
                        , AdvanceTx.advanceReferenceUtxos = references
                        , AdvanceTx.advanceFundingAddress =
                            liveFundingAddress context
                        , AdvanceTx.advanceObserverRewardAccount =
                            observerAccount
                        }
                    plan
                    funding
                    activeInput
                    (not observerRegistered)
                    >>= either (fail . show) pure
            let txId = AdvanceTx.resultAdvanceTxId result
            _ <-
                AdvanceTx.awaitAdvance
                    ( queryAssetUtxos
                        (advanceKoiosUrl settings)
                        (advanceKoiosToken settings)
                    )
                    2_000_000
                    (advanceTimeoutSeconds settings)
                    (AdvanceTx.planCheckpointPolicy plan)
                    (AdvanceTx.planCheckpointAssetName plan)
                    (renderTransactionId txId)
                    (AdvanceTx.planCheckpointAddress plan)
                    >>= either (fail . show) pure
            putStrLn $
                "advance txid: "
                    <> T.unpack (renderTransactionId txId)

prepareSubmittedPackage ::
    AdvanceSettings ->
    ActiveCheckpoint ->
    [(Int, BS.ByteString)] ->
    AdvancePackage ->
    IO AdvancePackage
prepareSubmittedPackage settings active signatures package
    | advanceValidatorTestUnderSigned settings = do
        when (null signatures) $
            fail "under-signed validator test needs at least one valid signature"
        warnValidatorTest "under-signed"
        pure $
            package
                { advanceEvidence =
                    (advanceEvidence package)
                        { aeCtrlSigs = take 1 signatures
                        }
                }
    | advanceValidatorTestUnderWitnessed settings = do
        validated <-
            either fail pure (attachControllerSignatures signatures package)
        when (length (aeWitReceipts $ advanceEvidence validated) < 2) $
            fail "under-witnessed validator test needs at least two receipts"
        warnValidatorTest "under-witnessed"
        pure $
            validated
                { advanceEvidence =
                    (advanceEvidence validated)
                        { aeWitReceipts =
                            take 1 (aeWitReceipts $ advanceEvidence validated)
                        }
                }
    | advanceValidatorTestStale settings = do
        unless
            ( cdNativeSn (activeCheckpointDatum active)
                >= cdNativeSn (advanceSuccessor package)
            )
            (fail "stale validator test requires an already-applied rotation")
        warnValidatorTest "stale replay"
        pure $
            package
                { advanceEvidence =
                    (advanceEvidence package)
                        { aeCtrlSigs = signatures
                        }
                }
    | otherwise =
        either fail pure (attachControllerSignatures signatures package)

warnValidatorTest :: String -> IO ()
warnValidatorTest label =
    putStrLn $
        "warning: ACCEPTANCE-ONLY "
            <> label
            <> " package will be sent to real validator evaluation"

requireAdvanceSetting :: String -> Maybe a -> IO a
requireAdvanceSetting name =
    maybe (fail $ name <> " is required when submitting an advance") pure

runClose :: CloseSettings -> IO ()
runClose settings = do
    unless
        (closeNetwork settings == "preprod" && closeNetworkMagic settings == 1)
        (fail "M1 V1 close supports only preprod network magic 1")
    unless
        ( T.length (closeConfiguredAid settings) == 44
            && "E" `T.isPrefixOf` closeConfiguredAid settings
        )
        (fail "AID must be one 44-character KERI E-code identifier")
    when (closeTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    kel <- BS.readFile (closeKel settings)
    inception <- either fail pure (parseInceptionExport kel)
    unless (closeConfiguredAid settings == inceptionAid inception) $
        fail "configured AID does not match the kli inception export"
    manifest <-
        readManifest (closeManifest settings) >>= either fail pure
    active <-
        queryActiveCheckpoint
            (closeKoiosUrl settings)
            (closeKoiosToken settings)
            manifest
            (closeConfiguredAid settings)
    package <-
        either fail pure (mkClosePackage manifest active $ closeTo settings)
    case (closeSigningPackage settings, closeControllerSignatures settings) of
        (Just directory, Nothing) -> do
            when (closeValidatorTestNonController settings) $
                fail "validator-test mode applies only when submitting"
            files <- writeCloseSigningPackage directory package
            putStrLn $
                "signing package: "
                    <> closePreimageFile files
            putStrLn $
                "preimage sha256: "
                    <> T.unpack (closePackageSha256 package)
            putStrLn $
                "spent checkpoint: "
                    <> T.unpack (closeSpentReference package)
            putStrLn $
                "refund: "
                    <> show (closeRefundLovelace package `div` 1_000_000)
                    <> " tADA to "
                    <> T.unpack (closeRefundAddress package)
        (Nothing, Just signatureFile) ->
            submitClose settings manifest package signatureFile
        _ ->
            fail
                "choose exactly one of --signing-package DIR or \
                \--controller-signatures FILE"

submitClose ::
    CloseSettings ->
    Manifest ->
    ClosePackage ->
    FilePath ->
    IO ()
submitClose settings manifest package signatureFile = do
    payer <- requireCloseSetting "--payer" (closePayer settings)
    nodeSocket <-
        requireCloseSetting "--node-socket" (closeNodeSocket settings)
    fundingAddress <-
        requireCloseSetting
            "--funding-address"
            (closeFundingAddress settings)
    changeAddress <-
        requireCloseSetting "--change-address" (closeChangeAddress settings)
    signatureBytes <- BS.readFile signatureFile
    signatures <-
        either fail pure (parseIndexedSignatureLines signatureBytes)
    submittedPackage <-
        if closeValidatorTestNonController settings
            then do
                when (null signatures) $
                    fail
                        "non-controller validator test needs at least one signature"
                warnValidatorTest "non-controller close"
                pure
                    package
                        { closeEvidence =
                            (closeEvidence package)
                                { ceCtrlSigs = signatures
                                }
                        }
            else
                either
                    fail
                    pure
                    (attachCloseControllerSignatures signatures package)
    plan <- either fail pure (CloseTx.mkClosePlan manifest submittedPackage)
    let liveConfig =
            closeLiveConfig
                settings
                payer
                nodeSocket
                fundingAddress
    withLiveContext liveConfig $ \context -> do
        references <- resolveManifestReferences context manifest
        change <- either fail pure (decodePaymentAddress changeAddress)
        active <-
            resolveOutput
                context
                ( activeCheckpointTxId $
                    closeActiveCheckpoint submittedPackage
                )
                ( activeCheckpointIndex $
                    closeActiveCheckpoint submittedPackage
                )
        funding <- indexedFundingUtxos context
        result <-
            CloseTx.runCloseTransaction
                CloseTx.CloseConfig
                    { CloseTx.closeRuntime =
                        liveTransactionRuntime context
                    , CloseTx.closeReferenceUtxos = references
                    , CloseTx.closeFundingAddress =
                        liveFundingAddress context
                    , CloseTx.closeChangeAddress = change
                    }
                plan
                funding
                active
                >>= either (fail . show) pure
        let txId = CloseTx.closeResultTxId result
        _ <-
            CloseTx.awaitClose
                (transactionSettled liveConfig)
                2_000_000
                (closeTimeoutSeconds settings)
                txId
                >>= either (fail . show) pure
        putStrLn $
            "close txid: "
                <> T.unpack (renderTransactionId txId)
        putStrLn $
            "refunded: "
                <> show (closeRefundLovelace submittedPackage `div` 1_000_000)
                <> " tADA to "
                <> T.unpack (closeRefundAddress submittedPackage)

requireCloseSetting :: String -> Maybe a -> IO a
requireCloseSetting name =
    maybe (fail $ name <> " is required when submitting a close") pure

runDeploy :: DeploySettings -> IO ()
runDeploy settings = do
    unless
        (deployNetwork settings == "preprod" && deployNetworkMagic settings == 1)
        (fail "M1 V1 deployment supports only preprod network magic 1")
    when (deployReferenceLovelace settings <= 0) $
        fail "reference-lovelace must be positive"
    when (deployTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    artifacts <- loadArtifacts (deployBlueprint settings)
    digest <- blueprintSha256 (deployBlueprint settings)
    commit <- resolveSourceCommit settings
    verifySourceTree (deploySourceRepo settings) commit
    references <-
        withLiveContext (deployLiveConfig settings) $ \context ->
            publishArtifactsLive settings context artifacts
    publishedAt <- publicationTimestamp
    manifest <-
        either fail pure $
            mkManifest
                (deploySourceRepositoryUrl settings)
                commit
                digest
                publishedAt
                artifacts
                references
    writeManifestAtomic (deployOut settings) manifest
    putStrLn ("manifest: " <> deployOut settings)

runVerify :: VerifySettings -> IO ()
runVerify settings = do
    manifest <-
        readManifest (verifyManifest settings) >>= either fail pure
    artifacts <- loadArtifacts (verifyBlueprint settings)
    digest <- blueprintSha256 (verifyBlueprint settings)
    let errors = manifestValidationErrors digest artifacts manifest
    unless (null errors) $
        fail ("manifest rebuild failed:\n" <> unlines errors)
    verifySourceTree
        (verifySourceRepo settings)
        (sourceCommit $ manifestSource manifest)
    putStrLn $
        "source identity: OK recorded commit="
            <> T.unpack (sourceCommit $ manifestSource manifest)
    forM_ (manifestScripts manifest) $ \script ->
        putStrLn $
            "hash "
                <> T.unpack (scriptName script)
                <> ": OK "
                <> T.unpack (scriptHash script)
    chainReferences <-
        queryReferenceScripts
            (verifyKoiosUrl settings)
            (verifyKoiosToken settings)
            (map scriptHash $ manifestScripts manifest)
    forM_ (manifestScripts manifest) $ \script -> do
        unless
            ( any
                (matchesReference (scriptHash script) (scriptReference script))
                chainReferences
            )
            ( fail $
                "on-chain reference is absent or spent for "
                    <> T.unpack (scriptName script)
                    <> ": "
                    <> T.unpack
                        (referenceTxId $ scriptReference script)
                    <> "#"
                    <> show
                        (referenceIndex $ scriptReference script)
            )
        putStrLn $
            "on-chain "
                <> T.unpack (scriptName script)
                <> ": OK "
                <> T.unpack
                    (referenceTxId $ scriptReference script)
                <> "#"
                <> show
                    (referenceIndex $ scriptReference script)
    putStrLn "manifest verify: OK — blueprint rebuilt; all hashes and on-chain references are live"

loadArtifacts :: FilePath -> IO [ScriptArtifact]
loadArtifacts path = do
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (deriveV1Scripts blueprint)

verifySourceTree :: FilePath -> Text -> IO ()
verifySourceTree repository commit = do
    unless
        (T.length commit == 40 && T.all isHexDigit commit)
        (fail "source commit must be exactly 40 hexadecimal characters")
    sourcePresent <- doesDirectoryExist (repository <> "/onchain")
    unless sourcePresent $
        fail "source repository has no onchain/ directory"
