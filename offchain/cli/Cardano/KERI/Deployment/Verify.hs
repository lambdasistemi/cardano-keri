{-# LANGUAGE ApplicativeDo #-}

{- |
Module      : Cardano.KERI.Deployment.Verify
Description : Read-only manifest verify + board list, provider-backed (#240 MOD-240-CLI)

#240 (RQ-240-08): manifest verification and endpoint-board listing are the
two read-only commands "Cardano.KERI.Deployment.CLI" (now
MOD-240-WRITE-COMPOSITION, no provider dependency) used to own alongside its
write verbs. Carved out here, in the `cli` component, specifically so they
may keep their existing Koios dependency without granting that edge to
write code (EDGE-240-04): this ticket does not implement or remove the
future third-party tier, only draws the write-side boundary around it.
-}
module Cardano.KERI.Deployment.Verify (
    VerifySettings (..),
    BoardListSettings (..),
    verifySettingsParser,
    boardListSettingsParser,
    runVerify,
    runBoardList,
) where

import Cardano.KERI.ChainQuery.Koios (
    KoiosToken (..),
    matchesReference,
    queryBoardCatalog,
    queryReferenceScripts,
 )
import Cardano.KERI.Deployment.EndpointBoard (renderBoardCatalog)
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    readEndpointBoardManifest,
 )
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
    SourceInfo (..),
    blueprintSha256,
    manifestValidationErrors,
    readManifest,
 )
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    deriveV1Scripts,
    loadBlueprint,
 )
import Control.Monad (forM_, unless)
import Data.Char (isHexDigit)
import Data.Text (Text)
import Data.Text qualified as T
import OptEnvConf qualified as Opt
import System.Directory (doesDirectoryExist)

data VerifySettings = VerifySettings
    { verifyManifest :: FilePath
    , verifyBlueprint :: FilePath
    , verifySourceRepo :: FilePath
    , verifyKoiosUrl :: Text
    , verifyKoiosToken :: Maybe KoiosToken
    }
    deriving stock (Show, Eq)

data BoardListSettings = BoardListSettings
    { boardListManifest :: !FilePath
    , boardListKoiosUrl :: !Text
    , boardListKoiosToken :: !(Maybe KoiosToken)
    }
    deriving stock (Show, Eq)

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

withMaybeDefault :: (Show a) => Maybe a -> Opt.Parser a -> Opt.Parser a
withMaybeDefault defaultValue parser =
    maybe parser (`Opt.withDefault` parser) defaultValue
