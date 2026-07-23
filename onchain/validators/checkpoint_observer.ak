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
//// Stake-credential liveness (A-010): each observer's stake credential is
//// creatable once by anyone and removable by no one. The publish handler is
//// an exhaustive whitelist: only the plain RegisterCredential certificate is
//// accepted; UnregisterCredential, delegation, DRep, pool, committee, and
//// every other certificate constructor fail explicitly. The ledger dispatch
//// already binds the script to its own credential. Withdraw continues to
//// carry selected-family evidence validation.

use cardano/assets.{PolicyId}
use cardano/certificate.{
  AuthorizeConstitutionalCommitteeProxy, Certificate, DelegateCredential,
  RegisterAndDelegateCredential, RegisterCredential,
  RegisterDelegateRepresentative, RegisterStakePool,
  RetireFromConstitutionalCommittee, RetireStakePool, UnregisterCredential,
  UnregisterDelegateRepresentative, UpdateDelegateRepresentative,
}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, validate_enforcement, validate_lifecycle,
}

/// Exhaustive certifying whitelist: plain registration only.
fn accept_own_registration_only(certificate: Certificate) -> Bool {
  when certificate is {
    RegisterCredential { .. } -> True
    UnregisterCredential { .. } -> fail
    DelegateCredential { .. } -> fail
    RegisterAndDelegateCredential { .. } -> fail
    RegisterDelegateRepresentative { .. } -> fail
    UpdateDelegateRepresentative { .. } -> fail
    UnregisterDelegateRepresentative { .. } -> fail
    RegisterStakePool { .. } -> fail
    RetireStakePool { .. } -> fail
    AuthorizeConstitutionalCommitteeProxy { .. } -> fail
    RetireFromConstitutionalCommittee { .. } -> fail
  }
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

  publish(_redeemer: Data, certificate: Certificate, _tx: Transaction) {
    accept_own_registration_only(certificate)
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

  publish(_redeemer: Data, certificate: Certificate, _tx: Transaction) {
    accept_own_registration_only(certificate)
  }

  else(_) {
    fail
  }
}
