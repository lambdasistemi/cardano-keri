//// A registration is validated when it is booked, at the real scale: the real
//// lifecycle observer and the application over the same booking transaction.
////
//// The observer decides the inception of each key the transaction books (the
//// hash-proof token in an input and burned, the registration predicate over the
//// event bytes and signatures); the application decides which requests the
//// observation names and the initial state each request commits. Every refusal
//// is a transaction one defect away from the accepted one beside it, so a test
//// that fails for any other reason is red for that reason.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{from_verification_key}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{
  Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
}
use cardano_keri/application/action.{Action, SpendAction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{KeyStateView, Live}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/registration.{RegistrationEvidence}
use cardano_keri/checkpoint/registration_vectors as vec
use checkpoint_observer
use keri_application
use keri_application_booking_fixture.{
  as_data, booked_entry, bookings_tx, observation_with, observed,
}
use keri_application_connected.{
  booking_floor, connected_fold, connected_request_of, d_reg, floor,
  hash_proof_policy, keys_of, observer_floor, proof_name_of, refund_hash,
}
use keri_application_requests as requests
use keri_application_requests.{Fold, fold_tx, reference, request_output}

// ---- the two handlers -----------------------------------------------------------

fn run_mint(actions: List<Action>, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    rows.observer_hash,
    booking_floor,
    floor,
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
  own_reference: OutputReference,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.spend(
    cfg.state_template_hash,
    rows.observer_hash,
    booking_floor,
    floor,
    rows.network_id,
    rows.checkpoint_minimum_ada,
    rows.termination_carrier,
    None,
    action,
    own_reference,
    tx,
  )
}

fn application_accepts(tx: Transaction) -> Bool {
  requests.accepts(run_mint, run_spend, tx)
}

/// The real lifecycle observer over the transaction's own withdrawal.
fn observer_accepts(tx: Transaction) -> Bool {
  expect [redeemer, ..] = list.filter_map(
    tx.redeemers,
    fn(Pair(purpose, redeemer)) {
      when purpose is {
        Withdraw(_) -> Some(redeemer)
        _ -> None
      }
    },
  )
  checkpoint_observer.observer_lifecycle.withdraw(
    0,
    hash_proof_policy,
    d_reg,
    redeemer,
    0,
    tx,
  )
}

// ---- the inceptions of the vectors -----------------------------------------------

type Inception {
  state: KeyStateView,
  evidence: RegistrationEvidence,
}

fn first() -> Inception {
  Inception { state: vec.pos_2key_datum, evidence: vec.pos_2key_evidence }
}

fn second() -> Inception {
  Inception {
    state: vec.pos_weighted_datum,
    evidence: vec.pos_weighted_evidence,
  }
}

fn entry(index: Int, inception: Inception) -> Data {
  booked_entry(index, as_data(inception.evidence))
}

fn lovelace_of_request(data: RegistrationData) -> Int {
  data.deposit + cfg.registration_cost + cfg.minimum_tip
}

/// The booking of `inceptions`, each its key's request at the floor, each with
/// its hash-proof token in an input and burned, and one observation listing
/// `listed` (an index and the inception whose evidence is carried).
fn booking_of(
  inceptions: List<Inception>,
  listed: List<(Int, Inception)>,
) -> Transaction {
  let requested = list.map(
    inceptions,
    fn(inception) {
      let data = connected_request_of(inception.state)
      (data, lovelace_of_request(data))
    },
  )
  let tx = bookings_tx(requested)
  let proofs = list.indexed_map(
    inceptions,
    fn(index, inception) {
      Input {
        output_reference: reference(90 + index),
        output: Output {
          address: from_verification_key(
            #"0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee",
          ),
          value: add(
            from_lovelace(2_000_000),
            hash_proof_policy,
            proof_name_of(inception.evidence, inception.state),
            1,
          ),
          datum: NoDatum,
          reference_script: None,
        },
      }
    },
  )
  let burns = list.foldl(
    inceptions,
    tx.mint,
    fn(inception, minted) {
      add(
        minted,
        hash_proof_policy,
        proof_name_of(inception.evidence, inception.state),
        -1,
      )
    },
  )
  observed(
    Transaction { ..tx, inputs: proofs, mint: burns },
    observation_with(
      list.map(listed, fn((index, inception)) { entry(index, inception) }),
    ),
  )
}

fn single() -> Transaction {
  booking_of([first()], [(0, first())])
}

// ---- booking-requires-inception --------------------------------------------------

test the_application_and_the_real_observer_accept_a_booking() {
  let tx = single()
  application_accepts(tx) && observer_accepts(tx)
}

test the_application_and_the_real_observer_accept_two_bookings_in_one_transaction() {
  let tx = booking_of([first(), second()], [(0, first()), (1, second())])
  application_accepts(tx) && observer_accepts(tx)
}

/// One observation lists what it attests: with the evidence of the first only,
/// the observer attests the first and the application refuses the second booking.
test two_bookings_with_the_evidence_of_one_are_refused() {
  let both = booking_of([first(), second()], [(0, first()), (1, second())])
  let only_first = booking_of([first(), second()], [(0, first())])
  application_accepts(both) && observer_accepts(both) && !application_accepts(
    only_first,
  )
}

test the_observer_refuses_a_booking_that_burns_no_hash_proof() {
  let tx = single()
  let unburned = Transaction {
    ..tx,
    mint: assets.merge(
      requests.mint_of([]),
      assets.from_asset(
        requests.application(),
        requests.approval_of(connected_request_of(first().state)),
        1,
      ),
    ),
  }
  observer_accepts(tx) && !observer_accepts(unburned)
}

test the_observer_refuses_a_booking_whose_proof_token_is_not_spent() {
  let tx = single()
  observer_accepts(tx) && !observer_accepts(Transaction { ..tx, inputs: [] })
}

test the_observer_refuses_evidence_of_another_inception() {
  let tx = single()
  let other = booking_of([first()], [(0, second())])
  observer_accepts(tx) && !observer_accepts(other)
}

test the_observer_refuses_a_request_below_its_deposit_floor() {
  let at = observer_request(observer_floor)
  let below = observer_request(observer_floor - 1)
  observer_accepts(at) && !observer_accepts(below)
}

/// The observer reads the deposit the request commits: a booking at exactly the
/// observer's floor is the observer's to accept (the application's own floor is
/// its own test).
fn observer_request(deposit: Int) -> Transaction {
  let tx = single()
  let data = RegistrationData { ..connected_request_of(first().state), deposit }
  Transaction {
    ..tx,
    outputs: [request_output(data, lovelace_of_request(data))],
  }
}

test the_observer_refuses_an_index_that_is_no_request() {
  let tx = single()
  let beyond = booking_of([first()], [(5, first())])
  observer_accepts(tx) && !observer_accepts(beyond)
}

test the_observer_refuses_a_request_at_another_address() {
  let tx = single()
  expect [request] = tx.outputs
  let elsewhere = Transaction {
    ..tx,
    outputs: [
      Output { ..request, address: from_verification_key(refund_hash()) },
    ],
  }
  observer_accepts(tx) && !observer_accepts(elsewhere)
}

// ---- booking-initial-state, at the real scale ------------------------------------

/// The booking of the first inception's request, committing `datum`.
fn with_datum(datum: Data) -> Transaction {
  let data = RegistrationData {
    ..connected_request_of(first().state),
    initial_datum: datum,
  }
  with_request(data)
}

fn with_request(data: RegistrationData) -> Transaction {
  Transaction {
    ..single(),
    outputs: [request_output(data, lovelace_of_request(data))],
    mint: assets.from_asset(
      requests.application(),
      requests.approval_of(data),
      1,
    ),
  }
}

/// The checkpoint datum of the first inception with the facts given.
fn state_of(
  aid: ByteArray,
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
  topped_up: Bool,
) -> Data {
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
      keys: keys_of(first().state),
    },
  )
}

