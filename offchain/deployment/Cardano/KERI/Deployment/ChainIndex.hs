{- |
Module      : Cardano.KERI.Deployment.ChainIndex
Description : Independent unspent reference-script lookup through Koios
-}
module Cardano.KERI.Deployment.ChainIndex (
    ChainReference (..),
    queryReferenceScripts,
    matchesReference,
) where

import Cardano.KERI.Deployment.Manifest (Reference (..))
import Data.Aeson (FromJSON (..), object, withObject, (.:), (.=))
import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Simple (
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

instance FromJSON ChainReference where
    parseJSON = withObject "ChainReference" $ \o ->
        ChainReference
            <$> o .: "script_hash"
            <*> o .: "tx_hash"
            <*> o .: "tx_index"

queryReferenceScripts :: Text -> [Text] -> IO [ChainReference]
queryReferenceScripts baseUrl hashes = do
    initial <-
        parseRequest $
            T.unpack (T.dropWhileEnd (== '/') baseUrl)
                <> "/reference_script_utxos"
    let request =
            setRequestBodyJSON (object ["_script_hashes" .= hashes]) $
                setRequestHeader "content-type" ["application/json"] $
                    setRequestMethod "POST" initial
    getResponseBody <$> httpJSON request

matchesReference :: Text -> Reference -> ChainReference -> Bool
matchesReference scriptHash reference chainReference =
    chainScriptHash chainReference == scriptHash
        && chainTxId chainReference == referenceTxId reference
        && chainIndex chainReference == referenceIndex reference
