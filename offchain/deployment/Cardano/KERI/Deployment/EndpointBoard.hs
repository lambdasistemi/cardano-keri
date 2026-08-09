{- |
Module      : Cardano.KERI.Deployment.EndpointBoard
Description : Verify KERI endpoint records and resolve the on-chain board

The catalog is deliberately fail-closed: every current output at the frozen
marker address must be an authentic board marker, otherwise no partial view is
returned. Current means the exact unspent set; valid duplicates stay visible.
-}
module Cardano.KERI.Deployment.EndpointBoard (
    EndpointRecord (..),
    BoardEntry (..),
    parseEndpointRecord,
    parseWitnessKey,
    resolveBoardCatalog,
    renderBoardCatalog,
    watchabilityGrade,
    missingBoardWitnesses,
    renderWatchability,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Cardano.KERI.ChainQuery (
    BoardEntry (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.ChainQuery.PlutusJson (plutusDataFromJson)
import Control.Monad (unless, when)
import Data.Aeson (
    FromJSON (..),
    eitherDecodeStrict',
    withObject,
    (.:),
    (.:?),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (digitToInt, isHexDigit)
import Data.List (sortOn)
import Data.Maybe (catMaybes)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import PlutusCore.Data (Data (..))

data EndpointRecord = EndpointRecord
    { endpointEventBytes :: !ByteString
    , endpointSignature :: !ByteString
    , endpointWitnessKey :: !ByteString
    , endpointAid :: !Text
    , endpointScheme :: !Text
    , endpointUrl :: !Text
    }
    deriving stock (Show, Eq)

data ReplyEvent = ReplyEvent
    { replyVersion :: !Text
    , replyType :: !Text
    , replyDigest :: !Text
    , replyDate :: !Text
    , replyRoute :: !Text
    , replyAttributes :: !ReplyAttributes
    }

data ReplyAttributes = ReplyAttributes
    { replyEndpointAid :: !Text
    , replyScheme :: !Text
    , replyUrl :: !Text
    }

newtype RoutedEvent = RoutedEvent
    { routedRoute :: Maybe Text
    }

instance FromJSON ReplyEvent where
    parseJSON = withObject "KERI reply event" $ \object ->
        ReplyEvent
            <$> object .: "v"
            <*> object .: "t"
            <*> object .: "d"
            <*> object .: "dt"
            <*> object .: "r"
            <*> object .: "a"

instance FromJSON ReplyAttributes where
    parseJSON = withObject "KERI endpoint attributes" $ \object ->
        ReplyAttributes
            <$> object .: "eid"
            <*> object .: "scheme"
            <*> object .: "url"

instance FromJSON RoutedEvent where
    parseJSON = withObject "KERI routed event" $ \object ->
        RoutedEvent <$> object .:? "r"

-- | Extract exactly one authentic @/loc/scheme@ reply from an OOBI stream.
parseEndpointRecord :: ByteString -> Either String EndpointRecord
parseEndpointRecord stream = do
    messages <- splitMessages stream
    records <- traverse endpointCandidate messages
    case catMaybes records of
        [record] -> pure record
        [] -> Left "OOBI has no /loc/scheme reply"
        _ -> Left "OOBI has more than one /loc/scheme reply"
  where
    endpointCandidate (raw, attachments) = do
        routed <-
            either
                (Left . ("invalid KERI event JSON: " <>))
                pure
                (eitherDecodeStrict' raw)
        if routedRoute routed /= Just "/loc/scheme"
            then pure Nothing
            else do
                event <- decodeReply raw
                Just <$> recordFromAttachedEvent raw attachments event

-- | Decode one witness's KERI B-code to its raw 32-byte Ed25519 key.
parseWitnessKey :: Text -> Either String ByteString
parseWitnessKey = decodeWitnessKey "witness identifier" . TE.encodeUtf8

resolveBoardCatalog ::
    Text ->
    Text ->
    [ChainAssetUtxo] ->
    Either String [BoardEntry]
resolveBoardCatalog policy markerAddress =
    traverse resolveOne . sortOn outputKey
  where
    outputKey output =
        (chainAssetTxId output, chainAssetIndex output)
    resolveOne output =
        prefixOutput output $ do
            unless (chainAssetAddress output == markerAddress) $
                Left "output address is not the board marker address"
            marker <-
                case chainAssetList output of
                    [asset] -> pure asset
                    _ -> Left "output must carry exactly one native asset"
            unless
                ( chainAssetPolicy marker == policy
                    && chainAssetQuantity marker == 1
                )
                $ Left "output does not carry exactly one board marker"
            markerKey <-
                decodeMarkerName (chainAssetName marker)
            datumValue <-
                maybe
                    (Left "output has no inline datum")
                    plutusDataFromJson
                    (chainAssetInlineDatum output)
            (datumKey, eventBytes, signature, owner) <-
                case datumValue of
                    Constr 0 [B key, B event, B sig, B ownerKeyHash] ->
                        pure (key, event, sig, ownerKeyHash)
                    _ -> Left "inline datum is not frozen BoardDatumV1"
            unless (BS.length datumKey == 32 && datumKey == markerKey) $
                Left "datum witness key does not match the marker asset name"
            unless (BS.length owner == 28) $
                Left "datum owner key hash is not 28 bytes"
            record <-
                validateEndpointEvent datumKey eventBytes signature
            pure
                BoardEntry
                    { boardWitnessKey = endpointWitnessKey record
                    , boardAid = endpointAid record
                    , boardScheme = endpointScheme record
                    , boardUrl = endpointUrl record
                    , boardTxId = chainAssetTxId output
                    , boardIndex = chainAssetIndex output
                    , boardLovelace = chainAssetLovelace output
                    , boardOwnerKeyHash = owner
                    }

renderBoardCatalog :: [BoardEntry] -> Text
renderBoardCatalog =
    T.unlines . map renderEntry
  where
    renderEntry entry =
        T.unwords
            [ boardAid entry
            , "verified"
            , boardScheme entry
            , boardUrl entry
            , "tx"
            , boardTxId entry
                <> "#"
                <> T.pack (show $ boardIndex entry)
            , "deposit"
            , T.pack (show $ boardLovelace entry)
            ]

{- | Count declared witness keys with at least one current verified record.
Duplicate board records never increase the numerator.
-}
watchabilityGrade :: [ByteString] -> [BoardEntry] -> (Int, Int)
watchabilityGrade witnesses entries =
    ( length
        [ ()
        | witness <- witnesses
        , witness `Set.member` catalogKeys
        ]
    , length witnesses
    )
  where
    catalogKeys = Set.fromList (map boardWitnessKey entries)

-- | Declared witness keys that have no current verified board record.
missingBoardWitnesses :: [ByteString] -> [BoardEntry] -> [ByteString]
missingBoardWitnesses witnesses entries =
    [ witness
    | witness <- witnesses
    , witness `Set.notMember` catalogKeys
    ]
  where
    catalogKeys = Set.fromList (map boardWitnessKey entries)

renderWatchability :: [ByteString] -> [BoardEntry] -> Text
renderWatchability witnesses entries =
    let (watchable, declared) = watchabilityGrade witnesses entries
     in "watchable "
            <> T.pack (show watchable)
            <> "/"
            <> T.pack (show declared)

recordFromAttachedEvent ::
    ByteString ->
    ByteString ->
    ReplyEvent ->
    Either String EndpointRecord
recordFromAttachedEvent raw attachments _event = do
    unless (BS.length attachments == 136) $
        Left "endpoint attachment is not one signer and signature"
    unless ("-CAB" `BS.isPrefixOf` attachments) $
        Left "endpoint attachment signer counter is malformed"
    let signerToken = BS.take 44 (BS.drop 4 attachments)
        signatureToken = BS.drop 48 attachments
    signerKey <- decodeWitnessKey "endpoint attachment signer" signerToken
    signature <-
        case parsePrimitive signatureToken of
            Right (Ed25519Signature rawSignature, trailing)
                | BS.null trailing -> pure rawSignature
            _ -> Left "endpoint attachment signature is malformed"
    record <- validateEndpointEvent signerKey raw signature
    unless (TE.encodeUtf8 (endpointAid record) == signerToken) $
        Left "endpoint attachment signer does not match event eid"
    pure record

validateEndpointEvent ::
    ByteString ->
    ByteString ->
    ByteString ->
    Either String EndpointRecord
validateEndpointEvent expectedKey raw signature = do
    event <- decodeReply raw
    validateEventVersion raw (replyVersion event)
    unless (replyType event == "rpy") $
        Left "endpoint event type is not rpy"
    unless
        ( not (T.null $ replyDate event)
            && T.all (not . isUrlWhitespace) (replyDate event)
        )
        $ Left "endpoint event datetime is empty or contains whitespace"
    unless (replyRoute event == "/loc/scheme") $
        Left "endpoint event route is not /loc/scheme"
    let attributes = replyAttributes event
        aid = replyEndpointAid attributes
        scheme = replyScheme attributes
        url = replyUrl attributes
    witnessKey <-
        decodeWitnessKey "endpoint eid" (TE.encodeUtf8 aid)
    unless (witnessKey == expectedKey) $
        Left "endpoint eid does not match the marker witness key"
    digest <-
        decodeDigest (TE.encodeUtf8 $ replyDigest event)
    digestOffset <- scalarOffset raw "d" (replyDigest event)
    unless (blake3Hash (blankDigest raw digestOffset) == digest) $
        Left "endpoint SAID does not bind the exact event bytes"
    unless (scheme == "http" || scheme == "https") $
        Left "endpoint scheme is not http or https"
    unless
        ( (scheme <> "://") `T.isPrefixOf` url
            && T.length url > T.length scheme + 3
            && T.all (not . isUrlWhitespace) url
        )
        $ Left "endpoint URL does not match its scheme"
    unless (BS.length signature == 64) $
        Left "endpoint signature is not 64 bytes"
    unless (verifyEd25519 witnessKey raw signature) $
        Left "endpoint signature does not verify"
    pure
        EndpointRecord
            { endpointEventBytes = raw
            , endpointSignature = signature
            , endpointWitnessKey = witnessKey
            , endpointAid = aid
            , endpointScheme = scheme
            , endpointUrl = url
            }

decodeReply :: ByteString -> Either String ReplyEvent
decodeReply raw =
    either
        (Left . ("invalid KERI reply JSON: " <>))
        pure
        (eitherDecodeStrict' raw)

validateEventVersion :: ByteString -> Text -> Either String ()
validateEventVersion raw version = do
    let encoded = TE.encodeUtf8 version
        prefix = "{\"v\":\"" <> encoded <> "\","
    unless
        ( BS.length encoded == 17
            && BS.take 10 encoded == "KERI10JSON"
            && BS.drop 16 encoded == "_"
            && prefix `BS.isPrefixOf` raw
        )
        $ Left "endpoint version is not canonical KERI 1.0 JSON"
    embeddedSize <-
        parseHexBytes
            "endpoint version size"
            (BS.take 6 $ BS.drop 10 encoded)
    unless (embeddedSize == BS.length raw) $
        Left "endpoint version size does not match event bytes"

splitMessages ::
    ByteString ->
    Either String [(ByteString, ByteString)]
splitMessages bytes
    | BS.null (BS.dropWhile isAsciiWhitespace bytes) = pure []
    | otherwise = do
        (raw, attachments, trailing) <-
            splitMessage (BS.dropWhile isAsciiWhitespace bytes)
        ((raw, attachments) :) <$> splitMessages trailing

splitMessage ::
    ByteString ->
    Either String (ByteString, ByteString, ByteString)
splitMessage stream = do
    let prefix = "{\"v\":\"KERI10JSON"
    unless (prefix `BS.isPrefixOf` stream) $
        Left "OOBI does not contain a KERI 1.0 JSON message"
    eventSize <-
        parseHexBytes
            "KERI message size"
            (BS.take 6 $ BS.drop (BS.length prefix) stream)
    when (eventSize <= 0 || eventSize > BS.length stream) $
        Left "OOBI embedded event size is out of bounds"
    let (raw, afterEvent) = BS.splitAt eventSize stream
    (attachmentQuadlets, afterCounter) <-
        parseCounter "-V" afterEvent
    let attachmentBytes = attachmentQuadlets * 4
    when (BS.length afterCounter < attachmentBytes) $
        Left "OOBI attachment group is truncated"
    let (attachments, trailing) =
            BS.splitAt attachmentBytes afterCounter
    pure (raw, attachments, trailing)

parseCounter ::
    ByteString ->
    ByteString ->
    Either String (Int, ByteString)
parseCounter code bytes = do
    when (BS.length bytes < 4) $
        Left ("truncated CESR counter " <> B8.unpack code)
    unless (BS.take 2 bytes == code) $
        Left ("expected CESR counter " <> B8.unpack code)
    high <- decodeBase64Digit (BS.index bytes 2)
    low <- decodeBase64Digit (BS.index bytes 3)
    pure (high * 64 + low, BS.drop 4 bytes)

decodeBase64Digit :: Word8 -> Either String Int
decodeBase64Digit byte
    | byte >= 0x41 && byte <= 0x5a =
        pure (fromIntegral byte - 0x41)
    | byte >= 0x61 && byte <= 0x7a =
        pure (fromIntegral byte - 0x61 + 26)
    | byte >= 0x30 && byte <= 0x39 =
        pure (fromIntegral byte - 0x30 + 52)
    | byte == 0x2d = pure 62
    | byte == 0x5f = pure 63
    | otherwise = Left "invalid CESR base64 counter digit"

decodeWitnessKey :: String -> ByteString -> Either String ByteString
decodeWitnessKey label token = do
    unless (BS.take 1 token == "B") $
        Left (label <> " is not a non-transferable B-code witness key")
    case parsePrimitive token of
        Right (Ed25519PublicKey key, trailing)
            | BS.null trailing -> pure key
        _ -> Left (label <> " is not one complete Ed25519 key")

decodeDigest :: ByteString -> Either String ByteString
decodeDigest token =
    case parsePrimitive token of
        Right (SelfAddressing digest, trailing)
            | BS.null trailing -> pure digest
        _ -> Left "endpoint d is not one complete E-code digest"

decodeMarkerName :: Text -> Either String ByteString
decodeMarkerName assetName = do
    bytes <-
        either
            (const $ Left "marker asset name is not hexadecimal")
            pure
            (convertFromBase Base16 $ TE.encodeUtf8 assetName)
    unless
        ( BS.length bytes == 32
            && TE.decodeUtf8 (convertToBase Base16 bytes) == assetName
        )
        $ Left "marker asset name is not canonical raw 32-byte key hex"
    pure bytes

scalarOffset ::
    ByteString ->
    Text ->
    Text ->
    Either String Int
scalarOffset raw field value = do
    let prefix = TE.encodeUtf8 ("\"" <> field <> "\":\"")
        needle = TE.encodeUtf8 value
        (before, match) = BS.breakSubstring prefix raw
    when (BS.null match) $
        Left (T.unpack field <> " field not found")
    let offset = BS.length before + BS.length prefix
    unless (needle `BS.isPrefixOf` BS.drop offset raw) $
        Left (T.unpack field <> " value does not match event bytes")
    pure offset

blankDigest :: ByteString -> Int -> ByteString
blankDigest raw digestOffset =
    BS.take digestOffset raw
        <> B8.replicate 44 '#'
        <> BS.drop (digestOffset + 44) raw

prefixOutput ::
    ChainAssetUtxo ->
    Either String a ->
    Either String a
prefixOutput output = \case
    Left err ->
        Left $
            T.unpack (chainAssetTxId output)
                <> "#"
                <> show (chainAssetIndex output)
                <> ": "
                <> err
    Right value -> Right value

parseHexBytes :: String -> ByteString -> Either String Int
parseHexBytes label bytes
    | BS.null bytes || not (all isHexDigit $ B8.unpack bytes) =
        Left (label <> " is not hexadecimal")
    | otherwise =
        pure $
            foldl
                (\acc digit -> acc * 16 + digitToInt digit)
                0
                (B8.unpack bytes)

isAsciiWhitespace :: Word8 -> Bool
isAsciiWhitespace byte =
    byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x20

isUrlWhitespace :: Char -> Bool
isUrlWhitespace char =
    char == ' ' || char == '\t' || char == '\r' || char == '\n'
