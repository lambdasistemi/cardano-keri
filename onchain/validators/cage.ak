use aiken/collection/dict
use aiken/collection/list.{find, foldl, has, head}
use aiken/crypto.{VerificationKeyHash, blake2b_256, verify_ed25519_signature}
use aiken/interval
use aiken/merkle_patricia_forestry.{MerklePatriciaForestry, empty, root}
use aiken/merkle_patricia_forestry as mpf
use aiken/option.{is_some}
use aiken/primitive/bytearray.{from_int_big_endian}
use cardano/address
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use lib.{TokenId, assetName, quantity, tokenFromValue}
use types.{
  Burning, CageDatum, Contribute, Delete, End, Insert, Migrating, Migration,
  Mint, MintRedeemer, Minting, Modify, OwnerAuth, Rejected, Request,
  RequestAction, RequestDatum, Retract, State, StateDatum, Update, UpdateAction,
  UpdateRedeemer,
}

/// Domain tag for value-write authorization messages.
const value_write_domain: ByteArray = "cardano-keri/value-write/v1"

validator mpfCage(_version: Int) {
  mint(redeemer: MintRedeemer, policyId: PolicyId, tx: Transaction) {
    when redeemer is {
      Minting(mint) -> validateMint(mint, policyId, tx)
      Migrating(migration) -> validateMigration(migration, policyId, tx)
      Burning(tokenId) -> validateBurn(tokenId, policyId, tx)
    }
  }

  spend(
    maybeDatum: Option<CageDatum>,
    redeemer: UpdateRedeemer,
    self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(datum) = maybeDatum
    when redeemer is {
      Retract(stateRef) -> {
        expect RequestDatum(request) = datum
        let Request { requestOwner, requestToken, submitted_at, .. } = request
        let Transaction {
          extra_signatories,
          validity_range,
          reference_inputs,
          ..
        } = tx
        expect has(extra_signatories, requestOwner)
        expect Some(stateInput) =
          find(
            reference_inputs,
            fn(input) { input.output_reference == stateRef },
          )
        expect Some(tokenId) = tokenFromValue(stateInput.output.value)
        expect requestToken == tokenId
        let State { process_time, retract_time, .. } = readState(stateInput)
        expect
          in_phase2(validity_range, submitted_at, process_time, retract_time)
        True
      }
      Contribute(tokenRef) -> {
        expect RequestDatum(request) = datum
        validRequest(request, tokenRef, tx)
      }
      _ -> {
        expect StateDatum(state) = datum
        expect validateOwnership(state, tx)
        let (input, tokenId) = extractToken(self, tx)
        when redeemer is {
          Modify(actions) -> validModify(state, input, tokenId, tx, actions)
          End -> {
            expect address.Script(policyId) =
              input.output.address.payment_credential
            validateEnd(policyId, tokenId, tx)
          }
          _ -> fail
        }
      }
    }
  }

  else(_) {
    fail
  }
}

pub fn extractToken(what: OutputReference, tx: Transaction) {
  expect Some(input) =
    find(tx.inputs, fn(input) { input.output_reference == what })
  expect Some(tokenId) = tokenFromValue(input.output.value)
  (input, tokenId)
}

fn validateEnd(policyId, tokenId, tx) {
  let Transaction { mint, .. } = tx
  expect Some(q) = quantity(policyId, mint, tokenId)
  expect q == -1
  True
}

/// Validate a `Burning` mint: the burn of a cage thread token must be exactly one
/// owner-authorized End lifecycle transition.
///
/// - The cage policy must mint **exactly one** entry — the burned `tokenId`'s
///   asset name at quantity **-1**. Inspecting the full `tokens(mint, policyId)`
///   map (not just the derived token's quantity) rejects any positive quantity
///   (a counterfeit), any extra asset name, and any mismatched entry (H1).
/// - The burn must be **coupled** to an owner-authorized `End`: a cage-script
///   state UTxO holding the burned token must be spent, and that state's owner
///   must sign. The `End` spend path independently re-checks the -1 burn, so a
///   `Burning` mint and its `End` spend are one exact lifecycle transition — a
///   burn with no matching state UTxO, or one the owner did not authorize, is
///   rejected (H6).
fn validateBurn(tokenId: TokenId, policyId: PolicyId, tx: Transaction) {
  let Transaction { mint, inputs, extra_signatories, .. } = tx
  expect [Pair(burnedName, burnedQty)] = dict.to_pairs(tokens(mint, policyId))
  expect burnedName == tokenId.assetName
  expect burnedQty == -1
  expect Some(stateInput) =
    find(
      inputs,
      fn(input) {
        input.output.address.payment_credential == address.Script(policyId) && quantity(
          policyId,
          input.output.value,
          tokenId,
        ) == Some(1)
      },
    )
  let State { owner, .. } = readState(stateInput)
  expect has(extra_signatories, owner)
  True
}

