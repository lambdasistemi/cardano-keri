{- |
Module      : Main
Description : Enforcement vector generator (#106 Slice 4) — fixtures -> Aiken

Reads the committed keripy fixtures
(@offchain\/test\/keri-fixtures\/fixtures\/*.json@) and emits a self-contained
Aiken module
(@onchain\/lib\/cardano_keri\/checkpoint\/enforcement_vectors.ak@) of
@pub const@ tip 'CheckpointDatumV1' + 'EventEvidence' values, one per
enforcement scenario, that the Aiken @enforcement_tests.ak@ drives through
@convict_predicate@\/@freeze_predicate@ to prove verdict parity with the
Slice-3 Haskell over the same fixtures.

The fixture -> (tip, evidence) mapping mirrors the Slice-3
@EnforcementSpec@ builders exactly (the parity is asserted in both languages
against the same committed JSON). The generator reuses the shipped
'CheckpointDatumV1'\/'EventEvidence'\/'Threshold' types and the shipped CESR
decoder; it is OFFLINE (no keripy) and deterministic (drift-checked).

Invocation: @gen-enforcement-vectors OUT_PATH [FIXTURES_DIR]@ (default fixtures
dir @test\/keri-fixtures\/fixtures@, resolved from the offchain package root).
-}
module Main (main) where

import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (
    EventEvidence (..),
    TombstoneV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Data.Aeson (
    Value (..),
    eitherDecodeFileStrict,
 )
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Foldable (toList)
import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Numeric (readHex)
import System.Environment (getArgs)
import Text.Read (readMaybe)

-- ---------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------

main :: IO ()
main = do
    args <- getArgs
    let (out, dir) = case args of
            (o : d : _) -> (Just o, d)
            [o] -> (Just o, defaultFixturesDir)
            [] -> (Nothing, defaultFixturesDir)
    fork <- load dir "fork.json"
    honest2 <- load dir "honest_2key.json"
    honest7 <- load dir "honest_7key.json"
    lagFx <- load dir "lag.json"
    forkW <- load dir "fork_witnessed.json"
    let scenarios =
            [
                ( "fork_convict"
                , "fork: rot_conflict double-signs the rot_recorded tip -> ConvictValid"
                , orDie (tipFrom fork "rot_recorded" 1)
                , orDie (evidenceFrom fork "rot_conflict" "rot_conflict_sigs" Nothing)
                )
            ,
                ( "fork_witnessed_convict"
                , "fork_witnessed: witnessed rot_conflict double-signs the witnessed rot_recorded tip -> ConvictValid"
                , orDie (tipFromWitnessed forkW "rot_recorded" "icp" 1)
                , orDie (evidenceFrom forkW "rot_conflict" "rot_conflict_sigs" (Just "rot_conflict_witness_receipts"))
                )
            ,
                ( "fork_witnessed_honest"
                , "fork_witnessed F3b: the witnessed AID's OWN honest rot_recorded as evidence -> ConvictInvalid(CvNoConflict)"
                , orDie (tipFromWitnessed forkW "rot_recorded" "icp" 1)
                , orDie (evidenceFrom forkW "rot_recorded" "rot_recorded_sigs" (Just "rot_recorded_witness_receipts"))
                )
            ,
                ( "honest2_convict"
                , "honest_2key: rot vs its own reflected state -> ConvictInvalid(CvNoConflict)"
                , orDie (tipFrom honest2 "rot" 1)
                , orDie (evidenceFrom honest2 "rot" "rot_sigs" Nothing)
                )
            ,
                ( "honest2_freeze"
                , "honest_2key: witnessless later rot -> FreezeValid"
                , orDie (tipFrom honest2 "icp" 0)
                , orDie (evidenceFrom honest2 "rot" "rot_sigs" Nothing)
                )
            ,
                ( "lag_freeze"
                , "lag: witnessed later rot (toad=1 receipt) -> FreezeValid"
                , orDie (tipFrom lagFx "icp" 0)
                , orDie (evidenceFrom lagFx "rot" "rot_sigs" (Just "rot_witness_receipts"))
                )
            ,
                ( "honest7_freeze"
                , "honest_7key: 3-of-7 partial reveal vs weighted nt -> FreezeValid"
                , orDie (tipFrom honest7 "icp" 0)
                , orDie (evidenceFrom honest7 "rot" "rot_sigs" Nothing)
                )
            ]
        rendered = render scenarios
    case out of
        Just path -> writeFile path rendered
        Nothing -> putStr rendered

defaultFixturesDir :: FilePath
defaultFixturesDir = "test/keri-fixtures/fixtures"

load :: FilePath -> FilePath -> IO Value
load dir name = do
    result <- eitherDecodeFileStrict (dir <> "/" <> name)
    case result of
        Right v -> pure v
        Left err -> error ("failed to decode " <> name <> ": " <> err)

orDie :: Either String a -> a
orDie = either error id

-- ---------------------------------------------------------
-- Scenario builders (mirror the Slice-3 EnforcementSpec builders)
-- ---------------------------------------------------------

tipFrom :: Value -> Text -> Integer -> Either String CheckpointDatumV1
tipFrom fx evKey seqNo = do
    de <- decodeEvent fx evKey
    pure
        CheckpointDatumV1
            { cdCesrAid = deAid de
            , cdCurKeys = deKeys de
            , cdCurThreshold = deKt de
            , cdNextKeys = deNext de
            , cdNextThreshold = deNt de
            , cdWitnesses = deWits de
            , cdToad = deToad de
            , cdSeq = seqNo
            , cdNativeSn = deSn de
            }

{- | Tip whose key state is @evKey@'s but whose witness set/toad come from
@witKey@ (the AID's inception): a KERI rotation carries no @b@ field, so a
witnessed AID's current witness set is inherited, not restated by the rot.
-}
tipFromWitnessed ::
    Value -> Text -> Text -> Integer -> Either String CheckpointDatumV1
tipFromWitnessed fx evKey witKey seqNo = do
    de <- decodeEvent fx evKey
    wde <- decodeEvent fx witKey
    pure
        CheckpointDatumV1
            { cdCesrAid = deAid de
            , cdCurKeys = deKeys de
            , cdCurThreshold = deKt de
            , cdNextKeys = deNext de
            , cdNextThreshold = deNt de
            , cdWitnesses = deWits wde
            , cdToad = deToad wde
            , cdSeq = seqNo
            , cdNativeSn = deSn de
            }

evidenceFrom ::
    Value -> Text -> Text -> Maybe Text -> Either String EventEvidence
evidenceFrom fx evKey ctrlKey witKey = do
    de <- decodeEvent fx evKey
    ctrl <- sigList fx ctrlKey
    wit <- maybe (Right []) (sigList fx) witKey
    pure
        EventEvidence
            { eeEventBytes = deBytes de
            , eeType = deType de
            , eeNativeSn = deSn de
            , eeCesrAid = deAid de
            , eeSaid = deSaid de
            , eeRevealedKeys = deKeys de
            , eeNextKeys = deNext de
            , eeCurThreshold = deKt de
            , eeNextThreshold = deNt de
            , eeWitnesses = deWits de
            , eeToad = deToad de
            , eeCtrlSigs = ctrl
            , eeWitSigs = wit
            }

-- ---------------------------------------------------------
-- Fixture decoding (KERI ked -> typed fields), mirrors EnforcementSpec
-- ---------------------------------------------------------

data DecodedEvent = DecodedEvent
    { deBytes :: ByteString
    , deType :: ByteString
    , deSn :: Integer
    , deAid :: ByteString
    , deSaid :: ByteString
    , deKeys :: [ByteString]
    , deNext :: [ByteString]
    , deKt :: Threshold
    , deNt :: Threshold
    , deWits :: [ByteString]
    , deToad :: Integer
    }

decodeEvent :: Value -> Text -> Either String DecodedEvent
decodeEvent fx evKey = do
    ev <- note (evKey <> " missing") (lookupKey evKey fx)
    ked <- note (evKey <> ".ked missing") (lookupKey "ked" ev)
    bytes <- decodeHex =<< textField ev "raw_hex"
    ty <- TE.encodeUtf8 <$> textField ked "t"
    sn <- hexIntField ked "s"
    aid <- digestRaw =<< textField ked "i"
    said <- digestRaw =<< textField ev "said"
    keys <- traverse verkeyRaw =<< textArrayField ked "k"
    next <- traverse digestRaw =<< textArrayField ked "n"
    kt <- thresholdField ked "kt"
    nt <- thresholdField ked "nt"
    wits <- traverse verkeyRaw =<< textArrayField ked "b"
    toad <- hexIntField ked "bt"
    pure
        DecodedEvent
            { deBytes = bytes
            , deType = ty
            , deSn = sn
            , deAid = aid
            , deSaid = said
            , deKeys = keys
            , deNext = next
            , deKt = kt
            , deNt = nt
            , deWits = wits
            , deToad = toad
            }

sigList :: Value -> Text -> Either String [(Int, ByteString)]
sigList fx key = do
    arr <- arrayField fx key
    traverse one arr
  where
    one entry = do
        idx <- intField entry "index"
        sig <- decodeHex =<< textField entry "sig_hex"
        pure (fromInteger idx, sig)

thresholdField :: Value -> Text -> Either String Threshold
thresholdField ked key = do
    v <- note (key <> " missing") (lookupKey key ked)
    case v of
        String t -> Unweighted <$> hexInt t
        Array a -> Weighted . pure <$> traverse weightVal (toList a)
        _ -> Left (T.unpack key <> ": threshold is not a string or array")

weightVal :: Value -> Either String Weight
weightVal (String t) = case T.splitOn "/" t of
    [num] -> flip Weight 1 <$> readDecimal num
    [num, den] -> Weight <$> readDecimal num <*> readDecimal den
    _ -> Left ("malformed weight: " <> T.unpack t)
weightVal _ = Left "weight is not a string"

hexIntField :: Value -> Text -> Either String Integer
hexIntField ked key = hexInt =<< textField ked key

hexInt :: Text -> Either String Integer
hexInt t = case readHex (T.unpack t) :: [(Integer, String)] of
    [(n, "")] -> Right n
    _ -> Left ("malformed hex integer: " <> T.unpack t)

readDecimal :: Text -> Either String Integer
readDecimal t =
    maybe (Left ("malformed integer: " <> T.unpack t)) Right (readMaybe (T.unpack t))

-- ---------------------------------------------------------
-- CESR / JSON helpers (mirror FixtureLoader; shipped decoder only)
-- ---------------------------------------------------------

decodeHex :: Text -> Either String ByteString
decodeHex t = convertFromBase Base16 (TE.encodeUtf8 t)

verkeyRaw :: Text -> Either String ByteString
verkeyRaw t =
    parseFull t >>= \case
        Ed25519PublicKey raw -> Right raw
        _ -> Left (T.unpack t <> ": not an Ed25519 public key")

digestRaw :: Text -> Either String ByteString
digestRaw t =
    parseFull t >>= \case
        SelfAddressing raw -> Right raw
        _ -> Left (T.unpack t <> ": not a self-addressing digest")

parseFull :: Text -> Either String Primitive
parseFull t = case parsePrimitive (TE.encodeUtf8 t) of
    Right (p, rest)
        | BS.null rest -> Right p
        | otherwise -> Left (T.unpack t <> ": trailing bytes after primitive")
    Left err -> Left (T.unpack t <> ": " <> err)

note :: Text -> Maybe a -> Either String a
note msg = maybe (Left (T.unpack msg)) Right

lookupKey :: Text -> Value -> Maybe Value
lookupKey k value = case value of
    Object o -> KM.lookup (K.fromText k) o
    _ -> Nothing

textField :: Value -> Text -> Either String Text
textField value k = note (k <> " missing or not a string") $ do
    field <- lookupKey k value
    case field of
        String t -> Just t
        _ -> Nothing

intField :: Value -> Text -> Either String Integer
intField value k = note (k <> " missing or not an integer") $ do
    field <- lookupKey k value
    case field of
        Number s -> Just (truncate s)
        _ -> Nothing

arrayField :: Value -> Text -> Either String [Value]
arrayField value k = note (k <> " missing or not an array") $ do
    field <- lookupKey k value
    case field of
        Array a -> Just (toList a)
        _ -> Nothing

textArrayField :: Value -> Text -> Either String [Text]
textArrayField value k = do
    elems <- arrayField value k
    traverse asText elems
  where
    asText (String t) = Right t
    asText _ = Left (T.unpack k <> ": element is not a string")

-- ---------------------------------------------------------
-- Aiken rendering
-- ---------------------------------------------------------

type Scenario = (String, String, CheckpointDatumV1, EventEvidence)

render :: [Scenario] -> String
render scenarios =
    header <> "\n" <> golden <> "\n" <> concatMap renderScenario scenarios
  where
    header =
        unlines
            [ "//// Auto-generated Aiken enforcement vectors for #106 — DO NOT EDIT."
            , "////"
            , "//// Regenerate with `just gen-enforcement-vectors` (runs"
            , "//// offchain/app/GenEnforcementVectors.hs over the committed keripy"
            , "//// fixtures). Each scenario is the tip datum + decoded evidence the"
            , "//// Slice-3 EnforcementSpec builds from the same JSON; enforcement_tests.ak"
            , "//// asserts convict_predicate/freeze_predicate reproduce the Haskell"
            , "//// verdicts, plus the TombstoneV1 codec golden. `just"
            , "//// check-enforcement-vectors` forbids drift."
            , ""
            , "use cardano_keri/checkpoint/datum.{CheckpointDatumV1}"
            , "use cardano_keri/checkpoint/enforcement.{EventEvidence}"
            , "use cardano_keri/checkpoint/threshold.{Unweighted, Weighted, Weight}"
            ]
    -- TombstoneV1 codec golden: canonical CBOR of a fixed synthetic record,
    -- byte-identical to the Haskell canonicalCbor (Constr 0, 3 fields).
    golden =
        unlines
            [ "/// TombstoneV1 { cesr_aid: 0xaa*32, convicted_at_native_sn: 1,"
            , "/// evidence_said: 0xcc*32 } canonical CBOR (byte-parity golden)"
            , "pub const golden_tombstone: ByteArray ="
            , "  " <> hexLit (canonicalCbor goldenTombstone)
            ]
    goldenTombstone =
        TombstoneV1 (BS.replicate 32 0xaa) 1 (BS.replicate 32 0xcc)

renderScenario :: Scenario -> String
renderScenario (name, doc, tip, evidence) =
    unlines
        [ "/// " <> doc
        , "pub const " <> name <> "_tip: CheckpointDatumV1 = " <> renderDatum tip
        , ""
        , "pub const " <> name <> "_evidence: EventEvidence = " <> renderEvidence evidence
        , ""
        ]

renderDatum :: CheckpointDatumV1 -> String
renderDatum d =
    "CheckpointDatumV1 { "
        <> intercalate
            ", "
            [ "cesr_aid: " <> hexLit (cdCesrAid d)
            , "cur_keys: " <> byteList (cdCurKeys d)
            , "cur_threshold: " <> renderThreshold (cdCurThreshold d)
            , "next_keys: " <> byteList (cdNextKeys d)
            , "next_threshold: " <> renderThreshold (cdNextThreshold d)
            , "witnesses: " <> byteList (cdWitnesses d)
            , "toad: " <> show (cdToad d)
            , "seq: " <> show (cdSeq d)
            , "native_sn: " <> show (cdNativeSn d)
            ]
        <> " }"

renderEvidence :: EventEvidence -> String
renderEvidence e =
    "EventEvidence { "
        <> intercalate
            ", "
            [ "event_bytes: " <> hexLit (eeEventBytes e)
            , "t: " <> hexLit (eeType e)
            , "native_sn: " <> show (eeNativeSn e)
            , "cesr_aid: " <> hexLit (eeCesrAid e)
            , "said: " <> hexLit (eeSaid e)
            , "revealed_keys: " <> byteList (eeRevealedKeys e)
            , "next_keys: " <> byteList (eeNextKeys e)
            , "cur_threshold: " <> renderThreshold (eeCurThreshold e)
            , "next_threshold: " <> renderThreshold (eeNextThreshold e)
            , "witnesses: " <> byteList (eeWitnesses e)
            , "toad: " <> show (eeToad e)
            , "ctrl_sigs: " <> sigLits (eeCtrlSigs e)
            , "wit_sigs: " <> sigLits (eeWitSigs e)
            ]
        <> " }"

renderThreshold :: Threshold -> String
renderThreshold (Unweighted m) = "Unweighted(" <> show m <> ")"
renderThreshold (Weighted clauses) =
    "Weighted([" <> intercalate ", " (map clause clauses) <> "])"
  where
    clause ws = "[" <> intercalate ", " (map weight ws) <> "]"
    weight (Weight num den) =
        "Weight { num: " <> show num <> ", den: " <> show den <> " }"

byteList :: [ByteString] -> String
byteList xs = "[" <> intercalate ", " (map hexLit xs) <> "]"

sigLits :: [(Int, ByteString)] -> String
sigLits xs = "[" <> intercalate ", " (map one xs) <> "]"
  where
    one (i, s) = "(" <> show i <> ", " <> hexLit s <> ")"

hexLit :: ByteString -> String
hexLit b = "#\"" <> BC.unpack (convertToBase Base16 b) <> "\""
