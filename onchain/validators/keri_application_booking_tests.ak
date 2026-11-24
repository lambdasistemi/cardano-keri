//// A registration is validated when it is booked: the application's mint and
//// spend over bookings that show an inception, and over folds that show none.
////
//// The observation here is the claim of the lifecycle observer's withdrawal and
//// the requests it names; the inception it attests is the observer's own
//// verdict (`keri_application_booking_connected_tests` runs the real observer).
//// The rows of the Lean vectors are in the generated `keri_application_rows_tests`;
//// the tests here are the requirements the rows do not state: what the booking's
//// observation must name, and what a fold may carry. A refusal is a transaction
//// one difference away from the accepted one beside it.

use aiken/cbor
use aiken/collection/list
use cardano/address.{Script}
use cardano/transaction.{OutputReference, Transaction, Withdraw}
use cardano_keri/application/action.{Action, BookRegistration, SpendAction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/observer.{
  BookedRequest, BookingEvidence, ObserverClaim, ObserverEnvelope, observe_book,
  observe_register,
}
use cardano_keri/checkpoint/registration.{RegistrationEvidence}
use keri_application
use keri_application_booking_fixture.{
  Observation, bookings_tx, observation, observation_with, observed,
  other_request, requests_tx, unobserved,
}
use keri_application_requests as requests
use keri_application_requests.{
  Booking, Fold, booked_entry, booking, booking_claim, booking_payload,
  booking_tx, envelope, fold, fold_tx, payload_of, reference, unread_evidence,
}

fn run_mint(actions: List<Action>, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    rows.checkpoint_minimum_ada,
    rows.termination_carrier,
    actions,
    requests.application(),
    tx,
  )
}

fn run_spend(
  action: SpendAction,
  reference: OutputReference,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.spend(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    rows.checkpoint_minimum_ada,
    rows.termination_carrier,
    None,
    action,
    reference,
    tx,
  )
}

/// Whether every handler the ledger would run over `tx` accepts.
fn accepts(tx: Transaction) -> Bool {
  requests.accepts(run_mint, run_spend, tx)
}

/// The transaction with only the observation given.
fn shown(tx: Transaction, o: Observation) -> Transaction {
  observed(unobserved(tx), o)
}

fn booked(b: Booking) -> Bool {
  accepts(shown(booking_tx(b), observation([0])))
}

// ---- booking-requires-inception ---------------------------------------------

/// The observation is the lifecycle observer's: another credential's withdrawal
/// shows no inception.
test a_withdrawal_of_another_credential_is_no_observation() {
  booked(booking()) && !accepts(
    shown(
      booking_tx(booking()),
      Observation {
        ..observation([0]),
        credential: #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
      },
    ),
  )
}

/// The withdrawal pays nothing.
test a_withdrawal_paying_lovelace_is_no_observation() {
  booked(booking()) && !accepts(
    shown(
      booking_tx(booking()),
      Observation { ..observation([0]), withdrawn: 1 },
    ),
  )
}

/// The observer's redeemer is an envelope: any other Data is no observation.
test a_redeemer_that_is_not_an_envelope_is_no_observation() {
  let tx = booking_tx(booking())
  booked(booking()) && !accepts(
    Transaction {
      ..tx,
      redeemers: list.map(
        tx.redeemers,
        fn(Pair(purpose, redeemer)) {
          when purpose is {
            Withdraw(_) -> Pair(purpose, unread_evidence())
            _ -> Pair(purpose, redeemer)
          }
        },
      ),
    },
  )
}

/// The observer's own withdrawal carries a claim for another application while
/// another script's withdrawal carries the right claim: the observation that ran
/// is not the one the booking needs.
test a_claim_carried_by_another_withdrawal_does_not_attest() {
  let tx = unobserved(booking_tx(booking()))
  let other = Script(
    #"0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425",
  )
  let wrong = ObserverClaim {
    ..booking_claim(),
    checkpoint_policy: rows.observer_hash,
  }
  booked(booking()) && !accepts(
    Transaction {
      ..tx,
      withdrawals: [Pair(Script(rows.observer_hash), 0), Pair(other, 0)],
      redeemers: list.concat(
        tx.redeemers,
        [
          Pair(
            Withdraw(Script(rows.observer_hash)),
            envelope(wrong, payload_of([0])),
          ),
          Pair(Withdraw(other), envelope(booking_claim(), payload_of([0]))),
        ],
      ),
    },
  )
}

