//// Unit and context tests for checkpoint_observer validator.

use aiken/interval
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, TombstoneV1}
use cardano_keri/checkpoint/enforcement_vectors as enf_vec
use cardano_keri/checkpoint/freeze_bond.{ArmedV1}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_freeze, observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/role.{
  Active, Armed, Frozen, Tombstone, address as role_address,
}
use checkpoint_observer

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

const hunter_pkh: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fn value_input(index: Int, value: Value) -> Input {
  input_at(
    out_ref(seed_tx_id, index),
    Output {
      address: from_verification_key(owner_vkh),
      value,
      datum: NoDatum,
      reference_script: None,
    },
  )
}

fn proof_input(name: ByteArray) -> Input {
  value_input(
    0,
    from_lovelace(min_ada) |> merge(from_asset(hp_policy, name, 1)),
  )
}

fn state_output(
  aid_name: ByteArray,
  lovelace: Int,
  d: CheckpointDatumV1,
) -> Output {
  Output {
    address: from_script(policy),
    value: from_lovelace(lovelace) |> merge(from_asset(policy, aid_name, 1)),
    datum: InlineDatum(V1(d)),
    reference_script: None,
  }
}

fn register_mint(aid_name: ByteArray, proof_name: ByteArray) -> Value {
  from_asset(policy, aid_name, 1)
    |> merge(from_asset(hp_policy, proof_name, -1))
}

fn register_tx(
  d: CheckpointDatumV1,
  lovelace: Int,
  e: RegistrationEvidence,
) -> Transaction {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let proof_name = proof_token_name(e.event_bytes, d.cesr_aid)
  mint_context(
    [proof_input(proof_name)],
    [state_output(aid_name, lovelace, d)],
    register_mint(aid_name, proof_name),
  )
}

test t115_r1_accept_observer_register_positive() {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: vec.pos_2key_evidence }
  let tx = register_tx(
    vec.pos_2key_datum,
    min_ada + d_reg + freeze_bond,
    vec.pos_2key_evidence,
  )
  run_lifecycle_withdraw(envelope, tx)
}

test t115_r1_reject_observer_register_evidence_canary_invalid_sig() fail {
  let bad_evidence = RegistrationEvidence {
    ..vec.pos_2key_evidence,
    ctrl_sigs: [],
  }
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: bad_evidence }
  let tx = register_tx(
    vec.pos_2key_datum,
    min_ada + d_reg + freeze_bond,
    vec.pos_2key_evidence,
  )
  run_lifecycle_withdraw(envelope, tx)
}

/// Ported from checkpoint_tests.ak's
/// t114_r3_reject_old_message_only_controller_signatures: the stale-message
/// controller signatures now fail the registration predicate in the observer.
test t115_r1_reject_observer_register_old_message_only_controller_sigs() fail {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: vec.r7_old_message_sigs_evidence,
  }
  let tx = register_tx(
    vec.r7_old_message_sigs_datum,
    min_ada + d_reg + freeze_bond,
    vec.r7_old_message_sigs_evidence,
  )
  run_lifecycle_withdraw(envelope, tx)
}

/// Ported from checkpoint_tests.ak's
/// t114_r3_reject_bad_controller_signature_threshold: the under-threshold
/// controller signatures now fail in the observer.
test t115_r1_reject_observer_register_bad_controller_sig_threshold() fail {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: vec.r7_below_threshold_evidence,
  }
  let tx = register_tx(
    vec.r7_below_threshold_datum,
    min_ada + d_reg + freeze_bond,
    vec.r7_below_threshold_evidence,
  )
  run_lifecycle_withdraw(envelope, tx)
}

/// Ported from checkpoint_tests.ak's
/// t114_r3_reject_bad_witness_receipt_threshold: the bad witness receipts now
/// fail in the observer.
test t115_r1_reject_observer_register_bad_witness_receipt_threshold() fail {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: vec.r7_receipts_bad_signature_evidence,
  }
  let tx = register_tx(
    vec.r7_receipts_bad_signature_datum,
    min_ada + d_reg + freeze_bond,
    vec.r7_receipts_bad_signature_evidence,
  )
  run_lifecycle_withdraw(envelope, tx)
}

