//// Convict/Freeze divergence-enforcement predicates (#106 Slice 4).
////
//// Mirrors the Slice-3 Haskell `Cardano.KERI.AID.Checkpoint.Enforcement`
//// verdict-for-verdict: pure predicates over already-decoded KERI
//// establishment-event evidence (`EventEvidence`) plus the tip
//// `CheckpointDatumV1`, returning a `XxxVerdict` sum (`XxxValid` ≙ `Right ()`,
//// `XxxInvalid(e)` ≙ `Left e`) with one constructor per check, evaluated in the
//// same order. The evidence is decoded: offset/slice extraction over the raw
//// CESR event is #24's concern, not this layer's. O1 is resolved — all
//// controller and witness signatures verify over `event_bytes` (the full event
//// serialization), never the SAID.
////
//// `enforcement_tests.ak` asserts these verdicts match the Haskell over the
//// committed keripy fixtures (`enforcement_vectors.ak`).

use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/message.{next_key_digest}
use cardano_keri/checkpoint/threshold.{Threshold, evaluate}

// ---------------------------------------------------------
// Decoded event evidence (mirrors the Slice-3 `EventEvidence`)
// ---------------------------------------------------------

/// A decoded KERI establishment event: the fields the predicates need plus the
/// raw serialization as the signature target (O1). Signatures are `(index, raw
/// signature)` pairs — `ctrl_sigs` index into `revealed_keys` (the event's own
/// `k`), `wit_sigs` index into the tip datum's stored witness set.
pub type EventEvidence {
  event_bytes: ByteArray,
  t: ByteArray,
  native_sn: Int,
  cesr_aid: ByteArray,
  revealed_keys: List<ByteArray>,
  next_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_sigs: List<(Int, ByteArray)>,
}

// ---------------------------------------------------------
// Convict (fork -> tombstone)
// ---------------------------------------------------------

/// A conviction rejection reason (mirrors the Slice-3 `ConvictError`).
pub type ConvictError {
  /// The evidence is not a rotation (`t != "rot"`).
  CvNotRotation
  /// The evidence is for a different AID than the tip.
  CvAidMismatch
  /// The evidence sn is not the tip's `native_sn` (not the same event slot).
  CvSeqMismatch
  /// The evidence does not reveal exactly the tip's `cur_keys`.
  CvRevealMismatch
  /// The verifying controller signatures do not satisfy `cur_threshold`.
  CvQuorumUnsatisfied
  /// The evidence agrees with the tip on the whole forward commitment.
  CvNoConflict
}

/// The conviction verdict. `ConvictValid` ≙ `Right ()`, `ConvictInvalid(e)` ≙
/// `Left e` (mirrors the Slice-3 `Either ConvictError ()`).
pub type ConvictVerdict {
  ConvictValid
  ConvictInvalid(ConvictError)
}

/// The conviction predicate: a rotation at the tip's own sn revealing the tip's
/// own `cur_keys` (a double-sign of one commitment), attributed to the current
/// quorum, that diverges from the tip on any forward field. Same ordered checks
/// as the Slice-3 Haskell `convictPredicate`.
pub fn convict_predicate(
  tip: CheckpointDatumV1,
  evidence: EventEvidence,
) -> ConvictVerdict {
  if evidence.t != "rot" {
    ConvictInvalid(CvNotRotation)
  } else if evidence.cesr_aid != tip.cesr_aid {
    ConvictInvalid(CvAidMismatch)
  } else if evidence.native_sn != tip.native_sn {
    ConvictInvalid(CvSeqMismatch)
  } else if evidence.revealed_keys != tip.cur_keys {
    ConvictInvalid(CvRevealMismatch)
  } else if !evaluate(
    tip.cur_threshold,
    list.length(tip.cur_keys),
    verified_positions(tip.cur_keys, evidence.event_bytes, evidence.ctrl_sigs),
  ) {
    ConvictInvalid(CvQuorumUnsatisfied)
  } else if forward_agrees(tip, evidence) {
    ConvictInvalid(CvNoConflict)
  } else {
    ConvictValid
  }
}

/// Whether the evidence agrees with the tip on the whole forward commitment
/// (`next_keys`, `next_threshold`, `witnesses`, `toad`) — agreement everywhere
/// is not a conflict.
fn forward_agrees(tip: CheckpointDatumV1, evidence: EventEvidence) -> Bool {
  evidence.next_keys == tip.next_keys && evidence.next_threshold == tip.next_threshold && evidence.witnesses == tip.witnesses && evidence.toad == tip.toad
}

// ---------------------------------------------------------
// Freeze (lag -> frozen)
// ---------------------------------------------------------

