//// #345 — the deposit option of Advance.
////
//// A deposit Advance lands the controller's witnessed rotation and restores the
//// freeze bond: the successor is unfrozen, holds the minimum ADA, the deposit,
//// the bond and the pool that is left, and the new keys of the rotation signed
//// an intent naming this rotation, this output and this amount.
////
//// These tests run the spend arm and the rotation observer over one
//// transaction, with the rotation of the Advance vector `adv_wit_2key`. Each
//// refusal is the accepted deposit changed in the one thing it is about; the
//// accepted deposits at the head of each group are its controls, and a refusal
//// that shared a fault with them would prove nothing about that group.

use aiken/primitive/bytearray
use cage_context.{out_ref}
use cardano/address.{from_verification_key}
use cardano/assets.{zero}
use cardano/transaction.{NoDatum, Output}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/datum.{CheckpointDatumV2}
use cardano_keri/checkpoint/observer.{ObserverClaim, ObserverEnvelope}
use checkpoint_observer
use checkpoint_register
use deposit_fixture.{
  Case, advance_envelope, advance_redeemer, bond_deposit, bond_keep,
  connected_case, connected_tx, honest, new_datum, old_datum, payees, signed,
  spent_value, successor_value,
}
use freeze_fixture.{
  Parts, advance_hash, d_reg, enforcement_hash, entitlement_hash, floor_frozen,
  floor_unfrozen, forged, freeze_bond, from_parts, hunter_pkh, other_hunter_pkh,
  paid, parts, premium, rotation, spent, token_value, under_receipted,
  under_signed, unevidenced, unit,
}
use registry_fixture.{
  application_policy, registry_name, representative, state_policy,
}

// The validators are called here: a fixture module cannot import them.

fn run_spend(c: Case) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    state_policy(),
    registry_name(),
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    c.network,
    d_reg,
    freeze_bond,
    premium,
    application_policy(),
    None,
    c.redeemer,
    c.own_ref,
    c.tx,
  )
}

/// The spending arm and the observer, both run over the one transaction.
fn run(c: Case) -> Bool {
  run_spend(c) && checkpoint_observer.observer_advance.withdraw(
    0,
    c.observed,
    0,
    c.tx,
  )
}

/// A pool below the premium (nothing is paid) and one that covers it.
const short_pool: Int = 1_000_000

const covering_pool: Int = 3_000_000

fn frozen_deposit_signed_with(
  signatures: List<(Int, ByteArray)>,
  pool: Int,
) -> Case {
  let observed = advance_envelope(rotation)
  connected_case(
    advance_redeemer(1, bond_deposit(signatures)),
    observed,
    connected_tx(
      old_datum(False, True),
      spent_value(True, pool),
      new_datum(False),
      successor_value(pool),
      payees(pool),
      zero,
      observed,
    ),
  )
}

/// A deposit of a frozen checkpoint whose successor and its value are given.
fn frozen_deposit_into(
  new: CheckpointDatumV2,
  successor_lovelace: Int,
  pool: Int,
) -> Case {
  let observed = advance_envelope(rotation)
  connected_case(
    advance_redeemer(1, bond_deposit(signed(@"frozen"))),
    observed,
    connected_tx(
      old_datum(False, True),
      spent_value(True, pool),
      new,
      successor_lovelace,
      payees(pool),
      zero,
      observed,
    ),
  )
}

/// A deposit of a frozen checkpoint whose outputs after the successor are given.
fn frozen_deposit_paying(others: List<Output>, pool: Int) -> Case {
  let observed = advance_envelope(rotation)
  connected_case(
    advance_redeemer(1, bond_deposit(signed(@"frozen"))),
    observed,
    connected_tx(
      old_datum(False, True),
      spent_value(True, pool),
      new_datum(False),
      successor_value(pool),
      others,
      zero,
      observed,
    ),
  )
}

/// A deposit of a frozen checkpoint whose observer evidence is given.
fn frozen_deposit_observing(evidence: AdvanceEvidence) -> Case {
  let observed = advance_envelope(evidence)
  connected_case(
    advance_redeemer(1, bond_deposit(signed(@"frozen"))),
    observed,
    connected_tx(
      old_datum(False, True),
      spent_value(True, short_pool),
      new_datum(False),
      successor_value(short_pool),
      [],
      zero,
      observed,
    ),
  )
}

// ---------------------------------------------------------------------
// The accepted deposits
// ---------------------------------------------------------------------

test fixture_amounts_are_the_lean_arithmetic() {
  and {
    floor_unfrozen - floor_frozen == freeze_bond,
    successor_value(short_pool) == floor_unfrozen + short_pool,
    successor_value(covering_pool) == floor_unfrozen + covering_pool - premium,
    freeze_bond == 5 * unit,
  }
}

test deposit_restores_the_bond_of_a_frozen_checkpoint() {
  run(honest(False, True, short_pool, @"frozen"))
}

