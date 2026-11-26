//// A registration is validated when it is booked: the application's mint and
//// spend over bookings that carry an attestation, and over folds that carry none.
////
//// The attestation here is a token of the attestation policy minted by the
//// transaction under the name the claim of the request digests; the inception
//// it witnesses is the attestation policy's own verdict
//// (`booking_attestation_tests` runs the policy,
//// `keri_application_booking_connected_tests` runs the policy and the
//// application over one transaction). The rows of the Lean vectors are in the
//// generated `keri_application_rows_tests`; the tests here are the requirements
//// the rows do not state: what the attestation must name and what a fold may
//// carry. A refusal is a transaction one difference away from the accepted one
//// beside it.

use aiken/builtin
use cardano/address.{Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction, Withdraw}
use cardano_keri/application/action.{Action, SpendAction}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/row_vectors as rows
use keri_application
use keri_application_booking_fixture.{
  bookings_tx, holding, minting, other_policy, other_request, requests_tx,
  unread_evidence,
}
use keri_application_requests as requests
use keri_application_requests.{
  attestation_of, attestation_policy, claim_of, fold, fold_tx, name_for,
}

fn run_mint(actions: List<Action>, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    attestation_policy(),
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
    attestation_policy(),
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

/// Whether every handler the ledger would run over `tx` accepts.
fn accepts(tx: Transaction) -> Bool {
  requests.accepts(run_mint, run_spend, tx)
}

fn first() -> RegistrationData {
  rows.request_data(9001)
}

fn one() -> List<(RegistrationData, Int)> {
  [(first(), 18)]
}

fn two() -> List<(RegistrationData, Int)> {
  [(first(), 18), (other_request(), 18)]
}

/// The booking of the first request with `quantity` units of the attestation
/// `name` of `policy` minted: the one minted for it by the accepted booking is
/// `(attestation_policy(), name_for(first(), 0), 1)`.
fn attested_by(policy: PolicyId, name: ByteArray, quantity: Int) -> Transaction {
  minting(requests_tx(one(), [0]), [(policy, name, quantity)])
}

/// The booking of both requests of `two()`, minting `items`.
fn pair_minting(items: List<(PolicyId, ByteArray, Int)>) -> Transaction {
  minting(requests_tx(two(), [0, 1]), items)
}

fn of_first() -> (PolicyId, ByteArray, Int) {
  (attestation_policy(), name_for(first(), 0), 1)
}

fn of_second() -> (PolicyId, ByteArray, Int) {
  (attestation_policy(), name_for(other_request(), 1), 1)
}

// ---- booking-requires-inception ---------------------------------------------

/// A booking is accepted when the transaction mints the attestation of its request.
test a_booking_with_its_attestation_is_accepted() {
  accepts(bookings_tx(one()))
}

/// Without the attestation in the mint field, the request is not booked.
test a_booking_without_its_attestation_is_refused() {
  accepts(bookings_tx(one())) && !accepts(requests_tx(one(), [0]))
}

/// The attestation is the configured policy's: the same name under another policy
/// shows no inception.
test an_attestation_of_another_policy_does_not_serve() {
  accepts(bookings_tx(one())) && !accepts(
    attested_by(other_policy(), name_for(first(), 0), 1),
  )
}

/// The attestation is minted in this transaction: the token held by an input, with
/// nothing minted, shows no inception here.
test an_attestation_held_in_an_input_does_not_serve() {
  accepts(bookings_tx(one())) && !accepts(
    holding(requests_tx(one(), [0]), attestation_policy(), name_for(first(), 0)),
  )
}

/// Exactly one unit is minted: two units of the name serve no better than none.
test an_attestation_minted_twice_does_not_serve() {
  accepts(attested_by(attestation_policy(), name_for(first(), 0), 1)) && !accepts(
    attested_by(attestation_policy(), name_for(first(), 0), 2),
  )
}

/// A burn of the name is no attestation.
test an_attestation_burned_does_not_serve() {
  accepts(attested_by(attestation_policy(), name_for(first(), 0), 1)) && !accepts(
    attested_by(attestation_policy(), name_for(first(), 0), -1),
  )
}

/// The application reads no withdrawal and no redeemer of another script: a
/// booking is accepted whatever withdrawals the transaction carries.
test a_booking_carrying_a_withdrawal_of_another_script_is_accepted() {
  let tx = bookings_tx(one())
  accepts(tx) && accepts(
    Transaction {
      ..tx,
      withdrawals: [Pair(Script(other_policy()), 0)],
      redeemers: [
        Pair(Withdraw(Script(other_policy())), unread_evidence()),
        ..tx.redeemers
      ],
    },
  )
}

// ---- observation-names-its-request --------------------------------------------

/// The name binds the application: the attestation of the same request for another
/// application policy shows nothing here.
test an_attestation_names_this_application() {
  accepts(bookings_tx(one())) && !accepts(
    attested_by(
      attestation_policy(),
      attestation_of(other_policy(), 0, first().initial_datum, first().deposit),
      1,
    ),
  )
}

/// The name binds the output index of the request.
test an_attestation_names_the_output_index_of_its_request() {
  accepts(bookings_tx(one())) && !accepts(
    attested_by(
      attestation_policy(),
      attestation_of(
        requests.application(),
        1,
        first().initial_datum,
        first().deposit,
      ),
      1,
    ),
  )
}

/// The name binds the initial datum the request commits.
test an_attestation_names_the_initial_datum_of_its_request() {
  accepts(bookings_tx(one())) && !accepts(
    attested_by(
      attestation_policy(),
      attestation_of(
        requests.application(),
        0,
        rows.initial_datum(1),
        first().deposit,
      ),
      1,
    ),
  )
}

/// The name binds the deposit the request commits.
test an_attestation_names_the_deposit_of_its_request() {
  accepts(bookings_tx(one())) && !accepts(
    attested_by(
      attestation_policy(),
      attestation_of(
        requests.application(),
        0,
        first().initial_datum,
        first().deposit + 1,
      ),
      1,
    ),
  )
}

/// Two bookings of one transaction each need their own attestation: with either
/// one's alone, the other is refused.
test two_bookings_each_need_their_own_attestation() {
  accepts(pair_minting([of_first(), of_second()])) && !accepts(
    pair_minting([of_first()]),
  ) && !accepts(pair_minting([of_second()]))
}

/// The attestation of one request does not serve the other: two units of the first
/// request's name, or the names exchanged between the two outputs, serve neither.
test the_attestation_of_one_request_does_not_serve_the_other() {
  let (policy, name, _) = of_first()
  let (_, other, _) = of_second()
  accepts(pair_minting([of_first(), of_second()])) && !accepts(
    pair_minting([(policy, name, 2)]),
  ) && !accepts(
    pair_minting(
      [
        (policy, name_for(other_request(), 0), 1),
        (policy, name_for(first(), 1), 1),
      ],
    ),
  ) && other != name
}

// ---- fold-reads-no-evidence --------------------------------------------------

/// A fold carries no attestation, no withdrawal and no proof: the window, the
/// delivered holding and the burned approval.
test a_fold_with_no_evidence_is_accepted() {
  let tx = fold_tx(fold())
  accepts(tx) && tx.withdrawals == []
}

// ---- the wire: the Haskell encoder and the validator read the same bytes -----------

fn wire_datum() -> Data {
  builtin.constr_data(1, [builtin.b_data("initial"), builtin.i_data(7)])
}

/// The claim of the application policy `c0..c0` for the request at output 3,
/// committing the datum above and 1,009,000,000 lovelace, serialised as the ledger
/// writes Plutus Data (`WireSpec` asserts the same string).
test the_claim_has_the_bytes_the_haskell_encoder_writes() {
  builtin.serialise_data(
    claim_of(
      #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0",
      3,
      wire_datum(),
      1_009_000_000,
    ),
  ) == #"d8799f582163617264616e6f2d6b6572692f626f6f6b2d726567697374726174696f6e2f7631581cc0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c003d87a9f47696e697469616c07ff1a3c241e40ff"
}

/// The name of that attestation, the BLAKE2b-256 of those bytes.
test the_attestation_name_is_the_digest_of_those_bytes() {
  attestation_of(
    #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0",
    3,
    wire_datum(),
    1_009_000_000,
  ) == #"4364c47043472214a864ab1e196061b4b0c00066407ec312ca2b94381e9ea934"
}
