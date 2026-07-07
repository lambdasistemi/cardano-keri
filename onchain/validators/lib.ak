/// Helper functions for token handling in the MPF Cage validator.
///
/// This module provides utilities for:
/// - Token identification and extraction from values
/// - Asset name computation from output references
/// - Value construction for single tokens
///
/// ## Role in the Cage System
///
/// The cage validator needs to identify, extract, and manipulate
/// single NFTs. This module provides the plumbing:
///
/// - `assetName`: Derives a unique, deterministic asset name from an
///   `OutputReference` using SHA2-256. This is the foundation of the
///   cage minting policy's uniqueness guarantee.
///
/// - `tokenFromValue`: Extracts the single non-ADA token from a value.
///   Used to identify which caged token a UTxO belongs to.
///
/// - `quantity`: Checks how many of a specific token exist in a value.
///   Used during minting validation to ensure exactly 1 token is minted.
///
/// - `valueFromToken`: Constructs a value with exactly 1 of a token.
///   Used in tests and when building expected output values.
///
/// ## Design Decisions
///
/// `TokenId` only contains the `assetName`, not the `PolicyId`. This is
/// because the policy ID is always the cage script's own hash, which is
/// available from context. Separating them avoids redundancy and makes
/// it easier to compare tokens across different operations.
///
/// ## Test Hints
/// - `assetName` is deterministic: same OutputReference always produces
///   same asset name
/// - `assetName` is collision-resistant: different OutputReferences produce
///   different asset names (SHA2-256 property)
/// - `tokenFromValue` returns None for ADA-only values
/// - `tokenFromValue` returns None for multi-policy values
/// - `tokenFromValue` returns None for multi-asset-name values under one policy
/// - `quantity` returns None when the policy or asset name is absent

use aiken/collection/dict.{get, keys}
use aiken/collection/list.{delete, find}
use aiken/crypto.{Hash, Sha2_256, sha2_256}
use aiken/primitive/bytearray.{concat, from_int_big_endian}
use cardano/assets.{AssetName, PolicyId, Value, from_asset, policies, tokens}
use cardano/transaction.{Input, Output, OutputReference}

/// A unique identifier for a token, consisting of just the asset name.
///
/// The policy ID is provided separately in functions that need it,
/// allowing the same TokenId to be used across different contexts.
///
/// ## Why Only AssetName
/// In the cage system, the policy ID is always the cage script's own
/// hash (since it's a combined minting+spending validator). By storing
/// only the asset name, we avoid carrying redundant policy ID references
/// through the datum structures. The asset name alone uniquely identifies
/// a caged token within the cage script's namespace.
///
/// ## Derivation
/// The asset name is derived from an OutputReference via `assetName()`.
/// It is the SHA2-256 hash of (transaction_id ++ output_index_as_2_bytes).
pub type TokenId {
  assetName: AssetName,
}

/// Get the quantity of a specific token in a value.
///
/// Looks up the given policy ID in the value's token map, then looks up
/// the asset name within that policy's token entries.
///
/// Returns `Some(quantity)` if the token exists (quantity may be positive
/// or negative, e.g., in mint fields), `None` if the policy or asset name
/// is not present.
///
/// ## Usage in Validators
/// Used in `validateMint` to verify that exactly 1 token is minted:
/// ```
/// quantity(policyId, mint, tokenId) == Some(1)
/// ```
///
/// ## Test Hints
/// - Token present with quantity 1 -> Some(1)
/// - Token present with quantity -1 (burn) -> Some(-1)
/// - Token not present (wrong policy) -> None
/// - Token not present (wrong asset name) -> None
/// - Empty value -> None
pub fn quantity(policyId : PolicyId, value: Value, TokenId { assetName }) -> Option<Int> {
  get(tokens(value, policyId), assetName)
}

/// Compute a unique asset name from an output reference.
///
/// The asset name is the SHA2-256 hash of the transaction ID concatenated
/// with the output index (as 2 big-endian bytes). This ensures uniqueness
/// since an output reference can only be consumed once.
///
/// ## Algorithm
/// 1. Take the transaction ID (a 32-byte hash)
/// 2. Encode the output index as 2 bytes in big-endian format
/// 3. Concatenate: tx_id ++ output_index_bytes
/// 4. Apply SHA2-256 to the concatenation
///
/// ## Why 2 Bytes for Output Index
/// Using `from_int_big_endian(ref.output_index, 2)` encodes the output
/// index as exactly 2 bytes. This supports output indices from 0 to 65535,
/// which is more than sufficient for Cardano transactions (which have far
/// fewer outputs in practice).
///
/// ## Uniqueness Guarantee
/// Since an OutputReference (tx_id, output_index) can only appear once
/// in the UTXO set, and `validateMint` requires this OutputReference to
/// be consumed in the minting transaction, the same asset name can never
/// be minted twice. The SHA2-256 hash makes it computationally infeasible
/// to find a different OutputReference that produces the same asset name.
///
/// ## Test Hints
/// - Same OutputReference always produces same hash (deterministic)
/// - Different tx_id -> different hash
/// - Different output_index -> different hash
/// - Output index 0 vs 256 -> different hash (tests big-endian encoding)
pub fn assetName(ref: OutputReference) -> Hash<Sha2_256, OutputReference> {
  let bytes =
    concat(ref.transaction_id, from_int_big_endian(ref.output_index, 2))
  sha2_256(bytes)
}

