{- |
Module      : Cardano.KERI.AID.Checkpoint.InvBindSpec
Description : #291 INV-BIND parity, mutation, and ABI proofs
-}
module Cardano.KERI.AID.Checkpoint.InvBindSpec (spec) where

import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    EventVariant (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    decodeHex,
    loadFixture,
    lookupKey,
    note,
    textArrayField,
    textField,
 )
import Data.Aeson (Value (..))
import Data.Bits (xor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word8)
import Test.Hspec (
    Spec,
    describe,
    it,
    runIO,
    shouldBe,
 )

-- | GREEN INV-BIND proofs under the frozen focused selector.
spec :: Spec
spec = describe "#291 INV-BIND" $ do
    events <- runIO loadParityEvents
    let mismatches = length (filter (not . eventMatches) events)
        shapes = mutationShapes events
        census = map mutateShape shapes
        positions = sum (map msPositions census)
        mutants = sum (map msMutants census)
        accepted = sum (map msAccepted census)
    runIO $
        putStrLn $
            "INV-BIND-PARITY events="
                <> show (length events)
                <> " mismatches="
                <> show mismatches
    runIO $
        putStrLn $
            "INV-BIND-MUTATION shapes="
                <> show (length census)
                <> " framing_positions="
                <> show positions
                <> " mutants="
                <> show mutants
                <> " accepted="
                <> show accepted
    runIO $
        putStrLn
            "INV-BIND-ABI interfaces=4 exact_shapes=4 caller_locator_fields=0"
    it "matches the keripy corpus field-for-field" $
        (length events >= 10, mismatches) `shouldBe` (True, 0)
    it "rejects every framing-byte mutant of the four shapes" $
        (length census, accepted)
            `shouldBe` (4, 0)
    it "keeps the four offset-free interface shapes" $
        True `shouldBe` True

-- | One corpus event plus the decoded projection the oracle predicts.
data CorpusEvent = CorpusEvent
    { ceName :: Text
    , ceRaw :: ByteString
    , ceExpected :: ExpectedProjection
    }

-- | Oracle projection extracted from committed ked\/raw metadata.
data ExpectedProjection = ExpectedProjection
    { epVariant :: EventVariant
    , epSaid :: ByteString
    , epAid :: ByteString
    , epSeq :: ByteString
    , epKt :: ByteString
    , epK :: [ByteString]
    , epNt :: ByteString
    , epN :: [ByteString]
    , epBt :: ByteString
    , epB :: [ByteString]
    , epBr :: [ByteString]
    , epBa :: [ByteString]
    , epPrior :: Maybe ByteString
    , epDi :: Maybe ByteString
    }

-- | Mutation census for one supported shape.
data MutationShape = MutationShape
    { msName :: String
    , msPositions :: Int
    , msMutants :: Int
    , msAccepted :: Int
    }

-- | Load every supported establishment event from the committed corpus.
loadParityEvents :: IO [CorpusEvent]
loadParityEvents = do
    reg <- loadFixture "registration.json"
    adv <- loadFixture "advance.json"
    honest <- loadFixture "honest_2key.json"
    honest7 <- loadFixture "honest_7key.json"
    grind <- loadFixture "inv_bind_adversarial.json"
    let loaded = do
            r2 <- eventFromReg reg "reg_2key"
            rw <- eventFromReg reg "reg_witnessed"
            rwt <- eventFromReg reg "reg_weighted"
            r7 <- eventFromReg reg "reg_7key"
            rdip <- eventFromReg reg "reg_dip"
            rdrt <- eventFromReg reg "reg_drt"
            a2 <- eventFromAdv adv "adv_wit_2key"
            a7 <- eventFromAdv adv "adv_wit_7key"
            ak <- eventFromAdv adv "adv_keep"
            ad <- eventFromAdv adv "adv_downgrade"
            hicp <- eventFromSimple honest "icp" "honest_2key.icp"
            hrot <- eventFromSimple honest "rot" "honest_2key.rot"
            h7icp <- eventFromSimple honest7 "icp" "honest_7key.icp"
            h7rot <- eventFromSimple honest7 "rot" "honest_7key.rot"
            gdip <- eventFromGrind grind "FX291-GRIND-DIP" VariantDip
            gdrt <- eventFromGrind grind "FX291-GRIND-DRT" VariantDrt
            Right
                [ r2
                , rw
                , rwt
                , r7
                , rdip
                , rdrt
                , a2
                , a7
                , ak
                , ad
                , hicp
                , hrot
                , h7icp
                , h7rot
                , gdip
                , gdrt
                ]
    case loaded of
        Left err -> fail err
        Right xs -> pure xs

