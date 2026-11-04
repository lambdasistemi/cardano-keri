{- |
Module      : Cardano.KERI.Deployment.Freeze
Description : Build the package and the plan of a one-step freeze (#345)

A freeze presents the controller's own later witnessed rotation, exactly as
the knowledge-event log exports it: the controller signatures and the witness
receipts are public. It writes the live datum with @frozen@ set and pays the
hunter the freeze bond. The package is the 'AdvancePackage' record (the same
evidence, successor, settlement and lovelace) and the plan is the
'AdvancePlan' record, so the Advance transaction runner submits it unchanged.
-}
module Cardano.KERI.Deployment.Freeze (
    mkFreezePackage,
    checkFreezePackage,
    mkFreezePlan,
) where

import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.Datum (
    KeyStateView (..),
    keyMaterialOf,
 )
import Cardano.KERI.AID.Checkpoint.Freeze (
    FreezeEvidence (..),
    FreezeInput (..),
    FreezeParams (..),
    FreezeSettlement (..),
    freezeSettlement,
    freezeVerdict,
    frozenLive,
 )
import Cardano.KERI.AID.Checkpoint.Message (SpentCheckpoint (..))
import Cardano.KERI.AID.Checkpoint.Value (
    RotationSettlement (..),
    checkpointMinAda,
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    freezeObserverRedeemerData,
    freezeSpendRedeemerData,
 )
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.Advance (
    AdvancePackage (..),
    PackageBase (..),
    packageBase,
    sha256Text,
 )
import Cardano.KERI.Deployment.AdvanceTransaction (
    AdvancePlan,
    mkAdvancePlanWith,
    premiumOutputIndex,
 )
import Cardano.KERI.Deployment.KEL (RotationExport (..))
import Cardano.KERI.Deployment.Manifest (
    DeploymentParameters (..),
    Manifest (..),
 )
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Text qualified as T

{- | The package of a freeze of this live checkpoint on this rotation. 'Left'
when the checkpoint is not live, is frozen or poisoned, holds a pool that
covers the premium, is below its floor, or the rotation is not later than it.
Whether the evidence is a witnessed rotation of exactly this checkpoint is
'checkFreezePackage'\'s question, asked before anything is built.
-}
mkFreezePackage ::
    Manifest ->
    ActiveCheckpoint ->
    RotationExport ->
    Either String AdvancePackage
mkFreezePackage manifest active rotation = do
    PackageBase
        { pbParameters = parameters
        , pbPremium = premium
        , pbSpent = spent
        } <-
        packageBase manifest active rotation
    let facts = activeCheckpointFacts active
        params = freezeParams parameters premium
        rotated = rotationDatum rotation
        evidence =
            (rotationEvidence rotation)
                { aeCtrlSigs = rotationEventSignatures rotation
                }
    unless (cdNativeSn rotated > scNativeSn spent) $
        Left "the rotation is not later than the checkpoint"
    settlement <-
        maybe
            (Left "the checkpoint cannot be frozen: it is not live, is frozen or poisoned, holds a pool that covers the premium, or is below its floor")
            Right
            (freezeSettlement params facts (activeCheckpointLovelace active))
    successorFacts <-
        maybe (Left "the checkpoint is not live") Right (frozenLive facts)
    pure
        AdvancePackage
            { advanceAid = rotationAid rotation
            , advanceActiveCheckpoint = active
            , advanceSpentReference =
                activeCheckpointTxId active
                    <> "#"
                    <> T.pack (show $ activeCheckpointIndex active)
            , advanceSpent = spent
            , advanceSuccessor = rotated
            , advanceSuccessorFacts = successorFacts
            , advanceSettlement =
                RotationSettlement
                    { settlementPaid = fsHunterPaid settlement
                    , settlementPoolAfter = fsPool settlement
                    }
            , advanceSuccessorLovelace = fsSuccessorLovelace settlement
            , advanceEvidence = evidence
            , advanceSigningPreimage = BS.empty
            , advanceDepositIntent = Nothing
            , advancePackageSha256 = sha256Text BS.empty
            }

{- | The Haskell verdict of the freeze this package describes, with the advance
predicate run over the live checkpoint and the rotation evidence: the check
the validator will make, made before a transaction is built.
-}
checkFreezePackage :: Manifest -> AdvancePackage -> Either String ()
checkFreezePackage manifest package = do
    let parameters = manifestParameters manifest
    premium <-
        maybe
            (Left "the manifest has no premiumLovelace")
            Right
            (parameterPremium parameters)
    let active = advanceActiveCheckpoint package
        rotated = advanceSuccessor package
    either (Left . ("freeze rejected: " <>) . show) Right $
        freezeVerdict
            (freezeParams parameters premium)
            FreezeInput
                { fiPolicy = scPolicyId (advanceSpent package)
                , fiSpentTxId = scTxid (advanceSpent package)
                , fiSpentIndex = scIndex (advanceSpent package)
                , fiSpentDatum = activeCheckpointFacts active
                , fiSpentLovelace = activeCheckpointLovelace active
                , fiSuccessorDatum = advanceSuccessorFacts package
                , fiSuccessorLovelace = advanceSuccessorLovelace package
                , fiHunterLovelace = settlementPaid (advanceSettlement package)
                , fiEvidence =
                    FreezeEvidence
                        { feRotatedKeys = keyMaterialOf rotated
                        , feRotatedSn = cdNativeSn rotated
                        , feRotation = advanceEvidence package
                        }
                }

freezeParams :: DeploymentParameters -> Integer -> FreezeParams
freezeParams parameters premium =
    FreezeParams
        { fpMinAda = checkpointMinAda
        , fpDeposit = parameterRegistrationBond parameters
        , fpBond = parameterFreezeBond parameters
        , fpPremium = premium
        }

{- | The plan of a freeze: the Freeze spend redeemer naming the hunter output,
the freeze observer envelope, the frozen datum, the exact successor lovelace
and the bond the hunter output receives.
-}
mkFreezePlan :: Manifest -> AdvancePackage -> Either String AdvancePlan
mkFreezePlan =
    mkAdvancePlanWith $ \policy package ->
        let spent = advanceSpent package
            rotated = advanceSuccessor package
         in ( freezeSpendRedeemerData premiumOutputIndex
            , freezeObserverRedeemerData
                policy
                (scTxid spent)
                (scIndex spent)
                FreezeEvidence
                    { feRotatedKeys = keyMaterialOf rotated
                    , feRotatedSn = cdNativeSn rotated
                    , feRotation = advanceEvidence package
                    }
            )
