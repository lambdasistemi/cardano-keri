{- |
Module      : Cardano.KERI.ChainQuery.PlutusJson
Description : Detailed Plutus Data <-> JSON codec, shared by both interpreters

A provider-neutral, generic Plutus 'Data' JSON rendering, moved here
unchanged from the former
@Cardano.KERI.Deployment.Registration.plutusDataJson@\/@plutusDataFromJson@
(re-exported there for every existing caller). Used by the local
interpreter to decode an inline datum's already-JSON-rendered value
(matching @Cardano.KERI.Indexer.Board@'s established pattern) and by the
Koios interpreter to reconstruct one from an extended UTxO response's
@inline_datum.value@ field.
-}
module Cardano.KERI.ChainQuery.PlutusJson (
    plutusDataJson,
    plutusDataFromJson,
) where

import Data.Aeson (Value, object, withObject, (.:), (.:?), (.=))
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import PlutusCore.Data (Data (..))

{- | Render Plutus 'Data' as the detailed JSON shape Koios's @inline_datum@
and this package's own manifests share.
-}
plutusDataJson :: Data -> Value
plutusDataJson = \case
    Constr constructor fields ->
        object
            [ "constructor" .= constructor
            , "fields" .= map plutusDataJson fields
            ]
    Map pairs ->
        object
            [ "map"
                .= [ object
                        [ "k" .= plutusDataJson key
                        , "v" .= plutusDataJson value
                        ]
                   | (key, value) <- pairs
                   ]
            ]
    List values -> object ["list" .= map plutusDataJson values]
    I value -> object ["int" .= value]
    B bytes -> object ["bytes" .= hexText bytes]

-- | The exact inverse of 'plutusDataJson'.
plutusDataFromJson :: Value -> Either String Data
plutusDataFromJson = parseEither parsePlutusData

parsePlutusData :: Value -> Parser Data
parsePlutusData = withObject "detailed Plutus data" $ \o -> do
    constructor <- o .:? "constructor"
    fields <- o .:? "fields"
    mapValues <- o .:? "map"
    listValues <- o .:? "list"
    integer <- o .:? "int"
    bytes <- o .:? "bytes"
    case ( constructor
         , fields
         , mapValues
         , listValues
         , integer
         , bytes
         ) of
        (Just tag, Just values, Nothing, Nothing, Nothing, Nothing) ->
            Constr tag <$> traverse parsePlutusData values
        (Nothing, Nothing, Just pairs, Nothing, Nothing, Nothing) ->
            Map <$> traverse parsePair pairs
        (Nothing, Nothing, Nothing, Just values, Nothing, Nothing) ->
            List <$> traverse parsePlutusData values
        (Nothing, Nothing, Nothing, Nothing, Just value, Nothing) ->
            pure (I value)
        (Nothing, Nothing, Nothing, Nothing, Nothing, Just encoded) ->
            B <$> parseHexBytes encoded
        _ -> fail "detailed Plutus data has an invalid or ambiguous shape"
  where
    parsePair = withObject "Plutus map pair" $ \pair ->
        (,)
            <$> (pair .: "k" >>= parsePlutusData)
            <*> (pair .: "v" >>= parsePlutusData)
    parseHexBytes encoded =
        either
            (const $ fail "Plutus bytes are not hexadecimal")
            pure
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)

hexText :: ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16
