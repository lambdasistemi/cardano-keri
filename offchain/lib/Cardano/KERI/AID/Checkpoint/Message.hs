{- |
Module      : Cardano.KERI.AID.Checkpoint.Message
Description : Locator asset-name derivation + pure advance transition, #115 R3

Locator asset-name derivation ('deriveAidAssetName') and the pure advance
transition equalities as predicates over OLD ('SpentCheckpoint'), NEW
(created 'CheckpointDatumV1'), the evidence witness-delta lists, and
revealed successor signers. Validator-free: this fixes the transition
checks #24 runs over the KERI rotation admission, not the transaction
context.

The advance is authorized by the KERI __dual-threshold rule__: the attached
signer evidence must satisfy the rotation's own current threshold over
@NEW.cur_keys@ __and__ the spent checkpoint's pre-rotation threshold
(@next_threshold@) over the committed @next_keys@ digests. The spent current
set never authorizes (KERI pre-rotation; parent #21). Partial\/reserve
rotation is supported: any satisfiable subset of the committed digests may be
revealed, and @NEW.cur_threshold@ may differ from the committed
@next_threshold@ — exactly the KERI rotation-validation rule.

R3 deletes the Cardano-specific 'AdvanceMessage' signed preimage. Deployment
and out-ref binding live in the transaction\/observer context; the pure
transition binds AID continuity, sequence advance, the incoming-set witness
rule (W1-W3), dual-threshold controller evidence, and successor
well-formedness. Controller signatures themselves verify over exact KERI
@event_bytes@ in "Cardano.KERI.AID.Checkpoint.Advance".
-}
module Cardano.KERI.AID.Checkpoint.Message (
    -- * Frozen constants
    checkpointAssetDomainTag,

    -- * Locator asset-name derivation
    deriveAidAssetName,

    -- * Advance (dual-threshold rotation + incoming-set witness admission)
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

-- ---------------------------------------------------------
-- Frozen constants
-- ---------------------------------------------------------

{- | @CHECKPOINT_ASSET_DOMAIN_TAG = UTF8("cardano-keri/checkpoint-asset/v1")@
— a constant 32-byte domain tag (asserted 32 bytes by the test suite).
-}
checkpointAssetDomainTag :: ByteString
checkpointAssetDomainTag =
    TE.encodeUtf8 "cardano-keri/checkpoint-asset/v1"

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
-- Advance transition context (dual-threshold + incoming-set witness)
-- ---------------------------------------------------------

{- | The spent checkpoint context the advance is validated against: its
deployment\/locator identity, exact @TxOutRef@ (filled by the spend\/
observer branch), current witness set (the W1-W3 delta base), and prior
key-state projection fields — including the committed
@(next_keys, next_threshold)@ pair the dual-threshold rule evaluates. A
validation-context type (not a wire type).
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
evidence). eq6 maps this evidence onto @NEW.cur_keys@ positions by direct
raw-key equality (the rotation's own threshold — no hashing) __and__ onto
the spent checkpoint's committed @next_keys@ positions via
@blake3_256(qb64(key))@ (the pre-rotation threshold; one single-block hash
per revealing key, on the rare rotation path only) — KERI's dual-threshold
rule. A stolen spent-current quorum maps to no committed @next_keys@
position, so it fails the pre-rotation threshold and is rejected.
-}
newtype RevealedSuccessorSigners = RevealedSuccessorSigners [Verkey]
    deriving stock (Show, Eq)

-- | Which advance transition check rejected.
data AdvanceError
    = -- | AID crossed or spent locator is not @deriveAidAssetName(cesr_aid)@.
      Eq2AssetOrAidMismatch
    | -- | @NEW.seq \/= OLD.seq + 1@ or @NEW.native_sn@ did not advance.
      Eq5SequenceMismatch
    | {- | W1: @wit_cut@ entries are not pairwise distinct, or one is not a
      member of the spent witness set.
      -}
      EqW1CutInvalid
    | {- | W2: @wit_add@ entries are not pairwise distinct, overlap
      @wit_cut@, or one is already among the surviving (uncut) witnesses.
      -}
      EqW2AddInvalid
    | -- | eq6: the revealed set did not satisfy NEW's current threshold.
      Eq6CurrentQuorumUnsatisfied
    | {- | eq6: the evidence did not satisfy the spent checkpoint's committed
      @(next_keys, next_threshold)@ — the KERI pre-rotation gate.
      -}
      Eq6PriorNextQuorumUnsatisfied
    | -- | eq7: created witnesses are not the W3-derived incoming set.
      Eq7CreatedStateMismatch
    | -- | eq8: the created datum failed 'datumWellFormed' (F18 + rule 14).
      Eq8CreatedIllFormed DatumError
    deriving stock (Show, Eq)

{- | The pure advance transition checks, in order, against OLD, NEW, and the
evidence witness-delta lists. W1\/W2 validate the witness delta against the
spent witness set. eq6 is the KERI dual-threshold rule over the revealed
signers. eq7 (W3) requires @NEW.witnesses@ equal the derived incoming set
(survivors in spent order, then adds in add order). eq8 requires NEW to be
well-formed.
-}
advanceEqualities ::
    SpentCheckpoint ->
    CheckpointDatumV1 ->
    -- | @wit_cut@ (KERI @br@).
    [Verkey] ->
    -- | @wit_add@ (KERI @ba@).
    [Verkey] ->
    RevealedSuccessorSigners ->
    Either AdvanceError ()
advanceEqualities sc created witCut witAdd (RevealedSuccessorSigners controlled) = do
    -- AID continuity + spent locator well-formedness.
    unless
        ( cdCesrAid created == scCesrAid sc
            && scAidAssetName sc == deriveAidAssetName (scCesrAid sc)
        )
        (Left Eq2AssetOrAidMismatch)
    -- Exact successor sequence; native KERI sequence advances.
    unless
        ( cdSeq created == scSeq sc + 1
            && cdNativeSn created > scNativeSn sc
        )
        (Left Eq5SequenceMismatch)
    -- W1: wit_cut entries are pairwise distinct and all members of the spent
    -- witness set.
    unless
        ( distinct witCut
            && all (`elem` scWitnesses sc) witCut
        )
        (Left EqW1CutInvalid)
    let survivors = filter (`notElem` witCut) (scWitnesses sc)
    -- W2: wit_add entries are pairwise distinct, disjoint from wit_cut, and
    -- not already among the survivors.
    unless
        ( distinct witAdd
            && all (`notElem` witCut) witAdd
            && all (`notElem` survivors) witAdd
        )
        (Left EqW2AddInvalid)
    -- eq6a: evidence satisfies NEW's own current threshold over NEW.cur_keys.
    unless
        ( evaluate
            (cdCurThreshold created)
            (length (cdCurKeys created))
            (positionsIn (cdCurKeys created) controlled)
        )
        (Left Eq6CurrentQuorumUnsatisfied)
    -- eq6b: evidence revealed in NEW.cur_keys satisfies OLD's committed
    -- (next_keys, next_threshold).
    let revealed = filter (`elem` cdCurKeys created) controlled
        revealedDigests = map (blake3Hash . qb64Verkey) revealed
    unless
        ( evaluate
            (scNextThreshold sc)
            (length (scNextKeys sc))
            (positionsIn (scNextKeys sc) revealedDigests)
        )
        (Left Eq6PriorNextQuorumUnsatisfied)
    -- eq7 (W3): NEW.witnesses equal the derived incoming set.
    let newSet = survivors <> witAdd
    unless (cdWitnesses created == newSet) (Left Eq7CreatedStateMismatch)
    -- eq8: nothing ill-formed can be written.
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
