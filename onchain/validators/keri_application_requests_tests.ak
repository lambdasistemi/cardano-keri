//// The application validator over booking, request spend, fold, return and
//// the pending termination: one refusal per guard of the Lean
//// `bookRegistration`, `spendRegistration`, `spendTermination`, the money a
//// transaction moves, the inputs it spends and the mint it makes.
////
//// Every refusal is one change to a perfect transaction the same handlers
//// accept (the control is asserted in the same test), every value derived from
//// the changed fact is recomputed by the fixture with the public Singular
//// functions, and the verdict is `False`, never a crash. The Lean rows
//// themselves are in `keri_application_rows_tests` (generated).
////
//// Layers: these hand-built transactions run the validator's handlers; the
//// generated rows run the same handlers on the Lean's scenarios; the
//// off-chain builders and the devnet journey follow this slice.

use aiken/builtin
use aiken/collection/list
use aiken/interval.{
  Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity,
}
use aiken/primitive/bytearray
use cardano/address.{Address, Inline, Script, VerificationKey, from_script}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, Mint, NoDatum, Output, OutputReference, Spend,
  Transaction, Withdraw,
}
use cardano_keri/application/action.{
  Action, BookRegistration, CreateConfiguration, FoldRegistration,
  FoldTermination, ReturnRegistration, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{Configuration, RegistrationData}
use cardano_keri/application/registration.{registration_approval}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{Live}
use keri_application
use keri_application_fixture.{template_input}
use keri_application_requests.{
  Booking, Fold, Return, Termination, active_of, app_address, application,
  approval_of, booking, booking_claim, booking_tx, checkpoint_address,
  checkpoint_spend, config_input, config_output, envelope, fold, fold_tx,
  foreign_registry, holding_output, mint_of, payload_of, pending_output, range,
  reference, registry, request_input, request_output, returned, termination,
  termination_approval_of, termination_tx,
}
use singular_state/preimage.{
  RegistryIdentity, active_token_name, configuration_token_name,
}

// ---- the handlers ---------------------------------------------------------------

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
    application(),
    tx,
  )
}

fn run_spend(
  action: SpendAction,
  input: OutputReference,
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
    input,
    tx,
  )
}

fn accepts(tx: Transaction) -> Bool {
  keri_application_requests.accepts(run_mint, run_spend, tx)
}

fn as_data(value: Data) -> Data {
  value
}

// ---- J2: the configuration record carries the checkpoint credential -----------

