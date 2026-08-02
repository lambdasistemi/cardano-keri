{- |
Module      : Cardano.KERI.CLI.Backend.Koios
Description : #177 Slice 1 Koios backend adapter

Refactors (does not duplicate) 'Cardano.KERI.Deployment.CheckpointIndex':
@checkpointAssetName@\/@resolveActiveCheckpoint@ (the live-UTxO resolution)
and @latestMintingTransaction@ (the burn/history precedence check) are
reused unchanged. 'resolveKoiosActive' cross-checks @queryAssetHistory@
before trusting a live-looking @queryAssetUtxos@ answer (DIRECTION-001): a
proven latest burn for the checkpoint asset always wins over a stale-looking
live UTxO, mirroring the retired @queryCheckpointStatusUsing@'s precedence.
'resolveKoiosFreshness' is the pure core RULING-001 targets: it derives
@as_of_slot@ from the live checkpoint UTxO's own creating tx
('activeCheckpointTxId'), never from
'Cardano.KERI.Deployment.ChainIndex.ChainMintingTransaction' (which stays
pinned at registration through any advance, since an advance spends and
recreates the checkpoint UTxO in place without touching the minting policy).
-}
module Cardano.KERI.CLI.Backend.Koios (
    mkKoiosBackend,
    resolveKoiosActive,
    resolveKoiosFreshness,
    resolveKoiosTransactionFreshness,
    resolveKoiosList,
    resolveKoiosPayer,
    catchKoios,
) where

import Cardano.KERI.AID.CESR (qb64Aid, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (..), CheckpointDatumV1 (..), checkpointDatumFromData)
import Cardano.KERI.CLI.Backend (
    BackendError (..),
    CheckpointFields (..),
    CheckpointListItem (..),
    Freshness (..),
    PayerUtxoFields (..),
    QueryBackend (..),
    StatusView (..),
    WatchabilityFields (..),
 )
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetHistory (..),
    ChainAssetUtxo (..),
    ChainMintingTransaction (..),
    ChainTip (..),
    ChainTransactionInfo (..),
    KoiosToken,
    queryAddressUtxos,
    queryAssetHistory,
    queryAssetUtxos,
    queryTip,
    queryTransactionInfo,
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    checkpointAssetName,
    latestMintingTransaction,
    resolveActiveCheckpoint,
 )
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    missingBoardWitnesses,
    queryBoardCatalog,
    watchabilityGrade,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
 )
import Cardano.KERI.Deployment.Registration (plutusDataFromJson)
import Cardano.KERI.Indexer.Query.Types (qb64Witness)
import Control.Exception (AsyncException, SomeException, fromException, tryJust)
import Control.Monad (unless, when)
import Data.Char (isHexDigit)
import Data.Foldable (traverse_)
import Data.List (find)
import Data.List qualified as List
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

-- | A refactored Koios client at the given base URL/token.
mkKoiosBackend :: Manifest -> EndpointBoardManifest -> Text -> Maybe KoiosToken -> QueryBackend
mkKoiosBackend manifest boardManifest baseUrl token =
    QueryBackend
        { qbSourceLabel = baseUrl
        , qbStatus = koiosStatus manifest boardManifest baseUrl token
        , qbBoardByWitness = \_ ->
            pure (Left (UnsupportedCapability "board-by-witness is not exposed by the Koios backend in this slice"))
        , qbListCheckpoints = koiosListCheckpoints manifest baseUrl token
        , qbCheckpointByAid = koiosCheckpointByAid manifest baseUrl token
        , qbPayerUtxos = koiosPayerUtxos baseUrl token
        }

koiosStatus ::
    Manifest ->
    EndpointBoardManifest ->
    Text ->
    Maybe KoiosToken ->
    Text ->
    IO (Either BackendError StatusView)
