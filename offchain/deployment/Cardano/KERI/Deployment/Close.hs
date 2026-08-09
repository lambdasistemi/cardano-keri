{- |
Module      : Cardano.KERI.Deployment.Close
Description : Build and authenticate the V1 Close signing package

The binary signing preimage is reconstructed only from the immutable
deployment, the exact live ACTIVE checkpoint, and the complete Cardano refund
address. KERI event signatures are not Close signatures.
-}
module Cardano.KERI.Deployment.Close (
    ClosePackage (..),
    CloseSigningFiles (..),
    decodeRefundAddress,
    mkClosePackage,
    attachCloseControllerSignatures,
    closeSigningMetadata,
    writeCloseSigningPackage,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    CloseContext (..),
    CloseEvidence (..),
    FullAddress (..),
    StakeCredential (..),
    closePredicate,
    reconstructCloseMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (canonicalCbor)
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..), ChainAsset (..))
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    ScriptEntry (..),
 )
import Cardano.Ledger.Address (
    Addr (..),
    decodeAddr,
 )
import Cardano.Ledger.BaseTypes (
    CertIx (..),
    Network (..),
    TxIx (..),
 )
import Cardano.Ledger.Credential (
    Credential (..),
    Ptr (..),
    SlotNo32 (..),
    StakeReference (..),
 )
import Cardano.Ledger.Hashes (
    KeyHash (..),
    ScriptHash (..),
 )
import Codec.Binary.Bech32 qualified as Bech32
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
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (
    createDirectoryIfMissing,
    renameFile,
 )
import System.FilePath (
    takeDirectory,
    (</>),
 )
import System.IO (
    hClose,
    openBinaryTempFile,
 )
import System.Posix.Files (
    groupReadMode,
    otherReadMode,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
    unionFileModes,
 )

data ClosePackage = ClosePackage
    { closeAid :: !Text
    , closeActiveCheckpoint :: !ActiveCheckpoint
    , closeSpentReference :: !Text
    , closeRefundAddress :: !Text
    , closeRefundLovelace :: !Integer
    , closeContext :: !CloseContext
    , closeEvidence :: !CloseEvidence
    , closeSigningPreimage :: !ByteString
    , closePackageSha256 :: !Text
    }
    deriving stock (Show, Eq)

data CloseSigningFiles = CloseSigningFiles
    { closePreimageFile :: !FilePath
    , closeMetadataFile :: !FilePath
    }
    deriving stock (Show, Eq)

-- | Decode a preprod Shelley payment address into the Aiken address wire.
decodeRefundAddress :: Text -> Either String FullAddress
decodeRefundAddress encoded = do
    (hrp, dataPart) <-
        either
            (Left . ("refund address is not Bech32: " <>) . show)
            Right
            (Bech32.decodeLenient encoded)
    unless (Bech32.humanReadablePartToText hrp == "addr_test") $
        Left "refund address must use the addr_test Bech32 prefix"
    bytes <-
        maybe
            (Left "refund address Bech32 data is invalid")
            Right
            (Bech32.dataPartToBytes dataPart)
    address <-
        maybe
            (Left "refund address is not a supported Shelley payment address")
            Right
            (decodeAddr bytes :: Maybe Addr)
    case address of
        Addr Testnet payment stake ->
            FullAddress
                <$> credential payment
                <*> traverseStake stake
        Addr Mainnet _ _ ->
            Left "refund address belongs to mainnet"
        AddrBootstrap{} ->
            Left "Byron bootstrap refund addresses are unsupported"
  where
    credential = \case
        KeyHashObj (KeyHash paymentHash) ->
            Right $ VerificationKeyCredential $ hashToBytes paymentHash
        ScriptHashObj (ScriptHash scriptHash) ->
            Right $ ScriptCredential $ hashToBytes scriptHash
    traverseStake = \case
        StakeRefNull -> Right Nothing
        StakeRefBase value ->
            Just . InlineStakeCredential <$> credential value
        StakeRefPtr (Ptr (SlotNo32 slot) (TxIx txIndex) (CertIx certIndex)) ->
            Right $
                Just $
                    PointerStakeCredential
                        (fromIntegral slot)
                        (fromIntegral txIndex)
                        (fromIntegral certIndex)

mkClosePackage ::
    Manifest ->
    ActiveCheckpoint ->
    Text ->
    Either String ClosePackage
