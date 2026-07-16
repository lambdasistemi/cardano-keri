module Cardano.KERI.AID.Checkpoint.DatumSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    DatumError (..),
    canonicalCbor,
    datumWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Word (
    Word8,
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
    fromBuiltinData,
    toBuiltinData,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldSatisfy,
 )

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

-- | Underlying canonical Plutus 'Data' tree of a value.
dataOf :: (ToData a) => a -> Data
dataOf x = let BuiltinData d = toBuiltinData x in d

-- | A strict 'ByteString' from an ASCII hex literal.
hexBs :: ByteString -> ByteString
hexBs s = either error id (convertFromBase Base16 s)

-- | A distinct, correctly-sized 32-byte value.
b32 :: Word8 -> ByteString
b32 = BS.replicate 32

-- Fixed test material shared with the independent golden generator.
k1, k2, k3, cesrDatum, nk1, w1, w2 :: ByteString
k1 = b32 0x01
k2 = b32 0x02
k3 = b32 0x03
cesrDatum = b32 0xaa
nk1 = b32 0x0a
w1 = b32 0xb1
w2 = b32 0xb2

-- | The inner v1 record from positional fields.
v1 ::
    ByteString ->
    [ByteString] ->
    Threshold ->
    [ByteString] ->
    Threshold ->
    [ByteString] ->
    Integer ->
    Integer ->
    Integer ->
    CheckpointDatumV1
v1 cesr keys thr nkeys nthr wits toad seqn nsn =
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

-- | The full 'CheckpointDatum' (@V1@-wrapped) from positional fields.
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
    V1 (v1 cesr keys thr nkeys nthr wits toad seqn nsn)

