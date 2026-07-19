//// #115 S5 advance evidence + AE1-AE10 + receipt gate (Aiken mirror).
////
//// Mirrors the S4 Haskell `Cardano.KERI.AID.Checkpoint.Advance`
//// verdict-for-verdict: the `AdvanceEvidence` record (the full keripy
//// `rot` serialization, per-field value offsets, the witness-delta lists,
//// the controller signatures, and the incoming-set witness receipts), the
//// message reconstruction that feeds the frozen `advance_equalities`
//// (eq1-eq8/W1-W3), the AE1-AE10 event-binding slice set (V6), and the
//// incoming-set witness receipt gate (V7).
////
//// `advance_predicate` runs, in order: V4 (reconstruction + the frozen
//// `advance_equalities`, with V5's controller-signature evidence folded
//// in as the revealed-signer positions), V6 (AE1-AE10 event binding), V7
//// (the receipt quorum). No SAID/blake3 proof is taken over the rot bytes
//// (ratified QC): `d` and `p` spans are deliberately unchecked.

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/message.{
  AdvanceError, AdvanceInvalid, AdvanceMessage, AdvanceValid,
  RevealedSuccessorSigners, SpentCheckpoint, advance_domain, advance_equalities,
  deriveAidAssetName, qb64_aid, qb64_verkey,
}
use cardano_keri/checkpoint/registration.{
  qb64_witness_verkey, respell_hex, respell_threshold, slice_matches,
}

// ---------------------------------------------------------
// Advance evidence
// ---------------------------------------------------------

/// The `Advance` redeemer evidence: the full keripy `rot` serialization,
/// per-field value offsets into it (the #114 offset convention, extended
/// with the `br`/`ba` witness-delta spans), the ordered witness-delta
/// lists themselves, the controller signatures, and the incoming-set
/// witness receipts.
///
/// `ctrl_sigs` index into the RECONSTRUCTED `AdvanceMessage`'s
/// `new_cur_keys` and sign its canonical-CBOR preimage — NOT the KERI
/// event bytes (`event_bytes`). `wit_receipts` index into the DERIVED
/// incoming witness set (the created datum's own `witnesses`, already
/// W3-derived and eq7-pinned) and sign `event_bytes` exactly (O1).
pub type AdvanceEvidence {
  event_bytes: ByteArray,
  off_t: Int,
  off_i: Int,
  off_s: Int,
  off_k: List<Int>,
  off_kt: Int,
  off_n: List<Int>,
  off_nt: Int,
  off_br: List<Int>,
  off_ba: List<Int>,
  off_bt: Int,
  wit_cut: List<ByteArray>,
  wit_add: List<ByteArray>,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_receipts: List<(Int, ByteArray)>,
}

// ---------------------------------------------------------
// Message reconstruction (V4)
// ---------------------------------------------------------

/// The RECONSTRUCTED `AdvanceMessage`: the spent context's
/// deployment/outref/prior fields, the created (successor) datum's own
/// key-state fields, and the evidence's witness-delta lists. This is the
/// only message shape the predicate ever consults — nothing
/// message-shaped is caller-supplied beyond the delta lists (V4), which
/// W1/W2 validate against the spent witness set and AE8/AE9 pin to the
/// receipted event bytes.
pub fn reconstruct_advance_message(
  spent: SpentCheckpoint,
  new: CheckpointDatumV1,
  wit_cut: List<ByteArray>,
  wit_add: List<ByteArray>,
) -> AdvanceMessage {
  AdvanceMessage {
    domain: advance_domain,
    network_id: spent.network_id,
    checkpoint_policy_id: spent.policy_id,
    aid_asset_name: deriveAidAssetName(new.cesr_aid),
    cesr_aid: new.cesr_aid,
    spent_txid: spent.txid,
    spent_index: spent.index,
    prior_seq: spent.seq,
    prior_native_sn: spent.native_sn,
    new_cur_keys: new.cur_keys,
    new_cur_threshold: new.cur_threshold,
    new_next_keys: new.next_keys,
    new_next_threshold: new.next_threshold,
    wit_cut,
    wit_add,
    new_toad: new.toad,
    seq_to: new.seq,
    native_sn_to: new.native_sn,
  }
}

// ---------------------------------------------------------
// Event binding (V6, AE1-AE10)
// ---------------------------------------------------------

