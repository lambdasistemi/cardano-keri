//// The booking attestation policy over transactions at the real scale.
////
//// The policy mints, for each request a booking transaction creates at the
//// application, one token whose name is the digest of the claim of that request,
//// and only when the inception of the request's key is shown (the hash-proof token
//// of its event spent and burned, the registration predicate over its event bytes
//// and signatures). Its burn branch mints nothing and needs no evidence. A refusal
//// of the script is its failing: each refusal is a `fail` test over the
//// transaction of the accepting control beside it, one difference away.

use aiken/builtin
use aiken/collection/list
use booking_attestation
use booking_attestation_fixture.{
  Inception, attestation_redeemer, booking_of, booking_of_request, burning,
  first, lovelace_of_request, proof_input, proving, second, single,
}
use cardano/address.{from_verification_key}
use cardano/assets.{PolicyId}
use cardano/transaction.{Output, Transaction, placeholder}
use cardano_keri/application/attestation.{BookedRequest, Burn, Issue}
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/checkpoint/registration.{RegistrationEvidence}
use keri_application_booking_fixture.{
  as_data, burn_redeemer, entry, issue_redeemer, minting, other_policy,
  redeeming, unread_evidence,
}
use keri_application_connected.{
  connected_request_of, d_reg, hash_proof_policy, observer_floor, proof_name_of,
}
use keri_application_requests.{
  application, attestation_of, attestation_policy, name_for,
}

fn name_of_first() -> ByteArray {
  name_for(connected_request_of(first().state), 0)
}

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

// ---- one valid booking with its earlier hash proof ------------------------------

test the_policy_accepts_the_inception_of_a_booked_request() {
  policy_accepts(single())
}

test the_policy_accepts_two_requests_in_one_transaction() {
  policy_accepts(booking_of([first(), second()], [(0, first()), (1, second())]))
}

test the_policy_accepts_the_entries_in_any_order() {
  policy_accepts(booking_of([first(), second()], [(1, second()), (0, first())]))
}

test the_policy_refuses_evidence_listed_against_the_other_request() fail {
  policy_accepts(booking_of([first(), second()], [(0, second()), (1, first())]))
}

test the_policy_refuses_the_evidence_of_another_inception() fail {
  policy_accepts(booking_of([first()], [(0, second())]))
}

test the_policy_refuses_evidence_whose_signatures_are_missing() fail {
  let unsigned = RegistrationEvidence { ..first().evidence, ctrl_sigs: [] }
  policy_accepts(
    booking_of(
      [first()],
      [(0, Inception { state: first().state, evidence: unsigned })],
    ),
  )
}

test the_policy_refuses_a_booking_that_burns_no_hash_proof() fail {
  policy_accepts(
    burning(
      single(),
      [(hash_proof_policy, proof_name_of(first().evidence, first().state), 1)],
    ),
  )
}

test the_policy_refuses_a_booking_whose_proof_token_is_not_spent() fail {
  policy_accepts(Transaction { ..single(), inputs: [] })
}

