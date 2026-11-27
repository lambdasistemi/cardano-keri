{- |
Module      : Cardano.KERI.AID.Checkpoint.InceptionPrefixSpec
Description : The prefix binding of an inception over keripy's fifteen cases (#590)

The fifteen indexed inceptions of the model draft #600 are built by keripy 1.3.5
(@gen_prefix_cases.py@): the seven keripy admits are decoded from their exact
bytes and bound to their prefix kind; the eight it refuses at construction have
no bytes, and their rules are checked on decoded events altered one field at a
time, the refusal controls at their boundary. Transferable and non-transferable
basic prefixes are kept apart.
-}
module Cardano.KERI.AID.Checkpoint.InceptionPrefixSpec (spec) where

import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    EventVariant (..),
    decodeEstablishmentEvent,
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    decodeHex,
    loadFixture,
    lookupKey,
    textField,
 )
import Cardano.KERI.AID.Checkpoint.InceptionPrefix (
    PrefixKind (..),
    PrefixRefusal (..),
    classifyIdentifier,
    verifyPrefixBinding,
 )
import Data.Aeson (Value (..))
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as B8
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (Spec, describe, it, runIO, shouldBe)

-- | One of the fifteen cases, with keripy's verdict and its artifacts if admitted.
data Case = Case
    { cLabel :: Text
    , cExpected :: Bool
    , cAdmitted :: Bool
    , cRaw :: Maybe ByteString
    , cPre :: Maybe ByteString
    , cSaid :: Maybe ByteString
    }

spec :: Spec
spec = describe "#590 inception prefix binding (keripy 1.3.5, draft #600)" $ do
    fixture <- runIO (loadFixture "inception_prefix_cases.json")
    let cases = either (error . ("cases: " <>)) id (loadCases fixture)
        admitted = [c | c <- cases, cAdmitted c]
        decoded c = case cRaw c >>= either (const Nothing) Just . decodeEstablishmentEvent of
            Just d -> d
            Nothing -> error ("does not decode: " <> T.unpack (cLabel c))
        named label = case [d | c <- admitted, cLabel c == label, let d = decoded c] of
            [d] -> d
            _ -> error ("no admitted case " <> T.unpack label)
        kindOfLabel label = case T.take 1 label of
            "B" -> BasicPrefix False
            "D" -> BasicPrefix True
            _ -> SelfAddressingPrefix
    it "has the model's fifteen cases, seven admitted by keripy" $
        (length cases, length admitted) `shouldBe` (15, 7)
    it "agrees with the model's verdict on every case" $
        [cLabel c | c <- cases, cAdmitted c /= cExpected c] `shouldBe` []
    describe "the derivation code decides the kind" $ do
        it "classifies the codes of the model" $
            map
                (classifyIdentifier . codeText)
                ["B", "1AAA", "1AAC", "1AAI", "D", "1AAB", "1AAD", "1AAJ", "E", "F", "G", "H", "I", "0D", "0E", "0F", "0G"]
                `shouldBe` map Just
                    ( replicate 4 (BasicPrefix False)
                        <> replicate 4 (BasicPrefix True)
                        <> replicate 9 SelfAddressingPrefix
                    )
        it "refuses a code outside the ordinary basic and self-addressing domain" $
            map (classifyIdentifier . codeText) ["X", "1AAF", "0A", "J"] `shouldBe` replicate 4 Nothing
    describe "the seven inceptions keripy admits" $ do
        it "decode with the identifier and own SAID keripy computed" $
            [ (cLabel c, Just (deeAid (decoded c)) == cPre c, Just (deeSaid (decoded c)) == cSaid c)
            | c <- admitted
            ]
                `shouldBe` [(cLabel c, True, True) | c <- admitted]
        it "keep a key-derived identifier distinct from the own SAID, and equal a self-addressing one" $
            [(cLabel c, deeAid (decoded c) == deeSaid (decoded c)) | c <- admitted]
                `shouldBe` [(cLabel c, T.take 1 (cLabel c) == "E") | c <- admitted]
        it "are bound to their prefix kind" $
            [(cLabel c, verifyPrefixBinding (decoded c)) | c <- admitted]
                `shouldBe` [(cLabel c, Right (kindOfLabel (cLabel c))) | c <- admitted]
        it "carry their anchors as the full array text" $
            ( deeAnchors (named "D empty")
            , B8.isPrefixOf "[{" (deeAnchors (named "D seal"))
            )
                `shouldBe` ("[]", True)
    describe "refusal controls on the decoded event" $ do
        let b = named "B empty"
            d = named "D empty"
            e = named "E digest"
            refuses what event = verifyPrefixBinding event `shouldBe` Left what
        it "a key other than the identifier is refused" $
            refuses KeyIsNotTheIdentifier d{deeK = [deeAid (named "B empty")]}
        it "two keys are refused" $
            refuses KeyIsNotTheIdentifier d{deeK = [deeAid d, deeAid b]}
        it "a signing threshold other than numeric one is refused" $ do
            refuses SigningThresholdIsNotOne d{deeKt = "2"}
            refuses SigningThresholdIsNotOne d{deeKt = "[\"1\"]"}
        it "a non-transferable prefix with next keys, witnesses or seals is refused" $ do
            refuses NonTransferableHasNextKeys b{deeN = [deeSaid d]}
            refuses NonTransferableHasWitnesses b{deeB = [deeAid b]}
            refuses NonTransferableHasSeals b{deeAnchors = deeAnchors (named "D seal")}
        it "the same next keys, witnesses and seals are admitted for a transferable prefix" $
            map
                (verifyPrefixBinding . named)
                ["D next", "D witness", "D seal"]
                `shouldBe` replicate 3 (Right (BasicPrefix True))
        it "a self-addressing identifier that is not the digest of the body is refused" $ do
            refuses IdentifierIsNotDerived e{deeAid = deeAid d, deeSaid = deeSaid e}
            refuses IdentifierIsNotDerived e{deeSaidPreimage = deeSaidPreimage d}
        it "an event that is not an inception is refused" $
            refuses NotAnInception d{deeVariant = VariantRot}
        it "an identifier of an unknown code is refused" $
            refuses UnknownDerivationCode d{deeAid = "X" <> B8.drop 1 (deeAid d)}
        it "a self-addressing code other than the supported digest is not admitted" $
            refuses UnsupportedDerivation e{deeAid = "F" <> B8.drop 1 (deeAid e)}
  where
    -- a qualified text that starts with the given code, padded to a plausible width
    codeText code = B8.pack (T.unpack code) <> B8.replicate 44 'A'

loadCases :: Value -> Either String [Case]
loadCases fx = do
    cases <- maybe (Left "no cases") Right (lookupKey "cases" fx)
    case cases of
        Array xs -> mapM one (toList xs)
        _ -> Left "cases is not an array"
  where
    one c = do
        label <- textField c "label"
        let flag key = case lookupKey key c of
                Just (Bool v) -> Right v
                _ -> Left ("no flag " <> T.unpack key)
        expected <- flag "expected"
        admitted <- flag "admitted"
        raw <- optionalHex c "raw_hex"
        pre <- optionalText c "pre"
        said <- optionalText c "said"
        Right (Case label expected admitted raw pre said)
    optionalHex c key = case lookupKey key c of
        Just (String t) -> Just <$> decodeHex t
        _ -> Right Nothing
    optionalText c key = case lookupKey key c of
        Just (String t) -> Right (Just (TE.encodeUtf8 t))
        _ -> Right Nothing

