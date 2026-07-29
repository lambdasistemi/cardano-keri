//// #165 S1 — endpoint-board validator lifecycle and adversarial tests.
////
//// These tests drive the real combined mint/spend handler with complete
//// transactions. The genuine Ed25519 fixture is RFC 8032 test vector 2:
//// public key `3d40…660c`, message `0x72`, signature `92a0…0c00`.

use aiken/crypto.{VerificationKeyHash}
use cage_context.{ada_output, input_at, out_ref, seed_tx_id}
use cardano/address.{Address, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/endpoint_board_types.{BoardDatumV1, Burn, Post, Retire, Update}
use endpoint_board

const policy: PolicyId =
  #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

const witness_key: ByteArray =
  #"3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

const witness_signature: ByteArray =
  #"92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"

const endpoint_record: ByteArray = #"72"

const owner: VerificationKeyHash =
  #"11111111111111111111111111111111111111111111111111111111"

const non_owner: VerificationKeyHash =
  #"22222222222222222222222222222222222222222222222222222222"

const wrong_key: ByteArray =
  #"4040404040404040404040404040404040404040404040404040404040404040"

const deposit: Int = 3_000_000

fn datum(
  key: ByteArray,
  record: ByteArray,
  signature: ByteArray,
  owner_key_hash: ByteArray,
) -> BoardDatumV1 {
  BoardDatumV1 {
    witness_key: key,
    endpoint_record: record,
    endpoint_signature: signature,
    owner_key_hash,
  }
}

fn honest_datum() -> BoardDatumV1 {
  datum(witness_key, endpoint_record, witness_signature, owner)
}

fn marker_value(name: ByteArray, quantity: Int, lovelace: Int) -> Value {
  from_lovelace(lovelace) |> merge(from_asset(policy, name, quantity))
}

fn board_output_at(
  address: Address,
  name: ByteArray,
  quantity: Int,
  lovelace: Int,
  board_datum: BoardDatumV1,
) -> Output {
  Output {
    address,
    value: marker_value(name, quantity, lovelace),
    datum: InlineDatum(board_datum),
    reference_script: None,
  }
}

fn board_output(
  name: ByteArray,
  quantity: Int,
  lovelace: Int,
  board_datum: BoardDatumV1,
) -> Output {
  board_output_at(from_script(policy), name, quantity, lovelace, board_datum)
}

fn own_ref() -> OutputReference {
  out_ref(seed_tx_id, 0)
}

fn board_input() {
  input_at(own_ref(), board_output(witness_key, 1, deposit, honest_datum()))
}

fn tx(
  inputs,
  outputs,
  mint,
  extra_signatories: List<VerificationKeyHash>,
) -> Transaction {
  Transaction { ..placeholder, inputs, outputs, mint, extra_signatories }
}

fn post_tx(output: Output, minted: Value) -> Transaction {
  tx([], [output], minted, [])
}

fn update_tx(output: Output, minted: Value, signatories) -> Transaction {
  tx([board_input()], [output], minted, signatories)
}

fn retire_tx(
  refund_address: Address,
  refund: Int,
  minted: Value,
  signatories,
) -> Transaction {
  tx([board_input()], [ada_output(refund_address, refund)], minted, signatories)
}

fn honest_post_tx() -> Transaction {
  post_tx(
    board_output(witness_key, 1, deposit, honest_datum()),
    from_asset(policy, witness_key, 1),
  )
}

fn honest_update_tx() -> Transaction {
  update_tx(
    board_output(witness_key, 1, deposit, honest_datum()),
    zero,
    [owner],
  )
}

fn refund_address() -> Address {
  from_verification_key(non_owner)
}

fn honest_retire_tx() -> Transaction {
  retire_tx(
    refund_address(),
    deposit,
    from_asset(policy, witness_key, -1),
    [owner],
  )
}

// ---------------------------------------------------------------------
// Post: authentic singleton mint at the marker address.
// ---------------------------------------------------------------------

test accept_authentic_post() {
  endpoint_board.endpoint_board.mint(Post, policy, honest_post_tx())
}

test reject_short_asset_name() fail {
  let short_key = #"3d4017"
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(
      board_output(short_key, 1, deposit, honest_datum()),
      from_asset(policy, short_key, 1),
    ),
  )
}

test reject_post_quantity_two() fail {
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(
      board_output(witness_key, 2, deposit, honest_datum()),
      from_asset(policy, witness_key, 2),
    ),
  )
}