koiosStatus manifest boardManifest baseUrl token aidText =
    case checkpointAssetName aidText of
        Left err -> pure (Left (MalformedResponse (T.pack err)))
        Right assetName -> do
            histories <- queryAssetHistory baseUrl token policy assetName
            case latestBurn policy assetName histories of
                Left err -> pure (Left err)
                Right (Just _burn) -> pure (Right (unregisteredView aidText))
                Right Nothing -> do
                    utxos <- queryAssetUtxos baseUrl token policy assetName
                    case resolveKoiosActive manifest aidText assetName histories utxos of
                        Left err -> pure (Left err)
                        Right Nothing -> pure (Right (unregisteredView aidText))
                        Right (Just active) -> do
                            tipResults <- queryTip baseUrl token
                            txInfoResults <- queryTransactionInfo baseUrl token [activeCheckpointTxId active]
                            catalog <-
                                queryBoardCatalog
                                    baseUrl
                                    token
                                    (endpointBoardPolicyId boardInfo)
                                    (endpointBoardAddress boardInfo)
                            let matchingTxInfo =
                                    find ((== activeCheckpointTxId active) . txInfoTxHash) txInfoResults
                            pure $ do
                                freshness <- resolveKoiosFreshness active matchingTxInfo (headMaybe tipResults)
                                pure (activeView baseUrl aidText active freshness catalog)
  where
    policy = checkpointPolicyId (manifestCheckpoint manifest)
    boardInfo = endpointBoardManifestInfo boardManifest
    headMaybe [] = Nothing
    headMaybe (x : _) = Just x

koiosCheckpointByAid ::
    Manifest ->
    Text ->
    Maybe KoiosToken ->
    Text ->
    IO (Either BackendError (Freshness, Maybe CheckpointFields))
koiosCheckpointByAid manifest baseUrl token aidText =
    catchKoios $ case checkpointAssetName aidText of
        Left err -> pure (Left (MalformedResponse (T.pack err)))
        Right assetName -> do
            histories <- queryAssetHistory baseUrl token policy assetName
            case latestBurn policy assetName histories of
                Left err -> pure (Left err)
                Right (Just _) -> freshnessWithoutRows
                Right Nothing -> do
                    utxos <- queryAssetUtxos baseUrl token policy assetName
                    case resolveKoiosActive manifest aidText assetName histories utxos of
                        Left err -> pure (Left err)
                        Right Nothing -> freshnessWithoutRows
                        Right (Just active) -> do
                            tips <- queryTip baseUrl token
                            txInfos <- queryTransactionInfo baseUrl token [activeCheckpointTxId active]
                            pure $ do
                                tip <- singleTip tips
                                freshness <-
                                    resolveKoiosTransactionFreshness
                                        [activeCheckpointTxId active]
                                        txInfos
                                        (Just tip)
                                pure (freshness, Just (checkpointFieldsOf active))
  where
    policy = checkpointPolicyId (manifestCheckpoint manifest)
    freshnessWithoutRows = do
        tips <- queryTip baseUrl token
        pure $ do
            tip <- singleTip tips
            freshness <- resolveKoiosTransactionFreshness [] [] (Just tip)
            pure (freshness, Nothing)

koiosListCheckpoints ::
    Manifest ->
    Text ->
    Maybe KoiosToken ->
    IO (Either BackendError (Freshness, [CheckpointListItem]))
koiosListCheckpoints manifest baseUrl token =
    catchKoios $ do
        utxos <- queryAddressUtxos baseUrl token checkpointAddress
        tips <- queryTip baseUrl token
        case traverse (decodeCheckpointUtxo manifest) utxos of
            Left err -> pure (Left err)
            Right decoded -> do
                let checkpoints = catMaybes decoded
                    txIds = map activeCheckpointTxId checkpoints
                txInfos <-
                    if null txIds
                        then pure []
                        else queryTransactionInfo baseUrl token (List.nub txIds)
                pure (resolveKoiosList manifest utxos txInfos =<< singleTipMaybe tips)
  where
    checkpointAddress = checkpointAddressBech32 (manifestCheckpoint manifest)

koiosPayerUtxos ::
    Text ->
    Maybe KoiosToken ->
    Text ->
    IO (Either BackendError (Freshness, [PayerUtxoFields]))
koiosPayerUtxos baseUrl token addressText =
    catchKoios $ do
        utxos <- queryAddressUtxos baseUrl token addressText
        tips <- queryTip baseUrl token
        let txIds = map chainAssetTxId utxos
        txInfos <-
            if null txIds
                then pure []
                else queryTransactionInfo baseUrl token (List.nub txIds)
        pure (resolveKoiosPayer addressText utxos txInfos =<< singleTipMaybe tips)

