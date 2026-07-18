{- |
Module      : Main
Description : Registration vector generator (#114 S3) — fixtures -> Aiken

Reads the committed keripy registration bundle
(@offchain\/test\/keri-fixtures\/fixtures\/registration.json@) and
emits a self-contained Aiken module
(@onchain\/lib\/cardano_keri\/checkpoint\/registration_vectors.ak@) of
@pub const@ scenario tuples — deployment context, genesis datum,
lovelace, 'RegistrationEvidence', and verdict — one per S2
'RegistrationSpec' family member, INCLUDING the full A-001 QB
condition-1 offset-misdirection family, plus the byte goldens
(reconstructed-message preimage, proof-token name, kt\/nt\/bt
re-spellings, B-code witness qb64) that @registration_tests.ak@
asserts byte-identical.

One computation feeds both languages: each scenario's verdict is the
Haskell 'registrationPredicate' output, and the generator ASSERTS it
equals the family's declared expectation before emitting — a Haskell
drift breaks the generator run (and the drift check), never silently
weakens the Aiken suite. Controller signatures are produced here from
the bundle's exported signer seeds over the reconstructed
'InceptionMessage' canonical-CBOR preimage (keripy stays the oracle
for KERI artifacts only). OFFLINE (no keripy) and deterministic
(drift-checked).

Invocation: @gen-registration-vectors OUT_PATH [FIXTURES_DIR]@
(default fixtures dir @test\/keri-fixtures\/fixtures@, resolved from
the offchain package root).
-}
module Main (main) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    DatumError (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    InceptionError (..),
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    RegistrationError (..),
    RegistrationEvidence (..),
    proofTokenName,
    qb64WitnessVerkey,
    registrationMessage,
    registrationPredicate,
    respellHex,
    respellThreshold,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
 )
import Control.Monad (unless)
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
-- Deployment contexts (mirror the S2 RegistrationSpec)
-- ---------------------------------------------------------

-- | The canonical test deployment (network 0, policy 0xCC..).
ctx0 :: DeploymentContext
ctx0 =
    DeploymentContext
        { dcNetworkId = 0
        , dcCheckpointPolicyId = BS.replicate 28 0xCC
        , dcMinAda = 2000000
        , dcDReg = 5000000
        }

-- | A crossed deployment: different network id.
ctxNet :: DeploymentContext
ctxNet = ctx0{dcNetworkId = 1}

-- | A crossed deployment: different checkpoint policy.
ctxPol :: DeploymentContext
ctxPol = ctx0{dcCheckpointPolicyId = BS.replicate 28 0xDD}

-- | An honest state-output lovelace comfortably above the floor.
funded :: Integer
funded = 10000000

-- | The exact R8 floor (@min_ada + d_reg@ of 'ctx0').
boundary :: Integer
boundary = dcMinAda ctx0 + dcDReg ctx0

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
    fx <- load dir "registration.json"
    let wit = orDie (regCase ctx0 fx "reg_witnessed")
        wgt = orDie (regCase ctx0 fx "reg_weighted")
        dip = orDie (regCase ctx0 fx "reg_dip")
        drt = orDie (regCase ctx0 fx "reg_drt")
        r2k = orDie (regCase ctx0 fx "reg_2key")
        r7k = orDie (regCase ctx0 fx "reg_7key")
        scenarios = buildScenarios wit wgt dip drt r2k r7k
    mapM_ assertVerdict scenarios
    let rendered = render wit wgt scenarios
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

{- | The generator's own honesty gate: the Haskell predicate must
return exactly the verdict the scenario family declares; a mismatch
aborts the run (nothing wrong is ever emitted).
-}
assertVerdict :: Scenario -> IO ()
assertVerdict s =
    unless (actual == scExpected s) . error $
        "scenario "
            <> scName s
            <> ": Haskell verdict "
            <> show actual
            <> " /= declared "
            <> show (scExpected s)
  where
    actual =
        registrationPredicate
            (scCtx s)
            (scDatum s)
            (scLovelace s)
            (scEvidence s)

-- ---------------------------------------------------------
-- Fixture case (mirrors the S2 RegistrationSpec regCase)
-- ---------------------------------------------------------

-- | One registration sub-fixture, lifted into predicate inputs.
data RegCase = RegCase
    { rcRaw :: ByteString
    , rcDatum :: CheckpointDatumV1
    , rcEvidence :: RegistrationEvidence
    , rcSigners :: [SignKeyDSIGN Ed25519DSIGN]
    , rcAttackers :: [SignKeyDSIGN Ed25519DSIGN]
    , rcAttackerKeys :: [ByteString]
    , rcEventSigs :: [(Int, ByteString)]
    }

-- | Build the 'RegCase' of a sub-fixture for a deployment context.
regCase :: DeploymentContext -> Value -> Text -> Either String RegCase
regCase ctx fx key = do
    sub <- note (key <> " missing") (lookupKey key fx)
    ev <- note (key <> ".event missing") (lookupKey "event" sub)
    raw <- decodeHex =<< textField ev "raw_hex"
    ked <- note (key <> ".event.ked missing") (lookupKey "ked" ev)
    aid <- digestRaw =<< textField ked "i"
    ks <- traverse verkeyRaw =<< textArrayField ked "k"
    ns <- traverse digestRaw =<< textArrayField ked "n"
    ws <- traverse verkeyRaw =<< textArrayField ked "b"
    kt <- thresholdField ked "kt"
    nt <- thresholdField ked "nt"
    bt <- hexIntField ked "bt"
    offs <- note (key <> ".offsets missing") (lookupKey "offsets" sub)
    offT <- off offs "t"
    offI <- off offs "i"
    offS <- off offs "s"
    offKt <- off offs "kt"
    offNt <- off offs "nt"
    offBt <- off offs "bt"
    offK <- offList offs "k"
    offN <- offList offs "n"
    offB <- offList offs "b"
    seeds <-
        note (key <> ".signer_seeds missing") (lookupKey "signer_seeds" sub)
    signers <- map mkSigner <$> seedList seeds "current"
    attackers <- map mkSigner <$> seedList seeds "next"
    eventSigs <- sigList sub "event_sigs"
    let datum =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = ks
                , cdCurThreshold = kt
                , cdNextKeys = ns
                , cdNextThreshold = nt
                , cdWitnesses = ws
                , cdToad = bt
                , cdSeq = 0
                , cdNativeSn = 0
                }
    pure
        RegCase
            { rcRaw = raw
            , rcDatum = datum
            , rcEvidence =
                RegistrationEvidence
                    { reEventBytes = raw
                    , reOffT = offT
                    , reOffI = offI
                    , reOffS = offS
                    , reOffK = offK
                    , reOffKt = offKt
                    , reOffN = offN
                    , reOffNt = offNt
                    , reOffB = offB
                    , reOffBt = offBt
                    , reCtrlSigs = signAll ctx signers datum
                    }
            , rcSigners = signers
            , rcAttackers = attackers
            , rcAttackerKeys = map verkeyOf attackers
            , rcEventSigs = eventSigs
            }
  where
    off o f = fromIntegral <$> intField o f
    offList o f = map fromIntegral <$> intArrayField o f

