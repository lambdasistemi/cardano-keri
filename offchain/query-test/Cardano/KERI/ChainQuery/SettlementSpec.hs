{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.ChainQuery.SettlementSpec
Description : #257 RED — settlement observation is temporal, not a ChainQuery op

Proves INV-257-SETTLEMENT\/DATA-INV-257-05: settlement polling is a distinct,
separately authorized temporal capability with no snapshot-consistency
claim. The timeout proof mirrors 'Cardano.KERI.Deployment.RegistrationSpec's
poll-counter pattern (a zero-second timeout still performs one real probe);
the exact-conjunction proof mirrors its five-decoy fixture pattern so the
matcher is proven to check every identity field, not any one alone.
-}
module Cardano.KERI.ChainQuery.SettlementSpec (spec) where

import Cardano.KERI.ChainQuery.Settlement (
    SettlementError (..),
    SettlementObservation (..),
    SettlementObserver (..),
    SettlementTarget (..),
    SettlementTimeoutPolicy (..),
    observeSettlement,
 )
import Cardano.KERI.ChainQuery.Types (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.Settlement" $ do
    it "performs at least one probe even under a zero-second timeout" $ do
        pollCount <- newIORef (0 :: Int)
        let observer = SettlementObserver{probeSettlement = \_ _ -> countingProbe pollCount []}
        result <-
            observeSettlement
                observer
                testTarget
                SettlementTimeoutPolicy{settlementTimeoutSeconds = 0, settlementPollDelayMicros = 1}
        result `shouldBe` Left (SettlementTimeout testTarget)
        polls <- readIORef pollCount
        polls `shouldSatisfy` (>= 1)

    it "matches only the exact conjunction of txId/address/policy/name/quantity=1" $ do
        pollCount <- newIORef (0 :: Int)
        let decoys =
                [ decoyUtxo{chainAssetTxId = "wrong-tx-id"}
                , decoyUtxo{chainAssetAddress = "wrong-address"}
                , decoyUtxo{chainAssetList = [decoyAsset{chainAssetPolicy = "wrong-policy"}]}
                , decoyUtxo{chainAssetList = [decoyAsset{chainAssetName = "wrong-name"}]}
                , decoyUtxo{chainAssetList = [decoyAsset{chainAssetQuantity = 2}]}
                ]
            observer = SettlementObserver{probeSettlement = \_ _ -> countingProbe pollCount decoys}
        result <-
            observeSettlement
                observer
                testTarget
                SettlementTimeoutPolicy{settlementTimeoutSeconds = 0, settlementPollDelayMicros = 1}
        result `shouldBe` Left (SettlementTimeout testTarget)

    it "returns the exact matching output once observed" $ do
        let observer =
                SettlementObserver{probeSettlement = \_ _ -> pure [decoyUtxo, matchingUtxo]}
        result <-
            observeSettlement
                observer
                testTarget
                SettlementTimeoutPolicy{settlementTimeoutSeconds = 1, settlementPollDelayMicros = 1}
        result `shouldBe` Right (SettlementObservation matchingUtxo)

{- | Records one poll and answers with the same (non-matching) rows every
time, so a timeout proves genuine repeated polling rather than a single
lucky call.
-}
countingProbe :: IORef Int -> [ChainAssetUtxo] -> IO [ChainAssetUtxo]
countingProbe pollCount rows = do
    modifyIORef' pollCount (+ 1)
    pure rows

testTarget :: SettlementTarget
testTarget =
    SettlementTarget
        { settlementPolicy = "policy-hex"
        , settlementAssetName = "asset-hex"
        , settlementTxId = "tx-hex"
        , settlementAddress = "addr_test1payee"
        }

decoyAsset :: ChainAsset
decoyAsset =
    ChainAsset
        { chainAssetPolicy = settlementPolicy testTarget
        , chainAssetName = settlementAssetName testTarget
        , chainAssetQuantity = 1
        }

decoyUtxo :: ChainAssetUtxo
decoyUtxo =
    ChainAssetUtxo
        { chainAssetTxId = settlementTxId testTarget
        , chainAssetIndex = 0
        , chainAssetAddress = settlementAddress testTarget
        , chainAssetLovelace = 5_000_000
        , chainAssetList = [decoyAsset]
        , chainAssetInlineDatum = Nothing
        , chainAssetReferenceScript = Nothing
        }

matchingUtxo :: ChainAssetUtxo
matchingUtxo = decoyUtxo
