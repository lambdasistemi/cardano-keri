{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.EndpointBoardTransactionSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    FullAddress (..),
 )
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    EndpointRecord (..),
    parseEndpointRecord,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
 )
import Cardano.KERI.Deployment.EndpointBoardTransaction (
    BoardFiles (..),
    BoardPostPlan (..),
    BoardRetirePlan (..),
    BoardRunnerConfig (..),
    BoardUpdatePlan (..),
    boardPostBuildArguments,
    boardRetireBuildArguments,
    boardUpdateBuildArguments,
    mkBoardPostPlan,
    mkBoardRetirePlan,
    mkBoardUpdatePlan,
    selectBoardEntry,
 )
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    NetworkInfo (..),
    Reference (..),
    SourceInfo (..),
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldNotContain,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "endpoint-board transaction plans" $ do
        it "posts exactly one authenticated marker owned by the payment key" $ do
            record <- loadRecord "witness-1-oobi.cesr"
            plan <-
                either fail pure $
                    mkBoardPostPlan sampleManifest fundingAddress 2_000_000 record
            boardPostPolicy plan `shouldBe` policy
            boardPostAddress plan `shouldBe` markerAddress
            boardPostAssetName plan `shouldBe` witnessHex record
            boardPostOutput plan
                `shouldBe` markerAddress
                    <> "+2000000 + 1 "
                    <> policy
                    <> "."
                    <> witnessHex record
            boardPostDatum plan
                `shouldBe` plutusDataJson
                    ( Constr
                        0
                        [ B (endpointWitnessKey record)
                        , B (endpointEventBytes record)
                        , B (endpointSignature record)
                        , B owner
                        ]
                    )
            boardPostMintRedeemer plan
                `shouldBe` plutusDataJson (Constr 0 [])
            let arguments =
                    boardPostBuildArguments
                        sampleRunner
                        plan
                        sampleFiles
                        "funding#0"
                        "collateral#1"
            arguments
                `shouldContain` [ "--tx-out"
                                , T.unpack (boardPostOutput plan)
                                , "--tx-out-inline-datum-file"
                                , boardFilesDatum sampleFiles
                                ]
            arguments
                `shouldContain` [ "--mint"
                                , "1 " <> T.unpack policy <> "." <> T.unpack (witnessHex record)
                                , "--mint-tx-in-reference"
                                , referenceText
                                , "--mint-plutus-script-v3"
                                , "--mint-reference-tx-in-redeemer-file"
                                , boardFilesMintRedeemer sampleFiles
                                , "--policy-id"
                                , T.unpack policy
                                ]

        it "updates only an explicitly resolved owned output without minting" $ do
            oldRecord <- loadRecord "witness-1-oobi.cesr"
            newRecord <- loadRecord "witness-1-oobi.cesr"
            let entry = sampleEntry oldRecord 0
            selectBoardEntry Nothing (endpointWitnessKey oldRecord) [entry]
                `shouldBe` Right entry
            selectBoardEntry
                Nothing
                (endpointWitnessKey oldRecord)
                [entry, entry{boardIndex = 1}]
                `shouldSatisfy` isLeft
            selectBoardEntry
                (Just $ txId <> "#1")
                (endpointWitnessKey oldRecord)
                [entry, entry{boardIndex = 1}]
                `shouldBe` Right entry{boardIndex = 1}
            plan <-
                either fail pure $
                    mkBoardUpdatePlan
                        sampleManifest
                        fundingAddress
                        entry
                        newRecord
            boardUpdateSpentReference plan `shouldBe` txId <> "#0"
            boardUpdateOutput plan
                `shouldBe` markerAddress
                    <> "+2000000 + 1 "
                    <> policy
                    <> "."
                    <> witnessHex oldRecord
            boardUpdateSpendRedeemer plan
                `shouldBe` plutusDataJson (Constr 0 [])
            let arguments =
                    boardUpdateBuildArguments
                        sampleRunner
                        plan
                        sampleFiles
                        "funding#0"
                        "collateral#1"
            arguments
                `shouldContain` [ "--tx-in"
                                , T.unpack (boardUpdateSpentReference plan)
                                , "--spending-tx-in-reference"
                                , referenceText
                                ]
            arguments
                `shouldContain` [ "--required-signer-hash"
                                , T.unpack ownerHex
                                ]
            arguments `shouldNotContain` ["--mint"]

        it "retires by burning the marker and refunding the exact deposit" $ do
            record <- loadRecord "witness-1-oobi.cesr"
            plan <-
                either fail pure $
                    mkBoardRetirePlan
                        sampleManifest
                        fundingAddress
                        refundAddress
                        (sampleEntry record 0)
            boardRetireSpentReference plan `shouldBe` txId <> "#0"
            boardRetireRefundOutput plan
                `shouldBe` refundAddress <> "+2000000"
            boardRetireSpendRedeemer plan
                `shouldBe` plutusDataJson
                    (Constr 1 [asPlcData refundFullAddress])
            boardRetireMintRedeemer plan
                `shouldBe` plutusDataJson (Constr 1 [])
            let arguments =
                    boardRetireBuildArguments
                        sampleRunner
                        plan
                        sampleFiles
                        "funding#0"
                        "collateral#1"
            arguments
                `shouldContain` [ "--tx-out"
                                , T.unpack (boardRetireRefundOutput plan)
                                ]
            arguments
                `shouldContain` [ "--mint"
                                , "-1 " <> T.unpack policy <> "." <> T.unpack (witnessHex record)
                                ]
            arguments
                `shouldContain` [ "--required-signer-hash"
                                , T.unpack ownerHex
                                ]
            arguments `shouldNotContain` ["--tx-out-inline-datum-file"]

        it "rejects a wrong owner, wrong witness update, and non-positive deposit" $ do
            first <- loadRecord "witness-1-oobi.cesr"
            second <- loadRecord "witness-2-oobi.cesr"
            let entry = sampleEntry first 0
            mkBoardPostPlan sampleManifest fundingAddress 0 first
                `shouldSatisfy` isLeft
            mkBoardUpdatePlan sampleManifest fundingAddress entry second
                `shouldSatisfy` isLeft
            mkBoardRetirePlan
                sampleManifest
                otherOwnerAddress
                refundAddress
                entry
                `shouldSatisfy` isLeft

