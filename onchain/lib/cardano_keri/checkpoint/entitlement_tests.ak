//// #254 S254-E — unit proofs for the shared bounty-entitlement rule, T254-107.
////
//// The applied-program rows live in `checkpoint_register_lifecycle_tests.ak`,
//// where whole transactions run through whole validators. What lives here is
//// the layer underneath: each leg of the shared rule, exercised on its own,
//// with an accepted honest neighbour beside every rejection so no row can pass
//// because its fixture was quietly broken.
////
//// Every negative in this module states what it changed from the honest case
//// and changes only that. A rejection that could also be explained by a
//// malformed fixture proves nothing about the rule.

use aiken/builtin
use aiken/cbor
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/bounty_commitment.{
  BountyAction, BountyCommitment, BountyCommitmentV1, BountyRevealV1,
  BountyScope, CommitmentFamily, CommitmentParameters, ConvictEntitlement,
  ConvictionTarget, EntitlementAid, EntitlementDeployment,
  EntitlementDigestWidth, EntitlementHash, EntitlementInvalid,
  EntitlementKeyState, EntitlementMarker, EntitlementNonceWidth,
  EntitlementValid, EntitlementVerdict, commitment_domain, commitment_hash,
  commitment_preimage, commitment_schema, marker_name,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV2, KeyMaterial, Live}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence}
use cardano_keri/checkpoint/enforcement_vectors as vec
use cardano_keri/checkpoint/entitlement.{
  EnforcementProofV1, enforcement_evidence_digest, entitlement_matches,
  validate_convict_entitlement, validate_entitlement_observation,
}
use cardano_keri/checkpoint/entitlement_vectors as ev
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
}
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

