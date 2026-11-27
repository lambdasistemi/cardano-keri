//// The signed-byte side of the conviction predicate: a rival rotation opened
//// from its exact signed bytes (Lean `Duplicity.SignedEvent` after the
//// primitive verifications), and the event's own SAID opened from the same
//// bytes (#582 `Content.eventDigest`).
////
//// The prover claims what the bytes say and where; nothing claimed is trusted.
//// Each field is bound to the bytes by the AE1-AE10 slice binder of the advance
//// (the type, identifier, sequence, keys, thresholds, next keys and the
//// receipt threshold) and, here, each of the four lists (`k`, `n`, `br`, `ba`)
//// is bound whole, bracket to bracket, so that a claim cannot leave out a key
//// or a witness cut that the signed bytes contain. The controller signatures
//// and the witness receipts are verified over the exact bytes; the receipts
//// against the witnesses the rival derives from the previous establishment and
//// its own cuts and additions.
////
//// The event's own digest is the BLAKE3 of the bytes with the 44 characters of
//// its `d` value replaced by `#` (keripy's SAID derivation), accepted only when
//// the `d` value the bytes carry is that digest: a declared digest that is not
//// the digest of the bytes is refused. The rival's own prior digest (`p`) is not
//// compared with any on-chain value, by decision; that is an open limit, not a
//// property (see the ticket's design note).

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/blake3
use cardano_keri/checkpoint/advance.{
  AdvanceEventValid, AdvanceEvidence, event_binding, verified_indices,
}
use cardano_keri/checkpoint/datum.{KeyStateView}
use cardano_keri/checkpoint/message.{qb64_aid, qb64_verkey}
use cardano_keri/checkpoint/registration.{qb64_witness_verkey, slice_matches}
use cardano_keri/checkpoint/rival.{Previous, Rotation, derived_witnesses}
use cardano_keri/checkpoint/threshold.{Threshold}

/// What the prover claims the rival's bytes say. Each field is bound to the
/// exact signed bytes by `open_rival`.
pub type RivalClaim {
  aid: ByteArray,
  sn: Int,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  toad: Int,
  /// Offset of the 44-character value of `d`.
  off_d: Int,
  /// Offsets of the opening bracket of each list.
  off_k_list: Int,
  off_n_list: Int,
  off_br_list: Int,
  off_ba_list: Int,
}

/// keripy's SAID dressing for one 44-character qualified value.
const dummy_span: ByteArray = "############################################"

const hash_limit: Int = 1024

/// The BLAKE3 of the bytes with the `d` value dressed, or none when the bytes
/// are over the hash limit or the span is not inside them.
pub fn event_said(event_bytes: ByteArray, off_d: Int) -> Option<ByteArray> {
  let length = bytearray.length(event_bytes)
  if length > hash_limit || off_d < 0 || off_d + 44 > length {
    None
  } else {
    let blank = bytearray.take(event_bytes, off_d)
      |> bytearray.concat(dummy_span)
      |> bytearray.concat(bytearray.drop(event_bytes, off_d + 44))
    Some(blake3.hash(blank))
  }
}

/// The event's own digest, opened from its bytes: the SAID recomputed from the
/// bytes, accepted only when it is the `d` value the bytes carry.
pub fn signed_event_digest(
  event_bytes: ByteArray,
  off_d: Int,
) -> Option<ByteArray> {
  when event_said(event_bytes, off_d) is {
    None -> None
    Some(digest) ->
      if slice_matches(event_bytes, off_d, qb64_aid(digest)) {
        Some(digest)
      } else {
        None
      }
  }
}

/// The JSON text keripy writes for a list of qualified values.
fn list_text(texts: List<ByteArray>) -> ByteArray {
  bytearray.concat(bytearray.concat("[", quoted(texts)), "]")
}

fn quoted(texts: List<ByteArray>) -> ByteArray {
  when texts is {
    [] -> ""
    [last] -> bytearray.concat(bytearray.concat("\"", last), "\"")
    [first, ..rest] ->
      bytearray.concat(
        bytearray.concat(bytearray.concat("\"", first), "\","),
        quoted(rest),
      )
  }
}

/// The four lists of the rival are the lists of the claim, whole.
fn lists_bound(claim: RivalClaim, e: AdvanceEvidence) -> Bool {
  and {
    slice_matches(
      e.event_bytes,
      claim.off_k_list,
      list_text(list.map(claim.cur_keys, qb64_verkey)),
    ),
    slice_matches(
      e.event_bytes,
      claim.off_n_list,
      list_text(list.map(claim.next_keys, qb64_aid)),
    ),
    slice_matches(
      e.event_bytes,
      claim.off_br_list,
      list_text(list.map(e.wit_cut, qb64_witness_verkey)),
    ),
    slice_matches(
      e.event_bytes,
      claim.off_ba_list,
      list_text(list.map(e.wit_add, qb64_witness_verkey)),
    ),
  }
}

/// The items of `items` at the given positions, in position order.
fn at_positions(items: List<ByteArray>, positions: List<Int>) -> List<ByteArray> {
  list.filter_map(positions, fn(position) { list.at(items, position) })
}

/// A rival opened from its exact signed bytes against the previous
/// establishment it follows: the claim bound to the bytes, the own digest
/// opened from them, the controller signatures verified over them, and the
/// witness receipts verified over them against the derived witnesses. None when
/// any binding fails.
pub fn open_rival(
  previous: Previous,
  claim: RivalClaim,
  e: AdvanceEvidence,
) -> Option<Rotation> {
  let view = KeyStateView {
    cesr_aid: claim.aid,
    cur_keys: claim.cur_keys,
    cur_threshold: claim.cur_threshold,
    next_keys: claim.next_keys,
    next_threshold: claim.next_threshold,
    witnesses: [],
    toad: claim.toad,
    seq: 0,
    native_sn: claim.sn,
  }
  when event_binding(view, e) is {
    AdvanceEventValid ->
      if lists_bound(claim, e) {
        when signed_event_digest(e.event_bytes, claim.off_d) is {
          None -> None
          Some(digest) -> {
            let skeleton = Rotation {
              aid: claim.aid,
              sn: claim.sn,
              is_rotation: True,
              structure_ok: True,
              keys: claim.cur_keys,
              threshold: claim.cur_threshold,
              next_threshold: claim.next_threshold,
              cuts: e.wit_cut,
              adds: e.wit_add,
              toad: claim.toad,
              signers: [],
              receipts: [],
              event_digest: digest,
            }
            let witnesses = derived_witnesses(previous, skeleton)
            Some(
              Rotation {
                ..skeleton,
                signers: at_positions(
                  claim.cur_keys,
                  verified_indices(claim.cur_keys, e.event_bytes, e.ctrl_sigs),
                ),
                receipts: at_positions(
                  witnesses,
                  verified_indices(witnesses, e.event_bytes, e.wit_receipts),
                ),
              },
            )
          }
        }
      } else {
        None
      }
    _ -> None
  }
}
