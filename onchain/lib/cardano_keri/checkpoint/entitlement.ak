//// #254 S254-E — the shared bounty-entitlement rule (`MOD-271-OBSERVER` plus
//// the thin checkpoint coupling), T254-107.
////
//// This module is the seam between two things that must never be conflated:
////
////   * `MOD-271-COMMITMENT` (the adopted #271 component) owns the commitment
////     object, its lifecycle, and its hash. At that boundary the enforcement
////     evidence digest is an **opaque** 32-byte value: the component cannot
////     and does not claim a supplied digest is the digest of actual evidence.
////   * The enforcement observer owns the **actual** Freeze/Convict evidence.
////     Deriving the canonical digest from that complete payload, and
////     reconciling it with the named mature commitment, is this module's row.
////
//// Consent is not entitlement. A signature proves a party agrees to be paid;
//// it never proves that party earned the payment, because an attacker signs as
//// itself and names itself. Only a prior, matured, hash-committed reservation
//// over (checkpoint, action, actual evidence, payee, nonce) distinguishes the
//// two — which is why `s254_e_signer_only_mutant_accepts_substitution` is a
//// permanent calibration control rather than a curiosity.
////
//// Split and combined checkpoint families call exactly these functions, so the
//// two cannot drift apart into different rules.

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/address.{VerificationKey}
use cardano/transaction.{NoDatum, OutputReference, Transaction}
use cardano_keri/bounty_commitment.{
  BountyAction, BountyCommitment, BountyCommitmentV1, BountyRevealV1,
  CommitmentFamily, ConvictEntitlement, EntitlementValid, EntitlementVerdict,
  FreezeEntitlement, at_or_after, at_or_before, burns_exactly_one,
  entitlement_matches as commitment_entitlement_matches, own_commitment,
}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence}
use cardano_keri/checkpoint/freeze_bond.{ArmedDatum, armed_hunter}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, observe_convict, observe_freeze,
}
use cardano_keri/checkpoint/role.{Active, Armed, Frozen, Role, Tombstone}

/// `DAT-254-ENFORCEMENT-PROOF`. The enforcement family's observer payload.
///
/// It carries the actual KERI evidence exactly as before, and adds the two
/// facts an entitlement verdict needs and evidence alone cannot supply: WHO
/// this enforcement is about to pay, and WHICH prior reservation earns it.
///
/// `payee_pkh` is stated here rather than inferred because an observer must be
/// able to authorize one specific beneficiary. The combined register compares
/// this field against the payee it actually routes value to, so an envelope
/// naming the honest hunter cannot be paired with a redeemer paying an
/// attacker.
///
/// It is declared in THIS module rather than beside the enforcement observer
/// because the A-002 split gives two observers one payload: the enforcement
/// observer validates the KERI evidence inside it, and the entitlement observer
/// validates the reservation that earns it. Both decode this exact type, from
/// one declaration, so the split can never become two payload shapes that drift
/// apart — which is the same argument that moved the 19-field evidence encoder
/// to a single home.
pub type EnforcementProofV1 {
  evidence: EnforcementEvidence,
  payee_pkh: ByteArray,
  reveal: BountyRevealV1,
}

/// The canonical digest of the COMPLETE actual enforcement payload.
///
/// Every field of the observer's evidence is inside the hash — the signed event
/// bytes, every offset, the decoded key material, both thresholds, and both
/// signature lists. Mutating any one of them yields a different digest, which is
/// precisely why a caller-supplied digest can never establish entitlement: the
/// commitment was opened over the digest of the evidence the hunter actually
/// found, and only that evidence reproduces it.
pub fn enforcement_evidence_digest(evidence: EnforcementEvidence) -> ByteArray {
  blake2b_256(cbor.serialise(evidence))
}

/// Reconcile a commitment against ACTUAL evidence.
///
/// This is the component's pure matcher with the opaque digest slot filled in
/// from the real observer payload rather than from anything the caller says.
/// The component still owns the hash recomputation, so independently changing
/// any scope field, the payee, the evidence, or the nonce breaks the match.
pub fn entitlement_matches(
  commitment: BountyCommitment,
  checkpoint_ref: OutputReference,
  action: BountyAction,
  evidence: EnforcementEvidence,
  nonce: ByteArray,
) -> EntitlementVerdict {
  commitment_entitlement_matches(
    commitment,
    checkpoint_ref,
    action,
    enforcement_evidence_digest(evidence),
    nonce,
  )
}

