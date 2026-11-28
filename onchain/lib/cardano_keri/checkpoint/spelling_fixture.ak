//// The qualified spelling of a fixture's key state: the identifier as an `E` digest and each current key as a `D` key,
//// the way keripy spells the committed inception and rotation events.

use aiken/collection/list
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, KeyMaterial, KeyStateView, Live, TerminationPending,
}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/qualified.{code_d, qualify}
use cardano_keri/checkpoint/registration.{QualifiedSpelling}

/// Raw 32 byte keys as the `D` qualified texts the datum keeps.
pub fn qualified_keys(keys: List<ByteArray>) -> List<ByteArray> {
  list.map(keys, fn(key) { qualify(code_d, key) })
}

/// A version 2 datum with its current keys qualified: the Lean writer vectors spell them as raw 32 byte keys, the
/// December datum keeps the qualified text.
pub fn qualified_datum(d: CheckpointDatumV2) -> CheckpointDatumV2 {
  when d is {
    Live {
      aid,
      sn,
      epoch,
      poisoned,
      frozen,
      born_at,
      refund_to,
      topped_up,
      keys,
    } ->
      Live {
        aid,
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up,
        keys: KeyMaterial { ..keys, cur_keys: qualified_keys(keys.cur_keys) },
      }
    TerminationPending { .. } -> d
  }
}

pub fn of_view(d: KeyStateView) -> QualifiedSpelling {
  QualifiedSpelling {
    aid: qb64_aid(d.cesr_aid),
    cur_keys: list.map(d.cur_keys, fn(key) { qualify(code_d, key) }),
  }
}