/// The output a step of the checkpoint produces: another transaction, so the
/// reference is not the one the commitment was opened against.
const successor_ref: OutputReference =
  OutputReference {
    transaction_id: #"5555555555555555555555555555555555555555555555555555555555555555",
    output_index: 0,
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

const evidence: EnforcementEvidence = vec.fork_witnessed_convict_wire

/// The deployment, the identifier and the key state of the honest spent
/// checkpoint: the key state a conviction is settled at.
fn honest_target() -> ConvictionTarget {
  ConvictionTarget {
    checkpoint_policy,
    aid: ev.aid,
    epoch: ev.epoch,
    sn: ev.sn,
  }
}

/// A live checkpoint datum of the honest identifier at the given key state.
fn live_datum(epoch: Int, sn: Int) -> CheckpointDatumV2 {
  marked_datum(epoch, sn, False, False, False)
}

/// The same, carrying the given poison, freeze and top-up marks.
fn marked_datum(
  epoch: Int,
  sn: Int,
  poisoned: Bool,
  frozen: Bool,
  topped_up: Bool,
) -> CheckpointDatumV2 {
  Live {
    aid: ev.aid,
    sn,
    epoch,
    poisoned,
    frozen,
    born_at: 0,
    refund_to: #"",
    topped_up,
    keys: KeyMaterial {
      cur_keys: [],
      cur_threshold: Unweighted(1),
      next_keys: [],
      next_threshold: Unweighted(1),
      witnesses: [],
      toad: 0,
    },
  }
}

/// The checkpoint the commitment was opened against: at `script`, carrying
/// `spent`.
fn spent_checkpoint(script: PolicyId, spent: CheckpointDatumV2) -> Input {
  spent_checkpoint_at(checkpoint_ref, script, spent)
}

/// A checkpoint output of its own: the reference it sits at is the one the
/// conviction spends and the claim names.
fn spent_checkpoint_at(
  ref: OutputReference,
  script: PolicyId,
  spent: CheckpointDatumV2,
) -> Input {
  Input {
    output_reference: ref,
    output: Output {
      address: from_script(script),
      value: from_lovelace(2_000_000),
      datum: InlineDatum(datum.write(spent)),
      reference_script: None,
    },
  }
}

fn honest_spent() -> Input {
  spent_checkpoint(checkpoint_policy, live_datum(ev.epoch, ev.sn))
}

// ---------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------

fn scope_for(action: BountyAction, at: ConvictionTarget) -> BountyScope {
  BountyScope {
    domain: commitment_domain,
    schema: commitment_schema,
    network: network_id,
    checkpoint_policy: at.checkpoint_policy,
    aid: at.aid,
    epoch: at.epoch,
    sn: at.sn,
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

/// The honest Convict reservation: this checkpoint, this action, the digest of
/// this actual evidence, this payee.
fn honest_commitment() -> BountyCommitment {
  commitment_over(
    scope_for(ConvictEntitlement, honest_target()),
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
  settlement_tx_spending(script, commitment, lower, upper, honest_spent())
}

/// The same settlement, spending the given checkpoint.
fn settlement_tx_spending(
  script: PolicyId,
  commitment: BountyCommitment,
  lower: Int,
  upper: Int,
  spent: Input,
) -> Transaction {
  let BountyCommitmentV1 { marker, payee_pkh, .. } = commitment
  Transaction {
    ..placeholder,
    inputs: [commitment_input(script, commitment), spent],
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

fn convict_verdict(
  f: CommitmentFamily,
  e: EnforcementEvidence,
  payee: ByteArray,
  r: BountyRevealV1,
  at: ConvictionTarget,
  tx: Transaction,
) -> Bool {
  validate_convict_entitlement(f, e, payee, r, at, tx)
}

/// Every rejection below is measured against this. If this row ever stops
/// passing, the negatives beside it stop meaning anything, because "rejected"
/// would no longer distinguish the mutation from the fixture.
test entitlement_honest_convict_settlement_accepts() {
  convict_verdict(
    family,
    evidence,
    hunter,
    reveal(),
    honest_target(),
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
    convict_verdict(
      foreign_family,
      evidence,
      hunter,
      reveal(),
      honest_target(),
      tx,
    ),
    !convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx),
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
  !convict_verdict(
    family,
    evidence,
    hunter,
    absent,
    honest_target(),
    honest_tx(),
  )
}

/// The committed payee is the whole point: an attacker naming itself against
/// somebody else's reservation is refused even though every other leg holds.
test entitlement_substituted_payee_rejects() {
  !convict_verdict(
    family,
    evidence,
    attacker,
    reveal(),
    honest_target(),
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
  !convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx)
}

/// Without the burn the reservation could settle again.
test entitlement_unburned_marker_rejects() {
  let tx = Transaction { ..honest_tx(), mint: zero }
  !convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx)
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
  !convict_verdict(
    family,
    mutated,
    hunter,
    reveal(),
    honest_target(),
    honest_tx(),
  )
}

/// A reservation opened for another deployment, identifier or key state cannot
/// settle this one; each is refused where the honest neighbour is accepted.
test entitlement_foreign_key_state_rejects() {
  let settle = fn(at: ConvictionTarget) {
    convict_verdict(family, evidence, hunter, reveal(), at, honest_tx())
  }
  and {
    settle(honest_target()),
    !settle(
      ConvictionTarget { ..honest_target(), checkpoint_policy: foreign_policy },
    ),
    !settle(ConvictionTarget { ..honest_target(), aid: flip_last(ev.aid) }),
    !settle(ConvictionTarget { ..honest_target(), epoch: ev.epoch + 1 }),
    !settle(ConvictionTarget { ..honest_target(), sn: ev.sn + 1 }),
  }
}

/// The nonce is inside the hashed preimage, so guessing it wrong breaks the
/// match even with every scope field right.
test entitlement_wrong_nonce_rejects() {
  let wrong = BountyRevealV1 {
    commitment_ref,
    nonce: other_nonce,
    refund_index: 0,
  }
  !convict_verdict(
    family,
    evidence,
    hunter,
    wrong,
    honest_target(),
    honest_tx(),
  )
}

/// The pure matcher agrees with the settlement rule about the honest case, so
/// the rows above are not passing because the matcher is inert.
test entitlement_matches_accepts_the_honest_preimage() {
  entitlement_matches(honest_commitment(), honest_target(), evidence, nonce) == EntitlementValid
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
  !convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx)
}

/// One slot of age is enough — the boundary is admitted, not merely the
/// interior, so the row above pins an exact edge rather than a vague gap.
test entitlement_exactly_one_slot_of_age_accepts() {
  let tx = settlement_tx(commit_policy, honest_commitment(), 1, 1)
  convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx)
}

/// Past `expires_at` the reservation is dead.
test entitlement_expired_reveal_rejects() {
  let tx = settlement_tx(
    commit_policy,
    honest_commitment(),
    applied_lifetime + 1,
    applied_lifetime + 2,
  )
  !convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx)
}

/// The last admissible slot is admitted.
test entitlement_reveal_at_exact_expiry_accepts() {
  let tx = settlement_tx(
    commit_policy,
    honest_commitment(),
    1,
    applied_lifetime,
  )
  convict_verdict(family, evidence, hunter, reveal(), honest_target(), tx)
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
  envelope_claiming(checkpoint_policy, action, own_ref, payee, e, r)
}

/// The same envelope, whose claim names `claimed` as the settling program.
fn envelope_claiming(
  claimed: PolicyId,
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
    claim: ObserverClaim {
      action,
      checkpoint_policy: claimed,
      own_ref: Some(own_ref),
    },
    payload: proof,
  }
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

/// The honest baseline for this half: the conviction settles against its own
/// reservation through the entitlement observer alone.
test s254_e_entitlement_observer_accepts_honest_envelopes() {
  observed(honest_convict_envelope(), honest_tx())
}

/// INV-271-ENTITLEMENT. An attacker naming itself in the payload cannot settle
/// somebody else's reservation, though every other leg is untouched.
test s254_e_entitlement_observer_substituted_payee_rejects() {
  let substituted = enforcement_envelope(
    observe_convict,
    checkpoint_ref,
    attacker,
    evidence,
    reveal(),
  )
  and {
    observed(honest_convict_envelope(), honest_tx()),
    !observed(substituted, honest_tx()),
  }
}

/// INV-271-ENTITLEMENT. A reveal naming an input the transaction never consumes
/// has no reservation behind it.
test s254_e_entitlement_observer_absent_commitment_rejects() {
  let absent = enforcement_envelope(
    observe_convict,
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
    observed(honest_convict_envelope(), honest_tx()),
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
    observe_convict,
    checkpoint_ref,
    hunter,
    EnforcementEvidence { ..evidence, native_sn: evidence.native_sn + 1 },
    reveal(),
  )
  and {
    observed(honest_convict_envelope(), honest_tx()),
    !observed(mutated, honest_tx()),
  }
}

/// INV-271-SCOPE. The nonce is inside the hashed preimage.
test s254_e_entitlement_observer_wrong_nonce_rejects() {
  let wrong = enforcement_envelope(
    observe_convict,
    checkpoint_ref,
    hunter,
    evidence,
    BountyRevealV1 { commitment_ref, nonce: other_nonce, refund_index: 0 },
  )
  and {
    observed(honest_convict_envelope(), honest_tx()),
    !observed(wrong, honest_tx()),
  }
}

// ---------------------------------------------------------------------
// commitment-names-key-state — the observer reads the key state, the
// identifier and the deployment off the spent checkpoint
//
// Each row is named after the row of `lean/checkpoint-commitment-vectors.json`
// it executes, and each pairs the refused case with its accepted neighbour in
// one assertion so that a dispatch refusing everything cannot pass.
// ---------------------------------------------------------------------

/// A reservation opened over the given deployment, identifier and key state.
fn commitment_naming(at: ConvictionTarget) -> BountyCommitment {
  commitment_over(
    scope_for(ConvictEntitlement, at),
    enforcement_evidence_digest(evidence),
    hunter,
    nonce,
  )
}

/// The conviction of `spent` settled through the entitlement observer with the
/// given reservation, inside its window.
fn settles(commitment: BountyCommitment, spent: Input) -> Bool {
  observed(
    enforcement_envelope(
      observe_convict,
      spent.output_reference,
      hunter,
      evidence,
      reveal(),
    ),
    settlement_tx_spending(
      commit_policy,
      commitment,
      1,
      applied_lifetime,
      spent,
    ),
  )
}

/// The output a rotation produced, at a reference of its own.
fn spent_at(epoch: Int, sn: Int) -> Input {
  spent_checkpoint_at(successor_ref, checkpoint_policy, live_datum(epoch, sn))
}

/// An output whose datum carries the given marks, at a reference of its own.
fn spent_marked(poisoned: Bool, frozen: Bool, topped_up: Bool) -> Input {
  spent_checkpoint_at(
    successor_ref,
    checkpoint_policy,
    marked_datum(ev.epoch, ev.sn, poisoned, frozen, topped_up),
  )
}

/// Lean vector row `accepted-output-topped-up`.
test accepted_output_topped_up() {
  and {
    settles(honest_commitment(), honest_spent()),
    settles(honest_commitment(), spent_marked(False, False, True)),
  }
}

/// Lean vector row `accepted-output-frozen`.
test accepted_output_frozen() {
  settles(honest_commitment(), spent_marked(False, True, False))
}

/// Lean vector row `accepted-output-poisoned`.
test accepted_output_poisoned() {
  settles(honest_commitment(), spent_marked(True, False, False))
}

/// Lean vector rows `refused-output-rotated` and `commitment-voided-by-a-rotation`:
/// a rotation moves the epoch or the sequence number, the earlier reservation
/// entitles nobody at the rotated output, and a reservation naming the new key
/// state does.
test refused_output_rotated() {
  let rotated = ConvictionTarget {
    ..honest_target(),
    epoch: ev.epoch + 1,
    sn: ev.sn + 1,
  }
  and {
    settles(honest_commitment(), honest_spent()),
    !settles(honest_commitment(), spent_at(ev.epoch + 1, ev.sn + 1)),
    !settles(honest_commitment(), spent_at(ev.epoch + 1, ev.sn)),
    !settles(honest_commitment(), spent_at(ev.epoch, ev.sn + 1)),
    settles(commitment_naming(rotated), spent_at(ev.epoch + 1, ev.sn + 1)),
  }
}

/// Lean vector row `refused-other-key-state`.
test refused_other_key_state() {
  let other = ConvictionTarget { ..honest_target(), epoch: ev.epoch + 1 }
  and {
    settles(honest_commitment(), honest_spent()),
    !settles(commitment_naming(other), honest_spent()),
    !settles(
      commitment_naming(ConvictionTarget { ..honest_target(), sn: ev.sn + 1 }),
      honest_spent(),
    ),
  }
}

/// Lean vector row `convict-revealing-the-other-aid-commitment`.
test convict_revealing_the_other_aid_commitment() {
  let other = ConvictionTarget { ..honest_target(), aid: flip_last(ev.aid) }
  and {
    settles(honest_commitment(), honest_spent()),
    !settles(commitment_naming(other), honest_spent()),
  }
}

/// Lean vector rows `refused-at-another-deployment` and
/// `conviction-needs-this-deployment`: the scope's checkpoint policy must be
/// the program the spent checkpoint sits at.
test refused_at_another_deployment() {
  let other = ConvictionTarget {
    ..honest_target(),
    checkpoint_policy: foreign_policy,
  }
  and {
    settles(honest_commitment(), honest_spent()),
    !settles(commitment_naming(other), honest_spent()),
    // the checkpoint program settling is the foreign one: the claim names it,
    // as the checkpoint program requires, and the honest reservation names the
    // other program
    !settles_claiming(foreign_policy, honest_commitment(), foreign_spent()),
    settles_claiming(foreign_policy, commitment_naming(other), foreign_spent()),
  }
}

fn foreign_spent() -> Input {
  spent_checkpoint(foreign_policy, live_datum(ev.epoch, ev.sn))
}

fn settles_claiming(
  claimed: PolicyId,
  commitment: BountyCommitment,
  spent: Input,
) -> Bool {
  observed(
    envelope_claiming(
      claimed,
      observe_convict,
      spent.output_reference,
      hunter,
      evidence,
      reveal(),
    ),
    settlement_tx_spending(
      commit_policy,
      commitment,
      1,
      applied_lifetime,
      spent,
    ),
  )
}

/// A claim that names a program other than the one the spent checkpoint sits at
/// is no observation of it.
test refused_a_claim_naming_another_program() fail {
  settles_claiming(foreign_policy, honest_commitment(), honest_spent())
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
    observed(honest_convict_envelope(), aged),
    !observed(honest_convict_envelope(), same_slot),
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
    observed(honest_convict_envelope(), honest_tx()),
    !observed(honest_convict_envelope(), expired),
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
      honest_spent(),
    ],
  }
  and {
    observed(honest_convict_envelope(), honest_tx()),
    !observed(
      honest_convict_envelope(),
      Transaction { ..honest_tx(), mint: zero },
    ),
    !observed(honest_convict_envelope(), short_deposit),
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
    observed_with(foreign_family, honest_convict_envelope(), tx),
    !observed_with(family, honest_convict_envelope(), tx),
  }
}

