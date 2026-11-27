//// Conviction predicate: the cases the model rows do not carry — the matched
//// wrong predecessor, a rival that differs from the writer only by digest,
//// the epoch clause, and the admission of thresholds (draft #582; the
//// expected verdicts are the model's definitions `rotationValid` and
//// `CheckpointConviction.accepts`, and the guards of
//// CheckpointRivalValidityControls.lean lines 44–64).

use cardano_keri/checkpoint/rival.{
  Previous, Rotation, Tip, conviction_accepts, rotation_valid,
}
use cardano_keri/checkpoint/rival_vectors.{
  commitment_of, previous_of, rotation_of, row_partial_other_committed_key,
  tip_of,
}
use cardano_keri/checkpoint/threshold.{Weight, Weighted}

// The base case is the model's row `partial-other-committed-key`: the rival
// reveals the other committed key, is receipted by the previous witness, and
// is accepted against the carried previous commitments.
fn base_previous() -> Previous {
  expect Some(previous) = row_partial_other_committed_key.tip.previous
  previous_of(previous)
}

fn base_rival() -> Rotation {
  rotation_of(row_partial_other_committed_key.rival)
}

fn base_tip() -> Tip {
  tip_of(row_partial_other_committed_key.tip)
}

test base_case_is_accepted() {
  and {
    rotation_valid(base_previous(), base_rival()),
    conviction_accepts(base_tip(), base_rival()),
  }
}

// The same rival, signatures and receipts judged against a predecessor that
// did not commit to the key it reveals: signingValid has no exposed key, so
// the previous next threshold cannot be met.
test wrong_predecessor_refuses_the_same_rival() {
  let wrong = Previous {
    ..base_previous(),
    next_keys: [commitment_of(1), commitment_of(3)],
  }
  let tip = Tip { ..base_tip(), previous: Some(wrong) }
  and {
    rotation_valid(base_previous(), base_rival()),
    !rotation_valid(wrong, base_rival()),
    !conviction_accepts(tip, base_rival()),
  }
}

// A rival whose digest equals the writer's is the writer: no conflict, though
// it is as valid as before.
test rival_with_the_writers_digest_is_no_conflict() {
  let same = Rotation { ..base_rival(), event_digest: base_tip().writer_digest }
  and {
    rotation_valid(base_previous(), same),
    !conviction_accepts(base_tip(), same),
  }
}

// `epoch != 0`: a checkpoint at epoch zero has not rotated even if a
// predecessor were present.
test epoch_zero_refuses_even_with_a_predecessor() {
  let tip = Tip { ..base_tip(), epoch: 0 }
  !conviction_accepts(tip, base_rival())
}

test structure_not_verified_refuses() {
  let rival = Rotation { ..base_rival(), structure_ok: False }
  !rotation_valid(base_previous(), rival)
}

// Admission as keripy accepts (draft #582): an individual weight above one,
// in the signing rule, the declared next rule or the predecessor's next rule,
// and a zero denominator in the declared next rule, are refused.
test weight_above_one_in_the_rival_signing_rule_is_refused() {
  let rival = Rotation {
    ..base_rival(),
    threshold: Weighted([[Weight { num: 2, den: 1 }]]),
  }
  !rotation_valid(base_previous(), rival)
}

test weight_above_one_in_the_declared_next_rule_is_refused() {
  let rival = Rotation {
    ..base_rival(),
    next_threshold: Weighted([[Weight { num: 2, den: 1 }]]),
  }
  !rotation_valid(base_previous(), rival)
}

test weight_above_one_in_the_predecessors_next_rule_is_refused() {
  let previous = Previous {
    ..base_previous(),
    next_threshold: Weighted(
      [[Weight { num: 2, den: 1 }, Weight { num: 0, den: 1 }]],
    ),
  }
  !rotation_valid(previous, base_rival())
}

test zero_denominator_in_the_declared_next_rule_is_refused() {
  let rival = Rotation {
    ..base_rival(),
    next_threshold: Weighted([[Weight { num: 1, den: 0 }]]),
  }
  !rotation_valid(base_previous(), rival)
}

// The model keeps the signed spelling: an unreduced fraction and a
// denominator above 2^32 in the declared next rule are admitted.
test unreduced_and_large_denominators_in_the_declared_next_rule_are_admitted() {
  let unreduced = Rotation {
    ..base_rival(),
    next_threshold: Weighted(
      [[Weight { num: 2, den: 4 }, Weight { num: 1, den: 2 }]],
    ),
  }
  let large = Rotation {
    ..base_rival(),
    next_threshold: Weighted(
      [
        [
          Weight { num: 1, den: 4294967297 },
          Weight { num: 4294967296, den: 4294967297 },
        ],
      ],
    ),
  }
  and {
    rotation_valid(base_previous(), unreduced),
    rotation_valid(base_previous(), large),
  }
}
