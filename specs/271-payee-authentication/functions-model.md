# Functions model — #271 enforcement bounty entitlement

Artifact ceiling: 8,000 bytes and 160 lines.

Only new or changed public signatures are modeled. Data is defined in
`data-model.md`; ownership is defined in `modules-model.md`.

## Shared protocol

### `commitment_preimage`

- **Signature:** `commitment_preimage(scope: BountyScope, evidence_digest: ByteArray, payee_pkh: ByteArray, nonce: ByteArray) -> BountyCommitmentPreimage`
- **Constraints:** canonical domain/version; exact scope/payee; nonce at least 32
  bytes; no transaction or KERI effect.

### `commitment_hash`

- **Signature:** `commitment_hash(preimage: BountyCommitmentPreimage) -> ByteArray`
- **Constraints:** canonical serialization and fixed 32-byte digest; identical
  Haskell/Aiken result.

### `enforcement_evidence_digest`

- **Signature:** `enforcement_evidence_digest(evidence: EnforcementEvidence) -> ByteArray`
- **Constraints:** hashes the canonical complete wire evidence consumed by the
  observer; no separately supplied digest is accepted.

### `entitlement_matches`

- **Signature:** `entitlement_matches(commitment: BountyCommitmentV1, checkpoint_ref: OutputReference, action: BountyAction, evidence: EnforcementEvidence, nonce: ByteArray) -> EntitlementVerdict`
- **Constraints:** scope, marker, payee, evidence, nonce, and action are checked;
  signer membership alone cannot return a valid verdict.

## Commitment validator/policy

### `validate_commitment_open`

- **Signature:** `validate_commitment_open(parameters: CommitmentParameters, seed_ref: OutputReference, datum: BountyCommitmentV1, policy_id: PolicyId, tx: Transaction) -> Bool`
- **Constraints:** exact seed, unique marker mint/confinement, datum/value/timing,
  one-slot age, positive finite applied lifetime with at least one mature reveal
  slot and no standalone default, deposit floor, and payee required signer.

### `validate_commitment_reveal`

- **Signature:** `validate_commitment_reveal(parameters: CommitmentParameters, reveal: BountyRevealV1, own_ref: OutputReference, tx: Transaction) -> Bool`
- **Constraints:** mature/unexpired interval, exact marker burn, committed-payee
  refund, and payee signer; entitlement/evidence coupling is additionally
  required by the enforcement observer.

### `validate_commitment_sweep`

- **Signature:** `validate_commitment_sweep(parameters: CommitmentParameters, sweep: ExpiredCommitmentSweepV1, own_ref: OutputReference, tx: Transaction) -> Bool`
- **Constraints:** strictly expired, exact marker burn and deposit payout, sweep
  recipient signer, no checkpoint effect.

## Enforcement integration

### `validate_freeze_entitlement`

- **Signature:** `validate_freeze_entitlement(parameters: EntitlementParameters, evidence: EnforcementEvidence, hunter_pkh: ByteArray, reveal: BountyRevealV1, checkpoint_ref: OutputReference, tx: Transaction) -> EntitlementVerdict`
- **Constraints:** exact Freeze scope/action/evidence; mature commitment; hunter
  equals committed payee; marker/refund terminal shape.

### `validate_convict_entitlement`

- **Signature:** `validate_convict_entitlement(parameters: EntitlementParameters, evidence: EnforcementEvidence, convictor_pkh: ByteArray, reveal: BountyRevealV1, checkpoint_ref: OutputReference, tx: Transaction) -> EntitlementVerdict`
- **Constraints:** exact Convict scope/action/evidence for ACTIVE, ARMED, or
  FROZEN; convictor equals committed payee.

### `validate_claim_entitled_payout`

- **Signature:** `validate_claim_entitled_payout(armed: DAT-254-ARMED, hunter_output_index: Int, tx: Transaction) -> Bool`
- **Constraints:** beneficiary and entitlement derive only from ARMED; exact
  bond/output; no fresh hunter signer requirement.

### `validate_convict_payouts`

- **Signature:** `validate_convict_payouts(source: CheckpointRoleState, convictor_entitlement: ValidEntitlement, convictor_output_index: Int, hunter_output_index: Int, tx: Transaction) -> Bool`
- **Constraints:** source-specific exact amounts; ARMED hunter derives from
  stored entitlement; distinct indices; no fresh hunter signer veto.

## Offchain parity and construction

### `encode_commitment_preimage`

- **Signature:** `encode_commitment_preimage(preimage: BountyCommitmentPreimage) -> ByteString`
- **Constraints:** byte-identical to onchain canonical serialization and frozen
  generated vectors.

### `prepare_bounty_commitment`

- **Signature:** `prepare_bounty_commitment(registry: ValidatedRegistry, source: ResolvedCheckpoint, action: BountyAction, evidence: EnforcementEvidence, payee: PaymentKeyHash, nonce: Nonce, seed: FundingOutput) -> Either CommitmentPlanError CommitmentPlan`
- **Constraints:** registry-derived family/parameters; exact input/action/evidence;
  no secret key material in result; caller retains nonce until reveal.

### `prepare_entitled_enforcement`

- **Signature:** `prepare_entitled_enforcement(registry: ValidatedRegistry, source: ResolvedCheckpoint, commitment: ResolvedCommitment, evidence: EnforcementEvidence, nonce: Nonce) -> Either EntitlementPlanError EnforcementPlan`
- **Constraints:** mature/unexpired matching commitment; resolved references and
  exact payout/refund values; cannot synthesize a new commitment.

### `prepare_expired_sweep`

- **Signature:** `prepare_expired_sweep(registry: ValidatedRegistry, commitment: ResolvedCommitment, recipient: PaymentKeyHash) -> Either SweepPlanError SweepPlan`
- **Constraints:** expiry and value derived from resolved output/registry;
  recipient becomes required signer.
