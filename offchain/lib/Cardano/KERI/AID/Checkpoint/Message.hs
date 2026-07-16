{- |
Module      : Cardano.KERI.AID.Checkpoint.Message
Description : Frozen signed inception\/advance message domains + F10 equalities, #68

The two domain-separated signed preimages ('InceptionMessage', 'AdvanceMessage')
and the locator asset-name derivation ('deriveAidAssetName'), plus the F10
advance checks as pure predicates. Validator-free: this fixes the message
bytes and the equality checks #24 runs over them, not the transaction context.

The advance is authorized by the KERI __dual-threshold rule__: the attached
signer evidence must satisfy the rotation's own current threshold over
@new_cur_keys@ __and__ the spent checkpoint's pre-rotation threshold
(@next_threshold@) over the committed @next_keys@ digests. The spent current
set never authorizes (KERI pre-rotation; parent #21). Partial\/reserve
rotation is supported: any satisfiable subset of the committed digests may be
revealed, and @new_cur_threshold@ may differ from the committed
@next_threshold@ — exactly the KERI rotation-validation rule. Each message
binds the deployment (@network_id@, @checkpoint_policy_id@) and token
(@aid_asset_name@), and every carried @aid_asset_name@ must equal
@deriveAidAssetName(cesr_aid)@.
-}
module Cardano.KERI.AID.Checkpoint.Message (
    -- * Frozen constants
    checkpointAssetDomainTag,
    inceptionDomain,
    advanceDomain,

    -- * Locator asset-name derivation
    deriveAidAssetName,

    -- * Inception (@icp@) registration
    EventType (..),
    InceptionMessage (..),
    inceptionMessage,
    inceptionDatum,
    InceptionError (..),
    validateInception,

    -- * Advance (rotation / two-seal handoff)
    AdvanceMessage (..),
    advanceMessage,
    SpentCheckpoint (..),
    RevealedSuccessorSigners (..),
    AdvanceError (..),
    advanceEqualities,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CesrAid,
    CheckpointDatumV1 (..),
    DatumError,
    KeyDigest,
    Verkey,
    blake2b_256,
    datumWellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold,
    evaluate,
 )
import Control.Monad (
    unless,
 )
import Data.Bifunctor (
    first,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet (
    IntSet,
 )
import Data.IntSet qualified as IntSet
import Data.Text.Encoding qualified as TE
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
 )

-- ---------------------------------------------------------
-- Frozen constants
-- ---------------------------------------------------------

{- | @CHECKPOINT_ASSET_DOMAIN_TAG = UTF8("cardano-keri/checkpoint-asset/v1")@
— a constant 32-byte domain tag (asserted 32 bytes by the test suite).
-}
checkpointAssetDomainTag :: ByteString
checkpointAssetDomainTag =
    TE.encodeUtf8 "cardano-keri/checkpoint-asset/v1"

-- | The frozen inception message domain (@icp@).
inceptionDomain :: ByteString
inceptionDomain = TE.encodeUtf8 "cardano-keri/checkpoint/icp/v1"

-- | The frozen advance message domain (@adv@).
advanceDomain :: ByteString
advanceDomain = TE.encodeUtf8 "cardano-keri/checkpoint/adv/v1"

-- ---------------------------------------------------------
-- Locator asset-name derivation (#92 -> #68 pin)
-- ---------------------------------------------------------

{- | @aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x46 ‖ cesr_aid)@
over the fixed 65-byte preimage. @0x46@ = ASCII @\'F\'@, the V1 F-only
(Blake2b-256) derivation code. The asset name is a deterministic label of the
AID; changing either constant requires a new version tag.
-}
deriveAidAssetName :: CesrAid -> ByteString
deriveAidAssetName cesrAid =
    blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x46 cesrAid)

-- ---------------------------------------------------------
-- Shared codec helper
-- ---------------------------------------------------------

-- | Strip the 'BuiltinData' wrapper of a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

-- ---------------------------------------------------------
-- Inception message (icp)
-- ---------------------------------------------------------

-- | The attested KERI inception event type. V1 accepts only 'Icp'.
data EventType = Icp | Dip | Drt
    deriving stock (Show, Eq)

-- | The signed inception preimage (Constr 0; 12 fields in frozen order).
data InceptionMessage = InceptionMessage
    { imDomain :: !ByteString
    , imNetworkId :: !Integer
    , imCheckpointPolicyId :: !ByteString
    , imAidAssetName :: !ByteString
    , imCesrAid :: !CesrAid
    , imCurKeys :: ![KeyDigest]
    , imCurThreshold :: !Threshold
    , imNextKeys :: ![KeyDigest]
    , imNextThreshold :: !Threshold
    , imWitnesses :: ![Verkey]
    , imToad :: !Integer
    , imNativeSn :: !Integer
    }
    deriving stock (Show, Eq)

