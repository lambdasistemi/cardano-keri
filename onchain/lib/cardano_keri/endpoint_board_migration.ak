//// Endpoint-board family migration enforcement (#254, MOD-254-BOARD-FAMILY).
////
//// This RED surface is deliberately fail-closed. The proof bundle fixes the
//// public contract before behavior is implemented: #253 continues to own the
//// authorized target datum, while this module owns only atomic migration.

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/endpoint_board_authorization.{AuthorizedBoardDatum}
use cardano_keri/migration/types.{MigrationTarget}

/// The immutable identity of the deployed preprod v0 board program.
pub type LegacyBoardIdentity {
  legacy_network_magic: Int,
  legacy_policy: PolicyId,
  legacy_reference: OutputReference,
  legacy_source_commit: ByteArray,
}

/// T254-004's committed preprod v0 board identity.
pub fn preprod_v0_identity() -> LegacyBoardIdentity {
  LegacyBoardIdentity {
    legacy_network_magic: 1,
    legacy_policy: #"54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c",
    legacy_reference: OutputReference {
      transaction_id: #"967b86211ab7c80876ae4b6bec0e478dd92a98f14d5c3d751a99ad01c04654d4",
      output_index: 0,
    },
    legacy_source_commit: "95b554fbdc9dee5b4437d3a8deeb882f114a0bf3",
  }
}

/// Leave a permanent board generation through one atomic successor edge.
pub fn validate_board_migrate_out(
  _target: MigrationTarget,
  _own_ref: OutputReference,
  _tx: Transaction,
) -> Bool {
  False
}

/// Enter from the one predecessor policy compiled into this target.
pub fn validate_board_migrate_in(
  _accepted_predecessor_policy: PolicyId,
  _source_ref: OutputReference,
  _target_record: AuthorizedBoardDatum,
  _policy_id: PolicyId,
  _tx: Transaction,
) -> Bool {
  False
}

/// Enter from the frozen deployed v0 board through Retire/Burn.
pub fn validate_legacy_board_migrate_in(
  _preprod_v0: LegacyBoardIdentity,
  _source_ref: OutputReference,
  _target_record: AuthorizedBoardDatum,
  _policy_id: PolicyId,
  _tx: Transaction,
) -> Bool {
  False
}
