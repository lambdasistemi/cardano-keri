//// Byte-identity + well-formedness tests for the Aiken `CheckpointDatumV1`
//// codec (#68 Slice 6). Each `cbor.serialise` assert mirrors a frozen
//// `vectors.ak` golden produced by the Slice-2/3 Haskell encoder
//// (`Cardano.KERI.AID.Checkpoint.Datum`) — this file is one half of the
//// cross-language parity proof. Field order (9 datum fields, with the
//// explicit KERI `(next_keys, next_threshold)` pre-rotation pair) and the
//// `V1` wrapper (Constr 0 wrapping the inner Constr 0) are protocol surface;
//// they change only by minting a new version tag. The `datum_well_formed`
//// verdicts mirror the Slice-3 hspec suite one-for-one.
////
//// The `datum_v2_well_formed` tests below are the write-time validity of the
//// version 2 datum's key material and numbers: one refusal per rule, and the
//// boundaries that must stay accepted. The Lean leaves key validity to the
//// writer (`CardanoKeri.CheckpointDatum`, "Validity"); the version 2 rules are
//// the version 1 rules for the key fields.

use aiken/builtin
use aiken/cbor
use aiken/collection/list
use cardano_keri/checkpoint/datum.{
  CesrAidWidth, CheckpointDatum, CheckpointDatumV1, CheckpointDatumV2,
  DatumInvalid, DatumValid, DuplicateWitness, KeyMaterial, Live, NegativeBornAt,
  NegativeEpoch, NegativeSn, NextIllFormed, TerminationPending,
  ThresholdIllFormed, ToadRange, V1, V2, WitnessWidth, datum_v2_well_formed,
  datum_well_formed,
}
use cardano_keri/checkpoint/datum_v2_vectors as v2_vectors
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

// ---------------------------------------------------------
// Version 2 write-time validity
// ---------------------------------------------------------

fn keys_v2(
  cur_keys: List<ByteArray>,
  cur_threshold: threshold.Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
) -> KeyMaterial {
  KeyMaterial {
    cur_keys,
    cur_threshold,
    next_keys: [nk1],
    next_threshold: Unweighted(1),
    witnesses,
    toad,
  }
}

fn live_v2(keys: KeyMaterial) -> CheckpointDatumV2 {
  Live {
    aid: cesr_datum,
    sn: 0,
    epoch: 0,
    poisoned: False,
    frozen: False,
    born_at: 0,
    refund_to: #"01020304",
    keys,
  }
}

fn pending_v2(keys: KeyMaterial) -> CheckpointDatumV2 {
  TerminationPending { aid: cesr_datum, sn: 0, epoch: 0, keys }
}

fn good_keys() -> KeyMaterial {
  keys_v2([k1], Unweighted(1), [], 0)
}

fn live_numbers(sn: Int, epoch: Int, born_at: Int) -> CheckpointDatumV2 {
  Live {
    aid: cesr_datum,
    sn,
    epoch,
    poisoned: False,
    frozen: False,
    born_at,
    refund_to: #"01020304",
    keys: good_keys(),
  }
}

fn pending_numbers(sn: Int, epoch: Int) -> CheckpointDatumV2 {
  TerminationPending { aid: cesr_datum, sn, epoch, keys: good_keys() }
}

test v2_live_valid() {
  datum_v2_well_formed(live_v2(good_keys())) == DatumValid
}

test v2_pending_valid() {
  datum_v2_well_formed(pending_v2(good_keys())) == DatumValid
}

test v2_witnesses_with_toad_at_count_valid() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1, w2], 2))) == DatumValid
}

test v2_witnesses_with_toad_one_valid() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1, w2], 1))) == DatumValid
}

test v2_cur_empty_keys() {
  datum_v2_well_formed(live_v2(keys_v2([], Unweighted(1), [], 0))) == DatumInvalid(
    ThresholdIllFormed(EmptyKeys),
  )
}

test v2_cur_key_width() {
  datum_v2_well_formed(live_v2(keys_v2([k31], Unweighted(1), [], 0))) == DatumInvalid(
    ThresholdIllFormed(KeyWidth),
  )
}

test v2_cur_duplicate_keys() {
  datum_v2_well_formed(live_v2(keys_v2([k1, k1], Unweighted(1), [], 0))) == DatumInvalid(
    ThresholdIllFormed(DuplicateKey),
  )
}

test v2_cur_threshold_out_of_range() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(2), [], 0))) == DatumInvalid(
    ThresholdIllFormed(UnweightedRange),
  )
}

test v2_next_empty_keys() {
  datum_v2_well_formed(live_v2(KeyMaterial { ..good_keys(), next_keys: [] })) == DatumInvalid(
    NextIllFormed(EmptyKeys),
  )
}

test v2_next_threshold_out_of_range() {
  datum_v2_well_formed(
    live_v2(KeyMaterial { ..good_keys(), next_threshold: Unweighted(2) }),
  ) == DatumInvalid(NextIllFormed(UnweightedRange))
}

test v2_witness_width() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1, k31], 1))) == DatumInvalid(
    WitnessWidth,
  )
}