const honest2_freeze_wire: EnforcementEvidence =
  EnforcementEvidence {
    event_bytes: enf_vec.honest2_freeze_evidence.event_bytes,
    off_t: 30,
    off_i: 91,
    off_s: 142,
    off_d: 40,
    off_k: [211, 258],
    off_kt: 202,
    off_n: [320, 367],
    off_nt: 311,
    off_bt: 420,
    native_sn: enf_vec.honest2_freeze_evidence.native_sn,
    said: enf_vec.honest2_freeze_evidence.said,
    revealed_keys: enf_vec.honest2_freeze_evidence.revealed_keys,
    next_keys: enf_vec.honest2_freeze_evidence.next_keys,
    cur_threshold: enf_vec.honest2_freeze_evidence.cur_threshold,
    next_threshold: enf_vec.honest2_freeze_evidence.next_threshold,
    toad: enf_vec.honest2_freeze_evidence.toad,
    ctrl_sigs: enf_vec.honest2_freeze_evidence.ctrl_sigs,
    wit_sigs: enf_vec.honest2_freeze_evidence.wit_sigs,
  }

test t115_r1_accept_observer_freeze_positive() {
  let own_ref = out_ref(seed_tx_id, 7)
  let d = enf_vec.honest2_freeze_tip
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let val = from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, aid_name, 1))
  let tx = spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: from_script(policy),
          value: val,
          datum: InlineDatum(V1(d)),
          reference_script: None,
        },
      ),
    ],
    [],
    [],
    zero,
    [],
    interval.everything,
    0,
  )
  let claim = ObserverClaim {
    action: observe_freeze,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope { claim, payload: honest2_freeze_wire }
  run_enforcement_withdraw(envelope, tx)
}

test t115_r1_reject_observer_freeze_canary_corrupted_sig() fail {
  let own_ref = out_ref(seed_tx_id, 7)
  let d = enf_vec.honest2_freeze_tip
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let val = from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, aid_name, 1))
  let tx = spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: from_script(policy),
          value: val,
          datum: InlineDatum(V1(d)),
          reference_script: None,
        },
      ),
    ],
    [],
    [],
    zero,
    [],
    interval.everything,
    0,
  )
  let bad_evidence = EnforcementEvidence {
    ..honest2_freeze_wire,
    ctrl_sigs: [],
  }
  let claim = ObserverClaim {
    action: observe_freeze,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope { claim, payload: bad_evidence }
  run_enforcement_withdraw(envelope, tx)
}

/// Build a freeze observer context over the lag wire/tip (mirrors the
/// checkpoint_tests.ak R2 arm negatives these were ported from).
fn lag_freeze_observer_tx(d: CheckpointDatumV1) -> Transaction {
  let own_ref = out_ref(seed_tx_id, 7)
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let val = from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, aid_name, 1))
  spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: from_script(policy),
          value: val,
          datum: InlineDatum(V1(d)),
          reference_script: None,
        },
      ),
    ],
    [],
    [],
    zero,
    [],
    interval.everything,
    0,
  )
}

fn run_lag_freeze_observer(d: CheckpointDatumV1, evidence: Data) -> Bool {
  let own_ref = out_ref(seed_tx_id, 7)
  let claim = ObserverClaim {
    action: observe_freeze,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope { claim, payload: evidence }
  run_enforcement_withdraw(envelope, lag_freeze_observer_tx(d))
}

/// Ported from checkpoint_tests.ak's t116_r2_reject_arm_live_ee_binding_mutation:
/// the EE-binding slice mutation is now rejected by the observer, not the
/// checkpoint.
test t115_r1_reject_observer_freeze_ee_binding_mutation() fail {
  let evidence = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    off_i: enf_vec.lag_freeze_wire.off_s,
  }
  run_lag_freeze_observer(enf_vec.lag_freeze_tip, evidence)
}

/// Ported from checkpoint_tests.ak's
/// t116_r2_reject_arm_live_freeze_predicate_replay: the replayed native_sn now
/// fails the freeze predicate in the observer.
test t115_r1_reject_observer_freeze_predicate_replay() fail {
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, native_sn: 1 }
  run_lag_freeze_observer(tip, enf_vec.lag_freeze_wire)
}

/// Ported from checkpoint_tests.ak's
/// t116_r2_reject_arm_live_duplicate_receipt_quorum: the duplicated receipt
/// quorum now fails the freeze predicate in the observer.
test t115_r1_reject_observer_freeze_duplicate_receipt_quorum() fail {
  expect [receipt] = enf_vec.lag_freeze_wire.wit_sigs
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, toad: 2 }
  let evidence = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    wit_sigs: [receipt, receipt],
  }
  run_lag_freeze_observer(tip, evidence)
}

