//// The guards an inception that declares no next keys meets, one by one, on the three signed inceptions of
//// `empty_next_bytes`: the created datum's well-formedness, the registration predicate's own key-state check, and the
//// binding of the signed event to the datum. The declaration rule: a next declaration is either a non-empty set with a
//// well-formed threshold, or the empty set with threshold zero; at an inception only.

use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, DatumInvalid, DatumValid, KeyMaterial, KeyStateView, Live,
  NextIllFormed, datum_v2_inception_well_formed,
}
use cardano_keri/checkpoint/empty_next_bytes as bytes
use cardano_keri/checkpoint/registration.{
  DeploymentContext, Icp, InceptionIllFormed, InceptionInvalid, InceptionValid,
  QualifiedSpelling, RegistrationEvidence, RegistrationValid,
  RegistrationVerdict, event_binding, registration_predicate,
  validate_inception_datum,
}
use cardano_keri/checkpoint/threshold.{EmptyKeys, Unweighted, UnweightedRange}

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

fn datum_of(identifier: ByteArray, d: KeyStateView) -> CheckpointDatumV2 {
  Live {
    aid: identifier,
    sn: 0,
    epoch: 0,
    poisoned: False,
    frozen: False,
    born_at: 10,
    refund_to: #"60",
    topped_up: False,
    keys: KeyMaterial {
      cur_keys: [identifier],
      cur_threshold: d.cur_threshold,
      next_keys: d.next_keys,
      next_threshold: d.next_threshold,
      witnesses: d.witnesses,
      toad: d.toad,
    },
  }
}

fn evidence(event: ByteArray, signature: ByteArray) -> RegistrationEvidence {
  RegistrationEvidence {
    event_bytes: event,
    ctrl_sigs: [(0, signature)],
    wit_receipts: [],
  }
}

// ---- guard 1: the created datum ------------------------------------------------

test the_created_datum_of_an_empty_next_declaration_is_well_formed() {
  and {
    datum_v2_inception_well_formed(
      datum_of(bytes.b_empty_identifier, state_of(bytes.b_empty_key)),
    ) == DatumValid,
    datum_v2_inception_well_formed(
      datum_of(bytes.d_empty_identifier, state_of(bytes.d_empty_key)),
    ) == DatumValid,
    datum_v2_inception_well_formed(
      datum_of(bytes.d_seal_identifier, state_of(bytes.d_seal_key)),
    ) == DatumValid,
  }
}

// ---- guard 2: the inception's own key-state check ------------------------------

test the_inception_key_state_of_an_empty_next_declaration_is_well_formed() {
  and {
    validate_inception_datum(Icp, state_of(bytes.b_empty_key)) == InceptionValid,
    validate_inception_datum(Icp, state_of(bytes.d_empty_key)) == InceptionValid,
    validate_inception_datum(Icp, state_of(bytes.d_seal_key)) == InceptionValid,
  }
}

// ---- not a guard: the binding of the signed event to the datum -----------------

test the_signed_event_is_bound_to_the_empty_next_datum() {
  let q = fn(identifier) {
    QualifiedSpelling { aid: identifier, cur_keys: [identifier] }
  }
  and {
    event_binding(
      state_of(bytes.b_empty_key),
      q(bytes.b_empty_identifier),
      evidence(bytes.b_empty_event, bytes.b_empty_signature),
    ) == RegistrationValid,
    event_binding(
      state_of(bytes.d_empty_key),
      q(bytes.d_empty_identifier),
      evidence(bytes.d_empty_event, bytes.d_empty_signature),
    ) == RegistrationValid,
    event_binding(
      state_of(bytes.d_seal_key),
      q(bytes.d_seal_identifier),
      evidence(bytes.d_seal_event, bytes.d_seal_signature),
    ) == RegistrationValid,
  }
}

// ---- the declaration rule keeps its refusals -----------------------------------

/// Empty next keys with a positive threshold: not a declaration.
test an_empty_next_set_with_a_positive_threshold_is_refused() {
  let d = KeyStateView {
    ..state_of(bytes.d_empty_key),
    next_threshold: Unweighted(1),
  }
  and {
    datum_v2_inception_well_formed(datum_of(bytes.d_empty_identifier, d)) == DatumInvalid(
      NextIllFormed(EmptyKeys),
    ),
    validate_inception_datum(Icp, d) == InceptionInvalid(
      InceptionIllFormed(NextIllFormed(EmptyKeys)),
    ),
  }
}

/// Next keys with threshold zero: the threshold rule for a non-empty set stands.
test a_non_empty_next_set_with_threshold_zero_is_refused() {
  let d = KeyStateView {
    ..state_of(bytes.d_empty_key),
    next_keys: [
      #"0101010101010101010101010101010101010101010101010101010101010101",
    ],
  }
  validate_inception_datum(Icp, d) == InceptionInvalid(
    InceptionIllFormed(NextIllFormed(UnweightedRange)),
  )
}

/// The signing threshold stays positive: an empty current set is not made admissible by an empty next set.
test an_empty_current_set_is_still_refused() {
  let d = KeyStateView { ..state_of(bytes.d_empty_key), cur_keys: [] }
  validate_inception_datum(Icp, d) != InceptionValid
}

// ---- the whole registration predicate -------------------------------------------

fn admitted(
  key: ByteArray,
  identifier: ByteArray,
  event: ByteArray,
  signature: ByteArray,
) -> RegistrationVerdict {
  registration_predicate(
    DeploymentContext { min_ada: 2_000_000, d_reg: 1_000_000_000 },
    state_of(key),
    QualifiedSpelling { aid: identifier, cur_keys: [identifier] },
    1_002_000_000,
    evidence(event, signature),
  )
}

test the_predicate_admits_a_non_transferable_key_with_no_next_keys() {
  admitted(
    bytes.b_empty_key,
    bytes.b_empty_identifier,
    bytes.b_empty_event,
    bytes.b_empty_signature,
  ) == RegistrationValid
}

test the_predicate_admits_a_transferable_key_with_no_next_keys() {
  admitted(
    bytes.d_empty_key,
    bytes.d_empty_identifier,
    bytes.d_empty_event,
    bytes.d_empty_signature,
  ) == RegistrationValid
}

test the_predicate_admits_a_transferable_key_with_no_next_keys_and_a_seal() {
  admitted(
    bytes.d_seal_key,
    bytes.d_seal_identifier,
    bytes.d_seal_event,
    bytes.d_seal_signature,
  ) == RegistrationValid
}
