{- |
Module      : Cardano.Node.Client.Balance
Description : Compatibility seam for the nodeclients PV11 bump

The PV11 nodeclients revision moved transaction balancing to
@cardano-tx-tools:tx-build@. This shim preserves the pre-existing Cage imports
unchanged while the Register builder uses the new module directly.
-}
module Cardano.Node.Client.Balance (
    module Tx,
    computeScriptIntegrity,
) where

import Cardano.Ledger.Alonzo.TxBody (ScriptIntegrityHash)
import Cardano.Ledger.Alonzo.TxWits (Redeemers, TxDats (..))
import Cardano.Ledger.BaseTypes (StrictMaybe)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Plutus.Language (Language)
import Cardano.Tx.Balance as Tx hiding (computeScriptIntegrity)
import Cardano.Tx.Balance qualified as Tx
import Data.Set qualified as Set

computeScriptIntegrity ::
    Language ->
    PParams ConwayEra ->
    Redeemers ConwayEra ->
    StrictMaybe ScriptIntegrityHash
computeScriptIntegrity language parameters redeemers =
    Tx.computeScriptIntegrity
        (Set.singleton language)
        parameters
        redeemers
        (TxDats mempty)