// ---- observation-names-its-request ------------------------------------------

/// The claim is the booking claim: the registration claim (action 0) of a
/// checkpoint's own register attests another thing.
test the_registration_claim_is_not_a_booking_claim() {
  booked(booking()) && !accepts(
    shown(
      booking_tx(booking()),
      Observation {
        ..observation([0]),
        claim: ObserverClaim { ..booking_claim(), action: observe_register },
      },
    ),
  )
}

/// The claim names this application: an observation of requests at another
/// script attests nothing here.
test a_claim_naming_another_application_is_no_observation() {
  booked(booking()) && !accepts(
    shown(
      booking_tx(booking()),
      Observation {
        ..observation([0]),
        claim: ObserverClaim {
          ..booking_claim(),
          checkpoint_policy: rows.observer_hash,
        },
      },
    ),
  )
}

/// A booking spends no output of the observer's: the claim names none.
test a_claim_naming_a_spent_output_is_no_observation() {
  booked(booking()) && !accepts(
    shown(
      booking_tx(booking()),
      Observation {
        ..observation([0]),
        claim: ObserverClaim { ..booking_claim(), own_ref: Some(reference(60)) },
      },
    ),
  )
}

/// An observation over one request beside the mint of another is refused: the
/// request the observation lists is not the one the mint books.
test an_observation_of_another_request_is_refused() {
  booked(booking()) && !accepts(shown(booking_tx(booking()), observation([1])))
}

/// An observation that lists no request shows no inception.
test an_observation_listing_no_request_is_refused() {
  booked(booking()) && !accepts(shown(booking_tx(booking()), observation([])))
}

/// One withdrawal carries every request the transaction books: both listed,
/// in either order, accepted.
test two_bookings_with_evidence_for_both_are_accepted() {
  let tx = bookings_tx([(rows.request_data(9001), 18), (other_request(), 18)])
  accepts(observed(tx, observation([0, 1]))) && accepts(
    observed(tx, observation([1, 0])),
  )
}

/// Two bookings with evidence for one of them: the other shows no inception.
test two_bookings_with_evidence_for_one_are_refused() {
  let tx = bookings_tx([(rows.request_data(9001), 18), (other_request(), 18)])
  accepts(observed(tx, observation([0, 1]))) && !accepts(
    observed(tx, observation([0])),
  ) && !accepts(observed(tx, observation([1])))
}

/// Two requests of the application sit among the outputs and the transaction books
/// one of them: the observation lists the request the booking names, not the other.
/// Each refusal is the accepted neighbour with one index changed, so a mint that
/// only counted the entries or only checked that the outputs they name exist
/// would accept them.
test an_observation_names_the_request_the_booking_books() {
  let two = [(rows.request_data(9001), 18), (other_request(), 18)]
  let first = requests_tx(two, [0])
  let second = requests_tx(two, [1])
  accepts(shown(first, observation([0]))) && !accepts(
    shown(first, observation([1])),
  ) && accepts(shown(second, observation([1]))) && !accepts(
    shown(second, observation([0])),
  )
}

/// The other request is real but no booking of the transaction names it: listing
/// it beside the booked one is refused, as is listing it alone; with both booked,
/// listing both is accepted and listing either alone is refused.
test an_observation_listing_a_second_real_request_no_booking_names_is_refused() {
  let two = [(rows.request_data(9001), 18), (other_request(), 18)]
  let one = requests_tx(two, [0])
  let both = requests_tx(two, [0, 1])
  accepts(shown(one, observation([0]))) && !accepts(
    shown(one, observation([0, 1])),
  ) && accepts(shown(both, observation([0, 1]))) && !accepts(
    shown(both, observation([0])),
  ) && !accepts(shown(both, observation([1])))
}

/// An entry no booking names is refused: the observation certifies exactly what
/// the transaction books.
test an_entry_no_booking_names_is_refused() {
  let tx = bookings_tx([(rows.request_data(9001), 18)])
  accepts(observed(tx, observation([0]))) && !accepts(
    observed(tx, observation([0, 1])),
  )
}

