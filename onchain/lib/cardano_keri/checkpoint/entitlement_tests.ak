//// #254 S254-E — unit proofs for the shared bounty-entitlement rule, T254-107.
////
//// The applied-program rows live in `checkpoint_tests.ak` and
//// `checkpoint_register_tests.ak`, where whole transactions run through whole
//// validators. What lives here is the layer underneath: each leg of the shared
//// rule, exercised on its own, with an accepted honest neighbour beside every
//// rejection so no row can pass because its fixture was quietly broken.
////
//// Every negative in this module states what it changed from the honest case
//// and changes only that. A rejection that could also be explained by a
//// malformed fixture proves nothing about the rule.

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{
  Address, Inline, Script, VerificationKey, from_script, from_verification_key,
}
use cardano/assets.{PolicyId, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/bounty_commitment.{
  BountyAction, BountyCommitment, BountyCommitmentV1, BountyRevealV1,
  BountyScope, CommitmentFamily, CommitmentParameters, ConvictEntitlement,
  EntitlementAction, EntitlementCheckpoint, EntitlementDigestWidth,
  EntitlementHash, EntitlementInvalid, EntitlementMarker, EntitlementNonceWidth,
  EntitlementValid, EntitlementVerdict, FreezeEntitlement, commitment_domain,
  commitment_hash, commitment_preimage, commitment_schema, marker_name,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence}
use cardano_keri/checkpoint/enforcement_vectors as vec
use cardano_keri/checkpoint/entitlement.{
  EnforcementProofV1, enforcement_evidence_digest, entitlement_matches,
  validate_claim_entitled_payout, validate_convict_entitlement,
  validate_convict_payouts, validate_entitlement_observation,
  validate_freeze_entitlement,
}
use cardano_keri/checkpoint/entitlement_vectors as ev
use cardano_keri/checkpoint/freeze_bond.{ArmedV1, ArmedV2}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_freeze,
}
use cardano_keri/checkpoint/role.{Active, Armed, Frozen, Tombstone}
use cardano_keri/checkpoint/threshold.{Unweighted}

// ---------------------------------------------------------------------
// Applied release identity
// ---------------------------------------------------------------------

const commit_policy: PolicyId =
  #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

/// A script that is NOT the release commitment family.
const foreign_policy: PolicyId =
  #"f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0"

const checkpoint_policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

/// EXPLICIT applied magnitudes. Finite, at or above the mandated one-slot age
/// and the 5 ADA floor, and deliberately not a published protocol default: the
/// superseded 10,000-slot constant is never recreated, not even test-side.
const applied_lifetime: Int = 4_321

const applied_deposit: Int = 5_000_000

const family: CommitmentFamily =
  CommitmentFamily {
    policy: commit_policy,
    parameters: CommitmentParameters {
      network: network_id,
      commit_min_age: 1,
      commitment_lifetime: applied_lifetime,
      commit_deposit: applied_deposit,
    },
  }

/// The same magnitudes pinned to the foreign script. This is the un-pinned
/// mutant expressed exactly: if the family policy were never consulted, this
/// field could not change any verdict.
const foreign_family: CommitmentFamily =
  CommitmentFamily { ..family, policy: foreign_policy }

const hunter: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const attacker: ByteArray =
  #"a77ac6e7a77ac6e7a77ac6e7a77ac6e7a77ac6e7a77ac6e7a77ac6e7"

const nonce: ByteArray =
  #"6e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e6365000f"

const other_nonce: ByteArray =
  #"6e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e6365ffff"

const seed_ref: OutputReference =
  OutputReference {
    transaction_id: #"1111111111111111111111111111111111111111111111111111111111111111",
    output_index: 3,
  }

const checkpoint_ref: OutputReference =
  OutputReference {
    transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
    output_index: 1,
  }

const other_checkpoint_ref: OutputReference =
  OutputReference {
    transaction_id: #"3333333333333333333333333333333333333333333333333333333333333333",
    output_index: 1,
  }

const commitment_ref: OutputReference =
  OutputReference {
    transaction_id: #"4444444444444444444444444444444444444444444444444444444444444444",
    output_index: 0,
  }

const evidence: EnforcementEvidence = vec.lag_freeze_wire

// ---------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------

fn scope_for(action: BountyAction, ref: OutputReference) -> BountyScope {
  BountyScope {
    domain: commitment_domain,
    schema: commitment_schema,
    network: network_id,
    checkpoint_policy,
    checkpoint_ref: ref,
    action,
    marker: marker_name(seed_ref),
    commit_upper: 0,
    eligible_after: 1,
    expires_at: applied_lifetime,
  }
}

fn commitment_over(
  scope: BountyScope,
  digest: ByteArray,
  payee_pkh: ByteArray,
  n: ByteArray,
) -> BountyCommitment {
  BountyCommitmentV1 {
    scope,
    payee_pkh,
    hash: commitment_hash(commitment_preimage(scope, digest, payee_pkh, n)),
    marker: scope.marker,
  }
}

/// The honest Freeze reservation: this checkpoint, this action, the digest of
/// this actual evidence, this payee.
fn honest_commitment() -> BountyCommitment {
  commitment_over(
    scope_for(FreezeEntitlement, checkpoint_ref),
    enforcement_evidence_digest(evidence),
    hunter,
    nonce,
  )
}

