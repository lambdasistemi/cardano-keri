//// Authorized endpoint-board combined minting and spending validator (#253).
////
//// Each current record is one enterprise-script UTxO containing one marker
//// whose asset name is the raw 32-byte witness key. The exact endpoint bytes
//// are authenticated by the witness's #165 endpoint signature, and the
//// Cardano binding of those bytes — this applied policy, this owner, this
//// one-use nonce — is authenticated by a second, independent witness
//// signature. A recorded Cardano payment key controls update/retire and the
//// complete lovelace deposit is preserved or refunded.
////
//// The validator is applied with the predecessor policy it accepts, so its
//// identity is a function of that parameter. The parameter is used here to
//// refuse a board marker — of this release or of its predecessor — as a Post
//// nonce: the nonce must be an ordinary consumed output, never another
//// lineage's marker.
////
//// It accepts only the six-field authorized shape. A four-field legacy datum
//// fails to decode at this policy, which is what keeps the two releases
//// distinguishable while both use constructor 0.

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Spend, Transaction,
  find_input, placeholder,
}
use cardano_keri/endpoint_board_authorization.{
  AuthorizedBoardDatum, BoardNonce, datum_is_authentic, nonce_names,
  nonce_reference,
}
use cardano_keri/endpoint_board_migration
use cardano_keri/endpoint_board_types.{
  BoardAction, BoardDatumV1, BoardMintRedeemer, Burn, LegacyMigrateIn, MigrateIn,
  MigrateOut, Post, Retire, Update,
}
use cardano_keri/migration/types.{Board, MigrationTarget}

fn exact_marker_value(
  value,
  policy_id: PolicyId,
  witness_key: ByteArray,
) -> Bool {
  let deposit = lovelace_of(value)
  deposit > 0 && value == (
    from_lovelace(deposit) |> merge(from_asset(policy_id, witness_key, 1))
  )
}

/// The single continuing output this policy may create.
fn board_outputs(policy_id: PolicyId, outputs: List<Output>) -> List<Output> {
  list.filter(outputs, fn(output) { output.address == from_script(policy_id) })
}

fn read_board_input(
  own_ref: OutputReference,
  tx: Transaction,
) -> (Output, PolicyId, AuthorizedBoardDatum) {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect Script(policy_id) = own_input.output.address.payment_credential
  expect own_input.output.address == from_script(policy_id)
  expect InlineDatum(datum_data) = own_input.output.datum
  expect datum: AuthorizedBoardDatum = datum_data
  expect datum_is_authentic(datum.witness_key, policy_id, datum)
  expect
    exact_marker_value(own_input.output.value, policy_id, datum.witness_key)
  (own_input.output, policy_id, datum)
}

/// The nonce output must be consumed by this very transaction and must not be
/// a board marker of this release or of the accepted predecessor release.
///
/// Consumption is what makes the witness's approval one-use: the ledger will
/// never allow the same output to be spent twice, so the same signed Post can
/// never create a second live record — nor resurrect a retired one.
fn consumes_ordinary_nonce(
  accepted_predecessor_policy: PolicyId,
  policy_id: PolicyId,
  datum: AuthorizedBoardDatum,
  tx: Transaction,
) -> Bool {
  expect Some(nonce_input) = find_input(tx.inputs, nonce_reference(datum.nonce))
  expect dict.to_pairs(tokens(nonce_input.output.value, policy_id)) == []
  expect
    dict.to_pairs(tokens(nonce_input.output.value, accepted_predecessor_policy)) == []
  True
}

fn validate_post(
  accepted_predecessor_policy: PolicyId,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { outputs, mint, .. } = tx
  expect [Pair(witness_key, quantity)] = dict.to_pairs(tokens(mint, policy_id))
  expect bytearray.length(witness_key) == 32
  expect quantity == 1
  expect [record_output] = board_outputs(policy_id, outputs)
  expect InlineDatum(datum_data) = record_output.datum
  expect datum: AuthorizedBoardDatum = datum_data
  expect datum_is_authentic(witness_key, policy_id, datum)
  expect exact_marker_value(record_output.value, policy_id, witness_key)
  consumes_ordinary_nonce(accepted_predecessor_policy, policy_id, datum, tx)
}

fn validate_burn(policy_id: PolicyId, tx: Transaction) -> Bool {
  let Transaction { inputs, mint, .. } = tx
  expect [Pair(witness_key, quantity)] = dict.to_pairs(tokens(mint, policy_id))
  expect bytearray.length(witness_key) == 32
  expect quantity == -1
  expect [board_input] = list.filter(
    inputs,
    fn(input) {
      input.output.address == from_script(policy_id) && quantity_of(
        input.output.value,
        policy_id,
        witness_key,
      ) == 1
    },
  )
  expect InlineDatum(datum_data) = board_input.output.datum
  expect datum: AuthorizedBoardDatum = datum_data
  expect datum_is_authentic(witness_key, policy_id, datum)
  expect exact_marker_value(board_input.output.value, policy_id, witness_key)
  True
}

