use aiken/crypto.{blake2b_256, verify_ed25519_signature}
use aiken/interval
use aiken/primitive/bytearray
use cage.{verifyOwnerAuth}
use cage_context.{
  ada_output, cage_policy, empty_root, end_tx, inline_output, input_at,
  insert_root, migrate_tx, min_ada, mint_context, mint_tx, modify_tx,
  old_cage_policy, out_ref, owner_vkh, request_datum, seed_tx_id, spend_context,
  state_datum, state_value, token_of,
}
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{from_asset, from_lovelace, merge, zero}
use cardano/transaction.{NoDatum, Output, OutputReference}
use types.{
  Burning, End, Insert, Migrating, Migration, Mint, Minting, Modify, OwnerAuth,
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
  cage.mpfCage.mint(
    0,
    old_cage_policy,
    Minting(Mint { asset }),
    cage_policy,
    tx,
  )
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
    old_cage_policy,
    Migrating(Migration { tokenId }),
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
  cage.mpfCage.spend(
    0,
    old_cage_policy,
    Some(in_state),
    Modify([]),
    own_ref,
    tx,
  )
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

  // FR6 binds the mutated key to the authenticated AID: the key's first 32 bytes
  // must be `blake2b_256(owner_aid)`. Use that digest as the request key so the
  // legitimate owner still authorizes. Insert key -> value "42" into the empty
  // value trie (proof []); the continuing state carries the recomputed root.
  let requestKey = blake2b_256(owner_aid)
  let new_root = insert_root(empty_root(), requestKey, "42", [])
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
        request_datum(tokenId, owner_vkh, requestKey, Insert("42"), tip, 0),
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

  cage.mpfCage.spend(
    0,
    old_cage_policy,
    Some(in_state),
    Modify([action]),
    own_ref,
    tx,
  )
}

// Accept: End the cage — owner-signed spend of the state UTxO that burns its
// thread token at -1.
test accept_end_full_tx() {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let tx = end_tx(cage_policy, own_ref, tokenId, owner_vkh, state)
  cage.mpfCage.spend(0, old_cage_policy, Some(state), End, own_ref, tx)
}

// Accept: a Burning mint coupled to an owner-authorized End. The owner spends the
// cage state UTxO holding the thread token and burns it at -1 — the mint side of
// the same lifecycle transition `accept_end_full_tx` authorizes. `end_tx` already
// assembles exactly this shape (state input carrying the token, owner signs, mint
// -1), so the hardened `validateBurn` accepts it.
test accept_burning_full_tx() {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let tx = end_tx(cage_policy, own_ref, tokenId, owner_vkh, state)
  cage.mpfCage.mint(0, old_cage_policy, Burning(tokenId), cage_policy, tx)
}

// ---- Slice 2 attack tests: minting confinement (FR1 / H3-mint) --------------
//
// RED→GREEN convention (plan.md): each attack asserts the DESIRED post-fix
// rejection with the `fail` form. On current permissive `validateMint` the
// malicious tx is ACCEPTED (handler returns without failing), so the
// `fail`-annotated test FAILS = RED. After the FR1 fix the tx is REJECTED
// (handler fails), so the test PASSES = GREEN.

// RED (a): a mint tx where exactly one cage token is minted (mint field carries
// the derived asset name at qty 1, consumed out-ref present) but the designated
// state output at the cage script does NOT contain that token — its value is
// ada-only (the token was sent elsewhere / omitted). Current `validateMint`
// never checks the token is confined in the state output, so it accepts. The
// FR1 fix requires `quantity(policyId, output.value, tokenId) == Some(1)`.
test reject_mint_token_absent_from_state_output() fail {
  let asset = out_ref(seed_tx_id, 0)
  let tokenId = token_of(asset)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  // State output sits at the cage script with an empty-root StateDatum, but its
  // value is ada-only: the minted thread token is NOT confined here.
  let state_out =
    inline_output(from_script(cage_policy), from_lovelace(min_ada), state)
  let tx =
    mint_context(
      [input_at(asset, ada_output(from_verification_key(owner_vkh), min_ada))],
      [state_out],
      from_asset(cage_policy, tokenId.assetName, 1),
    )
  cage.mpfCage.mint(
    0,
    old_cage_policy,
    Minting(Mint { asset }),
    cage_policy,
    tx,
  )
}