instance ToData InceptionMessage where
    toBuiltinData InceptionMessage{..} =
        BuiltinData $
            Constr
                0
                [ B imDomain
                , I imNetworkId
                , B imCheckpointPolicyId
                , B imAidAssetName
                , B imCesrAid
                , List (map B imCurKeys)
                , asData imCurThreshold
                , List (map B imNextKeys)
                , asData imNextThreshold
                , List (map B imWitnesses)
                , I imToad
                , I imNativeSn
                ]

{- | Build an 'InceptionMessage' with the frozen @icp@ domain filled in. The
remaining arguments are the fields in spec order (network id .. native sn).
-}
inceptionMessage ::
    Integer ->
    ByteString ->
    ByteString ->
    CesrAid ->
    [KeyDigest] ->
    Threshold ->
    [KeyDigest] ->
    Threshold ->
    [Verkey] ->
    Integer ->
    Integer ->
    InceptionMessage
inceptionMessage net pol asset cesr keys thr nkeys nthr wits toad nsn =
    InceptionMessage
        { imDomain = inceptionDomain
        , imNetworkId = net
        , imCheckpointPolicyId = pol
        , imAidAssetName = asset
        , imCesrAid = cesr
        , imCurKeys = keys
        , imCurThreshold = thr
        , imNextKeys = nkeys
        , imNextThreshold = nthr
        , imWitnesses = wits
        , imToad = toad
        , imNativeSn = nsn
        }

{- | The genesis checkpoint datum an accepted inception message mints:
the message's key-state fields at @seq = 0@.
-}
inceptionDatum :: InceptionMessage -> CheckpointDatumV1
inceptionDatum m =
    CheckpointDatumV1
        { cdCesrAid = imCesrAid m
        , cdCurKeys = imCurKeys m
        , cdCurThreshold = imCurThreshold m
        , cdNextKeys = imNextKeys m
        , cdNextThreshold = imNextThreshold m
        , cdWitnesses = imWitnesses m
        , cdToad = imToad m
        , cdSeq = 0
        , cdNativeSn = imNativeSn m
        }

-- | An inception rejection reason.
data InceptionError
    = -- | The signed preimage domain was not the frozen @icp@ literal.
      InceptionDomainMismatch
    | -- | A delegated (@dip@) or rotation (@drt@) inception was attested.
      DelegatedInceptionRejected
    | -- | @cesr_aid@ is not exactly 32 bytes (malformed AID width).
      InceptionAidWidth
    | -- | @aid_asset_name /= deriveAidAssetName(cesr_aid)@.
      InceptionAssetMismatch
    | -- | @native_sn /= 0@: a KERI @icp@ always has @s = 0@.
      InceptionNativeSnNonZero
    | -- | The implied genesis datum failed 'datumWellFormed' (F18 + rule 14).
      InceptionIllFormed DatumError
    deriving stock (Show, Eq)

{- | Registration acceptance predicate: the attested event must be a
non-delegated @icp@, the @cesr_aid@ must be a well-formed 32-byte AID, the
carried asset name must be the AID's own derived locator (a copied caller name
is insufficient), @native_sn@ must be @0@ (a KERI @icp@ always has @s = 0@),
and the implied genesis datum must be fully well-formed (F18 + rule 14). The
width check precedes the derivation check so a malformed AID is rejected on
width, not on a coincidental derivation.
-}
validateInception ::
    EventType -> InceptionMessage -> Either InceptionError ()
validateInception et m = do
    unless (imDomain m == inceptionDomain) (Left InceptionDomainMismatch)
    unless (et == Icp) (Left DelegatedInceptionRejected)
    unless (BS.length (imCesrAid m) == 32) (Left InceptionAidWidth)
    unless
        (imAidAssetName m == deriveAidAssetName (imCesrAid m))
        (Left InceptionAssetMismatch)
    unless (imNativeSn m == 0) (Left InceptionNativeSnNonZero)
    first InceptionIllFormed (datumWellFormed (inceptionDatum m))

-- ---------------------------------------------------------
-- Advance message (rotation / two-seal handoff) — F10 / #77
-- ---------------------------------------------------------

-- | The signed advance preimage (Constr 0; 17 fields in frozen order).
data AdvanceMessage = AdvanceMessage
    { amDomain :: !ByteString
    , amNetworkId :: !Integer
    , amCheckpointPolicyId :: !ByteString
    , amAidAssetName :: !ByteString
    , amCesrAid :: !CesrAid
    , amSpentTxid :: !ByteString
    , amSpentIndex :: !Integer
    , amPriorSeq :: !Integer
    , amPriorNativeSn :: !Integer
    , amNewCurKeys :: ![KeyDigest]
    , amNewCurThreshold :: !Threshold
    , amNewNextKeys :: ![KeyDigest]
    , amNewNextThreshold :: !Threshold
    , amNewWitnesses :: ![Verkey]
    , amNewToad :: !Integer
    , amSeqTo :: !Integer
    , amNativeSnTo :: !Integer
    }
    deriving stock (Show, Eq)