fn commitment_input(script: PolicyId, commitment: BountyCommitment) -> Input {
  let BountyCommitmentV1 { marker, .. } = commitment
  let datum: Data = commitment
  Input {
    output_reference: commitment_ref,
    output: Output {
      address: from_script(script),
      value: from_lovelace(applied_deposit)
        |> merge(from_asset(script, marker, 1)),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  }
}

fn payout(pkh: ByteArray, lovelace: Int) -> Output {
  Output {
    address: from_verification_key(pkh),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

/// A settlement transaction: the reservation consumed, its marker burned, the
/// deposit refunded, and a validity range inside the reservation's window.
fn settlement_tx(
  script: PolicyId,
  commitment: BountyCommitment,
  lower: Int,
  upper: Int,
) -> Transaction {
  let BountyCommitmentV1 { marker, payee_pkh, .. } = commitment
  Transaction {
    ..placeholder,
    inputs: [commitment_input(script, commitment)],
    outputs: [payout(payee_pkh, applied_deposit)],
    mint: from_asset(script, marker, -1),
    validity_range: interval.between(lower, upper),
  }
}

fn honest_tx() -> Transaction {
  settlement_tx(commit_policy, honest_commitment(), 1, applied_lifetime)
}

fn reveal() -> BountyRevealV1 {
  BountyRevealV1 { commitment_ref, nonce, refund_index: 0 }
}

fn freeze_verdict(
  f: CommitmentFamily,
  e: EnforcementEvidence,
  payee: ByteArray,
  r: BountyRevealV1,
  ref: OutputReference,
  tx: Transaction,
) -> Bool {
  validate_freeze_entitlement(f, e, payee, r, ref, tx)
}

// ---------------------------------------------------------------------
// The accepted honest baseline
// ---------------------------------------------------------------------

/// Every rejection below is measured against this. If this row ever stops
/// passing, the negatives beside it stop meaning anything, because "rejected"
/// would no longer distinguish the mutation from the fixture.
test entitlement_honest_freeze_settlement_accepts() {
  freeze_verdict(
    family,
    evidence,
    hunter,
    reveal(),
    checkpoint_ref,
    honest_tx(),
  )
}

// ---------------------------------------------------------------------
// INV-271-COMMITMENT-POLICY-AUTHENTICITY
// ---------------------------------------------------------------------

/// The counterfeit is structurally perfect and sits at the wrong script.
///
/// Judged against a family pinned to where it actually sits, the very same rule
/// ACCEPTS it — so nothing else objects and the fixture is sound. Judged against
/// the release family, it is refused. The pin is the only difference.
test entitlement_counterfeit_policy_rejects_and_unpinned_mutant_accepts() {
  let counterfeit = honest_commitment()
  let tx = settlement_tx(foreign_policy, counterfeit, 1, applied_lifetime)
  and {
    freeze_verdict(
      foreign_family,
      evidence,
      hunter,
      reveal(),
      checkpoint_ref,
      tx,
    ),
    !freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx),
  }
}

// ---------------------------------------------------------------------
// INV-271-ENTITLEMENT
// ---------------------------------------------------------------------

/// A reveal naming an input the transaction does not consume.
test entitlement_absent_commitment_rejects() {
  let absent = BountyRevealV1 {
    commitment_ref: other_checkpoint_ref,
    nonce,
    refund_index: 0,
  }
  !freeze_verdict(family, evidence, hunter, absent, checkpoint_ref, honest_tx())
}

/// The committed payee is the whole point: an attacker naming itself against
/// somebody else's reservation is refused even though every other leg holds.
test entitlement_substituted_payee_rejects() {
  !freeze_verdict(
    family,
    evidence,
    attacker,
    reveal(),
    checkpoint_ref,
    honest_tx(),
  )
}

/// A commitment whose value is not exactly the marker plus the applied deposit
/// is not an authentic reservation, however right its datum looks.
test entitlement_inexact_deposit_rejects() {
  let commitment = honest_commitment()
  let BountyCommitmentV1 { marker, .. } = commitment
  let datum: Data = commitment
  let tx = Transaction {
    ..honest_tx(),
    inputs: [
      Input {
        output_reference: commitment_ref,
        output: Output {
          address: from_script(commit_policy),
          value: from_lovelace(applied_deposit - 1)
            |> merge(from_asset(commit_policy, marker, 1)),
          datum: InlineDatum(datum),
          reference_script: None,
        },
      },
    ],
  }
  !freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx)
}

/// Without the burn the reservation could settle again.
test entitlement_unburned_marker_rejects() {
  let tx = Transaction { ..honest_tx(), mint: zero }
  !freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx)
}

// ---------------------------------------------------------------------
// INV-271-SCOPE — over ACTUAL evidence
// ---------------------------------------------------------------------

/// The digest is derived from the COMPLETE actual payload, so mutating any one
/// field of the evidence breaks the match. This is what a caller-supplied
/// digest field could never establish.
test entitlement_mutated_evidence_rejects() {
  let mutated = EnforcementEvidence {
    ..evidence,
    native_sn: evidence.native_sn + 1,
  }
  !freeze_verdict(
    family,
    mutated,
    hunter,
    reveal(),
    checkpoint_ref,
    honest_tx(),
  )
}

/// A Freeze reservation is not a Convict reservation.
test entitlement_action_cross_use_rejects() {
  !validate_convict_entitlement(
    family,
    evidence,
    hunter,
    reveal(),
    checkpoint_ref,
    honest_tx(),
  )
}

