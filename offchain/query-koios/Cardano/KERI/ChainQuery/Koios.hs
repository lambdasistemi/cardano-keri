{- |
Module      : Cardano.KERI.ChainQuery.Koios
Description : Concrete Koios HTTP client and interpreter (#257 MOD-257-KOIOS)

Owns the legacy Koios HTTP client, endpoint response decoding,
configuration, operation translation, and the explicit
sequential\/non-atomic consistency claim (RQ-257-05). Per A-001 (ruling on
Q-001), 'koiosInterpreter' is the sole resolver of a Koios registration
snapshot: 'decodeExtendedUtxoJson' captures every ledger-relevant field
Koios's own @_extended=true@ responses already carry (verified against the
real Koios OpenAPI @utxo_infos@ schema — @address@, @value@, @datum_hash@,
@inline_datum@, @reference_script@ \{hash,size,type,bytes\}, @asset_list@),
and "Cardano.KERI.ChainQuery.LedgerOutput" reconstructs the exact ledger
output — no N2C fallback. Never calls a local or future interpreter as
fallback (INV-257-PROVIDER).

Types and functions here that predate #257 (@ChainReference@\/@ChainAssetUtxo@
minus the reference-script field, @authorizeKoiosRequest@,
@queryReferenceScripts@\/@queryAddressUtxos@\/@queryAssetUtxos@\/
@queryAssetHistory@\/@queryTransactionInfo@) are moved unchanged from the
former @Cardano.KERI.Deployment.ChainIndex@. @queryScriptRedeemers@ and
@queryTransactionUtxos@ are dropped: T257-S1-05 confirmed zero call sites
anywhere in the tree besides their own definitions and test fixtures.
'queryTip' is extended to also decode the block hash Koios's @/tip@ response
already carries (previously unparsed), giving the watermark operation an
honest, single-response slot\/hash pair.
-}
module Cardano.KERI.ChainQuery.Koios (
    -- * Configuration
    KoiosToken (..),
    authorizeKoiosRequest,

    -- * Koios-response-only types
    ChainAssetHistory (..),
    ChainMintingTransaction (..),
    ChainScriptRedeemers (..),
    ChainScriptRedeemer (..),
    ChainTransactionUtxos (..),
    ChainTransactionPart (..),
    ChainTip (..),
    ChainTransactionInfo (..),

    -- * HTTP client
    queryReferenceScripts,
    queryAddressUtxos,
    queryAssetUtxos,
    queryAssetHistory,
    queryTip,
    queryTransactionInfo,
    queryUtxoInfo,
    matchesReference,

    -- * Extended-response decode (A-001)
    decodeExtendedUtxoJson,
    koiosReferenceScripts,

    -- * Checkpoint discovery (moved from the former

    -- @Cardano.KERI.Deployment.CheckpointIndex@)
    checkpointAssetName,
    koiosCurrentCheckpoint,
    koiosLiveCheckpoints,
    queryActiveCheckpoint,
    resolveActiveCheckpoint,
    resolveClosedCheckpoint,
    latestMintingTransaction,

    -- * Board catalog discovery (moved from the former

    -- @Cardano.KERI.Deployment.EndpointBoard.queryBoardCatalog@)
    koiosBoardCatalog,
    queryBoardCatalog,

    -- * Interpreter
    koiosInterpreter,
) where

