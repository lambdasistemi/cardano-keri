//// #271 S271-1 — protocol-level proofs for the family-independent bounty
//// commitment component: Haskell/Aiken canonical parity, seed-only marker
//// derivation, scope/preimage mutation coverage, applied-parameter and
//// scope well-formedness, and raw ledger validity-range semantics.
////
//// Every golden constant in `bounty_commitment_vectors` is produced by
//// `offchain/app/GenBountyCommitmentVectors.hs`; nothing here re-derives a
//// vector on the Aiken side, so a single-sided change breaks a test.

use aiken/cbor
use aiken/interval.{
  Finite, Interval, IntervalBound, IntervalBoundType, NegativeInfinity,
  PositiveInfinity,
}
use aiken/primitive/bytearray
use cardano/transaction.{OutputReference}
use cardano_keri/bounty_commitment.{
  BountyCommitment, BountyCommitmentPreimage, BountyCommitmentV1, BountyRevealV1,
  BountyScope, CommitmentHashWidth, CommitmentInvalid, CommitmentMarkerBinding,
  CommitmentParameters, CommitmentPayeeWidth, CommitmentValid,
  ConvictEntitlement, EntitlementAction, EntitlementCheckpoint,
  EntitlementDigestWidth, EntitlementHash, EntitlementInvalid, EntitlementMarker,
  EntitlementNonceWidth, EntitlementValid, ExpiredCommitmentSweepV1,
  FreezeEntitlement, Open, ParametersAge, ParametersDeposit, ParametersInvalid,
  ParametersLifetime, ParametersValid, Retire, Reveal, ScopeAge,
  ScopeCheckpointPolicyWidth, ScopeCheckpointRefWidth, ScopeDomain, ScopeInvalid,
  ScopeLifetime, ScopeMarkerWidth, ScopeNetwork, ScopeSchema, ScopeValid, Sweep,
  at_or_after, at_or_before, commit_deposit_floor, commit_min_age,
  commitment_domain, commitment_hash, commitment_preimage, commitment_schema,
  commitment_well_formed, entitlement_matches, marker_name, non_empty,
  parameters_well_formed, raw_upper, scope_well_formed, strictly_after,
}
use cardano_keri/bounty_commitment_vectors as vec

// ---------------------------------------------------------------------
// The canonical fixture, mirroring GenBountyCommitmentVectors.hs
// ---------------------------------------------------------------------

/// The opening seed the marker name is derived from.
pub fn seed_ref() -> OutputReference {
  OutputReference {
    transaction_id: vec.seed_txid,
    output_index: vec.seed_index,
  }
}

/// A different seed — a different marker identity.
pub fn other_seed_ref() -> OutputReference {
  OutputReference {
    transaction_id: vec.seed_txid,
    output_index: vec.seed_index + 1,
  }
}

/// The checkpoint the entitlement is scoped to.
pub fn checkpoint_ref() -> OutputReference {
  OutputReference {
    transaction_id: vec.checkpoint_txid,
    output_index: vec.checkpoint_index,
  }
}

/// The canonical fixture's applied release lifetime, in slots. An explicitly
/// named example of one deployment's choice — never a protocol default. The
/// generated vectors publish only the *derived* boundary, and
/// `bounty_commitment_generated_boundary_derives_from_the_example_lifetime`
/// keeps this example bound to it.
pub fn example_lifetime() -> Int {
  10_000
}

/// A second, deliberately different applied release lifetime. Two distinct
/// magnitudes are what make "the boundary is derived from the applied
/// parameter" falsifiable: one magnitude pinned in the protocol cannot serve
/// both, so every cross-pairing below would have to fail.
pub fn alt_lifetime() -> Int {
  250
}

/// The applied deployment magnitudes.
pub fn parameters() -> CommitmentParameters {
  CommitmentParameters {
    network: vec.network,
    commit_min_age: vec.commit_min_age,
    commitment_lifetime: example_lifetime(),
    commit_deposit: vec.commit_deposit,
  }
}

