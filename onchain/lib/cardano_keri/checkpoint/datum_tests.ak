//// Well-formedness tests for the Aiken `KeyStateView` and the version 2
//// datum, and the wire tests of the version 2 datum reader and writer. The
//// `key_state_well_formed` verdicts mirror the Haskell `DatumSpec` one-for-one.
////
//// The `datum_v2_well_formed` tests below are the write-time validity of the
//// version 2 datum's key material and numbers: one refusal per rule, and the
//// boundaries that must stay accepted. The Lean leaves key validity to the
//// writer (`CardanoKeri.CheckpointDatum`, "Validity"); the version 2 rules are
//// the key-state rules for the key fields.
////
//// The last section is the outer constructor: `datum.read` accepts exactly
//// constructor index 1 with one field, and refuses index 0.

use aiken/builtin
use aiken/collection/list
use cardano_keri/checkpoint/datum.{
  CesrAidWidth, CheckpointDatumV2, DatumInvalid, DatumValid, DuplicateWitness,
  KeyMaterial, KeyStateView, Live, NegativeBornAt, NegativeEpoch, NegativeSn,
  NextIllFormed, TerminationPending, ThresholdIllFormed, ToadRange, WitnessWidth,
  datum_v2_well_formed, key_state_well_formed,
}
use cardano_keri/checkpoint/datum_v2_vectors as v2_vectors
use cardano_keri/checkpoint/threshold.{
  DuplicateKey, EmptyKeys, KeyWidth, Unweighted, UnweightedRange, Weight,
  Weighted,
}