/// Build a convict observer context: the named checkpoint input plus the
/// Tombstone-role output carrying the TombstoneV1 datum whose evidence_said
/// the observer binds to the decoded evidence SAID (A-003 Option C).
fn convict_observer_tx(
  own_ref: OutputReference,
  d: CheckpointDatumV1,
  evidence_said: ByteArray,
) -> Transaction {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let val = from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, aid_name, 1))
  spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: from_script(policy),
          value: val,
          datum: InlineDatum(V1(d)),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: role_address(policy, Tombstone),
        value: from_lovelace(min_ada) |> merge(from_asset(policy, aid_name, 1)),
        datum: InlineDatum(
          TombstoneV1 {
            cesr_aid: d.cesr_aid,
            convicted_at_native_sn: d.native_sn,
            evidence_said,
          },
        ),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.everything,
    0,
  )
}

fn run_convict_observer(
  own_ref: OutputReference,
  d: CheckpointDatumV1,
  evidence: EnforcementEvidence,
) -> Bool {
  let claim = ObserverClaim {
    action: observe_convict,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope { claim, payload: evidence }
  run_enforcement_withdraw(
    envelope,
    convict_observer_tx(own_ref, d, evidence.said),
  )
}

/// Build an ARMED-shaped convict observer context: the named input sits at
/// the Armed role address carrying an `ArmedV1` wrapper datum (the shape a
/// real Convict-from-ARMED transaction spends), plus the Tombstone output.
fn armed_convict_observer_tx(
  own_ref: OutputReference,
  d: CheckpointDatumV1,
  evidence_said: ByteArray,
) -> Transaction {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let val = from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, aid_name, 1))
  spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: role_address(policy, Armed),
          value: val,
          datum: InlineDatum(
            ArmedV1 { checkpoint: d, hunter_pkh, deadline: 1_000 },
          ),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: role_address(policy, Tombstone),
        value: from_lovelace(min_ada) |> merge(from_asset(policy, aid_name, 1)),
        datum: InlineDatum(
          TombstoneV1 {
            cesr_aid: d.cesr_aid,
            convicted_at_native_sn: d.native_sn,
            evidence_said,
          },
        ),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.everything,
    0,
  )
}

/// RED (navigator green-review defect): ObserveConvict must resolve an
/// ARMED-shaped own input to its inner checkpoint datum. The frozen
/// architecture names ARMED as a required Convict-admitting role and
/// checkpoint.ak's validate_convict_armed admits it, so the observer must
/// process the same ARMED input. This currently FAILS: the shared
/// enforcement front-path decodes only a direct CheckpointDatum.V1 and
/// panics on the ArmedV1 wrapper.
test t115_r1_accept_observer_convict_armed_positive() {
  let own_ref = out_ref(seed_tx_id, 6)
  let claim = ObserverClaim {
    action: observe_convict,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: enf_vec.fork_witnessed_convict_wire,
  }
  run_enforcement_withdraw(
    envelope,
    armed_convict_observer_tx(
      own_ref,
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire.said,
    ),
  )
}

/// Build a FROZEN-shaped convict observer context: the named input sits at
/// the Frozen role address carrying a direct `CheckpointDatum.V1` datum (the
/// shape a real Convict-from-FROZEN transaction spends), plus the Tombstone
/// output.
fn frozen_convict_observer_tx(
  own_ref: OutputReference,
  d: CheckpointDatumV1,
  evidence_said: ByteArray,
) -> Transaction {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let val = from_lovelace(min_ada + d_reg)
    |> merge(from_asset(policy, aid_name, 1))
  spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: role_address(policy, Frozen),
          value: val,
          datum: InlineDatum(V1(d)),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: role_address(policy, Tombstone),
        value: from_lovelace(min_ada) |> merge(from_asset(policy, aid_name, 1)),
        datum: InlineDatum(
          TombstoneV1 {
            cesr_aid: d.cesr_aid,
            convicted_at_native_sn: d.native_sn,
            evidence_said,
          },
        ),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.everything,
    0,
  )
}

/// Regression guard: ObserveConvict must resolve a FROZEN-shaped own input
/// (direct V1 datum) to its inner checkpoint datum. This passes on the
/// current direct-V1 path and must keep passing after the ARMED unwrap fix.
test t115_r1_accept_observer_convict_frozen_positive() {
  let own_ref = out_ref(seed_tx_id, 6)
  let claim = ObserverClaim {
    action: observe_convict,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: enf_vec.fork_witnessed_convict_wire,
  }
  run_enforcement_withdraw(
    envelope,
    frozen_convict_observer_tx(
      own_ref,
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire.said,
    ),
  )
}

test t115_r1_accept_observer_convict_positive() {
  let own_ref = out_ref(seed_tx_id, 6)
  run_convict_observer(
    own_ref,
    enf_vec.fork_witnessed_convict_tip,
    enf_vec.fork_witnessed_convict_wire,
  )
}

