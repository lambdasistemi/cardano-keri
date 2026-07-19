{- |
Module      : Main
Description : Advance vector generator (#115 S5) — fixtures -> Aiken

Reads the committed keripy advance bundle
(@offchain\/test\/keri-fixtures\/fixtures\/advance.json@) and emits a
self-contained Aiken module
(@onchain\/lib\/cardano_keri\/checkpoint\/advance_vectors.ak@) of
@pub const@ scenario tuples — the spent context, created (successor)
datum, 'AdvanceEvidence', and verdict — one per S4 'AdvanceSpec' family
member (the four honest fixture families, every AE1-AE10 axis, the
A-001 offset-misdirection family, controller-evidence negatives, delta
malformations, and the receipt-quorum negatives), plus the four
reconstructed-message preimage byte goldens the honest families check.

One computation feeds both languages: each scenario's verdict is the
Haskell 'advancePredicate' output, and the generator ASSERTS it equals
the family's declared expectation before emitting — a Haskell drift
breaks the generator run (and the drift check), never silently weakens
the Aiken suite. Controller signatures are produced here from the
bundle's exported @rotation_current@\/@inception_current@ seeds over the
reconstructed 'AdvanceMessage' canonical-CBOR preimage; witness receipts
are the bundle's own @rot_witness_receipts@ (already signed over
@event_raw@, O1). OFFLINE (no keripy) and deterministic (drift-checked).

Invocation: @gen-advance-vectors OUT_PATH [FIXTURES_DIR]@ (default
fixtures dir @test\/keri-fixtures\/fixtures@, resolved from the
offchain package root).
-}
module Main (main) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEventError (..),
    AdvanceEvidence (..),
    AdvancePredicateError (..),
    advancePredicate,
    reconstructAdvanceMessage,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    DatumError (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceError (..),
    AdvanceMessage,
    SpentCheckpoint (..),
    deriveAidAssetName,
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
import Data.Bifunctor (second)
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
-- Test spent-checkpoint plumbing (mirrors the S4 AdvanceSpec)
-- ---------------------------------------------------------

testNetwork :: Integer
testNetwork = 1

testPolicy :: ByteString
testPolicy = BS.replicate 28 0xCC

testSpentTxid :: ByteString
testSpentTxid = BS.replicate 32 0xD1

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
    fx <- load dir "advance.json"
    let w2 = orDie (loadAdvCase fx "adv_wit_2key")
        w7 = orDie (loadAdvCase fx "adv_wit_7key")
        keep = orDie (loadAdvCase fx "adv_keep")
        down = orDie (loadAdvCase fx "adv_downgrade")
        scenarios = buildScenarios w2 w7 keep down
    mapM_ assertVerdict scenarios
    let rendered = render w2 w7 keep down scenarios
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
    actual = advancePredicate (scSpent s) (scCreated s) (scEvidence s)

-- ---------------------------------------------------------
-- Fixture case (mirrors the S4 AdvanceSpec advCase)
-- ---------------------------------------------------------

-- | One advance sub-fixture, lifted into predicate inputs.
data AdvCase = AdvCase
    { acRaw :: ByteString
    , acSpent :: SpentCheckpoint
    , acCreated :: CheckpointDatumV1
    , acEvidence :: AdvanceEvidence
    , acNewSet :: [ByteString]
    , acOldWitnesses :: [ByteString]
    , acSurvivors :: [ByteString]
    , acRotSigners :: [SignKeyDSIGN Ed25519DSIGN]
    , acIcpSigners :: [SignKeyDSIGN Ed25519DSIGN]
    , acIcpKeys :: [ByteString]
    , acEventRawCtrlSigs :: [(Int, ByteString)]
    , acOldWitnessSigners :: [(ByteString, SignKeyDSIGN Ed25519DSIGN)]
    , acOffP :: Int
    , acOffD :: Int
    , acOffA :: Int
    }

-- | Build the 'AdvCase' of a sub-fixture.
loadAdvCase :: Value -> Text -> Either String AdvCase
loadAdvCase doc key = do
    sub <- field doc key
    icp <- field sub "icp"
    rot <- field sub "rot"
    icpKed <- field icp "ked"
    rotKed <- field rot "ked"
    raw <- decodeHex =<< textField rot "raw_hex"
    aid <- digestRaw =<< textField icpKed "i"
    icpKeys <- traverse verkeyRaw =<< textArrayField icpKed "k"
    oldWitnesses <- traverse verkeyRaw =<< textArrayField icpKed "b"
    icpNext <- traverse digestRaw =<< textArrayField icpKed "n"
    icpNextThr <- thresholdField icpKed "nt"
    cuts <- traverse verkeyRaw =<< textArrayField rotKed "br"
    adds <- traverse verkeyRaw =<< textArrayField rotKed "ba"
    rotKeys <- traverse verkeyRaw =<< textArrayField rotKed "k"
    rotThr <- thresholdField rotKed "kt"
    rotNext <- traverse digestRaw =<< textArrayField rotKed "n"
    rotNextThr <- thresholdField rotKed "nt"
    toad <- hexIntField rotKed "bt"
    offs <- field sub "offsets"
    offT <- off offs "t"
    offI <- off offs "i"
    offS <- off offs "s"
    offKt <- off offs "kt"
    offNt <- off offs "nt"
    offBt <- off offs "bt"
    offK <- offList offs "k"
    offN <- offList offs "n"
    offBr <- offList offs "br"
    offBa <- offList offs "ba"
    seeds <- field sub "signer_seeds"
    rotSigners <- map mkSigner <$> seedList seeds "rotation_current"
    icpSigners <- map mkSigner <$> seedList seeds "inception_current"
    oldWitSigners <- map mkSigner <$> seedList seeds "witness_outgoing"
    eventRawCtrlSigs <- sigList sub "rot_sigs"
    honestReceipts <- sigList sub "rot_witness_receipts"
    offP <- off offs "p"
    saidText <- textField rot "said"
    offD <-
        note
            "d offset not found in raw bytes"
            (findSubstring (TE.encodeUtf8 saidText) raw)
    offA <-
        note
            "a offset not found in raw bytes"
            (fmap (+ 5) (findSubstring "\"a\":[" raw))
    let survivors = filter (`notElem` cuts) oldWitnesses
        newSet = survivors <> adds
        asset = deriveAidAssetName aid
        sc =
            SpentCheckpoint
                { scNetworkId = testNetwork
                , scPolicyId = testPolicy
                , scAidAssetName = asset
                , scTxid = testSpentTxid
                , scIndex = 0
                , scCesrAid = aid
                , scWitnesses = oldWitnesses
                , scNextKeys = icpNext
                , scNextThreshold = icpNextThr
                , scSeq = 0
                , scNativeSn = 0
                }
        created =
            CheckpointDatumV1
                { cdCesrAid = aid
                , cdCurKeys = rotKeys
                , cdCurThreshold = rotThr
                , cdNextKeys = rotNext
                , cdNextThreshold = rotNextThr
                , cdWitnesses = newSet
                , cdToad = toad
                , cdSeq = 1
                , cdNativeSn = 1
                }
        msg = reconstructAdvanceMessage sc created cuts adds
        evidence =
            AdvanceEvidence
                { aeEventBytes = raw
                , aeOffT = offT
                , aeOffI = offI
                , aeOffS = offS
                , aeOffK = offK
                , aeOffKt = offKt
                , aeOffN = offN
                , aeOffNt = offNt
                , aeOffBr = offBr
                , aeOffBa = offBa
                , aeOffBt = offBt
                , aeWitCut = cuts
                , aeWitAdd = adds
                , aeCtrlSigs = signAll msg rotSigners
                , aeWitReceipts = honestReceipts
                }
    pure
        AdvCase
            { acRaw = raw
            , acSpent = sc
            , acCreated = created
            , acEvidence = evidence
            , acNewSet = newSet
            , acOldWitnesses = oldWitnesses
            , acSurvivors = survivors
            , acRotSigners = rotSigners
            , acIcpSigners = icpSigners
            , acIcpKeys = icpKeys
            , acEventRawCtrlSigs = eventRawCtrlSigs
            , acOldWitnessSigners = zip oldWitnesses oldWitSigners
            , acOffP = offP
            , acOffD = offD
            , acOffA = offA
            }
  where
    field v k = note (k <> " missing") (lookupKey k v)
    off o f = fromIntegral <$> intField o f
    offList o f = map fromIntegral <$> intArrayField o f

-- | An Ed25519 signing key from a 32-byte exported seed.
mkSigner :: ByteString -> SignKeyDSIGN Ed25519DSIGN
mkSigner = genKeyDSIGN . mkSeedFromBytes

-- | Raw 64-byte Ed25519 signature over a message.
signOver :: SignKeyDSIGN Ed25519DSIGN -> ByteString -> ByteString
signOver sk msg = rawSerialiseSigDSIGN (signDSIGN () msg sk)

-- | Indexed signatures of all given signers over an 'AdvanceMessage' preimage.
signAll ::
    AdvanceMessage -> [SignKeyDSIGN Ed25519DSIGN] -> [(Int, ByteString)]
signAll msg signers =
    [(j, signOver sk preimage) | (j, sk) <- zip [0 ..] signers]
  where
    preimage = canonicalCbor msg

-- | The signer of a known raw verkey in an @(verkey, signer)@ association.
signerFor ::
    [(ByteString, SignKeyDSIGN Ed25519DSIGN)] ->
    ByteString ->
    SignKeyDSIGN Ed25519DSIGN
signerFor assocs key = case lookup key assocs of
    Just sk -> sk
    Nothing -> error "signerFor: key not found in fixture seed export"

-- | Flip the first byte of a signature (a corrupted-but-shaped mutation).
flipByte :: ByteString -> ByteString
flipByte bs = case BS.uncons bs of
    Just (b, rest) -> BS.cons (255 - b) rest
    Nothing -> bs

-- | Total head for fixture lists the bundle guarantees non-empty.
first1 :: [a] -> a
first1 (x : _) = x
first1 [] = error "fixture list unexpectedly empty"

-- | The offset of the first occurrence of @needle@ in @haystack@, if any.
findSubstring :: ByteString -> ByteString -> Maybe Int
findSubstring needle haystack = go 0
  where
    n = BS.length needle
    go i
        | i + n > BS.length haystack = Nothing
        | needle `BS.isPrefixOf` BS.drop i haystack = Just i
        | otherwise = go (i + 1)

-- ---------------------------------------------------------
-- Scenarios (mirror the S4 AdvanceSpec families)
-- ---------------------------------------------------------

-- | One emitted vector: inputs + the declared-and-asserted verdict.
data Scenario = Scenario
    { scName :: String
    , scDoc :: String
    , scSpent :: SpentCheckpoint
    , scCreated :: CheckpointDatumV1
    , scEvidence :: AdvanceEvidence
    , scExpected :: Either AdvancePredicateError ()
    }

{- | Every S4 family member as a deterministic construction over the
honest fixture cases — positives, the AE1-AE10 event-binding
negatives, the A-001 offset-misdirection family, controller-evidence
negatives, W1\/W2\/eq7\/eq8 delta malformations, and the V7
receipt-quorum negatives. Constructions mirror the S4 hspec bodies
exactly.
-}
buildScenarios :: AdvCase -> AdvCase -> AdvCase -> AdvCase -> [Scenario]
buildScenarios w2 w7 keep down =
    [ -- ---------------------------------------------------------
      -- positives: honest full-evidence packages
      -- ---------------------------------------------------------
      sc
        "pos_adv_wit_2key"
        "adv_wit_2key: witnessed cut+add accepted"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2)
        (Right ())
    , sc
        "pos_adv_wit_7key"
        "adv_wit_7key: GLEIF-scale witnessed cut+add accepted"
        (acSpent w7)
        (acCreated w7)
        (acEvidence w7)
        (Right ())
    , sc
        "pos_adv_keep"
        "adv_keep: no-delta rotation accepted; witnesses unchanged"
        (acSpent keep)
        (acCreated keep)
        (acEvidence keep)
        (Right ())
    , sc
        "pos_adv_downgrade"
        "adv_downgrade: cuts every witness; toad=0, zero receipts"
        (acSpent down)
        (acCreated down)
        (acEvidence down)
        (Right ())
    , -- ---------------------------------------------------------
      -- V6: AE1-AE10 event-binding negatives (one per axis)
      -- ---------------------------------------------------------
      sc
        "ae1_off_t_at_i"
        "AE1: off_t pointed at i -> AE1EventTypeMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffT = aeOffI (acEvidence w2)}
        (Left (AdvEventBinding AE1EventTypeMismatch))
    , sc
        "ae2_off_i_shift"
        "AE2: off_i shifted by one -> AE2AidMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffI = aeOffI (acEvidence w2) + 1}
        (Left (AdvEventBinding AE2AidMismatch))
    , sc
        "ae3_off_s_at_t"
        "AE3: off_s pointed at t -> AE3SequenceMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffS = aeOffT (acEvidence w2)}
        (Left (AdvEventBinding AE3SequenceMismatch))
    , let k0 = first1 (aeOffK (acEvidence w2))
       in sc
            "ae4_overlap_k"
            "AE4: overlapping off_k spans -> AE4CurKeysMismatch"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeOffK = [k0, k0 + 1]}
            (Left (AdvEventBinding AE4CurKeysMismatch))
    , sc
        "ae5_off_kt_at_bt"
        "AE5: off_kt pointed at bt -> AE5CurThresholdMismatch"
        (acSpent w7)
        (acCreated w7)
        (acEvidence w7){aeOffKt = aeOffBt (acEvidence w7)}
        (Left (AdvEventBinding AE5CurThresholdMismatch))
    , sc
        "ae6_off_n_at_k"
        "AE6: off_n pointed at off_k (E vs D code) -> AE6NextKeysMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffN = aeOffK (acEvidence w2)}
        (Left (AdvEventBinding AE6NextKeysMismatch))
    , sc
        "ae7_off_nt_at_kt"
        "AE7: off_nt pointed at kt -> AE7NextThresholdMismatch"
        (acSpent w7)
        (acCreated w7)
        (acEvidence w7){aeOffNt = aeOffKt (acEvidence w7)}
        (Left (AdvEventBinding AE7NextThresholdMismatch))
    , sc
        "ae8_off_br_at_ba"
        "AE8: off_br pointed at ba -> AE8WitCutMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffBr = aeOffBa (acEvidence w2)}
        (Left (AdvEventBinding AE8WitCutMismatch))
    , sc
        "ae9_off_ba_at_br"
        "AE9: off_ba pointed at br -> AE9WitAddMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffBa = aeOffBr (acEvidence w2)}
        (Left (AdvEventBinding AE9WitAddMismatch))
    , sc
        "ae10_off_bt_at_kt"
        "AE10: off_bt pointed at kt -> AE10ToadMismatch"
        (acSpent w7)
        (acCreated w7)
        (acEvidence w7){aeOffBt = aeOffKt (acEvidence w7)}
        (Left (AdvEventBinding AE10ToadMismatch))
    , -- ---------------------------------------------------------
      -- A-001 condition 1: the offset-misdirection family
      -- ---------------------------------------------------------
      sc
        "mis_trunc_i"
        "truncated slice: off_i at the byte tail -> AE2"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffI = BS.length (acRaw w2) - 10}
        (Left (AdvEventBinding AE2AidMismatch))
    , sc
        "mis_neg_i"
        "negative offset rejected -> AE2"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffI = -1}
        (Left (AdvEventBinding AE2AidMismatch))
    , let k0 = first1 (aeOffK (acEvidence w2))
       in sc
            "mis_dup_k"
            "duplicated off_k entries -> AE4"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeOffK = [k0, k0]}
            (Left (AdvEventBinding AE4CurKeysMismatch))
    , sc
        "mis_br_into_k"
        "off_br pointed into off_k (B vs D code) -> AE8"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffBr = take 1 (aeOffK (acEvidence w2))}
        (Left (AdvEventBinding AE8WitCutMismatch))
    , sc
        "mis_short_k"
        "shortened off_k (1 of 2) -> AE4CurKeysMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffK = take 1 (aeOffK (acEvidence w2))}
        (Left (AdvEventBinding AE4CurKeysMismatch))
    , sc
        "mis_short_n"
        "shortened off_n (1 of 2) -> AE6NextKeysMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffN = take 1 (aeOffN (acEvidence w2))}
        (Left (AdvEventBinding AE6NextKeysMismatch))
    , sc
        "mis_empty_br"
        "emptied off_br (0 of 1) -> AE8WitCutMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffBr = []}
        (Left (AdvEventBinding AE8WitCutMismatch))
    , sc
        "mis_empty_ba"
        "emptied off_ba (0 of 1) -> AE9WitAddMismatch"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffBa = []}
        (Left (AdvEventBinding AE9WitAddMismatch))
    , sc
        "mis_t_into_p"
        "off_t redirected into the unchecked p region -> AE1"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffT = acOffP w2}
        (Left (AdvEventBinding AE1EventTypeMismatch))
    , sc
        "mis_kt_into_d"
        "off_kt redirected into the unchecked d region -> AE5"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffKt = acOffD w2}
        (Left (AdvEventBinding AE5CurThresholdMismatch))
    , sc
        "mis_bt_into_a"
        "off_bt redirected into the unchecked a region -> AE10"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeOffBt = acOffA w2}
        (Left (AdvEventBinding AE10ToadMismatch))
    , -- ---------------------------------------------------------
      -- V5: controller-evidence negatives (folded into eq6)
      -- ---------------------------------------------------------
      let (_, sig) = first1 (aeCtrlSigs (acEvidence w2))
       in sc
            "ctrl_bad_index"
            "bad index: ctrl_sigs index out of range -> Eq6CurrentQuorumUnsatisfied"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeCtrlSigs = [(99, sig)]}
            (Left (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied))
    , sc
        "ctrl_wrong_preimage"
        "wrong preimage: KERI event_raw sigs MUST fail -> Eq6CurrentQuorumUnsatisfied"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeCtrlSigs = acEventRawCtrlSigs w2}
        (Left (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied))
    , sc
        "ctrl_below_threshold"
        "below threshold: 1 of kt=2 -> Eq6CurrentQuorumUnsatisfied"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeCtrlSigs = take 1 (aeCtrlSigs (acEvidence w2))}
        (Left (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied))
    , let msg =
            reconstructAdvanceMessage
                (acSpent w2)
                (acCreated w2)
                (aeWitCut (acEvidence w2))
                (aeWitAdd (acEvidence w2))
          stolen = signAll msg (acIcpSigners w2)
       in sc
            "ctrl_stolen_quorum"
            "stolen full spent-current quorum (icp keys) cannot rotate -> Eq6CurrentQuorumUnsatisfied"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeCtrlSigs = stolen}
            (Left (AdvMessageInvalid Eq6CurrentQuorumUnsatisfied))
    , let substituted = (acCreated w2){cdCurKeys = acIcpKeys w2}
          msg =
            reconstructAdvanceMessage
                (acSpent w2)
                substituted
                (aeWitCut (acEvidence w2))
                (aeWitAdd (acEvidence w2))
          sigs = signAll msg (acIcpSigners w2)
       in sc
            "ctrl_substituted_successor"
            "substituted successor evidence (uncommitted board) -> Eq6PriorNextQuorumUnsatisfied"
            (acSpent w2)
            substituted
            (acEvidence w2){aeCtrlSigs = sigs}
            (Left (AdvMessageInvalid Eq6PriorNextQuorumUnsatisfied))
    , -- ---------------------------------------------------------
      -- V4 delta malformations (W1/W2/eq7/eq8)
      -- ---------------------------------------------------------
      let cut = first1 (aeWitCut (acEvidence w2))
       in sc
            "w1_dup_cut"
            "duplicate cut -> EqW1CutInvalid"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitCut = [cut, cut]}
            (Left (AdvMessageInvalid EqW1CutInvalid))
    , sc
        "w1_cut_non_member"
        "cut of a non-member witness -> EqW1CutInvalid"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeWitCut = aeWitAdd (acEvidence w2)}
        (Left (AdvMessageInvalid EqW1CutInvalid))
    , let add = first1 (aeWitAdd (acEvidence w2))
       in sc
            "w2_dup_add"
            "duplicate add -> EqW2AddInvalid"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitAdd = [add, add]}
            (Left (AdvMessageInvalid EqW2AddInvalid))
    , let survivor = first1 (acSurvivors w2)
       in sc
            "w2_add_present"
            "add already present among survivors -> EqW2AddInvalid"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitAdd = [survivor]}
            (Left (AdvMessageInvalid EqW2AddInvalid))
    , sc
        "w2_cut_add_overlap"
        "cut/add overlap -> EqW2AddInvalid"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeWitAdd = aeWitCut (acEvidence w2)}
        (Left (AdvMessageInvalid EqW2AddInvalid))
    , sc
        "eq7_derived_set_mismatch"
        "derived-set mismatch (datum keeps outgoing set) -> Eq7CreatedStateMismatch"
        (acSpent w2)
        (acCreated w2){cdWitnesses = acOldWitnesses w2}
        (acEvidence w2)
        (Left (AdvMessageInvalid Eq7CreatedStateMismatch))
    , let wrongOrder = aeWitAdd (acEvidence w2) <> acSurvivors w2
       in sc
            "eq7_wrong_order"
            "wrong survivor order (adds before survivors) -> Eq7CreatedStateMismatch"
            (acSpent w2)
            (acCreated w2){cdWitnesses = wrongOrder}
            (acEvidence w2)
            (Left (AdvMessageInvalid Eq7CreatedStateMismatch))
    , let badToad = toInteger (length (acNewSet w2)) + 5
          created = (acCreated w2){cdToad = badToad}
          msg =
            reconstructAdvanceMessage
                (acSpent w2)
                created
                (aeWitCut (acEvidence w2))
                (aeWitAdd (acEvidence w2))
          sigs = signAll msg (acRotSigners w2)
       in sc
            "eq8_toad_out_of_bounds"
            "toad out of bounds -> Eq8CreatedIllFormed ToadRange"
            (acSpent w2)
            created
            (acEvidence w2){aeCtrlSigs = sigs}
            (Left (AdvMessageInvalid (Eq8CreatedIllFormed ToadRange)))
    , -- ---------------------------------------------------------
      -- V7: incoming-set witness receipt-quorum negatives
      -- ---------------------------------------------------------
      sc
        "v7_receipt_free"
        "receipt-free advance rejected (toad=2, no receipts)"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2){aeWitReceipts = []}
        (Left AdvReceiptQuorumUnsatisfied)
    , sc
        "v7_below_toad"
        "below-toad receipts: 1 of 2 rejected"
        (acSpent w2)
        (acCreated w2)
        (acEvidence w2)
            { aeWitReceipts = take 1 (aeWitReceipts (acEvidence w2))
            }
        (Left AdvReceiptQuorumUnsatisfied)
    , let r0 = first1 (aeWitReceipts (acEvidence w2))
       in sc
            "v7_bad_index"
            "bad/out-of-range receipt index does not count"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitReceipts = [r0, (99, snd r0)]}
            (Left AdvReceiptQuorumUnsatisfied)
    , let receipts = aeWitReceipts (acEvidence w2)
          r0 = first1 receipts
          r1 = receipts !! 1
          corrupted = second flipByte r1
       in sc
            "v7_bad_sig"
            "bad receipt signature does not count"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitReceipts = [r0, corrupted]}
            (Left AdvReceiptQuorumUnsatisfied)
    , let r0 = first1 (aeWitReceipts (acEvidence w2))
       in sc
            "v7_dup_index"
            "duplicate receipt index counts once"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitReceipts = [r0, r0]}
            (Left AdvReceiptQuorumUnsatisfied)
    , let receipts = aeWitReceipts (acEvidence w2)
          r0 = first1 receipts
          r1 = receipts !! 1
          relabeled = (1, snd r0)
       in sc
            "v7_wrong_member"
            "wrong-member index: a valid sig at a different in-range index does not count"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitReceipts = [relabeled, r1]}
            (Left AdvReceiptQuorumUnsatisfied)
    , let cutKey = first1 (aeWitCut (acEvidence w2))
          cutSigner = signerFor (acOldWitnessSigners w2) cutKey
          cutSig = signOver cutSigner (acRaw w2)
          attempts =
            [ (idx, cutSig)
            | idx <- [0 .. length (acNewSet w2) - 1]
            ]
       in sc
            "v7_cut_witness_receipt"
            "receipt by a cut witness never counts at any index"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitReceipts = attempts}
            (Left AdvReceiptQuorumUnsatisfied)
    , let attempts =
            [ (idx, signOver sk (acRaw w2))
            | (idx, (_, sk)) <- zip [0 ..] (acOldWitnessSigners w2)
            ]
       in sc
            "v7_outgoing_only_quorum"
            "outgoing-only quorum at old board positions rejected"
            (acSpent w2)
            (acCreated w2)
            (acEvidence w2){aeWitReceipts = attempts}
            (Left AdvReceiptQuorumUnsatisfied)
    , sc
        "v7_downgrade_nonempty_receipts"
        "adv_downgrade: any supplied receipt entry rejects (toad=0 requires none)"
        (acSpent down)
        (acCreated down)
        (acEvidence down){aeWitReceipts = [(0, BS.replicate 64 0)]}
        (Left AdvReceiptQuorumUnsatisfied)
    ]
  where
    sc = Scenario

