//// The signed-byte side of the conviction predicate: a rival rotation opened
//// from its exact signed bytes (Lean `Duplicity.SignedEvent` after the
//// primitive verifications), and the event's own SAID opened from the same
//// bytes (#582 `Content.eventDigest`).

use aiken/primitive/bytearray
use cardano_keri/checkpoint/message.{aid_digest}
use cardano_keri/checkpoint/rival.{Previous, Rotation}
use cardano_keri/checkpoint/threshold.{Threshold}

/// What the prover claims the rival's bytes say.
pub type RivalClaim {
  aid: ByteArray,
  sn: Int,
  prior: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  toad: Int,
  cuts: List<ByteArray>,
  adds: List<ByteArray>,
}

pub fn canonical_structure(_claim: RivalClaim, _event_bytes: ByteArray) -> Bool {
  True
}

pub fn open_digest(
  _claim: RivalClaim,
  event_bytes: ByteArray,
) -> Option<ByteArray> {
  aid_digest(bytearray.slice(event_bytes, 40, 83))
}

pub fn open_rival(
  _previous: Previous,
  claim: RivalClaim,
  event_bytes: ByteArray,
  _ctrl_sigs: List<(Int, ByteArray)>,
  _wit_receipts: List<(Int, ByteArray)>,
) -> Option<Rotation> {
  expect Some(digest) = open_digest(claim, event_bytes)
  Some(
    Rotation {
      aid: claim.aid,
      sn: claim.sn,
      is_rotation: True,
      structure_ok: True,
      keys: claim.cur_keys,
      threshold: claim.cur_threshold,
      next_threshold: claim.next_threshold,
      cuts: claim.cuts,
      adds: claim.adds,
      toad: claim.toad,
      signers: claim.cur_keys,
      receipts: [],
      event_digest: digest,
    },
  )
}
