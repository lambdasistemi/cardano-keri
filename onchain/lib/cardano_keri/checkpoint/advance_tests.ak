//// Advance verdict-parity + byte-parity tests (#115 S5).
////
//// Drives `advance_predicate` over the generated `advance_vectors.ak`
//// (the spent context, created/successor datum, evidence, and
//// Haskell-computed verdict the S4 `AdvanceSpec` families build from the
//// same committed keripy `advance.json`) and asserts, per vector, that
//// the Aiken predicate returns the SAME verdict the vector records —
//// verdict parity is the acceptance bar, not just byte parity. Each test
//// additionally pins the expected constructor in-line (a third
//// independent spelling next to the S4 hspec and the generator's own
//// assertion), so a generator bug cannot silently weaken the suite.
////
//// Covers: the four honest fixture families (`adv_wit_2key`,
//// `adv_wit_7key`, `adv_keep`, `adv_downgrade`); one executable rejection
//// per AE1-AE10 axis; the A-001 offset-misdirection family (spans into
//// `a`/`p`/`d`, cross-field/code confusion, truncated/negative/duplicated/
//// shortened/emptied offsets); controller-evidence negatives (bad index,
//// wrong preimage, below threshold, stolen current quorum, substituted
//// successor); W1/W2/eq7/eq8 delta malformations (dup cut/add, cut of a
//// non-member, add-already-present, cut/add overlap, derived-set
//// mismatch, wrong survivor order, toad out of bounds); and V7
//// receipt-quorum negatives (receipt-free, below-toad, bad/out-of-range
//// index, bad signature, duplicate index, wrong-member index, cut-witness
//// receipt, outgoing-only quorum, non-empty receipts at toad=0). Byte
//// parity is asserted for the four honest families' reconstructed
//// `AdvanceMessage` canonical-CBOR preimage (the V5 controller-signature
//// target).

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use cardano_keri/checkpoint/advance.{
  AE10ToadMismatch, AE1EventTypeMismatch, AE2AidMismatch, AE3SequenceMismatch,
  AE4CurKeysMismatch, AE5CurThresholdMismatch, AE6NextKeysMismatch,
  AE7NextThresholdMismatch, AE8WitCutMismatch, AE9WitAddMismatch,
  AdvEventBinding, AdvMessageInvalid, AdvReceiptQuorumUnsatisfied,
  AdvanceEvidence, AdvancePredicateInvalid, AdvancePredicateValid,
  AdvancePredicateVerdict, advance_predicate, reconstruct_advance_message,
}
use cardano_keri/checkpoint/advance_vectors as vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, ToadRange}
use cardano_keri/checkpoint/message.{
  Eq6CurrentQuorumUnsatisfied, Eq6PriorNextQuorumUnsatisfied,
  Eq7CreatedStateMismatch, Eq8CreatedIllFormed, EqW1CutInvalid, EqW2AddInvalid,
  SpentCheckpoint,
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
// Byte parity: the reconstructed message preimage (V5 target)
// ---------------------------------------------------------

test preimage_parity_adv_wit_2key() {
  cbor.serialise(
    reconstruct_advance_message(
      vec.pos_adv_wit_2key_spent,
      vec.pos_adv_wit_2key_created,
      vec.pos_adv_wit_2key_evidence.wit_cut,
      vec.pos_adv_wit_2key_evidence.wit_add,
    ),
  ) == vec.pos_adv_wit_2key_preimage
}

test preimage_parity_adv_wit_7key() {
  cbor.serialise(
    reconstruct_advance_message(
      vec.pos_adv_wit_7key_spent,
      vec.pos_adv_wit_7key_created,
      vec.pos_adv_wit_7key_evidence.wit_cut,
      vec.pos_adv_wit_7key_evidence.wit_add,
    ),
  ) == vec.pos_adv_wit_7key_preimage
}

test preimage_parity_adv_keep() {
  cbor.serialise(
    reconstruct_advance_message(
      vec.pos_adv_keep_spent,
      vec.pos_adv_keep_created,
      vec.pos_adv_keep_evidence.wit_cut,
      vec.pos_adv_keep_evidence.wit_add,
    ),
  ) == vec.pos_adv_keep_preimage
}

test preimage_parity_adv_downgrade() {
  cbor.serialise(
    reconstruct_advance_message(
      vec.pos_adv_downgrade_spent,
      vec.pos_adv_downgrade_created,
      vec.pos_adv_downgrade_evidence.wit_cut,
      vec.pos_adv_downgrade_evidence.wit_add,
    ),
  ) == vec.pos_adv_downgrade_preimage
}

// A committed ctrl signature verifies over the Aiken-recomputed preimage:
// the two languages agree on the exact signature target bytes.
test ctrl_sig_verifies_over_preimage() {
  let preimage = cbor.serialise(
    reconstruct_advance_message(
      vec.pos_adv_wit_2key_spent,
      vec.pos_adv_wit_2key_created,
      vec.pos_adv_wit_2key_evidence.wit_cut,
      vec.pos_adv_wit_2key_evidence.wit_add,
    ),
  )
  expect Some((idx, sig)) = list.head(vec.pos_adv_wit_2key_evidence.ctrl_sigs)
  expect Some(key) = list.at(vec.pos_adv_wit_2key_created.cur_keys, idx)
  verify_ed25519_signature(key, preimage, sig)
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

test ae1_off_t_at_i_rejects() {
  parity(
    vec.ae1_off_t_at_i_spent,
    vec.ae1_off_t_at_i_created,
    vec.ae1_off_t_at_i_evidence,
    vec.ae1_off_t_at_i_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE1EventTypeMismatch)),
  )
}

