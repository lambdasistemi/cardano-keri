//// Registration verdict-parity + byte-parity tests (#114 S3).
////
//// Drives `registration_predicate` over the generated
//// `registration_vectors.ak` (the deployment context, genesis datum,
//// lovelace, evidence, and Haskell-computed verdict the S2
//// `RegistrationSpec` families build from the same committed keripy
//// `registration.json`) and asserts, per vector, that the Aiken predicate
//// returns the SAME verdict the vector records — verdict parity is the
//// acceptance bar, not just byte parity. Each test additionally pins the
//// expected constructor in-line (a third independent spelling next to the
//// S2 hspec and the generator's own assertion), so a generator bug cannot
//// silently weaken the suite. Byte-identity is asserted where bytes are
//// asserted: controller signatures and witness receipts over exact event
//// bytes, the R5 proof-token name, the E5/E7/E9
//// canonical kt/nt/bt re-spellings, and the E8 B-code witness qb64 —
//// each against a Haskell-emitted golden AND (for slices) the actual
//// event bytes at the generator-exported offsets. Includes the full
//// A-001 QB condition-1 offset-misdirection family (wrong offsets,
//// overlapping spans, spans into other fields, D/E/B code-prefix
//// confusion, truncated slices, negative offsets, duplicated offsets).

