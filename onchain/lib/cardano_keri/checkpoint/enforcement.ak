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
  said: ByteArray,
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
  /// The conflicting event's witness receipts number fewer than the tip's
  /// `toad` (an unwitnessed event cannot frame a witnessed identity).
  CvInsufficientReceipts
  /// The evidence agrees with the tip on `n`/`nt`/`bt` (the whole conflict
  /// commitment) — not a conflict.
  CvNoConflict
}

/// The conviction verdict. `ConvictValid` ≙ `Right ()`, `ConvictInvalid(e)` ≙
/// `Left e` (mirrors the Slice-3 `Either ConvictError ()`).
pub type ConvictVerdict {
  ConvictValid
  ConvictInvalid(ConvictError)
}

/// The conviction predicate: a rotation at the tip's own sn revealing the tip's
/// own `cur_keys` (a double-sign of one commitment). Ordered checks (same as the
/// Slice-3 Haskell `convictPredicate`): (1) establishment gate — `rot` / same
/// AID / same `native_sn`; (2) same reveal — `k` equals `cur_keys`;
/// (3) controller attribution over `cur_threshold`; (4) witnessed anti-fork gate
/// — at least `toad` verifying witness receipts (vacuous when `toad = 0`);
/// (5) conflict — divergence on `n`/`nt`/`bt` only (the witness set is NOT a
/// conflict axis).
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
  } else if count_receipts(
    tip.witnesses,
    evidence.event_bytes,
    evidence.wit_sigs,
  ) < tip.toad {
    // step 4: witnessed anti-fork gate — the conflicting event must carry at
    // least `toad` verifying witness receipts (toad=0 is the vacuous
    // witnessless tier). Reuses the freeze predicate's receipt count.
    ConvictInvalid(CvInsufficientReceipts)
  } else if forward_agrees(tip, evidence) {
    ConvictInvalid(CvNoConflict)
  } else {
    ConvictValid
  }
}

/// Whether the evidence agrees with the tip on the forward commitment
/// (`next_keys`, `next_threshold`, `toad`) — agreement everywhere is not a
/// conflict. The witness set is NOT a conflict axis: a KERI rotation restates no
/// `b` (only the `br`/`ba` delta), so `evidence.witnesses` is always `[]` and
/// comparing it to a witnessed tip would phantom-convict the AID's own honest
/// rotation.
fn forward_agrees(tip: CheckpointDatumV1, evidence: EventEvidence) -> Bool {
  evidence.next_keys == tip.next_keys && evidence.next_threshold == tip.next_threshold && evidence.toad == tip.toad
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

// ---------------------------------------------------------
// Lifecycle: the conviction-record datum (TombstoneV1)
// ---------------------------------------------------------

/// The conviction record a Convict spend writes to the tombstone output — a
/// NEW frozen wire type (Constr 0, three fields in order), mirroring the
/// Slice-5 Haskell `TombstoneV1`. cbor.serialise is byte-identical to the
/// Haskell canonicalCbor (see enforcement_vectors.golden_tombstone).
pub type TombstoneV1 {
  cesr_aid: ByteArray,
  convicted_at_native_sn: Int,
  evidence_said: ByteArray,
}

// ---------------------------------------------------------
// Output-shape layer (spec Convict 6 / Freeze 4)
// ---------------------------------------------------------

/// The role of a continuing-output's script address in the #106 lifecycle.
pub type AddressRole {
  Active
  Frozen
  Tombstone
}

/// The datum a continuing output carries: the ongoing checkpoint state or the
/// terminal conviction record.
pub type OutputDatum {
  CheckpointOutput(CheckpointDatumV1)
  TombstoneOutput(TombstoneV1)
}

/// An abstract continuing-output descriptor — the schema-layer projection of a
/// transaction output (role, whether it carries the identity token, and its
/// datum), NOT the ledger's Output. The output-shape predicates operate on this.
pub type ContinuingOutput {
  role: AddressRole,
  has_token: Bool,
  datum: OutputDatum,
}

/// A conviction output-shape rejection reason (mirrors the Slice-5
/// `ConvictOutputError`).
pub type ConvictOutputError {
  /// The continuing output is not at the tombstone role.
  CoNotTombstone
  /// The continuing output does not carry the identity token.
  CoMissingToken
  /// The datum is not the exact expected TombstoneV1 conviction record.
  CoWrongRecord
}

/// The conviction output-shape verdict. `ConvictOutputValid` ≙ `Right ()`.
pub type ConvictOutputVerdict {
  ConvictOutputValid
  ConvictOutputInvalid(ConvictOutputError)
}

/// Convict output shape (spec Convict 6): the continuing output must sit at the
/// tombstone role, carry the token, and hold exactly
/// `TombstoneV1 { tip.cesr_aid, tip.native_sn, evidence.said }`. Same ordered
/// checks as the Slice-5 Haskell `convictOutputPredicate`.
pub fn convict_output_predicate(
  tip: CheckpointDatumV1,
  evidence: EventEvidence,
  out: ContinuingOutput,
) -> ConvictOutputVerdict {
  if out.role != Tombstone {
    ConvictOutputInvalid(CoNotTombstone)
  } else if !out.has_token {
    ConvictOutputInvalid(CoMissingToken)
  } else if out.datum != TombstoneOutput(
    TombstoneV1 {
      cesr_aid: tip.cesr_aid,
      convicted_at_native_sn: tip.native_sn,
      evidence_said: evidence.said,
    },
  ) {
    ConvictOutputInvalid(CoWrongRecord)
  } else {
    ConvictOutputValid
  }
}

/// A freeze output-shape rejection reason (mirrors the Slice-5
/// `FreezeOutputError`).
pub type FreezeOutputError {
  /// The continuing output is not at the frozen role.
  FoNotFrozen
  /// The continuing output does not carry the identity token.
  FoMissingToken
  /// The datum is not byte-identical to the tip checkpoint datum.
  FoDatumChanged
}

/// The freeze output-shape verdict. `FreezeOutputValid` ≙ `Right ()`.
pub type FreezeOutputVerdict {
  FreezeOutputValid
  FreezeOutputInvalid(FreezeOutputError)
}

/// Freeze output shape (spec Freeze 4): the continuing output must sit at the
/// frozen role, carry the token, and hold the tip checkpoint datum unchanged.
/// Same ordered checks as the Slice-5 Haskell `freezeOutputPredicate`.
pub fn freeze_output_predicate(
  tip: CheckpointDatumV1,
  out: ContinuingOutput,
) -> FreezeOutputVerdict {
  if out.role != Frozen {
    FreezeOutputInvalid(FoNotFrozen)
  } else if !out.has_token {
    FreezeOutputInvalid(FoMissingToken)
  } else if out.datum != CheckpointOutput(tip) {
    FreezeOutputInvalid(FoDatumChanged)
  } else {
    FreezeOutputValid
  }
}
