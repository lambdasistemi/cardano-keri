//// The two readers of a version 2 checkpoint datum agree.
////
//// A booking decides the initial state of a request's datum with the light
//// reader of `application/inception` (the facts it needs, the keys left as
//// `Data`); a checkpoint later reads the same bytes with the codec of
//// `checkpoint/datum`. The row below runs both over every datum vector the
//// repository has, live and pending, initial and not, and requires them to agree
//// on the AID, the sequence number, the epoch, the flags, `born_at` and
//// `refund_to`; a datum of a shape the light reader refuses is refused by the
//// codec too.

use aiken/builtin
use cardano_keri/application/inception.{facts_of}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{CheckpointDatumV2, Live, TerminationPending}
use cardano_keri/checkpoint/datum_v2_vectors as v2

/// Whether the light reader and the codec read `raw` as the same facts, or as no
/// live datum (a pending termination) together.
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

fn agrees_on(vector: CheckpointDatumV2) -> Bool {
  agree(datum.write(vector))
}

test the_readers_agree_on_a_registered_checkpoint() {
  agrees_on(v2.facts_registered_funded()) && agrees_on(
    v2.facts_registered_juvenile(),
  )
}

test the_readers_agree_on_a_rotated_checkpoint() {
  agrees_on(v2.facts_rotated())
}

test the_readers_agree_on_a_topped_up_poisoned_and_frozen_checkpoint() {
  agrees_on(v2.facts_topped_up()) && agrees_on(v2.facts_poisoned()) && agrees_on(
    v2.facts_frozen(),
  )
}

test the_readers_agree_on_large_numbers() {
  agrees_on(v2.facts_large_numbers())
}

test the_readers_agree_on_a_pending_termination() {
  agrees_on(v2.facts_pending_termination())
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

// ---- a shape the light reader refuses is refused by the codec -------------------

/// The retired layout, outer constructor 0.
fn retired() -> Data {
  builtin.constr_data(0, [builtin.i_data(0)])
}

/// A datum of an inner constructor no version knows.
fn unknown_form() -> Data {
  builtin.constr_data(1, [builtin.constr_data(2, [])])
}

/// A live datum one field short.
fn live_without_topped_up() -> Data {
  builtin.constr_data(
    1,
    [
      builtin.constr_data(
        0,
        [
          builtin.b_data(#"01"),
          builtin.i_data(0),
          builtin.i_data(0),
          builtin.constr_data(0, []),
          builtin.constr_data(0, []),
          builtin.i_data(0),
          builtin.b_data(#"01"),
        ],
      ),
    ],
  )
}

test the_light_reader_refuses_the_retired_layout() {
  facts_of(retired()) == None
}

test the_codec_refuses_the_retired_layout() fail {
  datum.read(retired()) == datum.read(retired())
}

test the_light_reader_refuses_an_unknown_form() {
  facts_of(unknown_form()) == None
}

test the_codec_refuses_an_unknown_form() fail {
  datum.read(unknown_form()) == datum.read(unknown_form())
}

test the_light_reader_refuses_a_live_datum_one_field_short() {
  facts_of(live_without_topped_up()) == None
}

test the_codec_refuses_a_live_datum_one_field_short() fail {
  datum.read(live_without_topped_up()) == datum.read(live_without_topped_up())
}