loadRecord :: FilePath -> IO EndpointRecord
loadRecord name = do
    path <- getDataFileName ("deployment-test/fixtures/" <> name)
    BS.readFile path >>= either fail pure . parseEndpointRecord

sampleEntry :: EndpointRecord -> Int -> BoardEntry
sampleEntry record index =
    BoardEntry
        { boardWitnessKey = endpointWitnessKey record
        , boardAid = endpointAid record
        , boardScheme = endpointScheme record
        , boardUrl = endpointUrl record
        , boardTxId = txId
        , boardIndex = index
        , boardLovelace = 2_000_000
        , boardOwnerKeyHash = owner
        }

witnessHex :: EndpointRecord -> Text
witnessHex =
    TE.decodeUtf8 . convertToBase Base16 . endpointWitnessKey

policy, markerAddress, txId, ownerHex :: Text
policy = "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"
markerAddress = "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"
txId = T.replicate 64 "1"
ownerHex = TE.decodeUtf8 (convertToBase Base16 owner)

owner :: BS.ByteString
owner = BS.pack [0x88, 0x83, 0xcd, 0xb7, 0x14, 0x31, 0x3b, 0x7a, 0xc3, 0x82, 0x46, 0xc1, 0xdd, 0x8d, 0x6f, 0xc3, 0xf8, 0x04, 0xf1, 0x53, 0xc1, 0xf1, 0xc4, 0xca, 0x38, 0x56, 0x1b, 0xa0]

fundingAddress, otherOwnerAddress, refundAddress :: Text
fundingAddress =
    "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d"
otherOwnerAddress =
    "addr_test1vpchzut3w9chzut3w9chzut3w9chzut3w9chzut3w9chzugnd3d2k"
refundAddress =
    fundingAddress

refundFullAddress :: FullAddress
refundFullAddress =
    FullAddress
        { faPaymentCredential =
            VerificationKeyCredential owner
        , faStakeCredential = Nothing
        }

sampleManifest :: EndpointBoardManifest
sampleManifest =
    EndpointBoardManifest
        { endpointBoardManifestSchemaVersion =
            "cardano-keri/m1-endpoint-board-manifest/v1"
        , endpointBoardManifestNetwork = NetworkInfo "preprod" 1
        , endpointBoardManifestSource =
            SourceInfo "https://github.com/lambdasistemi/cardano-keri" (T.replicate 40 "a")
        , endpointBoardManifestBlueprint = BlueprintInfo (T.replicate 64 "b")
        , endpointBoardManifestInfo =
            EndpointBoardInfo
                { endpointBoardPolicyId = policy
                , endpointBoardAddress = markerAddress
                , endpointBoardProgramBytes = 1
                , endpointBoardReference =
                    Reference (T.replicate 64 "c") 0
                }
        , endpointBoardManifestPublishedAt = "2026-07-29T11:00:00Z"
        }

referenceText :: String
referenceText = T.unpack (T.replicate 64 "c" <> "#0")

sampleRunner :: BoardRunnerConfig
sampleRunner =
    BoardRunnerConfig
        { boardRunnerCardanoCli = "cardano-cli"
        , boardRunnerNetworkMagic = 1
        , boardRunnerNodeSocket = "node.socket"
        , boardRunnerFundingAddress = fundingAddress
        , boardRunnerChangeAddress = fundingAddress
        , boardRunnerSigningKeyFile = "payment.skey"
        , boardRunnerKoiosUrl = "https://preprod.koios.rest/api/v1"
        , boardRunnerKoiosToken = Nothing
        , boardRunnerTimeoutSeconds = 600
        }

sampleFiles :: BoardFiles
sampleFiles =
    BoardFiles
        { boardFilesDatum = "datum.json"
        , boardFilesSpendRedeemer = "spend.json"
        , boardFilesMintRedeemer = "mint.json"
        , boardFilesBody = "board.body"
        , boardFilesSigned = "board.signed"
        }
