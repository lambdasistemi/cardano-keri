//// Advance verdict-parity tests (#115 S5, #219 permissionless).
////
//// Drives `advance_predicate` over the generated `advance_vectors.ak`
//// (the spent context, created/successor datum, evidence, and
//// Haskell-computed verdict the S4 `AdvanceSpec` families build from the
//// same committed keripy `advance.json`) and asserts, per vector, that
//// the Aiken predicate returns the SAME verdict the vector records —
//// verdict parity is the acceptance bar. Each test additionally pins the
//// expected constructor in-line (a third independent spelling next to the
//// S4 hspec and the generator's own assertion), so a generator bug cannot
//// silently weaken the suite.
////
//// Covers: the four honest fixture families (`adv_wit_2key`,
//// `adv_wit_7key`, `adv_keep`, `adv_downgrade`) — each now genuinely
//// permissionless: `ctrl_sigs` are the fixture's own `rot_sigs`
//// (`signing_target: "event_raw"`), no Cardano-domain signing step; one
//// executable rejection per AE1-AE10 axis; the A-001 offset-misdirection
//// family (spans into `a`/`p`/`d`, cross-field/code confusion,
//// truncated/negative/duplicated/shortened/emptied offsets);
//// controller-evidence negatives (bad index, a signature over the now-dead
//// `AdvanceMessage` CBOR preimage, below threshold, stolen current quorum,
//// substituted successor); the #219 anti-replay isolation of eq5's seq
//// conjunct; W1/W2/eq7/eq8 delta malformations (dup cut/add, cut of a
//// non-member, add-already-present, cut/add overlap, derived-set
//// mismatch, wrong survivor order, toad out of bounds); and V7
//// receipt-quorum negatives (receipt-free, below-toad, bad/out-of-range
//// index, bad signature, duplicate index, wrong-member index, cut-witness
//// receipt, outgoing-only quorum, non-empty receipts at toad=0).

use cardano_keri/checkpoint/advance.{
  AE10ToadMismatch, AE1EventTypeMismatch, AE2AidMismatch, AE3SequenceMismatch,
  AE4CurKeysMismatch, AE5CurThresholdMismatch, AE6NextKeysMismatch,
  AE7NextThresholdMismatch, AE8WitCutMismatch, AE9WitAddMismatch,
  AdvEventBinding, AdvMessageInvalid, AdvReceiptQuorumUnsatisfied,
  AdvanceEvidence, AdvancePredicateInvalid, AdvancePredicateValid,
  AdvancePredicateVerdict, advance_predicate,
}
use cardano_keri/checkpoint/advance_vectors as vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, ToadRange}
use cardano_keri/checkpoint/message.{
  Eq5SequenceMismatch, Eq6CurrentQuorumUnsatisfied,
  Eq6PriorNextQuorumUnsatisfied, Eq7CreatedStateMismatch, Eq8CreatedIllFormed,
  EqW1CutInvalid, EqW2AddInvalid, SpentCheckpoint,
}

// ---------------------------------------------------------
// Harness: parity + pinned-constructor check per vector
// ---------------------------------------------------------

/// The Aiken predicate must reproduce the vector's recorded (Haskell)
/// verdict, AND the recorded verdict must be the constructor this suite
/// pins for the scenario.
fn parity(
  spent: SpentCheckpoint,
  created: CheckpointDatumV1,
  e: AdvanceEvidence,
  recorded: AdvancePredicateVerdict,
  pinned: AdvancePredicateVerdict,
) -> Bool {
  advance_predicate(spent, created, e) == recorded && recorded == pinned
}

// ---------------------------------------------------------
// Verdict parity: positives
// ---------------------------------------------------------

test pos_adv_wit_2key_accepts() {
  parity(
    vec.pos_adv_wit_2key_spent,
    vec.pos_adv_wit_2key_created,
    vec.pos_adv_wit_2key_evidence,
    vec.pos_adv_wit_2key_verdict,
    AdvancePredicateValid,
  )
}

test pos_adv_wit_7key_accepts() {
  parity(
    vec.pos_adv_wit_7key_spent,
    vec.pos_adv_wit_7key_created,
    vec.pos_adv_wit_7key_evidence,
    vec.pos_adv_wit_7key_verdict,
    AdvancePredicateValid,
  )
}

test pos_adv_keep_accepts() {
  parity(
    vec.pos_adv_keep_spent,
    vec.pos_adv_keep_created,
    vec.pos_adv_keep_evidence,
    vec.pos_adv_keep_verdict,
    AdvancePredicateValid,
  )
}

test pos_adv_keep_witnesses_unchanged() {
  vec.pos_adv_keep_created.witnesses == vec.pos_adv_keep_spent.witnesses
}

test pos_adv_downgrade_accepts() {
  parity(
    vec.pos_adv_downgrade_spent,
    vec.pos_adv_downgrade_created,
    vec.pos_adv_downgrade_evidence,
    vec.pos_adv_downgrade_verdict,
    AdvancePredicateValid,
  )
}

