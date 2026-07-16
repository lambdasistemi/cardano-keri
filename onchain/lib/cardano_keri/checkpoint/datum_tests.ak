//// Byte-identity + well-formedness tests for the Aiken `CheckpointDatumV1`
//// codec (#68 Slice 6). Each `cbor.serialise` assert mirrors a frozen
//// `vectors.ak` golden produced by the Slice-2/3 Haskell encoder
//// (`Cardano.KERI.AID.Checkpoint.Datum`) — this file is one half of the
//// cross-language parity proof. Field order (9 datum fields, with the
//// explicit KERI `(next_keys, next_threshold)` pre-rotation pair) and the
//// `V1` wrapper (Constr 0 wrapping the inner Constr 0) are protocol surface;
//// they change only by minting a new version tag. The `datum_well_formed`
//// verdicts mirror the Slice-3 hspec suite one-for-one.

use aiken/cbor
use cardano_keri/checkpoint/datum.{
  CesrAidWidth, CheckpointDatumV1, DatumInvalid, DatumValid, DuplicateWitness,
  NextIllFormed, ThresholdIllFormed, ToadRange, V1, WitnessWidth,
  datum_well_formed,
}
use cardano_keri/checkpoint/threshold.{
  DuplicateKey, EmptyKeys, KeyWidth, Unweighted, UnweightedRange, Weight,
  Weighted,
}
use cardano_keri/checkpoint/vectors

// ---------------------------------------------------------
// Field fixtures (identical to the GenCheckpointVectors.hs inputs)
// ---------------------------------------------------------

const cesr_datum: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const k1: ByteArray =
  #"0101010101010101010101010101010101010101010101010101010101010101"

const k2: ByteArray =
  #"0202020202020202020202020202020202020202020202020202020202020202"

const k3: ByteArray =
  #"0303030303030303030303030303030303030303030303030303030303030303"

const nk1: ByteArray =
  #"0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a"

const w1: ByteArray =
  #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"

const w2: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

const cesr_short: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const k31: ByteArray =
  #"01010101010101010101010101010101010101010101010101010101010101"

// A well-formed baseline datum every negative below perturbs one field of.
fn base(
  cur_keys: List<ByteArray>,
  cur_threshold: threshold.Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
) -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: cesr_datum,
    cur_keys,
    cur_threshold,
    next_keys: [nk1],
    next_threshold: Unweighted(1),
    witnesses,
    toad,
    seq: 0,
    native_sn: 0,
  }
}

// ---------------------------------------------------------
// Datum byte-identity: cbor.serialise(V1(record)) == vectors.const
// ---------------------------------------------------------

test datum_1of1() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1],
        cur_threshold: Unweighted(1),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 0,
        native_sn: 0,
      },
    ),
  ) == vectors.golden_datum_1of1
}

test datum_integer_m_of_n() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2, k3],
        cur_threshold: Unweighted(2),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 7,
      },
    ),
  ) == vectors.golden_datum_integer_m_of_n
}

test datum_weighted() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2],
        cur_threshold: Weighted(
          [[Weight { num: 1, den: 2 }, Weight { num: 1, den: 2 }]],
        ),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 2,
        native_sn: 4,
      },
    ),
  ) == vectors.golden_datum_weighted
}

test datum_multi_clause() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2],
        cur_threshold: Weighted(
          [[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]],
        ),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 1,
        native_sn: 3,
      },
    ),
  ) == vectors.golden_datum_multi_clause
}

test datum_zero_weight() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2],
        cur_threshold: Weighted(
          [[Weight { num: 0, den: 1 }, Weight { num: 1, den: 1 }]],
        ),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 0,
        native_sn: 0,
      },
    ),
  ) == vectors.golden_datum_zero_weight
}

test datum_witnessed() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1],
        cur_threshold: Unweighted(1),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [w1, w2],
        toad: 2,
        seq: 3,
        native_sn: 9,
      },
    ),
  ) == vectors.golden_datum_witnessed
}

