//// Enforcement wire-binding and predicate parity tests (#116 Slice 2).
////
//// Drives the EE0-EE9 binder and `convict_predicate`/`freeze_predicate` over
//// generated vectors built from the same committed fixtures as the Haskell
//// `EnforcementSpec`. Positives, wire mutations, distinct receipt quorum, and
//// kt-only conflict must agree one-for-one across both languages.

use aiken/cbor
use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/enforcement.{
  Active, CheckpointOutput, CoMissingToken, CoNotTombstone, CoWrongRecord,
  ContinuingOutput, ConvictInvalid, ConvictOutputInvalid, ConvictOutputValid,
  ConvictValid, CvAidMismatch, CvInsufficientReceipts, CvNoConflict,
  CvQuorumUnsatisfied, CvRevealMismatch, CvSeqMismatch, EE0EventBytesLength,
  EE1EventTypeMismatch, EE2AidMismatch, EE3SequenceMismatch, EE4SaidMismatch,
  EE5RevealedKeysMismatch, EE6CurThresholdMismatch, EE7NextKeysMismatch,
  EE8NextThresholdMismatch, EE9ToadMismatch, EnforcementBindingInvalid,
  EnforcementBindingValid, EnforcementEvidence, EventEvidence, FoDatumChanged,
  FoNotFrozen, FreezeInvalid, FreezeOutputInvalid, FreezeOutputValid,
  FreezeValid, Frozen, FzInsufficientReceipts, FzNotAhead, FzUncommittedReveal,
  Tombstone, TombstoneOutput, TombstoneV1, bind_enforcement_evidence,
  convict_output_predicate, convict_predicate, freeze_output_predicate,
  freeze_predicate,
}
use cardano_keri/checkpoint/enforcement_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}

const zero32: ByteArray =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const other32: ByteArray =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

// ---------------------------------------------------------
// T116-S2 wire binding (shared generated fixture vectors)
// ---------------------------------------------------------

test wire_binding_accepts_offset_bearing_fixtures() {
  bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    vec.fork_convict_wire,
  ) == EnforcementBindingValid(vec.fork_convict_evidence) && bind_enforcement_evidence(
    vec.fork_witnessed_convict_tip.cesr_aid,
    vec.fork_witnessed_convict_wire,
  ) == EnforcementBindingValid(vec.fork_witnessed_convict_evidence) && bind_enforcement_evidence(
    vec.lag_freeze_tip.cesr_aid,
    vec.lag_freeze_wire,
  ) == EnforcementBindingValid(vec.lag_freeze_evidence)
}

test ee0_rejects_empty_and_over_1024_event_bytes() {
  let empty = EnforcementEvidence { ..vec.fork_convict_wire, event_bytes: #"" }
  let oversized = EnforcementEvidence {
    ..vec.fork_convict_wire,
    event_bytes: bytearray.concat(
      vec.honest7_freeze_evidence.event_bytes,
      vec.honest7_freeze_evidence.event_bytes,
    ),
  }
  bind_enforcement_evidence(vec.fork_convict_tip.cesr_aid, empty) == EnforcementBindingInvalid(
    EE0EventBytesLength,
  ) && bind_enforcement_evidence(vec.fork_convict_tip.cesr_aid, oversized) == EnforcementBindingInvalid(
    EE0EventBytesLength,
  )
}

test ee1_to_ee9_reject_every_misdirected_offset_axis() {
  let wire = vec.fork_convict_wire
  bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_t: wire.off_i },
  ) == EnforcementBindingInvalid(EE1EventTypeMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_i: wire.off_s },
  ) == EnforcementBindingInvalid(EE2AidMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_s: wire.off_t },
  ) == EnforcementBindingInvalid(EE3SequenceMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_d: wire.off_i },
  ) == EnforcementBindingInvalid(EE4SaidMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_k: wire.off_n },
  ) == EnforcementBindingInvalid(EE5RevealedKeysMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_kt: wire.off_bt },
  ) == EnforcementBindingInvalid(EE6CurThresholdMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_n: wire.off_k },
  ) == EnforcementBindingInvalid(EE7NextKeysMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_nt: wire.off_bt },
  ) == EnforcementBindingInvalid(EE8NextThresholdMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_bt: wire.off_t },
  ) == EnforcementBindingInvalid(EE9ToadMismatch)
}

test malformed_spans_counts_and_d_reject_at_their_binding_axis() {
  let wire = vec.fork_convict_wire
  expect Some(off_n0) = list.at(wire.off_n, 0)
  bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_i: -1 },
  ) == EnforcementBindingInvalid(EE2AidMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence {
      ..wire,
      off_i: bytearray.length(wire.event_bytes) - 1,
    },
  ) == EnforcementBindingInvalid(EE2AidMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_k: [] },
  ) == EnforcementBindingInvalid(EE5RevealedKeysMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, off_n: [off_n0, -1] },
  ) == EnforcementBindingInvalid(EE7NextKeysMismatch) && bind_enforcement_evidence(
    vec.fork_convict_tip.cesr_aid,
    EnforcementEvidence { ..wire, said: bytearray.take(wire.said, 31) },
  ) == EnforcementBindingInvalid(EE4SaidMismatch)
}

