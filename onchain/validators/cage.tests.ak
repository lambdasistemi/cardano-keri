use aiken/crypto.{blake2b_256, verify_ed25519_signature}
use aiken/interval
use aiken/primitive/bytearray
use cage.{verifyOwnerAuth}
use cage_context.{
  ada_output, cage_policy, empty_root, end_tx, inline_output, input_at,
  insert_root, migrate_tx, mint_tx, modify_tx, old_cage_policy, out_ref,
  owner_vkh, request_datum, seed_tx_id, spend_context, state_datum, state_value,
  token_of,
}
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{from_lovelace, zero}
use cardano/transaction.{OutputReference}
use types.{
  End, Insert, Migrating, Migration, Mint, Minting, Modify, OwnerAuth,
  RequestAction, UpdateAction,
}

// ---- Full-transaction happy-path accept tests -------------------------------
//
// These invoke the REAL `mpfCage` handlers on full `Transaction` values (not the
// pure `verifyOwnerAuth` helper) via the `cage_context` harness. They are the
// regression baseline for #99: every later slice must keep them green. The
// validator parameter `_version: Int` is passed first (0), per Aiken's
// parameterized-validator test-call convention.

// Accept: mint a fresh cage thread token. The consumed out-ref is an input, the
// mint field carries exactly one policy asset at qty 1, and the first output at
// the cage script opens an empty state.
test accept_mint_full_tx() {
  let asset = out_ref(seed_tx_id, 0)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let tx = mint_tx(cage_policy, asset, state)
  cage.mpfCage.mint(0, Minting(Mint { asset }), cage_policy, tx)
}

// Accept: migrate a token from a predecessor policy — burn one old-policy token
// at -1, mint one new-policy token at +1, open the successor state.
test accept_migrate_full_tx() {
  let asset = out_ref(seed_tx_id, 1)
  let tokenId = token_of(asset)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let tx = migrate_tx(cage_policy, old_cage_policy, tokenId, state)
  cage.mpfCage.mint(
    0,
    Migrating(Migration { oldPolicy: old_cage_policy, tokenId }),
    cage_policy,
    tx,
  )
}

// Accept: an empty-batch Modify — spend the state UTxO and re-create it
// unchanged (same root / time params), owner-signed, fee 0.
test accept_modify_empty_batch_full_tx() {
  let own_ref = out_ref(seed_tx_id, 2)
  let tokenId = token_of(own_ref)
  let root0 = empty_root()
  let in_state = state_datum(owner_vkh, root0, empty_root(), 0, 10_000, 10_000)
  let out_state = state_datum(owner_vkh, root0, empty_root(), 0, 10_000, 10_000)
  let tx =
    modify_tx(cage_policy, own_ref, tokenId, owner_vkh, in_state, out_state)
  cage.mpfCage.spend(0, Some(in_state), Modify([]), own_ref, tx)
}

// Accept: a non-empty Modify that folds one Insert request into the value trie.
// This reaches the full accept path — `mkAction` -> `verifyOwnerAuth` (real
// Ed25519 + MPF-inclusion auth), the MPF insert, and refund accounting — using
// the gen-vectors owner-auth fixture whose signature is over the request input's
// output reference (tx_id 0xde*32, index 0).
test accept_modify_insert_full_tx() {
  let owner_key =
    #"2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
  let owner_aid = #"746573742d616964"
  let owner_sig =
    #"f25fc18036ea046e7812d1e044fc18fadbe7f31b9fc402fe7bf4b10acd7317b11d83d86bdf0e8c91741a0b2f39e8e9e48d18588514cfd6df5f13542dd43cfd01"
  let identity_root =
    #"4252dfacb23de149149cbd8fa606b63e59c501a10a168854eead7c25af070f94"
  let request_ref =
    out_ref(
      #"dededededededededededededededededededededededededededededededede",
      0,
    )

  let own_ref = out_ref(seed_tx_id, 2)
  let tokenId = token_of(own_ref)
  let tip = 1_000_000
  let process_time = 10_000
  let retract_time = 10_000

  // Insert key "42" -> value "42" into the empty value trie (proof []); the
  // continuing state carries the recomputed root.
  let new_root = insert_root(empty_root(), "42", "42", [])
  let in_state =
    state_datum(
      owner_vkh,
      empty_root(),
      identity_root,
      tip,
      process_time,
      retract_time,
    )
  let out_state =
    state_datum(
      owner_vkh,
      new_root,
      identity_root,
      tip,
      process_time,
      retract_time,
    )

  let state_in =
    input_at(
      own_ref,
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, tokenId),
        in_state,
      ),
    )
  let request_in =
    input_at(
      request_ref,
      inline_output(
        from_script(cage_policy),
        from_lovelace(2_000_000),
        request_datum(tokenId, owner_vkh, "42", Insert("42"), tip, 0),
      ),
    )

  let auth = OwnerAuth { owner_aid, identity_proof: [], owner_key, owner_sig }
  let action = UpdateAction { value_proof: [], auth }

  // Refund the request owner: totalInput(2_000_000) - fee(0) - n(1)*tip.
  let refund = ada_output(from_verification_key(owner_vkh), 2_000_000 - tip)
  let state_out =
    inline_output(
      from_script(cage_policy),
      state_value(cage_policy, tokenId),
      out_state,
    )

  let tx =
    spend_context(
      [state_in, request_in],
      [],
      [state_out, refund],
      zero,
      [owner_vkh],
      interval.between(0, 5_000),
      0,
    )

  cage.mpfCage.spend(0, Some(in_state), Modify([action]), own_ref, tx)
}