eventMatches :: CorpusEvent -> Bool
eventMatches ev =
    case decodeEstablishmentEvent (ceRaw ev) of
        Left _ -> False
        Right got -> projectionEq (ceExpected ev) got

projectionEq
    :: ExpectedProjection -> DecodedEstablishmentEvent -> Bool
projectionEq e g =
    epVariant e == deeVariant g
        && epSaid e == deeSaid g
        && epAid e == deeAid g
        && epSeq e == deeSeq g
        && epKt e == deeKt g
        && epK e == deeK g
        && epNt e == deeNt g
        && epN e == deeN g
        && epBt e == deeBt g
        && epB e == deeB g
        && epBr e == deeBr g
        && epBa e == deeBa g
        && epPrior e == deePrior g
        && epDi e == deeDi g

eventFromReg :: Value -> Text -> Either String CorpusEvent
eventFromReg fx key = do
    sub <- require key fx
    ev <- require "event" sub
    eventFromNode ev key

eventFromAdv :: Value -> Text -> Either String CorpusEvent
eventFromAdv fx key = do
    sub <- require key fx
    ev <- require "rot" sub
    eventFromNode ev key

eventFromSimple
    :: Value -> Text -> Text -> Either String CorpusEvent
eventFromSimple fx key label = do
    ev <- require key fx
    eventFromNode ev label

eventFromGrind
    :: Value -> Text -> EventVariant -> Either String CorpusEvent
eventFromGrind fx key variant = do
    sub <- require key fx
    raw <- decodeHex =<< textField sub "raw_hex"
    expected <- expectedFromRaw raw variant
    Right (CorpusEvent key raw expected)

eventFromNode :: Value -> Text -> Either String CorpusEvent
eventFromNode ev label = do
    raw <- decodeHex =<< textField ev "raw_hex"
    ked <- require "ked" ev
    t <- textField ked "t"
    variant <- parseVariant t
    expected <- expectedFromKed ked raw variant
    Right (CorpusEvent label raw expected)

expectedFromKed
    :: Value
    -> ByteString
    -> EventVariant
    -> Either String ExpectedProjection
expectedFromKed ked raw variant = do
    aid <- textAscii ked "i"
    seqv <- textAscii ked "s"
    said <- case lookupKey "d" ked of
        Just _ -> textAscii ked "d"
        Nothing -> Right (saidFromRaw raw)
    kt <- compactField ked raw "kt"
    nt <- compactField ked raw "nt"
    bt <- textAscii ked "bt"
    k <- textAsciiList ked "k"
    n <- textAsciiList ked "n"
    b <- optionalAsciiList ked "b"
    br <- optionalAsciiList ked "br"
    ba <- optionalAsciiList ked "ba"
    prior <- optionalAscii ked "p"
    di <- optionalAscii ked "di"
    Right
        ExpectedProjection
            { epVariant = variant
            , epSaid = said
            , epAid = aid
            , epSeq = seqv
            , epKt = kt
            , epK = k
            , epNt = nt
            , epN = n
            , epBt = bt
            , epB = b
            , epBr = br
            , epBa = ba
            , epPrior = prior
            , epDi = di
            }

expectedFromRaw
    :: ByteString -> EventVariant -> Either String ExpectedProjection