// ---------------------------------------------------------
// Positives (the four fixture scenarios)
// ---------------------------------------------------------

test fork_convicts() {
  convict_predicate(vec.fork_convict_tip, vec.fork_convict_evidence) == ConvictValid
}

test honest2_convict_is_no_conflict() {
  convict_predicate(vec.honest2_convict_tip, vec.honest2_convict_evidence) == ConvictInvalid(
    CvNoConflict,
  )
}

test honest2_freezes() {
  freeze_predicate(vec.honest2_freeze_tip, vec.honest2_freeze_evidence) == FreezeValid
}

test lag_freezes() {
  freeze_predicate(vec.lag_freeze_tip, vec.lag_freeze_evidence) == FreezeValid
}

test honest7_freezes() {
  freeze_predicate(vec.honest7_freeze_tip, vec.honest7_freeze_evidence) == FreezeValid
}

// ---------------------------------------------------------
// Negatives (mutations of a base vector; no fixture edits)
// ---------------------------------------------------------

test f4_convict_seq_mismatch() {
  let evidence = EventEvidence {
    ..vec.fork_convict_evidence,
    native_sn: vec.fork_convict_evidence.native_sn + 7,
  }
  convict_predicate(vec.fork_convict_tip, evidence) == ConvictInvalid(
    CvSeqMismatch,
  )
}

test f5_convict_aid_mismatch() {
  let evidence = EventEvidence {
    ..vec.fork_convict_evidence,
    cesr_aid: other32,
  }
  convict_predicate(vec.fork_convict_tip, evidence) == ConvictInvalid(
    CvAidMismatch,
  )
}

test f7_convict_reveal_mismatch() {
  let evidence = EventEvidence {
    ..vec.fork_convict_evidence,
    revealed_keys: [other32],
  }
  convict_predicate(vec.fork_convict_tip, evidence) == ConvictInvalid(
    CvRevealMismatch,
  )
}

test f1_convict_quorum_unsatisfied() {
  let evidence = EventEvidence { ..vec.fork_convict_evidence, ctrl_sigs: [] }
  convict_predicate(vec.fork_convict_tip, evidence) == ConvictInvalid(
    CvQuorumUnsatisfied,
  )
}

test f10_freeze_not_ahead() {
  let evidence = EventEvidence {
    ..vec.honest2_freeze_evidence,
    native_sn: vec.honest2_freeze_tip.native_sn,
  }
  freeze_predicate(vec.honest2_freeze_tip, evidence) == FreezeInvalid(
    FzNotAhead,
  )
}

test f9_freeze_uncommitted_reveal() {
  let tip = CheckpointDatumV1 { ..vec.honest2_freeze_tip, next_keys: [zero32] }
  freeze_predicate(tip, vec.honest2_freeze_evidence) == FreezeInvalid(
    FzUncommittedReveal,
  )
}

test f8_freeze_insufficient_receipts() {
  let evidence = EventEvidence { ..vec.lag_freeze_evidence, wit_sigs: [] }
  freeze_predicate(vec.lag_freeze_tip, evidence) == FreezeInvalid(
    FzInsufficientReceipts,
  )
}

// ---------------------------------------------------------
// F2: some controller sigs verify, but below cur_threshold
// ---------------------------------------------------------

test f2_convict_quorum_below_threshold() {
  // honest_2key convict tip is a 2-of-2; keep only one verifying signature.
  let evidence = EventEvidence {
    ..vec.honest2_convict_evidence,
    ctrl_sigs: list.take(vec.honest2_convict_evidence.ctrl_sigs, 1),
  }
  convict_predicate(vec.honest2_convict_tip, evidence) == ConvictInvalid(
    CvQuorumUnsatisfied,
  )
}

// ---------------------------------------------------------
// TombstoneV1 codec byte-parity (against the Haskell golden)
// ---------------------------------------------------------

test tombstone_cbor_golden() {
  let tomb = TombstoneV1 {
    cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    convicted_at_native_sn: 1,
    evidence_said: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  }
  cbor.serialise(tomb) == vec.golden_tombstone
}

// ---------------------------------------------------------
// Convict output shape (Convict 6) + F13
// ---------------------------------------------------------

fn convict_tombstone(has_token: Bool, role) -> ContinuingOutput {
  ContinuingOutput {
    role,
    has_token,
    datum: TombstoneOutput(
      TombstoneV1 {
        cesr_aid: vec.fork_convict_tip.cesr_aid,
        convicted_at_native_sn: vec.fork_convict_tip.native_sn,
        evidence_said: vec.fork_convict_evidence.said,
      },
    ),
  }
}

test convict_output_valid() {
  convict_output_predicate(
    vec.fork_convict_tip,
    vec.fork_convict_evidence,
    convict_tombstone(True, Tombstone),
  ) == ConvictOutputValid
}