test deposit_restores_the_bond_and_pays_the_premium_when_the_pool_covers_it() {
  run(honest(False, True, covering_pool, @"frozen"))
}

test deposit_clears_the_poison_of_a_frozen_checkpoint() {
  run(honest(True, True, short_pool, @"frozen"))
}

test deposit_on_an_unfrozen_checkpoint_names_zero_and_is_accepted() {
  run(honest(False, False, short_pool, @"unfrozen"))
}

test deposit_on_an_unfrozen_checkpoint_pays_the_premium() {
  run(honest(False, False, covering_pool, @"unfrozen"))
}

// ---------------------------------------------------------------------
// The intent the signatures must name
// ---------------------------------------------------------------------

test deposit_naming_zero_on_a_frozen_checkpoint_is_refused() fail {
  run(honest(False, True, short_pool, @"frozen-names-zero"))
}

test deposit_naming_the_bond_on_an_unfrozen_checkpoint_is_refused() fail {
  run(honest(False, False, short_pool, @"unfrozen-names-bond"))
}

test deposit_signed_for_another_output_is_refused() fail {
  run(honest(False, True, short_pool, @"other-output"))
}

test deposit_signed_for_another_network_is_refused() fail {
  run(honest(False, True, short_pool, @"other-network"))
}

test deposit_signed_for_another_sequence_number_is_refused() fail {
  run(honest(False, True, short_pool, @"other-sn"))
}

test deposit_signed_for_the_epoch_of_the_spent_state_is_refused() fail {
  run(honest(False, True, short_pool, @"old-epoch"))
}

// ---------------------------------------------------------------------
// The signers: the new keys, at the new threshold
// ---------------------------------------------------------------------

test deposit_signed_by_the_keys_of_the_spent_state_is_refused() fail {
  run(honest(False, True, short_pool, @"signed-by-old-keys"))
}

test deposit_signed_by_one_of_two_new_keys_is_refused() fail {
  expect [first, ..] = signed(@"frozen")
  run(frozen_deposit_signed_with([first], short_pool))
}

test deposit_without_signatures_is_refused() fail {
  run(frozen_deposit_signed_with([], short_pool))
}

test deposit_counting_one_position_twice_is_refused() fail {
  expect [first, ..] = signed(@"frozen")
  run(frozen_deposit_signed_with([first, first], short_pool))
}

test deposit_with_a_signature_at_a_position_without_a_key_is_refused() fail {
  expect [first, (_, second)] = signed(@"frozen")
  run(frozen_deposit_signed_with([first, (7, second)], short_pool))
}

test deposit_with_each_signature_at_the_other_keys_position_is_refused() fail {
  expect [(_, first), (_, second)] = signed(@"frozen")
  run(frozen_deposit_signed_with([(0, second), (1, first)], short_pool))
}

test deposit_with_a_damaged_signature_is_refused() fail {
  expect [(i, first), second] = signed(@"frozen")
  let damaged = bytearray.push(
    bytearray.drop(first, 1),
    if bytearray.at(first, 0) == 0 {
      1
    } else {
      0
    },
  )
  run(frozen_deposit_signed_with([(i, damaged), second], short_pool))
}

// ---------------------------------------------------------------------
// The rotation: witnessed and later, the unchanged advance predicate
// ---------------------------------------------------------------------

test deposit_with_a_rotation_signed_by_too_few_keys_is_refused() fail {
  run(frozen_deposit_observing(under_signed()))
}

test deposit_with_a_rotation_receipted_by_too_few_witnesses_is_refused() fail {
  run(frozen_deposit_observing(under_receipted()))
}

test deposit_with_an_unevidenced_rotation_is_refused() fail {
  run(frozen_deposit_observing(unevidenced()))
}

test deposit_with_a_forged_controller_signature_is_refused() fail {
  run(frozen_deposit_observing(forged()))
}

/// The spend arm alone binds the observation to the spent output: the observer
/// would refuse a claim for another output as well (it cannot find the input),
/// so only a run without the observer tells the two apart.
test deposit_spend_arm_alone_accepts_the_honest_claim() {
  run_spend(honest(False, True, short_pool, @"frozen"))
}

test deposit_claiming_another_output_for_the_observer_is_refused() fail {
  let c = honest(False, True, short_pool, @"frozen")
  let other = out_ref(spent.txid, spent.index + 1)
  let claim = ObserverClaim { ..c.observed.claim, own_ref: Some(other) }
  let observed = ObserverEnvelope { ..c.observed, claim }
  let tx = connected_tx(
    old_datum(False, True),
    spent_value(True, short_pool),
    new_datum(False),
    successor_value(short_pool),
    [],
    zero,
    observed,
  )
  run_spend(Case { ..c, observed, tx })
}

// ---------------------------------------------------------------------
// The successor: unfrozen, holding the bond again
// ---------------------------------------------------------------------

test deposit_that_leaves_the_checkpoint_frozen_is_refused() fail {
  run(
    frozen_deposit_into(new_datum(True), floor_frozen + short_pool, short_pool),
  )
}