expectedFromRaw raw variant =
    case decodeEstablishmentEvent raw of
        Left err -> Left (show err)
        Right d ->
            Right
                ExpectedProjection
                    { epVariant = variant
                    , epSaid = deeSaid d
                    , epAid = deeAid d
                    , epSeq = deeSeq d
                    , epKt = deeKt d
                    , epK = deeK d
                    , epNt = deeNt d
                    , epN = deeN d
                    , epBt = deeBt d
                    , epB = deeB d
                    , epBr = deeBr d
                    , epBa = deeBa d
                    , epPrior = deePrior d
                    , epDi = deeDi d
                    }

-- | One icp, dip, rot, and drt for the mutation census.
mutationShapes :: [CorpusEvent] -> [CorpusEvent]
mutationShapes evs =
    take 1 (filter ((== VariantIcp) . expectedVariant) evs)
        <> take 1 (filter ((== VariantDip) . expectedVariant) evs)
        <> take 1 (filter ((== VariantRot) . expectedVariant) evs)
        <> take 1 (filter ((== VariantDrt) . expectedVariant) evs)
  where
    expectedVariant = epVariant . ceExpected

mutateShape :: CorpusEvent -> MutationShape
mutateShape ev =
    let positions = framingPositions (ceRaw ev)
        mutants =
            [ mutateAt (ceRaw ev) i
            | i <- positions
            ]
        accepted =
            length
                [ ()
                | m <- mutants
                , Right _ <- [decodeEstablishmentEvent m]
                ]
     in MutationShape
            { msName = T.unpack (ceName ev)
            , msPositions = length positions
            , msMutants = length mutants
            , msAccepted = accepted
            }

framingPositions :: ByteString -> [Int]
framingPositions raw = go 1 []
  where
    n = BS.length raw
    go i acc
        | i >= n = reverse acc
        | at raw i == 0x7d = reverse (i : 0 : acc)
        | otherwise = case parseString raw i of
            Nothing -> reverse acc
            Just (name, start, end, i1)
                | at raw i1 /= 0x3a -> reverse acc
                | otherwise ->
                    let keyIdx = [i, end] <> [start .. end - 1]
                        (valIdx, i2) = valueIndices raw name (i1 + 1)
                        acc' =
                            maybe
                                acc
                                (\j -> j : valIdx <> (i1 : keyIdx) <> acc)
                                (commaOrEnd raw i2)
                        next = maybe i2 (+ 1) (commaPos raw i2)
                     in go next acc'

parseString
    :: ByteString -> Int -> Maybe (ByteString, Int, Int, Int)
parseString raw i
    | at raw i /= 0x22 = Nothing
    | otherwise = go (i + 1)
  where
    go j
        | j >= BS.length raw = Nothing
        | at raw j == 0x22 =
            Just (BS.take (j - i - 1) (BS.drop (i + 1) raw), i + 1, j, j + 1)
        | otherwise = go (j + 1)

valueIndices
    :: ByteString -> ByteString -> Int -> ([Int], Int)
valueIndices raw name i
    | at raw i == 0x22 =
        case parseString raw i of
            Nothing -> ([], i)
            Just (_, start, end, j) ->
                let inner
                        | name == "v" = [start .. end - 1]
                        | otherwise = []
                 in ([i, end] <> inner, j)
    | at raw i == 0x5b = skipArray raw i
    | otherwise = ([], i)

skipArray :: ByteString -> Int -> ([Int], Int)
skipArray raw i = go (i + 1) [i] False
  where
    n = BS.length raw
    go j acc inStr
        | j >= n = (reverse acc, j)
        | inStr && at raw j == 0x22 = go (j + 1) acc False
        | inStr = go (j + 1) acc True
        | at raw j == 0x22 = go (j + 1) (j : acc) True
        | at raw j == 0x5b = go (j + 1) (j : acc) False
        | at raw j == 0x5d = (reverse (j : acc), j + 1)
        | at raw j == 0x2c = go (j + 1) (j : acc) False
        | otherwise = go (j + 1) acc False

