{- |
Module      : Cardano.KERI.Deployment.KEL
Description : Parse stock kli inception and rotation exports

The parser consumes the framed messages in a keripy 1.3.5 @kli export@ stream.
It preserves the exact event bytes and decodes only the CESR 1.0 attachment
material required by the frozen checkpoint validators.
-}
module Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    RotationExport (..),
    parseInceptionExport,
    parseRotationExport,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    datumWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
    evaluate,
 )
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (unless, when)
import Data.Aeson (
    FromJSON (..),
    Value (..),
    eitherDecodeStrict',
    withObject,
    (.:),
 )
import Data.Aeson.Types (Parser)
import Data.Bits (shiftL, shiftR, (.&.))
import Data.ByteArray.Encoding (
    Base (Base64URLUnpadded),
    convertFromBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (digitToInt, isHexDigit)
import Data.Foldable (toList)
import Data.IntSet qualified as IntSet
import Data.List (nub)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Text.Read (readMaybe)

{- | Registration material derived from one inception message.

The AID remains available in qb64 form for CLI output while the datum stores
the decoded 32-byte self-addressing digest expected on-chain.
-}
data InceptionExport = InceptionExport
    { inceptionAid :: !Text
    , inceptionDatum :: !CheckpointDatumV1
    , inceptionEvidence :: !RegistrationEvidence
    , inceptionDigestOffset :: !Int
    }
    deriving stock (Show, Eq)

{- | Rotation material derived from the first @rot@ after an inception.

The KERI event signatures are retained separately because they authenticate
the exact @rot@ bytes but are not the Cardano-specific, outref-bound
@AdvanceMessage@ signatures consumed in 'aeCtrlSigs'.
-}
data RotationExport = RotationExport
    { rotationAid :: !Text
    , rotationDatum :: !CheckpointDatumV1
    , rotationEvidence :: !AdvanceEvidence
    , rotationEventSignatures :: ![(Int, ByteString)]
    }
    deriving stock (Show, Eq)

data InceptionEvent = InceptionEvent
    { eventType :: !Text
    , eventDigest :: !Text
    , eventAid :: !Text
    , eventSequence :: !Text
    , eventCurrentThreshold :: !Threshold
    , eventCurrentKeys :: ![Text]
    , eventNextThreshold :: !Threshold
    , eventNextKeys :: ![Text]
    , eventToad :: !Text
    , eventWitnesses :: ![Text]
    }

instance FromJSON InceptionEvent where
    parseJSON = withObject "KERI inception event" $ \o -> do
        eventType <- o .: "t"
        eventDigest <- o .: "d"
        eventAid <- o .: "i"
        eventSequence <- o .: "s"
        eventCurrentThreshold <- o .: "kt" >>= parseThreshold
        eventCurrentKeys <- o .: "k"
        eventNextThreshold <- o .: "nt" >>= parseThreshold
        eventNextKeys <- o .: "n"
        eventToad <- o .: "bt"
        eventWitnesses <- o .: "b"
        pure InceptionEvent{..}

data RotationEvent = RotationEvent
    { rotationType :: !Text
    , rotationDigest :: !Text
    , rotationEventAid :: !Text
    , rotationSequence :: !Text
    , rotationPrior :: !Text
    , rotationCurrentThreshold :: !Threshold
    , rotationCurrentKeys :: ![Text]
    , rotationNextThreshold :: !Threshold
    , rotationNextKeys :: ![Text]
    , rotationToad :: !Text
    , rotationWitnessCuts :: ![Text]
    , rotationWitnessAdds :: ![Text]
    }

instance FromJSON RotationEvent where
    parseJSON = withObject "KERI rotation event" $ \o -> do
        rotationType <- o .: "t"
        rotationDigest <- o .: "d"
        rotationEventAid <- o .: "i"
        rotationSequence <- o .: "s"
        rotationPrior <- o .: "p"
        rotationCurrentThreshold <- o .: "kt" >>= parseThreshold
        rotationCurrentKeys <- o .: "k"
        rotationNextThreshold <- o .: "nt" >>= parseThreshold
        rotationNextKeys <- o .: "n"
        rotationToad <- o .: "bt"
        rotationWitnessCuts <- o .: "br"
        rotationWitnessAdds <- o .: "ba"
        pure RotationEvent{..}

{- | Parse the first complete inception message in a @kli export@ stream.

The function rejects non-inception events, malformed version framing,
unsupported indexed-signature encodings, missing signature groups, invalid
qb64 material, and a self-addressing digest that does not bind the exact raw
event bytes.
-}
parseInceptionExport :: ByteString -> Either String InceptionExport
parseInceptionExport stream = do
    (raw, attachments, _) <- splitMessage stream
    event <- eitherDecodeStrict' raw
    unless (eventType event == "icp") $
        Left "KEL first event is not an icp inception"
    unless
        (eventAid event == eventDigest event)
        (Left "inception i and d fields differ")
    sequenceNumber <- parseHexText "s" (eventSequence event)
    toad <- parseHexText "bt" (eventToad event)
    aid <- decodeSelfAddressing "i" (eventAid event)
    digest <- decodeSelfAddressing "d" (eventDigest event)
    unless (digest == aid) $
        Left "inception i and d digests differ"
    currentKeys <-
        traverse (decodePublicKey "k") (eventCurrentKeys event)
    nextKeys <-
        traverse (decodeSelfAddressing "n") (eventNextKeys event)
    witnesses <-
        traverse (decodePublicKey "b") (eventWitnesses event)
    (controllerSignatures, witnessReceipts) <-
        parseAttachments attachments
    when (null controllerSignatures) $
        Left "KEL inception has no controller indexed signatures"
    let offD = scalarOffset raw "d" (eventDigest event)
        offI = scalarOffset raw "i" (eventAid event)
    digestOffset <- offD
    aidOffset <- offI
    unless (blake3Hash (blankSaid raw digestOffset aidOffset) == aid) $
        Left "KEL inception SAID does not bind the exact event bytes"
    evidence <-
        RegistrationEvidence
            raw
            <$> scalarOffset raw "t" (eventType event)
            <*> pure aidOffset
            <*> scalarOffset raw "s" (eventSequence event)
            <*> traverse (arrayOffset raw "k") (eventCurrentKeys event)
            <*> thresholdOffset
                raw
                "kt"
                (eventCurrentThreshold event)
                (thresholdSpelling $ eventCurrentThreshold event)
            <*> traverse (arrayOffset raw "n") (eventNextKeys event)
            <*> thresholdOffset
                raw
                "nt"
                (eventNextThreshold event)
                (thresholdSpelling $ eventNextThreshold event)
            <*> traverse (arrayOffset raw "b") (eventWitnesses event)
            <*> scalarOffset raw "bt" (eventToad event)
            <*> pure controllerSignatures
            <*> pure witnessReceipts
    let datum =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = currentKeys
                , cdCurThreshold = eventCurrentThreshold event
                , cdNextKeys = nextKeys
                , cdNextThreshold = eventNextThreshold event
                , cdWitnesses = witnesses
                , cdToad = toad
                , cdSeq = 0
                , cdNativeSn = sequenceNumber
                }
    pure
        InceptionExport
            { inceptionAid = eventAid event
            , inceptionDatum = datum
            , inceptionEvidence = evidence
            , inceptionDigestOffset = digestOffset
            }

