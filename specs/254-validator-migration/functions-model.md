# Functions model — #254 validator migration

Artifact ceiling: 10,000 bytes and 200 lines.

Signatures fix the required arguments, results, and ownership boundary. Names
may be adapted only through a versioned mandate amendment before
implementation; no body or algorithm is specified here.

## `MOD-254-PROTOCOL`

### `migration_message`

- **Requirement / slice:** RQ-254-03, RQ-254-08 / S254-1.
- **Signature:** `migration_message(source: MigrationSource, target: MigrationTarget) -> MigrationMessage`
- **Arguments:** `source` carries network/policy/outref/role/state;
  `target` carries policy/address/role/refund.
- **Result:** canonical domain-separated message.
- **Constraints:** every redirectable source/target field is represented;
  canonical serialization is shared with the offchain mirror.

### `checkpoint_migration_authorized`

- **Requirement / slice:** RQ-254-03, RQ-254-04 / S254-1.
- **Signature:** `checkpoint_migration_authorized(source_state: CheckpointDatumV1, message: MigrationMessage, signatures: List<(Int, ByteArray)>) -> MigrationVerdict`
- **Arguments:** source KEL projection, canonical message, indexed signatures.
- **Result:** structured authority verdict.
- **Constraints:** current threshold only; duplicate/invalid/out-of-range
  indices do not count; no transaction signer or governance fallback.

### `valid_predecessor_transition`

- **Requirement / slice:** RQ-254-02, RQ-254-09 / S254-1.
- **Signature:** `valid_predecessor_transition(source: MigrationSource, successor: MigrationSuccessor, accepted_predecessor_policy: PolicyId, tx: Transaction) -> MigrationVerdict`
- **Arguments:** actual consumed source, actual proposed successor, applied
  predecessor-policy parameter, and the shared transaction.
- **Result:** structured predecessor-spend/continuity verdict.
- **Constraints:** exact source policy/ref is spent; source token is burned and
  same-name successor minted/confined in the same transaction. No datum version
  or origin field exists.

## `MOD-254-CHECKPOINT-FAMILY`

### `validate_checkpoint_migrate_out`

- **Requirement / slice:** RQ-254-05 through RQ-254-09, RQ-254-11 / S254-1.
- **Signature:** `validate_checkpoint_migrate_out(authorization: MigrationAuthorization, own_ref: OutputReference, tx: Transaction) -> Bool`
- **Arguments:** authorization, named input, full
  transaction.
- **Result:** ledger acceptance.
- **Constraints:** source role/state/value, controller authorization, exact
  source burn, target mint/output, and unchanged role payload are all checked.

### `validate_checkpoint_migrate_in`

- **Requirement / slice:** RQ-254-01, RQ-254-02, RQ-254-06, RQ-254-09 / S254-1.
- **Signature:** `validate_checkpoint_migrate_in(accepted_predecessor_policy: PolicyId, source_ref: OutputReference, authorization: MigrationAuthorization, policy_id: PolicyId, tx: Transaction) -> Bool`
- **Arguments:** applied predecessor-policy parameter, source ref,
  authorization, target policy, transaction.
- **Result:** ledger acceptance.
- **Constraints:** verifies the old arm ran, the named input belongs to the
  applied predecessor policy, and one old burn/one new mint/one exact target
  output compose atomically.

### `validate_legacy_checkpoint_migrate_in`

- **Requirement / slice:** RQ-254-07, RQ-254-10 / S254-1.
- **Signature:** `validate_legacy_checkpoint_migrate_in(preprod_v0: LegacyCheckpointIdentity, source_ref: OutputReference, close: LegacyCloseEvidence, authorization: MigrationAuthorization, policy_id: PolicyId, tx: Transaction) -> Bool`
- **Arguments:** frozen v0 identity, source ref, old Close evidence, new
  authorization, target policy, transaction.
- **Result:** ledger acceptance.
- **Constraints:** preprod network/policy and ACTIVE only; proves v0
  Close/CloseBurn, exact refund, and equal successor capitalization.

### `checkpoint_transition_continuous`

- **Requirement / slice:** RQ-254-05 through RQ-254-07 / S254-1.
- **Signature:** `checkpoint_transition_continuous(source: CheckpointRoleState, successor: CheckpointRoleState, value_change: PolicyReplacement) -> MigrationVerdict`
- **Arguments:** decoded source/successor roles and policy replacement.
- **Result:** structured identity/role/value verdict.
- **Constraints:** all KEL fields and role payload exact; only the
  source-to-target policy token changes.

## `MOD-254-BOARD-FAMILY`

### `validate_board_migrate_out`