test v2_duplicate_witness() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1, w1], 1))) == DatumInvalid(
    DuplicateWitness,
  )
}

test v2_toad_zero_with_witnesses() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1], 0))) == DatumInvalid(
    ToadRange,
  )
}

test v2_toad_above_witness_count() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1, w2], 3))) == DatumInvalid(
    ToadRange,
  )
}

test v2_toad_without_witnesses() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [], 1))) == DatumInvalid(
    ToadRange,
  )
}

test v2_toad_negative() {
  datum_v2_well_formed(live_v2(keys_v2([k1], Unweighted(1), [w1], -1))) == DatumInvalid(
    ToadRange,
  )
}

test v2_live_negative_sn() {
  datum_v2_well_formed(live_numbers(-1, 0, 0)) == DatumInvalid(NegativeSn)
}

test v2_live_negative_epoch() {
  datum_v2_well_formed(live_numbers(0, -1, 0)) == DatumInvalid(NegativeEpoch)
}

test v2_live_negative_born_at() {
  datum_v2_well_formed(live_numbers(0, 0, -1)) == DatumInvalid(NegativeBornAt)
}

test v2_pending_negative_sn() {
  datum_v2_well_formed(pending_numbers(-1, 0)) == DatumInvalid(NegativeSn)
}

test v2_pending_negative_epoch() {
  datum_v2_well_formed(pending_numbers(0, -1)) == DatumInvalid(NegativeEpoch)
}

test v2_pending_cur_empty_keys() {
  datum_v2_well_formed(pending_v2(keys_v2([], Unweighted(1), [], 0))) == DatumInvalid(
    ThresholdIllFormed(EmptyKeys),
  )
}

test v2_pending_witness_width() {
  datum_v2_well_formed(pending_v2(keys_v2([k1], Unweighted(1), [k31], 1))) == DatumInvalid(
    WitnessWidth,
  )
}

test v2_pending_toad_range() {
  datum_v2_well_formed(pending_v2(keys_v2([k1], Unweighted(1), [w1], 2))) == DatumInvalid(
    ToadRange,
  )
}

// ---------------------------------------------------------
// A version 1 read refuses a version 2 datum
// ---------------------------------------------------------
//
// Every version 1 read site is an `expect V1(..): CheckpointDatum = data`. The
// version sum gained its second constructor, so the cast must keep refusing a
// datum that carries it: a version 2 datum is not a version 1 datum.

/// The version 2 datums of the accepted Lean vectors, as `Data`.
fn as_data(datum: CheckpointDatum) -> Data {
  let data: Data = datum
  data
}

fn accepted_v2_data() -> List<Data> {
  [
    as_data(V2(v2_vectors.facts_registered_funded())),
    as_data(V2(v2_vectors.facts_registered_juvenile())),
    as_data(V2(v2_vectors.facts_rotated())),
    as_data(V2(v2_vectors.facts_poisoned())),
    as_data(V2(v2_vectors.facts_frozen())),
    as_data(V2(v2_vectors.facts_pending_termination())),
    as_data(V2(v2_vectors.facts_large_numbers())),
  ]
}

fn v1_cast(data: Data) -> CheckpointDatumV1 {
  expect V1(d): CheckpointDatum = data
  d
}

/// Whether the version 1 cast accepts the datum. A refusal test is a `fail` test,
/// which passes when its body errors and also when it evaluates to `False`; so
/// the body must be `True` whenever the cast succeeds.
fn v1_cast_accepts(data: Data) -> Bool {
  let d = v1_cast(data)
  d == d
}

fn v1_datum() -> CheckpointDatumV1 {
  base([k1], Unweighted(1), [], 0)
}

/// Control: the accepted version 2 datums are well-formed `Data` that cast as
/// version 2, so the refusals below are about the version tag alone.
test v2_vectors_cast_as_version_2() {
  list.length(accepted_v2_data()) == 7 && list.all(
    accepted_v2_data(),
    fn(data) {
      expect V2(_): CheckpointDatum = data
      True
    },
  )
}

/// Control: a version 1 datum still casts as version 1, to the same record.
test v1_datum_casts_as_version_1() {
  v1_cast(as_data(V1(v1_datum()))) == v1_datum()
}

test v1_cast_refuses_registered_funded() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_registered_funded())))
}

test v1_cast_refuses_registered_juvenile() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_registered_juvenile())))
}

test v1_cast_refuses_rotated() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_rotated())))
}

test v1_cast_refuses_poisoned() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_poisoned())))
}

test v1_cast_refuses_frozen() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_frozen())))
}

test v1_cast_refuses_pending_termination() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_pending_termination())))
}

test v1_cast_refuses_large_numbers() fail {
  v1_cast_accepts(as_data(V2(v2_vectors.facts_large_numbers())))
}

/// The vectors above differ from a version 1 record in shape as well as in tag.
/// This one isolates the tag: a well-formed version 1 record under the version
/// 2 constructor index is still not a version 1 datum.
test v1_cast_refuses_version_1_record_under_version_2_tag() fail {
  let record = builtin.un_constr_data(as_data(V1(v1_datum()))).2nd
  let tagged: Data = builtin.constr_data(1, record)
  v1_cast_accepts(tagged)
}
