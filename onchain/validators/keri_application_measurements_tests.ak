//// Execution units of the application's handlers, and the application beside
//// the real lifecycle observer.
////
//// The `measure_*` tests print exact units with `aiken check --plain-numbers`;
//// each handler measurement is read as the test that runs the handler minus the
//// `*_build` test that only builds its transaction. A fold is the spend handler
//// of its request plus the mint handler that sees the approval burn.
////
//// The connected tests run the real lifecycle observer (the withdrawal the
//// checkpoint program asks for at a Register) and the application over the same
//// transaction: a booking at exactly the observer's deposit floor, folded into a
//// holding the observer attests.

use aiken/builtin
use aiken/collection/list
use cardano/address.{Script, from_verification_key}
use cardano/assets.{Value, from_asset, from_lovelace, lovelace_of, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
  placeholder,
}
use cardano_keri/application/action.{
  Action, FoldRegistration, ReturnRegistration, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{CheckpointDatumV2, Live}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_register,
}
use cardano_keri/checkpoint/registration_vectors as vec
use checkpoint_observer
use checkpoint_register
use freeze_fixture.{
  advance_hash, advance_redeemer, enforcement_hash, entitlement_hash, hunter_pkh,
  network_id,
}
use keri_application
use keri_application_connected.{
  booking_floor, checkpoint_min_ada, connected_fold, connected_request, d_reg,
  floor, freeze_bond, hash_proof_policy, observer_floor, premium,
}
use keri_application_fixture.{creation, genesis, keri, template_input}
use keri_application_requests.{
  Booking, Fold, application, booking, booking_tx, checkpoint_hash, envelope,
  fold, fold_tx, holding_output, reference, return_tx, returned,
}
use registry_fixture.{active_name_of_key, registry_name, state_policy}
use topup_fixture.{topup_redeemer}

fn run_mint(
  minimum_deposit: Int,
  actions: List<Action>,
  tx: Transaction,
) -> Bool {
  run_mint_with(minimum_deposit, rows.initial_floor, actions, tx)
}

fn run_mint_with(
  minimum_deposit: Int,
  initial_floor: Int,
  actions: List<Action>,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    rows.observer_hash,
    minimum_deposit,
    initial_floor,
    rows.network_id,
    actions,
    application(),
    tx,
  )
}

fn run_spend(action: SpendAction, tx: Transaction) -> Bool {
  run_spend_with(rows.initial_floor, action, tx)
}

fn run_spend_with(
  initial_floor: Int,
  action: SpendAction,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.spend(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    initial_floor,
    rows.network_id,
    None,
    action,
    reference(60),
    tx,
  )
}

// ---- measurements -----------------------------------------------------------------

test measure_booking_build() {
  list.length(booking_tx(booking()).outputs) == 1
}

test measure_booking() {
  run_mint(rows.minimum_deposit, booking().actions, booking_tx(booking()))
}

test measure_fold_build() {
  list.length(fold_tx(fold()).outputs) == 1
}

test measure_fold() {
  let tx = fold_tx(fold())
  let none: List<Action> = []
  run_spend(FoldRegistration { holding_index: 0 }, tx) && run_mint(
    rows.minimum_deposit,
    none,
    tx,
  )
}

test measure_fold_spend_only() {
  run_spend(FoldRegistration { holding_index: 0 }, fold_tx(fold()))
}

test measure_return_build() {
  list.length(return_tx(returned()).outputs) == 2
}

test measure_return() {
  let tx = return_tx(returned())
  let none: List<Action> = []
  run_spend(ReturnRegistration, tx) && run_mint(rows.minimum_deposit, none, tx)
}

// ---- the application beside the real observer -------------------------------------------

fn observer_accepts(tx: Transaction) -> Bool {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: checkpoint_hash(),
    own_ref: None,
  }
  checkpoint_observer.observer_lifecycle.withdraw(
    0,
    hash_proof_policy,
    d_reg,
    envelope(claim, as_data(vec.pos_2key_evidence)),
    0,
    tx,
  )
}

