{- |
Module      : Cardano.KERI.Indexer.Codecs
Description : Decode checkpoint records from upstream UTxO index entries

Consumes 'Cardano.Node.Client.UTxOIndexer.Types' values and inverts the Conway
@TxOut@ serialisation performed by
'Cardano.Node.Client.UTxOIndexer.BlockExtract'.  Checkpoint datum and asset-name
semantics come from 'Cardano.KERI.AID.Checkpoint.Datum' and
'Cardano.KERI.AID.Checkpoint.Message'.
-}
module Cardano.KERI.Indexer.Codecs (
    CheckpointRecord (..),
    CheckpointDecodeError (..),
    decodeCheckpointOutput,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    checkpointDatumFromData,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    binaryDataToData,
 )
import Cardano.Ledger.Api.Tx.Out (
    datumTxOutL,
    valueTxOutL,
 )
import Cardano.Ledger.Binary (
    DecoderError,
    decodeFull,
 )
import Cardano.Ledger.Conway (
    ConwayEra,
 )
import Cardano.Ledger.Core (
    TxOut,
    eraProtVerLow,
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
    TxIn,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.Bifunctor (
    first,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Lens.Micro (
    (^.),
 )

-- | A live checkpoint recovered from one indexed UTxO.
data CheckpointRecord = CheckpointRecord
    { crAid :: !ByteString
    -- ^ Raw E-code-stripped 32-byte AID, sourced from the datum.
    , crAssetName :: !ByteString
    -- ^ Checkpoint NFT asset name carried by the output.
    , crTxIn :: !TxIn
    -- ^ Upstream indexed transaction input.
    , crAddress :: !Address
    -- ^ Upstream indexed address.
    , crDatum :: !CheckpointDatumV1
    -- ^ Decoded checkpoint state.
    }
    deriving stock (Eq, Show)

-- | Why an indexed output is not a checkpoint record.
data CheckpointDecodeError
    = TxOutUndecodable !String
    | NoInlineDatum
    | DatumUndecodable
    | NoCheckpointAsset
    | AssetNameMismatch
    | MultipleCheckpointAssets
    deriving stock (Eq, Show)

-- | Decode one upstream indexed output under the deployment checkpoint policy.
decodeCheckpointOutput ::
    PolicyID ->
    TxIn ->
    Address ->
    Indexer.TxOut ->
    Either CheckpointDecodeError CheckpointRecord
decodeCheckpointOutput checkpointPolicy txIn address (Indexer.TxOut rawTxOut) = do
    ledgerTxOut <-
        first
            (TxOutUndecodable . show)
            ( decodeFull
                (eraProtVerLow @ConwayEra)
                (BSL.fromStrict rawTxOut) ::
                Either DecoderError (TxOut ConwayEra)
            )
    datum <-
        case ledgerTxOut ^. datumTxOutL of
            Datum binaryDatum ->
                let Data plutusDatum = binaryDataToData binaryDatum
                 in case checkpointDatumFromData plutusDatum of
                        Just (V1 checkpointDatum) -> Right checkpointDatum
                        Nothing -> Left DatumUndecodable
            NoDatum -> Left NoInlineDatum
            DatumHash _ -> Left NoInlineDatum
    let aid = cdCesrAid datum
        expectedAssetName = deriveAidAssetName aid
        MaryValue _ (MultiAsset policies) = ledgerTxOut ^. valueTxOutL
        checkpointAssets =
            maybe [] Map.keys (Map.lookup checkpointPolicy policies)
    carriedAssetName <-
        case checkpointAssets of
            [] -> Left NoCheckpointAsset
            [AssetName name] -> Right (SBS.fromShort name)
            _ -> Left MultipleCheckpointAssets
    if carriedAssetName /= expectedAssetName
        then Left AssetNameMismatch
        else
            Right
                CheckpointRecord
                    { crAid = aid
                    , crAssetName = carriedAssetName
                    , crTxIn = txIn
                    , crAddress = address
                    , crDatum = datum
                    }