resolveKoiosList ::
    Manifest ->
    [ChainAssetUtxo] ->
    [ChainTransactionInfo] ->
    Maybe ChainTip ->
    Either BackendError (Freshness, [CheckpointListItem])
resolveKoiosList manifest utxos txInfos maybeTip = do
    decoded <- traverse (decodeCheckpointUtxo manifest) utxos
    let checkpoints = catMaybes decoded
        txIds = map activeCheckpointTxId checkpoints
    ensureUniqueOutputs utxos
    ensureUniqueAids checkpoints
    freshness <- resolveKoiosTransactionFreshness txIds txInfos maybeTip
    pure
        ( freshness
        , map
            ( \active ->
                CheckpointListItem
                    { cliAid = activeCheckpointAid active
                    , cliCheckpoint = checkpointFieldsOf active
                    }
            )
            checkpoints
        )

resolveKoiosPayer ::
    Text ->
    [ChainAssetUtxo] ->
    [ChainTransactionInfo] ->
    Maybe ChainTip ->
    Either BackendError (Freshness, [PayerUtxoFields])
resolveKoiosPayer addressText utxos txInfos maybeTip = do
    traverse_ (validatePayerUtxo addressText) utxos
    ensureUniqueOutputs utxos
    freshness <-
        resolveKoiosTransactionFreshness
            (map chainAssetTxId utxos)
            txInfos
            maybeTip
    pure (freshness, map payerFieldsOf utxos)

resolveKoiosTransactionFreshness ::
    [Text] ->
    [ChainTransactionInfo] ->
    Maybe ChainTip ->
    Either BackendError Freshness
resolveKoiosTransactionFreshness _ _ Nothing =
    Left (MalformedResponse "no observed Koios tip")
resolveKoiosTransactionFreshness requestedTxIds txInfos (Just (ChainTip tipSlot)) = do
    unless (tipSlot >= 0) $
        Left (MalformedResponse "observed Koios tip has a negative absolute slot")
    let expected = List.sort (List.nub requestedTxIds)
        actualHashes = map txInfoTxHash txInfos
    when (null expected) $
        Left (MalformedResponse "no supporting transactions for Koios operation freshness")
    unless (length actualHashes == length (List.nub actualHashes)) $
        Left (MalformedResponse "duplicate tx_info provenance for a supporting transaction")
    unless (List.sort actualHashes == expected) $
        Left (MalformedResponse "tx_info provenance does not exactly match supporting transactions")
    unless (all ((>= 0) . txInfoAbsoluteSlot) txInfos) $
        Left (MalformedResponse "supporting tx_info has a negative absolute slot")
    unless (all ((<= tipSlot) . txInfoAbsoluteSlot) txInfos) $
        Left (MalformedResponse "observed tip is behind a supporting transaction slot")
    let asOfSlot =
            case map txInfoAbsoluteSlot txInfos of
                [] -> tipSlot
                slots -> minimum slots
    pure $
        Freshness
            (Just (fromInteger asOfSlot))
            (Just (fromInteger (tipSlot - asOfSlot)))

decodeCheckpointUtxo :: Manifest -> ChainAssetUtxo -> Either BackendError (Maybe ActiveCheckpoint)
decodeCheckpointUtxo manifest utxo =
    case filter ((== policy) . chainAssetPolicy) (chainAssetList utxo) of
        [] -> Right Nothing
        [asset] -> do
            unless (chainAssetQuantity asset == 1) $
                Left (MalformedResponse "checkpoint output does not hold exactly one policy token")
            inline <-
                maybe
                    (Left (MalformedResponse "checkpoint output has no inline datum"))
                    Right
                    (chainAssetInlineDatum utxo)
            dat <- either (Left . MalformedResponse . T.pack) Right (plutusDataFromJson inline)
            checkpoint <-
                maybe
                    (Left (MalformedResponse "checkpoint inline datum is not the frozen V1 schema"))
                    Right
                    (checkpointDatumFromData dat)
            datum <- case checkpoint of
                V1 value -> Right value
            let aid = TE.decodeUtf8 (qb64Aid (cdCesrAid datum))
            assetName <- either (Left . MalformedResponse . T.pack) Right (checkpointAssetName aid)
            unless (chainAssetName asset == assetName) $
                Left (MalformedResponse "checkpoint asset name does not match inline datum AID")
            validateChainUtxo utxo
            Just
                <$> either
                    (Left . MalformedResponse . T.pack)
                    Right
                    (resolveActiveCheckpoint manifest aid assetName [utxo])
        _ -> Left (MalformedResponse "checkpoint output carries multiple assets under the checkpoint policy")
  where
    policy = checkpointPolicyId (manifestCheckpoint manifest)

validatePayerUtxo :: Text -> ChainAssetUtxo -> Either BackendError ()
validatePayerUtxo expectedAddress utxo = do
    unless (chainAssetAddress utxo == expectedAddress) $
        Left (MalformedResponse "payer UTxO address does not match the requested address")
    validateChainUtxo utxo

validateChainUtxo :: ChainAssetUtxo -> Either BackendError ()
validateChainUtxo utxo = do
    unless (T.length txId == 64 && T.all isHexDigit txId) $
        Left (MalformedResponse "UTxO transaction hash is not 32-byte hexadecimal text")
    unless (chainAssetIndex utxo >= 0) $
        Left (MalformedResponse "UTxO output index is negative")
    unless (chainAssetLovelace utxo >= 0) $
        Left (MalformedResponse "UTxO lovelace value is negative")
  where
    txId = chainAssetTxId utxo

ensureUniqueOutputs :: [ChainAssetUtxo] -> Either BackendError ()
ensureUniqueOutputs utxos =
    unless (length references == length (List.nub references)) $
        Left (MalformedResponse "Koios returned duplicate UTxO references")
  where
    references = map (\utxo -> (chainAssetTxId utxo, chainAssetIndex utxo)) utxos

ensureUniqueAids :: [ActiveCheckpoint] -> Either BackendError ()
ensureUniqueAids checkpoints =
    unless (length aids == length (List.nub aids)) $
        Left (MalformedResponse "Koios returned duplicate live checkpoints for one AID")
  where
    aids = map activeCheckpointAid checkpoints

singleTip :: [ChainTip] -> Either BackendError ChainTip
singleTip [tip] = Right tip
singleTip [] = Left (MalformedResponse "no observed Koios tip")
singleTip _ = Left (MalformedResponse "Koios returned multiple tip rows")

singleTipMaybe :: [ChainTip] -> Either BackendError (Maybe ChainTip)
singleTipMaybe tips = Just <$> singleTip tips

payerFieldsOf :: ChainAssetUtxo -> PayerUtxoFields
payerFieldsOf utxo =
    PayerUtxoFields
        { pufTxId = chainAssetTxId utxo
        , pufOutputIndex = chainAssetIndex utxo
        }

catchKoios :: IO (Either BackendError a) -> IO (Either BackendError a)
catchKoios action = do
    outcome <- tryJust synchronousException action
    pure $ case outcome of
        Left err -> Left (UpstreamUnavailable (T.pack (show err)))
        Right result -> result
  where
    synchronousException :: SomeException -> Maybe SomeException
    synchronousException err =
        case fromException err :: Maybe AsyncException of
            Just _ -> Nothing
            Nothing -> Just err

{- | Resolve the currently active checkpoint, preferring a proven latest
burn in @asset_history@ over a live-looking @asset_utxos@ answer
(DIRECTION-001): Koios's live UTxO index can still show a spent checkpoint
asset as present for a brief window after a Close, so the checkpoint's own
minting/burning history is the higher-precedence source. Only once no
proven burn is found does a resolved live UTxO count as active; either way,
a genuinely never-registered AID and a proven-closed one both render as
'Nothing' here.
-}
resolveKoiosActive ::
    Manifest ->
    Text ->
    Text ->
    [ChainAssetHistory] ->
    [ChainAssetUtxo] ->
    Either BackendError (Maybe ActiveCheckpoint)
resolveKoiosActive manifest aidText assetName histories utxos =
    case latestBurn policy assetName histories of
        Left err -> Left err
        Right (Just _burn) -> Right Nothing
        Right Nothing ->
            case resolveActiveCheckpoint manifest aidText assetName utxos of
                Left _notRegistered -> Right Nothing
                Right active -> Right (Just active)
  where
    policy = checkpointPolicyId (manifestCheckpoint manifest)

