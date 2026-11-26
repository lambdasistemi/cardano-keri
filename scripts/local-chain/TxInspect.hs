{-# LANGUAGE OverloadedStrings, TypeApplications #-}
-- Test-side inspector: print what a hex-encoded Conway transaction pays and declares.
-- usage: runghc TxInspect.hs <file with the transaction's CBOR as hex>
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Conway.TxBody (treasuryDonationTxBodyL)
import Cardano.Ledger.Api.Tx.Body (mintTxBodyL, feeTxBodyL, inputsTxBodyL, outputsTxBodyL, referenceInputsTxBodyL, collateralInputsTxBodyL, collateralReturnTxBodyL, totalCollateralTxBodyL, scriptIntegrityHashTxBodyL, vldtTxBodyL)
import Cardano.Ledger.Api.Tx.Out (coinTxOutL)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.Binary (decodeFullAnnotator, decCBOR, serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Crypto.Hash (hashToBytes)
import Data.ByteString.Short qualified as SBS
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Data.Foldable (toList)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Lens.Micro ((^.))
import System.Environment (getArgs)

main :: IO ()
main = do
    [path] <- getArgs
    hex <- B8.filter (`notElem` ("\n\r \"" :: String)) <$> BS.readFile path
    bytes <- maybe (fail "not hex") pure (unhex (B8.unpack hex))
    tx <- either (fail . show) pure (decodeFullAnnotator (eraProtVerHigh @ConwayEra) "ConwayTx" decCBOR (BL.fromStrict bytes)) :: IO ConwayTx
    let body = tx ^. bodyTxL
        Coin fee = body ^. feeTxBodyL
        Redeemers declared = tx ^. witsTxL . rdmrsTxWitsL
        outs = toList (body ^. outputsTxBodyL)
    putStrLn ("size " <> show (BS.length bytes))
    putStrLn ("fee " <> show fee)
    putStrLn ("inputs " <> show (Set.size (body ^. inputsTxBodyL)))
    putStrLn ("reference-inputs " <> show (Set.size (body ^. referenceInputsTxBodyL)))
    putStrLn ("collateral-inputs " <> show (Set.size (body ^. collateralInputsTxBodyL)))
    putStrLn ("outputs " <> show (length outs) <> " lovelace " <> show (sum [c | o <- outs, let Coin c = o ^. coinTxOutL]))
    putStrLn ("redeemers " <> show [ (show purpose, mem, steps) | (purpose, (_, ExUnits mem steps)) <- Map.toList declared ])
    putStrLn ("total-ex-units " <> show (sum [m | (_, (_, ExUnits m _)) <- Map.toList declared], sum [s | (_, (_, ExUnits _ s)) <- Map.toList declared]))
    let MultiAsset minted = body ^. mintTxBodyL
        hexOf = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
        digits = "0123456789abcdef"
    putStrLn ("mint " <> show [ (hexOf (hashToBytes h), hexOf (SBS.fromShort n), q) | (PolicyID (ScriptHash h), names) <- Map.toList minted, (AssetName n, q) <- Map.toList names ])
    let Coin donation = body ^. treasuryDonationTxBodyL
    putStrLn ("treasury-donation " <> show donation)
    putStrLn ("validity " <> show (body ^. vldtTxBodyL))

unhex :: String -> Maybe BS.ByteString
unhex = fmap BS.pack . go
  where
    go [] = Just []
    go (a : b : rest) = (:) <$> ((\x y -> fromIntegral (x * 16 + y)) <$> digit a <*> digit b) <*> go rest
    go _ = Nothing
    digit c
        | c >= '0' && c <= '9' = Just (fromEnum c - fromEnum '0')
        | c >= 'a' && c <= 'f' = Just (fromEnum c - fromEnum 'a' + 10)
        | c >= 'A' && c <= 'F' = Just (fromEnum c - fromEnum 'A' + 10)
        | otherwise = Nothing