test the_policy_refuses_a_booking_that_burns_another_proof_token() fail {
  policy_accepts(burning(single(), [(hash_proof_policy, #"ff", -1)]))
}

test the_policy_refuses_a_booking_that_burns_a_proof_token_it_shows_twice() fail {
  policy_accepts(
    burning(
      single(),
      [(hash_proof_policy, proof_name_of(first().evidence, first().state), -1)],
    ),
  )
}

// ---- the request the entry names ------------------------------------------------

/// The booking of the first request committing `deposit`: its output, its minted
/// attestation and its Issue entry all carry that deposit, so the deposit is the
/// only thing that differs between the two floor cases.
fn request_tx(deposit: Int) -> Transaction {
  booking_of_request(
    RegistrationData { ..connected_request_of(first().state), deposit },
    first(),
  )
}

test the_policy_accepts_a_request_at_its_deposit_floor() {
  policy_accepts(request_tx(observer_floor))
}

test the_policy_refuses_a_request_below_its_deposit_floor() fail {
  policy_accepts(request_tx(observer_floor - 1))
}

test the_policy_refuses_an_index_that_is_no_request() fail {
  policy_accepts(booking_of([first()], [(5, first())]))
}

test the_policy_refuses_a_request_at_another_address() fail {
  let tx = single()
  expect [request, ..rest] = tx.outputs
  policy_accepts(
    Transaction {
      ..tx,
      outputs: [
        Output {
          ..request,
          address: from_verification_key(
            #"0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee0bee",
          ),
        },
        ..rest
      ],
    },
  )
}

/// The booking of the first request, whose output is at the application, claiming
/// the application `claimed`: the redeemer names it and the attestation minted is
/// the digest of the claim for it, so the script credential of the output is the
/// only thing that can differ from the claim.
fn claiming(claimed: PolicyId) -> Transaction {
  let data = connected_request_of(first().state)
  redeeming(
    minting(
      proving([(data, lovelace_of_request(data))], [0], [], [first()]),
      [
        (
          attestation_policy(),
          attestation_of(claimed, 0, data.initial_datum, data.deposit),
          1,
        ),
      ],
    ),
    issue_redeemer(claimed, [entry(0, as_data(first().evidence))]),
  )
}

test the_policy_accepts_a_claim_for_the_application_the_request_is_at() {
  policy_accepts(claiming(application()))
}

test the_policy_refuses_a_claim_for_an_application_the_request_is_not_at() fail {
  policy_accepts(claiming(other_policy()))
}

// ---- the entries ----------------------------------------------------------------

test the_policy_refuses_an_issue_without_entries() fail {
  policy_accepts(
    redeeming(
      Transaction { ..single(), redeemers: [] },
      issue_redeemer(application(), []),
    ),
  )
}

/// The same index listed twice, with a proof token spent and burned for each entry:
/// every entry is verified and its proof burned, and the one attestation is minted
/// once; the entries are not distinct.
fn duplicated() -> Transaction {
  let tx = single()
  let doubled = Transaction {
    ..tx,
    inputs: list.concat(tx.inputs, [proof_input(1, first())]),
    redeemers: [],
  }
  redeeming(
    burning(
      doubled,
      [(hash_proof_policy, proof_name_of(first().evidence, first().state), -1)],
    ),
    issue_redeemer(
      application(),
      [entry(0, as_data(first().evidence)), entry(0, as_data(first().evidence))],
    ),
  )
}

test the_policy_refuses_one_index_listed_twice() fail {
  policy_accepts(duplicated())
}

test the_policy_accepts_one_index_listed_once_beside_a_second_proof_token() {
  let tx = single()
  policy_accepts(
    Transaction {
      ..tx,
      inputs: list.concat(tx.inputs, [proof_input(1, first())]),
    },
  )
}

// ---- an issue mints nothing it has not verified ----------------------------------

test the_policy_refuses_an_unverified_positive_name() fail {
  policy_accepts(minting(single(), [(attestation_policy(), #"ee", 1)]))
}

test the_policy_refuses_a_positive_empty_name() fail {
  policy_accepts(minting(single(), [(attestation_policy(), "", 1)]))
}

test the_policy_refuses_a_verified_name_minted_twice() fail {
  policy_accepts(
    minting(single(), [(attestation_policy(), name_of_first(), 1)]),
  )
}

test the_policy_accepts_a_burn_of_another_name_beside_an_issue() {
  policy_accepts(minting(single(), [(attestation_policy(), #"ee", -1)]))
}

test the_policy_accepts_a_burn_of_the_empty_name_beside_an_issue() {
  policy_accepts(minting(single(), [(attestation_policy(), "", -1)]))
}

// ---- burn needs no evidence ------------------------------------------------------

fn burn_of(items: List<(ByteArray, ByteArray, Int)>) -> Transaction {
  redeeming(minting(placeholder, items), burn_redeemer())
}

test an_all_negative_transaction_burns_without_evidence() {
  policy_accepts(
    burn_of(
      [
        (attestation_policy(), name_of_first(), -1),
        (attestation_policy(), #"ee", -3),
      ],
    ),
  )
}

test a_burn_may_burn_the_empty_name() {
  policy_accepts(burn_of([(attestation_policy(), "", -1)]))
}

test a_burn_with_a_positive_entry_is_refused() fail {
  policy_accepts(
    burn_of(
      [
        (attestation_policy(), name_of_first(), -1),
        (attestation_policy(), #"ee", 1),
      ],
    ),
  )
}

test a_burn_with_a_positive_empty_name_is_refused() fail {
  policy_accepts(
    burn_of(
      [
        (attestation_policy(), name_of_first(), -1),
        (attestation_policy(), "", 1),
      ],
    ),
  )
}

/// Only the policy's own names are its business: another policy's positive mint
/// beside a burn is not.
test a_burn_beside_another_policys_mint_is_accepted() {
  policy_accepts(
    burn_of(
      [(attestation_policy(), name_of_first(), -1), (other_policy(), #"ee", 1)],
    ),
  )
}

/// A negative mint under the policy, with the redeemer `redeemer`.
fn negative_mint_with(redeemer: Data) -> Transaction {
  redeeming(
    minting(placeholder, [(attestation_policy(), name_of_first(), -1)]),
    redeemer,
  )
}

test the_policy_accepts_that_mint_with_the_burn_redeemer() {
  policy_accepts(negative_mint_with(burn_redeemer()))
}

/// Entries are nonempty: an Issue that lists none is no Burn, whatever the mint.
test an_issue_without_entries_is_refused_over_a_negative_mint() fail {
  policy_accepts(negative_mint_with(issue_redeemer(application(), [])))
}

test a_redeemer_that_is_neither_issue_nor_burn_is_refused() fail {
  policy_accepts(negative_mint_with(unread_evidence()))
}

// ---- the wire: the Haskell encoder and the validator read the same bytes -----------

/// The evidence of the first wire request, field for field the one the Haskell wire
/// specification builds (`Cardano.KERI.AID.Checkpoint.WireSpec`).
fn wire_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    event_bytes: "icp",
    off_t: 1,
    off_i: 2,
    off_s: 3,
    off_k: [4],
    off_kt: 5,
    off_n: [6],
    off_nt: 7,
    off_b: [8],
    off_bt: 9,
    ctrl_sigs: [
      (
        0,
        #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1",
      ),
    ],
    wit_receipts: [
      (
        1,
        #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1",
      ),
    ],
  }
}

/// The evidence of the second wire request: every field differs from the first's, so
/// an encoder that attached evidence to the wrong request changes the bytes.
fn other_wire_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    event_bytes: "icq",
    off_t: 11,
    off_i: 12,
    off_s: 13,
    off_k: [14, 15],
    off_kt: 16,
    off_n: [17],
    off_nt: 18,
    off_b: [],
    off_bt: 19,
    ctrl_sigs: [
      (
        1,
        #"a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2",
      ),
      (
        2,
        #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
      ),
    ],
    wit_receipts: [],
  }
}

/// The Issue redeemer of the application policy `c0..c0` listing the request at
/// output 3 with the first evidence and the request at output 5 with the second, in
/// the types of the code under test.
fn wire_issue() -> Data {
  let redeemer: Data = Issue {
    application_policy: #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0",
    entries: [
      BookedRequest { request_index: 3, evidence: wire_evidence() },
      BookedRequest { request_index: 5, evidence: other_wire_evidence() },
    ],
  }
  redeemer
}

/// The bytes the Haskell encoder `bookingAttestationIssueData` must produce for the
/// same redeemer (`WireSpec` asserts the same string).
test the_issue_redeemer_has_the_bytes_the_haskell_encoder_writes() {
  builtin.serialise_data(wire_issue()) == #"d8799f581cc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c09fd8799f03d8799f436963700102039f04ff059f06ff079f08ff099f9f005840a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1ffff9f9f015840b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1ffffffffd8799f05d8799f436963710b0c0d9f0e0fff109f11ff1280139f9f015840a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2ff9f025840b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2ffff80ffffffff"
}

/// The redeemer these tests build as raw Data is the one the code under test reads.
test the_fixtures_redeemer_is_the_redeemer_the_policy_decodes() {
  let evidence: Data = wire_evidence()
  let typed: Data = Issue {
    application_policy: other_policy(),
    entries: [BookedRequest { request_index: 3, evidence: wire_evidence() }],
  }
  issue_redeemer(other_policy(), [entry(3, evidence)]) == typed
}

test a_burn_redeemer_built_as_raw_data_is_the_burn_the_policy_decodes() {
  let typed: Data = Burn
  burn_redeemer() == typed
}
