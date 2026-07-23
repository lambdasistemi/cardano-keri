{- |
Module      : Cardano.KERI.AID.Checkpoint.Advance
Description : #115 R3 advance evidence + AE1-AE10 + event-own signatures

Validator-free schema-support layer for the advance path (KERI rotation
admission), same shape as "Cardano.KERI.AID.Checkpoint.Registration":
pure predicates over an 'AdvanceEvidence' record plus the spent\/
created checkpoint state, returning @Either AdvancePredicateError ()@.

R3: controller signatures ('advancePredicate') verify over the exact full
KERI @event_bytes@ at distinct positions of @NEW.cur_keys@ — never over a
Cardano-specific AdvanceMessage. The AE1-AE10 event-binding slice set pins
the attested KERI @rot@ event bytes to the created state (reusing
"Cardano.KERI.AID.Checkpoint.Registration"'s @respellHex@\/
@respellThreshold@\/@qb64WitnessVerkey@); and the incoming-set witness
receipt gate counts distinct valid receipts indexed into the created
datum's own (already W3-derived and eq7-pinned) witness list. No
SAID\/blake3 proof is taken over the rot bytes (ratified QC): @d@ and @p@
spans are deliberately unchecked. The only Blake3 work is per-revealed-key
pre-rotation commitment matching inside the dual-threshold rule.
-}
module Cardano.KERI.AID.Checkpoint.Advance (
    -- * Advance evidence
    AdvanceEvidence (..),

    -- * Event binding (AE1-AE10)
    AdvanceEventError (..),
    eventBinding,

    -- * The advance predicate
    AdvancePredicateError (..),
    advancePredicate,
) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1 (..),
    Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    AdvanceError,
    RevealedSuccessorSigners (..),
    SpentCheckpoint (..),
    advanceEqualities,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    qb64WitnessVerkey,
    respellHex,
    respellThreshold,
 )