/// Construct a Value containing exactly 1 of the specified token.
///
/// Creates a Cardano Value with a single native token at quantity 1 under
/// the given policy ID and asset name. Does NOT include any ADA -- the
/// caller is responsible for adding minimum ADA if needed.
///
/// ## Usage
/// - In `validateMint`: the expected output value is built with this
///   function to compare against the actual minted value.
/// - In tests: used to construct expected UTxO values.
///
/// ## Test Hints
/// - The resulting value should have exactly one policy (besides ADA)
/// - The token quantity should be exactly 1
/// - `tokenFromValue(valueFromToken(pid, tid))` should return `Some(tid)`
pub fn valueFromToken(policyId : PolicyId , TokenId { assetName }: TokenId) -> Value {
  from_asset(policyId, assetName, 1)
}

/// Extract a single token ID from a value.
///
/// This function expects the value to contain exactly one non-ADA policy
/// with exactly one asset name. Returns `None` if the value doesn't match
/// this pattern (e.g., contains multiple tokens or no tokens).
///
/// This is useful for extracting the caged token from a UTxO that should
/// contain only ADA and a single NFT.
///
/// ## Algorithm (step by step)
/// 1. Get all policy IDs from the value via `policies(value)`
/// 2. Remove the ADA policy (empty string "") from the list via `delete`
/// 3. If exactly one non-ADA policy remains:
///    a. Get its token map via `tokens(value, policyId)`
///    b. Get all asset name keys from the token map
///    c. If exactly one asset name exists:
///       - Look it up in the token map (this always succeeds)
///       - Return `Some(TokenId { assetName })`
///    d. Otherwise return `None`
/// 4. If zero or more than one non-ADA policy, return `None`
///
/// ## Important: Ignores Quantity
/// Note that this function does NOT check the token quantity. It returns
/// the TokenId regardless of whether the quantity is 1, 2, or even -1.
/// The caller must verify quantity separately if needed.
///
/// ## Security Consideration
/// This function is used in `extractToken` (cage.ak) which is called for
/// both `Modify` and `End` operations. If a UTxO somehow contained two
/// different NFTs, this function would return `None` and the validator
/// would fail -- this is the correct behavior.
///
/// ## Test Hints
/// - Value with ADA + 1 NFT -> Some(TokenId)
/// - Value with only ADA -> None
/// - Value with ADA + 2 different policies -> None
/// - Value with ADA + 1 policy + 2 asset names -> None
/// - Value with 1 NFT (no ADA entry) -> Some(TokenId)
/// - Value with ADA + 1 NFT quantity 5 -> Some(TokenId) (quantity ignored)
pub fn tokenFromValue(value: Value) -> Option<TokenId> {
  // Remove ADA policy ("") from the policy list
  when delete(policies(value), "") is {
    // Exactly one non-ADA policy
    [policyId] -> {
      let tokens = tokens(value, policyId)
      // Check that there's exactly one asset name under this policy
      when keys(tokens) is {
        [assetName] ->
          // Look up the asset name (should always succeed since we got it from keys)
          when get(tokens, assetName) is {
            Some(_) -> Some(TokenId { assetName })
            _ -> None
          }
        _ -> None
      }
    }
    _ -> None
  }
}

/// Find an input by output reference and extract its token.
///
/// Searches the input list for the specified output reference and extracts
/// the single token from that input's value. Returns `None` if the input
/// is not found or doesn't contain exactly one token (aside from ADA).
///
/// This is a convenience function that combines input lookup with token
/// extraction. It's used in the `Contribute` validation path where we need
/// to find the State UTxO and extract its caged token to compare against
/// the request's `requestToken`.
///
/// ## Differences from `extractToken` in cage.ak
/// This function returns `Option` (graceful failure), while `extractToken`
/// in cage.ak uses `expect` (hard failure). This version is defined in the
/// library for reuse, while the cage.ak version is specialized for the
/// spending validator context where failure should abort the transaction.
///
/// ## Test Hints
/// - Input exists and contains exactly one NFT -> Some((input, tokenId))
/// - Input exists but has no NFT (ADA only) -> None
/// - Input exists but has multiple NFTs -> None
/// - Output reference not found in inputs -> None
pub fn extractTokenFromInputs(what: OutputReference, inputs: List<Input>) {
  when find(inputs, fn(input) { input.output_reference == what }) is {
    Some(input) ->
      when tokenFromValue(input.output.value) is {
        Some(tokenId) -> Some((input, tokenId))
        _ -> None
      }
    _ -> None
  }
}