/// A reservation opened over a different checkpoint cannot settle this one.
test entitlement_foreign_checkpoint_rejects() {
  !freeze_verdict(
    family,
    evidence,
    hunter,
    reveal(),
    other_checkpoint_ref,
    honest_tx(),
  )
}

/// The nonce is inside the hashed preimage, so guessing it wrong breaks the
/// match even with every scope field right.
test entitlement_wrong_nonce_rejects() {
  let wrong = BountyRevealV1 {
    commitment_ref,
    nonce: other_nonce,
    refund_index: 0,
  }
  !freeze_verdict(family, evidence, hunter, wrong, checkpoint_ref, honest_tx())
}

/// The pure matcher agrees with the settlement rule about the honest case, so
/// the rows above are not passing because the matcher is inert.
test entitlement_matches_accepts_the_honest_preimage() {
  entitlement_matches(
    honest_commitment(),
    checkpoint_ref,
    FreezeEntitlement,
    evidence,
    nonce,
  ) == EntitlementValid
}

// ---------------------------------------------------------------------
// INV-271-AGE and INV-271-LIFETIME
// ---------------------------------------------------------------------

/// Revealed in the very slot it was opened in: `eligible_after` is
/// `commit_upper + commit_min_age`, so slot 0 is not aged.
test entitlement_same_slot_reveal_rejects() {
  let tx = settlement_tx(
    commit_policy,
    honest_commitment(),
    0,
    applied_lifetime,
  )
  !freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx)
}

/// One slot of age is enough — the boundary is admitted, not merely the
/// interior, so the row above pins an exact edge rather than a vague gap.
test entitlement_exactly_one_slot_of_age_accepts() {
  let tx = settlement_tx(commit_policy, honest_commitment(), 1, 1)
  freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx)
}

/// Past `expires_at` the reservation is dead.
test entitlement_expired_reveal_rejects() {
  let tx = settlement_tx(
    commit_policy,
    honest_commitment(),
    applied_lifetime + 1,
    applied_lifetime + 2,
  )
  !freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx)
}

/// The last admissible slot is admitted.
test entitlement_reveal_at_exact_expiry_accepts() {
  let tx = settlement_tx(
    commit_policy,
    honest_commitment(),
    1,
    applied_lifetime,
  )
  freeze_verdict(family, evidence, hunter, reveal(), checkpoint_ref, tx)
}

// ---------------------------------------------------------------------
// A-002 — the entitlement observer's own dispatch
// ---------------------------------------------------------------------
//
// These rows are the disjoint half of the two-observer split: the entitlement
// observer reads the SAME `EnforcementProofV1` the enforcement observer reads,
// and validates the reservation rather than the KERI evidence.
//
// Every row below is PAIRED. It asserts that the honest same-envelope
// neighbour is ACCEPTED and that its single named mutation is REJECTED, in one
// assertion. That shape is not decoration: a rejection row on its own passes
// against a dispatch that refuses everything, so a fail-closed or inert
// implementation would show a full green wall of negatives. Pairing makes each
// row fail while the dispatch is inert, and makes each row's pass mean the
// dispatch actually distinguishes the two cases.
//
// One exception is stated rather than hidden: the unknown-action row must be a
// `fail` test, because refusing an action it does not own is an error and not a
// `False`, and an error cannot be conjoined with an accepted neighbour. It is
// therefore the one row that is satisfied by an inert dispatch. The dispatch's
// non-vacuity is established instead by
// `s254_e_entitlement_observer_routes_on_the_action_tag`, which requires the
// two known tags to reach DIFFERENT reservations.
//
// What is deliberately NOT here: the register-level missing-observer and
// mismatched-envelope mutants. Those need a second applied register credential,
// which does not exist until the register-arity slice is accepted, and
// simulating them at this layer would prove something weaker while looking like
// the real thing.

/// The envelope the split's two observers share.
fn enforcement_envelope(
  action: Int,
  own_ref: OutputReference,
  payee: ByteArray,
  e: EnforcementEvidence,
  r: BountyRevealV1,
) -> ObserverEnvelope {
  let proof: Data = EnforcementProofV1 {
    evidence: e,
    payee_pkh: payee,
    reveal: r,
  }
  ObserverEnvelope {
    claim: ObserverClaim { action, checkpoint_policy, own_ref: Some(own_ref) },
    payload: proof,
  }
}

fn honest_freeze_envelope() -> ObserverEnvelope {
  enforcement_envelope(
    observe_freeze,
    checkpoint_ref,
    hunter,
    evidence,
    reveal(),
  )
}

fn honest_convict_envelope() -> ObserverEnvelope {
  enforcement_envelope(
    observe_convict,
    checkpoint_ref,
    hunter,
    evidence,
    reveal(),
  )
}

fn observed_with(
  f: CommitmentFamily,
  envelope: ObserverEnvelope,
  tx: Transaction,
) -> Bool {
  validate_entitlement_observation(f, envelope, tx)
}

fn observed(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  observed_with(family, envelope, tx)
}

/// The Convict reservation: same checkpoint and evidence, different action.
fn convict_commitment() -> BountyCommitment {
  commitment_over(
    scope_for(ConvictEntitlement, checkpoint_ref),
    enforcement_evidence_digest(evidence),
    hunter,
    nonce,
  )
}

fn convict_tx() -> Transaction {
  settlement_tx(commit_policy, convict_commitment(), 1, applied_lifetime)
}