-- ---------------------------------------------------------
-- Fixture decoding helpers (mirror GenRegistrationVectors)
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
    fld <- lookupKey k value
    case fld of
        String t -> Just t
        _ -> Nothing

intField :: Value -> Text -> Either String Integer
intField value k = note (k <> " missing or not an integer") $ do
    fld <- lookupKey k value
    case fld of
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
    fld <- lookupKey k value
    case fld of
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

render :: AdvCase -> AdvCase -> AdvCase -> AdvCase -> [Scenario] -> String
render w2 w7 keep down scenarios =
    header <> "\n" <> goldens <> "\n" <> concatMap renderScenario scenarios
  where
    header =
        unlines
            [ "//// Auto-generated Aiken advance vectors for #115 — DO NOT EDIT."
            , "////"
            , "//// Regenerate with `just gen-advance-vectors` (runs"
            , "//// offchain/app/GenAdvanceVectors.hs over the committed keripy"
            , "//// advance.json). Each scenario is the spent context, created"
            , "//// (successor) datum, evidence, and verdict of one S4 AdvanceSpec"
            , "//// family member; the generator asserts the Haskell predicate returns"
            , "//// each recorded verdict before emitting, and advance_tests.ak"
            , "//// asserts advance_predicate reproduces them one-for-one (verdict"
            , "//// parity) plus the reconstructed-message preimage byte goldens."
            , "//// `just check-advance-vectors` forbids drift."
            , ""
            , "use cardano_keri/checkpoint/advance.{"
            , "  AE1EventTypeMismatch, AE2AidMismatch, AE3SequenceMismatch,"
            , "  AE4CurKeysMismatch, AE5CurThresholdMismatch, AE6NextKeysMismatch,"
            , "  AE7NextThresholdMismatch, AE8WitCutMismatch, AE9WitAddMismatch,"
            , "  AE10ToadMismatch, AdvEventBinding, AdvMessageInvalid,"
            , "  AdvReceiptQuorumUnsatisfied, AdvanceEvidence, AdvancePredicateInvalid,"
            , "  AdvancePredicateValid, AdvancePredicateVerdict,"
            , "}"
            , "use cardano_keri/checkpoint/datum.{CheckpointDatumV1, ToadRange}"
            , "use cardano_keri/checkpoint/message.{"
            , "  EqW1CutInvalid, EqW2AddInvalid, Eq6CurrentQuorumUnsatisfied,"
            , "  Eq6PriorNextQuorumUnsatisfied, Eq7CreatedStateMismatch,"
            , "  Eq8CreatedIllFormed, SpentCheckpoint,"
            , "}"
            , "use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}"
            ]
    goldens =
        unlines
            [ "/// adv_wit_2key reconstructed AdvanceMessage canonical-CBOR preimage"
            , "/// (the V5 controller-signature target; byte-parity golden)"
            , "pub const pos_adv_wit_2key_preimage: ByteArray ="
            , "  " <> hexLit (preimageOf w2)
            , ""
            , "/// adv_wit_7key reconstructed-message preimage"
            , "pub const pos_adv_wit_7key_preimage: ByteArray ="
            , "  " <> hexLit (preimageOf w7)
            , ""
            , "/// adv_keep reconstructed-message preimage"
            , "pub const pos_adv_keep_preimage: ByteArray ="
            , "  " <> hexLit (preimageOf keep)
            , ""
            , "/// adv_downgrade reconstructed-message preimage"
            , "pub const pos_adv_downgrade_preimage: ByteArray ="
            , "  " <> hexLit (preimageOf down)
            ]
    preimageOf c =
        canonicalCbor
            ( reconstructAdvanceMessage
                (acSpent c)
                (acCreated c)
                (aeWitCut (acEvidence c))
                (aeWitAdd (acEvidence c))
            )