/// The same deployment with the second applied release lifetime.
pub fn alt_parameters() -> CommitmentParameters {
  CommitmentParameters { ..parameters(), commitment_lifetime: alt_lifetime() }
}

/// The second release choice's derived expiry, from the same opening.
pub fn alt_expires_at() -> Int {
  vec.commit_upper + alt_lifetime()
}

/// The canonical scope.
pub fn scope() -> BountyScope {
  BountyScope {
    domain: vec.domain,
    schema: vec.schema,
    network: vec.network,
    checkpoint_policy: vec.checkpoint_policy,
    checkpoint_ref: checkpoint_ref(),
    action: FreezeEntitlement,
    marker: vec.marker,
    commit_upper: vec.commit_upper,
    eligible_after: vec.eligible_after,
    expires_at: vec.expires_at,
  }
}

fn preimage() -> BountyCommitmentPreimage {
  commitment_preimage(scope(), vec.evidence_digest, vec.payee, vec.nonce)
}

/// The canonical scope under the second release choice: same opening, same
/// one-slot maturity, a different derived expiry.
pub fn alt_scope() -> BountyScope {
  BountyScope { ..scope(), expires_at: alt_expires_at() }
}

/// The canonical live commitment datum.
pub fn commitment() -> BountyCommitment {
  BountyCommitmentV1 {
    scope: scope(),
    payee_pkh: vec.payee,
    hash: vec.commitment_hash,
    marker: vec.marker,
  }
}

fn reveal() -> BountyRevealV1 {
  BountyRevealV1 {
    commitment_ref: OutputReference {
      transaction_id: #"0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c",
      output_index: 0,
    },
    nonce: vec.nonce,
    refund_index: vec.refund_index,
  }
}

fn sweep() -> ExpiredCommitmentSweepV1 {
  ExpiredCommitmentSweepV1 {
    recipient_pkh: vec.recipient,
    payout_index: vec.payout_index,
  }
}