/// The honest baseline for this half: both enforcement actions settle against
/// their own reservation through the entitlement observer alone.
test s254_e_entitlement_observer_accepts_honest_envelopes() {
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    observed(honest_convict_envelope(), convict_tx()),
  }
}

/// The dispatch reads the claim's action tag and nothing else decides it: each
/// honest envelope is accepted against its own reservation and refused against
/// the other's, even though checkpoint, evidence, payee and nonce are identical.
///
/// This is the row that makes the whole section non-vacuous: an inert dispatch
/// cannot satisfy it, and neither can one that ignores the tag.
test s254_e_entitlement_observer_routes_on_the_action_tag() {
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    observed(honest_convict_envelope(), convict_tx()),
    !observed(honest_convict_envelope(), honest_tx()),
    !observed(honest_freeze_envelope(), convict_tx()),
  }
}

/// INV-271-ENTITLEMENT. An attacker naming itself in the payload cannot settle
/// somebody else's reservation, though every other leg is untouched.
test s254_e_entitlement_observer_substituted_payee_rejects() {
  let substituted = enforcement_envelope(
    observe_freeze,
    checkpoint_ref,
    attacker,
    evidence,
    reveal(),
  )
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(substituted, honest_tx()),
  }
}

/// INV-271-ENTITLEMENT. A reveal naming an input the transaction never consumes
/// has no reservation behind it.
test s254_e_entitlement_observer_absent_commitment_rejects() {
  let absent = enforcement_envelope(
    observe_freeze,
    checkpoint_ref,
    hunter,
    evidence,
    BountyRevealV1 {
      commitment_ref: other_checkpoint_ref,
      nonce,
      refund_index: 0,
    },
  )
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(absent, honest_tx()),
  }
}

/// INV-271-SCOPE, over ACTUAL evidence. The observer derives the canonical
/// digest from the complete payload it was handed, so an envelope carrying
/// evidence that differs in one integer cannot reproduce the committed hash.
///
/// This is the leg that makes it safe for this half not to revalidate KERI: the
/// evidence is not trusted here, it is hashed.
test s254_e_entitlement_observer_mutated_evidence_rejects() {
  let mutated = enforcement_envelope(
    observe_freeze,
    checkpoint_ref,
    hunter,
    EnforcementEvidence { ..evidence, native_sn: evidence.native_sn + 1 },
    reveal(),
  )
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(mutated, honest_tx()),
  }
}

/// INV-271-SCOPE. The nonce is inside the hashed preimage.
test s254_e_entitlement_observer_wrong_nonce_rejects() {
  let wrong = enforcement_envelope(
    observe_freeze,
    checkpoint_ref,
    hunter,
    evidence,
    BountyRevealV1 { commitment_ref, nonce: other_nonce, refund_index: 0 },
  )
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(wrong, honest_tx()),
  }
}

/// INV-271-SCOPE. The observer takes its checkpoint reference from the claim's
/// `own_ref`, so a reservation opened over a different checkpoint cannot settle
/// this one.
test s254_e_entitlement_observer_foreign_checkpoint_rejects() {
  let foreign = enforcement_envelope(
    observe_freeze,
    other_checkpoint_ref,
    hunter,
    evidence,
    reveal(),
  )
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(foreign, honest_tx()),
  }
}

/// INV-271-AGE. The boundary is pinned on both sides: one slot of age is
/// admitted, and a reveal in the very slot the commitment was opened in is not.
test s254_e_entitlement_observer_age_boundary_is_exact() {
  let aged = settlement_tx(commit_policy, honest_commitment(), 1, 1)
  let same_slot = settlement_tx(
    commit_policy,
    honest_commitment(),
    0,
    applied_lifetime,
  )
  and {
    observed(honest_freeze_envelope(), aged),
    !observed(honest_freeze_envelope(), same_slot),
  }
}

/// INV-271-LIFETIME. The last admissible slot settles; one slot later is dead.
test s254_e_entitlement_observer_expiry_boundary_is_exact() {
  let expired = settlement_tx(
    commit_policy,
    honest_commitment(),
    applied_lifetime + 1,
    applied_lifetime + 2,
  )
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(honest_freeze_envelope(), expired),
  }
}

/// INV-271-VALUE. The reservation must be authentic value, not merely an
/// authentic-looking datum, and its marker must burn so one reservation cannot
/// settle twice.
test s254_e_entitlement_observer_value_legs_reject() {
  let commitment = honest_commitment()
  let BountyCommitmentV1 { marker, .. } = commitment
  let datum: Data = commitment
  let short_deposit = Transaction {
    ..honest_tx(),
    inputs: [
      Input {
        output_reference: commitment_ref,
        output: Output {
          address: from_script(commit_policy),
          value: from_lovelace(applied_deposit - 1)
            |> merge(from_asset(commit_policy, marker, 1)),
          datum: InlineDatum(datum),
          reference_script: None,
        },
      },
    ],
  }
  and {
    observed(honest_freeze_envelope(), honest_tx()),
    !observed(
      honest_freeze_envelope(),
      Transaction { ..honest_tx(), mint: zero },
    ),
    !observed(honest_freeze_envelope(), short_deposit),
  }
}

