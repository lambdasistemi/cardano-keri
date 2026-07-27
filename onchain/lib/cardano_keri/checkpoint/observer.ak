//// #136 — the registration evidence observer.
////
//// Register is a small state-machine command. Its heavy KERI inception
//// evidence is carried by a zero-lovelace withdrawal observer, which checks
//// the hash-proof input and burn before running the unchanged registration
//// predicate. Later lifecycle stories may add their own observer families;
//// this module deliberately contains only the Register vertical.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{from_script}
use cardano/assets.{PolicyId, lovelace_of, quantity_of, tokens}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate,
}

/// The stable action tag for Register.
pub const observe_register: Int = 0

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