fn genesis_with(datum: Data) -> (Transaction, Action) {
  let registry_name = cfg.registry_name
  let tx = Transaction {
    ..transaction.placeholder,
    reference_inputs: [template_input(cfg.state_template)],
    inputs: [
      Input {
        output_reference: cfg.seed,
        output: Output {
          address: Address {
            payment_credential: VerificationKey(#"01"),
            stake_credential: None,
          },
          value: from_lovelace(5_000_000),
          datum: NoDatum,
          reference_script: None,
        },
      },
    ],
    outputs: [
      Output {
        ..config_output(registry(), cfg.checkpoint_credential),
        datum: InlineDatum(datum),
      },
    ],
    mint: mint_of(
      [
        (cfg.state_policy, registry_name, 1),
        (application(), singular_state_configuration_name(), 1),
      ],
    ),
  }
  (
    tx,
    CreateConfiguration {
      registry: registry(),
      seed: cfg.seed,
      output_index: 0,
    },
  )
}

fn singular_state_configuration_name() -> ByteArray {
  cfg.configuration_name
}

fn record_datum(fields: List<Data>) -> Data {
  builtin.constr_data(0, fields)
}

fn parameters_data() -> Data {
  as_data(keri_application_requests.parameters())
}

test a_record_naming_the_checkpoint_credential_is_created() {
  let (tx, action) = genesis_with(
    record_datum([parameters_data(), as_data(cfg.checkpoint_credential)]),
  )
  run_mint([action], tx)
}

test a_record_without_the_credential_is_refused() {
  let (good, action) = genesis_with(
    record_datum([parameters_data(), as_data(cfg.checkpoint_credential)]),
  )
  let (tx, _) = genesis_with(record_datum([parameters_data()]))
  run_mint([action], good) && !run_mint([action], tx)
}

test a_record_whose_credential_is_not_a_credential_is_refused() {
  let (good, action) = genesis_with(
    record_datum([parameters_data(), as_data(cfg.checkpoint_credential)]),
  )
  let (tx, _) = genesis_with(
    record_datum([parameters_data(), builtin.i_data(7)]),
  )
  run_mint([action], good) && !run_mint([action], tx)
}

test a_record_with_a_third_field_is_refused() {
  let (good, action) = genesis_with(
    record_datum([parameters_data(), as_data(cfg.checkpoint_credential)]),
  )
  let (tx, _) = genesis_with(
    record_datum(
      [parameters_data(), as_data(cfg.checkpoint_credential), builtin.i_data(0)],
    ),
  )
  run_mint([action], good) && !run_mint([action], tx)
}

// ---- J3: a booking is exact ---------------------------------------------------------

fn books(b: Booking) -> Bool {
  accepts(booking_tx(b))
}

fn refused_booking(b: Booking) -> Bool {
  books(booking()) && !books(b)
}

fn with_data(data: RegistrationData) -> Booking {
  Booking { ..booking(), data }
}

test a_booking_whose_booking_time_is_not_the_upper_bound_is_refused() {
  // The deadlines follow the recorded booking time, so only the booking time's
  // own relation to the interval's upper bound refuses it.
  let b = booking()
  refused_booking(
    with_data(
      RegistrationData {
        ..b.data,
        booked_at: 9,
        process_deadline: 9 + cfg.process_time,
        reclaim_end: 9 + cfg.process_time,
      },
    ),
  )
}

test a_booking_wider_than_the_booking_width_is_refused() {
  refused_booking(Booking { ..booking(), lower: 8 })
}

test a_booking_in_an_empty_interval_is_refused() {
  refused_booking(Booking { ..booking(), lower: 10 })
}

test a_booking_without_an_upper_bound_is_refused() {
  let b = booking()
  let tx = Transaction {
    ..booking_tx(b),
    validity_range: Interval {
      lower_bound: IntervalBound { bound_type: Finite(9), is_inclusive: True },
      upper_bound: IntervalBound {
        bound_type: PositiveInfinity,
        is_inclusive: True,
      },
    },
  }
  books(b) && !accepts(tx)
}

test a_booking_with_an_inclusive_upper_bound_reads_it_one_later() {
  // [9, 9] inclusive is the interval [9, 10): booked at 10 is exact.
  let b = booking()
  let inclusive = Transaction {
    ..booking_tx(b),
    validity_range: Interval {
      lower_bound: IntervalBound { bound_type: Finite(9), is_inclusive: True },
      upper_bound: IntervalBound { bound_type: Finite(9), is_inclusive: True },
    },
  }
  let other = Transaction {
    ..booking_tx(with_data(RegistrationData { ..b.data, booked_at: 9 })),
    validity_range: Interval {
      lower_bound: IntervalBound { bound_type: Finite(8), is_inclusive: True },
      upper_bound: IntervalBound { bound_type: Finite(9), is_inclusive: True },
    },
  }
  books(b) && accepts(inclusive) && !accepts(other)
}

test a_booking_with_a_reclaim_end_after_the_deadline_is_refused() {
  refused_booking(
    with_data(
      RegistrationData {
        ..booking().data,
        reclaim_end: booking().data.process_deadline + 1,
      },
    ),
  )
}

test a_booking_with_a_deadline_before_the_processing_time_is_refused() {
  refused_booking(
    with_data(
      RegistrationData {
        ..booking().data,
        process_deadline: booking().data.process_deadline - 1,
        reclaim_end: booking().data.process_deadline - 1,
      },
    ),
  )
}

test a_booking_below_the_minimum_deposit_by_one_is_refused() {
  let short = rows.minimum_deposit - 1
  let data = RegistrationData { ..booking().data, deposit: short }
  refused_booking(
    Booking {
      ..booking(),
      data,
      lovelace: short + cfg.registration_cost + cfg.minimum_tip,
    },
  )
}

test a_booking_at_the_minimum_deposit_alone_is_refused_for_its_pool() {
  // The registry's minimum deposit is met; the pool the deposit leaves does not
  // cover one premium (the initial floor is one lovelace above it).
  let data = RegistrationData {
    ..booking().data,
    deposit: rows.minimum_deposit,
  }
  books(booking()) && rows.minimum_deposit < rows.initial_floor && !books(
    Booking {
      ..booking(),
      data,
      lovelace: rows.minimum_deposit + cfg.registration_cost + cfg.minimum_tip,
    },
  )
}

test a_booking_above_the_minimum_deposit_is_accepted_when_exact() {
  let more = rows.minimum_deposit + 5
  let data = RegistrationData { ..booking().data, deposit: more }
  books(
    Booking {
      ..booking(),
      data,
      lovelace: more + cfg.registration_cost + cfg.minimum_tip,
    },
  )
}

test a_booking_whose_request_is_not_at_the_application_address_is_refused() {
  let b = booking()
  let tx = booking_tx(b)
  let elsewhere = Transaction {
    ..tx,
    outputs: [
      Output {
        ..request_output(b.data, b.lovelace),
        address: rows.other_address,
      },
    ],
  }
  books(b) && !accepts(elsewhere)
}

test a_booking_whose_request_holds_another_token_is_refused() {
  let b = booking()
  let tx = booking_tx(b)
  let extra = Transaction {
    ..tx,
    outputs: [
      Output {
        ..request_output(b.data, b.lovelace),
        value: add(request_output(b.data, b.lovelace).value, "x", "y", 1),
      },
    ],
  }
  books(b) && !accepts(extra)
}

test a_booking_whose_request_holds_another_approval_is_refused() {
  let b = booking()
  let other = RegistrationData { ..b.data, deposit: b.data.deposit + 1 }
  let tx = booking_tx(b)
  let swapped = Transaction {
    ..tx,
    outputs: [
      Output {
        ..request_output(b.data, b.lovelace),
        value: add(
          from_lovelace(b.lovelace),
          application(),
          approval_of(other),
          1,
        ),
      },
    ],
  }
  books(b) && !accepts(swapped)
}

test a_booking_whose_request_has_no_inline_datum_is_refused() {
  let b = booking()
  let tx = booking_tx(b)
  let hashed = Transaction {
    ..tx,
    outputs: [
      Output {
        ..request_output(b.data, b.lovelace),
        datum: DatumHash(
          #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
        ),
      },
    ],
  }
  books(b) && !accepts(hashed)
}

test a_booking_reading_only_another_registrys_record_is_refused() {
  let b = booking()
  let tx = booking_tx(b)
  let foreign_only = Transaction {
    ..tx,
    reference_inputs: [
      config_input(51, foreign_registry(), cfg.checkpoint_credential),
    ],
  }
  books(b) && !accepts(foreign_only)
}

test a_booking_reading_a_record_outside_the_application_address_is_refused() {
  let b = booking()
  let tx = booking_tx(b)
  let moved = Transaction {
    ..tx,
    reference_inputs: [
      Input {
        output_reference: reference(50),
        output: Output {
          ..config_output(registry(), cfg.checkpoint_credential),
          address: rows.other_address,
        },
      },
    ],
  }
  books(b) && !accepts(moved)
}

test a_booking_reading_a_record_that_is_a_spent_input_is_refused() {
  // The record is read by reference: the same record as a spent input is no
  // reference to read.
  let b = booking()
  let tx = booking_tx(b)
  let spent = Transaction {
    ..tx,
    reference_inputs: [],
    inputs: [config_input(50, registry(), cfg.checkpoint_credential)],
  }
  books(b) && !accepts(spent)
}

test a_booking_naming_an_output_that_is_not_there_is_refused() {
  let b = booking()
  books(b) && !accepts(
    Transaction {
      ..booking_tx(b),
      redeemers: [
        Pair(
          Mint(application()),
          as_data([BookRegistration { output_index: 1 }]),
        ),
      ],
    },
  )
}

test a_booking_naming_a_negative_output_is_refused() {
  let b = booking()
  books(b) && !accepts(
    Transaction {
      ..booking_tx(b),
      redeemers: [
        Pair(
          Mint(application()),
          as_data([BookRegistration { output_index: -1 }]),
        ),
      ],
    },
  )
}

test a_booking_naming_an_output_that_is_not_a_request_is_refused() {
  let b = booking()
  let tx = booking_tx(b)
  let other = Transaction {
    ..tx,
    outputs: [Output { ..request_output(b.data, b.lovelace), datum: NoDatum }],
  }
  books(b) && !accepts(other)
}

test a_booking_with_a_negative_deposit_is_refused() {
  refused_booking(with_data(RegistrationData { ..booking().data, deposit: -1 }))
}

// ---- J4: a booking commits the checkpoint validator ----------------------------------

test a_booking_committing_the_checkpoint_address_with_a_stake_credential_is_refused() {
  let staked = Address {
    ..checkpoint_address(),
    stake_credential: Some(
      Inline(
        VerificationKey(
          #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
        ),
      ),
    ),
  }
  refused_booking(
    with_data(RegistrationData { ..booking().data, holding_address: staked }),
  )
}

test a_booking_committing_a_key_address_as_the_holding_is_refused() {
  refused_booking(
    with_data(
      RegistrationData { ..booking().data, holding_address: rows.other_address },
    ),
  )
}

// ---- J5, J6: a fold delivers the genuine holding in its window -------------------------

fn folds(f: Fold) -> Bool {
  accepts(fold_tx(f))
}

fn refused_fold(f: Fold) -> Bool {
  folds(fold()) && !folds(f)
}

test a_fold_delivers_exactly_the_deposit() {
  folds(fold())
}

test a_fold_whose_holding_lacks_the_active_token_is_refused() {
  refused_fold(Fold { ..fold(), holding_active: 0 })
}

test a_fold_whose_holding_carries_two_active_tokens_is_refused() {
  refused_fold(Fold { ..fold(), holding_active: 2, active_mint: 2 })
}

test a_fold_that_does_not_mint_the_active_token_is_refused() {
  refused_fold(Fold { ..fold(), active_mint: 0 })
}

test a_fold_that_mints_the_active_token_twice_is_refused() {
  refused_fold(Fold { ..fold(), active_mint: 2 })
}

test a_fold_whose_holding_has_a_datum_hash_is_refused() {
  let f = fold()
  let tx = fold_tx(f)
  let hashed = Transaction {
    ..tx,
    outputs: [
      Output {
        ..holding_output(f),
        datum: DatumHash(
          #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
        ),
      },
    ],
  }
  folds(f) && !accepts(hashed)
}

test a_fold_whose_holding_has_no_datum_is_refused() {
  let f = fold()
  let tx = fold_tx(f)
  folds(f) && !accepts(
    Transaction {
      ..tx,
      outputs: [Output { ..holding_output(f), datum: NoDatum }],
    },
  )
}

test a_fold_naming_an_output_past_the_outputs_is_refused() {
  refused_fold(
    Fold { ..fold(), redeemer: FoldRegistration { holding_index: 1 } },
  )
}

test a_fold_naming_a_negative_output_is_refused() {
  refused_fold(
    Fold { ..fold(), redeemer: FoldRegistration { holding_index: -1 } },
  )
}

test a_fold_whose_holding_address_has_a_stake_credential_is_refused() {
  let staked = Address {
    ..checkpoint_address(),
    stake_credential: Some(
      Inline(
        VerificationKey(
          #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
        ),
      ),
    ),
  }
  refused_fold(Fold { ..fold(), holding_address: staked })
}

test a_fold_of_a_request_burning_its_approval_twice_is_refused() {
  refused_fold(Fold { ..fold(), burn: -2 })
}

test a_fold_burning_another_approval_is_refused() {
  let f = fold()
  let other = RegistrationData { ..f.data, deposit: f.data.deposit + 1 }
  let tx = fold_tx(f)
  let swapped = Transaction {
    ..tx,
    mint: mint_of(
      [
        (application(), approval_of(other), -1),
        (f.data.registry.policy, active_of(f.data), 1),
      ],
    ),
  }
  folds(f) && !accepts(swapped)
}

test a_fold_of_a_request_whose_record_is_not_read_is_refused() {
  let f = fold()
  folds(f) && !accepts(Transaction { ..fold_tx(f), reference_inputs: [] })
}

test a_fold_of_a_request_with_a_retraction_window_record_is_refused() {
  let f = fold()
  let retracting = Output {
    ..config_output(registry(), cfg.checkpoint_credential),
    datum: InlineDatum(
      Configuration {
        parameters: held.ApplicationParameters {
          ..keri_application_requests.parameters(),
          retract_time: 1,
        },
        checkpoint_credential: cfg.checkpoint_credential,
      },
    ),
  }
  folds(f) && !accepts(
    Transaction {
      ..fold_tx(f),
      reference_inputs: [
        Input { output_reference: reference(50), output: retracting },
      ],
    },
  )
}

test a_booking_committing_something_that_is_not_a_checkpoint_datum_is_refused() {
  refused_booking(
    booking_committing(booking().data, builtin.constr_data(7, [])),
  )
}

// J6: the windows

test a_fold_in_an_empty_interval_is_refused() {
  refused_fold(Fold { ..fold(), lower: 15 })
}

test a_fold_without_an_upper_bound_is_refused() {
  let f = fold()
  folds(f) && !accepts(
    Transaction {
      ..fold_tx(f),
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(12),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: PositiveInfinity,
          is_inclusive: True,
        },
      },
    },
  )
}