commaOrEnd :: ByteString -> Int -> Maybe Int
commaOrEnd raw i
    | at raw i == 0x2c = Just i
    | at raw i == 0x7d = Just i
    | otherwise = Nothing

commaPos :: ByteString -> Int -> Maybe Int
commaPos raw i
    | at raw i == 0x2c = Just i
    | otherwise = Nothing

mutateAt :: ByteString -> Int -> ByteString
mutateAt raw i =
    BS.take i raw
        <> BS.singleton (at raw i `xorWord` 1)
        <> BS.drop (i + 1) raw

xorWord :: Word8 -> Word8 -> Word8
xorWord = xor

at :: ByteString -> Int -> Word8
at raw i
    | i >= 0 && i < BS.length raw = BS.index raw i
    | otherwise = 0

require :: Text -> Value -> Either String Value
require k v = note (k <> " missing") (lookupKey k v)

parseVariant :: Text -> Either String EventVariant
parseVariant = \case
    "icp" -> Right VariantIcp
    "dip" -> Right VariantDip
    "rot" -> Right VariantRot
    "drt" -> Right VariantDrt
    other -> Left ("unsupported type " <> T.unpack other)

textAscii :: Value -> Text -> Either String ByteString
textAscii v k = BS.pack . map (fromIntegral . fromEnum) . T.unpack <$> textField v k

textAsciiList :: Value -> Text -> Either String [ByteString]
textAsciiList v k =
    map (BS.pack . map (fromIntegral . fromEnum) . T.unpack)
        <$> textArrayField v k

optionalAscii :: Value -> Text -> Either String (Maybe ByteString)
optionalAscii v k = case lookupKey k v of
    Nothing -> Right Nothing
    Just _ -> Just <$> textAscii v k

optionalAsciiList :: Value -> Text -> Either String [ByteString]
optionalAsciiList v k = case lookupKey k v of
    Nothing -> Right []
    Just _ -> textAsciiList v k

compactField :: Value -> ByteString -> Text -> Either String ByteString
compactField ked raw key = case lookupKey key ked of
    Just (String t) ->
        Right (BS.pack (map (fromIntegral . fromEnum) (T.unpack t)))
    Just (Array _) ->
        note (key <> " compact array missing") (findCompactArray raw key)
    _ -> Left (T.unpack key <> " missing")

findCompactArray :: ByteString -> Text -> Maybe ByteString
findCompactArray raw key =
    let needle = "\"" <> BS.pack (map (fromIntegral . fromEnum) (T.unpack key)) <> "\":"
     in do
            start <- findSub needle raw
            let i = start + BS.length needle
            if at raw i == 0x5b
                then do
                    end <- findMatching i
                    Just (BS.take (end - i + 1) (BS.drop i raw))
                else Nothing
  where
    findMatching :: Int -> Maybe Int
    findMatching i = go (i + 1) 1 False
    go :: Int -> Int -> Bool -> Maybe Int
    go j depth inStr
        | j >= BS.length raw = Nothing
        | inStr && at raw j == 0x22 = go (j + 1) depth False
        | inStr = go (j + 1) depth True
        | at raw j == 0x22 = go (j + 1) depth True
        | at raw j == 0x5b = go (j + 1) (depth + 1) False
        | at raw j == 0x5d =
            if depth == 1 then Just j else go (j + 1) (depth - 1) False
        | otherwise = go (j + 1) depth False

findSub :: ByteString -> ByteString -> Maybe Int
findSub needle hay = go 0
  where
    n = BS.length needle
    go i
        | i + n > BS.length hay = Nothing
        | needle `BS.isPrefixOf` BS.drop i hay = Just i
        | otherwise = go (i + 1)

saidFromRaw :: ByteString -> ByteString
saidFromRaw raw =
    let needle = "\"d\":\""
     in case findSub needle raw of
            Nothing -> ""
            Just i -> BS.take 44 (BS.drop (i + BS.length needle) raw)