test t115_r1_reject_observer_convict_canary_corrupted_wire() fail {
  let own_ref = out_ref(seed_tx_id, 6)
  let bad_evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    ctrl_sigs: [],
  }
  run_convict_observer(
    own_ref,
    enf_vec.fork_witnessed_convict_tip,
    bad_evidence,
  )
}

/// Ported from checkpoint_tests.ak's t116_r3_reject_live_ee_binding_mutation:
/// the EE-binding slice mutation is now rejected by the observer.
test t115_r1_reject_observer_convict_ee_binding_mutation() fail {
  let own_ref = out_ref(seed_tx_id, 6)
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    off_i: enf_vec.fork_witnessed_convict_wire.off_s,
  }
  run_convict_observer(own_ref, enf_vec.fork_witnessed_convict_tip, evidence)
}

/// Ported from checkpoint_tests.ak's t116_r3_reject_live_no_conflict_axis: an
/// honest (non-conflicting) wire no longer convicts in the observer.
test t115_r1_reject_observer_convict_no_conflict_axis() fail {
  let own_ref = out_ref(seed_tx_id, 6)
  run_convict_observer(
    own_ref,
    enf_vec.fork_witnessed_honest_tip,
    enf_vec.fork_witnessed_honest_wire,
  )
}

/// Ported from checkpoint_tests.ak's
/// t116_r3_reject_live_insufficient_witness_receipts: the under-witnessed wire
/// now fails the convict predicate in the observer.
test t115_r1_reject_observer_convict_insufficient_witness_receipts() fail {
  let own_ref = out_ref(seed_tx_id, 6)
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    wit_sigs: [],
  }
  run_convict_observer(own_ref, enf_vec.fork_witnessed_convict_tip, evidence)
}

/// Ported from checkpoint_tests.ak's
/// t116_r3_reject_duplicate_receipt_does_not_fake_distinct_witnesses: the
/// duplicated receipt no longer fakes a distinct quorum in the observer.
test t115_r1_reject_observer_convict_duplicate_receipt() fail {
  expect [receipt] = enf_vec.fork_witnessed_convict_wire.wit_sigs
  let own_ref = out_ref(seed_tx_id, 6)
  let tip = CheckpointDatumV1 { ..enf_vec.fork_witnessed_convict_tip, toad: 2 }
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    wit_sigs: [receipt, receipt],
  }
  run_convict_observer(own_ref, tip, evidence)
}

/// A-003 Option C: the observer binds the tombstone output's evidence_said to
/// the decoded evidence SAID, so a wrong recorded SAID rejects here (ported
/// from checkpoint_tests.ak's t116_r3_reject_wrong_tombstone_record).
test t115_r1_reject_observer_convict_wrong_tombstone_said() fail {
  let own_ref = out_ref(seed_tx_id, 6)
  let wrong_said = #"1111111111111111111111111111111111111111111111111111111111111111"
  let claim = ObserverClaim {
    action: observe_convict,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: enf_vec.fork_witnessed_convict_wire,
  }
  run_enforcement_withdraw(
    envelope,
    convict_observer_tx(own_ref, enf_vec.fork_witnessed_convict_tip, wrong_said),
  )
}

// ---------------------------------------------------------------------
// A-004 family split RED — observer dispatch by family
// ---------------------------------------------------------------------
// These tests reference the family-split validators observer_lifecycle and
// observer_enforcement, which do not exist yet in the single-observer
// production partition. They are the honest RED for the absent family-split
// API: they fail to compile/run because those validator blocks are absent.

/// Drive the observer_lifecycle withdraw handler (version, hash_proof_policy,
/// d_reg). ABSENT in the current single-observer partition.
fn run_lifecycle_withdraw(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  checkpoint_observer.observer_lifecycle.withdraw(
    0,
    hp_policy,
    d_reg,
    envelope,
    0,
    tx,
  )
}

/// Drive the observer_enforcement withdraw handler (version only). ABSENT in
/// the current single-observer partition.
fn run_enforcement_withdraw(envelope: ObserverEnvelope, tx: Transaction) -> Bool {
  checkpoint_observer.observer_enforcement.withdraw(0, envelope, 0, tx)
}

// --- lifecycle dispatch: accepts Register, rejects Freeze/Convict/Advance ---

test t115_r1_lifecycle_accepts_register() {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: vec.pos_2key_evidence }
  let tx = register_tx(
    vec.pos_2key_datum,
    min_ada + d_reg + freeze_bond,
    vec.pos_2key_evidence,
  )
  run_lifecycle_withdraw(envelope, tx)
}

