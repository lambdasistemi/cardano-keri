module Cardano.KERI.AID.Blake3.CheckpointSpec (
    spec,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (
    Blake3Checkpoint (..),
    CheckpointDatum (..),
    CheckpointRedeemer (..),
    absorbBlocks,
    blake3Hash,
    blake3Verify,
    finishFromCheckpoint,
    initialChainingValue,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Foldable (
    traverse_,
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
    UnsafeFromData (..),
    fromBuiltinData,
    toBuiltinData,
    unsafeFromBuiltinData,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = do
    describe "Blake3 checkpoint vectors" $ do
        traverse_
            vectorExample
            [ (0, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
            , (1, "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213")
            , (63, "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b")
            , (64, "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98")
            , (65, "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee")
            , (127, "d81293fda863f008c09e92fc382a81f5a0b4a1251cba1634016a0f86a6bd640d")
            , (128, "f17e570564b26578c33bb7f44643f539624b05df1a76c81f30acd548c44b45ef")
            , (1023, "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11")
            , (1024, "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7")
            ]

        it "verifies the 1024-byte whole input" $
            blake3Verify
                (vectorInput 1024)
                (hex "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7")
                `shouldBe` True

        it "finishes the 1024-byte 8+8 split from offset 512" $ do
            let input = vectorInput 1024
                Blake3Checkpoint cv offset =
                    absorbBlocks initialChainingValue input 0 8
            offset `shouldBe` 512
            finishFromCheckpoint cv input offset
                `shouldBe` hex
                    "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"

    describe "Blake3 checkpoint PlutusData" $ do
        it "roundtrips datum through safe and unsafe decoders" $ do
            let datum =
                    CheckpointDatum
                        { inputCommitment = BS.replicate 32 0x01
                        , checkpointCv = initialChainingValue
                        , checkpointOffset = 512
                        , checkpointLength = 1024
                        , expectedDigest = blake3Hash $ vectorInput 1024
                        }
                encoded = toBuiltinData datum
            fromBuiltinData encoded `shouldBe` Just datum
            unsafeFromBuiltinData encoded `shouldBe` datum

        it "roundtrips Step and Finish redeemers" $ do
            let step = CheckpointStep (vectorInput 1024) 8
                finish = CheckpointFinish (vectorInput 1024)
            fromBuiltinData (toBuiltinData step) `shouldBe` Just step
            fromBuiltinData (toBuiltinData finish) `shouldBe` Just finish
            unsafeFromBuiltinData (toBuiltinData step) `shouldBe` step
            unsafeFromBuiltinData (toBuiltinData finish) `shouldBe` finish

        it "encodes datum constructor index and field order exactly" $
            unBuiltin (toBuiltinData sampleDatum)
                `shouldBe` Constr
                    0
                    [ B $ inputCommitment sampleDatum
                    , B $ checkpointCv sampleDatum
                    , I $ checkpointOffset sampleDatum
                    , I $ checkpointLength sampleDatum
                    , B $ expectedDigest sampleDatum
                    ]

        it "encodes Step constructor index and field order exactly" $
            unBuiltin (toBuiltinData sampleStep)
                `shouldBe` Constr
                    0
                    [ B $ stepInput sampleStep
                    , I $ stepBlocks sampleStep
                    ]

        it "encodes Finish constructor index and field order exactly" $
            unBuiltin (toBuiltinData sampleFinish)
                `shouldBe` Constr
                    1
                    [ B $ finishInput sampleFinish
                    ]

vectorExample :: (Int, ByteString) -> Spec
vectorExample (len, expectedHex) =
    it ("hashes official hash-mode vector length " <> show len) $
        blake3Hash (vectorInput len) `shouldBe` hex expectedHex

vectorInput :: Int -> ByteString
vectorInput len =
    BS.pack $ fmap (fromIntegral . (`mod` 251)) [0 .. len - 1]

hex :: ByteString -> ByteString
hex encoded =
    case traverse nibble $ BS.unpack encoded of
        Just nibbles -> BS.pack $ bytes nibbles
        Nothing -> error "invalid test hex"
  where
    bytes (hi : lo : rest) = (hi * 16 + lo) : bytes rest
    bytes [] = []
    bytes [_] = error "odd-length test hex"

    nibble byte
        | byte >= 48 && byte <= 57 = Just $ byte - 48
        | byte >= 65 && byte <= 70 = Just $ byte - 55
        | byte >= 97 && byte <= 102 = Just $ byte - 87
        | otherwise = Nothing

unBuiltin :: BuiltinData -> Data
unBuiltin (BuiltinData datum) = datum

sampleDatum :: CheckpointDatum
sampleDatum =
    CheckpointDatum
        { inputCommitment = BS.replicate 32 0x11
        , checkpointCv = BS.replicate 32 0x22
        , checkpointOffset = 512
        , checkpointLength = 1024
        , expectedDigest =
            hex "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"
        }

sampleStep :: CheckpointRedeemer
sampleStep = CheckpointStep (BS.pack [0x01, 0x02, 0x03]) 8

sampleFinish :: CheckpointRedeemer
sampleFinish = CheckpointFinish $ BS.pack [0x04, 0x05, 0x06]
