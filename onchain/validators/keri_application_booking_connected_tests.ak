//// A registration is validated when it is booked, at the real scale: the real
//// attestation policy and the application over the same booking transaction.
////
//// The policy decides the inception of each key the transaction books (the
//// hash-proof token in an input and burned, the registration predicate over the
//// event bytes and signatures) and mints the attestation of the request; the
//// application decides that each request it books has its attestation in the
//// mint field and that the datum is the initial state of its key. Every refusal
//// is a transaction one difference away from the accepted one beside it, so a test
//// that fails for any other reason is red for that reason.

use aiken/builtin
use aiken/collection/list
use aiken/primitive/bytearray
use booking_attestation
use booking_attestation_fixture.{
  attestation_redeemer, booking_for, booking_of, booking_of_request, first,
  issued, second, single,
}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/application/action.{Action, SpendAction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum.{Live}
use cardano_keri/checkpoint/message.{qb64_aid}
use keri_application
use keri_application_booking_fixture.{redeeming}
use keri_application_connected.{
  booking_floor, connected_fold, connected_request_of, d_reg, floor,
  hash_proof_policy, keys_of, refund_hash,
}
use keri_application_requests as requests
use keri_application_requests.{Fold, attestation_policy, fold_tx}

/// The attestation policy over the transaction's own redeemer: the script
/// accepting, or failing.
fn policy_accepts(tx: Transaction) -> Bool {
  booking_attestation.booking_attestation.mint(
    hash_proof_policy,
    d_reg,
    attestation_redeemer(tx),
    attestation_policy(),
    tx,
  )
}

// ---- the two handlers -----------------------------------------------------------

fn run_mint(actions: List<Action>, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    attestation_policy(),
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
    attestation_policy(),
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

/// Both scripts the ledger runs over a booking accept.
fn accepted(tx: Transaction) -> Bool {
  application_accepts(tx) && policy_accepts(tx)
}

// ---- booking-requires-inception --------------------------------------------------

test the_application_and_the_real_policy_accept_a_booking() {
  accepted(single())
}

test the_application_and_the_real_policy_accept_two_bookings_in_one_transaction() {
  accepted(booking_of([first(), second()], [(0, first()), (1, second())]))
}

/// The entries of one Issue may come in any order: each carries the index of its
/// request and that request's own evidence.
test the_application_and_the_real_policy_accept_the_entries_in_any_order() {
  accepted(booking_of([first(), second()], [(1, second()), (0, first())]))
}

/// One attestation does not serve two bookings: the policy attests the first
/// request, with its inception shown, and the application refuses the second booking
/// of the same transaction, for which nothing is attested.
test two_bookings_with_the_inception_of_one_are_refused() {
  let both = booking_of([first(), second()], [(0, first()), (1, second())])
  let only_first = redeeming(
    booking_for([first(), second()], [0, 1], [0]),
    issued([(0, first())]),
  )
  accepted(both) && policy_accepts(only_first) && !application_accepts(
    only_first,
  )
}

// ---- booking-initial-state, at the real scale ------------------------------------

fn with_datum(datum: Data) -> Transaction {
  booking_of_request(
    RegistrationData {
      ..connected_request_of(first().state),
      initial_datum: datum,
    },
    first(),
  )
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

/// The initial datum of the first inception with its key material replaced by
/// something no key material is: the facts the application reads are intact.
fn unreadable_keys_datum() -> Data {
  builtin.constr_data(
    1,
    [
      builtin.constr_data(
        0,
        [
          builtin.b_data(initial_aid()),
          builtin.i_data(0),
          builtin.i_data(0),
          builtin.constr_data(0, []),
          builtin.constr_data(0, []),
          builtin.i_data(10),
          builtin.b_data(initial_refund()),
          builtin.constr_data(0, []),
          builtin.i_data(0),
        ],
      ),
    ],
  )
}

/// The application decodes the codec's own type: a datum whose key material the
/// codec refuses is no initial state, whatever its facts.
test a_booking_whose_key_material_the_codec_refuses_is_refused_by_the_application() {
  application_accepts(with_datum(state_with(0, 0, False, False, 10, False))) && !application_accepts(
    with_datum(unreadable_keys_datum()),
  )
}

/// The policy reads the same datum with the codec: the control keeps the hash-proof
/// token in an input and burned, as the refusal beside it does.
test the_policy_attests_the_datum_beside_the_one_it_refuses() {
  policy_accepts(with_datum(state_with(0, 0, False, False, 10, False)))
}

test the_policy_never_attests_a_datum_whose_keys_the_codec_refuses() fail {
  policy_accepts(with_datum(unreadable_keys_datum()))
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
  application_accepts(booking_of_request(at, first())) && !application_accepts(
    booking_of_request(RegistrationData { ..at, deposit: floor - 1 }, first()),
  )
}

// ---- fold-reads-no-evidence, at the real scale ------------------------------------

fn bare_connected_fold() -> Fold {
  connected_fold()
}

/// A fold at the real scale carries no withdrawal, no attestation, no hash-proof
/// token and no proof: the window, the delivered holding and the burned approval.
test a_fold_with_no_evidence_is_accepted_at_the_real_scale() {
  let tx = fold_tx(bare_connected_fold())
  application_accepts(tx) && tx.withdrawals == [] && list.length(tx.inputs) == 1
}
