//// #137 — isolated Freeze evidence observer.
////
//// Keeping the heavy enforcement predicate in its own module preserves the
//// applied size of observer_advance. The checkpoint Freeze arm owns only
//// state mechanics; this observer binds and validates the genuine KERI event.
////
//// #254 S254-E extends that division rather than blurring it. This observer is
//// the only party in the combined family that holds the COMPLETE ACTUAL
//// enforcement payload, so deriving its canonical digest and reconciling it
//// with the named mature commitment is its row and nobody else's
//// (`MOD-271-OBSERVER`). The combined register keeps value and state
//// ownership: it names which payee it is about to pay and requires this
//// observer to have authorized exactly that payee, so neither side trusts the
//// other's reading of the transaction.

use cardano/transaction.{InlineDatum, Transaction, find_input}
use cardano_keri/bounty_commitment.{CommitmentFamily}
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/enforcement.{
  ConvictValid, EnforcementBindingValid, FreezeValid, bind_enforcement_evidence,
  convict_predicate, freeze_predicate,
}
use cardano_keri/checkpoint/entitlement.{
  EnforcementProofV1, enforcement_evidence_digest,
}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumValid, armed_checkpoint, armed_datum_well_formed,
}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_convict, observe_freeze,
}
use cardano_keri/checkpoint/role.{Active, Armed, Frozen}

/// The payee this envelope authorizes, for a caller that owns the payout.
///
/// The combined register uses it to bind its own redeemer's payee to the one
/// this observer reconciled. It deliberately returns `None` for any envelope
/// this observer does not own, so a caller can never read a payee out of an
/// action that never established entitlement.
pub fn authorized_payee(envelope: ObserverEnvelope) -> Option<ByteArray> {
  let ObserverEnvelope { claim, payload } = envelope
  if claim.action == observe_freeze || claim.action == observe_convict {
    expect proof: EnforcementProofV1 = payload
    Some(proof.payee_pkh)
  } else {
    None
  }
}

/// Dispatch the two isolated enforcement actions without sharing their tags.
pub fn validate_enforcement(
  family: CommitmentFamily,
  envelope: ObserverEnvelope,
  tx: Transaction,
) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  expect proof: EnforcementProofV1 = payload
  if claim.action == observe_freeze {
    observe_freeze_impl(family, claim, proof, tx)
  } else if claim.action == observe_convict {
    observe_convict_impl(family, claim, proof, tx)
  } else {
    fail
  }
}

/// Validate the unchanged Freeze predicate over the named ACTIVE checkpoint
/// input, then reconcile the actual evidence with the reservation that entitles
/// the hunter. State mechanics, the bond, and the ARMED output stay in the thin
/// checkpoint script.
fn observe_freeze_impl(
  _family: CommitmentFamily,
  claim: ObserverClaim,
  proof: EnforcementProofV1,
  tx: Transaction,
) -> Bool {
  let EnforcementProofV1 { evidence, payee_pkh: _, reveal: _ } = proof
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
  expect freeze_predicate(tip, decoded) == FreezeValid
  // Entitlement lives in observer_entitlement. This half owns the KERI
  // evidence only; the register binds both observers to one envelope.
  True
}

/// Validate witnessed equivocation over the named live checkpoint input, then
/// reconcile the actual evidence with the convictor's reservation.
fn observe_convict_impl(
  _family: CommitmentFamily,
  claim: ObserverClaim,
  proof: EnforcementProofV1,
  tx: Transaction,
) -> Bool {
  let EnforcementProofV1 { evidence, payee_pkh: _, reveal: _ } = proof
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
    armed_checkpoint(armed)
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
  expect convict_predicate(tip, decoded) == ConvictValid
  // Entitlement lives in observer_entitlement. This half owns the KERI
  // evidence only; the register binds both observers to one envelope.
  True
}

/// The canonical digest of the evidence carried by an enforcement envelope.
///
/// Exposed so a measurement or parity fixture can name the exact value this
/// observer reconciles against, without re-deriving the rule.
pub fn envelope_evidence_digest(proof: EnforcementProofV1) -> ByteArray {
  enforcement_evidence_digest(proof.evidence)
}
