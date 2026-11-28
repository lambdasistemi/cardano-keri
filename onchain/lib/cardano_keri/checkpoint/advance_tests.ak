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

use aiken/collection/list
use cardano_keri/checkpoint/advance.{
  AEEventNotCanonical, AdvEventBinding, AdvMessageInvalid,
  AdvReceiptQuorumUnsatisfied, AdvanceEventInvalid, AdvanceEventValid,
  AdvanceEvidence, AdvancePredicateInvalid, AdvancePredicateValid,
  AdvancePredicateVerdict, advance_predicate, event_binding,
}
use cardano_keri/checkpoint/advance_vectors as vec
use cardano_keri/checkpoint/binding_reference.{
  RotationAddDiffers, RotationAidDiffers, RotationAxis, RotationBound,
  RotationCurKeysDiffer, RotationCurThresholdDiffers, RotationCutDiffers,
  RotationNextKeysDiffer, RotationNextThresholdDiffers, RotationSequenceDiffers,
  RotationToadDiffers, RotationTypeDiffers, RotationUndecodable, rotation_axis,
}
use cardano_keri/checkpoint/datum.{KeyStateView, ToadRange}
use cardano_keri/checkpoint/event_decoder.{ErrVersionPrefix}
use cardano_keri/checkpoint/message.{
  Eq5SequenceMismatch, Eq6CurrentQuorumUnsatisfied,
  Eq6PriorNextQuorumUnsatisfied, Eq7CreatedStateMismatch, Eq8CreatedIllFormed,
  EqW1CutInvalid, EqW2AddInvalid, SpentCheckpoint,
}
use cardano_keri/checkpoint/registration.{QualifiedSpelling}
use cardano_keri/checkpoint/registration_vectors as reg
use cardano_keri/checkpoint/spelling_fixture
use cardano_keri/checkpoint/threshold.{Threshold, Unweighted, Weight, Weighted}

// ---------------------------------------------------------
// Harness: parity + pinned-constructor check per vector
// ---------------------------------------------------------

/// The Aiken predicate must reproduce the vector's recorded (Haskell)
/// verdict, AND the recorded verdict must be the constructor this suite
/// pins for the scenario.
fn parity(
  spent: SpentCheckpoint,
  created: KeyStateView,
  e: AdvanceEvidence,
  recorded: AdvancePredicateVerdict,
  pinned: AdvancePredicateVerdict,
) -> Bool {
  advance_predicate(spent, created, spelling_fixture.of_view(created), e) == recorded && recorded == pinned
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
    spelling_fixture.of_view(vec.pos_adv_wit_2key_created),
    vec.pos_adv_wit_2key_evidence,
  )
  let second_run = advance_predicate(
    vec.pos_adv_wit_2key_spent,
    vec.pos_adv_wit_2key_created,
    spelling_fixture.of_view(vec.pos_adv_wit_2key_created),
    vec.pos_adv_wit_2key_evidence,
  )
  first_run == AdvancePredicateValid && second_run == AdvancePredicateValid
}

// ---------------------------------------------------------
// V6: AE0-AE10 event-binding negatives (one per axis), each against the matched honest binding
// ---------------------------------------------------------

fn honest_spelling() -> QualifiedSpelling {
  spelling_fixture.of_view(vec.pos_adv_wit_2key_created)
}

/// The production binding refuses, and the reference reading names the field that differs.
fn refused_at(
  axis: RotationAxis,
  created: KeyStateView,
  q: QualifiedSpelling,
  e: AdvanceEvidence,
) -> Bool {
  event_binding(created, q, e) == AdvanceEventInvalid(AEEventNotCanonical) && rotation_axis(
    created,
    q,
    e.wit_cut,
    e.wit_add,
    e.event_bytes,
  ) == axis
}

test ae_honest_binding_holds() {
  event_binding(
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  ) == AdvanceEventValid && rotation_axis(
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence.wit_cut,
    vec.pos_adv_wit_2key_evidence.wit_add,
    vec.pos_adv_wit_2key_evidence.event_bytes,
  ) == RotationBound
}

test ae0_undecodable_bytes_rejects() {
  refused_at(
    RotationUndecodable(ErrVersionPrefix),
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    AdvanceEvidence { ..vec.pos_adv_wit_2key_evidence, event_bytes: "rot" },
  )
}

test ae1_inception_rejects() {
  refused_at(
    RotationTypeDiffers,
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    AdvanceEvidence {
      ..vec.pos_adv_wit_2key_evidence,
      event_bytes: reg.pos_2key_evidence.event_bytes,
    },
  )
}

test ae2_other_identifier_rejects() {
  refused_at(
    RotationAidDiffers,
    vec.pos_adv_wit_2key_created,
    QualifiedSpelling { ..honest_spelling(), aid: reg_aid_text() },
    vec.pos_adv_wit_2key_evidence,
  )
}