test a_fold_with_an_inclusive_bound_on_the_last_instant_before_the_deadline_is_accepted() {
  // [12, 14] inclusive is [12, 15): it ends at the deadline.
  let f = fold()
  folds(f) && accepts(
    Transaction {
      ..fold_tx(f),
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(12),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(14),
          is_inclusive: True,
        },
      },
    },
  ) && !accepts(
    Transaction {
      ..fold_tx(f),
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(12),
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(15),
          is_inclusive: True,
        },
      },
    },
  )
}

test a_fold_before_the_deadline_by_a_wide_margin_is_accepted() {
  folds(fold()) && folds(Fold { ..fold(), lower: 1, upper: 3 })
}

fn returns(r: Return) -> Bool {
  accepts(return_tx_of(r))
}

fn return_tx_of(r: Return) -> Transaction {
  keri_application_requests.return_tx(r)
}

fn refused_return(r: Return) -> Bool {
  returns(returned()) && !returns(r)
}

test a_return_after_the_deadline_is_accepted() {
  returns(returned()) && returns(Return { ..returned(), lower: 40, upper: 50 })
}

test a_return_in_an_empty_interval_is_refused() {
  refused_return(Return { ..returned(), lower: 20 })
}

test a_return_without_a_lower_bound_is_refused() {
  let r = returned()
  returns(r) && !accepts(
    Transaction {
      ..return_tx_of(r),
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: NegativeInfinity,
          is_inclusive: True,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(20),
          is_inclusive: False,
        },
      },
    },
  )
}