/// An action this observer does not own is an error, exactly as in the
/// enforcement observer's dispatch: refusing it as `False` would let a caller
/// distinguish "not mine" from "not entitled".
///
/// Stated honestly: this is the one row in this section an inert dispatch also
/// satisfies. `s254_e_entitlement_observer_routes_on_the_action_tag` is what
/// establishes that the dispatch is not inert.
test s254_e_entitlement_observer_removed_freeze_action_fails() fail {
  observed(
    enforcement_envelope(2, checkpoint_ref, hunter, evidence, reveal()),
    honest_tx(),
  )
}

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
test entitlement_vectors_shapes_agree() {
  and {
    cbor.serialise(parity_commitment()) == ev.golden_commitment,
    cbor.serialise(parity_reveal()) == ev.golden_reveal,
    cbor.serialise(parity_parameters()) == ev.golden_commitment_parameters,
    cbor.serialise(parity_family()) == ev.golden_commitment_family,
  }
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
  let checkpoint = parity_target()
  let verdict_at = fn(at: ConvictionTarget) {
    verdict_tag(entitlement_matches(commitment, at, evidence_payload, ev.nonce))
  }
  and {
    // The expected tags are the model's refusals, written here by hand: the
    // generated constants must agree with them, never the reverse.
    verdict_at(
      ConvictionTarget {
        ..checkpoint,
        checkpoint_policy: flip_last(ev.checkpoint_policy),
      },
    ) == 4,
    verdict_at(ConvictionTarget { ..checkpoint, aid: flip_last(ev.aid) }) == 7,
    verdict_at(ConvictionTarget { ..checkpoint, epoch: ev.epoch + 1 }) == 8,
    verdict_at(ConvictionTarget { ..checkpoint, sn: ev.sn + 1 }) == 8,
    verdict_at(
      ConvictionTarget {
        ..checkpoint,
        checkpoint_policy: flip_last(ev.checkpoint_policy),
      },
    ) == ev.verdict_other_deployment,
    verdict_at(ConvictionTarget { ..checkpoint, aid: flip_last(ev.aid) }) == ev.verdict_other_aid,
    verdict_at(ConvictionTarget { ..checkpoint, epoch: ev.epoch + 1 }) == ev.verdict_other_epoch,
    verdict_at(ConvictionTarget { ..checkpoint, sn: ev.sn + 1 }) == ev.verdict_other_sn,
    verdict_tag(
      entitlement_matches(commitment, checkpoint, evidence_payload, ev.nonce),
    ) == ev.verdict_honest,
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
        evidence_payload,
        ev.short_nonce,
      ),
    ) == ev.verdict_short_nonce,
    verdict_tag(
      entitlement_matches(
        BountyCommitmentV1 { ..commitment, marker: ev.other_marker },
        checkpoint,
        evidence_payload,
        ev.nonce,
      ),
    ) == ev.verdict_marker_left_scope,
    verdict_tag(
      entitlement_matches(
        commitment,
        checkpoint,
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
        evidence_payload,
        ev.nonce |> flip_last,
      ),
    ) == ev.verdict_substituted_nonce,
    verdict_tag(
      entitlement_matches(
        BountyCommitmentV1 { ..commitment, payee_pkh: substituted_payee },
        checkpoint,
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
    ev.verdict_other_deployment != ev.verdict_short_nonce,
    ev.verdict_marker_left_scope != ev.verdict_other_deployment,
    ev.verdict_other_aid != ev.verdict_other_deployment,
    ev.verdict_other_epoch != ev.verdict_other_aid,
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

fn parity_target() -> ConvictionTarget {
  ConvictionTarget {
    checkpoint_policy: ev.checkpoint_policy,
    aid: ev.aid,
    epoch: ev.epoch,
    sn: ev.sn,
  }
}

fn parity_scope() -> BountyScope {
  BountyScope {
    domain: commitment_domain,
    schema: commitment_schema,
    network: ev.network,
    checkpoint_policy: ev.checkpoint_policy,
    aid: ev.aid,
    epoch: ev.epoch,
    sn: ev.sn,
    action: ConvictEntitlement,
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
    EntitlementInvalid(EntitlementDeployment) -> 4
    EntitlementInvalid(EntitlementAid) -> 7
    EntitlementInvalid(EntitlementKeyState) -> 8
    EntitlementInvalid(EntitlementMarker) -> 5
    EntitlementInvalid(EntitlementHash) -> 6
  }
}

// ---------------------------------------------------------------------
// scope-layout-versioned — the output a commitment names is no longer what decides
// ---------------------------------------------------------------------

/// A commitment of the retired layout: its scope names the output `ref`, where
/// the identifier and the key state now sit.
fn retired_commitment_naming(ref: OutputReference) -> Data {
  builtin.constr_data(
    0,
    [
      builtin.constr_data(
        0,
        [
          builtin.b_data(commitment_domain),
          builtin.i_data(1),
          builtin.i_data(network_id),
          builtin.b_data(checkpoint_policy),
          builtin.constr_data(
            0,
            [
              builtin.b_data(ref.transaction_id),
              builtin.i_data(ref.output_index),
            ],
          ),
          builtin.constr_data(0, []),
          builtin.b_data(marker_name(seed_ref)),
          builtin.i_data(0),
          builtin.i_data(1),
          builtin.i_data(applied_lifetime),
        ],
      ),
      builtin.b_data(hunter),
      builtin.b_data(honest_commitment().hash),
      builtin.b_data(marker_name(seed_ref)),
    ],
  )
}

/// A reservation of the retired layout whose scope names the very output the
/// conviction spends is not a reservation of this release: the output it names
/// decides nothing, and the layout is refused whole.
test refused_a_commitment_of_the_retired_layout_naming_the_spent_output() {
  let retired = Input {
    output_reference: commitment_ref,
    output: Output {
      address: from_script(commit_policy),
      value: from_lovelace(applied_deposit)
        |> merge(from_asset(commit_policy, marker_name(seed_ref), 1)),
      datum: InlineDatum(retired_commitment_naming(checkpoint_ref)),
      reference_script: None,
    },
  }
  let tx = Transaction { ..honest_tx(), inputs: [retired, honest_spent()] }
  and {
    observed(honest_convict_envelope(), honest_tx()),
    !observed(honest_convict_envelope(), tx),
  }
}