// ---------------------------------------------------------
// Field fixtures
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
) -> KeyStateView {
  KeyStateView {
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
// key_state_well_formed positives (mirrors DatumSpec)
// ---------------------------------------------------------

test wf_witnessless() {
  key_state_well_formed(base([k1], Unweighted(1), [], 0)) == DatumValid
}

test wf_witnessed() {
  key_state_well_formed(base([k1], Unweighted(1), [w1, w2], 2)) == DatumValid
}

test wf_zero_weight_member() {
  key_state_well_formed(
    base(
      [k1, k2],
      Weighted([[Weight { num: 0, den: 1 }, Weight { num: 1, den: 1 }]]),
      [],
      0,
    ),
  ) == DatumValid
}

// ---------------------------------------------------------
// key_state_well_formed rule-14 rejections (exact errors)
// ---------------------------------------------------------

test wf_toad_over_witness_count() {
  key_state_well_formed(base([k1], Unweighted(1), [w1], 2)) == DatumInvalid(
    ToadRange,
  )
}

test wf_toad_zero_with_witnesses() {
  // KERI bt rule: a witnessed state needs toad >= 1.
  key_state_well_formed(base([k1], Unweighted(1), [w1], 0)) == DatumInvalid(
    ToadRange,
  )
}

test wf_toad_nonzero_without_witnesses() {
  key_state_well_formed(base([k1], Unweighted(1), [], 1)) == DatumInvalid(
    ToadRange,
  )
}

test wf_negative_toad() {
  key_state_well_formed(base([k1], Unweighted(1), [w1], -1)) == DatumInvalid(
    ToadRange,
  )
}

test wf_duplicate_witness() {
  key_state_well_formed(base([k1], Unweighted(1), [w1, w1], 1)) == DatumInvalid(
    DuplicateWitness,
  )
}

test wf_witness_width() {
  key_state_well_formed(base([k1], Unweighted(1), [k31], 1)) == DatumInvalid(
    WitnessWidth,
  )
}

// ---------------------------------------------------------
// key_state_well_formed primitive-domain widths + delegated F18 checks
// ---------------------------------------------------------

test wf_cesr_aid_width() {
  key_state_well_formed(
    KeyStateView { ..base([k1], Unweighted(1), [], 0), cesr_aid: cesr_short },
  ) == DatumInvalid(CesrAidWidth)
}

test wf_cur_key_width() {
  key_state_well_formed(base([k31], Unweighted(1), [], 0)) == DatumInvalid(
    ThresholdIllFormed(KeyWidth),
  )
}

test wf_cur_empty_keys() {
  key_state_well_formed(base([], Unweighted(1), [], 0)) == DatumInvalid(
    ThresholdIllFormed(EmptyKeys),
  )
}

test wf_cur_duplicate_keys() {
  key_state_well_formed(base([k1, k1], Unweighted(1), [], 0)) == DatumInvalid(
    ThresholdIllFormed(DuplicateKey),
  )
}

test wf_next_empty_keys() {
  key_state_well_formed(
    KeyStateView { ..base([k1], Unweighted(1), [], 0), next_keys: [] },
  ) == DatumInvalid(NextIllFormed(EmptyKeys))
}

test wf_next_key_width() {
  key_state_well_formed(
    KeyStateView { ..base([k1], Unweighted(1), [], 0), next_keys: [k31] },
  ) == DatumInvalid(NextIllFormed(KeyWidth))
}

test wf_next_threshold_out_of_range() {
  key_state_well_formed(
    KeyStateView {
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
    topped_up: False,
    keys,
  }
}

fn pending_v2() -> CheckpointDatumV2 {
  TerminationPending { aid: cesr_datum, sn: 0, epoch: 0 }
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
    topped_up: False,
    keys: good_keys(),
  }
}

fn pending_numbers(sn: Int, epoch: Int) -> CheckpointDatumV2 {
  TerminationPending { aid: cesr_datum, sn, epoch }
}

test v2_live_valid() {
  datum_v2_well_formed(live_v2(good_keys())) == DatumValid
}

test v2_pending_valid() {
  datum_v2_well_formed(pending_v2()) == DatumValid
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

// ---------------------------------------------------------
// The outer constructor
// ---------------------------------------------------------
//
// The version 2 datum is `Constr 1 [<datum>]`. The reader refuses every other
// constructor index; the retired layout was index 0.

/// The version 2 datums of the accepted Lean vectors.
fn accepted_v2() -> List<CheckpointDatumV2> {
  [
    v2_vectors.facts_registered_funded(),
    v2_vectors.facts_registered_juvenile(),
    v2_vectors.facts_rotated(),
    v2_vectors.facts_poisoned(),
    v2_vectors.facts_frozen(),
    v2_vectors.facts_pending_termination(),
    v2_vectors.facts_large_numbers(),
  ]
}

/// The same fields under constructor index 0.
fn under_constructor_0(data: Data) -> Data {
  let fields = builtin.un_constr_data(data).2nd
  builtin.constr_data(0, fields)
}

/// Whether the reader accepts the datum. A refusal test is a `fail` test, which
/// passes when its body errors and also when it evaluates to `False`; so the
/// body must be `True` whenever the reader succeeds.
fn read_accepts(data: Data) -> Bool {
  let d = datum.read(data)
  d == d
}

/// Control: the reader returns each accepted vector, and the writer is its
/// inverse, so the refusals below are about the constructor index alone.
test read_returns_what_write_wrote() {
  list.length(accepted_v2()) == 7 && list.all(
    accepted_v2(),
    fn(facts) { datum.read(datum.write(facts)) == facts },
  )
}

test write_uses_constructor_index_1() {
  list.all(
    accepted_v2(),
    fn(facts) { builtin.un_constr_data(datum.write(facts)).1st == 1 },
  )
}

test read_refuses_registered_funded_under_constructor_0() fail {
  read_accepts(
    under_constructor_0(datum.write(v2_vectors.facts_registered_funded())),
  )
}

test read_refuses_registered_juvenile_under_constructor_0() fail {
  read_accepts(
    under_constructor_0(datum.write(v2_vectors.facts_registered_juvenile())),
  )
}

test read_refuses_rotated_under_constructor_0() fail {
  read_accepts(under_constructor_0(datum.write(v2_vectors.facts_rotated())))
}

test read_refuses_poisoned_under_constructor_0() fail {
  read_accepts(under_constructor_0(datum.write(v2_vectors.facts_poisoned())))
}

test read_refuses_frozen_under_constructor_0() fail {
  read_accepts(under_constructor_0(datum.write(v2_vectors.facts_frozen())))
}

test read_refuses_pending_termination_under_constructor_0() fail {
  read_accepts(
    under_constructor_0(datum.write(v2_vectors.facts_pending_termination())),
  )
}

test read_refuses_large_numbers_under_constructor_0() fail {
  read_accepts(
    under_constructor_0(datum.write(v2_vectors.facts_large_numbers())),
  )
}

/// The retired record: the nine-field key state under constructor index 0.
test read_refuses_the_nine_field_record_under_constructor_0() fail {
  let record: Data = base([k1], Unweighted(1), [], 0)
  read_accepts(builtin.constr_data(0, [record]))
}

/// The nine-field record is not a version 2 datum even under index 1.
test read_refuses_the_nine_field_record_under_constructor_1() fail {
  let record: Data = base([k1], Unweighted(1), [], 0)
  read_accepts(builtin.constr_data(1, [record]))
}

/// The datum is the only field.
test read_refuses_a_second_field() fail {
  let inner: Data = v2_vectors.facts_frozen()
  read_accepts(builtin.constr_data(1, [inner, inner]))
}
