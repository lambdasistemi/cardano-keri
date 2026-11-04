{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.AdvancePackageSpec
Description : What an Advance writes and pays, from the live version 2 checkpoint

The package and the plan follow the Lean @rotateKeepPaid@ and
@rotateKeepUnpaid@ clauses: the premium leaves the pool exactly when the pool
covers it, the successor holds exactly its held value, and every fact the
rotation does not change is copied.
-}
module Cardano.KERI.Deployment.AdvancePackageSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    datumKeyState,
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Value (RotationSettlement (..))
import Cardano.KERI.AID.Checkpoint.Wire (advanceSpendRedeemerData, asPlcData)
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.Advance (AdvancePackage (..), mkAdvancePackage)
import Cardano.KERI.Deployment.AdvanceTransaction (AdvancePlan (..), mkAdvancePlan)
import Cardano.KERI.Deployment.KEL (RotationExport (..), parseRotationExport)
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    readManifest,
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Paths_cardano_keri (getDataFileName)
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
spec = describe "Advance package and plan from a live version 2 checkpoint" $ do
    it "pays the premium out of a pool that covers it and keeps the rest" $ do
        (manifest, rotation) <- fixtures
        let pool = premiumOf manifest + 7
        package <- packageAt manifest rotation (floorOf manifest + pool) False
        settlementPaid (advanceSettlement package) `shouldBe` premiumOf manifest
        settlementPoolAfter (advanceSettlement package) `shouldBe` 7
        advanceSuccessorLovelace package `shouldBe` floorOf manifest + 7

    it "pays exactly the premium and leaves an empty pool when the pool equals it" $ do
        (manifest, rotation) <- fixtures
        package <-
            packageAt manifest rotation (floorOf manifest + premiumOf manifest) False
        settlementPaid (advanceSettlement package) `shouldBe` premiumOf manifest
        advanceSuccessorLovelace package `shouldBe` floorOf manifest

    it "pays nothing and keeps the whole pool one lovelace short of the premium" $ do
        (manifest, rotation) <- fixtures
        let lovelace = floorOf manifest + premiumOf manifest - 1
        package <- packageAt manifest rotation lovelace False
        settlementPaid (advanceSettlement package) `shouldBe` 0
        advanceSuccessorLovelace package `shouldBe` lovelace

    it "keeps a frozen checkpoint against its own floor" $ do
        (manifest, rotation) <- fixtures
        let frozenFloor = floorOf manifest - parameterFreezeBond (manifestParameters manifest)
        package <- packageAt manifest rotation (frozenFloor + premiumOf manifest + 3) True
        settlementPoolAfter (advanceSettlement package) `shouldBe` 3
        advanceSuccessorLovelace package `shouldBe` frozenFloor + 3

    it "copies the aid, birth, refund and frozen flag and advances the sequence and epoch" $ do
        (manifest, rotation) <- fixtures
        package <- packageAt manifest rotation (floorOf manifest) False
        case advanceSuccessorFacts package of
            Live{lvAid, lvSn, lvEpoch, lvPoisoned, lvFrozen, lvBornAt, lvRefundTo, lvKeys} -> do
                lvAid `shouldBe` aidTextOf rotation
                lvSn `shouldBe` cdNativeSn (rotationDatum rotation)
                lvEpoch `shouldBe` 1
                lvPoisoned `shouldBe` False
                lvFrozen `shouldBe` False
                lvBornAt `shouldBe` bornAt
                lvRefundTo `shouldBe` refundTo
                kmCurKeys lvKeys `shouldBe` cdCurKeys (rotationDatum rotation)
            TerminationPending{} -> expectationFailure "the successor is not live"
        datumKeyState (V2 (advanceSuccessorFacts package))
            `shouldBe` Just (rotationDatum rotation)

    it "refuses a checkpoint below its floor and a pending termination" $ do
        (manifest, rotation) <- fixtures
        mkAdvancePackage manifest (activeAt manifest rotation (floorOf manifest - 1) False) rotation
            `shouldSatisfy` isLeft
        let pending =
                (activeAt manifest rotation (floorOf manifest) False)
                    { activeCheckpointFacts =
                        TerminationPending
                            { tpAid = aidTextOf rotation
                            , tpSn = 0
                            , tpEpoch = 0
                            }
                    }
        mkAdvancePackage manifest pending rotation `shouldSatisfy` isLeft

    it "reads a manifest of a generation without a premium, as it was written" $ do
        value <- manifestValueWithoutPremium
        case Aeson.fromJSON value :: Aeson.Result Manifest of
            Aeson.Success _ -> pure ()
            Aeson.Error err -> expectationFailure err

    it "keeps a manifest without a premium without one, and one with it as written" $ do
        value <- manifestValueWithoutPremium
        case Aeson.fromJSON value :: Aeson.Result Manifest of
            Aeson.Success without -> do
                parameterPremium (manifestParameters without) `shouldBe` Nothing
                Aeson.fromJSON (Aeson.toJSON without) `shouldBe` Aeson.Success without
                case Aeson.toJSON (manifestParameters without) of
                    Aeson.Object fields -> KM.member "premiumLovelace" fields `shouldBe` False
                    other -> expectationFailure ("parameters are not an object: " <> show other)
            Aeson.Error err -> expectationFailure err
        (with, _) <- fixtures
        parameterPremium (manifestParameters with) `shouldBe` Just 2_000_000
        Aeson.fromJSON (Aeson.toJSON with) `shouldBe` Aeson.Success with

    it "refuses to advance under a manifest without a premium, and names the field" $ do
        value <- manifestValueWithoutPremium
        (_, rotation) <- fixtures
        case Aeson.fromJSON value :: Aeson.Result Manifest of
            Aeson.Success without ->
                case mkAdvancePackage without (activeAt without rotation (floorOf without + 10_000_000) False) rotation of
                    Left err -> err `shouldContain` "premiumLovelace"
                    Right _ -> expectationFailure "advanced without a premium"
            Aeson.Error err -> expectationFailure err

    it "plans the payee output index, the paid premium and the exact successor lovelace" $ do
        (manifest, rotation) <- fixtures
        let lovelace = floorOf manifest + premiumOf manifest + 7
        package <- packageAt manifest rotation lovelace False
        case mkAdvancePlan manifest package of
            Left err -> expectationFailure err
            Right plan -> do
                planSpendRedeemer plan
                    `shouldBe` plutusDataJson (advanceSpendRedeemerData 1)
                planPremiumPaid plan `shouldBe` premiumOf manifest
                planSuccessorLovelace plan `shouldBe` floorOf manifest + 7
                planSuccessorDatum plan
                    `shouldBe` plutusDataJson (asPlcData (V2 (advanceSuccessorFacts package)))

