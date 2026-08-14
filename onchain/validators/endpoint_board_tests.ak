//// #253 S253-2 — authorized endpoint-board lifecycle and adversarial tests.
////
//// These tests drive the real combined mint/spend handler with complete
//// transactions, applied with an accepted predecessor policy exactly as the
//// deployed target will be.
////
//// Every signature here is genuine Ed25519 produced by the independent
//// oracle (`evidence/vector-oracle.mjs`, OpenSSL) for the frozen test witness
//// `d9fc…4729` under THIS test policy, THIS record, THIS owner and THIS
//// out-ref. That matters: an attack fixture that merely corrupts bytes proves
//// only that garbage is rejected. These fixtures are all individually valid
//// signatures, so each rejection below is a rejection of a *binding*, not of
//// a malformed byte string.

use aiken/crypto.{VerificationKeyHash}
use cage_context.{ada_output, input_at, out_ref, seed_tx_id}
use cardano/address.{Address, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/endpoint_board_authorization.{AuthorizedBoardDatum, BoardNonce}
use cardano_keri/endpoint_board_types.{BoardDatumV1, Burn, Post, Retire, Update}
use endpoint_board

/// The applied target policy under which every signature below was produced.
const policy: PolicyId =
  #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

/// The predecessor policy this target release is applied with. A marker under
/// it may be migrated (S253-3), never consumed as an ordinary Post nonce.
const predecessor_policy: PolicyId =
  #"c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1"

const witness_key: ByteArray =
  #"d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729"

const endpoint_record: ByteArray = #"6c6f632f736368656d652d766563746f722d31"

const endpoint_signature: ByteArray =
  #"1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

const owner: VerificationKeyHash =
  #"11111111111111111111111111111111111111111111111111111111"

const new_owner: VerificationKeyHash =
  #"22222222222222222222222222222222222222222222222222222222"

const wrong_key: ByteArray =
  #"4040404040404040404040404040404040404040404040404040404040404040"

/// The ordinary funding output a Post names and consumes as its one-use nonce.
const post_nonce_tx_id: ByteArray =
  #"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2"

/// A different ordinary output, used to prove a Post cannot be satisfied by
/// consuming *some* input instead of *its* input.
const other_nonce_tx_id: ByteArray =
  #"a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3"

/// Witness authorization for the posted record: owner `owner`, nonce = the
/// consumed funding output above.
const post_authorization_signature: ByteArray =
  #"ce03b7d75283f61b34bbf84403a99cc35c168769639143cbd89c31d21755cf5ea52ea23890e011b30783312f96041729f1996f1fbe9caa040d91f5316259f608"

/// Witness authorization for its successor: same owner, nonce = the exact
/// spent board out-ref.
const successor_authorization_signature: ByteArray =
  #"6293d5c43801949c41ab88499ab334120b564f0bc087c11d3017d37c3c7aa31d07868fb2bee97371b139c4e8dd0d671d387a1e12aa65b9ef654dd13dba45580d"

/// Witness authorization for an authorized custody transfer: the witness
/// names `new_owner`, nonce = the exact spent board out-ref.
const transfer_authorization_signature: ByteArray =
  #"78cb03db990d6caae9f7ff4bb37c0b836d20d666dfa94719703a2656699f27ef7351106cb455562577bcf1873b2dcbb36fc46d98bcb7b89a0a6e7eb376af7404"

const deposit: Int = 3_000_000

// ---------------------------------------------------------------- fixtures

fn nonce_at(tx_id: ByteArray, index: Int) -> BoardNonce {
  BoardNonce { nonce_tx_id: tx_id, nonce_output_index: index }
}

fn authorized(
  owner_key_hash: ByteArray,
  nonce: BoardNonce,
  signature: ByteArray,
) -> AuthorizedBoardDatum {
  AuthorizedBoardDatum {
    witness_key,
    endpoint_record,
    endpoint_signature,
    owner_key_hash,
    nonce,
    authorization_signature: signature,
  }
}

/// The record a Post creates, and the record an Update or Retire spends.
fn posted_datum() -> AuthorizedBoardDatum {
  authorized(owner, nonce_at(post_nonce_tx_id, 0), post_authorization_signature)
}

/// Its successor: same owner, nonce = the spent board out-ref.
fn successor_datum() -> AuthorizedBoardDatum {
  authorized(owner, nonce_at(seed_tx_id, 0), successor_authorization_signature)
}

/// An authorized custody transfer to `new_owner`.
fn transfer_datum() -> AuthorizedBoardDatum {
  authorized(
    new_owner,
    nonce_at(seed_tx_id, 0),
    transfer_authorization_signature,
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

fn marker_value(name: ByteArray, quantity: Int, lovelace: Int) -> Value {
  from_lovelace(lovelace) |> merge(from_asset(policy, name, quantity))
}

fn board_output_at(
  address: Address,
  name: ByteArray,
  quantity: Int,
  lovelace: Int,
  board_datum: AuthorizedBoardDatum,
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
  board_datum: AuthorizedBoardDatum,
) -> Output {
  board_output_at(from_script(policy), name, quantity, lovelace, board_datum)
}

/// A board output carrying the frozen four-field legacy datum. The target
/// policy must refuse to decode it at all.
fn legacy_board_output() -> Output {
  Output {
    address: from_script(policy),
    value: marker_value(witness_key, 1, deposit),
    datum: InlineDatum(legacy_datum()),
    reference_script: None,
  }
}

fn own_ref() -> OutputReference {
  out_ref(seed_tx_id, 0)
}

fn board_input() -> Input {
  input_at(own_ref(), board_output(witness_key, 1, deposit, posted_datum()))
}

fn funding_address() -> Address {
  from_verification_key(owner)
}

/// The ordinary output a Post consumes: ada only, no marker of any board
/// policy.
fn nonce_input() -> Input {
  input_at(
    out_ref(post_nonce_tx_id, 0),
    ada_output(funding_address(), 10_000_000),
  )
}

/// The same output reference, but carrying a marker under the given policy.
fn marked_nonce_input(marker_policy: PolicyId) -> Input {
  input_at(
    out_ref(post_nonce_tx_id, 0),
    Output {
      address: from_script(marker_policy),
      value: from_lovelace(deposit)
        |> merge(from_asset(marker_policy, witness_key, 1)),
      datum: InlineDatum(posted_datum()),
      reference_script: None,
    },
  )
}

fn tx(
  inputs: List<Input>,
  outputs: List<Output>,
  mint: Value,
  extra_signatories: List<VerificationKeyHash>,
) -> Transaction {
  Transaction { ..placeholder, inputs, outputs, mint, extra_signatories }
}

fn post_tx(inputs: List<Input>, output: Output, minted: Value) -> Transaction {
  tx(inputs, [output], minted, [])
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
    [nonce_input()],
    board_output(witness_key, 1, deposit, posted_datum()),
    from_asset(policy, witness_key, 1),
  )
}

fn honest_update_tx() -> Transaction {
  update_tx(
    board_output(witness_key, 1, deposit, successor_datum()),
    zero,
    [owner],
  )
}

fn refund_address() -> Address {
  from_verification_key(new_owner)
}

fn honest_retire_tx() -> Transaction {
  retire_tx(
    refund_address(),
    deposit,
    from_asset(policy, witness_key, -1),
    [owner],
  )
}

fn mint_post(tx_value: Transaction) -> Bool {
  endpoint_board.endpoint_board.mint(predecessor_policy, Post, policy, tx_value)
}

fn spend_update(datum: AuthorizedBoardDatum, tx_value: Transaction) -> Bool {
  endpoint_board.endpoint_board.spend(
    predecessor_policy,
    Some(datum),
    Update,
    own_ref(),
    tx_value,
  )
}

fn spend_retire(tx_value: Transaction) -> Bool {
  endpoint_board.endpoint_board.spend(
    predecessor_policy,
    Some(posted_datum()),
    Retire { refund_address: refund_address() },
    own_ref(),
    tx_value,
  )
}

// ---------------------------------------------------------------------
// Post: both signatures, exact marker, and one exact consumed nonce.
// ---------------------------------------------------------------------

test endpoint_board_s253_post_accepts_exact_consumed_nonce() {
  mint_post(honest_post_tx())
}

/// INV-253-NONCE. The authorization is genuine and the marker is exact; the
/// only defect is that the named nonce output is not consumed. This is also
/// the resurrection control: once the nonce output has been spent it can
/// never appear among a later transaction's inputs, so the same signed Post
/// cannot create a second live record or revive a retired one.
test endpoint_board_s253_post_rejects_missing_nonce_input() fail {
  mint_post(
    post_tx(
      [],
      board_output(witness_key, 1, deposit, posted_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// A different input is consumed instead of the authorized one.
test endpoint_board_s253_post_rejects_a_different_consumed_input() fail {
  mint_post(
    post_tx(
      [
        input_at(
          out_ref(other_nonce_tx_id, 0),
          ada_output(funding_address(), 10_000_000),
        ),
      ],
      board_output(witness_key, 1, deposit, posted_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// The authorized out-ref exists but at a different output index.
test endpoint_board_s253_post_rejects_a_shifted_nonce_index() fail {
  mint_post(
    post_tx(
      [
        input_at(
          out_ref(post_nonce_tx_id, 1),
          ada_output(funding_address(), 10_000_000),
        ),
      ],
      board_output(witness_key, 1, deposit, posted_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// A board marker of the applied predecessor release is not an ordinary
/// output: consuming one is a migration, which S253-3 owns, and it must never
/// be laundered into an ordinary Post.
test endpoint_board_s253_post_rejects_predecessor_marker_as_nonce() fail {
  mint_post(
    post_tx(
      [marked_nonce_input(predecessor_policy)],
      board_output(witness_key, 1, deposit, posted_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// Nor may one lineage of this same release be cannibalised as another's
/// nonce.
test endpoint_board_s253_post_rejects_target_marker_as_nonce() fail {
  mint_post(
    post_tx(
      [marked_nonce_input(policy)],
      board_output(witness_key, 1, deposit, posted_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// INV-253-WITNESS-AUTH. The endpoint signature is genuine and the
/// authorization signature is a genuine 64-byte Ed25519 signature by the same
/// witness — over the successor's binding, not this one.
test endpoint_board_s253_post_rejects_endpoint_only_authority() fail {
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(
        witness_key,
        1,
        deposit,
        authorized(
          owner,
          nonce_at(post_nonce_tx_id, 0),
          successor_authorization_signature,
        ),
      ),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// INV-253-OWNER. A genuine authorization for `owner` copied into a datum
/// naming the attacker.
test endpoint_board_s253_post_rejects_owner_substitution() fail {
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(
        witness_key,
        1,
        deposit,
        authorized(
          new_owner,
          nonce_at(post_nonce_tx_id, 0),
          post_authorization_signature,
        ),
      ),
      from_asset(policy, witness_key, 1),
    ),
  )
}

/// The frozen four-field legacy shape must not decode at the target policy.
test endpoint_board_s253_post_rejects_the_legacy_four_field_datum() fail {
  mint_post(
    post_tx(
      [nonce_input()],
      legacy_board_output(),
      from_asset(policy, witness_key, 1),
    ),
  )
}

test endpoint_board_s253_post_rejects_short_asset_name() fail {
  let short_key = #"3d4017"
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(short_key, 1, deposit, posted_datum()),
      from_asset(policy, short_key, 1),
    ),
  )
}

test endpoint_board_s253_post_rejects_quantity_two() fail {
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(witness_key, 2, deposit, posted_datum()),
      from_asset(policy, witness_key, 2),
    ),
  )
}

test endpoint_board_s253_post_rejects_extra_policy_entry() fail {
  let minted = from_asset(policy, witness_key, 1)
    |> merge(from_asset(policy, wrong_key, 1))
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(witness_key, 1, deposit, posted_datum()),
      minted,
    ),
  )
}

test endpoint_board_s253_post_rejects_wrong_address() fail {
  mint_post(
    post_tx(
      [nonce_input()],
      board_output_at(refund_address(), witness_key, 1, deposit, posted_datum()),
      from_asset(policy, witness_key, 1),
    ),
  )
}

test endpoint_board_s253_post_rejects_asset_key_mismatch() fail {
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(wrong_key, 1, deposit, posted_datum()),
      from_asset(policy, wrong_key, 1),
    ),
  )
}

/// The endpoint bytes are altered; the endpoint signature no longer covers
/// them, and neither does the authorization.
test endpoint_board_s253_post_rejects_a_forged_endpoint_record() fail {
  let forged = AuthorizedBoardDatum { ..posted_datum(), endpoint_record: #"73" }
  mint_post(
    post_tx(
      [nonce_input()],
      board_output(witness_key, 1, deposit, forged),
      from_asset(policy, witness_key, 1),
    ),
  )
}

test endpoint_board_s253_post_rejects_duplicate_marker_outputs() fail {
  let output = board_output(witness_key, 1, deposit, posted_datum())
  mint_post(
    tx(
      [nonce_input()],
      [output, output],
      from_asset(policy, witness_key, 1),
      [],
    ),
  )
}

// ---------------------------------------------------------------------
// Update: recorded owner, exact predecessor nonce, one confined successor.
// ---------------------------------------------------------------------

test endpoint_board_s253_update_accepts_exact_predecessor_nonce() {
  spend_update(posted_datum(), honest_update_tx())
}

/// INV-253-NONCE. The successor carries the predecessor's own nonce instead
/// of the out-ref actually being spent, so one authorization could otherwise
/// bless an unbounded chain.
test endpoint_board_s253_update_rejects_wrong_predecessor_nonce() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(witness_key, 1, deposit, posted_datum()),
      zero,
      [owner],
    ),
  )
}

/// INV-253-OWNER. The genuine successor authorization for `owner` is copied
/// into a successor datum naming the attacker.
test endpoint_board_s253_update_rejects_owner_substitution() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(
        witness_key,
        1,
        deposit,
        authorized(
          new_owner,
          nonce_at(seed_tx_id, 0),
          successor_authorization_signature,
        ),
      ),
      zero,
      [owner],
    ),
  )
}

test endpoint_board_s253_update_rejects_multiple_successors() fail {
  let output = board_output(witness_key, 1, deposit, successor_datum())
  spend_update(
    posted_datum(),
    tx([board_input()], [output, output], zero, [owner]),
  )
}

/// Custody may move, but only when BOTH authorities agree: the recorded owner
/// signs the spend and the witness's fresh authorization names the new owner.
test endpoint_board_s253_update_accepts_authorized_custody_transfer() {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(witness_key, 1, deposit, transfer_datum()),
      zero,
      [owner],
    ),
  )
}

/// Witness approval of the new owner is not enough on its own.
test endpoint_board_s253_update_rejects_custody_transfer_without_the_old_owner() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(witness_key, 1, deposit, transfer_datum()),
      zero,
      [new_owner],
    ),
  )
}

test endpoint_board_s253_update_rejects_missing_owner() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(witness_key, 1, deposit, successor_datum()),
      zero,
      [],
    ),
  )
}

