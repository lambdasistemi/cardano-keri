//// The termination booking and the terminating fold beyond the Lean rows:
//// the treasury a transaction owes when it folds both kinds of request, and
//// the approvals a transaction may mint for bookings of one payload.
////
//// Every transaction is built by `keri_application_requests` from the
//// generated vectors; `accepts` runs the handlers the ledger would run.

use aiken/collection/list
use cardano/assets.{merge}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{
  Action, BookRegistration, BookTermination, FoldTermination, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/row_vectors as rows
use keri_application
use keri_application_requests as requests
use keri_application_requests.{
  Booking, Fold, Termination, TerminationBooking, booking, booking_tx,
  donation_of, fold, fold_tx, termination, termination_booking,
  termination_booking_tx, termination_tx,
}

fn accepts(tx: Transaction) -> Bool {
  requests.accepts(run_mint, run_spend, tx)
}

fn run_mint(actions: List<Action>, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
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
    None,
    action,
    reference,
    tx,
  )
}

// ---- the treasury of a transaction that folds both kinds of request -----------

/// One transaction folding the perfect registration (it owes the registration
/// cost, 2) and the perfect termination request (it owes its lovelace less the
/// tip, 2), donating `donation`.
fn both_folded(donation: Int) -> Transaction {
  let registration = fold_tx(Fold { ..fold(), donation })
  let termination_fold = termination_tx(
    Termination {
      ..termination(),
      key: rows.key_e2,
      redeemer: FoldTermination {
        registry: requests.registry(),
        key: rows.key_e2,
      },
    },
  )
  Transaction {
    ..registration,
    inputs: list.concat(registration.inputs, termination_fold.inputs),
    mint: merge(registration.mint, termination_fold.mint),
    redeemers: list.concat(registration.redeemers, termination_fold.redeemers),
    treasury_donation: donation_of(donation),
  }
}

test a_transaction_folding_both_kinds_donating_their_sum_is_accepted() {
  accepts(both_folded(4))
}

test a_transaction_folding_both_kinds_donating_one_less_than_their_sum_is_refused() {
  !accepts(both_folded(3))
}

test a_transaction_folding_both_kinds_donating_only_the_registration_cost_is_refused() {
  !accepts(both_folded(2))
}

test a_transaction_folding_both_kinds_donating_more_than_their_sum_is_accepted() {
  accepts(both_folded(5))
}

test each_kind_alone_owes_its_own_due() {
  and {
    accepts(fold_tx(Fold { ..fold(), donation: 2 })),
    !accepts(fold_tx(Fold { ..fold(), donation: 1 })),
    accepts(termination_tx(termination())),
    !accepts(termination_tx(Termination { ..termination(), donation: 1 })),
  }
}

// ---- bookings of one payload and the approvals minted for them ------------------

fn book(index: Int) -> Action {
  BookRegistration { output_index: index }
}

fn book_termination(index: Int) -> Action {
  BookTermination {
    pending: requests.pending_reference(),
    output_index: index,
    registry: requests.registry(),
    key: rows.key_e,
  }
}

test two_bookings_of_one_registration_payload_with_one_approval_minted_are_refused() {
  !accepts(
    booking_tx(
      Booking { ..booking(), mint: 1, copies: 2, actions: [book(0), book(1)] },
    ),
  )
}

test one_booking_of_a_registration_payload_with_one_approval_minted_is_accepted() {
  accepts(booking_tx(booking()))
}

test two_bookings_of_one_key_with_one_termination_approval_minted_are_refused() {
  !accepts(
    termination_booking_tx(
      TerminationBooking {
        ..termination_booking(),
        copies: 2,
        booker_lovelace: 0,
        mint: 1,
        actions: [book_termination(0), book_termination(1)],
      },
    ),
  )
}