test deposit_that_leaves_the_checkpoint_frozen_but_holds_the_bond_is_refused() fail {
  run(
    frozen_deposit_into(
      new_datum(True),
      successor_value(short_pool),
      short_pool,
    ),
  )
}

test deposit_unfrozen_without_the_bond_in_its_value_is_refused() fail {
  run(
    frozen_deposit_into(new_datum(False), floor_frozen + short_pool, short_pool),
  )
}

test deposit_one_lovelace_short_of_the_bond_is_refused() fail {
  run(
    frozen_deposit_into(
      new_datum(False),
      successor_value(short_pool) - 1,
      short_pool,
    ),
  )
}

test deposit_one_lovelace_over_the_bond_is_refused() fail {
  run(
    frozen_deposit_into(
      new_datum(False),
      successor_value(short_pool) + 1,
      short_pool,
    ),
  )
}

// ---------------------------------------------------------------------
// The premium: paid exactly when the pool covers it
// ---------------------------------------------------------------------

test deposit_paying_the_premium_short_by_one_lovelace_is_refused() fail {
  run(frozen_deposit_paying([paid(hunter_pkh, premium - 1)], covering_pool))
}

test deposit_paying_the_premium_to_an_output_with_the_token_is_refused() fail {
  run(
    frozen_deposit_paying(
      [
        Output {
          address: from_verification_key(hunter_pkh),
          value: token_value(premium),
          datum: NoDatum,
          reference_script: None,
        },
      ],
      covering_pool,
    ),
  )
}

test deposit_that_does_not_reduce_the_pool_by_the_premium_is_refused() fail {
  run(
    frozen_deposit_into(
      new_datum(False),
      floor_unfrozen + covering_pool,
      covering_pool,
    ),
  )
}

test deposit_that_takes_the_premium_from_a_pool_that_does_not_cover_it_is_refused() fail {
  run(
    frozen_deposit_into(
      new_datum(False),
      floor_unfrozen + short_pool - 1,
      short_pool,
    ),
  )
}

// ---------------------------------------------------------------------
// The frame: nothing else about the checkpoint changes
// ---------------------------------------------------------------------

test deposit_that_changes_the_refund_address_is_refused() fail {
  let moved = from_parts(
    Parts {
      ..parts(new_datum(False)),
      refund_to: bytearray.concat(#"61", other_hunter_pkh),
    },
  )
  run(frozen_deposit_into(moved, successor_value(short_pool), short_pool))
}

test deposit_that_changes_the_birth_slot_is_refused() fail {
  let moved = from_parts(Parts { ..parts(new_datum(False)), born_at: 1 })
  run(frozen_deposit_into(moved, successor_value(short_pool), short_pool))
}

test deposit_that_changes_the_identifier_is_refused() fail {
  let moved = from_parts(
    Parts { ..parts(new_datum(False)), aid: bytearray.push(#"", 69) },
  )
  run(frozen_deposit_into(moved, successor_value(short_pool), short_pool))
}

test deposit_that_mints_under_the_checkpoint_policy_is_refused() fail {
  let observed = advance_envelope(rotation)
  let c = honest(False, True, short_pool, @"frozen")
  run(
    Case {
      ..c,
      tx: connected_tx(
        old_datum(False, True),
        spent_value(True, short_pool),
        new_datum(False),
        successor_value(short_pool),
        [],
        representative(spent.cesr_aid, 1),
        observed,
      ),
    },
  )
}

// ---------------------------------------------------------------------
// The keep option: unchanged
// ---------------------------------------------------------------------

fn keeping(
  old: CheckpointDatumV2,
  input_lovelace: Int,
  new: CheckpointDatumV2,
  successor_lovelace: Int,
) -> Case {
  let observed = advance_envelope(rotation)
  connected_case(
    advance_redeemer(1, bond_keep()),
    observed,
    connected_tx(
      old,
      input_lovelace,
      new,
      successor_lovelace,
      [],
      zero,
      observed,
    ),
  )
}

test keep_of_an_unfrozen_checkpoint_is_accepted() {
  run(
    keeping(
      old_datum(False, False),
      spent_value(False, short_pool),
      new_datum(False),
      successor_value(short_pool),
    ),
  )
}

test keep_of_a_frozen_checkpoint_stays_frozen() {
  run(
    keeping(
      old_datum(False, True),
      spent_value(True, short_pool),
      new_datum(True),
      floor_frozen + short_pool,
    ),
  )
}

test keep_of_a_frozen_checkpoint_cannot_unfreeze_it() fail {
  run(
    keeping(
      old_datum(False, True),
      spent_value(True, short_pool),
      new_datum(False),
      successor_value(short_pool),
    ),
  )
}

test keep_of_an_unfrozen_checkpoint_cannot_freeze_it() fail {
  run(
    keeping(
      old_datum(False, False),
      spent_value(False, short_pool),
      new_datum(True),
      floor_frozen + short_pool,
    ),
  )
}
