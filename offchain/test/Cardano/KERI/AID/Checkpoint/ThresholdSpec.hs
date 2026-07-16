module Cardano.KERI.AID.Checkpoint.ThresholdSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
    evaluate,
    maxWeightDenom,
    wellFormed,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet
import Data.Word (
    Word8,
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins (
    serialiseData,
 )
import PlutusTx.Builtins.Internal (
    BuiltinByteString (..),
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

{- | Canonical Plutus 'Data' CBOR bytes of a value (the cross-language,
byte-for-byte contract; the same bytes Aiken @cbor.serialise@ emits).
-}
cborOf :: (ToData a) => a -> BuiltinByteString
cborOf = serialiseData . toBuiltinData

-- | A 'BuiltinByteString' literal from raw bytes.
bbs :: [Word8] -> BuiltinByteString
bbs = BuiltinByteString . BS.pack

-- | A distinct, correctly-sized 32-byte 'KeyDigest'.
k1, k2, k3, k4, k5 :: ByteString
k1 = BS.replicate 32 0x01
k2 = BS.replicate 32 0x02
k3 = BS.replicate 32 0x03
k4 = BS.replicate 32 0x04
k5 = BS.replicate 32 0x05

isLeft :: Either a b -> Bool
isLeft = either (const True) (const False)

spec :: Spec
spec = do
    -- ------------------------------------------------------
    -- Golden wire shape: frozen constructor indices
    -- ------------------------------------------------------
    describe "Threshold wire shape (frozen constructor indices)" $ do
        it "Unweighted m -> Constr 0 [I m]" $
            dataOf (Unweighted 3)
                `shouldBe` Constr 0 [I 3]
        it "single-clause Weighted -> Constr 1 [List [List [Constr 0 [I,I]]]]" $
            dataOf (Weighted [[Weight 1 2, Weight 1 2]])
                `shouldBe` Constr
                    1
                    [List [List [Constr 0 [I 1, I 2], Constr 0 [I 1, I 2]]]]
        it "multi-clause Weighted preserves clause order and split" $
            dataOf (Weighted [[Weight 1 1], [Weight 1 1]])
                `shouldBe` Constr
                    1
                    [ List
                        [ List [Constr 0 [I 1, I 1]]
                        , List [Constr 0 [I 1, I 1]]
                        ]
                    ]
        it "1-of-1 as Unweighted 1 -> Constr 0 [I 1]" $
            dataOf (Unweighted 1) `shouldBe` Constr 0 [I 1]
        it "1-of-1 as Weighted [[1/1]] -> Constr 1 [List [List [Constr 0]]]" $
            dataOf (Weighted [[Weight 1 1]])
                `shouldBe` Constr 1 [List [List [Constr 0 [I 1, I 1]]]]

    -- ------------------------------------------------------
    -- Golden canonical CBOR bytes (the cross-language contract).
    -- Pinned literals; the same bytes Aiken cbor.serialise emits in
    -- Slice 5. Constr 0 -> tag 0xd879; Constr 1 -> tag 0xd87a; fields and
    -- lists are indefinite CBOR arrays (0x9f .. 0xff).
    -- ------------------------------------------------------
    describe "Threshold canonical CBOR goldens" $ do
        it "integer m-of-n: Unweighted 3" $
            cborOf (Unweighted 3)
                `shouldBe` bbs [0xd8, 0x79, 0x9f, 0x03, 0xff]
        it "single-clause weighted [[1/2, 1/2]]" $
            cborOf (Weighted [[Weight 1 2, Weight 1 2]])
                `shouldBe` bbs
                    [ 0xd8
                    , 0x7a
                    , 0x9f
                    , 0x9f
                    , 0x9f
                    , 0xd8
                    , 0x79
                    , 0x9f
                    , 0x01
                    , 0x02
                    , 0xff
                    , 0xd8
                    , 0x79
                    , 0x9f
                    , 0x01
                    , 0x02
                    , 0xff
                    , 0xff
                    , 0xff
                    , 0xff
                    ]
        it "multi-clause weighted [[1/1], [1/1]]" $
            cborOf (Weighted [[Weight 1 1], [Weight 1 1]])
                `shouldBe` bbs
                    [ 0xd8
                    , 0x7a
                    , 0x9f
                    , 0x9f
                    , 0x9f
                    , 0xd8
                    , 0x79
                    , 0x9f
                    , 0x01
                    , 0x01
                    , 0xff
                    , 0xff
                    , 0x9f
                    , 0xd8
                    , 0x79
                    , 0x9f
                    , 0x01
                    , 0x01
                    , 0xff
                    , 0xff
                    , 0xff
                    , 0xff
                    ]
        it "1-of-1 as Unweighted 1" $
            cborOf (Unweighted 1)
                `shouldBe` bbs [0xd8, 0x79, 0x9f, 0x01, 0xff]
        it "1-of-1 as Weighted [[1/1]]" $
            cborOf (Weighted [[Weight 1 1]])
                `shouldBe` bbs
                    [ 0xd8
                    , 0x7a
                    , 0x9f
                    , 0x9f
                    , 0x9f
                    , 0xd8
                    , 0x79
                    , 0x9f
                    , 0x01
                    , 0x01
                    , 0xff
                    , 0xff
                    , 0xff
                    , 0xff
                    ]

    -- ------------------------------------------------------
    -- Frozen V1 constant (pinned to a literal, not the export)
    -- ------------------------------------------------------
    describe "frozen V1 constant" $
        it "maxWeightDenom == 2^32 == 4294967296" $
            maxWeightDenom `shouldBe` 4294967296

    -- ------------------------------------------------------
    -- toData / fromData roundtrip
    -- ------------------------------------------------------
    describe "toData/fromData roundtrip" $ do
        let roundtrips t =
                fromBuiltinData (toBuiltinData t) `shouldBe` Just t
        it "integer m-of-n" $ roundtrips (Unweighted 2)
        it "single-clause weighted" $
            roundtrips (Weighted [[Weight 1 2, Weight 1 2, Weight 1 2]])
        it "multi-clause weighted" $
            roundtrips (Weighted [[Weight 1 3, Weight 2 3], [Weight 1 1]])
        it "1-of-1 Unweighted" $ roundtrips (Unweighted 1)
        it "1-of-1 Weighted" $ roundtrips (Weighted [[Weight 1 1]])

    -- ------------------------------------------------------
    -- fromData rejects a non-canonical (unreduced) Weight (F18 rule 10)
    -- ------------------------------------------------------
    describe "fromData canonicality" $ do
        let decode :: Data -> Maybe Threshold
            decode = fromBuiltinData . BuiltinData
        it "accepts a reduced weight 1/2" $
            decode (Constr 1 [List [List [Constr 0 [I 1, I 2]]]])
                `shouldBe` Just (Weighted [[Weight 1 2]])
        it "rejects an unreduced weight 2/4 (rule 10)" $
            decode (Constr 1 [List [List [Constr 0 [I 2, I 4]]]])
                `shouldBe` Nothing
        it "rejects an over-unity weight 3/2" $
            decode (Constr 1 [List [List [Constr 0 [I 3, I 2]]]])
                `shouldBe` Nothing
        it "accepts the canonical zero weight 0/1" $
            decode
                ( Constr
                    1
                    [List [List [Constr 0 [I 0, I 1], Constr 0 [I 1, I 1]]]]
                )
                `shouldBe` Just (Weighted [[Weight 0 1, Weight 1 1]])
        it "rejects a non-canonical zero weight 0/2 (rule 10)" $
            decode (Constr 1 [List [List [Constr 0 [I 0, I 2]]]])
                `shouldBe` Nothing

    -- ------------------------------------------------------
    -- Positional order sensitivity (security-significant)
    -- ------------------------------------------------------
    describe "positional order sensitivity" $ do
        it "reordering weights within a clause changes the bytes" $
            dataOf (Weighted [[Weight 1 3, Weight 2 3]])
                `shouldSatisfy` (/= dataOf (Weighted [[Weight 2 3, Weight 1 3]]))
        it "reordering clauses changes the bytes" $
            dataOf (Weighted [[Weight 1 3], [Weight 2 3]])
                `shouldSatisfy` (/= dataOf (Weighted [[Weight 2 3], [Weight 1 3]]))

    -- ------------------------------------------------------
    -- F18 well-formedness (rules 1-13)
    -- ------------------------------------------------------
    describe "wellFormed positives" $ do
        it "integer m-of-n well-formed" $
            wellFormed [k1, k2, k3] (Unweighted 2) `shouldBe` Right ()
        it "single-clause weighted well-formed" $
            wellFormed
                [k1, k2]
                (Weighted [[Weight 1 2, Weight 1 2]])
                `shouldBe` Right ()
        it "multi-clause weighted well-formed" $
            wellFormed
                [k1, k2]
                (Weighted [[Weight 1 1], [Weight 1 1]])
                `shouldBe` Right ()
        it "1-of-1 Unweighted well-formed" $
            wellFormed [k1] (Unweighted 1) `shouldBe` Right ()
        it "1-of-1 Weighted well-formed" $
            wellFormed [k1] (Weighted [[Weight 1 1]]) `shouldBe` Right ()
        it "zero weight in a satisfiable clause well-formed (KERI reserve)" $
            wellFormed [k1, k2] (Weighted [[Weight 0 1, Weight 1 1]])
                `shouldBe` Right ()
        it "keripy multi-clause vector [[1/2,1/2,1/2],[1,1]] well-formed" $
            -- WebOfTrust/keripy tests/core/test_weighted_threshold.py
            wellFormed
                [k1, k2, k3, k4, k5]
                ( Weighted
                    [ [Weight 1 2, Weight 1 2, Weight 1 2]
                    , [Weight 1 1, Weight 1 1]
                    ]
                )
                `shouldBe` Right ()

    describe "wellFormed F18 rejections" $ do
        it "rule 1: empty key set" $
            wellFormed [] (Unweighted 1) `shouldBe` Left EmptyKeys
        it "rule 2: duplicate key" $
            wellFormed [k1, k1] (Unweighted 1)
                `shouldBe` Left DuplicateKey
        it "rule 3: key not 32 bytes" $
            wellFormed [BS.replicate 31 0x01] (Unweighted 1)
                `shouldBe` Left KeyWidth
        it "rule 4: m > n" $
            wellFormed [k1, k2] (Unweighted 3)
                `shouldBe` Left UnweightedRange
        it "rule 4: m < 1" $
            wellFormed [k1] (Unweighted 0)
                `shouldBe` Left UnweightedRange
        it "rule 5: empty clause set" $
            wellFormed [k1] (Weighted [])
                `shouldBe` Left EmptyClause
        it "rule 5: empty clause" $
            wellFormed [k1] (Weighted [[]])
                `shouldBe` Left EmptyClause
        it "rule 6: partition does not cover keys" $
            wellFormed [k1, k2] (Weighted [[Weight 1 1]])
                `shouldBe` Left PartitionMismatch
        it "rule 7: non-positive denominator" $
            wellFormed [k1] (Weighted [[Weight 1 0]])
                `shouldBe` Left NonPositiveDen
        it "rule 8: negative numerator" $
            wellFormed [k1] (Weighted [[Weight (-1) 2]])
                `shouldBe` Left NegativeNum
        it "an all-zero clause is unsatisfiable (rule 12, not rule 8)" $
            wellFormed [k1] (Weighted [[Weight 0 1]])
                `shouldBe` Left UnsatisfiableClause
        it "rule 9: over-unity weight" $
            wellFormed [k1] (Weighted [[Weight 3 2]])
                `shouldBe` Left OverUnityWeight
        it "rule 10: unreduced rational" $
            wellFormed [k1] (Weighted [[Weight 2 4]])
                `shouldBe` Left UnreducedWeight
        -- Literal bounds: these must fail if the frozen constant drifts.
        it "rule 11: denominator == 4294967296 is accepted (boundary)" $
            wellFormed
                [k1, k2]
                ( Weighted
                    [
                        [ Weight 1 4294967296
                        , Weight 4294967295 4294967296
                        ]
                    ]
                )
                `shouldBe` Right ()
        it "rule 11: denominator == 4294967297 is rejected (boundary)" $
            wellFormed
                [k1, k2]
                ( Weighted
                    [
                        [ Weight 1 4294967297
                        , Weight 4294967296 4294967297
                        ]
                    ]
                )
                `shouldBe` Left WeightOutOfBound
        it "rule 12: unsatisfiable clause (sum < 1)" $
            wellFormed [k1] (Weighted [[Weight 1 2]])
                `shouldBe` Left UnsatisfiableClause
        it "rule 13: a nested weighted-list weight shape is rejected" $
            let nested =
                    Constr
                        1
                        [ List
                            [ List
                                [ Constr
                                    0
                                    [ -- a nested weighted list where an
                                      -- exact rational numerator is required
                                      Constr
                                        1
                                        [List [List [Constr 0 [I 1, I 2]]]]
                                    , I 2
                                    ]
                                ]
                            ]
                        ]
             in ( fromBuiltinData (BuiltinData nested) ::
                    Maybe Threshold
                )
                    `shouldBe` Nothing

    -- Rule 13 (no nested weighted list) is enforced structurally by the
    -- typed API ('Weight' holds two 'Integer's, so a nested weighted
    -- threshold is unrepresentable) AND at the decode boundary: a nested
    -- weighted-list 'Data' shape fails 'fromData' (asserted above).

    -- ------------------------------------------------------
    -- evaluate
    -- ------------------------------------------------------
    describe "evaluate Unweighted" $ do
        it "2-of-3 satisfied by two signers" $
            evaluate (Unweighted 2) 3 (IntSet.fromList [0, 1])
                `shouldBe` True
        it "2-of-3 unsatisfied by one signer" $
            evaluate (Unweighted 2) 3 (IntSet.fromList [0])
                `shouldBe` False
        it "ignores out-of-range signer positions" $
            evaluate (Unweighted 2) 3 (IntSet.fromList [0, 7])
                `shouldBe` False

    describe "evaluate Weighted" $ do
        let half3 = Weighted [[Weight 1 2, Weight 1 2, Weight 1 2]]
        it "single clause: two halves reach 1" $
            evaluate half3 3 (IntSet.fromList [0, 1]) `shouldBe` True
        it "single clause: one half is short of 1" $
            evaluate half3 3 (IntSet.fromList [0]) `shouldBe` False
        let andClauses = Weighted [[Weight 1 1], [Weight 1 1]]
        it "multi-clause is ANDed: both clauses satisfied" $
            evaluate andClauses 2 (IntSet.fromList [0, 1])
                `shouldBe` True
        it "multi-clause is ANDed: one clause unsatisfied fails" $
            evaluate andClauses 2 (IntSet.fromList [0]) `shouldBe` False
        it "order-independent within a clause (sum is commutative)" $
            evaluate half3 3 (IntSet.fromList [2, 0])
                `shouldBe` evaluate half3 3 (IntSet.fromList [0, 2])
        let reserve = Weighted [[Weight 0 1, Weight 1 1]]
        it "a zero-weight signer contributes nothing" $
            evaluate reserve 2 (IntSet.fromList [0]) `shouldBe` False
        it "a full-weight signer satisfies despite a zero-weight peer" $
            evaluate reserve 2 (IntSet.fromList [1]) `shouldBe` True
        let keripyMc =
                Weighted
                    [ [Weight 1 2, Weight 1 2, Weight 1 2]
                    , [Weight 1 1, Weight 1 1]
                    ]
        it "keripy multi-clause vector: both clauses reached" $
            -- clause 0 needs two of three halves; clause 1 needs both ones
            evaluate keripyMc 5 (IntSet.fromList [0, 2, 3, 4])
                `shouldBe` True
        it "keripy multi-clause vector: unsigned second clause fails" $
            evaluate keripyMc 5 (IntSet.fromList [0, 1, 2])
                `shouldBe` False

    -- ------------------------------------------------------
    -- 1-of-1 degenerate equivalence
    -- ------------------------------------------------------
    describe "1-of-1 degenerate equivalence" $ do
        it "Unweighted 1 and Weighted [[1/1]] evaluate identically" $
            evaluate (Unweighted 1) 1 (IntSet.fromList [0])
                `shouldBe` evaluate
                    (Weighted [[Weight 1 1]])
                    1
                    (IntSet.fromList [0])
        it "both are well-formed over a single key" $
            ( wellFormed [k1] (Unweighted 1) == Right ()
                && wellFormed [k1] (Weighted [[Weight 1 1]]) == Right ()
            )
                `shouldSatisfy` id
        it "an unsatisfiable Unweighted 2-of-1 is rejected (not id)" $
            wellFormed [k1] (Unweighted 2) `shouldSatisfy` isLeft
