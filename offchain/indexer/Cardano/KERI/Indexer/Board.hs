{- |
Module      : Cardano.KERI.Indexer.Board
Description : Adapt indexed ledger board outputs into the frozen EndpointBoard oracle

FR-6 requires the query endpoint to authenticate board records "using the
existing 'Cardano.KERI.Deployment.EndpointBoard' semantics" with "no Koios
serving dependency". This module changes only the /input/ shape:
'Cardano.KERI.Deployment.EndpointBoard.resolveBoardCatalog' already accepts a
generic @['Cardano.KERI.Deployment.ChainIndex.ChainAssetUtxo']@ (Koios's
extended-UTxO JSON shape); 'indexedBoardCatalog' re-encodes each indexed
ledger 'TxOut' into that exact shape — using
'Cardano.KERI.Deployment.Registration.plutusDataJson', the already-exported
exact inverse of the 'Cardano.KERI.Deployment.Registration.plutusDataFromJson'
'resolveBoardCatalog' itself calls — and hands the list to the frozen,
unmodified validator. No signature/SAID/marker verification logic is
duplicated here; a decode failure on any single output fails the whole
catalog closed, exactly as a forged or malformed output does inside
'resolveBoardCatalog'.
-}
module Cardano.KERI.Indexer.Board (
    indexedBoardCatalog,
) where

import Cardano.Crypto.Hash.Class (hashToBytes)
import Cardano.KERI.ChainQuery (
    BoardEntry,
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.ChainQuery.PlutusJson (
    plutusDataJson,
 )
import Cardano.KERI.Deployment.EndpointBoard (
    resolveBoardCatalog,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    frozenEndpointBoardPolicyId,
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
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address (..),
    TxIn (..),
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Lens.Micro ((^.))

{- | Resolve the authenticated board catalog from every indexed output at
the configured board address, through the frozen 'resolveBoardCatalog'
oracle. Fails closed (returns 'Left') on the first undecodable, forged, or
malformed output — never a partial catalog.
-}
indexedBoardCatalog ::
    Address ->
    [(Indexer.TxIn, Indexer.TxOut)] ->
    Either String [BoardEntry]
indexedBoardCatalog addr entries = do
    utxos <- traverse (toChainAssetUtxo addressHex) entries
    resolveBoardCatalog frozenEndpointBoardPolicyId addressHex utxos
  where
    addressHex = hex (unAddress addr)

toChainAssetUtxo ::
    Text ->
    (Indexer.TxIn, Indexer.TxOut) ->
    Either String ChainAssetUtxo
toChainAssetUtxo addressHex (TxIn{txInId, txInIx}, Indexer.TxOut rawTxOut) = do
    ledgerTxOut <-
        first
            (("board output undecodable: " <>) . show)
            ( decodeFull
                (eraProtVerLow @ConwayEra)
                (BSL.fromStrict rawTxOut) ::
                Either DecoderError (TxOut ConwayEra)
            )
    let MaryValue (Coin lovelace) (MultiAsset policies) =
            ledgerTxOut ^. valueTxOutL
        assets =
            [ ChainAsset
                { chainAssetPolicy = policyIdHex policy
                , chainAssetName = assetNameHex name
                , chainAssetQuantity = quantity
                }
            | (policy, byName) <- Map.toList policies
            , (name, quantity) <- Map.toList byName
            ]
        inlineDatum = case ledgerTxOut ^. datumTxOutL of
            Datum binaryDatum ->
                let Data plutusDatum = binaryDataToData binaryDatum
                 in Just (plutusDataJson plutusDatum)
            NoDatum -> Nothing
            DatumHash _ -> Nothing
    pure
        ChainAssetUtxo
            { chainAssetTxId = hex txInId
            , chainAssetIndex = fromIntegral txInIx
            , chainAssetAddress = addressHex
            , chainAssetLovelace = lovelace
            , chainAssetList = assets
            , chainAssetInlineDatum = inlineDatum
            , chainAssetReferenceScript = Nothing
            }

policyIdHex :: PolicyID -> Text
policyIdHex (PolicyID (ScriptHash h)) = hex (hashToBytes h)

assetNameHex :: AssetName -> Text
assetNameHex (AssetName name) = hex (SBS.fromShort name)

hex :: BS.ByteString -> Text
hex = TE.decodeUtf8 . Base16.encode
