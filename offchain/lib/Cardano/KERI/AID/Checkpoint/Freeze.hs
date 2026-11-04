{- |
Module      : Cardano.KERI.AID.Checkpoint.Freeze
Description : The one-step freeze of a live checkpoint (#345, Lean @Step.freeze@)

Anyone may present the controller's own later witnessed rotation as a freeze
while the pool is below the premium: the hunter receives the freeze bond, the
datum keeps its old keys and sequence number with @frozen@ set, and the
output holds @Mc + D + pool@.  The rotation evidence is checked by the
unchanged advance predicate; because the successor keeps the old keys, the
rotated key state it needs travels in the evidence.
-}
module Cardano.KERI.AID.Checkpoint.Freeze (
    FreezeEvidence (..),
    FreezeSettlement (..),
    FreezeRefusal (..),
    FreezeParams (..),
    FreezeInput (..),
    frozenLive,
    freezeSettlement,
    freezeRotatedView,
    freezeSpentView,
    freezeVerdict,
) where

import Cardano.KERI.AID.CESR (aidDigest)
import Cardano.KERI.AID.Checkpoint.Advance (
    AdvanceEvidence,
    AdvancePredicateError,
    advancePredicate,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView,
    keyStateView,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    SpentCheckpoint (..),
    deriveAidAssetName,
 )
import Cardano.KERI.AID.Checkpoint.Value (heldValue, withValue)
import Control.Monad (guard, unless)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)

{- | What a freeze presents beside the transaction: the key material of the
rotation, its sequence number, and the rotation evidence.
-}
data FreezeEvidence = FreezeEvidence
    { feRotatedKeys :: !KeyMaterial
    , feRotatedSn :: !Integer
    , feRotation :: !AdvanceEvidence
    }
    deriving stock (Show, Eq)

-- | What a freeze settles.
data FreezeSettlement = FreezeSettlement
    { fsHunterPaid :: !Integer
    -- ^ the freeze bond the hunter output receives
    , fsSuccessorLovelace :: !Integer
    -- ^ what the frozen successor holds, exactly
    , fsPool :: !Integer
    -- ^ the pool the successor keeps
    }
    deriving stock (Show, Eq)

-- | Why a freeze is refused.
data FreezeRefusal
    = FreezeNotLive
    | FreezeAlreadyFrozen
    | FreezePoisoned
    | FreezeBelowFloor
    | FreezePoolCoversPremium
    | FreezeSuccessorNotTheFrozenCopy
    | FreezeSuccessorValueMismatch
    | FreezeBondUnpaid
    | FreezeAidNotCanonical
    | FreezeRotationRefused !AdvancePredicateError
    deriving stock (Show, Eq)

-- | The deployment amounts, in lovelace.
data FreezeParams = FreezeParams
    { fpMinAda :: !Integer
    , fpDeposit :: !Integer
    , fpBond :: !Integer
    , fpPremium :: !Integer
    }
    deriving stock (Show, Eq)

-- | A freeze as the validator sees it.
data FreezeInput = FreezeInput
    { fiPolicy :: !ByteString
    -- ^ the checkpoint policy the claim names
    , fiSpentTxId :: !ByteString
    , fiSpentIndex :: !Integer
    -- ^ the spent output the claim names
    , fiSpentDatum :: !CheckpointDatumV2
    , fiSpentLovelace :: !Integer
    , fiSuccessorDatum :: !CheckpointDatumV2
    , fiSuccessorLovelace :: !Integer
    , fiHunterLovelace :: !Integer
    , fiEvidence :: !FreezeEvidence
    }
    deriving stock (Show, Eq)

{- | The datum a freeze writes: the live datum with @frozen@ set. 'Nothing'
for a datum that is not live, already frozen or poisoned.
-}
frozenLive :: CheckpointDatumV2 -> Maybe CheckpointDatumV2
frozenLive = \case
    d@Live{lvPoisoned = False, lvFrozen = False} -> Just d{lvFrozen = True}
    _ -> Nothing

