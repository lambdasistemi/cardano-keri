{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- Test-side helper: a transaction a ledger will refuse, made from one that settled.
-- usage: runghc MutateTx.hs <hex of a settled transaction> <output file for the hex of the refused one>
-- The validity end is moved by one slot: the body, and so the transaction's identifier, change, and the
-- signature the witness set carries no longer covers it. The mutant spends inputs the original already spent.
-- It prints the identifier of the mutant. Local chain only.
import Cardano.Ledger.Api.Tx (bodyTxL, txIdTx)
import Cardano.Ledger.Api.Tx.Body (vldtTxBodyL)
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.BaseTypes (StrictMaybe (..))
import Cardano.Ledger.Binary (decCBOR, decodeFullAnnotator, serialize')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Slotting.Slot (SlotNo (..))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Lens.Micro ((&), (.~), (^.))
import System.Environment (getArgs)

main :: IO ()
main = do
    [input, output] <- getArgs
    hex <- B8.filter (`notElem` ("\n\r \"" :: String)) <$> BS.readFile input
    bytes <- maybe (fail "not hex") pure (unhex (B8.unpack hex))
    tx <- either (fail . show) pure (decodeFullAnnotator (eraProtVerHigh @ConwayEra) "ConwayTx" decCBOR (BL.fromStrict bytes)) :: IO ConwayTx
    let ValidityInterval before after = tx ^. bodyTxL . vldtTxBodyL
        moved = case after of
            SJust (SlotNo slot) -> SJust (SlotNo (slot + 1))
            SNothing -> SJust (SlotNo 1)
        mutant = tx & bodyTxL . vldtTxBodyL .~ ValidityInterval before moved
    B8.writeFile output (B8.pack (hexOf (serialize' (eraProtVerHigh @ConwayEra) mutant)) <> "\n")
    print (txIdTx mutant)
  where
    hexOf = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
    digits = "0123456789abcdef" :: String

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
