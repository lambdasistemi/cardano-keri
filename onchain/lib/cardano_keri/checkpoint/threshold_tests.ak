//// Byte-identity + F18 well-formedness + evaluation tests for the Aiken
//// `Threshold` codec (#68 Slice 5). The `cbor.serialise` byte-identity
//// asserts mirror the frozen `vectors.ak` goldens produced by the Slice-2/3
//// Haskell encoder — this file is the cross-language parity proof. The F18
//// negatives and `evaluate` cases mirror the Slice-2 hspec suite
//// (`Cardano.KERI.AID.Checkpoint.ThresholdSpec`) one-for-one.

use aiken/cbor
use cardano_keri/checkpoint/threshold.{
  DuplicateKey, EmptyClause, EmptyKeys, Invalid, KeyWidth, NegativeNum,
  NonPositiveDen, OverUnityWeight, PartitionMismatch, Threshold, UnreducedWeight,
  UnsatisfiableClause, Unweighted, UnweightedRange, Valid, Weight,
  WeightOutOfBound, Weighted, evaluate, max_weight_denom, well_formed,
}
use cardano_keri/checkpoint/vectors

// ---------------------------------------------------------
// Key fixtures (32-byte KERI KeyDigests; k31 is one byte short)
// ---------------------------------------------------------

const k1: ByteArray =
  #"0101010101010101010101010101010101010101010101010101010101010101"

const k2: ByteArray =
  #"0202020202020202020202020202020202020202020202020202020202020202"

const k3: ByteArray =
  #"0303030303030303030303030303030303030303030303030303030303030303"

const k4: ByteArray =
  #"0404040404040404040404040404040404040404040404040404040404040404"

const k5: ByteArray =
  #"0505050505050505050505050505050505050505050505050505050505050505"

const k31: ByteArray =
  #"01010101010101010101010101010101010101010101010101010101010101"

// ---------------------------------------------------------
// Byte-identity goldens: cbor.serialise(value) == vectors.const
// (Constr 0 -> tag 0xd879; Constr 1 -> tag 0xd87a; fields/lists are
// indefinite CBOR arrays 0x9f .. 0xff.)
// ---------------------------------------------------------

test cbor_integer_m_of_n() {
  cbor.serialise(Unweighted(3)) == vectors.golden_threshold_integer
}

test cbor_single_clause() {
  cbor.serialise(
    Weighted([[Weight { num: 1, den: 2 }, Weight { num: 1, den: 2 }]]),
  ) == vectors.golden_threshold_single_clause
}

test cbor_multi_clause() {
  cbor.serialise(
    Weighted([[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]]),
  ) == vectors.golden_threshold_multi_clause
}

test cbor_1of1_unweighted() {
  cbor.serialise(Unweighted(1)) == vectors.golden_threshold_1of1
}

test cbor_1of1_weighted() {
  cbor.serialise(Weighted([[Weight { num: 1, den: 1 }]])) == vectors.golden_threshold_weighted_1of1
}

test cbor_zero_weight() {
  cbor.serialise(
    Weighted([[Weight { num: 0, den: 1 }, Weight { num: 1, den: 1 }]]),
  ) == vectors.golden_threshold_zero_weight
}

// ---------------------------------------------------------
// Frozen V1 constant (pinned to a literal, not the export)
// ---------------------------------------------------------

test frozen_max_weight_denom() {
  max_weight_denom == 4294967296
}

// ---------------------------------------------------------
// F18 well-formedness positives
// ---------------------------------------------------------

test wf_integer_m_of_n() {
  well_formed([k1, k2, k3], Unweighted(2)) == Valid
}

test wf_single_clause() {
  well_formed(
    [k1, k2],
    Weighted([[Weight { num: 1, den: 2 }, Weight { num: 1, den: 2 }]]),
  ) == Valid
}

test wf_multi_clause() {
  well_formed(
    [k1, k2],
    Weighted([[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]]),
  ) == Valid
}

