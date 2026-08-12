//// The shared migration wire contract (#254, MOD-254-PROTOCOL). Protocol
//// data only: no migrate-in/out behaviour, no deployment identity, no
//// registry, no consumer resolution. Checkpoint, board, deployment, and the
//// #253 endpoints all read these types, so they are declared here once and
//// depend on nothing but ledger references, policies, addresses, and network
//// identity.
////
//// Constructor indices and field order are protocol surface: they change
//// only by minting a new `ValidatorVersion`. The Haskell mirror is
//// `Cardano.KERI.AID.Migration.Types`, and
//// `offchain/app/GenMigrationTypesVectors.hs` is the sole source of the
//// byte fixtures in `types_vectors.ak`, which `types_tests.ak` asserts this
//// encoder reproduces exactly.

use cardano/address.{Address}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference}

/// `MIGRATION_DOMAIN = UTF8("cardano-keri/migration/v1")` — the frozen
/// 25-byte domain separator every migration authorization carries, so an
/// authorization can never be replayed as another protocol's message.
pub const migration_domain: ByteArray =
  #"63617264616e6f2d6b6572692f6d6967726174696f6e2f7631"

/// A validator program generation (DAT-254-VERSION). The wrapper is
/// deliberate: a version is never a bare `Int`, so it cannot alias any other
/// positional integer field. `value` is non-negative; transaction validation
/// later binds it to the applied program and the N -> N+1 edge, which this
/// protocol layer does not check.
pub type ValidatorVersion {
  value: Int,
}

/// Which live lifecycle position a migration moves. The terminal burn state
/// is deliberately absent: it is an end state, not something that can be
/// migrated, so it is unrepresentable here rather than merely unused. `Board`
/// is the board-side position; its state and inventory rules belong to
/// S254-2, never to this module.
pub type MigrationRole {
  CheckpointActive
  CheckpointFrozen
  CheckpointArmed
  Board
}

/// The immediate migration predecessor (DAT-254-ORIGIN): the exact program
/// generation, minting policy, and spent output the current state came from.
/// Absent — `None` — for state that was never migrated. It is exactly one
/// step back, never a chain: each generation records its own predecessor.
pub type MigrationOrigin {
  source_version: ValidatorVersion,
  source_policy: PolicyId,
  source_ref: OutputReference,
}

/// Where a migration lands (DAT-254-TARGET). `legacy_refund_address` is
/// optional and legacy-only: it names where value from a retired generation
/// is returned, and is `None` for every target that has no legacy remainder.
pub type MigrationTarget {
  target_version: ValidatorVersion,
  target_policy: PolicyId,
  target_role: MigrationRole,
  target_address: Address,
  legacy_refund_address: Option<Address>,
}

/// Every input the later canonical authorization message is built from
/// (DAT-254-AUTHORIZATION). No redirectable caller field is omitted: the
/// domain and network pin the protocol and chain, the origin pins the exact
/// spent predecessor, the role and state pin what is being moved, the target
/// pins where it lands including any refund, and the indexed signatures carry
/// the controller evidence.
///
/// `source_state` is the source generation's own projected state, carried
/// verbatim as its canonical Plutus-Data serialization. This layer never
/// interprets, copies, or summarises it — a field-by-field restatement here
/// would be exactly the lossy alternate representation INV-254-IDENTITY
/// forbids, and would bind this module to checkpoint or board content. A
/// later version-specific validator decodes it with its own frozen codec.
///
/// The signatures are `(index, signature)` pairs over the current controller
/// key set. Representing them is all this landing does: quorum evaluation and
/// signature verification are later behaviour.
pub type MigrationAuthorization {
  domain: ByteArray,
  network_id: Int,
  source_origin: MigrationOrigin,
  source_role: MigrationRole,
  source_state: Data,
  target: MigrationTarget,
  controller_signatures: List<(Int, ByteArray)>,
}