/// An Update spends the current record and creates exactly one successor.
///
/// The successor's nonce is the exact out-ref just spent, so one witness
/// authorization can bless exactly one successor of exactly one predecessor.
/// Custody may move, but only when the recorded owner signs the spend AND the
/// witness's fresh authorization names the new owner: neither alone suffices.
fn validate_update(
  input_output: Output,
  policy_id: PolicyId,
  own_ref: OutputReference,
  old: AuthorizedBoardDatum,
  tx: Transaction,
) -> Bool {
  let Transaction { outputs, mint, extra_signatories, .. } = tx
  expect list.has(extra_signatories, old.owner_key_hash)
  expect dict.to_pairs(tokens(mint, policy_id)) == []
  expect [successor] = board_outputs(policy_id, outputs)
  expect successor.value == input_output.value
  expect InlineDatum(datum_data) = successor.datum
  expect new: AuthorizedBoardDatum = datum_data
  expect new.witness_key == old.witness_key
  expect nonce_names(new.nonce, own_ref)
  datum_is_authentic(old.witness_key, policy_id, new)
}

fn validate_retire(
  input_output: Output,
  policy_id: PolicyId,
  old: AuthorizedBoardDatum,
  refund_address,
  tx: Transaction,
) -> Bool {
  let Transaction { outputs, mint, extra_signatories, .. } = tx
  expect list.has(extra_signatories, old.owner_key_hash)
  expect dict.to_pairs(tokens(mint, policy_id)) == [Pair(old.witness_key, -1)]
  expect
    list.all(
      outputs,
      fn(output) { quantity_of(output.value, policy_id, old.witness_key) == 0 },
    )
  expect [refund] = list.filter(
    outputs,
    fn(output) { output.address == refund_address },
  )
  expect refund.value == from_lovelace(lovelace_of(input_output.value))
  expect NoDatum = refund.datum
  True
}

validator endpoint_board(accepted_predecessor_policy: PolicyId) {
  mint(redeemer: BoardMintRedeemer, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      Post -> validate_post(accepted_predecessor_policy, policy_id, tx)
      Burn -> validate_burn(policy_id, tx)
      MigrateIn { source_ref } ->
        endpoint_board_migration.validate_board_migrate_in(
          accepted_predecessor_policy,
          source_ref,
          policy_id,
          tx,
        )
      LegacyMigrateIn { source_ref, refund_address } ->
        endpoint_board_migration.validate_legacy_board_migrate_in(
          source_ref,
          refund_address,
          policy_id,
          tx,
        )
    }
  }

  spend(
    maybe_datum: Option<AuthorizedBoardDatum>,
    redeemer: BoardAction,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect Some(supplied_datum) = maybe_datum
    let (input_output, policy_id, old) = read_board_input(own_ref, tx)
    expect old == supplied_datum
    when redeemer is {
      Update -> validate_update(input_output, policy_id, own_ref, old, tx)
      Retire { refund_address } ->
        validate_retire(input_output, policy_id, old, refund_address, tx)
      MigrateOut { target } ->
        endpoint_board_migration.validate_board_migrate_out(target, own_ref, tx)
    }
  }

  else(_) {
    fail
  }
}

// S254-2 falsification fixture for the applied-parameter seam. This lives in
// the validator module so the control invokes the real mint entrypoint rather
// than only the migration helper beneath it.
const s254_2_source_policy: PolicyId =
  #"c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"

const s254_2_target_policy: PolicyId =
  #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

const s254_2_foreign_policy: PolicyId =
  #"d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2"

const s254_2_witness_key: ByteArray =
  #"d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729"

const s254_2_endpoint_record: ByteArray =
  #"6c6f632f736368656d652d766563746f722d31"

const s254_2_endpoint_signature: ByteArray =
  #"1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

const s254_2_owner: ByteArray =
  #"11111111111111111111111111111111111111111111111111111111"

const s254_2_refund_owner: ByteArray =
  #"22222222222222222222222222222222222222222222222222222222"

const s254_2_legacy_policy: PolicyId =
  #"54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

const s254_2_source_authorization_signature: ByteArray =
  #"9f6fc1ede2a56451d479fa7939d11a002488ed0796fac74c3ef9151bc373304dc8311bcc6bbc6b4e94a08e81a4a25c47934dd7c7757d3eb8a16793513f508d07"

const s254_2_target_authorization_signature: ByteArray =
  #"6293d5c43801949c41ab88499ab334120b564f0bc087c11d3017d37c3c7aa31d07868fb2bee97371b139c4e8dd0d671d387a1e12aa65b9ef654dd13dba45580d"

const s254_2_source_tx_id: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

