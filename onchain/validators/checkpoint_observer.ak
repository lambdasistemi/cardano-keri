//// #115 R1 — the checkpoint observer withdrawal validators (A-004 family
//// split).
////
//// Two zero-lovelace withdrawal observers split by evidence family:
////
//// - observer_lifecycle: ObserveRegister (and, when R3 opens it,
////   ObserveAdvance — reserved tag 1, fail-closed throughout R1). Those
////   actions share KEL-event binding, threshold, signature, and receipt
////   machinery. Parameterized by (version, hash_proof_policy, d_reg).
//// - observer_enforcement: ObserveFreeze and ObserveConvict, sharing the
////   enforcement-evidence binding and fork/lag predicates, plus the A-003
////   Option-C transitional tombstone `evidence_said` equality. Parameterized
////   by (version) only.
////
//// Each observer's redeemer names the checkpoint hash and the action context,
//// so there is no circular script-hash dependency. Neither observer hash
//// becomes an AID policy or role hash.
////
//// Stake-credential liveness: each observer admits ONLY its Withdraw purpose.
//// Every certificate purpose, including deregistration of its own script
//// stake credential, reaches that validator's fail-closed `else` handler, so
//// under Conway's script-credential authorization rule a deregistration
//// cannot be authorized. Registration of both credentials plus this
//// fail-closed dispatch is a deployment invariant, not an operator convention.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, validate_enforcement, validate_lifecycle,
}

validator observer_lifecycle(
  _version: Int,
  hash_proof_policy: PolicyId,
  d_reg: Int,
) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    validate_lifecycle(hash_proof_policy, d_reg, envelope, tx)
  }

  else(_) {
    fail
  }
}

validator observer_enforcement(_version: Int) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    validate_enforcement(envelope, tx)
  }

  else(_) {
    fail
  }
}