fn validateOwnership(state: State, tx: Transaction) {
  let Transaction { extra_signatories, .. } = tx
  let State { owner, .. } = state
  expect has(extra_signatories, owner)
  True
}

fn readState(input: Input) -> State {
  when input.output.datum is {
    InlineDatum(datum) ->
      if datum is StateDatum(state): CageDatum {
        state
      } else {
        fail
      }
    _ -> fail
  }
}

fn validRequest(request: Request, tokenRef: OutputReference, tx: Transaction) {
  let Request { requestToken, submitted_at, .. } = request
  let (input, tokenId) = extractToken(tokenRef, tx)
  expect requestToken == tokenId
  let State { process_time, retract_time, .. } = readState(input)
  let Transaction { validity_range, .. } = tx
  expect
    in_phase1(validity_range, submitted_at, process_time) || is_rejectable(
      validity_range,
      submitted_at,
      process_time,
      retract_time,
    )
  True
}

fn uncons(list: List<a>, cont: fn(a, List<a>) -> b) -> b {
  when list is {
    [] -> fail
    [x, ..xs] -> cont(x, xs)
  }
}

pub fn in_phase1(validity_range, submitted_at, process_time) -> Bool {
  interval.is_entirely_before(validity_range, submitted_at + process_time)
}

pub fn in_phase2(
  validity_range,
  submitted_at,
  process_time,
  retract_time,
) -> Bool {
  interval.is_entirely_after(validity_range, submitted_at + process_time - 1) && interval.is_entirely_before(
    validity_range,
    submitted_at + process_time + retract_time,
  )
}

pub fn is_rejectable(
  validity_range,
  submitted_at,
  process_time,
  retract_time,
) -> Bool {
  interval.is_entirely_after(
    validity_range,
    submitted_at + process_time + retract_time - 1,
  ) || interval.is_entirely_before(validity_range, submitted_at)
}

/// Verify that the owner of a request has authorized this specific value-write.
///
/// 1. Verify identity inclusion: identity_root[owner_aid] = blake2b_256(owner_key)
///    using a no-op MPF update (old == new proves membership).
/// 2. Verify the owner's Ed25519 signature over the request's output reference,
///    binding the auth to this specific UTxO (replay protection).
pub fn verifyOwnerAuth(
  auth: OwnerAuth,
  identity_root: ByteArray,
  out_ref: OutputReference,
) -> Bool {
  let OwnerAuth { owner_aid, identity_proof, owner_key, owner_sig } = auth
  // Step 1: verify identity inclusion via no-op MPF update
  let id_trie = mpf.from_root(identity_root)
  let cur_key_digest = blake2b_256(owner_key)
  expect _ =
    mpf.update(
      id_trie,
      owner_aid,
      identity_proof,
      cur_key_digest,
      cur_key_digest,
    )
  // Step 2: verify owner signature over domain ++ request output reference
  let msg =
    blake2b_256(
      value_write_domain
        |> bytearray.concat(out_ref.transaction_id)
        |> bytearray.concat(from_int_big_endian(out_ref.output_index, 2)),
    )
  expect verify_ed25519_signature(owner_key, msg, owner_sig)
  True
}

fn mkAction(
  tokenId,
  state_tip,
  process_time,
  retract_time,
  validity_range,
  identity_root,
) {
  fn(
    input: Input,
    acc: (
      MerklePatriciaForestry,
      List<RequestAction>,
      List<Pair<VerificationKeyHash, Int>>,
      Int,
    ),
  ) -> (
    MerklePatriciaForestry,
    List<RequestAction>,
    List<Pair<VerificationKeyHash, Int>>,
    Int,
  ) {
    when input.output.datum is {
      InlineDatum(datum) ->
        if datum is RequestDatum(request): CageDatum {
          let Request {
            requestToken,
            requestKey,
            requestValue,
            requestOwner,
            tip,
            submitted_at,
          } = request
          if requestToken == tokenId {
            expect tip == state_tip
            let (trie, actions, owners, totalInputLovelace) = acc
            let action, actionsTail <- uncons(actions)
            let inputLovelace = assets.lovelace_of(input.output.value)
            let newTrie =
              when action is {
                UpdateAction { value_proof, auth } -> {
                  expect in_phase1(validity_range, submitted_at, process_time)
                  // Verify AID owner authorization before applying MPF op
                  expect
                    verifyOwnerAuth(auth, identity_root, input.output_reference)
                  when requestValue is {
                    Insert(value) ->
                      mpf.insert(trie, requestKey, value, value_proof)
                    Delete(value) ->
                      mpf.delete(trie, requestKey, value, value_proof)
                    Update(oldValue, newValue) ->
                      mpf.update(
                        trie,
                        requestKey,
                        value_proof,
                        oldValue,
                        newValue,
                      )
                  }
                }
                Rejected -> {
                  expect
                    is_rejectable(
                      validity_range,
                      submitted_at,
                      process_time,
                      retract_time,
                    )
                  trie
                }
              }
            let newOwners =
              if inputLovelace > 0 {
                [Pair(requestOwner, inputLovelace), ..owners]
              } else {
                owners
              }
            (
              newTrie,
              actionsTail,
              newOwners,
              totalInputLovelace + inputLovelace,
            )
          } else {
            acc
          }
        } else {
          acc
        }
      _ -> acc
    }
  }
}

