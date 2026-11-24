//// The two readers of a version 2 checkpoint datum agree.
////
//// A booking decides the initial state of a request's datum with the light
//// reader of `application/inception` (it decodes the codec's own type and keeps the facts it needs; the
//// well-formedness of the keys is the observer's); a checkpoint later reads the same bytes with the codec of
//// `checkpoint/datum`. Every datum vector of the repository (the consumer
//// vectors, which hold the writer's accepted and refused datums and the
//// bytes that are no datum) is run through both, and each falls in one class:
////
//// - both read it as a live datum, and agree on the AID, the sequence number,
////   the epoch, the flags, `born_at`, `refund_to` and the top-up mark;
//// - both read it as a pending termination (the light reader names no live datum);
//// - both refuse it: the light reader names no live datum and the codec aborts
////   (the light reader decodes the codec's own type, key material included);
//// - the bytes are not one whole datum and never reach either reader.
////
//// A vector that moves between classes changes a test here.

use aiken/cbor
use cardano_keri/application/inception.{facts_of}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{Live, TerminationPending}
use cardano_keri/consumer_checkpoint_datum_check.{DatumVector}
use cardano_keri/consumer_checkpoint_datum_vectors as vectors

/// The Data of a vector, when its bytes are one whole Data.
fn raw_of(vector: DatumVector) -> Option<Data> {
  when vector.construction is {
    Some(data) -> Some(data)
    None -> cbor.deserialise(vector.datum)
  }
}

fn raw(vector: DatumVector) -> Data {
  expect Some(data) = raw_of(vector)
  data
}

/// Whether the light reader and the codec read `raw` as the same live facts, or
/// as no live datum (a pending termination) together.
fn agree(raw: Data) -> Bool {
  when (datum.read(raw), facts_of(raw)) is {
    (
      Live {
        aid,
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up,
        ..
      },
      Some(facts),
    ) -> and {
        facts.aid == aid,
        facts.sn == sn,
        facts.epoch == epoch,
        facts.poisoned == poisoned,
        facts.frozen == frozen,
        facts.born_at == born_at,
        facts.refund_to == refund_to,
        facts.topped_up == topped_up,
      }
    (TerminationPending { .. }, None) -> True
    _ -> False
  }
}

// ---- both read it, and agree --------------------------------------------------

test the_readers_agree_on_registered_funded() {
  agree(raw(vectors.vector_registered_funded()))
}

test the_readers_agree_on_registered_juvenile() {
  agree(raw(vectors.vector_registered_juvenile()))
}

test the_readers_agree_on_rotated() {
  agree(raw(vectors.vector_rotated()))
}

test the_readers_agree_on_topped_up() {
  agree(raw(vectors.vector_topped_up()))
}

test the_readers_agree_on_poisoned() {
  agree(raw(vectors.vector_poisoned()))
}

test the_readers_agree_on_frozen() {
  agree(raw(vectors.vector_frozen()))
}

test the_readers_agree_on_large_numbers() {
  agree(raw(vectors.vector_large_numbers()))
}

test the_readers_agree_on_sn_negative() {
  agree(raw(vectors.vector_sn_negative()))
}

test the_readers_agree_on_born_at_negative() {
  agree(raw(vectors.vector_born_at_negative()))
}

test the_readers_agree_on_pending_termination() {
  agree(raw(vectors.vector_pending_termination()))
}

test the_readers_agree_on_pending_negative_epoch() {
  agree(raw(vectors.vector_pending_negative_epoch()))
}

test the_readers_agree_on_the_initial_datums_of_the_rows() {
  agree(rows.initial_datum(0)) && agree(rows.initial_datum(1))
}

test the_readers_agree_on_every_other_state_of_the_rows() {
  and {
    agree(rows.variant(1)),
    agree(rows.variant(2)),
    agree(rows.variant(3)),
    agree(rows.variant(4)),
    agree(rows.variant(5)),
    agree(rows.variant(6)),
    agree(rows.variant(7)),
    agree(rows.variant(8)),
    agree(rows.variant(9)),
  }
}

// ---- both refuse it ------------------------------------------------------------

test the_light_reader_names_no_live_datum_in_version_1() {
  facts_of(raw(vectors.vector_version_1())) == None
}

test the_codec_refuses_version_1() fail {
  datum.read(raw(vectors.vector_version_1())) == datum.read(
    raw(vectors.vector_version_1()),
  )
}

