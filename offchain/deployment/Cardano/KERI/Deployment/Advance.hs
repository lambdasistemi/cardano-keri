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
    PackageBase (..),
    packageBase,
    mkAdvancePackage,
    attachControllerSignatures,
    advanceSigningMetadata,
    writeAdvanceSigningPackage,
    sha256Text,
) where

import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
    advancePredicate,
    reconstructAdvanceMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2,
    KeyStateView (..),
    canonicalCbor,
    rotatedLive,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    SpentCheckpoint (..),
 )
import Cardano.KERI.AID.Checkpoint.Value (
    RotationSettlement (..),
    checkpointMinAda,
    heldValue,
    rotationSettlement,
 )
import Cardano.KERI.ChainQuery (
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
    , advanceActiveCheckpoint :: !ActiveCheckpoint
    , advanceSpentReference :: !Text
    , advanceSpent :: !SpentCheckpoint
    , advanceSuccessor :: !KeyStateView
    , advanceSuccessorFacts :: !CheckpointDatumV2
    -- ^ the version 2 datum the successor output carries
    , advanceSettlement :: !RotationSettlement
    -- ^ the premium paid out of the pool and the pool left
    , advanceSuccessorLovelace :: !Integer
    -- ^ the lovelace the successor output holds, exactly
    , advanceEvidence :: !AdvanceEvidence
    , advanceSigningPreimage :: !ByteString
    -- ^ what the controller signs; empty for a freeze, which asks nobody's signature
    , advancePackageSha256 :: !Text
    }
    deriving stock (Show, Eq)

data AdvanceSigningFiles = AdvanceSigningFiles
    { advancePreimageFile :: !FilePath
    , advanceMetadataFile :: !FilePath
    }
    deriving stock (Show, Eq)

{- | What every rotation package starts from, once the manifest, the live
checkpoint and the rotation export agree: the deployment parameters, the
premium and the spent checkpoint the evidence is checked against.
-}
data PackageBase = PackageBase
    { pbParameters :: !DeploymentParameters
    , pbPremium :: !Integer
    , pbSpent :: !SpentCheckpoint
    }

packageBase ::
    Manifest ->
    ActiveCheckpoint ->
    RotationExport ->
    Either String PackageBase
packageBase manifest active rotation = do
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
    let pbParameters = manifestParameters manifest
        old = activeCheckpointDatum active
    pbPremium <-
        maybe
            (Left "the manifest has no premiumLovelace: its generation has no premium and cannot be advanced")
            Right
            (parameterPremium pbParameters)
    let pbSpent =
            SpentCheckpoint
                { scNetworkId = parameterNetworkDiscriminator pbParameters
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
    pure PackageBase{..}

mkAdvancePackage ::
    Manifest ->
    ActiveCheckpoint ->
    RotationExport ->
    Either String AdvancePackage
mkAdvancePackage manifest active rotation = do
    PackageBase{pbParameters = parameters, pbPremium = premium, pbSpent = spent} <-
        packageBase manifest active rotation
    let facts = activeCheckpointFacts active
    settlement <-
        maybe
            (Left "the checkpoint is not a live output holding its deposit and bond")
            Right
            ( rotationSettlement
                checkpointMinAda
                (parameterRegistrationBond parameters)
                (parameterFreezeBond parameters)
                premium
                facts
                (activeCheckpointLovelace active)
            )
    successorFacts <-
        maybe
            (Left "the checkpoint is not live")
            Right
            (rotatedLive facts (rotationDatum rotation))
    let successor = rotationDatum rotation
        evidence = rotationEvidence rotation
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
            , advanceActiveCheckpoint = active
            , advanceSpentReference =
                activeCheckpointTxId active
                    <> "#"
                    <> T.pack (show $ activeCheckpointIndex active)
            , advanceSpent = spent
            , advanceSuccessor = successor
            , advanceSuccessorFacts = successorFacts
            , advanceSettlement = settlement
            , advanceSuccessorLovelace =
                heldValue
                    checkpointMinAda
                    (parameterRegistrationBond parameters)
                    (parameterFreezeBond parameters)
                    successorFacts
                    (settlementPoolAfter settlement)
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
