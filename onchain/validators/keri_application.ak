//// KERI's application validator.
////
//// ## Responsibility
//// The application of the Lean model `CardanoKeri.Application` on the public
//// Singular registry. Its hash is both the approval policy of its registry and
//// the payment credential of the application address.
////
//// ## Dependencies
//// `application/configuration` decides the creation of a configuration record;
//// `application/state_policy` computes `state(A_keri)`.
////
//// ## Assumptions
//// The parameter is the compiled public `singular_state` script up to its
//// parameter, so the hash of this validator commits to the state script of its
//// registry.
////
//// ## Invariants
//// - `mint`: exactly the Lean `createConfiguration`; any other use of the
////   policy is refused at this revision.
//// - `spend`: refused for every input, since no action at this revision spends
////   an input at the application address.

use aiken/collection/list
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{Action, CreateConfiguration}
use cardano_keri/application/configuration.{create_configuration}

validator keri_application(state_template: ByteArray) {
  mint(redeemer: Action, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      CreateConfiguration { registry, seed, output_index } ->
        when list.at(tx.outputs, output_index) is {
          Some(output) ->
            create_configuration(
              state_template,
              policy_id,
              registry,
              seed,
              output,
              tx,
            )
          None -> False
        }
    }
  }

  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _own_reference: OutputReference,
    _tx: Transaction,
  ) {
    False
  }

  else(_) {
    fail
  }
}
