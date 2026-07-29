{- |
Module      : Cardano.KERI.Deployment.Advance
Description : Build and authenticate the V1 Advance signing package

The package boundary is deliberately split from transaction submission. The
binary canonical-CBOR preimage is reconstructed only from the live checkpoint,
the immutable deployment, and the genuine KLI rotation export. Native KERI
event signatures are never treated as Cardano Advance signatures.
-}
module Cardano.KERI.Deployment.Advance (
    AdvancePackage (..),
    AdvanceSigningFiles (..),
    mkAdvancePackage,
    attachControllerSignatures,
    advanceSigningMetadata,
    writeAdvanceSigningPackage,
) where

import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
    advancePredicate,
    reconstructAdvanceMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    SpentCheckpoint (..),
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
 )
import Cardano.KERI.Deployment.KEL (
    RotationExport (..),
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    ScriptEntry (..),
 )
import Control.Monad (unless)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson (
    Value,
    object,
    (.=),
 )
import Data.Aeson qualified as Aeson
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

data AdvancePackage = AdvancePackage
    { advanceAid :: !Text
    , advanceSpentReference :: !Text
    , advanceSpent :: !SpentCheckpoint
    , advanceSuccessor :: !CheckpointDatumV1
    , advanceEvidence :: !AdvanceEvidence
    , advanceSigningPreimage :: !ByteString
    , advancePackageSha256 :: !Text
    }
    deriving stock (Show, Eq)

data AdvanceSigningFiles = AdvanceSigningFiles
    { advancePreimageFile :: !FilePath
    , advanceMetadataFile :: !FilePath
    }
    deriving stock (Show, Eq)

mkAdvancePackage ::
    Manifest ->
    ActiveCheckpoint ->
    RotationExport ->
    Either String AdvancePackage
mkAdvancePackage manifest active rotation = do
    unless
        ( networkName (manifestNetwork manifest) == "preprod"
            && networkMagic (manifestNetwork manifest) == 1
        )
        (Left "advance manifest is not preprod network magic 1")
    unless
        (parameterNetworkDiscriminator (manifestParameters manifest) == 0)
        (Left "advance manifest network discriminator is not the frozen V1 value")
    unless
        (activeCheckpointAid active == rotationAid rotation)
        (Left "rotation AID does not match the live checkpoint")
    checkpoint <- scriptNamed "checkpoint-register" manifest
    _ <- scriptNamed "observer-advance" manifest
    let policyText = checkpointPolicyId (manifestCheckpoint manifest)
    unless (scriptHash checkpoint == policyText) $
        Left "manifest checkpoint policy does not match its script entry"
    policy <- decodeHexSized "checkpoint policy" 28 policyText
    assetName <-
        decodeHexSized
            "checkpoint asset name"
            32
            (activeCheckpointAssetName active)
    txId <-
        decodeHexSized
            "checkpoint transaction id"
            32
            (activeCheckpointTxId active)
    let old = activeCheckpointDatum active
        successor = rotationDatum rotation
        evidence = rotationEvidence rotation
        spent =
            SpentCheckpoint
                { scNetworkId =
                    parameterNetworkDiscriminator (manifestParameters manifest)
                , scPolicyId = policy
                , scAidAssetName = assetName
                , scTxid = txId
                , scIndex = fromIntegral $ activeCheckpointIndex active
                , scCesrAid = cdCesrAid old
                , scWitnesses = cdWitnesses old
                , scNextKeys = cdNextKeys old
                , scNextThreshold = cdNextThreshold old
                , scSeq = cdSeq old
                , scNativeSn = cdNativeSn old
                }
        preimage =
            canonicalCbor $
                reconstructAdvanceMessage
                    spent
                    successor
                    (aeWitCut evidence)
                    (aeWitAdd evidence)
    pure
        AdvancePackage
            { advanceAid = rotationAid rotation
            , advanceSpentReference =
                activeCheckpointTxId active
                    <> "#"
                    <> T.pack (show $ activeCheckpointIndex active)
            , advanceSpent = spent
            , advanceSuccessor = successor
            , advanceEvidence = evidence
            , advanceSigningPreimage = preimage
            , advancePackageSha256 = sha256Text preimage
            }

attachControllerSignatures ::
    [(Int, ByteString)] ->
    AdvancePackage ->
    Either String AdvancePackage
attachControllerSignatures signatures package = do
    let evidence =
            (advanceEvidence package)
                { aeCtrlSigs = signatures
                }
        updated =
            package
                { advanceEvidence = evidence
                }
    either
        (Left . ("Advance controller package rejected: " <>) . show)
        Right
        ( advancePredicate
            (advanceSpent updated)
            (advanceSuccessor updated)
            evidence
        )
    pure updated

advanceSigningMetadata :: AdvancePackage -> Value
advanceSigningMetadata package =
    object
        [ "schema" .= ("cardano-keri/advance-signing-package/v1" :: Text)
        , "aid" .= advanceAid package
        , "spentReference" .= advanceSpentReference package
        , "preimageFile" .= ("advance-message.cbor" :: Text)
        , "preimageSha256" .= advancePackageSha256 package
        ]

writeAdvanceSigningPackage ::
    FilePath ->
    AdvancePackage ->
    IO AdvanceSigningFiles
writeAdvanceSigningPackage directory package = do
    createDirectoryIfMissing True directory
    let advancePreimageFile = directory </> "advance-message.cbor"
        advanceMetadataFile = directory </> "package.json"
    BS.writeFile advancePreimageFile (advanceSigningPreimage package)
    Aeson.encodeFile advanceMetadataFile (advanceSigningMetadata package)
    pure AdvanceSigningFiles{..}

scriptNamed :: Text -> Manifest -> Either String ScriptEntry
scriptNamed name manifest =
    case filter ((== name) . scriptName) (manifestScripts manifest) of
        [script] -> Right script
        _ -> Left ("manifest script is not unique: " <> T.unpack name)

decodeHexSized :: String -> Int -> Text -> Either String ByteString
decodeHexSized label expected encoded = do
    bytes <-
        either
            (const $ Left $ label <> " is not hexadecimal")
            Right
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == expected) $
        Left (label <> " has the wrong byte length")
    pure bytes

sha256Text :: ByteString -> Text
sha256Text bytes =
    let digest = hash bytes :: Digest SHA256
     in TE.decodeUtf8 (convertToBase Base16 digest)
