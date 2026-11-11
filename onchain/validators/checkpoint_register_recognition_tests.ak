//// The checkpoint validator mints nothing, and checkpoint migration is retired.
////
//// The recognition of each arm and of its successor is exercised beside that
//// arm's own transactions, and the output a fold delivers beside the fold
//// (`keri_application_measurements_tests`). Here:
////
//// - any mint under the checkpoint validator's hash is refused, including the
////   former registration mint with the evidence the lifecycle observer reads;
//// - the former migration spend, written as raw redeemer data over an input
////   the former arm accepted, is refused.

use aiken/builtin
use cardano/address.{Script, from_script}
use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/script_context.{Minting, ScriptContext}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, Withdraw,
  placeholder,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV2}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{ObserverClaim, ObserverEnvelope}
use checkpoint_register
use freeze_fixture.{
  advance_hash, enforcement_hash, entitlement_hash, live, migration_hash,
  network_id, policy, spent, v2_data,
}
use keri_application_connected.{checkpoint_min_ada, d_reg, freeze_bond, premium}
use registry_fixture.{
  application_policy, registry_name, representative, state_policy,
}
use topup_fixture.{registered_with_pool}

fn run_spend(redeemer: Data, own_ref: OutputReference, tx: Transaction) -> Bool {
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
    own_ref,
    tx,
  )
}

fn run_mint(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.else(
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
    ScriptContext { transaction: tx, redeemer, info: Minting(policy) },
  )
}

// ---------------------------------------------------------------------
// The checkpoint validator mints nothing
// ---------------------------------------------------------------------

test the_former_registration_mint_is_refused() fail {
  let register: Data = builtin.constr_data(0, [])
  run_mint(register, registered_with_pool(premium))
}

// ---------------------------------------------------------------------
// Checkpoint migration is retired
// ---------------------------------------------------------------------

/// What the former migration spend was: constructor index two, no fields.
fn former_migrate_out() -> Data {
  builtin.constr_data(2, [])
}

/// The tag the former migration observation carried.
const former_migration_tag: Int = 5

/// A checkpoint the validator recognises under both generations: it holds the
/// retired register token and the representative asset, and the transaction
/// burns the retired token and carries the migration claim the former arm
/// required.
fn migration_attempt() -> (OutputReference, Transaction) {
  let digest = spent.cesr_aid
  let aid_name = deriveAidAssetName(digest)
  let own_ref = OutputReference { transaction_id: #"72", output_index: 72 }
  let input = Input {
    output_reference: own_ref,
    output: Output {
      address: from_script(policy),
      value: from_lovelace(checkpoint_min_ada + d_reg + freeze_bond)
        |> merge(from_asset(policy, aid_name, 1))
        |> merge(representative(digest, 1)),
      datum: InlineDatum(v2_data(live(False, False))),
      reference_script: None,
    },
  }
  let credential = Script(migration_hash)
  let envelope: Data = ObserverEnvelope {
    claim: ObserverClaim {
      action: former_migration_tag,
      checkpoint_policy: policy,
      own_ref: Some(own_ref),
    },
    payload: builtin.i_data(0),
  }
  (
    own_ref,
    Transaction {
      ..placeholder,
      inputs: [input],
      mint: from_asset(policy, aid_name, -1),
      withdrawals: [Pair(credential, 0)],
      redeemers: [Pair(Withdraw(credential), envelope)],
    },
  )
}

test the_former_migration_spend_is_refused() fail {
  let (own_ref, tx) = migration_attempt()
  run_spend(former_migrate_out(), own_ref, tx)
}

test the_former_burning_mint_is_refused() fail {
  let burn: Data = builtin.constr_data(1, [builtin.i_data(0)])
  run_mint(burn, registered_with_pool(premium))
}
