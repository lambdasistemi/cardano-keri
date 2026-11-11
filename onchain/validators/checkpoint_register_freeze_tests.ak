//// #345 — the one-step freeze of a live checkpoint.
////
//// Anyone may present the controller's own later witnessed rotation as a
//// freeze while the pool is below the premium: the hunter receives the
//// freeze bond, the datum keeps its old keys and sequence number with
//// `frozen` set, and the checkpoint holds `Mc + D + pool`.
////
//// Each refusal is the accepted freeze changed in the one thing it is about.
//// The accepted freeze at the head of each group is the control: a refusal
//// that shared a fault with it would prove nothing about that group.

use aiken/cbor
use aiken/primitive/bytearray
use cage_context.{out_ref}
use cardano/address.{Credential, Script, from_script}
use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/transaction.{Output, OutputReference, Transaction, Withdraw}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/advance_vectors as advance_vec
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, KeyMaterial, TerminationPending,
}
use cardano_keri/checkpoint/freeze_vectors as vec
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_freeze,
}
use checkpoint_observer
use checkpoint_register
use freeze_fixture.{
  Freeze, Parts, advance_hash, advance_redeemer, advance_tag, d_reg,
  enforcement_hash, entitlement_hash, envelope, envelope_with, floor_frozen,
  floor_unfrozen, forged, freeze_bond, freeze_redeemer, freeze_tag, freeze_tx,
  from_parts, honest_case, honest_envelope, honest_tx, hunter_pkh, into_case,
  live, mc, migration_hash, network_id, observing_case, other_hunter_pkh, paid,
  parts, paying_case, pending_data, policy, premium, rotated, rotation,
  spending_case, spent, spent_keys, spent_ref, token_value, under_receipted,
  under_signed, unevidenced, unit, v1_data, v2_data,
}
use registry_fixture.{
  Nothing, OtherKey, OtherRegistryName, OtherStatePolicy, QuantityTwo,
  RetiredRegisterToken, application_policy, holding, registry_name,
  representative, staked, state_policy, with_input_token, with_successor_address,
  with_successor_token,
}

// The validators are called here: a fixture module cannot import them.

fn run_spend(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    state_policy(),
    registry_name(),
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    application_policy(),
    None,
    redeemer,
    spent_ref(),
    tx,
  )
}

/// The spending arm and the observer, both run over the one transaction.
fn run(f: Freeze) -> Bool {
  run_spend(freeze_redeemer(f.hunter_output_index), f.tx) && checkpoint_observer.observer_advance.withdraw(
    0,
    f.observed,
    0,
    f.tx,
  )
}

fn run_freeze(
  hunter_output_index: Int,
  observed: ObserverEnvelope,
  tx: Transaction,
) -> Bool {
  run(Freeze { hunter_output_index, observed, tx })
}

fn honest(pool: Int) -> Bool {
  run(honest_case(pool))
}

fn freeze_into(new: CheckpointDatumV2, successor_lovelace: Int) -> Bool {
  run(into_case(new, successor_lovelace))
}

fn freeze_paying(hunter_output_index: Int, others: List<Output>) -> Bool {
  run(paying_case(hunter_output_index, others))
}

fn freeze_observing(evidence: AdvanceEvidence) -> Bool {
  run(observing_case(evidence))
}

fn freeze_spending(
  old: CheckpointDatumV2,
  input_lovelace: Int,
  successor: CheckpointDatumV2,
  successor_lovelace: Int,
) -> Bool {
  run(spending_case(old, input_lovelace, successor, successor_lovelace))
}

// ---------------------------------------------------------------------
// The accepted freeze
// ---------------------------------------------------------------------

test fixture_amounts_are_the_lean_arithmetic() {
  and {
    floor_unfrozen == mc + d_reg + freeze_bond,
    floor_frozen == mc + d_reg,
    freeze_bond == 5 * unit,
    premium == 2 * unit,
  }
}

test freeze_pays_the_bond_and_writes_the_frozen_datum() {
  honest(1_000_000)
}

test freeze_accepts_an_empty_pool() {
  honest(0)
}

test freeze_accepts_a_pool_one_lovelace_below_the_premium() {
  honest(premium - 1)
}