test a_return_before_the_deadline_is_refused() {
  refused_return(Return { ..returned(), lower: 1, upper: 3 })
}

test a_return_with_an_exclusive_lower_bound_at_the_deadline_is_read_one_later() {
  // (14, 20) with the lower bound exclusive is [15, 20): at the deadline.
  let r = returned()
  returns(r) && accepts(
    Transaction {
      ..return_tx_of(r),
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(14),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(20),
          is_inclusive: False,
        },
      },
    },
  ) && !accepts(
    Transaction {
      ..return_tx_of(r),
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(13),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(20),
          is_inclusive: False,
        },
      },
    },
  )
}

test a_return_keeps_the_approval_is_refused() {
  refused_return(Return { ..returned(), burn: 0 })
}

test a_return_of_a_request_without_its_record_is_refused() {
  let r = returned()
  returns(r) && !accepts(
    Transaction { ..return_tx_of(r), reference_inputs: [] },
  )
}

// ---- J7: a return pays its refund address ------------------------------------------------

test a_refund_split_over_two_outputs_to_the_refund_address_is_accepted() {
  returns(
    Return {
      ..returned(),
      pays: [
        (rows.refund_address, 10),
        (rows.refund_address, 7),
        (rows.spender_address, 1),
      ],
    },
  )
}

test a_refund_of_the_whole_request_to_the_refund_address_is_accepted() {
  returns(returned()) && returns(
    Return { ..returned(), pays: [(rows.refund_address, 17)] },
  )
}

test a_refund_nothing_is_refused() {
  refused_return(Return { ..returned(), pays: [(rows.spender_address, 17)] })
}

test a_refund_paid_to_the_refund_key_with_a_stake_credential_is_refused() {
  let staked = Address {
    ..rows.refund_address,
    stake_credential: Some(
      Inline(
        VerificationKey(
          #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
        ),
      ),
    ),
  }
  refused_return(
    Return { ..returned(), pays: [(staked, 16), (rows.spender_address, 1)] },
  )
}

fn two_returns(pays: List<(Address, Int)>) -> Transaction {
  // Two requests refunding the same address: each is owed its refund.
  let r = Return { ..returned(), lower: 20, upper: 25 }
  // The second request holds a deposit of one less: another approval.
  let other = rows.request_data(9003)
  let tx = return_tx_of(Return { ..r, pays })
  Transaction {
    ..tx,
    inputs: [
      request_input(0, r.data, r.request_lovelace),
      request_input(
        1,
        other,
        other.deposit + cfg.registration_cost + cfg.minimum_tip,
      ),
    ],
    mint: mint_of(
      [
        (application(), approval_of(r.data), -1),
        (application(), approval_of(other), -1),
      ],
    ),
    redeemers: [
      Pair(Spend(reference(60)), as_data(ReturnRegistration)),
      Pair(Spend(reference(61)), as_data(ReturnRegistration)),
      Pair(Mint(application()), as_data(no_actions())),
    ],
  }
}

test two_refunds_to_one_address_are_owed_together() {
  accepts(two_returns([(rows.refund_address, 32), (rows.spender_address, 2)])) && !accepts(
    two_returns([(rows.refund_address, 16), (rows.spender_address, 18)]),
  ) && accepts(
    two_returns(
      [
        (rows.refund_address, 17),
        (rows.refund_address, 15),
        (rows.spender_address, 2),
      ],
    ),
  )
}

// ---- J8: the treasury covers the costs -----------------------------------------------------

test a_fold_donating_nothing_is_refused() {
  refused_fold(Fold { ..fold(), donation: 0 })
}

test a_fold_donating_the_cost_is_accepted_and_one_less_is_refused() {
  folds(Fold { ..fold(), donation: cfg.registration_cost }) && !folds(
    Fold { ..fold(), donation: cfg.registration_cost - 1 },
  )
}

fn two_folds(donation: Int) -> Transaction {
  // Two requests of two AIDs folded in one transaction, each into its own
  // holding. (The observer attests one holding per transaction; this is the
  // application's own accounting.)
  let first = fold()
  let data2 = RegistrationData {
    ..first.data,
    key: rows.key_e2,
    initial_datum: rows.initial_datum(1),
  }
  let second = Fold {
    ..first,
    data: data2,
    holding_datum: rows.initial_datum(1),
  }
  let tx = fold_tx(first)
  Transaction {
    ..tx,
    inputs: [
      request_input(0, first.data, first.request_lovelace),
      request_input(1, second.data, second.request_lovelace),
    ],
    outputs: [holding_output(first), holding_output(second)],
    mint: mint_of(
      [
        (application(), approval_of(first.data), -1),
        (application(), approval_of(second.data), -1),
        (first.data.registry.policy, active_of(first.data), 1),
        (first.data.registry.policy, active_of(second.data), 1),
      ],
    ),
    treasury_donation: keri_application_requests.donation_of(donation),
    redeemers: [
      Pair(Spend(reference(60)), as_data(FoldRegistration { holding_index: 0 })),
      Pair(Spend(reference(61)), as_data(FoldRegistration { holding_index: 1 })),
      Pair(Mint(application()), as_data(no_actions())),
      ..list.filter(
        tx.redeemers,
        fn(Pair(purpose, _)) { is_withdrawal(purpose) },
      )
    ],
  }
}