test the_light_reader_names_no_live_datum_in_version_3() {
  facts_of(raw(vectors.vector_version_3())) == None
}

test the_codec_refuses_version_3() fail {
  datum.read(raw(vectors.vector_version_3())) == datum.read(
    raw(vectors.vector_version_3()),
  )
}

test the_light_reader_names_no_live_datum_in_version_no_field() {
  facts_of(raw(vectors.vector_version_no_field())) == None
}

test the_codec_refuses_version_no_field() fail {
  datum.read(raw(vectors.vector_version_no_field())) == datum.read(
    raw(vectors.vector_version_no_field()),
  )
}

test the_light_reader_names_no_live_datum_in_version_two_fields() {
  facts_of(raw(vectors.vector_version_two_fields())) == None
}

test the_codec_refuses_version_two_fields() fail {
  datum.read(raw(vectors.vector_version_two_fields())) == datum.read(
    raw(vectors.vector_version_two_fields()),
  )
}

test the_light_reader_names_no_live_datum_in_unknown_form() {
  facts_of(raw(vectors.vector_unknown_form())) == None
}

test the_codec_refuses_unknown_form() fail {
  datum.read(raw(vectors.vector_unknown_form())) == datum.read(
    raw(vectors.vector_unknown_form()),
  )
}

test the_light_reader_names_no_live_datum_in_live_eight_fields() {
  facts_of(raw(vectors.vector_live_eight_fields())) == None
}

test the_codec_refuses_live_eight_fields() fail {
  datum.read(raw(vectors.vector_live_eight_fields())) == datum.read(
    raw(vectors.vector_live_eight_fields()),
  )
}

test the_light_reader_names_no_live_datum_in_live_without_topped_up() {
  facts_of(raw(vectors.vector_live_without_topped_up())) == None
}

test the_codec_refuses_live_without_topped_up() fail {
  datum.read(raw(vectors.vector_live_without_topped_up())) == datum.read(
    raw(vectors.vector_live_without_topped_up()),
  )
}

test the_light_reader_names_no_live_datum_in_live_ten_fields() {
  facts_of(raw(vectors.vector_live_ten_fields())) == None
}

test the_codec_refuses_live_ten_fields() fail {
  datum.read(raw(vectors.vector_live_ten_fields())) == datum.read(
    raw(vectors.vector_live_ten_fields()),
  )
}

test the_light_reader_names_no_live_datum_in_pending_with_keys() {
  facts_of(raw(vectors.vector_pending_with_keys())) == None
}

test the_codec_refuses_pending_with_keys() fail {
  datum.read(raw(vectors.vector_pending_with_keys())) == datum.read(
    raw(vectors.vector_pending_with_keys()),
  )
}

test the_light_reader_names_no_live_datum_in_aid_integer() {
  facts_of(raw(vectors.vector_aid_integer())) == None
}

test the_codec_refuses_aid_integer() fail {
  datum.read(raw(vectors.vector_aid_integer())) == datum.read(
    raw(vectors.vector_aid_integer()),
  )
}

test the_light_reader_names_no_live_datum_in_epoch_bytes() {
  facts_of(raw(vectors.vector_epoch_bytes())) == None
}

test the_codec_refuses_epoch_bytes() fail {
  datum.read(raw(vectors.vector_epoch_bytes())) == datum.read(
    raw(vectors.vector_epoch_bytes()),
  )
}

test the_light_reader_names_no_live_datum_in_poisoned_not_boolean() {
  facts_of(raw(vectors.vector_poisoned_not_boolean())) == None
}

test the_codec_refuses_poisoned_not_boolean() fail {
  datum.read(raw(vectors.vector_poisoned_not_boolean())) == datum.read(
    raw(vectors.vector_poisoned_not_boolean()),
  )
}

test the_light_reader_names_no_live_datum_in_poisoned_boolean_with_field() {
  facts_of(raw(vectors.vector_poisoned_boolean_with_field())) == None
}

test the_codec_refuses_poisoned_boolean_with_field() fail {
  datum.read(raw(vectors.vector_poisoned_boolean_with_field())) == datum.read(
    raw(vectors.vector_poisoned_boolean_with_field()),
  )
}

test the_light_reader_names_no_live_datum_in_frozen_integer() {
  facts_of(raw(vectors.vector_frozen_integer())) == None
}

