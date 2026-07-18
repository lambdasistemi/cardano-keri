//// #114 S5 — checkpoint validator tests: the `Register` mint branch
//// (R1-R8) and the R10 fail-closed spend, RED first.
////
//// Each test drives the REAL `checkpoint.checkpoint.mint` /
//// `checkpoint.checkpoint.spend` handler on a full `Transaction` (the
//// `cage_context.mint_context` harness; #99 precedent). Positives are the
//// four honest S3 vector packages — `reg_2key`, `reg_7key` (the A-001
//// gate shapes, slice 5a), `reg_witnessed` (2-of-3), `reg_weighted`
//// (fractional `kt`) — each assembled as a full Tx-B context: the
//// proof-token input present AND burned (R5), the single-`Pair`
//// checkpoint mint (R1), the ACTIVE-address state output carrying the
//// token and the inline `V1` datum (R2), deposit met (R8). One positive
//// adds an EXTRA unrelated input (A-001 QC gate-room proof: the branch
//// must leave room for the #116 unicity-gate input).
////
//// The exhaustive R3/R4/E1-E9/R7/R8 families live in the S2/S3 layers
//// (`registration_tests.ak` over the shared vectors); here one R6 and one
//// R7 canary each prove the VALIDATOR routes through the S3 predicate and
//// rejects.
////
//// The validator parameters under test mirror the vectors' shared
//// `DeploymentContext` (`network_id = 0`, checkpoint policy = the ctx
//// `checkpoint_policy_id`, `d_reg = 5_000_000`, ledger floor
//// `min_ada = 2_000_000`): the R7 signatures sign the reconstructed
//// preimage under exactly that context.

use aiken/collection/list
use cage_context.{
  ada_output, input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id,
}
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, Transaction, placeholder,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use checkpoint.{Register}

/// The hash-proof policy parameter (Tx A's policy; any 28-byte id — the
/// proof token in the R5 input/burn is denominated under it).
const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// The checkpoint policy under test — MUST equal the shared vectors'
/// `checkpoint_policy_id` (the R7 signatures bind it via the preimage).
const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

const d_reg: Int = 5_000_000

// ---------------------------------------------------------------------
// Tx-B context builders
// ---------------------------------------------------------------------

/// An input at `ref` holding `value` under a plain key address (no datum).
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

/// The proof-token input: `min_ada` plus one `(hp_policy, name)` token.
fn proof_input(name: ByteArray) -> Input {
  value_input(
    0,
    from_lovelace(min_ada) |> merge(from_asset(hp_policy, name, 1)),
  )
}

/// The ACTIVE-address state output: `lovelace` + the minted checkpoint
/// token + the inline `V1`-wrapped datum.
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

/// The honest Tx-B mint value: checkpoint token +1, proof token -1.
fn register_mint(aid_name: ByteArray, proof_name: ByteArray) -> Value {
  from_asset(policy, aid_name, 1)
    |> merge(from_asset(hp_policy, proof_name, -1))
}

/// A full honest Tx-B context over one vector package.
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

/// Drive the real mint handler under the fixed deployment parameters.
fn run_register(e: RegistrationEvidence, tx: Transaction) -> Bool {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    Register { evidence: e },
    policy,
    tx,
  )
}

// ---------------------------------------------------------------------
// positives — the four honest packages (R1+R2+R5+predicate end-to-end)
// ---------------------------------------------------------------------

test accept_register_2key() {
  run_register(
    vec.pos_2key_evidence,
    register_tx(
      vec.pos_2key_datum,
      vec.pos_2key_lovelace,
      vec.pos_2key_evidence,
    ),
  )
}

test accept_register_7key() {
  run_register(
    vec.pos_7key_evidence,
    register_tx(
      vec.pos_7key_datum,
      vec.pos_7key_lovelace,
      vec.pos_7key_evidence,
    ),
  )
}

test accept_register_witnessed() {
  run_register(
    vec.pos_witnessed_evidence,
    register_tx(
      vec.pos_witnessed_datum,
      vec.pos_witnessed_lovelace,
      vec.pos_witnessed_evidence,
    ),
  )
}

test accept_register_weighted() {
  run_register(
    vec.pos_weighted_evidence,
    register_tx(
      vec.pos_weighted_datum,
      vec.pos_weighted_lovelace,
      vec.pos_weighted_evidence,
    ),
  )
}

/// Gate-room proof (A-001 QC): an EXTRA unrelated input must be admitted —
/// no check may assume a fixed input count or reject inputs beyond those
/// R5 names (structural room for the #116 unicity-gate input).
test accept_register_extra_input() {
  let tx = register_tx(
    vec.pos_2key_datum,
    vec.pos_2key_lovelace,
    vec.pos_2key_evidence,
  )
  let extra = value_input(7, from_lovelace(42_000_000))
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, inputs: list.concat(tx.inputs, [extra]) },
  )
}

// ---------------------------------------------------------------------
// R1 — mint shape
// ---------------------------------------------------------------------

/// R1: a second asset name under the checkpoint policy.
test reject_r1_extra_asset_name() fail {
  let aid_name = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
  let foreign_name = deriveAidAssetName(vec.pos_7key_datum.cesr_aid)
  let tx = mint_context(
    [proof_input(proof_name)],
    [state_output(aid_name, vec.pos_2key_lovelace, vec.pos_2key_datum)],
    register_mint(aid_name, proof_name)
      |> merge(from_asset(policy, foreign_name, 1)),
  )
  run_register(vec.pos_2key_evidence, tx)
}

