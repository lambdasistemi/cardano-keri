{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.RegistrationSpec (spec) where

import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.CheckpointIndex (renderCheckpointStatus)
import Cardano.KERI.Deployment.KEL (parseInceptionExport)
import Cardano.KERI.Deployment.Manifest (
    BlueprintInfo (..),
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    Reference (..),
    ScriptEntry (..),
    SourceInfo (..),
 )
import Cardano.KERI.Deployment.Registration (
    RegistrationFiles (..),
    RegistrationPlan (..),
    RegistrationRunnerConfig (..),
    mkRegistrationPlan,
    plutusDataJson,
    premintBuildArguments,
    registerBuildArguments,
    renderCardanoCliFailure,
 )
import Data.Aeson (object, (.=))
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text qualified as T
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "registration transaction plan" $ do
        it "encodes detailed Plutus script data" $
            plutusDataJson (Constr 0 [B "\xab\xcd", I 7])
                `shouldBe` object
                    [ "constructor" .= (0 :: Integer)
                    , "fields"
                        .= [ object ["bytes" .= ("abcd" :: String)]
                           , object ["int" .= (7 :: Integer)]
                           ]
                    ]

        it "keeps validator machine facts without opaque base64 dumps" $ do
            let rendered =
                    renderCardanoCliFailure
                        1
                        ( unlines
                            [ "Command failed: transaction build"
                            , "Error: The following scripts have execution failures:"
                            , "the script for policyId 0 failed with:"
                            , "Script hash: 581c0c16"
                            , "Script language: PlutusV3"
                            , "Protocol version: Version 11"
                            , "   ScriptInfo: MintingScript 0c16"
                            , "     TxInfo: enormous"
                            , "Script evaluation error: An error has occurred:"
                            , "The machine terminated because of an error"
                            , "Caused by: (error)"
                            , "Script base64 encoded arguments: opaque"
                            , "Script base64 encoded bytes: opaque"
                            ]
                        )
                        ""
            rendered `shouldContain` "ScriptInfo: MintingScript 0c16"
            rendered `shouldContain` "Caused by: (error)"
            rendered `shouldSatisfy` not . T.isInfixOf "opaque" . T.pack

        it "preserves non-validator cardano-cli failures verbatim" $
            renderCardanoCliFailure 2 "socket denied\n" ""
                `shouldContain` "stderr: socket denied"

        it "binds the genuine KLI export to the immutable V1 manifest" $ do
            fixture <-
                getDataFileName
                    "deployment-test/fixtures/kli-export-single.cesr"
            kel <- BS.readFile fixture >>= either fail pure . parseInceptionExport
            plan <-
                either
                    fail
                    pure
                    (mkRegistrationPlan sampleManifest 1_007_000_000 kel)
            planProofPolicy plan
                `shouldBe` "d767a22b85d0a1c1e2a987b970e990c22c423b2211e788252d28deca"
            planCheckpointPolicy plan
                `shouldBe` "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
            planCheckpointAddress plan
                `shouldBe` "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
            T.length (planProofName plan) `shouldBe` 64
            T.length (planCheckpointName plan) `shouldBe` 64
            planEscrowLovelace plan `shouldBe` 1_007_000_000
            premintBuildArguments
                runner
                plan
                files
                "funding#0"
                "collateral#1"
                False
                `shouldContain` [ "--mint-tx-in-reference"
                                , "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c#0"
                                , "--mint-plutus-script-v3"
                                , "--mint-reference-tx-in-redeemer-file"
                                , "premint.json"
                                , "--policy-id"
                                , "d767a22b85d0a1c1e2a987b970e990c22c423b2211e788252d28deca"
                                ]
            registerBuildArguments
                runner
                plan
                files
                "proof#0"
                "funding#0"
                "collateral#1"
                `shouldContain` [ "--withdrawal"
                                , T.unpack (planLifecycleRewardAddress plan) <> "+0"
                                , "--withdrawal-tx-in-reference"
                                , "c1ebe8b9a69160a04a9e490d4ab1149882f945774fba0cffac2dec7e6886b26f#0"
                                , "--withdrawal-plutus-script-v3"
                                , "--withdrawal-reference-tx-in-redeemer-file"
                                , "observer.json"
                                ]
            let active =
                    ChainAssetUtxo
                        "registertx"
                        0
                        (planCheckpointAddress plan)
                        1_007_000_000
                        [ ChainAsset
                            (planCheckpointPolicy plan)
                            (planCheckpointName plan)
                            1
                        ]
                        (Just $ planCheckpointDatum plan)
            renderCheckpointStatus
                sampleManifest
                (planAid plan)
                (planCheckpointName plan)
                []
                `shouldBe` Right ("state NOT REGISTERED aid " <> planAid plan)
            renderCheckpointStatus
                sampleManifest
                (planAid plan)
                (planCheckpointName plan)
                [active]
                `shouldSatisfy` either (const False) (T.isInfixOf "keys 1-of-1")
            renderCheckpointStatus
                sampleManifest
                (planAid plan)
                (planCheckpointName plan)
                [active, active]
                `shouldSatisfy` isLeft

sampleManifest :: Manifest
sampleManifest =
    Manifest
        { manifestSchemaVersion = "cardano-keri/m1-deployment-manifest/v1"
        , manifestNetwork = NetworkInfo "preprod" 1
        , manifestSource = SourceInfo "repository" "commit"
        , manifestBlueprint = BlueprintInfo "digest"
        , manifestParameters =
            DeploymentParameters
                0
                0
                1_000_000_000
                5_000_000
                10_000
        , manifestCheckpoint =
            CheckpointInfo
                "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"
                "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
        , manifestPublishedAt = "2026-07-28T14:37:05Z"
        , manifestScripts =
            [ entry
                "hash-proof"
                "d767a22b85d0a1c1e2a987b970e990c22c423b2211e788252d28deca"
                "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c"
            , entry
                "observer-lifecycle"
                "3d18237dc14be14284d775a5766016c7c4c432dedce287011701c6c7"
                "c1ebe8b9a69160a04a9e490d4ab1149882f945774fba0cffac2dec7e6886b26f"
            , entry
                "checkpoint-register"
                "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"
                "8a1a404f13b50ec0a266e1427f602916d830b62d757f3ac69976ccba0213c5d1"
            ]
        }
  where
    entry name hash txId =
        ScriptEntry name "blueprint" "role" hash 1 (Reference txId 0)

runner :: RegistrationRunnerConfig
runner =
    RegistrationRunnerConfig
        "cardano-cli"
        1
        "node.socket"
        "addr_test1payer"
        "payment.skey"
        "https://preprod.koios.rest/api/v1"
        Nothing
        600

files :: RegistrationFiles
files =
    RegistrationFiles
        "premint.json"
        "checkpoint.json"
        "burn.json"
        "observer.json"
        "certificate-redeemer.json"
        "certificate.json"
        "datum.json"
        "premint.body"
        "premint.signed"
        "register.body"
        "register.signed"