mkClosePackage manifest active closeRefundAddress = do
    unless
        ( networkName (manifestNetwork manifest) == "preprod"
            && networkMagic (manifestNetwork manifest) == 1
        )
        (Left "close manifest is not preprod network magic 1")
    unless
        (parameterNetworkDiscriminator (manifestParameters manifest) == 0)
        (Left "close manifest network discriminator is not the frozen V1 value")
    checkpoint <- scriptNamed "checkpoint-register" manifest
    let policyText = checkpointPolicyId (manifestCheckpoint manifest)
    unless (scriptHash checkpoint == policyText) $
        Left "manifest checkpoint policy does not match its script entry"
    policy <- decodeHexSized "checkpoint policy" 28 policyText
    _ <-
        decodeHexSized
            "checkpoint asset name"
            32
            (activeCheckpointAssetName active)
    txId <-
        decodeHexSized
            "checkpoint transaction id"
            32
            (activeCheckpointTxId active)
    refund <- decodeRefundAddress closeRefundAddress
    case faPaymentCredential refund of
        ScriptCredential scriptHashBytes
            | scriptHashBytes == policy ->
                Left "refund address cannot use the checkpoint script credential"
        _ -> pure ()
    validateCheckpointValue policyText (activeCheckpointAssetName active) active
    let old = activeCheckpointDatum active
        closeContext =
            CloseContext
                { ccNetworkId =
                    parameterNetworkDiscriminator (manifestParameters manifest)
                , ccCheckpointPolicyId = policy
                , ccSpentTxid = txId
                , ccSpentIndex = fromIntegral $ activeCheckpointIndex active
                , ccOld = old
                }
        closeEvidence =
            CloseEvidence
                { ceRefundAddress = refund
                , ceCtrlSigs = []
                }
        closeSigningPreimage =
            canonicalCbor $
                reconstructCloseMessage closeContext closeEvidence
        closeSpentReference =
            activeCheckpointTxId active
                <> "#"
                <> T.pack (show $ activeCheckpointIndex active)
        closeRefundLovelace = activeCheckpointLovelace active
        closeAid = activeCheckpointAid active
        closePackageSha256 = sha256Text closeSigningPreimage
    pure ClosePackage{closeActiveCheckpoint = active, ..}

attachCloseControllerSignatures ::
    [(Int, ByteString)] ->
    ClosePackage ->
    Either String ClosePackage
attachCloseControllerSignatures signatures package = do
    let evidence =
            (closeEvidence package)
                { ceCtrlSigs = signatures
                }
        updated = package{closeEvidence = evidence}
    either
        (Left . ("Close controller package rejected: " <>) . show)
        Right
        (closePredicate (closeContext updated) evidence)
    pure updated

closeSigningMetadata :: ClosePackage -> Value
closeSigningMetadata package =
    object
        [ "schema" .= ("cardano-keri/close-signing-package/v1" :: Text)
        , "aid" .= closeAid package
        , "spentReference" .= closeSpentReference package
        , "refundAddress" .= closeRefundAddress package
        , "refundLovelace" .= closeRefundLovelace package
        , "preimageFile" .= ("close-message.cbor" :: Text)
        , "preimageSha256" .= closePackageSha256 package
        ]

writeCloseSigningPackage ::
    FilePath ->
    ClosePackage ->
    IO CloseSigningFiles
writeCloseSigningPackage directory package = do
    createDirectoryIfMissing True directory
    let closePreimageFile = directory </> "close-message.cbor"
        closeMetadataFile = directory </> "package.json"
    writeAtomic closePreimageFile (closeSigningPreimage package)
    writeAtomic
        closeMetadataFile
        (BSL.toStrict $ Aeson.encode (closeSigningMetadata package) <> "\n")
    pure CloseSigningFiles{..}

validateCheckpointValue ::
    Text ->
    Text ->
    ActiveCheckpoint ->
    Either String ()
validateCheckpointValue policy assetName active =
    case activeCheckpointAssets active of
        [asset]
            | chainAssetPolicy asset == policy
                && chainAssetName asset == assetName
                && chainAssetQuantity asset == 1 ->
                pure ()
        _ ->
            Left
                "Close requires the ACTIVE value to contain only the singleton \
                \checkpoint token"

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

writeAtomic :: FilePath -> ByteString -> IO ()
writeAtomic output bytes = do
    let directory =
            case takeDirectory output of
                "" -> "."
                path -> path
    (temporary, handle) <-
        openBinaryTempFile directory ".ckeri-close-package.tmp"
    BS.hPut handle bytes
    hClose handle
    renameFile temporary output
    setFileMode
        output
        ( ownerReadMode
            `unionFileModes` ownerWriteMode
            `unionFileModes` groupReadMode
            `unionFileModes` otherReadMode
        )