import Cardano.KERI.AID.Ed25519 (
    verifyEd25519,
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
import Data.IntSet qualified as IntSet

-- ---------------------------------------------------------
-- Advance evidence
-- ---------------------------------------------------------

{- | The @Advance@ redeemer evidence: the full keripy @rot@
serialization, per-field value offsets into it (the #114 offset
convention, extended with the @br@\/@ba@ witness-delta spans), the
ordered witness-delta lists themselves, the controller signatures, and
the incoming-set witness receipts.

'aeCtrlSigs' index into @NEW.cur_keys@ and sign 'aeEventBytes' exactly
(R3 sole preimage). 'aeWitReceipts' index into the __derived__ incoming
witness set (@new_set@, W3) and sign 'aeEventBytes' exactly (O1).
-}
data AdvanceEvidence = AdvanceEvidence
    { aeEventBytes :: !ByteString
    -- ^ the full keripy @rot@ serialization (@serder.raw@)
    , aeOffT :: !Int
    -- ^ offset of the event-type value (@t@)
    , aeOffI :: !Int
    -- ^ offset of the 44-char qb64 AID (@i@)
    , aeOffS :: !Int
    -- ^ offset of the hex sequence-number value (@s@)
    , aeOffK :: ![Int]
    -- ^ offsets of the 44-char qb64 @k@ entries
    , aeOffKt :: !Int
    -- ^ offset of the @kt@ JSON value
    , aeOffN :: ![Int]
    -- ^ offsets of the 44-char qb64 @n@ entries
    , aeOffNt :: !Int
    -- ^ offset of the @nt@ JSON value
    , aeOffBr :: ![Int]
    -- ^ offsets of the 44-char qb64 @br@ (witness cut) entries
    , aeOffBa :: ![Int]
    -- ^ offsets of the 44-char qb64 @ba@ (witness add) entries
    , aeOffBt :: !Int
    -- ^ offset of the @bt@ JSON value
    , aeWitCut :: ![Verkey]
    -- ^ KERI @br@ — raw verkeys cut, in event order
    , aeWitAdd :: ![Verkey]
    -- ^ KERI @ba@ — raw verkeys added, in event order
    , aeCtrlSigs :: ![(Int, ByteString)]
    -- ^ @(index into NEW.cur_keys, sig over event_bytes)@
    , aeWitReceipts :: ![(Int, ByteString)]
    -- ^ @(index into the derived new_set, sig over event_bytes)@
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Event binding (AE1-AE10)
-- ---------------------------------------------------------

-- | Which AE axis rejected (one constructor per #115 AE1-AE10 check).
data AdvanceEventError
    = -- | AE1: the @t@ slice is not @\"rot\"@.
      AE1EventTypeMismatch
    | -- | AE2: the @i@ slice is not @NEW.cesr_aid@'s E-code qb64.
      AE2AidMismatch
    | {- | AE3: the @s@ slice is not the hex re-spelling of
      @NEW.native_sn@ (the rot's own @s = native_sn_to@).
      -}
      AE3SequenceMismatch
    | {- | AE4: @k@ offset count or a slice differs from
      @NEW.cur_keys@'s D-code qb64.
      -}
      AE4CurKeysMismatch
    | {- | AE5: the @kt@ slice is not the canonical re-spelling of
      @NEW.cur_threshold@.
      -}
      AE5CurThresholdMismatch
    | {- | AE6: @n@ offset count or a slice differs from
      @NEW.next_keys@'s E-code qb64.
      -}
      AE6NextKeysMismatch
    | {- | AE7: the @nt@ slice is not the canonical re-spelling of
      @NEW.next_threshold@.
      -}
      AE7NextThresholdMismatch
    | {- | AE8: @br@ offset count or a slice differs from the
      evidence's own @wit_cut@ B-code qb64.
      -}
      AE8WitCutMismatch
    | {- | AE9: @ba@ offset count or a slice differs from the
      evidence's own @wit_add@ B-code qb64.
      -}
      AE9WitAddMismatch
    | -- | AE10: the @bt@ slice is not the hex re-spelling of @NEW.toad@.
      AE10ToadMismatch
    deriving stock (Show, Eq)

{- | AE1-AE10 event-binding slice set. Every expected value is computed
from the created datum or the evidence's own witness-delta lists; the
prover's offsets only locate it. @d@ and @p@ are deliberately never
checked (ratified QC — no SAID proof on the advance path).
-}
eventBinding ::
    -- | The created (successor) datum @NEW@.
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    Either AdvanceEventError ()
eventBinding new e = do
    unless (slice (aeOffT e) "rot") (Left AE1EventTypeMismatch)
    unless
        (slice (aeOffI e) (qb64Aid (cdCesrAid new)))
        (Left AE2AidMismatch)
    unless
        (slice (aeOffS e) (respellHex (cdNativeSn new)))
        (Left AE3SequenceMismatch)
    unless
        (slices (aeOffK e) (map qb64Verkey (cdCurKeys new)))
        (Left AE4CurKeysMismatch)
    unless
        (slice (aeOffKt e) (respellThreshold (cdCurThreshold new)))
        (Left AE5CurThresholdMismatch)
    unless
        (slices (aeOffN e) (map qb64Aid (cdNextKeys new)))
        (Left AE6NextKeysMismatch)
    unless
        (slice (aeOffNt e) (respellThreshold (cdNextThreshold new)))
        (Left AE7NextThresholdMismatch)
    unless
        (slices (aeOffBr e) (map qb64WitnessVerkey (aeWitCut e)))
        (Left AE8WitCutMismatch)
    unless
        (slices (aeOffBa e) (map qb64WitnessVerkey (aeWitAdd e)))
        (Left AE9WitAddMismatch)
    unless
        (slice (aeOffBt e) (respellHex (cdToad new)))
        (Left AE10ToadMismatch)
  where
    slice = sliceMatches (aeEventBytes e)
    slices offs expected =
        length offs == length expected
            && and (zipWith slice offs expected)

-- ---------------------------------------------------------
-- The advance predicate
-- ---------------------------------------------------------

{- | Which advance validation rejected: transition equalities, event
binding, or the receipt quorum.
-}
data AdvancePredicateError
    = {- | Transition equalities rejected (AID\/sequence, W1\/W2, eq6
      dual-threshold — including the controller-evidence gate, W3, eq8).
      -}
      AdvMessageInvalid AdvanceError
    | -- | An AE1-AE10 event-binding slice mismatched.
      AdvEventBinding AdvanceEventError
    | {- | The count of distinct valid incoming-set witness receipts is
      below @NEW.toad@.
      -}
      AdvReceiptQuorumUnsatisfied
    deriving stock (Show, Eq)

{- | The pure advance predicate: transition equalities (with controller
signature evidence folded in as the revealed-signer positions over exact
@event_bytes@), AE1-AE10 event binding, and the incoming-set witness
receipt gate, in order.

Controller evidence is the distinct positions of 'aeCtrlSigs' whose
signature verifies over 'aeEventBytes' against @NEW.cur_keys@ at that
position (bad index or bad signature never counts, never aborts — the
@verified_positions@ convention).

Receipts count distinct indices of 'aeWitReceipts' whose signature
verifies over 'aeEventBytes' against the created datum's own witness list.
When @NEW.toad == 0@, the evidence must carry literally no receipt entries.
-}
advancePredicate ::
    SpentCheckpoint ->
    -- | The created (successor) datum @NEW@.
    CheckpointDatumV1 ->
    AdvanceEvidence ->
    Either AdvancePredicateError ()
advancePredicate sc new e = do
    let signed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- aeCtrlSigs e
                , Just k <- [cdCurKeys new `atMay` idx]
                , verifyEd25519 k (aeEventBytes e) sig
                ]
        revealed =
            RevealedSuccessorSigners
                [ k
                | (idx, k) <- zip [0 ..] (cdCurKeys new)
                , idx `IntSet.member` signed
                ]
    first
        AdvMessageInvalid
        (advanceEqualities sc new (aeWitCut e) (aeWitAdd e) revealed)
    first AdvEventBinding (eventBinding new e)
    if cdToad new == 0
        then unless (null (aeWitReceipts e)) (Left AdvReceiptQuorumUnsatisfied)
        else
            let receipted =
                    IntSet.fromList
                        [ idx
                        | (idx, sig) <- aeWitReceipts e
                        , Just w <- [cdWitnesses new `atMay` idx]
                        , verifyEd25519 w (aeEventBytes e) sig
                        ]
             in unless
                    (fromIntegral (IntSet.size receipted) >= cdToad new)
                    (Left AdvReceiptQuorumUnsatisfied)

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

{- | Does the slice of @raw@ at @off@ equal @expected@?
Bounds-checked: an out-of-range span never matches.
-}
sliceMatches :: ByteString -> Int -> ByteString -> Bool
sliceMatches raw off expected =
    off >= 0
        && off + n <= BS.length raw
        && BS.take n (BS.drop off raw) == expected
  where
    n = BS.length expected

-- | Total safe list indexing.
atMay :: [a] -> Int -> Maybe a
atMay xs i
    | i < 0 = Nothing
    | otherwise = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing
