//// Checkpoint `Register` branch ex-unit measurements (#114 S5 — the
//// A-001 QB-2 measurement gate).
////
//// Mirrors the `hash_proof_measurements.ak` precedent: every fixture is a
//// top-level `const` (folded at compile time, not charged to the measured
//// cost) and each `test measure_*` invokes the REAL
//// `checkpoint.checkpoint.mint` handler on its ACCEPT path over a full
//// Tx-B `Transaction`, so `aiken check --plain-numbers -m
//// measure_checkpoint` (justfile `measure-checkpoint`) reports the
//// mem/cpu of one honest registration per gate shape, against the mainnet
//// per-tx budget (memory 14,000,000; CPU 10,000,000,000).
////
//// Cells (the A-001 gate shapes, slice 5a / A-003): `reg_2key`
//// (unwitnessed 2-key), `reg_7key` (unwitnessed GLEIF-shaped 7-key — 7
//// Ed25519 verifications over the reconstructed preimage), and
//// `reg_witnessed` (3-witness toad-2, 2-of-2 signing). Each cell is the
//// FULL Register context: R1 mint shape, R2 ACTIVE-output checks, R5
//// proof-input lookup + burn-map check + blake2b proof-name recompute,
//// and the S3 predicate (R3 datum reconstruction, E1-E9 slices, R4
//// schema, R7 signatures, R8 deposit). The ≥25%-headroom verdict — STOP +
//// Q-file on a miss, never weakened checks — is the re-verifiable claim
//// in `specs/114-registration/MEASUREMENTS.md` (S6).
////
//// Builders are declared privately here because Aiken forbids `pub`
//// exports in a module importing a validator; they are the same Tx-B
//// shape as `checkpoint_tests.ak`'s `register_tx`.
////
//// This module adds NO validator behavior; measurement infrastructure only.

use aiken/interval
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{Address, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use cardano_keri/checkpoint/advance_vectors as adv_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, TombstoneV1}
use cardano_keri/checkpoint/enforcement_vectors as enf_vec
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/role.{Frozen, Tombstone}
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint.{Advance, Convict, Freeze, MintRedeemer, Register}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// Must equal the shared vectors' `checkpoint_policy_id` (the R7
/// signatures bind it via the reconstructed preimage).
const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

const d_reg: Int = 1_000_000_000

// ---------------------------------------------------------------------
// Tx-B builders (private mirror of checkpoint_tests.ak)
// ---------------------------------------------------------------------

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

// ---------------------------------------------------------------------
// one honest Tx-B per gate shape (consts: construction not charged)
// ---------------------------------------------------------------------

const tx_2key: Transaction =
  register_tx(vec.pos_2key_datum, vec.pos_2key_lovelace, vec.pos_2key_evidence)

const redeemer_2key: MintRedeemer = Register { evidence: vec.pos_2key_evidence }

const tx_7key: Transaction =
  register_tx(vec.pos_7key_datum, vec.pos_7key_lovelace, vec.pos_7key_evidence)

const redeemer_7key: MintRedeemer = Register { evidence: vec.pos_7key_evidence }

const tx_witnessed: Transaction =
  register_tx(
    vec.pos_witnessed_datum,
    vec.pos_witnessed_lovelace,
    vec.pos_witnessed_evidence,
  )

const redeemer_witnessed: MintRedeemer =
  Register { evidence: vec.pos_witnessed_evidence }

// reg_2key: 2 Ed25519 verifications, unweighted 2-of-2, no witnesses.
test measure_checkpoint_register_2key() {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    redeemer_2key,
    policy,
    tx_2key,
  )
}

// reg_7key (GLEIF shape): 7 Ed25519 verifications, weighted 7×1/3
// threshold, 7 E4 + 7 E6 slice checks over ~1 KiB of event bytes.
test measure_checkpoint_register_7key() {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    redeemer_7key,
    policy,
    tx_7key,
  )
}

// reg_witnessed (2-of-3 witnessed): 2 Ed25519 verifications plus the E8
// witness-slice set and rule-14 toad checks.
test measure_checkpoint_register_witnessed() {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    redeemer_witnessed,
    policy,
    tx_witnessed,
  )
}

// ---------------------------------------------------------------------
// Final ordinary thaw measurement (#116 S8). The FROZEN input retains the
// complete 1,000 ADA reference bond and the ACTIVE output carries it forward.
// The real Advance handler executes the full accepted no-delta rotation proof:
// V1/V2 role, datum, and token checks; V3 deposit; V4-V7 reconstruction,
// controller signatures, AE1-AE10 event binding, and witness receipt quorum.
//
// Advance vectors were generated under network_id = 1 (the Register cells
// above use 0) — the eq1 equality binds this value via the reconstructed
// preimage.

const adv_network_id: Int = 1