/// The shared settlement rule behind both enforcement actions.
///
/// Every leg is load-bearing:
///
///   * the FAMILY POLICY PIN establishes that the consumed reservation belongs
///     to this release's commitment program at all. `own_commitment` reads the
///     policy out of the consumed input's own script credential and hands it
///     back precisely so the caller can pin it; without that comparison the
///     rule accepts a commitment-shaped datum at ANY script. An attacker can
///     deploy an always-succeeding script, self-mint a marker, park exactly the
///     deposit beside it and author the whole datum — matching scope, its own
///     payee, the digest of someone else's evidence, and an `eligible_after`
///     already in the past — so every remaining leg below would pass and the
///     substitution attack would settle with no reservation, no capital at
///     risk and no aging. `INV-271-COMMITMENT-POLICY-AUTHENTICITY`.
///   * `own_commitment` establishes STRUCTURAL AUTHENTICITY — the named input
///     carries a decodable inline commitment datum and holds exactly its own
///     seed-derived marker plus the applied deposit. A datum that merely looks
///     right without that value is counterfeit.
///   * `entitlement_matches` establishes SCOPE over actual evidence.
///   * the payee equality establishes that the settlement pays the committed
///     beneficiary and no one else. This is the leg the substitution attack
///     breaks, and the reason a signature check cannot replace it.
///   * maturity and expiry establish LIVENESS: a commitment opened in the slot
///     it is revealed in is not aged, and an expired one is dead.
///   * the marker burn makes the reveal SINGLE-USE, so one reservation cannot
///     settle twice.
///
/// Note what is deliberately absent: no fresh signature from the payee is
/// required here. Consent was given when the commitment was opened and its
/// deposit locked; requiring it again would hand any party a veto.
///
/// Note also what this rule does NOT recheck, and why that is sound only
/// because of the policy pin. Scope well-formedness — domain, schema, network,
/// `eligible_after == commit_upper + commit_min_age` and
/// `expires_at == commit_upper + commitment_lifetime` — is established once, at
/// open time, by the genuine commitment program running over
/// `family.parameters`. That inheritance is exactly what the pin buys: a
/// commitment at the release policy provably went through that opening, and a
/// commitment anywhere else is refused before any of these fields is read.
fn validate_entitled_enforcement(
  family: CommitmentFamily,
  action: BountyAction,
  evidence: EnforcementEvidence,
  payee: ByteArray,
  reveal: BountyRevealV1,
  checkpoint_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  when own_commitment(family.parameters, reveal.commitment_ref, tx) is {
    None -> False
    Some((policy, commitment)) -> {
      let BountyCommitmentV1 { scope, payee_pkh, marker, .. } = commitment
      and {
        // The pin comes FIRST: nothing below can authorize a settlement out of
        // a reservation that never belonged to this release's family.
        policy == family.policy,
        entitlement_matches(
          commitment,
          checkpoint_ref,
          action,
          evidence,
          reveal.nonce,
        ) == EntitlementValid,
        payee_pkh == payee,
        at_or_after(tx.validity_range, scope.eligible_after),
        at_or_before(tx.validity_range, scope.expires_at),
        burns_exactly_one(tx, policy, marker),
      }
    }
  }
}

/// Freeze entitlement: the hunter named by this arming transaction must be the
/// payee of a matured, authentic commitment opened over THIS checkpoint, the
/// Freeze action, and the digest of THIS actual evidence.
pub fn validate_freeze_entitlement(
  family: CommitmentFamily,
  evidence: EnforcementEvidence,
  hunter: ByteArray,
  reveal: BountyRevealV1,
  checkpoint_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  validate_entitled_enforcement(
    family,
    FreezeEntitlement,
    evidence,
    hunter,
    reveal,
    checkpoint_ref,
    tx,
  )
}

