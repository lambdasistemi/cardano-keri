//// The attestation of a booking: the inception of a booked key, witnessed by a
//// token minted in the booking transaction.
////
//// ## Responsibility
//// Realizes the Lean premise `Env.inception data.key` for one booking. The
//// booking transaction mints, for each request it books, one token of the
//// attestation policy whose name is the digest of the claim of that request;
//// the application requires that token, with quantity one, in the mint field of
//// the transaction it executes in (`attested`). The policy mints it only when
//// the inception of the request's key is shown (`validate_attestation`): the
//// hash-proof token of the event in an input and burned, and the registration
//// predicate over the event bytes and signatures.
////
//// ## Dependencies
//// `checkpoint/observer` for the inception proof and the burn accounting,
//// `application/held` for the request's record; the Aiken standard library.
////
//// ## Assumptions
//// The ledger runs a minting policy whenever its policy id appears in the mint
//// field, whatever the asset name and the sign of the quantity. BLAKE2b-256 is
//// collision resistant, so the name of an attestation binds the claim it digests.
////
//// ## Invariants
//// The claim writes its fields as distinct fields of one value: the action, the
//// application policy, the zero-based output index, the exact initial datum of the
//// request and the committed deposit. A token minted for one request is no token
//// of another. An issue mints exactly one unit of each name it verified and no
//// other positive quantity; a burn mints nothing.

use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, quantity_of, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/application/held.{Registration, held_datum}
use cardano_keri/checkpoint/datum.{
  DatumValid, KeyStateView, Live, datum_v2_well_formed,
}
use cardano_keri/checkpoint/message.{aid_digest}
use cardano_keri/checkpoint/observer.{checkpoint_min_ada}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate,
}

/// The action the claim of a booking names.
const claim_tag: ByteArray = "cardano-keri/book-registration/v1"

/// The claim of a booking: constructor 0 holding these fields in this order.
type Claim {
  action: ByteArray,
  application_policy: PolicyId,
  output_index: Int,
  initial_datum: Data,
  deposit: Int,
}

/// The claim of the booking of the request at output `index`, committing
/// `initial_datum` and `deposit`, of the application `application_policy`.
pub fn attestation_claim(
  application_policy: PolicyId,
  index: Int,
  initial_datum: Data,
  deposit: Int,
) -> Data {
  let claim: Data = Claim {
    action: claim_tag,
    application_policy,
    output_index: index,
    initial_datum,
    deposit,
  }
  claim
}

/// The name of the attestation of that booking: the BLAKE2b-256 of the
/// serialised claim.
pub fn attestation_name(
  application_policy: PolicyId,
  index: Int,
  initial_datum: Data,
  deposit: Int,
) -> AssetName {
  blake2b_256(
    builtin.serialise_data(
      attestation_claim(application_policy, index, initial_datum, deposit),
    ),
  )
}

/// Whether the transaction mints, under `attestation_policy`, exactly one unit of
/// the attestation of the request at `index`.
pub fn attested(
  attestation_policy: PolicyId,
  application_policy: PolicyId,
  index: Int,
  initial_datum: Data,
  deposit: Int,
  tx: Transaction,
) -> Bool {
  quantity_of(
    tx.mint,
    attestation_policy,
    attestation_name(application_policy, index, initial_datum, deposit),
  ) == 1
}