use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, ThresholdIllFormed}
use cardano_keri/checkpoint/registration.{
  DRegBelowMinimum, DeploymentContext, E1EventTypeMismatch, E2AidMismatch,
  E3SequenceMismatch, E4CurKeysMismatch, E5CurThresholdMismatch,
  E6NextKeysMismatch, E7NextThresholdMismatch, E8WitnessesMismatch,
  E9ToadMismatch, InceptionIllFormed, InceptionNativeSnNonZero,
  R3GenesisDatumMismatch, R4InceptionInvalid, R7QuorumUnsatisfied,
  R7WitnessQuorumUnsatisfied, R8DepositBelowMinimum, RegistrationEvidence,
  RegistrationInvalid, RegistrationValid, RegistrationVerdict, proof_token_name,
  qb64_witness_verkey, registration_deposit_floor, registration_predicate,
  respell_hex, respell_threshold, slice_matches, valid_registration_deposit,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/threshold.{
  DuplicateKey, Unweighted, Weight, Weighted,
}

// ---------------------------------------------------------
// Harness: parity + pinned-constructor check per vector
// ---------------------------------------------------------

/// The Aiken predicate must reproduce the vector's recorded (Haskell)
/// verdict, AND the recorded verdict must be the constructor this suite
/// pins for the scenario.
fn parity(
  ctx: DeploymentContext,
  d: CheckpointDatumV1,
  lovelace: Int,
  e: RegistrationEvidence,
  recorded: RegistrationVerdict,
  pinned: RegistrationVerdict,
) -> Bool {
  registration_predicate(ctx, d, lovelace, e) == recorded && recorded == pinned
}

// ---------------------------------------------------------
// Byte parity: event-own controller signatures and witness receipts
// ---------------------------------------------------------

test ctrl_sig_verifies_over_exact_event_bytes() {
  expect Some((idx, sig)) = list.head(vec.pos_witnessed_evidence.ctrl_sigs)
  expect Some(key) = list.at(vec.pos_witnessed_datum.cur_keys, idx)
  verify_ed25519_signature(key, vec.pos_witnessed_evidence.event_bytes, sig)
}

test witness_receipt_verifies_over_exact_event_bytes() {
  expect Some((idx, sig)) = list.head(vec.pos_witnessed_evidence.wit_receipts)
  expect Some(key) = list.at(vec.pos_witnessed_datum.witnesses, idx)
  verify_ed25519_signature(key, vec.pos_witnessed_evidence.event_bytes, sig)
}

// ---------------------------------------------------------
// Byte parity: the R5 proof-token name
// ---------------------------------------------------------

test proof_name_parity_witnessed() {
  let name = proof_token_name(
    vec.pos_witnessed_evidence.event_bytes,
    vec.pos_witnessed_datum.cesr_aid,
  )
  name == vec.witnessed_proof_name && bytearray.length(name) == 32
}

test proof_name_parity_weighted() {
  proof_token_name(
    vec.pos_weighted_evidence.event_bytes,
    vec.pos_weighted_datum.cesr_aid,
  ) == vec.weighted_proof_name
}

// The name binds the (bytes, aid) PAIR: crossing either changes it.
test proof_name_binds_pair() {
  let crossed = proof_token_name(
    vec.pos_witnessed_evidence.event_bytes,
    vec.pos_weighted_datum.cesr_aid,
  )
  crossed != vec.witnessed_proof_name && crossed != vec.weighted_proof_name
}

// ---------------------------------------------------------
// Byte parity: canonical kt/nt/bt re-spelling (E5/E7/E9)
// ---------------------------------------------------------

test respell_hex_parity() {
  list.all(
    vec.respell_hex_golden,
    fn(p) {
      let (n, expected) = p
      respell_hex(n) == expected
    },
  )
}

test respell_threshold_unweighted() {
  respell_threshold(Unweighted(2)) == "2"
}

test respell_threshold_unity_weight() {
  respell_threshold(Weighted([[Weight { num: 1, den: 1 }]])) == "[\"1\"]"
}

test respell_weighted_kt_parity() {
  let respelled = respell_threshold(vec.pos_weighted_datum.cur_threshold)
  let e = vec.pos_weighted_evidence
  respelled == vec.weighted_kt_respell && slice_matches(
    e.event_bytes,
    e.off_kt,
    respelled,
  )
}

// The witnessed fixture's kt/nt/bt slices ARE the re-spellings.
test respell_slices_witnessed() {
  let e = vec.pos_witnessed_evidence
  let d = vec.pos_witnessed_datum
  slice_matches(e.event_bytes, e.off_kt, respell_threshold(d.cur_threshold)) && slice_matches(
    e.event_bytes,
    e.off_nt,
    respell_threshold(d.next_threshold),
  ) && slice_matches(e.event_bytes, e.off_bt, respell_hex(d.toad))
}

// ---------------------------------------------------------
// Byte parity: the E8 B-code witness qb64
// ---------------------------------------------------------

test witness_qb64_parity() {
  list.all(
    vec.witnessed_witness_qb64,
    fn(p) {
      let (raw, qb64) = p
      qb64_witness_verkey(raw) == qb64 && bytearray.take(qb64, 1) == #"42"
    },
  )
}

fn all_witness_slices(
  bytes: ByteArray,
  offs: List<Int>,
  wits: List<ByteArray>,
) -> Bool {
  when offs is {
    [] -> wits == []
    [o, ..os] ->
      when wits is {
        [] -> False
        [w, ..ws] ->
          slice_matches(bytes, o, qb64_witness_verkey(w)) && all_witness_slices(
            bytes,
            os,
            ws,
          )
      }
  }
}

test witness_qb64_is_event_slice() {
  let e = vec.pos_witnessed_evidence
  all_witness_slices(e.event_bytes, e.off_b, vec.pos_witnessed_datum.witnesses)
}

// ---------------------------------------------------------
// Verdict parity: positives
// ---------------------------------------------------------

test d1_deployment_floor_boundaries_match_haskell() {
  registration_deposit_floor == vec.d_reg_floor && valid_registration_deposit(
    vec.d_reg_floor,
  ) && !valid_registration_deposit(vec.d_reg_below_floor)
}

test d1_deployment_below_floor_rejects() {
  parity(
    vec.d1_deployment_below_floor_ctx,
    vec.d1_deployment_below_floor_datum,
    vec.d1_deployment_below_floor_lovelace,
    vec.d1_deployment_below_floor_evidence,
    vec.d1_deployment_below_floor_verdict,
    RegistrationInvalid(DRegBelowMinimum),
  )
}

test pos_witnessed_accepts() {
  parity(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    vec.pos_witnessed_evidence,
    vec.pos_witnessed_verdict,
    RegistrationValid,
  )
}

test pos_weighted_accepts() {
  parity(
    vec.pos_weighted_ctx,
    vec.pos_weighted_datum,
    vec.pos_weighted_lovelace,
    vec.pos_weighted_evidence,
    vec.pos_weighted_verdict,
    RegistrationValid,
  )
}

// Owner replay: the same complete package re-validates identically.
test pos_owner_replay() {
  let first_run = registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    vec.pos_witnessed_evidence,
  )
  let second_run = registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    vec.pos_witnessed_evidence,
  )
  first_run == RegistrationValid && second_run == RegistrationValid
}