// RED (b): a mint tx that mints the derived thread token AND an additional asset
// name ("extra") under the SAME cage policy. The state output honestly confines
// the derived token, so only the extra-asset-name check must reject. Current
// `validateMint` only checks the derived token's quantity via
// `quantity(policyId, mint, tokenId)` and never inspects the full
// `tokens(mint, policyId)` map, so it accepts. The FR1 fix requires exactly one
// asset name under the cage policy at qty 1.
test reject_mint_extra_asset_name_under_policy() fail {
  let asset = out_ref(seed_tx_id, 0)
  let tokenId = token_of(asset)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let state_out =
    inline_output(
      from_script(cage_policy),
      state_value(cage_policy, tokenId),
      state,
    )
  // Mint the derived token at qty 1 AND an unrelated asset name under the same
  // policy — an extra token minted alongside the thread token.
  let mint =
    from_asset(cage_policy, tokenId.assetName, 1)
      |> merge(from_asset(cage_policy, "extra", 1))
  let tx =
    mint_context(
      [input_at(asset, ada_output(from_verification_key(owner_vkh), min_ada))],
      [state_out],
      mint,
    )
  cage.mpfCage.mint(
    0,
    old_cage_policy,
    Minting(Mint { asset }),
    cage_policy,
    tx,
  )
}

// ---- Slice 3 attack tests: burn/End lifecycle (FR2 / H1+H6) -----------------
//
// Same RED→GREEN convention: each `fail` test asserts the DESIRED post-fix
// rejection. On the current permissive `Burning -> True` mint handler the
// malicious tx is ACCEPTED (handler returns True without failing), so the
// `fail`-annotated test FAILS = RED. After coupling the burn to an owner-
// authorized End the tx is REJECTED (handler fails), so the test PASSES = GREEN.
//
// The FR2 fix carries four separable invariants — the single cage-policy mint
// entry must be (i) the burned token's asset name at (ii) exactly -1, coupled to
// (iii) a spent cage-script state UTxO that carries *that* token, spent (iv) with
// the owner's signature. Each attack below is a well-formed owner-authorized End
// EXCEPT for one defect, so it isolates exactly one invariant: a weak
// implementation that skips any single check leaves that test RED.

// (a) POSITIVE mint. Everything is a well-formed owner-authorized End (matching
// state UTxO spent, owner signs, one cage-policy entry) EXCEPT the quantity is
// +1 — a counterfeit inflation, not a burn. Isolates the `qty == -1` check.
test reject_burning_positive_mint() fail {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let state_input =
    input_at(
      own_ref,
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, tokenId),
        state,
      ),
    )
  let tx =
    spend_context(
      [state_input],
      [],
      [],
      from_asset(cage_policy, tokenId.assetName, 1),
      [owner_vkh],
      interval.everything,
      0,
    )
  cage.mpfCage.mint(0, old_cage_policy, Burning(tokenId), cage_policy, tx)
}

// (b) NO matching End spend. Owner signs and the burn is a well-formed single -1
// entry, but the only spent cage-script state UTxO carries a DIFFERENT token
// than the one being burned — there is no End spend of the burned token's state.
// Isolates the token-matched coupling: a weak "any cage input / any signer"
// coupling would accept this, so requiring an arbitrary signer cannot masquerade
// as lifecycle coupling.
test reject_burn_state_input_token_mismatch() fail {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  // A different token sits in the spent cage state UTxO.
  let otherId = token_of(out_ref(seed_tx_id, 99))
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let mismatched_input =
    input_at(
      out_ref(seed_tx_id, 4),
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, otherId),
        state,
      ),
    )
  let tx =
    spend_context(
      [mismatched_input],
      [],
      [],
      from_asset(cage_policy, tokenId.assetName, -1),
      [owner_vkh],
      interval.everything,
      0,
    )
  cage.mpfCage.mint(0, old_cage_policy, Burning(tokenId), cage_policy, tx)
}

