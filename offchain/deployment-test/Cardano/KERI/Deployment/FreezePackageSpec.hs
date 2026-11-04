{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.FreezePackageSpec
Description : What a Freeze writes and pays, from the live version 2 checkpoint

The package and the plan follow the Lean @freeze@ clause: the datum is the live
datum with @frozen@ set and the old keys, the hunter output receives the
freeze bond, the successor holds the minimum ADA, the deposit and the pool,
and a pool that covers the premium, a frozen or poisoned checkpoint, or a
rotation that is not later is refused before anything is signed.
-}
module Cardano.KERI.Deployment.FreezePackageSpec (spec) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
    liveOfKeyState,
 )
import Cardano.KERI.AID.Checkpoint.Freeze (FreezeEvidence (..))
import Cardano.KERI.AID.Checkpoint.Message (SpentCheckpoint (..), deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Value (RotationSettlement (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    asPlcData,
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
 )
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.Advance (AdvancePackage (..))
import Cardano.KERI.Deployment.AdvanceTransaction (AdvancePlan (..))
import Cardano.KERI.Deployment.Freeze (mkFreezePackage, mkFreezePlan)
import Cardano.KERI.Deployment.KEL (RotationExport (..), parseRotationExport)
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    readManifest,
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
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
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Freeze package and plan from a live version 2 checkpoint" $ do
    it "pays the bond and keeps the pool when the pool is below the premium" $ do
        (manifest, rotation) <- fixtures
        let pool = premiumOf manifest - 1
        package <- packageAt manifest rotation (floorOf manifest + pool) False False
        settlementPaid (advanceSettlement package) `shouldBe` bondOf manifest
        settlementPoolAfter (advanceSettlement package) `shouldBe` pool
        advanceSuccessorLovelace package `shouldBe` frozenFloorOf manifest + pool

    it "freezes an empty pool" $ do
        (manifest, rotation) <- fixtures
        package <- packageAt manifest rotation (floorOf manifest) False False
        advanceSuccessorLovelace package `shouldBe` frozenFloorOf manifest

    it "writes the old keys, sequence number, epoch and every other fact, with frozen set" $ do
        (manifest, rotation) <- fixtures
        let active = activeAt manifest rotation (floorOf manifest + 1) False False
        package <- either fail pure (mkFreezePackage manifest active rotation)
        advanceSuccessorFacts package
            `shouldBe` setFrozen (activeCheckpointFacts active)

    it "presents the rotation as the log exports it, with its own controller signatures" $ do
        (manifest, rotation) <- fixtures
        package <- packageAt manifest rotation (floorOf manifest + 1) False False
        aeCtrlSigs (advanceEvidence package) `shouldBe` rotationEventSignatures rotation
        aeWitReceipts (advanceEvidence package)
            `shouldBe` aeWitReceipts (rotationEvidence rotation)
        aeCtrlSigs (advanceEvidence package) `shouldSatisfy` (not . null)

    it "refuses a pool equal to the premium" $ do
        (manifest, rotation) <- fixtures
        mkFreezePackage
            manifest
            (activeAt manifest rotation (floorOf manifest + premiumOf manifest) False False)
            rotation
            `shouldSatisfy` isLeft

    it "refuses a frozen checkpoint" $ do
        (manifest, rotation) <- fixtures
        mkFreezePackage
            manifest
            (activeAt manifest rotation (frozenFloorOf manifest + 1) True False)
            rotation
            `shouldSatisfy` isLeft

    it "refuses a poisoned checkpoint" $ do
        (manifest, rotation) <- fixtures
        mkFreezePackage
            manifest
            (activeAt manifest rotation (floorOf manifest + 1) False True)
            rotation
            `shouldSatisfy` isLeft

    it "refuses a checkpoint below its floor and a pending termination" $ do
        (manifest, rotation) <- fixtures
        mkFreezePackage manifest (activeAt manifest rotation (floorOf manifest - 1) False False) rotation
            `shouldSatisfy` isLeft
        let pending =
                (activeAt manifest rotation (floorOf manifest) False False)
                    { activeCheckpointFacts =
                        TerminationPending
                            { tpAid = aidTextOf rotation
                            , tpSn = 0
                            , tpEpoch = 0
                            }
                    }
        mkFreezePackage manifest pending rotation `shouldSatisfy` isLeft

    it "refuses a rotation that is not later than the checkpoint" $ do
        (manifest, rotation) <- fixtures
        let ahead = activeAt manifest rotation (floorOf manifest + 1) False False
            caughtUp =
                ahead
                    { activeCheckpointDatum =
                        (activeCheckpointDatum ahead)
                            { cdNativeSn = cdNativeSn (rotationDatum rotation)
                            }
                    , activeCheckpointFacts =
                        setSn
                            (cdNativeSn (rotationDatum rotation))
                            (activeCheckpointFacts ahead)
                    }
        mkFreezePackage manifest caughtUp rotation `shouldSatisfy` isLeft

    it "plans the hunter output index, the bond and the exact successor lovelace" $ do
        (manifest, rotation) <- fixtures
        let lovelace = floorOf manifest + 7
        package <- packageAt manifest rotation lovelace False False
        case mkFreezePlan manifest package of
            Left err -> expectationFailure err
            Right plan -> do
                planSpendRedeemer plan
                    `shouldBe` plutusDataJson (freezeSpendRedeemerData 1)
                planPremiumPaid plan `shouldBe` bondOf manifest
                planSuccessorLovelace plan `shouldBe` frozenFloorOf manifest + 7
                planSuccessorDatum plan
                    `shouldBe` plutusDataJson (asPlcData (V2 (advanceSuccessorFacts package)))
                planObserverRedeemer plan
                    `shouldBe` plutusDataJson
                        ( freezeObserverRedeemerData
                            (scPolicyId (advanceSpent package))
                            (scTxid (advanceSpent package))
                            (scIndex (advanceSpent package))
                            ( FreezeEvidence
                                { feRotatedKeys = keysOf (rotationDatum rotation)
                                , feRotatedSn = cdNativeSn (rotationDatum rotation)
                                , feRotation = advanceEvidence package
                                }
                            )
                        )

-- | A live datum with its frozen flag set; any other datum is left as it is.
setFrozen :: CheckpointDatumV2 -> CheckpointDatumV2
setFrozen = \case
    d@Live{} -> d{lvFrozen = True}
    other -> other

-- | A live datum at this sequence number; any other datum is left as it is.
setSn :: Integer -> CheckpointDatumV2 -> CheckpointDatumV2
setSn sn = \case
    d@Live{} -> d{lvSn = sn}
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

keysOf :: KeyStateView -> KeyMaterial
keysOf view =
    KeyMaterial
        { kmCurKeys = cdCurKeys view
        , kmCurThreshold = cdCurThreshold view
        , kmNextKeys = cdNextKeys view
        , kmNextThreshold = cdNextThreshold view
        , kmWitnesses = cdWitnesses view
        , kmToad = cdToad view
        }

aidTextOf :: RotationExport -> BS.ByteString
aidTextOf = TE.encodeUtf8 . rotationAid

bornAt :: Integer
bornAt = 1_700_000_000_000

refundTo :: BS.ByteString
refundTo = BS.cons 0x00 (BS.replicate 56 0x42)

-- | The live checkpoint one rotation behind the export, holding this lovelace.
activeAt :: Manifest -> RotationExport -> Integer -> Bool -> Bool -> ActiveCheckpoint
activeAt manifest rotation lovelace frozen poisoned =
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
                live@Live{} -> live{lvFrozen = frozen, lvPoisoned = poisoned}
                other -> other
        }
  where
    view = (rotationDatum rotation){cdSeq = 0, cdNativeSn = 0}

packageAt ::
    Manifest -> RotationExport -> Integer -> Bool -> Bool -> IO AdvancePackage
packageAt manifest rotation lovelace frozen poisoned =
    either
        fail
        pure
        (mkFreezePackage manifest (activeAt manifest rotation lovelace frozen poisoned) rotation)

hex :: BS.ByteString -> Text
hex = TE.decodeUtf8 . convertToBase Base16