- **Requirement / slice:** RQ-254-12 / S254-2.
- **Signature:** `validate_board_migrate_out(target: MigrationTarget, own_ref: OutputReference, tx: Transaction) -> Bool`
- **Arguments:** authorized target, board input, transaction.
- **Result:** ledger acceptance.
- **Constraints:** source owner signer, exact source burn, same witness marker,
  continuity fields/deposit, and target output.

### `validate_board_migrate_in`

- **Requirement / slice:** RQ-254-02, RQ-254-12 / S254-2.
- **Signature:** `validate_board_migrate_in(accepted_predecessor_policy: PolicyId, source_ref: OutputReference, target_record: BoardDatum, policy_id: PolicyId, tx: Transaction) -> Bool`
- **Arguments:** applied predecessor policy, source ref, proposed target datum,
  target policy, transaction.
- **Result:** ledger acceptance.
- **Constraints:** target schema authentication runs in addition to migration
  continuity; generic migration cannot return an authentication verdict.

### `validate_legacy_board_migrate_in`

- **Requirement / slice:** RQ-254-12, RQ-254-13 / S254-2.
- **Signature:** `validate_legacy_board_migrate_in(preprod_v0: LegacyBoardIdentity, source_ref: OutputReference, target_record: BoardDatum, policy_id: PolicyId, tx: Transaction) -> Bool`
- **Arguments:** frozen v0 identity, source record, target datum/policy,
  transaction.
- **Result:** ledger acceptance.
- **Constraints:** proves old Retire/Burn and owner signer, target
  authentication, same witness/content/owner, deposit, and marker.

## `MOD-254-PARITY`

### `encode_migration_message`

- **Requirement / slice:** RQ-254-03, RQ-254-08 / S254-1.
- **Signature:** `encode_migration_message(source: MigrationSource, target: MigrationTarget) -> ByteString`
- **Arguments:** offchain mirrors of the onchain message inputs.
- **Result:** canonical bytes signed by checkpoint controllers.
- **Constraints:** byte-identical to onchain canonical serialization; frozen
  domain and field order.

### `migration_verdict`

- **Requirement / slice:** all migration invariant rows / S254-1, S254-2.
- **Signature:** `migration_verdict(context: MigrationContext, transition: MigrationTransition) -> Either MigrationError MigrationReceipt`
- **Arguments:** source/target/hash/role/value/signature context and
  proposed transition.
- **Result:** parity verdict and normalized receipt.
- **Constraints:** error classes map one-for-one to generated Aiken vectors.

## `MOD-254-REGISTRY`

### `validate_validator_registry`

- **Requirement / slice:** RQ-254-14 / S254-3.
- **Signature:** `validate_validator_registry(registry: ValidatorRegistry) -> Either [RegistryError] ValidatedRegistry`
- **Arguments:** complete ordered release registry.
- **Result:** validated registry or all structural errors.
- **Constraints:** exact hashes/identities, unique release labels, valid
  accepted-predecessor policies, historical retention, earliest scan point.

### `append_validator_release`

- **Requirement / slice:** RQ-254-14, RQ-254-16 / S254-3.
- **Signature:** `append_validator_release(previous: ValidatedRegistry, release: ValidatorRelease) -> Either [RegistryError] ValidatorRegistry`
- **Arguments:** accepted registry and newly derived release.
- **Result:** append-only successor registry.
- **Constraints:** no overwrite/removal; applied hashes/references are derived
  from the exact build and supplied to M8 registration.

## `MOD-254-DEPLOYMENT`

### `prepare_checkpoint_migration`

- **Requirement / slice:** RQ-254-03 through RQ-254-10 / S254-3.
- **Signature:** `prepare_checkpoint_migration(registry: ValidatedRegistry, source: ActiveCheckpoint, target_release: ReleaseLabel, refund_address: Address) -> Either MigrationPlanError CheckpointMigrationPackage`
- **Arguments:** registry, exact source row, target, legacy refund.
- **Result:** unsigned canonical package containing no secret material.
- **Constraints:** family/role/hash selected from registry; v0 non-ACTIVE
  source rejects before package creation.

### `reconcile_cutover_inventory`

- **Requirement / slice:** RQ-254-13 / S254-3.
- **Signature:** `reconcile_cutover_inventory(source: CutoverInventory, successor: CutoverInventory) -> Either [ReconciliationError] CutoverReconciliation`
- **Arguments:** complete source and successor inventories.
- **Result:** one-for-one transcript.
- **Constraints:** no missing/duplicate pair; exactly three required board
  witnesses; dry-run or settled evidence is distinguished explicitly.

## Downstream signatures not owned here

Follower/query/relayer resolution signatures remain #171-owned. The required
arguments and results are the draft cross-seam contract in `plan.md`; #254 must
not create consumer callbacks, provider handles, or a second query algebra.