-- | An Ed25519 signing key from a 32-byte exported seed.
mkSigner :: ByteString -> SignKeyDSIGN Ed25519DSIGN
mkSigner = genKeyDSIGN . mkSeedFromBytes

-- | The raw 32-byte verkey of a signing key.
verkeyOf :: SignKeyDSIGN Ed25519DSIGN -> ByteString
verkeyOf = rawSerialiseVerKeyDSIGN . deriveVerKeyDSIGN

-- | Raw 64-byte Ed25519 signature over a message.
signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver sk msg = rawSerialiseSigDSIGN (signDSIGN () msg sk)

{- | Indexed signatures of all given signers over the reconstructed
'InceptionMessage' canonical-CBOR preimage for a datum + context.
-}
signAll ::
    DeploymentContext ->
    [SignKeyDSIGN Ed25519DSIGN] ->
    CheckpointDatumV1 ->
    [(Int, ByteString)]
signAll ctx signers datum =
    [ (j, signOver sk preimage)
    | (j, sk) <- zip [0 ..] signers
    ]
  where
    preimage = canonicalCbor (registrationMessage ctx datum)

-- ---------------------------------------------------------
-- Scenarios (mirror the S2 RegistrationSpec families)
-- ---------------------------------------------------------

-- | One emitted vector: inputs + the declared-and-asserted verdict.
data Scenario = Scenario
    { scName :: String
    , scDoc :: String
    , scCtx :: DeploymentContext
    , scDatum :: CheckpointDatumV1
    , scLovelace :: Integer
    , scEvidence :: RegistrationEvidence
    , scExpected :: Either RegistrationError ()
    }