{- | The checkpoint asset's own latest recorded burn, if @asset_history@
proves one — the DIRECTION-001 precedence source, checked before any live
UTxO snapshot is trusted. A closed 'BackendError' surfaces an ambiguous
history answer (more than one matching @asset_history@ entry).
-}
latestBurn ::
    Text ->
    Text ->
    [ChainAssetHistory] ->
    Either BackendError (Maybe ChainMintingTransaction)
latestBurn policy assetName histories =
    case latestMintingTransaction policy assetName histories of
        Left err -> Left (MalformedResponse (T.pack err))
        Right (Just minting) | chainMintingQuantity minting == -1 -> Right (Just minting)
        Right _ -> Right Nothing

{- | Derive honest freshness for one already-resolved active checkpoint:
@as_of_slot@ from @tx_info(activeCheckpointTxId).absolute_slot@, compared
against a freshly observed @tip.abs_slot@. Fails closed ('BackendError')
when either supporting call is missing, the tx_info answer is for a
different tx, or the resulting lag would be negative.
-}
resolveKoiosFreshness ::
    ActiveCheckpoint ->
    Maybe ChainTransactionInfo ->
    Maybe ChainTip ->
    Either BackendError Freshness
resolveKoiosFreshness _ Nothing _ =
    Left (MalformedResponse "no tx_info for the checkpoint's own creating tx")
resolveKoiosFreshness _ _ Nothing =
    Left (MalformedResponse "no observed Koios tip")
resolveKoiosFreshness active (Just txInfo) (Just tip)
    | txInfoTxHash txInfo /= activeCheckpointTxId active =
        Left (MalformedResponse "tx_info answer is for a different transaction than the checkpoint's own creating tx")
    | tipAbsSlot tip < txInfoAbsoluteSlot txInfo =
        Left (MalformedResponse "observed tip is behind the checkpoint's own slot — incoherent bound")
    | otherwise =
        Right $
            Freshness
                (Just (fromInteger (txInfoAbsoluteSlot txInfo)))
                (Just (fromInteger (tipAbsSlot tip - txInfoAbsoluteSlot txInfo)))

unregisteredView :: Text -> StatusView
unregisteredView aidText =
    StatusView
        { svSource = "koios"
        , svFreshness = Freshness Nothing Nothing
        , svAid = aidText
        , svCheckpoint = Nothing
        , svWatchability =
            WatchabilityFields
                { wfCheckpointPresent = False
                , wfWitnessesDeclared = 0
                , wfWitnessesListed = 0
                , wfMissingWitnesses = []
                }
        }

activeView :: Text -> Text -> ActiveCheckpoint -> Freshness -> [BoardEntry] -> StatusView
activeView baseUrl aidText active freshness catalog =
    StatusView
        { svSource = baseUrl
        , svFreshness = freshness
        , svAid = aidText
        , svCheckpoint = Just (checkpointFieldsOf active)
        , svWatchability = watchabilityFieldsOf active catalog
        }

checkpointFieldsOf :: ActiveCheckpoint -> CheckpointFields
checkpointFieldsOf active =
    CheckpointFields
        { cfTxId = activeCheckpointTxId active
        , cfOutputIndex = activeCheckpointIndex active
        , cfSequence = cdSeq datum
        , cfNativeSequence = cdNativeSn datum
        , cfCurrentKeys = map (TE.decodeUtf8 . qb64Verkey) (cdCurKeys datum)
        , cfCurrentThreshold = cdCurThreshold datum
        , cfWitnesses = map (TE.decodeUtf8 . qb64Witness) (cdWitnesses datum)
        , cfWitnessThreshold = cdToad datum
        }
  where
    datum = activeCheckpointDatum active

watchabilityFieldsOf :: ActiveCheckpoint -> [BoardEntry] -> WatchabilityFields
watchabilityFieldsOf active catalog =
    WatchabilityFields
        { wfCheckpointPresent = True
        , wfWitnessesDeclared = length declared
        , wfWitnessesListed = fst (watchabilityGrade declared catalog)
        , wfMissingWitnesses = map (TE.decodeUtf8 . qb64Witness) (missingBoardWitnesses declared catalog)
        }
  where
    declared = cdWitnesses (activeCheckpointDatum active)
