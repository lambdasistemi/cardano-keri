//// S0-F06 / S0-M06 — Tx-A proof-token policy.
////
//// Owns the bounded (<= 1024 B) KERI Blake3 SAID proof and the pair-bound
//// mint. Burning is always permitted so Tx-B can consume the token.

use aiken/collection/dict
use aiken/primitive/bytearray
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/blake3
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/m12/proof_token.{
  all_burns, proof_token_name, slice_matches, splice_dummies,
}

/// S0-F06 — Blake3 SAID + mint identity, or an all-burn mint map.
pub fn validate_staging_token(
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  off_i: Int,
  off_d: Int,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let entries = dict.to_pairs(tokens(tx.mint, policy_id))
  if all_burns(entries) {
    True
  } else {
    let len = bytearray.length(raw_event)
    and {
      len >= 1,
      len <= 1024,
      bytearray.length(cesr_aid) == 32,
      0 <= off_d,
      off_d + 44 <= off_i,
      off_i + 44 <= len,
      slice_matches(raw_event, off_d, qb64_aid(cesr_aid)),
      slice_matches(raw_event, off_i, qb64_aid(cesr_aid)),
      blake3.verify(splice_dummies(raw_event, off_i, off_d), cesr_aid),
      entries == [Pair(proof_token_name(raw_event, cesr_aid), 1)],
    }
  }
}