/// INV-271-COMMITMENT-POLICY-AUTHENTICITY. The counterfeit is structurally
/// perfect and sits at a script the attacker controls.
///
/// Judged against a family pinned to where it actually sits, this very rule
/// ACCEPTS it, so nothing else objects and the fixture is sound. Judged against
/// the release family it is refused. The applied family pin is the only
/// difference — which is precisely why the second observer must be applied to
/// the family too, rather than reading it from a redeemer.
test s254_e_entitlement_observer_counterfeit_policy_rejects() {
  let tx = settlement_tx(
    foreign_policy,
    honest_commitment(),
    1,
    applied_lifetime,
  )
  and {
    observed_with(foreign_family, honest_freeze_envelope(), tx),
    !observed_with(family, honest_freeze_envelope(), tx),
  }
}

/// An action this observer does not own is an error, exactly as in the
/// enforcement observer's dispatch: refusing it as `False` would let a caller
/// distinguish "not mine" from "not entitled".
///
/// Stated honestly: this is the one row in this section an inert dispatch also
/// satisfies. `s254_e_entitlement_observer_routes_on_the_action_tag` is what
/// establishes that the dispatch is not inert.
test s254_e_entitlement_observer_unknown_action_fails() fail {
  observed(
    enforcement_envelope(
      observe_advance,
      checkpoint_ref,
      hunter,
      evidence,
      reveal(),
    ),
    honest_tx(),
  )
}

// ---------------------------------------------------------------------
// INV-271-CONSENT — stored payee, no fresh signature
// ---------------------------------------------------------------------

fn armed_v1() -> Data {
  let d: Data = ArmedV1 {
    checkpoint: vec.lag_freeze_tip,
    hunter_pkh: hunter,
    deadline: 9,
  }
  d
}

fn armed_v2_datum() -> freeze_bond.ArmedDatum {
  ArmedV2 { checkpoint: vec.lag_freeze_tip, hunter_pkh: hunter, deadline: 9 }
}

fn armed_v1_datum() -> freeze_bond.ArmedDatum {
  ArmedV1 { checkpoint: vec.lag_freeze_tip, hunter_pkh: hunter, deadline: 9 }
}

fn claim_tx(out: Output) -> Transaction {
  Transaction { ..placeholder, outputs: [out], extra_signatories: [] }
}

/// The beneficiary comes from stored consent, and NO signature is required —
/// `extra_signatories` is empty. Requiring one would hand any party a veto.
test entitlement_claim_pays_stored_hunter_without_any_signature() {
  let tx = claim_tx(payout(hunter, 5_000_000))
  and {
    tx.extra_signatories == [],
    validate_claim_entitled_payout(armed_v2_datum(), 0, tx),
  }
}

/// Both ARMED constructors resolve the payee identically: that is what keeping
/// one `ArmedDatum` sum buys, and why the migration family can carry either.
test entitlement_claim_reads_both_armed_versions_identically() {
  let tx = claim_tx(payout(hunter, 5_000_000))
  and {
    validate_claim_entitled_payout(armed_v1_datum(), 0, tx),
    validate_claim_entitled_payout(armed_v2_datum(), 0, tx),
  }
}

/// Claim cannot acquire a new beneficiary.
test entitlement_claim_to_other_payee_rejects() {
  !validate_claim_entitled_payout(
    armed_v2_datum(),
    0,
    claim_tx(payout(attacker, 5_000_000)),
  )
}

/// A datum-bearing or script-locked output is not an enterprise payout.
test entitlement_claim_to_datum_bearing_output_rejects() {
  let out = Output {
    address: from_verification_key(hunter),
    value: from_lovelace(5_000_000),
    datum: InlineDatum(armed_v1()),
    reference_script: None,
  }
  !validate_claim_entitled_payout(armed_v2_datum(), 0, claim_tx(out))
}

/// A staked address is not the enterprise payout the rule requires.
test entitlement_claim_to_staked_address_rejects() {
  let out = Output {
    address: Address {
      payment_credential: VerificationKey(hunter),
      stake_credential: Some(Inline(Script(checkpoint_policy))),
    },
    value: from_lovelace(5_000_000),
    datum: NoDatum,
    reference_script: None,
  }
  !validate_claim_entitled_payout(armed_v2_datum(), 0, claim_tx(out))
}

/// An index past the end of the output list is not a payout.
test entitlement_claim_out_of_range_index_rejects() {
  !validate_claim_entitled_payout(
    armed_v2_datum(),
    7,
    claim_tx(payout(hunter, 5_000_000)),
  )
}

// ---------------------------------------------------------------------
// Conviction payout admissibility
// ---------------------------------------------------------------------

fn two_output_tx() -> Transaction {
  Transaction {
    ..placeholder,
    outputs: [payout(hunter, 1), payout(attacker, 2)],
  }
}

/// Entitlement is a STRUCTURAL precondition: a conviction that established none
/// routes nothing at all, whatever its indices say.
test entitlement_convict_payouts_require_entitlement() {
  and {
    validate_convict_payouts(Active, True, 0, 0, two_output_tx()),
    !validate_convict_payouts(Active, False, 0, 0, two_output_tx()),
  }
}

/// ARMED keeps the two protected payouts at distinct indices, so one output
/// cannot satisfy both the convictor's deposit and the hunter's bond.
test entitlement_convict_armed_requires_distinct_indices() {
  and {
    validate_convict_payouts(Armed, True, 0, 1, two_output_tx()),
    !validate_convict_payouts(Armed, True, 0, 0, two_output_tx()),
  }
}

