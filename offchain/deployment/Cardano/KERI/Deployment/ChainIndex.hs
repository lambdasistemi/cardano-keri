{- |
Module      : Cardano.KERI.Deployment.ChainIndex
Description : Independent unspent reference-script lookup through Koios
-}
module Cardano.KERI.Deployment.ChainIndex (
    ChainReference (..),
    KoiosToken (..),
    authorizeKoiosRequest,
    queryReferenceScripts,
    matchesReference,
) where

import Cardano.KERI.Deployment.Manifest (Reference (..))
import Data.Aeson (FromJSON (..), object, withObject, (.:), (.=))
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

data ChainReference = ChainReference
    { chainScriptHash :: Text
    , chainTxId :: Text
    , chainIndex :: Int
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

matchesReference :: Text -> Reference -> ChainReference -> Bool
matchesReference scriptHash reference chainReference =
    chainScriptHash chainReference == scriptHash
        && chainTxId chainReference == referenceTxId reference
        && chainIndex chainReference == referenceIndex reference
