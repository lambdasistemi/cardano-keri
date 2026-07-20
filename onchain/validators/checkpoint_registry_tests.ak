//// #116 S3 RED — full-context registry bootstrap and Register lineage.
////
//// These tests drive both real handlers. The mint-side Register fixture carries
//// the registry input/successor and its RecordRegistration redeemer; the
//// spend-side fixture carries the exact paired non-registry +1 mint.

use aiken/collection/list
use aiken/merkle_patricia_forestry.{Proof}
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id,
}
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Redeemer, ScriptPurpose,
  Spend, Transaction, placeholder,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as reg
use cardano_keri/checkpoint/role.{Registry}
use cardano_keri/checkpoint/unicity.{RegistryDatumV1}
use cardano_keri/checkpoint/unicity_vectors as vec
use checkpoint.{
  BootstrapRegistry, Close, RecordRegistration, Register, SpendRedeemer,
}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

const d_reg: Int = 5_000_000

const registry_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 9 }

fn registry_value() -> Value {
  from_lovelace(min_ada)
    |> merge(from_asset(policy, vec.registry_thread_name, 1))
}

fn registry_output(root: ByteArray) -> Output {
  Output {
    address: role.address(policy, Registry),
    value: registry_value(),
    datum: InlineDatum(RegistryDatumV1 { root }),
    reference_script: None,
  }
}

fn registry_input(root: ByteArray) -> Input {
  input_at(registry_ref, registry_output(root))
}

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

fn state_output(aid_name: ByteArray, d: CheckpointDatumV1) -> Output {
  Output {
    address: from_script(policy),
    value: from_lovelace(reg.pos_2key_lovelace)
      |> merge(from_asset(policy, aid_name, 1)),
    datum: InlineDatum(V1(d)),
    reference_script: None,
  }
}

fn register_mint(aid_name: ByteArray, proof_name: ByteArray) -> Value {
  from_asset(policy, aid_name, 1)
    |> merge(from_asset(hp_policy, proof_name, -1))
}

fn paired_redeemers(ref: OutputReference) -> Pairs<ScriptPurpose, Redeemer> {
  let registry_redeemer: Data = RecordRegistration
  [Pair(Spend(ref), registry_redeemer)]
}

fn register_tx(
  old_root: ByteArray,
  new_root: ByteArray,
  e: RegistrationEvidence,
) -> Transaction {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  let proof_name = proof_token_name(e.event_bytes, reg.pos_2key_datum.cesr_aid)
  Transaction {
    ..mint_context(
      [proof_input(proof_name), registry_input(old_root)],
      [state_output(aid_name, reg.pos_2key_datum), registry_output(new_root)],
      register_mint(aid_name, proof_name),
    ),
    redeemers: paired_redeemers(registry_ref),
  }
}

fn run_register(proof: Proof, tx: Transaction) -> Bool {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    vec.registry_seed,
    Register {
      evidence: reg.pos_2key_evidence,
      registry_ref,
      absence_proof: proof,
    },
    policy,
    tx,
  )
}

fn run_record(rdm: SpendRedeemer, tx: Transaction) -> Bool {
  let datum_data: Data = RegistryDatumV1 { root: vec.depth_0_old_root }
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    vec.registry_seed,
    Some(datum_data),
    rdm,
    registry_ref,
    tx,
  )
}

fn honest_register_tx() -> Transaction {
  register_tx(vec.depth_0_old_root, vec.depth_0_new_root, reg.pos_2key_evidence)
}

fn record_tx(mint: Value) -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [registry_input(vec.depth_0_old_root)],
    outputs: [registry_output(vec.depth_0_new_root)],
    mint,
  }
}

fn bootstrap_tx(
  inputs: List<Input>,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  mint_context(inputs, outputs, mint)
}

fn seed_input() -> Input {
  input_at(
    vec.registry_seed,
    Output {
      address: from_verification_key(owner_vkh),
      value: from_lovelace(min_ada),
      datum: NoDatum,
      reference_script: None,
    },
  )
}

fn run_bootstrap(tx: Transaction) -> Bool {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    vec.registry_seed,
    BootstrapRegistry,
    policy,
    tx,
  )
}

