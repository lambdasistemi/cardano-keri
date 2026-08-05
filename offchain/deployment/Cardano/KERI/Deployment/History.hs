{- |
Module      : Cardano.KERI.Deployment.History
Description : Judge independently sampled witnessed key-event histories

A read-only verifier and reconciler for complete KERI key-event histories.
It consumes genuine keripy 1.3.5 @kli export@-shaped KERI\/CESR bytes: a
sequence of framed @KERI10JSON@ messages (inception, then any number of
rotation or interaction events), each followed by its own CESR controller
and witness indexed-signature attachment groups, exactly as
'Cardano.KERI.Deployment.KEL' parses for the two-event registration
lineage — generalized here to an arbitrary-length multi-event history. It
proves one captured byte stream is a genuinely signed, hashed, and
witness-receipted lineage from inception through every returned event, then
judges currency, chain agreement, and cross-witness duplicity over a set of
independently sampled histories for one AID. It does not acquire, transport,
or render evidence; those are later slices. It does not read or change
'Cardano.KERI.Deployment.KEL'.
-}
module Cardano.KERI.Deployment.History (
    -- * Establishment state
    EstablishmentState (..),

    -- * Verified history

    {- | 'VerifiedHistory' is exported abstractly: only 'verifyHistory' can
    produce one, and only 'vhHead' reads it. Acquisition code cannot
    fabricate a successful verified history without passing verification.
    -}
    VerifiedHistory,
    verifyHistory,
    vhHead,

    -- * Witness samples
    WitnessId,
    SampleFailure (..),
    WitnessSample,

    -- * Duplicity
    DuplicityFinding (..),

    -- * Chain comparison
    ChainComparison (..),

    -- * Coverage and verdict
    CoverageMode (..),
    CoverageReport (..),
    ExitClass (..),
    Verdict (..),
    exitCode,
    judgeVerdict,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
    qb64Verkey,
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
import Data.List (find, nub)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Text.Read (readMaybe)

-- ---------------------------------------------------------
-- Establishment state
-- ---------------------------------------------------------

{- | The verified key-establishment projection at one inception or rotation
event: the fields a Cardano checkpoint is compared against.
-}
data EstablishmentState = EstablishmentState
    { esAid :: !ByteString
    , esNativeSn :: !Integer
    , esCurKeys :: ![ByteString]
    , esCurThreshold :: !Threshold
    , esNextDigests :: ![ByteString]
    , esNextThreshold :: !Threshold
    , esWitnesses :: ![ByteString]
    , esToad :: !Integer
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Verified history
-- ---------------------------------------------------------

{- | The complete result of independently verifying one sampled byte stream:
the latest establishment head, every establishment state along the lineage
(oldest first, for stale-ancestor comparison), every event's native sequence
and SAID (for duplicity comparison), and the union of witnesses declared
anywhere in the lineage (the coverage-universe contribution of this sample).
-}
data VerifiedHistory = VerifiedHistory
    { vhAid :: !ByteString
    , vhHead :: !EstablishmentState
    , vhEstablishments :: ![EstablishmentState]
    , vhEvents :: ![(Integer, ByteString)]
    , vhWitnessUniverse :: ![ByteString]
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- KERI event JSON shapes
-- ---------------------------------------------------------

newtype TypeProbe = TypeProbe {tpType :: Text}

instance FromJSON TypeProbe where
    parseJSON = withObject "KERI event type probe" $ \o ->
        TypeProbe <$> o .: "t"

data IcpEvent = IcpEvent
    { ieType :: !Text
    , ieDigest :: !Text
    , ieAid :: !Text
    , ieSeq :: !Text
    , ieKt :: !Threshold
    , ieK :: ![Text]
    , ieNt :: !Threshold
    , ieN :: ![Text]
    , ieBt :: !Text
    , ieB :: ![Text]
    }

instance FromJSON IcpEvent where
    parseJSON = withObject "KERI icp event" $ \o -> do
        ieType <- o .: "t"
        ieDigest <- o .: "d"
        ieAid <- o .: "i"
        ieSeq <- o .: "s"
        ieKt <- o .: "kt" >>= parseThreshold
        ieK <- o .: "k"
        ieNt <- o .: "nt" >>= parseThreshold
        ieN <- o .: "n"
        ieBt <- o .: "bt"
        ieB <- o .: "b"
        pure IcpEvent{..}

data RotEvent = RotEvent
    { reType :: !Text
    , reDigest :: !Text
    , reAid :: !Text
    , reSeq :: !Text
    , rePrior :: !Text
    , reKt :: !Threshold
    , reK :: ![Text]
    , reNt :: !Threshold
    , reN :: ![Text]
    , reBt :: !Text
    , reBr :: ![Text]
    , reBa :: ![Text]
    }

instance FromJSON RotEvent where
    parseJSON = withObject "KERI rot event" $ \o -> do
        reType <- o .: "t"
        reDigest <- o .: "d"
        reAid <- o .: "i"
        reSeq <- o .: "s"
        rePrior <- o .: "p"
        reKt <- o .: "kt" >>= parseThreshold
        reK <- o .: "k"
        reNt <- o .: "nt" >>= parseThreshold
        reN <- o .: "n"
        reBt <- o .: "bt"
        reBr <- o .: "br"
        reBa <- o .: "ba"
        pure RotEvent{..}

data IxnEvent = IxnEvent
    { xeType :: !Text
    , xeDigest :: !Text
    , xeAid :: !Text
    , xeSeq :: !Text
    , xePrior :: !Text
    }

instance FromJSON IxnEvent where
    parseJSON = withObject "KERI ixn event" $ \o -> do
        xeType <- o .: "t"
        xeDigest <- o .: "d"
        xeAid <- o .: "i"
        xeSeq <- o .: "s"
        xePrior <- o .: "p"
        pure IxnEvent{..}

parseThreshold :: Value -> Parser Threshold
parseThreshold = \case
    String value ->
        either fail (pure . Unweighted) $ parseHexText "threshold" value
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
        String weight -> either fail pure (parseWeight (T.unpack weight))
        _ -> fail "KERI threshold weight is not a string"

parseWeight :: String -> Either String Weight
parseWeight spelling =
    case break (== '/') spelling of
        (numerator, "") ->
            Weight <$> parseDecimal "weight numerator" numerator <*> pure 1
        (numerator, _ : denominator) ->
            Weight
                <$> parseDecimal "weight numerator" numerator
                <*> parseDecimal "weight denominator" denominator

parseDecimal :: String -> String -> Either String Integer
parseDecimal label spelling =
    maybe (Left (label <> " is not a decimal integer")) pure (readMaybe spelling)

-- ---------------------------------------------------------
-- Verification
-- ---------------------------------------------------------

{- | Verify a complete keripy-shaped KERI\/CESR history stream: framing and
complete consumption, lineage (AID\/prior\/native sequence), the
self-addressing binding of every event, controller and prior next-key
threshold satisfaction on every rotation, interaction-event signature
satisfaction against the current head, witness cut\/add delta validity,
and distinct witness receipts at or above the asserted @toad@.
Establishment state only changes on 'icp'\/'rot'; an 'ixn' advances native
lineage without moving the comparison head.
-}
verifyHistory :: ByteString -> Either String VerifiedHistory
verifyHistory stream0 = do
    (raw0, attachments0, rest0) <- splitMessage stream0
    event0 <- eitherDecodeStrict' raw0
    unless (ieType event0 == "icp") $
        Left "history first event is not an icp inception"
    unless (ieAid event0 == ieDigest event0) $
        Left "history inception AID and digest differ"
    aid <- decodeSelfAddressing "i" (ieAid event0)
    digest <- decodeSelfAddressing "d" (ieDigest event0)
    unless (digest == aid) $
        Left "history inception AID and digest are not equal digests"
    seq0 <- parseHexText "s" (ieSeq event0)
    when (seq0 /= 0) $
        Left "history inception native sequence is not zero"
    curKeys <- traverse (decodePublicKey "k") (ieK event0)
    when (null curKeys) $
        Left "history inception has no current keys"
    nextDigests <- traverse (decodeSelfAddressing "n") (ieN event0)
    witnesses <- traverse (decodePublicKey "b") (ieB event0)
    toad <- parseHexText "bt" (ieBt event0)
    let offD = scalarOffset raw0 "d" (ieDigest event0)
        offI = scalarOffset raw0 "i" (ieAid event0)
    digestOffset <- offD
    aidOffset <- offI
    unless (blake3Hash (blankSaid raw0 digestOffset aidOffset) == aid) $
        Left "history event SAID does not bind the exact event bytes"
    (ctrlSigs, witSigs) <- parseAttachments attachments0
    when (null ctrlSigs) $
        Left "history inception has no controller signatures"
    unless (distinct witnesses) $
        Left "history inception declares a duplicate witness"
    let positions0 = verifiedPositions curKeys raw0 ctrlSigs
    unless (evaluate (ieKt event0) (length curKeys) positions0) $
        Left "history inception controller signatures are below threshold"
    checkReceipts toad witnesses raw0 witSigs
    let head0 =
            EstablishmentState
                { esAid = aid
                , esNativeSn = seq0
                , esCurKeys = curKeys
                , esCurThreshold = ieKt event0
                , esNextDigests = nextDigests
                , esNextThreshold = ieNt event0
                , esWitnesses = witnesses
                , esToad = toad
                }
    loop
        rest0
        VerifiedHistory
            { vhAid = aid
            , vhHead = head0
            , vhEstablishments = [head0]
            , vhEvents = [(seq0, digest)]
            , vhWitnessUniverse = witnesses
            }
        digest
  where
    loop rest acc prevDigest
        | BS.null rest = pure acc
        | otherwise = do
            (raw, attachments, rest') <- splitMessage rest
            probe <- eitherDecodeStrict' raw
            case tpType probe of
                "rot" -> do
                    (acc', digest') <- foldRotation raw attachments prevDigest acc
                    loop rest' acc' digest'
                "ixn" -> do
                    (acc', digest') <- foldInteraction raw attachments prevDigest acc
                    loop rest' acc' digest'
                _ -> Left "history contains an unsupported event type"

foldRotation ::
    ByteString ->
    ByteString ->
    ByteString ->
    VerifiedHistory ->
    Either String (VerifiedHistory, ByteString)
foldRotation raw attachments prevDigest acc = do
    event <- eitherDecodeStrict' raw
    let prevHead = vhHead acc
    unless (reType event == "rot") $
        Left "history event is not a rot rotation"
    aid <- decodeSelfAddressing "i" (reAid event)
    unless (aid == vhAid acc) $
        Left "history event AID does not match inception"
    prior <- decodeSelfAddressing "p" (rePrior event)
    unless (prior == prevDigest) $
        Left "history event prior digest does not match predecessor"
    sn <- parseHexText "s" (reSeq event)
    unless (sn == fst (last (vhEvents acc)) + 1) $
        Left "history event native sequence does not immediately follow"
    curKeys <- traverse (decodePublicKey "k") (reK event)
    when (null curKeys) $
        Left "history rotation has no current keys"
    nextDigests <- traverse (decodeSelfAddressing "n") (reN event)
    cuts <- traverse (decodePublicKey "br") (reBr event)
    adds <- traverse (decodePublicKey "ba") (reBa event)
    toad <- parseHexText "bt" (reBt event)
    unless
        (map (blake3Hash . qb64Verkey) curKeys == esNextDigests prevHead)
        (Left "history rotation keys do not match prior next-key commitments")
    digestOffset <- scalarOffset raw "d" (reDigest event)
    digest <- decodeSelfAddressing "d" (reDigest event)
    unless (blake3Hash (blankDigest raw digestOffset) == digest) $
        Left "history event SAID does not bind the exact event bytes"
    (ctrlSigs, witSigs) <- parseAttachments attachments
    when (null ctrlSigs) $
        Left "history rotation has no controller signatures"
    let positions = verifiedPositions curKeys raw ctrlSigs
    unless (evaluate (reKt event) (length curKeys) positions) $
        Left "history rotation controller signatures are below threshold"
    unless
        ( evaluate
            (esNextThreshold prevHead)
            (length (esNextDigests prevHead))
            positions
        )
        (Left "history rotation signatures do not satisfy the prior next threshold")
    unless
        (distinct cuts && all (`elem` esWitnesses prevHead) cuts)
        (Left "history rotation witness cuts are not a distinct subset")
    let surviving = filter (`notElem` cuts) (esWitnesses prevHead)
    unless
        ( distinct adds
            && all (`notElem` cuts) adds
            && all (`notElem` surviving) adds
        )
        (Left "history rotation witness additions are not a valid delta")
    let incoming = surviving <> adds
    unless (distinct incoming) $
        Left "history rotation resulting witness set has a duplicate"
    checkReceipts toad incoming raw witSigs
    let newHead =
            EstablishmentState
                { esAid = aid
                , esNativeSn = sn
                , esCurKeys = curKeys
                , esCurThreshold = reKt event
                , esNextDigests = nextDigests
                , esNextThreshold = reNt event
                , esWitnesses = incoming
                , esToad = toad
                }
    pure
        ( acc
            { vhHead = newHead
            , vhEstablishments = vhEstablishments acc <> [newHead]
            , vhEvents = vhEvents acc <> [(sn, digest)]
            , vhWitnessUniverse = nub (vhWitnessUniverse acc <> incoming)
            }
        , digest
        )

foldInteraction ::
    ByteString ->
    ByteString ->
    ByteString ->
    VerifiedHistory ->
    Either String (VerifiedHistory, ByteString)
foldInteraction raw attachments prevDigest acc = do
    event <- eitherDecodeStrict' raw
    let prevHead = vhHead acc
    unless (xeType event == "ixn") $
        Left "history event is not an ixn interaction"
    aid <- decodeSelfAddressing "i" (xeAid event)
    unless (aid == vhAid acc) $
        Left "history event AID does not match inception"
    prior <- decodeSelfAddressing "p" (xePrior event)
    unless (prior == prevDigest) $
        Left "history event prior digest does not match predecessor"
    sn <- parseHexText "s" (xeSeq event)
    unless (sn == fst (last (vhEvents acc)) + 1) $
        Left "history event native sequence does not immediately follow"
    digestOffset <- scalarOffset raw "d" (xeDigest event)
    digest <- decodeSelfAddressing "d" (xeDigest event)
    unless (blake3Hash (blankDigest raw digestOffset) == digest) $
        Left "history event SAID does not bind the exact event bytes"
    (ctrlSigs, witSigs) <- parseAttachments attachments
    when (null ctrlSigs) $
        Left "history interaction has no controller signatures"
    let positions = verifiedPositions (esCurKeys prevHead) raw ctrlSigs
    unless (evaluate (esCurThreshold prevHead) (length (esCurKeys prevHead)) positions) $
        Left "history interaction controller signatures are below threshold"
    checkReceipts (esToad prevHead) (esWitnesses prevHead) raw witSigs
    pure
        ( acc
            { vhEvents = vhEvents acc <> [(sn, digest)]
            }
        , digest
        )

checkReceipts ::
    Integer -> [ByteString] -> ByteString -> [(Int, ByteString)] -> Either String ()
checkReceipts toad witnesses raw witSigs
    | toad <= 0 =
        unless (null witSigs) $
            Left "history witnessless event carries unexpected receipts"
    | otherwise =
        unless
            (toInteger (IntSet.size (verifiedPositions witnesses raw witSigs)) >= toad)
            (Left "history witness receipts are below toad")

-- ---------------------------------------------------------
-- KERI10JSON framing and CESR attachments
-- (mirrors Cardano.KERI.Deployment.KEL's parser; duplicated because that
-- module is out of this slice's fence and its internals are unexported)
-- ---------------------------------------------------------

splitMessage ::
    ByteString ->
    Either String (ByteString, ByteString, ByteString)
splitMessage stream = do
    let prefix = "{\"v\":\"KERI10JSON"
    unless (prefix `BS.isPrefixOf` stream) $
        Left "history stream does not start with a KERI 1.0 JSON message"
    let encodedSize = BS.take 6 (BS.drop (BS.length prefix) stream)
    size <- parseHexBytes "KERI message size" encodedSize
    when (size <= 0 || size > BS.length stream) $
        Left "history embedded event size is out of bounds"
    let (raw, afterEvent) = BS.splitAt size stream
    unless ("_\"" `BS.isInfixOf` BS.take 26 raw) $
        Left "history version string is malformed"
    (attachmentQuadlets, afterCounter) <- parseCounter "-V" afterEvent
    let attachmentBytes = attachmentQuadlets * 4
    when (BS.length afterCounter < attachmentBytes) $
        Left "history attachment group is truncated"
    let (attachments, remaining) = BS.splitAt attachmentBytes afterCounter
    pure (raw, attachments, BS.dropWhile isAsciiWhitespace remaining)

parseAttachments ::
    ByteString ->
    Either String ([(Int, ByteString)], [(Int, ByteString)])
parseAttachments = go Nothing Nothing
  where
    go controller witness rest
        | BS.null rest =
            pure (fromMaybe [] controller, fromMaybe [] witness)
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
            pure (fromMaybe [] controller, fromMaybe [] witness)
        | otherwise =
            Left $
                "history unsupported CESR attachment: "
                    <> B8.unpack (BS.take 4 rest)

verifiedPositions ::
    [ByteString] -> ByteString -> [(Int, ByteString)] -> IntSet.IntSet
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

-- ---------------------------------------------------------
-- Witness samples and duplicity
-- ---------------------------------------------------------

-- | An opaque witness identity; the sampler layer decides its exact shape.
type WitnessId = ByteString

-- | An acquisition-layer sample failure. Never itself a negative verdict.
data SampleFailure
    = Unreachable
    | MalformedReply
    | RejectedHistory !String
    deriving stock (Show, Eq)

{- | One witness's outcome: acquisition failure, or an independently verified
history.
-}
type WitnessSample = (WitnessId, Either SampleFailure VerifiedHistory)

{- | Whether two or more independently verified histories disagree at the
same AID and native sequence before any cross-witness merge.
-}
data DuplicityFinding
    = DuplicityNone
    | DuplicityFound ![(ByteString, Integer, ByteString, ByteString)]
    deriving stock (Show, Eq)

duplicityFinding :: [VerifiedHistory] -> DuplicityFinding
duplicityFinding histories =
    case conflicts of
        [] -> DuplicityNone
        _ -> DuplicityFound conflicts
  where
    allEvents =
        [ (vhAid vh, sn, said)
        | vh <- histories
        , (sn, said) <- vhEvents vh
        ]
    conflicts =
        nub
            [ (aid, sn, saidA, saidB)
            | (aid, sn, saidA) <- allEvents
            , (aid', sn', saidB) <- allEvents
            , aid == aid'
            , sn == sn'
            , saidA /= saidB
            , saidA < saidB
            ]

-- ---------------------------------------------------------
-- Chain comparison
-- ---------------------------------------------------------

{- | How the verified, quorum-agreed establishment head compares with the
indexed Cardano checkpoint.
-}
data ChainComparison
    = ChainCurrent
    | ChainStale
    | ChainMismatch
    | ChainUnrecorded
    deriving stock (Show, Eq)

compareChain ::
    EstablishmentState -> [EstablishmentState] -> Maybe EstablishmentState -> ChainComparison
compareChain head_ lineage checkpoint =
    case checkpoint of
        Nothing -> ChainUnrecorded
        Just cp
            | cp == head_ -> ChainCurrent
            | cp `elem` lineage -> ChainStale
            | otherwise -> ChainMismatch

-- ---------------------------------------------------------
-- Coverage and verdict
-- ---------------------------------------------------------

-- | Whether complete declared-witness coverage is load-bearing.
data CoverageMode = QuorumOnly | RequireFullCoverage
    deriving stock (Show, Eq)

data CoverageReport = CoverageReport
    { covDeclared :: !Int
    , covReachableValid :: !Int
    , covFull :: !Bool
    }
    deriving stock (Show, Eq)

data ExitClass = Affirmative | Negative | CannotAnswer
    deriving stock (Show, Eq)

exitCode :: ExitClass -> Int
exitCode Affirmative = 0
exitCode Negative = 1
exitCode CannotAnswer = 2

data Verdict = Verdict
    { verdictClass :: !ExitClass
    , verdictComparison :: !(Maybe ChainComparison)
    , verdictDuplicity :: !DuplicityFinding
    , verdictCoverage :: !CoverageReport
    }
    deriving stock (Show, Eq)

{- | Judge currency, chain agreement, and duplicity over one AID's
independently sampled witnesses. Currency is answerable when at least
@toad@ distinct declared witnesses are reachable-valid and agree on the
verified establishment head — a strict @>=@ comparison, never unanimity.
Duplicity presence overrides currency and does not require full coverage.
Coverage is qualified whenever a witness on the declared universe was not
reachable-valid; 'RequireFullCoverage' turns that qualification into
cannot-answer even when currency would otherwise be affirmative.
-}
judgeVerdict ::
    Integer ->
    CoverageMode ->
    [WitnessId] ->
    [WitnessSample] ->
    Maybe EstablishmentState ->
    Verdict
judgeVerdict toad coverageMode declaredWitnesses samples checkpoint =
    case duplicityFinding reachableHistories of
        finding@(DuplicityFound _) ->
            Verdict
                { verdictClass = Negative
                , verdictComparison = Nothing
                , verdictDuplicity = finding
                , verdictCoverage = coverage
                }
        DuplicityNone
            | coverageMode == RequireFullCoverage && not (covFull coverage) ->
                Verdict
                    { verdictClass = CannotAnswer
                    , verdictComparison = Nothing
                    , verdictDuplicity = DuplicityNone
                    , verdictCoverage = coverage
                    }
            | otherwise -> case agreedHead of
                Nothing ->
                    Verdict
                        { verdictClass = CannotAnswer
                        , verdictComparison = Nothing
                        , verdictDuplicity = DuplicityNone
                        , verdictCoverage = coverage
                        }
                Just (headState, lineage) ->
                    let comparison = compareChain headState lineage checkpoint
                        cls = case comparison of
                            ChainCurrent -> Affirmative
                            _ -> Negative
                     in Verdict
                            { verdictClass = cls
                            , verdictComparison = Just comparison
                            , verdictDuplicity = DuplicityNone
                            , verdictCoverage = coverage
                            }
  where
    -- One vote per distinct declared witness identity: a witness answering
    -- twice must never count as two witnesses toward quorum or coverage.
    reachable =
        nubByWid
            [ (wid, vh)
            | (wid, Right vh) <- samples
            , wid `elem` declaredWitnesses
            ]
    nubByWid [] = []
    nubByWid ((wid, vh) : more) =
        (wid, vh) : nubByWid (filter ((/= wid) . fst) more)
    reachableHistories = map snd reachable
    universe = nub (declaredWitnesses <> concatMap (vhWitnessUniverse . snd) reachable)
    coverage =
        CoverageReport
            { covDeclared = length universe
            , covReachableValid = length reachable
            , covFull = length reachable >= length universe
            }
    agreedHead =
        find
            (\(headState, _) -> countAgreeing headState >= toad)
            [(vhHead vh, vhEstablishments vh) | vh <- distinctHeads]
    distinctHeads = nubByHead reachableHistories
    nubByHead [] = []
    nubByHead (vh : more) = vh : nubByHead (filter ((/= vhHead vh) . vhHead) more)
    countAgreeing headState =
        toInteger (length [() | (_, vh) <- reachable, vhHead vh == headState])