{- | Parse the first rotation in a complete inception-to-rotation export.

The native KERI event signatures and witness receipts must authenticate the
exact @rot.raw@ bytes. The native signatures are deliberately not copied into
the Cardano-specific controller-signature field.
-}
parseRotationExport :: ByteString -> Either String RotationExport
parseRotationExport stream = do
    inception <- parseInceptionExport stream
    let old = inceptionDatum inception
    (_, _, afterInception) <- splitMessage stream
    when (BS.null afterInception) $
        Left "KEL export has no rotation after inception"
    (raw, attachments, trailing) <- splitMessage afterInception
    unless (BS.all isAsciiWhitespace trailing) $
        Left "KEL export has unsupported messages after the first rotation"
    event <- eitherDecodeStrict' raw
    unless (rotationType event == "rot") $
        Left "KEL second event is not a rot rotation"
    unless (rotationEventAid event == inceptionAid inception) $
        Left "rotation AID does not match inception"
    unless (rotationPrior event == inceptionAid inception) $
        Left "rotation prior digest does not match inception"
    sequenceNumber <- parseHexText "s" (rotationSequence event)
    unless (sequenceNumber == cdNativeSn old + 1) $
        Left "rotation native sequence does not immediately follow inception"
    toad <- parseHexText "bt" (rotationToad event)
    aid <- decodeSelfAddressing "i" (rotationEventAid event)
    digest <- decodeSelfAddressing "d" (rotationDigest event)
    currentKeys <-
        traverse (decodePublicKey "k") (rotationCurrentKeys event)
    nextKeys <-
        traverse (decodeSelfAddressing "n") (rotationNextKeys event)
    witnessCuts <-
        traverse (decodePublicKey "br") (rotationWitnessCuts event)
    witnessAdds <-
        traverse (decodePublicKey "ba") (rotationWitnessAdds event)
    unless
        (map (blake3Hash . qb64Verkey) currentKeys == cdNextKeys old)
        (Left "rotation current keys do not match inception next-key commitments")
    unless
        ( distinct witnessCuts
            && all (`elem` cdWitnesses old) witnessCuts
        )
        (Left "rotation witness cuts are not a distinct subset")
    let survivingWitnesses =
            filter (`notElem` witnessCuts) (cdWitnesses old)
    unless
        ( distinct witnessAdds
            && all (`notElem` witnessCuts) witnessAdds
            && all (`notElem` survivingWitnesses) witnessAdds
        )
        (Left "rotation witness additions are not a valid delta")
    let incomingWitnesses = survivingWitnesses <> witnessAdds
        datum =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = currentKeys
                , cdCurThreshold = rotationCurrentThreshold event
                , cdNextKeys = nextKeys
                , cdNextThreshold = rotationNextThreshold event
                , cdWitnesses = incomingWitnesses
                , cdToad = toad
                , cdSeq = cdSeq old + 1
                , cdNativeSn = sequenceNumber
                }
    either
        (Left . ("rotation successor datum is malformed: " <>) . show)
        Right
        (datumWellFormed datum)
    (eventSignatures, witnessReceipts) <- parseAttachments attachments
    when (null eventSignatures) $
        Left "KEL rotation has no controller indexed signatures"
    let controllerPositions =
            verifiedPositions currentKeys raw eventSignatures
    unless
        ( evaluate
            (rotationCurrentThreshold event)
            (length currentKeys)
            controllerPositions
        )
        (Left "KEL rotation controller signatures are below threshold")
    unless
        ( evaluate
            (cdNextThreshold old)
            (length $ cdNextKeys old)
            controllerPositions
        )
        (Left "KEL rotation signatures do not satisfy the prior next threshold")
    if toad == 0
        then
            unless (null witnessReceipts) $
                Left "KEL witnessless rotation carries unexpected receipts"
        else
            unless
                ( fromIntegral
                    ( IntSet.size $
                        verifiedPositions incomingWitnesses raw witnessReceipts
                    )
                    >= toad
                )
                (Left "KEL rotation witness receipts are below toad")
    digestOffset <- scalarOffset raw "d" (rotationDigest event)
    unless (blake3Hash (blankDigest raw digestOffset) == digest) $
        Left "KEL rotation SAID does not bind the exact event bytes"
    evidence <-
        AdvanceEvidence
            raw
            <$> scalarOffset raw "t" (rotationType event)
            <*> scalarOffset raw "i" (rotationEventAid event)
            <*> scalarOffset raw "s" (rotationSequence event)
            <*> traverse (arrayOffset raw "k") (rotationCurrentKeys event)
            <*> thresholdOffset
                raw
                "kt"
                (rotationCurrentThreshold event)
                (thresholdSpelling $ rotationCurrentThreshold event)
            <*> traverse (arrayOffset raw "n") (rotationNextKeys event)
            <*> thresholdOffset
                raw
                "nt"
                (rotationNextThreshold event)
                (thresholdSpelling $ rotationNextThreshold event)
            <*> traverse (arrayOffset raw "br") (rotationWitnessCuts event)
            <*> traverse (arrayOffset raw "ba") (rotationWitnessAdds event)
            <*> scalarOffset raw "bt" (rotationToad event)
            <*> pure witnessCuts
            <*> pure witnessAdds
            <*> pure []
            <*> pure witnessReceipts
    pure
        RotationExport
            { rotationAid = rotationEventAid event
            , rotationDatum = datum
            , rotationEvidence = evidence
            , rotationEventSignatures = eventSignatures
            }

