{- |
Module      : Cardano.KERI.AID.ReleaseSpec
Description : The release identity in the library, against the consumer predicate (#353)

The Lean consumer model takes a 'Context' and an 'Environment' as given. The
release identity is the one value both are built from, so the checks below ask
the library's own 'representativeAsset' and 'consumableHolding' (the producers)
rather than a copy of their results:

* the context an identity builds names the identity's network, release, seed
  and checkpoint validator, for any AID;
* the environment an identity builds authenticates every context of the same
  identity, and no context of an identity that differs in the network, the
  state policy or the checkpoint validator;
* the registry identity an identity names, and the active token name the
  Application module derives from it, are the ones the consumer's
  'representativeAsset' computes.
-}
module Cardano.KERI.AID.ReleaseSpec (
    spec,

    -- * Shared with the codec specification
    genReleaseIdentity,
    exampleIdentity,
) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    Credential (..),
    OutputReference (..),
    RegistryIdentity (..),
    activeTokenName,
    stateTokenName,
 )
import Cardano.KERI.AID.Consumer (
    Clause (..),
    Context (..),
    Environment (..),
    ObservedOutput (..),
    Release (..),
    consumableHolding,
    representativeAsset,
 )
import Cardano.KERI.AID.Release (
    ReleaseIdentity (..),
    registryIdentityOf,
    releaseContext,
    releaseEnvironment,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Test.Hspec (Spec, describe, it, shouldNotBe)
import Test.QuickCheck (
    Gen,
    choose,
    chooseInteger,
    elements,
    forAll,
    property,
    vectorOf,
    (===),
 )

genBytes :: Int -> Gen ByteString
genBytes n = BS.pack <$> vectorOf n (fromIntegral <$> choose (0 :: Int, 255))

genAmount :: Gen Integer
genAmount = chooseInteger (0, 50_000_000)

-- | An identity with hashes of the lengths the chain uses, at n > 1 sizes.
genReleaseIdentity :: Gen ReleaseIdentity
genReleaseIdentity = do
    riNetwork <- elements [0, 1]
    riRelease <-
        Release
            <$> genBytes 28
            <*> genBytes 28
            <*> genBytes 28
            <*> genBytes 28
    riSeed <- OutputReference <$> genBytes 32 <*> chooseInteger (0, 65_535)
    riCheckpointValidator <- genBytes 28
    riDeposit <- genAmount
    riFreezeBond <- genAmount
    riPremium <- genAmount
    riMinimumAda <- genAmount
    riTerminationCarrier <- genAmount
    riApplicationParameters <-
        ApplicationParameters
            <$> genAmount
            <*> genAmount
            <*> genAmount
            <*> genAmount
    pure ReleaseIdentity{..}

-- | A fixed identity, written out by hand: the shape of a deployer's file.
exampleIdentity :: ReleaseIdentity
exampleIdentity =
    ReleaseIdentity
        { riNetwork = 0
        , riRelease =
            Release
                { rlApplicationPolicy = BS.replicate 28 0x01
                , rlApplicationCredential = BS.replicate 28 0x02
                , rlStateProgram = BS.replicate 28 0x03
                , rlStatePolicy = BS.replicate 28 0x04
                }
        , riSeed = OutputReference (BS.replicate 32 0x05) 7
        , riCheckpointValidator = BS.replicate 28 0x06
        , riDeposit = 8_000_000
        , riFreezeBond = 2_000_000
        , riPremium = 500_000
        , riMinimumAda = 2_000_000
        , riTerminationCarrier = 1_500_000
        , riApplicationParameters =
            ApplicationParameters
                { registrationCost = 1_000_000
                , minimumTip = 500_000
                , processTime = 90_000
                , bookingWidth = 5_000
                }
        }

genAid :: Gen ByteString
genAid = genBytes 44

-- | An output at the identity's checkpoint validator holding nothing.
emptyOutputAt :: ReleaseIdentity -> ObservedOutput
emptyOutputAt ri =
    ObservedOutput
        { ooCredential = ScriptCredential (riCheckpointValidator ri)
        , ooAssets = []
        , ooDatum = Nothing
        }

authenticates :: ReleaseIdentity -> ReleaseIdentity -> ByteString -> Bool
authenticates environmentOf contextOf aid =
    ContextNotAuthenticated
        `notElem` consumableHolding
            0
            0
            (releaseEnvironment environmentOf)
            (releaseContext contextOf aid)
            (emptyOutputAt contextOf)

spec :: Spec
spec = describe "Cardano.KERI.AID.Release" $ do
    describe "releaseContext" $ do
        it "names the identity's network, release, seed and checkpoint validator, for any AID" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    forAll genAid $ \aid ->
                        releaseContext ri aid
                            === Context
                                { cxNetwork = riNetwork ri
                                , cxRelease = riRelease ri
                                , cxSeed = riSeed ri
                                , cxAid = aid
                                , cxCheckpointCredential =
                                    ScriptCredential (riCheckpointValidator ri)
                                }
    describe "releaseEnvironment" $ do
        it "resolves the identity's network, release and checkpoint validator" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    releaseEnvironment ri
                        === Environment
                            { envNetwork = riNetwork ri
                            , envRelease = Just (riRelease ri)
                            , envCheckpointCredential =
                                Just (ScriptCredential (riCheckpointValidator ri))
                            }
        it "authenticates every context of its own identity" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    forAll genAid $ \aid -> authenticates ri ri aid
        it "authenticates no context of an identity that differs in the network" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    forAll genAid $ \aid ->
                        not
                            ( authenticates
                                ri{riNetwork = 1 - riNetwork ri}
                                ri
                                aid
                            )
        it "authenticates no context of an identity that differs in the state policy" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    forAll genAid $ \aid ->
                        let other =
                                ri
                                    { riRelease =
                                        (riRelease ri)
                                            { rlStatePolicy =
                                                BS.map (+ 1) (rlStatePolicy (riRelease ri))
                                            }
                                    }
                         in not (authenticates other ri aid)
        it "authenticates no context of an identity that differs in the checkpoint validator" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    forAll genAid $ \aid ->
                        let other =
                                ri
                                    { riCheckpointValidator =
                                        BS.map (+ 1) (riCheckpointValidator ri)
                                    }
                         in not (authenticates other ri aid)
    describe "registryIdentityOf" $ do
        it "is the state policy of the release and the state token name of the seed" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    registryIdentityOf ri
                        === RegistryIdentity
                            (rlStatePolicy (riRelease ri))
                            (stateTokenName (riSeed ri))
        it "derives the consumer's representative asset, for any AID" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    forAll genAid $ \aid ->
                        representativeAsset (releaseContext ri aid)
                            === ( rlStatePolicy (riRelease ri)
                                , activeTokenName (registryIdentityOf ri) aid
                                )
        it "gives two different registries different representative assets for one AID" $ do
            let other = exampleIdentity{riSeed = OutputReference (BS.replicate 32 0x05) 8}
                aid = BS.replicate 44 0x45
            representativeAsset (releaseContext exampleIdentity aid)
                `shouldNotBe` representativeAsset (releaseContext other aid)
            registryIdentityOf exampleIdentity `shouldNotBe` registryIdentityOf other
