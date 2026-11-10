//// The operations of KERI's application.
////
//// ## Responsibility
//// The redeemers of the application: the mint redeemer lists the operations
//// of the Lean model's `Action` that create an output, the spend redeemer
//// names the operation that spends the input it is attached to.
////
//// ## Dependencies
//// `singular_state/preimage` for the identity of a registry.
////
//// ## Assumptions
//// None.
////
//// ## Invariants
//// One constructor per operation of the Lean `Action`; the input a spend
//// operation names is the input whose redeemer carries it.

use cardano/transaction.{OutputReference}
use singular_state/preimage.{RegistryIdentity}

/// An operation that brings an output into being, listed in the mint redeemer.
pub type Action {
  /// Create the configuration record of `registry` in the output at
  /// `output_index`, in the transaction that spends `seed`.
  CreateConfiguration {
    registry: RegistryIdentity,
    seed: OutputReference,
    output_index: Int,
  }
  /// Book the registration held by the output at `output_index`.
  BookRegistration { output_index: Int }
}

/// The operation that spends an input at the application address.
pub type SpendAction {
  /// Fold the request: the output at `holding_index` is the delivered holding.
  FoldRegistration { holding_index: Int }
  /// Return the request after its deadline.
  ReturnRegistration
  /// Fold the pending termination of `key` in `registry`.
  FoldTermination { registry: RegistryIdentity, key: ByteArray }
}
