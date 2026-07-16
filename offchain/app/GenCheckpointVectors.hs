{- |
Module      : Main
Description : Shared golden\/negative vector generator for the #68 checkpoint contract

The single Haskell computation that produces every canonical byte string of the
frozen @CheckpointDatumV1@ wire contract, reusing the Slice-2\/3 codec modules
(@Cardano.KERI.AID.Checkpoint.{Threshold,Datum,Message}@) as the sole source of
truth — it never re-implements encoding.

@main@ writes a self-contained Aiken fixtures module
(@onchain\/lib\/cardano_keri\/checkpoint\/vectors.ak@) of
@pub const \<name\>: ByteArray = #"\<hex\>"@ constants. Each constant is the exact
canonical Plutus-Data CBOR (or @blake2b_256@ digest) for its vector, so it is
byte-identical to the Slice-2\/3 hspec goldens for the same inputs. Slices 5\/6
assert their Aiken encoder reproduces these bytes; @just check-checkpoint-vectors@
forbids the committed copy from drifting from a regenerate.

Invocation: @gen-checkpoint-vectors [OUT_PATH]@. With a path argument the module is
written there; with none it is printed to stdout.
-}
module Main (main) where

import Cardano.KERI.AID.Blake3.Checkpoint (
    blake3Hash,
 )
import Cardano.KERI.AID.CESR (
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    blake2b_256,
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceMessage,
    InceptionMessage,
    advanceMessage,
    checkpointAssetDomainTag,
    deriveAidAssetName,
    inceptionMessage,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertToBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Word (
    Word8,
 )
import System.Environment (
    getArgs,
 )

-- ---------------------------------------------------------
-- Shared fixture material (identical to the Slice-2/3 hspec goldens)
-- ---------------------------------------------------------

-- | A 32-byte value of a single repeated byte.
b32 :: Word8 -> ByteString
b32 = BS.replicate 32

-- | A 28-byte value of a single repeated byte (a Cardano policy id width).
b28 :: Word8 -> ByteString
b28 = BS.replicate 28

-- Key digests / fixed material shared with DatumSpec.
k1, k2, k3, cesrDatum, nk1, w1, w2 :: ByteString
k1 = b32 0x01
k2 = b32 0x02
k3 = b32 0x03
cesrDatum = b32 0xaa
nk1 = b32 0x0a
w1 = b32 0xb1
w2 = b32 0xb2

-- Message-family material shared with MessageSpec.
policy, cesrA, cesrAFlipped :: ByteString
policy = b28 0xcc
cesrA = BS.pack [0 .. 31] -- the derivation golden's fixed cesr_aid (0x00..0x1f)
cesrAFlipped = BS.pack (1 : [1 .. 31]) -- one-bit flip of byte 0

-- ---------------------------------------------------------
-- Constructors matching the hspec fixtures
-- ---------------------------------------------------------

-- | The @V1@-wrapped checkpoint datum from positional fields.
mkV1 ::
    ByteString ->
    [ByteString] ->
    Threshold ->
    [ByteString] ->
    Threshold ->
    [ByteString] ->
    Integer ->
    Integer ->
    Integer ->
    CheckpointDatum
mkV1 cesr keys thr nkeys nthr wits toad seqn nsn =
    V1
        CheckpointDatumV1
            { cdCesrAid = cesr
            , cdCurKeys = keys
            , cdCurThreshold = thr
            , cdNextKeys = nkeys
            , cdNextThreshold = nthr
            , cdWitnesses = wits
            , cdToad = toad
            , cdSeq = seqn
            , cdNativeSn = nsn
            }

-- | The inception fixture (valid @icp@), matched to MessageSpec.
validIcp :: InceptionMessage
validIcp =
    inceptionMessage
        1 -- network_id
        policy
        (deriveAidAssetName cesrA)
        cesrA
        [k1] -- cur_keys
        (Unweighted 1) -- cur_threshold
        [k2] -- next_keys (KERI n)
        (Unweighted 1) -- next_threshold (KERI nt)
        [] -- witnesses
        0 -- toad
        0 -- native_sn

-- | The advance fixture (valid succession), matched to MessageSpec.
validAdv :: AdvanceMessage
validAdv =
    advanceMessage
        1 -- network_id
        policy
        (deriveAidAssetName cesrA)
        cesrA
        (b32 0xd0) -- spent_txid
        1 -- spent_index
        0 -- prior_seq
        0 -- prior_native_sn
        [b32 0x11] -- new_cur_keys (the revealed committed set)
        (Unweighted 1) -- new_cur_threshold
        [b32 0x22] -- new_next_keys
        (Unweighted 1) -- new_next_threshold
        [] -- new_witnesses
        0 -- new_toad
        1 -- seq_to
        1 -- native_sn_to

{- | The partial (reserve) rotation fixture, matched to MessageSpec: the GLEIF
production Root shape — 7 committed digests at @nt = [[1\/3 x7]]@, revealing
indices {0, 5, 6} with a restated @kt = [[1\/3 x3]]@, re-committing the 4
unexposed reserves plus 3 fresh digests.
-}
reserveAdv :: AdvanceMessage
reserveAdv =
    advanceMessage
        1
        policy
        (deriveAidAssetName cesrA)
        cesrA
        (b32 0xd0)
        1
        0
        0
        [rn 0, rn 5, rn 6]
        (third 3)
        (map (nkd . rn) [1, 2, 3, 4] <> map b32 [0x71, 0x72, 0x73])
        (third 7)
        []
        0
        1
        1
  where
    rn i = b32 (0x30 + i)
    third n = Weighted [replicate n (Weight 1 3)]
    -- The committed next-key digest of a raw verkey (the KEL n entry).
    nkd = blake3Hash . qb64Verkey

-- | The @deriveAidAssetName@ negative computed with the WRONG code (@0x46@).
wrongCodeAsset :: ByteString
wrongCodeAsset =
    blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x46 cesrA)

