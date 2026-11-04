module Cardano.KERI.AID.Checkpoint.FreezeBondSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.FreezeBond (
    freezeBondFloor,
    freezeBondValid,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec =
    describe "freeze-bond deployment parameters" $ do
        it "accepts the 5,000,000-lovelace mechanical floor" $
            freezeBondValid freezeBondFloor `shouldBe` True
        it "rejects one lovelace below the mechanical floor" $
            freezeBondValid (freezeBondFloor - 1) `shouldBe` False
