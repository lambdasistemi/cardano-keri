//// The change attestation's checks of the two-policy advance (rotation, freeze and depositing rotation use the same
//// ones): the datum transition of the spent checkpoint to its successor and the binding of the event to it, plus the
//// requirement of the fact asset (the signatures, thresholds, reveal and receipts) in the same mint field.
////
//// The observer's own functions (`observer.validate_advance` and `validate_freeze`) stay for the consumers that still
//// run them; these are the ones the change policy runs. The successor is the output at the claimed index, at the
//// checkpoint address.

use aiken/collection/list
use cardano/address.{from_script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/datum.{KeyMaterial, KeyStateView, Live}
use cardano_keri/checkpoint/message.{
  SpentCheckpoint, aid_digest, deriveAidAssetName,
}
use cardano_keri/checkpoint/observer.{
  FreezeEvidence, ObserverEnvelope, observe_advance, observe_freeze,
}
use cardano_keri/checkpoint/split.{fact_name, transition_ok}

/// An advance (rotation or depositing rotation): the change of the spent checkpoint to the output at `successor_index`.
pub fn validate_advance_change(
  event_policy: PolicyId,
  envelope: ObserverEnvelope,
  successor_index: Int,
  tx: Transaction,
) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect Some(own_ref) = claim.own_ref
  expect evidence: AdvanceEvidence = payload
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(old_data) = own_input.output.datum
  expect claim.action == observe_advance
  expect Live { aid, sn: old_sn, epoch: old_epoch, keys: old_keys, .. } = datum.read(
    old_data,
  )
  expect Some(state_output) = list.at(tx.outputs, successor_index)
  expect state_output.address == from_script(claim.checkpoint_policy)
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
  and {
    transition_ok(spent, new, evidence),
    quantity_of(
      tx.mint,
      event_policy,
      fact_name(
        evidence.event_bytes,
        new.cur_keys,
        new.cur_threshold,
        new.witnesses,
        new.toad,
        old_keys.next_keys,
        old_keys.next_threshold,
      ),
    ) == 1,
  }
}

/// A freeze: the later rotation as the evidence, the successor the frozen copy of the spent checkpoint at the claimed
/// index, at the checkpoint address (Lean `Step.freeze`: the same live state with `frozen` set, from a state neither
/// frozen nor poisoned).
pub fn validate_freeze_change(
  event_policy: PolicyId,
  envelope: ObserverEnvelope,
  successor_index: Int,
  tx: Transaction,
) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect claim.action == observe_freeze
  expect Some(own_ref) = claim.own_ref
  expect evidence: FreezeEvidence = payload
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(old_data) = own_input.output.datum
  let old = datum.read(old_data)
  expect  
      Live {
        aid,
        sn: old_sn,
        epoch: old_epoch,
        poisoned: False,
        frozen: False,
        born_at,
        refund_to,
        topped_up,
        keys: old_keys,
      }
    = old
  expect Some(state_output) = list.at(tx.outputs, successor_index)
  expect state_output.address == from_script(claim.checkpoint_policy)
  expect
    state_output.datum == InlineDatum(
      datum.write(
        Live {
          aid,
          sn: old_sn,
          epoch: old_epoch,
          poisoned: False,
          frozen: True,
          born_at,
          refund_to,
          topped_up,
          keys: old_keys,
        },
      ),
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
  and {
    transition_ok(spent, new, evidence.rotation),
    quantity_of(
      tx.mint,
      event_policy,
      fact_name(
        evidence.rotation.event_bytes,
        new.cur_keys,
        new.cur_threshold,
        new.witnesses,
        new.toad,
        old_keys.next_keys,
        old_keys.next_threshold,
      ),
    ) == 1,
  }
}

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