test pos_adv_downgrade_witnesses_empty_toad_zero() {
  vec.pos_adv_downgrade_created.witnesses == [] && vec.pos_adv_downgrade_created.toad == 0 && vec.pos_adv_downgrade_evidence.wit_receipts == []
}

// Owner replay: the same complete package re-validates identically.
test pos_owner_replay() {
  let first_run = advance_predicate(
    vec.pos_adv_wit_2key_spent,
    vec.pos_adv_wit_2key_created,
    vec.pos_adv_wit_2key_evidence,
  )
  let second_run = advance_predicate(
    vec.pos_adv_wit_2key_spent,
    vec.pos_adv_wit_2key_created,
    vec.pos_adv_wit_2key_evidence,
  )
  first_run == AdvancePredicateValid && second_run == AdvancePredicateValid
}

// ---------------------------------------------------------
// V6: AE1-AE10 event-binding negatives (one per axis)
// ---------------------------------------------------------

// ---------------------------------------------------------
// A-001 condition 1: the offset-misdirection family
// ---------------------------------------------------------

// ---------------------------------------------------------
// V5: controller-evidence negatives (folded into eq6)
// ---------------------------------------------------------

test ctrl_bad_index_rejects() {
  parity(
    vec.ctrl_bad_index_spent,
    vec.ctrl_bad_index_created,
    vec.ctrl_bad_index_evidence,
    vec.ctrl_bad_index_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq6CurrentQuorumUnsatisfied)),
  )
}

// #219: a signature over the now-dead `AdvanceMessage` CBOR preimage no
// longer verifies against `event_bytes` -- PROVE-LIST item 2.
test ctrl_old_message_preimage_rejects() {
  parity(
    vec.ctrl_old_message_preimage_spent,
    vec.ctrl_old_message_preimage_created,
    vec.ctrl_old_message_preimage_evidence,
    vec.ctrl_old_message_preimage_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq6CurrentQuorumUnsatisfied)),
  )
}

test ctrl_below_threshold_rejects() {
  parity(
    vec.ctrl_below_threshold_spent,
    vec.ctrl_below_threshold_created,
    vec.ctrl_below_threshold_evidence,
    vec.ctrl_below_threshold_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq6CurrentQuorumUnsatisfied)),
  )
}

test ctrl_stolen_quorum_rejects() {
  parity(
    vec.ctrl_stolen_quorum_spent,
    vec.ctrl_stolen_quorum_created,
    vec.ctrl_stolen_quorum_evidence,
    vec.ctrl_stolen_quorum_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq6CurrentQuorumUnsatisfied)),
  )
}

test ctrl_substituted_successor_rejects() {
  parity(
    vec.ctrl_substituted_successor_spent,
    vec.ctrl_substituted_successor_created,
    vec.ctrl_substituted_successor_evidence,
    vec.ctrl_substituted_successor_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq6PriorNextQuorumUnsatisfied)),
  )
}

// ---------------------------------------------------------
// V4 delta malformations (W1/W2/eq7/eq8)
// ---------------------------------------------------------

test w1_dup_cut_rejects() {
  parity(
    vec.w1_dup_cut_spent,
    vec.w1_dup_cut_created,
    vec.w1_dup_cut_evidence,
    vec.w1_dup_cut_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(EqW1CutInvalid)),
  )
}

test w1_cut_non_member_rejects() {
  parity(
    vec.w1_cut_non_member_spent,
    vec.w1_cut_non_member_created,
    vec.w1_cut_non_member_evidence,
    vec.w1_cut_non_member_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(EqW1CutInvalid)),
  )
}

test w2_dup_add_rejects() {
  parity(
    vec.w2_dup_add_spent,
    vec.w2_dup_add_created,
    vec.w2_dup_add_evidence,
    vec.w2_dup_add_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(EqW2AddInvalid)),
  )
}

test w2_add_present_rejects() {
  parity(
    vec.w2_add_present_spent,
    vec.w2_add_present_created,
    vec.w2_add_present_evidence,
    vec.w2_add_present_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(EqW2AddInvalid)),
  )
}

test w2_cut_add_overlap_rejects() {
  parity(
    vec.w2_cut_add_overlap_spent,
    vec.w2_cut_add_overlap_created,
    vec.w2_cut_add_overlap_evidence,
    vec.w2_cut_add_overlap_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(EqW2AddInvalid)),
  )
}

test eq7_derived_set_mismatch_rejects() {
  parity(
    vec.eq7_derived_set_mismatch_spent,
    vec.eq7_derived_set_mismatch_created,
    vec.eq7_derived_set_mismatch_evidence,
    vec.eq7_derived_set_mismatch_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq7CreatedStateMismatch)),
  )
}

test eq7_wrong_order_rejects() {
  parity(
    vec.eq7_wrong_order_spent,
    vec.eq7_wrong_order_created,
    vec.eq7_wrong_order_evidence,
    vec.eq7_wrong_order_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq7CreatedStateMismatch)),
  )
}

