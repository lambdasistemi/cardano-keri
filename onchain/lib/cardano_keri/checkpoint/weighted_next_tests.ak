//// The weighted next declarations an inception may make, and the ones it may not, at the inception's key-state check
//// (`key_state_inception_well_formed`). The declaration rule: a numeric threshold within the commitments, or weighted
//// clauses that are each non-empty, whose weights number at most the commitments, whose individual weights are at most
//// one with positive denominators, and whose every clause totals at least one, in any spelling of the weights. Clause
//// boundaries and the order of the commitments are the declaration's own. Every later key state keeps the strict rule.

use cardano_keri/checkpoint/datum.{
  DatumInvalid, DatumValid, KeyStateView, NextIllFormed,
  key_state_inception_well_formed, key_state_well_formed,
}
use cardano_keri/checkpoint/threshold.{
  EmptyKeys, UnreducedWeight, UnsatisfiableClause, Unweighted, Weight, Weighted,
}

const digest_a: ByteArray =
  #"0101010101010101010101010101010101010101010101010101010101010101"

const digest_b: ByteArray =
  #"0202020202020202020202020202020202020202020202020202020202020202"

const digest_c: ByteArray =
  #"0303030303030303030303030303030303030303030303030303030303030303"

fn declaring(
  next_keys: List<ByteArray>,
  next_threshold: threshold.Threshold,
) -> KeyStateView {
  KeyStateView {
    cesr_aid: #"1111111111111111111111111111111111111111111111111111111111111111",
    cur_keys: [
      #"1111111111111111111111111111111111111111111111111111111111111111",
    ],
    cur_threshold: Unweighted(1),
    next_keys,
    next_threshold,
    witnesses: [],
    toad: 0,
    seq: 0,
    native_sn: 0,
  }
}

fn w(num: Int, den: Int) -> Weight {
  Weight { num, den }
}

fn admitted(
  next_keys: List<ByteArray>,
  next_threshold: threshold.Threshold,
) -> Bool {
  key_state_inception_well_formed(declaring(next_keys, next_threshold)) == DatumValid
}

fn refused(
  next_keys: List<ByteArray>,
  next_threshold: threshold.Threshold,
) -> Bool {
  key_state_inception_well_formed(declaring(next_keys, next_threshold)) != DatumValid
}

// ---- admitted declarations (the exports of the local chain run) ---------------------------------------------------

test an_exact_clause_over_the_commitments_is_admitted() {
  admitted([digest_a, digest_b], Weighted([[w(1, 2), w(1, 2)]]))
}

test unreduced_weights_that_total_one_are_admitted() {
  admitted([digest_a, digest_b], Weighted([[w(2, 4), w(2, 4)]]))
}

test separate_whole_weight_clauses_over_more_commitments_are_admitted() {
  admitted([digest_a, digest_b, digest_c], Weighted([[w(1, 1)], [w(1, 1)]]))
}

// ---- refused declarations ---------------------------------------------------------------------------------------------

/// A clause that totals less than one.
test a_clause_below_one_is_refused() {
  key_state_inception_well_formed(
    declaring([digest_a, digest_b], Weighted([[w(1, 3), w(1, 3)]])),
  ) == DatumInvalid(NextIllFormed(UnsatisfiableClause))
}

/// A weighted clause with no commitments.
test a_weighted_clause_with_no_commitments_is_refused() {
  key_state_inception_well_formed(declaring([], Weighted([[w(1, 1)]]))) == DatumInvalid(
    NextIllFormed(EmptyKeys),
  )
}

/// More weights than commitments.
test more_weights_than_commitments_are_refused() {
  refused([digest_a, digest_b], Weighted([[w(1, 1)], [w(1, 1)], [w(1, 1)]]))
}

/// A sibling clause that reaches one does not rescue a clause that does not.
test a_short_clause_beside_a_whole_one_is_refused() {
  refused([digest_a, digest_b], Weighted([[w(1, 1)], [w(1, 3)]]))
}

test an_empty_clause_is_refused() {
  refused([digest_a, digest_b], Weighted([[w(1, 1), w(1, 1)], []]))
}

test a_weight_over_one_is_refused() {
  refused([digest_a, digest_b], Weighted([[w(3, 2), w(1, 2)]]))
}

test a_weight_with_a_zero_denominator_is_refused() {
  refused([digest_a, digest_b], Weighted([[w(1, 0), w(1, 2)]]))
}

test a_weight_with_a_negative_numerator_is_refused() {
  refused([digest_a, digest_b], Weighted([[w(-1, 2), w(3, 2)]]))
}

test a_denominator_above_the_bound_is_refused() {
  refused(
    [digest_a, digest_b],
    Weighted([[w(4294967297, 4294967297), w(1, 2)]]),
  )
}

test a_numeric_threshold_above_the_commitments_is_refused() {
  refused([digest_a, digest_b], Unweighted(3))
}

test a_numeric_threshold_within_the_commitments_is_admitted() {
  admitted([digest_a, digest_b], Unweighted(2))
}

test duplicate_commitments_are_refused() {
  refused([digest_a, digest_a], Weighted([[w(1, 2), w(1, 2)]]))
}

// ---- later key states keep the strict rule -------------------------------------------------------------------------

test a_later_key_state_still_refuses_unreduced_weights() {
  key_state_well_formed(
    declaring([digest_a, digest_b], Weighted([[w(2, 4), w(2, 4)]])),
  ) == DatumInvalid(NextIllFormed(UnreducedWeight))
}

test a_later_key_state_still_refuses_clauses_that_do_not_partition() {
  key_state_well_formed(
    declaring([digest_a, digest_b, digest_c], Weighted([[w(1, 1)], [w(1, 1)]])),
  ) != DatumValid
}