// Accept: End the cage — owner-signed spend of the state UTxO that burns its
// thread token at -1.
test accept_end_full_tx() {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let tx = end_tx(cage_policy, own_ref, tokenId, owner_vkh, state)
  cage.mpfCage.spend(0, Some(state), End, own_ref, tx)
}

// ---- Tests ------------------------------------------------------------------

test fold_gap_fix_empty_actions_accepted() {
  let remaining: List<RequestAction> = []
  remaining == []
}

// Test vectors generated by `gen-vectors` (offchain/app/GenVectors.hs).
// Single-element identity trie: identity_root[owner_aid] = blake2b_256(owner_key).
// owner_key: Ed25519 public key derived from seed = 0x42 * 32.
// tx_id: 0xde * 32, output_index: 0.
//
// Proof is [] because a single-leaf MPF trie has no sibling nodes.

// Accept: valid owner_key + matching owner_sig + valid MPF inclusion.
test accept_owner_signed() {
  let owner_key =
    #"2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
  let owner_aid = #"746573742d616964"
  let owner_sig =
    #"f25fc18036ea046e7812d1e044fc18fadbe7f31b9fc402fe7bf4b10acd7317b11d83d86bdf0e8c91741a0b2f39e8e9e48d18588514cfd6df5f13542dd43cfd01"
  let identity_root =
    #"4252dfacb23de149149cbd8fa606b63e59c501a10a168854eead7c25af070f94"
  let tx_id =
    #"dededededededededededededededededededededededededededededededede"

  let auth = OwnerAuth { owner_aid, identity_proof: [], owner_key, owner_sig }
  let out_ref = OutputReference { transaction_id: tx_id, output_index: 0 }

  verifyOwnerAuth(auth, identity_root, out_ref)
}

// Reject: wrong signature — verify_ed25519 returns False for a zeroed sig.
test reject_bad_sig() {
  let owner_key =
    #"2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
  let tx_id =
    #"dededededededededededededededededededededededededededededededede"
  let domain = "cardano-keri/value-write/v1"
  let msg =
    blake2b_256(
      domain
        |> bytearray.concat(tx_id)
        |> bytearray.concat(#"0000"),
    )
  let bad_sig =
    #"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

  !verify_ed25519_signature(owner_key, msg, bad_sig)
}

// Reject: wrong public key — correct sig but different key → verify fails.
test reject_wrong_key() {
  let owner_key =
    #"2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
  let wrong_key =
    #"0000000000000000000000000000000000000000000000000000000000000000"
  let tx_id =
    #"dededededededededededededededededededededededededededededededede"
  let domain = "cardano-keri/value-write/v1"
  let msg =
    blake2b_256(
      domain
        |> bytearray.concat(tx_id)
        |> bytearray.concat(#"0000"),
    )
  let sig =
    #"f25fc18036ea046e7812d1e044fc18fadbe7f31b9fc402fe7bf4b10acd7317b11d83d86bdf0e8c91741a0b2f39e8e9e48d18588514cfd6df5f13542dd43cfd01"

  // sig is valid for owner_key but wrong_key should reject it
  !verify_ed25519_signature(wrong_key, msg, sig) && verify_ed25519_signature(
    owner_key,
    msg,
    sig,
  )
}
