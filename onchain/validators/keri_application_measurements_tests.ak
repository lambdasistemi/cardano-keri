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

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Script, VerificationKey, from_verification_key}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, Transaction}
use cardano_keri/application/action.{
  Action, FoldRegistration, ReturnRegistration, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{KeyMaterial, KeyStateView, Live}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/observer.{ObserverClaim, observe_register}
use cardano_keri/checkpoint/registration.{proof_token_name}
use cardano_keri/checkpoint/registration_vectors as vec
use checkpoint_observer
use keri_application
use keri_application_fixture.{creation, genesis, keri, template_input}
use keri_application_requests.{
  Booking, Fold, application, booking, booking_tx, checkpoint_hash, envelope,
  fold, fold_tx, reference, return_tx, returned,
}

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

const hash_proof_policy: ByteArray =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// The deployment of the connected scenario: the checkpoint program's own numbers
/// (`d_reg`, the freeze bond, the premium, the minimum ADA). The observer asks a
/// holding to hold at least the minimum ADA and the deposit; a fold delivers a
/// register carrier: that and the freeze bond and one premium. A booking commits
/// at least the registry's minimum ADA and deposit, which is the checkpoint
/// deposit and the freeze bond.
const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

const premium: Int = 2_000_000

const checkpoint_min_ada: Int = 2_000_000

const observer_floor: Int = 1_002_000_000

const booking_floor: Int = 1_007_000_000

const floor: Int = 1_009_000_000

fn live_datum() -> Data {
  let d = vec.pos_2key_datum
  datum.write(
    Live {
      aid: qb64_aid(d.cesr_aid),
      sn: 0,
      epoch: 0,
      poisoned: False,
      frozen: False,
      born_at: 10,
      refund_to: bytearray.push(refund_hash(), 96),
      topped_up: False,
      keys: keys_of(d),
    },
  )
}

fn refund_hash() -> ByteArray {
  when rows.refund_address.payment_credential is {
    VerificationKey(hash) -> hash
    Script(hash) -> hash
  }
}

fn keys_of(d: KeyStateView) -> KeyMaterial {
  KeyMaterial {
    cur_keys: d.cur_keys,
    cur_threshold: d.cur_threshold,
    next_keys: d.next_keys,
    next_threshold: d.next_threshold,
    witnesses: d.witnesses,
    toad: d.toad,
  }
}

fn as_data(value: Data) -> Data {
  value
}

/// The request of the connected scenario: the AID of the observer's inception
/// vector, committing the datum the observer attests and a deposit at the floor.
fn connected_request() -> RegistrationData {
  RegistrationData {
    ..rows.request_data(9001),
    key: qb64_aid(vec.pos_2key_datum.cesr_aid),
    initial_datum: live_datum(),
    deposit: floor,
  }
}

fn proof_name() -> ByteArray {
  proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
}

fn connected_fold(burn_proof: Bool) -> Fold {
  let data = connected_request()
  let proof_input = Input {
    output_reference: reference(90),
    output: Output {
      address: from_verification_key(
        #"0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee",
      ),
      value: add(from_lovelace(2_000_000), hash_proof_policy, proof_name(), 1),
      datum: NoDatum,
      reference_script: None,
    },
  }
  Fold {
    ..fold(),
    data,
    request_lovelace: floor + cfg.registration_cost + cfg.minimum_tip,
    holding_lovelace: floor,
    holding_datum: live_datum(),
    payload: as_data(vec.pos_2key_evidence),
    extra_inputs: [proof_input],
    extra_mint: if burn_proof {
      [(hash_proof_policy, proof_name(), -1)]
    } else {
      []
    },
  }
}

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