/// Which AE axis rejected (one constructor per #115 AE1-AE10 check).
pub type AdvanceEventError {
  /// AE1: the `t` slice is not `"rot"`.
  AE1EventTypeMismatch
  /// AE2: the `i` slice is not `NEW.cesr_aid`'s E-code qb64.
  AE2AidMismatch
  /// AE3: the `s` slice is not the hex re-spelling of `NEW.native_sn` (the
  /// rot's own `s = native_sn_to`).
  AE3SequenceMismatch
  /// AE4: `k` offset count or a slice differs from `NEW.cur_keys`'s D-code
  /// qb64.
  AE4CurKeysMismatch
  /// AE5: the `kt` slice is not the canonical re-spelling of
  /// `NEW.cur_threshold`.
  AE5CurThresholdMismatch
  /// AE6: `n` offset count or a slice differs from `NEW.next_keys`'s
  /// E-code qb64.
  AE6NextKeysMismatch
  /// AE7: the `nt` slice is not the canonical re-spelling of
  /// `NEW.next_threshold`.
  AE7NextThresholdMismatch
  /// AE8: `br` offset count or a slice differs from the evidence's own
  /// `wit_cut` B-code qb64.
  AE8WitCutMismatch
  /// AE9: `ba` offset count or a slice differs from the evidence's own
  /// `wit_add` B-code qb64.
  AE9WitAddMismatch
  /// AE10: the `bt` slice is not the hex re-spelling of `NEW.toad`.
  AE10ToadMismatch
}

/// The AE1-AE10 event-binding verdict. `AdvanceEventValid` ≙ `Right ()`,
/// `AdvanceEventInvalid(e)` ≙ `Left e`.
pub type AdvanceEventVerdict {
  AdvanceEventValid
  AdvanceEventInvalid(AdvanceEventError)
}