test wf_1of1_unweighted() {
  well_formed([k1], Unweighted(1)) == Valid
}

test wf_1of1_weighted() {
  well_formed([k1], Weighted([[Weight { num: 1, den: 1 }]])) == Valid
}

test wf_zero_weight_in_satisfiable_clause() {
  // Zero weights are legal KERI (the reserve/custodial-rotation pattern).
  well_formed(
    [k1, k2],
    Weighted([[Weight { num: 0, den: 1 }, Weight { num: 1, den: 1 }]]),
  ) == Valid
}

test wf_keripy_multi_clause_vector() {
  // WebOfTrust/keripy tests/core/test_weighted_threshold.py:
  // [["1/2","1/2","1/2"],["1","1"]] over 5 keys.
  well_formed(
    [k1, k2, k3, k4, k5],
    Weighted(
      [
        [
          Weight { num: 1, den: 2 },
          Weight { num: 1, den: 2 },
          Weight { num: 1, den: 2 },
        ],
        [Weight { num: 1, den: 1 }, Weight { num: 1, den: 1 }],
      ],
    ),
  ) == Valid
}

// ---------------------------------------------------------
// F18 rejections (rules 1-12), mirroring the Slice-2 negatives
// ---------------------------------------------------------

test wf_rule1_empty_keys() {
  well_formed([], Unweighted(1)) == Invalid(EmptyKeys)
}

test wf_rule2_duplicate_key() {
  well_formed([k1, k1], Unweighted(1)) == Invalid(DuplicateKey)
}

test wf_rule3_key_width() {
  well_formed([k31], Unweighted(1)) == Invalid(KeyWidth)
}

test wf_rule4_m_gt_n() {
  well_formed([k1, k2], Unweighted(3)) == Invalid(UnweightedRange)
}

test wf_rule4_m_lt_1() {
  well_formed([k1], Unweighted(0)) == Invalid(UnweightedRange)
}

test wf_rule5_empty_clause_set() {
  well_formed([k1], Weighted([])) == Invalid(EmptyClause)
}

test wf_rule5_empty_clause() {
  well_formed([k1], Weighted([[]])) == Invalid(EmptyClause)
}

test wf_rule6_partition_mismatch() {
  well_formed([k1, k2], Weighted([[Weight { num: 1, den: 1 }]])) == Invalid(
    PartitionMismatch,
  )
}

test wf_rule7_non_positive_den() {
  well_formed([k1], Weighted([[Weight { num: 1, den: 0 }]])) == Invalid(
    NonPositiveDen,
  )
}

test wf_rule8_negative_num() {
  well_formed([k1], Weighted([[Weight { num: -1, den: 2 }]])) == Invalid(
    NegativeNum,
  )
}

test wf_all_zero_clause_unsatisfiable() {
  // An all-zero clause is caught by rule 12, not rule 8.
  well_formed([k1], Weighted([[Weight { num: 0, den: 1 }]])) == Invalid(
    UnsatisfiableClause,
  )
}

test wf_rule9_over_unity() {
  well_formed([k1], Weighted([[Weight { num: 3, den: 2 }]])) == Invalid(
    OverUnityWeight,
  )
}

test wf_rule10_unreduced() {
  well_formed([k1], Weighted([[Weight { num: 2, den: 4 }]])) == Invalid(
    UnreducedWeight,
  )
}

// Literal bounds: these must fail if the frozen constant drifts.
test wf_rule11_denom_at_bound_accepted() {
  well_formed(
    [k1, k2],
    Weighted(
      [
        [
          Weight { num: 1, den: 4294967296 },
          Weight { num: 4294967295, den: 4294967296 },
        ],
      ],
    ),
  ) == Valid
}

test wf_rule11_denom_over_bound_rejected() {
  well_formed(
    [k1, k2],
    Weighted(
      [
        [
          Weight { num: 1, den: 4294967297 },
          Weight { num: 4294967296, den: 4294967297 },
        ],
      ],
    ),
  ) == Invalid(WeightOutOfBound)
}

