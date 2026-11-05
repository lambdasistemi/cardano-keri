{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.TopUpPackageSpec
Description : What a top-up writes and holds, from the live version 2 checkpoint

The package and the plan follow the Lean @topUp@ clause: the datum is the live
datum with the top-up mark set and nothing else changed, the successor holds
the minimum ADA, the deposit, the bond (unless frozen) and the pool grown by
the amount, and an amount below the premium or a checkpoint already topped up
since its last rotation is refused before anything is built, with the Lean's
refusal names.
-}
module Cardano.KERI.Deployment.TopUpPackageSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyStateView (..),
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData, topUpSpendRedeemerData)
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.KEL (RotationExport (..), parseRotationExport)
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    readManifest,
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.KERI.Deployment.TopUp (
    TopUpPackage (..),
    TopUpPlan (..),
    checkTopUpPackage,
    mkTopUpPackage,
    mkTopUpPlan,
 )
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Either (isLeft, isRight)
import Data.List (isInfixOf)
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
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Top-up package and plan from a live version 2 checkpoint" $ do
    it "grows the pool by the amount and sets the mark, nothing else" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest + 1_000_000) False False False
        package <- either fail pure (mkTopUpPackage manifest active (premiumOf manifest))
        topUpSuccessorLovelace package
            `shouldBe` floorOf manifest + 1_000_000 + premiumOf manifest
        topUpPoolAfter package `shouldBe` 1_000_000 + premiumOf manifest
        topUpSuccessorFacts package `shouldBe` setMark (activeCheckpointFacts active)
        checkTopUpPackage manifest package `shouldBe` Right ()

    it "accepts an amount above the premium and an empty pool" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest) False False False
        mapM_
            ( \amount ->
                mkTopUpPackage manifest active amount `shouldSatisfy` isRight
            )
            [premiumOf manifest, premiumOf manifest + 1, 5 * premiumOf manifest]

    it "tops up a frozen checkpoint against its own floor" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (frozenFloorOf manifest + 1) True False False
        package <- either fail pure (mkTopUpPackage manifest active (premiumOf manifest))
        topUpSuccessorLovelace package
            `shouldBe` frozenFloorOf manifest + 1 + premiumOf manifest

    it "tops up a poisoned checkpoint" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest + 1) False True False
        mkTopUpPackage manifest active (premiumOf manifest) `shouldSatisfy` isRight

    it "refuses an amount one lovelace below the premium: top-up-below-premium" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest) False False False
        case mkTopUpPackage manifest active (premiumOf manifest - 1) of
            Left message -> message `shouldSatisfy` ("top-up-below-premium" `isInfixOf`)
            Right _ -> expectationFailure "a top-up below the premium was packaged"

    it "refuses a negative amount" $ do
        (manifest, rotation) <- fixtures
        mkTopUpPackage manifest (activeAt manifest rotation (floorOf manifest) False False False) (-1)
            `shouldSatisfy` isLeft

    it "refuses a second top-up in one key state: already-topped-up" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest) False False True
        case mkTopUpPackage manifest active (premiumOf manifest) of
            Left message -> message `shouldSatisfy` ("already-topped-up" `isInfixOf`)
            Right _ -> expectationFailure "a second top-up was packaged"

    it "refuses a checkpoint below its floor and a pending termination" $ do
        (manifest, rotation) <- fixtures
        mkTopUpPackage manifest (activeAt manifest rotation (floorOf manifest - 1) False False False) (premiumOf manifest)
            `shouldSatisfy` isLeft
        let pending =
                (activeAt manifest rotation (floorOf manifest) False False False)
                    { activeCheckpointFacts =
                        TerminationPending
                            { tpAid = aidTextOf rotation
                            , tpSn = 0
                            , tpEpoch = 0
                            }
                    }
        mkTopUpPackage manifest pending (premiumOf manifest) `shouldSatisfy` isLeft

    it "refuses a manifest that carries no premium" $ do
        (manifest, rotation) <- fixtures
        let withoutPremium =
                manifest
                    { manifestParameters =
                        (manifestParameters manifest){parameterPremium = Nothing}
                    }
        mkTopUpPackage
            withoutPremium
            (activeAt manifest rotation (floorOf manifest) False False False)
            (premiumOf manifest)
            `shouldSatisfy` isLeft

    it "plans the TopUp redeemer with the amount, the marked datum and the exact lovelace" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest + 7) False False False
            amount = 3 * premiumOf manifest
        package <- either fail pure (mkTopUpPackage manifest active amount)
        case mkTopUpPlan manifest package of
            Left err -> expectationFailure err
            Right plan -> do
                topUpPlanSpendRedeemer plan
                    `shouldBe` plutusDataJson (topUpSpendRedeemerData amount)
                topUpPlanSuccessorLovelace plan
                    `shouldBe` floorOf manifest + 7 + amount
                topUpPlanSuccessorDatum plan
                    `shouldBe` plutusDataJson (asPlcData (V2 (topUpSuccessorFacts package)))
                topUpPlanAmount plan `shouldBe` amount
                topUpPlanSpentReference plan `shouldBe` topUpSpentReference package

-- | A live datum with its top-up mark set; any other datum is left as it is.
setMark :: CheckpointDatumV2 -> CheckpointDatumV2
setMark = \case
    d@Live{} -> d{lvToppedUp = True}
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

premiumOf, bondOf, floorOf, frozenFloorOf :: Manifest -> Integer
premiumOf = fromMaybe (error "the fixture manifest has a premium") . parameterPremium . manifestParameters
bondOf = parameterFreezeBond . manifestParameters
frozenFloorOf manifest = 2_000_000 + parameterRegistrationBond (manifestParameters manifest)
floorOf manifest = frozenFloorOf manifest + bondOf manifest

aidTextOf :: RotationExport -> BS.ByteString
aidTextOf = TE.encodeUtf8 . rotationAid

bornAt :: Integer
bornAt = 1_700_000_000_000

refundTo :: BS.ByteString
refundTo = BS.cons 0x00 (BS.replicate 56 0x42)

-- | The live checkpoint holding this lovelace, with the flags and mark given.
activeAt ::
    Manifest -> RotationExport -> Integer -> Bool -> Bool -> Bool -> ActiveCheckpoint
activeAt manifest rotation lovelace frozen poisoned toppedUp =
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
                live@Live{} ->
                    live{lvFrozen = frozen, lvPoisoned = poisoned, lvToppedUp = toppedUp}
                other -> other
        }
  where
    view = (rotationDatum rotation){cdSeq = 0, cdNativeSn = 0}

hex :: BS.ByteString -> Text
hex = TE.decodeUtf8 . convertToBase Base16
