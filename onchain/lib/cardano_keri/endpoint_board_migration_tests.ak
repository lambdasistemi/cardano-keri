//// S254-2 endpoint-board migration RED bundle.
////
//// Every continuity mutant below remains individually authentic. The source
//// content/witness mutants were signed by the independent #253 OpenSSL oracle
//// under `source_policy`; the owner mutant uses #253's genuine target transfer
//// signature. A rejection therefore proves migration continuity, not merely
//// that an Ed25519 signature was corrupted.

use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/endpoint_board_authorization.{AuthorizedBoardDatum, BoardNonce}
use cardano_keri/endpoint_board_migration
use cardano_keri/endpoint_board_types.{BoardDatumV1}
use cardano_keri/migration/types.{Board, MigrationTarget}

const source_policy: PolicyId =
  #"c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"

const target_policy: PolicyId =
  #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

const other_policy: PolicyId =
  #"d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2"

const legacy_policy: PolicyId =
  #"54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

const witness_key: ByteArray =
  #"d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729"

const other_witness_key: ByteArray =
  #"63735ce88e35a698e3789e434073dc5d11b95845087d0c62b14c147929dc241e"

const endpoint_record: ByteArray = #"6c6f632f736368656d652d766563746f722d31"

const other_endpoint_record: ByteArray =
  #"6c6f632f736368656d652d766563746f722d58"

const endpoint_signature: ByteArray =
  #"1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

const other_endpoint_signature: ByteArray =
  #"60d5878ae8b4491905c34c08f6d2448dc66e63f5201dac9d8cc9e391f23ba2c1b2180f03e4b5c4ce3b5c8e2db106bac13a9c951598fb12b1be7a6200b86ecb0e"

const other_witness_endpoint_signature: ByteArray =
  #"a54ab047e0e8c7d882c03745d359a92280921376f34354fc6573182cf4fbbad9defdd4487e2ae84752360f856b5ae0baef5646a28b860caae11fa86fb8a48f0c"

const owner: VerificationKeyHash =
  #"11111111111111111111111111111111111111111111111111111111"

const new_owner: VerificationKeyHash =
  #"22222222222222222222222222222222222222222222222222222222"

const source_authorization_signature: ByteArray =
  #"9f6fc1ede2a56451d479fa7939d11a002488ed0796fac74c3ef9151bc373304dc8311bcc6bbc6b4e94a08e81a4a25c47934dd7c7757d3eb8a16793513f508d07"

const other_content_authorization_signature: ByteArray =
  #"1960e435cbb7d993beb20bacab085464c1e74ed740c1ce2053d6a5d6098c5640a303b17dcadd45d55941df912150134ff50970360e098ec0f0ad89b70ba9c70c"

const other_witness_authorization_signature: ByteArray =
  #"391ee15a550aeeaa3c4d61f5a3464c7270d4b063d202d1ac060d37ac7f77ab9f8e99b1203bb66adb416a0dcd29d513b6cbb19a14529fef5c3ff967034b93a205"

const target_authorization_signature: ByteArray =
  #"6293d5c43801949c41ab88499ab334120b564f0bc087c11d3017d37c3c7aa31d07868fb2bee97371b139c4e8dd0d671d387a1e12aa65b9ef654dd13dba45580d"

const transfer_authorization_signature: ByteArray =
  #"78cb03db990d6caae9f7ff4bb37c0b836d20d666dfa94719703a2656699f27ef7351106cb455562577bcf1873b2dcbb36fc46d98bcb7b89a0a6e7eb376af7404"

const deposit: Int = 4_000_000

const seed_tx_id: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