// (b′) End spend LACKS owner authorization. The matching state UTxO is spent and
// the burn is a well-formed single -1 entry, but nobody signs — the End is not
// owner-authorized. Isolates the owner-signature requirement.
test reject_burn_without_owner_signature() fail {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let state_input =
    input_at(
      own_ref,
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, tokenId),
        state,
      ),
    )
  let tx =
    spend_context(
      [state_input],
      [],
      [],
      from_asset(cage_policy, tokenId.assetName, -1),
      [],
      interval.everything,
      0,
    )
  cage.mpfCage.mint(0, old_cage_policy, Burning(tokenId), cage_policy, tx)
}

// (c) EXTRA cage-policy entry. A well-formed owner-authorized End (matching state
// UTxO spent, owner signs) EXCEPT the cage-policy mint map carries an extra asset
// name alongside the -1 burn. Isolates the exactly-one-cage-policy-entry check.
test reject_burning_extra_cage_entry() fail {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let state_input =
    input_at(
      own_ref,
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, tokenId),
        state,
      ),
    )
  let mint =
    from_asset(cage_policy, tokenId.assetName, -1)
      |> merge(from_asset(cage_policy, "extra", -1))
  let tx =
    spend_context(
      [state_input],
      [],
      [],
      mint,
      [owner_vkh],
      interval.everything,
      0,
    )
  cage.mpfCage.mint(0, old_cage_policy, Burning(tokenId), cage_policy, tx)
}

// (d) BURN LAUNDERED THROUGH MODIFY. The mint handler alone cannot tell which
// branch the spent state UTxO takes, so `validateBurn` accepts an owner-signed
// `Burning(tokenId)` whenever a matching cage state input is spent — even if that
// input is spent via `Modify`, not `End`. The coupling to End is completed on the
// SPEND side: every non-End state spend must refuse to co-occur with the matching
// -1 burn. Here the owner spends the state UTxO via `Modify([])` (dropping the
// token into a TOKENLESS continuing output) while burning it via `Burning`. Both
// handlers must not simultaneously succeed. This runs BOTH handlers on one tx:
// RED against a `validateBurn`-only fix (both pass), GREEN once `validModify`
// rejects a burn of its own thread token.
test reject_burn_via_modify_not_end() fail {
  let own_ref = out_ref(seed_tx_id, 3)
  let tokenId = token_of(own_ref)
  let in_state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let out_state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let state_input =
    input_at(
      own_ref,
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, tokenId),
        in_state,
      ),
    )
  // Continuing state output at the cage script but TOKENLESS (ada only): the
  // thread token is dropped here and separately burned by the mint below.
  let state_out =
    inline_output(from_script(cage_policy), from_lovelace(min_ada), out_state)
  let tx =
    spend_context(
      [state_input],
      [],
      [state_out],
      from_asset(cage_policy, tokenId.assetName, -1),
      [owner_vkh],
      interval.everything,
      0,
    )
  let mint_ok =
    cage.mpfCage.mint(0, old_cage_policy, Burning(tokenId), cage_policy, tx)
  let spend_ok =
    cage.mpfCage.spend(
      0,
      old_cage_policy,
      Some(in_state),
      Modify([]),
      own_ref,
      tx,
    )
  mint_ok && spend_ok
}

// ---- Slice 4 attack tests: migration pin + confinement (FR3 / H2+H3-migration)
//
// Same RED→GREEN convention: each `fail` test asserts the DESIRED post-fix
// rejection. On the current `validateMigration` (which trusts the caller-supplied
// `oldPolicy` and never inspects the full per-policy mint maps or confines the
// successor token in the state output) each malicious tx is ACCEPTED (handler
// returns True without failing), so the `fail`-annotated test FAILS = RED. After
// pinning the predecessor policy and hardening the exact-mint + confinement checks
// the tx is REJECTED (handler fails), so the test PASSES = GREEN.
//
// Each attack is an otherwise-well-formed migration EXCEPT for one defect, so it
// isolates exactly one invariant: the pinned predecessor (a), the exact single
// successor entry (b), and successor-token confinement in the state output (c).

