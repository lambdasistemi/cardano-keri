//// #114 S4 — the hash-proof minting policy (Tx A of the registration
//// path; spec "The hash-proof minting policy", H1-H4 as amended by the
//// slice-4 Q-001/A-001 ruling).
////
//// Parameter-free. A mint proves, in its own transaction, that the
//// expensive blake3 work binding (input_bytes, cesr_aid) was done: a KERI
//// `E`-code AID is the blake3 digest of the SAID-DUMMIED serialization
//// (keripy dresses the 44-char `i` and `d` value spans with `"#"×44`
//// before digesting), never of the final bytes. H2 therefore (a) pins
//// both spans to `qb64_aid(cesr_aid)` and (b) verifies blake3 over the
//// dummy-spliced blank — equality outside the spans holds by construction
//// of the splice (the #106 shared-check discipline).
////
//// The token name (H3) stays over the FINAL bytes —
//// `proof_token_name(input_bytes, cesr_aid)`, the S3 derivation — which
//// is what lets Tx B's R5 recompute the same name from
//// `evidence.event_bytes` with one cheap native blake2b. No placement
//// constraint: the token is pure existence evidence (spec). Burning is
//// always permitted (H4) — the registration transaction burns the proof.
////
//// Trust note (spec, amended): with prover-supplied spans the policy
//// proves "`cesr_aid` is the SAID of `input_bytes` under the claimed
//// spans". Fake spans over self-authored bytes buy an attacker nothing
//// beyond honest self-registration — Tx B's admission still requires
//// E1-E9 + R4 + R7 threshold signatures over the same bytes.

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/blake3
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/registration.{proof_token_name, slice_matches}

/// keripy's SAID dressing for one 44-char qb64 span: `"#"` × 44.
const dummy_span: ByteArray = "############################################"

/// The Tx-A redeemer: the FINAL keripy `icp` serialization, the raw
/// 32-byte AID digest, and the offsets of the 44-char `i` and `d` value
/// spans inside it (keripy's field order `v,t,d,i,...` is fixed, so the
/// `d` span always precedes the `i` span — H1 encodes that ordering).
pub type HashProofRedeemer {
  input_bytes: ByteArray,
  cesr_aid: ByteArray,
  off_i: Int,
  off_d: Int,
}

/// `input_bytes` with both 44-char spans overwritten by `"#"` × 44 — the
/// SAID blank the AID digest was computed over. Callers must have checked
/// `0 <= off_d`, `off_d + 44 <= off_i`, `off_i + 44 <= len` (H1).
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

// A non-empty mint map whose entries are all strictly negative — the H4
// burn shape. Empty cannot occur on-chain (a policy only runs when it
// appears in the mint map); mapping it to the mint branch fails closed.
fn all_burns(entries: Pairs<AssetName, Int>) -> Bool {
  when entries is {
    [] -> False
    _ -> list.all(entries, fn(entry) { entry.2nd < 0 })
  }
}

validator hash_proof {
  mint(redeemer: HashProofRedeemer, policy_id: PolicyId, tx: Transaction) {
    let entries = dict.to_pairs(tokens(tx.mint, policy_id))
    if all_burns(entries) {
      // H4 — burn branch: burning is always permitted, no other checks
      // (the redeemer content is ignored).
      True
    } else {
      let HashProofRedeemer { input_bytes, cesr_aid, off_i, off_d } = redeemer
      // H1 — one blake3 chunk, 32-byte AID, spans disjoint (d before i,
      // keripy field order) and inside the input.
      let len = bytearray.length(input_bytes)
      expect len <= 1024
      expect bytearray.length(cesr_aid) == 32
      expect 0 <= off_d && off_d + 44 <= off_i && off_i + 44 <= len
      // H2a — both spans hold the qb64 of the claimed AID (an `icp` is
      // self-addressing: d == i).
      let expected_span = qb64_aid(cesr_aid)
      expect slice_matches(input_bytes, off_d, expected_span)
      expect slice_matches(input_bytes, off_i, expected_span)
      // H2b — the SAID binding: blake3 over the dummy-spliced blank.
      expect blake3.verify(splice_dummies(input_bytes, off_i, off_d), cesr_aid)
      // H3 — exactly one entry under this policy: the pair-binding name
      // over the FINAL bytes at quantity one (full-map inspection).
      expect [Pair(minted_name, minted_qty)] = entries
      expect minted_name == proof_token_name(input_bytes, cesr_aid)
      expect minted_qty == 1
      True
    }
  }

  else(_) {
    fail
  }
}