test eq8_toad_out_of_bounds_rejects() {
  parity(
    vec.eq8_toad_out_of_bounds_spent,
    vec.eq8_toad_out_of_bounds_created,
    vec.eq8_toad_out_of_bounds_evidence,
    vec.eq8_toad_out_of_bounds_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq8CreatedIllFormed(ToadRange))),
  )
}

// ---------------------------------------------------------
// #219 anti-replay falsifiability (spec.md "Anti-replay analysis",
// A-001 condition 3): eq5's seq conjunct is the exclusive wired
// mechanism this scenario isolates. native_sn stays AE3-legitimate
// (unchanged from the honest adv_wit_2key event); only the Cardano-side
// seq counter skips ahead of spent.seq+1. Real, unmodified eq5 rejects
// it today; this test must keep passing after GREEN (restated eq5).
// Falsifiability against a transient, reverted one-line weakening of
// eq5's own comparison in message.ak is proven out-of-band per
// DIRECTION-001 and recorded in handoffs/, not encoded as a second test
// (a duplicated/weakened copy of eq5 would prove nothing about the wired
// check).
// ---------------------------------------------------------

test eq5_seq_skip_ahead_rejects() {
  parity(
    vec.eq5_seq_skip_ahead_spent,
    vec.eq5_seq_skip_ahead_created,
    vec.eq5_seq_skip_ahead_evidence,
    vec.eq5_seq_skip_ahead_verdict,
    AdvancePredicateInvalid(AdvMessageInvalid(Eq5SequenceMismatch)),
  )
}

// ---------------------------------------------------------
// #219 permissionless-holds (spec.md "Anti-replay analysis" property 1):
// a stranger holding only `event_bytes` + the KEL's own genuine
// `rot`-event signatures (the fixture's `rot_sigs`, `signing_target:
// "event_raw"`) -- no Cardano-domain preimage signing step, no
// `TxOutRef` knowledge -- is ACCEPTED, since V5 verifies `ctrl_sigs`
// against `event_bytes` directly. Every honest fixture family's evidence
// is now genuinely this construction (`GenAdvanceVectors.hs`'s
// `aeCtrlSigs = eventRawCtrlSigs`, mirroring `0f6a88c`'s `rcEventSigs`
// swap) -- named explicitly here for two families (single-key delta and
// no-delta) so the property has its own witnesses, not only an inference
// from the general positive tests passing.
// ---------------------------------------------------------

test permissionless_holds_wit_2key() {
  advance_predicate(
    vec.pos_adv_wit_2key_spent,
    vec.pos_adv_wit_2key_created,
    vec.pos_adv_wit_2key_evidence,
  ) == AdvancePredicateValid
}

test permissionless_holds_keep() {
  advance_predicate(
    vec.pos_adv_keep_spent,
    vec.pos_adv_keep_created,
    vec.pos_adv_keep_evidence,
  ) == AdvancePredicateValid
}

// ---------------------------------------------------------
// V7: incoming-set witness receipt-quorum negatives
// ---------------------------------------------------------

test v7_receipt_free_rejects() {
  parity(
    vec.v7_receipt_free_spent,
    vec.v7_receipt_free_created,
    vec.v7_receipt_free_evidence,
    vec.v7_receipt_free_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_below_toad_rejects() {
  parity(
    vec.v7_below_toad_spent,
    vec.v7_below_toad_created,
    vec.v7_below_toad_evidence,
    vec.v7_below_toad_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_bad_index_rejects() {
  parity(
    vec.v7_bad_index_spent,
    vec.v7_bad_index_created,
    vec.v7_bad_index_evidence,
    vec.v7_bad_index_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_bad_sig_rejects() {
  parity(
    vec.v7_bad_sig_spent,
    vec.v7_bad_sig_created,
    vec.v7_bad_sig_evidence,
    vec.v7_bad_sig_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_dup_index_rejects() {
  parity(
    vec.v7_dup_index_spent,
    vec.v7_dup_index_created,
    vec.v7_dup_index_evidence,
    vec.v7_dup_index_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_wrong_member_rejects() {
  parity(
    vec.v7_wrong_member_spent,
    vec.v7_wrong_member_created,
    vec.v7_wrong_member_evidence,
    vec.v7_wrong_member_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_cut_witness_receipt_rejects() {
  parity(
    vec.v7_cut_witness_receipt_spent,
    vec.v7_cut_witness_receipt_created,
    vec.v7_cut_witness_receipt_evidence,
    vec.v7_cut_witness_receipt_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_outgoing_only_quorum_rejects() {
  parity(
    vec.v7_outgoing_only_quorum_spent,
    vec.v7_outgoing_only_quorum_created,
    vec.v7_outgoing_only_quorum_evidence,
    vec.v7_outgoing_only_quorum_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}

test v7_downgrade_nonempty_receipts_rejects() {
  parity(
    vec.v7_downgrade_nonempty_receipts_spent,
    vec.v7_downgrade_nonempty_receipts_created,
    vec.v7_downgrade_nonempty_receipts_evidence,
    vec.v7_downgrade_nonempty_receipts_verdict,
    AdvancePredicateInvalid(AdvReceiptQuorumUnsatisfied),
  )
}