splitMessage ::
    ByteString ->
    Either String (ByteString, ByteString, ByteString)
splitMessage stream = do
    let prefix = "{\"v\":\"KERI10JSON"
    unless (prefix `BS.isPrefixOf` stream) $
        Left "KEL does not start with a KERI 1.0 JSON message"
    let encodedSize = BS.take 6 (BS.drop (BS.length prefix) stream)
    size <- parseHexBytes "KERI message size" encodedSize
    when (size <= 0 || size > BS.length stream) $
        Left "KEL embedded event size is out of bounds"
    let (raw, afterEvent) = BS.splitAt size stream
    unless ("_\"" `BS.isInfixOf` BS.take 26 raw) $
        Left "KEL version string is malformed"
    (attachmentQuadlets, afterCounter) <-
        parseCounter "-V" afterEvent
    let attachmentBytes = attachmentQuadlets * 4
    when (BS.length afterCounter < attachmentBytes) $
        Left "KEL attachment group is truncated"
    let (attachments, remaining) =
            BS.splitAt attachmentBytes afterCounter
    pure (raw, attachments, BS.dropWhile isAsciiWhitespace remaining)

parseAttachments ::
    ByteString ->
    Either String ([(Int, ByteString)], [(Int, ByteString)])
parseAttachments = go Nothing Nothing
  where
    go controller witness rest
        | BS.null rest =
            pure
                ( fromMaybe [] controller
                , fromMaybe [] witness
                )
        | "-A" `BS.isPrefixOf` rest = do
            when (isJust controller) $
                Left "duplicate controller signature group"
            (count, sigMaterial) <- parseCounter "-A" rest
            (sigs, remaining) <- parseIndexedSignatures count sigMaterial
            go (Just sigs) witness remaining
        | "-B" `BS.isPrefixOf` rest = do
            when (isJust witness) $
                Left "duplicate witness signature group"
            (count, sigMaterial) <- parseCounter "-B" rest
            (sigs, remaining) <- parseIndexedSignatures count sigMaterial
            go controller (Just sigs) remaining
        | "-E" `BS.isPrefixOf` rest =
            pure
                ( fromMaybe [] controller
                , fromMaybe [] witness
                )
        | otherwise =
            Left $
                "unsupported CESR inception attachment: "
                    <> B8.unpack (BS.take 4 rest)

