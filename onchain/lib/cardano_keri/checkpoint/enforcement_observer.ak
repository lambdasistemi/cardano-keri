//// #137 — isolated Freeze evidence observer.
////
//// Keeping the heavy enforcement predicate in its own module preserves the
//// applied size of observer_advance. The checkpoint Freeze arm owns only
//// state mechanics; this observer binds and validates the genuine KERI event.

use cardano/address.{from_script}
use cardano/transaction.{InlineDatum, Transaction, find_input}
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/enforcement.{
  EnforcementBindingValid, EnforcementEvidence, FreezeValid,
  bind_enforcement_evidence, freeze_predicate,
}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_freeze,
}

/// Validate the one action owned by the enforcement observer.
pub fn validate_enforcement(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect claim.action == observe_freeze
  observe_freeze_impl(claim, payload, tx)
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
  expect own_input.output.address == from_script(policy_id)
  expect InlineDatum(tip_data) = own_input.output.datum
  expect V1(tip): CheckpointDatum = tip_data
  expect EnforcementBindingValid(decoded) = bind_enforcement_evidence(
    tip.cesr_aid,
    evidence,
  )
  freeze_predicate(tip, decoded) == FreezeValid
}
