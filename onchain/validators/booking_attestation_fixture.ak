//// The booking transactions of the attestation policy at the real scale: the
//// inception vectors of the registration predicate, the hash-proof tokens of
//// their events held in inputs and burned, the requests the application books,
//// and the attestations the policy mints for them.
////
//// A refusal of the policy is the script failing: each refusal is a `fail` test
//// over the transaction of the accepting control beside it, one difference away.

use aiken/collection/list
use cardano/address.{from_verification_key}
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{Input, Mint, NoDatum, Output, Transaction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/checkpoint/datum.{KeyStateView}
use cardano_keri/checkpoint/registration.{RegistrationEvidence}
use cardano_keri/checkpoint/registration_vectors as vec
use keri_application_booking_fixture.{
  as_data, attesting, entry, issue_redeemer, minting, redeeming, requests_tx,
}
use keri_application_connected.{
  connected_request_of, hash_proof_policy, proof_name_of,
}
use keri_application_requests.{application, attestation_policy, reference}

/// An inception of the vectors: the key state its request commits and the
/// evidence that shows it.
pub type Inception {
  state: KeyStateView,
  evidence: RegistrationEvidence,
}

pub fn first() -> Inception {
  Inception { state: vec.pos_2key_datum, evidence: vec.pos_2key_evidence }
}

pub fn second() -> Inception {
  Inception {
    state: vec.pos_weighted_datum,
    evidence: vec.pos_weighted_evidence,
  }
}

/// The lovelace a request of the connected scenario holds.
pub fn lovelace_of_request(data: RegistrationData) -> Int {
  data.deposit + cfg.registration_cost + cfg.minimum_tip
}

/// The request of an inception at the connected scenario's deposit.
pub fn request_of(inception: Inception) -> (RegistrationData, Int) {
  let data = connected_request_of(inception.state)
  (data, lovelace_of_request(data))
}

/// The input that holds the hash-proof token of an inception.
pub fn proof_input(position: Int, inception: Inception) -> Input {
  Input {
    output_reference: reference(90 + position),
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
}

/// The booking of `requests`, creating every request and booking those at
/// `booked`, with the attestation of those at `attested` minted and held in change,
/// and the hash-proof token of each inception of `proofs` in an input and burned.
pub fn proving(
  requests: List<(RegistrationData, Int)>,
  booked: List<Int>,
  attested: List<Int>,
  proofs: List<Inception>,
) -> Transaction {
  let tx = minting(requests_tx(requests, booked), attesting(requests, attested))
  burning(
    Transaction {
      ..tx,
      inputs: list.indexed_map(
        proofs,
        fn(position, inception) { proof_input(position, inception) },
      ),
    },
    list.map(
      proofs,
      fn(inception) {
        (
          hash_proof_policy,
          proof_name_of(inception.evidence, inception.state),
          -1,
        )
      },
    ),
  )
}

/// The booking of `inceptions`, each its key's request at the connected scenario's
/// deposit, each booked, attested and proven.
pub fn proved(inceptions: List<Inception>) -> Transaction {
  booking_for(
    inceptions,
    list.range(0, list.length(inceptions) - 1),
    list.range(0, list.length(inceptions) - 1),
  )
}

/// The requests of `inceptions` created, those at `booked` booked, those at
/// `proven` attested and proven.
pub fn booking_for(
  inceptions: List<Inception>,
  booked: List<Int>,
  proven: List<Int>,
) -> Transaction {
  proving(
    list.map(inceptions, request_of),
    booked,
    proven,
    list.map(
      proven,
      fn(index) {
        expect Some(inception) = list.at(inceptions, index)
        inception
      },
    ),
  )
}

/// The Issue redeemer listing `listed` (an output index and the inception whose
/// evidence is carried).
pub fn issued(listed: List<(Int, Inception)>) -> Data {
  issue_redeemer(
    application(),
    list.map(
      listed,
      fn((index, inception)) { entry(index, as_data(inception.evidence)) },
    ),
  )
}

/// The booking of `inceptions` with the attestation policy's Issue redeemer
/// listing `listed`.
pub fn booking_of(
  inceptions: List<Inception>,
  listed: List<(Int, Inception)>,
) -> Transaction {
  redeeming(proved(inceptions), issued(listed))
}

/// The booking of the single request `data`, whose key's inception is `inception`.
pub fn booking_of_request(
  data: RegistrationData,
  inception: Inception,
) -> Transaction {
  redeeming(
    proving([(data, lovelace_of_request(data))], [0], [0], [inception]),
    issued([(0, inception)]),
  )
}

/// The transaction with the burns added to its mint field.
pub fn burning(
  tx: Transaction,
  burns: List<(ByteArray, ByteArray, Int)>,
) -> Transaction {
  Transaction {
    ..tx,
    mint: list.foldl(
      burns,
      tx.mint,
      fn((policy, name, quantity), value) { add(value, policy, name, quantity) },
    ),
  }
}

pub fn single() -> Transaction {
  booking_of([first()], [(0, first())])
}

/// The redeemer the transaction carries for the attestation policy.
pub fn attestation_redeemer(tx: Transaction) -> Data {
  expect [redeemer, ..] = list.filter_map(
    tx.redeemers,
    fn(Pair(purpose, redeemer)) {
      when purpose is {
        Mint(policy) ->
          if policy == attestation_policy() {
            Some(redeemer)
          } else {
            None
          }
        _ -> None
      }
    },
  )
  redeemer
}
