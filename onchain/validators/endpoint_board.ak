//// M1 endpoint-board combined minting and spending validator (#165).
////
//// Each current record is one enterprise-script UTxO containing one marker
//// whose asset name is the raw 32-byte witness key. The exact endpoint bytes
//// are authenticated by the witness at post/update. A recorded Cardano
//// payment key controls update/retire and the complete lovelace deposit is
//// preserved or refunded.

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
use cardano_keri/endpoint_board_types.{
  BoardAction, BoardDatumV1, BoardMintRedeemer, Burn, Post, Retire, Update,
}

/// Validate all byte-level invariants in the frozen datum.
pub fn datum_is_authentic(expected_key: ByteArray, datum: BoardDatumV1) -> Bool {
  bytearray.length(expected_key) == 32 && datum.witness_key == expected_key && bytearray.length(
    datum.endpoint_record,
  ) > 0 && bytearray.length(datum.endpoint_signature) == 64 && bytearray.length(
    datum.owner_key_hash,
  ) == 28 && verify_ed25519_signature(
    datum.witness_key,
    datum.endpoint_record,
    datum.endpoint_signature,
  )
}

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

fn read_board_input(
  own_ref: OutputReference,
  tx: Transaction,
) -> (Output, PolicyId, BoardDatumV1) {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect Script(policy_id) = own_input.output.address.payment_credential
  expect own_input.output.address == from_script(policy_id)
  expect InlineDatum(datum_data) = own_input.output.datum
  expect datum: BoardDatumV1 = datum_data
  expect datum_is_authentic(datum.witness_key, datum)
  expect
    exact_marker_value(own_input.output.value, policy_id, datum.witness_key)
  (own_input.output, policy_id, datum)
}

fn validate_post(policy_id: PolicyId, tx: Transaction) -> Bool {
  let Transaction { outputs, mint, .. } = tx
  expect [Pair(witness_key, quantity)] = dict.to_pairs(tokens(mint, policy_id))
  expect bytearray.length(witness_key) == 32
  expect quantity == 1
  expect [record_output] = list.filter(
    outputs,
    fn(output) { output.address == from_script(policy_id) },
  )
  expect InlineDatum(datum_data) = record_output.datum
  expect datum: BoardDatumV1 = datum_data
  expect datum_is_authentic(witness_key, datum)
  expect exact_marker_value(record_output.value, policy_id, witness_key)
  True
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
  expect datum: BoardDatumV1 = datum_data
  expect datum_is_authentic(witness_key, datum)
  expect exact_marker_value(board_input.output.value, policy_id, witness_key)
  True
}

fn validate_update(
  input_output: Output,
  policy_id: PolicyId,
  old: BoardDatumV1,
  tx: Transaction,
) -> Bool {
  let Transaction { outputs, mint, extra_signatories, .. } = tx
  expect list.has(extra_signatories, old.owner_key_hash)
  expect dict.to_pairs(tokens(mint, policy_id)) == []
  expect [successor] = list.filter(
    outputs,
    fn(output) { output.address == from_script(policy_id) },
  )
  expect successor.value == input_output.value
  expect InlineDatum(datum_data) = successor.datum
  expect new: BoardDatumV1 = datum_data
  expect new.witness_key == old.witness_key
  expect datum_is_authentic(old.witness_key, new)
  True
}

fn validate_retire(
  input_output: Output,
  policy_id: PolicyId,
  old: BoardDatumV1,
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

validator endpoint_board {
  mint(redeemer: BoardMintRedeemer, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      Post -> validate_post(policy_id, tx)
      Burn -> validate_burn(policy_id, tx)
    }
  }

  spend(
    maybe_datum: Option<BoardDatumV1>,
    redeemer: BoardAction,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect Some(supplied_datum) = maybe_datum
    let (input_output, policy_id, old) = read_board_input(own_ref, tx)
    expect old == supplied_datum
    when redeemer is {
      Update -> validate_update(input_output, policy_id, old, tx)
      Retire { refund_address } ->
        validate_retire(input_output, policy_id, old, refund_address, tx)
    }
  }

  else(_) {
    fail
  }
}
