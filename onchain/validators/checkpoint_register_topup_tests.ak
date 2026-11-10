//// #346 / #522 — the bounded top-up of a live checkpoint.
////
//// Anyone may add at least one premium to the pool of a live checkpoint once
//// per key state. The successor is the same datum with the top-up mark set and
//// holds exactly the amount more; every rotation clears the mark, a freeze
//// keeps it, and the registration starts the pool at one premium or more.
////
//// Each refusal is the accepted top-up changed in the one thing it is about.
//// The accepted top-up at the head of each group is the control: a refusal
//// that shared a fault with it would prove nothing about that group.
////
//// The datums are built here as `Data`, field by field (nine fields,
//// `topped_up` at index 7), beside the typed `Live` the validator reads.

use aiken/builtin
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cage_context.{out_ref, seed_tx_id}
use cardano/address.{from_script, with_delegation_key}
use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/transaction.{Transaction}
use checkpoint_observer
use checkpoint_register
use deposit_fixture
use freeze_fixture.{
  Freeze, advance_hash, d_reg, enforcement_hash, entitlement_hash, floor_frozen,
  floor_unfrozen, freeze_bond, freeze_redeemer, lifecycle_hash, mc,
  migration_hash, network_id, policy, premium, spent, spent_ref, token_value,
  unit, v1_data,
}
use registry_fixture.{
  Nothing, OtherKey, OtherRegistryName, OtherStatePolicy, QuantityTwo,
  RetiredRegisterToken, holding, representative, staked, state_policy,
  with_input_token, with_successor_address, with_successor_token,
}
use topup_fixture.{
  Bond, Deposit, Keep, Parts, Rotation, TopUp, base, change, eight_data, flag,
  freeze_case, from_case, held, held_at, honest, honest_case, hp_policy,
  inputs_after, into_case, live_of, marked_with, minting, nine_data, nine_fields,
  other_keys, other_policy, outputs_after, payer_input, pending_data,
  reg_evidence, register_envelope, register_with, registered_parts,
  registered_with_pool, rotation_case, script_output, second_checkpoint_input,
  second_checkpoint_output, signed_by, ten_data, token_name, topup_between,
  topup_redeemer, valued_case, valued_with, with_withdrawal, within,
  without_datum,
}

// The validators are called here: a fixture module cannot import them.

fn run_spend(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    None,
    redeemer,
    spent_ref(),
    tx,
  )
}

fn run_mint(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.mint(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    redeemer,
    policy,
    tx,
  )
}

/// The spending arm alone: a top-up needs no observer.
fn run(t: TopUp) -> Bool {
  run_spend(topup_redeemer(t.amount), t.tx)
}

fn run_register(tx: Transaction) -> Bool {
  let register: Data = builtin.constr_data(0, [])
  run_mint(register, tx) && checkpoint_observer.observer_lifecycle.withdraw(
    0,
    hp_policy,
    d_reg,
    register_envelope(),
    0,
    tx,
  )
}

fn run_rotation(r: Rotation) -> Bool {
  run_spend(r.redeemer, r.tx) && checkpoint_observer.observer_advance.withdraw(
    0,
    r.observed,
    0,
    r.tx,
  )
}

fn run_freeze(f: Freeze) -> Bool {
  run_spend(freeze_redeemer(f.hunter_output_index), f.tx) && checkpoint_observer.observer_advance.withdraw(
    0,
    f.observed,
    0,
    f.tx,
  )
}

// ---------------------------------------------------------------------
// The accepted top-up
// ---------------------------------------------------------------------

test fixture_amounts_are_the_lean_arithmetic() {
  and {
    floor_unfrozen == mc + d_reg + freeze_bond,
    floor_frozen == mc + d_reg,
    premium == 2 * unit,
    held(False, unit) == floor_unfrozen + unit,
    held(True, 0) == floor_frozen,
  }
}

test topup_sets_the_mark_and_adds_the_amount() {
  run(honest())
}

test topup_accepts_an_amount_of_exactly_the_premium() {
  run(honest_case(False, False, unit, premium))
}