test t115_r1_lifecycle_rejects_freeze() fail {
  let own_ref = out_ref(seed_tx_id, 7)
  let claim = ObserverClaim {
    action: observe_freeze,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope { claim, payload: honest2_freeze_wire }
  run_lifecycle_withdraw(
    envelope,
    lag_freeze_observer_tx(enf_vec.lag_freeze_tip),
  )
}

test t115_r1_lifecycle_rejects_convict() fail {
  let own_ref = out_ref(seed_tx_id, 6)
  let claim = ObserverClaim {
    action: observe_convict,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: enf_vec.fork_witnessed_convict_wire,
  }
  run_lifecycle_withdraw(
    envelope,
    convict_observer_tx(
      own_ref,
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire.said,
    ),
  )
}

test t115_r1_lifecycle_rejects_advance_in_r1() fail {
  let claim = ObserverClaim {
    action: observe_advance,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: 0 }
  run_lifecycle_withdraw(envelope, placeholder)
}

// --- enforcement dispatch: accepts Freeze/Convict, rejects Register/Advance ---

test t115_r1_enforcement_accepts_freeze() {
  let own_ref = out_ref(seed_tx_id, 7)
  let claim = ObserverClaim {
    action: observe_freeze,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope { claim, payload: enf_vec.lag_freeze_wire }
  run_enforcement_withdraw(
    envelope,
    lag_freeze_observer_tx(enf_vec.lag_freeze_tip),
  )
}

test t115_r1_enforcement_accepts_convict() {
  let own_ref = out_ref(seed_tx_id, 6)
  let claim = ObserverClaim {
    action: observe_convict,
    checkpoint_policy: policy,
    own_ref: Some(own_ref),
  }
  let envelope = ObserverEnvelope {
    claim,
    payload: enf_vec.fork_witnessed_convict_wire,
  }
  run_enforcement_withdraw(
    envelope,
    convict_observer_tx(
      own_ref,
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire.said,
    ),
  )
}

test t115_r1_enforcement_rejects_register() fail {
  let claim = ObserverClaim {
    action: observe_register,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: vec.pos_2key_evidence }
  let tx = register_tx(
    vec.pos_2key_datum,
    min_ada + d_reg + freeze_bond,
    vec.pos_2key_evidence,
  )
  run_enforcement_withdraw(envelope, tx)
}

test t115_r1_enforcement_rejects_advance_in_r1() fail {
  let claim = ObserverClaim {
    action: observe_advance,
    checkpoint_policy: policy,
    own_ref: None,
  }
  let envelope = ObserverEnvelope { claim, payload: 0 }
  run_enforcement_withdraw(envelope, placeholder)
}

// --- A-010 / T115-R2 certifying whitelist (typed RED) ---
//
// Each observer's stake credential is creatable once by anyone and removable
// by no one. The future publish/certifying handler must accept only the plain
// registration certificate for that observer's own script credential;
// UnregisterCredential and every other certificate constructor fail closed.
// These four tests call the future `.publish` handler with real Certificate
// constructors (not `.else` placeholders). They are RED until the production
// validator gains an exhaustive registration-only whitelist.

/// Applied observer_lifecycle script credential under test (28-byte hash).
const lifecycle_script_hash: ByteArray =
  #"0c785ee124129986e9584b017b647173c9b1f05aed1c4a91b2771d30"

/// Applied observer_enforcement script credential under test (28-byte hash).
const enforcement_script_hash: ByteArray =
  #"d7d22ccdb22fa1abffec72dcac1d28cd0ca07514e133e40131e7d534"

test t115_r2_lifecycle_accept_own_registration_cert() {
  let own = Script(lifecycle_script_hash)
  let cert = RegisterCredential { credential: own, deposit: Never }
  checkpoint_observer.observer_lifecycle.publish(
    0,
    hp_policy,
    d_reg,
    0,
    cert,
    placeholder,
  )
}

test t115_r2_lifecycle_reject_own_deregistration_cert() fail {
  let own = Script(lifecycle_script_hash)
  let cert = UnregisterCredential { credential: own, refund: Never }
  checkpoint_observer.observer_lifecycle.publish(
    0,
    hp_policy,
    d_reg,
    0,
    cert,
    placeholder,
  )
}

test t115_r2_enforcement_accept_own_registration_cert() {
  let own = Script(enforcement_script_hash)
  let cert = RegisterCredential { credential: own, deposit: Never }
  checkpoint_observer.observer_enforcement.publish(0, 0, cert, placeholder)
}

test t115_r2_enforcement_reject_own_deregistration_cert() fail {
  let own = Script(enforcement_script_hash)
  let cert = UnregisterCredential { credential: own, refund: Never }
  checkpoint_observer.observer_enforcement.publish(0, 0, cert, placeholder)
}
