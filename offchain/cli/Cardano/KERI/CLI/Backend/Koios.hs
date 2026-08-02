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
module Cardano.KERI.CLI.Backend.Koios (mkKoiosBackend, resolveKoiosActive, resolveKoiosFreshness) where

import Cardano.KERI.AID.CESR (qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.CLI.Backend (
    BackendError (..),
    CheckpointFields (..),
    Freshness (..),
    QueryBackend (..),
    StatusView (..),
    WatchabilityFields (..),
 )
import Cardano.KERI.Deployment.ChainIndex (
    ChainAssetHistory (..),
    ChainAssetUtxo,
    ChainMintingTransaction (..),
    ChainTip (..),
    ChainTransactionInfo (..),
    KoiosToken,
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
import Cardano.KERI.Indexer.Query.Types (qb64Witness)
import Data.List (find)
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