/// The indices are distinct: one request cannot be attested twice.
test a_request_listed_twice_is_refused() {
  let tx = bookings_tx([(rows.request_data(9001), 18), (other_request(), 18)])
  accepts(observed(tx, observation([0, 1]))) && !accepts(
    observed(tx, observation([0, 0, 1])),
  )
}

/// A payload that is not a list of entries is no observation.
test a_payload_that_is_not_the_booking_evidence_is_refused() {
  booked(booking()) && !accepts(
    shown(
      booking_tx(booking()),
      Observation { ..observation([0]), payload: unread_evidence() },
    ),
  ) && !accepts(
    shown(
      booking_tx(booking()),
      observation_with([booking_payload([booked_entry(0, unread_evidence())])]),
    ),
  )
}

// ---- fold-reads-no-evidence --------------------------------------------------

fn bare_fold() -> Fold {
  Fold { ..fold(), claim: None }
}

/// The model does not forbid a fold that still carries an observation: it reads
/// none, so a stray booking claim changes nothing.
test a_fold_carrying_a_stray_observation_is_accepted() {
  accepts(fold_tx(bare_fold())) && accepts(
    fold_tx(
      Fold {
        ..bare_fold(),
        claim: Some(booking_claim()),
        payload: booking_payload([booked_entry(0, unread_evidence())]),
      },
    ),
  )
}

// ---- the wire: the Haskell encoder and the validator read the same bytes -----------

/// The evidence of the first wire request, field for field the one the Haskell wire
/// specification builds (`Cardano.KERI.AID.Checkpoint.WireSpec`).
fn wire_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    event_bytes: "icp",
    off_t: 1,
    off_i: 2,
    off_s: 3,
    off_k: [4],
    off_kt: 5,
    off_n: [6],
    off_nt: 7,
    off_b: [8],
    off_bt: 9,
    ctrl_sigs: [
      (
        0,
        #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1",
      ),
    ],
    wit_receipts: [
      (
        1,
        #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1",
      ),
    ],
  }
}

/// The evidence of the second wire request: every field differs from the first's, so
/// an encoder that attached evidence to the wrong request changes the bytes.
fn other_wire_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    event_bytes: "icq",
    off_t: 11,
    off_i: 12,
    off_s: 13,
    off_k: [14, 15],
    off_kt: 16,
    off_n: [17],
    off_nt: 18,
    off_b: [],
    off_bt: 19,
    ctrl_sigs: [
      (
        1,
        #"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2",
      ),
      (
        2,
        #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
      ),
    ],
    wit_receipts: [],
  }
}

/// The booking envelope of the application policy `c0..c0` listing the request at
/// output 3 with the first evidence and the request at output 5 with the second, in
/// the types of the code under test.
fn wire_envelope() -> Data {
  let envelope: Data = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_book,
      checkpoint_policy: #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0",
      own_ref: None,
    },
    payload: BookingEvidence {
      requests: [
        BookedRequest { request_index: 3, evidence: wire_evidence() },
        BookedRequest { request_index: 5, evidence: other_wire_evidence() },
      ],
    },
  }
  envelope
}

/// The bytes the Haskell encoder `bookingObserverRedeemerData` must produce for
/// the same envelope (`WireSpec` asserts the same string).
test the_booking_envelope_has_the_bytes_the_haskell_encoder_writes() {
  cbor.serialise(wire_envelope()) == #"d8799fd8799f05581cc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0d87a80ffd8799f9fd8799f03d8799f436963700102039f04ff059f06ff079f08ff099f9f005840a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1ffff9f9f015840b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1ffffffffd8799f05d8799f436963710b0c0d9f0e0fff109f11ff1280139f9f015840a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2ff9f025840b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2ffff80ffffffffff"
}

/// The payload these tests build as raw Data is the one the code under test reads.
test the_fixtures_payload_is_the_payload_the_observer_decodes() {
  let evidence: Data = wire_evidence()
  let typed: Data = BookingEvidence {
    requests: [BookedRequest { request_index: 3, evidence: wire_evidence() }],
  }
  booking_payload([booked_entry(3, evidence)]) == typed
}