fn s254_2_source_ref() -> OutputReference {
  OutputReference { transaction_id: s254_2_source_tx_id, output_index: 0 }
}

fn s254_2_seam_datum(
  nonce_tx_id: ByteArray,
  authorization_signature: ByteArray,
) -> AuthorizedBoardDatum {
  AuthorizedBoardDatum {
    witness_key: s254_2_witness_key,
    endpoint_record: s254_2_endpoint_record,
    endpoint_signature: s254_2_endpoint_signature,
    owner_key_hash: s254_2_owner,
    nonce: BoardNonce { nonce_tx_id, nonce_output_index: 0 },
    authorization_signature,
  }
}

fn s254_2_seam_output(
  policy_id: PolicyId,
  datum: AuthorizedBoardDatum,
) -> Output {
  Output {
    address: from_script(policy_id),
    value: from_lovelace(4_000_000)
      |> merge(from_asset(policy_id, s254_2_witness_key, 1)),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn s254_2_seam_tx() -> Transaction {
  let source = s254_2_seam_datum(
    #"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2",
    s254_2_source_authorization_signature,
  )
  let target = s254_2_seam_datum(
    s254_2_source_tx_id,
    s254_2_target_authorization_signature,
  )
  Transaction {
    ..placeholder,
    inputs: [
      Input {
        output_reference: s254_2_source_ref(),
        output: s254_2_seam_output(s254_2_source_policy, source),
      },
    ],
    outputs: [s254_2_seam_output(s254_2_target_policy, target)],
    mint: from_asset(s254_2_source_policy, s254_2_witness_key, -1)
      |> merge(from_asset(s254_2_target_policy, s254_2_witness_key, 1)),
    extra_signatories: [s254_2_owner],
  }
}

fn s254_2_legacy_datum() -> BoardDatumV1 {
  BoardDatumV1 {
    witness_key: s254_2_witness_key,
    endpoint_record: s254_2_endpoint_record,
    endpoint_signature: s254_2_endpoint_signature,
    owner_key_hash: s254_2_owner,
  }
}

fn s254_2_refund_address() {
  from_verification_key(s254_2_refund_owner)
}

fn s254_2_legacy_tx() -> Transaction {
  let source_redeemer: Data = Retire { refund_address: s254_2_refund_address() }
  Transaction {
    ..placeholder,
    inputs: [
      Input {
        output_reference: s254_2_source_ref(),
        output: Output {
          address: from_script(s254_2_legacy_policy),
          value: from_lovelace(4_000_000)
            |> merge(from_asset(s254_2_legacy_policy, s254_2_witness_key, 1)),
          datum: InlineDatum(s254_2_legacy_datum()),
          reference_script: None,
        },
      },
    ],
    outputs: [
      Output {
        address: s254_2_refund_address(),
        value: from_lovelace(4_000_000),
        datum: NoDatum,
        reference_script: None,
      },
      s254_2_seam_output(
        s254_2_target_policy,
        s254_2_seam_datum(
          s254_2_source_tx_id,
          s254_2_target_authorization_signature,
        ),
      ),
    ],
    mint: from_asset(s254_2_legacy_policy, s254_2_witness_key, -1)
      |> merge(from_asset(s254_2_target_policy, s254_2_witness_key, 1)),
    extra_signatories: [s254_2_owner],
    redeemers: [Pair(Spend(s254_2_source_ref()), source_redeemer)],
  }
}

test board_validator_accepts_applied_predecessor_policy() {
  endpoint_board.mint(
    s254_2_source_policy,
    MigrateIn { source_ref: s254_2_source_ref() },
    s254_2_target_policy,
    s254_2_seam_tx(),
  )
}

test s254_2_board_validator_rejects_foreign_predecessor_policy() fail {
  endpoint_board.mint(
    s254_2_foreign_policy,
    MigrateIn { source_ref: s254_2_source_ref() },
    s254_2_target_policy,
    s254_2_seam_tx(),
  )
}

test s254_2_board_validator_migrate_out_uses_spent_reference() {
  endpoint_board.spend(
    s254_2_foreign_policy,
    Some(
      s254_2_seam_datum(
        #"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2",
        s254_2_source_authorization_signature,
      ),
    ),
    MigrateOut {
      target: MigrationTarget {
        target_policy: s254_2_target_policy,
        target_role: Board,
        target_address: from_script(s254_2_target_policy),
        legacy_refund_address: None,
      },
    },
    s254_2_source_ref(),
    s254_2_seam_tx(),
  )
}

test s254_2_board_validator_legacy_migrate_in_forwards_refund_address() {
  endpoint_board.mint(
    s254_2_source_policy,
    LegacyMigrateIn {
      source_ref: s254_2_source_ref(),
      refund_address: s254_2_refund_address(),
    },
    s254_2_target_policy,
    s254_2_legacy_tx(),
  )
}
