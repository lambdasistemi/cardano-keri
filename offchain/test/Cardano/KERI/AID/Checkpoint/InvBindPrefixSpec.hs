{- |
Module      : Cardano.KERI.AID.Checkpoint.InvBindPrefixSpec
Description : The own SAID of an establishment event, by prefix kind (#291, #590)

The decoder's SAID-blanked preimage must hash to the SAID keripy computed, for
a key-derived (basic) prefix, where @i@ is the qualified key and only @d@ is
dressed, for a self-addressing prefix, where @i@ equals @d@ and both are
dressed, and for a rotation, where @i@ is the established identifier and only
@d@ is dressed. Every expected digest is keripy 1.3.5's, read from the fixture.
-}
module Cardano.KERI.AID.Checkpoint.InvBindPrefixSpec (spec) where

import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    EventVariant (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    loadFixture,
    lookupKey,
    note,
    textField,
 )
import Data.Aeson (Value (..))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (Spec, describe, it, runIO, shouldBe)

spec :: Spec
spec = describe "#291/#590 own SAID by prefix kind" $ do
    prefix <- runIO (loadFixture "inv_bind_prefix.json")
    fork <- runIO (loadFixture "fork.json")
    forkWitnessed <- runIO (loadFixture "fork_witnessed.json")
    honest <- runIO (loadFixture "honest_2key.json")
    let inceptions = either (error . ("prefix fixture: " <>)) id (prefixCases prefix)
        rotations =
            either (error . ("rotation fixtures: " <>)) id $
                sequence
                    [ eventOf fork "rot_recorded" "fork.rot_recorded"
                    , eventOf fork "rot_conflict" "fork.rot_conflict"
                    , eventOf forkWitnessed "rot_recorded" "fork_witnessed.rot_recorded"
                    , eventOf forkWitnessed "rot_conflict" "fork_witnessed.rot_conflict"
                    , eventOf honest "rot" "honest_2key.rot"
                    ]
        icp name = case filter ((== name) . ceName) inceptions of
            [c] -> c
            _ -> error ("no case " <> T.unpack name)
        i01 = icp "I01"
        i02 = icp "I02"
    describe "I01, a key-derived prefix (i is the qualified key, d is the SAID)" $ do
        it "decodes as an inception whose i differs from its d" $
            fmap (\d -> (deeVariant d, deeAid d == ceAid i01, deeSaid d == ceSaid i01, deeAid d == deeSaid d)) (decodeEstablishmentEvent (ceRaw i01))
                `shouldBe` Right (VariantIcp, True, True, False)
        it "dresses d only, so the preimage keeps i and hashes to keripy's own SAID" $
            fmap preimageFacts (decodeEstablishmentEvent (ceRaw i01))
                `shouldBe` Right (PreimageFacts{pfHashes = 44, pfKeepsAid = True, pfDigest = Just (ceSaid i01)})
    describe "I02, a self-addressing prefix (i equals d)" $ do
        it "decodes as an inception whose i equals its d" $
            fmap (\d -> (deeVariant d, deeAid d == ceAid i02, deeAid d == deeSaid d)) (decodeEstablishmentEvent (ceRaw i02))
                `shouldBe` Right (VariantIcp, True, True)
        it "dresses both d and i and hashes to keripy's own SAID" $
            fmap preimageFacts (decodeEstablishmentEvent (ceRaw i02))
                `shouldBe` Right (PreimageFacts{pfHashes = 88, pfKeepsAid = False, pfDigest = Just (ceSaid i02)})
    describe "rotations (i is the established identifier)" $
        it "dress d only and hash to keripy's own SAID" $
            map (fmap preimageFacts . decodeEstablishmentEvent . ceRaw) rotations
                `shouldBe` [Right (PreimageFacts{pfHashes = 44, pfKeepsAid = True, pfDigest = Just (ceSaid c)}) | c <- rotations]

-- | One signed event with keripy's identifier and own SAID.
data CorpusCase = CorpusCase
    { ceName :: Text
    , ceRaw :: ByteString
    , ceAid :: ByteString
    , ceSaid :: ByteString
    }

data PreimageFacts = PreimageFacts
    { pfHashes :: Int
    , pfKeepsAid :: Bool
    , pfDigest :: Maybe ByteString
    }
    deriving stock (Show, Eq)

-- | What the preimage dresses, and the SAID its BLAKE3 spells.
preimageFacts :: DecodedEstablishmentEvent -> PreimageFacts
preimageFacts d =
    PreimageFacts
        { pfHashes = BS.length (BS.filter (== 0x23) pre)
        , pfKeepsAid = deeAid d `BS.isInfixOf` pre
        , pfDigest = Just (qb64Aid (blake3Hash pre))
        }
  where
    pre = deeSaidPreimage d

prefixCases :: Value -> Either String [CorpusCase]
prefixCases fx = do
    cases <- arrayField fx "cases"
    mapM one cases
  where
    one c = do
        name <- textField c "id"
        raw <- textField c "raw"
        aid <- textField c "pre"
        said <- textField c "said"
        Right (CorpusCase name (TE.encodeUtf8 raw) (TE.encodeUtf8 aid) (TE.encodeUtf8 said))

-- | A rotation of a keripy family fixture, with its identifier from the event.
eventOf :: Value -> Text -> Text -> Either String CorpusCase
eventOf fx key label = do
    ev <- note ("missing " <> key) (lookupKey key fx)
    raw <- decodeHex =<< textField ev "raw_hex"
    said <- textField ev "said"
    aid <- ownAid raw
    Right (CorpusCase label raw aid (TE.encodeUtf8 said))
  where
    ownAid raw = case B8.breakSubstring "\"i\":\"" raw of
        (_, rest) | not (BS.null rest) -> Right (BS.take 44 (BS.drop 5 rest))
        _ -> Left "no i field"