// Deposit boundary: exactly min_ada + d_reg passes.
test pos_deposit_boundary_accepts() {
  parity(
    vec.pos_deposit_boundary_ctx,
    vec.pos_deposit_boundary_datum,
    vec.pos_deposit_boundary_lovelace,
    vec.pos_deposit_boundary_evidence,
    vec.pos_deposit_boundary_verdict,
    RegistrationValid,
  )
}

// ---------------------------------------------------------
// Verdict parity: R3 genesis / R4 schema
// ---------------------------------------------------------

test r3_seq_nonzero_rejects() {
  parity(
    vec.r3_seq_nonzero_ctx,
    vec.r3_seq_nonzero_datum,
    vec.r3_seq_nonzero_lovelace,
    vec.r3_seq_nonzero_evidence,
    vec.r3_seq_nonzero_verdict,
    RegistrationInvalid(R3GenesisDatumMismatch),
  )
}

test r4_native_sn_nonzero_rejects() {
  parity(
    vec.r4_native_sn_nonzero_ctx,
    vec.r4_native_sn_nonzero_datum,
    vec.r4_native_sn_nonzero_lovelace,
    vec.r4_native_sn_nonzero_evidence,
    vec.r4_native_sn_nonzero_verdict,
    RegistrationInvalid(R4InceptionInvalid(InceptionNativeSnNonZero)),
  )
}

// ---------------------------------------------------------
// Verdict parity: per-slice E1-E9 negatives
// ---------------------------------------------------------

test e1_dip_rejects() {
  parity(
    vec.e1_dip_ctx,
    vec.e1_dip_datum,
    vec.e1_dip_lovelace,
    vec.e1_dip_evidence,
    vec.e1_dip_verdict,
    RegistrationInvalid(E1EventTypeMismatch),
  )
}

test e1_drt_rejects() {
  parity(
    vec.e1_drt_ctx,
    vec.e1_drt_datum,
    vec.e1_drt_lovelace,
    vec.e1_drt_evidence,
    vec.e1_drt_verdict,
    RegistrationInvalid(E1EventTypeMismatch),
  )
}

test e2_crossed_aid_rejects() {
  parity(
    vec.e2_crossed_aid_ctx,
    vec.e2_crossed_aid_datum,
    vec.e2_crossed_aid_lovelace,
    vec.e2_crossed_aid_evidence,
    vec.e2_crossed_aid_verdict,
    RegistrationInvalid(E2AidMismatch),
  )
}

test e3_off_s_at_t_rejects() {
  parity(
    vec.e3_off_s_at_t_ctx,
    vec.e3_off_s_at_t_datum,
    vec.e3_off_s_at_t_lovelace,
    vec.e3_off_s_at_t_evidence,
    vec.e3_off_s_at_t_verdict,
    RegistrationInvalid(E3SequenceMismatch),
  )
}

// The squat: attacker-keyed datum over the victim's genuine bytes.
test e4_squat_rejects() {
  parity(
    vec.e4_squat_ctx,
    vec.e4_squat_datum,
    vec.e4_squat_lovelace,
    vec.e4_squat_evidence,
    vec.e4_squat_verdict,
    RegistrationInvalid(E4CurKeysMismatch),
  )
}

