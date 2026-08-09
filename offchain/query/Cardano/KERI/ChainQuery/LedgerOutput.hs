{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.ChainQuery.LedgerOutput
Description : Pure, provider-neutral reconstruction of ledger outputs (A-001)

Per A-001 (ruling on Q-001): the selected snapshot interpreter is the sole,
fully-resolving authority for a registration phase's reference and payer
rows — never N2C. This module is the shared, pure (no HTTP, no store
handle) reconstruction any interpreter's already-decoded 'ChainAssetUtxo'\/
'ChainReference' can be converted through into the exact ledger
'Cardano.Ledger.Core.TxOut' a transaction builder consumes. Conversion is
total and fail-closed: a malformed address, value, datum, or a
reference-script whose decoded bytes do not hash to the requested script
hash returns 'ChainQueryError', never a partial or invented value
(DATA-INV-257-01).
-}
module Cardano.KERI.ChainQuery.LedgerOutput (
    chainAssetUtxoToLedgerOutput,
    chainReferenceToLedgerOutput,
) where

import Cardano.Crypto.Hash.Class (hashFromBytes, hashToBytes)
import Cardano.KERI.ChainQuery.PlutusJson (plutusDataFromJson)
import Cardano.KERI.ChainQuery.Types (
    ChainAsset (..),
    ChainAssetUtxo (..),
    ChainQueryError (..),
    ChainReference (..),
    ChainReferenceScript (..),
 )
