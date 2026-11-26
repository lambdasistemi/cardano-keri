//// The booking transactions of the application tests that show an inception.
////
//// A registration is validated when it is booked: the booking transaction
//// mints, for every request it books, one token of the booking attestation
//// policy whose name is the digest of the claim of that request (the action,
//// the application policy, the output index, the initial datum and the
//// committed deposit). The application's mint requires that token with quantity
//// one in the mint field; the attestation policy decides the inception itself.
////
//// The claim and the redeemers are built here as raw Plutus Data, never with the
//// types of the code under test, so a change of the code's own idea of the shape
//// is a change of the transaction these tests build.

use aiken/builtin
use aiken/collection/list
use cardano/address.{from_verification_key}
use cardano/assets.{AssetName, PolicyId, add, from_lovelace}
use cardano/transaction.{Input, Mint, NoDatum, Output, Transaction, placeholder}
use cardano_keri/application/action.{BookRegistration}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use keri_application_requests.{
  application, approval_of, attestation_policy, config_input, mint_of, name_for,
  range, reference, registry, request_output,
}

pub fn as_data(value: Data) -> Data {
  value
}

// ---- the attestation ----------------------------------------------------------

/// A policy that is neither the attestation policy nor the application.
pub fn other_policy() -> PolicyId {
  #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"
}

/// The Issue redeemer of the attestation policy: the application policy and one
/// entry (output index, evidence) for each request.
pub fn issue_redeemer(application_policy: PolicyId, entries: List<Data>) -> Data {
  builtin.constr_data(
    0,
    [builtin.b_data(application_policy), builtin.list_data(entries)],
  )
}

/// The Burn redeemer of the attestation policy.
pub fn burn_redeemer() -> Data {
  builtin.constr_data(1, [])
}

/// One entry of an Issue redeemer.
pub fn entry(index: Int, evidence: Data) -> Data {
  builtin.constr_data(0, [builtin.i_data(index), evidence])
}

/// What the attestation policy's redeemer is not: no Issue, no Burn.
pub fn unread_evidence() -> Data {
  builtin.i_data(0)
}

// ---- the observation of the bookings ------------------------------------------

/// The units of the attestation the transaction mints for the requests at
/// `indices`: one of each name.
pub fn attesting(
  requests: List<(RegistrationData, Int)>,
  indices: List<Int>,
) -> List<(PolicyId, AssetName, Int)> {
  list.map(
    indices,
    fn(index) {
      expect Some((data, _)) = list.at(requests, index)
      (attestation_policy(), name_for(data, index), 1)
    },
  )
}

/// The transaction with `items` minted, and every positive quantity held in a
/// change output: the attestations leave in the submitter's change.
pub fn minting(
  tx: Transaction,
  items: List<(PolicyId, AssetName, Int)>,
) -> Transaction {
  let minted = list.foldl(
    items,
    tx.mint,
    fn((policy, name, quantity), value) { add(value, policy, name, quantity) },
  )
  let held = list.foldl(
    items,
    from_lovelace(2_000_000),
    fn((policy, name, quantity), value) {
      if quantity > 0 {
        add(value, policy, name, quantity)
      } else {
        value
      }
    },
  )
  Transaction {
    ..tx,
    mint: minted,
    outputs: list.concat(
      tx.outputs,
      [
        Output {
          address: from_verification_key(
            #"c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0",
          ),
          value: held,
          datum: NoDatum,
          reference_script: None,
        },
      ],
    ),
  }
}

/// The transaction with an input that holds one unit of the token, as a leftover
/// of an earlier transaction does.
pub fn holding(
  tx: Transaction,
  policy: PolicyId,
  name: AssetName,
) -> Transaction {
  Transaction {
    ..tx,
    inputs: list.concat(
      tx.inputs,
      [
        Input {
          output_reference: reference(70),
          output: Output {
            address: from_verification_key(
              #"c0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0ffeec0",
            ),
            value: add(from_lovelace(2_000_000), policy, name, 1),
            datum: NoDatum,
            reference_script: None,
          },
        },
      ],
    ),
  }
}

/// The transaction with the redeemer of the attestation policy.
pub fn redeeming(tx: Transaction, redeemer: Data) -> Transaction {
  Transaction {
    ..tx,
    redeemers: list.concat(
      tx.redeemers,
      [Pair(Mint(attestation_policy()), redeemer)],
    ),
  }
}

// ---- the bookings -------------------------------------------------------------

/// A transaction creating each request, in order, at the output of its index,
/// and booking only those at the indices `booked`: the others sit at the
/// application address as requests no booking of this transaction mints. It
/// attests nothing.
pub fn requests_tx(
  requests: List<(RegistrationData, Int)>,
  booked: List<Int>,
) -> Transaction {
  Transaction {
    ..placeholder,
    outputs: list.map(
      requests,
      fn((data, lovelace)) { request_output(data, lovelace) },
    ),
    mint: mint_of(
      list.map(
        booked,
        fn(index) {
          expect Some((data, _)) = list.at(requests, index)
          (application(), approval_of(data), 1)
        },
      ),
    ),
    reference_inputs: [config_input(50, registry(), cfg.checkpoint_credential)],
    validity_range: range(9, 10),
    redeemers: [
      Pair(
        Mint(application()),
        as_data(
          list.map(
            booked,
            fn(index) { BookRegistration { output_index: index } },
          ),
        ),
      ),
    ],
  }
}

/// A transaction booking each request, in order, at the output of its index,
/// each with its attestation minted and held in change.
pub fn bookings_tx(requests: List<(RegistrationData, Int)>) -> Transaction {
  let indices = list.range(0, list.length(requests) - 1)
  minting(requests_tx(requests, indices), attesting(requests, indices))
}

/// A transaction creating each request and booking those at `booked`, with their
/// attestations.
pub fn booked_tx(
  requests: List<(RegistrationData, Int)>,
  booked: List<Int>,
) -> Transaction {
  minting(requests_tx(requests, booked), attesting(requests, booked))
}

/// The second request of the scenario: the other AID, with its own initial datum.
pub fn other_request() -> RegistrationData {
  RegistrationData {
    ..rows.request_data(9001),
    key: rows.key_e2,
    initial_datum: rows.initial_datum(1),
  }
}