verifiedPositions ::
    [ByteString] ->
    ByteString ->
    [(Int, ByteString)] ->
    IntSet.IntSet
verifiedPositions verkeys message signatures =
    IntSet.fromList
        [ index
        | (index, signature) <- signatures
        , Just verkey <- [atMay verkeys index]
        , verifyEd25519 verkey message signature
        ]

atMay :: [a] -> Int -> Maybe a
atMay values index
    | index < 0 = Nothing
    | otherwise =
        case drop index values of
            value : _ -> Just value
            [] -> Nothing

isAsciiWhitespace :: Word8 -> Bool
isAsciiWhitespace byte =
    byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x20

distinct :: (Eq a) => [a] -> Bool
distinct values = nub values == values

parseCounter :: ByteString -> ByteString -> Either String (Int, ByteString)
parseCounter code bytes = do
    when (BS.length bytes < 4) $
        Left ("truncated CESR counter " <> B8.unpack code)
    unless (code == BS.take 2 bytes) $
        Left ("expected CESR counter " <> B8.unpack code)
    high <- decodeBase64Digit (BS.index bytes 2)
    low <- decodeBase64Digit (BS.index bytes 3)
    pure (high * 64 + low, BS.drop 4 bytes)

parseIndexedSignatures ::
    Int ->
    ByteString ->
    Either String ([(Int, ByteString)], ByteString)