fn no_actions() -> List<Action> {
  []
}

fn is_withdrawal(purpose: transaction.ScriptPurpose) -> Bool {
  when purpose is {
    Withdraw(_) -> True
    _ -> False
  }
}

test the_donation_covers_the_costs_of_every_request_the_transaction_folds() {
  accepts(two_folds(2 * cfg.registration_cost)) && !accepts(
    two_folds(2 * cfg.registration_cost - 1),
  ) && !accepts(two_folds(cfg.registration_cost)) && accepts(
    two_folds(2 * cfg.registration_cost + 1),
  )
}

// ---- J9: a pending termination is spent only by its fold ---------------------------------------

fn terminates(t: Termination) -> Bool {
  accepts(termination_tx(t))
}

fn refused_termination(t: Termination) -> Bool {
  terminates(termination()) && !terminates(t)
}

test a_pending_termination_is_folded_burning_both_tokens() {
  terminates(termination())
}

test a_termination_fold_keeping_its_approval_is_refused() {
  refused_termination(Termination { ..termination(), approval_burn: 0 })
}

test a_termination_fold_burning_the_approval_twice_is_refused() {
  refused_termination(Termination { ..termination(), approval_burn: -2 })
}

test a_termination_fold_burning_the_active_token_twice_is_refused() {
  refused_termination(Termination { ..termination(), active_burn: -2 })
}

test a_termination_fold_naming_another_key_is_refused() {
  refused_termination(
    Termination {
      ..termination(),
      redeemer: FoldTermination { registry: registry(), key: rows.key_e2 },
    },
  )
}

test a_termination_fold_naming_another_registry_is_refused() {
  refused_termination(
    Termination {
      ..termination(),
      redeemer: FoldTermination {
        registry: foreign_registry(),
        key: rows.key_e,
      },
    },
  )
}

test a_pending_termination_with_a_datum_is_not_folded() {
  refused_termination(
    Termination { ..termination(), datum: InlineDatum(rows.initial_datum(0)) },
  )
}

test a_pending_termination_is_not_returned_or_folded_as_a_registration() {
  terminates(termination()) && list.all(
    [ReturnRegistration, FoldRegistration { holding_index: 0 }],
    fn(action) {
      !terminates(Termination { ..termination(), redeemer: action })
    },
  )
}

test a_pending_termination_holding_another_token_is_not_folded() {
  let t = termination()
  let tx = termination_tx(t)
  terminates(t) && !accepts(
    Transaction {
      ..tx,
      inputs: [
        Input {
          output_reference: reference(80),
          output: Output {
            ..pending_output(t),
            value: add(pending_output(t).value, "x", "y", 1),
          },
        },
      ],
    },
  )
}

// ---- J10: the application covers every input at its address -----------------------------------

test a_delivered_checkpoint_at_the_checkpoint_validator_is_not_the_applications() {
  accepts(checkpoint_spend(checkpoint_address())) && !keri_application_requests.application_runs(
    checkpoint_spend(checkpoint_address()),
  )
}

test a_checkpoint_at_the_application_address_is_refused_whatever_its_redeemer() {
  let tx = checkpoint_spend(app_address())
  list.all(
    keri_application_requests.possible_actions(),
    fn(action) { !run_spend(action, reference(70), tx) },
  )
}

test a_second_request_is_refused_whatever_its_redeemer_but_a_fold() {
  // The fold of one request, with a second request spent beside it: the second
  // may be returned before its deadline (refused), or terminated (refused).
  let f = fold()
  let tx = fold_tx(Fold { ..f, burn: -2, second: Some((f.data, None)) })
  let with_redeemer = fn(action: SpendAction) {
    Transaction {
      ..tx,
      redeemers: [Pair(Spend(reference(61)), as_data(action)), ..tx.redeemers],
    }
  }
  list.all(
    [
      ReturnRegistration,
      FoldTermination { registry: registry(), key: rows.key_e },
    ],
    fn(action) { !accepts(with_redeemer(action)) },
  )
}

test a_request_of_an_unknown_registry_is_refused_at_its_spend() {
  let f = fold()
  let data = RegistrationData { ..f.data, registry: foreign_registry() }
  let g = Fold { ..f, data }
  folds(f) && folds(g) && !accepts(
    Transaction {
      ..fold_tx(g),
      reference_inputs: [
        config_input(50, registry(), cfg.checkpoint_credential),
      ],
    },
  )
}

// ---- J11: the mint is closed -----------------------------------------------------------------------

test an_extra_approval_beside_a_booking_is_refused() {
  let b = booking()
  let other = RegistrationData { ..b.data, deposit: b.data.deposit + 1 }
  books(b) && !accepts(
    Transaction {
      ..booking_tx(b),
      mint: mint_of(
        [
          (application(), approval_of(b.data), 1),
          (application(), approval_of(other), 1),
        ],
      ),
    },
  )
}

test an_approval_minted_with_no_action_is_refused() {
  let b = booking()
  books(b) && !accepts(
    Transaction {
      ..booking_tx(b),
      redeemers: [Pair(Mint(application()), as_data(no_actions()))],
    },
  )
}

test an_approval_burned_without_its_request_is_refused() {
  let f = fold()
  let name = approval_of(f.data)
  let tx = Transaction {
    ..transaction.placeholder,
    mint: mint_of([(application(), name, -1)]),
    redeemers: [Pair(Mint(application()), as_data(no_actions()))],
  }
  !accepts(tx)
}

