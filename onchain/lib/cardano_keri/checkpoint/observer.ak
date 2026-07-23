//// #115 R1 — the generic zero-lovelace withdrawal observer.
////
//// Heavy Register, Freeze, and Convict evidence verification moves here out
//// of the checkpoint validator. The checkpoint retains the state-machine,
//// complete-Value, own-policy token/mint/burn, role/datum, deadline, and
//// payout mechanics and validates only the small exact observer claim (the
//// ran-check); it never imports or decodes the evidence payload. This module
//// owns that payload: it decodes the opaque evidence `Data` according to the
//// claim's action and runs the UNCHANGED registration/freeze/convict
//// predicates over it.
////
//// The action-tag positions are frozen:
////
////   0 ObserveRegister
////   1 ObserveAdvance   (opened in R3; event-own signatures)
////   2 ObserveFreeze
////   3 ObserveConvict
////
//// The observer redeemer envelope is a small claim (action tag, checkpoint
//// h, optional own OutputReference) plus an opaque `Data` evidence payload.
//// Registration's distinct hash-proof event-derived proof input/burn check
//// lives here because computing its event-derived token name is evidence
//// verification.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, lovelace_of, quantity_of, tokens}
use cardano/transaction.{InlineDatum, OutputReference, Transaction, find_input}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{
  ConvictValid, EnforcementBindingValid, EnforcementEvidence, EventEvidence,
  FreezeValid, TombstoneV1, bind_enforcement_evidence, convict_predicate,
  freeze_predicate,
}
use cardano_keri/checkpoint/freeze_bond.{ArmedDatum, ArmedV1}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate,
}
use cardano_keri/checkpoint/role.{Armed, Tombstone, address as role_address}

/// Frozen action-tag positions (R3 opens ObserveAdvance without renumbering).
pub const observe_register: Int = 0

pub const observe_advance: Int = 1

pub const observe_freeze: Int = 2

pub const observe_convict: Int = 3

/// The small exact claim the checkpoint ran-check validates. `action` selects
/// the evidence type the payload decodes to; `checkpoint_policy` is the
/// current checkpoint h (the applied checkpoint hash, both its mint policy
/// and payment credential); `own_ref` names the spent checkpoint input for
/// spend actions and is `None` for Register.
pub type ObserverClaim {
  action: Int,
  checkpoint_policy: PolicyId,
  own_ref: Option<OutputReference>,
}

/// The observer redeemer: a small claim plus an opaque evidence payload.
pub type ObserverEnvelope {
  claim: ObserverClaim,
  payload: Data,
}

/// The ledger min-ADA floor, mirroring `checkpoint.checkpoint_min_ada`. The
/// observer re-derives the same reserve arithmetic the checkpoint's R8
/// deposit check uses, so the moved registration predicate runs over the
/// identical lovelace quantity.
const checkpoint_min_ada: Int = 2_000_000

/// Lifecycle dispatch (R3 four-program): ObserveRegister only.
/// ObserveAdvance, ObserveFreeze, ObserveConvict, and every unknown action
/// fail closed (Advance moved to validate_advance / observer_advance).
pub fn validate_lifecycle(
  hash_proof_policy: PolicyId,
  d_reg: Int,
  envelope: ObserverEnvelope,
  tx: Transaction,
) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  if claim.action == observe_register {
    observe_register_impl(hash_proof_policy, d_reg, claim, payload, tx)
  } else {
    // ObserveAdvance, ObserveFreeze, ObserveConvict, unknown: fail closed.
    fail
  }
}

/// Advance dispatch (R3 four-program): ObserveAdvance only.
/// ObserveRegister, ObserveFreeze, ObserveConvict, and every unknown action
/// fail closed.
pub fn validate_advance(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  if claim.action == observe_advance {
    observe_advance_impl(claim, payload, tx)
  } else {
    fail
  }
}

/// Enforcement dispatch (A-004 family split): ObserveFreeze and ObserveConvict
/// only. ObserveRegister, ObserveAdvance, and every unknown action fail closed.
pub fn validate_enforcement(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  let ObserverEnvelope { claim, payload } = envelope
  if claim.action == observe_freeze {
    observe_freeze_impl(claim, payload, tx)
  } else if claim.action == observe_convict {
    observe_convict_impl(claim, payload, tx)
  } else {
    // ObserveRegister, ObserveAdvance, and every unknown action fail closed in
    // the enforcement observer.
    fail
  }
}

/// ObserveRegister: locate the unique ACTIVE h output and its V1 datum,
/// validate the proof-token input plus the hash-proof-policy full-map exact
/// burn using the event-derived proof name, then run the unchanged
/// registration predicate over the datum, output lovelace, and evidence.
fn observe_register_impl(
  hash_proof_policy: PolicyId,
  d_reg: Int,
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> Bool {
  expect evidence: RegistrationEvidence = payload
  let Transaction { inputs, outputs, mint, .. } = tx
  let policy_id = claim.checkpoint_policy
  // The unique ACTIVE h output carries the inline V1 datum (the one-element
  // filter is the datum-confusion guard, exactly as the checkpoint's R2).
  let active = from_script(policy_id)
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == active },
  )
  expect InlineDatum(datum_data) = state_output.datum
  expect V1(d): CheckpointDatum = datum_data
  // The distinct hash-proof event-derived proof input/burn: some input
  // carries the proof token named over (event_bytes, aid) at quantity one,
  // and the hash-proof policy's full mint map is exactly that burn.
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
  // The unchanged registration predicate over datum, output lovelace, and
  // RegistrationEvidence.
  let ctx = DeploymentContext { min_ada: checkpoint_min_ada, d_reg }
  expect
    registration_predicate(ctx, d, lovelace_of(state_output.value), evidence) == RegistrationValid
  True
}

