//// Family-independent bounty-commitment protocol and lifecycle (#271
//// S271-1, `MOD-271-PROTOCOL` + `MOD-271-COMMITMENT`).
////
//// This module owns the versioned entitlement action, scope, opaque
//// preimage/hash, marker identity, reveal/sweep data, applied parameters,
//// and the three lifecycle predicates (open, reveal, expired sweep). It
//// depends only on ledger primitives — never on checkpoint datum internals
//// or KERI evidence semantics (`EDGE-271-01`, `PROMOTE-271-02`). Nothing
//// here claims a checkpoint is protected: #254 S254-E adopts the component.
////
//// The enforcement evidence digest is an **opaque** 32-byte value at this
//// boundary. Deriving it from an actual `EnforcementEvidence` is the
//// enforcement observer's row (S254-E); this component therefore cannot and
//// does not claim that a supplied digest is actual (`DATA-INV-271-02`).

use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval.{Finite, Interval, NegativeInfinity, PositiveInfinity}
use aiken/primitive/bytearray
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, Value, ada_asset_name, ada_policy_id, flatten, tokens,
}
use cardano/transaction.{
  Datum, InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}

// ---------------------------------------------------------------------
// Frozen protocol surface
// ---------------------------------------------------------------------

/// Canonical protocol domain. Part of every commitment preimage, so a
/// foreign domain can never collide with this family's hashes.
pub const commitment_domain: ByteArray = "cardano-keri/bounty-commitment"

/// Canonical schema version of the wire shapes in this module.
pub const commitment_schema: Int = 1

/// Mandated minimum commitment age: one network slot.
pub const commit_min_age: Int = 1

/// Mandated floor for the applied commitment deposit, in lovelace.
///
/// The floor's removal was tested and rejected, so be exact about what it
/// buys. It raises the *concurrent capital* an attacker must lock to open
/// Open_1..Open_N over candidate checkpoint/action/evidence preimages and
/// reveal only the one that matches. It does not defeat that grind and does
/// not force a loss: minimum ADA plus the permissionless expired sweep bound
/// how long each losing commitment's UTxO lives, and the attacker may
/// self-sweep its own expired losers and recycle the deposit. A surviving
/// economic residual, not a defeated attack.
pub const commit_deposit_floor: Int = 5_000_000

/// Marker asset names are a full blake2b-256 digest.
pub const marker_width: Int = 32

/// Cardano verification-key hash width.
pub const pkh_width: Int = 28

/// Enforcement evidence digest width.
pub const digest_width: Int = 32

/// Minimum commitment nonce width.
pub const nonce_min_width: Int = 32

// ---------------------------------------------------------------------
// DAT-271-ACTION / DAT-271-SCOPE / DAT-271-PREIMAGE
// ---------------------------------------------------------------------

/// Closed versioned entitlement action. ClaimFreeze has no action of its
/// own: it consumes the hunter entitlement Freeze already recorded.
pub type BountyAction {
  FreezeEntitlement
  ConvictEntitlement
}

/// `DAT-271-SCOPE`. Everything a commitment is scoped to, all of it inside
/// the hashed preimage, so no field can be swapped after the fact.
pub type BountyScope {
  domain: ByteArray,
  schema: Int,
  network: Int,
  checkpoint_policy: PolicyId,
  checkpoint_ref: OutputReference,
  action: BountyAction,
  marker: AssetName,
  commit_upper: Int,
  eligible_after: Int,
  expires_at: Int,
}

/// `DAT-271-PREIMAGE`. Its canonical serialization is frozen protocol
/// surface; the digest and nonce never appear in the live datum.
pub type BountyCommitmentPreimage {
  scope: BountyScope,
  evidence_digest: ByteArray,
  payee_pkh: ByteArray,
  nonce: ByteArray,
}

/// `DAT-271-COMMITMENT`. Versioned by constructor: `BountyCommitmentV1`
/// bytes are frozen once deployed.
pub type BountyCommitment {
  BountyCommitmentV1 {
    scope: BountyScope,
    payee_pkh: ByteArray,
    hash: ByteArray,
    marker: AssetName,
  }
}