{- | Every S2 family member as a deterministic construction over the
honest fixture cases — positives, R3\/R4, per-slice E1-E9, R7
signature negatives, R8, and the full A-001 offset-misdirection
family — plus the two true-shape honest scenarios (unwitnessed 2-key,
unwitnessed GLEIF 7-key; A-003\/T114-S5a) the S5 validator positives
and measurement cells build from. Constructions mirror the S2 spec
bodies exactly.
-}
buildScenarios ::
    RegCase ->
    RegCase ->
    RegCase ->
    RegCase ->
    RegCase ->
    RegCase ->
    [Scenario]
buildScenarios wit wgt dip drt r2k r7k =
    [ sc
        "pos_witnessed"
        "reg_witnessed (3-wit toad-2) honest package -> Valid"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit)
        (Right ())
    , sc
        "pos_weighted"
        "reg_weighted (fractional kt) honest package -> Valid"
        ctx0
        (rcDatum wgt)
        funded
        (rcEvidence wgt)
        (Right ())
    , sc
        "pos_deposit_boundary"
        "deposit boundary: exactly min_ada + d_reg -> Valid"
        ctx0
        (rcDatum wit)
        boundary
        (rcEvidence wit)
        (Right ())
    , sc
        "pos_2key"
        "reg_2key (unwitnessed 2-key) honest package -> Valid"
        ctx0
        (rcDatum r2k)
        funded
        (rcEvidence r2k)
        (Right ())
    , sc
        "pos_7key"
        "reg_7key (unwitnessed GLEIF 7-key) honest package -> Valid"
        ctx0
        (rcDatum r7k)
        funded
        (rcEvidence r7k)
        (Right ())
    , sc
        "r3_seq_nonzero"
        "seq /= 0 -> R3GenesisDatumMismatch"
        ctx0
        (rcDatum wit){cdSeq = 1}
        funded
        (rcEvidence wit)
        (Left R3GenesisDatumMismatch)
    , sc
        "r4_native_sn_nonzero"
        "native_sn /= 0 -> R4 InceptionNativeSnNonZero"
        ctx0
        (rcDatum wit){cdNativeSn = 1}
        funded
        (rcEvidence wit)
        (Left (R4InceptionInvalid InceptionNativeSnNonZero))
    , sc
        "e1_dip"
        "reg_dip: real keripy delegated inception -> E1"
        ctx0
        (rcDatum dip)
        funded
        (rcEvidence dip)
        (Left E1EventTypeMismatch)
    , sc
        "e1_drt"
        "reg_drt: real keripy delegated rotation -> E1"
        ctx0
        (rcDatum drt)
        funded
        (rcEvidence drt)
        (Left E1EventTypeMismatch)
    , let d = (rcDatum wit){cdCesrAid = cdCesrAid (rcDatum wgt)}
       in sc
            "e2_crossed_aid"
            "crossed AID in the datum (re-signed) -> E2"
            ctx0
            d
            funded
            (rcEvidence wit)
                { reCtrlSigs = signAll ctx0 (rcSigners wit) d
                }
            (Left E2AidMismatch)
    , sc
        "e3_off_s_at_t"
        "off_s pointed at t -> E3"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffS = reOffT (rcEvidence wit)}
        (Left E3SequenceMismatch)
    , let d = (rcDatum wit){cdCurKeys = rcAttackerKeys wit}
       in sc
            "e4_squat"
            "squat: attacker keys over victim bytes -> E4"
            ctx0
            d
            funded
            (rcEvidence wit)
                { reCtrlSigs = signAll ctx0 (rcAttackers wit) d
                }
            (Left E4CurKeysMismatch)
    , sc
        "e5_kt_restated"
        "restated unweighted kt -> E5"
        ctx0
        (rcDatum wit){cdCurThreshold = Unweighted 1}
        funded
        (rcEvidence wit)
        (Left E5CurThresholdMismatch)
    , sc
        "e5_weighted_mutated"
        "mutated weighted clause -> E5"
        ctx0
        (rcDatum wgt)
            { cdCurThreshold =
                Weighted [[Weight 1 3, Weight 1 4, Weight 1 4]]
            }
        funded
        (rcEvidence wgt)
        (Left E5CurThresholdMismatch)
    , sc
        "e6_next_flipped"
        "substituted next digest -> E6"
        ctx0
        (rcDatum wit){cdNextKeys = flipFirst (cdNextKeys (rcDatum wit))}
        funded
        (rcEvidence wit)
        (Left E6NextKeysMismatch)
    , sc
        "e7_nt_restated"
        "restated nt -> E7"
        ctx0
        (rcDatum wit){cdNextThreshold = Unweighted 1}
        funded
        (rcEvidence wit)
        (Left E7NextThresholdMismatch)
    , sc
        "e8_witness_flipped"
        "substituted witness verkey -> E8"
        ctx0
        (rcDatum wit){cdWitnesses = flipFirst (cdWitnesses (rcDatum wit))}
        funded
        (rcEvidence wit)
        (Left E8WitnessesMismatch)
    , sc
        "e8_witness_count"
        "witness count mismatch -> E8"
        ctx0
        (rcDatum wit){cdWitnesses = drop 1 (cdWitnesses (rcDatum wit))}
        funded
        (rcEvidence wit)
        (Left E8WitnessesMismatch)
    , sc
        "e9_toad_restated"
        "restated toad -> E9"
        ctx0
        (rcDatum wit){cdToad = 1}
        funded
        (rcEvidence wit)
        (Left E9ToadMismatch)
    , sc
        "r7_event_raw_sigs"
        "the bundle's own KERI event_raw sigs MUST fail -> R7"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reCtrlSigs = rcEventSigs wit}
        (Left R7QuorumUnsatisfied)
    , sc
        "r7_below_threshold"
        "below threshold: 1 of kt=2 -> R7"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit)
            { reCtrlSigs = take 1 (reCtrlSigs (rcEvidence wit))
            }
        (Left R7QuorumUnsatisfied)
    , sc
        "r7_below_weighted"
        "below weighted threshold: 2 of 3 quarters -> R7"
        ctx0
        (rcDatum wgt)
        funded
        (rcEvidence wgt)
            { reCtrlSigs = drop 1 (reCtrlSigs (rcEvidence wgt))
            }
        (Left R7QuorumUnsatisfied)
    , sc
        "r7_dup_index"
        "duplicated index does not stack -> R7"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit)
            { reCtrlSigs =
                replicate 2 (first1 (reCtrlSigs (rcEvidence wit)))
            }
        (Left R7QuorumUnsatisfied)
    , sc
        "r7_attacker_signed"
        "attacker-signed message over victim keys -> R7"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit)
            { reCtrlSigs = signAll ctx0 (rcAttackers wit) (rcDatum wit)
            }
        (Left R7QuorumUnsatisfied)
    , sc
        "r7_crossed_network"
        "crossed network_id (sigs for network 0) -> R7"
        ctxNet
        (rcDatum wit)
        funded
        (rcEvidence wit)
        (Left R7QuorumUnsatisfied)
    , sc
        "r7_crossed_policy"
        "crossed checkpoint policy (sigs for 0xCC..) -> R7"
        ctxPol
        (rcDatum wit)
        funded
        (rcEvidence wit)
        (Left R7QuorumUnsatisfied)
    , sc
        "r8_deposit_short"
        "one lovelace short of min_ada + d_reg -> R8"
        ctx0
        (rcDatum wit)
        (boundary - 1)
        (rcEvidence wit)
        (Left R8DepositBelowMinimum)
    , sc
        "mis_off_i_shift"
        "misdirection: off_i shifted by one -> E2"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffI = reOffI (rcEvidence wit) + 1}
        (Left E2AidMismatch)
    , let k0 = first1 (reOffK (rcEvidence wit))
       in sc
            "mis_overlap_k"
            "misdirection: overlapping spans off_k[1]=off_k[0]+1 -> E4"
            ctx0
            (rcDatum wit)
            funded
            (rcEvidence wit){reOffK = [k0, k0 + 1]}
            (Left E4CurKeysMismatch)
    , sc
        "mis_k_into_n"
        "misdirection: off_k pointed into n (D vs E code) -> E4"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffK = reOffN (rcEvidence wit)}
        (Left E4CurKeysMismatch)
    , sc
        "mis_k_into_b"
        "misdirection: off_k pointed into b (D vs B code) -> E4"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffK = take 2 (reOffB (rcEvidence wit))}
        (Left E4CurKeysMismatch)
    , sc
        "mis_i_at_k"
        "misdirection: off_i pointed at a k entry (E vs D code) -> E2"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffI = first1 (reOffK (rcEvidence wit))}
        (Left E2AidMismatch)
    , sc
        "mis_b_at_k"
        "misdirection: off_b pointed at k entries (B vs D code) -> E8"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit)
            { reOffB =
                reOffK (rcEvidence wit)
                    <> drop 2 (reOffB (rcEvidence wit))
            }
        (Left E8WitnessesMismatch)
    , sc
        "mis_trunc_i"
        "misdirection: off_i at the byte tail (truncated) -> E2"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffI = BS.length (rcRaw wit) - 10}
        (Left E2AidMismatch)
    , let k0 = first1 (reOffK (rcEvidence wit))
       in sc
            "mis_trunc_k"
            "misdirection: last off_k at the tail (truncated) -> E4"
            ctx0
            (rcDatum wit)
            funded
            (rcEvidence wit)
                { reOffK = [k0, BS.length (rcRaw wit) - 20]
                }
            (Left E4CurKeysMismatch)
    , sc
        "mis_neg_i"
        "misdirection: negative off_i -> E2"
        ctx0
        (rcDatum wit)
        funded
        (rcEvidence wit){reOffI = -1}
        (Left E2AidMismatch)
    , let k0raw = first1 (cdCurKeys (rcDatum wit))
          k0off = first1 (reOffK (rcEvidence wit))
          d = (rcDatum wit){cdCurKeys = [k0raw, k0raw]}
       in sc
            "mis_dup_k"
            "misdirection: duplicated offsets duplicate the key -> R4 F18"
            ctx0
            d
            funded
            (rcEvidence wit)
                { reOffK = [k0off, k0off]
                , reCtrlSigs = signAll ctx0 (rcSigners wit) d
                }
            ( Left
                ( R4InceptionInvalid
                    ( InceptionIllFormed
                        (ThresholdIllFormed DuplicateKey)
                    )
                )
            )
    ]
  where
    sc = Scenario