parseIndexedSignatures count bytes = go count bytes []
  where
    go remaining rest acc
        | remaining == 0 = pure (reverse acc, rest)
        | BS.length rest < 88 =
            Left "truncated CESR indexed Ed25519 signature"
        | otherwise = do
            let (token, following) = BS.splitAt 88 rest
            unless (BS.head token == 0x41) $
                Left "unsupported CESR indexed signature code"
            index <- decodeBase64Digit (BS.index token 1)
            signature <- decodeSmallIndexedSignature token
            unless (BS.length signature == 64) $
                Left "CESR indexed Ed25519 signature is not 64 bytes"
            go (remaining - 1) following ((index, signature) : acc)

decodeSmallIndexedSignature :: ByteString -> Either String ByteString
decodeSmallIndexedSignature token = do
    encodedDigits <- traverse decodeBase64Digit (BS.unpack $ BS.drop 2 token)
    let shiftedDigits =
            zipWith
                ( \current following ->
                    ((current .&. 0x03) `shiftL` 4)
                        + (following `shiftR` 2)
                )
                encodedDigits
                (drop 1 encodedDigits <> [0])
    normalized <- BS.pack <$> traverse encodeBase64Digit shiftedDigits
    convertFromBase Base64URLUnpadded normalized

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
    | otherwise = Left "invalid CESR base64 counter/index digit"

encodeBase64Digit :: Int -> Either String Word8
encodeBase64Digit value
    | value >= 0 && value < 26 = pure (fromIntegral value + 0x41)
    | value < 52 = pure (fromIntegral value - 26 + 0x61)
    | value < 62 = pure (fromIntegral value - 52 + 0x30)
    | value == 62 = pure 0x2d
    | value == 63 = pure 0x5f
    | otherwise = Left "invalid normalized base64 signature digit"

decodePublicKey :: String -> Text -> Either String ByteString
decodePublicKey field text =
    case parsePrimitive (TE.encodeUtf8 text) of
        Right (Ed25519PublicKey raw, rest)
            | BS.null rest -> pure raw
        _ -> Left (field <> " is not one complete Ed25519 qb64 key")

decodeSelfAddressing :: String -> Text -> Either String ByteString
decodeSelfAddressing field text =
    case parsePrimitive (TE.encodeUtf8 text) of
        Right (SelfAddressing raw, rest)
            | BS.null rest -> pure raw
        _ -> Left (field <> " is not one complete E-code qb64 digest")

parseThreshold :: Value -> Parser Threshold
parseThreshold = \case
    String value ->
        either fail (pure . Unweighted) $
            parseHexText "threshold" value
    Array values ->
        Weighted <$> parseClauses (toList values)
    _ -> fail "KERI threshold must be a hex string or weighted array"
  where
    parseClauses values =
        case values of
            String{} : _ -> (: []) <$> traverse parseWeightValue values
            Array{} : _ -> traverse parseClause values
            [] -> fail "KERI weighted threshold is empty"
            _ -> fail "KERI weighted threshold mixes array shapes"
    parseClause = \case
        Array weights -> traverse parseWeightValue (toList weights)
        _ -> fail "KERI weighted threshold clause is not an array"
    parseWeightValue = \case
        String weight ->
            either fail pure (parseWeight $ T.unpack weight)
        _ -> fail "KERI threshold weight is not a string"

parseWeight :: String -> Either String Weight
parseWeight spelling =
    case break (== '/') spelling of
        (numerator, "") ->
            Weight
                <$> parseDecimal "weight numerator" numerator
                <*> pure 1
        (numerator, _ : denominator) ->
            Weight
                <$> parseDecimal "weight numerator" numerator
                <*> parseDecimal "weight denominator" denominator

parseDecimal :: String -> String -> Either String Integer
parseDecimal label spelling =
    maybe
        (Left $ label <> " is not a decimal integer")
        pure
        (readMaybe spelling)

parseHexText :: String -> Text -> Either String Integer
parseHexText label = parseHexInteger label . T.unpack

