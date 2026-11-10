//// The configuration record of a registry.
////
//// ## Responsibility
//// The decision sites of the Lean model's `configurationShape`,
//// `configurationOf`, `parametersValid` and `createConfiguration`: the record
//// that holds the request parameters and the checkpoint validator's
//// credential of a registry is created once, in the registry's genesis
//// transaction, at the application address, holding exactly its own token,
//// and is read by reference.
////
//// ## Dependencies
//// `application/held` for the records; `application/state_policy` for the
//// state policy of the application; `singular_state/preimage` for the token
//// names; `singular_state/state` for the accounting of a policy's mint.
////
//// ## Assumptions
//// The ledger runs the mint handler of the state policy whenever that policy
//// is minted, and that handler is the public genesis rule; it spends an input
//// at most once. The genesis transaction references an output whose inline
//// datum is the state script's template; the application's first parameter is
//// that template's hash. A configuration record exists only for a registry
//// whose state policy was checked at its genesis, and its token name commits
//// the whole registry (policy and name): a booking that reads the record of a
//// registry needs no other check of its state policy.
////
//// ## Invariants
//// The token of a configuration record is named from the registry it
//// configures. The registry is the one whose state policy is
//// `state(application)`. That the whole mint under the application policy is
//// accounted for is decided by `application/mint`.

use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId, flatten, quantity_of, without_lovelace}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use cardano_keri/application/held.{
  ApplicationParameters, Configuration, held_datum,
}
use cardano_keri/application/state_policy.{state_policy}
use singular_state/preimage.{
  RegistryIdentity, configuration_token_name, state_token_name,
}

/// What a configuration record holds: the request parameters of the registry
/// and the credential of the checkpoint validator where its checkpoints live.
pub type Record {
  parameters: ApplicationParameters,
  checkpoint_credential: Credential,
}

/// Model `parametersValid`: a KERI registry has no retraction window. The Lean
/// fields are naturals, so each integer field of the record is at least zero.
pub fn parameters_valid(parameters: ApplicationParameters) -> Bool {
  and {
    parameters.registration_cost >= 0,
    parameters.minimum_tip >= 0,
    parameters.process_time >= 0,
    parameters.booking_width >= 0,
    parameters.retract_time == 0,
  }
}

/// Model `configurationShape`: the record of the configuration of `registry`
/// that `output` is, when it is one: it sits at the application address,
/// carries a configuration record inline, and holds exactly the one token of
/// the configuration of `registry` besides ADA.
pub fn configuration_record(
  application_policy: PolicyId,
  registry: RegistryIdentity,
  output: Output,
) -> Option<Record> {
  let at_application_address = output.address.payment_credential == Script(
    application_policy,
  )
  let holds_only_the_token = flatten(without_lovelace(output.value)) == [
    (application_policy, configuration_token_name(registry), 1),
  ]
  if at_application_address && holds_only_the_token {
    when held_datum(output) is {
      Some(Configuration { parameters, checkpoint_credential }) ->
        Some(Record { parameters, checkpoint_credential })
      _ -> None
    }
  } else {
    None
  }
}

/// Model `configurationOf`: the record of `registry` among the reference
/// inputs.
pub fn configuration_of(
  application_policy: PolicyId,
  registry: RegistryIdentity,
  reference_inputs: List<Input>,
) -> Option<Record> {
  when
    list.filter_map(
      reference_inputs,
      fn(input) {
        configuration_record(application_policy, registry, input.output)
      },
    )
  is {
    [record, ..] -> Some(record)
    [] -> None
  }
}

/// The bytes an inline datum carries, when it is a byte string; any other datum
/// is none, so a reference input of another shape is passed over.
fn bytes_of(raw: Data) -> Option<ByteArray> {
  let none: fn() -> Option<ByteArray> = fn() { None }
  let bytes: fn() -> Option<ByteArray> = fn() { Some(builtin.un_b_data(raw)) }
  let read = builtin.choose_data(raw, none, none, none, none, bytes)
  read()
}

/// The state script's template: the byte string in the inline datum of a
/// reference input whose BLAKE2b-256 is `state_template_hash`, the parameter of
/// the application. Any other reference input is passed over.
pub fn template_of(
  state_template_hash: ByteArray,
  reference_inputs: List<Input>,
) -> Option<ByteArray> {
  when
    list.filter_map(
      reference_inputs,
      fn(input) {
        when input.output.datum is {
          InlineDatum(raw) ->
            when bytes_of(raw) is {
              Some(bytes) ->
                if blake2b_256(bytes) == state_template_hash {
                  Some(bytes)
                } else {
                  None
                }
              None -> None
            }
          _ -> None
        }
      },
    )
  is {
    [template, ..] -> Some(template)
    [] -> None
  }
}

/// Model `createConfiguration`: `output` is the configuration record of
/// `registry`, created in the genesis transaction of that registry, whose state
/// policy is `state(application_policy)`: the seed is spent once, the state
/// policy mints the registry's state token once, and the parameters are valid.
/// That the state policy is invoked is the same fact as its token being minted.
pub fn create_configuration(
  state_template_hash: ByteArray,
  application_policy: PolicyId,
  registry: RegistryIdentity,
  seed: OutputReference,
  output: Output,
  tx: Transaction,
) -> Bool {
  and {
    when configuration_record(application_policy, registry, output) is {
      Some(record) -> parameters_valid(record.parameters)
      None -> False
    },
    registry.name == state_token_name(seed),
    list.count(tx.inputs, fn(input) { input.output_reference == seed }) == 1,
    when template_of(state_template_hash, tx.reference_inputs) is {
      Some(template) ->
        registry.policy == state_policy(template, application_policy)
      None -> False
    },
    quantity_of(tx.mint, registry.policy, registry.name) == 1,
  }
}
