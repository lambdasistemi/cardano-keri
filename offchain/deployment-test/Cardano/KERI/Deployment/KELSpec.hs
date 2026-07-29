{- |
Module      : Cardano.KERI.Deployment.KELSpec
Description : Genuine keripy export compatibility for ckeri registration
-}
module Cardano.KERI.Deployment.KELSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence (..),
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    RegistrationEvidence (..),
    registrationPredicate,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.Deployment.CLI (registerPreflight)
import Cardano.KERI.Deployment.KEL (
    InceptionExport (..),
    RotationExport (..),
    parseInceptionExport,
    parseRotationExport,
 )
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec =
    describe "kli export inception KEL" $ do
        it "consumes an unwitnessed 1-of-1 keripy 1.3.5 export" $ do
            parsed <- load "kli-export-single.cesr"
            cdCurThreshold (inceptionDatum parsed) `shouldBe` Unweighted 1
            length (cdCurKeys $ inceptionDatum parsed) `shouldBe` 1
            cdToad (inceptionDatum parsed) `shouldBe` 0
            reCtrlSigs (inceptionEvidence parsed)
                `shouldSatisfyLength` 1
            reWitReceipts (inceptionEvidence parsed)
                `shouldSatisfyLength` 0
            predicateAccepts parsed

        it "consumes a witnessed 2-of-5 keripy 1.3.5 export" $ do
            parsed <- load "kli-export-2-of-5.cesr"
            cdCurThreshold (inceptionDatum parsed) `shouldBe` Unweighted 2
            length (cdCurKeys $ inceptionDatum parsed) `shouldBe` 5
            length (cdWitnesses $ inceptionDatum parsed) `shouldBe` 3
            cdToad (inceptionDatum parsed) `shouldBe` 2
            reCtrlSigs (inceptionEvidence parsed)
                `shouldSatisfyLength` 5
            reWitReceipts (inceptionEvidence parsed)
                `shouldSatisfyLength` 3
            predicateAccepts parsed

        it "refuses witnessed registration until explicitly acknowledged" $ do
            parsed <- load "kli-export-2-of-5.cesr"
            registerPreflight "preprod" 1 False False 0 parsed
                `shouldSatisfy` isLeft
            registerPreflight "preprod" 1 True False 0 parsed
                `shouldBe` Right ()

        it "refuses duplicate, ambiguous, and non-preprod registration" $ do
            parsed <- load "kli-export-single.cesr"
            registerPreflight "preprod" 1 False False 1 parsed
                `shouldSatisfy` isLeft
            registerPreflight "preprod" 1 False False 2 parsed
                `shouldSatisfy` isLeft
            registerPreflight "preprod" 1 False True 1 parsed
                `shouldBe` Right ()
            registerPreflight "preprod" 1 False True 2 parsed
                `shouldBe` Right ()
            registerPreflight "preview" 2 False False 0 parsed
                `shouldSatisfy` isLeft

        describe "witnessed rotation" $ do
            it "consumes the second message from a genuine keripy 1.3.5 export" $ do
                parsed <- loadRotation "kli-export-2-of-5-rotation.cesr"
                rotationAid parsed
                    `shouldBe` "EDujsIfURabzXyyBulukdlPkG_BX9d4px6VEQFMd33zT"
                cdSeq (rotationDatum parsed) `shouldBe` 1
                cdNativeSn (rotationDatum parsed) `shouldBe` 1
                cdCurThreshold (rotationDatum parsed) `shouldBe` Unweighted 2
                length (cdCurKeys $ rotationDatum parsed) `shouldBe` 5
                length (cdNextKeys $ rotationDatum parsed) `shouldBe` 5
                length (cdWitnesses $ rotationDatum parsed) `shouldBe` 3
                cdToad (rotationDatum parsed) `shouldBe` 2
                rotationEventSignatures parsed `shouldSatisfyLength` 5
                aeCtrlSigs (rotationEvidence parsed) `shouldSatisfyLength` 0
                aeWitReceipts (rotationEvidence parsed) `shouldSatisfyLength` 3
                aeWitCut (rotationEvidence parsed) `shouldSatisfyLength` 0
                aeWitAdd (rotationEvidence parsed) `shouldSatisfyLength` 0
                fieldAt
                    (aeEventBytes $ rotationEvidence parsed)
                    (aeOffT $ rotationEvidence parsed)
                    3
                    `shouldBe` "rot"
                fieldAt
                    (aeEventBytes $ rotationEvidence parsed)
                    (aeOffI $ rotationEvidence parsed)
                    44
                    `shouldBe` "EDujsIfURabzXyyBulukdlPkG_BX9d4px6VEQFMd33zT"

load :: FilePath -> IO InceptionExport
load name = do
    path <- getDataFileName ("deployment-test/fixtures/" <> name)
    bytes <- BS.readFile path
    either
        (\err -> expectationFailure err >> fail err)
        pure
        (parseInceptionExport bytes)

loadRotation :: FilePath -> IO RotationExport
loadRotation name = do
    path <- getDataFileName ("deployment-test/fixtures/" <> name)
    bytes <- BS.readFile path
    either
        (\err -> expectationFailure err >> fail err)
        pure
        (parseRotationExport bytes)

fieldAt :: BS.ByteString -> Int -> Int -> BS.ByteString
fieldAt bytes offset size = BS.take size (BS.drop offset bytes)

predicateAccepts :: InceptionExport -> IO ()
predicateAccepts parsed =
    registrationPredicate
        DeploymentContext
            { dcMinAda = 2_000_000
            , dcDReg = 1_000_000_000
            }
        (inceptionDatum parsed)
        1_007_000_000
        (inceptionEvidence parsed)
        `shouldBe` Right ()

shouldSatisfyLength :: [a] -> Int -> IO ()
shouldSatisfyLength values expected =
    length values `shouldBe` expected
