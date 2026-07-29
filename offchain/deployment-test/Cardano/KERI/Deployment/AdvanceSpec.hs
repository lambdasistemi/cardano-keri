{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.AdvanceSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
 )
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.Advance (
    AdvancePackage (..),
    AdvanceSigningFiles (..),
    advanceSigningMetadata,
    attachControllerSignatures,
    mkAdvancePackage,
    writeAdvanceSigningPackage,
 )
import Cardano.KERI.Deployment.AdvanceTransaction (
    AdvanceFiles (..),
    AdvancePlan (..),
    AdvanceRunnerConfig (..),
    advanceBuildArguments,
    mkAdvancePlan,
    observerRegistrationBuildArguments,
 )
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    checkpointAssetName,
    resolveActiveCheckpoint,
 )
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    RotationExport (..),
    parseInceptionExport,
    parseRotationExport,
 )
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
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Data.Aeson (eitherDecodeFileStrict')
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8')
import Paths_cardano_keri (getDataFileName)
import System.IO.Temp (withSystemTempDirectory)
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
    describe "advance signing package" $ do
        it "binds live ACTIVE outref and rotation state into binary canonical CBOR" $ do
            (inception, rotation) <- loadJourney
            assetName <- either fail pure (checkpointAssetName $ rotationAid rotation)
            let activeUtxo =
                    ChainAssetUtxo
                        (T.replicate 64 "1")
                        2
                        checkpointAddress
                        1_007_000_000
                        [ ChainAsset
                            checkpointPolicy
                            assetName
                            1
                        ]
                        ( Just $
                            plutusDataJson $
                                asPlcData $
                                    V1 $
                                        inceptionDatum inception
                        )
            active <-
                either
                    fail
                    pure
                    ( resolveActiveCheckpoint
                        sampleManifest
                        (rotationAid rotation)
                        assetName
                        [activeUtxo]
                    )
            package <-
                either fail pure (mkAdvancePackage sampleManifest active rotation)
            advanceAid package `shouldBe` rotationAid rotation
            advanceSpentReference package
                `shouldBe` T.replicate 64 "1" <> "#2"
            advanceSuccessor package `shouldBe` rotationDatum rotation
            aeCtrlSigs (advanceEvidence package) `shouldBe` []
            T.length (advancePackageSha256 package) `shouldBe` 64
            decodeUtf8' (advanceSigningPreimage package)
                `shouldSatisfy` isLeft
            withSystemTempDirectory "ckeri-advance-package" $ \directory -> do
                files <- writeAdvanceSigningPackage directory package
                BS.readFile (advancePreimageFile files)
                    >>= (`shouldBe` advanceSigningPreimage package)
                eitherDecodeFileStrict' (advanceMetadataFile files)
                    >>= either fail pure
                    >>= (`shouldBe` advanceSigningMetadata package)

        it "does not substitute KERI rot.raw signatures for AdvanceMessage signatures" $ do
            (inception, rotation) <- loadJourney
            assetName <- either fail pure (checkpointAssetName $ rotationAid rotation)
            let activeUtxo =
                    ChainAssetUtxo
                        (T.replicate 64 "1")
                        2
                        checkpointAddress
                        1_007_000_000
                        [ChainAsset checkpointPolicy assetName 1]
                        ( Just $
                            plutusDataJson $
                                asPlcData $
                                    V1 $
                                        inceptionDatum inception
                        )
            active <-
                either fail pure $
                    resolveActiveCheckpoint
                        sampleManifest
                        (rotationAid rotation)
                        assetName
                        [activeUtxo]
            package <-
                either fail pure (mkAdvancePackage sampleManifest active rotation)
            attachControllerSignatures
                (rotationEventSignatures rotation)
                package
                `shouldSatisfy` isLeft

        it "builds the thin observer transaction while preserving the complete state value" $ do
            (inception, rotation) <- loadJourney
            assetName <- either fail pure (checkpointAssetName $ rotationAid rotation)
            let activeUtxo =
                    ChainAssetUtxo
                        (T.replicate 64 "1")
                        2
                        checkpointAddress
                        1_007_000_000
                        [ChainAsset checkpointPolicy assetName 1]
                        ( Just $
                            plutusDataJson $
                                asPlcData $
                                    V1 $
                                        inceptionDatum inception
                        )
            active <-
                either fail pure $
                    resolveActiveCheckpoint
                        sampleManifest
                        (rotationAid rotation)
                        assetName
                        [activeUtxo]
            package <-
                either fail pure (mkAdvancePackage sampleManifest active rotation)
            plan <- either fail pure (mkAdvancePlan sampleManifest package)
            planSpentReference plan `shouldBe` T.replicate 64 "1" <> "#2"
            planCheckpointReference plan
                `shouldBe` "8a1a404f13b50ec0a266e1427f602916d830b62d757f3ac69976ccba0213c5d1#0"
            planAdvanceReference plan
                `shouldBe` "aaeb5ebe4e9783dc614b8a48634ef7fd9bb517cc0fdc3a4d701a26bd94679734#0"
            planStateOutput plan
                `shouldBe` checkpointAddress
                    <> "+1007000000 + 1 "
                    <> checkpointPolicy
                    <> "."
                    <> assetName
            let arguments =
                    advanceBuildArguments
                        sampleRunner
                        plan
                        sampleAdvanceFiles
                        "funding#0"
                        "collateral#1"
            arguments
                `shouldContain` [ "--withdrawal"
                                , T.unpack (planAdvanceRewardAddress plan) <> "+0"
                                , "--withdrawal-tx-in-reference"
                                , T.unpack (planAdvanceReference plan)
                                , "--withdrawal-plutus-script-v3"
                                ]
            arguments
                `shouldContain` [ "--tx-in"
                                , T.unpack (planSpentReference plan)
                                , "--spending-tx-in-reference"
                                , T.unpack (planCheckpointReference plan)
                                , "--spending-plutus-script-v3"
                                ]
            arguments `shouldNotContain` ["--mint"]
            observerRegistrationBuildArguments
                sampleRunner
                plan
                sampleAdvanceFiles
                "funding#0"
                "collateral#1"
                `shouldContain` [ "--certificate-file"
                                , filesObserverCertificate sampleAdvanceFiles
                                , "--certificate-tx-in-reference"
                                , T.unpack (planAdvanceReference plan)
                                , "--certificate-plutus-script-v3"
                                , "--certificate-reference-tx-in-redeemer-file"
                                , filesObserverCertificateRedeemer sampleAdvanceFiles
                                ]

loadJourney :: IO (InceptionExport, RotationExport)
loadJourney = do
    path <-
        getDataFileName
            "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
    bytes <- BS.readFile path
    (,)
        <$> either fail pure (parseInceptionExport bytes)
        <*> either fail pure (parseRotationExport bytes)

checkpointAddress :: T.Text
checkpointAddress =
    "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"

checkpointPolicy :: T.Text
checkpointPolicy =
    "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"

sampleRunner :: AdvanceRunnerConfig
sampleRunner =
    AdvanceRunnerConfig
        { runnerCardanoCli = "cardano-cli"
        , runnerNetworkMagic = 1
        , runnerNodeSocket = "node.socket"
        , runnerFundingAddress = "addr_test1funding"
        , runnerSigningKeyFile = "payment.skey"
        , runnerKoiosUrl = "https://preprod.koios.rest/api/v1"
        , runnerKoiosToken = Nothing
        , runnerTimeoutSeconds = 600
        }

sampleAdvanceFiles :: AdvanceFiles
sampleAdvanceFiles =
    AdvanceFiles
        { filesSpendRedeemer = "spend.json"
        , filesObserverRedeemer = "observer.json"
        , filesObserverCertificateRedeemer = "observer-certificate.json"
        , filesObserverCertificate = "observer.cert"
        , filesObserverRegistrationBody = "observer-registration.body"
        , filesObserverRegistrationSigned = "observer-registration.signed"
        , filesSuccessorDatum = "successor.json"
        , filesBody = "advance.body"
        , filesSigned = "advance.signed"
        }

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
            CheckpointInfo checkpointAddress checkpointPolicy
        , manifestPublishedAt = "2026-07-28T14:37:05Z"
        , manifestScripts =
            [ ScriptEntry
                "observer-advance"
                "checkpoint_observer.observer_advance.withdraw"
                "withdrawal"
                "50dbbef1c38646d29a1e333337fc5244fe2da3149bf9d5545e5b92c6"
                1
                ( Reference
                    "aaeb5ebe4e9783dc614b8a48634ef7fd9bb517cc0fdc3a4d701a26bd94679734"
                    0
                )
            , ScriptEntry
                "checkpoint-register"
                "checkpoint_register.checkpoint_register.mint"
                "mint-spend"
                checkpointPolicy
                1
                ( Reference
                    "8a1a404f13b50ec0a266e1427f602916d830b62d757f3ac69976ccba0213c5d1"
                    0
                )
            ]
        }
