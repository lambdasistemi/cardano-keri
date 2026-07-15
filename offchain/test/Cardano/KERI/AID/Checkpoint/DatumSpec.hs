module Cardano.KERI.AID.Checkpoint.DatumSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    DatumError (..),
    NextCommitment (..),
    blake2b_256,
    canonicalCbor,
    datumWellFormed,
    keysetCommit,
    nextDigest,
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
k1, k2, k3, cesrDatum, nextConst, w1, w2 :: ByteString
k1 = b32 0x01
k2 = b32 0x02
k3 = b32 0x03
cesrDatum = b32 0xaa
nextConst = b32 0x0a
w1 = b32 0xb1
w2 = b32 0xb2

-- | The inner v1 record from positional fields.
v1 ::
    ByteString ->
    [ByteString] ->
    Threshold ->
    ByteString ->
    [ByteString] ->
    Integer ->
    Integer ->
    Integer ->
    CheckpointDatumV1
v1 cesr keys thr nxt wits toad seqn nsn =
    CheckpointDatumV1
        { cdCesrAid = cesr
        , cdCurKeys = keys
        , cdCurThreshold = thr
        , cdNextDigest = nxt
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
    ByteString ->
    [ByteString] ->
    Integer ->
    Integer ->
    Integer ->
    CheckpointDatum
mkV1 cesr keys thr nxt wits toad seqn nsn =
    V1 (v1 cesr keys thr nxt wits toad seqn nsn)

spec :: Spec
spec = do
    -- ------------------------------------------------------
    -- Frozen wire shape: outer version sum + inner record
    -- ------------------------------------------------------
    describe "CheckpointDatum wire shape (frozen constructor indices)" $ do
        it "V1 is Constr 0 wrapping the inner Constr 0 record" $
            dataOf (mkV1 cesrDatum [k1] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` Constr
                    0
                    [ Constr
                        0
                        [ B cesrDatum
                        , List [B k1]
                        , Constr 0 [I 1]
                        , B nextConst
                        , List []
                        , I 0
                        , I 0
                        , I 0
                        ]
                    ]
        it "inner record keeps the 8 fields in frozen positional order" $
            dataOf (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) nextConst [] 0 5 7)
                `shouldBe` Constr
                    0
                    [ Constr
                        0
                        [ B cesrDatum
                        , List [B k1, B k2, B k3]
                        , Constr 0 [I 2]
                        , B nextConst
                        , List []
                        , I 0
                        , I 5
                        , I 7
                        ]
                    ]

    -- ------------------------------------------------------
    -- Canonical CBOR goldens (byte-for-byte cross-language pin).
    -- Independently computed (a hand-built Plutus-Data CBOR encoder +
    -- BLAKE2b via Python hashlib), validated against Slice 2's frozen
    -- Threshold goldens.
    -- ------------------------------------------------------
    describe "CheckpointDatumV1 canonical CBOR goldens" $ do
        it "1-of-1 (Unweighted 1, witnessless)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000000ffff"
        it "integer m-of-n (Unweighted 2, 3 keys)" $
            canonicalCbor (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) nextConst [] 0 5 7)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f582001010101010101010101010101010101010101010101010101010101010101015820020202020202020202020202020202020202020202020202020202020202020258200303030303030303030303030303030303030303030303030303030303030303ffd8799f02ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000507ffff"
        it "single-clause weighted [[1/2, 1/2]]" $
            canonicalCbor
                (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 1 2, Weight 1 2]]) nextConst [] 0 2 4)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0102ffd8799f0102ffffffff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000204ffff"
        it "multi-clause weighted [[1/1], [1/1]]" $
            canonicalCbor
                (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 1 1], [Weight 1 1]]) nextConst [] 0 1 3)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0101ffff9fd8799f0101ffffffff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000103ffff"
        it "witnessed (non-empty witnesses, toad=2)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) nextConst [w1, w2] 2 3 9)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a9f5820b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b15820b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2ff020309ffff"
        it "witnessless (toad=0, empty witnesses)" $
            canonicalCbor (mkV1 cesrDatum [k1] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` hexBs
                    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000000ffff"

    -- ------------------------------------------------------
    -- toData / fromData roundtrip
    -- ------------------------------------------------------
    describe "toData/fromData roundtrip" $ do
        let roundtrips d = fromBuiltinData (toBuiltinData d) `shouldBe` Just d
        it "1-of-1" $ roundtrips (mkV1 cesrDatum [k1] (Unweighted 1) nextConst [] 0 0 0)
        it "integer m-of-n" $ roundtrips (mkV1 cesrDatum [k1, k2, k3] (Unweighted 2) nextConst [] 0 5 7)
        it "single-clause weighted" $
            roundtrips (mkV1 cesrDatum [k1, k2] (Weighted [[Weight 1 2, Weight 1 2]]) nextConst [] 0 2 4)
        it "witnessed" $ roundtrips (mkV1 cesrDatum [k1] (Unweighted 1) nextConst [w1, w2] 2 3 9)

    -- ------------------------------------------------------
    -- NextCommitment / keyset_commit / next_digest
    -- ------------------------------------------------------
    describe "NextCommitment and the next-key commitment" $ do
        let nc = NextCommitment [k2] (Unweighted 1)
        it "NextCommitment canonical CBOR golden" $
            canonicalCbor nc
                `shouldBe` hexBs
                    "d8799f9f58200202020202020202020202020202020202020202020202020202020202020202ffd8799f01ffff"
        it "keysetCommit golden (blake2b_256 of the canonical CBOR)" $
            keysetCommit nc
                `shouldBe` hexBs
                    "7a3a5a75a5237ec477925c6cc500f6db3aa85cdb341295e5d78c81bdf278a8eb"
        it "keysetCommit is blake2b_256 of the canonical CBOR (definitional)" $
            keysetCommit nc `shouldBe` blake2b_256 (canonicalCbor nc)
        it "keysetCommit is 32 bytes" $
            BS.length (keysetCommit nc) `shouldBe` 32
        it "nextDigest nk nt == keysetCommit (NextCommitment nk nt)" $
            nextDigest [k2] (Unweighted 1) `shouldBe` keysetCommit nc
        it "reordering next keys changes the commitment" $
            nextDigest [k1, k2] (Unweighted 1)
                `shouldSatisfy` (/= nextDigest [k2, k1] (Unweighted 1))

    -- ------------------------------------------------------
    -- Datum well-formedness: exact rejections.
    -- Primitive-domain widths are pinned here; key-set / threshold checks
    -- are DELEGATED to the reused Slice-2 F18 'wellFormed' (asserted via the
    -- 'ThresholdIllFormed' wrapper), so GREEN cannot skip them.
    -- ------------------------------------------------------
    describe "datumWellFormed positives" $ do
        it "witnessless toad=0 well-formed" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` Right ()
        it "witnessed 0<=toad<=len well-formed" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) nextConst [w1, w2] 2 3 9)
                `shouldBe` Right ()

    describe "datumWellFormed rule-14 rejections (exact errors)" $ do
        it "toad greater than witness count -> ToadRange" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) nextConst [w1] 2 0 0)
                `shouldBe` Left ToadRange
        it "negative toad -> ToadRange" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) nextConst [w1] (-1) 0 0)
                `shouldBe` Left ToadRange
        it "duplicate witness -> DuplicateWitness" $
            datumWellFormed (v1 cesrDatum [k1] (Unweighted 1) nextConst [w1, w1] 1 0 0)
                `shouldBe` Left DuplicateWitness
        it "witness not 32 bytes -> WitnessWidth" $
            datumWellFormed
                (v1 cesrDatum [k1] (Unweighted 1) nextConst [BS.replicate 31 0xb1] 1 0 0)
                `shouldBe` Left WitnessWidth

    describe "datumWellFormed primitive-domain widths (exact errors)" $ do
        it "cesr_aid not 32 bytes -> CesrAidWidth" $
            datumWellFormed
                (v1 (BS.replicate 31 0xaa) [k1] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` Left CesrAidWidth
        it "next_digest not 32 bytes -> NextDigestWidth" $
            datumWellFormed
                (v1 cesrDatum [k1] (Unweighted 1) (BS.replicate 31 0x0a) [] 0 0 0)
                `shouldBe` Left NextDigestWidth

    describe "datumWellFormed delegates key-set checks to Slice-2 wellFormed" $ do
        it "key not 32 bytes -> ThresholdIllFormed KeyWidth" $
            datumWellFormed
                (v1 cesrDatum [BS.replicate 31 0x01] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed KeyWidth)
        it "empty key set -> ThresholdIllFormed EmptyKeys" $
            datumWellFormed (v1 cesrDatum [] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed EmptyKeys)
        it "duplicate keys -> ThresholdIllFormed DuplicateKey" $
            datumWellFormed (v1 cesrDatum [k1, k1] (Unweighted 1) nextConst [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed DuplicateKey)
        it "unsatisfiable weighted clause -> ThresholdIllFormed UnsatisfiableClause" $
            datumWellFormed
                (v1 cesrDatum [k1] (Weighted [[Weight 1 2]]) nextConst [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed UnsatisfiableClause)