test the_codec_refuses_frozen_integer() fail {
  datum.read(raw(vectors.vector_frozen_integer())) == datum.read(
    raw(vectors.vector_frozen_integer()),
  )
}

test the_light_reader_names_no_live_datum_in_refund_integer() {
  facts_of(raw(vectors.vector_refund_integer())) == None
}

test the_codec_refuses_refund_integer() fail {
  datum.read(raw(vectors.vector_refund_integer())) == datum.read(
    raw(vectors.vector_refund_integer()),
  )
}

test the_light_reader_names_no_live_datum_in_topped_up_integer() {
  facts_of(raw(vectors.vector_topped_up_integer())) == None
}

test the_codec_refuses_topped_up_integer() fail {
  datum.read(raw(vectors.vector_topped_up_integer())) == datum.read(
    raw(vectors.vector_topped_up_integer()),
  )
}

test the_light_reader_names_no_live_datum_in_topped_up_not_boolean() {
  facts_of(raw(vectors.vector_topped_up_not_boolean())) == None
}

test the_codec_refuses_topped_up_not_boolean() fail {
  datum.read(raw(vectors.vector_topped_up_not_boolean())) == datum.read(
    raw(vectors.vector_topped_up_not_boolean()),
  )
}

test the_light_reader_names_no_live_datum_in_not_a_constructor() {
  facts_of(raw(vectors.vector_not_a_constructor())) == None
}

test the_codec_refuses_not_a_constructor() fail {
  datum.read(raw(vectors.vector_not_a_constructor())) == datum.read(
    raw(vectors.vector_not_a_constructor()),
  )
}

test the_light_reader_names_no_live_datum_in_keys_list() {
  facts_of(raw(vectors.vector_keys_list())) == None
}

test the_codec_refuses_keys_list() fail {
  datum.read(raw(vectors.vector_keys_list())) == datum.read(
    raw(vectors.vector_keys_list()),
  )
}

test the_light_reader_names_no_live_datum_in_keys_five_fields() {
  facts_of(raw(vectors.vector_keys_five_fields())) == None
}

test the_codec_refuses_keys_five_fields() fail {
  datum.read(raw(vectors.vector_keys_five_fields())) == datum.read(
    raw(vectors.vector_keys_five_fields()),
  )
}

test the_light_reader_names_no_live_datum_in_key_integer() {
  facts_of(raw(vectors.vector_key_integer())) == None
}

test the_codec_refuses_key_integer() fail {
  datum.read(raw(vectors.vector_key_integer())) == datum.read(
    raw(vectors.vector_key_integer()),
  )
}

test the_light_reader_names_no_live_datum_in_threshold_unknown_form() {
  facts_of(raw(vectors.vector_threshold_unknown_form())) == None
}

test the_codec_refuses_threshold_unknown_form() fail {
  datum.read(raw(vectors.vector_threshold_unknown_form())) == datum.read(
    raw(vectors.vector_threshold_unknown_form()),
  )
}

test the_light_reader_names_no_live_datum_in_weight_one_field() {
  facts_of(raw(vectors.vector_weight_one_field())) == None
}

test the_codec_refuses_weight_one_field() fail {
  datum.read(raw(vectors.vector_weight_one_field())) == datum.read(
    raw(vectors.vector_weight_one_field()),
  )
}

test the_light_reader_names_no_live_datum_in_witnesses_map() {
  facts_of(raw(vectors.vector_witnesses_map())) == None
}

test the_codec_refuses_witnesses_map() fail {
  datum.read(raw(vectors.vector_witnesses_map())) == datum.read(
    raw(vectors.vector_witnesses_map()),
  )
}

test the_light_reader_names_no_live_datum_in_toad_bytes() {
  facts_of(raw(vectors.vector_toad_bytes())) == None
}

test the_codec_refuses_toad_bytes() fail {
  datum.read(raw(vectors.vector_toad_bytes())) == datum.read(
    raw(vectors.vector_toad_bytes()),
  )
}

// ---- bytes that are not one whole datum -----------------------------------------

test trailing_byte_is_no_datum_for_either_reader() {
  raw_of(vectors.vector_trailing_byte()) == None
}

test truncated_is_no_datum_for_either_reader() {
  raw_of(vectors.vector_truncated()) == None
}

test empty_is_no_datum_for_either_reader() {
  raw_of(vectors.vector_empty()) == None
}

test break_byte_is_no_datum_for_either_reader() {
  raw_of(vectors.vector_break_byte()) == None
}
