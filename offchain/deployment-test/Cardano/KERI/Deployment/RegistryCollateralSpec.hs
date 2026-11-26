{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryCollateralSpec
Description : the collateral of a balanced body is declared at the fee the body ends with

A body that runs a script names its collateral input, the total collateral it will pay if the script fails, and the
output that returns the rest to the payer. These examples balance one body at the boundaries of that rule: a collateral
that is larger than the fee needs, one short of it, exactly the total, one lovelace under and exactly at the least an
output may hold, and one over it. Each reads the body that comes out, never a calculation beside it.
-}
module Cardano.KERI.Deployment.RegistryCollateralSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.RegistryDeploySpec (pricedParameters)
import Cardano.KERI.Deployment.RegistryTransactions (Funding (..), RegistryTransactionError (..), balanced)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Alonzo.PParams (ppCollateralPercentageL)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (bodyTxL, estimateMinFeeTx, mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (collateralReturnTxBodyL, feeTxBodyL, mkBasicTxBody, totalCollateralTxBodyL)
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, coinTxOutL, getMinCoinTxOut, mkBasicTxOut)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (Inject (..), Network (..), StrictMaybe (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Credential (Credential (KeyHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Lens.Micro ((&), (.~), (^.))
import PlutusCore.Data qualified as PLC
import Test.Hspec

payer :: Addr
payer = Addr Testnet (KeyHashObj (KeyHash (fromJust (hashFromBytes (BS.replicate 28 0x55))))) StakeRefNull

refundTo :: Addr
refundTo = Addr Testnet (KeyHashObj (KeyHash (fromJust (hashFromBytes (BS.replicate 28 0x66))))) StakeRefNull

refOf :: Int -> TxIn
refOf n = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 (fromIntegral n)))))) (TxIx 0)

{- | A body that runs one script, pays 5 ada to a refund address and is funded by a collateral output of the given
lovelace and a larger one besides it.
-}
balancedWith :: Integer -> Either RegistryTransactionError ConwayTx
balancedWith held = balancedAmong held 50_000_000

balancedAmong :: Integer -> Integer -> Either RegistryTransactionError ConwayTx
balancedAmong held other =
    balanced pricedParameters [] [collateral, extra] [refund] payer (Funding [collateral, extra] collateral) template
  where
    collateral = (refOf 1, mkBasicTxOut payer (inject (Coin held)))
    extra = (refOf 2, mkBasicTxOut payer (inject (Coin other)))
    refund = mkBasicTxOut refundTo (inject (Coin 5_000_000))
    template =
        mkBasicTx mkBasicTxBody
            & witsTxL . rdmrsTxWitsL .~ Redeemers (Map.singleton (ConwaySpending (AsIx 0)) (Data (PLC.I 0), ExUnits 1_000_000 400_000_000))

percentage :: Integer
percentage = fromIntegral (pricedParameters ^. ppCollateralPercentageL)

required :: ConwayTx -> Integer
required tx = let Coin fee = tx ^. bodyTxL . feeTxBodyL in (fee * percentage + 99) `div` 100

built :: Integer -> IO ConwayTx
built held = either (\e -> fail ("held " <> show held <> " not built: " <> show e)) pure (balancedWith held)

-- | The least an output that returns lovelace to the payer may hold.
leastReturn :: Integer
leastReturn = let Coin c = getMinCoinTxOut pricedParameters (mkBasicTxOut payer (inject (Coin 1_000_000))) in c

-- | The smallest value in a range for which a predicate holds, the predicate being false below it and true from it.
smallest :: (Integer -> IO Bool) -> Integer -> Integer -> IO Integer
smallest holds low high
    | low >= high = pure high
    | otherwise = do
        let middle = (low + high) `div` 2
        ok <- holds middle
        if ok then smallest holds low middle else smallest holds (middle + 1) high

builds :: Integer -> Bool
builds = either (const False) (const True) . balancedWith

returns :: Integer -> Bool
returns held = case balancedWith held of
    Right tx -> tx ^. bodyTxL . collateralReturnTxBodyL /= SNothing
    Left _ -> False

