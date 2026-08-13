//// Endpoint-board family migration enforcement (#254, MOD-254-BOARD-FAMILY).
////
//// #253 continues to own the authorized target datum and authentication
//// predicate. This module composes that predicate unchanged and owns only the
//// atomic predecessor-spend, token replacement, continuity, and v0 bridge.

use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use aiken/primitive/bytearray
use cardano/address.{Script, from_script}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/endpoint_board_authorization.{
  AuthorizedBoardDatum, datum_is_authentic, nonce_names,
}
use cardano_keri/endpoint_board_types.{BoardDatumV1}
use cardano_keri/migration/types.{Board, MigrationTarget}

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
  target: MigrationTarget,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let (source_output, source_policy, source) = read_authorized_source(
    own_ref,
    tx,
  )
  expect target.target_role == Board
  expect target.target_address == from_script(target.target_policy)
  expect target.legacy_refund_address == None
  permanent_transition(
    source_output,
    source_policy,
    own_ref,
    source,
    target.target_policy,
    None,
    tx,
  )
}

/// Enter from the one predecessor policy compiled into this target.
pub fn validate_board_migrate_in(
  accepted_predecessor_policy: PolicyId,
  source_ref: OutputReference,
  target_record: AuthorizedBoardDatum,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let (source_output, source_policy, source) = read_authorized_source(
    source_ref,
    tx,
  )
  expect source_policy == accepted_predecessor_policy
  permanent_transition(
    source_output,
    source_policy,
    source_ref,
    source,
    policy_id,
    Some(target_record),
    tx,
  )
}

/// Enter from the frozen deployed v0 board through Retire/Burn.
pub fn validate_legacy_board_migrate_in(
  preprod_v0: LegacyBoardIdentity,
  source_ref: OutputReference,
  target_record: AuthorizedBoardDatum,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  expect preprod_v0 == preprod_v0_identity()
  expect Some(source_input) = find_input(tx.inputs, source_ref)
  expect source_input.output.address == from_script(preprod_v0.legacy_policy)
  expect InlineDatum(source_data) = source_input.output.datum
  expect source: BoardDatumV1 = source_data
  expect legacy_datum_is_authentic(source)
  expect
    exact_marker_value(
      source_input.output,
      preprod_v0.legacy_policy,
      source.witness_key,
    )
  expect list.has(tx.extra_signatories, source.owner_key_hash)
  expect policy_id != preprod_v0.legacy_policy
  expect
    exact_token_replacement(
      preprod_v0.legacy_policy,
      policy_id,
      source.witness_key,
      tx,
    )
  expect Some(successor) = sole_successor(policy_id, source.witness_key, tx)
  expect successor.address == from_script(policy_id)
  expect InlineDatum(successor_data) = successor.datum
  expect observed: AuthorizedBoardDatum = successor_data
  expect observed == target_record
  expect
    board_continuity(
      source.witness_key,
      source.endpoint_record,
      source.endpoint_signature,
      source.owner_key_hash,
      lovelace_of(source_input.output.value),
      source_ref,
      policy_id,
      target_record,
      successor,
    )
  // The v0 Retire/Burn scripts execute in this same transaction. Mirror their
  // observable effect here: no source marker survives and exactly one
  // datum-free output refunds the complete source deposit. The successor is
  // independently capitalized with the same protected lovelace.
  expect
    list.all(
      tx.outputs,
      fn(output) {
        quantity_of(output.value, preprod_v0.legacy_policy, source.witness_key) == 0
      },
    )
  let deposit = lovelace_of(source_input.output.value)
  expect [_refund] = list.filter(
    tx.outputs,
    fn(output) { is_exact_refund(output, deposit) },
  )
  True
}