/// Flip the low bit of the last byte, preserving the width. Every mutation
/// below stays canonically shaped so rejection can only come from the bound
/// value itself, never from a width check.
pub fn flip_last(bs: ByteArray) -> ByteArray {
  let len = bytearray.length(bs)
  let last = bytearray.at(bs, len - 1)
  let flipped = if last % 2 == 0 {
    last + 1
  } else {
    last - 1
  }
  bytearray.take(bs, len - 1)
    |> bytearray.concat(bytearray.push(#"", flipped))
}

// ---------------------------------------------------------------------
// INV-271-PARITY — canonical Haskell/Aiken bytes
// ---------------------------------------------------------------------

test bounty_commitment_constants_match_haskell() {
  and {
    commitment_domain == vec.domain,
    commitment_schema == vec.schema,
    commit_min_age == vec.commit_min_age,
    commit_deposit_floor == vec.commit_deposit_floor,
  }
}

/// The generated fixture must publish the *derived* boundary and no release
/// default. Nothing on either side may name a mandated lifetime magnitude, so
/// this is what binds the named example to the oracle's arithmetic: change the
/// fixture's lifetime in the Haskell generator without changing the example
/// here, and this reddens instead of regenerating quietly.
test bounty_commitment_generated_boundary_derives_from_the_example_lifetime() {
  and {
    vec.expires_at == vec.commit_upper + example_lifetime(),
    vec.eligible_after == vec.commit_upper + vec.commit_min_age,
    // the two examples are genuinely different deployments, so every
    // cross-pairing below is a real discrimination and not a tautology
    alt_lifetime() != example_lifetime(),
    alt_expires_at() != vec.expires_at,
  }
}

test bounty_commitment_reference_cbor_matches_haskell() {
  and {
    cbor.serialise(seed_ref()) == vec.golden_seed_ref,
    cbor.serialise(checkpoint_ref()) == vec.golden_checkpoint_ref,
  }
}

test bounty_commitment_action_cbor_matches_haskell() {
  and {
    cbor.serialise(FreezeEntitlement) == vec.golden_action_freeze,
    cbor.serialise(ConvictEntitlement) == vec.golden_action_convict,
    vec.golden_action_freeze != vec.golden_action_convict,
  }
}

test bounty_commitment_scope_cbor_matches_haskell() {
  cbor.serialise(scope()) == vec.golden_scope
}

test bounty_commitment_preimage_cbor_matches_haskell() {
  cbor.serialise(preimage()) == vec.golden_preimage
}

test bounty_commitment_datum_cbor_matches_haskell() {
  cbor.serialise(commitment()) == vec.golden_commitment
}

test bounty_commitment_redeemer_cbor_matches_haskell() {
  and {
    cbor.serialise(reveal()) == vec.golden_reveal,
    cbor.serialise(sweep()) == vec.golden_sweep,
    cbor.serialise(Reveal(reveal())) == vec.golden_spend_reveal,
    cbor.serialise(Sweep(sweep())) == vec.golden_spend_sweep,
    cbor.serialise(Open { seed_ref: seed_ref() }) == vec.golden_mint_open,
    cbor.serialise(Retire) == vec.golden_mint_retire,
  }
}

test bounty_commitment_hash_matches_haskell() {
  commitment_hash(preimage()) == vec.commitment_hash
}

// ---------------------------------------------------------------------
// DAT-271-MARKER — the name derives from the consumed seed and nothing else
// ---------------------------------------------------------------------

test bounty_commitment_marker_derives_from_seed_only() {
  and {
    marker_name(seed_ref()) == vec.marker,
    marker_name(other_seed_ref()) == vec.other_marker,
    vec.marker != vec.other_marker,
  }
}

// ---------------------------------------------------------------------
// INV-271-SCOPE — every independently changed field moves the hash, and
// moves it to exactly the digest the Haskell oracle computed
// ---------------------------------------------------------------------

fn moved(mutated: BountyCommitmentPreimage, expected: ByteArray) -> Bool {
  and {
    commitment_hash(mutated) == expected,
    commitment_hash(mutated) != vec.commitment_hash,
  }
}

fn with_scope(s: BountyScope) -> BountyCommitmentPreimage {
  BountyCommitmentPreimage { ..preimage(), scope: s }
}

test bounty_commitment_scope_domain_and_schema_bind() {
  and {
    moved(
      with_scope(BountyScope { ..scope(), domain: "cardano-keri/other" }),
      vec.mut_domain,
    ),
    moved(
      with_scope(BountyScope { ..scope(), schema: vec.schema + 1 }),
      vec.mut_schema,
    ),
  }
}

test bounty_commitment_scope_network_binds() {
  moved(with_scope(BountyScope { ..scope(), network: 2 }), vec.mut_network)
}

test bounty_commitment_scope_checkpoint_binds() {
  and {
    moved(
      with_scope(
        BountyScope {
          ..scope(),
          checkpoint_policy: flip_last(vec.checkpoint_policy),
        },
      ),
      vec.mut_checkpoint_policy,
    ),
    moved(
      with_scope(
        BountyScope {
          ..scope(),
          checkpoint_ref: OutputReference {
            transaction_id: flip_last(vec.checkpoint_txid),
            output_index: vec.checkpoint_index,
          },
        },
      ),
      vec.mut_checkpoint_txid,
    ),
    moved(
      with_scope(
        BountyScope {
          ..scope(),
          checkpoint_ref: OutputReference {
            transaction_id: vec.checkpoint_txid,
            output_index: vec.checkpoint_index + 1,
          },
        },
      ),
      vec.mut_checkpoint_index,
    ),
  }
}

test bounty_commitment_scope_action_binds() {
  moved(
    with_scope(BountyScope { ..scope(), action: ConvictEntitlement }),
    vec.mut_action,
  )
}

test bounty_commitment_scope_marker_binds() {
  moved(
    with_scope(BountyScope { ..scope(), marker: vec.other_marker }),
    vec.mut_marker,
  )
}

test bounty_commitment_scope_timing_binds() {
  and {
    moved(
      with_scope(
        BountyScope {
          ..scope(),
          commit_upper: vec.commit_upper + 1,
          eligible_after: vec.eligible_after + 1,
          expires_at: vec.expires_at + 1,
        },
      ),
      vec.mut_window,
    ),
    moved(
      with_scope(
        BountyScope { ..scope(), eligible_after: vec.eligible_after + 1 },
      ),
      vec.mut_eligible_after,
    ),
    moved(
      with_scope(BountyScope { ..scope(), expires_at: vec.expires_at + 1 }),
      vec.mut_expires_at,
    ),
  }
}

test bounty_commitment_payee_digest_and_nonce_bind() {
  and {
    moved(
      BountyCommitmentPreimage { ..preimage(), payee_pkh: flip_last(vec.payee) },
      vec.mut_payee,
    ),
    moved(
      BountyCommitmentPreimage {
        ..preimage(),
        evidence_digest: flip_last(vec.evidence_digest),
      },
      vec.mut_digest,
    ),
    moved(
      BountyCommitmentPreimage { ..preimage(), nonce: flip_last(vec.nonce) },
      vec.mut_nonce,
    ),
  }
}

// ---------------------------------------------------------------------
// DAT-271-PARAMETERS — mandated age and deposit floor, applied release
// lifetime, no ambient lookup
// ---------------------------------------------------------------------

test bounty_commitment_parameters_are_the_mandated_ones() {
  and {
    parameters_well_formed(parameters()) == ParametersValid,
    parameters_well_formed(
      CommitmentParameters { ..parameters(), commit_min_age: 2 },
    ) == ParametersInvalid(ParametersAge),
    // a release one slot shorter than this fixture's example is a different
    // deployment choice, not an invalid one: the age and the floor are
    // mandated magnitudes, the release lifetime is an applied one
    parameters_well_formed(
      CommitmentParameters {
        ..parameters(),
        commitment_lifetime: example_lifetime() - 1,
      },
    ) == ParametersValid,
    parameters_well_formed(
      CommitmentParameters {
        ..parameters(),
        commit_deposit: commit_deposit_floor - 1,
      },
    ) == ParametersInvalid(ParametersDeposit),
    parameters_well_formed(
      CommitmentParameters {
        ..parameters(),
        commit_deposit: commit_deposit_floor,
      },
    ) == ParametersValid,
  }
}

// ---------------------------------------------------------------------
// INV-271-YAGNI-LIFETIME — the release lifetime is an applied deployment
// parameter, not a protocol magnitude. Its *magnitude* constrains nothing
// about safety; what the protocol owes is that the value is explicit,
// positive, and long enough to contain at least one mature reveal slot.
// ---------------------------------------------------------------------

test bounty_commitment_parameterized_lifetime_is_accepted_at_both_examples() {
  and {
    parameters_well_formed(parameters()) == ParametersValid,
    parameters_well_formed(alt_parameters()) == ParametersValid,
    // the shortest admissible release: expiry lands exactly on the first
    // mature slot, so the reveal window is one slot wide and non-empty
    parameters_well_formed(
      CommitmentParameters {
        ..parameters(),
        commitment_lifetime: vec.commit_min_age,
      },
    ) == ParametersValid,
  }
}

test bounty_commitment_invalid_lifetime_parameters_reject() {
  // Honest limit: because the mandated age is exactly one slot, "shorter
  // than the age" and "nonpositive" denote the SAME set of magnitudes. All
  // three spellings are proved so the rule stays honest whichever way a
  // future reader reads it — they are one class, not three.
  let nonpositive_lifetime = CommitmentParameters {
    ..parameters(),
    commitment_lifetime: 0,
  }
  let negative_lifetime = CommitmentParameters {
    ..parameters(),
    commitment_lifetime: -1,
  }
  let short_lifetime = CommitmentParameters {
    ..parameters(),
    commitment_lifetime: vec.commit_min_age - 1,
  }
  and {
    parameters_well_formed(nonpositive_lifetime) == ParametersInvalid(
      ParametersLifetime,
    ),
    parameters_well_formed(negative_lifetime) == ParametersInvalid(
      ParametersLifetime,
    ),
    parameters_well_formed(short_lifetime) == ParametersInvalid(
      ParametersLifetime,
    ),
  }
}

test bounty_commitment_parameterized_lifetime_derives_distinct_expiry() {
  and {
    // each applied release accepts exactly its own derived boundary
    scope_well_formed(parameters(), scope()) == ScopeValid,
    scope_well_formed(alt_parameters(), alt_scope()) == ScopeValid,
    // and rejects the other example's: the magnitude is applied, not ambient
    scope_well_formed(alt_parameters(), scope()) == ScopeInvalid(ScopeLifetime),
    scope_well_formed(parameters(), alt_scope()) == ScopeInvalid(ScopeLifetime),
    // the exact one-slot maturity is untouched by either release choice
    scope_well_formed(
      alt_parameters(),
      BountyScope { ..alt_scope(), eligible_after: vec.commit_upper },
    ) == ScopeInvalid(ScopeAge),
    scope_well_formed(
      alt_parameters(),
      BountyScope { ..alt_scope(), eligible_after: vec.eligible_after + 1 },
    ) == ScopeInvalid(ScopeAge),
  }
}

test bounty_commitment_deposit_floor_bounds_grind_capital_only() {
  // The floor's removal was tested and rejected, so state what it buys. It
  // raises the *concurrent capital* an attacker must lock to open
  // Open_1..Open_N over candidate checkpoint/action/evidence preimages and
  // reveal only the matching one. It does not defeat that grind and does
  // not force a loss: minimum ADA plus the permissionless expired sweep
  // bound how long each losing UTxO lives, and the attacker may self-sweep
  // its own expired losers and recycle the deposit. Surviving residual, not
  // a defeated attack.
  and {
    commit_deposit_floor == 5_000_000,
    parameters_well_formed(
      CommitmentParameters {
        ..parameters(),
        commit_deposit: commit_deposit_floor - 1,
      },
    ) == ParametersInvalid(ParametersDeposit),
    parameters_well_formed(
      CommitmentParameters {
        ..parameters(),
        commit_deposit: commit_deposit_floor,
      },
    ) == ParametersValid,
    // the floor is a property of the deployment, not of the release choice:
    // a shorter lifetime buys no discount on the capital at risk
    parameters_well_formed(
      CommitmentParameters {
        ..alt_parameters(),
        commit_deposit: commit_deposit_floor - 1,
      },
    ) == ParametersInvalid(ParametersDeposit),
    parameters_well_formed(
      CommitmentParameters {
        ..alt_parameters(),
        commit_deposit: commit_deposit_floor,
      },
    ) == ParametersValid,
  }
}

// ---------------------------------------------------------------------
// DAT-271-SCOPE — canonical widths, configured family, derived timing
// ---------------------------------------------------------------------

test bounty_commitment_scope_well_formedness_is_exact() {
  and {
    scope_well_formed(parameters(), scope()) == ScopeValid,
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), domain: "cardano-keri/other" },
    ) == ScopeInvalid(ScopeDomain),
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), schema: vec.schema + 1 },
    ) == ScopeInvalid(ScopeSchema),
    scope_well_formed(parameters(), BountyScope { ..scope(), network: 2 }) == ScopeInvalid(
      ScopeNetwork,
    ),
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), checkpoint_policy: #"c1c1" },
    ) == ScopeInvalid(ScopeCheckpointPolicyWidth),
    scope_well_formed(
      parameters(),
      BountyScope {
        ..scope(),
        checkpoint_ref: OutputReference {
          transaction_id: #"c2c2",
          output_index: vec.checkpoint_index,
        },
      },
    ) == ScopeInvalid(ScopeCheckpointRefWidth),
    scope_well_formed(parameters(), BountyScope { ..scope(), marker: #"0f82" }) == ScopeInvalid(
      ScopeMarkerWidth,
    ),
  }
}