spec :: Spec
spec = describe "#558 the collateral of a balanced body is declared at the fee the body ends with" $ do
    it "returns the excess of a large collateral: the total is the rounded 150% of the fee the body pays, the rest goes to the payer" $ do
        tx <- built 100_000_000
        let total = required tx
        tx ^. bodyTxL . totalCollateralTxBodyL `shouldBe` SJust (Coin total)
        case tx ^. bodyTxL . collateralReturnTxBodyL of
            SJust out -> do
                out ^. coinTxOutL `shouldBe` Coin (100_000_000 - total)
                out ^. addrTxOutL `shouldBe` payer
            SNothing -> expectationFailure "no collateral return"
    it "prices the return into the fee: the body pays more than the least its body without the return would" $ do
        tx <- built 100_000_000
        let stripped = tx & bodyTxL . totalCollateralTxBodyL .~ SNothing & bodyTxL . collateralReturnTxBodyL .~ SNothing
            Coin without = estimateMinFeeTx pricedParameters stripped 1 0 0
            Coin paid = tx ^. bodyTxL . feeTxBodyL
        paid `shouldSatisfy` (> without)
    it "prices one key witness: the fee it pays is the least for the body it ends with, with that witness" $ do
        tx <- built 100_000_000
        let Coin paid = tx ^. bodyTxL . feeTxBodyL
            Coin least = estimateMinFeeTx pricedParameters tx 1 0 0
        paid `shouldBe` least
    it "is refused at the collateral one lovelace under the smallest that builds, and that smallest is the rounded final fee" $ do
        smallestHeld <- smallest (pure . builds) 1 100_000_000
        smallestHeld `shouldSatisfy` (> 1)
        balancedWith (smallestHeld - 1) `shouldSatisfy` isNotEnough
        mapM_ (\extra -> builds (smallestHeld + extra) `shouldBe` True) [0, 1, 7, 1_000]
        tx <- built smallestHeld
        -- nothing is left to return: the collateral is the total, and the total is the rounded 150% of the fee paid
        tx ^. bodyTxL . totalCollateralTxBodyL `shouldBe` SJust (Coin smallestHeld)
        tx ^. bodyTxL . collateralReturnTxBodyL `shouldBe` SNothing
        required tx `shouldBe` smallestHeld
    it "takes the whole collateral as the total, and returns nothing, up to one lovelace under the least a return may hold" $ do
        smallestHeld <- smallest (pure . builds) 1 100_000_000
        firstReturn <- smallest (pure . returns) smallestHeld 100_000_000
        firstReturn `shouldSatisfy` (> smallestHeld)
        mapM_
            ( \held -> do
                tx <- built held
                tx ^. bodyTxL . totalCollateralTxBodyL `shouldBe` SJust (Coin held)
                tx ^. bodyTxL . collateralReturnTxBodyL `shouldBe` SNothing
            )
            [smallestHeld, smallestHeld + 1, firstReturn - 1]
    it "returns exactly the least an output may hold at the first collateral that returns anything, and one lovelace more for one more" $ do
        smallestHeld <- smallest (pure . builds) 1 100_000_000
        firstReturn <- smallest (pure . returns) smallestHeld 100_000_000
        atLeast <- built firstReturn
        fmap (^. coinTxOutL) (atLeast ^. bodyTxL . collateralReturnTxBodyL) `shouldBe` SJust (Coin leastReturn)
        atLeast ^. bodyTxL . totalCollateralTxBodyL `shouldBe` SJust (Coin (required atLeast))
        above <- built (firstReturn + 1)
        fmap (^. coinTxOutL) (above ^. bodyTxL . collateralReturnTxBodyL) `shouldBe` SJust (Coin (leastReturn + 1))
        above ^. bodyTxL . totalCollateralTxBodyL `shouldBe` SJust (Coin (required atLeast))
    it "still refuses a body whose change would be under the least an output may hold" $ do
        reference <- either (fail . show) pure (balancedAmong 2_000_000 50_000_000)
        let Coin fee = reference ^. bodyTxL . feeTxBodyL
        case balancedAmong 2_000_000 (5_000_000 + fee - 2_000_000 + 100_000) of
            Left (FeeRefused _) -> pure ()
            other -> expectationFailure ("not a refusal for a thin change: " <> either show (const "a built body") other)
  where
    isNotEnough = \case
        Left (NotEnoughFunds _) -> True
        _ -> False