fn out_ref(tx_id: ByteArray, index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

fn input_at(reference: OutputReference, output: Output) -> Input {
  Input { output_reference: reference, output }
}

fn ada_output(address: Address, lovelace: Int) -> Output {
  Output {
    address,
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn source_ref() -> OutputReference {
  out_ref(seed_tx_id, 0)
}

fn refund_address() -> Address {
  from_verification_key(new_owner)
}

fn nonce(tx_id: ByteArray) -> BoardNonce {
  BoardNonce { nonce_tx_id: tx_id, nonce_output_index: 0 }
}

fn authorized(
  key: ByteArray,
  record: ByteArray,
  endpoint_sig: ByteArray,
  owner_key_hash: ByteArray,
  bound_nonce: BoardNonce,
  authorization_signature: ByteArray,
) -> AuthorizedBoardDatum {
  AuthorizedBoardDatum {
    witness_key: key,
    endpoint_record: record,
    endpoint_signature: endpoint_sig,
    owner_key_hash,
    nonce: bound_nonce,
    authorization_signature,
  }
}

fn source_datum() -> AuthorizedBoardDatum {
  authorized(
    witness_key,
    endpoint_record,
    endpoint_signature,
    owner,
    nonce(#"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"),
    source_authorization_signature,
  )
}

fn target_datum() -> AuthorizedBoardDatum {
  authorized(
    witness_key,
    endpoint_record,
    endpoint_signature,
    owner,
    nonce(seed_tx_id),
    target_authorization_signature,
  )
}

fn changed_owner_target() -> AuthorizedBoardDatum {
  authorized(
    witness_key,
    endpoint_record,
    endpoint_signature,
    new_owner,
    nonce(seed_tx_id),
    transfer_authorization_signature,
  )
}

fn changed_content_source() -> AuthorizedBoardDatum {
  authorized(
    witness_key,
    other_endpoint_record,
    other_endpoint_signature,
    owner,
    nonce(#"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"),
    other_content_authorization_signature,
  )
}

fn changed_witness_source() -> AuthorizedBoardDatum {
  authorized(
    other_witness_key,
    endpoint_record,
    other_witness_endpoint_signature,
    owner,
    nonce(#"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"),
    other_witness_authorization_signature,
  )
}

fn legacy_datum() -> BoardDatumV1 {
  BoardDatumV1 {
    witness_key,
    endpoint_record,
    endpoint_signature,
    owner_key_hash: owner,
  }
}

fn marker_value(policy_id: PolicyId, name: ByteArray, lovelace: Int) -> Value {
  from_lovelace(lovelace) |> merge(from_asset(policy_id, name, 1))
}

fn current_output(policy_id: PolicyId, datum: AuthorizedBoardDatum) -> Output {
  Output {
    address: from_script(policy_id),
    value: marker_value(policy_id, datum.witness_key, deposit),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn legacy_output() -> Output {
  Output {
    address: from_script(legacy_policy),
    value: marker_value(legacy_policy, witness_key, deposit),
    datum: InlineDatum(legacy_datum()),
    reference_script: None,
  }
}

fn target_output(
  datum: AuthorizedBoardDatum,
  name: ByteArray,
  lovelace: Int,
) -> Output {
  Output {
    address: from_script(target_policy),
    value: marker_value(target_policy, name, lovelace),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn migration_target(refund: Option<Address>) -> MigrationTarget {
  MigrationTarget {
    target_policy,
    target_role: Board,
    target_address: from_script(target_policy),
    legacy_refund_address: refund,
  }
}

fn permanent_tx(
  source: AuthorizedBoardDatum,
  successor: AuthorizedBoardDatum,
  successor_name: ByteArray,
  successor_deposit: Int,
  include_source: Bool,
  include_successor: Bool,
) -> Transaction {
  let source_inputs = if include_source {
    [input_at(source_ref(), current_output(source_policy, source))]
  } else {
    []
  }
  let successor_outputs = if include_successor {
    [target_output(successor, successor_name, successor_deposit)]
  } else {
    []
  }
  Transaction {
    ..placeholder,
    inputs: source_inputs,
    outputs: successor_outputs,
    mint: from_asset(source_policy, source.witness_key, -1)
      |> merge(from_asset(target_policy, successor_name, 1)),
    extra_signatories: [owner],
  }
}

fn honest_permanent_tx() -> Transaction {
  permanent_tx(source_datum(), target_datum(), witness_key, deposit, True, True)
}

fn legacy_tx(successor_name: ByteArray, include_source: Bool) -> Transaction {
  let source_inputs = if include_source {
    [input_at(source_ref(), legacy_output())]
  } else {
    []
  }
  Transaction {
    ..placeholder,
    inputs: source_inputs,
    outputs: [
      ada_output(refund_address(), deposit),
      target_output(target_datum(), successor_name, deposit),
    ],
    mint: from_asset(legacy_policy, witness_key, -1)
      |> merge(from_asset(target_policy, successor_name, 1)),
    extra_signatories: [owner],
  }
}

fn migrate_out(tx: Transaction) -> Bool {
  endpoint_board_migration.validate_board_migrate_out(
    migration_target(None),
    source_ref(),
    tx,
  )
}

fn migrate_in(accepted: PolicyId, tx: Transaction) -> Bool {
  endpoint_board_migration.validate_board_migrate_in(
    accepted,
    source_ref(),
    target_datum(),
    target_policy,
    tx,
  )
}

fn legacy_migrate_in(tx: Transaction) -> Bool {
  endpoint_board_migration.validate_legacy_board_migrate_in(
    endpoint_board_migration.preprod_v0_identity(),
    source_ref(),
    target_datum(),
    target_policy,
    tx,
  )
}

test board_migrate_out_accepts_atomic_successor() {
  migrate_out(honest_permanent_tx())
}

test s254_2_board_migrate_out_is_permanent() fail {
  migrate_out(
    permanent_tx(
      source_datum(),
      target_datum(),
      witness_key,
      deposit,
      True,
      False,
    ),
  )
}

test board_migrate_in_accepts_applied_predecessor() {
  migrate_in(source_policy, honest_permanent_tx())
}

test s254_2_board_migrate_in_requires_applied_predecessor() fail {
  migrate_in(other_policy, honest_permanent_tx())
}

test board_migration_preserves_all_continuity_fields() {
  migrate_in(source_policy, honest_permanent_tx())
}

test s254_2_board_continuity_owner_witness_content_deposit() fail {
  migrate_in(
    source_policy,
    permanent_tx(
      source_datum(),
      changed_owner_target(),
      witness_key,
      deposit,
      True,
      True,
    ),
  )
}

test board_migration_rejects_changed_witness() fail {
  migrate_in(
    source_policy,
    permanent_tx(
      changed_witness_source(),
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
    ),
  )
}

test board_migration_rejects_changed_content() fail {
  migrate_in(
    source_policy,
    permanent_tx(
      changed_content_source(),
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
    ),
  )
}

test board_migration_rejects_changed_deposit() fail {
  migrate_in(
    source_policy,
    permanent_tx(
      source_datum(),
      target_datum(),
      witness_key,
      deposit - 1,
      True,
      True,
    ),
  )
}

test board_v0_bridge_accepts_same_name_successor() {
  legacy_migrate_in(legacy_tx(witness_key, True))
}

test s254_2_board_v0_retire_burn_bridge_same_name_successor() fail {
  legacy_migrate_in(legacy_tx(other_witness_key, True))
}

test board_permanent_migration_spends_predecessor_in_same_transaction() {
  migrate_in(source_policy, honest_permanent_tx())
}

test s254_2_board_predecessor_spent_in_same_transaction() fail {
  migrate_in(
    source_policy,
    permanent_tx(
      source_datum(),
      target_datum(),
      witness_key,
      deposit,
      False,
      True,
    ),
  )
}

test board_legacy_migration_rejects_missing_predecessor() fail {
  legacy_migrate_in(legacy_tx(witness_key, False))
}

test board_migration_accepts_unchanged_target_authentication() {
  migrate_in(source_policy, honest_permanent_tx())
}

test s254_2_board_target_authentication_not_weakened() fail {
  let forged = AuthorizedBoardDatum {
    ..target_datum(),
    authorization_signature: source_authorization_signature,
  }
  endpoint_board_migration.validate_board_migrate_in(
    source_policy,
    source_ref(),
    forged,
    target_policy,
    permanent_tx(source_datum(), forged, witness_key, deposit, True, True),
  )
}
