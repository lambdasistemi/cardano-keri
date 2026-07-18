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

use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id,
}
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge}
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use checkpoint.{MintRedeemer, Register}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// Must equal the shared vectors' `checkpoint_policy_id` (the R7
/// signatures bind it via the reconstructed preimage).
const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

const d_reg: Int = 5_000_000

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