/// ACTIVE and FROZEN carry one protected payout, so index equality is not a
/// defect there — stated as an accepted neighbour so the row above is known to
/// be about ARMED rather than about indices in general.
test entitlement_convict_active_and_frozen_allow_one_index() {
  and {
    validate_convict_payouts(Active, True, 0, 0, two_output_tx()),
    validate_convict_payouts(Frozen, True, 0, 0, two_output_tx()),
  }
}

/// A tombstone is terminal and admits no payout at all.
test entitlement_convict_tombstone_admits_no_payout() {
  !validate_convict_payouts(Tombstone, True, 0, 1, two_output_tx())
}

/// Indices must actually address an output.
test entitlement_convict_out_of_range_indices_reject() {
  and {
    !validate_convict_payouts(Active, True, 9, 0, two_output_tx()),
    !validate_convict_payouts(Active, True, -1, 0, two_output_tx()),
    !validate_convict_payouts(Armed, True, 0, 9, two_output_tx()),
  }
}

// ---------------------------------------------------------------------
// The digest itself
// ---------------------------------------------------------------------

/// The canonical digest is the blake2b-256 of the complete serialized payload —
/// stated here so the Haskell mirror has one exact statement to agree with.
test entitlement_evidence_digest_is_blake2b_256_of_the_whole_payload() {
  enforcement_evidence_digest(evidence) == blake2b_256(cbor.serialise(evidence))
}

/// Distinct payloads have distinct digests. Without this the scope rows above
/// could pass against a constant.
test entitlement_evidence_digest_separates_payloads() {
  let mutated = EnforcementEvidence {
    ..evidence,
    native_sn: evidence.native_sn + 1,
  }
  enforcement_evidence_digest(evidence) != enforcement_evidence_digest(mutated)
}

// ---------------------------------------------------------------------
// Cross-language parity against the generated entitlement vectors
// ---------------------------------------------------------------------
//
// Everything below turns on `entitlement_vectors.ak`, whose every value comes
// from ONE Haskell computation and from nothing else. The rows here are what
// make those numbers load-bearing: without them the committed module would be
// constants nobody reads, and `check-bounty-entitlement-vectors.sh` would only
// be proving that a file equals itself.
//
// The parity claim is deliberately narrow and is stated so it can be checked:
// the two languages agree on the canonical digest of the COMPLETE actual
// enforcement payload, on the wire bytes of the shapes S254-E introduced, and
// on the shared matcher's VERDICT — including which reason it gives. It is not
// a claim about the settlement rule's transaction legs, which no constant can
// express; those are the rows above and their Haskell twins.

/// The fixture the Haskell source hashed, rebuilt here field for field.
///
/// It is spelled out rather than reused from `enforcement_vectors` on purpose:
/// the whole point is that two independent constructions of the same record
/// serialize identically. Every field's value is a committed vector, so a
/// silent edit on either side moves `golden_evidence` and reddens the row
/// below before it can reach a digest.
fn parity_evidence() -> EnforcementEvidence {
  EnforcementEvidence {
    event_bytes: ev.event_bytes,
    off_t: 1,
    off_i: 2,
    off_s: 3,
    off_d: 4,
    off_k: [5],
    off_kt: 6,
    off_n: [7],
    off_nt: 8,
    off_bt: 9,
    native_sn: 10,
    said: ev.said,
    revealed_keys: [ev.verkey],
    next_keys: [ev.key_digest],
    cur_threshold: Unweighted(1),
    next_threshold: Unweighted(1),
    toad: 0,
    ctrl_sigs: [(0, ev.controller_signature)],
    wit_sigs: [(0, ev.witness_signature)],
  }
}

/// Aiken's serialization of the rebuilt payload is the exact byte string the
/// Haskell source emitted. This is the row every digest row below rests on: a
/// digest agreement over payloads that were not the same payload would be a
/// coincidence, not parity.
test entitlement_vectors_evidence_bytes_agree() {
  cbor.serialise(parity_evidence()) == ev.golden_evidence
}

/// The canonical digest agrees across the two languages.
test entitlement_vectors_evidence_digest_agrees() {
  enforcement_evidence_digest(parity_evidence()) == ev.evidence_digest
}

