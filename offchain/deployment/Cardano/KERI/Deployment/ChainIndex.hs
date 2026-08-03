{- |
Module      : Cardano.KERI.Deployment.ChainIndex
Description : Independent unspent reference-script lookup through Koios
-}
module Cardano.KERI.Deployment.ChainIndex (
    ChainReference (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainAssetHistory (..),
    ChainMintingTransaction (..),
    ChainScriptRedeemers (..),
    ChainScriptRedeemer (..),
    ChainTransactionUtxos (..),
    ChainTransactionPart (..),
    ChainTip (..),
    ChainTransactionInfo (..),
    KoiosToken (..),
    authorizeKoiosRequest,
    queryReferenceScripts,
    queryAddressUtxos,
    queryAssetUtxos,
    queryAssetHistory,
    queryScriptRedeemers,
    queryTransactionUtxos,
    queryTip,
    queryTransactionInfo,
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

data ChainAssetHistory = ChainAssetHistory
    { chainHistoryPolicy :: !Text
    , chainHistoryAssetName :: !Text
    , chainMintingTransactions :: ![ChainMintingTransaction]
    }
    deriving stock (Show, Eq)

data ChainMintingTransaction = ChainMintingTransaction
    { chainMintingTxId :: !Text
    , chainMintingQuantity :: !Integer
    , chainMintingBlockTime :: !Integer
    }
    deriving stock (Show, Eq)

data ChainScriptRedeemers = ChainScriptRedeemers
    { chainRedeemerScriptHash :: !Text
    , chainScriptRedeemers :: ![ChainScriptRedeemer]
    }
    deriving stock (Show, Eq)

data ChainScriptRedeemer = ChainScriptRedeemer
    { chainRedeemerPurpose :: !Text
    , chainRedeemerTxId :: !Text
    , chainRedeemerData :: !Value
    }
    deriving stock (Show, Eq)

data ChainTransactionUtxos = ChainTransactionUtxos
    { chainTransactionTxId :: !Text
    , chainTransactionInputs :: ![ChainTransactionPart]
    , chainTransactionOutputs :: ![ChainTransactionPart]
    }
    deriving stock (Show, Eq)

data ChainTransactionPart = ChainTransactionPart
    { chainTransactionPartTxId :: !Text
    , chainTransactionPartIndex :: !Int
    , chainTransactionPartAddress :: !Text
    , chainTransactionPartLovelace :: !Integer
    , chainTransactionPartAssets :: ![ChainAsset]
    }
    deriving stock (Show, Eq)

{- | The observed chain tip's absolute slot (Koios @GET \/tip@'s @abs_slot@),
FR-4's independently-observed freshness bound.
-}
newtype ChainTip = ChainTip
    { tipAbsSlot :: Integer
    }
    deriving stock (Show, Eq)

{- | One transaction's absolute slot (Koios @POST \/tx_info@'s
@absolute_slot@) — FR-4's honest @as_of_slot@ source, keyed by the exact
originating tx of the live UTxO being rendered, never by an
@asset_history@ minting/burn event (see RULING-001: an advance never
mints/burns, so that event stays pinned at registration).
-}
data ChainTransactionInfo = ChainTransactionInfo
    { txInfoTxHash :: !Text
    , txInfoAbsoluteSlot :: !Integer
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
            joinMaybe
                <$> traverse
                    (withObject "InlineDatum" (.:? "value"))
                    inline
        ChainAssetUtxo
            <$> o .: "tx_hash"
            <*> o .: "tx_index"
            <*> o .: "address"
            <*> integerTextField o "value"
            <*> o .: "asset_list"
            <*> pure chainAssetInlineDatum

instance FromJSON ChainAssetHistory where
    parseJSON = withObject "ChainAssetHistory" $ \o ->
        ChainAssetHistory
            <$> o .: "policy_id"
            <*> o .: "asset_name"
            <*> o .: "minting_txs"

instance FromJSON ChainMintingTransaction where
    parseJSON = withObject "ChainMintingTransaction" $ \o ->
        ChainMintingTransaction
            <$> o .: "tx_hash"
            <*> integerTextField o "quantity"
            <*> o .: "block_time"

instance FromJSON ChainScriptRedeemers where
    parseJSON = withObject "ChainScriptRedeemers" $ \o ->
        ChainScriptRedeemers
            <$> o .: "script_hash"
            <*> o .: "redeemers"

instance FromJSON ChainScriptRedeemer where
    parseJSON = withObject "ChainScriptRedeemer" $ \o ->
        ChainScriptRedeemer
            <$> o .: "purpose"
            <*> o .: "tx_hash"
            <*> o .: "datum_value"

instance FromJSON ChainTransactionUtxos where
    parseJSON = withObject "ChainTransactionUtxos" $ \o ->
        ChainTransactionUtxos
            <$> o .: "tx_hash"
            <*> o .: "inputs"
            <*> o .: "outputs"

instance FromJSON ChainTip where
    parseJSON = withObject "ChainTip" $ \o ->
        ChainTip <$> o .: "abs_slot"

instance FromJSON ChainTransactionInfo where
    parseJSON = withObject "ChainTransactionInfo" $ \o ->
        ChainTransactionInfo
            <$> o .: "tx_hash"
            <*> o .: "absolute_slot"

instance FromJSON ChainTransactionPart where
    parseJSON = withObject "ChainTransactionPart" $ \o -> do
        paymentAddress <- o .: "payment_addr"
        chainTransactionPartAddress <-
            withObject "PaymentAddress" (.: "bech32") paymentAddress
        ChainTransactionPart
            <$> o .: "tx_hash"
            <*> o .: "tx_index"
            <*> pure chainTransactionPartAddress
            <*> integerTextField o "value"
            <*> o .: "asset_list"

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

-- | Discover every current output at an address, including inline datum data.
queryAddressUtxos ::
    Text ->
    Maybe KoiosToken ->
    Text ->
    IO [ChainAssetUtxo]
queryAddressUtxos baseUrl token address = do
    initial <- parseRequest (endpoint baseUrl "address_utxos")
    let request =
            setRequestBodyJSON
                ( object
                    [ "_addresses" .= [address]
                    , "_extended" .= True
                    ]
                )
                $ setRequestHeader "content-type" ["application/json"]
                $ setRequestMethod "POST" initial
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

queryAssetHistory ::
    Text ->
    Maybe KoiosToken ->
    Text ->
    Text ->
    IO [ChainAssetHistory]
queryAssetHistory baseUrl token policyId assetName = do
    initial <-
        parseRequest $
            endpoint baseUrl "asset_history"
                <> "?_asset_policy="
                <> T.unpack policyId
                <> "&_asset_name="
                <> T.unpack assetName
    getResponseBody <$> httpJSON (authorizeKoiosRequest token initial)

queryScriptRedeemers ::
    Text ->
    Maybe KoiosToken ->
    Text ->
    IO [ChainScriptRedeemers]
queryScriptRedeemers baseUrl token scriptHash = do
    initial <-
        parseRequest $
            endpoint baseUrl "script_redeemers"
                <> "?_script_hash="
                <> T.unpack scriptHash
    getResponseBody <$> httpJSON (authorizeKoiosRequest token initial)

queryTransactionUtxos ::
    Text ->
    Maybe KoiosToken ->
    [Text] ->
    IO [ChainTransactionUtxos]
queryTransactionUtxos baseUrl token txIds = do
    initial <- parseRequest (endpoint baseUrl "tx_utxos")
    let request =
            setRequestBodyJSON (object ["_tx_hashes" .= txIds]) $
                setRequestHeader "content-type" ["application/json"] $
                    setRequestMethod "POST" initial
    getResponseBody <$> httpJSON (authorizeKoiosRequest token request)

-- | The observed chain tip (Koios @GET \/tip@, a singleton array).
queryTip :: Text -> Maybe KoiosToken -> IO [ChainTip]
queryTip baseUrl token = do
    initial <- parseRequest (endpoint baseUrl "tip")
    getResponseBody <$> httpJSON (authorizeKoiosRequest token initial)

-- | One or more transactions' absolute slots (Koios @POST \/tx_info@).
queryTransactionInfo :: Text -> Maybe KoiosToken -> [Text] -> IO [ChainTransactionInfo]
queryTransactionInfo baseUrl token txIds = do
    initial <- parseRequest (endpoint baseUrl "tx_info")
    let request =
            setRequestBodyJSON (object ["_tx_hashes" .= txIds]) $
                setRequestHeader "content-type" ["application/json"] $
                    setRequestMethod "POST" initial
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

endpoint :: Text -> String -> String
endpoint baseUrl path =
    T.unpack (T.dropWhileEnd (== '/') baseUrl) <> "/" <> path