test e5_kt_restated_rejects() {
  parity(
    vec.e5_kt_restated_ctx,
    vec.e5_kt_restated_datum,
    vec.e5_kt_restated_lovelace,
    vec.e5_kt_restated_evidence,
    vec.e5_kt_restated_verdict,
    RegistrationInvalid(E5CurThresholdMismatch),
  )
}

test e5_weighted_mutated_rejects() {
  parity(
    vec.e5_weighted_mutated_ctx,
    vec.e5_weighted_mutated_datum,
    vec.e5_weighted_mutated_lovelace,
    vec.e5_weighted_mutated_evidence,
    vec.e5_weighted_mutated_verdict,
    RegistrationInvalid(E5CurThresholdMismatch),
  )
}

test e6_next_flipped_rejects() {
  parity(
    vec.e6_next_flipped_ctx,
    vec.e6_next_flipped_datum,
    vec.e6_next_flipped_lovelace,
    vec.e6_next_flipped_evidence,
    vec.e6_next_flipped_verdict,
    RegistrationInvalid(E6NextKeysMismatch),
  )
}

test e7_nt_restated_rejects() {
  parity(
    vec.e7_nt_restated_ctx,
    vec.e7_nt_restated_datum,
    vec.e7_nt_restated_lovelace,
    vec.e7_nt_restated_evidence,
    vec.e7_nt_restated_verdict,
    RegistrationInvalid(E7NextThresholdMismatch),
  )
}

test e8_witness_flipped_rejects() {
  parity(
    vec.e8_witness_flipped_ctx,
    vec.e8_witness_flipped_datum,
    vec.e8_witness_flipped_lovelace,
    vec.e8_witness_flipped_evidence,
    vec.e8_witness_flipped_verdict,
    RegistrationInvalid(E8WitnessesMismatch),
  )
}

test e8_witness_count_rejects() {
  parity(
    vec.e8_witness_count_ctx,
    vec.e8_witness_count_datum,
    vec.e8_witness_count_lovelace,
    vec.e8_witness_count_evidence,
    vec.e8_witness_count_verdict,
    RegistrationInvalid(E8WitnessesMismatch),
  )
}

test e9_toad_restated_rejects() {
  parity(
    vec.e9_toad_restated_ctx,
    vec.e9_toad_restated_datum,
    vec.e9_toad_restated_lovelace,
    vec.e9_toad_restated_evidence,
    vec.e9_toad_restated_verdict,
    RegistrationInvalid(E9ToadMismatch),
  )
}

// ---------------------------------------------------------
// Verdict parity: R7 signature negatives
// ---------------------------------------------------------

const witnessed_receipt_0: ByteArray =
  #"36784a60e6e13b49c8934684165191c141874f88c1838be882775be595b63cbffbde39404a71b414f66796eb6bfc4359b45cc09a57b3edefad449d04b92e0208"

const witnessed_receipt_2: ByteArray =
  #"634b84d49b459055f1839ba3e7b6d3c6b274ef0e50ffad7e4ed870b601fe692e06886c1aad66bdf7d1cd03342ba786548eac6e7a48c335eb287a8a4c684aed0e"

fn event_own_witnessed_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    ..vec.pos_witnessed_evidence,
    wit_receipts: [(0, witnessed_receipt_0), (2, witnessed_receipt_2)],
  }
}

// The bundle's own KERI signatures authenticate the exact inception event,
// with its indexed witness receipts satisfying toad=2.
test r7_event_own_controller_sigs_accept() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    event_own_witnessed_evidence(),
  ) == RegistrationValid
}

test r7_old_inception_message_only_sigs_reject() {
  registration_predicate(
    vec.r7_old_message_sigs_ctx,
    vec.r7_old_message_sigs_datum,
    vec.r7_old_message_sigs_lovelace,
    vec.r7_old_message_sigs_evidence,
  ) == RegistrationInvalid(R7QuorumUnsatisfied)
}