-- | Total head for fixture lists the bundle guarantees non-empty.
first1 :: [a] -> a
first1 (x : _) = x
first1 [] = error "fixture list unexpectedly empty"

-- | Flip one bit of the first entry (a 32-byte-preserving mutation).
flipFirst :: [ByteString] -> [ByteString]
flipFirst [] = []
flipFirst (x : xs) = BS.cons (255 - BS.head x) (BS.tail x) : xs

-- ---------------------------------------------------------
-- Fixture decoding helpers (mirror GenEnforcementVectors)
-- ---------------------------------------------------------

sigList :: Value -> Text -> Either String [(Int, ByteString)]
sigList fx key = do
    arr <- arrayField fx key
    traverse one arr
  where
    one entry = do
        idx <- intField entry "index"
        sig <- decodeHex =<< textField entry "sig_hex"
        pure (fromInteger idx, sig)

-- | The exported seed hexes of @signer_seeds.<branch>@.
seedList :: Value -> Text -> Either String [ByteString]
seedList seeds branch = do
    entries <- arrayField seeds branch
    traverse (\e -> decodeHex =<< textField e "seed_hex") entries

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
    maybe
        (Left ("malformed integer: " <> T.unpack t))
        Right
        (readMaybe (T.unpack t))

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

intArrayField :: Value -> Text -> Either String [Integer]
intArrayField value k = do
    elems <- arrayField value k
    traverse asInt elems
  where
    asInt (Number s) = Right (truncate s)
    asInt _ = Left (T.unpack k <> ": element is not an integer")

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