/// V6 — the AE1-AE10 event-binding slice set. Every expected value is
/// computed from the created datum (derivation-code-prefixed qb64 or exact
/// keripy re-spelling) or the evidence's own witness-delta lists
/// (`wit_cut`/`wit_add`); the prover's offsets only locate it (the
/// #106/#114 offset-misdirection discipline). `d` and `p` are deliberately
/// never checked (ratified QC — no SAID proof on the advance path).
pub fn event_binding(
  new: CheckpointDatumV1,
  e: AdvanceEvidence,
) -> AdvanceEventVerdict {
  if !slice_matches(e.event_bytes, e.off_t, "rot") {
    AdvanceEventInvalid(AE1EventTypeMismatch)
  } else if !slice_matches(e.event_bytes, e.off_i, qb64_aid(new.cesr_aid)) {
    AdvanceEventInvalid(AE2AidMismatch)
  } else if !slice_matches(e.event_bytes, e.off_s, respell_hex(new.native_sn)) {
    AdvanceEventInvalid(AE3SequenceMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_k,
    list.map(new.cur_keys, qb64_verkey),
  ) {
    AdvanceEventInvalid(AE4CurKeysMismatch)
  } else if !slice_matches(
    e.event_bytes,
    e.off_kt,
    respell_threshold(new.cur_threshold),
  ) {
    AdvanceEventInvalid(AE5CurThresholdMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_n,
    list.map(new.next_keys, qb64_aid),
  ) {
    AdvanceEventInvalid(AE6NextKeysMismatch)
  } else if !slice_matches(
    e.event_bytes,
    e.off_nt,
    respell_threshold(new.next_threshold),
  ) {
    AdvanceEventInvalid(AE7NextThresholdMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_br,
    list.map(e.wit_cut, qb64_witness_verkey),
  ) {
    AdvanceEventInvalid(AE8WitCutMismatch)
  } else if !slices_match(
    e.event_bytes,
    e.off_ba,
    list.map(e.wit_add, qb64_witness_verkey),
  ) {
    AdvanceEventInvalid(AE9WitAddMismatch)
  } else if !slice_matches(e.event_bytes, e.off_bt, respell_hex(new.toad)) {
    AdvanceEventInvalid(AE10ToadMismatch)
  } else {
    AdvanceEventValid
  }
}

// Offset-count equality + slice equality at every offset (the AE4/AE6/
// AE8/AE9 list form; mirrors the S4 Haskell `slices`).
fn slices_match(
  raw: ByteArray,
  offs: List<Int>,
  expected: List<ByteArray>,
) -> Bool {
  when offs is {
    [] -> expected == []
    [o, ..os] ->
      when expected is {
        [] -> False
        [x, ..xs] -> slice_matches(raw, o, x) && slices_match(raw, os, xs)
      }
  }
}

// ---------------------------------------------------------
// The advance predicate
// ---------------------------------------------------------

/// Which advance validation rejected: message equalities, event binding,
/// or the receipt quorum.
pub type AdvancePredicateError {
  /// V4: `advance_equalities` rejected (eq1-eq5, W1/W2, eq6 dual-threshold
  /// — including the controller-evidence gate, amended eq7, eq8).
  AdvMessageInvalid(AdvanceError)
  /// V6: an AE1-AE10 event-binding slice mismatched.
  AdvEventBinding(AdvanceEventError)
  /// V7: the count of distinct valid incoming-set witness receipts is
  /// below `NEW.toad`.
  AdvReceiptQuorumUnsatisfied
}

/// The advance predicate verdict. `AdvancePredicateValid` ≙ `Right ()`,
/// `AdvancePredicateInvalid(e)` ≙ `Left e` (mirrors the S4 Haskell
/// `Either AdvancePredicateError ()`).
pub type AdvancePredicateVerdict {
  AdvancePredicateValid
  AdvancePredicateInvalid(AdvancePredicateError)
}

/// The pure advance predicate: V4 (message reconstruction + equalities,
/// with V5's controller-signature evidence folded in as the `signers`
/// argument), V6 (AE1-AE10 event binding), V7 (incoming-set witness
/// receipt gate), in order.
///
/// V5's controller evidence is the distinct positions of `ctrl_sigs` whose
/// signature verifies over the reconstructed message's canonical-CBOR
/// preimage against `NEW.cur_keys` at that position (bad index or bad
/// signature never counts, never aborts — the `verified_positions`
/// convention).
///
/// V7 counts distinct indices of `wit_receipts` whose signature verifies
/// over `event_bytes` against the created datum's own witness list at
/// that position. Because V4's eq7 (amended, W3) already pins that list to
/// be exactly the derived incoming set, no separate re-derivation is
/// needed here: a cut witness sits at no position of it, so its receipt
/// can never count — structurally, not by filter. When `NEW.toad == 0`,
/// the evidence must carry literally no receipt entries (the brief's
/// downgrade rule): a non-empty list is rejected outright, even one whose
/// entries could never verify, rather than silently ignored.
pub fn advance_predicate(
  spent: SpentCheckpoint,
  new: CheckpointDatumV1,
  e: AdvanceEvidence,
) -> AdvancePredicateVerdict {
  let msg = reconstruct_advance_message(spent, new, e.wit_cut, e.wit_add)
  let preimage = cbor.serialise(msg)
  let revealed = RevealedSuccessorSigners(
    keys_at(new.cur_keys, verified_indices(new.cur_keys, preimage, e.ctrl_sigs)),
  )
  when advance_equalities(spent, msg, new, revealed) is {
    AdvanceInvalid(err) -> AdvancePredicateInvalid(AdvMessageInvalid(err))
    AdvanceValid ->
      when event_binding(new, e) is {
        AdvanceEventInvalid(err) ->
          AdvancePredicateInvalid(AdvEventBinding(err))
        AdvanceEventValid ->
          if new.toad == 0 {
            if e.wit_receipts != [] {
              AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied)
            } else {
              AdvancePredicateValid
            }
          } else {
            let receipted = verified_indices(
              new.witnesses,
              e.event_bytes,
              e.wit_receipts,
            )
            if list.length(receipted) >= new.toad {
              AdvancePredicateValid
            } else {
              AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied)
            }
          }
      }
  }
}

// ---------------------------------------------------------
// Helpers
// ---------------------------------------------------------

// The distinct positions whose `(idx, sig)` verifies with `keys[idx]`
// over `msg` (mirrors the S4 Haskell `IntSet.fromList` dedup; reused for
// both V5's controller-signature gate and V7's receipt gate).
fn verified_indices(
  keys: List<ByteArray>,
  msg: ByteArray,
  sigs: List<(Int, ByteArray)>,
) -> List<Int> {
  list.unique(
    list.filter_map(
      sigs,
      fn(pair) {
        let (idx, sig) = pair
        when list.at(keys, idx) is {
          Some(k) ->
            if verify_ed25519_signature(k, msg, sig) {
              Some(idx)
            } else {
              None
            }
          None -> None
        }
      },
    ),
  )
}

// The keys of `keys` at the given (already-distinct) `positions`,
// preserving `keys`' own ascending order (mirrors the S4 Haskell
// `zip [0..] (cdCurKeys new)` filter by IntSet membership).
fn keys_at(keys: List<ByteArray>, positions: List<Int>) -> List<ByteArray> {
  list.indexed_foldr(
    keys,
    [],
    fn(i, k, acc) {
      if list.has(positions, i) {
        [k, ..acc]
      } else {
        acc
      }
    },
  )
}