fn honest_bootstrap_tx() -> Transaction {
  bootstrap_tx(
    [seed_input()],
    [registry_output(vec.empty_root)],
    from_asset(policy, vec.registry_thread_name, 1),
  )
}

// U1 — exact registry input identity, address, token, and datum.

test accept_registry_gated_register_depth_0() {
  run_register(vec.depth_0_proof, honest_register_tx())
}

test reject_u1_absent_registry_input() fail {
  let tx = honest_register_tx()
  expect Some(first) = list.head(tx.inputs)
  run_register(vec.depth_0_proof, Transaction { ..tx, inputs: [first] })
}

test reject_u1_wrong_registry_reference() fail {
  let tx = honest_register_tx()
  let wrong = OutputReference { ..registry_ref, output_index: 10 }
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    vec.registry_seed,
    Register {
      evidence: reg.pos_2key_evidence,
      registry_ref: wrong,
      absence_proof: vec.depth_0_proof,
    },
    policy,
    tx,
  )
}

test reject_u1_wrong_registry_thread_token() fail {
  let tx = honest_register_tx()
  let bad = input_at(
    registry_ref,
    Output {
      ..registry_output(vec.depth_0_old_root),
      value: from_lovelace(min_ada) |> merge(from_asset(policy, #"bad0", 1)),
    },
  )
  expect Some(first) = list.head(tx.inputs)
  run_register(vec.depth_0_proof, Transaction { ..tx, inputs: [first, bad] })
}

test reject_u1_active_address_used_for_registry() fail {
  let tx = honest_register_tx()
  let bad = input_at(
    registry_ref,
    Output {
      ..registry_output(vec.depth_0_old_root),
      address: from_script(policy),
    },
  )
  expect Some(first) = list.head(tx.inputs)
  run_register(vec.depth_0_proof, Transaction { ..tx, inputs: [first, bad] })
}

test reject_u1_missing_registry_datum() fail {
  let tx = honest_register_tx()
  let bad = input_at(
    registry_ref,
    Output { ..registry_output(vec.depth_0_old_root), datum: NoDatum },
  )
  expect Some(first) = list.head(tx.inputs)
  run_register(vec.depth_0_proof, Transaction { ..tx, inputs: [first, bad] })
}

// U2 — proof/root transition and complete-value continuity.

test reject_u2_wrong_absence_proof() fail {
  run_register(vec.depth_16_proof, honest_register_tx())
}

test reject_u2_present_key_insert() fail {
  run_register(
    vec.depth_0_proof,
    register_tx(
      vec.depth_0_new_root,
      vec.depth_0_new_root,
      reg.pos_2key_evidence,
    ),
  )
}

test reject_u2_wrong_successor_root() fail {
  run_register(
    vec.depth_0_proof,
    register_tx(vec.depth_0_old_root, #"ffffffff", reg.pos_2key_evidence),
  )
}

test reject_u2_changed_registry_value() fail {
  let tx = honest_register_tx()
  let changed = Output {
    ..registry_output(vec.depth_0_new_root),
    value: registry_value() |> merge(from_lovelace(1)),
  }
  expect Some(first) = list.head(tx.outputs)
  run_register(
    vec.depth_0_proof,
    Transaction { ..tx, outputs: [first, changed] },
  )
}

test reject_u2_root_rollback() fail {
  run_register(
    vec.depth_0_proof,
    register_tx(
      vec.depth_0_old_root,
      vec.depth_0_old_root,
      reg.pos_2key_evidence,
    ),
  )
}

test reject_u2_stale_root_proof() fail {
  run_register(
    vec.depth_8_proof,
    register_tx(
      vec.depth_16_old_root,
      vec.depth_8_new_root,
      reg.pos_2key_evidence,
    ),
  )
}

// U3 — the mint and registry-spend halves are inseparable.

test reject_u3_register_without_record_registration() fail {
  let tx = honest_register_tx()
  run_register(vec.depth_0_proof, Transaction { ..tx, redeemers: [] })
}

test reject_u3_register_with_wrong_registry_redeemer() fail {
  let tx = honest_register_tx()
  let close_redeemer: Data = Close
  run_register(
    vec.depth_0_proof,
    Transaction { ..tx, redeemers: [Pair(Spend(registry_ref), close_redeemer)] },
  )
}

test accept_u3_record_registration_with_exact_non_registry_plus_one() {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  run_record(RecordRegistration, record_tx(from_asset(policy, aid_name, 1)))
}

test reject_u3_record_without_paired_mint() fail {
  run_record(RecordRegistration, record_tx(zero))
}

test reject_u3_record_with_quantity_two() fail {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  run_record(RecordRegistration, record_tx(from_asset(policy, aid_name, 2)))
}

test reject_u3_record_with_duplicate_asset_names() fail {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  run_record(
    RecordRegistration,
    record_tx(
      from_asset(policy, aid_name, 1)
        |> merge(from_asset(policy, #"a110", 1)),
    ),
  )
}

test reject_u3_record_with_registry_thread_mint() fail {
  run_record(
    RecordRegistration,
    record_tx(from_asset(policy, vec.registry_thread_name, 1)),
  )
}

// U4 — one-shot bootstrap and permanent thread confinement.

test accept_u4_first_registry_bootstrap() {
  run_bootstrap(honest_bootstrap_tx())
}

test reject_u4_second_bootstrap_replay_without_seed() fail {
  let tx = honest_bootstrap_tx()
  run_bootstrap(Transaction { ..tx, inputs: [] })
}

test reject_u4_seed_absent() fail {
  run_bootstrap(
    bootstrap_tx(
      [],
      [registry_output(vec.empty_root)],
      from_asset(policy, vec.registry_thread_name, 1),
    ),
  )
}

test reject_u4_thread_smuggled_to_active_output() fail {
  let smuggled = Output {
    ..registry_output(vec.empty_root),
    address: from_script(policy),
  }
  run_bootstrap(
    bootstrap_tx(
      [seed_input()],
      [smuggled],
      from_asset(policy, vec.registry_thread_name, 1),
    ),
  )
}

test reject_u4_thread_burn() fail {
  run_record(
    RecordRegistration,
    record_tx(from_asset(policy, vec.registry_thread_name, -1)),
  )
}

test reject_u4_thread_remint() fail {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  run_record(
    RecordRegistration,
    record_tx(
      from_asset(policy, aid_name, 1)
        |> merge(from_asset(policy, vec.registry_thread_name, 1)),
    ),
  )
}

test reject_u4_duplicate_registry_successor() fail {
  let tx = honest_register_tx()
  run_register(
    vec.depth_0_proof,
    Transaction {
      ..tx,
      outputs: list.concat(tx.outputs, [registry_output(vec.depth_0_new_root)]),
    },
  )
}

test reject_u4_missing_registry_successor() fail {
  let tx = honest_register_tx()
  expect Some(first) = list.head(tx.outputs)
  run_register(vec.depth_0_proof, Transaction { ..tx, outputs: [first] })
}

test reject_u4_registry_delete_attempt() fail {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  let tx = record_tx(from_asset(policy, aid_name, 1))
  run_record(RecordRegistration, Transaction { ..tx, outputs: [] })
}

test reject_u4_registry_update_attempt_with_wrong_redeemer() fail {
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  run_record(Close, record_tx(from_asset(policy, aid_name, 1)))
}

// U5 — one root cannot authorize two registrations for the same AID.

test reject_u5_two_same_aid_registrations_from_one_root() fail {
  let tx = honest_register_tx()
  expect Some(duplicate_state) = list.head(tx.outputs)
  let duplicate_registry = registry_output(vec.depth_0_new_root)
  let aid_name = deriveAidAssetName(reg.pos_2key_datum.cesr_aid)
  run_register(
    vec.depth_0_proof,
    Transaction {
      ..tx,
      outputs: list.concat(tx.outputs, [duplicate_state, duplicate_registry]),
      mint: tx.mint |> merge(from_asset(policy, aid_name, 1)),
    },
  )
}

test reject_u5_no_reregistration_after_presence() fail {
  run_register(
    vec.depth_0_proof,
    register_tx(
      vec.depth_0_new_root,
      vec.depth_0_new_root,
      reg.pos_2key_evidence,
    ),
  )
}
