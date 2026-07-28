{-# LANGUAGE OverloadedStrings #-}

module Cardano.KERI.Deployment.ChainIndexSpec (spec) where

import Cardano.KERI.Deployment.ChainIndex (
    KoiosToken (..),
    authorizeKoiosRequest,
 )
import Network.HTTP.Simple (getRequestHeader, parseRequest)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec =
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