{- | The fixture manifest as JSON with the premium field removed: the shape of a
manifest written for a generation that has none.
-}
manifestValueWithoutPremium :: IO Aeson.Value
manifestValueWithoutPremium = do
    path <-
        getDataFileName "deployment-test/fixtures/register-preflight-m1-manifest.json"
    decoded <- Aeson.eitherDecodeFileStrict' path >>= either fail pure
    pure $ case decoded of
        Aeson.Object top
            | Just (Aeson.Object fields) <- KM.lookup "parameters" top ->
                Aeson.Object
                    ( KM.insert
                        "parameters"
                        (Aeson.Object (KM.delete "premiumLovelace" fields))
                        top
                    )
        other -> other

fixtures :: IO (Manifest, RotationExport)
fixtures = do
    manifestPath <-
        getDataFileName "deployment-test/fixtures/register-preflight-m1-manifest.json"
    manifest <-
        readManifest manifestPath >>= either fail pure
    rotationPath <-
        getDataFileName "deployment-test/fixtures/kli-export-2-of-5-rotation.cesr"
    rotation <-
        BS.readFile rotationPath
            >>= either fail pure . parseRotationExport
    pure (manifest, rotation)

premiumOf :: Manifest -> Integer
premiumOf = fromMaybe (error "the fixture manifest has a premium") . parameterPremium . manifestParameters

{- | The lovelace a live, unfrozen checkpoint holds with an empty pool: the
minimum ADA, the deposit and the freeze bond.
-}
floorOf :: Manifest -> Integer
floorOf manifest =
    2_000_000
        + parameterRegistrationBond (manifestParameters manifest)
        + parameterFreezeBond (manifestParameters manifest)

aidTextOf :: RotationExport -> BS.ByteString
aidTextOf = TE.encodeUtf8 . rotationAid

bornAt :: Integer
bornAt = 1_700_000_000_000

refundTo :: BS.ByteString
refundTo = BS.cons 0x00 (BS.replicate 56 0x42)

-- | The live checkpoint one rotation behind the export, holding this lovelace.
activeAt :: Manifest -> RotationExport -> Integer -> Bool -> ActiveCheckpoint
activeAt manifest rotation lovelace frozen =
    ActiveCheckpoint
        { activeCheckpointAid = rotationAid rotation
        , activeCheckpointAssetName = hex (deriveAidAssetName (cdCesrAid view))
        , activeCheckpointTxId = hex (BS.replicate 32 0x10)
        , activeCheckpointIndex = 0
        , activeCheckpointAddress = checkpointAddressBech32 (manifestCheckpoint manifest)
        , activeCheckpointLovelace = lovelace
        , activeCheckpointAssets = []
        , activeCheckpointDatum = view
        , activeCheckpointFacts =
            case liveOfKeyState refundTo bornAt view of
                live@Live{} -> live{lvFrozen = frozen}
                other -> other
        }
  where
    view = (rotationDatum rotation){cdSeq = 0, cdNativeSn = 0}

packageAt ::
    Manifest -> RotationExport -> Integer -> Bool -> IO AdvancePackage
packageAt manifest rotation lovelace frozen =
    either
        fail
        pure
        (mkAdvancePackage manifest (activeAt manifest rotation lovelace frozen) rotation)

hex :: BS.ByteString -> Text
hex = TE.decodeUtf8 . convertToBase Base16