/// A freeze rejection reason (mirrors the Slice-3 `FreezeError`).
pub type FreezeError {
  /// The evidence is not a rotation (`t != "rot"`).
  FzNotRotation
  /// The evidence is for a different AID than the tip.
  FzAidMismatch
  /// The evidence sn is not strictly ahead of the tip's `native_sn`.
  FzNotAhead
  /// A verifying revealed key's digest is not in the tip's `next_keys`.
  FzUncommittedReveal
  /// The committed positions do not satisfy the tip's `next_threshold`.
  FzPriorQuorumUnsatisfied
  /// Verifying witness receipts number fewer than the tip's `toad`.
  FzInsufficientReceipts
}

/// The freeze verdict. `FreezeValid` ≙ `Right ()`, `FreezeInvalid(e)` ≙
/// `Left e` (mirrors the Slice-3 `Either FreezeError ()`).
pub type FreezeVerdict {
  FreezeValid
  FreezeInvalid(FreezeError)
}

/// The freeze predicate: a rotation strictly ahead of the tip that provably
/// spends the tip's own pre-rotation commitment and carries enough witness
/// receipts. Same ordered checks as the Slice-3 Haskell `freezePredicate`.
pub fn freeze_predicate(
  tip: CheckpointDatumV1,
  evidence: EventEvidence,
) -> FreezeVerdict {
  if evidence.t != "rot" {
    FreezeInvalid(FzNotRotation)
  } else if evidence.cesr_aid != tip.cesr_aid {
    FreezeInvalid(FzAidMismatch)
  } else if !(evidence.native_sn > tip.native_sn) {
    FreezeInvalid(FzNotAhead)
  } else {
    // Committed reveal: each verifying revealed key's next_key_digest must sit
    // in the tip's committed next_keys, and those positions must satisfy the
    // committed next_threshold (KERI pre-rotation gate).
    let verified = verified_keys(
      evidence.revealed_keys,
      evidence.event_bytes,
      evidence.ctrl_sigs,
    )
    when locate_all(verified, tip.next_keys) is {
      None -> FreezeInvalid(FzUncommittedReveal)
      Some(positions) ->
        if !evaluate(tip.next_threshold, list.length(tip.next_keys), positions) {
          FreezeInvalid(FzPriorQuorumUnsatisfied)
        } else if count_receipts(
          tip.witnesses,
          evidence.event_bytes,
          evidence.wit_sigs,
        ) >= tip.toad {
          FreezeValid
        } else {
          FreezeInvalid(FzInsufficientReceipts)
        }
    }
  }
}

// ---------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------

/// The positions whose `(idx, sig)` verifies with `keys[idx]` over `msg`.
fn verified_positions(
  keys: List<ByteArray>,
  msg: ByteArray,
  sigs: List<(Int, ByteArray)>,
) -> List<Int> {
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
  )
}

/// The keys whose `(idx, sig)` verifies with `keys[idx]` over `msg`.
fn verified_keys(
  keys: List<ByteArray>,
  msg: ByteArray,
  sigs: List<(Int, ByteArray)>,
) -> List<ByteArray> {
  list.filter_map(
    sigs,
    fn(pair) {
      let (idx, sig) = pair
      when list.at(keys, idx) is {
        Some(k) ->
          if verify_ed25519_signature(k, msg, sig) {
            Some(k)
          } else {
            None
          }
        None -> None
      }
    },
  )
}

/// Locate every key's `next_key_digest` in `next_keys`; `None` if any is
/// uncommitted (mirrors the Haskell `traverse (elemIndex ...)` short-circuit).
fn locate_all(
  keys: List<ByteArray>,
  next_keys: List<ByteArray>,
) -> Option<List<Int>> {
  when keys is {
    [] -> Some([])
    [k, ..rest] ->
      when list.index_of(next_keys, next_key_digest(k)) is {
        None -> None
        Some(p) ->
          when locate_all(rest, next_keys) is {
            None -> None
            Some(ps) -> Some([p, ..ps])
          }
      }
  }
}

/// Count `wit_sigs` that verify with the tip witness at their index over `msg`.
fn count_receipts(
  witnesses: List<ByteArray>,
  msg: ByteArray,
  wit_sigs: List<(Int, ByteArray)>,
) -> Int {
  list.foldl(
    wit_sigs,
    0,
    fn(pair, acc) {
      let (idx, sig) = pair
      when list.at(witnesses, idx) is {
        Some(w) ->
          if verify_ed25519_signature(w, msg, sig) {
            acc + 1
          } else {
            acc
          }
        None -> acc
      }
    },
  )
}