/// `DAT-271-REVEAL`. The evidence is not duplicated here.
pub type BountyRevealV1 {
  commitment_ref: OutputReference,
  nonce: ByteArray,
  refund_index: Int,
}

/// `DAT-271-SWEEP`.
pub type ExpiredCommitmentSweepV1 {
  recipient_pkh: ByteArray,
  payout_index: Int,
}

/// Spending redeemer of the commitment program.
pub type BountySpend {
  Reveal(BountyRevealV1)
  Sweep(ExpiredCommitmentSweepV1)
}

/// Minting redeemer of the commitment program.
pub type BountyMint {
  Open { seed_ref: OutputReference }
  Retire
}

/// `DAT-271-PARAMETERS`, applied magnitudes only. No ambient manifest
/// lookup and no protocol default: every value, including the release
/// lifetime, is an explicit argument of the applied program.
pub type CommitmentParameters {
  network: Int,
  commit_min_age: Int,
  commitment_lifetime: Int,
  commit_deposit: Int,
}

/// Deployment identity of the applied program. The #254 registry and the
/// enforcement observer name the policy through this record; the script
/// itself learns its policy from the ledger context instead, because
/// embedding its own hash as a parameter would be circular.
pub type CommitmentFamily {
  policy: PolicyId,
  parameters: CommitmentParameters,
}

// ---------------------------------------------------------------------
// Structured verdicts — one distinct reason per rejectable fact
// ---------------------------------------------------------------------

pub type ParametersError {
  ParametersAge
  ParametersLifetime
  ParametersDeposit
}

pub type ParametersVerdict {
  ParametersValid
  ParametersInvalid(ParametersError)
}

pub type ScopeError {
  ScopeDomain
  ScopeSchema
  ScopeNetwork
  ScopeCheckpointPolicyWidth
  ScopeCheckpointRefWidth
  ScopeMarkerWidth
  ScopeAge
  ScopeLifetime
}

pub type ScopeVerdict {
  ScopeValid
  ScopeInvalid(ScopeError)
}

pub type CommitmentError {
  CommitmentScope(ScopeError)
  CommitmentPayeeWidth
  CommitmentHashWidth
  CommitmentMarkerBinding
}

pub type CommitmentVerdict {
  CommitmentValid
  CommitmentInvalid(CommitmentError)
}

pub type EntitlementError {
  EntitlementDigestWidth
  EntitlementNonceWidth
  EntitlementAction
  EntitlementCheckpoint
  EntitlementMarker
  EntitlementHash
}

pub type EntitlementVerdict {
  EntitlementValid
  EntitlementInvalid(EntitlementError)
}

// ---------------------------------------------------------------------
// Pure protocol
// ---------------------------------------------------------------------

/// `DAT-271-MARKER`. The marker name derives from the consumed opening seed
/// and from nothing else, so two openings cannot counterfeit one identity.
/// The commitment hash binds the marker (the scope carries it) without the
/// marker ever depending on the hash — no circular derivation.
pub fn marker_name(seed_ref: OutputReference) -> AssetName {
  blake2b_256(cbor.serialise(seed_ref))
}

/// Assemble a preimage. Pure: no transaction or KERI effect.
pub fn commitment_preimage(
  scope: BountyScope,
  evidence_digest: ByteArray,
  payee_pkh: ByteArray,
  nonce: ByteArray,
) -> BountyCommitmentPreimage {
  BountyCommitmentPreimage { scope, evidence_digest, payee_pkh, nonce }
}

/// The canonical commitment hash: blake2b-256 of the canonical versioned
/// serialization of the preimage. Identical in Haskell and Aiken.
pub fn commitment_hash(preimage: BountyCommitmentPreimage) -> ByteArray {
  blake2b_256(cbor.serialise(preimage))
}