test reject_post_extra_policy_entry() fail {
  let minted = from_asset(policy, witness_key, 1)
    |> merge(from_asset(policy, wrong_key, 1))
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(board_output(witness_key, 1, deposit, honest_datum()), minted),
  )
}

test reject_post_wrong_address() fail {
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(
      board_output_at(refund_address(), witness_key, 1, deposit, honest_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

test reject_post_asset_key_mismatch() fail {
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(
      board_output(wrong_key, 1, deposit, honest_datum()),
      from_asset(policy, wrong_key, 1),
    ),
  )
}

test reject_post_forged_signature() fail {
  let forged = datum(witness_key, #"73", witness_signature, owner)
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(
      board_output(witness_key, 1, deposit, forged),
      from_asset(policy, witness_key, 1),
    ),
  )
}

test reject_post_bad_owner_width() fail {
  let bad_owner = datum(witness_key, endpoint_record, witness_signature, #"11")
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    post_tx(
      board_output(witness_key, 1, deposit, bad_owner),
      from_asset(policy, witness_key, 1),
    ),
  )
}

test reject_post_duplicate_marker_outputs() fail {
  let output = board_output(witness_key, 1, deposit, honest_datum())
  endpoint_board.endpoint_board.mint(
    Post,
    policy,
    tx([], [output, output], from_asset(policy, witness_key, 1), []),
  )
}

// ---------------------------------------------------------------------
// Update: owner-authorized spend/recreate, same marker and deposit.
// ---------------------------------------------------------------------

test accept_owner_update() {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    honest_update_tx(),
  )
}

test reject_update_missing_owner() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    update_tx(board_output(witness_key, 1, deposit, honest_datum()), zero, []),
  )
}

test reject_update_changed_marker_key() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    update_tx(
      board_output(wrong_key, 1, deposit, honest_datum()),
      zero,
      [owner],
    ),
  )
}

test reject_update_changed_deposit() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    update_tx(
      board_output(witness_key, 1, deposit - 1, honest_datum()),
      zero,
      [owner],
    ),
  )
}

test reject_update_marker_mint() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    update_tx(
      board_output(witness_key, 1, deposit, honest_datum()),
      from_asset(policy, witness_key, 1),
      [owner],
    ),
  )
}

test reject_update_forged_replacement() fail {
  let forged = datum(witness_key, #"73", witness_signature, owner)
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    update_tx(board_output(witness_key, 1, deposit, forged), zero, [owner]),
  )
}

test reject_update_duplicate_continuing_outputs() fail {
  let output = board_output(witness_key, 1, deposit, honest_datum())
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Update,
    own_ref(),
    tx([board_input()], [output, output], zero, [owner]),
  )
}

// ---------------------------------------------------------------------
// Retire: coupled exact burn and complete token-free refund.
// ---------------------------------------------------------------------

test accept_owner_retire() {
  endpoint_board.endpoint_board.mint(Burn, policy, honest_retire_tx()) && endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Retire { refund_address: refund_address() },
    own_ref(),
    honest_retire_tx(),
  )
}

test reject_retire_missing_owner() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Retire { refund_address: refund_address() },
    own_ref(),
    retire_tx(
      refund_address(),
      deposit,
      from_asset(policy, witness_key, -1),
      [],
    ),
  )
}

test reject_retire_wrong_burn_quantity() fail {
  endpoint_board.endpoint_board.mint(
    Burn,
    policy,
    retire_tx(
      refund_address(),
      deposit,
      from_asset(policy, witness_key, -2),
      [owner],
    ),
  )
}

test reject_retire_short_refund() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Retire { refund_address: refund_address() },
    own_ref(),
    retire_tx(
      refund_address(),
      deposit - 1,
      from_asset(policy, witness_key, -1),
      [owner],
    ),
  )
}

test reject_retire_wrong_refund_target() fail {
  endpoint_board.endpoint_board.spend(
    Some(honest_datum()),
    Retire { refund_address: refund_address() },
    own_ref(),
    retire_tx(
      from_verification_key(owner),
      deposit,
      from_asset(policy, witness_key, -1),
      [owner],
    ),
  )
}

test reject_burn_without_board_input() fail {
  endpoint_board.endpoint_board.mint(
    Burn,
    policy,
    tx([], [], from_asset(policy, witness_key, -1), [owner]),
  )
}
