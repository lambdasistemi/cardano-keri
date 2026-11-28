{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.ComposedBookingsSpec
Description : composed bookings of the frozen signed exports: signed size, declared execution totals, fee

The booking builder books several requests in one transaction. Over the frozen signed exports of
`deployment-test/fixtures/compiled` (the compiled entry-point checks read the same bytes) each composition is built by
the production builder with the production derivation's applied programs and the ledger's in-process evaluation, then
read back: the size of the transaction with one key witness, the execution units it declares in total and per purpose,
and its fee, against the limits the target network records (`koios-recorded` protocol parameters: 16,384 bytes,
17,500,000 memory, 10,000,000,000 CPU). Every composition prints a line beginning @RECEIPT@.
-}
module Cardano.KERI.Deployment.ComposedBookingsSpec (spec) where

import Cardano.Crypto.DSIGN.Class (SignedDSIGN (..), rawDeserialiseSigDSIGN, rawDeserialiseVerKeyDSIGN)
import Cardano.KERI.Deployment.RegistryBookingEvaluationSpec (chainOf, evaluatedUnits, parameters)
import Cardano.KERI.Deployment.RegistryBookingShapeSpec (Scenario (..), claimsOf, scenarioOf)
import Cardano.KERI.Deployment.RegistryTransactions (bookRegistrations)
import Cardano.KERI.Deployment.RegistryTransactionsSpec (built, deposit, interval, pricedParameters)
import Cardano.Ledger.Alonzo.Scripts (ExUnits (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.PParams (ppMaxTxExUnitsL, ppMaxTxSizeL)
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL)
import Cardano.Ledger.Api.Tx.Wits (addrTxWitsL, rdmrsTxWitsL)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Core (sizeTxF)
import Cardano.Ledger.Keys (VKey (..), WitVKey (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Exception (SomeException, try)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Set qualified as Set
import Lens.Micro ((%~), (&), (^.))
import Test.Hspec (Spec, describe, it, shouldBe)

-- | The transaction with one key witness of the width the ledger serializes.
signedSize :: ConwayTx -> Integer
signedSize tx =
    toInteger ((tx & witsTxL . addrTxWitsL %~ Set.insert witness) ^. sizeTxF)
  where
    witness = WitVKey (VKey (fromJust (rawDeserialiseVerKeyDSIGN (BS.replicate 32 7)))) (SignedDSIGN (fromJust (rawDeserialiseSigDSIGN (BS.replicate 64 7))))

declared :: ConwayTx -> [ExUnits]
declared tx = let Redeemers m = tx ^. witsTxL . rdmrsTxWitsL in [u | (_, u) <- Map.elems m]

totals :: [ExUnits] -> (Integer, Integer)
totals us = (sum [toInteger m | ExUnits m _ <- us], sum [toInteger t | ExUnits _ t <- us])

{- | The transaction as the live path ends with it: built, evaluated by the ledger, and built again declaring what the
ledger counted for each purpose.
-}
measured :: Scenario -> IO ConwayTx
measured s = do
    params <- parameters
    let wholeTx = params ^. ppMaxTxExUnitsL
        Redeemers declaredFirst = scBooking s ^. witsTxL . rdmrsTxWitsL
        generous = Map.map (const wholeTx) declaredFirst
        build budgets =
            fst <$> built (bookRegistrations pricedParameters (scRegistry s) (scReferences s) (scPayer s) (scRequests s) interval 0 budgets)
        counted tx = either (fail . ("not evaluated: " <>) . show) pure (sequence (evaluatedUnits params (chainOf s) tx))
    -- the builder's fallback budget of a script is below what a large booking needs: the first pass gives every purpose the whole of
    -- a transaction's units, the second declares what the ledger counted
    wide <- build generous
    units <- counted wide
    build units

compose :: [String] -> [(FilePath, Integer)]
compose names = [(fixture n, deposit + 1_000_000 * k) | (k, n) <- zip [0 :: Integer ..] names]
  where
    fixture n = (if take 4 n == "kli-" then "" else "compiled/") <> n <> ".cesr"

report :: String -> [String] -> IO (Either String ())
report label names = do
    attempt <- try (scenarioOf (compose names) >>= \s -> (,) s <$> measured s)
    case attempt of
        Left err -> do
            putStrLn ("RECEIPT\tcomposed\t" <> label <> "\trequests=" <> show (length names) <> "\tnot-built\t" <> take 600 (map (\c -> if c == '\n' then ' ' else c) (show (err :: SomeException))))
            pure (Left (takeWhile (/= '\n') (show err)))
        Right (s, tx) -> do
            params <- parameters
            let us = declared tx
                (mem, steps) = totals us
                ExUnits maxMem maxSteps = params ^. ppMaxTxExUnitsL
                limitBytes = toInteger (params ^. ppMaxTxSizeL)
                Coin fee = tx ^. bodyTxL . feeTxBodyL
                booked = length (claimsOf (scRegistry s) tx (scRecords s))
                accepted = all (either (const False) (const True)) (evaluatedUnits params (chainOf s) tx)
                within = signedSize tx <= limitBytes && mem <= toInteger maxMem && steps <= toInteger maxSteps
            putStrLn $
                "RECEIPT\tcomposed\t"
                    <> label
                    <> "\trequests="
                    <> show (length names)
                    <> "\tbooked="
                    <> show booked
                    <> "\tunsigned="
                    <> show (toInteger (tx ^. sizeTxF))
                    <> "\tsigned="
                    <> show (signedSize tx)
                    <> "/"
                    <> show limitBytes
                    <> "\tpurposes="
                    <> show (length us)
                    <> "\tmemory="
                    <> show mem
                    <> "/"
                    <> show maxMem
                    <> "\tsteps="
                    <> show steps
                    <> "/"
                    <> show maxSteps
                    <> "\tfee="
                    <> show fee
                    <> "\tre-evaluated="
                    <> (if accepted then "accepted" else "refused")
            pure $
                if booked == length names && accepted && within
                    then Right ()
                    else Left "outside the network limits, refused, or not every request booked"

{- | A growing composition: every prefix of the list is built; the counts that fit are those up to the first that does not,
and none beyond it fits.
-}
growth :: String -> [String] -> IO [Int]
growth label names = do
    results <- mapM (\n -> (,) n <$> report (label <> " x" <> show n) (take n names)) [1 .. length names]
    pure [n | (n, Right ()) <- results]

spec :: Spec
spec = describe "composed bookings of the frozen signed exports, over the builder's booking entry point and the ledger's evaluation" $ do
    it "books one request of each prefix kind, B, D and E, in one transaction within the network limits" $ do
        r <- report "B+D+E" ["b-empty", "d-empty", "i02"]
        r `shouldBe` Right ()
    it "books a seal and the weighted next declarations in one transaction within the network limits" $ do
        r <- report "seal+weighted" ["d-seal", "w-exact", "w-partial"]
        r `shouldBe` Right ()
    it "books the three E-prefixed exports, one of two keys, one of five and one of three, in one transaction within the network limits" $ do
        r <- report "E x3" ["i02", "kli-export-single", "kli-export-2-of-5"]
        r `shouldBe` Right ()
    it "books each export alone within the network limits" $ do
        let names = ["b-empty", "d-empty", "d-seal", "i02", "w-exact", "w-partial", "kli-export-single", "kli-export-2-of-5"]
        rs <- mapM (\n -> report n [n]) names
        rs `shouldBe` map (const (Right ())) names
    it "reads how many requests of the six non-anchor shapes one transaction books" $ do
        fits <- growth "shapes" ["b-empty", "d-empty", "d-seal", "w-exact", "w-partial", "i02"]
        fits `shouldBe` [1 .. length fits]
    it "reads how many of the largest fitting events one transaction books" $ do
        fits <- growth "anchors" ["anchors-13", "anchors-12", "anchors-10", "anchors-08", "anchors-04", "anchors-02", "anchors-01", "anchors-00"]
        fits `shouldBe` [1 .. length fits]
    it "reads how many of the smallest events one transaction books, then of the middle ones" $ do
        small <- growth "anchors ascending" ["anchors-00", "anchors-01", "anchors-02", "anchors-04", "anchors-08", "anchors-10", "anchors-12", "anchors-13"]
        small `shouldBe` [1 .. length small]