fn read_authorized_source(
  source_ref: OutputReference,
  tx: Transaction,
) -> (Output, PolicyId, AuthorizedBoardDatum) {
  expect Some(source_input) = find_input(tx.inputs, source_ref)
  expect Script(source_policy) = source_input.output.address.payment_credential
  expect source_input.output.address == from_script(source_policy)
  expect InlineDatum(source_data) = source_input.output.datum
  expect source: AuthorizedBoardDatum = source_data
  expect datum_is_authentic(source.witness_key, source_policy, source)
  expect
    exact_marker_value(source_input.output, source_policy, source.witness_key)
  (source_input.output, source_policy, source)
}

fn permanent_transition(
  source_output: Output,
  source_policy: PolicyId,
  source_ref: OutputReference,
  source: AuthorizedBoardDatum,
  target_policy: PolicyId,
  supplied_target: Option<AuthorizedBoardDatum>,
  tx: Transaction,
) -> Bool {
  expect source_policy != target_policy
  expect list.has(tx.extra_signatories, source.owner_key_hash)
  expect
    exact_token_replacement(
      source_policy,
      target_policy,
      source.witness_key,
      tx,
    )
  expect Some(successor) = sole_successor(target_policy, source.witness_key, tx)
  expect successor.address == from_script(target_policy)
  expect InlineDatum(successor_data) = successor.datum
  expect target: AuthorizedBoardDatum = successor_data
  expect
    when supplied_target is {
      Some(expected) -> target == expected
      None -> True
    }
  board_continuity(
    source.witness_key,
    source.endpoint_record,
    source.endpoint_signature,
    source.owner_key_hash,
    lovelace_of(source_output.value),
    source_ref,
    target_policy,
    target,
    successor,
  )
}

fn board_continuity(
  witness_key: ByteArray,
  endpoint_record: ByteArray,
  endpoint_signature: ByteArray,
  owner_key_hash: ByteArray,
  deposit: Int,
  source_ref: OutputReference,
  target_policy: PolicyId,
  target: AuthorizedBoardDatum,
  successor: Output,
) -> Bool {
  and {
    target.witness_key == witness_key,
    target.endpoint_record == endpoint_record,
    target.endpoint_signature == endpoint_signature,
    target.owner_key_hash == owner_key_hash,
    nonce_names(target.nonce, source_ref),
    datum_is_authentic(witness_key, target_policy, target),
    exact_marker_value(successor, target_policy, witness_key),
    lovelace_of(successor.value) == deposit,
  }
}

fn exact_marker_value(
  output: Output,
  policy_id: PolicyId,
  witness_key: ByteArray,
) -> Bool {
  let deposit = lovelace_of(output.value)
  deposit > 0 && output.value == (
    from_lovelace(deposit) |> merge(from_asset(policy_id, witness_key, 1))
  )
}

fn exact_token_replacement(
  source_policy: PolicyId,
  target_policy: PolicyId,
  witness_key: ByteArray,
  tx: Transaction,
) -> Bool {
  and {
    dict.to_pairs(tokens(tx.mint, source_policy)) == [Pair(witness_key, -1)],
    dict.to_pairs(tokens(tx.mint, target_policy)) == [Pair(witness_key, 1)],
  }
}

fn sole_successor(
  policy_id: PolicyId,
  witness_key: ByteArray,
  tx: Transaction,
) -> Option<Output> {
  when
    list.filter(
      tx.outputs,
      fn(output) { quantity_of(output.value, policy_id, witness_key) == 1 },
    )
  is {
    [output] -> Some(output)
    _ -> None
  }
}

fn legacy_datum_is_authentic(datum: BoardDatumV1) -> Bool {
  and {
    bytearray.length(datum.witness_key) == 32,
    bytearray.length(datum.endpoint_record) > 0,
    bytearray.length(datum.endpoint_signature) == 64,
    bytearray.length(datum.owner_key_hash) == 28,
    verify_ed25519_signature(
      datum.witness_key,
      datum.endpoint_record,
      datum.endpoint_signature,
    ),
  }
}

fn is_exact_refund(output: Output, deposit: Int) -> Bool {
  when output.datum is {
    NoDatum -> output.value == from_lovelace(deposit)
    _ -> False
  }
}
