//// #136 — the Register-only checkpoint observer.
////
//// The script stake credential can be registered once by anyone and cannot
//// authorize deregistration. Its withdrawal path accepts only a
//// RegistrationEvidence envelope and delegates to the pure registration
//// observer.

use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/observer.{ObserverEnvelope, validate_registration}

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
    validate_registration(hash_proof_policy, d_reg, envelope, tx)
  }

  publish(_redeemer: Data, certificate: Certificate, _tx: Transaction) {
    accept_own_registration_only(certificate)
  }

  else(_) {
    fail
  }
}
