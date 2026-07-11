//// Reusable full-transaction test harness for the `mpfCage` validator.
////
//// The existing `cage.tests.ak` could only call the pure `verifyOwnerAuth`
//// helper. Every security fix in #99 must instead be demonstrated against the
//// **real handler on a full `Transaction`** (`cage.mpfCage.mint` /
//// `cage.mpfCage.spend`). This module provides the smallest reusable set of
//// constructors — `Transaction`, `Input`, `Output`, `OutputReference`,
//// `Value`, and `CageDatum` (`StateDatum` / `RequestDatum`) — needed to
//// assemble mint-side and spend-side transactions.
////
//// Two layers are exposed so later slices never rebuild full `Transaction`
//// literals:
////
//// - **Primitive constructors** (`out_ref`, `state_value`, `inline_output`,
////   `ada_output`, `input_at`, `state_datum`, `request_datum`, ...) build the
////   individual pieces an attack fixture perturbs (token-drop, extra
////   asset/quantity, output-root/value swap, lifecycle changes).
//// - **General context constructors** (`mint_context`, `spend_context`) accept
////   the exact `inputs` / `outputs` / `mint` / `extra_signatories` /
////   `validity_range` / `fee` an attack varies, folded over
////   `transaction.placeholder`.
////
//// The **named happy-path builders** (`mint_tx`, `migrate_tx`, `modify_tx`,
//// `end_tx`) are thin wrappers over the general constructors that assemble the
//// four shapes the current code accepts; the full-tx accept tests in
//// `cage.tests.ak` are the #99 regression baseline.
////
//// This module adds **no** validator behavior; it is test infrastructure only.

