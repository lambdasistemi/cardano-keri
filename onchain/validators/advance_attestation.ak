//// The change policy of the two-policy advance (rotation, freeze and depositing rotation): for each claim named in its
//// redeemer, the spent checkpoint's datum transition to the output at the claimed successor index, with the fact
//// policy's asset at +1 in the same mint field. The asset name is the digest of the claim: action, checkpoint policy,
//// spent reference and successor index. A mint handler only; Burn needs no evidence.

use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/checkpoint/attest.{
  validate_advance_change, validate_freeze_change,
}
use cardano_keri/checkpoint/observer.{
  ObserverEnvelope, observe_advance, observe_freeze,
}

type Claimed {
  tag: ByteArray,
  action: Int,
  checkpoint_policy: PolicyId,
  spent: OutputReference,
  successor_index: Int,
}

type Claim {
  envelope: ObserverEnvelope,
  successor_index: Int,
}

type Redeemer {
  Issue { claims: List<Claim> }
  Burn
}

fn name_of(c: Claim) -> ByteArray {
  let envelope = c.envelope
  expect Some(spent) = envelope.claim.own_ref
  let claim: Data = Claimed {
    tag: "cardano-keri/advance/v1",
    action: envelope.claim.action,
    checkpoint_policy: envelope.claim.checkpoint_policy,
    spent,
    successor_index: c.successor_index,
  }
  blake2b_256(builtin.serialise_data(claim))
}

validator advance_attestation(_version: Int, event_policy: PolicyId) {
  mint(redeemer: Data, policy_id: PolicyId, tx: Transaction) {
    expect action: Redeemer = redeemer
    let own = dict.to_pairs(tokens(tx.mint, policy_id))
    when action is {
      Burn -> list.all(own, fn(Pair(_, quantity)) { quantity < 0 })
      Issue { claims } -> {
        let names = list.map(claims, name_of)
        and {
          !list.is_empty(claims),
          list.length(list.unique(names)) == list.length(names),
          list.all(
            claims,
            fn(c) {
              let envelope = c.envelope
              if envelope.claim.action == observe_freeze {
                validate_freeze_change(
                  event_policy,
                  envelope,
                  c.successor_index,
                  tx,
                )
              } else {
                envelope.claim.action == observe_advance && validate_advance_change(
                  event_policy,
                  envelope,
                  c.successor_index,
                  tx,
                )
              }
            },
          ),
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