render :: RegCase -> RegCase -> [Scenario] -> String
render wit wgt scenarios =
    header <> "\n" <> goldens <> "\n" <> concatMap renderScenario scenarios
  where
    header =
        unlines
            [ "//// Auto-generated Aiken registration vectors for #114 — DO NOT EDIT."
            , "////"
            , "//// Regenerate with `just gen-registration-vectors` (runs"
            , "//// offchain/app/GenRegistrationVectors.hs over the committed keripy"
            , "//// registration.json). Each scenario is the deployment context, genesis"
            , "//// datum, lovelace, evidence, and verdict of one S2 RegistrationSpec"
            , "//// family member; the generator asserts the Haskell predicate returns"
            , "//// each recorded verdict before emitting, and registration_tests.ak"
            , "//// asserts registration_predicate reproduces them one-for-one (verdict"
            , "//// parity) plus the preimage/proof-name/re-spelling/qb64 byte goldens."
            , "//// `just check-registration-vectors` forbids drift."
            , ""
            , "use cardano_keri/checkpoint/datum.{CheckpointDatumV1, ThresholdIllFormed}"
            , "use cardano_keri/checkpoint/message.{InceptionIllFormed, InceptionNativeSnNonZero}"
            , "use cardano_keri/checkpoint/registration.{"
            , "  DeploymentContext, E1EventTypeMismatch, E2AidMismatch, E3SequenceMismatch,"
            , "  E4CurKeysMismatch, E5CurThresholdMismatch, E6NextKeysMismatch,"
            , "  E7NextThresholdMismatch, E8WitnessesMismatch, E9ToadMismatch,"
            , "  R3GenesisDatumMismatch, R4InceptionInvalid, R7QuorumUnsatisfied,"
            , "  R8DepositBelowMinimum, RegistrationEvidence, RegistrationInvalid,"
            , "  RegistrationValid, RegistrationVerdict,"
            , "}"
            , "use cardano_keri/checkpoint/threshold.{DuplicateKey, Unweighted, Weight, Weighted}"
            ]
    goldens =
        unlines
            [ "/// reg_witnessed reconstructed InceptionMessage canonical-CBOR"
            , "/// preimage under ctx0 (the R7 signature target; byte-parity golden)"
            , "pub const witnessed_preimage: ByteArray ="
            , "  " <> hexLit (preimageOf wit)
            , ""
            , "/// reg_weighted reconstructed-message preimage under ctx0"
            , "pub const weighted_preimage: ByteArray ="
            , "  " <> hexLit (preimageOf wgt)
            , ""
            , "/// blake2b_256(reg_witnessed bytes ‖ aid) — the R5 proof-token name"
            , "pub const witnessed_proof_name: ByteArray ="
            , "  " <> hexLit (proofNameOf wit)
            , ""
            , "/// blake2b_256(reg_weighted bytes ‖ aid)"
            , "pub const weighted_proof_name: ByteArray ="
            , "  " <> hexLit (proofNameOf wgt)
            , ""
            , "/// The reg_weighted kt canonical re-spelling (the E5 expected bytes)"
            , "pub const weighted_kt_respell: ByteArray ="
            , "  " <> hexLit (respellThreshold (cdCurThreshold (rcDatum wgt)))
            , ""
            , "/// respellHex goldens: (n, keripy {:x} spelling bytes)"
            , "pub const respell_hex_golden: List<(Int, ByteArray)> ="
            , "  " <> respellHexGolden
            , ""
            , "/// (raw witness verkey, its B-code qb64) for every reg_witnessed b entry"
            , "pub const witnessed_witness_qb64: List<(ByteArray, ByteArray)> ="
            , "  " <> witnessQb64Golden
            ]
    preimageOf c = canonicalCbor (registrationMessage ctx0 (rcDatum c))
    proofNameOf c = proofTokenName (rcRaw c) (cdCesrAid (rcDatum c))
    respellHexGolden =
        "["
            <> intercalate
                ", "
                [ "(" <> show n <> ", " <> hexLit (respellHex n) <> ")"
                | n <- [0, 2, 10, 26 :: Integer]
                ]
            <> "]"
    witnessQb64Golden =
        "["
            <> intercalate
                ", "
                [ "(" <> hexLit w <> ", " <> hexLit (qb64WitnessVerkey w) <> ")"
                | w <- cdWitnesses (rcDatum wit)
                ]
            <> "]"

