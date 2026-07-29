{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.KERI.Deployment.CloseSpec (spec) where

import Cardano.Crypto.DSIGN.Class (
    SignKeyDSIGN,
    VerKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (
    Ed25519DSIGN,
 )
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    CloseEvidence (..),
    FullAddress (..),
    closeSpendRedeemerData,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    checkpointAssetName,
    renderResolvedCheckpointStatus,
    resolveActiveCheckpoint,
 )
import Cardano.KERI.Deployment.Close (
    ClosePackage (..),
    CloseSigningFiles (..),
    attachCloseControllerSignatures,
    closeSigningMetadata,
    decodeRefundAddress,
    mkClosePackage,
    writeCloseSigningPackage,
 )
import Cardano.KERI.Deployment.CloseTransaction (
    CloseFiles (..),
    ClosePlan (..),
    CloseRunnerConfig (..),
    closeBuildArguments,
    mkClosePlan,
 )
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    parseInceptionExport,
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
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString qualified as BS
import Data.Either (isLeft, isRight)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data (Data (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (
    fileMode,
    getFileStatus,
    groupReadMode,
    intersectFileModes,
    otherReadMode,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldNotBe,
    shouldNotContain,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "close signing package" $ do
        it "decodes the complete preprod enterprise refund address" $ do
            paymentHash <-
                either
                    (fail . show)
                    pure
                    ( convertFromBase Base16 $
                        TE.encodeUtf8
                            "8883cdb714313b7ac38246c1dd8d6fc3f804f153c1f1c4ca38561ba0"
                    )
            decodeRefundAddress refundAddress
                `shouldBe` Right
                    FullAddress
                        { faPaymentCredential =
                            VerificationKeyCredential paymentHash
                        , faStakeCredential = Nothing
                        }
            decodeRefundAddress checkpointAddress `shouldSatisfy` isRight
            decodeRefundAddress "stake_test1uqfu..." `shouldSatisfy` isLeft

        it "binds the live ACTIVE outref and full refund target into binary CBOR" $ do
            active <- sampleActive
            package <-
                either
                    fail
                    pure
                    (mkClosePackage sampleManifest active refundAddress)
            mkClosePackage sampleManifest active checkpointAddress
                `shouldSatisfy` isLeft
            closeAid package `shouldBe` activeCheckpointAid active
            closeSpentReference package
                `shouldBe` T.replicate 64 "1" <> "#2"
            closeRefundAddress package `shouldBe` refundAddress
            closeRefundLovelace package `shouldBe` 1_007_000_000
            ceCtrlSigs (closeEvidence package) `shouldBe` []
            T.length (closePackageSha256 package) `shouldBe` 64
            BS.null (closeSigningPreimage package) `shouldBe` False

            redirected <-
                either
                    fail
                    pure
                    (mkClosePackage sampleManifest active otherRefundAddress)
            closeSigningPreimage redirected
                `shouldNotBe` closeSigningPreimage package

            withSystemTempDirectory "ckeri-close-package" $ \directory -> do
                files <- writeCloseSigningPackage directory package
                BS.readFile (closePreimageFile files)
                    >>= (`shouldBe` closeSigningPreimage package)
                eitherDecodeFileStrict' (closeMetadataFile files)
                    >>= either fail pure
                    >>= (`shouldBe` closeSigningMetadata package)
                mapM_
                    ( \output -> do
                        mode <- fileMode <$> getFileStatus output
                        mode `intersectFileModes` groupReadMode
                            `shouldBe` groupReadMode
                        mode `intersectFileModes` otherReadMode
                            `shouldBe` otherReadMode
                    )
                    [closePreimageFile files, closeMetadataFile files]

        it "prefers a proved latest Close over a stale ACTIVE index row" $ do
            active <- sampleActive
            let stale =
                    ChainAssetUtxo
                        (activeCheckpointTxId active)
                        (activeCheckpointIndex active)
                        (activeCheckpointAddress active)
                        (activeCheckpointLovelace active)
                        (activeCheckpointAssets active)
                        (Just $ plutusDataJson $ asPlcData $ V1 $ activeCheckpointDatum active)
                closeTxId = T.replicate 64 "2"
            renderResolvedCheckpointStatus
                sampleManifest
                (activeCheckpointAid active)
                (activeCheckpointAssetName active)
                [stale]
                (Just closeTxId)
                `shouldBe` Right
                    ( "state NOT REGISTERED (closed at "
                        <> closeTxId
                        <> ") aid "
                        <> activeCheckpointAid active
                    )

        it "accepts only signatures from the live current controller set" $ do
            active <- sampleActive
            package <-
                either fail pure $
                    mkClosePackage sampleManifest active refundAddress
            let signature =
                    rawSerialiseSigDSIGN $
                        signDSIGN
                            ()
                            (closeSigningPreimage package)
                            controllerSigningKey
                outsider =
                    rawSerialiseSigDSIGN $
                        signDSIGN
                            ()
                            (closeSigningPreimage package)
                            outsiderSigningKey
            attachCloseControllerSignatures [(0, signature)] package
                `shouldSatisfy` either (const False) (const True)
            attachCloseControllerSignatures [(0, outsider)] package
                `shouldSatisfy` isLeft

        it "spends and burns the checkpoint while refunding the complete escrow" $ do
            active <- sampleActive
            unsigned <-
                either fail pure $
                    mkClosePackage sampleManifest active refundAddress
            let signature =
                    rawSerialiseSigDSIGN $
                        signDSIGN
                            ()
                            (closeSigningPreimage unsigned)
                            controllerSigningKey
            package <-
                either fail pure $
                    attachCloseControllerSignatures [(0, signature)] unsigned
            plan <- either fail pure (mkClosePlan sampleManifest package)
            closePlanSpentReference plan
                `shouldBe` T.replicate 64 "1" <> "#2"
            closePlanCheckpointReference plan
                `shouldBe` "8a1a404f13b50ec0a266e1427f602916d830b62d757f3ac69976ccba0213c5d1#0"
            closePlanRefundOutput plan
                `shouldBe` refundAddress <> "+1007000000"
            closePlanSpendRedeemer plan
                `shouldBe` plutusDataJson
                    (closeSpendRedeemerData $ closeEvidence package)
            closePlanMintRedeemer plan
                `shouldBe` plutusDataJson
                    ( Constr
                        1
                        [ Constr
                            0
                            [B (BS.replicate 32 0x11), I 2]
                        ]
                    )
            let arguments =
                    closeBuildArguments
                        sampleCloseRunner
                        plan
                        sampleCloseFiles
                        "funding#0"
                        "collateral#1"
            arguments
                `shouldContain` [ "--tx-in"
                                , T.unpack (closePlanSpentReference plan)
                                , "--spending-tx-in-reference"
                                , T.unpack (closePlanCheckpointReference plan)
                                , "--spending-plutus-script-v3"
                                , "--spending-reference-tx-in-inline-datum-present"
                                , "--spending-reference-tx-in-redeemer-file"
                                , closeFilesSpendRedeemer sampleCloseFiles
                                ]
            arguments
                `shouldContain` [ "--mint"
                                , "-1 "
                                    <> T.unpack checkpointPolicy
                                    <> "."
                                    <> T.unpack (closePlanAssetName plan)
                                , "--mint-tx-in-reference"
                                , T.unpack (closePlanCheckpointReference plan)
                                , "--mint-plutus-script-v3"
                                , "--mint-reference-tx-in-redeemer-file"
                                , closeFilesMintRedeemer sampleCloseFiles
                                , "--policy-id"
                                , T.unpack checkpointPolicy
                                ]
            arguments
                `shouldContain` [ "--tx-out"
                                , T.unpack (closePlanRefundOutput plan)
                                , "--change-address"
                                , T.unpack otherRefundAddress
                                ]
            arguments `shouldNotContain` ["--tx-out-inline-datum-file"]

sampleActive :: IO ActiveCheckpoint
sampleActive = do
    path <-
        getDataFileName "deployment-test/fixtures/kli-export-single.cesr"
    bytes <- BS.readFile path
    inception <- either fail pure (parseInceptionExport bytes)
    assetName <-
        either fail pure (checkpointAssetName $ inceptionAid inception)
    let datum =
            (inceptionDatum inception)
                { cdCurKeys =
                    [rawSerialiseVerKeyDSIGN $ deriveVerKey controllerSigningKey]
                , cdCurThreshold = Unweighted 1
                }
        utxo =
            ChainAssetUtxo
                (T.replicate 64 "1")
                2
                checkpointAddress
                1_007_000_000
                [ChainAsset checkpointPolicy assetName 1]
                (Just $ plutusDataJson $ asPlcData $ V1 datum)
    either
        fail
        pure
        ( resolveActiveCheckpoint
            sampleManifest
            (inceptionAid inception)
            assetName
            [utxo]
        )

deriveVerKey ::
    SignKeyDSIGN Ed25519DSIGN ->
    VerKeyDSIGN Ed25519DSIGN
deriveVerKey = deriveVerKeyDSIGN

controllerSigningKey :: SignKeyDSIGN Ed25519DSIGN
controllerSigningKey = genKeyDSIGN $ mkSeedFromBytes $ BS.replicate 32 0x41

outsiderSigningKey :: SignKeyDSIGN Ed25519DSIGN
outsiderSigningKey = genKeyDSIGN $ mkSeedFromBytes $ BS.replicate 32 0x42

checkpointAddress :: T.Text
checkpointAddress =
    "addr_test1wqxpdsfvar9xppev4h25t5fg9uraeya46g4pxnjyy564wdqhr6822"

refundAddress :: T.Text
refundAddress =
    "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d"

otherRefundAddress :: T.Text
otherRefundAddress =
    "addr_test1vpchzut3w9chzut3w9chzut3w9chzut3w9chzut3w9chzugnd3d2k"

sampleCloseRunner :: CloseRunnerConfig
sampleCloseRunner =
    CloseRunnerConfig
        { closeRunnerCardanoCli = "cardano-cli"
        , closeRunnerNetworkMagic = 1
        , closeRunnerNodeSocket = "node.socket"
        , closeRunnerFundingAddress = refundAddress
        , closeRunnerChangeAddress = otherRefundAddress
        , closeRunnerSigningKeyFile = "payment.skey"
        , closeRunnerKoiosUrl = "https://preprod.koios.rest/api/v1"
        , closeRunnerKoiosToken = Nothing
        , closeRunnerTimeoutSeconds = 600
        }

sampleCloseFiles :: CloseFiles
sampleCloseFiles =
    CloseFiles
        { closeFilesSpendRedeemer = "spend.json"
        , closeFilesMintRedeemer = "mint.json"
        , closeFilesBody = "close.body"
        , closeFilesSigned = "close.signed"
        }

checkpointPolicy :: T.Text
checkpointPolicy =
    "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"

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
