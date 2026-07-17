{- |
Module      : Cardano.KERI.AID.Checkpoint.FixtureLoader
Description : Shared committed-keripy-fixture loading + CESR decode helpers

Reusable test-support factored out of the Slice-2 @Keri68OracleSpec@: load a
committed fixture JSON via @Paths_cardano_keri@ data-files, drill 'Value'
fields, and decode the hex / qb64 primitives through the SHIPPED CESR parser
(never a hand-rolled base64url). Consumed by both @Keri68OracleSpec@ and the
Slice-3 @EnforcementSpec@.
-}
module Cardano.KERI.AID.Checkpoint.FixtureLoader (
    -- * Loading
    loadFixture,

    -- * Value drilling
    note,
    lookupKey,
    textField,
    intField,
    arrayField,
    textArrayField,

    -- * Decoders (shipped CESR / memory primitives)
    decodeHex,
    verkeyRaw,
    digestRaw,
) where

import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Data.Aeson (Value (..), eitherDecodeFileStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)

-- | Load a committed fixture by basename under @test/keri-fixtures/fixtures@.
loadFixture :: FilePath -> IO Value
loadFixture name = do
    path <- getDataFileName ("test/keri-fixtures/fixtures/" <> name)
    result <- eitherDecodeFileStrict path
    case result of
        Right v -> pure v
        Left err -> fail ("failed to decode " <> name <> ": " <> err)

-- | Lift a 'Maybe' into 'Either' with a message.
note :: Text -> Maybe a -> Either String a
note msg = maybe (Left (T.unpack msg)) Right

-- | Look up a key in a JSON object (else 'Nothing').
lookupKey :: Text -> Value -> Maybe Value
lookupKey k value = case value of
    Object o -> KM.lookup (K.fromText k) o
    _ -> Nothing

-- | Require a string field.
textField :: Value -> Text -> Either String Text
textField value k = note (k <> " missing or not a string") $ do
    field <- lookupKey k value
    case field of
        String t -> Just t
        _ -> Nothing

-- | Require an integer (JSON number) field.
intField :: Value -> Text -> Either String Integer
intField value k = note (k <> " missing or not an integer") $ do
    field <- lookupKey k value
    case field of
        Number s -> Just (truncate s)
        _ -> Nothing

-- | Require an array field.
arrayField :: Value -> Text -> Either String [Value]
arrayField value k = note (k <> " missing or not an array") $ do
    field <- lookupKey k value
    case field of
        Array a -> Just (toList a)
        _ -> Nothing

-- | Require an array-of-strings field.
textArrayField :: Value -> Text -> Either String [Text]
textArrayField value k = do
    elems <- arrayField value k
    traverse asText elems
  where
    asText (String t) = Right t
    asText _ = Left (T.unpack k <> ": element is not a string")

-- | Decode a base16 (hex) text to raw bytes.
decodeHex :: Text -> Either String ByteString
decodeHex t = convertFromBase Base16 (TE.encodeUtf8 t)

-- | Decode a qb64 verkey (@B@ or @D@) to its raw 32 bytes via shipped CESR.
verkeyRaw :: Text -> Either String ByteString
verkeyRaw t =
    parseFull t >>= \case
        Ed25519PublicKey raw -> Right raw
        _ -> Left (T.unpack t <> ": not an Ed25519 public key")

-- | Decode a qb64 @E@ self-addressing digest to its raw 32 bytes.
digestRaw :: Text -> Either String ByteString
digestRaw t =
    parseFull t >>= \case
        SelfAddressing raw -> Right raw
        _ -> Left (T.unpack t <> ": not a self-addressing digest")

-- | Parse exactly one CESR primitive, requiring the whole token be consumed.
parseFull :: Text -> Either String Primitive
parseFull t = case parsePrimitive (TE.encodeUtf8 t) of
    Right (p, rest)
        | BS.null rest -> Right p
        | otherwise -> Left (T.unpack t <> ": trailing bytes after primitive")
    Left err -> Left (T.unpack t <> ": " <> err)
