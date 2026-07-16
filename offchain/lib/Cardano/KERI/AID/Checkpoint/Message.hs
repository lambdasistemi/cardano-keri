{- |
Module      : Cardano.KERI.AID.Checkpoint.Message
Description : Frozen signed inception\/advance message domains + F10 equalities, #68

The two domain-separated signed preimages ('InceptionMessage', 'AdvanceMessage')
and the locator asset-name derivation ('deriveAidAssetName'), plus the seven F10
advance equalities as pure predicates. Validator-free: this fixes the message
bytes and the equality checks #24 runs over them, not the transaction context.

The advance is authorized by the __revealed successor set__
(@new_cur_keys@\/@new_cur_threshold@), never the spent current set (KERI
pre-rotation; parent #21). Each message binds the deployment (@network_id@,
@checkpoint_policy_id@) and token (@aid_asset_name@), and every carried
@aid_asset_name@ must equal @deriveAidAssetName(cesr_aid)@.
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
    Digest32,
    KeyDigest,
    NextCommitment (..),
    Verkey,
    blake2b_256,
    keysetCommit,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold,
    evaluate,
   wellFormed,
 )
import Control.Monad (
    unless,
 )
import Data.Either (
   isRight,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
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

-- | The signed inception preimage (Constr 0; 11 fields in frozen order).
data InceptionMessage = InceptionMessage
    { imDomain :: !ByteString
    , imNetworkId :: !Integer
    , imCheckpointPolicyId :: !ByteString
    , imAidAssetName :: !ByteString
    , imCesrAid :: !CesrAid
    , imCurKeys :: ![KeyDigest]
    , imCurThreshold :: !Threshold
    , imNextDigest :: !Digest32
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
                , B imNextDigest
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
    Digest32 ->
    [Verkey] ->
    Integer ->
    Integer ->
    InceptionMessage
inceptionMessage net pol asset cesr keys thr nxt wits toad nsn =
    InceptionMessage
        { imDomain = inceptionDomain
        , imNetworkId = net
        , imCheckpointPolicyId = pol
        , imAidAssetName = asset
        , imCesrAid = cesr
        , imCurKeys = keys
        , imCurThreshold = thr
        , imNextDigest = nxt
        , imWitnesses = wits
        , imToad = toad
        , imNativeSn = nsn
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
    deriving stock (Show, Eq)

{- | Registration acceptance predicate: the attested event must be a
non-delegated @icp@, the @cesr_aid@ must be a well-formed 32-byte AID, and the
carried asset name must be the AID's own derived locator (a copied caller name
is insufficient). The width check precedes the derivation check so a malformed
AID is rejected on width, not on a coincidental derivation.
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
    , amPriorCommit :: !Digest32
    , amPriorSeq :: !Integer
    , amPriorNativeSn :: !Integer
    , amNewCurKeys :: ![KeyDigest]
    , amNewCurThreshold :: !Threshold
    , amNewNextDigest :: !Digest32
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
                , B amPriorCommit
                , I amPriorSeq
                , I amPriorNativeSn
                , List (map B amNewCurKeys)
                , asData amNewCurThreshold
                , B amNewNextDigest
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
    Digest32 ->
    Integer ->
    Integer ->
    [KeyDigest] ->
    Threshold ->
    Digest32 ->
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
    priorCommit
    priorSeq
    priorNativeSn
    newKeys
    newThr
    newNext
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
            , amPriorCommit = priorCommit
            , amPriorSeq = priorSeq
            , amPriorNativeSn = priorNativeSn
            , amNewCurKeys = newKeys
            , amNewCurThreshold = newThr
            , amNewNextDigest = newNext
            , amNewWitnesses = newWits
            , amNewToad = newToad
            , amSeqTo = seqTo
            , amNativeSnTo = nativeSnTo
            }

{- | The spent checkpoint context the advance is validated against: its
deployment, identity-asset name, exact @TxOutRef@, and prior key-state
projection fields.
-}
data SpentCheckpoint = SpentCheckpoint
    { scNetworkId :: !Integer
    , scPolicyId :: !ByteString
    , scAidAssetName :: !ByteString
    , scTxid :: !ByteString
    , scIndex :: !Integer
    , scCesrAid :: !CesrAid
    , scNextDigest :: !Digest32
    , scSeq :: !Integer
    , scNativeSn :: !Integer
    }
    deriving stock (Show, Eq)

{- | The key digests of the raw keys that produced valid signatures (the
signer evidence). eq6 maps this evidence onto @new_cur_keys@ positions and
'evaluate's the __revealed successor__ threshold. Because the evidence is
key-based, the SAME evidence can be evaluated against the spent-current set:
a stolen spent-current quorum satisfies the spent-current threshold yet maps
to no successor position, so it fails the successor threshold and is rejected.
-}
newtype RevealedSuccessorSigners = RevealedSuccessorSigners [KeyDigest]
    deriving stock (Show, Eq)

-- | Which advance validation rejected: the frozen domain gate or eq1-eq7.
data AdvanceError
    = -- | The signed preimage domain was not the frozen @adv@ literal.
      AdvanceDomainMismatch
    | -- | eq1: @network_id@ / @checkpoint_policy_id@ do not match the deployment.
      --
      -- The numbered constructors below still mirror the seven F10 equalities.
      Eq1NetworkPolicyMismatch
    | -- | eq2: asset name is not the AID's derived locator, or the AID crossed.
      Eq2AssetOrAidMismatch
    | -- | eq3: @(spent_txid, spent_index)@ is not the spent @TxOutRef@.
      Eq3OutRefMismatch
    | -- | eq4: the reveal does not match @spent.next_digest@ / prior fields.
      Eq4PriorMismatch
    | -- | eq5: @seq_to /= spent.seq + 1@ or @native_sn_to@ did not advance.
      Eq5SequenceMismatch
    | -- | eq6: the __revealed successor__ set did not authorize the advance.
      Eq6SuccessorQuorumUnsatisfied
    | -- | eq7: the created datum does not equal the message's new-state fields.
      Eq7CreatedStateMismatch
    deriving stock (Show, Eq)

{- | The seven F10 advance equalities as pure predicates, checked in order,
against the actual created checkpoint datum. Crucially eq6 evaluates the
signer evidence against the __revealed successor set__
(@new_cur_keys@\/@new_cur_threshold@), not the spent current set — so a full
stolen spent-current quorum yields no successor authorization and is rejected.
eq7 requires the created datum to equal the message's new-state fields exactly
(nothing written that was not signed).
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
    -- eq4: the reveal matches the pre-committed successor and prior fields.
    unless
        ( amPriorCommit am == scNextDigest sc
            && amPriorCommit am
                == keysetCommit
                    (NextCommitment (amNewCurKeys am) (amNewCurThreshold am))
            && amPriorSeq am == scSeq sc
            && amPriorNativeSn am == scNativeSn sc
        )
        (Left Eq4PriorMismatch)
    -- eq5: exact successor sequence; native KERI sequence advances.
    unless
        (amSeqTo am == scSeq sc + 1 && amNativeSnTo am > scNativeSn sc)
        (Left Eq5SequenceMismatch)
    -- eq6: the REVEALED successor set authorizes (NOT the spent current set).
    -- Map the key-based signer evidence onto new_cur_keys positions.
    let sigPositions =
            IntSet.fromList
                [ i
                | (i, k) <- zip [0 ..] (amNewCurKeys am)
                , k `elem` controlled
                ]
    unless
        (isRight (wellFormed (amNewCurKeys am) (amNewCurThreshold am)))
        (Left Eq6SuccessorQuorumUnsatisfied)
    unless
        (evaluate (amNewCurThreshold am) (length (amNewCurKeys am)) sigPositions)
        (Left Eq6SuccessorQuorumUnsatisfied)
    -- eq7: the created datum equals the message's new-state fields exactly.
    let expected =
            CheckpointDatumV1
                { cdCesrAid = amCesrAid am
                , cdCurKeys = amNewCurKeys am
                , cdCurThreshold = amNewCurThreshold am
                , cdNextDigest = amNewNextDigest am
                , cdWitnesses = amNewWitnesses am
                , cdToad = amNewToad am
                , cdSeq = amSeqTo am
                , cdNativeSn = amNativeSnTo am
                }
    unless (created == expected) (Left Eq7CreatedStateMismatch)