// (a) ATTACKER-CREATED PREDECESSOR POLICY. The attacker controls their own policy
// `attacker_policy`, mints a token under it, "burns" it at -1, and mints a
// genuine successor at +1 under the real cage policy — opening a real cage state
// they did not migrate from any prior cage. Current `validateMigration` trusts
// the redeemer's `oldPolicy`, so it accepts. The FR3 fix pins the predecessor
// policy by construction so an attacker-created predecessor cannot satisfy it.
test reject_migrate_attacker_predecessor_policy() fail {
  let asset = out_ref(seed_tx_id, 1)
  let tokenId = token_of(asset)
  let attacker_policy =
    #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  // Successor token honestly confined in the state output, so only the
  // predecessor pin can reject.
  let state_out =
    inline_output(
      from_script(cage_policy),
      state_value(cage_policy, tokenId),
      state,
    )
  let mint =
    from_asset(attacker_policy, tokenId.assetName, -1)
      |> merge(from_asset(cage_policy, tokenId.assetName, 1))
  let tx = mint_context([], [state_out], mint)
  cage.mpfCage.mint(
    0,
    old_cage_policy,
    Migrating(Migration { tokenId }),
    cage_policy,
    tx,
  )
}

// (b) EXTRA SUCCESSOR-POLICY ASSET NAME. A genuine predecessor burn at -1, the
// successor token minted at +1 AND confined in the state output, but the cage
// policy ALSO mints an unrelated asset name ("evil") — an extra token minted
// alongside the successor thread token. Current `validateMigration` only checks
// the named token's quantity via `quantity(policyId, mint, tokenId)` and never
// inspects the full `tokens(mint, policyId)` map, so it accepts. The FR3 fix
// requires exactly one asset name under the successor policy at qty 1.
test reject_migrate_extra_successor_asset() fail {
  let asset = out_ref(seed_tx_id, 1)
  let tokenId = token_of(asset)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  let state_out =
    inline_output(
      from_script(cage_policy),
      state_value(cage_policy, tokenId),
      state,
    )
  let mint =
    from_asset(old_cage_policy, tokenId.assetName, -1)
      |> merge(from_asset(cage_policy, tokenId.assetName, 1))
      |> merge(from_asset(cage_policy, "evil", 1))
  let tx = mint_context([], [state_out], mint)
  cage.mpfCage.mint(
    0,
    old_cage_policy,
    Migrating(Migration { tokenId }),
    cage_policy,
    tx,
  )
}

// (c) SUCCESSOR TOKEN ABSENT FROM STATE OUTPUT. A genuine predecessor burn at -1
// and exactly one successor mint at +1, but the designated state output is
// ada-only — the successor thread token is not confined where the state lives
// (it was sent elsewhere / omitted). Current `validateMigration` never checks the
// token is present in the state output, so it accepts. The FR3 fix requires
// `quantity(policyId, output.value, tokenId) == Some(1)` on the state output.
test reject_migrate_successor_token_absent_from_state_output() fail {
  let asset = out_ref(seed_tx_id, 1)
  let tokenId = token_of(asset)
  let state =
    state_datum(owner_vkh, empty_root(), empty_root(), 0, 10_000, 10_000)
  // State output at the cage script with an empty-root StateDatum, but ada-only:
  // the successor token is NOT confined here.
  let state_out =
    inline_output(from_script(cage_policy), from_lovelace(min_ada), state)
  let mint =
    from_asset(old_cage_policy, tokenId.assetName, -1)
      |> merge(from_asset(cage_policy, tokenId.assetName, 1))
  let tx = mint_context([], [state_out], mint)
  cage.mpfCage.mint(
    0,
    old_cage_policy,
    Migrating(Migration { tokenId }),
    cage_policy,
    tx,
  )
}

