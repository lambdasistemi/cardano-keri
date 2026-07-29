{- |
Module      : Cardano.KERI.Deployment.EndpointBoardManifest
Description : Reproducible locator for the frozen preprod endpoint board
-}
module Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardManifest (..),
    EndpointBoardInfo (..),
    endpointBoardManifestSchema,
    frozenEndpointBoardPolicyId,
    frozenEndpointBoardAddress,
    mkEndpointBoardManifest,
    endpointBoardManifestValidationErrors,
    readEndpointBoardManifest,
    writeEndpointBoardManifestAtomic,
) where

import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    NetworkInfo (..),
    Reference (..),
    SourceInfo (..),
 )
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    boardAddress,
    scriptHashText,
 )
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
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Char (isHexDigit)
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory (createDirectoryIfMissing, renameFile)
import System.FilePath (takeDirectory)
import System.IO (hClose, openBinaryTempFile)

data EndpointBoardManifest = EndpointBoardManifest
    { endpointBoardManifestSchemaVersion :: !Text
    , endpointBoardManifestNetwork :: !NetworkInfo
    , endpointBoardManifestSource :: !SourceInfo
    , endpointBoardManifestBlueprint :: !BlueprintInfo
    , endpointBoardManifestInfo :: !EndpointBoardInfo
    , endpointBoardManifestPublishedAt :: !Text
    }
    deriving stock (Show, Eq)

data EndpointBoardInfo = EndpointBoardInfo
    { endpointBoardPolicyId :: !Text
    , endpointBoardAddress :: !Text
    , endpointBoardProgramBytes :: !Int
    , endpointBoardReference :: !Reference
    }
    deriving stock (Show, Eq)

instance ToJSON EndpointBoardManifest where
    toJSON manifest =
        object
            [ "schema" .= endpointBoardManifestSchemaVersion manifest
            , "network" .= endpointBoardManifestNetwork manifest
            , "source" .= endpointBoardManifestSource manifest
            , "blueprint" .= endpointBoardManifestBlueprint manifest
            , "board" .= endpointBoardManifestInfo manifest
            , "publishedAt" .= endpointBoardManifestPublishedAt manifest
            ]

instance FromJSON EndpointBoardManifest where
    parseJSON = withObject "EndpointBoardManifest" $ \objectValue ->
        EndpointBoardManifest
            <$> objectValue .: "schema"
            <*> objectValue .: "network"
            <*> objectValue .: "source"
            <*> objectValue .: "blueprint"
            <*> objectValue .: "board"
            <*> objectValue .: "publishedAt"

instance ToJSON EndpointBoardInfo where
    toJSON info =
        object
            [ "policyId" .= endpointBoardPolicyId info
            , "address" .= endpointBoardAddress info
            , "programBytes" .= endpointBoardProgramBytes info
            , "reference" .= endpointBoardReference info
            ]

instance FromJSON EndpointBoardInfo where
    parseJSON = withObject "EndpointBoardInfo" $ \objectValue ->
        EndpointBoardInfo
            <$> objectValue .: "policyId"
            <*> objectValue .: "address"
            <*> objectValue .: "programBytes"
            <*> objectValue .: "reference"

endpointBoardManifestSchema :: Text
endpointBoardManifestSchema =
    "cardano-keri/m1-endpoint-board-manifest/v1"

frozenEndpointBoardPolicyId :: Text
frozenEndpointBoardPolicyId =
    "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

frozenEndpointBoardAddress :: Text
frozenEndpointBoardAddress =
    "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"

mkEndpointBoardManifest ::
    Text ->
    Text ->
    Text ->
    Text ->
    ScriptArtifact ->
    Reference ->
    Either String EndpointBoardManifest
