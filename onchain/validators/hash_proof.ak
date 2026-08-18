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
use cardano_keri/checkpoint/event_decoder.{
  DecodeOk, VariantIcp, decode_establishment_event,
}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/registration.{proof_token_name}

/// The Tx-A redeemer: exact event bytes and the raw 32-byte CESR AID.
/// SAID blanking is derived by the total parser.
pub type HashProofRedeemer {
  input_bytes: ByteArray,
  cesr_aid: ByteArray,
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
      let HashProofRedeemer { input_bytes, cesr_aid } = redeemer
      expect bytearray.length(cesr_aid) == 32
      expect DecodeOk(ev) = decode_establishment_event(input_bytes)
      expect ev.variant == VariantIcp
      let expected_span = qb64_aid(cesr_aid)
      expect ev.said == expected_span
      expect ev.aid == expected_span
      expect blake3.verify(ev.said_preimage, cesr_aid)
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
