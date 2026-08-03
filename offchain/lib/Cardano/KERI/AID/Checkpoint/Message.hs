{- |
Module      : Cardano.KERI.AID.Checkpoint.Message
Description : Locator asset-name derivation + F10 advance checks, #68/#219

'deriveAidAssetName' and the F10 advance checks as pure predicates.
Validator-free: this fixes the equality checks #24 runs over the spent
context and the actual successor datum, not the transaction context.

The advance is authorized by the KERI __dual-threshold rule__: the attached
signer evidence must satisfy the rotation's own current threshold over
@new.cur_keys@ __and__ the spent checkpoint's pre-rotation threshold
(@next_threshold@) over the committed @next_keys@ digests. The spent current
set never authorizes (KERI pre-rotation; parent #21). Partial\/reserve
rotation is supported: any satisfiable subset of the committed digests may be
revealed, and @new.cur_threshold@ may differ from the committed
@next_threshold@ — exactly the KERI rotation-validation rule.

'advanceEqualities' (#219) checks the actual spent context and the actual
successor datum directly — no reconstructed signed-message layer sits
between them. The controller-signature evidence
("Cardano.KERI.AID.Checkpoint.Advance" V5) verifies against the KERI event's
own bytes (mirrors registration's R7, @0f6a88c@); the checks here need no
txid-shaped or deployment-shaped field to bind them.

The advance additionally carries the __incoming-set witness rule__ (#115):
@wit_cut@\/@wit_add@ are KERI's delta (never a full witness list), and
'advanceEqualities' derives the incoming set (@new_set = (spent.witnesses -
wit_cut) ++ wit_add@, survivors first in spent order, then adds in add
order) and requires the created datum's witnesses to equal it exactly.

'AdvanceMessage'\/'advanceDomain'\/'advanceMessage' are retained only for
'Cardano.KERI.Deployment.Advance.mkAdvancePackage' (offchain\/deployment,
out of #219 phase-1 scope) — dead to 'advanceEqualities' since #219, which
takes the spent context and successor datum directly. Tracked fast-follow
deletion after #181.
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

-- | Which advance validation rejected: one of the F10 checks.
data AdvanceError
    = -- | eq2: asset name is not the AID's derived locator, or the AID crossed.
      Eq2AssetOrAidMismatch
    | -- | eq5: @new.seq /= spent.seq + 1@ or @new.native_sn@ did not advance.
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
    | {- | eq7 (W3): the created datum's witnesses do not equal the derived
      incoming set.
      -}
      Eq7CreatedStateMismatch
    | -- | eq8: the created datum failed 'datumWellFormed' (F18 + rule 14).
      Eq8CreatedIllFormed DatumError
    deriving stock (Show, Eq)

{- | The F10 advance checks as pure predicates, checked in order, against the
actual spent context and the actual successor datum directly — no
reconstructed signed-message layer sits between them (#219). W1\/W2
(between eq5 and eq6) validate the witness delta against the spent witness
set: @wit_cut@ entries must be pairwise distinct and all members of
@spent.witnesses@ (W1); @wit_add@ entries must be pairwise distinct,
disjoint from @wit_cut@, and not already among the surviving (uncut)
witnesses (W2). eq6 is the KERI __dual-threshold rule__: the signer
evidence must satisfy the rotation's own @new.cur_threshold@ over
@new.cur_keys@ __and__ the spent checkpoint's committed @next_threshold@
over its @next_keys@ digests — where only evidence from keys revealed in
@new.cur_keys@ counts toward the pre-rotation gate (in KERI, rotation
signatures are indexed over the event's own key list). A full stolen
spent-current quorum maps to no committed @next_keys@ position and is
rejected; partial\/reserve rotation (a satisfiable subset reveal, with a
restated current threshold) is accepted. eq7 (W3) requires the created
datum's witnesses to equal the __derived__ incoming set exactly — survivors
(the spent witnesses minus @wit_cut@, in spent order) followed by @wit_add@
(in add order) — never the signed lists directly; eq8 requires that state
to be well-formed (which alone bounds @toad@: rule 14 requires
@0 <= toad <= length(new_set)@, @0@ only when @new_set@ is empty).
-}
advanceEqualities ::
    SpentCheckpoint ->
    -- | The created (successor) datum @NEW@.
    CheckpointDatumV1 ->
    -- | @wit_cut@ (KERI @br@).
    [Verkey] ->
    -- | @wit_add@ (KERI @ba@).
    [Verkey] ->
    RevealedSuccessorSigners ->
    Either AdvanceError ()
advanceEqualities sc new witCut witAdd (RevealedSuccessorSigners controlled) = do
    -- eq2: the successor's own derived asset locator matches the spent
    -- asset, and the AID is unchanged across the advance.
    unless
        ( deriveAidAssetName (cdCesrAid new) == scAidAssetName sc
            && cdCesrAid new == scCesrAid sc
        )
        (Left Eq2AssetOrAidMismatch)
    -- eq5: exact successor sequence; native KERI sequence advances.
    unless
        (cdSeq new == scSeq sc + 1 && cdNativeSn new > scNativeSn sc)
        (Left Eq5SequenceMismatch)
    -- W1: wit_cut entries are pairwise distinct and all members of the spent
    -- witness set (a dup cut or a cut of a non-member is a malformed
    -- rotation — neither is otherwise caught, as set-wise both are no-ops).
    unless
        (distinct witCut && all (`elem` scWitnesses sc) witCut)
        (Left EqW1CutInvalid)
    -- The surviving (uncut) witnesses, in spent order — the W3 derivation
    -- base, reused by W2 and eq7 below.
    let survivors = filter (`notElem` witCut) (scWitnesses sc)
    -- W2: wit_add entries are pairwise distinct, disjoint from wit_cut (no
    -- cut-then-re-add in one event), and not already among the survivors
    -- (no add-already-present).
    unless
        ( distinct witAdd
            && all (`notElem` witCut) witAdd
            && all (`notElem` survivors) witAdd
        )
        (Left EqW2AddInvalid)
    -- eq6 (dual threshold, KERI rotation rule):
    -- (a) the evidence satisfies the rotation's own current threshold over
    --     new.cur_keys;
    unless
        ( evaluate
            (cdCurThreshold new)
            (length (cdCurKeys new))
            (positionsIn (cdCurKeys new) controlled)
        )
        (Left Eq6CurrentQuorumUnsatisfied)
    -- (b) the evidence revealed in new.cur_keys satisfies the spent
    --     checkpoint's committed (next_keys, next_threshold) — pre-rotation.
    --     Each revealing key is digested once (blake3 over its 44-char qb64)
    --     to find its committed position; the KEL n entries are matched
    --     byte-for-byte.
    let revealed = filter (`elem` cdCurKeys new) controlled
        revealedDigests = map (blake3Hash . qb64Verkey) revealed
    unless
        ( evaluate
            (scNextThreshold sc)
            (length (scNextKeys sc))
            (positionsIn (scNextKeys sc) revealedDigests)
        )
        (Left Eq6PriorNextQuorumUnsatisfied)
    -- eq7 (W3): the created datum's witnesses equal the derived incoming
    -- set: survivors (spent order) followed by wit_add (add order) — never
    -- the signed lists directly.
    let newSet = survivors <> witAdd
    unless (cdWitnesses new == newSet) (Left Eq7CreatedStateMismatch)
    -- eq8: nothing ill-formed can be written (F18 + rule 14 on the successor).
    first Eq8CreatedIllFormed (datumWellFormed new)

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