/// The applied magnitudes must be admissible: exactly the mandated one-slot
/// age, an explicit release lifetime long enough to contain at least one
/// mature reveal slot, and a deposit at or above the floor.
///
/// The release lifetime's *magnitude* is a deployment choice, not a security
/// invariant, so this module publishes no default for it and pins no exact
/// value. What it does owe is that the applied value is explicit and denotes
/// a reachable window: `expires_at` is `commit_upper + commitment_lifetime`
/// and the first mature slot is `commit_upper + commit_min_age`, so a
/// lifetime below the age would expire the commitment before it could ever
/// be revealed. Because the leg above has already pinned the applied age to
/// the mandated one slot, this same comparison is what rejects zero and
/// negative lifetimes — they are one class of magnitude, not three.
pub fn parameters_well_formed(
  parameters: CommitmentParameters,
) -> ParametersVerdict {
  if parameters.commit_min_age != commit_min_age {
    ParametersInvalid(ParametersAge)
  } else if parameters.commitment_lifetime < parameters.commit_min_age {
    ParametersInvalid(ParametersLifetime)
  } else if parameters.commit_deposit < commit_deposit_floor {
    ParametersInvalid(ParametersDeposit)
  } else {
    ParametersValid
  }
}

/// Scope well-formedness against the applied parameters, including the two
/// derived timing identities. `eligible_after` and `expires_at` are
/// *derived* from the stored raw opening endpoint, never merely asserted.
pub fn scope_well_formed(
  parameters: CommitmentParameters,
  scope: BountyScope,
) -> ScopeVerdict {
  if scope.domain != commitment_domain {
    ScopeInvalid(ScopeDomain)
  } else if scope.schema != commitment_schema {
    ScopeInvalid(ScopeSchema)
  } else if scope.network != parameters.network {
    ScopeInvalid(ScopeNetwork)
  } else if bytearray.length(scope.checkpoint_policy) != pkh_width {
    ScopeInvalid(ScopeCheckpointPolicyWidth)
  } else if bytearray.length(scope.checkpoint_ref.transaction_id) != digest_width || scope.checkpoint_ref.output_index < 0 {
    ScopeInvalid(ScopeCheckpointRefWidth)
  } else if bytearray.length(scope.marker) != marker_width {
    ScopeInvalid(ScopeMarkerWidth)
  } else if scope.eligible_after != scope.commit_upper + parameters.commit_min_age {
    ScopeInvalid(ScopeAge)
  } else if scope.expires_at != scope.commit_upper + parameters.commitment_lifetime {
    ScopeInvalid(ScopeLifetime)
  } else {
    ScopeValid
  }
}

/// Datum well-formedness: a well-formed scope, canonical widths, and the
/// marker binding between datum and scope.
pub fn commitment_well_formed(
  parameters: CommitmentParameters,
  commitment: BountyCommitment,
) -> CommitmentVerdict {
  let BountyCommitmentV1 { scope, payee_pkh, hash, marker } = commitment
  when scope_well_formed(parameters, scope) is {
    ScopeInvalid(reason) -> CommitmentInvalid(CommitmentScope(reason))
    ScopeValid ->
      if bytearray.length(payee_pkh) != pkh_width {
        CommitmentInvalid(CommitmentPayeeWidth)
      } else if bytearray.length(hash) != digest_width {
        CommitmentInvalid(CommitmentHashWidth)
      } else if marker != scope.marker {
        CommitmentInvalid(CommitmentMarkerBinding)
      } else {
        CommitmentValid
      }
  }
}

/// Pure standalone scope/preimage matching. It recomputes the commitment
/// hash from the committed scope and payee plus the supplied digest and
/// nonce, so independently changing any scope field, the payee, the digest,
/// or the nonce breaks the match.
///
/// It deliberately does **not** claim the digest is the digest of actual
/// evidence, and it touches no checkpoint state: that coupling is the
/// enforcement observer's obligation (`DATA-INV-271-02`, S254-E).
pub fn entitlement_matches(
  commitment: BountyCommitment,
  checkpoint_ref: OutputReference,
  action: BountyAction,
  evidence_digest: ByteArray,
  nonce: ByteArray,
) -> EntitlementVerdict {
  let BountyCommitmentV1 { scope, payee_pkh, hash, marker } = commitment
  if bytearray.length(evidence_digest) != digest_width {
    EntitlementInvalid(EntitlementDigestWidth)
  } else if bytearray.length(nonce) < nonce_min_width {
    EntitlementInvalid(EntitlementNonceWidth)
  } else if scope.action != action {
    EntitlementInvalid(EntitlementAction)
  } else if scope.checkpoint_ref != checkpoint_ref {
    EntitlementInvalid(EntitlementCheckpoint)
  } else if marker != scope.marker {
    EntitlementInvalid(EntitlementMarker)
  } else if commitment_hash(
    commitment_preimage(scope, evidence_digest, payee_pkh, nonce),
  ) != hash {
    EntitlementInvalid(EntitlementHash)
  } else {
    EntitlementValid
  }
}

