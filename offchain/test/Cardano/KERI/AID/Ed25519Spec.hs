module Cardano.KERI.AID.Ed25519Spec (spec) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Data.ByteString qualified as BS
import Test.Hspec (Spec, describe, it, shouldBe)

deterministicKey :: SignKeyDSIGN Ed25519DSIGN
deterministicKey = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 0x01))

spec :: Spec
spec = describe "Ed25519" $ do
    let sk = deterministicKey
        vk = rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN sk)
        msg = "hello cardano-keri" :: BS.ByteString
        sig = rawSerialiseSigDSIGN (signDSIGN () msg sk)

    it "accepts a valid signature" $
        verifyEd25519 vk msg sig `shouldBe` True

    it "rejects a tampered message" $
        verifyEd25519 vk "wrong" sig `shouldBe` False

    it "rejects a tampered signature" $
        verifyEd25519 vk msg (BS.map (+ 1) sig) `shouldBe` False

    it "rejects an invalid public key" $
        verifyEd25519 (BS.replicate 32 0x00) msg sig `shouldBe` False