-- ---------------------------------------------------------
-- The vector set
-- ---------------------------------------------------------

{- | A single named fixture: its Aiken identifier, a one-line doc, and its exact
canonical bytes.
-}
data Vec = Vec String String ByteString

{- | Every canonical vector, computed once from the reused codec modules. The
@golden_@\/@negative_@ prefixes are the family markers the acceptance harness
greps for.
-}
vectors :: [Vec]
vectors =
    -- Threshold canonical CBOR (Slice 5 mirror).
    [ Vec
        "golden_threshold_integer"
        "threshold: integer m-of-n (Unweighted 3)"
        (canonicalCbor (Unweighted 3))
    , Vec
        "golden_threshold_single_clause"
        "threshold: single-clause weighted [[1/2, 1/2]]"
        (canonicalCbor (Weighted [[Weight 1 2, Weight 1 2]]))
    , Vec
        "golden_threshold_multi_clause"
        "threshold: multi-clause weighted [[1/1], [1/1]]"
        (canonicalCbor (Weighted [[Weight 1 1], [Weight 1 1]]))
    , Vec
        "golden_threshold_1of1"
        "threshold: 1-of-1 as Unweighted 1"
        (canonicalCbor (Unweighted 1))
    , Vec
        "golden_threshold_weighted_1of1"
        "threshold: 1-of-1 as Weighted [[1/1]]"
        (canonicalCbor (Weighted [[Weight 1 1]]))
    , Vec
        "golden_threshold_zero_weight"
        "threshold: zero-weight clause member [[0/1, 1/1]] (KERI reserve)"
        (canonicalCbor (Weighted [[Weight 0 1, Weight 1 1]]))
    , -- Datum canonical CBOR (Slice 6 mirror).
      Vec
        "golden_datum_1of1"
        "datum: 1-of-1 (Unweighted 1, witnessless)"
        ( canonicalCbor
            (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
        )
    , Vec
        "golden_datum_integer_m_of_n"
        "datum: integer m-of-n (Unweighted 2, 3 keys)"
        ( canonicalCbor
            (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) [nk1] (Unweighted 1) [] 0 5 7)
        )
    , Vec
        "golden_datum_weighted"
        "datum: single-clause weighted [[1/2, 1/2]]"
        ( canonicalCbor
            ( mkV1
                cesrDatum
                [k1, k2]
                (Weighted [[Weight 1 2, Weight 1 2]])
                [nk1]
                (Unweighted 1)
                []
                0
                2
                4
            )
        )
    , Vec
        "golden_datum_multi_clause"
        "datum: multi-clause weighted [[1/1], [1/1]]"
        ( canonicalCbor
            ( mkV1
                cesrDatum
                [k1, k2]
                (Weighted [[Weight 1 1], [Weight 1 1]])
                [nk1]
                (Unweighted 1)
                []
                0
                1
                3
            )
        )
    , Vec
        "golden_datum_zero_weight"
        "datum: zero-weight clause member [[0/1, 1/1]] (KERI reserve)"
        ( canonicalCbor
            ( mkV1
                cesrDatum
                [k1, k2]
                (Weighted [[Weight 0 1, Weight 1 1]])
                [nk1]
                (Unweighted 1)
                []
                0
                0
                0
            )
        )
    , Vec
        "golden_datum_witnessed"
        "datum: witnessed (non-empty witnesses, toad=2)"
        ( canonicalCbor
            (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w2] 2 3 9)
        )
    , Vec
        "golden_datum_witnessless"
        "datum: witnessless (toad=0, empty witnesses)"
        ( canonicalCbor
            (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
        )
    , -- deriveAidAssetName: the golden derivation + its key negatives.
      Vec
        "golden_derivation_cesr_aid"
        "derivation: the fixed cesr_aid preimage (0x00..0x1f)"
        cesrA
    , Vec
        "golden_aid_asset_name"
        "derivation: aid_asset_name = blake2b_256(tag ++ 0x45 ++ cesr_aid)"
        (deriveAidAssetName cesrA)
    , Vec
        "negative_aid_asset_name_wrong_code"
        "derivation negative: wrong code 0x46 (not 0x45)"
        wrongCodeAsset
    , Vec
        "negative_aid_asset_name_mutated_aid"
        "derivation negative: one-bit-flipped cesr_aid"
        (deriveAidAssetName cesrAFlipped)
    , -- Signed message preimages (Slice 6 mirror).
      Vec
        "golden_inception_message"
        "message: InceptionMessage (icp) canonical CBOR"
        (canonicalCbor validIcp)
    , Vec
        "golden_advance_message"
        "message: AdvanceMessage (valid succession) canonical CBOR"
        (canonicalCbor validAdv)
    , Vec
        "golden_advance_reserve_message"
        "message: AdvanceMessage (partial/reserve rotation, GLEIF Root shape)"
        (canonicalCbor reserveAdv)
    ]