test endpoint_board_s253_update_rejects_changed_marker_key() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(wrong_key, 1, deposit, successor_datum()),
      zero,
      [owner],
    ),
  )
}

test endpoint_board_s253_update_rejects_changed_deposit() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(witness_key, 1, deposit - 1, successor_datum()),
      zero,
      [owner],
    ),
  )
}

test endpoint_board_s253_update_rejects_marker_mint() fail {
  spend_update(
    posted_datum(),
    update_tx(
      board_output(witness_key, 1, deposit, successor_datum()),
      from_asset(policy, witness_key, 1),
      [owner],
    ),
  )
}

/// The successor's endpoint bytes are altered while both signatures are kept.
test endpoint_board_s253_update_rejects_a_forged_replacement() fail {
  let forged = AuthorizedBoardDatum {
    ..successor_datum(),
    endpoint_record: #"73",
  }
  spend_update(
    posted_datum(),
    update_tx(board_output(witness_key, 1, deposit, forged), zero, [owner]),
  )
}

// ---------------------------------------------------------------------
// Retire: recorded owner, coupled exact burn, complete token-free refund.
// ---------------------------------------------------------------------

test endpoint_board_s253_retire_preserves_owner_burn_and_refund() {
  endpoint_board.endpoint_board.mint(
    predecessor_policy,
    Burn,
    policy,
    honest_retire_tx(),
  ) && spend_retire(honest_retire_tx())
}

test endpoint_board_s253_retire_rejects_missing_owner() fail {
  spend_retire(
    retire_tx(
      refund_address(),
      deposit,
      from_asset(policy, witness_key, -1),
      [],
    ),
  )
}

test endpoint_board_s253_retire_rejects_wrong_burn_quantity() fail {
  endpoint_board.endpoint_board.mint(
    predecessor_policy,
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

test endpoint_board_s253_retire_rejects_short_refund() fail {
  spend_retire(
    retire_tx(
      refund_address(),
      deposit - 1,
      from_asset(policy, witness_key, -1),
      [owner],
    ),
  )
}

test endpoint_board_s253_retire_rejects_wrong_refund_target() fail {
  spend_retire(
    retire_tx(
      from_verification_key(owner),
      deposit,
      from_asset(policy, witness_key, -1),
      [owner],
    ),
  )
}

test endpoint_board_s253_burn_rejects_a_transaction_without_a_board_input() fail {
  endpoint_board.endpoint_board.mint(
    predecessor_policy,
    Burn,
    policy,
    tx([], [], from_asset(policy, witness_key, -1), [owner]),
  )
}
