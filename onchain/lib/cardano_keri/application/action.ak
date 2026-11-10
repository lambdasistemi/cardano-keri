//// The operations of KERI's application.
////
//// ## Responsibility
//// The redeemer of the application policy: one constructor per operation of
//// the Lean model's `Action`, naming the output it creates.
////
//// ## Dependencies
//// `singular_state/preimage` for the identity of a registry.
////
//// ## Assumptions
//// None.
////
//// ## Invariants
//// At this revision the policy has one operation, the creation of the
//// configuration record of a registry.

use cardano/transaction.{OutputReference}
use singular_state/preimage.{RegistryIdentity}

pub type Action {
  /// Create the configuration record of `registry` in the output at
  /// `output_index`, in the transaction that spends `seed`.
  CreateConfiguration {
    registry: RegistryIdentity,
    seed: OutputReference,
    output_index: Int,
  }
}
