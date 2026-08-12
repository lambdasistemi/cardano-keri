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
use cardano_keri/migration/types.{MigrationOrigin, ValidatorVersion}

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

/// The checkpoint datum version sum. `V1` is constructor index 0; a v1-only
/// validator fails closed on an unknown constructor. Serialises as
/// `Constr 0 [<inner CheckpointDatumV1>]`.
pub type CheckpointDatum {
  V1(CheckpointDatumV1)
}

// ---------------------------------------------------------
// Versioned checkpoint state (#254, DAT-254-CHECKPOINT)
// ---------------------------------------------------------

/// The frozen KEL projection wrapped with the deployment metadata the
/// migration family needs (DAT-254-CHECKPOINT).
///
/// `state` is the *same* `CheckpointDatumV1` the v0 family carries, referenced
/// rather than restated: migration metadata must never become KEL state, and a
/// field-by-field copy here would be exactly the lossy alternate
/// representation INV-254-IDENTITY forbids.
///
/// - `validator_version`: the generation of the program that owns this output.
///   A natively registered row carries its applied version and no origin.
/// - `migration_origin`: the *immediate* predecessor this row was migrated
///   from — one step back, never a chain. `None` for a natively created row.
pub type VersionedCheckpoint {
  validator_version: ValidatorVersion,
  migration_origin: Option<MigrationOrigin>,
  state: CheckpointDatumV1,
}

/// The versioned checkpoint datum sum, carried at the ACTIVE and FROZEN
/// addresses exactly as `CheckpointDatum` is in the v0 family. `VersionedV1`
/// is constructor index 0; an unknown constructor fails closed.
///
/// This is a *new* wire type beside `CheckpointDatum`, never a relabelling of
/// it: the deployed v0 rows keep their own encoding and their own program.
pub type VersionedCheckpointDatum {
  VersionedV1(VersionedCheckpoint)
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
}

/// The datum well-formedness verdict. `DatumValid` ≙ `Right ()`,
/// `DatumInvalid(e)` ≙ `Left e` (mirrors the Slice-3
/// `Either DatumError ()`).
pub type DatumVerdict {
  DatumValid
  DatumInvalid(DatumError)
}

/// Full datum well-formedness. Delegates the current and next key-set +
/// threshold F18 checks to the Slice-5 `well_formed`, and additionally pins
/// the fixed-width primitive domains (`cesr_aid`, witness verkeys all exactly
/// 32 bytes) and the rule-14 witness/`toad` constraints. Nothing malformed
/// can serialize past it.
pub fn datum_well_formed(d: CheckpointDatumV1) -> DatumVerdict {
  if bytearray.length(d.cesr_aid) != 32 {
    DatumInvalid(CesrAidWidth)
  } else {
    when threshold.well_formed(d.cur_keys, d.cur_threshold) is {
      Invalid(e) -> DatumInvalid(ThresholdIllFormed(e))
      _ ->
        when threshold.well_formed(d.next_keys, d.next_threshold) is {
          Invalid(e) -> DatumInvalid(NextIllFormed(e))
          _ ->
            if !list.all(d.witnesses, fn(w) { bytearray.length(w) == 32 }) {
              DatumInvalid(WitnessWidth)
            } else if list.length(list.unique(d.witnesses)) != list.length(
              d.witnesses,
            ) {
              DatumInvalid(DuplicateWitness)
            } else if !toad_ok(d.toad, list.length(d.witnesses)) {
              DatumInvalid(ToadRange)
            } else {
              DatumValid
            }
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
