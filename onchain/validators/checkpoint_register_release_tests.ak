//// The checkpoint validator's `Release` spend beyond the Lean verdicts: the
//// approval must be of this validator's own registry, minted under the
//// application policy it is applied to, minted and not burned.
////
//// The names are computed here from the public Singular preimage, not by the
//// validator under test. The five Lean verdicts are in
//// `checkpoint_register_release_rows_tests`.

use aiken/builtin
use aiken/cbor
use cardano/address.{from_script}
use cardano/assets.{Value, from_asset, from_lovelace, merge}
use cardano/transaction.{InlineDatum, Input, Output, Transaction, placeholder}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum
use checkpoint_register
use freeze_fixture.{
  advance_hash, d_reg, enforcement_hash, entitlement_hash, freeze_bond,
  network_id, policy, premium, spent_ref,
}
use singular_state/preimage.{
  RegistryIdentity, approval_name, termination_preimage,
}

fn lean_registry() -> RegistryIdentity {
  RegistryIdentity {
    policy: rows.lean_state_policy,
    name: rows.lean_registry_name,
  }
}

fn pending_datum() -> Data {
  expect Some(lean) = list_at_zero()
  expect Some(datum) = cbor.deserialise(lean)
  datum
}

/// The datum of the Lean's first release row: a pending termination of the
/// first Lean termination approval's key.
fn list_at_zero() -> Option<ByteArray> {
  when rows.lean_releases is {
    [first, ..] -> Some(first.datum)
    [] -> None
  }
}

fn key() -> ByteArray {
  when rows.lean_termination_approvals is {
    [first, ..] -> first.key
    [] -> fail
  }
}

fn approval_of(registry: RegistryIdentity) -> ByteArray {
  approval_name(termination_preimage(key(), registry))
}

fn released(minted: Value, applied_policy: ByteArray) -> Bool {
  let pending = Output {
    address: from_script(policy),
    value: from_lovelace(4),
    datum: InlineDatum(pending_datum()),
    reference_script: None,
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [Input { output_reference: spent_ref(), output: pending }],
    mint: minted,
  }
  checkpoint_register.checkpoint_register.spend(
    rows.lean_state_policy,
    rows.lean_registry_name,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    applied_policy,
    None,
    builtin.constr_data(5, []),
    spent_ref(),
    tx,
  )
}

fn approval_minted(
  policy_id: ByteArray,
  registry: RegistryIdentity,
  quantity: Int,
) -> Value {
  from_asset(policy_id, approval_of(registry), quantity)
}

test the_pending_output_is_released_into_the_approval_of_its_own_registry() {
  released(
    approval_minted(rows.lean_application_policy, lean_registry(), 1),
    rows.lean_application_policy,
  )
}

test an_approval_of_another_registry_does_not_release() {
  let other = RegistryIdentity {
    policy: rows.lean_application_policy,
    name: rows.lean_registry_name,
  }
  !released(
    approval_minted(rows.lean_application_policy, other, 1),
    rows.lean_application_policy,
  )
}

test an_approval_of_another_registry_name_does_not_release() {
  let other = RegistryIdentity { policy: rows.lean_state_policy, name: #"00" }
  !released(
    approval_minted(rows.lean_application_policy, other, 1),
    rows.lean_application_policy,
  )
}

test an_approval_minted_under_another_policy_does_not_release() {
  !released(
    approval_minted(rows.lean_state_policy, lean_registry(), 1),
    rows.lean_application_policy,
  )
}

test the_validator_applied_to_another_application_is_not_released_by_this_one() {
  !released(
    approval_minted(rows.lean_application_policy, lean_registry(), 1),
    rows.lean_state_policy,
  )
}

test an_approval_burned_does_not_release() {
  !released(
    approval_minted(rows.lean_application_policy, lean_registry(), -1),
    rows.lean_application_policy,
  )
}

test the_approval_beside_another_token_is_released() {
  released(
    merge(
      approval_minted(rows.lean_application_policy, lean_registry(), 1),
      from_asset(rows.lean_state_policy, #"01", 1),
    ),
    rows.lean_application_policy,
  )
}

test a_datum_that_is_not_a_constructor_is_no_pending_termination() {
  and {
    datum.pending_aid(builtin.i_data(5)) == None,
    datum.pending_aid(builtin.b_data(#"01")) == None,
    datum.pending_aid(builtin.list_data([])) == None,
    datum.pending_aid(builtin.constr_data(1, [builtin.i_data(0)])) == None,
    datum.pending_aid(builtin.constr_data(0, [])) == None,
  }
}

test a_pending_termination_names_its_aid() {
  datum.pending_aid(pending_datum()) == Some(key())
}
