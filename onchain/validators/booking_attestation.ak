//// The booking attestation policy.
////
//// ## Responsibility
//// Witnesses, inside the transaction that books requests of an application, the
//// inception of each key whose request it books. For each request of the
//// application its Issue redeemer lists, the policy runs the inception proof (the
//// hash-proof token of the event in an input and burned, the unchanged
//// registration predicate over the event bytes and signatures) and mints one
//// token named by the digest of the claim of that request. It mints nothing it
//// has not verified. Its Burn redeemer mints nothing and needs no evidence.
////
//// ## Dependencies
//// `application/attestation`.
////
//// ## Assumptions
//// The first parameter is the hash-proof policy and the second the checkpoint
//// deposit floor `d_reg` of the registration predicate. The application whose
//// bookings it witnesses requires the tokens of this policy; the application's
//// own hash is not a parameter, the Issue redeemer names it and the policy checks
//// it against the script credential of each request's output.
////
//// ## Invariants
//// Everything minted under the policy is the attestation of a verified request,
//// exactly once, or a burn.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use cardano_keri/application/attestation.{validate_attestation}

validator booking_attestation(hash_proof_policy: PolicyId, d_reg: Int) {
  mint(redeemer: Data, policy_id: PolicyId, tx: Transaction) {
    validate_attestation(hash_proof_policy, d_reg, policy_id, redeemer, tx)
  }

  else(_) {
    fail
  }
}
