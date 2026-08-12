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
use cardano/address.{Script, from_script}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, lovelace_of, merge, quantity_of, tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/endpoint_board_authorization.{
  AuthorizedBoardDatum, datum_is_authentic, nonce_names, nonce_reference,
}
use cardano_keri/endpoint_board_types.{
  BoardAction, BoardMintRedeemer, Burn, Post, Retire, Update,
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
    }
  }

  else(_) {
    fail
  }
}