fn sumRefunds(
  outputs: List<Output>,
  owners: List<Pair<VerificationKeyHash, Int>>,
) -> Int {
  when owners is {
    [] -> 0
    [Pair(owner, _), ..rest] -> {
      expect [output, ..remaining] = outputs
      expect address.VerificationKey(vkh) = output.address.payment_credential
      expect vkh == owner
      assets.lovelace_of(output.value) + sumRefunds(remaining, rest)
    }
  }
}

fn validModify(
  state: State,
  input: Input,
  tokenId: TokenId,
  tx: Transaction,
  actions: List<RequestAction>,
) {
  let Transaction { outputs, inputs, validity_range, fee: tx_fee, mint, .. } =
    tx
  // Spend-side half of the H6 mint↔End coupling (see `validateBurn`): a Modify
  // continues the cage lifecycle, so it must NOT mint or burn its own thread
  // token. Burning is exclusively the owner-authorized End path, so a burn
  // cannot be laundered through a Modify of the same state UTxO.
  expect address.Script(scriptPolicy) = input.output.address.payment_credential
  expect None = quantity(scriptPolicy, mint, tokenId)
  let State { root, tip, process_time, retract_time, .. } = state
  expect Some(output) = head(outputs)
  expect InlineDatum(outDatum) = output.datum
  expect StateDatum(State {
    root: newRoot,
    process_time: outProcessTime,
    retract_time: outRetractTime,
    identity_root: outIdentityRoot,
    ..
  }) = outDatum
  // Enforce immutability of time params
  expect process_time == outProcessTime
  expect retract_time == outRetractTime

  // identity_root may advance (oracle updates it) but must not silently regress
  // (handled by oracle governance; not checked here — oracle signs the tx)
  let (expectedNewTrie, remainingActions, owners, totalInputLovelace) =
    inputs
      |> foldl(
          (mpf.from_root(root), actions, [], 0),
          mkAction(
            tokenId,
            tip,
            process_time,
            retract_time,
            validity_range,
            outIdentityRoot,
          ),
        )
  // Fold gap fix: all actions must be consumed
  expect remainingActions == []
  expect mpf.root(expectedNewTrie) == newRoot
  expect
    output.address.payment_credential == input.output.address.payment_credential

  let n = list.length(owners)
  expect [_, ..refundOutputs] = outputs
  let orderedOwners = list.reverse(owners)
  let totalRefunded = sumRefunds(refundOutputs, orderedOwners)
  expect totalRefunded == totalInputLovelace - tx_fee - n * tip
  True
}

pub fn validateMint(minting: Mint, policyId: PolicyId, tx: Transaction) {
  let Mint { asset } = minting
  let Transaction { outputs, mint, inputs, .. } = tx
  let tokenId = TokenId { assetName: assetName(asset) }
  expect is_some(find_input(inputs, asset))
  // Exactly one asset name under the cage policy, and it is the derived thread
  // token at quantity 1. Inspecting the full `tokens(mint, policyId)` map (not
  // just the derived token's quantity) rejects any extra asset name or extra
  // quantity minted under the cage policy.
  expect [Pair(mintedName, mintedQty)] = dict.to_pairs(tokens(mint, policyId))
  expect mintedName == tokenId.assetName
  expect mintedQty == 1
  expect Some(output) = head(outputs)
  expect address.Script(targetScriptHash) = output.address.payment_credential
  expect targetScriptHash == policyId
  expect InlineDatum(tokenState) = output.datum
  expect StateDatum(State { root: tokenRoot, .. }) = tokenState
  expect tokenRoot == root(empty)
  // Confine the minted thread token in the designated state output.
  expect quantity(policyId, output.value, tokenId) == Some(1)
  True
}

pub fn validateMigration(
  migration: Migration,
  policyId: PolicyId,
  tx: Transaction,
) {
  let Migration { oldPolicy, tokenId } = migration
  let Transaction { outputs, mint, .. } = tx
  expect
    when quantity(oldPolicy, mint, tokenId) is {
      Some(qty) -> qty == -1
      None -> False
    }
  expect
    when quantity(policyId, mint, tokenId) is {
      Some(qty) -> qty == 1
      None -> False
    }
  expect Some(output) = head(outputs)
  expect address.Script(targetScriptHash) = output.address.payment_credential
  expect targetScriptHash == policyId
  expect InlineDatum(tokenState) = output.datum
  expect StateDatum(State { .. }) = tokenState
  True
}