import Cardano.Ledger.Address (Addr, decodeAddrEither)
import Cardano.Ledger.Alonzo.Scripts (AlonzoEraScript (..))
import Cardano.Ledger.Api.Scripts.Data (Data (Data), Datum (Datum), dataToBinaryData)
import Cardano.Ledger.Api.Tx.Out (datumTxOutL, mkBasicTxOut, referenceScriptTxOutL)
import Cardano.Ledger.BaseTypes (StrictMaybe (SJust), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, TxOut, hashScript)
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.Language (Language (..), Plutus (..), PlutusBinary (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Codec.Binary.Bech32 qualified as Bech32
import Data.Aeson (Value)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word16)
import Lens.Micro ((&), (.~))

{- | DAT-257-ASSET-OUTPUT: reconstruct a payer row. Any reference script the
output happens to carry is still decoded and attached (fail-closed on
malformed bytes) but its hash is not cross-checked against a request,
since none is named here.
-}
chainAssetUtxoToLedgerOutput :: ChainAssetUtxo -> Either ChainQueryError (TxIn, TxOut ConwayEra)
chainAssetUtxoToLedgerOutput = convertOutput Nothing

{- | DAT-257-REFERENCE: reconstruct a reference row whose decoded script
bytes must hash to the requested script hash.
-}
chainReferenceToLedgerOutput :: ChainReference -> Either ChainQueryError (TxIn, TxOut ConwayEra)
chainReferenceToLedgerOutput ref =
    convertOutput (Just (chainReferenceScriptHash ref)) (chainReferenceOutput ref)

convertOutput :: Maybe Text -> ChainAssetUtxo -> Either ChainQueryError (TxIn, TxOut ConwayEra)
convertOutput expectedScriptHash utxo = do
    txIn <- decodeTxIn (chainAssetTxId utxo) (chainAssetIndex utxo)
    addr <- decodeAddress (chainAssetAddress utxo)
    assets <- assetsToMultiAsset (chainAssetList utxo)
    let value = MaryValue (Coin (chainAssetLovelace utxo)) assets
        base = mkBasicTxOut addr value
    withDatum <- attachDatum (chainAssetInlineDatum utxo) base
    withScript <-
        attachReferenceScript expectedScriptHash (chainAssetReferenceScript utxo) withDatum
    pure (txIn, withScript)

decodeTxIn :: Text -> Int -> Either ChainQueryError TxIn
decodeTxIn txIdHex index = do
    checkIndexRange
    bytes <- decodeHex txIdHex
    checkTxIdLength bytes
    digest <-
        maybe
            (Left (DecodingFailure ("transaction id is not a ledger hash: " <> txIdHex)))
            Right
            (hashFromBytes bytes)
    pure (TxIn (TxId (unsafeMakeSafeHash digest)) (TxIx (fromIntegral index)))
  where
    checkIndexRange
        | index < 0 || index > fromIntegral (maxBound :: Word16) =
            Left (DecodingFailure ("output index outside the ledger range: " <> T.pack (show index)))
        | otherwise = Right ()
    checkTxIdLength bytes
        | BS.length bytes /= 32 =
            Left (DecodingFailure ("transaction id is not 32 bytes: " <> txIdHex))
        | otherwise = Right ()

decodeAddress :: Text -> Either ChainQueryError Addr
decodeAddress bech32Text = do
    (_hrp, dataPart) <-
        first
            (\err -> DecodingFailure ("address is not bech32: " <> T.pack (show err)))
            (Bech32.decodeLenient bech32Text)
    bytes <-
        maybe (Left (DecodingFailure "address data part is invalid")) Right (Bech32.dataPartToBytes dataPart)
    first (DecodingFailure . T.pack) (decodeAddrEither bytes)

assetsToMultiAsset :: [ChainAsset] -> Either ChainQueryError MultiAsset
assetsToMultiAsset assets = do
    entries <- traverse toEntry assets
    pure $ MultiAsset $ Map.fromListWith (Map.unionWith (+)) entries
  where
    toEntry a = do
        policyHash <- decodeScriptHash28 (chainAssetPolicy a)
        nameBytes <- decodeHex (chainAssetName a)
        pure
            ( PolicyID policyHash
            , Map.singleton (AssetName (SBS.toShort nameBytes)) (chainAssetQuantity a)
            )

attachDatum :: Maybe Value -> TxOut ConwayEra -> Either ChainQueryError (TxOut ConwayEra)
attachDatum Nothing txOut = pure txOut
attachDatum (Just jsonValue) txOut =
    case plutusDataFromJson jsonValue of
        Left err -> Left (DecodingFailure ("inline datum is not valid Plutus data: " <> T.pack err))
        Right dat -> pure (txOut & datumTxOutL .~ Datum (dataToBinaryData (Data dat)))

attachReferenceScript ::
    Maybe Text ->
    Maybe ChainReferenceScript ->
    TxOut ConwayEra ->
    Either ChainQueryError (TxOut ConwayEra)
attachReferenceScript Nothing Nothing txOut = pure txOut
attachReferenceScript Nothing (Just scriptInfo) txOut = do
    script <- decodeScript scriptInfo
    pure (txOut & referenceScriptTxOutL .~ SJust script)
attachReferenceScript (Just _) Nothing _ =
    Left (DecodingFailure "requested reference output carries no reference script")
attachReferenceScript (Just expectedHex) (Just scriptInfo) txOut = do
    script <- decodeScript scriptInfo
    let actualHex = hexScriptHash (hashScript script)
    if actualHex /= expectedHex
        then
            Left $
                DecodingFailure $
                    "reference script bytes hash to "
                        <> actualHex
                        <> ", not the requested "
                        <> expectedHex
        else pure (txOut & referenceScriptTxOutL .~ SJust script)

decodeScript :: ChainReferenceScript -> Either ChainQueryError (Script ConwayEra)
decodeScript info = do
    bytes <- decodeHex (chainReferenceScriptBytes info)
    let shortBytes = SBS.toShort bytes
    case T.toLower (chainReferenceScriptType info) of
        "plutusv1" -> wrap (mkPlutusScript (Plutus @'PlutusV1 (PlutusBinary shortBytes)))
        "plutusv2" -> wrap (mkPlutusScript (Plutus @'PlutusV2 (PlutusBinary shortBytes)))
        "plutusv3" -> wrap (mkPlutusScript (Plutus @'PlutusV3 (PlutusBinary shortBytes)))
        other -> Left (DecodingFailure ("unsupported reference script type: " <> other))
  where
    wrap =
        maybe
            (Left (DecodingFailure "reference script bytes are not a valid Plutus script"))
            (Right . fromPlutusScript)

decodeScriptHash28 :: Text -> Either ChainQueryError ScriptHash
decodeScriptHash28 hexHash = do
    bytes <- decodeHex hexHash
    if BS.length bytes /= 28
        then Left (DecodingFailure ("script hash is not 28 bytes: " <> hexHash))
        else do
            digest <-
                maybe
                    (Left (DecodingFailure ("script hash is not a ledger hash: " <> hexHash)))
                    Right
                    (hashFromBytes bytes)
            pure (ScriptHash digest)

decodeHex :: Text -> Either ChainQueryError ByteString
decodeHex hexText =
    first
        (const (DecodingFailure ("not hexadecimal: " <> hexText)))
        (convertFromBase Base16 (TE.encodeUtf8 hexText))

hexScriptHash :: ScriptHash -> Text
hexScriptHash (ScriptHash digest) = TE.decodeUtf8 (convertToBase Base16 (hashToBytes digest))
