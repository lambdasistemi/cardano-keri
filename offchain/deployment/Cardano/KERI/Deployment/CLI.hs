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
    StatusSettings (..),
    registerPreflight,
    runInstructions,
) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.Deployment.ChainIndex (
    KoiosToken (..),
    matchesReference,
    queryReferenceScripts,
 )
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    parseInceptionExport,
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
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    deriveV1Scripts,
    loadBlueprint,
 )
import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import OptEnvConf qualified as Opt
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)

data Instructions
    = Deploy DeploySettings
    | ManifestVerify VerifySettings
    | Register RegisterSettings
    | Status StatusSettings
    deriving stock (Show, Eq)

data DeploySettings = DeploySettings
    { deployNetwork :: Text
    , deployNetworkMagic :: Int
    , deployBlueprint :: FilePath
    , deployNodeSocket :: FilePath
    , deployFundingAddress :: Text
    , deploySigningKeyFile :: FilePath
    , deployCardanoCli :: FilePath
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
    , registerCardanoCli :: FilePath
    , registerManifest :: FilePath
    , registerKoiosUrl :: Text
    , registerKoiosToken :: Maybe KoiosToken
    , registerTimeoutSeconds :: Int
    , registerAllowUnlistedWitnesses :: Bool
    , registerAllowExistingCheckpoint :: Bool
    , registerEscrowLovelace :: Integer
    }
    deriving stock (Show, Eq)

data StatusSettings = StatusSettings
    { statusAid :: Text
    , statusManifest :: FilePath
    , statusKoiosUrl :: Text
    , statusKoiosToken :: Maybe KoiosToken
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
                    "status"
                    "Report the live V1 checkpoint for an AID"
                    (Status <$> Opt.subConfig "status" statusSettingsParser)
                ]

deploySettingsParser :: Opt.Parser DeploySettings
deploySettingsParser = do
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
            "Cardano CLI payment signing-key file"
            Nothing
    deployCardanoCli <-
        stringSetting
            "cardano-cli"
            "CKERI_CARDANO_CLI"
            "cardano-cli"
            "cardano-cli executable"
            (Just "cardano-cli")
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
            (Just "deploy/preprod/m1-manifest.json")
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
    registerCardanoCli <-
        stringSetting
            "cardano-cli"
            "CKERI_CARDANO_CLI"
            "cardano-cli"
            "cardano-cli executable"
            (Just "cardano-cli")
    registerManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
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

statusSettingsParser :: Opt.Parser StatusSettings
statusSettingsParser = do
    statusAid <-
        T.pack
            <$> Opt.setting
                [ Opt.reader Opt.str
                , Opt.argument
                , Opt.env "CKERI_AID"
                , Opt.conf "aid"
                , Opt.metavar "AID"
                , Opt.help "44-character KERI E-code identifier"
                ]
    statusManifest <-
        stringSetting
            "manifest"
            "CKERI_MANIFEST"
            "manifest"
            "V1 preprod deployment manifest"
            (Just "deploy/preprod/m1-manifest.json")
    statusKoiosUrl <-
        textSetting
            "koios-url"
            "CKERI_KOIOS_URL"
            "koios-url"
            "Koios API base URL"
            (Just "https://preprod.koios.rest/api/v1")
    statusKoiosToken <- optionalKoiosTokenParser
    pure StatusSettings{..}

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
    Status settings -> runStatus settings

registerPreflight ::
    Text ->
    Int ->
    Bool ->
    Bool ->
    Int ->
    InceptionExport ->
    Either String ()
registerPreflight network networkMagic allowUnlisted allowExisting existingCount inception = do
    unless (network == "preprod" && networkMagic == 1) $
        Left "M1 V1 registration supports only preprod network magic 1"
    when (existingCount < 0) $
        Left "checkpoint discovery count cannot be negative"
    when (not allowExisting && existingCount == 1) $
        Left "checkpoint already registered; refusing before premint"
    when (not allowExisting && existingCount > 1) $
        Left "checkpoint discovery is ambiguous; refusing before premint"
    when
        ( not allowUnlisted
            && not (null $ cdWitnesses $ inceptionDatum inception)
        )
        ( Left
            "declared witnesses have no board record check yet; pass \
            \--allow-unlisted-witnesses to acknowledge reduced watchability"
        )

runRegister :: RegisterSettings -> IO ()
runRegister settings = do
    when (registerTimeoutSeconds settings <= 0) $
        fail "timeout-seconds must be positive"
    kel <- BS.readFile (registerKel settings)
    inception <- either fail pure (parseInceptionExport kel)
    either
        fail
        pure
        ( registerPreflight
            (registerNetwork settings)
            (registerNetworkMagic settings)
            (registerAllowUnlistedWitnesses settings)
            (registerAllowExistingCheckpoint settings)
            0
            inception
        )
    fail "registration transaction runner is not implemented"

runStatus :: StatusSettings -> IO ()
runStatus settings = do
    unless
        (T.length (statusAid settings) == 44 && "E" `T.isPrefixOf` statusAid settings)
        (fail "AID must be one 44-character KERI E-code identifier")
    fail "checkpoint status lookup is not implemented"

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
    commit <-
        maybe
            (gitOutput (deploySourceRepo settings) ["rev-parse", "HEAD"])
            pure
            (deploySourceCommit settings)
    verifySourceTree (deploySourceRepo settings) commit
    references <-
        publishScripts
            PublishConfig
                { publishCardanoCli = deployCardanoCli settings
                , publishNetworkMagic = deployNetworkMagic settings
                , publishNodeSocket = deployNodeSocket settings
                , publishFundingAddress = deployFundingAddress settings
                , publishSigningKeyFile = deploySigningKeyFile settings
                , publishReferenceLovelace =
                    deployReferenceLovelace settings
                , publishKoiosUrl = deployKoiosUrl settings
                , publishKoiosToken = deployKoiosToken settings
                , publishTimeoutSeconds = deployTimeoutSeconds settings
                }
            artifacts
    now <- getCurrentTime
    let publishedAt =
            T.pack $
                formatTime
                    defaultTimeLocale
                    "%Y-%m-%dT%H:%M:%SZ"
                    now
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
        "source rebuild: OK commit="
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
    putStrLn "manifest verify: OK — rebuilt from source; all hashes and on-chain references are live"

loadArtifacts :: FilePath -> IO [ScriptArtifact]
loadArtifacts path = do
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (deriveV1Scripts blueprint)

verifySourceTree :: FilePath -> Text -> IO ()
verifySourceTree repository commit = do
    _ <-
        gitOutput
            repository
            ["cat-file", "-e", T.unpack commit <> "^{commit}"]
    (exitCode, _, err) <-
        readProcessWithExitCode
            "git"
            [ "-C"
            , repository
            , "diff"
            , "--quiet"
            , T.unpack commit
            , "--"
            , "onchain"
            ]
            ""
    case exitCode of
        ExitSuccess -> pure ()
        ExitFailure 1 ->
            fail $
                "tracked onchain/ source differs from manifest commit "
                    <> T.unpack commit
        ExitFailure code ->
            fail $
                "git source comparison failed with exit "
                    <> show code
                    <> ": "
                    <> err

gitOutput :: FilePath -> [String] -> IO Text
gitOutput repository arguments = do
    (exitCode, output, err) <-
        readProcessWithExitCode
            "git"
            ("-C" : repository : arguments)
            ""
    case exitCode of
        ExitSuccess -> pure (T.strip $ T.pack output)
        ExitFailure code ->
            fail $
                "git failed with exit "
                    <> show code
                    <> ": "
                    <> err
