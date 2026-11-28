//// The booking attestation policy over the weighted next declarations of the local chain run, as exported: an exact
//// one (two commitments, one clause of `1/2 + 1/2`), one with unreduced weights (`2/4 + 2/4`) and one whose clauses do
//// not partition the commitments (three commitments, two clauses of one whole weight). The signed bodies, the indexed
//// controller signatures, the clause boundaries and the order of the commitments are the exports' own; the datum
//// declares the same weights as the body spells them.

use aiken/crypto as aiken_crypto
use booking_attestation
use booking_attestation_fixture.{
  attestation_redeemer, booking_of_signed, export_parts,
}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/datum.{KeyStateView}
use cardano_keri/checkpoint/link9_exports as exported
use cardano_keri/checkpoint/qualified
use cardano_keri/checkpoint/threshold.{Threshold, Unweighted, Weight, Weighted}
use keri_application_connected.{d_reg, hash_proof_policy}
use keri_application_requests.{attestation_policy}

fn state_of(
  key: ByteArray,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
) -> KeyStateView {
  KeyStateView {
    cesr_aid: key,
    cur_keys: [key],
    cur_threshold: Unweighted(1),
    next_keys,
    next_threshold,
    witnesses: [],
    toad: 0,
    seq: 0,
    native_sn: 0,
  }
}

fn booking_of_export(
  export: ByteArray,
  size: Int,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
) -> Transaction {
  let (body, identifier, signature) = export_parts(export, size)
  expect Some(key) = qualified.identifier_payload(identifier)
  booking_of_signed(
    state_of(key, next_keys, next_threshold),
    identifier,
    body,
    signature,
  )
}

fn policy_accepts(tx: Transaction) -> Bool {
  booking_attestation.booking_attestation.mint(
    hash_proof_policy,
    d_reg,
    attestation_redeemer(tx),
    attestation_policy(),
    tx,
  )
}

fn halves() -> Threshold {
  Weighted([[Weight { num: 1, den: 2 }, Weight { num: 1, den: 2 }]])
}

fn two_quarters_over_four() -> Threshold {
  Weighted([[Weight { num: 2, den: 4 }, Weight { num: 2, den: 4 }]])
}

fn two_whole_clauses() -> Threshold {
  Weighted([[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]])
}

test link9_w_exact_export_is_the_recorded_one() {
  crypto_sha(exported.w_exact_export) == exported.w_exact_export_sha256
}

test link9_w_unreduced_export_is_the_recorded_one() {
  crypto_sha(exported.w_unreduced_export) == exported.w_unreduced_export_sha256
}

test link9_w_partial_export_is_the_recorded_one() {
  crypto_sha(exported.w_partial_export) == exported.w_partial_export_sha256
}

fn crypto_sha(bytes: ByteArray) -> ByteArray {
  aiken_crypto.sha2_256(bytes)
}

test the_policy_admits_the_exact_weighted_next_declaration() {
  policy_accepts(
    booking_of_export(
      exported.w_exact_export,
      exported.w_exact_body_size,
      [exported.w_exact_next_0, exported.w_exact_next_1],
      halves(),
    ),
  )
}

test the_policy_admits_the_unreduced_weighted_next_declaration() {
  policy_accepts(
    booking_of_export(
      exported.w_unreduced_export,
      exported.w_unreduced_body_size,
      [exported.w_unreduced_next_0, exported.w_unreduced_next_1],
      two_quarters_over_four(),
    ),
  )
}

test the_policy_admits_the_partial_weighted_next_declaration() {
  policy_accepts(
    booking_of_export(
      exported.w_partial_export,
      exported.w_partial_body_size,
      [
        exported.w_partial_next_0,
        exported.w_partial_next_1,
        exported.w_partial_next_2,
      ],
      two_whole_clauses(),
    ),
  )
}

/// The consumer gap, kept visible: the datum a builder writes with the weights reduced (`1/2 + 1/2`) does not equal
/// the signed body that spells `2/4 + 2/4`, and the booking refuses it. A builder is compatible only if its datum
/// carries the original fraction pairs.
test the_policy_refuses_the_unreduced_export_under_a_reduced_datum() fail {
  policy_accepts(
    booking_of_export(
      exported.w_unreduced_export,
      exported.w_unreduced_body_size,
      [exported.w_unreduced_next_0, exported.w_unreduced_next_1],
      halves(),
    ),
  )
}

/// And the reverse: the exact body under the unreduced datum.
test the_policy_refuses_the_exact_export_under_an_unreduced_datum() fail {
  policy_accepts(
    booking_of_export(
      exported.w_exact_export,
      exported.w_exact_body_size,
      [exported.w_exact_next_0, exported.w_exact_next_1],
      two_quarters_over_four(),
    ),
  )
}

/// The partial export's clauses merged into one clause over the same commitments.
test the_policy_refuses_the_partial_export_with_its_clauses_merged() fail {
  policy_accepts(
    booking_of_export(
      exported.w_partial_export,
      exported.w_partial_body_size,
      [
        exported.w_partial_next_0,
        exported.w_partial_next_1,
        exported.w_partial_next_2,
      ],
      Weighted([[Weight { num: 1, den: 1 }, Weight { num: 1, den: 1 }]]),
    ),
  )
}
