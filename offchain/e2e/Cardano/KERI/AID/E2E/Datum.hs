{- |
Module      : Cardano.KERI.AID.E2E.Datum
Description : Plutus <-> ledger Data conversions for the cage e2e builder

Adapts the read-only @Cardano.MPFS.OnChain.Datum@ precedent: convert a
@ToData@ value into a ledger 'Data' or an inline 'Datum', and read a
@FromData@ value back out of a spent 'TxOut'.
-}
module Cardano.KERI.AID.E2E.Datum (
    toPlcData,
    toLedgerData,
    mkInlineDatum,
    extractDatum,
    rawInlineData,
) where

import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    binaryDataToData,
    dataToBinaryData,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, datumTxOutL)
import Cardano.Ledger.Conway (ConwayEra)
import Lens.Micro ((^.))
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (FromData (..), ToData (..))

-- | Extract the raw Plutus 'PLC.Data' from a @ToData@ value.
toPlcData :: (ToData a) => a -> PLC.Data
toPlcData x = let BuiltinData d = toBuiltinData x in d

-- | Convert a @ToData@ value into a ledger 'Data'.
toLedgerData :: (ToData a) => a -> Data ConwayEra
toLedgerData = Data . toPlcData

-- | Wrap Plutus 'PLC.Data' as an inline 'Datum'.
mkInlineDatum :: PLC.Data -> Datum ConwayEra
mkInlineDatum d = Datum $ dataToBinaryData (Data d :: Data ConwayEra)

-- | Read a @FromData@ value out of a spent output's inline datum.
extractDatum :: (FromData a) => TxOut ConwayEra -> Maybe a
extractDatum txOut =
    case txOut ^. datumTxOutL of
        Datum bd ->
            let Data plcData = binaryDataToData bd
             in fromBuiltinData (BuiltinData plcData)
        _ -> Nothing

{- | Read the raw Plutus 'PLC.Data' of an output's inline datum, for
structural inspection without a full @FromData@ instance.
-}
rawInlineData :: TxOut ConwayEra -> Maybe PLC.Data
rawInlineData txOut =
    case txOut ^. datumTxOutL of
        Datum bd -> let Data plcData = binaryDataToData bd in Just plcData
        _ -> Nothing
