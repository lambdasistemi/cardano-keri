{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.FutureDeclarationSpec
Description : The future (next) declaration of an inception, against the admission rule of the model

The ordinary inception admission, as the December model map states it: the
declared next width is bounded by the signed commitments, the weights of both
thresholds are at most one, next fractions have positive denominators, and a
numeric zero is a valid future threshold; the current threshold needs a satisfied
signing quorum. 'futureWellFormed' applies the inception rule to numeric zero and
the F18 well-formedness to every other declaration. Each row below pins what the
implementation answers; a row marked @narrower@ is refused here by an F18 rule the
stated admission rule does not name, so it may be a case the model admits.
-}
module Cardano.KERI.AID.Checkpoint.FutureDeclarationSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Registration (futureThresholdMatches, respellThreshold)
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
    futureThresholdFromData,
    futureWellFormed,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import PlutusTx.IsData.Class (FromData (..), ToData (..))
import Test.Hspec (Spec, describe, it, shouldBe)

commitments :: Int -> [ByteString]
commitments n = [BS.replicate 32 (fromIntegral k) | k <- [1 .. n]]

spec :: Spec
spec = describe "the future declaration of an inception" $ do
    describe "agrees with the stated admission rule" $ do
        row "no commitments, numeric zero" 0 (Unweighted 0) (Right ())
        row "one commitment, numeric zero" 1 (Unweighted 0) (Right ())
        row "three commitments, numeric zero" 3 (Unweighted 0) (Right ())
        row "one commitment, one of one" 1 (Unweighted 1) (Right ())
        row "three commitments, two of three" 3 (Unweighted 2) (Right ())
        row "three commitments, three of three" 3 (Unweighted 3) (Right ())
        row "width above the commitments" 1 (Unweighted 2) (Left UnweightedRange)
        row "no commitments, a positive threshold" 0 (Unweighted 1) (Left UnweightedRange)
        row "a weight above one" 1 (Weighted [[Weight 3 2]]) (Left OverUnityWeight)
        row "a zero denominator" 1 (Weighted [[Weight 1 0]]) (Left NonPositiveDen)
        row "a weighted clause over every commitment" 2 (Weighted [[Weight 1 2, Weight 1 2]]) (Right ())
        row "a weighted threshold of whole weights" 2 (Weighted [[Weight 1 1], [Weight 1 1]]) (Right ())
    describe "the four rows of Q-069 and their neighbours, by rational value" $ do
        row "a clause of 1/3 + 1/3 does not reach one" 2 (Weighted [[Weight 1 3, Weight 1 3]]) (Left UnsatisfiableClause)
        row "an unreduced clause of 2/4 + 2/4 reaches one" 2 (Weighted [[Weight 2 4, Weight 2 4]]) (Right ())
        row "two whole-weight clauses over three commitments" 3 (Weighted [[Weight 1 1], [Weight 1 1]]) (Right ())
        row "a whole-weight clause over no commitments" 0 (Weighted [[Weight 1 1]]) (Left PartitionMismatch)
        row "a second clause below one beside a clause that reaches it" 2 (Weighted [[Weight 1 1], [Weight 1 3]]) (Left UnsatisfiableClause)
        row "no clauses" 0 (Weighted []) (Left EmptyClause)
        row "an empty clause" 1 (Weighted [[]]) (Left EmptyClause)
        row "a weight below zero" 1 (Weighted [[Weight (-1) 2]]) (Left NegativeNum)
    describe "commitments" $ do
        it "a duplicated commitment is refused" $
            futureWellFormed (commitments 1 <> commitments 1) (Unweighted 0) `shouldBe` Left DuplicateKey
        it "a commitment of another width is refused" $
            futureWellFormed [BS.replicate 31 1] (Unweighted 0) `shouldBe` Left KeyWidth
    describe "the future threshold as the datum carries it keeps the signed pair" $ do
        it "reads the pair (2,4) as signed, where the frozen weight codec asks for lowest terms" $ do
            futureThresholdFromData (toBuiltinData (Weighted [[Weight 2 4, Weight 2 4]]))
                `shouldBe` Just (Weighted [[Weight 2 4, Weight 2 4]])
            (fromBuiltinData (toBuiltinData (Weight 2 4)) :: Maybe Weight) `shouldBe` Nothing
        it "keeps refusing a weight that is not a fraction of one" $ do
            futureThresholdFromData (toBuiltinData (Weighted [[Weight 3 2]])) `shouldBe` Nothing
            futureThresholdFromData (toBuiltinData (Weighted [[Weight 1 0]])) `shouldBe` Nothing
            futureThresholdFromData (toBuiltinData (Weighted [[Weight (-1) 2]])) `shouldBe` Nothing
        it "reads a numeric threshold" $
            futureThresholdFromData (toBuiltinData (Unweighted 0)) `shouldBe` Just (Unweighted 0)
    describe "E7: the signed future threshold against the datum's, pair for pair (draft #600 at ce10e471, InceptionPrefix.verify)" $ do
        let weights = [(n, d) | d <- [1 .. 6], n <- [0 .. d]]
            scalings = [2, 3 :: Integer]
        it "matches a datum that carries the signed pairs, over every pair with denominator 1 to 6" $
            and [futureThresholdMatches (respellThreshold (Weighted [[Weight n d, Weight n d]])) (Weighted [[Weight n d, Weight n d]]) | (n, d) <- weights]
                `shouldBe` True
        it "refuses a datum whose pair has the same value but another numerator and denominator, in both directions" $
            [ (n, d, k)
            | (n, d) <- weights
            , k <- scalings
            , futureThresholdMatches (respellThreshold (Weighted [[Weight (n * k) (d * k)]])) (Weighted [[Weight n d]])
                || futureThresholdMatches (respellThreshold (Weighted [[Weight n d]])) (Weighted [[Weight (n * k) (d * k)]])
            ]
                `shouldBe` []
        it "refuses a datum that differs in one pair of a clause, in clause order, or in clause count" $ do
            let signed = respellThreshold (Weighted [[Weight 1 2, Weight 1 3], [Weight 1 1]])
            futureThresholdMatches signed (Weighted [[Weight 1 2, Weight 1 3], [Weight 1 1]]) `shouldBe` True
            futureThresholdMatches signed (Weighted [[Weight 1 3, Weight 1 2], [Weight 1 1]]) `shouldBe` False
            futureThresholdMatches signed (Weighted [[Weight 1 2, Weight 1 3]]) `shouldBe` False
            futureThresholdMatches signed (Weighted [[Weight 1 2, Weight 2 6], [Weight 1 1]]) `shouldBe` False
        it "keeps the numeric threshold by exact spelling" $ do
            futureThresholdMatches (respellThreshold (Unweighted 1)) (Unweighted 1) `shouldBe` True
            futureThresholdMatches (respellThreshold (Unweighted 2)) (Unweighted 1) `shouldBe` False
  where
    row name count threshold expected =
        it name $ futureWellFormed (commitments count) threshold `shouldBe` expected
