//// #136/#142 — registration and rotation evidence observers.
////
//// Register is a small state-machine command. Its heavy KERI inception
//// evidence is carried by a zero-lovelace withdrawal observer, which checks
//// the hash-proof input and burn before running the unchanged registration
//// predicate. Advance uses its own observer family: the checkpoint keeps the
//// value/state mechanics while this module runs the unchanged heavy rotation
//// predicate over the named OLD input and unique NEW successor.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{from_script}
use cardano/assets.{PolicyId, lovelace_of, quantity_of, tokens}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/datum.{
  DatumValid, KeyMaterial, KeyStateView, Live, datum_v2_well_formed,
}
use cardano_keri/checkpoint/message.{
  SpentCheckpoint, aid_digest, deriveAidAssetName,
}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate,
}

/// The stable action tag for Register.
pub const observe_register: Int = 0

/// The stable action tag for Advance.
pub const observe_advance: Int = 1

/// The stable action tag for Freeze: the controller's own later rotation presented
/// as a freeze of a checkpoint whose pool is below the premium. Tag 2 was the
/// two-step freeze's and has been unused since it was removed.
pub const observe_freeze: Int = 2

/// The stable action tag for Convict.
pub const observe_convict: Int = 4

/// The claim checked independently by the checkpoint minting policy.
pub type ObserverClaim {
  action: Int,
  checkpoint_policy: PolicyId,
  own_ref: Option<OutputReference>,
}

/// The claim and its registration evidence payload.
pub type ObserverEnvelope {
  claim: ObserverClaim,
  payload: Data,
}

pub const checkpoint_min_ada: Int = 2_000_000

/// Validate the one action owned by the registration observer.
pub fn validate_registration(
  hash_proof_policy: PolicyId,
  d_reg: Int,
  envelope: ObserverEnvelope,
  tx: Transaction,
) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect claim.action == observe_register
  expect claim.own_ref == None
  expect evidence: RegistrationEvidence = payload
  let Transaction { inputs, outputs, mint, .. } = tx
  let policy_id = claim.checkpoint_policy
  let active = from_script(policy_id)
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == active },
  )
  expect InlineDatum(datum_data) = state_output.datum
  let registered = datum.read(datum_data)
  expect datum_v2_well_formed(registered) == DatumValid
  expect Live { aid, keys, .. } = registered
  expect Some(digest) = aid_digest(aid)
  // The event's own predicate runs over the key state the datum declares,
  // read as the inception: sequence number and epoch zero.
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
      inputs,
      fn(input) {
        quantity_of(input.output.value, hash_proof_policy, proof_name) == 1
      },
    )
  expect [Pair(burned_name, burned_qty)] = dict.to_pairs(
    tokens(mint, hash_proof_policy),
  )
  expect burned_name == proof_name
  expect burned_qty == -1
  let ctx = DeploymentContext { min_ada: checkpoint_min_ada, d_reg }
  expect
    registration_predicate(ctx, d, lovelace_of(state_output.value), evidence) == RegistrationValid
  True
}

/// Validate a genuine rotation against the named live input and successor.
///
/// The rotation evidence is verified by the unchanged advance predicate over
/// the key states the two version 2 datums declare: the spent checkpoint's
/// epoch and sequence number play the predicate's checkpoint counter and
/// native sequence number, and the successor must carry the same AID text.
pub fn validate_advance(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect Some(own_ref) = claim.own_ref
  expect evidence: AdvanceEvidence = payload
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(old_data) = own_input.output.datum
  expect claim.action == observe_advance
  expect Live { aid, sn: old_sn, epoch: old_epoch, keys: old_keys, .. } = datum.read(
    old_data,
  )
  expect Some(state_output) = list.find(
    tx.outputs,
    fn(output) { output.address == from_script(claim.checkpoint_policy) },
  )
  expect InlineDatum(new_data) = state_output.datum
  expect Live { aid: new_aid, sn: new_sn, epoch: new_epoch, keys: new_keys, .. }
    = datum.read(new_data)
  expect new_aid == aid
  expect Some(digest) = aid_digest(aid)
  let new = KeyStateView {
    cesr_aid: digest,
    cur_keys: new_keys.cur_keys,
    cur_threshold: new_keys.cur_threshold,
    next_keys: new_keys.next_keys,
    next_threshold: new_keys.next_threshold,
    witnesses: new_keys.witnesses,
    toad: new_keys.toad,
    seq: new_epoch,
    native_sn: new_sn,
  }
  let spent = spent_checkpoint(
    claim.checkpoint_policy,
    own_ref,
    digest,
    old_keys,
    old_epoch,
    old_sn,
  )
  advance_predicate(spent, new, evidence) == AdvancePredicateValid
}

/// The rotation evidence of a freeze: the successor keeps the old keys, so the
/// key state the advance predicate needs cannot be read from it and travels
/// here. The rotated epoch is the spent epoch plus one and is not carried.
pub type FreezeEvidence {
  rotated_keys: KeyMaterial,
  rotated_sn: Int,
  rotation: AdvanceEvidence,
}

/// Validate a genuine later rotation against the named live input, as the
/// evidence of a freeze (Lean `Step.freeze`, `env.rotationTo`, `l.sn < sn'`).
///
/// The unchanged advance predicate runs over the key states the spent datum
/// and the evidence declare. Everything about the freeze that is not evidence
/// (the pool, the flags, the successor, the hunter) is the checkpoint
/// program's.
pub fn validate_freeze(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect claim.action == observe_freeze
  expect Some(own_ref) = claim.own_ref
  expect evidence: FreezeEvidence = payload
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(old_data) = own_input.output.datum
  expect Live { aid, sn: old_sn, epoch: old_epoch, keys: old_keys, .. } = datum.read(
    old_data,
  )
  expect Some(digest) = aid_digest(aid)
  let rotated = evidence.rotated_keys
  let new = KeyStateView {
    cesr_aid: digest,
    cur_keys: rotated.cur_keys,
    cur_threshold: rotated.cur_threshold,
    next_keys: rotated.next_keys,
    next_threshold: rotated.next_threshold,
    witnesses: rotated.witnesses,
    toad: rotated.toad,
    seq: old_epoch + 1,
    native_sn: evidence.rotated_sn,
  }
  let spent = spent_checkpoint(
    claim.checkpoint_policy,
    own_ref,
    digest,
    old_keys,
    old_epoch,
    old_sn,
  )
  advance_predicate(spent, new, evidence.rotation) == AdvancePredicateValid
}

/// The spent checkpoint an advance or a freeze rotates away from: the spent
/// epoch and sequence number play the predicate's checkpoint counter and
/// native sequence number.
fn spent_checkpoint(
  policy_id: PolicyId,
  own_ref: OutputReference,
  digest: ByteArray,
  old_keys: KeyMaterial,
  old_epoch: Int,
  old_sn: Int,
) -> SpentCheckpoint {
  SpentCheckpoint {
    network_id: 0,
    policy_id,
    aid_asset_name: deriveAidAssetName(digest),
    txid: own_ref.transaction_id,
    index: own_ref.output_index,
    cesr_aid: digest,
    witnesses: old_keys.witnesses,
    next_keys: old_keys.next_keys,
    next_threshold: old_keys.next_threshold,
    seq: old_epoch,
    native_sn: old_sn,
  }
}
