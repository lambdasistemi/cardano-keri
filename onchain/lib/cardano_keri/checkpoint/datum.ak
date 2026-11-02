//// Frozen sovereign per-AID `CheckpointDatumV1` wire codec (#68 Slice 6).
////
//// Mirrors the Slice-3 Haskell `Cardano.KERI.AID.Checkpoint.Datum`
//// byte-for-byte: the `CheckpointDatum` version sum (`V1` = Constr 0 wrapping
//// the inner record) and the 9-field `CheckpointDatumV1` record (Constr 0)
//// encode to the exact canonical Plutus-Data CBOR the Haskell encoder emits
//// (see `vectors.ak`). Constructor indices and field order are protocol
//// surface; they change only by minting a new version tag. The pre-rotation
//// commitment is the explicit `(next_keys, next_threshold)` pair — the KERI
//// `n` digest list plus `nt` — so a rotation may reveal any satisfiable
//// subset of the committed digests (KERI partial/reserve rotation) and
//// restate its own current threshold, exactly as the KERI dual-threshold
//// rule allows.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/checkpoint/threshold.{Invalid, Threshold, ThresholdError}

// ---------------------------------------------------------
// Types (constructor order + field order frozen against vectors.ak)
// ---------------------------------------------------------

/// The frozen sovereign per-AID checkpoint state (Constr 0). The 9 fields are
/// positional and security-significant; reordering changes the bytes.
///
/// - `cesr_aid`: external AID binding (KERI `i`)
/// - `cur_keys`: current establishment key digests (KERI `k`), positional
/// - `cur_threshold`: current signing threshold (KERI `kt`)
/// - `next_keys`: pre-rotation next-key digests (KERI `n`), positional
/// - `next_threshold`: pre-rotation next threshold (KERI `nt`)
/// - `witnesses`: current witness verkeys (KERI `b`), positional
/// - `toad`: witness threshold (KERI `bt`); 0 iff no witnesses, else in [1, len]
/// - `seq`: Cardano checkpoint projection counter; starts 0, +1 per advance
/// - `native_sn`: KERI native sequence number `s` of the reflected est. event
pub type CheckpointDatumV1 {
  cesr_aid: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
  seq: Int,
  native_sn: Int,
}

/// The key material of a version 2 checkpoint (Lean `KeyMaterial`): the
/// version 1 record's key fields, with the same types, in their own record.
pub type KeyMaterial {
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
}

/// The version 2 checkpoint datum (Lean `CheckpointDatumV2`).
pub type CheckpointDatumV2 {
  Live {
    aid: ByteArray,
    sn: Int,
    epoch: Int,
    poisoned: Bool,
    frozen: Bool,
    born_at: Int,
    refund_to: ByteArray,
    keys: KeyMaterial,
  }
  TerminationPending { aid: ByteArray, sn: Int, epoch: Int, keys: KeyMaterial }
}

/// The checkpoint datum version sum. `V1` is constructor index 0 and `V2`
/// index 1; a validator fails closed on a constructor it does not know.
pub type CheckpointDatum {
  V1(CheckpointDatumV1)
  V2(CheckpointDatumV2)
}

// ---------------------------------------------------------
// Datum-level well-formedness (spec rule 14)
// ---------------------------------------------------------

/// A datum-level well-formedness rejection reason (mirrors the Slice-3
/// Haskell `DatumError`).
pub type DatumError {
  /// `cesr_aid` is not exactly 32 bytes.
  CesrAidWidth
  /// The current key set/threshold failed the F18 `well_formed` predicate.
  ThresholdIllFormed(ThresholdError)
  /// The pre-rotation `(next_keys, next_threshold)` pair failed the same
  /// F18 `well_formed` predicate.
  NextIllFormed(ThresholdError)
  /// A witness verkey is not exactly 32 bytes.
  WitnessWidth
  /// The witness set has a duplicate verkey.
  DuplicateWitness
  /// `toad` violates the KERI `bt` rule: `toad == 0` iff `witnesses` is
  /// empty, else `1 <= toad <= len(witnesses)` (rule 14).
  ToadRange
  /// A version 2 `sn` is negative.
  NegativeSn
  /// A version 2 `epoch` is negative.
  NegativeEpoch
  /// A version 2 `born_at` is negative.
  NegativeBornAt
}

/// The datum well-formedness verdict. `DatumValid` ≙ `Right ()`,
/// `DatumInvalid(e)` ≙ `Left e` (mirrors the Slice-3
/// `Either DatumError ()`).
pub type DatumVerdict {
  DatumValid
  DatumInvalid(DatumError)
}

/// Full datum well-formedness. Pins the fixed-width primitive domain
/// (`cesr_aid` exactly 32 bytes) and delegates the key material to
/// `key_material_verdict`. Nothing malformed can serialize past it.
pub fn datum_well_formed(d: CheckpointDatumV1) -> DatumVerdict {
  if bytearray.length(d.cesr_aid) != 32 {
    DatumInvalid(CesrAidWidth)
  } else {
    key_material_verdict(
      d.cur_keys,
      d.cur_threshold,
      d.next_keys,
      d.next_threshold,
      d.witnesses,
      d.toad,
    )
  }
}

/// Write-time validity of a version 2 datum (the Lean leaves it to the
/// writer): the numbers it carries are non-negative and its key material is
/// the version 1 key material rule. No rule on `aid` or `refund_to`.
pub fn datum_v2_well_formed(d: CheckpointDatumV2) -> DatumVerdict {
  when d is {
    Live { sn, epoch, born_at, keys, .. } ->
      if sn < 0 {
        DatumInvalid(NegativeSn)
      } else if epoch < 0 {
        DatumInvalid(NegativeEpoch)
      } else if born_at < 0 {
        DatumInvalid(NegativeBornAt)
      } else {
        keys_verdict(keys)
      }
    TerminationPending { sn, epoch, keys, .. } ->
      if sn < 0 {
        DatumInvalid(NegativeSn)
      } else if epoch < 0 {
        DatumInvalid(NegativeEpoch)
      } else {
        keys_verdict(keys)
      }
  }
}

fn keys_verdict(k: KeyMaterial) -> DatumVerdict {
  key_material_verdict(
    k.cur_keys,
    k.cur_threshold,
    k.next_keys,
    k.next_threshold,
    k.witnesses,
    k.toad,
  )
}

/// The current and next key-set + threshold F18 checks (the Slice-5
/// `well_formed`), then the rule-14 witness/`toad` constraints: witness
/// verkeys exactly 32 bytes, no duplicates.
fn key_material_verdict(
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
) -> DatumVerdict {
  when threshold.well_formed(cur_keys, cur_threshold) is {
    Invalid(e) -> DatumInvalid(ThresholdIllFormed(e))
    _ ->
      when threshold.well_formed(next_keys, next_threshold) is {
        Invalid(e) -> DatumInvalid(NextIllFormed(e))
        _ ->
          if !list.all(witnesses, fn(w) { bytearray.length(w) == 32 }) {
            DatumInvalid(WitnessWidth)
          } else if list.length(list.unique(witnesses)) != list.length(
            witnesses,
          ) {
            DatumInvalid(DuplicateWitness)
          } else if !toad_ok(toad, list.length(witnesses)) {
            DatumInvalid(ToadRange)
          } else {
            DatumValid
          }
      }
  }
}

// KERI bt rule: 0 iff the witness list is empty, else in [1, len].
fn toad_ok(toad: Int, wit_count: Int) -> Bool {
  if wit_count == 0 {
    toad == 0
  } else {
    1 <= toad && toad <= wit_count
  }
}