test f13_convict_output_missing_token() {
  convict_output_predicate(
    vec.fork_convict_tip,
    vec.fork_convict_evidence,
    convict_tombstone(False, Tombstone),
  ) == ConvictOutputInvalid(CoMissingToken)
}

test f13_convict_output_wrong_record() {
  let out = ContinuingOutput {
    role: Tombstone,
    has_token: True,
    datum: CheckpointOutput(vec.fork_convict_tip),
  }
  convict_output_predicate(vec.fork_convict_tip, vec.fork_convict_evidence, out) == ConvictOutputInvalid(
    CoWrongRecord,
  )
}

test f13_convict_output_wrong_role() {
  convict_output_predicate(
    vec.fork_convict_tip,
    vec.fork_convict_evidence,
    convict_tombstone(True, Active),
  ) == ConvictOutputInvalid(CoNotTombstone)
}

// ---------------------------------------------------------
// Freeze output shape (Freeze 4) + F12
// ---------------------------------------------------------

fn freeze_checkpoint(has_token: Bool, role, datum) -> ContinuingOutput {
  ContinuingOutput { role, has_token, datum: CheckpointOutput(datum) }
}

test freeze_output_valid() {
  freeze_output_predicate(
    vec.lag_freeze_tip,
    freeze_checkpoint(True, Frozen, vec.lag_freeze_tip),
  ) == FreezeOutputValid
}

test f12_freeze_output_wrong_role() {
  freeze_output_predicate(
    vec.lag_freeze_tip,
    freeze_checkpoint(True, Active, vec.lag_freeze_tip),
  ) == FreezeOutputInvalid(FoNotFrozen)
}

test f12_freeze_output_mutated_datum() {
  let mutated = CheckpointDatumV1 {
    ..vec.lag_freeze_tip,
    native_sn: vec.lag_freeze_tip.native_sn + 1,
  }
  freeze_output_predicate(
    vec.lag_freeze_tip,
    freeze_checkpoint(True, Frozen, mutated),
  ) == FreezeOutputInvalid(FoDatumChanged)
}

// ---------------------------------------------------------
// Slice 7 — anti-fork: witness receipts on convict evidence
// ---------------------------------------------------------

// A WITNESSED fork (witness double-receipts sn=1, diverging n) convicts.
test fork_witnessed_convicts() {
  convict_predicate(
    vec.fork_witnessed_convict_tip,
    vec.fork_witnessed_convict_evidence,
  ) == ConvictValid
}

// F3b (framing-hole regression): the witnessed AID's OWN honest rot_recorded,
// presented as evidence, agrees on n/nt/bt -> must NOT convict. Failed RED
// before the Slice-7 fix (the conflict check's phantom `b` mismatch faked a
// conflict); passes now that the step-5 witness term is dropped.
test f3b_witnessed_honest_recorded_is_no_conflict() {
  convict_predicate(
    vec.fork_witnessed_honest_tip,
    vec.fork_witnessed_honest_evidence,
  ) == ConvictInvalid(CvNoConflict)
}

// F1b: a witnessed AID (toad=1) whose conflicting event carries too few witness
// receipts cannot be convicted. Failed RED before the Slice-7 witness gate.
test f1b_witnessed_fork_insufficient_receipts() {
  let evidence = EventEvidence {
    ..vec.fork_witnessed_convict_evidence,
    wit_sigs: [],
  }
  convict_predicate(vec.fork_witnessed_convict_tip, evidence) == ConvictInvalid(
    CvInsufficientReceipts,
  )
}

// W3: quorum counts distinct verifying witness indices, not signature pairs.
test duplicate_receipt_cannot_fake_convict_toad_two() {
  let tip = CheckpointDatumV1 { ..vec.fork_witnessed_convict_tip, toad: 2 }
  let evidence = EventEvidence {
    ..vec.fork_witnessed_convict_evidence,
    wit_sigs: list.concat(
      vec.fork_witnessed_convict_evidence.wit_sigs,
      vec.fork_witnessed_convict_evidence.wit_sigs,
    ),
  }
  convict_predicate(tip, evidence) == ConvictInvalid(CvInsufficientReceipts)
}

test duplicate_receipt_cannot_fake_freeze_toad_two() {
  let tip = CheckpointDatumV1 { ..vec.lag_freeze_tip, toad: 2 }
  let evidence = EventEvidence {
    ..vec.lag_freeze_evidence,
    wit_sigs: list.concat(
      vec.lag_freeze_evidence.wit_sigs,
      vec.lag_freeze_evidence.wit_sigs,
    ),
  }
  freeze_predicate(tip, evidence) == FreezeInvalid(FzInsufficientReceipts)
}

// W4: `kt` is a forward-agreement axis, after attribution under tip.kt.
test kt_only_divergence_convicts_after_tip_threshold_attribution() {
  let evidence = EventEvidence {
    ..vec.honest2_convict_evidence,
    cur_threshold: Unweighted(1),
  }
  convict_predicate(vec.honest2_convict_tip, evidence) == ConvictValid
}
