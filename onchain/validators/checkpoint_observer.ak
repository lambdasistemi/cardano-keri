//// #136/#137/#142 — Register, Advance, and Convict checkpoint observers.
////
//// Each script stake credential can be registered once by anyone and cannot
//// authorize deregistration. Lifecycle owns Register evidence; the distinct
//// Advance observer owns the heavy rotation predicate.

use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use cardano_keri/bounty_commitment.{CommitmentFamily}
use cardano_keri/checkpoint/enforcement_observer.{validate_enforcement}
use cardano_keri/checkpoint/entitlement.{validate_entitlement_observation}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, observe_freeze, observe_migration, validate_advance,
  validate_freeze, validate_registration,
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

/// The rotation evidence observer: the rotation an Advance writes, and the
/// same rotation presented as the evidence of a Freeze (#345). The claim's
/// action tag picks the verdict; both run the unchanged advance predicate.
validator observer_advance(_version: Int) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    if envelope.claim.action == observe_freeze {
      validate_freeze(envelope, tx)
    } else {
      validate_advance(envelope, tx)
    }
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
/// heavy half runs here. It takes no applied parameter: the source generation
/// is the one whose program asks, named by the claim, and the controllers'
/// signed package must name that same policy and output.
validator observer_migration {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    let claim = envelope.claim
    expect claim.action == observe_migration
    // The checkpoint program independently requires this same claim to name
    // its own policy and its own consumed output, so neither side is trusting
    // the other's reading of the transaction.
    expect Some(source_ref) = claim.own_ref
    expect proof: MigrationProof = envelope.payload
    validate_migration_observation(source_ref, proof, tx)
  }

  publish(_redeemer: Data, certificate: Certificate, _tx: Transaction) {
    accept_own_registration_only(certificate)
  }

  else(_) {
    fail
  }
}

/// The enforcement observer is applied with the release commitment family:
/// the policy is the identity of the commitment program whose reservations
/// this release honours, and the nested parameters are its explicit finite
/// age, lifetime and deposit magnitudes.
validator observer_enforcement(_version: Int, commitment: CommitmentFamily) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    validate_enforcement(commitment, envelope, tx)
  }

  publish(_redeemer: Data, certificate: Certificate, _tx: Transaction) {
    accept_own_registration_only(certificate)
  }

  else(_) {
    fail
  }
}

/// #254 A-002 — the entitlement half of the two-observer split.
///
/// It is applied with exactly the arguments `observer_enforcement` takes, and
/// for the same reason: the commitment family's policy is inside this program's
/// own hash, so a release cannot point its entitlement rule at a different
/// reservation program without changing the credential it publishes.
///
/// The split exists because one applied program carrying both responsibilities
/// measures 16,912 bytes against the 16,133-byte signed-reference publication
/// budget, and the entitlement leg inside it is 2,117 bytes of generated
/// Plutus-Data codecs that cannot be cut without deleting a demonstrated check.
/// Splitting moves bytes, not authority: this handler validates the mature
/// authentic reservation, `observer_enforcement` validates the actual KERI
/// evidence, and neither alone authorizes a settlement.
validator observer_entitlement(_version: Int, commitment: CommitmentFamily) {
  withdraw(redeemer: Data, _account: Data, tx: Transaction) {
    expect envelope: ObserverEnvelope = redeemer
    validate_entitlement_observation(commitment, envelope, tx)
  }

  publish(_redeemer: Data, certificate: Certificate, _tx: Transaction) {
    accept_own_registration_only(certificate)
  }

  else(_) {
    fail
  }
}
