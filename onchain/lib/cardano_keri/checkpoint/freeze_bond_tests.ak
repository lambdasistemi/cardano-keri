//// Haskell/Aiken parity tests for the isolated #116 R1 freeze-bond model.

use aiken/cbor
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{TombstoneV1}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumInvalid, ArmedDatumValid, ArmedV1, ArmedV2, Deadline,
  DeadlineInvalid, Exclusive, Finite, HunterPkhWidth, Inclusive,
  MissingUpperBound, NegativeInfinity, NonFiniteUpperBound,
  NonPositiveFreezeWindow, PositiveInfinity, arm_deadline, armed_checkpoint,
  armed_datum_well_formed, armed_deadline, armed_hunter,
  claim_at_or_after_deadline, classify, freeze_bond_valid, freeze_window_valid,
  response_before_deadline,
}
use cardano_keri/checkpoint/freeze_bond_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}

fn checkpoint() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    cur_keys: [
      #"0101010101010101010101010101010101010101010101010101010101010101",
    ],
    cur_threshold: Unweighted(1),
    next_keys: [
      #"0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a",
    ],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 0,
    native_sn: 0,
  }
}

fn armed() -> ArmedDatum {
  ArmedV1 { checkpoint: checkpoint(), hunter_pkh: vec.hunter, deadline: 1001 }
}

test parameter_floor_and_window_match_haskell() {
  and {
    freeze_bond_valid(vec.freeze_bond_floor) == vec.bond_floor_valid,
    freeze_bond_valid(vec.freeze_bond_floor - 1) == vec.bond_below_valid,
    freeze_window_valid(0) == vec.window_zero_valid,
    freeze_window_valid(-1) == vec.window_negative_valid,
    freeze_window_valid(1) == vec.window_one_valid,
  }
}

test armed_cbor_matches_haskell_golden() {
  cbor.serialise(armed()) == vec.golden_armed
}

test armed_wrapper_classifies() {
  expect Some(data) = cbor.deserialise(vec.golden_armed)
  classify(data) == Some(armed())
}

test checkpoint_wrapper_does_not_classify_as_armed() {
  expect Some(data) = cbor.deserialise(vec.golden_checkpoint)
  classify(data) == None
}

fn armed_v1_with(hunter_pkh: ByteArray) -> ArmedDatum {
  ArmedV1 { checkpoint: checkpoint(), hunter_pkh, deadline: 1001 }
}

fn armed_v2_with(hunter_pkh: ByteArray) -> ArmedDatum {
  ArmedV2 { checkpoint: checkpoint(), hunter_pkh, deadline: 1001 }
}

/// Width is a wire property of the ARMED state, so it must hold identically for
/// the legacy constructor and the lean #254 successor. Checking only one of them
/// would leave the other free to carry a malformed payee.
test hunter_width_is_exactly_28_bytes() {
  and {
    armed_datum_well_formed(armed()) == ArmedDatumValid,
    armed_datum_well_formed(armed_v2_with(vec.hunter)) == ArmedDatumValid,
    armed_datum_well_formed(armed_v1_with(vec.hunter_short)) == ArmedDatumInvalid(
      HunterPkhWidth,
    ),
    armed_datum_well_formed(armed_v1_with(vec.hunter_long)) == ArmedDatumInvalid(
      HunterPkhWidth,
    ),
    armed_datum_well_formed(armed_v2_with(vec.hunter_short)) == ArmedDatumInvalid(
      HunterPkhWidth,
    ),
    armed_datum_well_formed(armed_v2_with(vec.hunter_long)) == ArmedDatumInvalid(
      HunterPkhWidth,
    ),
  }
}

/// The shared accessors read the same three fields out of either constructor.
/// Claim and the ARMED conviction share depend on this: they must see the
/// stored payee whichever version the state was written in.
test shared_accessors_agree_across_both_armed_versions() {
  and {
    armed_hunter(armed_v1_with(vec.hunter)) == vec.hunter,
    armed_hunter(armed_v2_with(vec.hunter)) == vec.hunter,
    armed_checkpoint(armed_v1_with(vec.hunter)) == checkpoint(),
    armed_checkpoint(armed_v2_with(vec.hunter)) == checkpoint(),
    armed_deadline(armed_v1_with(vec.hunter)) == 1001,
    armed_deadline(armed_v2_with(vec.hunter)) == 1001,
  }
}

test arm_deadline_uses_raw_endpoint_without_normalizing_inclusivity() {
  and {
    arm_deadline(500, Some(Finite(1000, Inclusive))) == Deadline(
      vec.deadline_inclusive,
    ),
    arm_deadline(500, Some(Finite(1000, Exclusive))) == Deadline(
      vec.deadline_exclusive,
    ),
  }
}

test arm_deadline_rejects_missing_unbounded_and_nonpositive_window() {
  and {
    arm_deadline(500, None) == DeadlineInvalid(MissingUpperBound),
    arm_deadline(500, Some(NegativeInfinity)) == DeadlineInvalid(
      NonFiniteUpperBound,
    ),
    arm_deadline(500, Some(PositiveInfinity)) == DeadlineInvalid(
      NonFiniteUpperBound,
    ),
    arm_deadline(0, Some(Finite(1000, Inclusive))) == DeadlineInvalid(
      NonPositiveFreezeWindow,
    ),
  }
}

test arm_deadline_uses_arbitrary_precision_without_an_artificial_cap() {
  arm_deadline(10, Some(Finite(1000000000000000000000000000000, Exclusive))) == Deadline(
    vec.deadline_large,
  )
}

test response_raw_boundaries_match_haskell() {
  and {
    response_before_deadline(1000, Some(Finite(999, Inclusive))) == vec.response_before,
    response_before_deadline(1000, Some(Finite(1000, Exclusive))) == vec.response_exact,
    response_before_deadline(1000, Some(Finite(1001, Inclusive))) == vec.response_after,
    response_before_deadline(1000, Some(PositiveInfinity)) == vec.response_unbounded,
    response_before_deadline(1000, None) == vec.response_missing,
  }
}

test claim_raw_boundaries_match_haskell() {
  and {
    claim_at_or_after_deadline(1000, Some(Finite(999, Exclusive))) == vec.claim_before,
    claim_at_or_after_deadline(1000, Some(Finite(1000, Inclusive))) == vec.claim_exact,
    claim_at_or_after_deadline(1000, Some(Finite(1001, Exclusive))) == vec.claim_after,
    claim_at_or_after_deadline(1000, Some(NegativeInfinity)) == vec.claim_unbounded,
    claim_at_or_after_deadline(1000, None) == vec.claim_missing,
  }
}

test historical_checkpoint_bytes_are_unchanged() {
  cbor.serialise(V1(checkpoint())) == vec.golden_checkpoint
}

test historical_tombstone_bytes_are_unchanged() {
  cbor.serialise(
    TombstoneV1 {
      cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      convicted_at_native_sn: 1,
      evidence_said: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    },
  ) == vec.golden_tombstone
}