renderScenario :: Scenario -> String
renderScenario s =
    unlines
        [ "/// " <> scDoc s
        , "pub const " <> n <> "_spent: SpentCheckpoint = " <> renderSpent (scSpent s)
        , ""
        , "pub const "
            <> n
            <> "_created: CheckpointDatumV1 = "
            <> renderDatum (scCreated s)
        , ""
        , "pub const "
            <> n
            <> "_evidence: AdvanceEvidence = "
            <> renderEvidence (scEvidence s)
        , ""
        , "pub const "
            <> n
            <> "_verdict: AdvancePredicateVerdict = "
            <> renderVerdict (scExpected s)
        , ""
        ]
  where
    n = scName s

renderSpent :: SpentCheckpoint -> String
renderSpent s =
    "SpentCheckpoint { "
        <> intercalate
            ", "
            [ "network_id: " <> show (scNetworkId s)
            , "policy_id: " <> hexLit (scPolicyId s)
            , "aid_asset_name: " <> hexLit (scAidAssetName s)
            , "txid: " <> hexLit (scTxid s)
            , "index: " <> show (scIndex s)
            , "cesr_aid: " <> hexLit (scCesrAid s)
            , "witnesses: " <> byteList (scWitnesses s)
            , "next_keys: " <> byteList (scNextKeys s)
            , "next_threshold: " <> renderThreshold (scNextThreshold s)
            , "seq: " <> show (scSeq s)
            , "native_sn: " <> show (scNativeSn s)
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

renderEvidence :: AdvanceEvidence -> String
renderEvidence e =
    "AdvanceEvidence { "
        <> intercalate
            ", "
            [ "event_bytes: " <> hexLit (aeEventBytes e)
            , "off_t: " <> show (aeOffT e)
            , "off_i: " <> show (aeOffI e)
            , "off_s: " <> show (aeOffS e)
            , "off_k: " <> intList (aeOffK e)
            , "off_kt: " <> show (aeOffKt e)
            , "off_n: " <> intList (aeOffN e)
            , "off_nt: " <> show (aeOffNt e)
            , "off_br: " <> intList (aeOffBr e)
            , "off_ba: " <> intList (aeOffBa e)
            , "off_bt: " <> show (aeOffBt e)
            , "wit_cut: " <> byteList (aeWitCut e)
            , "wit_add: " <> byteList (aeWitAdd e)
            , "ctrl_sigs: " <> sigLits (aeCtrlSigs e)
            , "wit_receipts: " <> sigLits (aeWitReceipts e)
            ]
        <> " }"

renderVerdict :: Either AdvancePredicateError () -> String
renderVerdict (Right ()) = "AdvancePredicateValid"
renderVerdict (Left e) =
    "AdvancePredicateInvalid(" <> renderPredicateError e <> ")"

renderPredicateError :: AdvancePredicateError -> String
renderPredicateError = \case
    AdvMessageInvalid ae -> "AdvMessageInvalid(" <> renderAdvanceError ae <> ")"
    AdvEventBinding ee -> "AdvEventBinding(" <> renderAdvanceEventError ee <> ")"
    AdvReceiptQuorumUnsatisfied -> "AdvReceiptQuorumUnsatisfied"

renderAdvanceError :: AdvanceError -> String
renderAdvanceError = \case
    AdvanceDomainMismatch -> "AdvanceDomainMismatch"
    Eq1NetworkPolicyMismatch -> "Eq1NetworkPolicyMismatch"
    Eq2AssetOrAidMismatch -> "Eq2AssetOrAidMismatch"
    Eq3OutRefMismatch -> "Eq3OutRefMismatch"
    Eq4PriorMismatch -> "Eq4PriorMismatch"
    Eq5SequenceMismatch -> "Eq5SequenceMismatch"
    EqW1CutInvalid -> "EqW1CutInvalid"
    EqW2AddInvalid -> "EqW2AddInvalid"
    Eq6CurrentQuorumUnsatisfied -> "Eq6CurrentQuorumUnsatisfied"
    Eq6PriorNextQuorumUnsatisfied -> "Eq6PriorNextQuorumUnsatisfied"
    Eq7CreatedStateMismatch -> "Eq7CreatedStateMismatch"
    Eq8CreatedIllFormed de -> "Eq8CreatedIllFormed(" <> renderDatumError de <> ")"

renderAdvanceEventError :: AdvanceEventError -> String
renderAdvanceEventError = \case
    AE1EventTypeMismatch -> "AE1EventTypeMismatch"
    AE2AidMismatch -> "AE2AidMismatch"
    AE3SequenceMismatch -> "AE3SequenceMismatch"
    AE4CurKeysMismatch -> "AE4CurKeysMismatch"
    AE5CurThresholdMismatch -> "AE5CurThresholdMismatch"
    AE6NextKeysMismatch -> "AE6NextKeysMismatch"
    AE7NextThresholdMismatch -> "AE7NextThresholdMismatch"
    AE8WitCutMismatch -> "AE8WitCutMismatch"
    AE9WitAddMismatch -> "AE9WitAddMismatch"
    AE10ToadMismatch -> "AE10ToadMismatch"

renderDatumError :: DatumError -> String
renderDatumError = \case
    CesrAidWidth -> "CesrAidWidth"
    ThresholdIllFormed te -> "ThresholdIllFormed(" <> renderThresholdError te <> ")"
    NextIllFormed te -> "NextIllFormed(" <> renderThresholdError te <> ")"
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