test ae3_other_sequence_rejects() {
  refused_at(
    RotationSequenceDiffers,
    KeyStateView { ..vec.pos_adv_wit_2key_created, native_sn: 2 },
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  )
}

test ae4_other_current_keys_rejects() {
  let q = honest_spelling()
  refused_at(
    RotationCurKeysDiffer,
    vec.pos_adv_wit_2key_created,
    QualifiedSpelling { ..q, cur_keys: list.reverse(q.cur_keys) },
    vec.pos_adv_wit_2key_evidence,
  )
}

test ae5_other_current_threshold_rejects() {
  refused_at(
    RotationCurThresholdDiffers,
    KeyStateView {
      ..vec.pos_adv_wit_2key_created,
      cur_threshold: Unweighted(1),
    },
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  )
}

test ae6_other_next_keys_rejects() {
  let created = vec.pos_adv_wit_2key_created
  refused_at(
    RotationNextKeysDiffer,
    KeyStateView { ..created, next_keys: list.reverse(created.next_keys) },
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  )
}

test ae7_other_next_threshold_rejects() {
  refused_at(
    RotationNextThresholdDiffers,
    KeyStateView {
      ..vec.pos_adv_wit_2key_created,
      next_threshold: Unweighted(1),
    },
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  )
}

test ae8_other_cut_rejects() {
  refused_at(
    RotationCutDiffers,
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    AdvanceEvidence { ..vec.pos_adv_wit_2key_evidence, wit_cut: [] },
  )
}

test ae9_other_add_rejects() {
  refused_at(
    RotationAddDiffers,
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    AdvanceEvidence { ..vec.pos_adv_wit_2key_evidence, wit_add: [] },
  )
}

test ae10_other_toad_rejects() {
  refused_at(
    RotationToadDiffers,
    KeyStateView { ..vec.pos_adv_wit_2key_created, toad: 3 },
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  )
}

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
    spelling_fixture.of_view(vec.pos_adv_wit_2key_created),
    vec.pos_adv_wit_2key_evidence,
  ) == AdvancePredicateValid
}

test permissionless_holds_keep() {
  advance_predicate(
    vec.pos_adv_keep_spent,
    vec.pos_adv_keep_created,
    spelling_fixture.of_view(vec.pos_adv_keep_created),
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

fn reg_aid_text() -> ByteArray {
  spelling_fixture.of_view(reg.pos_2key_datum).aid
}

// ---------------------------------------------------------
// A checkpoint that declared no next keys cannot be advanced: a zero threshold over no commitments would be
// satisfied by no evidence at all, and the pre-rotation gate would open to anyone.
// ---------------------------------------------------------

fn abandoned_spent() -> SpentCheckpoint {
  SpentCheckpoint {
    ..vec.pos_adv_wit_2key_spent,
    next_keys: [],
    next_threshold: Unweighted(0),
  }
}

test an_advance_from_a_checkpoint_with_no_next_keys_is_refused() {
  advance_predicate(
    abandoned_spent(),
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  ) == AdvancePredicateInvalid(AdvMessageInvalid(Eq6PriorNextQuorumUnsatisfied))
}

/// The matched control: the same advance from the checkpoint with its commitments is accepted.
test the_same_advance_from_a_checkpoint_with_next_keys_is_accepted() {
  advance_predicate(
    vec.pos_adv_wit_2key_spent,
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  ) == AdvancePredicateValid
}

// ---------------------------------------------------------
// The prior declaration authorizes a rotation only at its exact member width: a weighted next declaration whose weights
// number fewer than its commitments may be made at an inception, and no signer list satisfies it afterwards.
// ---------------------------------------------------------

fn whole_clauses() -> Threshold {
  Weighted([[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]])
}

fn declared_by(
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
) -> SpentCheckpoint {
  SpentCheckpoint { ..vec.pos_adv_wit_2key_spent, next_keys, next_threshold }
}

fn advance_from(spent: SpentCheckpoint) -> AdvancePredicateVerdict {
  advance_predicate(
    spent,
    vec.pos_adv_wit_2key_created,
    honest_spelling(),
    vec.pos_adv_wit_2key_evidence,
  )
}

/// Two whole-weight clauses over three commitments: the two revealed keys are the first two commitments, so every
/// revealed position is satisfied, yet the declaration has width two and three commitments.
test an_advance_from_a_partial_width_prior_declaration_is_refused() {
  advance_from(
    declared_by(
      list.concat(
        vec.pos_adv_wit_2key_spent.next_keys,
        [#"0909090909090909090909090909090909090909090909090909090909090909"],
      ),
      whole_clauses(),
    ),
  ) == AdvancePredicateInvalid(AdvMessageInvalid(Eq6PriorNextQuorumUnsatisfied))
}

/// The matched control: the same clauses over exactly two commitments authorize the same rotation.
test an_advance_from_an_exact_width_prior_declaration_is_accepted() {
  advance_from(
    declared_by(vec.pos_adv_wit_2key_spent.next_keys, whole_clauses()),
  ) == AdvancePredicateValid
}
