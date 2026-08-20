//// S0 pair-bound proof-token helpers, ported from the M1 hash-proof
//// / registration R5 surface without editing those files.

use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Transaction}

/// keripy SAID dressing for one 44-char qb64 span.
pub const dummy_span: ByteArray = "############################################"

/// `blake2b_256(event_bytes ‖ cesr_aid)` — Cardano label for the pair.
pub fn proof_token_name(
  event_bytes: ByteArray,
  cesr_aid: ByteArray,
) -> ByteArray {
  blake2b_256(bytearray.concat(event_bytes, cesr_aid))
}

/// Bounds-checked slice equality.
pub fn slice_matches(raw: ByteArray, off: Int, expected: ByteArray) -> Bool {
  let n = bytearray.length(expected)
  off >= 0 && off + n <= bytearray.length(raw) && bytearray.take(
    bytearray.drop(raw, off),
    n,
  ) == expected
}

/// Dummy-splice both 44-char SAID spans.
pub fn splice_dummies(
  input_bytes: ByteArray,
  off_i: Int,
  off_d: Int,
) -> ByteArray {
  bytearray.take(input_bytes, off_d)
    |> bytearray.concat(dummy_span)
    |> bytearray.concat(
        input_bytes
          |> bytearray.drop(off_d + 44)
          |> bytearray.take(off_i - off_d - 44),
      )
    |> bytearray.concat(dummy_span)
    |> bytearray.concat(bytearray.drop(input_bytes, off_i + 44))
}

/// True when every mint entry under the policy is a burn.
pub fn all_burns(entries: Pairs<AssetName, Int>) -> Bool {
  when entries is {
    [] -> False
    _ -> list.all(entries, fn(entry) { entry.2nd < 0 })
  }
}

/// Tx-B: some input holds the pair-named token and the mint map is that burn.
pub fn consume_and_burn_proof(
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
  tx: Transaction,
) -> Bool {
  let name = proof_token_name(raw_event, cesr_aid)
  let Transaction { inputs, mint, .. } = tx
  and {
    list.any(
      inputs,
      fn(input) {
        when dict.to_pairs(tokens(input.output.value, proof_policy)) is {
          [Pair(n, q)] -> n == name && q == 1
          _ -> False
        }
      },
    ),
    dict.to_pairs(tokens(mint, proof_policy)) == [Pair(name, -1)],
  }
}
