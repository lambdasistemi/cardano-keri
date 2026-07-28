{- |
Module      : Cardano.KERI.Deployment.Manifest
Description : Stable M1 V1 release-manifest schema and source rebuild checks
-}
module Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    NetworkInfo (..),
    SourceInfo (..),
    BlueprintInfo (..),
    DeploymentParameters (..),
    CheckpointInfo (..),
    ScriptEntry (..),
    Reference (..),
    manifestSchema,
    blueprintSha256,
    mkManifest,
    manifestValidationErrors,
    readManifest,
    writeManifestAtomic,
) where

import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    checkpointAddress,
    scriptHashText,
    v1CheckpointVersion,
    v1FreezeBond,
    v1FreezeWindow,
    v1NetworkDiscriminator,
    v1RegistrationBond,
 )
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (
    FromJSON (..),
    ToJSON (..),
    eitherDecodeFileStrict',
    object,
    withObject,
    (.:),
    (.=),
 )
import Data.Aeson qualified as Aeson
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.List (find, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (createDirectoryIfMissing, renameFile)
import System.FilePath (takeDirectory)
import System.IO (hClose, openBinaryTempFile)

data Manifest = Manifest
    { manifestSchemaVersion :: Text
    , manifestNetwork :: NetworkInfo
    , manifestSource :: SourceInfo
    , manifestBlueprint :: BlueprintInfo
    , manifestParameters :: DeploymentParameters
    , manifestCheckpoint :: CheckpointInfo
    , manifestPublishedAt :: Text
    , manifestScripts :: [ScriptEntry]
    }
    deriving stock (Show, Eq)

data NetworkInfo = NetworkInfo
    { networkName :: Text
    , networkMagic :: Int
    }
    deriving stock (Show, Eq)

data SourceInfo = SourceInfo
    { sourceRepository :: Text
    , sourceCommit :: Text
    }
    deriving stock (Show, Eq)

newtype BlueprintInfo = BlueprintInfo
    { blueprintDigestSha256 :: Text
    }
    deriving stock (Show, Eq)

data DeploymentParameters = DeploymentParameters
    { parameterCheckpointVersion :: Integer
    , parameterNetworkDiscriminator :: Integer
    , parameterRegistrationBond :: Integer
    , parameterFreezeBond :: Integer
    , parameterFreezeWindow :: Integer
    }
    deriving stock (Show, Eq)

data CheckpointInfo = CheckpointInfo
    { checkpointAddressBech32 :: Text
    , checkpointPolicyId :: Text
    }
    deriving stock (Show, Eq)

data ScriptEntry = ScriptEntry
    { scriptName :: Text
    , scriptBlueprintTitle :: Text
    , scriptRole :: Text
    , scriptHash :: Text
    , scriptProgramBytes :: Int
    , scriptReference :: Reference
    }
    deriving stock (Show, Eq)

data Reference = Reference
    { referenceTxId :: Text
    , referenceIndex :: Int
    }
    deriving stock (Show, Eq)

instance ToJSON Manifest where
    toJSON manifest =
        object
            [ "schema" .= manifestSchemaVersion manifest
            , "network" .= manifestNetwork manifest
            , "source" .= manifestSource manifest
            , "blueprint" .= manifestBlueprint manifest
            , "parameters" .= manifestParameters manifest
            , "checkpoint" .= manifestCheckpoint manifest
            , "publishedAt" .= manifestPublishedAt manifest
            , "scripts" .= manifestScripts manifest
            ]

instance FromJSON Manifest where
    parseJSON = withObject "Manifest" $ \o ->
        Manifest
            <$> o .: "schema"
            <*> o .: "network"
            <*> o .: "source"
            <*> o .: "blueprint"
            <*> o .: "parameters"
            <*> o .: "checkpoint"
            <*> o .: "publishedAt"
            <*> o .: "scripts"

instance ToJSON NetworkInfo where
    toJSON network =
        object
            [ "name" .= networkName network
            , "magic" .= networkMagic network
            ]

instance FromJSON NetworkInfo where
    parseJSON = withObject "NetworkInfo" $ \o ->
        NetworkInfo <$> o .: "name" <*> o .: "magic"

instance ToJSON SourceInfo where
    toJSON source =
        object
            [ "repository" .= sourceRepository source
            , "commit" .= sourceCommit source
            ]

instance FromJSON SourceInfo where
    parseJSON = withObject "SourceInfo" $ \o ->
        SourceInfo <$> o .: "repository" <*> o .: "commit"

instance ToJSON BlueprintInfo where
    toJSON blueprint =
        object ["sha256" .= blueprintDigestSha256 blueprint]

instance FromJSON BlueprintInfo where
    parseJSON = withObject "BlueprintInfo" $ \o ->
        BlueprintInfo <$> o .: "sha256"

instance ToJSON DeploymentParameters where
    toJSON parameters =
        object
            [ "checkpointVersion" .= parameterCheckpointVersion parameters
            , "networkDiscriminator" .= parameterNetworkDiscriminator parameters
            , "registrationBondLovelace" .= parameterRegistrationBond parameters
            , "freezeBondLovelace" .= parameterFreezeBond parameters
            , "freezeWindowSlots" .= parameterFreezeWindow parameters
            ]

instance FromJSON DeploymentParameters where
    parseJSON = withObject "DeploymentParameters" $ \o ->
        DeploymentParameters
            <$> o .: "checkpointVersion"
            <*> o .: "networkDiscriminator"
            <*> o .: "registrationBondLovelace"
            <*> o .: "freezeBondLovelace"
            <*> o .: "freezeWindowSlots"

instance ToJSON CheckpointInfo where
    toJSON checkpoint =
        object
            [ "address" .= checkpointAddressBech32 checkpoint
            , "policyId" .= checkpointPolicyId checkpoint
            ]

instance FromJSON CheckpointInfo where
    parseJSON = withObject "CheckpointInfo" $ \o ->
        CheckpointInfo <$> o .: "address" <*> o .: "policyId"

instance ToJSON ScriptEntry where
    toJSON script =
        object
            [ "name" .= scriptName script
            , "blueprintTitle" .= scriptBlueprintTitle script
            , "role" .= scriptRole script
            , "hash" .= scriptHash script
            , "programBytes" .= scriptProgramBytes script
            , "reference" .= scriptReference script
            ]

instance FromJSON ScriptEntry where
    parseJSON = withObject "ScriptEntry" $ \o ->
        ScriptEntry
            <$> o .: "name"
            <*> o .: "blueprintTitle"
            <*> o .: "role"
            <*> o .: "hash"
            <*> o .: "programBytes"
            <*> o .: "reference"

instance ToJSON Reference where
    toJSON reference =
        object
            [ "txId" .= referenceTxId reference
            , "index" .= referenceIndex reference
            ]

instance FromJSON Reference where
    parseJSON = withObject "Reference" $ \o ->
        Reference <$> o .: "txId" <*> o .: "index"

manifestSchema :: Text
manifestSchema = "cardano-keri/m1-deployment-manifest/v1"

v1Parameters :: DeploymentParameters
v1Parameters =
    DeploymentParameters
        { parameterCheckpointVersion = v1CheckpointVersion
        , parameterNetworkDiscriminator = v1NetworkDiscriminator
        , parameterRegistrationBond = v1RegistrationBond
        , parameterFreezeBond = v1FreezeBond
        , parameterFreezeWindow = v1FreezeWindow
        }

blueprintSha256 :: FilePath -> IO Text
blueprintSha256 path = do
    bytes <- BS.readFile path
    let digest = hash bytes :: Digest SHA256
    pure $ TE.decodeUtf8 (convertToBase Base16 digest)

mkManifest ::
    Text ->
    Text ->
    Text ->
    Text ->
    [ScriptArtifact] ->
    [(Text, Reference)] ->
    Either String Manifest
mkManifest repository commit blueprintDigest publishedAt artifacts references = do
    address <- checkpointAddress artifacts
    checkpoint <-
        maybe
            (Left "checkpoint-register artifact is absent")
            Right
            (find ((== "checkpoint-register") . artifactName) artifacts)
    entries <- traverse toEntry artifacts
    pure
        Manifest
            { manifestSchemaVersion = manifestSchema
            , manifestNetwork = NetworkInfo "preprod" 1
            , manifestSource = SourceInfo repository commit
            , manifestBlueprint = BlueprintInfo blueprintDigest
            , manifestParameters = v1Parameters
            , manifestCheckpoint =
                CheckpointInfo
                    { checkpointAddressBech32 = address
                    , checkpointPolicyId =
                        scriptHashText (artifactScriptHash checkpoint)
                    }
            , manifestPublishedAt = publishedAt
            , manifestScripts = entries
            }
  where
    referenceMap = Map.fromList references
    toEntry artifact = do
        reference <-
            maybe
                (Left $ "reference is absent for " <> T.unpack (artifactName artifact))
                Right
                (Map.lookup (artifactName artifact) referenceMap)
        pure
            ScriptEntry
                { scriptName = artifactName artifact
                , scriptBlueprintTitle = artifactBlueprintTitle artifact
                , scriptRole = artifactRole artifact
                , scriptHash = scriptHashText (artifactScriptHash artifact)
                , scriptProgramBytes = SBS.length (artifactProgram artifact)
                , scriptReference = reference
                }

manifestValidationErrors ::
    Text ->
    [ScriptArtifact] ->
    Manifest ->
    [String]
manifestValidationErrors blueprintDigest artifacts manifest =
    concat
        [ mismatch
            "schema"
            manifestSchema
            (manifestSchemaVersion manifest)
        , mismatch
            "network"
            (NetworkInfo "preprod" 1)
            (manifestNetwork manifest)
        , mismatch
            "blueprint sha256"
            (BlueprintInfo blueprintDigest)
            (manifestBlueprint manifest)
        , mismatch
            "deployment parameters"
            v1Parameters
            (manifestParameters manifest)
        , sourceErrors
        , checkpointErrors
        , scriptErrors
        , referenceErrors
        ]
  where
    mismatch :: (Eq a, Show a) => String -> a -> a -> [String]
    mismatch label expected actual
        | expected == actual = []
        | otherwise =
            [ label
                <> " mismatch: expected "
                <> show expected
                <> ", got "
                <> show actual
            ]
    source = manifestSource manifest
    sourceErrors =
        [ "source repository is empty"
        | T.null (sourceRepository source)
        ]
            <> [ "source commit is not a 40-character hex commit"
               | not (isCommit (sourceCommit source))
               ]
    isCommit text =
        T.length text == 40
            && T.all
                (\character -> character `elem` ("0123456789abcdef" :: String))
                text
    expectedCheckpoint = do
        address <- checkpointAddress artifacts
        checkpoint <-
            maybe
                (Left "checkpoint-register artifact is absent")
                Right
                (find ((== "checkpoint-register") . artifactName) artifacts)
        pure
            CheckpointInfo
                { checkpointAddressBech32 = address
                , checkpointPolicyId =
                    scriptHashText (artifactScriptHash checkpoint)
                }
    checkpointErrors =
        case expectedCheckpoint of
            Left err -> [err]
            Right expected ->
                mismatch "checkpoint" expected (manifestCheckpoint manifest)
    expectedScripts =
        [ ( artifactName artifact
          , artifactBlueprintTitle artifact
          , artifactRole artifact
          , scriptHashText (artifactScriptHash artifact)
          , SBS.length (artifactProgram artifact)
          )
        | artifact <- artifacts
        ]
    actualScripts =
        [ ( scriptName script
          , scriptBlueprintTitle script
          , scriptRole script
          , scriptHash script
          , scriptProgramBytes script
          )
        | script <- manifestScripts manifest
        ]
    scriptErrors =
        mismatch
            "script names"
            (sort $ map (\(name, _, _, _, _) -> name) expectedScripts)
            (sort $ map (\(name, _, _, _, _) -> name) actualScripts)
            <> concatMap checkScript expectedScripts
    checkScript expected@(name, _, _, _, _) =
        case filter (\(actualName, _, _, _, _) -> actualName == name) actualScripts of
            [actual] -> mismatch ("script " <> T.unpack name) expected actual
            [] -> ["script is absent: " <> T.unpack name]
            _ -> ["script is duplicated: " <> T.unpack name]
    references = map scriptReference (manifestScripts manifest)
    referenceErrors =
        concatMap checkReference references
            <> [ "script references are not unique"
               | length references /= length (nub references)
               ]
    checkReference reference =
        [ "reference transaction id is not 64-character lowercase hex: "
            <> T.unpack (referenceTxId reference)
        | not (isLowerHex64 $ referenceTxId reference)
        ]
            <> [ "reference output index is negative: "
                    <> show (referenceIndex reference)
               | referenceIndex reference < 0
               ]
    isLowerHex64 text =
        T.length text == 64
            && T.all
                (\character -> character `elem` ("0123456789abcdef" :: String))
                text

readManifest :: FilePath -> IO (Either String Manifest)
readManifest = eitherDecodeFileStrict'

writeManifestAtomic :: FilePath -> Manifest -> IO ()
writeManifestAtomic output manifest = do
    let directory =
            case takeDirectory output of
                "" -> "."
                path -> path
    createDirectoryIfMissing True directory
    (temporary, handle) <-
        openBinaryTempFile directory ".ckeri-manifest.json.tmp"
    BSL.hPut handle (Aeson.encode manifest <> "\n")
    hClose handle
    renameFile temporary output
