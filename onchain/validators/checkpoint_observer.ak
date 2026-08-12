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
  ObserverEnvelope, observe_migration, validate_advance, validate_registration,
}
use cardano_keri/migration/checkpoint.{
  MigrationProof, validate_migration_observation,
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

/// #254 A-001 — the promoted checkpoint-migration observer.
///
/// The applied Register program cannot carry the migration verdict and stay
/// under the released 16,133-byte signed-reference transaction ceiling, so the
/// heavy half runs here. `version` and `predecessor_policy` are applied
/// parameters, never redeemer fields: that is what makes an unknown, skipped,
/// or foreign predecessor unrepresentable rather than merely rejected.
validator observer_migration(version: Int, predecessor_policy: PolicyId) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    let claim = envelope.claim
    expect claim.action == observe_migration
    // The checkpoint program independently requires this same claim to name
    // its own policy and its own consumed output, so neither side is trusting
    // the other's reading of the transaction.
    expect Some(source_ref) = claim.own_ref
    expect proof: MigrationProof = envelope.payload
    validate_migration_observation(
      version,
      predecessor_policy,
      claim.checkpoint_policy,
      source_ref,
      proof,
      tx,
    )
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
