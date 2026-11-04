module Cardano.KERI.AID.Checkpoint.DatumSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    DatumError (..),
    KeyStateView (..),
    keyStateWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Word (
    Word8,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

-- | A distinct, correctly-sized 32-byte value.
b32 :: Word8 -> ByteString
b32 = BS.replicate 32

-- Fixed test material.
k1, k2, cesrDatum, nk1, w1, w2 :: ByteString
k1 = b32 0x01
k2 = b32 0x02
cesrDatum = b32 0xaa
nk1 = b32 0x0a
w1 = b32 0xb1
w2 = b32 0xb2

-- | The key state view from positional fields.
keyState ::
    ByteString ->
    [ByteString] ->
    Threshold ->
    [ByteString] ->
    Threshold ->
    [ByteString] ->
    Integer ->
    Integer ->
    Integer ->
    KeyStateView
keyState cesr keys thr nkeys nthr wits toad seqn nsn =
    KeyStateView
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

spec :: Spec
spec = do
    -- ------------------------------------------------------
    -- Datum well-formedness: exact rejections.
    -- Primitive-domain widths are pinned here; key-set / threshold checks
    -- for BOTH the current and next pairs are DELEGATED to the reused
    -- Slice-2 F18 'wellFormed' (asserted via the 'ThresholdIllFormed' /
    -- 'NextIllFormed' wrappers), so GREEN cannot skip them.
    -- ------------------------------------------------------
    describe "keyStateWellFormed positives" $ do
        it "witnessless toad=0 well-formed" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Right ()
        it "witnessed 1<=toad<=len well-formed" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w2] 2 3 9)
                `shouldBe` Right ()
        it "zero-weight clause member well-formed (KERI reserve pattern)" $
            keyStateWellFormed
                (keyState cesrDatum [k1, k2] (Weighted [[Weight 0 1, Weight 1 1]]) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Right ()

    describe "keyStateWellFormed rule-14 rejections (exact errors)" $ do
        it "toad greater than witness count -> ToadRange" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1] 2 0 0)
                `shouldBe` Left ToadRange
        it "toad=0 with non-empty witnesses -> ToadRange (KERI bt rule)" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1] 0 0 0)
                `shouldBe` Left ToadRange
        it "non-zero toad with empty witnesses -> ToadRange" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 1 0 0)
                `shouldBe` Left ToadRange
        it "negative toad -> ToadRange" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1] (-1) 0 0)
                `shouldBe` Left ToadRange
        it "duplicate witness -> DuplicateWitness" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [w1, w1] 1 0 0)
                `shouldBe` Left DuplicateWitness
        it "witness not 32 bytes -> WitnessWidth" $
            keyStateWellFormed
                (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 1) [BS.replicate 31 0xb1] 1 0 0)
                `shouldBe` Left WitnessWidth

    describe "keyStateWellFormed primitive-domain widths (exact errors)" $ do
        it "cesr_aid not 32 bytes -> CesrAidWidth" $
            keyStateWellFormed
                (keyState (BS.replicate 31 0xaa) [k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left CesrAidWidth

    describe "keyStateWellFormed delegates key-set checks to Slice-2 wellFormed" $ do
        it "key not 32 bytes -> ThresholdIllFormed KeyWidth" $
            keyStateWellFormed
                (keyState cesrDatum [BS.replicate 31 0x01] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed KeyWidth)
        it "empty key set -> ThresholdIllFormed EmptyKeys" $
            keyStateWellFormed (keyState cesrDatum [] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed EmptyKeys)
        it "duplicate keys -> ThresholdIllFormed DuplicateKey" $
            keyStateWellFormed (keyState cesrDatum [k1, k1] (Unweighted 1) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed DuplicateKey)
        it "unsatisfiable weighted clause -> ThresholdIllFormed UnsatisfiableClause" $
            keyStateWellFormed
                (keyState cesrDatum [k1] (Weighted [[Weight 1 2]]) [nk1] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (ThresholdIllFormed UnsatisfiableClause)

    describe "keyStateWellFormed delegates next-pair checks to Slice-2 wellFormed" $ do
        it "empty next keys -> NextIllFormed EmptyKeys" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (NextIllFormed EmptyKeys)
        it "next key not 32 bytes -> NextIllFormed KeyWidth" $
            keyStateWellFormed
                (keyState cesrDatum [k1] (Unweighted 1) [BS.replicate 31 0x0a] (Unweighted 1) [] 0 0 0)
                `shouldBe` Left (NextIllFormed KeyWidth)
        it "next threshold out of range -> NextIllFormed UnweightedRange" $
            keyStateWellFormed (keyState cesrDatum [k1] (Unweighted 1) [nk1] (Unweighted 2) [] 0 0 0)
                `shouldBe` Left (NextIllFormed UnweightedRange)