renderScenario :: Scenario -> String
renderScenario s =
    unlines
        [ "/// " <> scDoc s
        , "pub const " <> n <> "_ctx: DeploymentContext = " <> renderCtx (scCtx s)
        , ""
        , "pub const "
            <> n
            <> "_datum: CheckpointDatumV1 = "
            <> renderDatum (scDatum s)
        , ""
        , "pub const " <> n <> "_lovelace: Int = " <> show (scLovelace s)
        , ""
        , "pub const "
            <> n
            <> "_evidence: RegistrationEvidence = "
            <> renderEvidence (scEvidence s)
        , ""
        , "pub const "
            <> n
            <> "_verdict: RegistrationVerdict = "
            <> renderVerdict (scExpected s)
        , ""
        ]
  where
    n = scName s

renderCtx :: DeploymentContext -> String
renderCtx ctx =
    "DeploymentContext { "
        <> intercalate
            ", "
            [ "network_id: " <> show (dcNetworkId ctx)
            , "checkpoint_policy_id: " <> hexLit (dcCheckpointPolicyId ctx)
            , "min_ada: " <> show (dcMinAda ctx)
            , "d_reg: " <> show (dcDReg ctx)
            ]
        <> " }"

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

renderEvidence :: RegistrationEvidence -> String
renderEvidence e =
    "RegistrationEvidence { "
        <> intercalate
            ", "
            [ "event_bytes: " <> hexLit (reEventBytes e)
            , "off_t: " <> show (reOffT e)
            , "off_i: " <> show (reOffI e)
            , "off_s: " <> show (reOffS e)
            , "off_k: " <> intList (reOffK e)
            , "off_kt: " <> show (reOffKt e)
            , "off_n: " <> intList (reOffN e)
            , "off_nt: " <> show (reOffNt e)
            , "off_b: " <> intList (reOffB e)
            , "off_bt: " <> show (reOffBt e)
            , "ctrl_sigs: " <> sigLits (reCtrlSigs e)
            ]
        <> " }"

