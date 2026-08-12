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
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/freeze_bond.{ArmedDatum, ArmedV1}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate,
}

/// The stable action tag for Register.
pub const observe_register: Int = 0

/// The stable action tag for Advance.
pub const observe_advance: Int = 1

/// The stable action tag for Freeze.
pub const observe_freeze: Int = 2

/// The stable action tag for an Armed response Advance.
pub const observe_response_advance: Int = 3

/// The stable action tag for Convict.
pub const observe_convict: Int = 4

/// The stable action tag for a checkpoint-family migration (#254).
///
/// The heavy migration verdict — canonical message reconstruction, the
/// controller quorum, the family edge, and identity/role/value continuity —
/// runs in its own observer, because the applied Register program cannot hold
/// it and stay under the released signed-reference transaction ceiling. Only
/// the tag lives here; the checks stay owned by MOD-254-CHECKPOINT-FAMILY.
pub const observe_migration: Int = 5

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

const checkpoint_min_ada: Int = 2_000_000

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
  expect V1(d): CheckpointDatum = datum_data
  let proof_name = proof_token_name(evidence.event_bytes, d.cesr_aid)
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

/// Validate a genuine rotation against the named ACTIVE input and successor.
pub fn validate_advance(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect Some(own_ref) = claim.own_ref
  expect evidence: AdvanceEvidence = payload
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(old_data) = own_input.output.datum
  let old = if claim.action == observe_advance {
    expect V1(old): CheckpointDatum = old_data
    old
  } else {
    // The thin checkpoint arm admits only actions 1 and 3, so this branch is
    // necessarily the Armed response form in the composed transaction.
    expect ArmedV1 { checkpoint: old, .. }: ArmedDatum = old_data
    old
  }
  expect Some(state_output) = list.find(
    tx.outputs,
    fn(output) { output.address == from_script(claim.checkpoint_policy) },
  )
  expect InlineDatum(new_data) = state_output.datum
  expect V1(new): CheckpointDatum = new_data
  let spent = SpentCheckpoint {
    network_id: 0,
    policy_id: claim.checkpoint_policy,
    aid_asset_name: deriveAidAssetName(old.cesr_aid),
    txid: own_ref.transaction_id,
    index: own_ref.output_index,
    cesr_aid: old.cesr_aid,
    witnesses: old.witnesses,
    next_keys: old.next_keys,
    next_threshold: old.next_threshold,
    seq: old.seq,
    native_sn: old.native_sn,
  }
  advance_predicate(spent, new, evidence) == AdvancePredicateValid
}