test ae2_off_i_shift_rejects() {
  parity(
    vec.ae2_off_i_shift_spent,
    vec.ae2_off_i_shift_created,
    vec.ae2_off_i_shift_evidence,
    vec.ae2_off_i_shift_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE2AidMismatch)),
  )
}

test ae3_off_s_at_t_rejects() {
  parity(
    vec.ae3_off_s_at_t_spent,
    vec.ae3_off_s_at_t_created,
    vec.ae3_off_s_at_t_evidence,
    vec.ae3_off_s_at_t_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE3SequenceMismatch)),
  )
}

test ae4_overlap_k_rejects() {
  parity(
    vec.ae4_overlap_k_spent,
    vec.ae4_overlap_k_created,
    vec.ae4_overlap_k_evidence,
    vec.ae4_overlap_k_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE4CurKeysMismatch)),
  )
}

test ae5_off_kt_at_bt_rejects() {
  parity(
    vec.ae5_off_kt_at_bt_spent,
    vec.ae5_off_kt_at_bt_created,
    vec.ae5_off_kt_at_bt_evidence,
    vec.ae5_off_kt_at_bt_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE5CurThresholdMismatch)),
  )
}

test ae6_off_n_at_k_rejects() {
  parity(
    vec.ae6_off_n_at_k_spent,
    vec.ae6_off_n_at_k_created,
    vec.ae6_off_n_at_k_evidence,
    vec.ae6_off_n_at_k_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE6NextKeysMismatch)),
  )
}

test ae7_off_nt_at_kt_rejects() {
  parity(
    vec.ae7_off_nt_at_kt_spent,
    vec.ae7_off_nt_at_kt_created,
    vec.ae7_off_nt_at_kt_evidence,
    vec.ae7_off_nt_at_kt_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE7NextThresholdMismatch)),
  )
}

test ae8_off_br_at_ba_rejects() {
  parity(
    vec.ae8_off_br_at_ba_spent,
    vec.ae8_off_br_at_ba_created,
    vec.ae8_off_br_at_ba_evidence,
    vec.ae8_off_br_at_ba_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE8WitCutMismatch)),
  )
}