import Cardano.KERI.AID.CESR (Primitive (..), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    checkpointDatumFromData,
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.ChainQuery.Interpreter (ChainQueryInterpreter, chainQueryInterpreter)
import Cardano.KERI.ChainQuery.PlutusJson (plutusDataFromJson)
import Cardano.KERI.ChainQuery.Types (
    ActiveCheckpoint (..),
    BoardEntry (..),
    BoardLocator (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainReference (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Populated),
    QuerySource (SourceKoios),
    SnapshotConsistency (LegacySequential),
    parseExtendedChainAssetUtxo,
    validBoardLocator,
    validCheckpointLocator,
    validPayerAddresses,
    validReferenceHashes,
 )
import Cardano.KERI.Deployment.EndpointBoard (resolveBoardCatalog)
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
    Reference (..),
 )
import Control.Monad (unless)
import Data.Aeson (
    FromJSON (..),
    Object,
    Value,
    object,
    withObject,
    (.:),
    (.=),
 )
import Data.Aeson.Key (Key)
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.List (maximumBy)
import Data.Ord (comparing)
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
import PlutusCore.Data (Data (..))
import Text.Read (readMaybe)

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

{- | The observed chain tip (Koios @GET \/tip@): both its absolute slot and
its block header hash, so 'koiosInterpreter's watermark operation is an
honest, single-response slot\/hash pair (previously only the slot was
decoded here).
-}
data ChainTip = ChainTip
    { tipAbsSlot :: !Integer
    , tipHash :: !Text
    }
    deriving stock (Show, Eq)

{- | One transaction's absolute slot (Koios @POST \/tx_info@'s
@absolute_slot@) — FR-4's honest @as_of_slot@ source, keyed by the exact
originating tx of the live UTxO being rendered.
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

{- | Decode one Koios extended UTxO response object into the promoted
'ChainAssetUtxo' view (A-001), fail-closed. The 'FromJSON'\/'Parser' machinery
this wraps lives in "Cardano.KERI.ChainQuery.Types"
('parseExtendedChainAssetUtxo') solely to avoid orphan instances.
-}
decodeExtendedUtxoJson :: Value -> Either ChainQueryError ChainAssetUtxo
decodeExtendedUtxoJson value =
    either (Left . DecodingFailure . T.pack) Right $
        parseEither parseExtendedChainAssetUtxo value

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
        ChainTip <$> o .: "abs_slot" <*> o .: "hash"

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
    IO [(Text, Text, Int)]
queryReferenceScripts baseUrl token hashes = do
    initial <-
        parseRequest $
            T.unpack (T.dropWhileEnd (== '/') baseUrl)
                <> "/reference_script_utxos"
    let request =
            setRequestBodyJSON (object ["_script_hashes" .= hashes]) $
                setRequestHeader "content-type" ["application/json"] $
                    setRequestMethod "POST" initial
    map scriptUtxoTriple . getResponseBody <$> httpJSON (authorizeKoiosRequest token request)

-- | The minimal @script_utxos@ response shape: script hash, tx hash, tx index.
data ScriptUtxo = ScriptUtxo !Text !Text !Int

scriptUtxoTriple :: ScriptUtxo -> (Text, Text, Int)
scriptUtxoTriple (ScriptUtxo h t i) = (h, t, i)

instance FromJSON ScriptUtxo where
    parseJSON = withObject "ScriptUtxo" $ \o ->
        ScriptUtxo <$> o .: "script_hash" <*> o .: "tx_hash" <*> o .: "tx_index"

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

{- | Extended UTxO information for exact @tx_hash#tx_index@ references
(Koios @POST \/utxo_info@, @_extended=true@) — the second step of the A-001
two-call reference-output resolution, resolving @reference_script_utxos@'s
minimal identity into a fully decodable extended row.
-}
queryUtxoInfo :: Text -> Maybe KoiosToken -> [(Text, Int)] -> IO [ChainAssetUtxo]
queryUtxoInfo baseUrl token refs = do
    initial <- parseRequest (endpoint baseUrl "utxo_info")
    let request =
            setRequestBodyJSON
                ( object
                    [ "_utxo_refs" .= map renderRef refs
                    , "_extended" .= True
                    ]
                )
                $ setRequestHeader "content-type" ["application/json"]
                $ setRequestMethod "POST" initial
    getResponseBody <$> httpJSON (authorizeKoiosRequest token request)
  where
    renderRef (txId, index) = txId <> "#" <> T.pack (show index)

matchesReference :: Text -> Reference -> (Text, Text, Int) -> Bool
matchesReference scriptHash reference (candidateHash, candidateTxId, candidateIndex) =
    candidateHash == scriptHash
        && candidateTxId == referenceTxId reference
        && candidateIndex == referenceIndex reference

integerTextField :: Object -> Key -> Parser Integer
integerTextField objectValue field = do
    spelling <- objectValue .: field
    maybe
        (fail $ "expected decimal integer string in " <> show field)
        pure
        (readMaybe $ T.unpack spelling)

endpoint :: Text -> String -> String
endpoint baseUrl path =
    T.unpack (T.dropWhileEnd (== '/') baseUrl) <> "/" <> path

{- | Discover each requested reference script's current @tx_hash#tx_index@
via 'queryReferenceScripts', then fully resolve it via 'queryUtxoInfo'
(A-001's two-Koios-call, no-N2C resolution).
-}
koiosReferenceScripts :: Text -> Maybe KoiosToken -> [Text] -> IO (Either ChainQueryError [ChainReference])
koiosReferenceScripts _baseUrl _token [] = pure (Right [])
koiosReferenceScripts baseUrl token hashes =
    case validReferenceHashes hashes of
        Left err -> pure (Left err)
        Right () -> do
            discovered <- queryReferenceScripts baseUrl token hashes
            if length discovered /= length hashes
                then pure (Left (ProviderFailure "Koios did not return exactly one reference per requested hash"))
                else do
                    let refs = [(txId, index) | (_, txId, index) <- discovered]
                    extended <- queryUtxoInfo baseUrl token refs
                    pure (assembleReferences discovered extended)

assembleReferences :: [(Text, Text, Int)] -> [ChainAssetUtxo] -> Either ChainQueryError [ChainReference]
assembleReferences discovered extended = traverse assembleOne discovered
  where
    assembleOne (scriptHash, txId, index) =
        case [u | u <- extended, chainAssetTxId u == txId, chainAssetIndex u == index] of
            [utxo] -> Right (ChainReference scriptHash utxo)
            [] ->
                Left (ProviderFailure ("utxo_info did not return the requested output " <> txId))
            _ ->
                Left (ProviderFailure ("utxo_info returned duplicate rows for " <> txId))

koiosBoardCatalog :: Text -> Maybe KoiosToken -> BoardLocator -> IO (Either ChainQueryError [BoardEntry])
koiosBoardCatalog baseUrl token locator =
    case validBoardLocator locator of
        Left err -> pure (Left err)
        Right () -> do
            utxos <- queryAddressUtxos baseUrl token (boardLocatorAddress locator)
            pure $
                first (DecodingFailure . T.pack) $
                    resolveBoardCatalog (boardLocatorPolicyId locator) (boardLocatorAddress locator) utxos

{- | @Text@\/@Text@-shaped, IO-throwing compatibility wrapper for the
pre-#257 caller ("Cardano.KERI.CLI.Backend.Koios", the #176\/#177
status-endpoint backend — a different write verb, untouched by #257's
registration migration). Moved here unchanged (module relocation only)
from the former @Cardano.KERI.Deployment.EndpointBoard.queryBoardCatalog@.
-}
queryBoardCatalog :: Text -> Maybe KoiosToken -> Text -> Text -> IO [BoardEntry]
queryBoardCatalog baseUrl token policy markerAddress =
    koiosBoardCatalog baseUrl token (BoardLocator policy markerAddress)
        >>= either (fail . show) pure

{- | The current checkpoint UTxO for one AID (Koios @asset_utxos@ filtered
to the checkpoint's derived asset name). More than one live output is
reported ambiguous, never silently narrowed (INV-257-PROVIDER).

Known simplification versus the pre-#257 @queryActiveCheckpoint@: the
escrow-floor cross-check against @DeploymentParameters@ is not repeated
here, since 'CheckpointLocator' carries only the policy and address per
the frozen data-model (DAT-257-CHECKPOINT-LOCATOR) — identity and datum
validation are unchanged.
-}
koiosCurrentCheckpoint ::
    Text -> Maybe KoiosToken -> CheckpointLocator -> Text -> IO (Either ChainQueryError (Maybe ActiveCheckpoint))
koiosCurrentCheckpoint baseUrl token locator aid =
    case validCheckpointLocator locator of
        Left err -> pure (Left err)
        Right () -> case checkpointAssetName aid of
            Left err -> pure (Left (InvalidLocator (T.pack err)))
            Right assetName -> do
                utxos <- queryAssetUtxos baseUrl token (checkpointLocatorPolicyId locator) assetName
                pure $ case utxos of
                    [] -> Right Nothing
                    [utxo] ->
                        first (DecodingFailure . T.pack) $
                            Just <$> resolveActiveCheckpointOne locator aid assetName utxo
                    _ -> Left (AmbiguousCurrentState "more than one live checkpoint output for this AID")

{- | Manifest-shaped, IO-throwing compatibility wrapper for the pre-#257
callers (advance\/close paths in "Cardano.KERI.Deployment.CLI" — write
verbs #240, not #257, will migrate later). Moved here unchanged (module
relocation only) from the former
@Cardano.KERI.Deployment.CheckpointIndex.queryActiveCheckpoint@.
-}
queryActiveCheckpoint :: Text -> Maybe KoiosToken -> Manifest -> Text -> IO ActiveCheckpoint
queryActiveCheckpoint baseUrl token manifest aid = do
    result <-
        koiosCurrentCheckpoint
            baseUrl
            token
            CheckpointLocator
                { checkpointLocatorPolicyId = checkpointPolicyId (manifestCheckpoint manifest)
                , checkpointLocatorAddress = checkpointAddressBech32 (manifestCheckpoint manifest)
                }
            aid
    case result of
        Left err -> fail (show err)
        Right Nothing -> fail "checkpoint is not registered"
        Right (Just active) -> pure active

{- | Every currently live checkpoint at the checkpoint address (Koios
@address_utxos@, decoding each output; a malformed decode fails closed).
-}
koiosLiveCheckpoints :: Text -> Maybe KoiosToken -> CheckpointLocator -> IO (Either ChainQueryError [ActiveCheckpoint])
koiosLiveCheckpoints baseUrl token locator =
    case validCheckpointLocator locator of
        Left err -> pure (Left err)
        Right () -> do
            utxos <- queryAddressUtxos baseUrl token (checkpointLocatorAddress locator)
            pure $
                first (DecodingFailure . T.pack) $
                    traverse (decodeOneLiveCheckpoint locator) (filter carriesCheckpointPolicy utxos)
  where
    carriesCheckpointPolicy utxo =
        any ((== checkpointLocatorPolicyId locator) . chainAssetPolicy) (chainAssetList utxo)

decodeOneLiveCheckpoint :: CheckpointLocator -> ChainAssetUtxo -> Either String ActiveCheckpoint
decodeOneLiveCheckpoint locator utxo = do
    aidBytes <- decodedCheckpointAid utxo
    resolveActiveCheckpointOne locator (hexText aidBytes) (assetNameOf utxo) utxo
  where
    assetNameOf u = case [chainAssetName a | a <- chainAssetList u, chainAssetPolicy a == checkpointLocatorPolicyId locator] of
        [name] -> name
        _ -> ""
    hexText = TE.decodeUtf8 . convertToBase Base16
    decodedCheckpointAid u = do
        inline <- maybe (Left "checkpoint output has no inline datum") Right (chainAssetInlineDatum u)
        dat <- plutusDataFromJson inline
        checkpoint <- maybe (Left "checkpoint inline datum is not the frozen V1 schema") Right (checkpointDatumFromData dat)
        case checkpoint of
            V1 value -> Right (cdCesrAid value)

{- | Resolve one exactly-one-output checkpoint asset match into
'ActiveCheckpoint' (address, quantity, datum, and AID identity checks).
-}
resolveActiveCheckpointOne :: CheckpointLocator -> Text -> Text -> ChainAssetUtxo -> Either String ActiveCheckpoint
resolveActiveCheckpointOne locator aid assetName utxo = do
    unless (chainAssetAddress utxo == checkpointLocatorAddress locator) $
        Left "checkpoint asset is not at the known checkpoint address"
    unless (assetQuantity (checkpointLocatorPolicyId locator) assetName (chainAssetList utxo) == 1) $
        Left "checkpoint output does not hold exactly one queried token"
    inline <- maybe (Left "checkpoint output has no inline datum") Right (chainAssetInlineDatum utxo)
    dat <- plutusDataFromJson inline
    checkpoint <- maybe (Left "checkpoint inline datum is not the frozen V1 schema") Right (checkpointDatumFromData dat)
    datum <- case checkpoint of
        V1 value -> Right value
    expectedAid <- case parsePrimitive (TE.encodeUtf8 aid) of
        Right (SelfAddressing raw, rest) | BS.null rest -> Right raw
        _ -> Left "AID must be one 44-character KERI E-code identifier"
    unless (cdCesrAid datum == expectedAid) $
        Left "checkpoint inline datum AID does not match the queried asset"
    pure
        ActiveCheckpoint
            { activeCheckpointAid = aid
            , activeCheckpointAssetName = assetName
            , activeCheckpointTxId = chainAssetTxId utxo
            , activeCheckpointIndex = chainAssetIndex utxo
            , activeCheckpointAddress = chainAssetAddress utxo
            , activeCheckpointLovelace = chainAssetLovelace utxo
            , activeCheckpointAssets = chainAssetList utxo
            , activeCheckpointDatum = datum
            }

{- | Manifest\/list-shaped compatibility wrapper for the pre-#257 caller
("Cardano.KERI.CLI.Backend.Koios", the #176\/#177 status-endpoint backend —
a different write verb, untouched by #257's registration migration). Moved
here unchanged (module relocation only) from the former
@Cardano.KERI.Deployment.CheckpointIndex.resolveActiveCheckpoint@.
-}
resolveActiveCheckpoint ::
    Manifest -> Text -> Text -> [ChainAssetUtxo] -> Either String ActiveCheckpoint
resolveActiveCheckpoint _ _ _ [] =
    Left "checkpoint is not registered"
resolveActiveCheckpoint manifest aid assetName [utxo] =
    resolveActiveCheckpointOne
        CheckpointLocator
            { checkpointLocatorPolicyId = checkpointPolicyId (manifestCheckpoint manifest)
            , checkpointLocatorAddress = checkpointAddressBech32 (manifestCheckpoint manifest)
            }
        aid
        assetName
        utxo
resolveActiveCheckpoint _ _ _ matches =
    Left $
        "checkpoint lookup is ambiguous: "
            <> show (length matches)
            <> " live outputs"

assetQuantity :: Text -> Text -> [ChainAsset] -> Integer
assetQuantity policyId assetName =
    sum
        . map chainAssetQuantity
        . filter (\asset -> chainAssetPolicy asset == policyId && chainAssetName asset == assetName)

{- | Derive an AID's checkpoint asset name (Blake3-derived, matching the
on-chain minting policy).
-}
checkpointAssetName :: Text -> Either String Text
checkpointAssetName aid =
    case parsePrimitive (TE.encodeUtf8 aid) of
        Right (SelfAddressing raw, rest)
            | BS.null rest ->
                Right $ TE.decodeUtf8 $ convertToBase Base16 $ deriveAidAssetName raw
        _ -> Left "AID must be one 44-character KERI E-code identifier"

{- | The checkpoint asset's own latest recorded burn, used to prove a
closed checkpoint (kept for the #176 status backend's DIRECTION-001
precedence check; not used by #257's registration proof verb).
-}
latestMintingTransaction ::
    Text -> Text -> [ChainAssetHistory] -> Either String (Maybe ChainMintingTransaction)
latestMintingTransaction policy assetName histories =
    case filter (\h -> chainHistoryPolicy h == policy && chainHistoryAssetName h == assetName) histories of
        [] -> Right Nothing
        [history] ->
            Right $ case chainMintingTransactions history of
                [] -> Nothing
                transactions ->
                    Just $
                        maximumBy
                            (comparing (\t -> (chainMintingBlockTime t, chainMintingTxId t)))
                            transactions
        _ -> Left "Koios returned ambiguous checkpoint asset history"

{- | Prove a checkpoint's on-chain closure from its latest -1 mint, the
matching 'ChainScriptRedeemers', and the closing transaction's own inputs
and outputs (kept for the #176 status backend's DIRECTION-001 precedence
check; not used by #257's registration proof verb).
-}
resolveClosedCheckpoint ::
    Text ->
    Text ->
    [ChainAssetHistory] ->
    [ChainScriptRedeemers] ->
    [ChainTransactionUtxos] ->
    Either String (Maybe Text)
resolveClosedCheckpoint policy assetName histories redeemerSets transactions = do
    latest <- latestMintingTransaction policy assetName histories
    case latest of
        Nothing -> pure Nothing
        Just minting
            | chainMintingQuantity minting /= -1 ->
                pure Nothing
            | otherwise ->
                pure $
                    if provesClose minting
                        then Just (chainMintingTxId minting)
                        else Nothing
  where
    provesClose minting =
        case ( matchingRedeemers
             , filter
                ( (== chainMintingTxId minting)
                    . chainTransactionTxId
                )
                transactions
             ) of
            ([redeemers], [transaction]) ->
                case checkpointInputs transaction of
                    [checkpointInput] ->
                        hasCloseBurn minting checkpointInput redeemers
                            && hasCloseSpend minting redeemers
                            && hasExactRefund checkpointInput transaction
                    _ -> False
            _ -> False
    matchingRedeemers =
        filter ((== policy) . chainRedeemerScriptHash) redeemerSets
    checkpointInputs transaction =
        filter
            ( \input ->
                case chainTransactionPartAssets input of
                    [asset] ->
                        chainAssetPolicy asset == policy
                            && chainAssetName asset == assetName
                            && chainAssetQuantity asset == 1
                    _ -> False
            )
            (chainTransactionInputs transaction)
    hasCloseBurn minting input redeemers =
        any
            ( \redeemer ->
                chainRedeemerPurpose redeemer == "mint"
                    && chainRedeemerTxId redeemer == chainMintingTxId minting
                    && case plutusDataFromJson (chainRedeemerData redeemer) of
                        Right
                            ( Constr
                                    1
                                    [Constr 0 [B spentTxId, I spentIndex]]
                                ) ->
                                closeSpendTxIdHex spentTxId == chainTransactionPartTxId input
                                    && spentIndex
                                        == fromIntegral
                                            (chainTransactionPartIndex input)
                        _ -> False
            )
            (chainScriptRedeemers redeemers)
    hasCloseSpend minting redeemers =
        any
            ( \redeemer ->
                chainRedeemerPurpose redeemer == "spend"
                    && chainRedeemerTxId redeemer == chainMintingTxId minting
                    && case plutusDataFromJson (chainRedeemerData redeemer) of
                        Right (Constr 0 [_closeEvidence]) -> True
                        _ -> False
            )
            (chainScriptRedeemers redeemers)
    hasExactRefund input transaction =
        any
            ( \output ->
                chainTransactionPartLovelace output
                    == chainTransactionPartLovelace input
                    && chainTransactionPartAddress output
                        /= chainTransactionPartAddress input
                    && null (chainTransactionPartAssets output)
            )
            (chainTransactionOutputs transaction)

closeSpendTxIdHex :: BS.ByteString -> Text
closeSpendTxIdHex = TE.decodeUtf8 . convertToBase Base16

{- | The Koios interpreter (RQ-257-05): every operation Koios can answer
translates to its existing HTTP calls, and the result is labelled
'LegacySequential' — several independent calls, never a shared-snapshot
claim.
-}
koiosInterpreter :: Text -> Maybe KoiosToken -> ChainQueryInterpreter IO
koiosInterpreter baseUrl token =
    chainQueryInterpreter
        (koiosCurrentCheckpoint baseUrl token)
        (koiosLiveCheckpoints baseUrl token)
        (koiosReferenceScripts baseUrl token)
        (koiosBoardCatalog baseUrl token)
        ( \addresses ->
            case validPayerAddresses addresses of
                Left err -> pure (Left err)
                Right () -> do
                    results <- traverse (queryAddressUtxos baseUrl token) addresses
                    pure (Right (concat results))
        )
        ( do
            tips <- queryTip baseUrl token
            pure $ case tips of
                [tip] -> Right (Populated (ChainWatermark (fromInteger (tipAbsSlot tip)) (tipHash tip)))
                [] -> Left (ProviderFailure "Koios returned no tip")
                _ -> Left (ProviderFailure "Koios returned multiple tip rows")
        )
        SourceKoios
        LegacySequential
