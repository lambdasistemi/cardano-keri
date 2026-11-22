{- |
Module      : Cardano.KERI.ChainQuery.ReleaseIdentitySpec
Description : The release identity file: encoding, decoding and refusals (#353)

A deployer writes one JSON file naming the release the readers follow. The
checks quantify over the extent of the encoding rather than a list written
beside it: every field of a generated identity's encoding is deleted in turn
(a distinct @MissingField@), every hash and transaction id is cut and
lengthened (@WrongLength@) and replaced by non-hex text of the right length
(@NotHex@), every amount is made negative (@NegativeAmount@). Decoding what
was encoded returns the identity, for generated identities at many sizes, and
a document written by hand decodes to the expected identity.
-}
module Cardano.KERI.ChainQuery.ReleaseIdentitySpec (
    spec,
) where

import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Cardano.KERI.AID.ReleaseSpec (exampleIdentity, genReleaseIdentity)
import Cardano.KERI.ChainQuery.ReleaseIdentity (
    ReleaseIdentityError (..),
    decodeReleaseIdentity,
    encodeReleaseIdentity,
 )
import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Functor.Identity (Identity (..))
import Data.List (nub)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Test.Hspec (Spec, describe, it, shouldBe)
import Test.QuickCheck (
    conjoin,
    counterexample,
    forAll,
    property,
    (===),
 )

-- | The path of every leaf of a JSON document.
leafPaths :: Value -> [[Text]]
leafPaths = \case
    Object o -> [Key.toText k : p | (k, v) <- KeyMap.toList o, p <- leafPaths v]
    _ -> [[]]

dotted :: [Text] -> Text
dotted = T.intercalate "."

at :: [Text] -> Value -> Maybe Value
at [] v = Just v
at (k : ks) (Object o) = KeyMap.lookup (Key.fromText k) o >>= at ks
at _ _ = Nothing

modifyAt :: [Text] -> (Maybe Value -> Maybe Value) -> Value -> Value
modifyAt [] _ v = v
modifyAt [k] f (Object o) =
    Object (runIdentity (KeyMap.alterF (Identity . f) (Key.fromText k) o))
modifyAt (k : ks) f (Object o) =
    Object (runIdentity (KeyMap.alterF (Identity . fmap (modifyAt ks f)) (Key.fromText k) o))
modifyAt _ _ v = v

render :: Value -> ByteString
render = BL.toStrict . Aeson.encode

encodedValue :: ReleaseIdentity -> Value
encodedValue ri =
    fromMaybe Null (Aeson.decodeStrict (encodeReleaseIdentity ri))

{- | Decode the document with this exact JSON number text at a path: the number is
written as a sentinel and its text replaced in the rendered document, so
exponent notation (which the encoder never writes) reaches the decoder.
-}
decodeWithLiteral :: [Text] -> ByteString -> ReleaseIdentity -> Either ReleaseIdentityError ReleaseIdentity
decodeWithLiteral path literal ri =
    decodeReleaseIdentity (replaceOnce sentinel literal rendered)
  where
    sentinel = "424242424242"
    rendered = render (modifyAt path (const (Just (Number 424242424242))) (encodedValue ri))
    replaceOnce needle replacement bytes =
        let (before, rest) = BS.breakSubstring needle bytes
         in before <> replacement <> BS.drop (BS.length needle) rest

decodeWith :: (Value -> Value) -> ReleaseIdentity -> Either ReleaseIdentityError ReleaseIdentity
decodeWith edit = decodeReleaseIdentity . render . edit . encodedValue

-- | Fields holding a hash or transaction id, with their length in bytes.
hashFields :: [([Text], Int)]
hashFields =
    [ (["release", "application_policy"], 28)
    , (["release", "application_credential"], 28)
    , (["release", "state_program"], 28)
    , (["release", "state_policy"], 28)
    , (["seed", "transaction_id"], 32)
    , (["checkpoint_validator"], 28)
    ]

amountFields :: [[Text]]
amountFields =
    ["seed", "index"]
        : [ ["amounts", n]
          | n <-
                [ "deposit"
                , "freeze_bond"
                , "premium"
                , "minimum_ada"
                , "termination_carrier"
                ]
          ]
            <> [ ["application_parameters", n]
               | n <-
                    [ "registration_cost"
                    , "minimum_tip"
                    , "process_time"
                    , "booking_width"
                    ]
               ]

{- | The constructor name of an error: what makes two refusals distinct.
| Integers far outside any field's range, positive and negative: each must reach
the check of its own field and not be masked by an earlier one.
-}
large :: [Integer]
large = [10 ^ (40 :: Int), negate (10 ^ (40 :: Int)), 10 ^ (1_000 :: Int), negate (10 ^ (1_000 :: Int))]

-- | Exact integers written with an exponent, with the integer each stands for.
exponents :: [(ByteString, Integer)]
exponents =
    [ ("1e40", 10 ^ (40 :: Int))
    , ("-1e40", negate (10 ^ (40 :: Int)))
    , ("1E+40", 10 ^ (40 :: Int))
    , ("1e1000", 10 ^ (1_000 :: Int))
    , ("-1e1000", negate (10 ^ (1_000 :: Int)))
    ]

kind :: ReleaseIdentityError -> String
kind = takeWhile (/= ' ') . show

{- | A document as a deployer writes it: every byte string is one byte
repeated, in hexadecimal.
-}
handwritten :: ByteString
handwritten =
    BC.pack $
        concat
            [ "{\"schema_version\":1,\"network\":0,"
            , "\"release\":{"
            , "\"application_policy\":\"" <> rep 28 "01" <> "\","
            , "\"application_credential\":\"" <> rep 28 "02" <> "\","
            , "\"state_program\":\"" <> rep 28 "03" <> "\","
            , "\"state_policy\":\"" <> rep 28 "04" <> "\"},"
            , "\"seed\":{\"transaction_id\":\"" <> rep 32 "05" <> "\",\"index\":7},"
            , "\"checkpoint_validator\":\"" <> rep 28 "06" <> "\","
            , "\"amounts\":{\"deposit\":8000000,\"freeze_bond\":2000000,"
            , "\"premium\":500000,\"minimum_ada\":2000000,"
            , "\"termination_carrier\":1500000},"
            , "\"application_parameters\":{\"registration_cost\":1000000,"
            , "\"minimum_tip\":500000,\"process_time\":90000,"
            , "\"booking_width\":5000}}"
            ]
  where
    rep n = concat . replicate n

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.ReleaseIdentity" $ do
    describe "round trip" $ do
        it "decodes what it encodes, for generated identities" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    decodeReleaseIdentity (encodeReleaseIdentity ri) === Right ri
        it "writes the schema version, the network and the amounts as numbers" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    let v = encodedValue ri
                     in conjoin
                            [ at ["schema_version"] v === Just (Number 1)
                            , at ["network"] v
                                === Just (Number (fromIntegral (riNetwork ri)))
                            , at ["amounts", "deposit"] v
                                === Just (Number (fromIntegral (riDeposit ri)))
                            ]
        it "reads a document written by hand" $
            decodeReleaseIdentity handwritten `shouldBe` Right exampleIdentity
    describe "refusals" $ do
        it "names every field of the encoding it deletes: one MissingField each" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ counterexample
                            (T.unpack (dotted path))
                            ( decodeWith (modifyAt path (const Nothing)) ri
                                === Left (MissingField (dotted path))
                            )
                        | path <- leafPaths (encodedValue ri)
                        , path /= ["schema_version"]
                        ]
        it "reads a document without a schema version as one it does not know" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    decodeWith (modifyAt ["schema_version"] (const Nothing)) ri
                        === Left (MissingField "schema_version")
        it "refuses an unknown schema version" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ decodeWith
                            (modifyAt ["schema_version"] (const (Just (Number (fromIntegral v)))))
                            ri
                            === Left (UnknownSchemaVersion v)
                        | v <- [0, 2, 3, -1, 1_000] <> large
                        ]
        it "reads a number written with an exponent as the integer it is, and refuses it by its own field" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        ( [ decodeWithLiteral ["schema_version"] lit ri === Left (UnknownSchemaVersion v)
                          | (lit, v) <- exponents
                          ]
                            <> [ decodeWithLiteral ["network"] lit ri === Left (NetworkOutOfRange v)
                               | (lit, v) <- exponents
                               ]
                            <> [ decodeWithLiteral path lit ri === Left (NegativeAmount (dotted path))
                               | path <- amountFields
                               , (lit, v) <- exponents
                               , v < 0
                               ]
                        )
        it "refuses a hash or transaction id of the wrong length, naming the field" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ conjoin
                            [ counterexample (T.unpack (dotted path)) $
                                decodeWith
                                    (modifyAt path (fmap (resize delta)))
                                    ri
                                    === Left (WrongLength (dotted path) len (len + delta))
                            | delta <- [-1, 1, -len]
                            ]
                        | (path, len) <- hashFields
                        ]
        it "refuses a hash or transaction id that is not hexadecimal" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ decodeWith
                            (modifyAt path (const (Just (String (T.replicate (2 * len) "z")))))
                            ri
                            === Left (NotHex (dotted path))
                        | (path, len) <- hashFields
                        ]
        it "refuses a negative amount, naming the field" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ decodeWith (modifyAt path (const (Just (Number (fromIntegral n))))) ri
                            === Left (NegativeAmount (dotted path))
                        | path <- amountFields
                        , n <- [-1] <> map negate (filter (> 0) large)
                        ]
        it "refuses a network outside its range" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ decodeWith (modifyAt ["network"] (const (Just (Number (fromIntegral n))))) ri
                            === Left (NetworkOutOfRange n)
                        | n <- [2, 3, 256, -1] <> large
                        ]
        it "refuses a field of another type" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    conjoin
                        [ decodeWith (modifyAt path (const (Just (Bool True)))) ri
                            === Left (WrongType (dotted path))
                        | path <- amountFields <> map fst hashFields <> [["network"]]
                        ]
        it "refuses text that is not JSON and JSON that is not an object" $ do
            kind' (decodeReleaseIdentity "{") `shouldBe` "NotJson"
            decodeReleaseIdentity "[1]" `shouldBe` Left (NotAnObject "")
        it "refuses a nested object that is not an object" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    decodeWith (modifyAt ["release"] (const (Just (Number 1)))) ri
                        === Left (NotAnObject "release")
        it "gives every kind of refusal its own error" $
            property $
                forAll genReleaseIdentity $ \ri ->
                    let refusals =
                            [ decodeWith (modifyAt ["network"] (const Nothing)) ri
                            , decodeWith (modifyAt ["schema_version"] (const (Just (Number 2)))) ri
                            , decodeWith (modifyAt ["checkpoint_validator"] (const (Just (String "zz")))) ri
                            , decodeWith (modifyAt ["checkpoint_validator"] (const (Just (String "00")))) ri
                            , decodeWith (modifyAt ["amounts", "deposit"] (const (Just (Number (-5))))) ri
                            , decodeWith (modifyAt ["network"] (const (Just (Number 9)))) ri
                            , decodeWith (modifyAt ["network"] (const (Just (Bool False)))) ri
                            , decodeWith (modifyAt ["seed"] (const (Just Null))) ri
                            , decodeReleaseIdentity "{"
                            ]
                     in length (nub (map kind' refusals)) === length refusals
  where
    kind' = either kind (const "Right")
    resize delta (String hex) =
        String (T.take (T.length hex + 2 * delta) (hex <> T.replicate (2 * delta) "00"))
    resize _ v = v