fn application_accepts(tx: Transaction) -> Bool {
  let none: List<Action> = []
  run_spend_with(floor, FoldRegistration { holding_index: 0 }, tx) && run_mint_with(
    booking_floor,
    floor,
    none,
    tx,
  )
}

test the_application_and_the_real_observer_accept_a_fold_at_the_floor() {
  let tx = fold_tx(connected_fold(True))
  application_accepts(tx) && observer_accepts(tx)
}

test the_application_does_not_read_the_hash_proof_burn() {
  // The hash-proof token is not burned: the application, which does not read
  // it, accepts; the observer does read it (next test).
  application_accepts(fold_tx(connected_fold(False)))
}

test the_observer_refuses_a_fold_that_burns_no_hash_proof() fail {
  observer_accepts(fold_tx(connected_fold(False)))
}

fn booking_at(deposit: Int) -> Booking {
  Booking {
    ..booking(),
    data: RegistrationData { ..connected_request(), deposit },
    lovelace: deposit + cfg.registration_cost + cfg.minimum_tip,
  }
}

test a_booking_at_the_registrys_floor_is_accepted_and_one_below_is_refused() {
  let at = booking_at(booking_floor)
  let below = booking_at(booking_floor - 1)
  run_mint_with(booking_floor, floor, at.actions, booking_tx(at)) && !run_mint_with(
    booking_floor,
    floor,
    below.actions,
    booking_tx(below),
  )
}

test a_booking_between_the_floors_is_bookable_but_not_foldable() {
  // The model's declared limit: booking checks the registry's floor, a fold the
  // checkpoint's initial floor, one premium above it. A request between them is
  // accepted at booking; its fold leaves a pool under one premium.
  let between = booking_at(booking_floor)
  let f = connected_fold(True)
  let data = RegistrationData { ..f.data, deposit: booking_floor }
  run_mint_with(booking_floor, floor, between.actions, booking_tx(between)) && !application_accepts(
    fold_tx(
      Fold {
        ..f,
        data,
        request_lovelace: booking_floor + cfg.registration_cost + cfg.minimum_tip,
        holding_lovelace: booking_floor,
      },
    ),
  )
}

test the_deployment_floors_are_the_checkpoint_programs_numbers() {
  booking_floor == checkpoint_min_ada + d_reg + freeze_bond && floor == booking_floor + premium && observer_floor == checkpoint_min_ada + d_reg
}

// ---- the configuration record's genesis (reads and hashes the template) -------------------

fn genesis_with_template() -> (Transaction, Action) {
  let d = keri()
  (
    Transaction {
      ..genesis(d),
      reference_inputs: [template_input(cfg.state_template)],
    },
    creation(d, 0),
  )
}

test measure_genesis_build() {
  let (tx, action) = genesis_with_template()
  list.length(tx.outputs) == 1 && action == action
}

test measure_genesis() {
  let (tx, action) = genesis_with_template()
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    [action],
    application(),
    tx,
  )
}

// ---- the checkpoint validator over what a fold delivers -----------------------------------

fn run_checkpoint_spend(
  redeemer: Data,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
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
    None,
    redeemer,
    own_ref,
    tx,
  )
}

// ---------------------------------------------------------------------
// The output a fold delivers
// ---------------------------------------------------------------------