test datum_witnessless() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1],
        cur_threshold: Unweighted(1),
        next_keys: [nk1],
        next_threshold: Unweighted(1),
        witnesses: [],
        toad: 0,
        seq: 0,
        native_sn: 0,
      },
    ),
  ) == vectors.golden_datum_witnessless
}

// ---------------------------------------------------------
// datum_well_formed positives (mirrors DatumSpec)
// ---------------------------------------------------------

test wf_witnessless() {
  datum_well_formed(base([k1], Unweighted(1), [], 0)) == DatumValid
}

test wf_witnessed() {
  datum_well_formed(base([k1], Unweighted(1), [w1, w2], 2)) == DatumValid
}

test wf_zero_weight_member() {
  datum_well_formed(
    base(
      [k1, k2],
      Weighted([[Weight { num: 0, den: 1 }, Weight { num: 1, den: 1 }]]),
      [],
      0,
    ),
  ) == DatumValid
}

// ---------------------------------------------------------
// datum_well_formed rule-14 rejections (exact errors)
// ---------------------------------------------------------

test wf_toad_over_witness_count() {
  datum_well_formed(base([k1], Unweighted(1), [w1], 2)) == DatumInvalid(
    ToadRange,
  )
}

test wf_toad_zero_with_witnesses() {
  // KERI bt rule: a witnessed state needs toad >= 1.
  datum_well_formed(base([k1], Unweighted(1), [w1], 0)) == DatumInvalid(
    ToadRange,
  )
}

test wf_toad_nonzero_without_witnesses() {
  datum_well_formed(base([k1], Unweighted(1), [], 1)) == DatumInvalid(ToadRange)
}

test wf_negative_toad() {
  datum_well_formed(base([k1], Unweighted(1), [w1], -1)) == DatumInvalid(
    ToadRange,
  )
}

test wf_duplicate_witness() {
  datum_well_formed(base([k1], Unweighted(1), [w1, w1], 1)) == DatumInvalid(
    DuplicateWitness,
  )
}

test wf_witness_width() {
  datum_well_formed(base([k1], Unweighted(1), [k31], 1)) == DatumInvalid(
    WitnessWidth,
  )
}

// ---------------------------------------------------------
// datum_well_formed primitive-domain widths + delegated F18 checks
// ---------------------------------------------------------

test wf_cesr_aid_width() {
  datum_well_formed(
    CheckpointDatumV1 {
      ..base([k1], Unweighted(1), [], 0),
      cesr_aid: cesr_short,
    },
  ) == DatumInvalid(CesrAidWidth)
}

test wf_cur_key_width() {
  datum_well_formed(base([k31], Unweighted(1), [], 0)) == DatumInvalid(
    ThresholdIllFormed(KeyWidth),
  )
}

test wf_cur_empty_keys() {
  datum_well_formed(base([], Unweighted(1), [], 0)) == DatumInvalid(
    ThresholdIllFormed(EmptyKeys),
  )
}

test wf_cur_duplicate_keys() {
  datum_well_formed(base([k1, k1], Unweighted(1), [], 0)) == DatumInvalid(
    ThresholdIllFormed(DuplicateKey),
  )
}

test wf_next_empty_keys() {
  datum_well_formed(
    CheckpointDatumV1 { ..base([k1], Unweighted(1), [], 0), next_keys: [] },
  ) == DatumInvalid(NextIllFormed(EmptyKeys))
}

test wf_next_key_width() {
  datum_well_formed(
    CheckpointDatumV1 { ..base([k1], Unweighted(1), [], 0), next_keys: [k31] },
  ) == DatumInvalid(NextIllFormed(KeyWidth))
}

test wf_next_threshold_out_of_range() {
  datum_well_formed(
    CheckpointDatumV1 {
      ..base([k1], Unweighted(1), [], 0),
      next_threshold: Unweighted(2),
    },
  ) == DatumInvalid(NextIllFormed(UnweightedRange))
}
