{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.DeployedGenerationSpec
Description : the bytes the deployed builders put on the wire do not move

The commands that run against the deployed preprod generation (register,
advance, freeze, top-up) build their redeemers with these functions. The
expected bytes were taken from the builders at the commit this generation
replaced the registration and migration arms; a changed constructor index or
field order changes the bytes and fails here.
-}
module Cardano.KERI.AID.Checkpoint.DeployedGenerationSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Deposit (BondOption (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceSpendRedeemerData,
    convictSpendRedeemerData,
    freezeSpendRedeemerData,
    topUpSpendRedeemerData,
 )
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinByteString (..), BuiltinData (..), serialiseData)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- | The canonical CBOR of a Plutus datum, as base 16 text.
hexOf :: Data -> ByteString
hexOf d =
    let BuiltinByteString bytes = serialiseData (BuiltinData d)
     in convertToBase Base16 bytes

spec :: Spec
spec = describe "the deployed generation's wire bytes" $ do
    it "Advance, keep the bond, payee output 4 is spend constructor 0" $
        hexOf (advanceSpendRedeemerData 4 Keep)
            `shouldBe` "d8799f04d87980ff"
    it "Advance with the deposit option carries its signatures" $
        hexOf (advanceSpendRedeemerData 4 (Deposit [(1, BS.replicate 64 0xa1)]))
            `shouldBe` "d8799f04d87a9f9f9f015840a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1ffffffff"
    it "Convict is spend constructor 1" $
        hexOf (convictSpendRedeemerData (BS.replicate 28 0x51) 3)
            `shouldBe` "d87a9f581c5151515151515151515151515151515151515151515151515151515103ff"
    it "Freeze is spend constructor 3, after the retired migration index" $
        hexOf (freezeSpendRedeemerData 5) `shouldBe` "d87c9f05ff"
    it "TopUp is spend constructor 4" $
        hexOf (topUpSpendRedeemerData 2000000) `shouldBe` "d87d9f1a001e8480ff"
    it "a changed constructor index changes the bytes (the control can fail)" $
        hexOf (Constr 2 [I 5]) `shouldSatisfy` (/= hexOf (freezeSpendRedeemerData 5))