test wf_rule12_unsatisfiable_clause() {
  well_formed([k1], Weighted([[Weight { num: 1, den: 2 }]])) == Invalid(
    UnsatisfiableClause,
  )
}

// Rule 13: a nested weighted-list weight shape is rejected at the decode
// boundary. The typed `Weight` fields make nesting unrepresentable in a value,
// so hostile *wire* data is the only way to smuggle it in: this raw Plutus-Data
// CBOR is `Constr 1 [[Constr 0 [Constr 1 [[[Weight 1 2]]], I 2]]]` — the outer
// Weight's `num` position (an `Int`) is itself a nested `Weighted` threshold.
// Decoding it as `Threshold` must fail (mirrors Slice-2 `fromBuiltinData`
// returning `Nothing`). The `fail` test passes iff the soft-cast errors.
const nested_weight_cbor: ByteArray =
  #"d87a9f9f9fd8799fd87a9f9f9fd8799f0102ffffffff02ffffffff"

test wf_rule13_nested_weight_rejected() fail {
  expect Some(data) = cbor.deserialise(nested_weight_cbor)
  expect _thr: Threshold = data
  True
}

// ---------------------------------------------------------
// evaluate — Unweighted
// ---------------------------------------------------------

test eval_unweighted_satisfied() {
  evaluate(Unweighted(2), 3, [0, 1]) == True
}

test eval_unweighted_unsatisfied() {
  evaluate(Unweighted(2), 3, [0]) == False
}

test eval_unweighted_ignores_out_of_range() {
  evaluate(Unweighted(2), 3, [0, 7]) == False
}

// ---------------------------------------------------------
// evaluate — Weighted
// ---------------------------------------------------------

const half3: Threshold =
  Weighted(
    [
      [
        Weight { num: 1, den: 2 },
        Weight { num: 1, den: 2 },
        Weight { num: 1, den: 2 },
      ],
    ],
  )

const and_clauses: Threshold =
  Weighted([[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]])

test eval_weighted_two_halves_reach_one() {
  evaluate(half3, 3, [0, 1]) == True
}

test eval_weighted_one_half_short() {
  evaluate(half3, 3, [0]) == False
}

test eval_weighted_multi_clause_anded_satisfied() {
  evaluate(and_clauses, 2, [0, 1]) == True
}

test eval_weighted_multi_clause_anded_one_unsatisfied() {
  evaluate(and_clauses, 2, [0]) == False
}

test eval_weighted_order_independent() {
  evaluate(half3, 3, [2, 0]) == evaluate(half3, 3, [0, 2])
}

const reserve: Threshold =
  Weighted([[Weight { num: 0, den: 1 }, Weight { num: 1, den: 1 }]])

test eval_zero_weight_signer_contributes_nothing() {
  evaluate(reserve, 2, [0]) == False
}

test eval_full_weight_signer_satisfies_despite_zero_peer() {
  evaluate(reserve, 2, [1]) == True
}

const keripy_mc: Threshold =
  Weighted(
    [
      [
        Weight { num: 1, den: 2 },
        Weight { num: 1, den: 2 },
        Weight { num: 1, den: 2 },
      ],
      [Weight { num: 1, den: 1 }, Weight { num: 1, den: 1 }],
    ],
  )

test eval_keripy_multi_clause_both_clauses_reached() {
  evaluate(keripy_mc, 5, [0, 2, 3, 4]) == True
}

test eval_keripy_multi_clause_unsigned_second_clause_fails() {
  evaluate(keripy_mc, 5, [0, 1, 2]) == False
}

// ---------------------------------------------------------
// 1-of-1 degenerate equivalence
// ---------------------------------------------------------

test eval_1of1_equivalence() {
  evaluate(Unweighted(1), 1, [0]) == evaluate(
    Weighted([[Weight { num: 1, den: 1 }]]),
    1,
    [0],
  )
}
