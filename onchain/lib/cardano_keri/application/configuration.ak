//// The configuration record of a registry.
////
//// ## Responsibility
//// The decision sites of the Lean model's `configurationShape`,
//// `parametersValid` and `createConfiguration`: the record that holds the
//// request parameters of a registry is created once, in the registry's genesis
//// transaction, at the application address, holding exactly its own token.
////
//// ## Dependencies
//// `application/held` for the records; `application/state_policy` for the
//// state policy of the application; `singular_state/preimage` for the token
//// names; `singular_state/state` for the accounting of a policy's mint.
////
//// ## Assumptions
//// The ledger runs the mint handler of the state policy whenever that policy
//// is minted, and that handler is the public genesis rule; it spends an input
//// at most once.
////
//// ## Invariants
//// The token of a configuration record is named from the registry it
//// configures. The whole mint under the application policy is that one token,
//// once, so a second record of a registry, or any other token under the
//// policy, is refused. The registry is the one whose state policy is
//// `state(application)`.

use aiken/collection/list
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, flatten, quantity_of, without_lovelace}
use cardano/transaction.{Output, OutputReference, Transaction}
use cardano_keri/application/held.{
  ApplicationParameters, Configuration, held_datum,
}
use cardano_keri/application/state_policy.{state_policy}
use singular_state/preimage.{
  RegistryIdentity, configuration_token_name, state_token_name,
}
use singular_state/state.{policy_delta}

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

/// Model `configurationShape`: the parameters of the configuration record of
/// `registry` that `output` is, when it is one: it sits at the application
/// address, carries a configuration record inline, and holds exactly the one
/// token of the configuration of `registry` besides ADA.
pub fn configuration_parameters(
  application_policy: PolicyId,
  registry: RegistryIdentity,
  output: Output,
) -> Option<ApplicationParameters> {
  let at_application_address = output.address.payment_credential == Script(
    application_policy,
  )
  let holds_only_the_token = flatten(without_lovelace(output.value)) == [
    (application_policy, configuration_token_name(registry), 1),
  ]
  if at_application_address && holds_only_the_token {
    when held_datum(output) is {
      Some(Configuration { parameters }) -> Some(parameters)
      None -> None
    }
  } else {
    None
  }
}

/// Model `createConfiguration`: `output` is the configuration record of
/// `registry`, created in the genesis transaction of that registry, whose state
/// policy is `state(application_policy)`: the seed is spent once, the state
/// policy mints the registry's state token once, the record's token is the
/// whole mint of the application policy, and the parameters are valid. That the
/// state policy is invoked is the same fact as its token being minted.
pub fn create_configuration(
  state_template: ByteArray,
  application_policy: PolicyId,
  registry: RegistryIdentity,
  seed: OutputReference,
  output: Output,
  tx: Transaction,
) -> Bool {
  let configuration_name: AssetName = configuration_token_name(registry)
  and {
    when configuration_parameters(application_policy, registry, output) is {
      Some(parameters) -> parameters_valid(parameters)
      None -> False
    },
    registry.name == state_token_name(seed),
    list.count(tx.inputs, fn(input) { input.output_reference == seed }) == 1,
    policy_delta(tx.mint, application_policy, [Pair(configuration_name, 1)]),
    registry.policy == state_policy(state_template, application_policy),
    quantity_of(tx.mint, registry.policy, registry.name) == 1,
  }
}