const advance_deposit: Int = min_ada + d_reg

/// OLD checkpoint datum: the real keripy `icp` key state this honest `rot`
/// advances FROM (mirrors checkpoint_tests.ak's identically named const —
/// `cur_keys`/`cur_threshold`/`toad` play no role in
/// `advance_predicate`, only `next_keys`/`next_threshold`/`witnesses`/
/// `seq`/`native_sn` do, reused byte-for-byte from the vectors' own
/// `..._spent` `SpentCheckpoint`).
const old_adv_keep: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: adv_vec.pos_adv_keep_spent.cesr_aid,
    cur_keys: [
      #"12ccc14d7d0a648007b1f4d80f915be8c822eceab255959ba4a9513de0ab9514",
      #"1ceb4e251e1c7ef619bfec5a2ab7515aa328b02b6379f5e7a1af6381f800a605",
    ],
    cur_threshold: Unweighted(2),
    next_keys: adv_vec.pos_adv_keep_spent.next_keys,
    next_threshold: adv_vec.pos_adv_keep_spent.next_threshold,
    witnesses: adv_vec.pos_adv_keep_spent.witnesses,
    toad: 2,
    seq: adv_vec.pos_adv_keep_spent.seq,
    native_sn: adv_vec.pos_adv_keep_spent.native_sn,
  }

fn advance_own_ref(spent: SpentCheckpoint) -> OutputReference {
  out_ref(spent.txid, spent.index)
}

fn advance_old_input(spent: SpentCheckpoint, old: CheckpointDatumV1) -> Input {
  input_at(
    advance_own_ref(spent),
    Output {
      address: role.address(policy, Frozen),
      value: from_lovelace(advance_deposit)
        |> merge(from_asset(policy, spent.aid_asset_name, 1)),
      datum: InlineDatum(V1(old)),
      reference_script: None,
    },
  )
}

fn advance_new_output(
  spent: SpentCheckpoint,
  lovelace: Int,
  new: CheckpointDatumV1,
) -> Output {
  Output {
    address: from_script(policy),
    value: from_lovelace(lovelace)
      |> merge(from_asset(policy, spent.aid_asset_name, 1)),
    datum: InlineDatum(V1(new)),
    reference_script: None,
  }
}

fn advance_tx(
  spent: SpentCheckpoint,
  old: CheckpointDatumV1,
  new: CheckpointDatumV1,
) -> Transaction {
  spend_context(
    [advance_old_input(spent, old)],
    [],
    [advance_new_output(spent, advance_deposit, new)],
    zero,
    [],
    interval.everything,
    0,
  )
}

const own_ref_advance_from_frozen: OutputReference =
  OutputReference {
    transaction_id: adv_vec.pos_adv_keep_spent.txid,
    output_index: adv_vec.pos_adv_keep_spent.index,
  }

const tx_advance_from_frozen: Transaction =
  advance_tx(
    adv_vec.pos_adv_keep_spent,
    old_adv_keep,
    adv_vec.pos_adv_keep_created,
  )

// Ordinary no-delta thaw: 2 controller Ed25519 verifications and 2 witness
// receipts over the full rot bytes, with empty wit_cut/wit_add.
test measure_checkpoint_advance_from_frozen() {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    adv_network_id,
    d_reg,
    None,
    Advance { evidence: adv_vec.pos_adv_keep_evidence },
    own_ref_advance_from_frozen,
    tx_advance_from_frozen,
  )
}

// ---------------------------------------------------------------------
// Slice-4 live Freeze measurement fixture. S6 owns the final lag/2-key/7-key
// matrix and report; this cell keeps the committed lag wire on the real
// handler ACCEPT path as soon as Freeze opens.
// ---------------------------------------------------------------------

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

const honest7_freeze_wire: EnforcementEvidence =
  EnforcementEvidence {
    event_bytes: enf_vec.honest7_freeze_evidence.event_bytes,
    off_t: 30,
    off_i: 91,
    off_s: 142,
    off_d: 40,
    off_k: [227, 274, 321],
    off_kt: 201,
    off_n: [423, 470, 517, 564, 611, 658, 705],
    off_nt: 373,
    off_bt: 758,
    native_sn: enf_vec.honest7_freeze_evidence.native_sn,
    said: enf_vec.honest7_freeze_evidence.said,
    revealed_keys: enf_vec.honest7_freeze_evidence.revealed_keys,
    next_keys: enf_vec.honest7_freeze_evidence.next_keys,
    cur_threshold: enf_vec.honest7_freeze_evidence.cur_threshold,
    next_threshold: enf_vec.honest7_freeze_evidence.next_threshold,
    toad: enf_vec.honest7_freeze_evidence.toad,
    ctrl_sigs: enf_vec.honest7_freeze_evidence.ctrl_sigs,
    wit_sigs: enf_vec.honest7_freeze_evidence.wit_sigs,
  }

