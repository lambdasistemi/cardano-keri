{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.KERI.Deployment.ChainIndexSpec (spec) where

import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetHistory (..),
    ChainMintingTransaction (..),
    ChainScriptRedeemer (..),
    ChainScriptRedeemers (..),
    ChainTransactionPart (..),
    ChainTransactionUtxos (..),
    KoiosToken (..),
    authorizeKoiosRequest,
 )
import Cardano.KERI.Deployment.CheckpointIndex (resolveClosedCheckpoint)
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Network.HTTP.Simple (getRequestHeader, parseRequest)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = do
    describe "Koios authorization" $ do
        it "uses anonymous requests when no token is configured" $ do
            request <- parseRequest "https://preprod.koios.rest/api/v1/tip"
            getRequestHeader
                "authorization"
                (authorizeKoiosRequest Nothing request)
                `shouldBe` []
        it "uses a bearer token when one is configured" $ do
            request <- parseRequest "https://preprod.koios.rest/api/v1/tip"
            getRequestHeader
                "authorization"
                (authorizeKoiosRequest (Just $ KoiosToken "operator-token") request)
                `shouldBe` ["Bearer operator-token"]
        it "redacts the configured token from diagnostics" $
            show (KoiosToken "operator-token")
                `shouldBe` "KoiosToken <redacted>"

    describe "proved checkpoint closure" $ do
        it "requires the latest -1 mint, CloseBurn, Close spend, and exact refund" $ do
            resolveClosedCheckpoint
                policy
                assetName
                [history]
                [closeRedeemers]
                [closeTransaction]
                `shouldBe` Right (Just closeTxId)

        it "does not mislabel ConvictBurn as controller Close" $ do
            resolveClosedCheckpoint
                policy
                assetName
                [history]
                [convictRedeemers]
                [closeTransaction]
                `shouldBe` Right Nothing

policy, assetName, closeTxId :: T.Text
policy = "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
assetName = "ababbe19b3edeb46f67a09a55a7a9b9cf5fbfff26e813adc82f860d12955399e"
closeTxId = "2222222222222222222222222222222222222222222222222222222222222222"

history :: ChainAssetHistory
history =
    ChainAssetHistory
        policy
        assetName
        [ ChainMintingTransaction closeTxId (-1) 20
        , ChainMintingTransaction
            "1111111111111111111111111111111111111111111111111111111111111111"
            1
            10
        ]

closeRedeemers :: ChainScriptRedeemers
closeRedeemers =
    ChainScriptRedeemers
        policy
        [ ChainScriptRedeemer
            "mint"
            closeTxId
            ( plutusDataJson $
                Constr
                    1
                    [ Constr
                        0
                        [B (BS.replicate 32 0x11), I 0]
                    ]
            )
        , ChainScriptRedeemer
            "spend"
            closeTxId
            (plutusDataJson $ Constr 0 [Constr 0 []])
        ]

convictRedeemers :: ChainScriptRedeemers
convictRedeemers =
    ChainScriptRedeemers
        policy
        [ ChainScriptRedeemer
            "mint"
            closeTxId
            ( plutusDataJson $
                Constr
                    2
                    [ Constr
                        0
                        [B (BS.replicate 32 0x11), I 0]
                    ]
            )
        , ChainScriptRedeemer
            "spend"
            closeTxId
            (plutusDataJson $ Constr 4 [])
        ]

closeTransaction :: ChainTransactionUtxos
closeTransaction =
    ChainTransactionUtxos
        closeTxId
        [ ChainTransactionPart
            "1111111111111111111111111111111111111111111111111111111111111111"
            0
            "addr_test1checkpoint"
            1_007_000_000
            [ChainAsset policy assetName 1]
        ]
        [ ChainTransactionPart
            closeTxId
            0
            "addr_test1refund"
            1_007_000_000
            []
        ]
