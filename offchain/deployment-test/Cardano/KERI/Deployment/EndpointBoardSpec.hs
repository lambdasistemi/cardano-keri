{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.EndpointBoardSpec
Description : Genuine witness OOBI parsing and fail-closed board catalog tests
-}
module Cardano.KERI.Deployment.EndpointBoardSpec (spec) where

import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    EndpointRecord (..),
    parseEndpointRecord,
    renderBoardCatalog,
    resolveBoardCatalog,
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Control.Monad (forM_)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldContain,
    shouldSatisfy,
 )

spec :: Spec
spec = do
    describe "signed KERI endpoint record" $ do
        it "extracts and verifies the genuine witness-1 /loc/scheme reply" $ do
            record <- loadRecord
            endpointAid record
                `shouldBe` "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
            endpointScheme record `shouldBe` "https"
            endpointUrl record
                `shouldBe` "https://witness-1.preprod.plutimus.com/"
            BS.length (endpointWitnessKey record) `shouldBe` 32
            BS.length (endpointSignature record) `shouldBe` 64
            BS.take 1 (endpointEventBytes record) `shouldBe` "{"

        it "verifies every genuine preprod witness OOBI"
            $ forM_
                [
                    ( "witness-1-oobi.cesr"
                    , "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
                    , "https://witness-1.preprod.plutimus.com/"
                    )
                ,
                    ( "witness-2-oobi.cesr"
                    , "BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B"
                    , "https://witness-2.preprod.plutimus.com/"
                    )
                ,
                    ( "witness-3-oobi.cesr"
                    , "BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4"
                    , "https://witness-3.preprod.plutimus.com/"
                    )
                ]
            $ \(name, aid, url) -> do
                record <-
                    loadFixtureNamed name
                        >>= expectRight . parseEndpointRecord
                endpointAid record `shouldBe` aid
                endpointUrl record `shouldBe` url

        it "rejects a changed endpoint when the CESR signature is retained" $ do
            bytes <- loadFixture
            parseEndpointRecord
                (replaceOnce "witness-1" "witness-X" bytes)
                `shouldSatisfy` isLeftContaining "SAID"

        it "rejects an unsupported route instead of accepting another reply" $ do
            bytes <- loadFixture
            parseEndpointRecord
                (replaceOnce "/loc/scheme" "/bad/scheme" bytes)
                `shouldSatisfy` isLeftContaining "/loc/scheme"

        it "rejects malformed endpoint attachment material" $ do
            bytes <- loadFixture
            parseEndpointRecord
                (replaceOnce "-CABBCZT" "-CABCCZT" bytes)
                `shouldSatisfy` isLeftContaining "signer"

    describe "fail-closed endpoint board catalog" $ do
        it "decodes an authentic marker and renders its source output" $ do
            record <- loadRecord
            entries <-
                expectRight $
                    resolveBoardCatalog policy markerAddress [validUtxo record]
            entries `shouldBe` [expectedEntry record 0]
            T.unpack (renderBoardCatalog entries)
                `shouldContain` T.unpack (endpointAid record)
            T.unpack (renderBoardCatalog entries)
                `shouldContain` (T.unpack txId <> "#0")

        it "surfaces every valid unspent duplicate in output-reference order" $ do
            record <- loadRecord
            let second =
                    (validUtxo record)
                        { chainAssetTxId = T.replicate 64 "2"
                        , chainAssetIndex = 3
                        }
            resolveBoardCatalog policy markerAddress [second, validUtxo record]
                `shouldBe` Right
                    [ expectedEntry record 0
                    , (expectedEntry record 3)
                        { boardTxId = T.replicate 64 "2"
                        }
                    ]

        it "rejects the whole catalog and names a wrong-address output" $ do
            record <- loadRecord
            resolveBoardCatalog
                policy
                markerAddress
                [(validUtxo record){chainAssetAddress = "addr_test1wrong"}]
                `shouldSatisfy` isLeftContaining (T.unpack txId <> "#0")

        it "rejects wrong marker quantity, policy, and asset-name binding" $ do
            record <- loadRecord
            let marker = onlyMarker record
                cases =
                    [ [marker{chainAssetQuantity = 2}]
                    , [marker{chainAssetPolicy = "wrong"}]
                    , [marker{chainAssetName = T.replicate 64 "0"}]
                    ]
                resolve assets =
                    resolveBoardCatalog
                        policy
                        markerAddress
                        [(validUtxo record){chainAssetList = assets}]
            map resolve cases
                `shouldSatisfy` all
                    (isLeftContaining $ T.unpack txId <> "#0")

        it "rejects malformed datum and retained-signature event tampering" $ do
            record <- loadRecord
            let malformed =
                    (validUtxo record)
                        { chainAssetInlineDatum =
                            Just (plutusDataJson $ Constr 0 [B "short"])
                        }
                forged =
                    (validUtxo record)
                        { chainAssetInlineDatum =
                            Just $
                                plutusDataJson $
                                    Constr
                                        0
                                        [ B (endpointWitnessKey record)
                                        , B $
                                            replaceOnce
                                                "witness-1"
                                                "witness-X"
                                                (endpointEventBytes record)
                                        , B (endpointSignature record)
                                        , B owner
                                        ]
                        }
            resolveBoardCatalog policy markerAddress [malformed]
                `shouldSatisfy` isLeftContaining (T.unpack txId <> "#0")
            resolveBoardCatalog policy markerAddress [forged]
                `shouldSatisfy` isLeftContaining (T.unpack txId <> "#0")

        it "rejects a witness-supplied non-KERI version before trusting it" $ do
            record <- loadRecord
            let versionDrift =
                    (validUtxo record)
                        { chainAssetInlineDatum =
                            Just $
                                plutusDataJson $
                                    Constr
                                        0
                                        [ B (endpointWitnessKey record)
                                        , B $
                                            replaceOnce
                                                "KERI10JSON"
                                                "KERI11JSON"
                                                (endpointEventBytes record)
                                        , B (endpointSignature record)
                                        , B owner
                                        ]
                        }
            resolveBoardCatalog policy markerAddress [versionDrift]
                `shouldSatisfy` isLeftContaining "version"