parseHexBytes :: String -> ByteString -> Either String Int
parseHexBytes label bytes = do
    value <- parseHexInteger label (B8.unpack bytes)
    if value > fromIntegral (maxBound :: Int)
        then Left (label <> " exceeds Int")
        else pure (fromIntegral value)

parseHexInteger :: String -> String -> Either String Integer
parseHexInteger label spelling
    | null spelling || not (all isHexDigit spelling) =
        Left (label <> " is not hexadecimal")
    | otherwise =
        pure $
            foldl
                (\acc digit -> acc * 16 + fromIntegral (digitToInt digit))
                0
                spelling

scalarOffset :: ByteString -> Text -> Text -> Either String Int
scalarOffset raw field value = do
    let prefix = TE.encodeUtf8 ("\"" <> field <> "\":\"")
        needle = TE.encodeUtf8 value
    start <- findBytes (T.unpack field <> " field") prefix raw
    let offset = start + BS.length prefix
    unless (needle `BS.isPrefixOf` BS.drop offset raw) $
        Left (T.unpack field <> " value does not match event bytes")
    pure offset

arrayOffset :: ByteString -> Text -> Text -> Either String Int
arrayOffset raw field value = do
    let prefix = TE.encodeUtf8 ("\"" <> field <> "\":[")
        needle = TE.encodeUtf8 ("\"" <> value <> "\"")
    start <- findBytes (T.unpack field <> " array") prefix raw
    relative <-
        findBytes
            (T.unpack field <> " array value")
            needle
            (BS.drop start raw)
    pure (start + relative + 1)

thresholdOffset ::
    ByteString ->
    Text ->
    Threshold ->
    ByteString ->
    Either String Int
thresholdOffset raw field threshold spelling =
    case threshold of
        Unweighted _ ->
            scalarOffset raw field (TE.decodeUtf8 spelling)
        Weighted _ -> do
            let prefix = TE.encodeUtf8 ("\"" <> field <> "\":")
            start <- findBytes (T.unpack field <> " field") prefix raw
            let offset = start + BS.length prefix
            unless (spelling `BS.isPrefixOf` BS.drop offset raw) $
                Left (T.unpack field <> " threshold does not match event bytes")
            pure offset

thresholdSpelling :: Threshold -> ByteString
thresholdSpelling = \case
    Unweighted value -> B8.pack (showHex value)
    Weighted [clause] -> renderClause clause
    Weighted clauses ->
        "[" <> BS.intercalate "," (map renderClause clauses) <> "]"
  where
    renderClause weights =
        "["
            <> BS.intercalate
                ","
                (map (quote . renderWeight) weights)
            <> "]"
    renderWeight (Weight numerator 1) = B8.pack (show numerator)
    renderWeight (Weight numerator denominator) =
        B8.pack (show numerator <> "/" <> show denominator)
    quote value = "\"" <> value <> "\""

showHex :: Integer -> String
showHex value
    | value < 16 = [hexDigit value]
    | otherwise =
        showHex (value `div` 16) <> [hexDigit (value `mod` 16)]
  where
    hexDigit digit
        | digit < 10 =
            toEnum (fromEnum '0' + fromIntegral digit)
        | otherwise =
            toEnum (fromEnum 'a' + fromIntegral digit - 10)

findBytes :: String -> ByteString -> ByteString -> Either String Int
findBytes label needle haystack =
    let (before, match) = BS.breakSubstring needle haystack
     in if BS.null match
            then Left (label <> " not found")
            else pure (BS.length before)

blankSaid :: ByteString -> Int -> Int -> ByteString
blankSaid raw digestOffset aidOffset =
    BS.take digestOffset raw
        <> B8.replicate 44 '#'
        <> BS.take
            (aidOffset - digestOffset - 44)
            (BS.drop (digestOffset + 44) raw)
        <> B8.replicate 44 '#'
        <> BS.drop (aidOffset + 44) raw

blankDigest :: ByteString -> Int -> ByteString
blankDigest raw digestOffset =
    BS.take digestOffset raw
        <> B8.replicate 44 '#'
        <> BS.drop (digestOffset + 44) raw