/// Convict entitlement, over any of ACTIVE, ARMED or FROZEN. The action is a
/// distinct scope value, so a Freeze reservation can never be spent as a
/// Convict one.
pub fn validate_convict_entitlement(
  family: CommitmentFamily,
  evidence: EnforcementEvidence,
  convictor: ByteArray,
  reveal: BountyRevealV1,
  checkpoint_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  validate_entitled_enforcement(
    family,
    ConvictEntitlement,
    evidence,
    convictor,
    reveal,
    checkpoint_ref,
    tx,
  )
}

/// The entitlement half of the A-002 two-observer split.
///
/// The applied enforcement observer measures 16,912 bytes against the 16,133
/// signed-reference publication budget, and the entitlement leg inside it is
/// 2,117 of them — almost entirely generated Plutus-Data codecs that cannot be
/// cut without deleting a demonstrated check. A-002 therefore separates the two
/// responsibilities into two applied observers reading the SAME payload:
///
///   * the enforcement observer owns the actual Freeze/Convict KERI evidence;
///   * this rule owns the mature, authentic, hash-committed reservation that
///     entitles a named payee to be paid for it.
///
/// It deliberately does NOT revalidate the evidence, and that is not a hole.
/// The canonical digest is derived HERE from the COMPLETE payload the envelope
/// carries, so an envelope whose evidence differs in any one field yields a
/// different digest and cannot reproduce the committed hash. What this half
/// cannot establish on its own is that the evidence is genuine KERI — which is
/// exactly the other observer's row. Neither half alone authorizes settlement:
/// binding the two to one envelope value is the register's, and belongs to the
/// post-rebase slice that owns the register's applied credentials.
///
/// This is placement, not a weakening or a duplication of authority.
pub fn validate_entitlement_observation(
  family: CommitmentFamily,
  envelope: ObserverEnvelope,
  tx: Transaction,
) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect proof: EnforcementProofV1 = payload
  let EnforcementProofV1 { evidence, payee_pkh, reveal } = proof
  // The checkpoint reference comes from the claim the checkpoint program
  // independently checks against its own consumed output, never from the
  // payload, so an envelope cannot name one checkpoint to the register and
  // another to its own reservation.
  expect Some(own_ref) = claim.own_ref
  if claim.action == observe_freeze {
    validate_freeze_entitlement(
      family,
      evidence,
      payee_pkh,
      reveal,
      own_ref,
      tx,
    )
  } else if claim.action == observe_convict {
    validate_convict_entitlement(
      family,
      evidence,
      payee_pkh,
      reveal,
      own_ref,
      tx,
    )
  } else {
    fail
  }
}

/// Claim pays the hunter recorded in the ARMED state — stored consent, not a
/// fresh redeemer field and not a fresh signature.
///
/// The beneficiary is read through `armed_hunter` and nothing else, so Claim
/// cannot acquire a new payee. The output must be a datum-free,
/// reference-script-free enterprise payout to that exact key hash; the lovelace
/// magnitude stays with the checkpoint, which owns the bond parameter.
pub fn validate_claim_entitled_payout(
  armed: ArmedDatum,
  hunter_output_index: Int,
  tx: Transaction,
) -> Bool {
  let hunter_pkh = armed_hunter(armed)
  when list.at(tx.outputs, hunter_output_index) is {
    Some(out) -> and {
        out.address.payment_credential == VerificationKey(hunter_pkh),
        out.address.stake_credential == None,
        out.datum == NoDatum,
        out.reference_script == None,
      }
    None -> False
  }
}

/// Admissibility of a conviction's payout structure for the source role.
///
/// The convictor's entitlement is a STRUCTURAL precondition of any payout: a
/// conviction that did not establish entitlement routes nothing at all, whatever
/// its indices say. ARMED additionally keeps the two protected payouts at
/// distinct indices so one output cannot satisfy both the convictor's deposit
/// and the hunter's bond. A tombstone is terminal and admits no payout.
pub fn validate_convict_payouts(
  source: Role,
  valid_entitlement: Bool,
  convictor_index: Int,
  hunter_index: Int,
  tx: Transaction,
) -> Bool {
  and {
    valid_entitlement,
    convictor_index >= 0,
    convictor_index < list.length(tx.outputs),
    when source is {
      Armed -> and {
          convictor_index != hunter_index,
          hunter_index >= 0,
          hunter_index < list.length(tx.outputs),
        }
      Active -> True
      Frozen -> True
      Tombstone -> False
    },
  }
}