test bounty_commitment_scope_timing_is_derived_not_asserted() {
  and {
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), eligible_after: vec.commit_upper },
    ) == ScopeInvalid(ScopeAge),
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), eligible_after: vec.eligible_after + 1 },
    ) == ScopeInvalid(ScopeAge),
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), expires_at: vec.expires_at - 1 },
    ) == ScopeInvalid(ScopeLifetime),
    scope_well_formed(
      parameters(),
      BountyScope { ..scope(), expires_at: vec.expires_at + 1 },
    ) == ScopeInvalid(ScopeLifetime),
  }
}

test bounty_commitment_datum_well_formedness_is_exact() {
  and {
    commitment_well_formed(parameters(), commitment()) == CommitmentValid,
    commitment_well_formed(
      parameters(),
      BountyCommitmentV1 { ..commitment(), payee_pkh: #"9a9a" },
    ) == CommitmentInvalid(CommitmentPayeeWidth),
    commitment_well_formed(
      parameters(),
      BountyCommitmentV1 { ..commitment(), hash: #"abcd" },
    ) == CommitmentInvalid(CommitmentHashWidth),
    commitment_well_formed(
      parameters(),
      BountyCommitmentV1 { ..commitment(), marker: vec.other_marker },
    ) == CommitmentInvalid(CommitmentMarkerBinding),
  }
}

// ---------------------------------------------------------------------
// INV-271-AGE / INV-271-LIFETIME — raw ledger boundary semantics
// ---------------------------------------------------------------------

fn bound(t: IntervalBoundType<Int>, inclusive: Bool) -> IntervalBound<Int> {
  IntervalBound { bound_type: t, is_inclusive: inclusive }
}

/// A fully explicit validity range: no normalization, both endpoints raw.
pub fn window(
  lo: IntervalBoundType<Int>,
  lo_inc: Bool,
  hi: IntervalBoundType<Int>,
  hi_inc: Bool,
) -> Interval<Int> {
  Interval { lower_bound: bound(lo, lo_inc), upper_bound: bound(hi, hi_inc) }
}

/// `[l, +inf)` or `(l, +inf)`.
pub fn from_slot(l: Int, inclusive: Bool) -> Interval<Int> {
  window(Finite(l), inclusive, PositiveInfinity, False)
}

/// `(-inf, u]` or `(-inf, u)`.
pub fn until_slot(u: Int, inclusive: Bool) -> Interval<Int> {
  window(NegativeInfinity, False, Finite(u), inclusive)
}

/// A bounded window, the shape a real reveal or sweep carries.
pub fn between(l: Int, l_inc: Bool, u: Int, u_inc: Bool) -> Interval<Int> {
  window(Finite(l), l_inc, Finite(u), u_inc)
}

test bounty_commitment_opening_stores_the_raw_upper_endpoint() {
  and {
    raw_upper(until_slot(vec.commit_upper, True)) == Some(
      (vec.commit_upper, True),
    ),
    raw_upper(until_slot(vec.commit_upper, False)) == Some(
      (vec.commit_upper, False),
    ),
    raw_upper(from_slot(vec.commit_upper, True)) == None,
    raw_upper(window(NegativeInfinity, False, NegativeInfinity, False)) == None,
  }
}

test bounty_commitment_same_slot_reveal_is_immature() {
  and {
    // an inclusive lower at the opening slot could share that very slot
    !at_or_after(from_slot(vec.commit_upper, True), vec.eligible_after),
    // an exclusive lower one slot earlier has the same earliest instant
    !at_or_after(from_slot(vec.commit_upper - 1, False), vec.eligible_after),
  }
}

test bounty_commitment_one_slot_age_boundary_accepts() {
  and {
    // the exact one-slot boundary, spelled inclusively
    at_or_after(from_slot(vec.eligible_after, True), vec.eligible_after),
    // the same semantic instant, spelled exclusively
    at_or_after(from_slot(vec.commit_upper, False), vec.eligible_after),
    at_or_after(from_slot(vec.eligible_after + 1, True), vec.eligible_after),
  }
}

test bounty_commitment_infinite_or_malformed_ranges_reject() {
  and {
    !at_or_after(
      window(NegativeInfinity, False, Finite(vec.expires_at), True),
      vec.eligible_after,
    ),
    !at_or_after(
      window(PositiveInfinity, False, PositiveInfinity, False),
      vec.eligible_after,
    ),
    !at_or_before(
      window(Finite(vec.eligible_after), True, PositiveInfinity, False),
      vec.expires_at,
    ),
    !at_or_before(
      window(Finite(vec.eligible_after), True, NegativeInfinity, False),
      vec.expires_at,
    ),
    !strictly_after(
      window(NegativeInfinity, True, PositiveInfinity, False),
      vec.expires_at,
    ),
  }
}

test bounty_commitment_expiry_boundary_is_exact() {
  and {
    // the exact final reveal endpoint accepts, either spelling
    at_or_before(until_slot(vec.expires_at, True), vec.expires_at),
    at_or_before(until_slot(vec.expires_at + 1, False), vec.expires_at),
    // one slot later rejects, either spelling
    !at_or_before(until_slot(vec.expires_at + 1, True), vec.expires_at),
    !at_or_before(until_slot(vec.expires_at + 2, False), vec.expires_at),
  }
}

test bounty_commitment_sweep_needs_strictly_post_expiry() {
  and {
    // at expiry is premature, either spelling
    !strictly_after(from_slot(vec.expires_at, True), vec.expires_at),
    !strictly_after(from_slot(vec.expires_at - 1, False), vec.expires_at),
    // the first semantically post-expiry instant accepts, either spelling
    strictly_after(from_slot(vec.expires_at + 1, True), vec.expires_at),
    strictly_after(from_slot(vec.expires_at, False), vec.expires_at),
  }
}

// ---------------------------------------------------------------------
// INV-271-AGE / INV-271-LIFETIME — an EMPTY interval denotes no ledger
// instant at all, so a predicate that merely compared its bounds would
// hold vacuously over it. Submission-1 audit findings 1 and 2
// (report sha256 781f2282…, instruments finite-empty-range-v2 /
// finite-empty-sweep): `[1002,1001]` made both shipped reveal legs true,
// and `[11001,11000]` satisfied the shipped sweep leg.
// ---------------------------------------------------------------------

test bounty_commitment_non_empty_classifies_every_bound_pairing() {
  and {
    // honest windows, both mandated spellings
    non_empty(between(vec.eligible_after, True, vec.expires_at, True)),
    non_empty(between(vec.commit_upper, False, vec.expires_at + 1, False)),
    // a single admissible slot is not empty, inclusively or exclusively
    non_empty(between(vec.eligible_after, True, vec.eligible_after, True)),
    non_empty(between(5000, False, 5002, False)),
    // reversed finite bounds
    !non_empty(between(1002, True, 1001, True)),
    !non_empty(between(vec.expires_at + 1, True, vec.expires_at, True)),
    // zero-width exclusive: earliest 5001, latest 5000
    !non_empty(between(5000, False, 5001, False)),
    // half-open and unbounded windows are never empty
    non_empty(from_slot(vec.eligible_after, True)),
    non_empty(until_slot(vec.expires_at, True)),
    non_empty(window(NegativeInfinity, False, PositiveInfinity, False)),
    // degenerate infinity pairings denote nothing
    !non_empty(window(PositiveInfinity, False, PositiveInfinity, False)),
    !non_empty(window(NegativeInfinity, False, NegativeInfinity, False)),
    !non_empty(
      window(Finite(vec.eligible_after), True, NegativeInfinity, False),
    ),
    !non_empty(window(PositiveInfinity, False, Finite(vec.expires_at), True)),
  }
}

test bounty_commitment_boundary_predicates_reject_empty_ranges() {
  // `reversed` is the exact interval the audit instrument applied: it sits
  // inside the canonical reveal window on both legs, yet denotes no slot.
  let reversed = between(1002, True, 1001, True)
  let zero_width = between(5000, False, 5001, False)
  let honest = between(vec.eligible_after, True, vec.expires_at, True)
  let honest_exclusive = between(
    vec.commit_upper,
    False,
    vec.expires_at + 1,
    False,
  )
  and {
    !at_or_after(reversed, vec.eligible_after),
    !at_or_before(reversed, vec.expires_at),
    !at_or_after(zero_width, vec.eligible_after),
    !at_or_before(zero_width, vec.expires_at),
    // the sweep instrument's interval, and its zero-width exclusive twin
    !strictly_after(
      between(vec.expires_at + 1, True, vec.expires_at, True),
      vec.expires_at,
    ),
    !strictly_after(
      between(vec.expires_at, False, vec.expires_at + 1, False),
      vec.expires_at,
    ),
    // every mandated accepted boundary is untouched
    at_or_after(honest, vec.eligible_after),
    at_or_before(honest, vec.expires_at),
    at_or_after(honest_exclusive, vec.eligible_after),
    at_or_before(honest_exclusive, vec.expires_at),
    strictly_after(
      between(vec.expires_at + 1, True, vec.expires_at + 2_000, True),
      vec.expires_at,
    ),
    strictly_after(
      between(vec.expires_at, False, vec.expires_at + 2_000, True),
      vec.expires_at,
    ),
  }
}

// ---------------------------------------------------------------------
// entitlement_matches — pure standalone scope/preimage matching
// ---------------------------------------------------------------------

test bounty_commitment_entitlement_matches_the_honest_opening() {
  entitlement_matches(
    commitment(),
    checkpoint_ref(),
    FreezeEntitlement,
    vec.evidence_digest,
    vec.nonce,
  ) == EntitlementValid
}

test bounty_commitment_entitlement_rejects_substituted_context() {
  and {
    entitlement_matches(
      commitment(),
      checkpoint_ref(),
      ConvictEntitlement,
      vec.evidence_digest,
      vec.nonce,
    ) == EntitlementInvalid(EntitlementAction),
    entitlement_matches(
      commitment(),
      other_seed_ref(),
      FreezeEntitlement,
      vec.evidence_digest,
      vec.nonce,
    ) == EntitlementInvalid(EntitlementCheckpoint),
    entitlement_matches(
      BountyCommitmentV1 { ..commitment(), marker: vec.other_marker },
      checkpoint_ref(),
      FreezeEntitlement,
      vec.evidence_digest,
      vec.nonce,
    ) == EntitlementInvalid(EntitlementMarker),
  }
}

test bounty_commitment_entitlement_rejects_substituted_secrets() {
  and {
    entitlement_matches(
      commitment(),
      checkpoint_ref(),
      FreezeEntitlement,
      flip_last(vec.evidence_digest),
      vec.nonce,
    ) == EntitlementInvalid(EntitlementHash),
    entitlement_matches(
      commitment(),
      checkpoint_ref(),
      FreezeEntitlement,
      vec.evidence_digest,
      flip_last(vec.nonce),
    ) == EntitlementInvalid(EntitlementHash),
    entitlement_matches(
      commitment(),
      checkpoint_ref(),
      FreezeEntitlement,
      #"eded",
      vec.nonce,
    ) == EntitlementInvalid(EntitlementDigestWidth),
    entitlement_matches(
      commitment(),
      checkpoint_ref(),
      FreezeEntitlement,
      vec.evidence_digest,
      #"1111",
    ) == EntitlementInvalid(EntitlementNonceWidth),
  }
}

test bounty_commitment_entitlement_cannot_be_satisfied_by_the_payee_alone() {
  // A commitment whose stored hash was computed for a different payee can
  // never be matched by presenting the honest digest and nonce. Signer
  // membership is not part of this verdict at all.
  entitlement_matches(
    BountyCommitmentV1 { ..commitment(), payee_pkh: flip_last(vec.payee) },
    checkpoint_ref(),
    FreezeEntitlement,
    vec.evidence_digest,
    vec.nonce,
  ) == EntitlementInvalid(EntitlementHash)
}