// ---------------------------------------------------------------------
// Raw ledger validity-range semantics
// ---------------------------------------------------------------------

/// The raw finite upper endpoint, exactly as declared. Inclusivity is
/// returned, never folded away: the opening stores the raw endpoint.
pub fn raw_upper(range: Interval<Int>) -> Option<(Int, Bool)> {
  when range.upper_bound.bound_type is {
    Finite(u) -> Some((u, range.upper_bound.is_inclusive))
    _ -> None
  }
}

/// The earliest slot the transaction can be in, honouring exclusivity.
pub fn earliest_slot(range: Interval<Int>) -> Option<Int> {
  when range.lower_bound.bound_type is {
    Finite(l) ->
      if range.lower_bound.is_inclusive {
        Some(l)
      } else {
        Some(l + 1)
      }
    _ -> None
  }
}

/// The latest slot the transaction can be in, honouring exclusivity.
pub fn latest_slot(range: Interval<Int>) -> Option<Int> {
  when range.upper_bound.bound_type is {
    Finite(u) ->
      if range.upper_bound.is_inclusive {
        Some(u)
      } else {
        Some(u - 1)
      }
    _ -> None
  }
}

/// Whether the interval denotes at least one ledger slot.
/// Whether the interval denotes at least one ledger slot.
///
/// This is load-bearing, not hygiene. "Every possible execution slot is at
/// or after `t`" is **vacuously true** over an interval that admits no slot
/// at all, so comparing the two endpoints independently would accept a
/// reversed finite window whose lower is mature and whose upper is
/// unexpired — the window `[1002,1001]` satisfies both reveal legs, and
/// `[11001,11000]` satisfies the sweep leg, while denoting no instant.
/// Every predicate below therefore establishes non-emptiness *first*.
pub fn non_empty(range: Interval<Int>) -> Bool {
  when (range.lower_bound.bound_type, range.upper_bound.bound_type) is {
    // Nothing is at or before negative infinity, or at or after positive
    // infinity; either pairing denotes the empty set whatever the other
    // endpoint says.
    (_, NegativeInfinity) -> False
    (PositiveInfinity, _) -> False
    // Two finite endpoints: compare the admissible slots they actually
    // denote, so a zero-width exclusive pair is empty as surely as a
    // reversed inclusive one.
    (Finite(_), Finite(_)) ->
      when (earliest_slot(range), latest_slot(range)) is {
        (Some(l), Some(u)) -> l <= u
        _ -> False
      }
    // One finite endpoint and one infinity on the admitting side.
    _ -> True
  }
}

/// The interval denotes at least one slot, and every one of them is at or
/// after `t`.
pub fn at_or_after(range: Interval<Int>, t: Int) -> Bool {
  non_empty(range) && when earliest_slot(range) is {
    Some(l) -> l >= t
    None -> False
  }
}

/// The interval denotes at least one slot, and every one of them is at or
/// before `t`.
pub fn at_or_before(range: Interval<Int>, t: Int) -> Bool {
  non_empty(range) && when latest_slot(range) is {
    Some(u) -> u <= t
    None -> False
  }
}

/// The interval denotes at least one slot, and every one of them is
/// strictly after `t`.
pub fn strictly_after(range: Interval<Int>, t: Int) -> Bool {
  non_empty(range) && when earliest_slot(range) is {
    Some(l) -> l > t
    None -> False
  }
}

// ---------------------------------------------------------------------
// Value, datum and output shapes
// ---------------------------------------------------------------------

/// Decode an inline commitment datum, rejecting every other datum form.
pub fn inline_commitment(datum: Datum) -> Option<BountyCommitment> {
  when datum is {
    InlineDatum(data) ->
      if data is commitment: BountyCommitment {
        Some(commitment)
      } else {
        None
      }
    _ -> None
  }
}

