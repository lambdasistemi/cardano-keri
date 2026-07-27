//// #136 — real-script tests for the register-only checkpoint vertical.

use aiken/interval
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
  placeholder,
}
use cardano_keri/checkpoint/close.{CloseEvidence}
use cardano_keri/checkpoint/close_vectors as close_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use checkpoint_observer
use checkpoint_register.{Close, CloseBurn, Register}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const lifecycle_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

fn proof_input(name: ByteArray) -> Input {
  input_at(
    out_ref(seed_tx_id, 0),
    Output {
      address: from_verification_key(owner_vkh),
      value: from_lovelace(min_ada) |> merge(from_asset(hp_policy, name, 1)),
      datum: NoDatum,
      reference_script: None,
    },
  )
}

fn state_output(d: CheckpointDatumV1, lovelace: Int) -> Output {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  Output {
    address: from_script(policy),
    value: from_lovelace(lovelace) |> merge(from_asset(policy, aid_name, 1)),
    datum: InlineDatum(V1(d)),
    reference_script: None,
  }
}

fn register_mint(d: CheckpointDatumV1, proof_name: ByteArray) -> Value {
  from_asset(policy, deriveAidAssetName(d.cesr_aid), 1)
    |> merge(from_asset(hp_policy, proof_name, -1))
}

fn register_envelope(evidence: RegistrationEvidence) -> ObserverEnvelope {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  ObserverEnvelope { claim, payload: evidence }
}

fn register_tx(
  d: CheckpointDatumV1,
  lovelace: Int,
  evidence: RegistrationEvidence,
) -> Transaction {
  let proof_name = proof_token_name(evidence.event_bytes, d.cesr_aid)
  let tx = mint_context(
    [proof_input(proof_name)],
    [state_output(d, lovelace)],
    register_mint(d, proof_name),
  )
  let credential = Script(lifecycle_hash)
  let envelope = register_envelope(evidence)
  let redeemer: Data = envelope
  Transaction {
    ..tx,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

fn run_register(
  d: CheckpointDatumV1,
  lovelace: Int,
  evidence: RegistrationEvidence,
) -> Bool {
  let tx = register_tx(d, lovelace, evidence)
  checkpoint_register.checkpoint_register.mint(
    0,
    lifecycle_hash,
    0,
    d_reg,
    freeze_bond,
    Register,
    policy,
    tx,
  ) && checkpoint_observer.observer_lifecycle.withdraw(
    0,
    hp_policy,
    d_reg,
    register_envelope(evidence),
    0,
    tx,
  )
}

test register_small_accepts_honest_two_key_identity() {
  run_register(
    vec.pos_2key_datum,
    min_ada + d_reg + freeze_bond,
    vec.pos_2key_evidence,
  )
}

test register_small_rejects_forged_controller_threshold() fail {
  let forged = RegistrationEvidence { ..vec.pos_2key_evidence, ctrl_sigs: [] }
  run_register(vec.pos_2key_datum, min_ada + d_reg + freeze_bond, forged)
}

test register_small_rejects_undersized_bonded_reserve() fail {
  run_register(
    vec.pos_2key_datum,
    min_ada + d_reg + freeze_bond - 1,
    vec.pos_2key_evidence,
  )
}

test lifecycle_observer_registration_is_permissionless() {
  checkpoint_observer.observer_lifecycle.publish(
    0,
    hp_policy,
    d_reg,
    0,
    RegisterCredential { credential: Script(lifecycle_hash), deposit: Never },
    placeholder,
  )
}

test lifecycle_observer_deregistration_fails_closed() fail {
  checkpoint_observer.observer_lifecycle.publish(
    0,
    hp_policy,
    d_reg,
    0,
    UnregisterCredential { credential: Script(lifecycle_hash), refund: Never },
    placeholder,
  )
}

fn close_own_ref() -> OutputReference {
  OutputReference {
    transaction_id: close_vec.pos_2key_context.spent_txid,
    output_index: close_vec.pos_2key_context.spent_index,
  }
}

fn close_tx(evidence: CloseEvidence) -> Transaction {
  let context = close_vec.pos_2key_context
  let aid_name = deriveAidAssetName(context.old.cesr_aid)
  let bonded = min_ada + d_reg + freeze_bond
  let own_input = input_at(
    close_own_ref(),
    Output {
      address: from_script(policy),
      value: from_lovelace(bonded) |> merge(from_asset(policy, aid_name, 1)),
      datum: InlineDatum(V1(context.old)),
      reference_script: None,
    },
  )
  let refund = Output {
    address: evidence.refund_address,
    value: from_lovelace(bonded),
    datum: NoDatum,
    reference_script: None,
  }
  spend_context(
    [own_input],
    [],
    [refund],
    from_asset(policy, aid_name, -1),
    [],
    interval.everything,
    0,
  )
}

fn run_close(evidence: CloseEvidence) -> Bool {
  let tx = close_tx(evidence)
  checkpoint_register.checkpoint_register.mint(
    0,
    lifecycle_hash,
    1,
    d_reg,
    freeze_bond,
    CloseBurn { checkpoint_ref: close_own_ref() },
    policy,
    tx,
  ) && checkpoint_register.checkpoint_register.spend(
    0,
    lifecycle_hash,
    1,
    d_reg,
    freeze_bond,
    None,
    Close { evidence },
    close_own_ref(),
    tx,
  )
}

test close_small_accepts_controller_authorized_refund() {
  run_close(close_vec.pos_2key_evidence)
}

test close_small_rejects_unauthorized_controller() fail {
  run_close(close_vec.neg_below_threshold_evidence)
}
