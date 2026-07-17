//// Convict/Freeze verdict-parity tests (#106 Slice 4).
////
//// Drives `convict_predicate`/`freeze_predicate` over the generated
//// `enforcement_vectors.ak` (the tip datum + decoded evidence the Slice-3
//// Haskell `EnforcementSpec` builds from the same committed keripy fixtures)
//// and asserts the Aiken verdicts match the Haskell one-for-one — the positives
//// (fork convict, honest_2key CvNoConflict, honest_2key/lag/honest_7key freeze)
//// and the negatives (F1/F4/F5/F7/F8/F9/F10) via in-test mutation of a base
//// vector. Any disagreement means one mirror is wrong.

use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/enforcement.{
  ConvictInvalid, ConvictValid, CvAidMismatch, CvNoConflict, CvQuorumUnsatisfied,
  CvRevealMismatch, CvSeqMismatch, EventEvidence, FreezeInvalid, FreezeValid,
  FzInsufficientReceipts, FzNotAhead, FzUncommittedReveal, convict_predicate,
  freeze_predicate,
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