spec :: Spec
spec = do
    -- ------------------------------------------------------
    -- Frozen wire shape: outer version sum + inner record
    -- ------------------------------------------------------
    describe "CheckpointDatum wire shape (frozen constructor indices)" $ do
        it "V1 is Constr 0 wrapping the inner Constr 0 record" $
            dataOf (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Constr
                    0
                    [ Constr
                        0
                        [ B cesrDatum
                        , List [B k1]
                        , Constr 0 [I 1]
                        , List [B nk1]
                        , Constr 0 [I 1]
                        , List []
                        , I 0
                        , I 0
                        , I 0
                        ]
                    ]
        it "inner record keeps the 9 fields in frozen positional order" $
            dataOf (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) [nk1] (Unweighted 1) [] 0 5 7)
                `shouldBe` Constr
                    0
                    [ Constr
                        0
                        [ B cesrDatum
                        , List [B k1, B k2, B k3]
                        , Constr 0 [I 2]
                        , List [B nk1]
                        , Constr 0 [I 1]
                        , List []
                        , I 0
                        , I 5
                        , I 7
                        ]
                    ]

    -- ------------------------------------------------------
    -- Canonical CBOR goldens (byte-for-byte cross-language pin).
    -- Derived from the previously verified 8-field goldens (independently
    -- computed via a hand-built Plutus-Data CBOR encoder) by the mechanical
    -- field splice: the 32-byte next_digest bytestring (5820 ‖ digest)
    -- becomes the next_keys list (9f 5820 ‖ digest ‖ ff) followed by the
    -- next_threshold encoding (d8799f01ff = Unweighted 1).
    -- ------------------------------------------------------
    describe "CheckpointDatumV1 canonical CBOR goldens" $ do
        it "1-of-1 (Unweighted 1, witnessless)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff80000000ffff"
        it "integer m-of-n (Unweighted 2, 3 keys)" $
            canonicalCbor (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) [nk1] (Unweighted 1) [] 0 5 7)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f582001010101010101010101010101010101010101010101010101010101010101015820020202020202020202020202020202020202020202020202020202020202020258200303030303030303030303030303030303030303030303030303030303030303ffd8799f02ff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff80000507ffff"
        it "single-clause weighted [[1/2, 1/2]]" $
            canonicalCbor
                (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 1 2, Weight 1 2]]) [nk1] (Unweighted 1) [] 0 2 4)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0102ffd8799f0102ffffffff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff80000204ffff"
        it "multi-clause weighted [[1/1], [1/1]]" $
            canonicalCbor
                (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 1 1], [Weight 1 1]]) [nk1] (Unweighted 1) [] 0 1 3)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0101ffff9fd8799f0101ffffffff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff80000103ffff"
        it "zero-weight clause member [[0/1, 1/1]] (KERI reserve pattern)" $
            canonicalCbor
                (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 0 1, Weight 1 1]]) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0001ffd8799f0101ffffffff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff80000000ffff"
        it "witnessed (non-empty witnesses, toad=2)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w2] 2 3 9)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff9f5820b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b15820b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2ff020309ffff"
        it "witnessless (toad=0, empty witnesses)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0affd8799f01ff80000000ffff"

    -- ------------------------------------------------------
    -- toData / fromData roundtrip
    -- ------------------------------------------------------
    describe "toData/fromData roundtrip" $ do
        let roundtrips d = fromBuiltinData (toBuiltinData d) `shouldBe` Just d
        it "1-of-1" $
            roundtrips (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
        it "integer m-of-n" $
            roundtrips (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) [nk1] (Unweighted 1) [] 0 5 7)
        it "single-clause weighted" $
            roundtrips (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 1 2, Weight 1 2]]) [nk1] (Unweighted 1) [] 0 2 4)
        it "zero-weight clause member" $
            roundtrips (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 0 1, Weight 1 1]]) [nk1] (Unweighted 1) [] 0 0 0)
        it "witnessed" $
            roundtrips (mkV1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w2] 2 3 9)

    -- ------------------------------------------------------
    -- The explicit pre-rotation pair (KERI n + nt)
    -- ------------------------------------------------------
    describe "the explicit (next_keys, next_threshold) commitment" $ do
        it "reordering next keys changes the datum bytes (positional)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) [nk1, k2] (Unweighted 1) [] 0 0 0)
                `shouldSatisfy` ( /=
                                    canonicalCbor
                                        (mkV1 cesrDatum [k1] (Unweighted 1) [k2, nk1] (Unweighted 1) [] 0 0 0)
                                )
        it "changing the next threshold changes the datum bytes" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) [nk1, k2] (Unweighted 1) [] 0 0 0)
                `shouldSatisfy` ( /=
                                    canonicalCbor
                                        (mkV1 cesrDatum [k1] (Unweighted 1) [nk1, k2] (Unweighted 2) [] 0 0 0)
                                )

    -- ------------------------------------------------------
    -- Datum well-formedness: exact rejections.
    -- Primitive-domain widths are pinned here; key-set / threshold checks
    -- for BOTH the current and next pairs are DELEGATED to the reused
    -- Slice-2 F18 'wellFormed' (asserted via the 'ThresholdIllFormed' /
    -- 'NextIllFormed' wrappers), so GREEN cannot skip them.
    -- ------------------------------------------------------
    describe "datumWellFormed positives" $ do
        it "witnessless toad=0 well-formed" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Right ()
        it "witnessed 1<=toad<=len well-formed" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w2] 2 3 9)
                `shouldBe` Right ()
        it "zero-weight clause member well-formed (KERI reserve pattern)" $
            datumWellFormed
                (v1 cesrDatum [k1, k2] (Weighted [[Weight 0 1, Weight 1 1]]) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Right ()

    describe "datumWellFormed rule-14 rejections (exact errors)" $ do
        it "toad greater than witness count -> ToadRange" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1] 2 0 0)
                `shouldBe` Left ToadRange
        it "toad=0 with non-empty witnesses -> ToadRange (KERI bt rule)" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1] 0 0 0)
                `shouldBe` Left ToadRange
        it "non-zero toad with empty witnesses -> ToadRange" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 1 0 0)
                `shouldBe` Left ToadRange
        it "negative toad -> ToadRange" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1] (-1) 0 0)
                `shouldBe` Left ToadRange
        it "duplicate witness -> DuplicateWitness" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w1] 1 0 0)
                `shouldBe` Left DuplicateWitness
        it "witness not 32 bytes -> WitnessWidth" $
            datumWellFormed
                (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [BS.replicate 31 0xb1] 1 0 0)
                `shouldBe` Left WitnessWidth

    describe "datumWellFormed primitive-domain widths (exact errors)" $ do
        it "cesr_aid not 32 bytes -> CesrAidWidth" $
            datumWellFormed
                (v1 (BS.replicate 31 0xaa) [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left CesrAidWidth

    describe "datumWellFormed delegates key-set checks to Slice-2 wellFormed" $ do
        it "key not 32 bytes -> ThresholdIllFormed KeyWidth" $
            datumWellFormed
                (v1 cesrDatum [BS.replicate 31 0x01] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed KeyWidth)
        it "empty key set -> ThresholdIllFormed EmptyKeys" $
            datumWellFormed (v1 cesrDatum [] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed EmptyKeys)
        it "duplicate keys -> ThresholdIllFormed DuplicateKey" $
            datumWellFormed (v1 cesrDatum [k1, k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed DuplicateKey)
        it "unsatisfiable weighted clause -> ThresholdIllFormed UnsatisfiableClause" $
            datumWellFormed
                (v1 cesrDatum [k1] (Weighted [[Weight 1 2]]) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed UnsatisfiableClause)

    describe "datumWellFormed delegates next-pair checks to Slice-2 wellFormed" $ do
        it "empty next keys -> NextIllFormed EmptyKeys" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (NextIllFormed EmptyKeys)
        it "next key not 32 bytes -> NextIllFormed KeyWidth" $
            datumWellFormed
                (v1 cesrDatum [k1] (Unweighted 1) [BS.replicate 31 0x0a] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (NextIllFormed KeyWidth)
        it "next threshold out of range -> NextIllFormed UnweightedRange" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 2) [] 0 0 0)
                `shouldBe` Left (NextIllFormed UnweightedRange)
