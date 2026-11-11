//// The booking of a termination.
////
//// ## Responsibility
//// The decision sites of the Lean model's `terminationShape`, `convictedPending`,
//// `terminationLovelace` and `bookTermination`: a termination approval is minted
//// only for a request placed at the application address holding exactly the
//// registry's active token of the key and that approval, when the transaction
//// spends the convicted checkpoint's pending output for that key, at the
//// checkpoint validator the configuration record names. Anyone may book; no
//// signature is read.
////
//// ## Dependencies
//// `application/configuration` and `application/held`; `checkpoint/datum` for the
//// pending datum; `singular_state/preimage` for the names; the Aiken standard
//// library.
////
//// ## Assumptions
//// A configuration record exists only for a registry whose state policy is
//// `state(A_keri)` (see `application/configuration`), so the record stands in
//// for the Lean's state-policy clause. The checkpoint validator releases the
//// pending output only into a transaction minting one termination approval of
//// its key (`checkpoint_register`, `Release`).
////
//// ## Invariants
//// The name of a termination approval commits the registry and the key.

use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{
  AssetName, PolicyId, flatten, lovelace_of, quantity_of, without_lovelace,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/application/configuration.{Record, configuration_of}
use cardano_keri/application/held.{ApplicationParameters}
use cardano_keri/checkpoint/datum.{pending_aid}
use singular_state/preimage.{
  RegistryIdentity, active_token_name, approval_name, termination_preimage,
}

/// The name of the approval of the termination of `key` in `registry`.
pub fn termination_approval(
  registry: RegistryIdentity,
  key: ByteArray,
) -> AssetName {
  approval_name(termination_preimage(key, registry))
}

/// Model `terminationShape`: `output` sits at the application address with no
/// datum and holds exactly the registry's active token of `key` and the
/// termination approval, besides ADA.
pub fn termination_shape(
  application_policy: PolicyId,
  output: Output,
  registry: RegistryIdentity,
  key: ByteArray,
) -> Bool {
  and {
    list.length(flatten(without_lovelace(output.value))) == 2,
    output.address.payment_credential == Script(application_policy),
    output.datum == NoDatum,
    quantity_of(output.value, registry.policy, active_token_name(registry, key)) == 1,
    quantity_of(
      output.value,
      application_policy,
      termination_approval(registry, key),
    ) == 1,
  }
}

/// Model `convictedPending`: `input` is the pending output a conviction leaves
/// for `key` of `registry`: at the checkpoint validator the record names,
/// carrying the pending-termination datum of the AID `key`, holding exactly
/// the registry's minimum ADA and its one active token of the key.
pub fn convicted_pending(
  record: Record,
  checkpoint_minimum_ada: Int,
  registry: RegistryIdentity,
  key: ByteArray,
  input: Output,
) -> Bool {
  and {
    input.address.payment_credential == record.checkpoint_credential,
    when input.datum is {
      InlineDatum(raw) -> pending_aid(raw) == Some(key)
      _ -> False
    },
    lovelace_of(input.value) == checkpoint_minimum_ada,
    list.length(flatten(without_lovelace(input.value))) == 1,
    quantity_of(input.value, registry.policy, active_token_name(registry, key)) == 1,
  }
}

/// Model `terminationLovelace`: the exact lovelace a termination request holds,
/// the termination carrier and the registry's minimum tip.
pub fn termination_lovelace(
  termination_carrier: Int,
  parameters: ApplicationParameters,
) -> Int {
  termination_carrier + parameters.minimum_tip
}

/// Model `bookTermination` for the action naming `pending`, the output at
/// `index`, `registry` and `key`. The approval is minted once by this check;
/// that it is minted only here is the caller's accounting (`application/mint`).
pub fn book_termination(
  application_policy: PolicyId,
  checkpoint_minimum_ada: Int,
  termination_carrier: Int,
  pending: OutputReference,
  index: Int,
  registry: RegistryIdentity,
  key: ByteArray,
  tx: Transaction,
) -> Bool {
  when
    (
      configuration_of(application_policy, registry, tx.reference_inputs),
      find_input(tx.inputs, pending),
      list.at(tx.outputs, index),
    )
  is {
    (Some(record), Some(input), Some(output)) -> and {
        list.count(tx.inputs, fn(spent) { spent.output_reference == pending }) == 1,
        convicted_pending(
          record,
          checkpoint_minimum_ada,
          registry,
          key,
          input.output,
        ),
        termination_shape(application_policy, output, registry, key),
        lovelace_of(output.value) == termination_lovelace(
          termination_carrier,
          record.parameters,
        ),
        quantity_of(
          tx.mint,
          application_policy,
          termination_approval(registry, key),
        ) == 1,
      }
    _ -> False
  }
}
