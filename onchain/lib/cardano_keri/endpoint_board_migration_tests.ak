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
  InlineDatum, Input, NoDatum, Output, OutputReference, Spend, Transaction,
  placeholder,
}
use cardano_keri/endpoint_board_authorization.{AuthorizedBoardDatum, BoardNonce}
use cardano_keri/endpoint_board_migration
use cardano_keri/endpoint_board_types.{BoardDatumV1, Retire}
use cardano_keri/migration/types.{Board, CheckpointActive, MigrationTarget}

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

const stranger: VerificationKeyHash =
  #"44444444444444444444444444444444444444444444444444444444"

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

const source_nonce_tx_id: ByteArray =
  #"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"

const foreign_source_tx_id: ByteArray =
  #"a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3"

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
    nonce(source_nonce_tx_id),
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
    nonce(source_nonce_tx_id),
    other_content_authorization_signature,
  )
}

fn changed_witness_source() -> AuthorizedBoardDatum {
  authorized(
    other_witness_key,
    endpoint_record,
    other_witness_endpoint_signature,
    owner,
    nonce(source_nonce_tx_id),
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

fn authorized_output(
  policy_id: PolicyId,
  datum: AuthorizedBoardDatum,
  name: ByteArray,
  lovelace: Int,
) -> Output {
  Output {
    address: from_script(policy_id),
    value: marker_value(policy_id, name, lovelace),
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

fn transition_mint(
  source_policy_id: PolicyId,
  target_policy_id: PolicyId,
  source_name: ByteArray,
  target_name: ByteArray,
) -> Value {
  from_asset(source_policy_id, source_name, -1)
    |> merge(from_asset(target_policy_id, target_name, 1))
}

fn transition_tx(
  source_policy_id: PolicyId,
  target_policy_id: PolicyId,
  reference: OutputReference,
  source: AuthorizedBoardDatum,
  source_deposit: Int,
  successor: AuthorizedBoardDatum,
  successor_name: ByteArray,
  successor_deposit: Int,
  include_source: Bool,
  include_successor: Bool,
  minted: Value,
  signatories: List<VerificationKeyHash>,
) -> Transaction {
  let source_inputs = if include_source {
    [
      input_at(
        reference,
        authorized_output(
          source_policy_id,
          source,
          source.witness_key,
          source_deposit,
        ),
      ),
    ]
  } else {
    []
  }
  let successor_outputs = if include_successor {
    [
      authorized_output(
        target_policy_id,
        successor,
        successor_name,
        successor_deposit,
      ),
    ]
  } else {
    []
  }
  Transaction {
    ..placeholder,
    inputs: source_inputs,
    outputs: successor_outputs,
    mint: minted,
    extra_signatories: signatories,
  }
}

fn permanent_tx_with(
  source: AuthorizedBoardDatum,
  source_deposit: Int,
  successor: AuthorizedBoardDatum,
  successor_name: ByteArray,
  successor_deposit: Int,
  include_source: Bool,
  include_successor: Bool,
  minted: Value,
  signatories: List<VerificationKeyHash>,
) -> Transaction {
  transition_tx(
    source_policy,
    target_policy,
    source_ref(),
    source,
    source_deposit,
    successor,
    successor_name,
    successor_deposit,
    include_source,
    include_successor,
    minted,
    signatories,
  )
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
  permanent_tx_with(
    source,
    deposit,
    successor,
    successor_name,
    successor_deposit,
    include_source,
    include_successor,
    transition_mint(
      source_policy,
      target_policy,
      source.witness_key,
      successor_name,
    ),
    [owner],
  )
}

fn honest_permanent_tx() -> Transaction {
  permanent_tx(source_datum(), target_datum(), witness_key, deposit, True, True)
}

fn legacy_tx_with(
  reference: OutputReference,
  source_output: Output,
  include_source: Bool,
  outputs: List<Output>,
  minted: Value,
  signatories: List<VerificationKeyHash>,
) -> Transaction {
  let source_inputs = if include_source {
    [input_at(reference, source_output)]
  } else {
    []
  }
  let source_redeemer: Data = Retire { refund_address: refund_address() }
  Transaction {
    ..placeholder,
    inputs: source_inputs,
    outputs,
    mint: minted,
    extra_signatories: signatories,
    redeemers: [Pair(Spend(reference), source_redeemer)],
  }
}

fn legacy_tx(successor_name: ByteArray, include_source: Bool) -> Transaction {
  legacy_tx_with(
    source_ref(),
    legacy_output(),
    include_source,
    [
      ada_output(refund_address(), deposit),
      authorized_output(target_policy, target_datum(), successor_name, deposit),
    ],
    transition_mint(legacy_policy, target_policy, witness_key, successor_name),
    [owner],
  )
}

fn migrate_out(tx: Transaction) -> Bool {
  endpoint_board_migration.validate_board_migrate_out(
    migration_target(None),
    source_ref(),
    tx,
  )
}

fn migrate_in_at(
  accepted: PolicyId,
  reference: OutputReference,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  endpoint_board_migration.validate_board_migrate_in(
    accepted,
    reference,
    policy_id,
    tx,
  )
}

fn migrate_in(accepted: PolicyId, tx: Transaction) -> Bool {
  migrate_in_at(accepted, source_ref(), target_policy, tx)
}

fn target_migrate_in(
  accepted: PolicyId,
  reference: OutputReference,
  tx: Transaction,
) -> Bool {
  migrate_in_at(accepted, reference, target_policy, tx)
}

fn legacy_migrate_in_at(
  reference: OutputReference,
  expected_refund_address: Address,
  tx: Transaction,
) -> Bool {
  endpoint_board_migration.validate_legacy_board_migrate_in(
    reference,
    expected_refund_address,
    target_policy,
    tx,
  )
}

fn legacy_migrate_in(tx: Transaction) -> Bool {
  endpoint_board_migration.validate_legacy_board_migrate_in(
    source_ref(),
    refund_address(),
    target_policy,
    tx,
  )
}

test board_migrate_out_accepts_atomic_successor() {
  migrate_out(honest_permanent_tx())
}

test s254_2_board_migrate_out_is_permanent() fail {
  migrate_out(
    permanent_tx_with(
      source_datum(),
      deposit,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
      from_asset(target_policy, witness_key, 1),
      [owner],
    ),
  )
}

test s254_2_board_migrate_out_requires_exactly_one_target_mint() fail {
  migrate_out(
    permanent_tx_with(
      source_datum(),
      deposit,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
      from_asset(source_policy, witness_key, -1)
        |> merge(from_asset(target_policy, witness_key, 2)),
      [owner],
    ),
  )
}

test s254_2_board_migrate_out_rejects_foreign_role() fail {
  endpoint_board_migration.validate_board_migrate_out(
    MigrationTarget { ..migration_target(None), target_role: CheckpointActive },
    source_ref(),
    honest_permanent_tx(),
  )
}

test s254_2_board_migrate_out_rejects_foreign_target_address() fail {
  endpoint_board_migration.validate_board_migrate_out(
    MigrationTarget {
      ..migration_target(None),
      target_address: from_script(other_policy),
    },
    source_ref(),
    honest_permanent_tx(),
  )
}

test s254_2_board_migrate_out_rejects_legacy_refund() fail {
  endpoint_board_migration.validate_board_migrate_out(
    MigrationTarget {
      ..migration_target(None),
      legacy_refund_address: Some(refund_address()),
    },
    source_ref(),
    honest_permanent_tx(),
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

test s254_2_board_migration_rejects_unauthentic_source() fail {
  let forged_source = AuthorizedBoardDatum {
    ..source_datum(),
    authorization_signature: target_authorization_signature,
  }
  migrate_in(
    source_policy,
    permanent_tx(
      forged_source,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
    ),
  )
}

test s254_2_board_migration_rejects_wrong_source_marker() fail {
  let wrong_source = Output {
    ..authorized_output(source_policy, source_datum(), witness_key, deposit),
    value: from_lovelace(deposit),
  }
  let invalid = Transaction {
    ..honest_permanent_tx(),
    inputs: [input_at(source_ref(), wrong_source)],
  }
  migrate_in(source_policy, invalid)
}

test s254_2_board_migration_rejects_duplicate_successor() fail {
  let successor = authorized_output(
    target_policy,
    target_datum(),
    witness_key,
    deposit,
  )
  let invalid = Transaction {
    ..honest_permanent_tx(),
    outputs: [successor, successor],
  }
  migrate_in(source_policy, invalid)
}

test s254_2_board_migration_rejects_zero_deposit() fail {
  migrate_in_at(
    source_policy,
    source_ref(),
    target_policy,
    transition_tx(
      source_policy,
      target_policy,
      source_ref(),
      source_datum(),
      0,
      target_datum(),
      witness_key,
      0,
      True,
      True,
      transition_mint(source_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_migration_rejects_target_marker_mismatch() fail {
  migrate_in_at(
    source_policy,
    source_ref(),
    target_policy,
    transition_tx(
      source_policy,
      target_policy,
      source_ref(),
      source_datum(),
      deposit,
      target_datum(),
      other_witness_key,
      deposit,
      True,
      True,
      transition_mint(source_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_continuity_owner_witness_content_deposit() fail {
  let reference = out_ref(source_nonce_tx_id, 0)
  migrate_in_at(
    target_policy,
    reference,
    source_policy,
    transition_tx(
      target_policy,
      source_policy,
      reference,
      changed_owner_target(),
      deposit,
      source_datum(),
      witness_key,
      deposit,
      True,
      True,
      transition_mint(target_policy, source_policy, witness_key, witness_key),
      [new_owner],
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

test board_migration_rejects_changed_source_reference() fail {
  let reference = out_ref(foreign_source_tx_id, 0)
  migrate_in_at(
    source_policy,
    reference,
    target_policy,
    transition_tx(
      source_policy,
      target_policy,
      reference,
      source_datum(),
      deposit,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
      transition_mint(source_policy, target_policy, witness_key, witness_key),
      [owner],
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
  migrate_in_at(
    source_policy,
    source_ref(),
    target_policy,
    transition_tx(
      source_policy,
      target_policy,
      source_ref(),
      source_datum(),
      deposit + 1,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
      transition_mint(source_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_permanent_migration_rejects_missing_owner() fail {
  migrate_in(
    source_policy,
    permanent_tx_with(
      source_datum(),
      deposit,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
      transition_mint(source_policy, target_policy, witness_key, witness_key),
      [],
    ),
  )
}

test s254_2_board_permanent_migration_rejects_foreign_owner() fail {
  migrate_in(
    source_policy,
    permanent_tx_with(
      source_datum(),
      deposit,
      target_datum(),
      witness_key,
      deposit,
      True,
      True,
      transition_mint(source_policy, target_policy, witness_key, witness_key),
      [stranger],
    ),
  )
}

test board_v0_bridge_accepts_same_name_successor() {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx(witness_key, True),
  )
}

test s254_2_board_v0_retire_burn_bridge_same_name_successor() fail {
  legacy_migrate_in(legacy_tx(other_witness_key, True))
}

test s254_2_board_legacy_migration_rejects_missing_owner() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_foreign_owner() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [stranger],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_short_refund() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit - 1),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_foreign_refund() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(from_verification_key(stranger), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_refund_redeemer_mismatch() fail {
  let foreign_refund = from_verification_key(stranger)
  legacy_migrate_in_at(
    source_ref(),
    foreign_refund,
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(foreign_refund, deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_duplicate_refund() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_surviving_source_marker() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
        legacy_output(),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_wrong_source_marker() fail {
  let unmarked_source = Output {
    ..legacy_output(),
    value: from_lovelace(deposit),
  }
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      unmarked_source,
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_unauthentic_source() fail {
  let forged_datum = BoardDatumV1 {
    ..legacy_datum(),
    endpoint_signature: target_authorization_signature,
  }
  let forged_source = Output {
    ..legacy_output(),
    datum: InlineDatum(forged_datum),
  }
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      forged_source,
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_wrong_source_address() fail {
  let misplaced_source = Output {
    ..legacy_output(),
    address: from_script(other_policy),
  }
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      misplaced_source,
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_wrong_successor_address() fail {
  let misplaced_successor = Output {
    ..authorized_output(target_policy, target_datum(), witness_key, deposit),
    address: from_script(other_policy),
  }
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [ada_output(refund_address(), deposit), misplaced_successor],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_missing_burn() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      from_asset(target_policy, witness_key, 1),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_wrong_mint_quantity() fail {
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      from_asset(legacy_policy, witness_key, -1)
        |> merge(from_asset(target_policy, witness_key, 2)),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_datum_bearing_refund() fail {
  let datum_refund = Output {
    address: refund_address(),
    value: from_lovelace(deposit),
    datum: InlineDatum(legacy_datum()),
    reference_script: None,
  }
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        datum_refund,
        authorized_output(target_policy, target_datum(), witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}

test s254_2_board_legacy_migration_rejects_wrong_source_reference() fail {
  let claimed_reference = out_ref(source_nonce_tx_id, 0)
  let base = legacy_tx_with(
    source_ref(),
    legacy_output(),
    True,
    [
      ada_output(refund_address(), deposit),
      authorized_output(source_policy, source_datum(), witness_key, deposit),
    ],
    transition_mint(legacy_policy, source_policy, witness_key, witness_key),
    [owner],
  )
  let source_redeemer: Data = Retire { refund_address: refund_address() }
  let invalid = Transaction {
    ..base,
    redeemers: [Pair(Spend(claimed_reference), source_redeemer)],
  }
  endpoint_board_migration.validate_legacy_board_migrate_in(
    claimed_reference,
    refund_address(),
    source_policy,
    invalid,
  )
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
  target_migrate_in(
    source_policy,
    source_ref(),
    permanent_tx(source_datum(), forged, witness_key, deposit, True, True),
  )
}

test s254_2_board_legacy_target_authentication_not_weakened() fail {
  let forged = AuthorizedBoardDatum {
    ..target_datum(),
    authorization_signature: source_authorization_signature,
  }
  legacy_migrate_in_at(
    source_ref(),
    refund_address(),
    legacy_tx_with(
      source_ref(),
      legacy_output(),
      True,
      [
        ada_output(refund_address(), deposit),
        authorized_output(target_policy, forged, witness_key, deposit),
      ],
      transition_mint(legacy_policy, target_policy, witness_key, witness_key),
      [owner],
    ),
  )
}