/// Every independently mutated field of the payload moves the digest to the
/// exact value the Haskell source computed for that same mutation.
///
/// One row per field, because "the digest covers the payload" is only true if
/// no field is outside it — and a single lumped mutation would pass while
/// eighteen fields sat unhashed.
test entitlement_vectors_every_evidence_field_agrees() {
  let base = parity_evidence()
  let flipped_event = ev.event_bytes |> flip_last
  let flipped_said = ev.said |> flip_last
  let flipped_verkey = ev.verkey |> flip_last
  let flipped_key_digest = ev.key_digest |> flip_last
  let flipped_signature = ev.controller_signature |> flip_last
  and {
    digest_of(EnforcementEvidence { ..base, event_bytes: flipped_event }) == ev.mut_ev_event_bytes,
    digest_of(EnforcementEvidence { ..base, off_t: 11 }) == ev.mut_ev_off_t,
    digest_of(EnforcementEvidence { ..base, off_i: 12 }) == ev.mut_ev_off_i,
    digest_of(EnforcementEvidence { ..base, off_s: 13 }) == ev.mut_ev_off_s,
    digest_of(EnforcementEvidence { ..base, off_d: 14 }) == ev.mut_ev_off_d,
    digest_of(EnforcementEvidence { ..base, off_k: [15] }) == ev.mut_ev_off_k,
    digest_of(EnforcementEvidence { ..base, off_kt: 16 }) == ev.mut_ev_off_kt,
    digest_of(EnforcementEvidence { ..base, off_n: [17] }) == ev.mut_ev_off_n,
    digest_of(EnforcementEvidence { ..base, off_nt: 18 }) == ev.mut_ev_off_nt,
    digest_of(EnforcementEvidence { ..base, off_bt: 19 }) == ev.mut_ev_off_bt,
    digest_of(EnforcementEvidence { ..base, native_sn: 20 }) == ev.mut_ev_native_sn,
    digest_of(EnforcementEvidence { ..base, said: flipped_said }) == ev.mut_ev_said,
    digest_of(EnforcementEvidence { ..base, revealed_keys: [flipped_verkey] }) == ev.mut_ev_revealed_keys,
    digest_of(EnforcementEvidence { ..base, next_keys: [flipped_key_digest] }) == ev.mut_ev_next_keys,
    digest_of(EnforcementEvidence { ..base, cur_threshold: Unweighted(2) }) == ev.mut_ev_cur_threshold,
    digest_of(EnforcementEvidence { ..base, next_threshold: Unweighted(2) }) == ev.mut_ev_next_threshold,
    digest_of(EnforcementEvidence { ..base, toad: 1 }) == ev.mut_ev_toad,
    digest_of(
      EnforcementEvidence { ..base, ctrl_sigs: [(0, flipped_signature)] },
    ) == ev.mut_ev_ctrl_sigs,
    digest_of(
      EnforcementEvidence { ..base, wit_sigs: [(1, ev.witness_signature)] },
    ) == ev.mut_ev_wit_sigs,
  }
}

/// The digest rows above would still pass if every committed mutant happened
/// to equal the honest digest. This is the control that says they do not.
test entitlement_vectors_mutant_digests_are_distinct() {
  let mutants = [
    ev.mut_ev_event_bytes,
    ev.mut_ev_off_t,
    ev.mut_ev_off_i,
    ev.mut_ev_off_s,
    ev.mut_ev_off_d,
    ev.mut_ev_off_k,
    ev.mut_ev_off_kt,
    ev.mut_ev_off_n,
    ev.mut_ev_off_nt,
    ev.mut_ev_off_bt,
    ev.mut_ev_native_sn,
    ev.mut_ev_said,
    ev.mut_ev_revealed_keys,
    ev.mut_ev_next_keys,
    ev.mut_ev_cur_threshold,
    ev.mut_ev_next_threshold,
    ev.mut_ev_toad,
    ev.mut_ev_ctrl_sigs,
    ev.mut_ev_wit_sigs,
  ]
  and {
    list.length(mutants) == 19,
    list.all(mutants, fn(digest) { digest != ev.evidence_digest }),
    list.unique(mutants) == mutants,
  }
}

/// The shapes S254-E introduced serialize identically in the two languages.
///
/// `golden_armed_v1` and `golden_armed_v2` are the row that pins the shared
/// sum's constructor indices across the boundary: an off-chain mirror that
/// wrote the successor at constructor zero would produce a datum the validator
/// still decodes, and the two would silently disagree about which version was
/// written.
test entitlement_vectors_shapes_agree() {
  let armed_state = parity_armed_state()
  and {
    cbor.serialise(parity_commitment()) == ev.golden_commitment,
    cbor.serialise(parity_reveal()) == ev.golden_reveal,
    cbor.serialise(parity_parameters()) == ev.golden_commitment_parameters,
    cbor.serialise(parity_family()) == ev.golden_commitment_family,
    cbor.serialise(
      ArmedV1 {
        checkpoint: armed_state,
        hunter_pkh: ev.hunter,
        deadline: ev.deadline,
      },
    ) == ev.golden_armed_v1,
    cbor.serialise(
      ArmedV2 {
        checkpoint: armed_state,
        hunter_pkh: ev.hunter,
        deadline: ev.deadline,
      },
    ) == ev.golden_armed_v2,
  }
}

/// The two ARMED constructors are genuinely different bytes. Without this the
/// row above would pass for a mirror that collapsed them.
test entitlement_vectors_armed_versions_are_distinguishable() {
  ev.golden_armed_v1 != ev.golden_armed_v2
}

/// The shared matcher reaches the same VERDICT — and the same reason — as the
/// Haskell mirror, over ACTUAL evidence, for every named row.
///
/// Verdict parity is the point. Two matchers can agree on every serialized
/// byte and still disagree about a boundary; only comparing the outcome, with
/// its reason, rules that out.
test entitlement_vectors_verdicts_agree() {
  let commitment = parity_commitment()
  let evidence_payload = parity_evidence()
  let checkpoint = parity_checkpoint_ref()
  let other_checkpoint = OutputReference {
    transaction_id: ev.checkpoint_txid,
    output_index: ev.other_checkpoint_index,
  }
  and {
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
        FreezeEntitlement,
        evidence_payload,
        ev.nonce,
      ),
    ) == ev.verdict_honest,
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
        FreezeEntitlement,
        evidence_payload,
        ev.short_nonce,
      ),
    ) == ev.verdict_short_nonce,
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
        ConvictEntitlement,
        evidence_payload,
        ev.nonce,
      ),
    ) == ev.verdict_convict_action,
    verdict_tag(
      entitlement_matches(
        commitment,
        other_checkpoint,
        FreezeEntitlement,
        evidence_payload,
        ev.nonce,
      ),
    ) == ev.verdict_other_checkpoint,
    verdict_tag(
      entitlement_matches(
        BountyCommitmentV1 { ..commitment, marker: ev.other_marker },
        checkpoint,
        FreezeEntitlement,
        evidence_payload,
        ev.nonce,
      ),
    ) == ev.verdict_marker_left_scope,
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
        FreezeEntitlement,
        EnforcementEvidence {
          ..evidence_payload,
          event_bytes: ev.event_bytes |> flip_last,
        },
        ev.nonce,
      ),
    ) == ev.verdict_substituted_evidence,
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
        FreezeEntitlement,
        evidence_payload,
        ev.nonce |> flip_last,
      ),
    ) == ev.verdict_substituted_nonce,
    verdict_tag(
      entitlement_matches(
        BountyCommitmentV1 { ..commitment, payee_pkh: substituted_payee },
        checkpoint,
        FreezeEntitlement,
        evidence_payload,
        ev.nonce,
      ),
    ) == ev.verdict_substituted_payee,
  }
}

