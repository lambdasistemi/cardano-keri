{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.WalletHoldingSpec
Description : the check that a wallet holds none of an asset counts every quantity and fails when the node cannot be read

The journey that returns an expired request and burns the attestation its booking left asks the
node what the wallet holds. The check counts the asset across all outputs, so a quantity other than one
is seen, and it fails when the query fails: a node that did not answer proves nothing.
-}
module Cardano.KERI.Deployment.WalletHoldingSpec (spec) where

import Cardano.KERI.Deployment.RegistryDeploySpec (walletAddress)
import Cardano.KERI.Deployment.RegistryTransactionsSpec (scriptHashOf)
import Cardano.KERI.Deployment.WalletHolding (heldQuantity, requireNoneHeld)
import Cardano.Ledger.Api.Tx.Out (TxOut, mkBasicTxOut)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Control.Exception (try)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Test.Hspec

policy, otherPolicy :: PolicyID
policy = PolicyID (scriptHashOf (BS.replicate 28 0x61))
otherPolicy = PolicyID (scriptHashOf (BS.replicate 28 0x62))

-- | An output holding the given quantities of assets, each under a policy and a name.
holding :: [(PolicyID, BS.ByteString, Integer)] -> TxOut ConwayEra
holding assets =
    mkBasicTxOut
        walletAddress
        (MaryValue (Coin 2_000_000) (MultiAsset (Map.fromListWith Map.union [(p, Map.singleton (AssetName (SBS.toShort n)) q) | (p, n, q) <- assets])))

spec :: Spec
spec = describe "#559 the check that a wallet holds none of an asset" $ do
    describe "the quantity it counts" $ do
        it "is zero when no output holds the asset" $
            heldQuantity policy "target" [holding [], holding [(policy, "another", 1)]] `shouldBe` 0
        it "counts a name only under its own policy" $
            heldQuantity policy "target" [holding [(otherPolicy, "target", 3), (policy, "another", 4)]] `shouldBe` 0
        it "is one for one output holding one" $
            heldQuantity policy "target" [holding [(policy, "target", 1)]] `shouldBe` 1
        it "sees a quantity other than one, which an exactly-one test would miss" $
            heldQuantity policy "target" [holding [(policy, "target", 5)]] `shouldBe` 5
        it "adds the quantity across every output the wallet has" $
            heldQuantity policy "target" [holding [(policy, "target", 1)], holding [], holding [(policy, "target", 5)]] `shouldBe` 6
    describe "the check" $ do
        let none = pure [holding [(policy, "another", 1)]]
        it "passes when the node answers and no output holds the asset" $
            requireNoneHeld "after the burn" none policy "target"
        it "fails when one output still holds the asset, naming the check" $ do
            outcome <- try @IOError (requireNoneHeld "after the burn" (pure [holding [(policy, "target", 1)]]) policy "target")
            either show (const "passed") outcome `shouldContain` "after the burn"
        it "fails when the quantity held is not one" $ do
            outcome <- try @IOError (requireNoneHeld "after the burn" (pure [holding [(policy, "target", 5)]]) policy "target")
            outcome `shouldSatisfy` either (const True) (const False)
        it "fails when the total across outputs is positive although no output holds exactly one" $ do
            outcome <- try @IOError (requireNoneHeld "after the burn" (pure [holding [(policy, "target", 2)], holding [(policy, "target", 3)]]) policy "target")
            outcome `shouldSatisfy` either (const True) (const False)
        it "fails when the node cannot be asked: the failed query is not evidence of absence" $ do
            outcome <- try @IOError (requireNoneHeld "after the burn" (ioError (userError "the node timed out")) policy "target")
            case outcome of
                Left failure -> show failure `shouldContain` "the node timed out"
                Right () -> expectationFailure "a query that failed passed the check"