renderVerdict :: Either RegistrationError () -> String
renderVerdict (Right ()) = "RegistrationValid"
renderVerdict (Left e) =
    "RegistrationInvalid(" <> renderError e <> ")"

renderError :: RegistrationError -> String
renderError = \case
    R3GenesisDatumMismatch -> "R3GenesisDatumMismatch"
    R4InceptionInvalid ie ->
        "R4InceptionInvalid(" <> renderInceptionError ie <> ")"
    E1EventTypeMismatch -> "E1EventTypeMismatch"
    E2AidMismatch -> "E2AidMismatch"
    E3SequenceMismatch -> "E3SequenceMismatch"
    E4CurKeysMismatch -> "E4CurKeysMismatch"
    E5CurThresholdMismatch -> "E5CurThresholdMismatch"
    E6NextKeysMismatch -> "E6NextKeysMismatch"
    E7NextThresholdMismatch -> "E7NextThresholdMismatch"
    E8WitnessesMismatch -> "E8WitnessesMismatch"
    E9ToadMismatch -> "E9ToadMismatch"
    R7QuorumUnsatisfied -> "R7QuorumUnsatisfied"
    R8DepositBelowMinimum -> "R8DepositBelowMinimum"

renderInceptionError :: InceptionError -> String
renderInceptionError = \case
    InceptionDomainMismatch -> "InceptionDomainMismatch"
    DelegatedInceptionRejected -> "DelegatedInceptionRejected"
    InceptionAidWidth -> "InceptionAidWidth"
    InceptionAssetMismatch -> "InceptionAssetMismatch"
    InceptionNativeSnNonZero -> "InceptionNativeSnNonZero"
    InceptionIllFormed de ->
        "InceptionIllFormed(" <> renderDatumError de <> ")"

renderDatumError :: DatumError -> String
renderDatumError = \case
    CesrAidWidth -> "CesrAidWidth"
    ThresholdIllFormed te ->
        "ThresholdIllFormed(" <> renderThresholdError te <> ")"
    NextIllFormed te ->
        "NextIllFormed(" <> renderThresholdError te <> ")"
    WitnessWidth -> "WitnessWidth"
    DuplicateWitness -> "DuplicateWitness"
    ToadRange -> "ToadRange"

-- | Nullary constructor names are shared verbatim across languages.
renderThresholdError :: ThresholdError -> String
renderThresholdError = show

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

intList :: [Int] -> String
intList xs = "[" <> intercalate ", " (map show xs) <> "]"

sigLits :: [(Int, ByteString)] -> String
sigLits xs = "[" <> intercalate ", " (map one xs) <> "]"
  where
    one (i, s) = "(" <> show i <> ", " <> hexLit s <> ")"

hexLit :: ByteString -> String
hexLit b = "#\"" <> BC.unpack (convertToBase Base16 b) <> "\""