/// Exactly the quantity-one marker plus exactly `deposit` lovelace, and
/// nothing else at all. Full-value equality, not a containment test.
pub fn exact_commitment_value(
  policy: PolicyId,
  marker: AssetName,
  deposit: Int,
  value: Value,
) -> Bool {
  flatten(value) == [
    (ada_policy_id, ada_asset_name, deposit), (policy, marker, 1),
  ]
}

/// Exactly `amount` lovelace and nothing else.
pub fn exact_lovelace_value(amount: Int, value: Value) -> Bool {
  flatten(value) == [(ada_policy_id, ada_asset_name, amount)]
}

/// A datum-free, reference-script-free, lovelace-only enterprise payout to
/// `pkh` at exactly `index`.
pub fn exact_payout(
  tx: Transaction,
  index: Int,
  pkh: ByteArray,
  amount: Int,
) -> Bool {
  when list.at(tx.outputs, index) is {
    Some(out) -> and {
        out.address == Address {
          payment_credential: VerificationKey(pkh),
          stake_credential: None,
        },
        exact_lovelace_value(amount, out.value),
        out.datum == NoDatum,
        out.reference_script == None,
      }
    None -> False
  }
}

/// The transaction's whole mint map under `policy` is exactly one entry
/// burning exactly one `marker`.
pub fn burns_exactly_one(
  tx: Transaction,
  policy: PolicyId,
  marker: AssetName,
) -> Bool {
  dict.to_pairs(tokens(tx.mint, policy)) == [Pair(marker, -1)]
}

/// No output retains any asset of `policy`.
pub fn no_output_holds(tx: Transaction, policy: PolicyId) -> Bool {
  list.all(tx.outputs, fn(out) { dict.is_empty(tokens(out.value, policy)) })
}

/// The transaction mints nothing under `policy`.
pub fn no_mint_under(tx: Transaction, policy: PolicyId) -> Bool {
  dict.is_empty(tokens(tx.mint, policy))
}

/// The outputs sitting at the script credential `policy`.
pub fn script_outputs(tx: Transaction, policy: PolicyId) -> List<Output> {
  list.filter(
    tx.outputs,
    fn(out) { out.address.payment_credential == Script(policy) },
  )
}

/// The authentic commitment being spent at `own_ref`: it must sit at a
/// script credential, carry a decodable inline commitment datum, and hold
/// exactly its own seed-derived marker plus the applied deposit. A
/// matching-looking datum without that value is counterfeit and yields
/// `None`.
pub fn own_commitment(
  parameters: CommitmentParameters,
  own_ref: OutputReference,
  tx: Transaction,
) -> Option<(PolicyId, BountyCommitment)> {
  when find_input(tx.inputs, own_ref) is {
    Some(input) ->
      when input.output.address.payment_credential is {
        Script(policy) ->
          when inline_commitment(input.output.datum) is {
            Some(commitment) -> {
              let BountyCommitmentV1 { marker, .. } = commitment
              if exact_commitment_value(
                policy,
                marker,
                parameters.commit_deposit,
                input.output.value,
              ) {
                Some((policy, commitment))
              } else {
                None
              }
            }
            None -> None
          }
        _ -> None
      }
    None -> None
  }
}

// ---------------------------------------------------------------------
// Lifecycle predicates
// ---------------------------------------------------------------------