fn freeze_measurement_value(d: CheckpointDatumV1) -> Value {
  from_lovelace(advance_deposit)
    |> merge(from_asset(policy, deriveAidAssetName(d.cesr_aid), 1))
}

fn freeze_measurement_tx(
  own_ref: OutputReference,
  d: CheckpointDatumV1,
) -> Transaction {
  let value = freeze_measurement_value(d)
  spend_context(
    [
      input_at(
        own_ref,
        Output {
          address: from_script(policy),
          value,
          datum: InlineDatum(V1(d)),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: role.address(policy, Frozen),
        value,
        datum: InlineDatum(V1(d)),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.everything,
    0,
  )
}

const own_ref_freeze_2key: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 7 }

const tx_freeze_2key: Transaction =
  freeze_measurement_tx(own_ref_freeze_2key, enf_vec.honest2_freeze_tip)

const own_ref_freeze_7key: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 5 }

const tx_freeze_7key: Transaction =
  freeze_measurement_tx(own_ref_freeze_7key, enf_vec.honest7_freeze_tip)

test measure_checkpoint_freeze_2key() {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    None,
    Freeze { evidence: honest2_freeze_wire },
    own_ref_freeze_2key,
    tx_freeze_2key,
  )
}

test measure_checkpoint_freeze_7key() {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    None,
    Freeze { evidence: honest7_freeze_wire },
    own_ref_freeze_7key,
    tx_freeze_7key,
  )
}

const own_ref_freeze_lag: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 8 }

fn freeze_lag_value() -> Value {
  from_lovelace(advance_deposit)
    |> merge(
        from_asset(
          policy,
          deriveAidAssetName(enf_vec.lag_freeze_tip.cesr_aid),
          1,
        ),
      )
}

const tx_freeze_lag: Transaction =
  spend_context(
    [
      input_at(
        own_ref_freeze_lag,
        Output {
          address: from_script(policy),
          value: freeze_lag_value(),
          datum: InlineDatum(V1(enf_vec.lag_freeze_tip)),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: role.address(policy, Frozen),
        value: freeze_lag_value(),
        datum: InlineDatum(V1(enf_vec.lag_freeze_tip)),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.everything,
    0,
  )

test measure_checkpoint_freeze_lag() {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    None,
    Freeze { evidence: enf_vec.lag_freeze_wire },
    own_ref_freeze_lag,
    tx_freeze_lag,
  )
}

// ---------------------------------------------------------------------
// Slice-5 live Convict measurement fixtures. S6 owns the final combined
// matrix, percentages, and report; these cells keep the committed witnessed
// fork on both real ACTIVE and FROZEN handler ACCEPT paths.
// ---------------------------------------------------------------------

const own_ref_convict_witnessed: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 6 }

fn convict_witnessed_input_value() -> Value {
  from_lovelace(advance_deposit)
    |> merge(
        from_asset(
          policy,
          deriveAidAssetName(enf_vec.fork_witnessed_convict_tip.cesr_aid),
          1,
        ),
      )
}

fn convict_witnessed_tombstone_value() -> Value {
  from_lovelace(min_ada)
    |> merge(
        from_asset(
          policy,
          deriveAidAssetName(enf_vec.fork_witnessed_convict_tip.cesr_aid),
          1,
        ),
      )
}

fn convict_witnessed_tx(input_address: Address) -> Transaction {
  spend_context(
    [
      input_at(
        own_ref_convict_witnessed,
        Output {
          address: input_address,
          value: convict_witnessed_input_value(),
          datum: InlineDatum(V1(enf_vec.fork_witnessed_convict_tip)),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: role.address(policy, Tombstone),
        value: convict_witnessed_tombstone_value(),
        datum: InlineDatum(
          TombstoneV1 {
            cesr_aid: enf_vec.fork_witnessed_convict_tip.cesr_aid,
            convicted_at_native_sn: enf_vec.fork_witnessed_convict_tip.native_sn,
            evidence_said: enf_vec.fork_witnessed_convict_wire.said,
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

const tx_convict_witnessed_active: Transaction =
  convict_witnessed_tx(from_script(policy))

const tx_convict_witnessed_frozen: Transaction =
  convict_witnessed_tx(role.address(policy, Frozen))

test measure_checkpoint_convict_witnessed_active() {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    None,
    Convict { evidence: enf_vec.fork_witnessed_convict_wire },
    own_ref_convict_witnessed,
    tx_convict_witnessed_active,
  )
}

test measure_checkpoint_convict_witnessed_frozen() {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    None,
    Convict { evidence: enf_vec.fork_witnessed_convict_wire },
    own_ref_convict_witnessed,
    tx_convict_witnessed_frozen,
  )
}
