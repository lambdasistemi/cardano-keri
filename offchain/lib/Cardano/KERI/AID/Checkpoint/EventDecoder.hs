{- |
Module      : Cardano.KERI.AID.Checkpoint.EventDecoder
Description : Bytes-only total parse of a KERI establishment event (#291)

Derives event variant, protected field values, and SAID blanking solely
from complete event bytes. No caller offset is accepted.
-}
module Cardano.KERI.AID.Checkpoint.EventDecoder (
    EventVariant (..),
    EventDecodeError (..),
    DecodedEstablishmentEvent (..),
    decodeEstablishmentEvent,
    decodeSaidPreimage,
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word8)

-- | Structural establishment-event variant.
data EventVariant
    = -- | Inception.
      VariantIcp
    | -- | Delegated inception.
      VariantDip
    | -- | Rotation.
      VariantRot
    | -- | Delegated rotation.
      VariantDrt
    deriving stock (Show, Eq)

-- | Closed total-parse rejection.
data EventDecodeError
    = -- | Length is not in 1–1024.
      ErrLengthBound
    | -- | Version prefix is not @KERI10JSON......_@.
      ErrVersionPrefix
    | -- | Declared version size disagrees with the byte length.
      ErrVersionSize
    | -- | JSON framing is malformed or escaped.
      ErrFraming
    | -- | Field order, name, count, duplicate, missing, or unknown.
      ErrFieldOrder
    | -- | A required value has the wrong JSON shape.
      ErrValueShape
    | -- | @t@ is not a supported establishment type.
      ErrUnsupportedType
    | -- | Unparsed bytes remain after the object.
      ErrTrailing
    deriving stock (Show, Eq)

-- | Protected raw spellings from a successful total parse.
data DecodedEstablishmentEvent = DecodedEstablishmentEvent
    { deeVariant :: !EventVariant
    , deeSaid :: !ByteString
    -- ^ 44-char qb64 @d@ content
    , deeAid :: !ByteString
    -- ^ 44-char qb64 @i@ content
    , deeSeq :: !ByteString
    -- ^ hex sequence spelling
    , deePrior :: !(Maybe ByteString)
    -- ^ @p@ content for rot\/drt
    , deeKt :: !ByteString
    -- ^ unquoted string or full JSON array
    , deeK :: ![ByteString]
    , deeNt :: !ByteString
    , deeN :: ![ByteString]
    , deeBt :: !ByteString
    , deeB :: ![ByteString]
    , deeBr :: ![ByteString]
    , deeBa :: ![ByteString]
    , deeDi :: !(Maybe ByteString)
    , deeSaidPreimage :: !ByteString
    }
    deriving stock (Show, Eq)

-- | Decode one bounded establishment event from bytes alone.
decodeEstablishmentEvent
    :: ByteString
    -> Either EventDecodeError DecodedEstablishmentEvent
decodeEstablishmentEvent raw = do
    let n = BS.length raw
    checkBound n
    fields <- parseObject raw
    case fields of
        (vName, vVal, _) : rest
            | vName == "v" -> do
                checkVersion n vVal
                assemble rest raw
        _ -> Left ErrFieldOrder

-- | SAID-blanked preimage from a successful total parse.
decodeSaidPreimage
    :: ByteString -> Either EventDecodeError ByteString
decodeSaidPreimage raw =
    deeSaidPreimage <$> decodeEstablishmentEvent raw

checkBound :: Int -> Either EventDecodeError ()
checkBound n
    | n >= 1 && n <= 1024 = Right ()
    | otherwise = Left ErrLengthBound

checkVersion :: Int -> ByteString -> Either EventDecodeError ()
checkVersion n v
    | BS.length v /= 17 = Left ErrVersionPrefix
    | BS.take 10 v /= "KERI10JSON" = Left ErrVersionPrefix
    | BS.index v 16 /= 0x5f = Left ErrVersionPrefix
    | otherwise = do
        size <- parseHex6 (BS.take 6 (BS.drop 10 v))
        if size == n then Right () else Left ErrVersionSize

parseHex6 :: ByteString -> Either EventDecodeError Int
parseHex6 bs
    | BS.length bs /= 6 = Left ErrVersionPrefix
    | otherwise = go 0 0
  where
    go i acc
        | i == 6 = Right acc
        | otherwise = case hexDigit (BS.index bs i) of
            Just d -> go (i + 1) (acc * 16 + d)
            Nothing -> Left ErrVersionPrefix

hexDigit :: Word8 -> Maybe Int
hexDigit c
    | c >= 0x30 && c <= 0x39 = Just (fromIntegral (c - 0x30))
    | c >= 0x61 && c <= 0x66 = Just (fromIntegral (c - 0x57))
    | otherwise = Nothing

-- | Parse a complete compact JSON object into named values and starts.
parseObject
    :: ByteString
    -> Either EventDecodeError [(ByteString, ByteString, Int)]
parseObject raw = do
    let n = BS.length raw
    require (n >= 2 && at raw 0 == 0x7b && at raw (n - 1) == 0x7d) ErrFraming
    (fs, i) <- parseFields raw 1 []
    if i == n - 1 then Right (reverse fs) else Left ErrTrailing

parseFields
    :: ByteString
    -> Int
    -> [(ByteString, ByteString, Int)]
    -> Either EventDecodeError ([(ByteString, ByteString, Int)], Int)
parseFields raw i acc
    | at raw i == 0x7d = Right (acc, i)
    | otherwise = do
        (name, i1) <- parseString raw i
        require (at raw i1 == 0x3a) ErrFraming
        (val, start, i2) <- parseValue raw (i1 + 1)
        let acc' = (name, val, start) : acc
        case at raw i2 of
            0x2c -> parseFields raw (i2 + 1) acc'
            0x7d -> Right (acc', i2)
            _ -> Left ErrFraming

parseString
    :: ByteString -> Int -> Either EventDecodeError (ByteString, Int)
parseString raw i = do
    require (at raw i == 0x22) ErrFraming
    go (i + 1)
  where
    go j
        | j >= BS.length raw = Left ErrFraming
        | at raw j == 0x5c = Left ErrFraming
        | at raw j == 0x22 = Right (BS.take (j - i - 1) (BS.drop (i + 1) raw), j + 1)
        | otherwise = go (j + 1)

parseValue
    :: ByteString
    -> Int
    -> Either EventDecodeError (ByteString, Int, Int)
parseValue raw i
    | at raw i == 0x22 = do
        (content, j) <- parseString raw i
        Right (content, i + 1, j)
    | at raw i == 0x5b = do
        j <- skipArray raw i
        Right (BS.take (j - i) (BS.drop i raw), i, j)
    | otherwise = Left ErrValueShape

skipArray :: ByteString -> Int -> Either EventDecodeError Int
skipArray raw i = do
    require (at raw i == 0x5b) ErrFraming
    go (i + 1) 1 False
  where
    go :: Int -> Int -> Bool -> Either EventDecodeError Int
    go j depth inStr
        | j >= BS.length raw = Left ErrFraming
        | inStr && at raw j == 0x5c = Left ErrFraming
        | inStr && at raw j == 0x22 = go (j + 1) depth False
        | inStr = go (j + 1) depth True
        | at raw j == 0x22 = go (j + 1) depth True
        | at raw j == 0x5b = go (j + 1) (depth + 1) False
        | at raw j == 0x5d =
            if depth == 1
                then Right (j + 1)
                else go (j + 1) (depth - 1) False
        | otherwise = go (j + 1) depth False

assemble
    :: [(ByteString, ByteString, Int)]
    -> ByteString
    -> Either EventDecodeError DecodedEstablishmentEvent
assemble rest raw = do
    (tName, tVal, _) <- hd rest
    require (tName == "t") ErrFieldOrder
    variant <- parseType tVal
    let names = map (\(n, _, _) -> n) rest
        expected = "t" : schemaTail variant
    require (names == expected) ErrFieldOrder
    said <- req "d" rest
    aid <- req "i" rest
    seqv <- req "s" rest
    kt <- req "kt" rest
    k <- reqList "k" rest
    nt <- req "nt" rest
    n <- reqList "n" rest
    bt <- req "bt" rest
    prior <- optPrior variant rest
    b <- optList variant ["VariantIcp", "VariantDip"] "b" rest
    br <- optList variant ["VariantRot", "VariantDrt"] "br" rest
    ba <- optList variant ["VariantRot", "VariantDrt"] "ba" rest
    di <- case variant of
        VariantDip -> Just <$> req "di" rest
        _ -> Right Nothing
    dStart <- startOf "d" rest
    iStart <- startOf "i" rest
    require (BS.length said == 44 && BS.length aid == 44) ErrValueShape
    let preimage = blank raw dStart iStart
    Right
        DecodedEstablishmentEvent
            { deeVariant = variant
            , deeSaid = said
            , deeAid = aid
            , deeSeq = seqv
            , deePrior = prior
            , deeKt = kt
            , deeK = k
            , deeNt = nt
            , deeN = n
            , deeBt = bt
            , deeB = b
            , deeBr = br
            , deeBa = ba
            , deeDi = di
            , deeSaidPreimage = preimage
            }

schemaTail :: EventVariant -> [ByteString]
schemaTail = \case
    VariantIcp -> ["d", "i", "s", "kt", "k", "nt", "n", "bt", "b", "c", "a"]
    VariantDip -> ["d", "i", "s", "kt", "k", "nt", "n", "bt", "b", "c", "a", "di"]
    VariantRot -> ["d", "i", "s", "p", "kt", "k", "nt", "n", "bt", "br", "ba", "a"]
    VariantDrt -> ["d", "i", "s", "p", "kt", "k", "nt", "n", "bt", "br", "ba", "a"]

parseType :: ByteString -> Either EventDecodeError EventVariant
parseType = \case
    "icp" -> Right VariantIcp
    "dip" -> Right VariantDip
    "rot" -> Right VariantRot
    "drt" -> Right VariantDrt
    _ -> Left ErrUnsupportedType

hd
    :: [(ByteString, ByteString, Int)]
    -> Either EventDecodeError (ByteString, ByteString, Int)
hd (x : _) = Right x
hd [] = Left ErrFieldOrder

req
    :: ByteString
    -> [(ByteString, ByteString, Int)]
    -> Either EventDecodeError ByteString
req name fs = case [v | (n, v, _) <- fs, n == name] of
    [v] -> Right v
    _ -> Left ErrFieldOrder

reqList
    :: ByteString
    -> [(ByteString, ByteString, Int)]
    -> Either EventDecodeError [ByteString]
reqList name fs = do
    raw <- req name fs
    parseStringArray raw

optPrior
    :: EventVariant
    -> [(ByteString, ByteString, Int)]
    -> Either EventDecodeError (Maybe ByteString)
optPrior VariantRot fs = Just <$> req "p" fs
optPrior VariantDrt fs = Just <$> req "p" fs
optPrior _ _ = Right Nothing

optList
    :: EventVariant
    -> [String]
    -> ByteString
    -> [(ByteString, ByteString, Int)]
    -> Either EventDecodeError [ByteString]
optList variant kinds name fs
    | show variant `elem` kinds = reqList name fs
    | otherwise = Right []

startOf
    :: ByteString
    -> [(ByteString, ByteString, Int)]
    -> Either EventDecodeError Int
startOf name fs = case [s | (n, _, s) <- fs, n == name] of
    [s] -> Right s
    _ -> Left ErrFieldOrder

parseStringArray :: ByteString -> Either EventDecodeError [ByteString]
parseStringArray raw
    | BS.null raw || at raw 0 /= 0x5b || at raw (BS.length raw - 1) /= 0x5d =
        Left ErrValueShape
    | BS.length raw == 2 = Right []
    | otherwise = go 1 []
  where
    end = BS.length raw - 1
    go i acc
        | i >= end = Right (reverse acc)
        | otherwise = do
            (s, j) <- parseString raw i
            let acc' = s : acc
            case at raw j of
                0x2c -> go (j + 1) acc'
                0x5d -> Right (reverse acc')
                _ -> Left ErrValueShape

blank :: ByteString -> Int -> Int -> ByteString
blank raw dStart iStart =
    BS.take dStart raw
        <> hashes
        <> BS.take (iStart - dStart - 44) (BS.drop (dStart + 44) raw)
        <> hashes
        <> BS.drop (iStart + 44) raw
  where
    hashes = BS.replicate 44 0x23

at :: ByteString -> Int -> Word8
at raw i
    | i >= 0 && i < BS.length raw = BS.index raw i
    | otherwise = 0

require :: Bool -> EventDecodeError -> Either EventDecodeError ()
require True _ = Right ()
require False e = Left e