/// `validate_commitment_open`. Within the on-chain program `datum` is the
/// commitment decoded from the unique script output, so that leg is
/// definitional there; the load-bearing legs are the exact seed
/// consumption, the seed-only marker derivation, the whole-mint-map
/// uniqueness, the exact confined value, the stored raw opening endpoint,
/// and the creation-time payee signature.
pub fn validate_commitment_open(
  parameters: CommitmentParameters,
  seed_ref: OutputReference,
  datum: BountyCommitment,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let BountyCommitmentV1 { scope, payee_pkh, marker, .. } = datum
  and {
    parameters_well_formed(parameters) == ParametersValid,
    commitment_well_formed(parameters, datum) == CommitmentValid,
    // the exact declared opening seed is consumed by this transaction
    list.any(tx.inputs, fn(input) { input.output_reference == seed_ref }),
    // the identity is derived from that seed, never asserted by the datum
    marker == marker_name(seed_ref),
    // the opening interval must denote at least one slot before its upper
    // endpoint is stored: a reversed window still names a plausible raw
    // endpoint while admitting no instant to have opened in
    non_empty(tx.validity_range),
    // the raw opening upper endpoint is stored verbatim
    when raw_upper(tx.validity_range) is {
      Some((upper, _inclusive)) -> scope.commit_upper == upper
      None -> False
    },
    // the whole mint map under this policy: this marker, quantity one
    dict.to_pairs(tokens(tx.mint, policy_id)) == [Pair(marker, 1)],
    // exactly one script output, confining exactly the marker and deposit
    when script_outputs(tx, policy_id) is {
      [out] -> and {
          exact_commitment_value(
            policy_id,
            marker,
            parameters.commit_deposit,
            out.value,
          ),
          inline_commitment(out.datum) == Some(datum),
          out.reference_script == None,
        }
      _ -> False
    },
    // creation-time consent of the fixed future beneficiary
    list.has(tx.extra_signatories, payee_pkh),
  }
}

/// `validate_commitment_reveal`. Mature, unexpired, exactly one marker
/// burned, exact deposit refunded to the committed payee, payee signing.
/// Evidence coupling is additionally required by the enforcement observer.
pub fn validate_commitment_reveal(
  parameters: CommitmentParameters,
  reveal: BountyRevealV1,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  when own_commitment(parameters, own_ref, tx) is {
    None -> False
    Some((policy, commitment)) -> {
      let BountyCommitmentV1 { scope, payee_pkh, marker, .. } = commitment
      and {
        parameters_well_formed(parameters) == ParametersValid,
        commitment_well_formed(parameters, commitment) == CommitmentValid,
        // the redeemer names this very commitment
        reveal.commitment_ref == own_ref,
        bytearray.length(reveal.nonce) >= nonce_min_width,
        // matured: the interval is disjoint from the opening slot
        at_or_after(tx.validity_range, scope.eligible_after),
        // unexpired
        at_or_before(tx.validity_range, scope.expires_at),
        burns_exactly_one(tx, policy, marker),
        no_output_holds(tx, policy),
        exact_payout(
          tx,
          reveal.refund_index,
          payee_pkh,
          parameters.commit_deposit,
        ),
        list.has(tx.extra_signatories, payee_pkh),
      }
    }
  }
}

/// `validate_commitment_sweep`. Strictly expired, exactly one marker
/// burned, exact deposit paid to the signing recipient, and no checkpoint
/// effect.
pub fn validate_commitment_sweep(
  parameters: CommitmentParameters,
  sweep: ExpiredCommitmentSweepV1,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  when own_commitment(parameters, own_ref, tx) is {
    None -> False
    Some((policy, commitment)) -> {
      let BountyCommitmentV1 { scope, marker, .. } = commitment
      and {
        parameters_well_formed(parameters) == ParametersValid,
        commitment_well_formed(parameters, commitment) == CommitmentValid,
        // strictly after expiry, honouring the raw endpoint's inclusivity
        strictly_after(tx.validity_range, scope.expires_at),
        burns_exactly_one(tx, policy, marker),
        no_output_holds(tx, policy),
        exact_payout(
          tx,
          sweep.payout_index,
          sweep.recipient_pkh,
          parameters.commit_deposit,
        ),
        list.has(tx.extra_signatories, sweep.recipient_pkh),
        // a sweep grants no entitlement, so it touches no checkpoint
        no_mint_under(tx, scope.checkpoint_policy),
      }
    }
  }
}

/// A burn-only mint map under this policy: non-empty and every entry
/// strictly negative. An empty map cannot occur on-chain because a policy
/// only runs when it appears in the mint map, so it fails closed.
pub fn all_burns(entries: Pairs<AssetName, Int>) -> Bool {
  when entries is {
    [] -> False
    _ -> list.all(entries, fn(entry) { entry.2nd < 0 })
  }
}