fn delivered_ref() -> OutputReference {
  OutputReference { transaction_id: #"71", output_index: 71 }
}

fn delivered_input(output: Output) -> Input {
  Input { output_reference: delivered_ref(), output }
}

fn delivered() -> Output {
  holding_output(connected_fold(True))
}

fn delivered_live(output: Output) -> CheckpointDatumV2 {
  expect InlineDatum(data) = output.datum
  datum.read(data)
}

/// An Advance of the checkpoint `output`: the successor is the delivered datum
/// one sequence number and one epoch later, holding what a live, unfrozen
/// checkpoint holds (the minimum ADA, the deposit, the bond) and the pool left
/// after one premium, with the premium paid to the second output. The observer
/// withdrawal carries the claim the arm requires; the observer's own verdict
/// is its own test.
fn advance_of(output: Output) -> Bool {
  expect Live { aid, sn, epoch, frozen, born_at, refund_to, keys, .. } = delivered_live(
    output,
  )
  let floor_unfrozen = checkpoint_min_ada + d_reg + freeze_bond
  let pool = lovelace_of(output.value) - floor_unfrozen
  let successor = Output {
    address: output.address,
    value: from_lovelace(floor_unfrozen + pool - premium)
      |> merge(representative_of(output)),
    datum: InlineDatum(
      datum.write(
        Live {
          aid,
          sn: sn + 1,
          epoch: epoch + 1,
          poisoned: False,
          frozen,
          born_at,
          refund_to,
          topped_up: False,
          keys,
        },
      ),
    ),
    reference_script: None,
  }
  let payee = Output {
    address: from_verification_key(hunter_pkh),
    value: from_lovelace(premium),
    datum: NoDatum,
    reference_script: None,
  }
  let credential = Script(advance_hash)
  let envelope: Data = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_advance,
      checkpoint_policy: checkpoint_hash(),
      own_ref: Some(delivered_ref()),
    },
    payload: builtin.i_data(0),
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [delivered_input(output)],
    outputs: [successor, payee],
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), envelope)],
  }
  run_checkpoint_spend(advance_redeemer(1), delivered_ref(), tx)
}

/// A TopUp of the checkpoint `output` by `amount`: the successor is the
/// delivered datum with the top-up mark set, holding `amount` more.
fn top_up_of(output: Output, amount: Int) -> Bool {
  expect Live { aid, sn, epoch, poisoned, frozen, born_at, refund_to, keys, .. }
    = delivered_live(output)
  let successor = Output {
    address: output.address,
    value: from_lovelace(lovelace_of(output.value) + amount)
      |> merge(representative_of(output)),
    datum: InlineDatum(
      datum.write(
        Live {
          aid,
          sn,
          epoch,
          poisoned,
          frozen,
          born_at,
          refund_to,
          topped_up: True,
          keys,
        },
      ),
    ),
    reference_script: None,
  }
  let tx = Transaction {
    ..placeholder,
    inputs: [delivered_input(output)],
    outputs: [successor],
  }
  run_checkpoint_spend(topup_redeemer(amount), delivered_ref(), tx)
}

/// The token the delivered output holds, so a successor can hold the same.
fn representative_of(output: Output) -> Value {
  expect Live { aid, .. } = delivered_live(output)
  from_asset(state_policy(), active_name_of_key(aid), 1)
}

test a_fold_over_the_connected_scenario_is_accepted() {
  let tx = fold_tx(connected_fold(True))
  application_accepts(tx) && observer_accepts(tx)
}

test the_output_a_fold_delivers_is_advanced() {
  advance_of(delivered())
}

test the_output_a_fold_delivers_is_topped_up() {
  top_up_of(delivered(), premium)
}

fn one_lovelace_below_the_checkpoints_floor() -> Fold {
  Fold {
    ..connected_fold(True),
    holding_lovelace: checkpoint_min_ada + d_reg + freeze_bond - 1,
  }
}

test a_fold_delivering_one_lovelace_below_the_checkpoints_floor_is_refused() {
  !application_accepts(fold_tx(one_lovelace_below_the_checkpoints_floor()))
}

test an_output_one_lovelace_below_the_checkpoints_floor_is_not_advanced() fail {
  advance_of(holding_output(one_lovelace_below_the_checkpoints_floor()))
}

test an_output_one_lovelace_below_the_checkpoints_floor_is_not_topped_up() fail {
  top_up_of(holding_output(one_lovelace_below_the_checkpoints_floor()), premium)
}

fn without_the_token() -> Fold {
  Fold { ..connected_fold(True), holding_active: 0, active_mint: 0 }
}

test a_fold_delivering_no_active_token_is_refused() {
  !application_accepts(fold_tx(without_the_token()))
}

test an_output_holding_no_active_token_is_not_advanced() fail {
  advance_of(holding_output(without_the_token()))
}

test an_output_holding_no_active_token_is_not_topped_up() fail {
  top_up_of(holding_output(without_the_token()), premium)
}
