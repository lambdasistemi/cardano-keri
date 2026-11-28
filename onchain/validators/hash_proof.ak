//// The hash-proof minting policy (the first transaction of a registration).
////
//// Parameter-free. A mint proves, in its own transaction, that the expensive blake3 work binding an inception event to
//// its own digest was done. The event is read by the structural reader from its exact bytes; no position is supplied.
//// The digest `d` is the blake3 of the event with `d` blanked, and with `i` blanked as well when the identifier is
//// itself a digest (keripy's dressing). The redeemer names the raw 32 byte payload of the identifier `i`, whatever its
//// code: for a key identifier it is the key, for a digest identifier it is the digest.
////
//// The token name stays over the FINAL bytes, `proof_token_name(input_bytes, cesr_aid)`, so the registration, which
//// holds the same bytes, recomputes it with one cheap native blake2b. Burning is always permitted: the registration
//// transaction burns the proof.
////
//// Trust note: the policy proves that the event's `d` is its own digest and that the raw payload of its `i` is
//// `cesr_aid`. A fake event over self-authored bytes buys an attacker nothing beyond honest self-registration: the
//// registration still requires the binding to the datum and the controller signatures over the same bytes.

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/own_digest.{proven}
use cardano_keri/checkpoint/registration.{proof_token_name}

/// The redeemer: the FINAL keripy `icp` serialization and the raw 32 byte payload of its identifier.
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
      // H1, H2 — one blake3 chunk: the event's own digest is the blake3 of its dressed preimage and the payload of its
      // identifier is the claimed one.
      expect bytearray.length(cesr_aid) == 32
      expect proven(input_bytes, cesr_aid)
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