test r7_controller_negative_index_rejects() {
  expect [(_, sig0), sig1] = event_own_witnessed_evidence().ctrl_sigs
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      ctrl_sigs: [(-1, sig0), sig1],
    },
  ) == RegistrationInvalid(R7QuorumUnsatisfied)
}

test r7_controller_out_of_range_index_rejects() {
  expect [(_, sig0), sig1] = event_own_witnessed_evidence().ctrl_sigs
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      ctrl_sigs: [(99, sig0), sig1],
    },
  ) == RegistrationInvalid(R7QuorumUnsatisfied)
}

test r7_controller_bad_signature_rejects() {
  expect [(idx0, sig0), sig1] = event_own_witnessed_evidence().ctrl_sigs
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      ctrl_sigs: [(idx0, bytearray.push(bytearray.drop(sig0, 1), 255)), sig1],
    },
  ) == RegistrationInvalid(R7QuorumUnsatisfied)
}

test r7_controller_crossed_event_bytes_rejects() {
  let e = event_own_witnessed_evidence()
  let n = bytearray.length(e.event_bytes)
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..e,
      event_bytes: bytearray.concat(bytearray.take(e.event_bytes, n - 1), #"00"),
    },
  ) == RegistrationInvalid(R7QuorumUnsatisfied)
}