test topup_accepts_an_amount_above_the_premium() {
  run(honest_case(False, False, unit, premium + 1))
}

test topup_accepts_an_amount_of_several_premiums() {
  run(honest_case(False, False, unit, 5 * unit))
}

test topup_accepts_an_empty_pool() {
  run(honest_case(False, False, 0, premium))
}

test topup_accepts_a_fresh_unfrozen_unpoisoned_checkpoint() {
  run(honest_case(False, False, unit, premium))
}

test topup_accepts_a_fresh_frozen_unpoisoned_checkpoint() {
  run(honest_case(False, True, unit, premium))
}

test topup_accepts_a_fresh_unfrozen_poisoned_checkpoint() {
  run(honest_case(True, False, unit, premium))
}

test topup_accepts_a_fresh_frozen_poisoned_checkpoint() {
  run(honest_case(True, True, unit, premium))
}

test topup_accepts_a_frozen_checkpoint_whose_pool_is_below_the_premium() {
  run(honest_case(False, True, premium - 1, premium))
}

test topup_accepts_any_validity_range() {
  and {
    run(within(interval.everything)),
    run(within(interval.after(0))),
    run(within(interval.before(registered_after()))),
    run(within(interval.between(1, registered_after()))),
  }
}

fn registered_after() -> Int {
  1_900_000_000_000
}

