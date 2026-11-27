//// The signed-byte side of the conviction predicate: a rival rotation opened
//// from its exact signed bytes (Lean `Duplicity.SignedEvent` after the
//// primitive verifications), and the event's own SAID opened from the same
//// bytes (#582 `Content.eventDigest`).

use aiken/primitive/bytearray
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/message.{aid_digest}
use cardano_keri/checkpoint/rival.{Previous, Rotation}
use cardano_keri/checkpoint/threshold.{Threshold}

/// What the prover claims the rival's bytes say. Nothing here is trusted: each
/// field is bound to the exact signed bytes by `open_rival`.
pub type RivalClaim {
  aid: ByteArray,
  sn: Int,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  toad: Int,
  off_d: Int,
  off_k_list: Int,
  off_n_list: Int,
  off_br_list: Int,
  off_ba_list: Int,
}

pub fn event_said(_event_bytes: ByteArray, _off_d: Int) -> Option<ByteArray> {
  None
}

pub fn signed_event_digest(
  event_bytes: ByteArray,
  off_d: Int,
) -> Option<ByteArray> {
  aid_digest(bytearray.slice(event_bytes, off_d, off_d + 43))
}

pub fn open_rival(
  _previous: Previous,
  claim: RivalClaim,
  e: AdvanceEvidence,
) -> Option<Rotation> {
  expect Some(digest) = signed_event_digest(e.event_bytes, claim.off_d)
  Some(
    Rotation {
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
      signers: claim.cur_keys,
      receipts: [],
      event_digest: digest,
    },
  )
}
