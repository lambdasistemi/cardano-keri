//// #115 R3 — four-program checkpoint observer withdrawal validators.
////
//// Three zero-lovelace withdrawal observers split by evidence family:
////
//// - observer_lifecycle: ObserveRegister only. Parameterized by
////   (version, hash_proof_policy, d_reg).
//// - observer_advance: ObserveAdvance only (event-own signatures).
////   Parameterized by (version) only.
//// - observer_enforcement: ObserveFreeze and ObserveConvict. Parameterized
////   by (version) only.
////
//// Each observer's redeemer names the checkpoint hash and the action context,
//// so there is no circular script-hash dependency. Neither observer hash
//// becomes an AID policy or role hash.
////
//// Stake-credential liveness (A-010): each observer's stake credential is
//// creatable once by anyone and removable by no one. Certifying whitelist
//// (A-017 shape): RegisterCredential success; every other constructor fails.

use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, validate_advance, validate_enforcement, validate_lifecycle,
}

/// Exhaustive certifying whitelist: plain registration only (A-017 shape).
fn accept_own_registration_only(certificate: Certificate) -> Bool {
  when certificate is {
    RegisterCredential { .. } -> True
    _ -> fail
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

validator observer_advance(_version: Int) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    validate_advance(envelope, tx)
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
