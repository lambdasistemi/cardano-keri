{- |
Module      : Cardano.KERI.CLI.Backend.Local
Description : #177 Slice 1 local RocksDB backend adapter

FR-2: payload and @as_of_slot@ come from one @kv-transactions@ transaction —
'Cardano.KERI.Indexer.Query.Tx.watchabilityTx' already reads the checkpoint
address, the board address, and the watermark together, so reusing it here
(rather than composing 'checkpointTx' and a separate watchability read) is
what keeps this a single coherent observation. @tip_lag_slots@ renders
'Nothing': a one-shot local CLI read opens no live node/tip channel in this
slice, so there is no honest lag to report (never a fabricated zero).
-}
module Cardano.KERI.CLI.Backend.Local (mkLocalBackend, openLocalBackend) where

import Cardano.KERI.AID.CESR (Primitive (SelfAddressing), parsePrimitive, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.CLI.Backend (
    BackendError (..),
    CheckpointFields (..),
    Freshness (..),
    QueryBackend (..),
    StatusView (..),
    WatchabilityFields (..),
 )
import Cardano.KERI.Deployment.EndpointBoard (BoardEntry, missingBoardWitnesses, watchabilityGrade)
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (endpointBoardAddress),
    EndpointBoardManifest (..),
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (checkpointAddressBech32, checkpointPolicyId),
    Manifest (..),
 )
import Cardano.KERI.Indexer.App (decodePolicyId)
import Cardano.KERI.Indexer.Codecs (CheckpointRecord (..))
import Cardano.KERI.Indexer.Config (decodeAddress)
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..), watchabilityTx)
import Cardano.KERI.Indexer.Query.Types (hexTxId, qb64Witness)
import Cardano.Node.Client.UTxOIndexer.Indexer (withRocksDBIndexerRunner)
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent.STM (retry)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Database.KV.Transaction (RunTransaction (..))

mkLocalBackend :: QueryHandle cf op -> QueryBackend
mkLocalBackend handle =
    QueryBackend
        { qbSourceLabel = "local"
        , qbStatus = localStatus handle
        , qbBoardByWitness = \_ ->
            pure (Left (UnsupportedCapability "board-by-witness is not exposed by the local backend in this slice"))
        }

{- | Production wiring: decode the checkpoint\/board addresses once, then open
and close the RocksDB store fresh on every call — @qbStatus@ is only ever
invoked once per @ckeri status@ process, so this keeps 'mkLocalBackend' (the
tested unit, given an already-open handle) unchanged while still respecting
'withRocksDBIndexerRunner's bracket discipline (its handle is invalid once
the bracket callback returns, so nothing may return a detached backend that
outlives it).
-}
openLocalBackend :: Manifest -> EndpointBoardManifest -> FilePath -> IO QueryBackend
openLocalBackend manifest boardManifest storePath = do
    checkpointAddress <- either fail pure (decodeAddress (checkpointAddressBech32 checkpoint))
    checkpointPolicy <- either fail pure (decodePolicyId (checkpointPolicyId checkpoint))
    boardAddress <- either fail pure (decodeAddress (endpointBoardAddress boardInfo))
    pure
        QueryBackend
            { qbSourceLabel = "local"
            , qbStatus = \aidText ->
                withRocksDBIndexerRunner storePath $ \_handle runner ->
                    qbStatus
                        (mkLocalBackend (QueryHandle runner checkpointAddress checkpointPolicy boardAddress retry))
                        aidText
            , qbBoardByWitness = \_ ->
                pure (Left (UnsupportedCapability "board-by-witness is not exposed by the local backend in this slice"))
            }
  where
    checkpoint = manifestCheckpoint manifest
    boardInfo = endpointBoardManifestInfo boardManifest

localStatus :: QueryHandle cf op -> Text -> IO (Either BackendError StatusView)
localStatus handle aidText =
    case decodeAid aidText of
        Left err -> pure (Left (MalformedResponse err))
        Right aid -> do
            (mRecord, catalogResult, watermark) <- runTransaction (qhRunner handle) (watchabilityTx handle aid)
            pure $ case catalogResult of
                Left err -> Left (MalformedResponse ("board catalog: " <> T.pack err))
                Right catalog ->
                    Right
                        StatusView
                            { svSource = "local"
                            , svFreshness = Freshness (slotWord <$> watermark) Nothing
                            , svAid = aidText
                            , svCheckpoint = checkpointFieldsOf <$> mRecord
                            , svWatchability = watchabilityFieldsOf mRecord catalog
                            }
  where
    slotWord (Indexer.SlotNo w) = w

decodeAid :: Text -> Either Text BS.ByteString
decodeAid aidText =
    case parsePrimitive (TE.encodeUtf8 aidText) of
        Right (SelfAddressing raw, rest)
            | BS.null rest -> Right raw
        _ -> Left "AID must be one 44-character KERI E-code identifier"

checkpointFieldsOf :: CheckpointRecord -> CheckpointFields
checkpointFieldsOf record =
    CheckpointFields
        { cfTxId = hexTxId (Indexer.txInId txIn)
        , cfOutputIndex = fromIntegral (Indexer.txInIx txIn)
        , cfSequence = cdSeq datum
        , cfNativeSequence = cdNativeSn datum
        , cfCurrentKeys = map (TE.decodeUtf8 . qb64Verkey) (cdCurKeys datum)
        , cfCurrentThreshold = cdCurThreshold datum
        , cfWitnesses = map (TE.decodeUtf8 . qb64Witness) (cdWitnesses datum)
        , cfWitnessThreshold = cdToad datum
        }
  where
    txIn = crTxIn record
    datum = crDatum record

watchabilityFieldsOf :: Maybe CheckpointRecord -> [BoardEntry] -> WatchabilityFields
watchabilityFieldsOf Nothing _ =
    WatchabilityFields
        { wfCheckpointPresent = False
        , wfWitnessesDeclared = 0
        , wfWitnessesListed = 0
        , wfMissingWitnesses = []
        }
watchabilityFieldsOf (Just record) catalog =
    WatchabilityFields
        { wfCheckpointPresent = True
        , wfWitnessesDeclared = length declared
        , wfWitnessesListed = fst (watchabilityGrade declared catalog)
        , wfMissingWitnesses = map (TE.decodeUtf8 . qb64Witness) (missingBoardWitnesses declared catalog)
        }
  where
    declared = cdWitnesses (crDatum record)
