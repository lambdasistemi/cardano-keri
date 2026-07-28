//// #137 — isolated Freeze evidence observer.
////
//// Keeping the heavy enforcement predicate in its own module preserves the
//// applied size of observer_advance. The checkpoint Freeze arm owns only
//// state mechanics; this observer binds and validates the genuine KERI event.

use cardano/transaction.{InlineDatum, Transaction, find_input}
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/enforcement.{
  ConvictValid, EnforcementBindingValid, EnforcementEvidence, FreezeValid,
  bind_enforcement_evidence, convict_predicate, freeze_predicate,
}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumValid, ArmedV1, armed_datum_well_formed,
}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_convict, observe_freeze,
}
use cardano_keri/checkpoint/role.{Active, Armed, Frozen}

/// Dispatch the two isolated enforcement actions without sharing their tags.
pub fn validate_enforcement(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  if claim.action == observe_freeze {
    observe_freeze_impl(claim, payload, tx)
  } else if claim.action == observe_convict {
    observe_convict_impl(claim, payload, tx)
  } else {
    fail
  }
}

/// Validate the unchanged Freeze predicate over the named ACTIVE checkpoint
/// input. State mechanics, the hunter, and the ARMED output stay in the thin
/// checkpoint script.
fn observe_freeze_impl(
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> Bool {
  expect evidence: EnforcementEvidence = payload
  expect Some(own_ref) = claim.own_ref
  let policy_id = claim.checkpoint_policy
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect own_input.output.address == role.address(policy_id, Active)
  expect InlineDatum(tip_data) = own_input.output.datum
  expect V1(tip): CheckpointDatum = tip_data
  expect EnforcementBindingValid(decoded) = bind_enforcement_evidence(
    tip.cesr_aid,
    evidence,
  )
  freeze_predicate(tip, decoded) == FreezeValid
}

/// Validate witnessed equivocation over the named live checkpoint input.
fn observe_convict_impl(
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> Bool {
  expect evidence: EnforcementEvidence = payload
  expect Some(own_ref) = claim.own_ref
  let policy_id = claim.checkpoint_policy
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect InlineDatum(source_data) = own_input.output.datum
  let tip = if own_input.output.address == role.address(policy_id, Active) {
    expect V1(tip): CheckpointDatum = source_data
    tip
  } else if own_input.output.address == role.address(policy_id, Armed) {
    expect armed: ArmedDatum = source_data
    expect ArmedDatumValid = armed_datum_well_formed(armed)
    let ArmedV1 { checkpoint: tip, .. } = armed
    tip
  } else if own_input.output.address == role.address(policy_id, Frozen) {
    expect V1(tip): CheckpointDatum = source_data
    tip
  } else {
    fail
  }
  expect EnforcementBindingValid(decoded) = bind_enforcement_evidence(
    tip.cesr_aid,
    evidence,
  )
  convict_predicate(tip, decoded) == ConvictValid
}