/// ObserveAdvance: resolve the named checkpoint input to its OLD V1 datum
/// (ACTIVE role for R3 — ARMED/FROZEN spend coupling opens in R4), require a
/// unique ACTIVE successor with NEW V1 datum, and run the pure
/// `advance_predicate` over OLD, NEW, and the event-own AdvanceEvidence
/// (controller signatures over exact event_bytes, dual thresholds, W1-W3,
/// AE1-AE10, incoming-set receipts).
fn observe_advance_impl(
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> Bool {
  expect evidence: AdvanceEvidence = payload
  expect Some(own_ref) = claim.own_ref
  let Transaction { inputs, outputs, .. } = tx
  let policy_id = claim.checkpoint_policy
  // Named spent checkpoint input: locked by h, ACTIVE address, inline V1(OLD).
  // A-017: ACTIVE == from_script(policy); CSE across own-input and successor.
  // Payment Script(policy) is implied by full-address equality.
  expect Some(own_input) = find_input(inputs, own_ref)
  let active = from_script(policy_id)
  expect own_input.output.address == active
  expect InlineDatum(old_data) = own_input.output.datum
  expect V1(old): CheckpointDatum = old_data
  // Unique ACTIVE successor carries inline V1(NEW).
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == active },
  )
  expect InlineDatum(new_data) = state_output.datum
  expect V1(new): CheckpointDatum = new_data
  // Spent context for the pure transition (locator + W1-W3 base + prior
  // commitment). Deployment/out-ref fields are filled from the claim and
  // named input; pure equalities no longer re-check message-bound eq1/eq3/eq4.
  let spent = SpentCheckpoint {
    network_id: 0,
    policy_id,
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
  expect advance_predicate(spent, new, evidence) == AdvancePredicateValid
  True
}

/// Shared enforcement front-path for ObserveFreeze and ObserveConvict:
/// resolve the named checkpoint input to its inner V1 datum and bind the
/// unchanged EnforcementEvidence exactly once, so the EE0-EE9 binding call
/// graph is not duplicated across the two action branches. Returns the inner
/// checkpoint datum and the decoded EventEvidence; the action-specific
/// predicate (and Option C tombstone binding) runs in the caller.
fn bind_checkpoint_enforcement(
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> (CheckpointDatumV1, EventEvidence) {
  expect evidence: EnforcementEvidence = payload
  expect Some(own_ref) = claim.own_ref
  let tip = resolve_checkpoint_input(claim.checkpoint_policy, own_ref, tx)
  expect EnforcementBindingValid(decoded) = bind_enforcement_evidence(
    tip.cesr_aid,
    evidence,
  )
  (tip, decoded)
}

/// ObserveFreeze: bind the unchanged EnforcementEvidence (shared front-path)
/// and run the unchanged freeze predicate.
fn observe_freeze_impl(
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> Bool {
  let (tip, decoded) = bind_checkpoint_enforcement(claim, payload, tx)
  expect freeze_predicate(tip, decoded) == FreezeValid
  True
}

/// ObserveConvict: bind the unchanged EnforcementEvidence (shared front-path),
/// run the unchanged convict predicate, and bind the tombstone output's
/// `evidence_said` to the decoded evidence SAID (A-003 Option C). The
/// checkpoint no longer pins `evidence_said` itself; the observer sees both
/// the evidence and the transaction tombstone output, so the tested
/// wrong-SAID rejection is preserved through the complete coupled context.
fn observe_convict_impl(
  claim: ObserverClaim,
  payload: Data,
  tx: Transaction,
) -> Bool {
  expect evidence: EnforcementEvidence = payload
  let (tip, decoded) = bind_checkpoint_enforcement(claim, payload, tx)
  expect convict_predicate(tip, decoded) == ConvictValid
  // A-003 Option C: pin the tombstone output's evidence_said to the decoded
  // evidence SAID. The unique Tombstone-role output carries the inline
  // TombstoneV1 datum.
  expect [tombstone_output] = list.filter(
    tx.outputs,
    fn(output) {
      output.address == role_address(claim.checkpoint_policy, Tombstone)
    },
  )
  expect InlineDatum(tombstone_data) = tombstone_output.datum
  expect tombstone: TombstoneV1 = tombstone_data
  expect tombstone.evidence_said == evidence.said
  True
}

/// Resolve the named spent checkpoint input to its inner V1 checkpoint datum.
/// The input must be locked by the checkpoint script (its payment credential
/// is the claim's checkpoint h). An ACTIVE or FROZEN input carries a direct
/// inline `CheckpointDatum.V1`; an ARMED input carries an `ArmedV1` wrapper,
/// which is unwrapped to its inner checkpoint datum (mirroring
/// checkpoint.ak's own classify_spend_input / validate_convict_armed). Role,
/// ref, hash, and datum guards are unchanged.
fn resolve_checkpoint_input(
  policy_id: PolicyId,
  own_ref: OutputReference,
  tx: Transaction,
) -> CheckpointDatumV1 {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_hash == policy_id
  expect InlineDatum(datum_data) = own_input.output.datum
  if own_input.output.address == role_address(own_hash, Armed) {
    // Decode and unwrap the ArmedV1 wrapper. The checkpoint's own
    // Convict-from-ARMED dispatch (validate_convict_armed) already enforces
    // armed_datum_well_formed on this identical input in the same coupled
    // transaction, and the observer never reads hunter_pkh — so the
    // well-formedness re-check is not repeated here (coupled-script
    // responsibility partition, not independent acceptance).
    expect armed: ArmedDatum = datum_data
    let ArmedV1 { checkpoint: tip, .. } = armed
    tip
  } else {
    expect V1(tip): CheckpointDatum = datum_data
    tip
  }
}