mkEndpointBoardManifest repository commit blueprintDigest publishedAt artifact reference = do
    address <- boardAddress artifact
    let manifest =
            EndpointBoardManifest
                { endpointBoardManifestSchemaVersion =
                    endpointBoardManifestSchema
                , endpointBoardManifestNetwork = NetworkInfo "preprod" 1
                , endpointBoardManifestSource =
                    SourceInfo repository commit
                , endpointBoardManifestBlueprint =
                    BlueprintInfo blueprintDigest
                , endpointBoardManifestInfo =
                    EndpointBoardInfo
                        { endpointBoardPolicyId =
                            scriptHashText (artifactScriptHash artifact)
                        , endpointBoardAddress = address
                        , endpointBoardProgramBytes =
                            SBS.length (artifactProgram artifact)
                        , endpointBoardReference = reference
                        }
                , endpointBoardManifestPublishedAt = publishedAt
                }
        errors =
            endpointBoardManifestValidationErrors
                blueprintDigest
                artifact
                manifest
    if null errors
        then pure manifest
        else Left (unlines errors)

endpointBoardManifestValidationErrors ::
    Text ->
    ScriptArtifact ->
    EndpointBoardManifest ->
    [String]
endpointBoardManifestValidationErrors blueprintDigest artifact manifest =
    consumerErrors manifest
        <> mismatch
            "blueprint sha256"
            blueprintDigest
            (blueprintDigestSha256 $ endpointBoardManifestBlueprint manifest)
        <> mismatch
            "board policy id"
            (scriptHashText $ artifactScriptHash artifact)
            (endpointBoardPolicyId info)
        <> case boardAddress artifact of
            Left err -> ["derived board address failed: " <> err]
            Right address ->
                mismatch
                    "board address"
                    address
                    (endpointBoardAddress info)
        <> mismatch
            "board program bytes"
            (SBS.length $ artifactProgram artifact)
            (endpointBoardProgramBytes info)
  where
    info = endpointBoardManifestInfo manifest

readEndpointBoardManifest ::
    FilePath ->
    IO (Either String EndpointBoardManifest)
readEndpointBoardManifest path =
    eitherDecodeFileStrict' path >>= \case
        Left err -> pure (Left err)
        Right manifest ->
            case consumerErrors manifest of
                [] -> pure (Right manifest)
                errors -> pure (Left $ unlines errors)

writeEndpointBoardManifestAtomic ::
    FilePath ->
    EndpointBoardManifest ->
    IO ()
writeEndpointBoardManifestAtomic path manifest = do
    let directory = takeDirectory path
    createDirectoryIfMissing True directory
    (temporary, handle) <-
        openBinaryTempFile directory "endpoint-board-manifest.json.tmp"
    BSL.hPut handle (Aeson.encode manifest)
    hClose handle
    renameFile temporary path

consumerErrors :: EndpointBoardManifest -> [String]
consumerErrors manifest =
    mismatch
        "schema"
        endpointBoardManifestSchema
        (endpointBoardManifestSchemaVersion manifest)
        <> mismatch
            "network"
            (NetworkInfo "preprod" 1)
            (endpointBoardManifestNetwork manifest)
        <> mismatch
            "frozen board policy id"
            frozenEndpointBoardPolicyId
            (endpointBoardPolicyId info)
        <> mismatch
            "frozen board address"
            frozenEndpointBoardAddress
            (endpointBoardAddress info)
        <> [ "source repository is empty"
           | T.null $
                sourceRepository $
                    endpointBoardManifestSource manifest
           ]
        <> [ "source commit is not a 40-character hex commit"
           | not $
                isHexLength 40 $
                    sourceCommit $
                        endpointBoardManifestSource manifest
           ]
        <> [ "blueprint sha256 is not 64-character hex"
           | not $
                isHexLength 64 $
                    blueprintDigestSha256 $
                        endpointBoardManifestBlueprint manifest
           ]
        <> [ "board program bytes must be positive"
           | endpointBoardProgramBytes info <= 0
           ]
        <> referenceErrors (endpointBoardReference info)
        <> [ "publishedAt is empty"
           | T.null (endpointBoardManifestPublishedAt manifest)
           ]
  where
    info = endpointBoardManifestInfo manifest

referenceErrors :: Reference -> [String]
referenceErrors reference =
    [ "board reference transaction id is not 64-character hex"
    | not (isHexLength 64 $ referenceTxId reference)
    ]
        <> [ "board reference output index is negative"
           | referenceIndex reference < 0
           ]

isHexLength :: Int -> Text -> Bool
isHexLength expected text =
    T.length text == expected
        && T.all isHexDigit text

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