-- ---------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------

-- | Lowercase hex of a 'ByteString'.
toHex :: ByteString -> String
toHex = BC.unpack . convertToBase Base16

{- | Render one fixture as a documented Aiken constant. The hex is emitted on its
own indented line; @aiken fmt@ (run by @just gen-checkpoint-vectors@) collapses
short constants back onto a single line, yielding canonical, drift-stable output.
-}
renderVec :: Vec -> String
renderVec (Vec name doc bytes) =
    unlines
        [ "/// " <> doc
        , "pub const " <> name <> ": ByteArray ="
        , "  #\"" <> toHex bytes <> "\""
        ]

-- | The full self-contained Aiken fixtures module.
render :: String
render =
    header <> "\n" <> concatMap (\v -> renderVec v <> "\n") vectors
  where
    header =
        unlines
            [ "//// Auto-generated Aiken checkpoint fixtures for #68 — DO NOT EDIT."
            , "////"
            , "//// Regenerate with `just gen-checkpoint-vectors` (runs"
            , "//// offchain/app/GenCheckpointVectors.hs). Each constant is the exact"
            , "//// canonical Plutus-Data CBOR (or blake2b_256 digest) the Haskell"
            , "//// encoder emits, so it is byte-identical to the Slice-2/3 hspec"
            , "//// goldens. Slices 5/6 assert the Aiken encoder reproduces these"
            , "//// bytes; `just check-checkpoint-vectors` forbids drift."
            ]

-- ---------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------

-- | Write the fixtures module to the argv path, or to stdout when none is given.
main :: IO ()
main = do
    args <- getArgs
    case args of
        (out : _) -> writeFile out render
        [] -> putStr render
