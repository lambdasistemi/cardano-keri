//// Scratch sizing, shape 1: the advance predicate split into the fact about data
//// (this event is signed by these keys at their threshold, reveals the spent
//// checkpoint's commitments, and is receipted by these witnesses) and the change
//// (the datum transition and the event binding), the second requiring the first's
//// asset in the same mint field.

use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256, verify_ed25519_signature}
use cardano_keri/checkpoint/advance.{
  AdvanceEventValid, AdvanceEvidence, event_binding, verified_indices,
}
use cardano_keri/checkpoint/datum.{
  DatumInvalid, KeyStateView, key_state_well_formed,
}
use cardano_keri/checkpoint/message.{
  SpentCheckpoint, deriveAidAssetName, next_key_digest,
}
use cardano_keri/checkpoint/threshold.{Threshold, evaluate}

/// What the first policy attests: the signed and revealed facts of one event.
pub type SignedFact {
  event_bytes: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
  spent_next_keys: List<ByteArray>,
  spent_next_threshold: Threshold,
  ctrl_sigs: List<(Int, ByteArray)>,
  wit_receipts: List<(Int, ByteArray)>,
}

/// The name of the attestation of those facts: the event by digest and the key
/// states it was checked against.
pub fn fact_name(
  event_bytes: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
  spent_next_keys: List<ByteArray>,
  spent_next_threshold: Threshold,
) -> ByteArray {
  let fact: Data = (
    "cardano-keri/signed/v1",
    blake2b_256(event_bytes),
    cur_keys,
    cur_threshold,
    witnesses,
    toad,
    spent_next_keys,
    spent_next_threshold,
  )
  blake2b_256(builtin.serialise_data(fact))
}

pub fn signed_name(f: SignedFact) -> ByteArray {
  fact_name(
    f.event_bytes,
    f.cur_keys,
    f.cur_threshold,
    f.witnesses,
    f.toad,
    f.spent_next_keys,
    f.spent_next_threshold,
  )
}

fn positions_in(keys: List<ByteArray>, controlled: List<ByteArray>) -> List<Int> {
  list.indexed_foldr(
    keys,
    [],
    fn(i, k, acc) {
      if list.has(controlled, k) {
        [i, ..acc]
      } else {
        acc
      }
    },
  )
}

fn keys_at(keys: List<ByteArray>, positions: List<Int>) -> List<ByteArray> {
  list.indexed_foldr(
    keys,
    [],
    fn(i, k, acc) {
      if list.has(positions, i) {
        [k, ..acc]
      } else {
        acc
      }
    },
  )
}

/// The first policy's check: signatures, current threshold, pre-rotation reveal, receipts.
pub fn signed_ok(f: SignedFact) -> Bool {
  let controlled = keys_at(
    f.cur_keys,
    verified_indices(f.cur_keys, f.event_bytes, f.ctrl_sigs),
  )
  and {
    evaluate(
      f.cur_threshold,
      list.length(f.cur_keys),
      positions_in(f.cur_keys, controlled),
    ),
    evaluate(
      f.spent_next_threshold,
      list.length(f.spent_next_keys),
      positions_in(
        f.spent_next_keys,
        list.map(
          list.filter(controlled, fn(k) { list.has(f.cur_keys, k) }),
          next_key_digest,
        ),
      ),
    ),
    if f.toad == 0 {
      f.wit_receipts == []
    } else {
      list.length(verified_indices(f.witnesses, f.event_bytes, f.wit_receipts)) >= f.toad
    },
  }
}

fn distinct(xs: List<ByteArray>) -> Bool {
  list.length(list.unique(xs)) == list.length(xs)
}

/// The second policy's check: the datum transition (no signatures) and the event binding.
pub fn transition_ok(
  spent: SpentCheckpoint,
  new: KeyStateView,
  e: AdvanceEvidence,
) -> Bool {
  let survivors = list.filter(
    spent.witnesses,
    fn(w) { !list.has(e.wit_cut, w) },
  )
  let new_set = list.concat(survivors, e.wit_add)
  and {
    deriveAidAssetName(new.cesr_aid) == spent.aid_asset_name,
    new.cesr_aid == spent.cesr_aid,
    new.seq == spent.seq + 1,
    new.native_sn > spent.native_sn,
    distinct(e.wit_cut),
    list.all(e.wit_cut, fn(w) { list.has(spent.witnesses, w) }),
    distinct(e.wit_add),
    list.all(e.wit_add, fn(w) { !list.has(e.wit_cut, w) }),
    list.all(e.wit_add, fn(w) { !list.has(survivors, w) }),
    new.witnesses == new_set,
    when key_state_well_formed(new) is {
      DatumInvalid(_) -> False
      _ -> True
    },
    event_binding(new, e) == AdvanceEventValid,
  }
}
