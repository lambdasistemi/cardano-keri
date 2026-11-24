//// The inception of a booked key and the initial state its request commits.
////
//// ## Responsibility
//// Realizes the Lean premise `Env.inception data.key` for a booking: the
//// transaction that books requests carries one withdrawal of the lifecycle
//// observer whose claim is the booking claim of this application and which lists
//// exactly the requests the transaction books (`bookings_observed`); and the
//// Lean `initialStateDatum`: a request's datum is the live version 2 datum of
//// its key at sequence number 0 and epoch 0, neither poisoned, frozen nor
//// topped up, born at the booking bound and recording as refund address the
//// ledger bytes of the request's refund address (`books_initial_state`).
////
//// ## Dependencies
//// `checkpoint/refund` for the ledger bytes of a refund address; the Aiken
//// standard library. The observer envelope and the version 2 checkpoint datum
//// are read here only as far as the binding needs, with the fields they do not
//// read left as `Data`, so that no decoder for them is compiled into the script.
////
//// ## Assumptions
//// The lifecycle observer's withdrawal validator verifies, for each request the
//// envelope lists, the inception of the AID and keys the request's datum
//// declares (the hash-proof burn and the registration predicate), over the
//// deposit the request commits. It attests the outputs at the application
//// address by their index among the transaction's outputs.
////
//// ## Invariants
//// The claim is the booking claim (action `observe_book` = 5, this application's
//// policy, no spent output); the withdrawal pays no lovelace; the indices the
//// payload lists are distinct and are exactly the outputs the transaction books.

use aiken/collection/list
use cardano/address.{Address, Credential, Script}
use cardano/transaction.{Transaction, Withdraw}
use cardano_keri/checkpoint/refund.{ledger_bytes}

/// The stable action tag of the booking claim (`checkpoint/observer.observe_book`).
const observe_book: Int = 5

/// The claim of an observer envelope (`checkpoint/observer.ObserverClaim`):
/// the spent output it names is left undecoded.
type Claim {
  action: Int,
  checkpoint_policy: ByteArray,
  own_ref: Data,
}

/// The envelope the lifecycle observer is called with
/// (`checkpoint/observer.ObserverEnvelope`).
type Envelope {
  claim: Claim,
  payload: Data,
}

/// The payload of the booking claim (`checkpoint/observer.BookingEvidence`): the
/// evidence of each request is not read.
type Booked {
  requests: List<Listed>,
}

type Listed {
  request_index: Int,
  evidence: Data,
}

/// A checkpoint datum as `checkpoint/datum` writes it: nothing for version 1,
/// the version 2 datum inside constructor 1. Only the facts of a live datum are
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

/// The facts of a live version 2 checkpoint datum that the initial state fixes.
pub type Facts {
  aid: ByteArray,
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
  topped_up: Bool,
}

/// The facts of the datum `raw`, when it is a live version 2 checkpoint datum: a
/// pending termination, a version 1 datum or another datum has none.
pub fn facts_of(raw: Data) -> Option<Facts> {
  if raw is Version2 { datum }: Written {
    when datum is {
      Live {
        aid,
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up,
        ..
      } ->
        Some(
          Facts {
            aid,
            sn,
            epoch,
            poisoned,
            frozen,
            born_at,
            refund_to,
            topped_up,
          },
        )
      Pending { .. } -> None
    }
  } else {
    None
  }
}

/// Model `initialStateDatum`: the request's datum is the live datum of its key at
/// sequence number 0 and epoch 0, neither poisoned, frozen nor topped up, born at
/// the request's booking bound and recording as refund address the ledger bytes
/// of the request's refund address on the chain's network. The pool, the one fact
/// that is not in the datum, is the deposit against the initial floor.
pub fn books_initial_state(
  raw: Data,
  key: ByteArray,
  booked_at: Int,
  refund_address: Address,
  network_id: Int,
) -> Bool {
  when (facts_of(raw), ledger_bytes(network_id, refund_address)) is {
    (Some(facts), Some(refund)) -> and {
        facts.aid == key,
        facts.sn == 0,
        facts.epoch == 0,
        !facts.poisoned,
        !facts.frozen,
        !facts.topped_up,
        facts.born_at == booked_at,
        facts.refund_to == refund,
      }
    _ -> False
  }
}

/// Whether the transaction carries the lifecycle observer's withdrawal with the
/// booking claim of `application_policy`, listing exactly the outputs at
/// `booked` (the index of each booking action), once each.
pub fn bookings_observed(
  lifecycle_observer: ByteArray,
  application_policy: ByteArray,
  booked: List<Int>,
  tx: Transaction,
) -> Bool {
  if list.is_empty(booked) {
    True
  } else {
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
              credential == observer && names_exactly(
                redeemer,
                application_policy,
                booked,
              )
            _ -> False
          }
        },
      ),
    }
  }
}

/// Whether `redeemer` is the booking claim of the application whose payload
/// lists each index of `booked` once and nothing else: as many entries as there
/// are bookings, each booking among them (the bookings are distinct, so no entry
/// repeats and none names another output).
fn names_exactly(
  redeemer: Data,
  application_policy: ByteArray,
  booked: List<Int>,
) -> Bool {
  let none: Data = None
  if redeemer is Envelope { claim, payload }: Envelope {
    and {
      claim.action == observe_book,
      claim.checkpoint_policy == application_policy,
      claim.own_ref == none,
      if payload is Booked { requests }: Booked {
        let listed = list.map(requests, fn(entry) { entry.request_index })
        and {
          list.length(listed) == list.length(booked),
          list.all(booked, fn(index) { list.has(listed, index) }),
        }
      } else {
        False
      },
    }
  } else {
    False
  }
}
