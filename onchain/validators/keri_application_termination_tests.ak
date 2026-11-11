//// The termination booking and the terminating fold beyond the Lean rows:
//// the treasury a transaction owes when it folds both kinds of request, and
//// the approvals a transaction may mint for bookings of one payload.
////
//// Every transaction is built by `keri_application_requests` from the
//// generated vectors; `accepts` runs the handlers the ledger would run.

use aiken/builtin
use aiken/collection/list
use cardano/assets.{merge}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{
  Action, BookRegistration, BookTermination, FoldTermination, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/row_vectors as rows
use checkpoint_register
use freeze_fixture.{
  advance_hash, d_reg, enforcement_hash, entitlement_hash, freeze_bond,
  network_id, premium,
}
use keri_application
use keri_application_requests as requests
use keri_application_requests.{
  Booking, Fold, Termination, TerminationBooking, booking, booking_tx,
  donation_of, fold, fold_tx, termination, termination_booking,
  termination_booking_tx, termination_tx,
}
use registry_fixture.{application_policy, registry_name, state_policy}

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

// ---- the treasury of a transaction that folds both kinds of request -----------

/// One transaction folding the perfect registration (it owes the registration
/// cost, 2) and the perfect termination request (it owes its lovelace less the
/// tip, 2), donating `donation`.
fn both_folded(donation: Int) -> Transaction {
  both_folded_with(3, donation)
}

/// The same, with the termination request holding `request` lovelace in place
/// of 3: it then owes `request` less the tip 1, not the registration cost.
fn both_folded_with(request: Int, donation: Int) -> Transaction {
  let registration = fold_tx(Fold { ..fold(), donation })
  let termination_fold = termination_tx(
    Termination {
      ..termination(),
      lovelace: request,
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
    reference_inputs: list.concat(
      registration.reference_inputs,
      termination_fold.reference_inputs,
    ),
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

// ---- the application and the checkpoint validator over one booking ---------------

/// The verdict of the checkpoint validator's `Release` spend of the pending
/// output of the transaction, applied to the scenario's registry and
/// application.
fn released(tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    state_policy(),
    registry_name(),
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    application_policy(),
    None,
    builtin.constr_data(5, []),
    requests.pending_reference(),
    tx,
  )
}

test a_booking_is_accepted_by_the_application_and_releases_the_pending_output() {
  let tx = termination_booking_tx(termination_booking())
  accepts(tx) && released(tx)
}

test a_booking_of_another_key_is_refused_by_both_validators() {
  let tx = termination_booking_tx(
    TerminationBooking {
      ..termination_booking(),
      key: rows.key_e2,
      actions: [
        BookTermination {
          pending: requests.pending_reference(),
          output_index: 0,
          registry: requests.registry(),
          key: rows.key_e2,
        },
      ],
    },
  )
  !accepts(tx) && !released(tx)
}

test the_pending_output_of_a_live_checkpoint_is_released_by_neither() {
  let tx = termination_booking_tx(
    TerminationBooking {
      ..termination_booking(),
      pending_datum: rows.initial_datum(0),
    },
  )
  !accepts(tx) && !released(tx)
}

// ---- the pending output holds the active token and nothing else -------------------

test a_pending_output_holding_another_token_beside_the_active_one_is_refused() {
  !accepts(
    termination_booking_tx(
      TerminationBooking { ..termination_booking(), pending_extra_token: True },
    ),
  )
}

test a_pending_output_holding_another_token_instead_of_the_active_one_is_refused() {
  !accepts(
    termination_booking_tx(
      TerminationBooking {
        ..termination_booking(),
        pending_holds_active: False,
        pending_extra_token: True,
      },
    ),
  )
}

// ---- the due of a terminating fold is its request less the tip, not the registration cost

/// The perfect request holds 3: its due, 2, equals the registration cost. These
/// requests hold other amounts, so the two cannot be mistaken for each other.
fn terminated_holding(lovelace: Int, donation: Int) -> Transaction {
  termination_tx(Termination { ..termination(), lovelace, donation })
}

test a_terminating_fold_donating_its_request_less_the_tip_is_accepted_whatever_the_registration_cost() {
  and {
    accepts(terminated_holding(6, 5)),
    accepts(terminated_holding(1, 0)),
  }
}

test a_terminating_fold_donating_one_less_than_its_request_less_the_tip_is_refused() {
  and {
    !accepts(terminated_holding(6, 4)),
    !accepts(terminated_holding(6, 2)),
  }
}

test a_terminating_fold_of_a_request_below_the_tip_owes_nothing() {
  accepts(terminated_holding(0, 0))
}

test a_mixed_transaction_owes_the_registration_cost_and_the_request_less_the_tip() {
  and {
    accepts(both_folded_with(8, 2 + 7)),
    !accepts(both_folded_with(8, 2 + 6)),
    !accepts(both_folded_with(8, 2 + 2)),
  }
}

test a_request_below_the_tip_does_not_reduce_what_a_registration_fold_owes() {
  and {
    accepts(both_folded_with(0, 2)),
    !accepts(both_folded_with(0, 1)),
  }
}
