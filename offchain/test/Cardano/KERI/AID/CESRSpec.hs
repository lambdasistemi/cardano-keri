module Cardano.KERI.AID.CESRSpec (spec) where

import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive)
import Cardano.Crypto.DSIGN
    ( SignKeyDSIGN
    , genKeyDSIGN
    , rawSerialiseSigDSIGN
    , rawSerialiseVerKeyDSIGN
    , signDSIGN
    , deriveVerKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Data.ByteArray.Encoding (Base (Base64URLUnpadded), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

deterministicKey :: SignKeyDSIGN Ed25519DSIGN
deterministicKey = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 0x01))

-- Encode bytes as a CESR 1-char primitive: prefix + unpadded base64url
cesr1 :: Char -> ByteString -> ByteString
cesr1 code payload =
    let lead = BS.singleton 0x00  -- 1 lead byte
        raw = lead <> payload
        encoded = convertToBase Base64URLUnpadded raw :: ByteString
    in BS.singleton (fromIntegral (fromEnum code)) <> BS.tail encoded

-- Encode bytes as a CESR 2-char primitive: prefix + unpadded base64url
cesr2 :: ByteString -> ByteString -> ByteString
cesr2 code payload =
    let lead = BS.replicate 2 0x00  -- 2 lead bytes
        raw = lead <> payload
        encoded = convertToBase Base64URLUnpadded raw :: ByteString
    in code <> BS.drop 2 encoded

spec :: Spec
spec = describe "CESR" $ do
    let sk = deterministicKey
        vkBytes = rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN sk)
        msg = "hello" :: ByteString
        sigBytes = rawSerialiseSigDSIGN (signDSIGN () msg sk)
        digestBytes = BS.replicate 32 0xAB

    it "round-trips an Ed25519 public key (B code)" $ do
        let encoded = cesr1 'B' vkBytes
        parsePrimitive encoded `shouldBe` Right (Ed25519PublicKey vkBytes, "")

    it "round-trips an Ed25519 signature (0B code)" $ do
        let encoded = cesr2 "0B" sigBytes
        parsePrimitive encoded `shouldBe` Right (Ed25519Signature sigBytes, "")

    it "round-trips a self-addressing identifier (E code)" $ do
        let encoded = cesr1 'E' digestBytes
        parsePrimitive encoded `shouldBe` Right (SelfAddressing digestBytes, "")

    it "returns unconsumed remainder" $ do
        let encoded = cesr1 'E' digestBytes <> "extra"
        case parsePrimitive encoded of
            Right (_, rest) -> rest `shouldBe` "extra"
            Left err -> fail err

    it "rejects empty input" $
        parsePrimitive "" `shouldSatisfy` \case Left _ -> True; _ -> False

    it "rejects truncated input" $
        parsePrimitive "B" `shouldSatisfy` \case Left _ -> True; _ -> False

    it "rejects unknown 1-char code" $ do
        let encoded = cesr1 'X' (BS.replicate 32 0x00)
        parsePrimitive encoded `shouldSatisfy` \case Left _ -> True; _ -> False