test freeze_accepts_a_hunter_paid_more_than_the_bond() {
  freeze_paying(1, [paid(hunter_pkh, freeze_bond + 7)])
}

test freeze_accepts_the_observer_alone() {
  checkpoint_observer.observer_advance.withdraw(
    0,
    honest_envelope(),
    0,
    honest_tx(1_000_000),
  )
}

/// The Haskell encoders and the Aiken types agree on the bytes: the typed
/// value serialises to exactly what `gen-freeze-vectors` computed.
test freeze_spend_redeemer_is_the_haskell_encoding() {
  let redeemer: Data = checkpoint_register.Freeze {
    hunter_output_index: vec.hunter_output_index,
  }
  cbor.serialise(redeemer) == vec.spend_redeemer_cbor
}

test freeze_evidence_is_the_haskell_encoding() {
  let payload: Data = vec.evidence
  cbor.serialise(payload) == vec.evidence_cbor
}

test freeze_observer_envelope_is_the_haskell_encoding() {
  let envelope: Data = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_freeze,
      checkpoint_policy: vec.policy,
      own_ref: Some(vec.spent_ref),
    },
    payload: vec.evidence,
  }
  cbor.serialise(envelope) == vec.observer_envelope_cbor
}

test freeze_action_tag_is_two_and_the_fixture_agrees() {
  observe_freeze == 2 && freeze_tag == observe_freeze
}

test freeze_is_spend_constructor_three() {
  // Advance is 0, Convict 1 and MigrateOut 2: the freeze is appended.
  run_spend(freeze_redeemer(1), honest_tx(1_000_000))
}

// ---------------------------------------------------------------------
// The spending arm's own claim bindings
//
// Only the spending arm runs here: the observer is not called, so only the
// spending arm can refuse. Each refusal is the honest transaction with the
// observation the arm reads changed in one thing; the control accepts the
// honest observation alone.
// ---------------------------------------------------------------------

fn spend_arm_given(
  observed: ObserverEnvelope,
  withdrawals: List<Pair<Credential, Int>>,
  redeemer_credential: Credential,
) -> Bool {
  let tx = honest_tx(1_000_000)
  let redeemer: Data = observed
  run_spend(
    freeze_redeemer(1),
    Transaction {
      ..tx,
      withdrawals,
      redeemers: [Pair(Withdraw(redeemer_credential), redeemer)],
    },
  )
}

fn observer_credential() -> Credential {
  Script(advance_hash)
}

fn spend_arm_observing(observed: ObserverEnvelope) -> Bool {
  spend_arm_given(
    observed,
    [Pair(observer_credential(), 0)],
    observer_credential(),
  )
}

fn claim_of(
  action: Int,
  policy: ByteArray,
  own_ref: Option<OutputReference>,
) -> ObserverEnvelope {
  let honest_observed = honest_envelope()
  ObserverEnvelope {
    ..honest_observed,
    claim: ObserverClaim { action, checkpoint_policy: policy, own_ref },
  }
}

test freeze_spend_arm_accepts_the_honest_claim_alone() {
  spend_arm_observing(honest_envelope())
}

test freeze_spend_arm_refuses_the_advance_action_tag() fail {
  spend_arm_observing(claim_of(advance_tag, policy, Some(spent_ref())))
}

test freeze_spend_arm_refuses_an_unknown_action_tag() fail {
  spend_arm_observing(claim_of(7, policy, Some(spent_ref())))
}

test freeze_spend_arm_refuses_a_claim_naming_another_output() fail {
  spend_arm_observing(
    claim_of(freeze_tag, policy, Some(out_ref(spent.txid, spent.index + 1))),
  )
}

test freeze_spend_arm_refuses_a_claim_naming_no_output() fail {
  spend_arm_observing(claim_of(freeze_tag, policy, None))
}

test freeze_spend_arm_refuses_a_claim_of_another_policy() fail {
  spend_arm_observing(claim_of(freeze_tag, migration_hash, Some(spent_ref())))
}

test freeze_spend_arm_refuses_a_withdrawal_of_lovelace() fail {
  spend_arm_given(
    honest_envelope(),
    [Pair(observer_credential(), 1)],
    observer_credential(),
  )
}