/// R1: the derived name minted at quantity 2.
test reject_r1_quantity_two() fail {
  let aid_name = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
  let tx = mint_context(
    [proof_input(proof_name)],
    [state_output(aid_name, vec.pos_2key_lovelace, vec.pos_2key_datum)],
    register_mint(aid_name, proof_name)
      |> merge(from_asset(policy, aid_name, 1)),
  )
  run_register(vec.pos_2key_evidence, tx)
}

// ---------------------------------------------------------------------
// R2 — state output
// ---------------------------------------------------------------------

/// R2: no output at the ACTIVE address at all.
test reject_r2_no_state_output() fail {
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
  let aid_name = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let tx = mint_context(
    [proof_input(proof_name)],
    [ada_output(from_verification_key(owner_vkh), vec.pos_2key_lovelace)],
    register_mint(aid_name, proof_name),
  )
  run_register(vec.pos_2key_evidence, tx)
}

/// R2: a second output at the ACTIVE address (datum-confusion guard).
test reject_r2_two_state_outputs() fail {
  let tx = register_tx(
    vec.pos_2key_datum,
    vec.pos_2key_lovelace,
    vec.pos_2key_evidence,
  )
  let second = ada_output(from_script(policy), min_ada)
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, outputs: list.concat(tx.outputs, [second]) },
  )
}

/// R2: the state output (token + datum) sits at a foreign address.
test reject_r2_wrong_address() fail {
  let aid_name = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
  let stray = Output {
    ..state_output(aid_name, vec.pos_2key_lovelace, vec.pos_2key_datum),
    address: from_verification_key(owner_vkh),
  }
  let tx = mint_context(
    [proof_input(proof_name)],
    [stray],
    register_mint(aid_name, proof_name),
  )
  run_register(vec.pos_2key_evidence, tx)
}

/// R2: ACTIVE-address output present (datum, deposit) but WITHOUT the
/// minted token.
test reject_r2_missing_token() fail {
  let aid_name = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
  let bare = Output {
    address: from_script(policy),
    value: from_lovelace(vec.pos_2key_lovelace),
    datum: InlineDatum(V1(vec.pos_2key_datum)),
    reference_script: None,
  }
  let tx = mint_context(
    [proof_input(proof_name)],
    [bare],
    register_mint(aid_name, proof_name),
  )
  run_register(vec.pos_2key_evidence, tx)
}

// ---------------------------------------------------------------------
// R5 — hash-proof consumption
// ---------------------------------------------------------------------

/// R5: no input carries the proof token.
test reject_r5_missing_proof_input() fail {
  let tx = register_tx(
    vec.pos_2key_datum,
    vec.pos_2key_lovelace,
    vec.pos_2key_evidence,
  )
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, inputs: [value_input(1, from_lovelace(min_ada))] },
  )
}

/// R5: the consumed proof token carries another pair's name.
test reject_r5_wrong_proof_name() fail {
  let tx = register_tx(
    vec.pos_2key_datum,
    vec.pos_2key_lovelace,
    vec.pos_2key_evidence,
  )
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, inputs: [proof_input(vec.witnessed_proof_name)] },
  )
}

/// R5: proof input present but NOT burned (no hash-proof mint entry).
test reject_r5_unburned_proof() fail {
  let aid_name = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
  let tx = mint_context(
    [proof_input(proof_name)],
    [state_output(aid_name, vec.pos_2key_lovelace, vec.pos_2key_datum)],
    from_asset(policy, aid_name, 1),
  )
  run_register(vec.pos_2key_evidence, tx)
}

// ---------------------------------------------------------------------
// R8 — deposit floor (routed through the validator)
// ---------------------------------------------------------------------

/// R8: state-output lovelace one below `min_ada + d_reg`.
test reject_r8_deposit_below_floor() fail {
  run_register(
    vec.pos_2key_evidence,
    register_tx(vec.pos_2key_datum, 6_999_999, vec.pos_2key_evidence),
  )
}

// ---------------------------------------------------------------------
// R6/R7 canaries — the validator routes through the S3 predicate
// (exhaustive families live in registration_tests.ak)
// ---------------------------------------------------------------------

/// R6 canary (E1): `off_t` pointed away from the `t` value.
test reject_r6_canary_misdirected_off_t() fail {
  let e = RegistrationEvidence { ..vec.pos_2key_evidence, off_t: 3 }
  run_register(
    e,
    register_tx(
      vec.pos_2key_datum,
      vec.pos_2key_lovelace,
      vec.pos_2key_evidence,
    ),
  )
}

/// R7 canary: one signature of a 2-of-2 package (below threshold).
test reject_r7_canary_below_threshold() fail {
  let e = RegistrationEvidence {
    ..vec.pos_2key_evidence,
    ctrl_sigs: list.take(vec.pos_2key_evidence.ctrl_sigs, 1),
  }
  run_register(
    e,
    register_tx(
      vec.pos_2key_datum,
      vec.pos_2key_lovelace,
      vec.pos_2key_evidence,
    ),
  )
}

// ---------------------------------------------------------------------
// R10 — spend paths fail closed
// ---------------------------------------------------------------------

/// R10: any spend redeemer fails closed (#115-#117 land here).
test reject_r10_spend_fails_closed() fail {
  let datum_data: Data = V1(vec.pos_2key_datum)
  let rdm: Data = 0
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    Some(datum_data),
    rdm,
    out_ref(seed_tx_id, 0),
    placeholder,
  )
}
