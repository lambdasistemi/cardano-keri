//// The inception evidence of a folded key.
////
//// ## Responsibility
//// Realizes the Lean premise `Env.inception data.key`: the folded request's
//// key has its inception evidence. The evidence is the registration
//// observation the checkpoint program asks for at a Register, run over the
//// holding the fold delivers, and bound to the folded key by the AID the
//// holding's datum declares.
////
//// ## Dependencies
//// None beyond the standard library: the observer envelope and the version 2
//// checkpoint datum are read here only as far as the binding needs, with the
//// fields it does not read left as `Data`, so that no decoder for them is
//// compiled into the script.
////
//// ## Assumptions
//// The lifecycle observer's withdrawal validator verifies, for the one output
//// at the claimed checkpoint address, the inception of the AID and keys its
//// datum declares (the hash-proof burn and the registration predicate); it is
//// the same observation `checkpoint_register` requires at a Register. It
//// attests one output at the address per transaction.
////
//// ## Invariants
//// The claim is the registration claim (action `observe_register` = 0, the
//// checkpoint validator's script hash, no spent output); the withdrawal pays
//// no lovelace; the holding's datum is a live version 2 datum whose AID is the
//// request's key.

use aiken/collection/list
use cardano/address.{Address, Credential, Script}
use cardano/transaction.{InlineDatum, Output, Transaction, Withdraw}
use cardano_keri/checkpoint/refund.{ledger_bytes}

/// The stable action tag of the registration claim
/// (`checkpoint/observer.observe_register`).
const observe_register: Int = 0

/// The claim of an observer envelope (`checkpoint/observer.ObserverClaim`):
/// the spent output it names is left undecoded.
type Claim {
  action: Int,
  checkpoint_policy: ByteArray,
  own_ref: Data,
}

/// The envelope the lifecycle observer is called with
/// (`checkpoint/observer.ObserverEnvelope`): the payload is not read.
type Envelope {
  claim: Claim,
  payload: Data,
}

/// A checkpoint datum as `checkpoint/datum` writes it: nothing for version 1,
/// the version 2 datum inside constructor 1. Only the AID of a live datum is
/// read; every other field is left as `Data`.
type Written {
  /// Version 1: nothing to read. Present so that version 2 keeps constructor 1.
  Skipped
  Version2 { datum: Head }
}

type Head {
  Live {
    aid: ByteArray,
    sn: Int,
    epoch: Int,
    poisoned: Bool,
    frozen: Bool,
    born_at: Int,
    refund_to: ByteArray,
    topped_up: Bool,
    keys: Data,
  }
  Pending { aid: ByteArray, sn: Int, epoch: Int }
}

/// The live version 2 checkpoint datum a holding's inline datum is, if it is
/// one: a pending termination, a version 1 datum or another datum is none.
fn live_datum(holding: Output) -> Option<Head> {
  when holding.datum is {
    InlineDatum(raw) ->
      if raw is Version2 { datum }: Written {
        when datum is {
          Live { .. } -> Some(datum)
          Pending { .. } -> None
        }
      } else {
        None
      }
    _ -> None
  }
}

/// The AID a holding's inline datum declares, when it is a live version 2
/// checkpoint datum.
pub fn declared_aid(holding: Output) -> Option<ByteArray> {
  when live_datum(holding) is {
    Some(Live { aid, .. }) -> Some(aid)
    _ -> None
  }
}

/// Model `writesInitialState` (the AID is bound by `inception_attested`): the
/// holding's datum is the live datum of sequence number 0 and epoch 0, neither
/// poisoned, frozen nor topped up, born at the request's booking bound and
/// recording as refund address the ledger bytes of the request's refund address
/// on the chain's network.
pub fn writes_initial_state(
  holding: Output,
  booked_at: Int,
  refund_address: Address,
  network_id: Int,
) -> Bool {
  when (live_datum(holding), ledger_bytes(network_id, refund_address)) is {
    (
      Some(Live {
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up,
        ..
      }),
      Some(refund),
    ) -> and {
        sn == 0,
        epoch == 0,
        !poisoned,
        !frozen,
        !topped_up,
        born_at == booked_at,
        refund_to == refund,
      }
    _ -> False
  }
}

/// Whether `redeemer` is the registration claim for the checkpoint program
/// whose script hash is `checkpoint_hash`: no spent output is named.
fn registration_claim(redeemer: Data, checkpoint_hash: ByteArray) -> Bool {
  let none: Data = None
  if redeemer is Envelope { claim, .. }: Envelope {
    and {
      claim.action == observe_register,
      claim.checkpoint_policy == checkpoint_hash,
      claim.own_ref == none,
    }
  } else {
    False
  }
}

/// Realization of `Env.inception key` for the holding a fold delivers at the
/// checkpoint validator `checkpoint`.
pub fn inception_attested(
  lifecycle_observer: ByteArray,
  checkpoint: Credential,
  holding: Output,
  key: ByteArray,
  tx: Transaction,
) -> Bool {
  when checkpoint is {
    Script(checkpoint_hash) -> {
      let observer: Credential = Script(lifecycle_observer)
      and {
        list.any(
          tx.withdrawals,
          fn(Pair(credential, lovelace)) {
            credential == observer && lovelace == 0
          },
        ),
        list.any(
          tx.redeemers,
          fn(Pair(purpose, redeemer)) {
            when purpose is {
              Withdraw(credential) ->
                credential == observer && registration_claim(
                  redeemer,
                  checkpoint_hash,
                )
              _ -> False
            }
          },
        ),
        declared_aid(holding) == Some(key),
      }
    }
    _ -> False
  }
}