test an_approval_burned_from_an_input_outside_the_application_address_is_refused() {
  let f = fold()
  let name = approval_of(f.data)
  let held_elsewhere = Input {
    output_reference: reference(90),
    output: Output {
      address: rows.other_address,
      value: add(from_lovelace(2_000_000), application(), name, 1),
      datum: NoDatum,
      reference_script: None,
    },
  }
  let tx = Transaction {
    ..transaction.placeholder,
    inputs: [held_elsewhere],
    mint: mint_of([(application(), name, -1)]),
    redeemers: [Pair(Mint(application()), as_data(no_actions()))],
  }
  !accepts(tx)
}

test a_configuration_token_minted_outside_the_genesis_is_refused() {
  let b = booking()
  books(b) && !accepts(
    Transaction {
      ..booking_tx(b),
      mint: mint_of(
        [
          (application(), approval_of(b.data), 1),
          (application(), cfg.configuration_name, 1),
        ],
      ),
    },
  )
}

test two_bookings_of_one_output_mint_one_approval_not_two() {
  // Each action asks that the approval be minted once (Lean `bookRegistration`):
  // the approval minted twice satisfies neither.
  let b = booking()
  books(b) && !accepts(
    Transaction {
      ..booking_tx(Booking { ..b, mint: 2 }),
      redeemers: [
        Pair(
          Mint(application()),
          as_data(
            [
              BookRegistration { output_index: 0 },
              BookRegistration { output_index: 0 },
            ],
          ),
        ),
      ],
    },
  )
}

test a_booking_and_a_fold_in_one_transaction_are_accepted_together() {
  let b = booking()
  let f = fold()
  let booked = booking_tx(b)
  let folded = fold_tx(f)
  let both = Transaction {
    ..folded,
    outputs: list.concat(folded.outputs, booked.outputs),
    mint: mint_of(
      [
        (application(), approval_of(b.data), 1),
        (application(), approval_of(f.data), -1),
        (f.data.registry.policy, active_of(f.data), 1),
      ],
    ),
    reference_inputs: list.concat(
      folded.reference_inputs,
      [config_input(51, foreign_registry(), cfg.checkpoint_credential)],
    ),
    redeemers: [
      Pair(Spend(reference(60)), as_data(FoldRegistration { holding_index: 0 })),
      Pair(Mint(application()), as_data([BookRegistration { output_index: 1 }])),
      ..list.filter(
        folded.redeemers,
        fn(Pair(purpose, _)) { is_withdrawal(purpose) },
      )
    ],
    validity_range: range(14, 15),
  }
  // The booking clock reads the same interval: booked at its upper bound.
  // A request of another deposit: its approval is not the folded one.
  let booked_here = Booking {
    ..b,
    lovelace: b.lovelace + 1,
    data: RegistrationData {
      ..b.data,
      deposit: b.data.deposit + 1,
      booked_at: 15,
      process_deadline: 20,
      reclaim_end: 20,
      initial_datum: initial_datum_born_at(15),
    },
  }
  let both_here = Transaction {
    ..both,
    outputs: [
      holding_output(f),
      request_output(booked_here.data, booked_here.lovelace),
    ],
    mint: mint_of(
      [
        (application(), approval_of(booked_here.data), 1),
        (application(), approval_of(f.data), -1),
        (f.data.registry.policy, active_of(f.data), 1),
      ],
    ),
    withdrawals: [Pair(Script(rows.observer_hash), 0)],
    redeemers: list.concat(
      both.redeemers,
      [
        Pair(
          Withdraw(Script(rows.observer_hash)),
          envelope(booking_claim(), payload_of([1])),
        ),
      ],
    ),
  }
  accepts(both_here)
}

// ---- J12: the approval commits everything it names --------------------------------------------------

test the_approval_name_is_the_public_singular_name_of_its_preimage() {
  list.all(
    [9001, 9002, 9003, 9004, 9005, 9006],
    fn(raw) {
      let data = rows.request_data(raw)
      registration_approval(data) == approval_of(data)
    },
  )
}

test the_approval_names_are_the_independent_ones() {
  list.all(
    rows.approval_names,
    fn(entry) {
      let (raw, name) = entry
      let data = rows.request_data(raw)
      registration_approval(data) == name && approval_of(data) == name
    },
  )
}

test the_active_and_termination_names_are_the_independent_ones() {
  let data = rows.request_data(9001)
  active_of(data) == rows.active_name && keri_application_requests.termination_approval_of(
    registry(),
    rows.key_e,
  ) == rows.termination_approval_name
}

test the_datums_of_the_vectors_read_back_to_the_lean_bytes() {
  rows.datums_read_back()
}