// ---- Slice 5 attack tests: Modify confinement + authorization ----------------
//                            (FR4+FR5+FR6 / H3-modify+H4+H5)
//
// Same RED→GREEN convention: each `fail` test asserts the DESIRED post-fix
// rejection. On the current `validModify`/`mkAction` (which never requires the
// thread token in the continuing output, authenticates against the tx's OWN
// OUTPUT identity_root, and never binds the authenticated `owner_aid` to the
// mutated `requestKey`) each malicious tx is ACCEPTED (handler returns True
// without failing), so the `fail`-annotated test FAILS = RED. After the Slice-5
// hardening the tx is REJECTED (handler fails), so the test PASSES = GREEN.
//
// (b)/(c)/(d) reuse the gen-vectors owner-auth fixture (valid Ed25519 signature
// over request_ref `0xde*32,0` and a genuine single-leaf identity trie), so the
// authorization path is genuinely reached; each perturbs exactly one axis so it
// isolates one invariant: token confinement (a / FR4), input-root auth (b / FR5),
// and aid↔key binding (c, d / FR6).

// (a) TOKEN MOVED OUT (FR4/H3-modify). A no-burn empty-batch `Modify`: the thread
// token is NOT burned (`mint` is empty, so the S3 reverse guard passes) but the
// continuing state output at the cage script is TOKENLESS — the token is sent to
// an attacker's non-cage output instead. Current `validModify` never requires the
// token in the continuing output, so it accepts. The FR4 fix requires
// `quantity(scriptPolicy, output.value, tokenId) == Some(1)` on that output.
test reject_modify_token_moved_out_of_state_output() fail {
  let own_ref = out_ref(seed_tx_id, 2)
  let tokenId = token_of(own_ref)
  let root0 = empty_root()
  let in_state = state_datum(owner_vkh, root0, empty_root(), 0, 10_000, 10_000)
  let out_state = state_datum(owner_vkh, root0, empty_root(), 0, 10_000, 10_000)
  let attacker_vkh = #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  let state_input =
    input_at(
      own_ref,
      inline_output(
        from_script(cage_policy),
        state_value(cage_policy, tokenId),
        in_state,
      ),
    )
  // Continuing state output at the cage script but TOKENLESS (ada only).
  let state_out =
    inline_output(from_script(cage_policy), from_lovelace(min_ada), out_state)
  // The thread token is moved OUT to an attacker's non-cage output (not burned).
  let attacker_out =
    Output {
      address: from_verification_key(attacker_vkh),
      value: state_value(cage_policy, tokenId),
      datum: NoDatum,
      reference_script: None,
    }
  let tx =
    spend_context(
      [state_input],
      [],
      [state_out, attacker_out],
      zero,
      [owner_vkh],
      interval.everything,
      0,
    )
  cage.mpfCage.spend(
    0,
    old_cage_policy,
    Some(in_state),
    Modify([]),
    own_ref,
    tx,
  )
}

