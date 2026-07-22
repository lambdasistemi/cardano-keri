{- |
Module      : Cardano.KERI.AID.Checkpoint.Message
Description : Frozen signed advance message domain + F10 equalities, #68

The signed 'AdvanceMessage', locator asset-name derivation
('deriveAidAssetName'), and F10 advance checks as pure predicates.
Validator-free: this fixes the message bytes and the equality checks #24 runs
over them, not the transaction context.

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

The advance additionally carries the __incoming-set witness rule__ (#115): the
signed preimage carries KERI's delta (@wit_cut@\/@wit_add@) rather than a full
witness list, and 'advanceEqualities' derives the incoming set
(@new_set = (spent.witnesses - wit_cut) ++ wit_add@, survivors first in spent
order, then adds in add order) and requires the created datum's witnesses to
equal it exactly.
-}
module Cardano.KERI.AID.Checkpoint.Message (
    -- * Frozen constants
    checkpointAssetDomainTag,
    advanceDomain,

    -- * Locator asset-name derivation
    deriveAidAssetName,

    -- * Advance (dual-threshold rotation + incoming-set witness admission)
    AdvanceMessage (..),
    advanceMessage,
    SpentCheckpoint (..),
    RevealedSuccessorSigners (..),
    AdvanceError (..),
    advanceEqualities,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (
    blake3Hash,
 )
import Cardano.KERI.AID.CESR (
    qb64Verkey,
 )
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
import Data.List (
    nub,
 )
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

-- | The frozen advance message domain (@adv@).
advanceDomain :: ByteString
advanceDomain = TE.encodeUtf8 "cardano-keri/checkpoint/adv/v1"

-- ---------------------------------------------------------
-- Locator asset-name derivation (#92 -> #68 pin)
-- ---------------------------------------------------------

{- | @aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x45 ‖ cesr_aid)@
over the fixed 65-byte preimage. @0x45@ = ASCII @\'E\'@, the V1 E-native
(Blake3-256) derivation code — the production KERI AID default. The outer
hash stays @blake2b_256@: it is a Cardano-internal label of the AID, never a
KERI artifact, so the cheap native builtin is correct here. Changing either
constant requires a new version tag.
-}
deriveAidAssetName :: CesrAid -> ByteString
deriveAidAssetName cesrAid =
    blake2b_256 (checkpointAssetDomainTag <> BS.cons 0x45 cesrAid)

-- ---------------------------------------------------------
-- Shared codec helper
-- ---------------------------------------------------------

-- | Strip the 'BuiltinData' wrapper of a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

-- ---------------------------------------------------------
-- Advance message (dual-threshold rotation + incoming-set witness
-- admission) — F10 / #77, amended for the incoming-set witness rule (#115)
-- ---------------------------------------------------------

{- | The signed advance preimage (Constr 0; 18 fields in frozen order). Field
14 carries the KERI rotation's witness-cut delta (@br@) and field 15 the
witness-add delta (@ba@) — the incoming witness set is never signed directly;
'advanceEqualities' derives it (see the module doc).
-}
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
    , amNewCurKeys :: ![Verkey]
    , amNewCurThreshold :: !Threshold
    , amNewNextKeys :: ![KeyDigest]
    , amNewNextThreshold :: !Threshold
    , amWitCut :: ![Verkey]
    , amWitAdd :: ![Verkey]
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
                , List (map B amWitCut)
                , List (map B amWitAdd)
                , I amNewToad
                , I amSeqTo
                , I amNativeSnTo
                ]

{- | Build an 'AdvanceMessage' with the frozen @adv@ domain filled in. The
remaining arguments are the fields in spec order (network id .. native_sn_to),
with the witness cut delta immediately before the witness add delta.
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
    [Verkey] ->
    Threshold ->
    [KeyDigest] ->
    Threshold ->
    [Verkey] ->
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
    witCut
    witAdd
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
            , amWitCut = witCut
            , amWitAdd = witAdd
            , amNewToad = newToad
            , amSeqTo = seqTo
            , amNativeSnTo = nativeSnTo
            }

{- | The spent checkpoint context the advance is validated against: its
deployment, identity-asset name, exact @TxOutRef@, current witness set (the
W1-W3 delta base), and prior key-state projection fields — including the
committed @(next_keys, next_threshold)@ pair the dual-threshold rule
evaluates. A validation-context type (not a wire type; the spend branch fills
it from the spent inline datum) — no golden changes beyond the message.
-}
data SpentCheckpoint = SpentCheckpoint
    { scNetworkId :: !Integer
    , scPolicyId :: !ByteString
    , scAidAssetName :: !ByteString
    , scTxid :: !ByteString
    , scIndex :: !Integer
    , scCesrAid :: !CesrAid
    , scWitnesses :: ![Verkey]
    , scNextKeys :: ![KeyDigest]
    , scNextThreshold :: !Threshold
    , scSeq :: !Integer
    , scNativeSn :: !Integer
    }
    deriving stock (Show, Eq)

{- | The __raw__ verkeys that produced valid signatures (the signer
evidence). eq6 maps this evidence onto @new_cur_keys@ positions by direct
raw-key equality (the rotation's own threshold — no hashing) __and__ onto
the spent checkpoint's committed @next_keys@ positions via
@blake3_256(qb64(key))@ (the pre-rotation threshold; one single-block hash
per revealing key, on the rare rotation path only) — KERI's dual-threshold
rule. A stolen spent-current quorum maps to no committed @next_keys@
position, so it fails the pre-rotation threshold and is rejected.
-}
newtype RevealedSuccessorSigners = RevealedSuccessorSigners [Verkey]
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
    | {- | W1: @wit_cut@ entries are not pairwise distinct, or one is not a
      member of the spent witness set.
      -}
      EqW1CutInvalid
    | {- | W2: @wit_add@ entries are not pairwise distinct, overlap
      @wit_cut@, or one is already among the surviving (uncut) witnesses.
      -}
      EqW2AddInvalid
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
actual created checkpoint datum. W1\/W2 (between eq5 and eq6) validate the
witness delta against the spent witness set: @wit_cut@ entries must be
pairwise distinct and all members of @spent.witnesses@ (W1); @wit_add@
entries must be pairwise distinct, disjoint from @wit_cut@, and not already
among the surviving (uncut) witnesses (W2). eq6 is the KERI
__dual-threshold rule__: the signer evidence must satisfy the rotation's own
@new_cur_threshold@ over @new_cur_keys@ __and__ the spent checkpoint's
committed @next_threshold@ over its @next_keys@ digests — where only
evidence from keys revealed in @new_cur_keys@ counts toward the pre-rotation
gate (in KERI, rotation signatures are indexed over the event's own key
list). A full stolen spent-current quorum maps to no committed @next_keys@
position and is rejected; partial\/reserve rotation (a satisfiable subset
reveal, with a restated current threshold) is accepted. eq7 (amended, W3)
requires the created datum to equal the message's new-state fields exactly,
with its witnesses equal to the __derived__ incoming set — survivors (the
spent witnesses minus @wit_cut@, in spent order) followed by @wit_add@ (in
add order) — never the signed lists directly; eq8 requires that state to be
well-formed (which alone bounds @new_toad@: rule 14 requires
@0 <= new_toad <= length(new_set)@, @0@ only when @new_set@ is empty).
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
    -- W1: wit_cut entries are pairwise distinct and all members of the spent
    -- witness set (a dup cut or a cut of a non-member is a malformed
    -- rotation — neither is otherwise caught, as set-wise both are no-ops).
    unless
        ( distinct (amWitCut am)
            && all (`elem` scWitnesses sc) (amWitCut am)
        )
        (Left EqW1CutInvalid)
    -- The surviving (uncut) witnesses, in spent order — the W3 derivation
    -- base, reused by W2 and eq7 below.
    let survivors = filter (`notElem` amWitCut am) (scWitnesses sc)
    -- W2: wit_add entries are pairwise distinct, disjoint from wit_cut (no
    -- cut-then-re-add in one event), and not already among the survivors
    -- (no add-already-present).
    unless
        ( distinct (amWitAdd am)
            && all (`notElem` amWitCut am) (amWitAdd am)
            && all (`notElem` survivors) (amWitAdd am)
        )
        (Left EqW2AddInvalid)
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
    --     Each revealing key is digested once (blake3 over its 44-char qb64)
    --     to find its committed position; the KEL n entries are matched
    --     byte-for-byte.
    let revealed = filter (`elem` amNewCurKeys am) controlled
        revealedDigests = map (blake3Hash . qb64Verkey) revealed
    unless
        ( evaluate
            (scNextThreshold sc)
            (length (scNextKeys sc))
            (positionsIn (scNextKeys sc) revealedDigests)
        )
        (Left Eq6PriorNextQuorumUnsatisfied)
    -- eq7 (amended, W3): the created datum equals the message's new-state
    -- fields exactly, with witnesses equal to the derived incoming set:
    -- survivors (spent order) followed by wit_add (add order).
    let newSet = survivors <> amWitAdd am
        expected =
            CheckpointDatumV1
                { cdCesrAid = amCesrAid am
                , cdCurKeys = amNewCurKeys am
                , cdCurThreshold = amNewCurThreshold am
                , cdNextKeys = amNewNextKeys am
                , cdNextThreshold = amNewNextThreshold am
                , cdWitnesses = newSet
                , cdToad = amNewToad am
                , cdSeq = amSeqTo am
                , cdNativeSn = amNativeSnTo am
                }
    unless (created == expected) (Left Eq7CreatedStateMismatch)
    -- eq8: nothing ill-formed can be written (F18 + rule 14 on the successor).
    first Eq8CreatedIllFormed (datumWellFormed created)

-- | Positions in @keys@ whose entry appears in the given evidence list.
positionsIn :: [ByteString] -> [ByteString] -> IntSet
positionsIn keys controlled =
    IntSet.fromList
        [ i
        | (i, k) <- zip [0 ..] keys
        , k `elem` controlled
        ]

-- | Pairwise distinctness (no duplicate 'ByteString' entries).
distinct :: [ByteString] -> Bool
distinct xs = length (nub xs) == length xs
