//// Checkpoint-family migration enforcement (#254, MOD-254-CHECKPOINT-FAMILY).
////
//// Three entries, one authorization rule. `validate_checkpoint_migrate_out`
//// is the source generation's exit arm, `validate_checkpoint_migrate_in` the
//// successor generation's entry arm pinned to its exact predecessor, and
//// `validate_legacy_checkpoint_migrate_in` the one-off bridge out of the
//// immutable deployed preprod v0 program, which has no migrate-out arm of its
//// own and must therefore be left through its existing `Close`/`CloseBurn`.
////
//// Authorization is **data, not caller identity**: the only thing that can
//// move a checkpoint is a quorum of its own current controller keys signing
//// `migration_message`. There is deliberately no governance key, no payment
//// credential, no `extra_signatories` fallback and no relayer allowlist, so a
//// valid package stays valid whoever submits it.
////
//// The Haskell mirror is `Cardano.KERI.AID.Migration.Checkpoint` and
//// `offchain/app/GenCheckpointMigrationVectors.hs` is the sole source of
//// `checkpoint_vectors.ak`'s byte fixtures.

use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use cardano/address.{Address, Script}
use cardano/assets.{
  PolicyId, Value, from_asset, from_lovelace, lovelace_of, merge, quantity_of,
  tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/checkpoint/datum.{
  CheckpointDatum, CheckpointDatumV1, DatumValid, V1, VersionedCheckpoint,
  VersionedCheckpointDatum, VersionedV1, datum_well_formed,
}
use cardano_keri/checkpoint/freeze_bond.{
  VersionedArmed, VersionedArmedDatum, VersionedArmedV1,
}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/role
use cardano_keri/checkpoint/threshold.{evaluate}
use cardano_keri/migration/types.{
  CheckpointActive, CheckpointArmed, CheckpointFrozen, MigrationAuthorization,
  MigrationOrigin, MigrationRole, MigrationTarget, ValidatorVersion,
  migration_domain,
}

// ---------------------------------------------------------
// Message inputs
// ---------------------------------------------------------

/// Everything about the generation being left, as the *transaction* observes
/// it — never as the caller asserts it. `state` is the source's own projected
/// state carried verbatim, exactly as `MigrationAuthorization.source_state`
/// carries it.
pub type MigrationSource {
  network_id: Int,
  source_version: ValidatorVersion,
  source_policy: PolicyId,
  source_ref: OutputReference,
  source_role: MigrationRole,
  source_state: Data,
}

/// The canonical, versioned, domain-separated migration preimage. Field order
/// is protocol surface: it changes only by minting a new `ValidatorVersion`.
/// Every caller-controlled field that could redirect identity, value, or
/// successor selection appears here, which is what makes a signature over it
/// unreplayable onto a different move.
pub type MigrationMessage {
  domain: ByteArray,
  network_id: Int,
  source_version: ValidatorVersion,
  source_policy: PolicyId,
  source_ref: OutputReference,
  source_role: MigrationRole,
  source_state: Data,
  target_version: ValidatorVersion,
  target_policy: PolicyId,
  target_role: MigrationRole,
  target_address: Address,
  legacy_refund_address: Option<Address>,
}

/// The applied predecessor a target program pins. Both fields are compiled
/// into the successor program as parameters, so no datum or redeemer value can
/// substitute either identity.
pub type Predecessor {
  predecessor_version: ValidatorVersion,
  predecessor_policy: PolicyId,
}

/// The successor a transaction actually proposes, read from its output.
pub type MigrationSuccessor {
  successor_version: ValidatorVersion,
  successor_policy: PolicyId,
  successor_origin: Option<MigrationOrigin>,
  successor_role: MigrationRole,
}

/// A decoded lifecycle position plus its complete role payload. ARMED carries
/// its hunter and deadline; ACTIVE and FROZEN carry neither.
pub type CheckpointRoleState {
  state_role: MigrationRole,
  checkpoint: CheckpointDatumV1,
  hunter_pkh: Option<ByteArray>,
  deadline: Option<Int>,
}

/// The single admitted value difference across a migration: one named token
/// moves from the source policy to the target policy and nothing else changes.
pub type PolicyReplacement {
  source_policy: PolicyId,
  target_policy: PolicyId,
  asset_name: ByteArray,
  source_value: Value,
  successor_value: Value,
}

/// The immutable identity of the deployed preprod v0 checkpoint program. It is
/// data, pinned by the target program, never derived by recompiling current
/// source: recompilation would produce different bytes and prove nothing about
/// what is actually on preprod.
pub type LegacyCheckpointIdentity {
  legacy_network_name: ByteArray,
  legacy_network_magic: Int,
  legacy_network_id: Int,
  legacy_version: ValidatorVersion,
  legacy_policy: PolicyId,
  legacy_source_commit: ByteArray,
}

/// The v0 exit this bridge requires the same transaction to have performed:
/// its controller-authorized `Close` refund plus the exact `CloseBurn`.
pub type LegacyCloseEvidence {
  legacy_refund_address: Address,
  legacy_refund_lovelace: Int,
  legacy_burned_asset_name: ByteArray,
}

// ---------------------------------------------------------
// Verdicts
// ---------------------------------------------------------

/// Why a migration was refused. Each class maps one-for-one onto a generated
/// Aiken vector and onto a Haskell `MigrationError` constructor, so a parity
/// disagreement is observable as a class change and not only as a byte change.
pub type MigrationError {
  /// the carried source projection is not a well-formed checkpoint datum
  MigrationDatumIllFormed
  /// the current controller threshold is not met by valid distinct indices
  MigrationQuorumUnsatisfied
  /// the target is not exactly the source generation plus one
  MigrationVersionNotSuccessor
  /// the consumed source is not the successor program's pinned predecessor
  MigrationForeignPredecessor
  /// the recorded origin is not the actual consumed source output
  MigrationOriginMismatch
  /// the successor's applied version marker disagrees with its datum
  MigrationAppliedVersionMismatch
  /// a KEL projection field changed across the move
  MigrationIdentityChanged
  /// the lifecycle position or its role payload changed across the move
  MigrationRoleChanged
  /// value moved by more than the one admitted policy-token replacement
  MigrationValueChanged
  /// the behaviour required here is not implemented
  MigrationNotImplemented
}

/// `MigrationValid` ≙ `Right ()`, `MigrationInvalid(e)` ≙ `Left e`.
pub type MigrationVerdict {
  MigrationValid
  MigrationInvalid(MigrationError)
}

// ---------------------------------------------------------
// Behaviour (S254-1B RED: modelled surface, fail-closed bodies)
// ---------------------------------------------------------

/// Build the sole canonical signed migration preimage.
pub fn migration_message(
  source: MigrationSource,
  target: MigrationTarget,
) -> MigrationMessage {
  MigrationMessage {
    domain: migration_domain,
    network_id: source.network_id,
    source_version: source.source_version,
    source_policy: source.source_policy,
    source_ref: source.source_ref,
    source_role: source.source_role,
    source_state: source.source_state,
    target_version: target.target_version,
    target_policy: target.target_policy,
    target_role: target.target_role,
    target_address: target.target_address,
    legacy_refund_address: target.legacy_refund_address,
  }
}

/// Evaluate the source checkpoint's *own* current controller quorum over the
/// canonical message. Nothing else in the transaction can authorize a move.
pub fn checkpoint_migration_authorized(
  _source_state: CheckpointDatumV1,
  _message: MigrationMessage,
  _signatures: List<(Int, ByteArray)>,
) -> MigrationVerdict {
  MigrationInvalid(MigrationNotImplemented)
}

/// Check the permanent N -> N+1 edge, the pinned predecessor identity, and the
/// successor's recorded origin against the actually consumed source.
pub fn valid_migration_edge(
  _source: MigrationSource,
  _successor: MigrationSuccessor,
  _expected_predecessor: Predecessor,
) -> MigrationVerdict {
  MigrationInvalid(MigrationNotImplemented)
}

/// Check that identity, lifecycle position, role payload, and protected value
/// all survive the move, admitting only the one policy-token replacement.
pub fn checkpoint_transition_continuous(
  _source: CheckpointRoleState,
  _successor: CheckpointRoleState,
  _value_change: PolicyReplacement,
) -> MigrationVerdict {
  MigrationInvalid(MigrationNotImplemented)
}

/// The source generation's exit arm.
pub fn validate_checkpoint_migrate_out(
  _version: Int,
  _authorization: MigrationAuthorization,
  _own_ref: OutputReference,
  _tx: Transaction,
) -> Bool {
  False
}

/// The successor generation's entry arm, pinned to its exact predecessor.
pub fn validate_checkpoint_migrate_in(
  _version: Int,
  _predecessor: Predecessor,
  _source_ref: OutputReference,
  _authorization: MigrationAuthorization,
  _policy_id: PolicyId,
  _tx: Transaction,
) -> Bool {
  False
}

/// The one-off bridge out of the immutable deployed preprod v0 program.
pub fn validate_legacy_checkpoint_migrate_in(
  _preprod_v0: LegacyCheckpointIdentity,
  _source_ref: OutputReference,
  _close: LegacyCloseEvidence,
  _authorization: MigrationAuthorization,
  _policy_id: PolicyId,
  _tx: Transaction,
) -> Bool {
  False
}
