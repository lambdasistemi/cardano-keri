//// Frozen wire types for the M1 endpoint board (#165).
////
//// `BoardDatumV1` is the follower-facing constructor documented in
//// `specs/165-endpoint-board/datum-schema.md`. Its constructor index and field
//// order are part of the released policy contract.

use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address}
use cardano/transaction.{OutputReference}
use cardano_keri/migration/types.{MigrationTarget}

/// An authenticated KERI endpoint record and its Cardano lifecycle owner.
pub type BoardDatumV1 {
  witness_key: ByteArray,
  endpoint_record: ByteArray,
  endpoint_signature: ByteArray,
  owner_key_hash: VerificationKeyHash,
}

/// Mint-side lifecycle discriminator.
pub type BoardMintRedeemer {
  Post
  Burn
  MigrateIn { source_ref: OutputReference }
  LegacyMigrateIn { source_ref: OutputReference }
}

/// Spend-side endpoint-board lifecycle action.
pub type BoardAction {
  Update
  Retire { refund_address: Address }
  MigrateOut { target: MigrationTarget }
}
