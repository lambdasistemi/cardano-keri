module Cardano.KERI.AID.Cage.SignSpec
    ( spec
    ) where

import Cardano.KERI.AID.Cage.Sign
    ( signValueWrite
    , valueWriteMessage
    )
import Cardano.KERI.AID.Ed25519
    ( verifyEd25519
    )
import Cardano.Crypto.DSIGN
    ( SignKeyDSIGN
    , deriveVerKeyDSIGN
    , genKeyDSIGN
    , rawSerialiseVerKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Crypto.Seed
    ( mkSeedFromBytes
    )
import qualified Data.ByteString as BS
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

-- ---------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------

-- | Fixed seed for deterministic tests.
testSignKey :: Cardano.Crypto.DSIGN.SignKeyDSIGN Ed25519DSIGN
testSignKey = genKeyDSIGN $ mkSeedFromBytes $ BS.replicate 32 0x42

testPubKeyBytes :: BS.ByteString
testPubKeyBytes =
    rawSerialiseVerKeyDSIGN $ deriveVerKeyDSIGN testSignKey

fakeTxId :: BS.ByteString
fakeTxId = BS.replicate 32 0xde

-- ---------------------------------------------------------
-- Spec
-- ---------------------------------------------------------

spec :: Spec
spec = do
    describe "valueWriteMessage" $ do
        it "is 32 bytes" $
            BS.length (valueWriteMessage fakeTxId 0) `shouldBe` 32
        it "differs for different output indices" $
            valueWriteMessage fakeTxId 0
                /= valueWriteMessage fakeTxId 1
                `shouldBe` True
        it "differs for different tx ids" $
            valueWriteMessage fakeTxId 0
                /= valueWriteMessage (BS.replicate 32 0xab) 0
                `shouldBe` True

    describe "signValueWrite" $ do
        it "produces a signature that verifies" $ do
            let sig = signValueWrite testSignKey fakeTxId 0
                msg = valueWriteMessage fakeTxId 0
            verifyEd25519 testPubKeyBytes msg sig `shouldBe` True

        it "rejects sig over wrong tx_id" $ do
            let sig = signValueWrite testSignKey fakeTxId 0
                wrongMsg = valueWriteMessage (BS.replicate 32 0xff) 0
            verifyEd25519 testPubKeyBytes wrongMsg sig `shouldBe` False

        it "rejects sig over wrong output index" $ do
            let sig = signValueWrite testSignKey fakeTxId 0
                wrongMsg = valueWriteMessage fakeTxId 1
            verifyEd25519 testPubKeyBytes wrongMsg sig `shouldBe` False

        it "rejects sig verified against wrong public key" $ do
            let sig = signValueWrite testSignKey fakeTxId 0
                msg = valueWriteMessage fakeTxId 0
                wrongKey = BS.replicate 32 0x00
            verifyEd25519 wrongKey msg sig `shouldBe` False

        it "is deterministic" $ do
            let sig1 = signValueWrite testSignKey fakeTxId 42
                sig2 = signValueWrite testSignKey fakeTxId 42
            sig1 `shouldBe` sig2

        it "output index 255 and 256 produce different messages" $ do
            valueWriteMessage fakeTxId 255
                /= valueWriteMessage fakeTxId 256
                `shouldBe` True