test ae9_off_ba_at_br_rejects() {
  parity(
    vec.ae9_off_ba_at_br_spent,
    vec.ae9_off_ba_at_br_created,
    vec.ae9_off_ba_at_br_evidence,
    vec.ae9_off_ba_at_br_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE9WitAddMismatch)),
  )
}

test ae10_off_bt_at_kt_rejects() {
  parity(
    vec.ae10_off_bt_at_kt_spent,
    vec.ae10_off_bt_at_kt_created,
    vec.ae10_off_bt_at_kt_evidence,
    vec.ae10_off_bt_at_kt_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE10ToadMismatch)),
  )
}

// ---------------------------------------------------------
// A-001 condition 1: the offset-misdirection family
// ---------------------------------------------------------

test mis_trunc_i_rejects() {
  parity(
    vec.mis_trunc_i_spent,
    vec.mis_trunc_i_created,
    vec.mis_trunc_i_evidence,
    vec.mis_trunc_i_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE2AidMismatch)),
  )
}

test mis_neg_i_rejects() {
  parity(
    vec.mis_neg_i_spent,
    vec.mis_neg_i_created,
    vec.mis_neg_i_evidence,
    vec.mis_neg_i_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE2AidMismatch)),
  )
}

test mis_dup_k_rejects() {
  parity(
    vec.mis_dup_k_spent,
    vec.mis_dup_k_created,
    vec.mis_dup_k_evidence,
    vec.mis_dup_k_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE4CurKeysMismatch)),
  )
}

test mis_br_into_k_rejects() {
  parity(
    vec.mis_br_into_k_spent,
    vec.mis_br_into_k_created,
    vec.mis_br_into_k_evidence,
    vec.mis_br_into_k_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE8WitCutMismatch)),
  )
}

test mis_short_k_rejects() {
  parity(
    vec.mis_short_k_spent,
    vec.mis_short_k_created,
    vec.mis_short_k_evidence,
    vec.mis_short_k_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE4CurKeysMismatch)),
  )
}

test mis_short_n_rejects() {
  parity(
    vec.mis_short_n_spent,
    vec.mis_short_n_created,
    vec.mis_short_n_evidence,
    vec.mis_short_n_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE6NextKeysMismatch)),
  )
}

test mis_empty_br_rejects() {
  parity(
    vec.mis_empty_br_spent,
    vec.mis_empty_br_created,
    vec.mis_empty_br_evidence,
    vec.mis_empty_br_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE8WitCutMismatch)),
  )
}

test mis_empty_ba_rejects() {
  parity(
    vec.mis_empty_ba_spent,
    vec.mis_empty_ba_created,
    vec.mis_empty_ba_evidence,
    vec.mis_empty_ba_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE9WitAddMismatch)),
  )
}

test mis_t_into_p_rejects() {
  parity(
    vec.mis_t_into_p_spent,
    vec.mis_t_into_p_created,
    vec.mis_t_into_p_evidence,
    vec.mis_t_into_p_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE1EventTypeMismatch)),
  )
}

test mis_kt_into_d_rejects() {
  parity(
    vec.mis_kt_into_d_spent,
    vec.mis_kt_into_d_created,
    vec.mis_kt_into_d_evidence,
    vec.mis_kt_into_d_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE5CurThresholdMismatch)),
  )
}

test mis_bt_into_a_rejects() {
  parity(
    vec.mis_bt_into_a_spent,
    vec.mis_bt_into_a_created,
    vec.mis_bt_into_a_evidence,
    vec.mis_bt_into_a_verdict,
    AdvancePredicateInvalid(AdvEventBinding(AE10ToadMismatch)),
  )
}

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

test ctrl_wrong_preimage_rejects() {
  parity(
    vec.ctrl_wrong_preimage_spent,
    vec.ctrl_wrong_preimage_created,
    vec.ctrl_wrong_preimage_evidence,
    vec.ctrl_wrong_preimage_verdict,
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