instance ToData AdvanceMessage where
    toBuiltinData AdvanceMessage{..} =
        BuiltinData $
            Constr
                0
                [ B amDomain
                , I amNetworkId
                , B amCheckpointPolicyId
                , B amAidAssetName
                , B amCesrAid
                , B amSpentTxid
                , I amSpentIndex
                , I amPriorSeq
                , I amPriorNativeSn
                , List (map B amNewCurKeys)
                , asData amNewCurThreshold
                , List (map B amNewNextKeys)
                , asData amNewNextThreshold
                , List (map B amNewWitnesses)
                , I amNewToad
                , I amSeqTo
                , I amNativeSnTo
                ]

{- | Build an 'AdvanceMessage' with the frozen @adv@ domain filled in. The
remaining arguments are the fields in spec order (network id .. native_sn_to).
-}
advanceMessage ::
    Integer ->
    ByteString ->
    ByteString ->
    CesrAid ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    [KeyDigest] ->
    Threshold ->
    [KeyDigest] ->
    Threshold ->
    [Verkey] ->
    Integer ->
    Integer ->
    Integer ->
    AdvanceMessage
advanceMessage
    net
    pol
    asset
    cesr
    spentTxid
    spentIndex
    priorSeq
    priorNativeSn
    newKeys
    newThr
    newNextKeys
    newNextThr
    newWits
    newToad
    seqTo
    nativeSnTo =
        AdvanceMessage
            { amDomain = advanceDomain
            , amNetworkId = net
            , amCheckpointPolicyId = pol
            , amAidAssetName = asset
            , amCesrAid = cesr
            , amSpentTxid = spentTxid
            , amSpentIndex = spentIndex
            , amPriorSeq = priorSeq
            , amPriorNativeSn = priorNativeSn
            , amNewCurKeys = newKeys
            , amNewCurThreshold = newThr
            , amNewNextKeys = newNextKeys
            , amNewNextThreshold = newNextThr
            , amNewWitnesses = newWits
            , amNewToad = newToad
            , amSeqTo = seqTo
            , amNativeSnTo = nativeSnTo
            }

{- | The spent checkpoint context the advance is validated against: its
deployment, identity-asset name, exact @TxOutRef@, and prior key-state
projection fields — including the committed @(next_keys, next_threshold)@
pair the dual-threshold rule evaluates.
-}
data SpentCheckpoint = SpentCheckpoint
    { scNetworkId :: !Integer
    , scPolicyId :: !ByteString
    , scAidAssetName :: !ByteString
    , scTxid :: !ByteString
    , scIndex :: !Integer
    , scCesrAid :: !CesrAid
    , scNextKeys :: ![KeyDigest]
    , scNextThreshold :: !Threshold
    , scSeq :: !Integer
    , scNativeSn :: !Integer
    }
    deriving stock (Show, Eq)