use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Interval}
use aiken/merkle_patricia_forestry.{Proof, empty, from_root, insert, root}
use cardano/address.{Address, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use lib.{TokenId, assetName, valueFromToken}
use types.{CageDatum, Operation, Request, RequestDatum, State, StateDatum}

// ============================================================================
// Shared fixture constants
// ============================================================================

/// Cage script hash (its own minting policy id). 28 bytes.
pub const cage_policy: PolicyId =
  #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

/// A predecessor cage policy, used by the Migrate happy path. 28 bytes.
pub const old_cage_policy: PolicyId =
  #"01010101010101010101010101010101010101010101010101010101"

/// State-UTxO owner verification-key hash. 28 bytes.
pub const owner_vkh: VerificationKeyHash =
  #"0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee"

/// A generic transaction id used to seed output references. 32 bytes.
pub const seed_tx_id: ByteArray =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

/// Default lovelace held alongside the thread token in a cage UTxO.
pub const min_ada: Int = 2_000_000

/// The MPF root of the empty value trie (a fresh cage state).
pub fn empty_root() -> ByteArray {
  root(empty)
}

/// The MPF root obtained by applying an insert to a trie rooted at `base`.
/// Lets a Modify fixture compute the continuing-state root the validator will
/// recompute, without hard-coding a version-specific digest.
pub fn insert_root(
  base: ByteArray,
  key: ByteArray,
  value: ByteArray,
  proof: Proof,
) -> ByteArray {
  root(insert(from_root(base), key, value, proof))
}

// ============================================================================
// Primitive constructors
// ============================================================================

/// Build an `OutputReference` from a transaction id and output index.
pub fn out_ref(tx_id: ByteArray, index: Int) -> OutputReference {
  OutputReference { transaction_id: tx_id, output_index: index }
}

/// A value carrying `min_ada` lovelace plus exactly one thread token.
pub fn state_value(policyId: PolicyId, tokenId: TokenId) -> Value {
  from_lovelace(min_ada) |> merge(valueFromToken(policyId, tokenId))
}

/// An output at `address` holding `value` with an inline `CageDatum`.
pub fn inline_output(address: Address, value: Value, datum: CageDatum) -> Output {
  Output { address, value, datum: InlineDatum(datum), reference_script: None }
}

/// A plain ada-only output with no datum (used for refunds / funding).
pub fn ada_output(address: Address, lovelace: Int) -> Output {
  Output {
    address,
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

/// An `Input` pairing an output reference with the output it spends.
pub fn input_at(ref: OutputReference, output: Output) -> Input {
  Input { output_reference: ref, output }
}

/// The `TokenId` a cage would derive from consuming `ref`.
pub fn token_of(ref: OutputReference) -> TokenId {
  TokenId { assetName: assetName(ref) }
}

/// A `StateDatum` with the given fields.
pub fn state_datum(
  owner: VerificationKeyHash,
  root: ByteArray,
  identity_root: ByteArray,
  tip: Int,
  process_time: Int,
  retract_time: Int,
) -> CageDatum {
  StateDatum(
    State { owner, root, identity_root, tip, process_time, retract_time },
  )
}

/// A `RequestDatum` with the given fields.
pub fn request_datum(
  requestToken: TokenId,
  requestOwner: VerificationKeyHash,
  requestKey: ByteArray,
  requestValue: Operation,
  tip: Int,
  submitted_at: Int,
) -> CageDatum {
  RequestDatum(
    Request {
      requestToken,
      requestOwner,
      requestKey,
      requestValue,
      tip,
      submitted_at,
    },
  )
}

// ============================================================================
// General context constructors
// ============================================================================

/// A mint-side `Transaction` folded over `transaction.placeholder`. Attacks
/// vary `inputs` (consumed out-ref), `outputs` (state output value/datum), and
/// the `mint` field directly.
pub fn mint_context(
  inputs: List<Input>,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  Transaction { ..placeholder, inputs, outputs, mint }
}

/// A spend-side `Transaction` folded over `transaction.placeholder`. Attacks
/// vary the spent state input, request inputs, continuing-state / refund
/// outputs, `mint` (End burn), signatories, `validity_range`, and `fee`.
pub fn spend_context(
  inputs: List<Input>,
  reference_inputs: List<Input>,
  outputs: List<Output>,
  mint: Value,
  extra_signatories: List<VerificationKeyHash>,
  validity_range: Interval<Int>,
  fee: Int,
) -> Transaction {
  Transaction {
    ..placeholder,
    inputs,
    reference_inputs,
    outputs,
    mint,
    extra_signatories,
    validity_range,
    fee,
  }
}

// ============================================================================
// Named happy-path transaction builders
// ============================================================================

/// Mint-side transaction that mints a fresh cage thread token.
///
/// - `asset` (the consumed out-ref) is present in `inputs`;
/// - `mint` carries exactly one `policyId` asset (`assetName(asset)`) at qty 1;
/// - the first output sits at the cage script and carries `state`, which the
///   caller builds with `root == empty_root()`. The thread token is confined in
///   that state output.
pub fn mint_tx(
  policyId: PolicyId,
  asset: OutputReference,
  state: CageDatum,
) -> Transaction {
  let tokenId = token_of(asset)
  mint_context(
    [input_at(asset, ada_output(from_verification_key(owner_vkh), min_ada))],
    [
      inline_output(
        from_script(policyId),
        state_value(policyId, tokenId),
        state,
      ),
    ],
    from_asset(policyId, tokenId.assetName, 1),
  )
}

/// Migrate-side transaction: burn one predecessor-policy token, mint one
/// successor-policy token of the same asset name, and open the successor state.
pub fn migrate_tx(
  policyId: PolicyId,
  oldPolicy: PolicyId,
  tokenId: TokenId,
  state: CageDatum,
) -> Transaction {
  mint_context(
    [],
    [
      inline_output(
        from_script(policyId),
        state_value(policyId, tokenId),
        state,
      ),
    ],
    from_asset(oldPolicy, tokenId.assetName, -1)
      |> merge(from_asset(policyId, tokenId.assetName, 1)),
  )
}

/// Spend-side Modify transaction (empty batch / no-op): spend the state UTxO at
/// `own_ref` and re-create it unchanged. `in_state` and `out_state` must share
/// the same root / process_time / retract_time; `owner` signs; no request
/// inputs, fee 0, so refund accounting closes at zero owners.
pub fn modify_tx(
  policyId: PolicyId,
  own_ref: OutputReference,
  tokenId: TokenId,
  owner: VerificationKeyHash,
  in_state: CageDatum,
  out_state: CageDatum,
) -> Transaction {
  spend_context(
    [
      input_at(
        own_ref,
        inline_output(
          from_script(policyId),
          state_value(policyId, tokenId),
          in_state,
        ),
      ),
    ],
    [],
    [
      inline_output(
        from_script(policyId),
        state_value(policyId, tokenId),
        out_state,
      ),
    ],
    zero,
    [owner],
    interval.everything,
    0,
  )
}

/// Spend-side End transaction: spend the state UTxO at `own_ref`, signed by the
/// owner, burning its thread token at -1.
pub fn end_tx(
  policyId: PolicyId,
  own_ref: OutputReference,
  tokenId: TokenId,
  owner: VerificationKeyHash,
  state: CageDatum,
) -> Transaction {
  spend_context(
    [
      input_at(
        own_ref,
        inline_output(
          from_script(policyId),
          state_value(policyId, tokenId),
          state,
        ),
      ),
    ],
    [],
    [],
    from_asset(policyId, tokenId.assetName, -1),
    [owner],
    interval.everything,
    0,
  )
}