/// The committed verdict set distinguishes. If every row carried the same tag
/// the row above would pass against a matcher that ignored its arguments.
test entitlement_vectors_verdict_set_is_not_constant() {
  and {
    ev.verdict_honest == 0,
    ev.verdict_short_nonce != ev.verdict_honest,
    ev.verdict_convict_action != ev.verdict_short_nonce,
    ev.verdict_other_checkpoint != ev.verdict_convict_action,
    ev.verdict_marker_left_scope != ev.verdict_other_checkpoint,
    ev.verdict_substituted_evidence != ev.verdict_marker_left_scope,
  }
}

// ---------------------------------------------------------------------
// Parity fixture, rebuilt from the committed vectors and nothing else
// ---------------------------------------------------------------------

/// The payee the substitution row names. It is the only value in the parity
/// fixture that is not a committed vector, because its whole role is to be a
/// key the reservation never named.
const substituted_payee: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn digest_of(payload: EnforcementEvidence) -> ByteArray {
  enforcement_evidence_digest(payload)
}

/// Flip the low bit of the last byte, leaving the width unchanged — the same
/// perturbation the Haskell source applies.
///
/// Aiken has no integer xor operator, so the low bit is flipped by parity:
/// adding one to an even byte and subtracting one from an odd byte is exactly
/// `xor 1`, and never leaves the 0..255 range.
fn flip_last(value: ByteArray) -> ByteArray {
  let width = bytearray.length(value)
  if width == 0 {
    value
  } else {
    let last = bytearray.at(value, width - 1)
    let flipped = if last % 2 == 0 {
      last + 1
    } else {
      last - 1
    }
    bytearray.concat(
      bytearray.take(value, width - 1),
      bytearray.push("", flipped),
    )
  }
}

fn parity_checkpoint_ref() -> OutputReference {
  OutputReference {
    transaction_id: ev.checkpoint_txid,
    output_index: ev.checkpoint_index,
  }
}

fn parity_scope() -> BountyScope {
  BountyScope {
    domain: commitment_domain,
    schema: commitment_schema,
    network: ev.network,
    checkpoint_policy: ev.checkpoint_policy,
    checkpoint_ref: parity_checkpoint_ref(),
    action: FreezeEntitlement,
    marker: ev.marker,
    commit_upper: ev.commit_upper,
    eligible_after: ev.eligible_after,
    expires_at: ev.expires_at,
  }
}

fn parity_commitment() -> BountyCommitment {
  let scope = parity_scope()
  BountyCommitmentV1 {
    scope,
    payee_pkh: ev.payee,
    hash: commitment_hash(
      commitment_preimage(scope, ev.evidence_digest, ev.payee, ev.nonce),
    ),
    marker: ev.marker,
  }
}

fn parity_reveal() -> BountyRevealV1 {
  BountyRevealV1 {
    commitment_ref: OutputReference {
      transaction_id: ev.commitment_txid,
      output_index: ev.commitment_index,
    },
    nonce: ev.nonce,
    refund_index: ev.refund_index,
  }
}

fn parity_parameters() -> CommitmentParameters {
  CommitmentParameters {
    network: ev.network,
    commit_min_age: ev.commit_min_age,
    commitment_lifetime: ev.expires_at - ev.commit_upper,
    commit_deposit: ev.commit_deposit,
  }
}

fn parity_family() -> CommitmentFamily {
  CommitmentFamily {
    policy: ev.commitment_policy,
    parameters: parity_parameters(),
  }
}

fn parity_armed_state() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: #"0101010101010101010101010101010101010101010101010101010101010101",
    cur_keys: [ev.verkey],
    cur_threshold: Unweighted(1),
    next_keys: [ev.key_digest],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 1,
    native_sn: 1,
  }
}

/// The matcher's verdict as the same stable tag the Haskell source emits.
///
/// Spelled out rather than derived, because a derived mapping could agree with
/// the other language by construction. Writing both independently is what makes
/// the comparison mean something.
fn verdict_tag(verdict: EntitlementVerdict) -> Int {
  when verdict is {
    EntitlementValid -> 0
    EntitlementInvalid(EntitlementDigestWidth) -> 1
    EntitlementInvalid(EntitlementNonceWidth) -> 2
    EntitlementInvalid(EntitlementAction) -> 3
    EntitlementInvalid(EntitlementCheckpoint) -> 4
    EntitlementInvalid(EntitlementMarker) -> 5
    EntitlementInvalid(EntitlementHash) -> 6
  }
}
