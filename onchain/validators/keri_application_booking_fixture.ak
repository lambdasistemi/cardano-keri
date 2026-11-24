//// The booking transactions of the application tests that show an inception.
////
//// A registration is validated when it is booked: the booking transaction
//// carries one withdrawal from the lifecycle observer whose redeemer is the
//// booking claim and lists, for every request the transaction books, the
//// evidence of its key's inception. The application's mint decides the claim
//// and which requests it names; the observer decides the inception itself.
////
//// The payload is built here as raw Plutus Data (constructor 0 holding the list
//// of constructor 0 entries `request_index, evidence`), never with the types of
//// the code under test, so a change of the code's own idea of the shape is a
//// change of the transaction these tests build.

use aiken/builtin
use aiken/collection/list
use cardano/address.{Script}
use cardano/transaction.{Mint, Transaction, Withdraw, placeholder}
use cardano_keri/application/action.{Action, BookRegistration}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/observer.{ObserverClaim}
use keri_application_requests.{
  application, approval_of, config_input, envelope, mint_of, range, registry,
  request_output,
}

/// The stable action tag of the booking claim (the interface of the booking).
pub const observe_book: Int = 5

pub fn as_data(value: Data) -> Data {
  value
}

// ---- the observation ----------------------------------------------------------

/// The claim of a booking: the application policy is the script the requests sit
/// at, no output is spent.
pub fn booking_claim() -> ObserverClaim {
  ObserverClaim {
    action: observe_book,
    checkpoint_policy: application(),
    own_ref: None,
  }
}

/// One entry of the payload: the request at `index` and its key's evidence.
pub fn booked_entry(index: Int, evidence: Data) -> Data {
  builtin.constr_data(0, [builtin.i_data(index), evidence])
}

/// The payload of the booking claim.
pub fn booking_payload(entries: List<Data>) -> Data {
  builtin.constr_data(0, [builtin.list_data(entries)])
}

/// What the application never reads: the evidence the observer reads.
pub fn unread_evidence() -> Data {
  builtin.i_data(0)
}

pub type Observation {
  credential: ByteArray,
  claim: ObserverClaim,
  payload: Data,
  withdrawn: Int,
}

/// The observation of a perfect booking of the requests at `indices`.
pub fn observation(indices: List<Int>) -> Observation {
  observation_with(
    list.map(indices, fn(index) { booked_entry(index, unread_evidence()) }),
  )
}

pub fn observation_with(entries: List<Data>) -> Observation {
  Observation {
    credential: rows.observer_hash,
    claim: booking_claim(),
    payload: booking_payload(entries),
    withdrawn: 0,
  }
}

/// The transaction with the observation's withdrawal and redeemer added.
pub fn observed(tx: Transaction, o: Observation) -> Transaction {
  Transaction {
    ..tx,
    withdrawals: list.concat(
      tx.withdrawals,
      [Pair(Script(o.credential), o.withdrawn)],
    ),
    redeemers: list.concat(
      tx.redeemers,
      [Pair(Withdraw(Script(o.credential)), envelope(o.claim, o.payload))],
    ),
  }
}

// ---- the bookings -------------------------------------------------------------

/// A transaction booking each request, in order, at the output of its index.
pub fn bookings_tx(requests: List<(RegistrationData, Int)>) -> Transaction {
  Transaction {
    ..placeholder,
    outputs: list.map(
      requests,
      fn((data, lovelace)) { request_output(data, lovelace) },
    ),
    mint: mint_of(
      list.map(
        requests,
        fn((data, _)) { (application(), approval_of(data), 1) },
      ),
    ),
    reference_inputs: [config_input(50, registry(), cfg.checkpoint_credential)],
    validity_range: range(9, 10),
    redeemers: [
      Pair(Mint(application()), as_data(actions_for(list.length(requests)))),
    ],
  }
}

fn actions_for(count: Int) -> List<Action> {
  list.map(
    list.range(0, count - 1),
    fn(index) { BookRegistration { output_index: index } },
  )
}

/// The second request of the scenario: the other AID, with its own initial datum.
pub fn other_request() -> RegistrationData {
  RegistrationData {
    ..rows.request_data(9001),
    key: rows.key_e2,
    initial_datum: rows.initial_datum(1),
  }
}
