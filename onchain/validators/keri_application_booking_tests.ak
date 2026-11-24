//// A registration is validated when it is booked: the application's mint and
//// spend over bookings that show an inception, and over folds that show none.
////
//// The observation here is the claim of the lifecycle observer's withdrawal and
//// the requests it names; the inception it attests is the observer's own
//// verdict (`keri_application_booking_connected_tests` runs the real observer).
//// Each test name is the Lean row it follows (`lean/application-vectors.json`)
//// where one exists. A refusal is a transaction one defect away from the
//// accepted row beside it.

use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{Action, BookRegistration, SpendAction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/observer.{ObserverClaim, observe_register}
use keri_application
use keri_application_booking_fixture.{
  Observation, booked_entry, booking_claim, booking_payload, bookings_tx,
  observation, observation_with, observed, other_request, unread_evidence,
}
use keri_application_requests as requests
use keri_application_requests.{
  Booking, Fold, booking, booking_tx, fold, fold_tx, reference,
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

fn booked(b: Booking) -> Bool {
  accepts(observed(booking_tx(b), observation([0])))
}

// ---- booking-requires-inception ---------------------------------------------

/// Lean row `booking`: a perfect booking, its inception shown.
test row_booking() {
  booked(booking())
}

/// Lean row `booking-without-inception-evidence`: no observation, refused.
test row_booking_without_inception_evidence() {
  booked(booking()) && !accepts(booking_tx(booking()))
}

/// The observation is the lifecycle observer's: another credential's withdrawal
/// shows no inception.
test a_withdrawal_of_another_credential_is_no_observation() {
  booked(booking()) && !accepts(
    observed(
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
    observed(
      booking_tx(booking()),
      Observation { ..observation([0]), withdrawn: 1 },
    ),
  )
}

// ---- observation-names-its-request ------------------------------------------

/// The claim is the booking claim: the registration claim (action 0) of a
/// checkpoint's own register attests another thing.
test the_registration_claim_is_not_a_booking_claim() {
  booked(booking()) && !accepts(
    observed(
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
    observed(
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
    observed(
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
  booked(booking()) && !accepts(
    observed(booking_tx(booking()), observation([1])),
  )
}

/// An observation that lists no request shows no inception.
test an_observation_listing_no_request_is_refused() {
  booked(booking()) && !accepts(
    observed(booking_tx(booking()), observation([])),
  )
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
    observed(
      booking_tx(booking()),
      Observation { ..observation([0]), payload: unread_evidence() },
    ),
  ) && !accepts(
    observed(
      booking_tx(booking()),
      observation_with([booking_payload([booked_entry(0, unread_evidence())])]),
    ),
  )
}

// ---- booking-initial-state --------------------------------------------------

fn books_request(raw: Int, lovelace: Int) -> Bool {
  accepts(
    observed(
      booking_tx(
        Booking { ..booking(), data: rows.request_data(raw), lovelace },
      ),
      observation([0]),
    ),
  )
}

/// Lean row `booking-advanced-sequence`.
test row_booking_advanced_sequence() {
  booked(booking()) && !books_request(9011, 18)
}

/// Lean row `booking-advanced-epoch`.
test row_booking_advanced_epoch() {
  booked(booking()) && !books_request(9012, 18)
}

/// Lean row `booking-poisoned`.
test row_booking_poisoned() {
  booked(booking()) && !books_request(9013, 18)
}

/// Lean row `booking-frozen`.
test row_booking_frozen() {
  booked(booking()) && !books_request(9014, 18)
}

/// Lean row `booking-topped-up`.
test row_booking_topped_up() {
  booked(booking()) && !books_request(9015, 18)
}

/// Lean row `booking-born-later`.
test row_booking_born_later() {
  booked(booking()) && !books_request(9016, 18)
}

/// Lean row `booking-other-refund`.
test row_booking_other_refund() {
  booked(booking()) && !books_request(9017, 18)
}

/// Lean row `booking-pending-termination`.
test row_booking_pending_termination() {
  booked(booking()) && !books_request(9018, 18)
}

/// Lean row `booking-other-aid`: the datum of another AID than the request's key.
test row_booking_other_aid() {
  booked(booking()) && !books_request(9019, 18)
}

// ---- booking-checks-awaiting-decision ---------------------------------------
// The two refusals the model proposes and the statements list as awaiting a
// decision; built as the model states them.

/// Lean row `booking-pool-below-premium`: a deposit that leaves a pool below one
/// premium (14 against the initial floor 15).
test row_booking_pool_below_premium() {
  booked(booking()) && !books_request(9007, 17)
}

/// Lean row `booking-unrecorded-refund`: a refund address no checkpoint datum
/// can record.
test row_booking_unrecorded_refund() {
  booked(booking()) && !books_request(9008, 18)
}

// ---- fold-reads-no-evidence --------------------------------------------------

fn bare_fold() -> Fold {
  Fold { ..fold(), claim: None }
}

/// Lean row `fold-without-inception-evidence`: a fold carries no observation, no
/// proof; accepted.
test row_fold_without_inception_evidence() {
  accepts(fold_tx(bare_fold()))
}

/// The model does not forbid a fold that still carries an observation: it reads
/// none, so a stray booking claim changes nothing (a question in the statements).
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

// ---- fold-delivers-initial-state --------------------------------------------

/// Lean row `fold-committed-datum-not-initial`: the fold delivers the committed
/// datum, whatever it is: the booking validated it, the fold validates none.
test row_fold_committed_datum_not_initial() {
  accepts(fold_tx(bare_fold())) && accepts(
    fold_tx(
      Fold {
        ..bare_fold(),
        data: rows.request_data(9011),
        holding_datum: rows.variant(1),
      },
    ),
  )
}

/// Lean row `fold-at-committed-other-address`: the fold compares the holding with
/// the address the approval commits and nothing else.
test row_fold_at_committed_other_address() {
  accepts(fold_tx(bare_fold())) && accepts(
    fold_tx(
      Fold {
        ..bare_fold(),
        data: rows.request_data(9004),
        holding_address: rows.other_address,
      },
    ),
  )
}

/// The holding carries the committed datum itself and exactly the deposit: a
/// fold delivering another datum or one lovelace more is refused as before.
test row_fold_other_datum_and_amounts_stay_refused() {
  accepts(fold_tx(bare_fold())) && !accepts(
    fold_tx(Fold { ..bare_fold(), holding_datum: rows.variant(9) }),
  ) && !accepts(fold_tx(Fold { ..bare_fold(), holding_lovelace: 16 })) && !accepts(
    fold_tx(Fold { ..bare_fold(), holding_lovelace: 14 }),
  )
}

// ---- kept-as-main -------------------------------------------------------------

/// The treasury donation of a fold covers the registration cost, as on main.
test row_fold_donation_short_stays_refused() {
  accepts(fold_tx(bare_fold())) && !accepts(
    fold_tx(Fold { ..bare_fold(), donation: 1 }),
  )
}

/// The action list of a booking still books each output once.
test row_booking_twice_stays_refused() {
  booked(booking()) && !accepts(
    observed(
      booking_tx(
        Booking {
          ..booking(),
          actions: [
            BookRegistration { output_index: 0 },
            BookRegistration { output_index: 0 },
          ],
        },
      ),
      observation([0]),
    ),
  )
}
