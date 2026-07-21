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
    ArmedDatum (..),
    ArmedDatumError (..),
    DeadlineError (..),
    Inclusivity (..),
    RawBound (..),
    Role (..),
    armDeadline,
    armedDatumWellFormed,
    claimAtOrAfterDeadline,
    freezeBondFloor,
    freezeBondValid,
    freezeWindowValid,
    responseBeforeDeadline,
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
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
    fromBuiltinData,
    toBuiltinData,
 )
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
        it "requires a strictly positive freeze window" $
            map freezeWindowValid [-1, 0, 1] `shouldBe` [False, False, True]

    describe "checkpoint roles" $ do
        it "keeps existing role tags exact and adds ARMED at 0x02" $
            map roleTag [Active, Frozen, Tombstone, Armed]
                `shouldBe` [Nothing, Just "\x00", Just "\x01", Just "\x02"]
        it "keeps the historical FROZEN and TOMBSTONE role hashes exact" $ do
            roleHash policy Frozen
                `shouldBe` Just
                    (hexBs "881658d75a7a9154184d35b016cab83368059bf0c0da1befde545ea6")
            roleHash policy Tombstone
                `shouldBe` Just
                    (hexBs "44f8b57fb50b9ffee7ec21037a031a61b5b3919a7fee4f5eab4cea77")
        it "derives the new ARMED role hash from tag 0x02" $
            roleHash policy Armed
                `shouldBe` Just
                    (hexBs "d5a386b02d995fcb2295d04733fc0501108a70d7351a504c53ba711e")
        it "does not invent a staking-role hash for bare ACTIVE" $
            roleHash policy Active `shouldBe` Nothing

    describe "ArmedV1 wire codec" $ do
        it "uses constructor 0 as the version tag around checkpoint, hunter, deadline" $
            dataOf armedDatum
                `shouldBe` Constr
                    0
                    [ dataOf checkpointV1
                    , B hunter
                    , I 1001
                    ]
        it "has the exact canonical CBOR golden" $
            canonicalCbor armedDatum `shouldBe` hexBs armedGolden
        it "round-trips through Plutus Data" $
            fromBuiltinData (toBuiltinData armedDatum) `shouldBe` Just armedDatum
        it "accepts exactly a 28-byte hunter key hash" $
            armedDatumWellFormed armedDatum `shouldBe` Right ()
        it "rejects hunter key hashes below or above 28 bytes" $ do
            armedDatumWellFormed armedDatum{adHunterPkh = BS.replicate 27 0xbb}
                `shouldBe` Left HunterPkhWidth
            armedDatumWellFormed armedDatum{adHunterPkh = BS.replicate 29 0xbb}
                `shouldBe` Left HunterPkhWidth

    describe "arm deadline from the raw upper endpoint" $ do
        it "adds W_freeze to the finite endpoint without moving exclusive bounds" $ do
            armDeadline 500 (Just (Finite 1000 Inclusive)) `shouldBe` Right 1500
            armDeadline 500 (Just (Finite 1000 Exclusive)) `shouldBe` Right 1500
        it "rejects a missing or infinite upper endpoint" $ do
            armDeadline 500 Nothing `shouldBe` Left MissingUpperBound
            armDeadline 500 (Just NegativeInfinity) `shouldBe` Left NonFiniteUpperBound
            armDeadline 500 (Just PositiveInfinity) `shouldBe` Left NonFiniteUpperBound
        it "rejects a non-positive freeze window" $ do
            armDeadline 0 (Just (Finite 1000 Inclusive))
                `shouldBe` Left NonPositiveFreezeWindow
            armDeadline (-1) (Just (Finite 1000 Inclusive))
                `shouldBe` Left NonPositiveFreezeWindow
        it "uses arbitrary-precision integer addition without an artificial cap" $
            armDeadline 10 (Just (Finite (10 ^ (100 :: Integer)) Exclusive))
                `shouldBe` Right (10 ^ (100 :: Integer) + 10)

    describe "raw deadline boundary verdicts" $ do
        it "allows response only when the raw finite upper endpoint is before deadline" $ do
            responseBeforeDeadline deadline (Just (Finite 999 Inclusive)) `shouldBe` True
            responseBeforeDeadline deadline (Just (Finite 999 Exclusive)) `shouldBe` True
            responseBeforeDeadline deadline (Just (Finite 1000 Inclusive)) `shouldBe` False
            responseBeforeDeadline deadline (Just (Finite 1000 Exclusive)) `shouldBe` False
            responseBeforeDeadline deadline (Just (Finite 1001 Inclusive)) `shouldBe` False
        it "allows claim only when the raw finite lower endpoint is at or after deadline" $ do
            claimAtOrAfterDeadline deadline (Just (Finite 999 Inclusive)) `shouldBe` False
            claimAtOrAfterDeadline deadline (Just (Finite 1000 Inclusive)) `shouldBe` True
            claimAtOrAfterDeadline deadline (Just (Finite 1000 Exclusive)) `shouldBe` True
            claimAtOrAfterDeadline deadline (Just (Finite 1001 Exclusive)) `shouldBe` True
        it "rejects missing and unbounded required endpoints" $ do
            responseBeforeDeadline deadline Nothing `shouldBe` False
            responseBeforeDeadline deadline (Just PositiveInfinity) `shouldBe` False
            claimAtOrAfterDeadline deadline Nothing `shouldBe` False
            claimAtOrAfterDeadline deadline (Just NegativeInfinity) `shouldBe` False

    describe "historical canonical bytes" $ do
        it "keeps CheckpointDatumV1 bytes unchanged" $
            canonicalCbor (V1 checkpointV1)
                `shouldBe` hexBs checkpointGolden
        it "keeps TombstoneV1 bytes unchanged" $
            canonicalCbor tombstone
                `shouldBe` hexBs
                    "d8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa015820ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccff"

-- | Underlying canonical Plutus 'Data' tree of a value.
dataOf :: (ToData a) => a -> Data
dataOf x = let BuiltinData d = toBuiltinData x in d

-- | Decode an ASCII hexadecimal fixture.
hexBs :: ByteString -> ByteString
hexBs = either error id . convertFromBase Base16

policy :: ByteString
policy = BS.replicate 28 0xcc

hunter :: ByteString
hunter = BS.replicate 28 0xbb

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

armedDatum :: ArmedDatum
armedDatum =
    ArmedV1
        { adCheckpoint = checkpointV1
        , adHunterPkh = hunter
        , adDeadline = 1001
        }

tombstone :: TombstoneV1
tombstone =
    TombstoneV1
        (BS.replicate 32 0xaa)
        1
        (BS.replicate 32 0xcc)

deadline :: Integer
deadline = 1000

checkpointGolden :: ByteString
checkpointGolden =
    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        <> "9f58200101010101010101010101010101010101010101010101010101010101010101ff"
        <> "d8799f01ff"
        <> "9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0aff"
        <> "d8799f01ff80000000ffff"

armedGolden :: ByteString
armedGolden =
    "d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        <> "9f58200101010101010101010101010101010101010101010101010101010101010101ff"
        <> "d8799f01ff"
        <> "9f58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0aff"
        <> "d8799f01ff80000000ff"
        <> "581cbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        <> "1903e9ff"