test a_changed_registry_key_address_datum_or_deposit_changes_the_approval() {
  let data = rows.request_data(9001)
  let base = registration_approval(data)
  let changed = [
    RegistrationData { ..data, registry: foreign_registry() },
    RegistrationData {
      ..data,
      registry: RegistryIdentity { policy: data.registry.policy, name: #"00" },
    },
    RegistrationData { ..data, key: rows.key_e2 },
    RegistrationData { ..data, holding_address: rows.other_address },
    RegistrationData { ..data, initial_datum: rows.initial_datum(1) },
    RegistrationData { ..data, deposit: data.deposit + 1 },
  ]
  list.all(
    changed,
    fn(other) {
      registration_approval(other) != base && registration_approval(other) == approval_of(
        other,
      )
    },
  )
}

test the_fields_the_approval_does_not_name_do_not_change_it() {
  let data = rows.request_data(9001)
  let base = registration_approval(data)
  list.all(
    [
      RegistrationData { ..data, booked_at: data.booked_at + 1 },
      RegistrationData { ..data, process_deadline: data.process_deadline + 1 },
      RegistrationData { ..data, reclaim_end: data.reclaim_end + 1 },
      RegistrationData { ..data, refund_address: rows.other_address },
      RegistrationData { ..data, controller: #"01" },
    ],
    fn(other) { registration_approval(other) == base },
  )
}

// ---- J13: a fold delivers exactly the initial checkpoint state -----------------------------

/// The initial datum of the AID with another refund record: bytes of the ledger
/// address the datum records for the request's refund.
fn initial_datum_refunding_to(refund_to: ByteArray) -> Data {
  expect Live { aid, sn, epoch, poisoned, frozen, born_at, topped_up, keys, .. }
    = datum.read(rows.initial_datum(0))
  datum.write(
    Live {
      aid,
      sn,
      epoch,
      poisoned,
      frozen,
      born_at,
      refund_to,
      topped_up,
      keys,
    },
  )
}

/// The initial datum of the AID born at slot `born_at`.
fn initial_datum_born_at(born_at: Int) -> Data {
  expect  
      Live { aid, sn, epoch, poisoned, frozen, refund_to, topped_up, keys, .. }
    = datum.read(rows.initial_datum(0))
  datum.write(
    Live {
      aid,
      sn,
      epoch,
      poisoned,
      frozen,
      born_at,
      refund_to,
      topped_up,
      keys,
    },
  )
}

/// A booking of the request `data` committing `datum`, holding exactly what its
/// deposit, the registration cost and the minimum tip make.
fn booking_committing(data: RegistrationData, datum: Data) -> Booking {
  let committed = RegistrationData { ..data, initial_datum: datum }
  Booking {
    ..booking(),
    data: committed,
    lovelace: committed.deposit + cfg.registration_cost + cfg.minimum_tip,
  }
}

test a_booking_whose_datum_is_born_at_another_slot_than_the_booking_bound_is_refused() {
  // The booking bound moves one slot later with its deadline; the datum stays
  // born at the earlier bound.
  let b = booking()
  let later = RegistrationData {
    ..b.data,
    booked_at: b.data.booked_at + 1,
    process_deadline: b.data.process_deadline + 1,
    reclaim_end: b.data.reclaim_end + 1,
  }
  refused_booking(
    Booking { ..b, data: later, lower: b.lower + 1, upper: b.upper + 1 },
  )
}

test a_booking_whose_datum_records_the_refund_on_another_network_is_refused() {
  // The datum records the refund address for network 1; the chain is network 0.
  let other_network = bytearray.push(refund_hash(), 97)
  refused_booking(
    booking_committing(
      booking().data,
      initial_datum_refunding_to(other_network),
    ),
  )
}

fn refund_hash() -> ByteArray {
  when rows.refund_address.payment_credential is {
    VerificationKey(hash) -> hash
    Script(hash) -> hash
  }
}

test a_booking_whose_request_refunds_to_a_script_is_accepted_when_the_datum_records_it() {
  let script_refund = Address {
    payment_credential: Script(refund_hash()),
    stake_credential: None,
  }
  let data = RegistrationData {
    ..booking().data,
    refund_address: script_refund,
  }
  let recorded = bytearray.push(refund_hash(), 112)
  let key_recorded = bytearray.push(refund_hash(), 96)
  books(booking_committing(data, initial_datum_refunding_to(recorded))) && !books(
    booking_committing(data, initial_datum_refunding_to(key_recorded)),
  )
}

test a_booking_whose_request_refunds_to_a_staked_address_needs_the_base_address_bytes() {
  let stake = VerificationKey(
    #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
  )
  let staked = Address {
    payment_credential: VerificationKey(refund_hash()),
    stake_credential: Some(Inline(stake)),
  }
  let data = RegistrationData { ..booking().data, refund_address: staked }
  let base_bytes = bytearray.concat(
    refund_hash(),
    #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c",
  )
  let recorded = bytearray.push(base_bytes, 0)
  books(booking_committing(data, initial_datum_refunding_to(recorded))) && !books(
    booking_committing(
      data,
      initial_datum_refunding_to(bytearray.push(refund_hash(), 96)),
    ),
  )
}

test a_booking_leaving_a_pool_of_exactly_one_premium_is_accepted_and_one_less_is_refused() {
  // The default booking commits the initial floor: the pool is one premium. A
  // deposit one lovelace less leaves the pool under the premium.
  let b = booking()
  let data = RegistrationData { ..b.data, deposit: rows.initial_floor - 1 }
  books(b) && rows.initial_floor == b.data.deposit && !books(
    Booking {
      ..b,
      data,
      lovelace: data.deposit + cfg.registration_cost + cfg.minimum_tip,
    },
  )
}

test a_booking_leaving_a_larger_pool_is_accepted() {
  let b = booking()
  let data = RegistrationData { ..b.data, deposit: rows.initial_floor + 7 }
  books(
    Booking {
      ..b,
      data,
      lovelace: data.deposit + cfg.registration_cost + cfg.minimum_tip,
    },
  )
}

// ---- J11, rebound: what the actions justify -------------------------------------------------

test two_bookings_of_two_requests_mint_two_approvals() {
  let b = booking()
  let other = RegistrationData { ..b.data, deposit: b.data.deposit + 1 }
  let tx = booking_tx(b)
  let both = Transaction {
    ..tx,
    outputs: [
      request_output(b.data, b.lovelace),
      request_output(other, b.lovelace + 1),
    ],
    mint: mint_of(
      [
        (application(), approval_of(b.data), 1),
        (application(), approval_of(other), 1),
      ],
    ),
    redeemers: [
      Pair(
        Mint(application()),
        as_data(
          [
            BookRegistration { output_index: 0 },
            BookRegistration { output_index: 1 },
          ],
        ),
      ),
      Pair(
        Withdraw(Script(rows.observer_hash)),
        envelope(booking_claim(), payload_of([0, 1])),
      ),
    ],
    withdrawals: [Pair(Script(rows.observer_hash), 0)],
  }
  books(b) && accepts(both)
}

test a_booking_naming_one_output_twice_is_refused() {
  let b = booking()
  refused_booking(
    Booking {
      ..b,
      actions: [
        BookRegistration { output_index: 0 },
        BookRegistration { output_index: 0 },
      ],
    },
  )
}

test two_equal_requests_booked_with_two_approvals_are_refused() {
  refused_booking(
    Booking {
      ..booking(),
      copies: 2,
      mint: 2,
      actions: [
        BookRegistration { output_index: 0 },
        BookRegistration { output_index: 1 },
      ],
    },
  )
}

test an_approval_minted_beside_a_fold_with_no_booking_is_refused() {
  let f = fold()
  let other = RegistrationData { ..f.data, deposit: f.data.deposit + 1 }
  let tx = fold_tx(f)
  folds(f) && !accepts(
    Transaction {
      ..tx,
      mint: mint_of(
        [
          (application(), approval_of(f.data), -1),
          (application(), approval_of(other), 1),
          (f.data.registry.policy, active_of(f.data), 1),
        ],
      ),
    },
  )
}

test a_request_committing_other_key_material_is_the_requests_own_datum() {
  // The key material of the datum is pinned by the committed hash and read by the
  // observer, not by the initial-state rule: a request that commits a datum with
  // other keys is booked, and folded into exactly that datum.
  let datum = rows.variant(9)
  let f = fold()
  books(booking_committing(booking().data, datum)) && folds(
    Fold {
      ..f,
      data: RegistrationData { ..f.data, initial_datum: datum },
      holding_datum: datum,
    },
  )
}

test a_booking_of_a_registry_whose_record_is_another_applications_is_refused() {
  // A record of the registry created under another application sits at that
  // application's address with that application's token: no record of this
  // registry exists under this one, so the booking names a registry this
  // application never created.
  let b = booking()
  let foreign = foreign_registry()
  let other = RegistrationData { ..b.data, registry: foreign }
  let record = Input {
    output_reference: reference(51),
    output: Output {
      ..config_output(foreign, cfg.checkpoint_credential),
      address: from_script(cfg.foreign_application_policy),
      value: add(
        from_lovelace(cfg.record_lovelace),
        cfg.foreign_application_policy,
        configuration_token_name(foreign),
        1,
      ),
    },
  }
  let tx = booking_tx(Booking { ..b, data: other })
  books(b) && !accepts(
    Transaction { ..tx, reference_inputs: [record, ..tx.reference_inputs] },
  )
}

// ---- the shape of a request that is spent, and the actions that do not spend it ----------

test a_fold_of_a_request_holding_another_token_is_refused() {
  let f = fold()
  let tx = fold_tx(f)
  let extra = request_output(f.data, f.request_lovelace)
  folds(f) && !accepts(
    Transaction {
      ..tx,
      inputs: [
        Input {
          output_reference: reference(60),
          output: Output { ..extra, value: add(extra.value, "x", "y", 1) },
        },
      ],
    },
  )
}

test a_return_of_a_request_holding_another_token_is_refused() {
  let r = returned()
  let tx = return_tx_of(r)
  let extra = request_output(r.data, r.request_lovelace)
  returns(r) && !accepts(
    Transaction {
      ..tx,
      inputs: [
        Input {
          output_reference: reference(60),
          output: Output { ..extra, value: add(extra.value, "x", "y", 1) },
        },
      ],
    },
  )
}

test a_fold_of_a_request_holding_less_than_its_deposit_is_refused() {
  let f = fold()
  refused_fold(Fold { ..f, request_lovelace: f.data.deposit - 1 })
}

test a_return_of_a_request_holding_less_than_its_deposit_is_refused() {
  // The refund is paid in full (everything but the tip), so the payments are
  // right and only the request's own funding refuses it.
  let r = returned()
  let held = r.data.deposit - 1
  refused_return(
    Return {
      ..r,
      request_lovelace: held,
      pays: [(rows.refund_address, held - cfg.minimum_tip)],
    },
  )
}

test a_request_is_not_spent_by_the_fold_of_a_termination() {
  refused_fold(
    Fold {
      ..fold(),
      redeemer: FoldTermination { registry: registry(), key: rows.key_e },
    },
  )
}

test a_pending_termination_must_hold_the_active_token_it_names() {
  // The input holds the active token of another key and the approval of the
  // named one; the burns are of the named key's tokens.
  let t = termination()
  let tx = termination_tx(t)
  let held = Output {
    ..pending_output(t),
    value: add(
      add(
        from_lovelace(t.lovelace),
        application(),
        termination_approval_of(t.registry, rows.key_e),
        1,
      ),
      t.registry.policy,
      active_token_name(t.registry, rows.key_e2),
      1,
    ),
  }
  terminates(t) && !accepts(
    Transaction {
      ..tx,
      inputs: [Input { output_reference: reference(80), output: held }],
    },
  )
}

test refunds_to_two_addresses_are_owed_separately() {
  // Two requests refunding two addresses: each address is owed its own refund,
  // not the sum of both.
  let r = Return { ..returned(), lower: 20, upper: 25 }
  let other = RegistrationData {
    ..rows.request_data(9003),
    refund_address: rows.other_address,
  }
  let pay = fn(address, lovelace) {
    Output {
      address,
      value: from_lovelace(lovelace),
      datum: NoDatum,
      reference_script: None,
    }
  }
  let tx = return_tx_of(r)
  let both = Transaction {
    ..tx,
    inputs: [
      request_input(0, r.data, r.request_lovelace),
      request_input(
        1,
        other,
        other.deposit + cfg.registration_cost + cfg.minimum_tip,
      ),
    ],
    outputs: [
      pay(rows.refund_address, 17),
      pay(rows.other_address, 15),
      pay(rows.spender_address, 2),
    ],
    mint: mint_of(
      [
        (application(), approval_of(r.data), -1),
        (application(), approval_of(other), -1),
      ],
    ),
    redeemers: [
      Pair(Spend(reference(60)), as_data(ReturnRegistration)),
      Pair(Spend(reference(61)), as_data(ReturnRegistration)),
      Pair(Mint(application()), as_data(no_actions())),
    ],
  }
  accepts(both) && !accepts(
    Transaction {
      ..both,
      outputs: [pay(rows.refund_address, 17), pay(rows.spender_address, 17)],
    },
  )
}