test topup_accepts_with_an_unrelated_extra_signatory() {
  run(signed_by([#"62626262626262626262626262626262626262626262626262626262"]))
}

test topup_accepts_with_no_extra_signatory() {
  run(signed_by([]))
}

test topup_accepts_with_an_observer_withdrawal_present() {
  run(with_withdrawal())
}

test topup_accepts_other_outputs_after_the_successor() {
  run(outputs_after([change(1_000_000)]))
}

test topup_accepts_a_funder_who_is_anyone() {
  run(inputs_after([payer_input(10 * unit)]))
}

// ---------------------------------------------------------------------
// topup-at-least-premium
// ---------------------------------------------------------------------

test topup_refuses_an_amount_one_below_the_premium() fail {
  run(honest_case(False, False, unit, premium - 1))
}

test topup_refuses_an_amount_of_zero() fail {
  run(honest_case(False, False, unit, 0))
}

test topup_refuses_a_negative_amount() fail {
  run(honest_case(False, False, 5 * unit, -1))
}

test topup_refuses_an_amount_of_one_lovelace() fail {
  run(honest_case(False, False, unit, 1))
}

test topup_refuses_a_redeemer_amount_that_is_not_the_value_growth() fail {
  let t = honest()
  run(TopUp { ..t, amount: premium + 1 })
}

test topup_refuses_a_redeemer_amount_below_the_value_growth() fail {
  let t = honest_case(False, False, unit, premium + 5)
  run(TopUp { ..t, amount: premium })
}

// ---------------------------------------------------------------------
// topup-fresh-only: one top-up per key state
// ---------------------------------------------------------------------

test topup_refuses_a_second_top_up_in_one_key_state() fail {
  run(
    topup_between(
      premium,
      nine_data(base(False, False, True)),
      nine_data(base(False, False, True)),
      held(False, unit),
      held(False, unit + premium),
      [],
    ),
  )
}

test topup_refuses_a_top_up_of_a_marked_checkpoint_that_clears_the_mark() fail {
  run(
    topup_between(
      premium,
      nine_data(base(False, False, True)),
      nine_data(base(False, False, False)),
      held(False, unit),
      held(False, unit + premium),
      [],
    ),
  )
}

test topup_refuses_a_top_up_of_a_marked_frozen_checkpoint() fail {
  run(
    topup_between(
      premium,
      nine_data(base(False, True, True)),
      nine_data(base(False, True, True)),
      held(True, unit),
      held(True, unit + premium),
      [],
    ),
  )
}

// ---------------------------------------------------------------------
// topup-datum-exact: the successor is the input with the mark set
// ---------------------------------------------------------------------

test topup_refuses_a_successor_without_the_mark() fail {
  run(into_case(nine_data(base(False, False, False))))
}

test topup_refuses_a_successor_whose_mark_is_an_integer() fail {
  let mark: Data = 1
  run(into_case(marked_with(base(False, False, True), mark)))
}

test topup_refuses_a_successor_whose_mark_is_not_a_boolean() fail {
  run(
    into_case(marked_with(base(False, False, True), builtin.constr_data(2, []))),
  )
}

test topup_refuses_a_successor_whose_mark_carries_a_field() fail {
  run(
    into_case(
      marked_with(
        base(False, False, True),
        builtin.constr_data(1, [builtin.i_data(0)]),
      ),
    ),
  )
}

test topup_refuses_a_successor_that_changes_the_aid() fail {
  let b = base(False, False, True)
  run(into_case(nine_data(Parts { ..b, aid: bytearray.push(b.aid, 65) })))
}

test topup_refuses_a_successor_that_changes_the_sn() fail {
  let b = base(False, False, True)
  run(into_case(nine_data(Parts { ..b, sn: b.sn + 1 })))
}

test topup_refuses_a_successor_that_changes_the_epoch() fail {
  let b = base(False, False, True)
  run(into_case(nine_data(Parts { ..b, epoch: b.epoch + 1 })))
}

test topup_refuses_a_successor_that_sets_the_poison() fail {
  run(into_case(nine_data(base(True, False, True))))
}

test topup_refuses_a_successor_that_sets_the_frozen_flag() fail {
  run(into_case(nine_data(base(False, True, True))))
}

test topup_refuses_a_successor_that_clears_the_poison() fail {
  run(
    topup_between(
      premium,
      nine_data(base(True, False, False)),
      nine_data(base(False, False, True)),
      held(False, unit),
      held(False, unit + premium),
      [],
    ),
  )
}

test topup_refuses_a_successor_that_clears_the_frozen_flag() fail {
  run(
    topup_between(
      premium,
      nine_data(base(False, True, False)),
      nine_data(base(False, False, True)),
      held(True, unit),
      held(False, unit + premium),
      [],
    ),
  )
}

test topup_refuses_a_successor_that_changes_the_refund_address() fail {
  let b = base(False, False, True)
  run(
    into_case(
      nine_data(Parts { ..b, refund_to: bytearray.push(b.refund_to, 0) }),
    ),
  )
}

test topup_refuses_a_successor_that_changes_the_keys() fail {
  let b = base(False, False, True)
  run(into_case(nine_data(Parts { ..b, keys: other_keys() })))
}

test topup_refuses_a_successor_with_born_at_lowered() fail {
  let b = base(False, False, True)
  run(into_case(nine_data(Parts { ..b, born_at: b.born_at - 1 })))
}

test topup_refuses_a_successor_with_born_at_raised() fail {
  let b = base(False, False, True)
  run(into_case(nine_data(Parts { ..b, born_at: b.born_at + 1 })))
}

test topup_refuses_a_successor_of_eight_fields() fail {
  run(into_case(eight_data(base(False, False, True))))
}

test topup_refuses_a_successor_of_ten_fields() fail {
  run(into_case(ten_data(base(False, False, True))))
}

test topup_refuses_a_successor_that_is_termination_pending() fail {
  run(into_case(pending_data()))
}

test topup_refuses_a_successor_written_as_the_retired_layout() fail {
  run(into_case(v1_data()))
}

// ---------------------------------------------------------------------
// topup-live-only: what is spent must be a version 2 live datum
// ---------------------------------------------------------------------

test topup_refuses_a_termination_pending_input() fail {
  run(from_case(pending_data()))
}

test topup_refuses_an_input_of_eight_fields() fail {
  run(from_case(eight_data(base(False, False, False))))
}

test topup_refuses_an_input_of_ten_fields() fail {
  run(from_case(ten_data(base(False, False, False))))
}

test topup_refuses_an_input_of_the_retired_layout() fail {
  run(from_case(v1_data()))
}

test topup_refuses_an_input_whose_mark_is_not_a_boolean() fail {
  run(from_case(marked_with(base(False, False, False), builtin.i_data(0))))
}

test topup_refuses_an_input_held_away_from_the_checkpoint_address() fail {
  run(held_at(with_delegation_key(from_script(policy), #"63")))
}

test topup_refuses_an_input_with_no_datum() fail {
  run(without_datum())
}

// ---------------------------------------------------------------------
// topup-value-exact
// ---------------------------------------------------------------------

test topup_refuses_a_successor_holding_one_lovelace_less() fail {
  run(valued_case(held(False, unit + premium) - 1))
}

test topup_refuses_a_successor_holding_one_lovelace_more() fail {
  run(valued_case(held(False, unit + premium) + 1))
}

test topup_refuses_a_successor_holding_nothing_more() fail {
  run(valued_case(held(False, unit)))
}

test topup_refuses_a_successor_holding_an_extra_asset() fail {
  run(
    valued_with(
      token_value(held(False, unit + premium))
        |> merge(from_asset(other_policy(), #"01", 1)),
    ),
  )
}

test topup_refuses_a_successor_holding_a_second_token_of_the_policy() fail {
  run(
    valued_with(
      from_lovelace(held(False, unit + premium))
        |> merge(from_asset(state_policy(), token_name(), 2)),
    ),
  )
}

// ---------------------------------------------------------------------
// topup-token-stays, topup-single-checkpoint
// ---------------------------------------------------------------------

test topup_refuses_a_successor_that_does_not_hold_the_token() fail {
  run(valued_with(from_lovelace(held(False, unit + premium))))
}

test topup_refuses_the_token_paid_to_another_output() fail {
  let h = honest()
  run(
    TopUp {
      ..h,
      tx: Transaction {
        ..h.tx,
        outputs: [
          script_output(
            from_lovelace(held(False, unit + premium)),
            nine_data(base(False, False, True)),
          ),
          script_output(
            from_lovelace(2_000_000)
              |> merge(from_asset(state_policy(), token_name(), 1)),
            nine_data(base(False, False, True)),
          ),
        ],
      },
    },
  )
}

test topup_refuses_the_token_leaving_the_checkpoint_address() fail {
  let h = honest()
  run(
    TopUp {
      ..h,
      tx: Transaction {
        ..h.tx,
        outputs: [
          script_output(
            from_lovelace(held(False, unit + premium)),
            nine_data(base(False, False, True)),
          ),
          change(2_000_000),
        ],
      },
    },
  )
}

test topup_refuses_a_mint_under_the_policy() fail {
  run(minting(from_asset(policy, #"b3", 1)))
}

test topup_refuses_a_burn_under_the_policy() fail {
  run(minting(from_asset(policy, #"b3", -1)))
}

test topup_refuses_a_burn_of_the_checkpoint_token() fail {
  run(minting(from_asset(state_policy(), token_name(), -1)))
}

test topup_accepts_a_mint_under_another_policy() {
  run(minting(from_asset(other_policy(), #"b3", 1)))
}

test topup_refuses_a_second_checkpoint_output() fail {
  run(outputs_after([second_checkpoint_output()]))
}

test topup_refuses_a_second_checkpoint_input() fail {
  run(inputs_after([second_checkpoint_input()]))
}

// ---------------------------------------------------------------------
// The registration: the pool starts at one premium or more
// ---------------------------------------------------------------------

test register_accepts_a_pool_of_exactly_the_premium() {
  run_register(registered_with_pool(premium))
}

test register_accepts_a_pool_above_the_premium() {
  run_register(registered_with_pool(premium + 1))
}

test register_accepts_a_pool_of_several_premiums() {
  run_register(registered_with_pool(7 * unit))
}

test register_refuses_a_pool_one_below_the_premium() fail {
  run_register(registered_with_pool(premium - 1))
}

test register_refuses_an_empty_pool() fail {
  run_register(registered_with_pool(0))
}

test register_writes_the_mark_clear() {
  run_register(
    register_with(nine_data(registered_parts(False)), floor_unfrozen + premium),
  )
}

test register_refuses_a_set_mark() fail {
  run_register(
    register_with(nine_data(registered_parts(True)), floor_unfrozen + premium),
  )
}

test register_refuses_a_mark_that_is_not_a_boolean() fail {
  run_register(
    register_with(
      marked_with(registered_parts(False), builtin.i_data(0)),
      floor_unfrozen + premium,
    ),
  )
}

test register_refuses_a_datum_of_eight_fields() fail {
  run_register(
    register_with(eight_data(registered_parts(False)), floor_unfrozen + premium),
  )
}

test register_refuses_a_datum_of_ten_fields() fail {
  run_register(
    register_with(ten_data(registered_parts(False)), floor_unfrozen + premium),
  )
}

// ---------------------------------------------------------------------
// rotation-clears-mark: every accepted Advance writes the mark clear
// ---------------------------------------------------------------------

fn rotates(bond: Bond, frozen: Bool, pool: Int, old: Bool, new: Bool) -> Bool {
  run_rotation(rotation_case(bond, frozen, pool, old, new))
}

test keep_rotation_of_a_marked_checkpoint_clears_the_mark_when_paid() {
  rotates(Keep, False, 3 * unit, True, False)
}

test keep_rotation_of_a_marked_checkpoint_clears_the_mark_when_unpaid() {
  rotates(Keep, False, unit, True, False)
}

test deposit_rotation_of_a_marked_frozen_checkpoint_clears_the_mark_when_paid() {
  rotates(Deposit, True, 3 * unit, True, False)
}

test deposit_rotation_of_a_marked_frozen_checkpoint_clears_the_mark_when_unpaid() {
  rotates(Deposit, True, unit, True, False)
}

test keep_rotation_of_a_marked_frozen_checkpoint_stays_frozen_and_clears_the_mark() {
  rotates(Keep, True, 3 * unit, True, False)
}

test deposit_rotation_of_a_marked_unfrozen_checkpoint_clears_the_mark() {
  rotates(Deposit, False, 3 * unit, True, False)
}

test keep_rotation_of_a_fresh_checkpoint_writes_the_mark_clear() {
  rotates(Keep, False, 3 * unit, False, False)
}

test keep_rotation_refuses_a_set_mark_after_a_marked_input_paid() fail {
  rotates(Keep, False, 3 * unit, True, True)
}

test keep_rotation_refuses_a_set_mark_after_a_marked_input_unpaid() fail {
  rotates(Keep, False, unit, True, True)
}

test keep_rotation_refuses_a_set_mark_after_a_fresh_input() fail {
  rotates(Keep, False, 3 * unit, False, True)
}

test deposit_rotation_refuses_a_set_mark_after_a_marked_input_paid() fail {
  rotates(Deposit, True, 3 * unit, True, True)
}

test deposit_rotation_refuses_a_set_mark_after_a_marked_input_unpaid() fail {
  rotates(Deposit, True, unit, True, True)
}

test deposit_rotation_refuses_a_set_mark_after_a_fresh_input() fail {
  rotates(Deposit, True, 3 * unit, False, True)
}

// ---------------------------------------------------------------------
// freeze-keeps-mark
// ---------------------------------------------------------------------

test freeze_of_a_marked_checkpoint_keeps_the_mark() {
  run_freeze(freeze_case(True, True))
}

test freeze_of_a_fresh_checkpoint_keeps_the_mark_clear() {
  run_freeze(freeze_case(False, False))
}

test freeze_refuses_to_clear_the_mark() fail {
  run_freeze(freeze_case(True, False))
}

test freeze_refuses_to_set_the_mark() fail {
  run_freeze(freeze_case(False, True))
}

// ---------------------------------------------------------------------
// Fixture controls: the hand-built datum is the Lean layout
// ---------------------------------------------------------------------

test the_hand_built_datum_has_nine_fields_with_the_mark_at_seven() {
  let marked = nine_fields(base(False, False, True))
  let clear = nine_fields(base(False, False, False))
  and {
    list.length(marked) == 9,
    list.at(marked, 7) == Some(flag(True)),
    list.at(clear, 7) == Some(flag(False)),
    list.at(marked, 8) == list.at(clear, 8),
  }
}

test the_outpoint_helpers_are_distinct() {
  out_ref(seed_tx_id, 7) != spent_ref()
}

// ---------------------------------------------------------------------
// The redeemer: constructor four, appended after Freeze
// ---------------------------------------------------------------------

test the_top_up_redeemer_is_the_fifth_spend_constructor_with_its_amount() {
  expect checkpoint_register.TopUp { amount } = topup_redeemer(premium)
  amount == premium
}

test the_freeze_redeemer_keeps_its_constructor() {
  expect checkpoint_register.Freeze { hunter_output_index } = freeze_redeemer(1)
  hunter_output_index == 1
}

test the_advance_redeemer_keeps_its_constructor() {
  expect checkpoint_register.Advance { payee_output_index, .. } = deposit_fixture.advance_redeemer(
    1,
    deposit_fixture.bond_keep(),
  )
  payee_output_index == 1
}

test a_spend_redeemer_of_constructor_five_is_refused() fail {
  let amount: Data = premium
  expect _redeemer: checkpoint_register.SpendRedeemer = builtin.constr_data(
    5,
    [amount],
  )
  True
}

// ---------------------------------------------------------------------
// topup: a checkpoint is recognised by the representative asset of its AID
// (Lean `representativeAsset`) and its successor holds the same asset, once
// ---------------------------------------------------------------------

fn topup_over(tx: Transaction) -> Bool {
  run(TopUp { ..honest(), tx })
}

fn topup_base() -> Transaction {
  honest().tx
}

test topup_accepts_an_input_holding_the_representative_asset() {
  topup_over(with_input_token(topup_base(), representative(spent.cesr_aid, 1)))
}

test topup_refuses_an_input_holding_no_token() fail {
  topup_over(
    with_input_token(topup_base(), holding(Nothing, spent.cesr_aid, policy)),
  )
}

test topup_refuses_an_input_holding_the_asset_of_another_state_policy() fail {
  topup_over(
    with_input_token(
      topup_base(),
      holding(OtherStatePolicy, spent.cesr_aid, policy),
    ),
  )
}

test topup_refuses_an_input_holding_the_asset_of_another_registry_name() fail {
  topup_over(
    with_input_token(
      topup_base(),
      holding(OtherRegistryName, spent.cesr_aid, policy),
    ),
  )
}

test topup_refuses_an_input_holding_the_asset_of_another_key() fail {
  topup_over(
    with_input_token(topup_base(), holding(OtherKey, spent.cesr_aid, policy)),
  )
}

test topup_refuses_an_input_holding_two_of_the_representative_asset() fail {
  topup_over(
    with_input_token(topup_base(), holding(QuantityTwo, spent.cesr_aid, policy)),
  )
}

test topup_accepts_a_successor_holding_the_representative_asset() {
  topup_over(
    with_successor_token(topup_base(), representative(spent.cesr_aid, 1)),
  )
}

test topup_refuses_a_successor_holding_no_token() fail {
  topup_over(
    with_successor_token(topup_base(), holding(Nothing, spent.cesr_aid, policy)),
  )
}

test topup_refuses_a_successor_holding_two_of_the_representative_asset() fail {
  topup_over(
    with_successor_token(
      topup_base(),
      holding(QuantityTwo, spent.cesr_aid, policy),
    ),
  )
}

test topup_refuses_a_successor_holding_the_asset_of_another_key() fail {
  topup_over(
    with_successor_token(
      topup_base(),
      holding(OtherKey, spent.cesr_aid, policy),
    ),
  )
}

test topup_refuses_a_successor_holding_the_asset_of_another_state_policy() fail {
  topup_over(
    with_successor_token(
      topup_base(),
      holding(OtherStatePolicy, spent.cesr_aid, policy),
    ),
  )
}

test topup_refuses_a_checkpoint_that_holds_only_the_retired_register_token() fail {
  let retired = holding(RetiredRegisterToken, spent.cesr_aid, policy)
  topup_over(
    with_successor_token(with_input_token(topup_base(), retired), retired),
  )
}

test topup_refuses_a_successor_at_a_staked_address() fail {
  topup_over(with_successor_address(topup_base(), staked(policy)))
}