test r7_witness_receipt_free_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence { ..event_own_witnessed_evidence(), wit_receipts: [] },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_witness_below_toad_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      wit_receipts: [(0, witnessed_receipt_0)],
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_witness_duplicate_index_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      wit_receipts: [(0, witnessed_receipt_0), (0, witnessed_receipt_0)],
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_witness_negative_index_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      wit_receipts: [(-1, witnessed_receipt_0), (2, witnessed_receipt_2)],
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_witness_out_of_range_index_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      wit_receipts: [(99, witnessed_receipt_0), (2, witnessed_receipt_2)],
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_witness_wrong_key_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      wit_receipts: event_own_witnessed_evidence().ctrl_sigs,
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_witness_bad_signature_rejects() {
  registration_predicate(
    vec.pos_witnessed_ctx,
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    RegistrationEvidence {
      ..event_own_witnessed_evidence(),
      wit_receipts: [
        (0, bytearray.push(bytearray.drop(witnessed_receipt_0, 1), 255)),
        (2, witnessed_receipt_2),
      ],
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_toad_zero_requires_literal_empty_receipts() {
  registration_predicate(
    vec.pos_2key_ctx,
    vec.pos_2key_datum,
    vec.pos_2key_lovelace,
    RegistrationEvidence {
      ..vec.pos_2key_evidence,
      wit_receipts: [
        (
          0,
          #"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        ),
      ],
    },
  ) == RegistrationInvalid(R7WitnessQuorumUnsatisfied)
}

test r7_below_threshold_rejects() {
  parity(
    vec.r7_below_threshold_ctx,
    vec.r7_below_threshold_datum,
    vec.r7_below_threshold_lovelace,
    vec.r7_below_threshold_evidence,
    vec.r7_below_threshold_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  )
}

test r7_below_weighted_rejects() {
  parity(
    vec.r7_below_weighted_ctx,
    vec.r7_below_weighted_datum,
    vec.r7_below_weighted_lovelace,
    vec.r7_below_weighted_evidence,
    vec.r7_below_weighted_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  )
}

test r7_dup_index_rejects() {
  parity(
    vec.r7_dup_index_ctx,
    vec.r7_dup_index_datum,
    vec.r7_dup_index_lovelace,
    vec.r7_dup_index_evidence,
    vec.r7_dup_index_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  )
}

test r7_wrong_controller_keys_rejects() {
  parity(
    vec.r7_wrong_controller_keys_ctx,
    vec.r7_wrong_controller_keys_datum,
    vec.r7_wrong_controller_keys_lovelace,
    vec.r7_wrong_controller_keys_evidence,
    vec.r7_wrong_controller_keys_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  )
}

test r7_crossed_event_bytes_rejects_vector() {
  parity(
    vec.r7_crossed_event_bytes_ctx,
    vec.r7_crossed_event_bytes_datum,
    vec.r7_crossed_event_bytes_lovelace,
    vec.r7_crossed_event_bytes_evidence,
    vec.r7_crossed_event_bytes_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  )
}

test r7_generated_controller_index_signature_matrix_matches_haskell() {
  parity(
    vec.r7_negative_index_ctx,
    vec.r7_negative_index_datum,
    vec.r7_negative_index_lovelace,
    vec.r7_negative_index_evidence,
    vec.r7_negative_index_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  ) && parity(
    vec.r7_oob_index_ctx,
    vec.r7_oob_index_datum,
    vec.r7_oob_index_lovelace,
    vec.r7_oob_index_evidence,
    vec.r7_oob_index_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  ) && parity(
    vec.r7_bad_signature_ctx,
    vec.r7_bad_signature_datum,
    vec.r7_bad_signature_lovelace,
    vec.r7_bad_signature_evidence,
    vec.r7_bad_signature_verdict,
    RegistrationInvalid(R7QuorumUnsatisfied),
  )
}

test r7_generated_witness_receipt_matrix_matches_haskell() {
  parity(
    vec.r7_receipts_empty_ctx,
    vec.r7_receipts_empty_datum,
    vec.r7_receipts_empty_lovelace,
    vec.r7_receipts_empty_evidence,
    vec.r7_receipts_empty_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_receipts_below_toad_ctx,
    vec.r7_receipts_below_toad_datum,
    vec.r7_receipts_below_toad_lovelace,
    vec.r7_receipts_below_toad_evidence,
    vec.r7_receipts_below_toad_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_receipts_dup_index_ctx,
    vec.r7_receipts_dup_index_datum,
    vec.r7_receipts_dup_index_lovelace,
    vec.r7_receipts_dup_index_evidence,
    vec.r7_receipts_dup_index_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_receipts_negative_index_ctx,
    vec.r7_receipts_negative_index_datum,
    vec.r7_receipts_negative_index_lovelace,
    vec.r7_receipts_negative_index_evidence,
    vec.r7_receipts_negative_index_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_receipts_oob_index_ctx,
    vec.r7_receipts_oob_index_datum,
    vec.r7_receipts_oob_index_lovelace,
    vec.r7_receipts_oob_index_evidence,
    vec.r7_receipts_oob_index_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_receipts_wrong_keys_ctx,
    vec.r7_receipts_wrong_keys_datum,
    vec.r7_receipts_wrong_keys_lovelace,
    vec.r7_receipts_wrong_keys_evidence,
    vec.r7_receipts_wrong_keys_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_receipts_bad_signature_ctx,
    vec.r7_receipts_bad_signature_datum,
    vec.r7_receipts_bad_signature_lovelace,
    vec.r7_receipts_bad_signature_evidence,
    vec.r7_receipts_bad_signature_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  ) && parity(
    vec.r7_zero_toad_nonempty_ctx,
    vec.r7_zero_toad_nonempty_datum,
    vec.r7_zero_toad_nonempty_lovelace,
    vec.r7_zero_toad_nonempty_evidence,
    vec.r7_zero_toad_nonempty_verdict,
    RegistrationInvalid(R7WitnessQuorumUnsatisfied),
  )
}

// ---------------------------------------------------------
// Verdict parity: R8 deposit floor
// ---------------------------------------------------------

test r8_deposit_short_rejects() {
  parity(
    vec.r8_deposit_short_ctx,
    vec.r8_deposit_short_datum,
    vec.r8_deposit_short_lovelace,
    vec.r8_deposit_short_evidence,
    vec.r8_deposit_short_verdict,
    RegistrationInvalid(R8DepositBelowMinimum),
  )
}

// ---------------------------------------------------------
// Verdict parity: the A-001 offset-misdirection family
// ---------------------------------------------------------

test mis_off_i_shift_rejects() {
  parity(
    vec.mis_off_i_shift_ctx,
    vec.mis_off_i_shift_datum,
    vec.mis_off_i_shift_lovelace,
    vec.mis_off_i_shift_evidence,
    vec.mis_off_i_shift_verdict,
    RegistrationInvalid(E2AidMismatch),
  )
}

test mis_overlap_k_rejects() {
  parity(
    vec.mis_overlap_k_ctx,
    vec.mis_overlap_k_datum,
    vec.mis_overlap_k_lovelace,
    vec.mis_overlap_k_evidence,
    vec.mis_overlap_k_verdict,
    RegistrationInvalid(E4CurKeysMismatch),
  )
}

// D-code expected bytes vs E-code n entries: prefix confusion fails.
test mis_k_into_n_rejects() {
  parity(
    vec.mis_k_into_n_ctx,
    vec.mis_k_into_n_datum,
    vec.mis_k_into_n_lovelace,
    vec.mis_k_into_n_evidence,
    vec.mis_k_into_n_verdict,
    RegistrationInvalid(E4CurKeysMismatch),
  )
}

// D-code expected bytes vs B-code b entries: prefix confusion fails.
test mis_k_into_b_rejects() {
  parity(
    vec.mis_k_into_b_ctx,
    vec.mis_k_into_b_datum,
    vec.mis_k_into_b_lovelace,
    vec.mis_k_into_b_evidence,
    vec.mis_k_into_b_verdict,
    RegistrationInvalid(E4CurKeysMismatch),
  )
}

// E-code expected bytes vs a D-code k entry: prefix confusion fails.
test mis_i_at_k_rejects() {
  parity(
    vec.mis_i_at_k_ctx,
    vec.mis_i_at_k_datum,
    vec.mis_i_at_k_lovelace,
    vec.mis_i_at_k_evidence,
    vec.mis_i_at_k_verdict,
    RegistrationInvalid(E2AidMismatch),
  )
}

// B-code expected bytes vs D-code k entries: prefix confusion fails.
test mis_b_at_k_rejects() {
  parity(
    vec.mis_b_at_k_ctx,
    vec.mis_b_at_k_datum,
    vec.mis_b_at_k_lovelace,
    vec.mis_b_at_k_evidence,
    vec.mis_b_at_k_verdict,
    RegistrationInvalid(E8WitnessesMismatch),
  )
}

test mis_trunc_i_rejects() {
  parity(
    vec.mis_trunc_i_ctx,
    vec.mis_trunc_i_datum,
    vec.mis_trunc_i_lovelace,
    vec.mis_trunc_i_evidence,
    vec.mis_trunc_i_verdict,
    RegistrationInvalid(E2AidMismatch),
  )
}

test mis_trunc_k_rejects() {
  parity(
    vec.mis_trunc_k_ctx,
    vec.mis_trunc_k_datum,
    vec.mis_trunc_k_lovelace,
    vec.mis_trunc_k_evidence,
    vec.mis_trunc_k_verdict,
    RegistrationInvalid(E4CurKeysMismatch),
  )
}

test mis_neg_i_rejects() {
  parity(
    vec.mis_neg_i_ctx,
    vec.mis_neg_i_datum,
    vec.mis_neg_i_lovelace,
    vec.mis_neg_i_evidence,
    vec.mis_neg_i_verdict,
    RegistrationInvalid(E2AidMismatch),
  )
}

// Duplicated offsets force a duplicate datum key: slips past E4 only to
// fail R4's F18 rule 2 (the A-001 misdirection collapse argument).
test mis_dup_k_rejects() {
  parity(
    vec.mis_dup_k_ctx,
    vec.mis_dup_k_datum,
    vec.mis_dup_k_lovelace,
    vec.mis_dup_k_evidence,
    vec.mis_dup_k_verdict,
    RegistrationInvalid(
      R4InceptionInvalid(InceptionIllFormed(ThresholdIllFormed(DuplicateKey))),
    ),
  )
}
