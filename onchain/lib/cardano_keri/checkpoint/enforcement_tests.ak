//// Convict/Freeze verdict-parity tests (#106 Slice 4).
////
//// Drives `convict_predicate`/`freeze_predicate` over the generated
//// `enforcement_vectors.ak` (the tip datum + decoded evidence the Slice-3
//// Haskell `EnforcementSpec` builds from the same committed keripy fixtures)
//// and asserts the Aiken verdicts match the Haskell one-for-one — the positives
//// (fork convict, honest_2key CvNoConflict, honest_2key/lag/honest_7key freeze)
//// and the negatives (F1/F4/F5/F7/F8/F9/F10) via in-test mutation of a base
//// vector. Any disagreement means one mirror is wrong.

use aiken/cbor
use aiken/collection/list
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/enforcement.{
  Active, CheckpointOutput, CoMissingToken, CoNotTombstone, CoWrongRecord,
  ContinuingOutput, ConvictInvalid, ConvictOutputInvalid, ConvictOutputValid,
  ConvictValid, CvAidMismatch, CvNoConflict, CvQuorumUnsatisfied,
  CvRevealMismatch, CvSeqMismatch, EventEvidence, FoDatumChanged, FoNotFrozen,
  FreezeInvalid, FreezeOutputInvalid, FreezeOutputValid, FreezeValid, Frozen,
  FzInsufficientReceipts, FzNotAhead, FzUncommittedReveal, Tombstone,
  TombstoneOutput, TombstoneV1, convict_output_predicate, convict_predicate,
  freeze_output_predicate, freeze_predicate,
}
use cardano_keri/checkpoint/enforcement_vectors as vec

const zero32: ByteArray =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const other32: ByteArray =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

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
// Convict output shape (Convict 5) + F13
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