/// The inception of the key a checkpoint datum declares, shown by `evidence`
/// over `lovelace`: the hash-proof token of the event is in an input and the
/// registration predicate holds over the key state the datum declares, read as
/// the inception (sequence number and epoch zero). It returns the name of the
/// hash-proof token the transaction must burn. It is the proof the registration
/// observer runs (`checkpoint/observer.validate_registration`), kept as a copy of
/// its own here so that the observer, whose applied hash is published and
/// recorded, is not touched.
fn inception_proof(
  hash_proof_policy: PolicyId,
  d_reg: Int,
  datum_data: Data,
  lovelace: Int,
  evidence: RegistrationEvidence,
  tx: Transaction,
) -> ByteArray {
  let registered = datum.read(datum_data)
  expect datum_v2_well_formed(registered) == DatumValid
  expect Live { aid, keys, .. } = registered
  expect Some(digest) = aid_digest(aid)
  let d = KeyStateView {
    cesr_aid: digest,
    cur_keys: keys.cur_keys,
    cur_threshold: keys.cur_threshold,
    next_keys: keys.next_keys,
    next_threshold: keys.next_threshold,
    witnesses: keys.witnesses,
    toad: keys.toad,
    seq: 0,
    native_sn: 0,
  }
  let proof_name = proof_token_name(evidence.event_bytes, digest)
  expect
    list.any(
      tx.inputs,
      fn(input) {
        quantity_of(input.output.value, hash_proof_policy, proof_name) == 1
      },
    )
  let ctx = DeploymentContext { min_ada: checkpoint_min_ada, d_reg }
  expect registration_predicate(ctx, d, lovelace, evidence) == RegistrationValid
  proof_name
}

/// The transaction burns each hash-proof token as often as it is listed, and
/// nothing else under the policy.
fn burns_exactly(
  hash_proof_policy: PolicyId,
  proofs: List<ByteArray>,
  tx: Transaction,
) -> Bool {
  and {
    list.all(
      proofs,
      fn(name) {
        quantity_of(tx.mint, hash_proof_policy, name) == 0 - list.count(
          proofs,
          fn(listed) { listed == name },
        )
      },
    ),
    list.all(
      dict.to_pairs(tokens(tx.mint, hash_proof_policy)),
      fn(Pair(name, quantity)) { list.has(proofs, name) && quantity < 0 },
    ),
  }
}

/// The inception evidence of one request an issue names: the index of its output
/// among the transaction's outputs and the evidence of its key.
pub type BookedRequest {
  request_index: Int,
  evidence: RegistrationEvidence,
}

/// The redeemer of the attestation policy.
pub type AttestationRedeemer {
  /// Mint the attestation of each listed request of the application.
  Issue { application_policy: PolicyId, entries: List<BookedRequest> }
  /// Burn attestations: nothing is minted.
  Burn
}

/// The mint of `tx` under the policy `policy_id`, as its own redeemer allows.
pub fn validate_attestation(
  hash_proof_policy: PolicyId,
  d_reg: Int,
  policy_id: PolicyId,
  redeemer: Data,
  tx: Transaction,
) -> Bool {
  expect action: AttestationRedeemer = redeemer
  let own = dict.to_pairs(tokens(tx.mint, policy_id))
  when action is {
    Burn -> list.all(own, fn(Pair(_, quantity)) { quantity < 0 })
    Issue { application_policy, entries } -> {
      let indices = list.map(entries, fn(entry) { entry.request_index })
      let verified = list.map(
        entries,
        fn(entry) {
          expect Some(output) = list.at(tx.outputs, entry.request_index)
          expect output.address.payment_credential == Script(application_policy)
          expect Some(Registration { registration }) = held_datum(output)
          (
            attestation_name(
              application_policy,
              entry.request_index,
              registration.initial_datum,
              registration.deposit,
            ),
            inception_proof(
              hash_proof_policy,
              d_reg,
              registration.initial_datum,
              registration.deposit,
              entry.evidence,
              tx,
            ),
          )
        },
      )
      let names = list.map(verified, fn((name, _)) { name })
      and {
        !list.is_empty(entries),
        list.length(list.unique(indices)) == list.length(indices),
        burns_exactly(
          hash_proof_policy,
          list.map(verified, fn((_, proof)) { proof }),
          tx,
        ),
        list.all(names, fn(name) { quantity_of(tx.mint, policy_id, name) == 1 }),
        list.all(
          own,
          fn(Pair(name, quantity)) {
            if list.has(names, name) {
              True
            } else {
              quantity < 0
            }
          },
        ),
      }
    }
  }
}
