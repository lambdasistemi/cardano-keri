//// The fact policy of the two-policy advance: it attests, for each event named in its redeemer, that the event's
//// bytes are signed by the current keys at the current threshold, reveal the spent checkpoint's committed next keys
//// at their threshold, and are receipted by the witnesses at the witness threshold. The asset name is the digest of
//// that fact. A mint handler only: Burn needs no evidence, every positive own name is verified, every other own name
//// is strictly negative.

use aiken/collection/dict
use aiken/collection/list
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/split.{SignedFact, signed_name, signed_ok}

type Redeemer {
  Issue { facts: List<SignedFact> }
  Burn
}

validator event_attestation(_version: Int) {
  mint(redeemer: Data, policy_id: PolicyId, tx: Transaction) {
    expect action: Redeemer = redeemer
    let own = dict.to_pairs(tokens(tx.mint, policy_id))
    when action is {
      Burn -> list.all(own, fn(Pair(_, quantity)) { quantity < 0 })
      Issue { facts } -> {
        let names = list.map(facts, signed_name)
        and {
          !list.is_empty(facts),
          list.length(list.unique(names)) == list.length(names),
          list.all(facts, signed_ok),
          list.all(
            names,
            fn(name) { quantity_of(tx.mint, policy_id, name) == 1 },
          ),
          list.all(
            own,
            fn(Pair(name, quantity)) {
              if list.has(names, name) {
                True
              } else {
                quantity < 0
              }
            },
          ),
        }
      }
    }
  }

  else(_) {
    fail
  }
}
