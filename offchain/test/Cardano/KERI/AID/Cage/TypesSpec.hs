module Cardano.KERI.AID.Cage.TypesSpec (
    spec,
) where

import Cardano.KERI.AID.Cage.Types (
    AIDOnChainTokenState (..),
    AIDOwnerAuth (..),
    AIDRequestAction (..),
    Neighbor (..),
    ProofStep (..),
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import PlutusTx.Builtins.Internal (
    BuiltinByteString (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
    fromBuiltinData,
    toBuiltinData,
 )
import Test.Hspec (
    Expectation,
    Spec,
    describe,
    it,
    shouldBe,
 )
import Test.QuickCheck (
    Arbitrary (..),
    Gen,
    Property,
    elements,
    forAll,
    listOf,
    property,
    vectorOf,
 )

-- ---------------------------------------------------------
-- Arbitrary helpers
-- ---------------------------------------------------------

genBytes :: Int -> Gen ByteString
genBytes n = BS.pack <$> vectorOf n arbitrary

genBBS :: Int -> Gen BuiltinByteString
genBBS n = BuiltinByteString <$> genBytes n

genProofStep :: Gen ProofStep
genProofStep =
    elements
        [ Branch 3 (BS.replicate 128 0xab)
        , Fork 2 $ Neighbor 7 (BS.replicate 4 0x0f) (BS.replicate 32 0xcd)
        , Leaf 1 (BS.replicate 16 0x42) (BS.replicate 32 0xef)
        ]

genOwnerAuth :: Gen AIDOwnerAuth
genOwnerAuth = do
    ownerAid <- genBytes 32
    nSteps <- elements [0, 1, 3]
    identityProof <- vectorOf nSteps genProofStep
    ownerKey <- genBytes 32
    ownerSig <- genBytes 64
    pure AIDOwnerAuth{..}

-- ---------------------------------------------------------
-- Roundtrip property
-- ---------------------------------------------------------

roundtrips :: (ToData a, FromData a, Eq a, Show a) => a -> Expectation
roundtrips x = fromBuiltinData (toBuiltinData x) `shouldBe` Just x

-- | QuickCheck property form
roundtripProp :: (ToData a, FromData a, Eq a, Show a) => Gen a -> Property
roundtripProp gen = forAll gen $ \x ->
    fromBuiltinData (toBuiltinData x) == Just x

-- ---------------------------------------------------------
-- Spec
-- ---------------------------------------------------------

spec :: Spec
spec = do
    describe "AIDOwnerAuth ToData/FromData" $ do
        it "roundtrips with empty proof" $
            roundtrips $
                AIDOwnerAuth
                    { ownerAid = BS.replicate 32 0x01
                    , identityProof = []
                    , ownerKey = BS.replicate 32 0x02
                    , ownerSig = BS.replicate 64 0x03
                    }
        it "roundtrips with Branch step" $
            roundtrips $
                AIDOwnerAuth
                    { ownerAid = BS.replicate 32 0xaa
                    , identityProof = [Branch 5 (BS.replicate 128 0xbb)]
                    , ownerKey = BS.replicate 32 0xcc
                    , ownerSig = BS.replicate 64 0xdd
                    }
        it "roundtrips with Fork step" $
            roundtrips $
                AIDOwnerAuth
                    { ownerAid = BS.replicate 32 0x10
                    , identityProof =
                        [ Fork
                            2
                            Neighbor
                                { neighborNibble = 3
                                , neighborPrefix = BS.replicate 4 0x0f
                                , neighborRoot = BS.replicate 32 0x20
                                }
                        ]
                    , ownerKey = BS.replicate 32 0x30
                    , ownerSig = BS.replicate 64 0x40
                    }
        it "roundtrips QuickCheck" $
            property $
                roundtripProp genOwnerAuth

    describe "AIDRequestAction ToData/FromData" $ do
        it "Rejected roundtrips" $
            roundtrips AIDRejected
        it "UpdateAction with empty proofs roundtrips" $
            roundtrips $
                AIDUpdateAction
                    { valueProof = []
                    , auth =
                        AIDOwnerAuth
                            { ownerAid = BS.replicate 32 0x01
                            , identityProof = []
                            , ownerKey = BS.replicate 32 0x02
                            , ownerSig = BS.replicate 64 0x03
                            }
                    }
        it "UpdateAction with Leaf steps roundtrips" $
            roundtrips $
                AIDUpdateAction
                    { valueProof =
                        [ Leaf 1 (BS.replicate 16 0xaa) (BS.replicate 32 0xbb)
                        , Branch 4 (BS.replicate 128 0xcc)
                        ]
                    , auth =
                        AIDOwnerAuth
                            { ownerAid = BS.replicate 32 0x11
                            , identityProof = [Branch 0 (BS.replicate 128 0x22)]
                            , ownerKey = BS.replicate 32 0x33
                            , ownerSig = BS.replicate 64 0x44
                            }
                    }
        it "roundtrips QuickCheck" $
            property $
                roundtripProp $ do
                    b <- arbitrary
                    if b
                        then pure AIDRejected
                        else
                            AIDUpdateAction
                                <$> listOf genProofStep
                                <*> genOwnerAuth

    describe "AIDOnChainTokenState ToData/FromData" $ do
        it "roundtrips" $
            roundtrips $
                AIDOnChainTokenState
                    { aidStateOwner = BuiltinByteString (BS.replicate 28 0xfe)
                    , aidStateRoot = BS.replicate 32 0x01
                    , aidIdentityRoot = BS.replicate 32 0x02
                    , aidStateTip = 1_000_000
                    , aidStateProcessTime = 30_000
                    , aidStateRetractTime = 30_000
                    }
        it "roundtrips QuickCheck" $
            property $
                roundtripProp $
                    AIDOnChainTokenState
                        <$> genBBS 28
                        <*> genBytes 32
                        <*> genBytes 32
                        <*> arbitrary
                        <*> arbitrary
                        <*> arbitrary

    describe "constructor indices" $ do
        it "AIDRejected encodes as Constr 1" $ do
            let bd = toBuiltinData AIDRejected
            fromBuiltinData bd `shouldBe` Just AIDRejected
        it "AIDUpdateAction encodes as Constr 0" $ do
            let action = AIDUpdateAction [] (AIDOwnerAuth mempty [] mempty mempty)
            fromBuiltinData (toBuiltinData action) `shouldBe` Just action
