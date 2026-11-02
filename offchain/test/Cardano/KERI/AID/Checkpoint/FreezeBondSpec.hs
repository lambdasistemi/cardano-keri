module Cardano.KERI.AID.Checkpoint.FreezeBondSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Enforcement (
    TombstoneV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (
    Role (..),
    freezeBondFloor,
    freezeBondValid,
    roleHash,
    roleTag,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = do
    describe "freeze-bond deployment parameters" $ do
        it "accepts the 5,000,000-lovelace mechanical floor" $
            freezeBondValid freezeBondFloor `shouldBe` True
        it "rejects one lovelace below the mechanical floor" $
            freezeBondValid (freezeBondFloor - 1) `shouldBe` False

    describe "checkpoint roles" $ do
        it "keeps the role tags exact" $
            map roleTag [Active, Tombstone]
                `shouldBe` [Nothing, Just "\x01"]
        it "keeps the historical TOMBSTONE role hash exact" $
            roleHash policy Tombstone
                `shouldBe` Just
                    (hexBs "44f8b57fb50b9ffee7ec21037a031a61b5b3919a7fee4f5eab4cea77")
        it "does not invent a staking-role hash for bare ACTIVE" $
            roleHash policy Active `shouldBe` Nothing

    describe "historical canonical bytes" $ do
        it "keeps CheckpointDatumV1 bytes unchanged" $
            canonicalCbor (V1 checkpointV1)
                `shouldBe` hexBs checkpointGolden
        it "keeps TombstoneV1 bytes unchanged" $
            canonicalCbor tombstone
                `shouldBe` hexBs
                    "d8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa015820ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccff"

-- | Decode an ASCII hexadecimal fixture.
hexBs :: ByteString -> ByteString
hexBs = either error id . convertFromBase Base16

policy :: ByteString
policy = BS.replicate 28 0xcc

checkpointV1 :: CheckpointDatumV1
checkpointV1 =
    CheckpointDatumV1
        { cdCesrAid = BS.replicate 32 0xaa
        , cdCurKeys = [BS.replicate 32 0x01]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x0a]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }

tombstone :: TombstoneV1
tombstone =
    TombstoneV1
        (BS.replicate 32 0xaa)
        1
        (BS.replicate 32 0xcc)

checkpointGolden :: ByteString
checkpointGolden =
    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        <> "9f58200101010101010101010101010101010101010101010101010101010101010101ff"
        <> "d8799f01ff"
        <> "9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0aff"
        <> "d8799f01ff80000000ffff"
