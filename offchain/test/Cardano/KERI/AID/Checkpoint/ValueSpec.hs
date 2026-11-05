{- |
Module      : Cardano.KERI.AID.Checkpoint.ValueSpec
Description : The lovelace a version 2 checkpoint holds against the Lean vectors

The rows are those of @lean\/checkpoint-value-vectors.json@ (minimum ADA 4,
deposit 8, freeze bond 2): the floor and the held value of each state, and the
pool each lovelace amount reads as. The premium cases are the Lean
@rotateKeepPaid@ and @rotateKeepUnpaid@ clauses: the premium is paid exactly
when the pool covers it.
-}
module Cardano.KERI.AID.Checkpoint.ValueSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Value (
    RotationSettlement (..),
    heldValue,
    rotationSettlement,
    valueFloor,
    withValue,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

mc, d, b :: Integer
mc = 4
d = 8
b = 2

keys :: KeyMaterial
keys =
    KeyMaterial
        { kmCurKeys = []
        , kmCurThreshold = Unweighted 1
        , kmNextKeys = []
        , kmNextThreshold = Unweighted 1
        , kmWitnesses = []
        , kmToad = 0
        }

live :: Bool -> CheckpointDatumV2
live frozen = liveMarked frozen False

liveMarked :: Bool -> Bool -> CheckpointDatumV2
liveMarked frozen toppedUp =
    Live
        { lvAid = "aid"
        , lvSn = 4
        , lvEpoch = 2
        , lvPoisoned = False
        , lvFrozen = frozen
        , lvBornAt = 100
        , lvRefundTo = "refund"
        , lvToppedUp = toppedUp
        , lvKeys = keys
        }

pending :: CheckpointDatumV2
pending =
    TerminationPending{tpAid = "aid", tpSn = 4, tpEpoch = 2}

spec :: Spec
spec = describe "Checkpoint.Value (Lean checkpoint-value-vectors)" $ do
    it "floors a live output at Mc + D + B and a frozen one at Mc + D" $ do
        valueFloor mc d b (live False) `shouldBe` 14
        valueFloor mc d b (live True) `shouldBe` 12

    it "holds the same value whatever the top-up mark says (Lean held row topped-up)" $ do
        let marked = liveMarked False True
        valueFloor mc d b marked `shouldBe` valueFloor mc d b (live False)
        heldValue mc d b marked 4 `shouldBe` heldValue mc d b (live False) 4
        withValue mc d b marked 18 `shouldBe` withValue mc d b (live False) 18

    it "floors a pending termination at Mc whatever the pool" $ do
        valueFloor mc d b pending `shouldBe` 4
        heldValue mc d b pending 9 `shouldBe` 4

    it "holds the floor plus the pool" $ do
        heldValue mc d b (live False) 5_000_000 `shouldBe` 5_000_014
        heldValue mc d b (live True) 3 `shouldBe` 15

    it "reads the pool above the floor and refuses an amount below it" $ do
        withValue mc d b (live False) 5_000_014 `shouldBe` Just 5_000_000
        withValue mc d b (live False) 14 `shouldBe` Just 0
        withValue mc d b (live False) 13 `shouldBe` Nothing
        withValue mc d b (live True) 15 `shouldBe` Just 3
        withValue mc d b (live True) 11 `shouldBe` Nothing

    it "reads a pending termination only at exactly Mc" $ do
        withValue mc d b pending 4 `shouldBe` Just 0
        withValue mc d b pending 5 `shouldBe` Nothing
        withValue mc d b pending 3 `shouldBe` Nothing

    it "pays the premium out of a pool that covers it, to the lovelace" $ do
        rotationSettlement mc d b 3 (live False) 20
            `shouldBe` Just (RotationSettlement 3 3)
        rotationSettlement mc d b 3 (live False) 17
            `shouldBe` Just (RotationSettlement 3 0)

    it "pays nothing and keeps the pool when one lovelace short" $
        rotationSettlement mc d b 3 (live False) 16
            `shouldBe` Just (RotationSettlement 0 2)

    it "settles a frozen output against its own floor" $
        rotationSettlement mc d b 3 (live True) 18
            `shouldBe` Just (RotationSettlement 3 3)

    it "refuses an output below its floor or pending" $ do
        rotationSettlement mc d b 3 (live False) 13 `shouldBe` Nothing
        rotationSettlement mc d b 3 pending 4 `shouldBe` Nothing
