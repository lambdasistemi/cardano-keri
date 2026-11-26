{- |
Module      : Cardano.KERI.Deployment.WalletHolding
Description : what a wallet holds of one asset, and the check that it holds none

A journey that burns an asset asks the node what the wallet holds afterwards. The answer is the
total quantity across every output the node returns, and the check that it is zero fails when the
node cannot be asked: a failed read is no evidence of absence.
-}
module Cardano.KERI.Deployment.WalletHolding (
    heldQuantity,
    requireNoneHeld,
) where

import Cardano.Ledger.Api.Tx.Out (TxOut, valueTxOutL)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID)
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))

-- | The total quantity of an asset the outputs hold: every output counts, whatever quantity it holds.
heldQuantity :: PolicyID -> ByteString -> [TxOut ConwayEra] -> Integer
heldQuantity policy name outputs =
    sum
        [ quantity
        | out <- outputs
        , let MaryValue _ (MultiAsset assets) = out ^. valueTxOutL
        , Just names <- [Map.lookup policy assets]
        , Just quantity <- [Map.lookup (AssetName (SBS.toShort name)) names]
        ]

{- | The check that the outputs the node returns hold none of an asset. The query is run here, and
its own failure is the check's: nothing is caught, so an unanswered question never passes.
-}
requireNoneHeld :: String -> IO [TxOut ConwayEra] -> PolicyID -> ByteString -> IO ()
requireNoneHeld label query policy name = do
    outputs <- query
    let held = heldQuantity policy name outputs
    unless (held == 0) $
        ioError (userError (label <> ": the wallet still holds " <> show held <> " of the asset"))