test freeze_spend_arm_refuses_a_withdrawal_of_another_credential() fail {
  spend_arm_given(
    honest_envelope(),
    [Pair(Script(migration_hash), 0)],
    observer_credential(),
  )
}

test freeze_spend_arm_refuses_a_redeemer_of_another_credential() fail {
  spend_arm_given(
    honest_envelope(),
    [Pair(observer_credential(), 0)],
    Script(migration_hash),
  )
}

// ---------------------------------------------------------------------
// freeze-requires-short-pool
// ---------------------------------------------------------------------

test freeze_refuses_a_pool_equal_to_the_premium() fail {
  honest(premium)
}

test freeze_refuses_a_pool_one_lovelace_above_the_premium() fail {
  honest(premium + 1)
}

test freeze_refuses_a_pool_far_above_the_premium() fail {
  honest(50 * premium)
}

// ---------------------------------------------------------------------
// freeze-requires-unfrozen, freeze-requires-unpoisoned
// ---------------------------------------------------------------------

test freeze_refuses_a_frozen_checkpoint() fail {
  freeze_spending(
    live(False, True),
    floor_frozen + 1_000_000,
    live(False, True),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_poisoned_checkpoint() fail {
  freeze_spending(
    live(True, False),
    floor_unfrozen + 1_000_000,
    from_parts(Parts { ..parts(live(True, False)), frozen: True }),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_poisoned_checkpoint_whose_successor_is_clean() fail {
  // The successor is the frozen copy of the spent datum with the poison
  // cleared, so the copy rule is met by a validator that ignores the poison:
  // only the premise that the checkpoint is unpoisoned can refuse it.
  freeze_spending(
    live(True, False),
    floor_unfrozen + 1_000_000,
    live(False, True),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_poisoned_frozen_checkpoint() fail {
  freeze_spending(
    live(True, True),
    floor_frozen + 1_000_000,
    live(True, True),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_termination_pending_input() fail {
  freeze_observing_pending()
}

fn freeze_observing_pending() -> Bool {
  run_freeze(
    1,
    honest_envelope(),
    freeze_tx(
      pending_data(),
      v2_data(live(False, True)),
      mc,
      floor_frozen,
      [paid(hunter_pkh, freeze_bond)],
      honest_envelope(),
    ),
  )
}

test freeze_refuses_a_version_1_input() fail {
  run_freeze(
    1,
    honest_envelope(),
    freeze_tx(
      v1_data(),
      v2_data(live(False, True)),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, freeze_bond)],
      honest_envelope(),
    ),
  )
}

// ---------------------------------------------------------------------
// freeze-requires-witnessed-later-rotation
// ---------------------------------------------------------------------

test freeze_refuses_a_rotation_without_signatures_or_receipts() fail {
  freeze_observing(unevidenced())
}

test freeze_refuses_a_forged_controller_signature() fail {
  freeze_observing(forged())
}

test freeze_refuses_an_under_signed_rotation() fail {
  freeze_observing(under_signed())
}

test freeze_refuses_an_under_receipted_rotation() fail {
  freeze_observing(under_receipted())
}

test freeze_refuses_a_missing_observer() fail {
  let tx = honest_tx(1_000_000)
  run_spend(
    freeze_redeemer(1),
    Transaction { ..tx, withdrawals: [], redeemers: [] },
  )
}

test freeze_refuses_the_advance_action_tag() fail {
  let observed = envelope(advance_tag, spent_ref(), rotation, rotated.native_sn)
  run_freeze(
    1,
    observed,
    freeze_tx(
      v2_data(live(False, False)),
      v2_data(live(False, True)),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, freeze_bond)],
      observed,
    ),
  )
}

test freeze_refuses_an_observation_of_another_output() fail {
  let observed = envelope(
    freeze_tag,
    out_ref(spent.txid, spent.index + 1),
    rotation,
    rotated.native_sn,
  )
  run_freeze(
    1,
    observed,
    freeze_tx(
      v2_data(live(False, False)),
      v2_data(live(False, True)),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, freeze_bond)],
      observed,
    ),
  )
}

test freeze_refuses_a_payload_that_is_not_freeze_evidence() fail {
  let honest_observed = honest_envelope()
  let observed = ObserverEnvelope { ..honest_observed, payload: rotation }
  run_freeze(
    1,
    observed,
    freeze_tx(
      v2_data(live(False, False)),
      v2_data(live(False, True)),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, freeze_bond)],
      observed,
    ),
  )
}

