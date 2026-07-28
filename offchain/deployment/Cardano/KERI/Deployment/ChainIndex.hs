{- |
Module      : Cardano.KERI.Deployment.ChainIndex
Description : Independent unspent reference-script lookup through Koios
-}
module Cardano.KERI.Deployment.ChainIndex (
    ChainReference (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    KoiosToken (..),
    authorizeKoiosRequest,
    queryReferenceScripts,
    queryAssetUtxos,
    matchesReference,
) where

import Cardano.KERI.Deployment.Manifest (Reference (..))
import Data.Aeson (
    FromJSON (..),
    Object,
    Value,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
 )
import Data.Aeson.Key (Key)
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Simple (
    Request,
    getResponseBody,
    httpJSON,
    parseRequest,
    setRequestBodyJSON,
    setRequestHeader,
    setRequestMethod,
 )
import Text.Read (readMaybe)

data ChainReference = ChainReference
    { chainScriptHash :: Text
    , chainTxId :: Text
    , chainIndex :: Int
    }
    deriving stock (Show, Eq)

data ChainAsset = ChainAsset
    { chainAssetPolicy :: Text
    , chainAssetName :: Text
    , chainAssetQuantity :: Integer
    }
    deriving stock (Show, Eq)

data ChainAssetUtxo = ChainAssetUtxo
    { chainAssetTxId :: Text
    , chainAssetIndex :: Int
    , chainAssetAddress :: Text
    , chainAssetLovelace :: Integer
    , chainAssetList :: [ChainAsset]
    , chainAssetInlineDatum :: Maybe Value
    }
    deriving stock (Show, Eq)

-- | Koios API bearer token whose 'Show' instance never reveals the secret.
newtype KoiosToken = KoiosToken Text
    deriving stock (Eq)

instance Show KoiosToken where
    show _ = "KoiosToken <redacted>"

instance FromJSON ChainReference where
    parseJSON = withObject "ChainReference" $ \o ->
        ChainReference
            <$> o .: "script_hash"
            <*> o .: "tx_hash"
            <*> o .: "tx_index"

instance FromJSON ChainAsset where
    parseJSON = withObject "ChainAsset" $ \o ->
        ChainAsset
            <$> o .: "policy_id"
            <*> o .: "asset_name"
            <*> integerTextField o "quantity"

instance FromJSON ChainAssetUtxo where
    parseJSON = withObject "ChainAssetUtxo" $ \o -> do
        inline <- o .:? "inline_datum"
        chainAssetInlineDatum <-
            traverse
                (withObject "InlineDatum" (.:? "value"))
                inline
                >>= pure . joinMaybe
        ChainAssetUtxo
            <$> o .: "tx_hash"
            <*> o .: "tx_index"
            <*> o .: "address"
            <*> integerTextField o "value"
            <*> o .: "asset_list"
            <*> pure chainAssetInlineDatum

-- | Attach bearer authorization when a token is configured.
authorizeKoiosRequest :: Maybe KoiosToken -> Request -> Request
authorizeKoiosRequest maybeToken request =
    case maybeToken of
        Nothing -> request
        Just (KoiosToken token) ->
            setRequestHeader
                "authorization"
                ["Bearer " <> TE.encodeUtf8 token]
                request

queryReferenceScripts ::
    Text ->
    Maybe KoiosToken ->
    [Text] ->
    IO [ChainReference]
queryReferenceScripts baseUrl token hashes = do
    initial <-
        parseRequest $
            T.unpack (T.dropWhileEnd (== '/') baseUrl)
                <> "/reference_script_utxos"
    let request =
            setRequestBodyJSON (object ["_script_hashes" .= hashes]) $
                setRequestHeader "content-type" ["application/json"] $
                    setRequestMethod "POST" initial
    getResponseBody <$> httpJSON (authorizeKoiosRequest token request)

queryAssetUtxos ::
    Text ->
    Maybe KoiosToken ->
    Text ->
    Text ->
    IO [ChainAssetUtxo]
queryAssetUtxos baseUrl token policyId assetName = do
    initial <-
        parseRequest $
            T.unpack (T.dropWhileEnd (== '/') baseUrl)
                <> "/asset_utxos"
    let request =
            setRequestBodyJSON
                ( object
                    [ "_asset_list" .= [[policyId, assetName]]
                    , "_extended" .= True
                    ]
                )
                $ setRequestHeader "content-type" ["application/json"]
                $ setRequestMethod "POST" initial
    getResponseBody <$> httpJSON (authorizeKoiosRequest token request)

matchesReference :: Text -> Reference -> ChainReference -> Bool
matchesReference scriptHash reference chainReference =
    chainScriptHash chainReference == scriptHash
        && chainTxId chainReference == referenceTxId reference
        && chainIndex chainReference == referenceIndex reference

integerTextField :: Object -> Key -> Parser Integer
integerTextField objectValue field = do
    spelling <- objectValue .: field
    maybe
        (fail $ "expected decimal integer string in " <> show field)
        pure
        (readMaybe $ T.unpack spelling)

joinMaybe :: Maybe (Maybe a) -> Maybe a
joinMaybe = \case
    Nothing -> Nothing
    Just value -> value
