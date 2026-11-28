//// The booking attestation policy over the inceptions that declare no next keys: a non-transferable key identifier, a
//// transferable key identifier, and a transferable key identifier with a seal in its anchor. Each is signed, its
//// event rebuilt from the datum, its hash-proof token spent and burned; the booking is admitted. The controls beside
//// them: the same inception with next commitments, and the empty declaration with a threshold other than zero.

use aiken/builtin
use aiken/crypto.{sha2_256}
use aiken/primitive/bytearray
use booking_attestation
use booking_attestation_fixture.{
  Inception, attestation_redeemer, booking_of_request,
}
use cardano/transaction.{Transaction}
use cardano_keri/base64url
use cardano_keri/checkpoint/datum.{KeyStateView}
use cardano_keri/checkpoint/empty_next_bytes as bytes
use cardano_keri/checkpoint/link2_exports as exported
use cardano_keri/checkpoint/qualified
use cardano_keri/checkpoint/registration.{RegistrationEvidence}
use cardano_keri/checkpoint/threshold.{Unweighted}
use keri_application_connected.{connected_request_for, d_reg, hash_proof_policy}
use keri_application_requests.{attestation_policy}

fn state_of(key: ByteArray) -> KeyStateView {
  KeyStateView {
    cesr_aid: key,
    cur_keys: [key],
    cur_threshold: Unweighted(1),
    next_keys: [],
    next_threshold: Unweighted(0),
    witnesses: [],
    toad: 0,
    seq: 0,
    native_sn: 0,
  }
}

fn inception_of(
  key: ByteArray,
  event: ByteArray,
  signature: ByteArray,
) -> Inception {
  Inception {
    state: state_of(key),
    evidence: RegistrationEvidence {
      event_bytes: event,
      ctrl_sigs: [(0, signature)],
      wit_receipts: [],
    },
  }
}

fn booking(
  key: ByteArray,
  identifier: ByteArray,
  event: ByteArray,
  signature: ByteArray,
) -> Transaction {
  let inception = inception_of(key, event, signature)
  booking_of_request(
    connected_request_for(inception.state, identifier),
    inception,
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

test the_policy_admits_a_non_transferable_key_with_no_next_keys() {
  policy_accepts(
    booking(
      bytes.b_empty_key,
      bytes.b_empty_identifier,
      bytes.b_empty_event,
      bytes.b_empty_signature,
    ),
  )
}

test the_policy_admits_a_transferable_key_with_no_next_keys() {
  policy_accepts(
    booking(
      bytes.d_empty_key,
      bytes.d_empty_identifier,
      bytes.d_empty_event,
      bytes.d_empty_signature,
    ),
  )
}

test the_policy_admits_a_transferable_key_with_no_next_keys_and_a_seal() {
  policy_accepts(
    booking(
      bytes.d_seal_key,
      bytes.d_seal_identifier,
      bytes.d_seal_event,
      bytes.d_seal_signature,
    ),
  )
}

// ---- the three exports of the local chain run, byte for byte ----------------------------------------------------------
//
// The signed body and its indexed controller signature attachment as the run exported them (`link2_exports`), bound
// to their recorded SHA-256. The body, the identifier, the key and the signature are read from the export itself.

fn body_of(export: ByteArray, size: Int) -> ByteArray {
  builtin.slice_bytearray(0, size, export)
}

/// The 64 signature bytes of the attachment `-VAX-AAB` + one 88 character indexed signature after the body.
fn signature_of(export: ByteArray, size: Int) -> ByteArray {
  let text = builtin.slice_bytearray(size + 8, 88, export)
  expect Some(raw) = base64url.decode(
    bytearray.concat("AA", bytearray.drop(text, 2)),
  )
  builtin.slice_bytearray(2, 64, raw)
}

fn identifier_of(body: ByteArray) -> ByteArray {
  builtin.slice_bytearray(91, 44, body)
}

fn export_booking(export: ByteArray, size: Int) -> Transaction {
  let body = body_of(export, size)
  let identifier = identifier_of(body)
  expect Some(key) = qualified.identifier_payload(identifier)
  booking(key, identifier, body, signature_of(export, size))
}

test link2_b_empty_export_is_the_recorded_one() {
  sha2_256(exported.b_empty_export) == exported.b_empty_export_sha256
}

test link2_d_empty_export_is_the_recorded_one() {
  sha2_256(exported.d_empty_export) == exported.d_empty_export_sha256
}

test link2_d_seal_export_is_the_recorded_one() {
  sha2_256(exported.d_seal_export) == exported.d_seal_export_sha256
}

test the_policy_admits_the_exported_b_empty_inception() {
  policy_accepts(
    export_booking(exported.b_empty_export, exported.b_empty_body_size),
  )
}

test the_policy_admits_the_exported_d_empty_inception() {
  policy_accepts(
    export_booking(exported.d_empty_export, exported.d_empty_body_size),
  )
}

test the_policy_admits_the_exported_d_seal_inception() {
  policy_accepts(
    export_booking(exported.d_seal_export, exported.d_seal_body_size),
  )
}

/// Controls: the exported body under the signature of another export is refused.
test the_policy_refuses_the_exported_d_empty_body_under_the_d_seal_signature() fail {
  let body = body_of(exported.d_empty_export, exported.d_empty_body_size)
  let identifier = identifier_of(body)
  expect Some(key) = qualified.identifier_payload(identifier)
  policy_accepts(
    booking(
      key,
      identifier,
      body,
      signature_of(exported.d_seal_export, exported.d_seal_body_size),
    ),
  )
}

/// The exported seal body with its last byte changed is refused.
test the_policy_refuses_the_exported_d_seal_body_with_a_changed_byte() fail {
  let body = body_of(exported.d_seal_export, exported.d_seal_body_size)
  let identifier = identifier_of(body)
  expect Some(key) = qualified.identifier_payload(identifier)
  policy_accepts(
    booking(
      key,
      identifier,
      bytearray.concat(
        builtin.slice_bytearray(0, exported.d_seal_body_size - 1, body),
        "~",
      ),
      signature_of(exported.d_seal_export, exported.d_seal_body_size),
    ),
  )
}