policy, markerAddress, txId :: Text
policy = "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"
markerAddress = "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"
txId = T.replicate 64 "1"

owner :: ByteString
owner = BS.replicate 28 0x33

validUtxo :: EndpointRecord -> ChainAssetUtxo
validUtxo record =
    ChainAssetUtxo
        { chainAssetTxId = txId
        , chainAssetIndex = 0
        , chainAssetAddress = markerAddress
        , chainAssetLovelace = 2_000_000
        , chainAssetList = [onlyMarker record]
        , chainAssetInlineDatum =
            Just $
                plutusDataJson $
                    Constr
                        0
                        [ B (endpointWitnessKey record)
                        , B (endpointEventBytes record)
                        , B (endpointSignature record)
                        , B owner
                        ]
        }

onlyMarker :: EndpointRecord -> ChainAsset
onlyMarker record =
    ChainAsset
        { chainAssetPolicy = policy
        , chainAssetName =
            TE.decodeUtf8 (convertToBase Base16 $ endpointWitnessKey record)
        , chainAssetQuantity = 1
        }

expectedEntry :: EndpointRecord -> Int -> BoardEntry
expectedEntry record index =
    BoardEntry
        { boardAid = endpointAid record
        , boardScheme = endpointScheme record
        , boardUrl = endpointUrl record
        , boardTxId = txId
        , boardIndex = index
        , boardLovelace = 2_000_000
        , boardOwnerKeyHash = owner
        }

loadRecord :: IO EndpointRecord
loadRecord = loadFixture >>= expectRight . parseEndpointRecord

loadFixture :: IO ByteString
loadFixture = loadFixtureNamed "witness-1-oobi.cesr"

loadFixtureNamed :: FilePath -> IO ByteString
loadFixtureNamed name = do
    path <-
        getDataFileName
            ("deployment-test/fixtures/" <> name)
    BS.readFile path

expectRight :: Either String a -> IO a
expectRight = \case
    Left err -> expectationFailure err >> fail err
    Right value -> pure value

replaceOnce :: ByteString -> ByteString -> ByteString -> ByteString
replaceOnce needle replacement haystack =
    case BS.breakSubstring needle haystack of
        (before, after)
            | BS.null after -> haystack
            | otherwise ->
                before
                    <> replacement
                    <> BS.drop (BS.length needle) after

isLeftContaining :: String -> Either String a -> Bool
isLeftContaining needle = \case
    Left err -> T.pack needle `T.isInfixOf` T.pack err
    Right _ -> False
