//// Frozen sovereign per-AID `CheckpointDatumV1` wire codec (#68 Slice 6).
////
//// Mirrors the Slice-3 Haskell `Cardano.KERI.AID.Checkpoint.Datum`
//// byte-for-byte: the `CheckpointDatum` version sum (`V1` = Constr 0 wrapping
//// the inner record), the 8-field `CheckpointDatumV1` record (Constr 0), and
//// the `NextCommitment` pre-rotation commitment preimage (Constr 0) encode to
//// the exact canonical Plutus-Data CBOR the Haskell encoder emits (see
//// `vectors.ak`). Constructor indices and field order are protocol surface;
//// they change only by minting a new version tag. `next_digest` commits the
//// next keys AND next threshold via `keyset_commit` = `blake2b_256` of the
//// canonical CBOR.

use aiken/cbor
use aiken/crypto
use cardano_keri/checkpoint/threshold.{Threshold}

// ---------------------------------------------------------
// Types (constructor order + field order frozen against vectors.ak)
// ---------------------------------------------------------

/// The frozen sovereign per-AID checkpoint state (Constr 0). The 8 fields are
/// positional and security-significant; reordering changes the bytes.
///
/// - `cesr_aid`: external AID binding (KERI `i`)
/// - `cur_keys`: current establishment key digests (KERI `k`), positional
/// - `cur_threshold`: current signing threshold (KERI `kt`)
/// - `next_digest`: pre-rotation commitment — `keyset_commit` over `(n, nt)`
/// - `witnesses`: current witness verkeys (KERI `b`), positional
/// - `toad`: witness threshold (KERI `bt`); `0 <= toad <= len(witnesses)`
/// - `seq`: Cardano checkpoint projection counter; starts 0, +1 per advance
/// - `native_sn`: KERI native sequence number `s` of the reflected est. event
pub type CheckpointDatumV1 {
  cesr_aid: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_digest: ByteArray,
  witnesses: List<ByteArray>,
  toad: Int,
  seq: Int,
  native_sn: Int,
}

/// The checkpoint datum version sum. `V1` is constructor index 0; a v1-only
/// validator fails closed on an unknown constructor. Serialises as
/// `Constr 0 [<inner CheckpointDatumV1>]`.
pub type CheckpointDatum {
  V1(CheckpointDatumV1)
}

/// The pre-rotation next-key commitment preimage (Constr 0): the next keys and
/// next threshold whose `keyset_commit` is stored as `next_digest`.
pub type NextCommitment {
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
}

// ---------------------------------------------------------
// Canonical serialization commitments
// ---------------------------------------------------------

/// `keyset_commit(c) = blake2b_256(canonical_cbor(c))` — binds the next (or,
/// in the advance message, the revealed successor) key-state. `cbor.serialise`
/// emits the same canonical Plutus-Data bytes the Haskell `serialiseData`
/// encoder produces.
pub fn keyset_commit(nc: NextCommitment) -> ByteArray {
  crypto.blake2b_256(cbor.serialise(nc))
}

/// `next_digest = keyset_commit(NextCommitment next_keys next_threshold)`.
pub fn next_digest(nk: List<ByteArray>, nt: Threshold) -> ByteArray {
  keyset_commit(NextCommitment { next_keys: nk, next_threshold: nt })
}
