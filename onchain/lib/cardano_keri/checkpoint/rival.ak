//// The conviction predicate of the checkpoint spend: a rival rotation is
//// judged against the commitments of the event before the one that wrote the
//// checkpoint, under the rival's own thresholds and derived witnesses (Lean
//// `Duplicity.rotationValid`, `CheckpointConviction.accepts`).

use cardano_keri/checkpoint/threshold.{Threshold}

/// What the previous establishment committed to (Lean `Predecessor`). The
/// profile is non-delegated, so the delegated flag is not carried.
pub type Previous {
  aid: ByteArray,
  sn: Int,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
}

/// A rival rotation as decoded, with the signatures and receipts that
/// verified over its own signed bytes (Lean `SignedEvent` after the primitive
/// verifications). `event_digest` is the event's own digest.
pub type Rotation {
  aid: ByteArray,
  sn: Int,
  is_rotation: Bool,
  structure_ok: Bool,
  keys: List<ByteArray>,
  threshold: Threshold,
  next_threshold: Threshold,
  cuts: List<ByteArray>,
  adds: List<ByteArray>,
  toad: Int,
  signers: List<ByteArray>,
  receipts: List<ByteArray>,
  event_digest: ByteArray,
}

/// The spent checkpoint's side of a conviction (Lean `Tip`, without the key
/// material whose agreement with the datum is a separate check).
pub type Tip {
  aid: ByteArray,
  epoch: Int,
  sn: Int,
  previous: Option<Previous>,
  writer_digest: ByteArray,
}

pub fn rotation_valid(_previous: Previous, _rival: Rotation) -> Bool {
  True
}

pub fn conviction_accepts(_tip: Tip, _rival: Rotation) -> Bool {
  False
}