test freeze_refuses_an_observer_alone_given_unevidenced_rotation() fail {
  let observed = envelope_with(unevidenced())
  checkpoint_observer.observer_advance.withdraw(
    0,
    observed,
    0,
    honest_tx(1_000_000),
  )
}

test freeze_refuses_a_rotation_from_other_next_keys() fail {
  // The spent checkpoint committed to other pre-rotation keys: the genuine
  // rotation of this vector is no rotation of that state.
  let other_keys = KeyMaterial {
    ..spent_keys(),
    next_keys: [
      #"0000000000000000000000000000000000000000000000000000000000000001",
      #"0000000000000000000000000000000000000000000000000000000000000002",
    ],
  }
  let old = Parts { ..parts(live(False, False)), keys: other_keys }
  freeze_spending(
    from_parts(old),
    floor_unfrozen + 1_000_000,
    from_parts(Parts { ..old, frozen: True }),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_rotation_that_is_not_later() fail {
  // The spent checkpoint is already at the rotation's sequence number.
  let old = Parts { ..parts(live(False, False)), sn: rotated.native_sn }
  freeze_spending(
    from_parts(old),
    floor_unfrozen + 1_000_000,
    from_parts(Parts { ..old, frozen: True }),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_rotation_to_an_earlier_sequence_number() fail {
  let old = Parts { ..parts(live(False, False)), sn: rotated.native_sn + 3 }
  freeze_spending(
    from_parts(old),
    floor_unfrozen + 1_000_000,
    from_parts(Parts { ..old, frozen: True }),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_rotation_of_another_identifier() fail {
  let old = Parts {
    ..parts(live(False, False)),
    aid: qb64_aid(advance_vec.pos_adv_keep_spent.cesr_aid),
  }
  freeze_spending(
    from_parts(old),
    floor_unfrozen + 1_000_000,
    from_parts(Parts { ..old, frozen: True }),
    floor_frozen + 1_000_000,
  )
}

// ---------------------------------------------------------------------
// freeze-successor-is-the-same-datum-frozen
// ---------------------------------------------------------------------

fn frozen_successor() -> Parts {
  parts(live(False, True))
}

test freeze_refuses_a_successor_that_stays_unfrozen() fail {
  // The successor holds exactly what its own (unfrozen) facts say, so only
  // the copy rule can refuse it.
  freeze_into(live(False, False), floor_unfrozen + 1_000_000)
}

test freeze_refuses_a_changed_aid() fail {
  freeze_into(
    from_parts(
      Parts {
        ..frozen_successor(),
        aid: qb64_aid(advance_vec.pos_adv_keep_spent.cesr_aid),
      },
    ),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_changed_sequence_number() fail {
  freeze_into(
    from_parts(Parts { ..frozen_successor(), sn: frozen_successor().sn + 1 }),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_changed_epoch() fail {
  freeze_into(
    from_parts(
      Parts { ..frozen_successor(), epoch: frozen_successor().epoch + 1 },
    ),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_successor_on_the_rotated_keys() fail {
  // The datum stays on the old keys; writing the rotation's keys is the
  // rotation, not the freeze.
  freeze_into(
    from_parts(
      Parts { ..frozen_successor(), keys: freeze_fixture.keys_of(rotated) },
    ),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_changed_birth_slot() fail {
  freeze_into(
    from_parts(
      Parts { ..frozen_successor(), born_at: frozen_successor().born_at + 1 },
    ),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_changed_refund_address() fail {
  freeze_into(
    from_parts(
      Parts {
        ..frozen_successor(),
        refund_to: bytearray.concat(#"61", other_hunter_pkh),
      },
    ),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_poisoned_successor() fail {
  freeze_into(
    from_parts(Parts { ..frozen_successor(), poisoned: True }),
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_termination_pending_successor() fail {
  freeze_into(
    TerminationPending {
      aid: frozen_successor().aid,
      sn: frozen_successor().sn,
      epoch: frozen_successor().epoch,
    },
    floor_frozen + 1_000_000,
  )
}

test freeze_refuses_a_version_1_successor() fail {
  run_freeze(
    1,
    honest_envelope(),
    freeze_tx(
      v2_data(live(False, False)),
      v1_data(),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, freeze_bond)],
      honest_envelope(),
    ),
  )
}

fn at_other_script(output: Output) -> Output {
  Output { ..output, address: from_script(migration_hash) }
}

test freeze_refuses_a_successor_at_another_script() fail {
  let tx = honest_tx(1_000_000)
  expect [successor, hunter] = tx.outputs
  run_freeze(
    1,
    honest_envelope(),
    Transaction { ..tx, outputs: [at_other_script(successor), hunter] },
  )
}

test freeze_refuses_two_successors() fail {
  let tx = honest_tx(1_000_000)
  expect [successor, hunter] = tx.outputs
  run_freeze(
    2,
    honest_envelope(),
    Transaction { ..tx, outputs: [successor, successor, hunter] },
  )
}

test freeze_refuses_no_successor() fail {
  let tx = honest_tx(1_000_000)
  expect [_, hunter] = tx.outputs
  run_freeze(0, honest_envelope(), Transaction { ..tx, outputs: [hunter] })
}

// ---------------------------------------------------------------------
// freeze-successor-holds-the-frozen-value
// ---------------------------------------------------------------------

test freeze_refuses_a_successor_one_lovelace_above() fail {
  freeze_into(live(False, True), floor_frozen + 1_000_001)
}

test freeze_refuses_a_successor_one_lovelace_below() fail {
  freeze_into(live(False, True), floor_frozen + 999_999)
}

test freeze_refuses_a_successor_that_keeps_the_bond() fail {
  freeze_into(live(False, True), floor_unfrozen + 1_000_000)
}

test freeze_refuses_a_successor_that_pays_the_bond_twice() fail {
  freeze_into(live(False, True), floor_frozen + 1_000_000 - freeze_bond)
}

test freeze_refuses_a_successor_without_the_token() fail {
  let tx = honest_tx(1_000_000)
  expect [successor, hunter] = tx.outputs
  run_freeze(
    1,
    honest_envelope(),
    Transaction {
      ..tx,
      outputs: [
        Output { ..successor, value: from_lovelace(floor_frozen + 1_000_000) },
        hunter,
      ],
    },
  )
}

test freeze_refuses_a_successor_with_a_second_token() fail {
  let tx = honest_tx(1_000_000)
  expect [successor, hunter] = tx.outputs
  run_freeze(
    1,
    honest_envelope(),
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..successor,
          value: merge(successor.value, representative(#"00", 1)),
        },
        hunter,
      ],
    },
  )
}

test freeze_refuses_a_spent_output_below_its_floor() fail {
  freeze_spending(
    live(False, False),
    floor_unfrozen - 1,
    live(False, True),
    floor_frozen - 1,
  )
}

// ---------------------------------------------------------------------
// freeze-pays-the-hunter-the-bond
// ---------------------------------------------------------------------

test freeze_refuses_a_bond_paid_one_lovelace_short() fail {
  freeze_paying(1, [paid(hunter_pkh, freeze_bond - 1)])
}

test freeze_refuses_a_missing_hunter_output() fail {
  freeze_paying(1, [])
}

test freeze_refuses_a_hunter_index_beyond_the_outputs() fail {
  freeze_paying(7, [paid(hunter_pkh, freeze_bond)])
}

test freeze_refuses_a_negative_hunter_index() fail {
  freeze_paying(-1, [paid(hunter_pkh, freeze_bond)])
}

test freeze_refuses_the_successor_as_the_hunter() fail {
  freeze_paying(0, [paid(hunter_pkh, freeze_bond)])
}

test freeze_refuses_a_hunter_output_that_holds_the_token() fail {
  let tx = honest_tx(1_000_000)
  expect [successor, hunter] = tx.outputs
  run_freeze(
    1,
    honest_envelope(),
    Transaction {
      ..tx,
      outputs: [successor, Output { ..hunter, value: token_value(freeze_bond) }],
    },
  )
}

// ---------------------------------------------------------------------
// freeze-mints-nothing
// ---------------------------------------------------------------------

test freeze_refuses_a_mint_under_the_policy() fail {
  let tx = honest_tx(1_000_000)
  run_freeze(
    1,
    honest_envelope(),
    Transaction { ..tx, mint: representative(spent.cesr_aid, 1) },
  )
}

test freeze_refuses_a_burn_under_the_policy() fail {
  let tx = honest_tx(1_000_000)
  run_freeze(
    1,
    honest_envelope(),
    Transaction { ..tx, mint: representative(spent.cesr_aid, -1) },
  )
}

test freeze_accepts_a_mint_under_another_policy() {
  let tx = honest_tx(1_000_000)
  run_freeze(
    1,
    honest_envelope(),
    Transaction { ..tx, mint: from_asset(advance_hash, #"01", 1) },
  )
}

// ---------------------------------------------------------------------
// existing-arms-unchanged: the freeze does not leak into the other arms
// ---------------------------------------------------------------------

test advance_refuses_the_freeze_action_tag() fail {
  // An Advance redeemer beside an observer envelope tagged as a freeze.
  let tx = honest_tx(1_000_000)
  run_spend(advance_redeemer(1), tx)
}

// ---------------------------------------------------------------------
// freeze: a checkpoint is recognised by the representative asset of its AID
// (Lean `representativeAsset`) and its successor holds the same asset, once
// ---------------------------------------------------------------------

fn freeze_over(tx: Transaction) -> Bool {
  run_freeze(1, honest_envelope(), tx)
}

fn freeze_base() -> Transaction {
  honest_tx(1_000_000)
}

test freeze_accepts_an_input_holding_the_representative_asset() {
  freeze_over(
    with_input_token(freeze_base(), representative(spent.cesr_aid, 1)),
  )
}

test freeze_refuses_an_input_holding_no_token() fail {
  freeze_over(
    with_input_token(freeze_base(), holding(Nothing, spent.cesr_aid, policy)),
  )
}

test freeze_refuses_an_input_holding_the_asset_of_another_state_policy() fail {
  freeze_over(
    with_input_token(
      freeze_base(),
      holding(OtherStatePolicy, spent.cesr_aid, policy),
    ),
  )
}

test freeze_refuses_an_input_holding_the_asset_of_another_registry_name() fail {
  freeze_over(
    with_input_token(
      freeze_base(),
      holding(OtherRegistryName, spent.cesr_aid, policy),
    ),
  )
}

test freeze_refuses_an_input_holding_the_asset_of_another_key() fail {
  freeze_over(
    with_input_token(freeze_base(), holding(OtherKey, spent.cesr_aid, policy)),
  )
}

test freeze_refuses_an_input_holding_two_of_the_representative_asset() fail {
  freeze_over(
    with_input_token(
      freeze_base(),
      holding(QuantityTwo, spent.cesr_aid, policy),
    ),
  )
}

test freeze_accepts_a_successor_holding_the_representative_asset() {
  freeze_over(
    with_successor_token(freeze_base(), representative(spent.cesr_aid, 1)),
  )
}

test freeze_refuses_a_successor_holding_no_token() fail {
  freeze_over(
    with_successor_token(
      freeze_base(),
      holding(Nothing, spent.cesr_aid, policy),
    ),
  )
}

test freeze_refuses_a_successor_holding_two_of_the_representative_asset() fail {
  freeze_over(
    with_successor_token(
      freeze_base(),
      holding(QuantityTwo, spent.cesr_aid, policy),
    ),
  )
}

test freeze_refuses_a_successor_holding_the_asset_of_another_key() fail {
  freeze_over(
    with_successor_token(
      freeze_base(),
      holding(OtherKey, spent.cesr_aid, policy),
    ),
  )
}

test freeze_refuses_a_successor_holding_the_asset_of_another_state_policy() fail {
  freeze_over(
    with_successor_token(
      freeze_base(),
      holding(OtherStatePolicy, spent.cesr_aid, policy),
    ),
  )
}

test freeze_refuses_a_checkpoint_that_holds_only_the_retired_register_token() fail {
  let retired = holding(RetiredRegisterToken, spent.cesr_aid, policy)
  freeze_over(
    with_successor_token(with_input_token(freeze_base(), retired), retired),
  )
}

test freeze_refuses_a_successor_at_a_staked_address() fail {
  freeze_over(with_successor_address(freeze_base(), staked(policy)))
}
