//// #136 — real-script tests for the register-only checkpoint vertical.

use aiken/interval
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
  placeholder,
}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/advance_vectors as advance_vec
use cardano_keri/checkpoint/close.{CloseEvidence}
use cardano_keri/checkpoint/close_vectors as close_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint_observer
use checkpoint_register.{Advance, Close, CloseBurn, Register}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const lifecycle_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const advance_hash: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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
    advance_hash,
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
    advance_hash,
    1,
    d_reg,
    freeze_bond,
    CloseBurn { checkpoint_ref: close_own_ref() },
    policy,
    tx,
  ) && checkpoint_register.checkpoint_register.spend(
    0,
    lifecycle_hash,
    advance_hash,
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

// ---------------------------------------------------------------------
// #142 RED — the small checkpoint surface must admit the already-ratified
// two-key KERI rotation and reject the three named authorization failures.
// `Advance` is deliberately absent from checkpoint_register until GREEN.
// ---------------------------------------------------------------------

const rotate_deposit: Int = min_ada + d_reg

fn rotate_old(spent: SpentCheckpoint) -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: spent.cesr_aid,
    cur_keys: [
      #"bf1145e4449d74e9f09bd6aaffcbcd295f2a82e9fcbb5689c5346b3c274bccbb",
      #"95d507a9923dc62701d5619c117a3cbb8ae91cfe3f99e96cc0ae986cb52b586d",
    ],
    cur_threshold: Unweighted(2),
    next_keys: spent.next_keys,
    next_threshold: spent.next_threshold,
    witnesses: spent.witnesses,
    toad: 2,
    seq: spent.seq,
    native_sn: spent.native_sn,
  }
}

fn rotate_ref(spent: SpentCheckpoint) -> OutputReference {
  out_ref(spent.txid, spent.index)
}

fn rotate_value(spent: SpentCheckpoint) -> Value {
  from_lovelace(rotate_deposit)
    |> merge(from_asset(policy, spent.aid_asset_name, 1))
}

fn rotate_tx(spent: SpentCheckpoint, created: CheckpointDatumV1) -> Transaction {
  let own_input = input_at(
    rotate_ref(spent),
    Output {
      address: from_script(policy),
      value: rotate_value(spent),
      datum: InlineDatum(V1(rotate_old(spent))),
      reference_script: None,
    },
  )
  let successor = Output {
    address: from_script(policy),
    value: rotate_value(spent),
    datum: InlineDatum(V1(created)),
    reference_script: None,
  }
  spend_context([own_input], [], [successor], zero, [], interval.everything, 0)
}

fn advance_envelope(
  spent: SpentCheckpoint,
  evidence: AdvanceEvidence,
) -> ObserverEnvelope {
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_advance,
      checkpoint_policy: policy,
      own_ref: Some(rotate_ref(spent)),
    },
    payload: evidence,
  }
}

fn with_advance_observer(
  tx: Transaction,
  envelope: ObserverEnvelope,
) -> Transaction {
  let credential = Script(advance_hash)
  let redeemer: Data = envelope
  Transaction {
    ..tx,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

fn run_rotate_small(
  spent: SpentCheckpoint,
  created: CheckpointDatumV1,
  evidence: AdvanceEvidence,
) -> Bool {
  let envelope = advance_envelope(spent, evidence)
  let tx = with_advance_observer(rotate_tx(spent, created), envelope)
  checkpoint_register.checkpoint_register.spend(
    0,
    lifecycle_hash,
    advance_hash,
    1,
    d_reg,
    freeze_bond,
    None,
    Advance,
    rotate_ref(spent),
    tx,
  ) && advance_predicate(spent, created, evidence) == AdvancePredicateValid
}

test rotate_small_rejects_missing_advance_observer() fail {
  let spent = advance_vec.pos_adv_wit_2key_spent
  checkpoint_register.checkpoint_register.spend(
    0,
    lifecycle_hash,
    advance_hash,
    1,
    d_reg,
    freeze_bond,
    None,
    Advance,
    rotate_ref(spent),
    rotate_tx(spent, advance_vec.pos_adv_wit_2key_created),
  )
}

test rotate_small_accepts_witnessed_two_key_rotation() {
  run_rotate_small(
    advance_vec.pos_adv_wit_2key_spent,
    advance_vec.pos_adv_wit_2key_created,
    advance_vec.pos_adv_wit_2key_evidence,
  )
}

test rotate_small_rejects_stolen_current_keys() fail {
  run_rotate_small(
    advance_vec.ctrl_stolen_quorum_spent,
    advance_vec.ctrl_stolen_quorum_created,
    advance_vec.ctrl_stolen_quorum_evidence,
  )
}

test rotate_small_rejects_below_successor_threshold() fail {
  run_rotate_small(
    advance_vec.ctrl_below_threshold_spent,
    advance_vec.ctrl_below_threshold_created,
    advance_vec.ctrl_below_threshold_evidence,
  )
}

test rotate_small_rejects_under_witnessed_rotation() fail {
  run_rotate_small(
    advance_vec.v7_receipt_free_spent,
    advance_vec.v7_receipt_free_created,
    advance_vec.v7_receipt_free_evidence,
  )
}

test rotate_small_rejects_changed_successor_value() fail {
  let spent = advance_vec.pos_adv_wit_2key_spent
  let tx = rotate_tx(spent, advance_vec.pos_adv_wit_2key_created)
  expect [successor] = tx.outputs
  let changed_successor = Output {
    ..successor,
    value: from_lovelace(rotate_deposit + 1)
      |> merge(from_asset(policy, spent.aid_asset_name, 1)),
  }
  checkpoint_register.checkpoint_register.spend(
    0,
    lifecycle_hash,
    advance_hash,
    1,
    d_reg,
    freeze_bond,
    None,
    Advance,
    rotate_ref(spent),
    with_advance_observer(
      Transaction { ..tx, outputs: [changed_successor] },
      advance_envelope(spent, advance_vec.pos_adv_wit_2key_evidence),
    ),
  )
}
