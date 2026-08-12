# Data model — #271 enforcement bounty entitlement

Artifact ceiling: 10,000 bytes and 200 lines.

This model owns new data, relationships, validation, and state invariants.
Placement is in `modules-model.md`; signatures are in `functions-model.md`.

## `DAT-271-ACTION` — `BountyAction`

Closed versioned variants: `FreezeEntitlement` and `ConvictEntitlement`.
ClaimFreeze has no new action because it consumes the hunter entitlement
already recorded by Freeze. The action tag is part of the commitment hash.

## `DAT-271-SCOPE` — `BountyScope`

Fields:

- protocol domain and schema version;
- network discriminator;
- checkpoint policy and exact checkpoint `OutputReference`;
- **DAT-271-ACTION**;
- unique commitment marker identity;
- finite `commit_upper`, `eligible_after`, and `expires_at`.

Validation requires canonical widths, the configured policy/network,
`eligible_after = commit_upper + commit_min_age`, and
`expires_at = commit_upper + commitment_lifetime`.

## `DAT-271-PREIMAGE` — `BountyCommitmentPreimage`

Fields:

- **DAT-271-SCOPE**;
- canonical digest of the complete actual `EnforcementEvidence`;
- 28-byte payee verification-key hash;
- nonce of at least 32 bytes.

Canonical serialization and domain are frozen versioned protocol surface. The
commitment hash is `blake2b_256` of those bytes. Evidence digest and nonce are
not fields of the output datum.

## `DAT-271-MARKER` — `CommitmentMarker`

A quantity-one asset under the applied commitment policy. Its asset name is
derived only from the consumed opening seed, so two openings cannot counterfeit
one identity. The commitment hash binds that marker without a circular
derivation.

Relationships:

- Open consumes the exact seed and mints/confines one marker.
- Reveal or Sweep consumes one marker input and burns exactly one.
- The marker never appears in a checkpoint or payout output.

## `DAT-271-COMMITMENT` — `BountyCommitmentV1`

Fields:

- scope: **DAT-271-SCOPE**;
- payee key hash;
- opaque commitment hash;
- marker asset name.

The output value is exactly the quantity-one marker plus applied
`D_commit`, with inline datum and no other asset. Opening requires the payee in
transaction `extra_signatories`; this records consent to the future fixed
beneficiary. A matching-looking datum without the marker is counterfeit.

## `DAT-271-REVEAL` — `BountyRevealV1`

Fields:

- commitment input reference;
- nonce;
- commitment-deposit refund output index.

The evidence is not duplicated here. **MOD-271-OBSERVER** derives its digest
from the actual observer payload and reconstructs **DAT-271-PREIMAGE** using the
committed payee/scope and supplied nonce.

Valid reveal state:

- finite validity lower is at or after `eligible_after`;
- finite upper is at or before `expires_at`;
- commitment hash, actual evidence, action, and checkpoint input match;
- marker burns once;
- exact `D_commit` refunds to the committed payee with no datum/extra asset;
- the payee is a required signer for the reveal/refund.

## `DAT-271-SWEEP` — `ExpiredCommitmentSweepV1`

Fields: sweep recipient key hash and exact output index.

It is valid only with finite lower strictly after `expires_at`. It burns the
marker and pays exactly `D_commit` to a datum-free, lovelace-only enterprise
address for the recipient, who must be in `extra_signatories`. It references no
checkpoint and grants no entitlement.

## `DAT-271-ARMED` — `ArmedV2`

Versioned checkpoint-family datum containing:

- versioned inner checkpoint state from #254;
- hunter payee key hash;
- hunter commitment marker identity;
- existing hard response deadline.

Freeze may create it only from a matching valid reveal. Claim and ARMED Convict
use both stored hunter and entitlement identity; neither accepts a caller-
selected hunter. `ArmedV1` bytes remain historical and unchanged.

## `DAT-271-ENFORCEMENT-REDEEMERS`

Changed successor-family fields:

- Freeze: evidence remains in the observer; checkpoint redeemer adds commitment
  reference, nonce/reveal identity, committed hunter, and refund index.
- ClaimFreeze: retains hunter payout index and derives beneficiary solely from
  **DAT-271-ARMED**.
- Convict: evidence remains in the observer; checkpoint redeemer adds commitment
  reference, nonce/reveal identity, committed convictor, commitment refund
  index, and existing source-specific payout indices.

Wire changes use new constructors/version tags in the #254 family. Existing v0
constructor indices and serialized data are not edited.

## `DAT-271-PARAMETERS`

- commitment policy/reference identity;
- `commit_min_age`: one network slot in ledger validity units;
- `commitment_lifetime`: 10,000 network slots;
- `commit_deposit`: `max(5,000,000 lovelace, ledger minimum for commitment
  output)` at release preparation.

The #254 registry records exact applied values and network slot conversion.
Changing them creates a new family identity.

## State transitions

- `Seed + Open -> LiveCommitment`
- `LiveCommitment + matching ACTIVE Freeze -> ArmedV2 + marker burn + deposit refund`
- `LiveCommitment + matching ACTIVE|ARMED|FROZEN Convict -> terminal checkpoint burn + marker burn + exact payouts/refund`
- `ArmedV2 -> ClaimFreeze -> FROZEN`, retaining no caller-selected beneficiary.
- `Expired LiveCommitment -> Sweep -> marker absent + sweep payout`
- Losing/stale commitments cannot touch a changed/spent checkpoint and become
  sweepable only at their own expiry.

## Data invariants

- **DATA-INV-271-01:** opaque hash, authentic marker, payee, and scope identify
  one entitlement; none is replaceable by redeemer assertion.
- **DATA-INV-271-02:** actual observer evidence, not a caller-supplied digest,
  determines preimage matching.
- **DATA-INV-271-03:** reveal interval is disjoint from the opening slot and
  bounded by expiry.
- **DATA-INV-271-04:** marker and `D_commit` are conserved exactly across every
  terminal commitment path.
- **DATA-INV-271-05:** every later hunter payment derives from `ArmedV2` and its
  creation-time consent, without a new beneficiary or veto.
- **DATA-INV-271-06:** first valid checkpoint spend decides a race; commitment
  timestamps or caller order claims never decide ledger settlement.
- **DATA-INV-271-07:** entitlement fields are economic transaction context, not
  KEL projection fields, and cannot change enforcement evidence meaning.
