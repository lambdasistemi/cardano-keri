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
  aid_of, commitment_of, key_of, previous_of, rotation_of,
  row_partial_other_committed_key, row_rival_witness_change, tip_of,
}
use cardano_keri/checkpoint/threshold.{Threshold, Unweighted, Weight, Weighted}

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
  // the rival reveals the first committed key, so the weight of two alone
  // would meet the rule: only the ceiling refuses it
  let rival = Rotation {
    ..base_rival(),
    keys: [key_of(1)],
    signers: [key_of(1)],
  }
  !rotation_valid(previous, rival)
}

test zero_denominator_in_the_declared_next_rule_is_refused() {
  // 0/0 passes the weight ceiling; only the denominator rule refuses it
  let rival = Rotation {
    ..base_rival(),
    next_threshold: Weighted([[Weight { num: 0, den: 0 }]]),
  }
  !rotation_valid(base_previous(), rival)
}

// The model keeps the signed spelling: an unreduced fraction and a
// denominator above 2^32 in the declared next rule are admitted.
test unreduced_and_large_denominators_in_the_declared_next_rule_are_admitted() {
  let unreduced = Rotation {
    ..base_rival(),
    next_key_count: 2,
    next_threshold: Weighted(
      [[Weight { num: 2, den: 4 }, Weight { num: 1, den: 2 }]],
    ),
  }
  let large = Rotation {
    ..base_rival(),
    next_key_count: 2,
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

// ---------------------------------------------------------
// Structure of the signed rules and the witness lists (Lean `Threshold.satisfied`,
// `signingValid`, `receiptsValid`): cases the model rows do not carry, each the
// refusing half of a pair whose accepting half is the base case or a model row.
// ---------------------------------------------------------

test weighted_rule_must_partition_the_keys() {
  let rival = Rotation {
    ..base_rival(),
    threshold: Weighted(
      [[Weight { num: 1, den: 1 }, Weight { num: 1, den: 1 }]],
    ),
  }
  !rotation_valid(base_previous(), rival)
}

test zero_denominator_in_the_signing_rule_is_refused() {
  // 0/0 passes the weight ceiling and, unchecked, sums to a met clause
  let rival = Rotation {
    ..base_rival(),
    threshold: Weighted([[Weight { num: 0, den: 0 }]]),
  }
  !rotation_valid(base_previous(), rival)
}

test negative_count_is_not_a_threshold() {
  let rival = Rotation { ..base_rival(), threshold: Unweighted(-1) }
  let previous = Previous { ..base_previous(), next_threshold: Unweighted(-1) }
  and {
    !rotation_valid(base_previous(), rival),
    !rotation_valid(previous, base_rival()),
  }
}

test rival_for_another_identifier_than_the_checkpoint_is_refused() {
  let tip = Tip { ..base_tip(), aid: aid_of(2) }
  and {
    conviction_accepts(base_tip(), base_rival()),
    !conviction_accepts(tip, base_rival()),
  }
}

test duplicate_previous_commitments_refuse() {
  let previous = Previous {
    ..base_previous(),
    next_keys: [commitment_of(2), commitment_of(2)],
  }
  !rotation_valid(previous, base_rival())
}

test duplicate_rival_keys_refuse() {
  let rival = Rotation { ..base_rival(), keys: [key_of(2), key_of(2)] }
  !rotation_valid(base_previous(), rival)
}

test no_previous_commitment_refuses_even_for_a_zero_count() {
  let previous = Previous {
    ..base_previous(),
    next_keys: [],
    next_threshold: Unweighted(0),
  }
  !rotation_valid(previous, base_rival())
}

test no_rival_key_refuses_even_for_a_zero_count() {
  let previous = Previous { ..base_previous(), next_threshold: Unweighted(0) }
  let rival = Rotation {
    ..base_rival(),
    keys: [],
    threshold: Unweighted(0),
    signers: [],
  }
  !rotation_valid(previous, rival)
}

test negative_receipt_threshold_refuses() {
  let rival = Rotation { ..base_rival(), toad: -1 }
  !rotation_valid(base_previous(), rival)
}

// The witness change of the model row `rival-witness-change`, with a repeated
// cut, a repeated addition and a repeated previous witness.
fn witness_change() -> Rotation {
  rotation_of(row_rival_witness_change.rival)
}

test the_witness_change_row_is_the_accepting_half() {
  expect Some(previous) = row_rival_witness_change.tip.previous
  rotation_valid(previous_of(previous), witness_change())
}

test repeated_cut_refuses() {
  expect Some(previous) = row_rival_witness_change.tip.previous
  let rival = Rotation { ..witness_change(), cuts: [key_of(10), key_of(10)] }
  !rotation_valid(previous_of(previous), rival)
}

test repeated_addition_refuses() {
  expect Some(previous) = row_rival_witness_change.tip.previous
  let rival = Rotation { ..witness_change(), adds: [key_of(11), key_of(11)] }
  !rotation_valid(previous_of(previous), rival)
}

test repeated_previous_witness_refuses() {
  let previous = Previous {
    ..base_previous(),
    witnesses: [key_of(10), key_of(10)],
  }
  !rotation_valid(previous, base_rival())
}

// A rotation must be later than the establishment it follows (Lean
// `sequence_zero_refused` is the case at zero).
test rotation_at_the_previous_sequence_is_refused() {
  let rival = base_rival()
  let previous = Previous { ..base_previous(), sn: rival.sn }
  and {
    rotation_valid(base_previous(), rival),
    !rotation_valid(previous, rival),
  }
}

// W11 (#598, keripy refused): a nonempty resulting witness set with a receipt
// threshold of zero is not admitted, receipts or not. The control is the empty
// resulting set with threshold zero (#591: every witness cut), which stays
// admitted; a positive threshold with no eligible receipt is refused as before.
test a_nonempty_witness_set_needs_a_positive_receipt_threshold() {
  let zero_with_receipt = Rotation { ..base_rival(), toad: 0 }
  let empty_set = Rotation {
    ..base_rival(),
    cuts: [key_of(10)],
    toad: 0,
    receipts: [],
  }
  let short = Rotation { ..base_rival(), toad: 1, receipts: [] }
  and {
    rotation_valid(base_previous(), base_rival()),
    !rotation_valid(base_previous(), zero_with_receipt),
    rotation_valid(base_previous(), empty_set),
    !rotation_valid(base_previous(), short),
  }
}

// Signer membership of the previous quorum (Lean `signingValid`,
// Duplicity.lean:170-176: the previous next threshold counts the committed
// keys that the rival both reveals and signs with). The rival reveals one
// committed key (1) and one uncommitted key (3) and meets its own count-1 rule
// whichever of the two signs; only the signature of the committed key meets
// the previous rule. Expected: accepted when key 1 signs, refused when only
// key 3 signs although key 1 is revealed.
fn two_key_rival(signer: Int) -> Rotation {
  Rotation {
    ..base_rival(),
    keys: [key_of(1), key_of(3)],
    signers: [key_of(signer)],
  }
}

test previous_quorum_follows_the_signer_not_the_revealed_key() {
  and {
    rotation_valid(base_previous(), two_key_rival(1)),
    !rotation_valid(base_previous(), two_key_rival(3)),
  }
}

// W05 (#598, keripy refused): adding a witness the previous set already has is
// not admitted, at whatever receipt threshold; the genuine addition of an absent
// witness (with its receipt) is the control. The model's derivation still does
// not repeat a present witness, but admission refuses the addition first.
test an_addition_of_a_present_witness_is_refused() {
  let present_one = Rotation { ..base_rival(), adds: [key_of(10)], toad: 1 }
  let present_two = Rotation { ..present_one, toad: 2 }
  let genuine = Rotation {
    ..base_rival(),
    adds: [key_of(11)],
    toad: 2,
    receipts: [key_of(10), key_of(11)],
  }
  and {
    !rotation_valid(base_previous(), present_one),
    !rotation_valid(base_previous(), present_two),
    rotation_valid(base_previous(), genuine),
  }
}

// W04 (#598, keripy refused): cutting a witness that is not in the previous set.
// The control is cutting a member.
test a_cut_of_a_nonmember_is_refused() {
  let cut_member = Rotation {
    ..base_rival(),
    cuts: [key_of(10)],
    adds: [key_of(11)],
    toad: 1,
    receipts: [key_of(11)],
  }
  let cut_nonmember = Rotation { ..cut_member, cuts: [key_of(12)] }
  and {
    rotation_valid(base_previous(), cut_member),
    !rotation_valid(base_previous(), cut_nonmember),
  }
}

// W06 (#598, keripy refused): cutting and adding the same witness. The control
// is a replacement by two distinct witnesses.
test a_cut_and_an_addition_of_the_same_witness_is_refused() {
  let same = Rotation {
    ..base_rival(),
    cuts: [key_of(10)],
    adds: [key_of(10)],
    toad: 1,
  }
  let distinct_replacement = Rotation {
    ..base_rival(),
    cuts: [key_of(10)],
    adds: [key_of(11)],
    toad: 1,
    receipts: [key_of(11)],
  }
  and {
    !rotation_valid(base_previous(), same),
    rotation_valid(base_previous(), distinct_replacement),
  }
}

// #596: a numeric signing threshold of zero is never satisfied, whoever signs,
// in the rival's rule and in the predecessor's next rule (Lean
// `zero_signing_threshold_unsatisfied`, `rotation_zero_signing_threshold_refused`).
test a_zero_signing_threshold_is_never_satisfied() {
  let rival = Rotation { ..base_rival(), threshold: Unweighted(0) }
  let previous = Previous { ..base_previous(), next_threshold: Unweighted(0) }
  let none_signed = Rotation { ..base_rival(), signers: [] }
  and {
    !rotation_valid(base_previous(), rival),
    !rotation_valid(previous, base_rival()),
    !rotation_valid(previous, none_signed),
  }
}

// #595: the rival's own declared next rule must fit the next keys it declares
// (Lean `Threshold.fitsNextKeys`): a count wider than the keys, a weighted rule
// wider than the keys, an empty weighted declaration, a clause that cannot reach
// one. A count of zero over no keys (abandonment) and a weighted rule narrower
// than the keys are admitted.
test the_declared_next_rule_must_fit_the_declared_next_keys() {
  let with_next = fn(count: Int, next: Threshold) {
    Rotation { ..base_rival(), next_key_count: count, next_threshold: next }
  }
  let half = Weight { num: 1, den: 2 }
  and {
    rotation_valid(base_previous(), with_next(2, Unweighted(2))),
    !rotation_valid(base_previous(), with_next(1, Unweighted(2))),
    rotation_valid(base_previous(), with_next(0, Unweighted(0))),
    !rotation_valid(base_previous(), with_next(1, Weighted([[half, half]]))),
    rotation_valid(base_previous(), with_next(2, Weighted([[half, half]]))),
    rotation_valid(
      base_previous(),
      with_next(2, Weighted([[Weight { num: 1, den: 1 }]])),
    ),
    !rotation_valid(base_previous(), with_next(2, Weighted([]))),
    !rotation_valid(
      base_previous(),
      with_next(2, Weighted([[Weight { num: 1, den: 4 }, half]])),
    ),
  }
}

// T15 of the keripy comparison (#589): keripy refuses to construct the
// threshold [3/2, 1/2]. The model's admission guard refuses it in each of the
// three places it is read (the rival's signing rule, its declared next rule
// and the predecessor's next rule); without the ceiling the two keys signing
// would satisfy it. The control is the admissible [1/2, 1/2] under the same
// keys, signers and receipts.
test the_589_t15_threshold_is_refused_wherever_the_rival_reads_it() {
  let t15 = Weighted([[Weight { num: 3, den: 2 }, Weight { num: 1, den: 2 }]])
  let halves = Weighted(
    [[Weight { num: 1, den: 2 }, Weight { num: 1, den: 2 }]],
  )
  let two_keys = Rotation {
    ..base_rival(),
    keys: [key_of(1), key_of(2)],
    signers: [key_of(1), key_of(2)],
  }
  let previous = Previous {
    ..base_previous(),
    next_threshold: Weighted(
      [[Weight { num: 3, den: 2 }, Weight { num: 1, den: 2 }]],
    ),
  }
  and {
    rotation_valid(base_previous(), Rotation { ..two_keys, threshold: halves }),
    !rotation_valid(base_previous(), Rotation { ..two_keys, threshold: t15 }),
    !rotation_valid(
      base_previous(),
      Rotation { ..two_keys, threshold: halves, next_threshold: t15 },
    ),
    !rotation_valid(previous, Rotation { ..two_keys, threshold: halves }),
  }
}