{- | What a freeze of an output holding this lovelace settles. 'Nothing' when
the datum cannot be frozen, the output is below its floor, or the pool
covers the premium.
-}
freezeSettlement ::
    FreezeParams -> CheckpointDatumV2 -> Integer -> Maybe FreezeSettlement
freezeSettlement FreezeParams{..} facts lovelace = do
    successor <- frozenLive facts
    pool <- withValue fpMinAda fpDeposit fpBond facts lovelace
    guard (pool < fpPremium)
    pure
        FreezeSettlement
            { fsHunterPaid = fpBond
            , fsSuccessorLovelace =
                heldValue fpMinAda fpDeposit fpBond successor pool
            , fsPool = pool
            }

{- | The key state the rotation evidence is checked against: the spent
datum's identifier, one more epoch, the rotation's sequence number and keys.
-}
freezeRotatedView ::
    CheckpointDatumV2 -> FreezeEvidence -> Maybe KeyStateView
freezeRotatedView spent FreezeEvidence{..} = case spent of
    Live{lvAid, lvEpoch} ->
        (\raw -> keyStateView raw feRotatedSn (lvEpoch + 1) feRotatedKeys)
            <$> aidDigest lvAid
    TerminationPending{} -> Nothing

{- | The spent checkpoint the rotation is checked against, derived from the
spent datum and the output the claim names exactly as the observer derives it:
the datum's epoch and sequence number are the predicate's counter and native
sequence number. 'Nothing' for a datum that is not live or whose identifier
is not canonical.
-}
freezeSpentView ::
    ByteString -> ByteString -> Integer -> CheckpointDatumV2 -> Maybe SpentCheckpoint
freezeSpentView policy txid index = \case
    Live{lvAid, lvSn, lvEpoch, lvKeys} -> do
        raw <- aidDigest lvAid
        pure
            SpentCheckpoint
                { scNetworkId = 0
                , scPolicyId = policy
                , scAidAssetName = deriveAidAssetName raw
                , scTxid = txid
                , scIndex = index
                , scCesrAid = raw
                , scWitnesses = kmWitnesses lvKeys
                , scNextKeys = kmNextKeys lvKeys
                , scNextThreshold = kmNextThreshold lvKeys
                , scSeq = lvEpoch
                , scNativeSn = lvSn
                }
    TerminationPending{} -> Nothing

{- | The Haskell verdict of a freeze: the validator's premises, in order. The
rotation evidence is checked by the advance predicate, unchanged.
-}
freezeVerdict :: FreezeParams -> FreezeInput -> Either FreezeRefusal ()
freezeVerdict params@FreezeParams{..} FreezeInput{..} = do
    case fiSpentDatum of
        TerminationPending{} -> Left FreezeNotLive
        Live{lvFrozen = True} -> Left FreezeAlreadyFrozen
        Live{lvPoisoned = True} -> Left FreezePoisoned
        Live{} -> Right ()
    pool <-
        maybe
            (Left FreezeBelowFloor)
            Right
            (withValue fpMinAda fpDeposit fpBond fiSpentDatum fiSpentLovelace)
    unless (pool < fpPremium) $ Left FreezePoolCoversPremium
    settlement <-
        maybe
            (Left FreezeNotLive)
            Right
            (freezeSettlement params fiSpentDatum fiSpentLovelace)
    unless (Just fiSuccessorDatum == frozenLive fiSpentDatum) $
        Left FreezeSuccessorNotTheFrozenCopy
    unless (fiSuccessorLovelace == fsSuccessorLovelace settlement) $
        Left FreezeSuccessorValueMismatch
    unless (fiHunterLovelace >= fsHunterPaid settlement) $
        Left FreezeBondUnpaid
    spent <-
        maybe
            (Left FreezeAidNotCanonical)
            Right
            (freezeSpentView fiPolicy fiSpentTxId fiSpentIndex fiSpentDatum)
    rotated <-
        maybe
            (Left FreezeAidNotCanonical)
            Right
            (freezeRotatedView fiSpentDatum fiEvidence)
    first FreezeRotationRefused $
        advancePredicate spent rotated (feRotation fiEvidence)
