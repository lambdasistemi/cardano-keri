//// The shared migration wire contract (#254, MOD-254-PROTOCOL). Protocol
//// data only: no migrate-in/out behaviour, no deployment identity, no
//// registry, no consumer resolution. Checkpoint, board, deployment, and the
//// #253 endpoints all read these types, so they are declared here once and
//// depend on nothing but ledger references, policies, addresses, and network
//// identity.
////
//// Constructor indices and field order are protocol surface: they change
//// only by a new applied program hash. The Haskell mirror is
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

/// The exact predecessor a migration consumes (DAT-254-PREDECESSOR): the
/// minting policy that holds it and the output being spent.
///
/// There is no program generation here and no stored back-pointer. The
/// successor program is applied with the one predecessor policy it accepts, so
/// its own hash is its release identity, and the atomic transaction — spend
/// this output, burn its token, mint and confine the same-name successor — is
/// the lineage edge. A datum field restating either would be duplicated state
/// that no consumer reads.
pub type MigrationPredecessor {
  predecessor_policy: PolicyId,
  predecessor_ref: OutputReference,
}

/// Where a migration lands (DAT-254-TARGET). `legacy_refund_address` is
/// optional and legacy-only: it names where value from a retired generation
/// is returned, and is `None` for every target that has no legacy remainder.
pub type MigrationTarget {
  target_policy: PolicyId,
  target_role: MigrationRole,
  target_address: Address,
  legacy_refund_address: Option<Address>,
}

/// Every input the later canonical authorization message is built from
/// (DAT-254-AUTHORIZATION). No redirectable caller field is omitted: the
/// domain and network pin the protocol and chain, the predecessor pins the
/// exact spent output, the role and state pin what is being moved, the target
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
  source: MigrationPredecessor,
  source_role: MigrationRole,
  source_state: Data,
  target: MigrationTarget,
  controller_signatures: List<(Int, ByteArray)>,
}