// (b) OUTPUT-ROOT SELF-AUTHORIZATION (FR5/H4). The aid→key mapping the owner auth
// proves membership in is placed ONLY in the tx's OWN OUTPUT identity_root; the
// spent state's INPUT identity_root is an empty trie that does NOT contain it.
// `requestKey` is FR6-valid (`blake2b_256(owner_aid)`), so the only reason to
// reject is FR5. Current `mkAction` authenticates against the OUTPUT root, so a
// tx can introduce its own authority and is accepted. The FR5 fix authenticates
// against `state.identity_root` (the spent input), where the mapping is absent.
test reject_modify_output_identity_root_self_auth() fail {
  let owner_key =
    #"2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12"
  let owner_aid = #"746573742d616964"
  let owner_sig =
    #"f25fc18036ea046e7812d1e044fc18fadbe7f31b9fc402fe7bf4b10acd7317b11d83d86bdf0e8c91741a0b2f39e8e9e48d18588514cfd6df5f13542dd43cfd01"
  // Fabricated aid→key mapping — placed ONLY in the tx's own OUTPUT datum.
  let fabricated_root =
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

  // FR6-valid key so the ONLY defect is the FR5 input-vs-output root swap.
  let requestKey = blake2b_256(owner_aid)
  let new_root = insert_root(empty_root(), requestKey, "42", [])

  // INPUT identity_root does NOT contain the aid→key mapping (empty trie);
  // OUTPUT identity_root is the fabricated root that DOES contain it.
  let in_state =
    state_datum(
      owner_vkh,
      empty_root(),
      empty_root(),
      tip,
      process_time,
      retract_time,
    )
  let out_state =
    state_datum(
      owner_vkh,
      new_root,
      fabricated_root,
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
        request_datum(tokenId, owner_vkh, requestKey, Insert("42"), tip, 0),
      ),
    )

  let auth = OwnerAuth { owner_aid, identity_proof: [], owner_key, owner_sig }
  let action = UpdateAction { value_proof: [], auth }
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
  cage.mpfCage.spend(
    0,
    old_cage_policy,
    Some(in_state),
    Modify([action]),
    own_ref,
    tx,
  )
}

// (c) UNRELATED AID AUTHORIZES THE KEY (FR6/H5). A genuinely authenticated owner
// (owner_aid `test-aid`, valid identity inclusion in BOTH input and output roots,
// valid signature) authorizes a `requestKey` in a DIFFERENT namespace: a 32-byte
// key whose first 32 bytes are NOT `blake2b_256(owner_aid)`. Current `mkAction`
// never binds `owner_aid` to `requestKey`, so any registered AID authorizes any
// key. The FR6 fix requires `bytearray.take(requestKey, 32) == blake2b_256(owner_aid)`.
test reject_modify_unrelated_aid_authorizes_key() fail {
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

  // A 32-byte key in a DIFFERENT namespace: first 32 bytes ≠ blake2b_256(owner_aid).
  let requestKey =
    #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let new_root = insert_root(empty_root(), requestKey, "42", [])

  // Genuine identity_root in BOTH input and output (isolates FR6 from FR5).
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
        request_datum(tokenId, owner_vkh, requestKey, Insert("42"), tip, 0),
      ),
    )

  let auth = OwnerAuth { owner_aid, identity_proof: [], owner_key, owner_sig }
  let action = UpdateAction { value_proof: [], auth }
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
  cage.mpfCage.spend(
    0,
    old_cage_policy,
    Some(in_state),
    Modify([action]),
    own_ref,
    tx,
  )
}

// (d) RAW-AID PREFIX AUTHORIZES THE KEY (FR6/H5). Like (c) but the `requestKey`
// prefix is the RAW `owner_aid` bytes themselves (padded to 32 bytes), NOT their
// `blake2b_256`. A naive binding that compared the raw AID prefix would wrongly
// accept this; the frozen FR6 rule requires the first 32 bytes to equal
// `blake2b_256(owner_aid)`, and the AID bytes are not their own digest — reject.
test reject_modify_raw_aid_prefix_authorizes_key() fail {
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

  // requestKey = raw owner_aid (`test-aid`, 8 bytes) padded to 32 bytes. Its
  // first 32 bytes are the AID itself, NOT blake2b_256(owner_aid).
  let requestKey =
    #"746573742d616964000000000000000000000000000000000000000000000000"
  let new_root = insert_root(empty_root(), requestKey, "42", [])

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
        request_datum(tokenId, owner_vkh, requestKey, Insert("42"), tip, 0),
      ),
    )

  let auth = OwnerAuth { owner_aid, identity_proof: [], owner_key, owner_sig }
  let action = UpdateAction { value_proof: [], auth }
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
  cage.mpfCage.spend(
    0,
    old_cage_policy,
    Some(in_state),
    Modify([action]),
    own_ref,
    tx,
  )
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
