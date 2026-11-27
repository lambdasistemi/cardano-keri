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

import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    ThresholdError (..),
    Weight (..),
    futureWellFormed,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
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
        row "no commitments, a positive threshold" 0 (Unweighted 1) (Left EmptyKeys)
        row "a weight above one" 1 (Weighted [[Weight 3 2]]) (Left OverUnityWeight)
        row "a zero denominator" 1 (Weighted [[Weight 1 0]]) (Left NonPositiveDen)
        row "a weighted clause over every commitment" 2 (Weighted [[Weight 1 2, Weight 1 2]]) (Right ())
        row "a weighted threshold of whole weights" 2 (Weighted [[Weight 1 1], [Weight 1 1]]) (Right ())
    describe "narrower than the stated rule: refused by an F18 rule the rule does not name" $ do
        row "a clause whose weights do not reach one (narrower)" 2 (Weighted [[Weight 1 3, Weight 1 3]]) (Left UnsatisfiableClause)
        row "an unreduced fraction (narrower)" 2 (Weighted [[Weight 2 4, Weight 2 4]]) (Left UnreducedWeight)
        row "clauses that cover fewer commitments than are signed (narrower)" 3 (Weighted [[Weight 1 1], [Weight 1 1]]) (Left PartitionMismatch)
        row "a weighted threshold with no commitments (narrower)" 0 (Weighted [[Weight 1 1]]) (Left EmptyKeys)
    describe "commitments" $ do
        it "a duplicated commitment is refused" $
            futureWellFormed (commitments 1 <> commitments 1) (Unweighted 0) `shouldBe` Left DuplicateKey
        it "a commitment of another width is refused" $
            futureWellFormed [BS.replicate 31 1] (Unweighted 0) `shouldBe` Left KeyWidth
  where
    row name count threshold expected =
        it name $ futureWellFormed (commitments count) threshold `shouldBe` expected
