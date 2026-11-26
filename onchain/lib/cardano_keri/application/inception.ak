//// The initial state a booked request commits.
////
//// ## Responsibility
//// Realizes the Lean `initialStateDatum`: a request's datum is the live version 2
//// datum of its key at sequence number 0 and epoch 0, neither poisoned, frozen nor
//// topped up, born at the booking bound and recording as refund address the ledger
//// bytes of the request's refund address (`books_initial_state`). That the key has
//// its inception is the attestation minted with the booking
//// (`application/attestation`).
////
//// ## Dependencies
//// `checkpoint/refund` for the ledger bytes of a refund address; the Aiken
//// standard library. The version 2 checkpoint datum is read here only as far as the
//// initial state needs, with the key material read by the codec's own type.
////
//// ## Invariants
//// The datum is read as the checkpoint codec reads it: a datum the codec refuses
//// is no initial state.

use cardano/address.{Address}
use cardano_keri/checkpoint/datum.{CheckpointDatumV2, Live, TerminationPending}
use cardano_keri/checkpoint/refund.{ledger_bytes}

/// A checkpoint datum as `checkpoint/datum` writes it: nothing for version 1,
/// the version 2 datum inside constructor 1. It is the codec's own type, so a datum
/// the codec refuses is no datum here either; only the facts of a live datum are
/// read, and the well-formedness of the key material is the attestation policy's.
type Written {
  /// Version 1: nothing to read. Present so that version 2 keeps constructor 1.
  Skipped
  Version2 { datum: CheckpointDatumV2 }
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

/// The facts of the datum `raw`, when it is a live version 2 checkpoint datum the
/// codec reads: a pending termination, a version 1 datum or another datum has none.
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
      TerminationPending { .. } -> None
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
