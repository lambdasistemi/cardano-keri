//// #136/#137/#142 — Register, Advance, and Freeze checkpoint observers.
////
//// Each script stake credential can be registered once by anyone and cannot
//// authorize deregistration. Lifecycle owns Register evidence; the distinct
//// Advance observer owns the heavy rotation predicate.

use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/enforcement_observer.{validate_enforcement}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, validate_advance, validate_registration,
}

fn accept_own_registration_only(certificate: Certificate) -> Bool {
  expect RegisterCredential { .. } = certificate
  True
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