{- | The key digests of the raw keys that produced valid signatures (the
signer evidence). eq6 maps this evidence onto @new_cur_keys@ positions (the
rotation's own threshold) __and__ onto the spent checkpoint's committed
@next_keys@ positions (the pre-rotation threshold) — KERI's dual-threshold
rule. Because the evidence is key-based, a stolen spent-current quorum maps
to no committed @next_keys@ position, so it fails the pre-rotation threshold
and is rejected.
-}
newtype RevealedSuccessorSigners = RevealedSuccessorSigners [KeyDigest]
    deriving stock (Show, Eq)

-- | Which advance validation rejected: the frozen domain gate or one of eq1-eq8.
data AdvanceError
    = -- | The signed preimage domain was not the frozen @adv@ literal.
      AdvanceDomainMismatch
    | {- | eq1: @network_id@ / @checkpoint_policy_id@ do not match the deployment.

      The numbered constructors below mirror the eight F10 advance checks.
      -}
      Eq1NetworkPolicyMismatch
    | -- | eq2: asset name is not the AID's derived locator, or the AID crossed.
      Eq2AssetOrAidMismatch
    | -- | eq3: @(spent_txid, spent_index)@ is not the spent @TxOutRef@.
      Eq3OutRefMismatch
    | -- | eq4: @prior_seq@ / @prior_native_sn@ do not match the spent datum.
      Eq4PriorMismatch
    | -- | eq5: @seq_to /= spent.seq + 1@ or @native_sn_to@ did not advance.
      Eq5SequenceMismatch
    | -- | eq6: the revealed set did not satisfy its own current threshold.
      Eq6CurrentQuorumUnsatisfied
    | {- | eq6: the evidence did not satisfy the spent checkpoint's committed
      @(next_keys, next_threshold)@ — the KERI pre-rotation gate.
      -}
      Eq6PriorNextQuorumUnsatisfied
    | -- | eq7: the created datum does not equal the message's new-state fields.
      Eq7CreatedStateMismatch
    | -- | eq8: the created datum failed 'datumWellFormed' (F18 + rule 14).
      Eq8CreatedIllFormed DatumError
    deriving stock (Show, Eq)

{- | The F10 advance checks as pure predicates, checked in order, against the
actual created checkpoint datum. eq6 is the KERI __dual-threshold rule__: the
signer evidence must satisfy the rotation's own @new_cur_threshold@ over
@new_cur_keys@ __and__ the spent checkpoint's committed @next_threshold@ over
its @next_keys@ digests — where only evidence from keys revealed in
@new_cur_keys@ counts toward the pre-rotation gate (in KERI, rotation
signatures are indexed over the event's own key list). A full stolen
spent-current quorum maps to no committed @next_keys@ position and is
rejected; partial\/reserve rotation (a satisfiable subset reveal, with a
restated current threshold) is accepted. eq7 requires the created datum to
equal the message's new-state fields exactly (nothing written that was not
signed); eq8 requires that state to be well-formed.
-}
advanceEqualities ::
    SpentCheckpoint ->
    AdvanceMessage ->
    CheckpointDatumV1 ->
    RevealedSuccessorSigners ->
    Either AdvanceError ()
advanceEqualities sc am created (RevealedSuccessorSigners controlled) = do
    unless (amDomain am == advanceDomain) (Left AdvanceDomainMismatch)
    -- eq1: deployment (network + policy) binding.
    unless
        ( amNetworkId am == scNetworkId sc
            && amCheckpointPolicyId am == scPolicyId sc
        )
        (Left Eq1NetworkPolicyMismatch)
    -- eq2: asset name is the AID's own derived locator, spent asset, and AID.
    unless
        ( amAidAssetName am == deriveAidAssetName (amCesrAid am)
            && amAidAssetName am == scAidAssetName sc
            && amCesrAid am == scCesrAid sc
        )
        (Left Eq2AssetOrAidMismatch)
    -- eq3: exact spent TxOutRef.
    unless
        (amSpentTxid am == scTxid sc && amSpentIndex am == scIndex sc)
        (Left Eq3OutRefMismatch)
    -- eq4: the message binds the exact prior projection state.
    unless
        ( amPriorSeq am == scSeq sc
            && amPriorNativeSn am == scNativeSn sc
        )
        (Left Eq4PriorMismatch)
    -- eq5: exact successor sequence; native KERI sequence advances.
    unless
        (amSeqTo am == scSeq sc + 1 && amNativeSnTo am > scNativeSn sc)
        (Left Eq5SequenceMismatch)
    -- eq6 (dual threshold, KERI rotation rule):
    -- (a) the evidence satisfies the rotation's own current threshold over
    --     new_cur_keys;
    unless
        ( evaluate
            (amNewCurThreshold am)
            (length (amNewCurKeys am))
            (positionsIn (amNewCurKeys am) controlled)
        )
        (Left Eq6CurrentQuorumUnsatisfied)
    -- (b) the evidence revealed in new_cur_keys satisfies the spent
    --     checkpoint's committed (next_keys, next_threshold) — pre-rotation.
    let revealed = filter (`elem` amNewCurKeys am) controlled
    unless
        ( evaluate
            (scNextThreshold sc)
            (length (scNextKeys sc))
            (positionsIn (scNextKeys sc) revealed)
        )
        (Left Eq6PriorNextQuorumUnsatisfied)
    -- eq7: the created datum equals the message's new-state fields exactly.
    let expected =
            CheckpointDatumV1
                { cdCesrAid = amCesrAid am
                , cdCurKeys = amNewCurKeys am
                , cdCurThreshold = amNewCurThreshold am
                , cdNextKeys = amNewNextKeys am
                , cdNextThreshold = amNewNextThreshold am
                , cdWitnesses = amNewWitnesses am
                , cdToad = amNewToad am
                , cdSeq = amSeqTo am
                , cdNativeSn = amNativeSnTo am
                }
    unless (created == expected) (Left Eq7CreatedStateMismatch)
    -- eq8: nothing ill-formed can be written (F18 + rule 14 on the successor).
    first Eq8CreatedIllFormed (datumWellFormed created)

-- | Positions in @keys@ whose digest appears in the signer evidence.
positionsIn :: [KeyDigest] -> [KeyDigest] -> IntSet
positionsIn keys controlled =
    IntSet.fromList
        [ i
        | (i, k) <- zip [0 ..] keys
        , k `elem` controlled
        ]
