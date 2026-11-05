{- |
Module      : Cardano.KERI.AID.Checkpoint.NineFieldDatumSpec
Description : The live checkpoint datum has nine fields, the top-up mark at index 7 (#346)

The version 2 live datum is constructor 0 of nine fields: aid, sn, epoch,
poisoned, frozen, born_at, refund_to, @topped_up@ (a Boolean), keys. The
datums below are built field by field as 'Data', beside the typed codec the
library exposes: a spec that built them with the codec under test could not
disagree with it. An eight-field live datum (the retired width), a ten-field
one and a mark that is not a Boolean are refused; the termination-pending
datum is unchanged.
-}
module Cardano.KERI.AID.Checkpoint.NineFieldDatumSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    checkpointDatumFromData,
    checkpointDatumToData,
 )
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BC
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

aidText :: ByteString
aidText = BC.pack "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"

flag :: Bool -> Data
flag b = Constr (if b then 1 else 0) []

-- | The key material: one current key, one next digest, no witnesses.
keysData :: Data
keysData =
    Constr
        0
        [ List [B (BC.replicate 32 'k')]
        , Constr 0 [I 1]
        , List [B (BC.replicate 32 'n')]
        , Constr 0 [I 1]
        , List []
        , I 0
        ]

-- | The nine fields of a live datum, in wire order.
nineFields :: Bool -> Bool -> Bool -> [Data]
nineFields poisoned frozen toppedUp =
    [ B aidText
    , I 4
    , I 2
    , flag poisoned
    , flag frozen
    , I 100
    , B (BC.replicate 29 'r')
    , flag toppedUp
    , keysData
    ]

live :: [Data] -> Data
live fields = Constr 1 [Constr 0 fields]

withMark :: Data -> [Data] -> [Data]
withMark mark fields = take 7 fields <> [mark] <> drop 8 fields

spec :: Spec
spec = describe "live checkpoint datum of nine fields" $ do
    describe "accepted" $ do
        mapM_
            ( \(name, poisoned, frozen, marked) ->
                it ("reads and writes the datum " <> name) $ do
                    let wire = live (nineFields poisoned frozen marked)
                    fmap checkpointDatumToData (checkpointDatumFromData wire)
                        `shouldBe` Just wire
            )
            [ ("with the mark clear", False, False, False)
            , ("with the mark set", False, False, True)
            , ("poisoned and marked", True, False, True)
            , ("frozen and marked", False, True, True)
            , ("frozen, poisoned and marked", True, True, True)
            ]
        it "reads the mark as the Boolean at index 7" $ do
            let mark wire = case checkpointDatumFromData wire of
                    Just (V2 Live{lvToppedUp}) -> Just lvToppedUp
                    _ -> Nothing
            mark (live (nineFields False False False)) `shouldBe` Just False
            mark (live (nineFields False False True)) `shouldBe` Just True
        it "leaves the termination-pending datum as it was" $ do
            let wire = Constr 1 [Constr 1 [B aidText, I 4, I 2]]
            fmap checkpointDatumToData (checkpointDatumFromData wire)
                `shouldBe` Just wire
    describe "refused" $ do
        it "refuses the retired live datum of eight fields" $
            checkpointDatumFromData
                (live (take 7 (nineFields False False False) <> [keysData]))
                `shouldBe` Nothing
        it "refuses a live datum of ten fields" $
            checkpointDatumFromData
                (live (nineFields False False False <> [I 0]))
                `shouldBe` Nothing
        it "refuses a mark that is an integer" $
            checkpointDatumFromData
                (live (withMark (I 1) (nineFields False False False)))
                `shouldBe` Nothing
        it "refuses a mark of another constructor" $
            checkpointDatumFromData
                (live (withMark (Constr 2 []) (nineFields False False False)))
                `shouldBe` Nothing
        it "refuses a mark that carries a field" $
            checkpointDatumFromData
                (live (withMark (Constr 1 [I 0]) (nineFields False False False)))
                `shouldBe` Nothing
        it "refuses key material in the mark's place" $
            checkpointDatumFromData
                (live (withMark keysData (nineFields False False False)))
                `shouldBe` Nothing
