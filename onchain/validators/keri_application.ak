//// KERI's application validator.
////
//// ## Responsibility
//// The application of the Lean model `CardanoKeri.Application` on the public
//// Singular registry. Its hash is both the approval policy of its registry and
//// the payment credential of the application address. `accepted` is
//// `inputsCovered ∧ every action ∧ moneyRouted`: the mint handler decides the
//// actions that create an output and the whole mint and burn, each spend
//// handler decides the action that spends its input and the money the
//// transaction moves. The ledger runs the mint handler whenever the policy
//// appears in the mint and the spend handler for every input at the address, so
//// no input and no mint escapes.
////
//// ## Dependencies
//// `application/mint` and `application/spend`.
////
//// ## Assumptions
//// The first parameter is the BLAKE2b-256 of the compiled public `singular_state`
//// script up to its parameter (the template), so the hash of this validator
//// commits to the state script of its registry; the template itself is published
//// once, in the inline datum of an output a genesis transaction references. The
//// second is the script hash of the lifecycle observer that attests inception
//// evidence. The third is the registry's minimum ADA plus its deposit: the least
//// deposit a booking commits. The fourth is what a fold's holding must hold, the
//// registry's minimum ADA, the checkpoint deposit, the freeze bond and one
//// premium; the fifth the network the refund addresses are recorded for. A
//// deployment sets the checkpoint's numbers equal to `checkpoint_register`'s
//// `d_reg`, `freeze_bond` and `premium` and `network_id`.
////
//// ## Invariants
//// - `mint`: the actions of the redeemer, and nothing else, are minted; every
////   burn is consumed from an input at this address.
//// - `spend`: the action of the redeemer, and the money of the transaction.

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{Action}
use cardano_keri/application/mint.{application_mint}
use cardano_keri/application/spend.{application_spend}

validator keri_application(
  state_template_hash: ByteArray,
  lifecycle_observer: ByteArray,
  minimum_deposit: Int,
  initial_floor: Int,
  network_id: Int,
) {
  mint(redeemer: List<Action>, policy_id: PolicyId, tx: Transaction) {
    application_mint(
      state_template_hash,
      minimum_deposit,
      policy_id,
      redeemer,
      tx,
    )
  }

  spend(
    _datum: Option<Data>,
    redeemer: Data,
    own_reference: OutputReference,
    tx: Transaction,
  ) {
    application_spend(
      lifecycle_observer,
      initial_floor,
      network_id,
      redeemer,
      own_reference,
      tx,
    )
  }

  else(_) {
    fail
  }
}