fn initial_aid() -> ByteArray {
  qb64_aid(first().state.cesr_aid)
}

fn initial_refund() -> ByteArray {
  bytearray.push(refund_hash(), 96)
}

fn state_with(
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  topped_up: Bool,
) -> Data {
  state_of(
    initial_aid(),
    sn,
    epoch,
    poisoned,
    frozen,
    born_at,
    initial_refund(),
    topped_up,
  )
}

test a_booking_commits_the_initial_state_of_its_key() {
  application_accepts(with_datum(state_with(0, 0, False, False, 10, False))) && !application_accepts(
    with_datum(state_with(1, 0, False, False, 10, False)),
  ) && !application_accepts(
    with_datum(state_with(0, 1, False, False, 10, False)),
  ) && !application_accepts(
    with_datum(state_with(0, 0, True, False, 10, False)),
  ) && !application_accepts(
    with_datum(state_with(0, 0, False, True, 10, False)),
  ) && !application_accepts(
    with_datum(state_with(0, 0, False, False, 11, False)),
  ) && !application_accepts(
    with_datum(state_with(0, 0, False, False, 10, True)),
  ) && !application_accepts(
    with_datum(
      state_of(
        qb64_aid(second().state.cesr_aid),
        0,
        0,
        False,
        False,
        10,
        initial_refund(),
        False,
      ),
    ),
  )
}

test a_booking_commits_the_refund_address_of_its_request() {
  application_accepts(with_datum(state_with(0, 0, False, False, 10, False))) && !application_accepts(
    with_datum(
      state_of(
        initial_aid(),
        0,
        0,
        False,
        False,
        10,
        bytearray.push(
          #"72777c81868b90959a9fa4a9aeb3b8bdc2c7ccd1d6dbe0e5eaeff4f9",
          96,
        ),
        False,
      ),
    ),
  )
}

test a_booking_below_the_initial_floor_is_refused() {
  let at = connected_request_of(first().state)
  application_accepts(with_request(at)) && !application_accepts(
    with_request(RegistrationData { ..at, deposit: floor - 1 }),
  )
}

// ---- fold-reads-no-evidence, at the real scale ------------------------------------

fn bare_connected_fold() -> Fold {
  Fold {
    ..connected_fold(False),
    claim: None,
    extra_inputs: [],
    extra_mint: [],
  }
}

/// A fold at the real scale carries no observer withdrawal, no hash-proof token
/// and no proof: the window, the delivered holding and the burned approval.
test a_fold_with_no_evidence_is_accepted_at_the_real_scale() {
  let tx = fold_tx(bare_connected_fold())
  application_accepts(tx) && list.is_empty(tx.withdrawals) && list.length(
    tx.inputs,
  ) == 1
}
