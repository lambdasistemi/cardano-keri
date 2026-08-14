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
//// adds an EXTRA unrelated input (A-001 QC gate-room proof).
////
//// The exhaustive R3/R4/E1-E9/R7/R8 families live in the S2/S3 layers
//// (`registration_tests.ak` over the shared vectors); here one R6 and one
//// R7 canary each prove the VALIDATOR routes through the S3 predicate and
//// rejects.
////
//// The registration deployment values under test mirror the vectors'
//// shared `DeploymentContext` (`d_reg = 1_000_000_000`, ledger floor
//// `min_ada = 2_000_000`). R7 authenticates the exact inception-event
//// bytes with the event's own controller signatures and witness receipts;
//// the validator separately enforces the ledger policy and network context.
//// Ordinary fixtures use the non-normative reference d_reg =
//// 1_000_000_000 lovelace.

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/primitive/bytearray
use cage_context.{
  ada_output, input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id,
  spend_context,
}
use cardano/address.{
  Address, from_script, from_verification_key, with_delegation_script,
}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use cardano_keri/bounty_commitment.{
  BountyRevealV1, CommitmentFamily, CommitmentParameters,
}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/advance_vectors as adv_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, TombstoneV1}
use cardano_keri/checkpoint/enforcement_vectors as enf_vec
use cardano_keri/checkpoint/entitlement.{validate_freeze_entitlement}
use cardano_keri/checkpoint/freeze_bond.{ArmedDatum, ArmedV1, ArmedV2}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/role.{Active, Armed, Frozen, Tombstone}
use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}
use checkpoint.{Advance, Close, Register}

/// Test-side encoding of the ratified Slice-4 spend redeemer. Keeping this
/// local makes the RED diff test-only while still exercising the real handler's
/// `Data` decoder; GREEN changes the live `SpendRedeemer` to this exact shape.
type Slice4SpendRedeemer {
  Slice4Advance { evidence: AdvanceEvidence }
  Slice4Freeze { evidence: EnforcementEvidence }
  Slice4Convict
  Slice4Close
}

/// Test-side encoding of the ratified Slice-5 spend redeemer. The constructor
/// order mirrors the live type exactly; only Convict changes shape. Keeping it
/// local lets the validator-level positive observe a genuine decoder/dispatch
/// RED before production is changed.
type Slice5SpendRedeemer {
  Slice5Advance { evidence: AdvanceEvidence }
  Slice5Freeze { evidence: EnforcementEvidence }
  Slice5Convict { evidence: EnforcementEvidence }
  Slice5Close
}

/// Test-side target wire for T116-R2. Its constructor order is the exact
/// six-parameter validator's spend wire; the RED helper below still invokes
/// the delivered four-parameter script so this test-only diff type-checks.
type R2SpendRedeemer {
  R2Advance { evidence: AdvanceEvidence }
  R2Freeze { evidence: EnforcementEvidence, hunter_pkh: ByteArray }
  R2ClaimFreeze { hunter_output_index: Int }
  R2Convict
  R2Close
}

/// Test-side target wire for T116-R3. The constructor order preserves the R2
/// wire and gives Convict the existing evidence plus explicit recipients and
/// named payout indices. Keeping it local lets RED exercise the real handler
/// before production dispatch is reopened.
type R3SpendRedeemer {
  R3Advance { evidence: AdvanceEvidence }
  R3Freeze { evidence: EnforcementEvidence, hunter_pkh: ByteArray }
  R3ClaimFreeze { hunter_output_index: Int }
  R3Convict {
    evidence: EnforcementEvidence,
    convictor_pkh: ByteArray,
    convictor_output_index: Int,
    hunter_output_index: Int,
  }
  R3Close
}

/// The hash-proof policy parameter (Tx A's policy; any 28-byte id — the
/// proof token in the R5 input/burn is denominated under it).
const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// The checkpoint policy under test. The validator enforces it through the
/// minted checkpoint asset and state output; it is not part of R7's signed
/// KERI event bytes.
const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

const d_reg: Int = 1_000_000_000

const r2_freeze_bond: Int = 5_000_000

const r2_freeze_window: Int = 500

const register_floor: Int = min_ada + d_reg + r2_freeze_bond

const register_surplus_lovelace: Int = 17

const unrelated_policy: PolicyId =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

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

fn state_output_with_value(value: Value, d: CheckpointDatumV1) -> Output {
  Output {
    address: from_script(policy),
    value,
    datum: InlineDatum(V1(d)),
    reference_script: None,
  }
}

fn bonded_state_value(aid_name: ByteArray, lovelace: Int) -> Value {
  from_lovelace(lovelace) |> merge(from_asset(policy, aid_name, 1))
}

fn bonded_state_value_with_foreign_asset(
  aid_name: ByteArray,
  lovelace: Int,
) -> Value {
  bonded_state_value(aid_name, lovelace)
    |> merge(from_asset(unrelated_policy, #"f4", 3))
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

fn bonded_register_tx(
  d: CheckpointDatumV1,
  value: Value,
  e: RegistrationEvidence,
) -> Transaction {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let proof_name = proof_token_name(e.event_bytes, d.cesr_aid)
  mint_context(
    [proof_input(proof_name)],
    [state_output_with_value(value, d)],
    register_mint(aid_name, proof_name),
  )
}

fn bonded_register_tx_at(
  d: CheckpointDatumV1,
  lovelace: Int,
  e: RegistrationEvidence,
) -> Transaction {
  let aid_name = deriveAidAssetName(d.cesr_aid)
  bonded_register_tx(d, bonded_state_value(aid_name, lovelace), e)
}

/// Drive the real mint handler under the fixed deployment parameters.
fn run_register(e: RegistrationEvidence, tx: Transaction) -> Bool {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    Register { evidence: e },
    policy,
    tx,
  )
}

/// Invoke Register with an explicit deployment bond parameter.
fn run_register_with_deposit(
  d_reg_parameter: Int,
  e: RegistrationEvidence,
  tx: Transaction,
) -> Bool {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg_parameter,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    Register { evidence: e },
    policy,
    tx,
  )
}

// ---------------------------------------------------------------------
// positives — the four honest packages (R1+R2+R5+predicate end-to-end)
// ---------------------------------------------------------------------

test t114_r3_accept_register_2key_at_bonded_floor() {
  run_register(
    vec.pos_2key_evidence,
    bonded_register_tx_at(
      vec.pos_2key_datum,
      register_floor,
      vec.pos_2key_evidence,
    ),
  )
}

test t114_r3_accept_register_7key_with_conservative_surplus() {
  run_register(
    vec.pos_7key_evidence,
    bonded_register_tx_at(
      vec.pos_7key_datum,
      register_floor + register_surplus_lovelace,
      vec.pos_7key_evidence,
    ),
  )
}

test t114_r3_accept_register_witnessed_with_foreign_asset_surplus() {
  let aid_name = deriveAidAssetName(vec.pos_witnessed_datum.cesr_aid)
  run_register(
    vec.pos_witnessed_evidence,
    bonded_register_tx(
      vec.pos_witnessed_datum,
      bonded_state_value_with_foreign_asset(
        aid_name,
        register_floor + register_surplus_lovelace,
      ),
      vec.pos_witnessed_evidence,
    ),
  )
}

test t114_r3_accept_register_weighted_without_submitter_signature() {
  run_register(
    vec.pos_weighted_evidence,
    bonded_register_tx_at(
      vec.pos_weighted_datum,
      register_floor,
      vec.pos_weighted_evidence,
    ),
  )
}

/// The final #114 Register shape has no shared coordinating state.
test t114_r3_accept_registration_without_shared_state() {
  run_register_with_deposit(
    d_reg,
    vec.pos_2key_evidence,
    bonded_register_tx_at(
      vec.pos_2key_datum,
      register_floor,
      vec.pos_2key_evidence,
    ),
  )
}

/// Gate-room proof (A-001 QC): an EXTRA unrelated input must be admitted —
/// no check may assume a fixed input count or reject inputs beyond those
/// R5 names.
test t114_r3_accept_register_with_unrelated_key_and_script_inputs_and_output() {
  let tx = bonded_register_tx_at(
    vec.pos_2key_datum,
    register_floor,
    vec.pos_2key_evidence,
  )
  let extra_key = value_input(7, from_lovelace(42_000_000))
  let extra_script = input_at(
    out_ref(seed_tx_id, 27),
    Output {
      address: from_script(unrelated_policy),
      value: from_lovelace(9_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  )
  let extra_output = ada_output(from_verification_key(owner_vkh), 8_000_000)
  run_register(
    vec.pos_2key_evidence,
    Transaction {
      ..tx,
      inputs: list.concat(tx.inputs, [extra_key, extra_script]),
      outputs: list.concat(tx.outputs, [extra_output]),
    },
  )
}

/// Duplicate same-AID ACTIVE history is reference-only: Register creates a
/// fresh independent ACTIVE output without consuming the sovereign state.
test t114_r3_accept_duplicate_active_via_reference_input() {
  let d = vec.pos_2key_datum
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let history = input_at(
    out_ref(seed_tx_id, 28),
    state_output_with_value(bonded_state_value(aid_name, register_floor), d),
  )
  let tx = bonded_register_tx_at(d, register_floor, vec.pos_2key_evidence)
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, reference_inputs: [history] },
  )
}

/// Register may inspect checkpoint history as a reference input but must not
/// consume any input locked by this checkpoint script.
test t114_r3_reject_register_consuming_checkpoint_script_input() fail {
  let tx = bonded_register_tx_at(
    vec.pos_2key_datum,
    register_floor,
    vec.pos_2key_evidence,
  )
  let consumed = input_at(
    out_ref(seed_tx_id, 29),
    Output {
      address: from_script(policy),
      value: from_lovelace(min_ada),
      datum: NoDatum,
      reference_script: None,
    },
  )
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, inputs: list.concat(tx.inputs, [consumed]) },
  )
}

/// D1: reject a deployment configured below the mechanical floor.
test t116_s7_reject_d_reg_below_mechanical_floor_registration_mint() fail {
  let tx = register_tx(
    vec.pos_2key_datum,
    vec.pos_2key_lovelace,
    vec.pos_2key_evidence,
  )
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    vec.d_reg_below_floor,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    Register { evidence: vec.pos_2key_evidence },
    policy,
    tx,
  )
}

/// B1: reject a freeze-bond deployment one below its independent floor before
/// mint dispatch.
test t114_r3_reject_freeze_bond_below_mechanical_floor_registration_mint() fail {
  let tx = bonded_register_tx_at(
    vec.pos_2key_datum,
    register_floor,
    vec.pos_2key_evidence,
  )
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    r2_freeze_bond - 1,
    r2_freeze_window,
    applied_commitment,
    Register { evidence: vec.pos_2key_evidence },
    policy,
    tx,
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

/// R2: the ACTIVE output carries the right token but no inline datum.
test t114_r3_reject_register_missing_inline_datum() fail {
  let d = vec.pos_2key_datum
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let proof_name = proof_token_name(
    vec.pos_2key_evidence.event_bytes,
    d.cesr_aid,
  )
  let bare = Output {
    address: from_script(policy),
    value: bonded_state_value(aid_name, register_floor),
    datum: NoDatum,
    reference_script: None,
  }
  run_register(
    vec.pos_2key_evidence,
    mint_context(
      [proof_input(proof_name)],
      [bare],
      register_mint(aid_name, proof_name),
    ),
  )
}

/// R2: the ACTIVE output's complete own-policy asset map contains another
/// name even though the Register mint itself is the exact singleton.
test t114_r3_reject_register_output_extra_own_policy_asset_name() fail {
  let d = vec.pos_2key_datum
  let aid_name = deriveAidAssetName(d.cesr_aid)
  let value = bonded_state_value(aid_name, register_floor)
    |> merge(from_asset(policy, #"ee", 1))
  run_register(
    vec.pos_2key_evidence,
    bonded_register_tx(d, value, vec.pos_2key_evidence),
  )
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

/// R8: state-output lovelace one below `min_ada + d_reg + B`.
test t114_r3_reject_register_one_below_bonded_floor() fail {
  run_register(
    vec.pos_2key_evidence,
    bonded_register_tx_at(
      vec.pos_2key_datum,
      register_floor - 1,
      vec.pos_2key_evidence,
    ),
  )
}

/// R8: the old pure-predicate reserve omits the complete applied bond.
test t114_r3_reject_register_missing_freeze_bond() fail {
  run_register(
    vec.pos_2key_evidence,
    bonded_register_tx_at(
      vec.pos_2key_datum,
      min_ada + d_reg,
      vec.pos_2key_evidence,
    ),
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

test t114_r3_reject_old_message_only_controller_signatures() fail {
  run_register(
    vec.r7_old_message_sigs_evidence,
    bonded_register_tx_at(
      vec.r7_old_message_sigs_datum,
      register_floor,
      vec.r7_old_message_sigs_evidence,
    ),
  )
}

test t114_r3_reject_bad_controller_signature_threshold() fail {
  run_register(
    vec.r7_below_threshold_evidence,
    bonded_register_tx_at(
      vec.r7_below_threshold_datum,
      register_floor,
      vec.r7_below_threshold_evidence,
    ),
  )
}

test t114_r3_reject_bad_witness_receipt_threshold() fail {
  run_register(
    vec.r7_receipts_bad_signature_evidence,
    bonded_register_tx_at(
      vec.r7_receipts_bad_signature_datum,
      register_floor,
      vec.r7_receipts_bad_signature_evidence,
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
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    Some(datum_data),
    rdm,
    out_ref(seed_tx_id, 0),
    placeholder,
  )
}

// ---------------------------------------------------------------------
// Advance spend branch (#115 S6) — V1-V7 end-to-end over constructed
// ScriptContext data. Positives replay the S1 keripy honest fixture
// families end-to-end (real Advance evidence, real successor datum);
// negatives probe each transaction-shape check the validator itself owns
// (V1-V3) plus one end-to-end predicate-evidence rejection through V4-V7
// (the exhaustive AE/W/ctrl/receipt families already live in
// advance_tests.ak at the predicate level). Slice 4 below opens Freeze and
// ordinary-Advance thaw while Convict/Close stay fail-closed.
// ---------------------------------------------------------------------

/// Advance vectors were generated under network_id = 1 (the Register
/// branch above uses 0) — the eq1 equality binds this value via the
/// reconstructed preimage.
const adv_network_id: Int = 1

/// The successor lovelace used by the honest Advance fixtures: exactly the
/// V3 floor (`checkpoint_min_ada + d_reg` = 2_000_000 + 5_000_000).
const advance_deposit: Int = min_ada + d_reg

/// OLD checkpoint datums: the real keripy `icp` key state (`k`/`kt`/`b`/`bt`,
/// raw-decoded from `fixtures/advance.json`) each S1 honest family's `rot`
/// actually advanced FROM. `next_keys`/`next_threshold`/`witnesses`/`seq`/
/// `native_sn` are reused byte-for-byte from the vectors' own `..._spent`
/// `SpentCheckpoint` (the only OLD fields `advance_predicate` consults);
/// `cur_keys`/`cur_threshold`/`toad` play no role in the predicate but are
/// the real icp values, for end-to-end fidelity.
const old_adv_wit_2key: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: adv_vec.pos_adv_wit_2key_spent.cesr_aid,
    cur_keys: [
      #"bf1145e4449d74e9f09bd6aaffcbcd295f2a82e9fcbb5689c5346b3c274bccbb",
      #"95d507a9923dc62701d5619c117a3cbb8ae91cfe3f99e96cc0ae986cb52b586d",
    ],
    cur_threshold: Unweighted(2),
    next_keys: adv_vec.pos_adv_wit_2key_spent.next_keys,
    next_threshold: adv_vec.pos_adv_wit_2key_spent.next_threshold,
    witnesses: adv_vec.pos_adv_wit_2key_spent.witnesses,
    toad: 2,
    seq: adv_vec.pos_adv_wit_2key_spent.seq,
    native_sn: adv_vec.pos_adv_wit_2key_spent.native_sn,
  }

const old_adv_wit_7key: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: adv_vec.pos_adv_wit_7key_spent.cesr_aid,
    cur_keys: [
      #"0380fcebe3b1b3d0d6a196c6059c92975cf446f03c69bf089c0d0d7be611063e",
      #"87d4034a197c50e9133f3a97c81d45a28a23744bea198bf7896060d40c502ddc",
      #"6b6431d375e8db08b1f9e3c5c0c1dc71cd186e7ad155c03dd1e07cf32d1bcf51",
      #"f9f02712abf08ee233d729b47d76f4e789dc4cf46d6e9fae8c020dd6323806f6",
      #"9d3e1ade7c4c87e2a1c4b1595f38ae404a13f5736b8a241a17c4750ab43cc935",
      #"0db754920b399dafec84660f7f516138a6d509523ce5532d19ff3e4b1b41a22b",
      #"f50a4c9bf688e8ce210f8109e8247fc81ef20f8d4a029500d4ceb7be0e23becb",
    ],
    cur_threshold: Weighted(
      [
        [
          Weight { num: 1, den: 3 },
          Weight { num: 1, den: 3 },
          Weight { num: 1, den: 3 },
          Weight { num: 1, den: 3 },
          Weight { num: 1, den: 3 },
          Weight { num: 1, den: 3 },
          Weight { num: 1, den: 3 },
        ],
      ],
    ),
    next_keys: adv_vec.pos_adv_wit_7key_spent.next_keys,
    next_threshold: adv_vec.pos_adv_wit_7key_spent.next_threshold,
    witnesses: adv_vec.pos_adv_wit_7key_spent.witnesses,
    toad: 2,
    seq: adv_vec.pos_adv_wit_7key_spent.seq,
    native_sn: adv_vec.pos_adv_wit_7key_spent.native_sn,
  }

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

const old_adv_downgrade: CheckpointDatumV1 =
  CheckpointDatumV1 {
    cesr_aid: adv_vec.pos_adv_downgrade_spent.cesr_aid,
    cur_keys: [
      #"4927ac8d0d088f48036a5586c0b5338c70afb8a8fd5366c690fcb1ec622bf4a8",
      #"5d0363fe2fa651c91b772228932cb41a236e17441c6b318c902f1e728243d2c1",
    ],
    cur_threshold: Unweighted(2),
    next_keys: adv_vec.pos_adv_downgrade_spent.next_keys,
    next_threshold: adv_vec.pos_adv_downgrade_spent.next_threshold,
    witnesses: adv_vec.pos_adv_downgrade_spent.witnesses,
    toad: 2,
    seq: adv_vec.pos_adv_downgrade_spent.seq,
    native_sn: adv_vec.pos_adv_downgrade_spent.native_sn,
  }

// ---------------------------------------------------------------------
// Advance context builders
// ---------------------------------------------------------------------

fn advance_own_ref(spent: SpentCheckpoint) -> OutputReference {
  out_ref(spent.txid, spent.index)
}

/// The spent ACTIVE-address input: the checkpoint token at quantity one,
/// inline `V1(old)`.
fn advance_old_input(spent: SpentCheckpoint, old: CheckpointDatumV1) -> Input {
  advance_old_input_at(spent, old, role.address(policy, Active))
}

fn advance_old_input_at(
  spent: SpentCheckpoint,
  old: CheckpointDatumV1,
  address: Address,
) -> Input {
  input_at(
    advance_own_ref(spent),
    Output {
      address,
      value: from_lovelace(min_ada)
        |> merge(from_asset(policy, spent.aid_asset_name, 1)),
      datum: InlineDatum(V1(old)),
      reference_script: None,
    },
  )
}

/// The ACTIVE-address successor output: `lovelace` + the same token +
/// inline `V1(new)`.
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

/// A full honest Advance spend context: consume `old` at `spent`'s outref,
/// create `new` at the deposit floor, no mint/burn under the checkpoint
/// policy.
fn advance_tx(
  spent: SpentCheckpoint,
  old: CheckpointDatumV1,
  new: CheckpointDatumV1,
) -> Transaction {
  advance_tx_from(spent, old, new, role.address(policy, Active))
}

fn advance_tx_from(
  spent: SpentCheckpoint,
  old: CheckpointDatumV1,
  new: CheckpointDatumV1,
  address: Address,
) -> Transaction {
  spend_context(
    [advance_old_input_at(spent, old, address)],
    [],
    [advance_new_output(spent, advance_deposit, new)],
    zero,
    [],
    interval.everything,
    0,
  )
}

/// Drive the real spend handler under the fixed advance deployment
/// parameters.
fn run_advance(
  redeemer: Data,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    adv_network_id,
    d_reg,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    None,
    redeemer,
    own_ref,
    tx,
  )
}

fn run_advance_with_d_reg(
  d_reg_parameter: Int,
  redeemer: Data,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    adv_network_id,
    d_reg_parameter,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    None,
    redeemer,
    own_ref,
    tx,
  )
}

/// A second, structurally-valid but off-protocol datum shape: casting
/// through this (instead of the real single-constructor `CheckpointDatum`)
/// produces a `Data` value that is NOT `V1(...)`, to prove non-V1 datums
/// fail closed without a second real datum version existing.
type NonV1Probe {
  ProbeV1(CheckpointDatumV1)
  ProbeV2(CheckpointDatumV1)
}

// ---------------------------------------------------------------------
// positives — the four honest families + gate-room
// ---------------------------------------------------------------------

test t116_r2_stage_reject_advance_wit_2key() fail {
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(adv_vec.pos_adv_wit_2key_spent),
    advance_tx(
      adv_vec.pos_adv_wit_2key_spent,
      old_adv_wit_2key,
      adv_vec.pos_adv_wit_2key_created,
    ),
  )
}

/// D1 RED: the same invalid deployment parameter must reject before spend
/// dispatch. Delivered code admits this otherwise-honest Advance.
test t116_s7_reject_d_reg_below_mechanical_floor_checkpoint_spend() fail {
  run_advance_with_d_reg(
    vec.d_reg_below_floor,
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(adv_vec.pos_adv_wit_2key_spent),
    advance_tx(
      adv_vec.pos_adv_wit_2key_spent,
      old_adv_wit_2key,
      adv_vec.pos_adv_wit_2key_created,
    ),
  )
}

test t116_r2_stage_reject_advance_wit_7key() fail {
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_7key_evidence },
    advance_own_ref(adv_vec.pos_adv_wit_7key_spent),
    advance_tx(
      adv_vec.pos_adv_wit_7key_spent,
      old_adv_wit_7key,
      adv_vec.pos_adv_wit_7key_created,
    ),
  )
}

test t116_r2_stage_reject_advance_keep() fail {
  run_advance(
    Advance { evidence: adv_vec.pos_adv_keep_evidence },
    advance_own_ref(adv_vec.pos_adv_keep_spent),
    advance_tx(
      adv_vec.pos_adv_keep_spent,
      old_adv_keep,
      adv_vec.pos_adv_keep_created,
    ),
  )
}

test t116_r2_stage_reject_advance_downgrade() fail {
  run_advance(
    Advance { evidence: adv_vec.pos_adv_downgrade_evidence },
    advance_own_ref(adv_vec.pos_adv_downgrade_spent),
    advance_tx(
      adv_vec.pos_adv_downgrade_spent,
      old_adv_downgrade,
      adv_vec.pos_adv_downgrade_created,
    ),
  )
}

/// Gate-room proof (#116): an EXTRA unrelated input must be admitted — no
/// check may assume a fixed input count.
test t116_r2_stage_reject_advance_extra_input() fail {
  let tx = advance_tx(
    adv_vec.pos_adv_wit_2key_spent,
    old_adv_wit_2key,
    adv_vec.pos_adv_wit_2key_created,
  )
  let extra = value_input(7, from_lovelace(42_000_000))
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(adv_vec.pos_adv_wit_2key_spent),
    Transaction { ..tx, inputs: list.concat(tx.inputs, [extra]) },
  )
}

// ---------------------------------------------------------------------
// V2 — successor output
// ---------------------------------------------------------------------

/// V2: a second output at the ACTIVE address (datum-confusion guard).
test reject_v2_second_active_output() fail {
  let tx = advance_tx(
    adv_vec.pos_adv_wit_2key_spent,
    old_adv_wit_2key,
    adv_vec.pos_adv_wit_2key_created,
  )
  let second = ada_output(from_script(policy), min_ada)
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(adv_vec.pos_adv_wit_2key_spent),
    Transaction { ..tx, outputs: list.concat(tx.outputs, [second]) },
  )
}

/// V2: the ACTIVE-address successor output (datum, deposit) but WITHOUT
/// the checkpoint token.
test reject_v2_missing_token() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let bare = Output {
    address: from_script(policy),
    value: from_lovelace(advance_deposit),
    datum: InlineDatum(V1(adv_vec.pos_adv_wit_2key_created)),
    reference_script: None,
  }
  let tx = spend_context(
    [advance_old_input(spent, old_adv_wit_2key)],
    [],
    [bare],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V2: the checkpoint token at quantity two on the successor output.
test reject_v2_extra_token_quantity() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let doubled = Output {
    address: from_script(policy),
    value: from_lovelace(advance_deposit)
      |> merge(from_asset(policy, spent.aid_asset_name, 2)),
    datum: InlineDatum(V1(adv_vec.pos_adv_wit_2key_created)),
    reference_script: None,
  }
  let tx = spend_context(
    [advance_old_input(spent, old_adv_wit_2key)],
    [],
    [doubled],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

// ---------------------------------------------------------------------
// no mint/burn under the checkpoint policy (the token moves, never mints)
// ---------------------------------------------------------------------

test reject_advance_stray_mint() fail {
  let tx = advance_tx(
    adv_vec.pos_adv_wit_2key_spent,
    old_adv_wit_2key,
    adv_vec.pos_adv_wit_2key_created,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(adv_vec.pos_adv_wit_2key_spent),
    Transaction { ..tx, mint: from_asset(policy, #"ee", 1) },
  )
}

test reject_advance_stray_burn() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let tx = advance_tx(spent, old_adv_wit_2key, adv_vec.pos_adv_wit_2key_created)
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    Transaction { ..tx, mint: from_asset(policy, spent.aid_asset_name, -1) },
  )
}

// ---------------------------------------------------------------------
// V1 — own input / OLD datum
// ---------------------------------------------------------------------

/// V1: the spent input carries no datum at all.
test reject_v1_missing_old_datum() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let bare_input = input_at(
    advance_own_ref(spent),
    Output {
      address: from_script(policy),
      value: from_lovelace(min_ada)
        |> merge(from_asset(policy, spent.aid_asset_name, 1)),
      datum: NoDatum,
      reference_script: None,
    },
  )
  let tx = spend_context(
    [bare_input],
    [],
    [
      advance_new_output(
        spent,
        advance_deposit,
        adv_vec.pos_adv_wit_2key_created,
      ),
    ],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V1: the spent input's inline datum is not the `V1` constructor.
test reject_v1_non_v1_old_datum() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let probe_input = input_at(
    advance_own_ref(spent),
    Output {
      address: from_script(policy),
      value: from_lovelace(min_ada)
        |> merge(from_asset(policy, spent.aid_asset_name, 1)),
      datum: InlineDatum(ProbeV2(old_adv_wit_2key)),
      reference_script: None,
    },
  )
  let tx = spend_context(
    [probe_input],
    [],
    [
      advance_new_output(
        spent,
        advance_deposit,
        adv_vec.pos_adv_wit_2key_created,
      ),
    ],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V1: the spent input (token + datum) sits at a foreign address.
test reject_v1_wrong_active_address() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let stray_input = input_at(
    advance_own_ref(spent),
    Output {
      address: from_verification_key(owner_vkh),
      value: from_lovelace(min_ada)
        |> merge(from_asset(policy, spent.aid_asset_name, 1)),
      datum: InlineDatum(V1(old_adv_wit_2key)),
      reference_script: None,
    },
  )
  let tx = spend_context(
    [stray_input],
    [],
    [
      advance_new_output(
        spent,
        advance_deposit,
        adv_vec.pos_adv_wit_2key_created,
      ),
    ],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V1: the named own input carries a valid inline `V1(OLD)` datum but NOT
/// the checkpoint token derived from it.
test reject_v1_missing_token() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let bare_input = input_at(
    advance_own_ref(spent),
    Output {
      address: from_script(policy),
      value: from_lovelace(min_ada),
      datum: InlineDatum(V1(old_adv_wit_2key)),
      reference_script: None,
    },
  )
  let tx = spend_context(
    [bare_input],
    [],
    [
      advance_new_output(
        spent,
        advance_deposit,
        adv_vec.pos_adv_wit_2key_created,
      ),
    ],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V1: the named own input carries the checkpoint token at quantity two.
test reject_v1_extra_token_quantity() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let doubled_input = input_at(
    advance_own_ref(spent),
    Output {
      address: from_script(policy),
      value: from_lovelace(min_ada)
        |> merge(from_asset(policy, spent.aid_asset_name, 2)),
      datum: InlineDatum(V1(old_adv_wit_2key)),
      reference_script: None,
    },
  )
  let tx = spend_context(
    [doubled_input],
    [],
    [
      advance_new_output(
        spent,
        advance_deposit,
        adv_vec.pos_adv_wit_2key_created,
      ),
    ],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V1: the redeemer's `out_ref` names no input in the transaction at all.
test reject_v1_wrong_outref() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let tx = advance_tx(spent, old_adv_wit_2key, adv_vec.pos_adv_wit_2key_created)
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    out_ref(spent.txid, spent.index + 1),
    tx,
  )
}

// ---------------------------------------------------------------------
// V2 — NEW datum
// ---------------------------------------------------------------------

/// V2: the ACTIVE-address successor output carries no datum at all.
test reject_v2_missing_new_datum() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let bare = Output {
    address: from_script(policy),
    value: from_lovelace(advance_deposit)
      |> merge(from_asset(policy, spent.aid_asset_name, 1)),
    datum: NoDatum,
    reference_script: None,
  }
  let tx = spend_context(
    [advance_old_input(spent, old_adv_wit_2key)],
    [],
    [bare],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

/// V2: the successor output's inline datum is not the `V1` constructor.
test reject_v2_non_v1_new_datum() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let probe = Output {
    address: from_script(policy),
    value: from_lovelace(advance_deposit)
      |> merge(from_asset(policy, spent.aid_asset_name, 1)),
    datum: InlineDatum(ProbeV2(adv_vec.pos_adv_wit_2key_created)),
    reference_script: None,
  }
  let tx = spend_context(
    [advance_old_input(spent, old_adv_wit_2key)],
    [],
    [probe],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

// ---------------------------------------------------------------------
// V3 — deposit continuity
// ---------------------------------------------------------------------

/// V3: successor lovelace one below `checkpoint_min_ada + d_reg`.
test reject_v3_deposit_below_floor() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let tx = spend_context(
    [advance_old_input(spent, old_adv_wit_2key)],
    [],
    [
      advance_new_output(
        spent,
        advance_deposit - 1,
        adv_vec.pos_adv_wit_2key_created,
      ),
    ],
    zero,
    [],
    interval.everything,
    0,
  )
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    tx,
  )
}

// ---------------------------------------------------------------------
// V4 / eq5 — sequence continuity (routed through the S5 predicate)
// ---------------------------------------------------------------------

/// eq5: `seq` skips ahead of `spent.seq + 1`.
test reject_eq5_sequence_skip() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let skipped = CheckpointDatumV1 {
    ..adv_vec.pos_adv_wit_2key_created,
    seq: adv_vec.pos_adv_wit_2key_created.seq + 1,
  }
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    advance_tx(spent, old_adv_wit_2key, skipped),
  )
}

/// eq5: `native_sn` does not strictly increase over the spent state.
test reject_eq5_native_sn_non_increasing() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  let stalled = CheckpointDatumV1 {
    ..adv_vec.pos_adv_wit_2key_created,
    native_sn: spent.native_sn,
  }
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    advance_tx(spent, old_adv_wit_2key, stalled),
  )
}

// ---------------------------------------------------------------------
// V4-V7 — at least one end-to-end predicate-evidence rejection (the
// exhaustive AE/W/ctrl/receipt families live in advance_tests.ak)
// ---------------------------------------------------------------------

/// V7: a receipt-free advance (zero witness receipts, toad > 0) rejects
/// end-to-end through the real spend handler.
test reject_v7_end_to_end_receipt_free() fail {
  run_advance(
    Advance { evidence: adv_vec.v7_receipt_free_evidence },
    advance_own_ref(adv_vec.v7_receipt_free_spent),
    advance_tx(
      adv_vec.v7_receipt_free_spent,
      old_adv_wit_2key,
      adv_vec.v7_receipt_free_created,
    ),
  )
}

// ---------------------------------------------------------------------
// T116-S4 RED — live Freeze and ordinary-Advance thaw. Every case invokes
// the five-argument applied checkpoint spend handler; the enforcement input
// is the committed wire fixture, never a pure-predicate substitute.
// ---------------------------------------------------------------------

const freeze_own_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 8 }

const other_aid: ByteArray =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

fn unknown_role_address() -> Address {
  from_script(policy)
    |> with_delegation_script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      )
}

fn freeze_value(tip: CheckpointDatumV1) -> Value {
  from_lovelace(advance_deposit)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
    |> merge(from_asset(hp_policy, #"f0", 3))
}

fn freeze_input(
  tip: CheckpointDatumV1,
  address: Address,
  datum: Data,
  value: Value,
) -> Input {
  input_at(
    freeze_own_ref,
    Output { address, value, datum: InlineDatum(datum), reference_script: None },
  )
}

fn freeze_output(address: Address, datum: Data, value: Value) -> Output {
  Output { address, value, datum: InlineDatum(datum), reference_script: None }
}

fn freeze_context(
  tip: CheckpointDatumV1,
  input_address: Address,
  input_datum: Data,
  input_value: Value,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  spend_context(
    [freeze_input(tip, input_address, input_datum, input_value)],
    [],
    outputs,
    mint,
    [],
    interval.everything,
    0,
  )
}

fn freeze_tx(tip: CheckpointDatumV1) -> Transaction {
  let value = freeze_value(tip)
  freeze_context(
    tip,
    role.address(policy, Active),
    V1(tip),
    value,
    [freeze_output(role.address(policy, Frozen), V1(tip), value)],
    zero,
  )
}

fn run_freeze(
  evidence: EnforcementEvidence,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let redeemer: Data = Slice4Freeze { evidence }
  run_advance(redeemer, own_ref, tx)
}

// Honest REDs: current Slice-3 code rejects both because Freeze is fail-closed
// and Advance admits only ACTIVE. GREEN must flip these exact tests.
test t116_r2_reject_old_direct_active_to_frozen_wire() fail {
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_r2_stage_reject_advance_thaw_from_frozen() fail {
  let tip = old_adv_wit_2key
  let value = from_lovelace(min_ada + d_reg)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_r2(
    R2Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    r2_context(
      tip,
      role.address(policy, Frozen),
      V1(tip),
      value,
      [],
      zero,
      interval.everything,
    ),
  )
}

// EE0-EE9 at the live handler boundary.
test t116_s4_reject_freeze_ee0_empty_event() fail {
  let wire = EnforcementEvidence { ..enf_vec.lag_freeze_wire, event_bytes: #"" }
  run_freeze(wire, freeze_own_ref, freeze_tx(enf_vec.lag_freeze_tip))
}

test t116_s4_reject_freeze_ee0_over_1024_event() fail {
  let wire = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    event_bytes: bytearray.concat(
      enf_vec.honest7_freeze_evidence.event_bytes,
      enf_vec.honest7_freeze_evidence.event_bytes,
    ),
  }
  run_freeze(wire, freeze_own_ref, freeze_tx(enf_vec.lag_freeze_tip))
}

test t116_s4_reject_freeze_ee1_type_offset() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_t: wire.off_i },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee2_aid_offset() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_i: wire.off_s },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee3_sequence_offset() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_s: wire.off_t },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee4_said_width() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, said: bytearray.take(wire.said, 31) },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee5_key_count() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_k: [] },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee6_threshold_offset() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_kt: wire.off_t },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee7_next_key_count() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_n: [] },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee8_next_threshold_offset() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_nt: wire.off_t },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_ee9_toad_offset() fail {
  let wire = enf_vec.lag_freeze_wire
  run_freeze(
    EnforcementEvidence { ..wire, off_bt: wire.off_t },
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_reject_freeze_replayed_not_ahead_event() fail {
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, native_sn: 1 }
  run_freeze(enf_vec.lag_freeze_wire, freeze_own_ref, freeze_tx(tip))
}

test t116_s4_reject_freeze_crossed_aid_wire() fail {
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, cesr_aid: other_aid }
  run_freeze(enf_vec.lag_freeze_wire, freeze_own_ref, freeze_tx(tip))
}

test t116_s4_reject_freeze_w3_duplicate_receipt_for_toad_two() fail {
  expect [receipt] = enf_vec.lag_freeze_wire.wit_sigs
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, toad: 2 }
  let wire = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    wit_sigs: [receipt, receipt],
  }
  run_freeze(wire, freeze_own_ref, freeze_tx(tip))
}

// R1 input role/datum/token boundary. Whole-address role checks reject every
// staking mutation even though payment credentials still name this validator.
test t116_s4_reject_freeze_from_frozen_as_standalone_thaw() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Frozen),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Active), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_from_tombstone_role() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Tombstone),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_from_unknown_role() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      unknown_role_address(),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_wrong_role_datum_pairing() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      TombstoneV1 {
        cesr_aid: tip.cesr_aid,
        convicted_at_native_sn: tip.native_sn,
        evidence_said: other_aid,
      },
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_missing_input_token() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = from_lovelace(advance_deposit)
    |> merge(from_asset(hp_policy, #"f0", 3))
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_input_token_quantity_two() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_wrong_own_ref() fail {
  run_freeze(
    enf_vec.lag_freeze_wire,
    out_ref(seed_tx_id, 7),
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

// F12-L output confinement: exactly one FROZEN output, same inline V1 Data
// and complete Value, with no own-policy mint or burn.
test t116_s4_reject_freeze_missing_frozen_output() fail {
  let tip = enf_vec.lag_freeze_tip
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      freeze_value(tip),
      [],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_duplicate_frozen_output() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  let frozen = freeze_output(role.address(policy, Frozen), V1(tip), value)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [frozen, frozen],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_active_output() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Active), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_tombstone_output() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Tombstone), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_unknown_role_output() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(unknown_role_address(), V1(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_changed_datum() fail {
  let tip = enf_vec.lag_freeze_tip
  let changed = CheckpointDatumV1 { ..tip, seq: tip.seq + 1 }
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(changed), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_missing_output_datum() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  let bare = Output {
    address: role.address(policy, Frozen),
    value,
    datum: NoDatum,
    reference_script: None,
  }
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [bare],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_non_v1_output_datum() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), ProbeV2(tip), value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_any_complete_value_change() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [
        freeze_output(
          role.address(policy, Frozen),
          V1(tip),
          value |> merge(from_lovelace(1)),
        ),
      ],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_output_token_omission() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = freeze_value(tip)
  let output_value = from_lovelace(advance_deposit)
    |> merge(from_asset(hp_policy, #"f0", 3))
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      input_value,
      [freeze_output(role.address(policy, Frozen), V1(tip), output_value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_output_token_quantity_change() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = freeze_value(tip)
  let output_value = input_value
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      input_value,
      [freeze_output(role.address(policy, Frozen), V1(tip), output_value)],
      zero,
    ),
  )
}

test t116_s4_reject_freeze_own_policy_mint() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      from_asset(policy, #"ee", 1),
    ),
  )
}

test t116_s4_reject_freeze_own_policy_burn() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Frozen), V1(tip), value)],
      from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    ),
  )
}

// T1: only an ordinary, fully-valid Advance may thaw FROZEN back to ACTIVE.
test t116_s4_reject_invalid_advance_proof_from_frozen() fail {
  let spent = adv_vec.v7_receipt_free_spent
  run_advance(
    Advance { evidence: adv_vec.v7_receipt_free_evidence },
    advance_own_ref(spent),
    advance_tx_from(
      spent,
      old_adv_wit_2key,
      adv_vec.v7_receipt_free_created,
      role.address(policy, Frozen),
    ),
  )
}

test t116_s4_reject_advance_from_tombstone() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    advance_tx_from(
      spent,
      old_adv_wit_2key,
      adv_vec.pos_adv_wit_2key_created,
      role.address(policy, Tombstone),
    ),
  )
}

test t116_s4_reject_advance_from_unknown_role() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    advance_tx_from(
      spent,
      old_adv_wit_2key,
      adv_vec.pos_adv_wit_2key_created,
      unknown_role_address(),
    ),
  )
}

// ---------------------------------------------------------------------
// T116-S5 — witnessed Convict, bounty release, exact TombstoneV1, and
// pre-dispatch terminality. Every boundary test drives the real applied
// checkpoint handler.
// ---------------------------------------------------------------------

const convict_own_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 6 }

fn convict_input_value(tip: CheckpointDatumV1) -> Value {
  from_lovelace(advance_deposit)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
    |> merge(from_asset(hp_policy, #"f1", 3))
}

fn tombstone_value(tip: CheckpointDatumV1) -> Value {
  from_lovelace(min_ada)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
}

fn tombstone_record(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
) -> TombstoneV1 {
  TombstoneV1 {
    cesr_aid: tip.cesr_aid,
    convicted_at_native_sn: tip.native_sn,
    evidence_said: evidence.said,
  }
}

fn convict_input(address: Address, datum: Data, value: Value) -> Input {
  input_at(
    convict_own_ref,
    Output { address, value, datum: InlineDatum(datum), reference_script: None },
  )
}

fn convict_output(address: Address, datum: Data, value: Value) -> Output {
  Output { address, value, datum: InlineDatum(datum), reference_script: None }
}

fn convict_context(
  input_address: Address,
  input_datum: Data,
  input_value: Value,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  spend_context(
    [convict_input(input_address, input_datum, input_value)],
    [],
    outputs,
    mint,
    [],
    interval.everything,
    0,
  )
}

fn convict_tx_from(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  input_address: Address,
) -> Transaction {
  convict_context(
    input_address,
    V1(tip),
    convict_input_value(tip),
    [
      convict_output(
        role.address(policy, Tombstone),
        tombstone_record(tip, evidence),
        tombstone_value(tip),
      ),
    ],
    zero,
  )
}

fn run_convict(
  evidence: EnforcementEvidence,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let redeemer: Data = Slice5Convict { evidence }
  run_advance(redeemer, own_ref, tx)
}

// Genuine RED: this is a committed, controller-and-witness-signed conflicting
// rotation. Slice 4 cannot decode its fielded Convict wire evidence yet.
test t116_r2_stage_reject_convict_from_active_real_witnessed_wire() fail {
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_tx_from(
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire,
      role.address(policy, Active),
    ),
  )
}

test t116_r2_stage_reject_convict_from_frozen_real_witnessed_wire() fail {
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_tx_from(
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire,
      role.address(policy, Frozen),
    ),
  )
}

// F1b/F3b through the live handler, not the pure predicate.
test t116_s5_reject_f1b_insufficient_witnessed_receipts() fail {
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    wit_sigs: [],
  }
  run_convict(
    evidence,
    convict_own_ref,
    convict_tx_from(
      enf_vec.fork_witnessed_convict_tip,
      evidence,
      role.address(policy, Active),
    ),
  )
}

test t116_s5_reject_f3b_witnessed_honest_recorded_no_conflict() fail {
  run_convict(
    enf_vec.fork_witnessed_honest_wire,
    convict_own_ref,
    convict_tx_from(
      enf_vec.fork_witnessed_honest_tip,
      enf_vec.fork_witnessed_honest_wire,
      role.address(policy, Active),
    ),
  )
}

// Live EE binding, replay, and crossed-AID regressions.
test t116_s5_reject_convict_misdirected_wire_offset() fail {
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    off_i: enf_vec.fork_witnessed_convict_wire.off_s,
  }
  run_convict(
    evidence,
    convict_own_ref,
    convict_tx_from(
      enf_vec.fork_witnessed_convict_tip,
      evidence,
      role.address(policy, Active),
    ),
  )
}

test t116_s5_reject_convict_replayed_sequence() fail {
  let tip = CheckpointDatumV1 {
    ..enf_vec.fork_witnessed_convict_tip,
    native_sn: enf_vec.fork_witnessed_convict_tip.native_sn + 1,
  }
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_tx_from(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      role.address(policy, Active),
    ),
  )
}

test t116_s5_reject_convict_crossed_aid_wire() fail {
  let tip = CheckpointDatumV1 {
    ..enf_vec.fork_witnessed_convict_tip,
    cesr_aid: other_aid,
  }
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_tx_from(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      role.address(policy, Active),
    ),
  )
}

// F13-L input role/datum/token/outref confinement.
test t116_s5_reject_convict_from_wrong_input_role() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_tx_from(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      unknown_role_address(),
    ),
  )
}

test t116_s5_reject_convict_wrong_input_datum_family() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      ProbeV2(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_missing_input_token() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let input_value = from_lovelace(advance_deposit)
    |> merge(from_asset(hp_policy, #"f1", 3))
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      input_value,
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_input_token_quantity_two() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let input_value = convict_input_value(tip)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      input_value,
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_wrong_own_ref() fail {
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    out_ref(seed_tx_id, 5),
    convict_tx_from(
      enf_vec.fork_witnessed_convict_tip,
      enf_vec.fork_witnessed_convict_wire,
      role.address(policy, Active),
    ),
  )
}

// F13-L exact Tombstone address, unique output, datum, record, token, and
// min-ADA-only value. The input residual is intentionally absent here.
test t116_s5_reject_convict_missing_tombstone_output() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [],
      zero,
    ),
  )
}

test t116_s5_reject_convict_duplicate_tombstone_output() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let output = convict_output(
    role.address(policy, Tombstone),
    tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
    tombstone_value(tip),
  )
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [output, output],
      zero,
    ),
  )
}

test t116_s5_reject_convict_wrong_role_output() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Frozen),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_missing_tombstone_datum() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let output = Output {
    address: role.address(policy, Tombstone),
    value: tombstone_value(tip),
    datum: NoDatum,
    reference_script: None,
  }
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [output],
      zero,
    ),
  )
}

test t116_s5_reject_convict_non_tombstone_datum() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          V1(tip),
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_wrong_tombstone_record() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let record = TombstoneV1 {
    ..tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
    cesr_aid: other_aid,
  }
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          record,
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_wrong_evidence_said_record() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let record = TombstoneV1 {
    ..tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
    evidence_said: other_aid,
  }
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          record,
          tombstone_value(tip),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_output_token_omission() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          from_lovelace(min_ada),
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_output_token_quantity_two() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let value = tombstone_value(tip)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          value,
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_retained_registration_deposit() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let value = from_lovelace(advance_deposit)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          value,
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_retained_extra_native_asset() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let value = tombstone_value(tip) |> merge(from_asset(hp_policy, #"f1", 3))
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    convict_context(
      role.address(policy, Active),
      V1(tip),
      convict_input_value(tip),
      [
        convict_output(
          role.address(policy, Tombstone),
          tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
          value,
        ),
      ],
      zero,
    ),
  )
}

test t116_s5_reject_convict_own_policy_mint() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = convict_tx_from(
    tip,
    enf_vec.fork_witnessed_convict_wire,
    role.address(policy, Active),
  )
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    Transaction { ..tx, mint: from_asset(policy, #"ee", 1) },
  )
}

test t116_s5_reject_convict_own_policy_burn() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = convict_tx_from(
    tip,
    enf_vec.fork_witnessed_convict_wire,
    role.address(policy, Active),
  )
  run_convict(
    enf_vec.fork_witnessed_convict_wire,
    convict_own_ref,
    Transaction {
      ..tx,
      mint: from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    },
  )
}

// F11: every current spend redeemer is tried against a real TOMBSTONE role,
// exact TombstoneV1 record, and quantity-one AID token. All must fail before
// branch-specific predicates can admit the state.
fn terminal_tombstone_tx() -> Transaction {
  let tip = enf_vec.fork_witnessed_convict_tip
  spend_context(
    [
      convict_input(
        role.address(policy, Tombstone),
        tombstone_record(tip, enf_vec.fork_witnessed_convict_wire),
        tombstone_value(tip),
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

test t116_s5_f11_reject_advance_from_terminal_tombstone() fail {
  let redeemer: Data = Slice5Advance {
    evidence: adv_vec.pos_adv_wit_2key_evidence,
  }
  run_advance(redeemer, convict_own_ref, terminal_tombstone_tx())
}

test t116_s5_f11_reject_freeze_from_terminal_tombstone() fail {
  let redeemer: Data = Slice5Freeze { evidence: enf_vec.lag_freeze_wire }
  run_advance(redeemer, convict_own_ref, terminal_tombstone_tx())
}

test t116_s5_f11_reject_convict_from_terminal_tombstone() fail {
  let redeemer: Data = Slice5Convict {
    evidence: enf_vec.fork_witnessed_convict_wire,
  }
  run_advance(redeemer, convict_own_ref, terminal_tombstone_tx())
}

test t116_s5_f11_reject_close_from_terminal_tombstone() fail {
  let redeemer: Data = Slice5Close
  run_advance(redeemer, convict_own_ref, terminal_tombstone_tx())
}

// A same-AID tombstone may be supplied as read-only history and does not
// prevent creation of a fresh independent ACTIVE registration.
test t114_r3_accept_post_conviction_via_reference_input() {
  let d = vec.pos_2key_datum
  let key = deriveAidAssetName(d.cesr_aid)
  let tombstone = input_at(
    convict_own_ref,
    Output {
      address: role.address(policy, Tombstone),
      value: from_lovelace(min_ada) |> merge(from_asset(policy, key, 1)),
      datum: InlineDatum(
        TombstoneV1 {
          cesr_aid: d.cesr_aid,
          convicted_at_native_sn: d.native_sn,
          evidence_said: other_aid,
        },
      ),
      reference_script: None,
    },
  )
  let tx = bonded_register_tx_at(d, register_floor, vec.pos_2key_evidence)
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, reference_inputs: [tombstone] },
  )
}

// ---------------------------------------------------------------------
// T116-R2 RED — ACTIVE -> ARMED Arm and ARMED -> FROZEN Claim.
//
// The helper exposes the target six deployment parameters while the RED
// implementation deliberately invokes the delivered four-parameter handler.
// GREEN changes that one call to the exact target application after these
// full-context tests have failed for the missing live behavior.
// ---------------------------------------------------------------------

const r2_arm_upper: Int = 1_000

const r2_deadline: Int = r2_arm_upper + r2_freeze_window

const r2_hunter: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const r2_other_hunter: ByteArray =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const r2_hunter_short: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fn r2_reserve_value(tip: CheckpointDatumV1) -> Value {
  from_lovelace(min_ada + d_reg + r2_freeze_bond)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
}

fn r2_surplus_value(tip: CheckpointDatumV1) -> Value {
  r2_reserve_value(tip)
    |> merge(from_lovelace(17))
    |> merge(from_asset(hp_policy, #"f2", 3))
}

fn r2_armed_datum(
  tip: CheckpointDatumV1,
  hunter_pkh: ByteArray,
  deadline: Int,
) -> ArmedDatum {
  ArmedV2 { checkpoint: tip, hunter_pkh, deadline }
}

fn r2_armed_output(
  tip: CheckpointDatumV1,
  value: Value,
  hunter_pkh: ByteArray,
  deadline: Int,
) -> Output {
  freeze_output(
    role.address(policy, Armed),
    r2_armed_datum(tip, hunter_pkh, deadline),
    value,
  )
}

fn r2_frozen_output(tip: CheckpointDatumV1, value: Value) -> Output {
  freeze_output(role.address(policy, Frozen), V1(tip), value)
}

fn r2_hunter_output(hunter_pkh: ByteArray, value: Value, datum: Datum) -> Output {
  Output {
    address: from_verification_key(hunter_pkh),
    value,
    datum,
    reference_script: None,
  }
}

fn r2_context(
  tip: CheckpointDatumV1,
  input_address: Address,
  input_datum: Data,
  input_value: Value,
  outputs: List<Output>,
  mint: Value,
  validity_range: interval.Interval<Int>,
) -> Transaction {
  spend_context(
    [freeze_input(tip, input_address, input_datum, input_value)],
    [],
    outputs,
    mint,
    [],
    validity_range,
    0,
  )
}

fn r2_arm_tx_with(
  tip: CheckpointDatumV1,
  value: Value,
  hunter_pkh: ByteArray,
  deadline: Int,
  validity_range: interval.Interval<Int>,
) -> Transaction {
  r2_context(
    tip,
    role.address(policy, Active),
    V1(tip),
    value,
    [r2_armed_output(tip, value, hunter_pkh, deadline)],
    zero,
    validity_range,
  )
}

fn r2_arm_tx(tip: CheckpointDatumV1) -> Transaction {
  r2_arm_tx_with(
    tip,
    r2_surplus_value(tip),
    r2_hunter,
    r2_deadline,
    interval.between(0, r2_arm_upper),
  )
}

fn r2_claim_tx_with(
  tip: CheckpointDatumV1,
  input_value: Value,
  hunter_pkh: ByteArray,
  deadline: Int,
  outputs: List<Output>,
  validity_range: interval.Interval<Int>,
) -> Transaction {
  r2_context(
    tip,
    role.address(policy, Armed),
    r2_armed_datum(tip, hunter_pkh, deadline),
    input_value,
    outputs,
    zero,
    validity_range,
  )
}

fn r2_claim_tx(tip: CheckpointDatumV1, lower: Int) -> Transaction {
  let input_value = r2_surplus_value(tip)
  r2_claim_tx_with(
    tip,
    input_value,
    r2_hunter,
    r2_deadline,
    [
      r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
      r2_frozen_output(
        tip,
        input_value |> merge(from_lovelace(-r2_freeze_bond)),
      ),
    ],
    interval.after(lower),
  )
}

fn run_r2_with_parameters(
  freeze_bond_parameter: Int,
  freeze_window_parameter: Int,
  redeemer: R2SpendRedeemer,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let redeemer_data: Data = redeemer
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    freeze_bond_parameter,
    freeze_window_parameter,
    applied_commitment,
    None,
    redeemer_data,
    own_ref,
    tx,
  )
}

fn run_r2(redeemer: R2SpendRedeemer, tx: Transaction) -> Bool {
  run_r2_with_parameters(
    r2_freeze_bond,
    r2_freeze_window,
    redeemer,
    freeze_own_ref,
    tx,
  )
}

fn r2_arm_redeemer(hunter_pkh: ByteArray) -> R2SpendRedeemer {
  R2Freeze { evidence: enf_vec.lag_freeze_wire, hunter_pkh }
}

fn r2_claim_redeemer(index: Int) -> R2SpendRedeemer {
  R2ClaimFreeze { hunter_output_index: index }
}

// The #116 arming acceptance rows below likewise carry the hunter's authentic
// matured reservation now. Each still asserts exactly what it always did — that
// the complete value is preserved and the deadline recorded, that the exact
// reserve floor is admissible, that a raw exclusive upper endpoint is never
// normalized inward, and that unrelated inputs and outputs are tolerated — with
// the arm made entitled rather than unauthenticated.

test t116_r2_accept_arm_preserves_complete_value_and_records_deadline() {
  run_s254e_arm(r2_arm_tx(enf_vec.lag_freeze_tip))
}

test t116_r2_accept_arm_at_exact_reserve_floor() {
  let tip = enf_vec.lag_freeze_tip
  run_s254e_arm(
    r2_arm_tx_with(
      tip,
      r2_reserve_value(tip),
      r2_hunter,
      r2_deadline,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_accept_arm_raw_exclusive_upper_without_normalizing() {
  let tip = enf_vec.lag_freeze_tip
  run_s254e_arm(
    r2_arm_tx_with(
      tip,
      r2_surplus_value(tip),
      r2_hunter,
      r2_deadline,
      interval.entirely_between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_accept_arm_with_unrelated_extra_input_and_output() {
  let tip = enf_vec.lag_freeze_tip
  let tx = r2_arm_tx(tip)
  let extra_input = value_input(19, from_lovelace(42_000_000))
  let extra_output = r2_hunter_output(
    r2_other_hunter,
    from_lovelace(9_000_000),
    NoDatum,
  )
  run_s254e_arm(
    Transaction {
      ..tx,
      inputs: list.concat(tx.inputs, [extra_input]),
      outputs: list.concat(tx.outputs, [extra_output]),
    },
  )
}

test t116_r2_accept_claim_at_exact_deadline() {
  run_r2(r2_claim_redeemer(0), r2_claim_tx(enf_vec.lag_freeze_tip, r2_deadline))
}

test t116_r2_accept_claim_after_deadline() {
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx(enf_vec.lag_freeze_tip, r2_deadline + 1),
  )
}

test t116_r2_accept_claim_at_exact_reserve_and_preserve_frozen_reserve() {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_reserve_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_accept_claim_with_unrelated_extra_input_and_output() {
  let tip = enf_vec.lag_freeze_tip
  let tx = r2_claim_tx(tip, r2_deadline)
  let extra_input = value_input(20, from_lovelace(42_000_000))
  let extra_output = r2_hunter_output(
    r2_other_hunter,
    from_lovelace(9_000_000),
    NoDatum,
  )
  run_r2(
    r2_claim_redeemer(0),
    Transaction {
      ..tx,
      inputs: list.concat(tx.inputs, [extra_input]),
      outputs: list.concat(tx.outputs, [extra_output]),
    },
  )
}

test t116_r2_reject_freeze_bond_below_floor_before_dispatch() fail {
  run_r2_with_parameters(
    r2_freeze_bond - 1,
    r2_freeze_window,
    r2_arm_redeemer(r2_hunter),
    freeze_own_ref,
    r2_arm_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_r2_reject_zero_freeze_window_before_dispatch() fail {
  run_r2_with_parameters(
    r2_freeze_bond,
    0,
    r2_arm_redeemer(r2_hunter),
    freeze_own_ref,
    r2_arm_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_r2_reject_negative_freeze_window_before_dispatch() fail {
  run_r2_with_parameters(
    r2_freeze_bond,
    -1,
    r2_arm_redeemer(r2_hunter),
    freeze_own_ref,
    r2_arm_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_r2_reject_arm_hunter_wrong_width() fail {
  run_r2(r2_arm_redeemer(r2_hunter_short), r2_arm_tx(enf_vec.lag_freeze_tip))
}

test t116_r2_reject_arm_empty_validity_range() fail {
  let tip = enf_vec.lag_freeze_tip
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_arm_tx_with(
      tip,
      r2_surplus_value(tip),
      r2_hunter,
      r2_deadline,
      interval.empty,
    ),
  )
}

test t116_r2_reject_arm_nonfinite_upper_bound() fail {
  let tip = enf_vec.lag_freeze_tip
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_arm_tx_with(
      tip,
      r2_surplus_value(tip),
      r2_hunter,
      r2_deadline,
      interval.after(0),
    ),
  )
}

test t116_r2_reject_arm_wrong_deadline() fail {
  let tip = enf_vec.lag_freeze_tip
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_arm_tx_with(
      tip,
      r2_surplus_value(tip),
      r2_hunter,
      r2_deadline - 1,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_wrong_successor_wrapper() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_surplus_value(tip)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [freeze_output(role.address(policy, Armed), V1(tip), value)],
      zero,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_live_ee_binding_mutation() fail {
  let tip = enf_vec.lag_freeze_tip
  let evidence = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    off_i: enf_vec.lag_freeze_wire.off_s,
  }
  run_r2(R2Freeze { evidence, hunter_pkh: r2_hunter }, r2_arm_tx(tip))
}

test t116_r2_reject_arm_live_freeze_predicate_replay() fail {
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, native_sn: 1 }
  run_r2(r2_arm_redeemer(r2_hunter), r2_arm_tx(tip))
}

test t116_r2_reject_arm_live_duplicate_receipt_quorum() fail {
  expect [receipt] = enf_vec.lag_freeze_wire.wit_sigs
  let tip = CheckpointDatumV1 { ..enf_vec.lag_freeze_tip, toad: 2 }
  let evidence = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    wit_sigs: [receipt, receipt],
  }
  run_r2(R2Freeze { evidence, hunter_pkh: r2_hunter }, r2_arm_tx(tip))
}

test t116_r2_reject_arm_input_below_protected_reserve() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_reserve_value(tip) |> merge(from_lovelace(-1))
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_arm_tx_with(
      tip,
      value,
      r2_hunter,
      r2_deadline,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_missing_token() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = from_lovelace(min_ada + d_reg + r2_freeze_bond)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_arm_tx_with(
      tip,
      value,
      r2_hunter,
      r2_deadline,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_input_token_quantity_two() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_reserve_value(tip)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_arm_tx_with(
      tip,
      value,
      r2_hunter,
      r2_deadline,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_mutated_inner_checkpoint() fail {
  let tip = enf_vec.lag_freeze_tip
  let changed = CheckpointDatumV1 { ..tip, seq: tip.seq + 1 }
  let value = r2_surplus_value(tip)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [r2_armed_output(changed, value, r2_hunter, r2_deadline)],
      zero,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_changed_complete_value() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_surplus_value(tip)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [
        r2_armed_output(
          tip,
          value |> merge(from_lovelace(1)),
          r2_hunter,
          r2_deadline,
        ),
      ],
      zero,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_missing_successor() fail {
  let tip = enf_vec.lag_freeze_tip
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      r2_surplus_value(tip),
      [],
      zero,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_duplicate_successor() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_surplus_value(tip)
  let successor = r2_armed_output(tip, value, r2_hunter, r2_deadline)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [successor, successor],
      zero,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_arm_own_policy_mint() fail {
  let tip = enf_vec.lag_freeze_tip
  let tx = r2_arm_tx(tip)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    Transaction { ..tx, mint: from_asset(policy, #"ee", 1) },
  )
}

test t116_r2_reject_arm_own_policy_burn() fail {
  let tip = enf_vec.lag_freeze_tip
  let tx = r2_arm_tx(tip)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    Transaction {
      ..tx,
      mint: from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    },
  )
}

test t116_r2_reject_repeated_arm_from_armed() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_surplus_value(tip)
  run_r2(
    r2_arm_redeemer(r2_hunter),
    r2_context(
      tip,
      role.address(policy, Armed),
      r2_armed_datum(tip, r2_hunter, r2_deadline),
      value,
      [r2_armed_output(tip, value, r2_hunter, r2_deadline)],
      zero,
      interval.between(0, r2_arm_upper),
    ),
  )
}

test t116_r2_reject_claim_before_deadline() fail {
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx(enf_vec.lag_freeze_tip, r2_deadline - 1),
  )
}

test t116_r2_reject_claim_unbounded_lower() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.before(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_input_below_protected_reserve() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_reserve_value(tip) |> merge(from_lovelace(-1))
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_missing_input_token() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = from_lovelace(min_ada + d_reg + r2_freeze_bond)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_input_token_quantity_two() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_reserve_value(tip)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_wrong_payout_index() fail {
  run_r2(r2_claim_redeemer(1), r2_claim_tx(enf_vec.lag_freeze_tip, r2_deadline))
}

test t116_r2_reject_claim_out_of_bounds_payout_index() fail {
  run_r2(r2_claim_redeemer(9), r2_claim_tx(enf_vec.lag_freeze_tip, r2_deadline))
}

test t116_r2_reject_claim_wrong_beneficiary() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(
          r2_other_hunter,
          from_lovelace(r2_freeze_bond),
          NoDatum,
        ),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_underpaid_bond() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond - 1), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_overpaid_bond() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond + 1), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_payout_with_datum() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(
          r2_hunter,
          from_lovelace(r2_freeze_bond),
          InlineDatum(V1(tip)),
        ),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_payout_with_extra_asset() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  let payout_value = from_lovelace(r2_freeze_bond)
    |> merge(from_asset(hp_policy, #"ff", 1))
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, payout_value, NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_retained_bond_in_frozen_value() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(tip, input_value),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_over_subtracted_frozen_value() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond - 1)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_mutated_inner_checkpoint() fail {
  let tip = enf_vec.lag_freeze_tip
  let changed = CheckpointDatumV1 { ..tip, seq: tip.seq + 1 }
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          changed,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_missing_frozen_successor() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum)],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_duplicate_frozen_successor() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  let frozen = r2_frozen_output(
    tip,
    input_value |> merge(from_lovelace(-r2_freeze_bond)),
  )
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter,
      r2_deadline,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        frozen,
        frozen,
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_wrong_role_datum_pairing() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_context(
      tip,
      role.address(policy, Armed),
      V1(tip),
      input_value,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      zero,
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_armed_wrapper_at_active_role() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_context(
      tip,
      role.address(policy, Active),
      r2_armed_datum(tip, r2_hunter, r2_deadline),
      input_value,
      [
        r2_hunter_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      zero,
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_malformed_hunter_width() fail {
  let tip = enf_vec.lag_freeze_tip
  let input_value = r2_surplus_value(tip)
  run_r2(
    r2_claim_redeemer(0),
    r2_claim_tx_with(
      tip,
      input_value,
      r2_hunter_short,
      r2_deadline,
      [
        r2_hunter_output(
          r2_hunter_short,
          from_lovelace(r2_freeze_bond),
          NoDatum,
        ),
        r2_frozen_output(
          tip,
          input_value |> merge(from_lovelace(-r2_freeze_bond)),
        ),
      ],
      interval.after(r2_deadline),
    ),
  )
}

test t116_r2_reject_claim_own_policy_mint() fail {
  let tip = enf_vec.lag_freeze_tip
  let tx = r2_claim_tx(tip, r2_deadline)
  run_r2(
    r2_claim_redeemer(0),
    Transaction { ..tx, mint: from_asset(policy, #"ee", 1) },
  )
}

test t116_r2_reject_claim_own_policy_burn() fail {
  let tip = enf_vec.lag_freeze_tip
  let tx = r2_claim_tx(tip, r2_deadline)
  run_r2(
    r2_claim_redeemer(0),
    Transaction {
      ..tx,
      mint: from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    },
  )
}

test t116_r2_stage_reject_active_advance() fail {
  let tip = old_adv_wit_2key
  let value = r2_reserve_value(tip)
  run_r2(
    R2Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [],
      zero,
      interval.everything,
    ),
  )
}

test t116_r2_stage_reject_armed_advance_reserved_for_115() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = r2_surplus_value(tip)
  run_r2(
    R2Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    r2_context(
      tip,
      role.address(policy, Armed),
      r2_armed_datum(tip, r2_hunter, r2_deadline),
      value,
      [],
      zero,
      interval.before(r2_deadline - 1),
    ),
  )
}

test t116_r2_stage_reject_convict() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let value = r2_reserve_value(tip)
  run_r2(
    R2Convict,
    r2_context(
      tip,
      role.address(policy, Active),
      V1(tip),
      value,
      [],
      zero,
      interval.everything,
    ),
  )
}

test t116_r2_stage_reject_close() fail {
  run_r2(R2Close, r2_arm_tx(enf_vec.lag_freeze_tip))
}

/// D2 retained guard: reference-only same-AID history cannot weaken the live
/// reserve; a repeated registration one lovelace below `min+D_reg+B` rejects.
test t114_r3_reject_repeated_registration_one_below_bonded_floor() fail {
  let d = vec.pos_2key_datum
  let key = deriveAidAssetName(d.cesr_aid)
  let tombstone = input_at(
    convict_own_ref,
    Output {
      address: role.address(policy, Tombstone),
      value: from_lovelace(min_ada) |> merge(from_asset(policy, key, 1)),
      datum: InlineDatum(
        TombstoneV1 {
          cesr_aid: d.cesr_aid,
          convicted_at_native_sn: d.native_sn,
          evidence_said: other_aid,
        },
      ),
      reference_script: None,
    },
  )
  let tx = bonded_register_tx_at(d, register_floor - 1, vec.pos_2key_evidence)
  run_register(
    vec.pos_2key_evidence,
    Transaction { ..tx, reference_inputs: [tombstone] },
  )
}

test reject_close_fails_closed() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  run_advance(
    Close,
    advance_own_ref(spent),
    advance_tx(spent, old_adv_wit_2key, adv_vec.pos_adv_wit_2key_created),
  )
}

// ---------------------------------------------------------------------
// T116-R3 RED — exact ACTIVE/ARMED/FROZEN conviction routing.
//
// Every context below uses the committed witnessed-fork evidence, an exact
// terminal tombstone, balanced protected-reserve payouts, and explicit
// output indices. The delivered R2 handler has no fielded Convict wire or
// live Convict dispatch, so the honest contexts are the intended RED.
// ---------------------------------------------------------------------

const r3_convictor: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const r3_other_convictor: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const r3_convictor_short: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const r3_surplus_lovelace: Int = 17

fn r3_change_value() -> Value {
  from_lovelace(r3_surplus_lovelace)
    |> merge(from_asset(hp_policy, #"f3", 3))
}

fn r3_state_value(tip: CheckpointDatumV1, protected_lovelace: Int) -> Value {
  from_lovelace(min_ada + protected_lovelace)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
    |> merge(r3_change_value())
}

fn r3_terminal_value(tip: CheckpointDatumV1) -> Value {
  tombstone_value(tip)
}

fn r3_terminal_output(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  value: Value,
) -> Output {
  convict_output(
    role.address(policy, Tombstone),
    tombstone_record(tip, evidence),
    value,
  )
}

fn r3_payout_output(pkh: ByteArray, value: Value, datum: Datum) -> Output {
  r2_hunter_output(pkh, value, datum)
}

fn r3_change_output() -> Output {
  r3_payout_output(r3_other_convictor, r3_change_value(), NoDatum)
}

fn r3_context(
  input_address: Address,
  input_datum: Data,
  input_value: Value,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  convict_context(input_address, input_datum, input_value, outputs, mint)
}

fn r3_active_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  convictor_value: Value,
  convictor_datum: Datum,
  terminal_value: Value,
) -> Transaction {
  r3_context(
    role.address(policy, Active),
    V1(tip),
    r3_state_value(tip, d_reg + r2_freeze_bond),
    [
      r3_payout_output(convictor_pkh, convictor_value, convictor_datum),
      r3_terminal_output(tip, evidence, terminal_value),
      r3_change_output(),
    ],
    zero,
  )
}

fn r3_active_tx() -> Transaction {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  r3_active_tx_with(
    tip,
    evidence,
    r3_convictor,
    from_lovelace(d_reg + r2_freeze_bond),
    NoDatum,
    r3_terminal_value(tip),
  )
}

fn r3_armed_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  hunter_pkh: ByteArray,
  convictor_value: Value,
  hunter_value: Value,
  convictor_datum: Datum,
  hunter_datum: Datum,
  terminal_value: Value,
) -> Transaction {
  r3_context(
    role.address(policy, Armed),
    r2_armed_datum(tip, hunter_pkh, r2_deadline),
    r3_state_value(tip, d_reg + r2_freeze_bond),
    [
      r3_payout_output(convictor_pkh, convictor_value, convictor_datum),
      r3_payout_output(hunter_pkh, hunter_value, hunter_datum),
      r3_terminal_output(tip, evidence, terminal_value),
      r3_change_output(),
    ],
    zero,
  )
}

fn r3_armed_tx() -> Transaction {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  r3_armed_tx_with(
    tip,
    evidence,
    r3_convictor,
    r2_hunter,
    from_lovelace(d_reg),
    from_lovelace(r2_freeze_bond),
    NoDatum,
    NoDatum,
    r3_terminal_value(tip),
  )
}

fn r3_frozen_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  convictor_value: Value,
  convictor_datum: Datum,
  terminal_value: Value,
) -> Transaction {
  r3_context(
    role.address(policy, Frozen),
    V1(tip),
    r3_state_value(tip, d_reg),
    [
      r3_payout_output(convictor_pkh, convictor_value, convictor_datum),
      r3_terminal_output(tip, evidence, terminal_value),
      r3_change_output(),
    ],
    zero,
  )
}

fn r3_frozen_tx() -> Transaction {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  r3_frozen_tx_with(
    tip,
    evidence,
    r3_convictor,
    from_lovelace(d_reg),
    NoDatum,
    r3_terminal_value(tip),
  )
}

fn r3_convict_redeemer(
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  hunter_output_index: Int,
) -> R3SpendRedeemer {
  R3Convict {
    evidence,
    convictor_pkh,
    convictor_output_index,
    hunter_output_index,
  }
}

fn run_r3_with_d_reg(
  d_reg_parameter: Int,
  redeemer: R3SpendRedeemer,
  tx: Transaction,
) -> Bool {
  let redeemer_data: Data = redeemer
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg_parameter,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    None,
    redeemer_data,
    convict_own_ref,
    tx,
  )
}

fn run_r3(redeemer: R3SpendRedeemer, tx: Transaction) -> Bool {
  run_r3_with_d_reg(d_reg, redeemer, tx)
}

fn r3_honest_redeemer(
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  hunter_output_index: Int,
) -> R3SpendRedeemer {
  r3_convict_redeemer(
    enf_vec.fork_witnessed_convict_wire,
    convictor_pkh,
    convictor_output_index,
    hunter_output_index,
  )
}

// The #116 conviction acceptance rows below now carry an authentic matured
// reservation for the convictor they pay. They are unchanged in what they
// assert — deposit and bond routing, surplus change, index distinctness,
// tolerance of unrelated inputs and outputs — but a conviction with no
// reservation at all is exactly what this slice makes rejectable, so the honest
// fixture has to become an honest ENTITLED fixture or these rows would be
// asserting the acceptance of the defect.

test t116_r3_accept_convict_active_routes_deposit_and_bond() {
  run_s254e_convict(r3_convictor, 0, 0, r3_active_tx())
}

test t116_r3_accept_convict_armed_routes_deposit_and_recorded_hunter_bond() {
  run_s254e_convict(r3_convictor, 0, 1, r3_armed_tx())
}

test t116_r3_accept_convict_frozen_routes_deposit() {
  run_s254e_convict(r3_convictor, 0, 0, r3_frozen_tx())
}

test t116_r3_accept_convict_preserves_unreserved_surplus_as_change() {
  run_s254e_convict(r3_convictor, 0, 0, r3_active_tx())
}

test t116_r3_accept_convict_with_unrelated_extra_input_and_output() {
  let tx = r3_active_tx()
  let extra_input = value_input(23, from_lovelace(42_000_000))
  let extra_output = r3_payout_output(
    r2_other_hunter,
    from_lovelace(9_000_000),
    NoDatum,
  )
  run_s254e_convict(
    r3_convictor,
    0,
    0,
    Transaction {
      ..tx,
      inputs: list.concat(tx.inputs, [extra_input]),
      outputs: list.concat(tx.outputs, [extra_output]),
    },
  )
}

test t116_r3_accept_self_conviction_and_same_hunter_recipient_at_distinct_indices() {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  let tx = r3_armed_tx_with(
    tip,
    evidence,
    r2_hunter,
    r2_hunter,
    from_lovelace(d_reg),
    from_lovelace(r2_freeze_bond),
    NoDatum,
    NoDatum,
    r3_terminal_value(tip),
  )
  run_s254e_convict(r2_hunter, 0, 1, tx)
}

test t116_r3_accept_armed_distinct_indices_when_payout_amounts_coincide() {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  let equal_d_reg = r2_freeze_bond
  let input_value = r3_state_value(tip, equal_d_reg + r2_freeze_bond)
  let tx = r3_context(
    role.address(policy, Armed),
    r2_armed_datum(tip, r2_hunter, r2_deadline),
    input_value,
    [
      r3_payout_output(r2_hunter, from_lovelace(equal_d_reg), NoDatum),
      r3_payout_output(r2_hunter, from_lovelace(r2_freeze_bond), NoDatum),
      r3_terminal_output(tip, evidence, r3_terminal_value(tip)),
      r3_change_output(),
    ],
    zero,
  )
  run_s254e_convict_with_d_reg(equal_d_reg, r2_hunter, 0, 1, tx)
}

test t116_r3_reject_convictor_wrong_width() fail {
  run_r3(r3_honest_redeemer(r3_convictor_short, 0, 0), r3_active_tx())
}

test t116_r3_reject_active_wrong_convictor_beneficiary() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_other_convictor,
      from_lovelace(d_reg + r2_freeze_bond),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_armed_hunter_redirection() fail {
  let tx = r3_armed_tx()
  expect [convictor_output,
        hunter_output, terminal_output, change_output] = tx.outputs
  let redirected_hunter_output = Output {
    ..hunter_output,
    address: from_verification_key(r3_other_convictor),
  }
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    Transaction {
      ..tx,
      outputs: [
        convictor_output, redirected_hunter_output, terminal_output,
        change_output,
      ],
    },
  )
}

test t116_r3_reject_wrong_convictor_output_index() fail {
  run_r3(r3_honest_redeemer(r3_convictor, 1, 1), r3_active_tx())
}

test t116_r3_reject_out_of_bounds_convictor_output_index() fail {
  run_r3(r3_honest_redeemer(r3_convictor, 99, 0), r3_active_tx())
}

test t116_r3_reject_negative_convictor_output_index() fail {
  run_r3(r3_honest_redeemer(r3_convictor, -1, 0), r3_active_tx())
}

test t116_r3_reject_armed_wrong_hunter_output_index() fail {
  run_r3(r3_honest_redeemer(r3_convictor, 0, 2), r3_armed_tx())
}

test t116_r3_reject_armed_out_of_bounds_hunter_output_index() fail {
  run_r3(r3_honest_redeemer(r3_convictor, 0, 99), r3_armed_tx())
}

test t116_r3_reject_armed_reused_payout_index() fail {
  run_r3(r3_honest_redeemer(r3_convictor, 0, 0), r3_armed_tx())
}

test t116_r3_reject_active_underpaid_deposit_and_bond() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond - 1),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_active_overpaid_deposit_and_bond() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond + 1),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_armed_underpaid_deposit() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg - 1),
      from_lovelace(r2_freeze_bond),
      NoDatum,
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_armed_overpaid_deposit() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg + 1),
      from_lovelace(r2_freeze_bond),
      NoDatum,
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_armed_underpaid_hunter_bond() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg),
      from_lovelace(r2_freeze_bond - 1),
      NoDatum,
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_armed_overpaid_hunter_bond() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg),
      from_lovelace(r2_freeze_bond + 1),
      NoDatum,
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_frozen_underpaid_deposit() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_frozen_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg - 1),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_frozen_overpaid_deposit() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_frozen_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg + 1),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_convictor_payout_with_datum() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond),
      InlineDatum(V1(tip)),
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_convictor_payout_with_extra_asset() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let payout = from_lovelace(d_reg + r2_freeze_bond)
    |> merge(from_asset(hp_policy, #"ff", 1))
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      payout,
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_hunter_payout_with_datum() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg),
      from_lovelace(r2_freeze_bond),
      NoDatum,
      InlineDatum(V1(tip)),
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_hunter_payout_with_extra_asset() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let hunter_value = from_lovelace(r2_freeze_bond)
    |> merge(from_asset(hp_policy, #"ff", 1))
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg),
      hunter_value,
      NoDatum,
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_deposit_retained_in_tombstone() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let terminal = r3_terminal_value(tip) |> merge(from_lovelace(d_reg))
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond),
      NoDatum,
      terminal,
    ),
  )
}

test t116_r3_reject_bond_retained_in_tombstone() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let terminal = r3_terminal_value(tip)
    |> merge(from_lovelace(r2_freeze_bond))
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    r3_armed_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg),
      from_lovelace(r2_freeze_bond),
      NoDatum,
      NoDatum,
      terminal,
    ),
  )
}

test t116_r3_reject_surplus_asset_retained_in_tombstone() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let terminal = r3_terminal_value(tip)
    |> merge(from_asset(hp_policy, #"f3", 3))
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_frozen_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg),
      NoDatum,
      terminal,
    ),
  )
}

test t116_r3_reject_wrong_tombstone_record() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  let wrong_record = TombstoneV1 {
    ..tombstone_record(tip, evidence),
    evidence_said: other_aid,
  }
  let tx = r3_context(
    role.address(policy, Active),
    V1(tip),
    r3_state_value(tip, d_reg + r2_freeze_bond),
    [
      r3_payout_output(
        r3_convictor,
        from_lovelace(d_reg + r2_freeze_bond),
        NoDatum,
      ),
      convict_output(
        role.address(policy, Tombstone),
        wrong_record,
        r3_terminal_value(tip),
      ),
      r3_change_output(),
    ],
    zero,
  )
  run_r3(r3_honest_redeemer(r3_convictor, 0, 0), tx)
}

test t116_r3_reject_missing_terminal_token() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let terminal = from_lovelace(min_ada)
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    r3_frozen_tx_with(
      tip,
      enf_vec.fork_witnessed_convict_wire,
      r3_convictor,
      from_lovelace(d_reg),
      NoDatum,
      terminal,
    ),
  )
}

test t116_r3_reject_missing_input_token() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = r3_active_tx()
  expect [own_input] = tx.inputs
  let missing = Input {
    ..own_input,
    output: Output {
      ..own_input.output,
      value: own_input.output.value
        |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1)),
    },
  }
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    Transaction { ..tx, inputs: [missing] },
  )
}

test t116_r3_reject_input_token_quantity_two() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = r3_active_tx()
  expect [own_input] = tx.inputs
  let doubled = Input {
    ..own_input,
    output: Output {
      ..own_input.output,
      value: own_input.output.value
        |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1)),
    },
  }
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    Transaction { ..tx, inputs: [doubled] },
  )
}

test t116_r3_reject_missing_tombstone_output() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = r3_context(
    role.address(policy, Active),
    V1(tip),
    r3_state_value(tip, d_reg + r2_freeze_bond),
    [
      r3_payout_output(
        r3_convictor,
        from_lovelace(d_reg + r2_freeze_bond),
        NoDatum,
      ),
      r3_change_output(),
    ],
    zero,
  )
  run_r3(r3_honest_redeemer(r3_convictor, 0, 0), tx)
}

test t116_r3_reject_duplicate_tombstone_output() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  let terminal = r3_terminal_output(tip, evidence, r3_terminal_value(tip))
  let tx = r3_context(
    role.address(policy, Frozen),
    V1(tip),
    r3_state_value(tip, d_reg),
    [
      r3_payout_output(r3_convictor, from_lovelace(d_reg), NoDatum),
      terminal,
      terminal,
      r3_change_output(),
    ],
    zero,
  )
  run_r3(r3_honest_redeemer(r3_convictor, 0, 0), tx)
}

test t116_r3_reject_convict_from_wrong_role() fail {
  let tx = r3_active_tx()
  expect [own_input] = tx.inputs
  let wrong = Input {
    ..own_input,
    output: Output { ..own_input.output, address: unknown_role_address() },
  }
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    Transaction { ..tx, inputs: [wrong] },
  )
}

test t116_r3_reject_armed_role_with_checkpoint_datum() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = r3_armed_tx()
  expect [own_input] = tx.inputs
  let wrong = Input {
    ..own_input,
    output: Output { ..own_input.output, datum: InlineDatum(V1(tip)) },
  }
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 1),
    Transaction { ..tx, inputs: [wrong] },
  )
}

test t116_r3_reject_active_role_with_armed_datum() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = r3_active_tx()
  expect [own_input] = tx.inputs
  let wrong = Input {
    ..own_input,
    output: Output {
      ..own_input.output,
      datum: InlineDatum(r2_armed_datum(tip, r2_hunter, r2_deadline)),
    },
  }
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    Transaction { ..tx, inputs: [wrong] },
  )
}

test t116_r3_reject_live_ee_binding_mutation() fail {
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    off_i: enf_vec.fork_witnessed_convict_wire.off_s,
  }
  run_r3(r3_convict_redeemer(evidence, r3_convictor, 0, 0), r3_active_tx())
}

test t116_r3_reject_live_no_conflict_axis() fail {
  let tip = enf_vec.fork_witnessed_honest_tip
  let evidence = enf_vec.fork_witnessed_honest_wire
  run_r3(
    r3_convict_redeemer(evidence, r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      evidence,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_live_insufficient_witness_receipts() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    wit_sigs: [],
  }
  run_r3(
    r3_convict_redeemer(evidence, r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      evidence,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_duplicate_receipt_does_not_fake_distinct_witnesses() fail {
  expect [receipt] = enf_vec.fork_witnessed_convict_wire.wit_sigs
  let tip = CheckpointDatumV1 { ..enf_vec.fork_witnessed_convict_tip, toad: 2 }
  let evidence = EnforcementEvidence {
    ..enf_vec.fork_witnessed_convict_wire,
    wit_sigs: [receipt, receipt],
  }
  run_r3(
    r3_convict_redeemer(evidence, r3_convictor, 0, 0),
    r3_active_tx_with(
      tip,
      evidence,
      r3_convictor,
      from_lovelace(d_reg + r2_freeze_bond),
      NoDatum,
      r3_terminal_value(tip),
    ),
  )
}

test t116_r3_reject_own_policy_mint() fail {
  let tx = r3_active_tx()
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    Transaction { ..tx, mint: from_asset(policy, #"ee", 1) },
  )
}

test t116_r3_reject_own_policy_burn() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let tx = r3_active_tx()
  run_r3(
    r3_honest_redeemer(r3_convictor, 0, 0),
    Transaction {
      ..tx,
      mint: from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    },
  )
}

test t116_r3_reject_convict_from_terminal_tombstone() fail {
  run_r3(r3_honest_redeemer(r3_convictor, 0, 0), terminal_tombstone_tx())
}

// ---------------------------------------------------------------------
// #254 S254-E — bounty-entitlement controls (T254-107), RED first.
//
// The defect under proof: at the pre-slice base `validate_arm` accepts a
// caller-supplied `hunter_pkh` and `validate_convict_*` a caller-supplied
// `convictor_pkh`, gated by nothing but a 28-byte width check. Neither arm
// requires a signature, let alone entitlement. An observer of a valid
// Freeze/Convict transaction can therefore rebuild it naming itself and
// take the bounty.
//
// The wire and commitment shapes below are TEST-SIDE mirrors, exactly as
// `Slice4SpendRedeemer` / `R2SpendRedeemer` / `R3SpendRedeemer` above: they
// keep the RED diff test-only while driving the REAL handler's `Data`
// decoder. Their field order and constructor indices mirror the frozen #271
// component byte-for-byte, so a locally built commitment hashes to exactly
// the value the adopted component computes. Nothing here copies a component
// blob; adoption is a separate, ratified step.
//
// Row shapes:
//   * positive rows drive the TARGET wire and must ACCEPT. At base the live
//     `SpendRedeemer` cannot decode that wire, so they fail for the intended
//     missing behavior. These are the load-bearing REDs.
//   * negative rows assert the substitution/scope/age/race attacks REJECT.
//   * `s254_e_signer_only_mutant_accepts_substitution` is the calibration
//     control: it REQUIRES a signer-only design to accept the attack, which
//     is what stops every negative row from being satisfiable by adding a
//     signature check instead of an entitlement check.
// ---------------------------------------------------------------------

const s254e_commit_policy: PolicyId =
  #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

const s254e_commit_domain: ByteArray = "cardano-keri/bounty-commitment"

const s254e_commit_schema: Int = 1

const s254e_commit_min_age: Int = 1

const s254e_commit_deposit: Int = 5_000_000

/// An EXPLICIT applied lifetime for these fixtures, threaded through every
/// scope construction below rather than published as a protocol default.
///
/// The component deliberately publishes no lifetime default and pins no exact
/// value: the magnitude is a deployment choice, not a security invariant. The
/// superseded 10,000-slot default is never recreated here, not even test-side.
/// The only property these fixtures need is that the applied value is finite,
/// explicit, and at or above the mandated one-slot age, so the window contains
/// a reachable mature reveal slot.
const s254e_applied_test_lifetime: Int = 4_321

/// The attacker: a well-formed 28-byte key hash that never opened a
/// commitment for this checkpoint, action or evidence.
const s254e_attacker: ByteArray =
  #"a77ac6e7a77ac6e7a77ac6e7a77ac6e7a77ac6e7a77ac6e7a77ac6e7"

const s254e_nonce: ByteArray =
  #"6e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e6365000f"

const s254e_other_nonce: ByteArray =
  #"6e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e6365ffff"

const s254e_seed_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 77 }

const s254e_commitment_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 78 }

const s254e_losing_commitment_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 79 }

/// A well-formed reference to a commitment the transaction does not consume.
/// Naming it produces a verdict from the entitlement leg rather than a decoder
/// rejection.
const s254e_absent_commitment_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 80 }

/// A foreign script that is NOT the release commitment family. Anything parked
/// there is counterfeit however well-formed it looks.
const s254e_foreign_commit_policy: PolicyId =
  #"f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0"

/// Test-side mirror of the frozen `BountyAction`.
type S254EAction {
  S254EFreezeEntitlement
  S254EConvictEntitlement
}

/// Test-side mirror of the frozen `BountyScope`.
type S254EScope {
  domain: ByteArray,
  schema: Int,
  network: Int,
  checkpoint_policy: PolicyId,
  checkpoint_ref: OutputReference,
  action: S254EAction,
  marker: ByteArray,
  commit_upper: Int,
  eligible_after: Int,
  expires_at: Int,
}

/// Test-side mirror of the frozen `BountyCommitmentPreimage`.
type S254EPreimage {
  scope: S254EScope,
  evidence_digest: ByteArray,
  payee_pkh: ByteArray,
  nonce: ByteArray,
}

/// Test-side mirror of the frozen `BountyCommitment`.
type S254ECommitment {
  S254ECommitmentV1 {
    scope: S254EScope,
    payee_pkh: ByteArray,
    hash: ByteArray,
    marker: ByteArray,
  }
}

/// Test-side mirror of the frozen `BountyRevealV1`.
type S254EReveal {
  commitment_ref: OutputReference,
  nonce: ByteArray,
  refund_index: Int,
}

/// The S254-E target spend wire. Constructor order mirrors the live
/// `SpendRedeemer` exactly; only Freeze and Convict change shape, each
/// gaining the reveal that names the commitment establishing entitlement.
type S254ESpendRedeemer {
  S254EAdvance { evidence: AdvanceEvidence }
  S254EFreeze {
    evidence: EnforcementEvidence,
    hunter_pkh: ByteArray,
    reveal: S254EReveal,
  }
  S254EClaimFreeze { hunter_output_index: Int }
  S254EConvict {
    evidence: EnforcementEvidence,
    convictor_pkh: ByteArray,
    convictor_output_index: Int,
    hunter_output_index: Int,
    reveal: S254EReveal,
  }
  S254EClose
}

/// The canonical digest of the COMPLETE actual enforcement payload. Any
/// field mutation changes it, which is what makes a caller-supplied digest
/// insufficient to establish entitlement.
fn s254e_evidence_digest(evidence: EnforcementEvidence) -> ByteArray {
  blake2b_256(cbor.serialise(evidence))
}

fn s254e_marker(seed_ref: OutputReference) -> ByteArray {
  blake2b_256(cbor.serialise(seed_ref))
}

/// Build a scope from an EXPLICIT applied lifetime. The lifetime is a
/// parameter, never an ambient default: `eligible_after` and `expires_at` are
/// both derived from the raw opening endpoint and the applied magnitudes.
fn s254e_scope_with_lifetime(
  checkpoint_ref: OutputReference,
  action: S254EAction,
  marker: ByteArray,
  commit_upper: Int,
  applied_lifetime: Int,
) -> S254EScope {
  S254EScope {
    domain: s254e_commit_domain,
    schema: s254e_commit_schema,
    network: network_id,
    checkpoint_policy: policy,
    checkpoint_ref,
    action,
    marker,
    commit_upper,
    eligible_after: commit_upper + s254e_commit_min_age,
    expires_at: commit_upper + applied_lifetime,
  }
}

fn s254e_scope(
  checkpoint_ref: OutputReference,
  action: S254EAction,
  marker: ByteArray,
  commit_upper: Int,
) -> S254EScope {
  s254e_scope_with_lifetime(
    checkpoint_ref,
    action,
    marker,
    commit_upper,
    s254e_applied_test_lifetime,
  )
}

fn s254e_commitment(
  scope: S254EScope,
  evidence_digest: ByteArray,
  payee_pkh: ByteArray,
  nonce: ByteArray,
) -> S254ECommitment {
  let preimage = S254EPreimage { scope, evidence_digest, payee_pkh, nonce }
  S254ECommitmentV1 {
    scope,
    payee_pkh,
    hash: blake2b_256(cbor.serialise(preimage)),
    marker: scope.marker,
  }
}

/// An authentic commitment UTxO: script credential, inline commitment datum,
/// and exactly its own seed-derived marker plus the applied deposit.
fn s254e_commitment_input(
  ref: OutputReference,
  commitment: S254ECommitment,
) -> Input {
  s254e_commitment_input_at(s254e_commit_policy, ref, commitment)
}

/// The same UTxO shape at an arbitrary script. The counterfeit control uses it
/// to park a structurally perfect commitment somewhere it does not belong.
fn s254e_commitment_input_at(
  script: PolicyId,
  ref: OutputReference,
  commitment: S254ECommitment,
) -> Input {
  let S254ECommitmentV1 { marker, .. } = commitment
  let datum: Data = commitment
  input_at(
    ref,
    Output {
      address: from_script(script),
      value: from_lovelace(s254e_commit_deposit)
        |> merge(from_asset(script, marker, 1)),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  )
}

/// The marker burn that makes a reveal single-use.
fn s254e_marker_burn(marker: ByteArray) -> Value {
  from_asset(s254e_commit_policy, marker, -1)
}

fn s254e_marker_burn_at(script: PolicyId, marker: ByteArray) -> Value {
  from_asset(script, marker, -1)
}

fn s254e_refund_output(payee_pkh: ByteArray) -> Output {
  r2_hunter_output(payee_pkh, from_lovelace(s254e_commit_deposit), NoDatum)
}

fn s254e_reveal(
  ref: OutputReference,
  nonce: ByteArray,
  index: Int,
) -> S254EReveal {
  S254EReveal { commitment_ref: ref, nonce, refund_index: index }
}

/// The LIVE reveal type, for rows that call the shared rule directly rather
/// than through the applied program's redeemer wire.
fn s254e_live_reveal(
  ref: OutputReference,
  nonce: ByteArray,
  index: Int,
) -> BountyRevealV1 {
  BountyRevealV1 { commitment_ref: ref, nonce, refund_index: index }
}

fn run_s254e(
  redeemer: S254ESpendRedeemer,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  run_s254e_with_d_reg(d_reg, redeemer, own_ref, tx)
}

fn run_s254e_with_d_reg(
  d_reg_parameter: Int,
  redeemer: S254ESpendRedeemer,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let redeemer_data: Data = redeemer
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg_parameter,
    r2_freeze_bond,
    r2_freeze_window,
    applied_commitment,
    None,
    redeemer_data,
    own_ref,
    tx,
  )
}

/// An honest ENTITLED conviction: the transaction under test plus the matured
/// authentic reservation the named convictor opened over this checkpoint, the
/// Convict action, and the digest of this actual evidence.
fn run_s254e_convict(
  convictor_pkh: ByteArray,
  convictor_index: Int,
  hunter_index: Int,
  tx: Transaction,
) -> Bool {
  run_s254e_convict_with_d_reg(
    d_reg,
    convictor_pkh,
    convictor_index,
    hunter_index,
    tx,
  )
}

fn run_s254e_convict_with_d_reg(
  d_reg_parameter: Int,
  convictor_pkh: ByteArray,
  convictor_index: Int,
  hunter_index: Int,
  tx: Transaction,
) -> Bool {
  run_s254e_with_d_reg(
    d_reg_parameter,
    s254e_convict_redeemer(convictor_pkh, convictor_index, hunter_index),
    convict_own_ref,
    s254e_with_convict_commitment(
      tx,
      s254e_convict_commitment(convict_own_ref, convictor_pkh),
    ),
  )
}

// --- Freeze entitlement -------------------------------------------------

/// The commitment an honest hunter opened for THIS checkpoint, THIS action
/// and THIS actual evidence, matured by exactly one slot.
fn s254e_freeze_commitment(payee_pkh: ByteArray) -> S254ECommitment {
  let scope = s254e_scope(
    freeze_own_ref,
    S254EFreezeEntitlement,
    s254e_marker(s254e_seed_ref),
    0,
  )
  s254e_commitment(
    scope,
    s254e_evidence_digest(enf_vec.lag_freeze_wire),
    payee_pkh,
    s254e_nonce,
  )
}

/// An entitled arm: the honest ARMED transition plus the matured commitment
/// input, its marker burn, and the exact deposit refund to the committed
/// payee. `extra_signatories` is deliberately EMPTY — entitlement comes from
/// the aged commitment, never from a fresh signature.
fn s254e_arm_tx_with(
  commitment: S254ECommitment,
  commitment_ref: OutputReference,
  hunter_pkh: ByteArray,
  evidence_tip: CheckpointDatumV1,
) -> Transaction {
  let S254ECommitmentV1 { marker, payee_pkh, .. } = commitment
  let base = r2_arm_tx_with(
    evidence_tip,
    r2_surplus_value(evidence_tip),
    hunter_pkh,
    r2_deadline,
    interval.between(s254e_commit_min_age, r2_arm_upper),
  )
  Transaction {
    ..base,
    inputs: list.concat(
      base.inputs,
      [s254e_commitment_input(commitment_ref, commitment)],
    ),
    outputs: list.concat(base.outputs, [s254e_refund_output(payee_pkh)]),
    mint: s254e_marker_burn(marker),
  }
}

/// Make an EXISTING arm transaction entitled without disturbing what the row
/// under test is about.
///
/// The validity range keeps its exact upper endpoint — that is what anchors the
/// stored deadline, and what the raw-exclusive row exists to pin — while the
/// lower endpoint moves up to the maturity slot, because a commitment revealed
/// in the slot it was opened in is not aged. Everything else the row set up
/// (values, extra inputs and outputs, the ARMED successor) is carried through
/// untouched.
fn s254e_entitle_arm(base: Transaction, hunter_pkh: ByteArray) -> Transaction {
  let commitment = s254e_freeze_commitment(hunter_pkh)
  let S254ECommitmentV1 { marker, payee_pkh, .. } = commitment
  Transaction {
    ..base,
    validity_range: interval.Interval {
      lower_bound: interval.IntervalBound {
        bound_type: interval.Finite(s254e_commit_min_age),
        is_inclusive: True,
      },
      upper_bound: base.validity_range.upper_bound,
    },
    inputs: list.concat(
      base.inputs,
      [s254e_commitment_input(s254e_commitment_ref, commitment)],
    ),
    outputs: list.concat(base.outputs, [s254e_refund_output(payee_pkh)]),
    mint: base.mint |> merge(s254e_marker_burn(marker)),
  }
}

/// An honest ENTITLED arm over an arbitrary arming transaction.
fn run_s254e_arm(base: Transaction) -> Bool {
  run_s254e(
    s254e_entitled_arm_redeemer(r2_hunter),
    freeze_own_ref,
    s254e_entitle_arm(base, r2_hunter),
  )
}

fn s254e_entitled_arm_tx() -> Transaction {
  s254e_arm_tx_with(
    s254e_freeze_commitment(r2_hunter),
    s254e_commitment_ref,
    r2_hunter,
    enf_vec.lag_freeze_tip,
  )
}

fn s254e_arm_redeemer(
  hunter_pkh: ByteArray,
  reveal: S254EReveal,
) -> S254ESpendRedeemer {
  S254EFreeze { evidence: enf_vec.lag_freeze_wire, hunter_pkh, reveal }
}

fn s254e_entitled_arm_redeemer(hunter_pkh: ByteArray) -> S254ESpendRedeemer {
  s254e_arm_redeemer(
    hunter_pkh,
    s254e_reveal(s254e_commitment_ref, s254e_nonce, 2),
  )
}

/// LOAD-BEARING RED. The entitled settlement must be accepted: a matured,
/// authentic commitment naming this checkpoint, this action, this actual
/// evidence and this payee settles and refunds the deposit. At base the live
/// redeemer cannot carry a reveal at all, so this fails for exactly the
/// missing behavior.
test s254_e_freeze_entitled_settlement_accepts() {
  run_s254e(
    s254e_entitled_arm_redeemer(r2_hunter),
    freeze_own_ref,
    s254e_entitled_arm_tx(),
  )
}

/// INV-271-ENTITLEMENT. A Freeze carrying no commitment at all must reject.
/// At base an unaccompanied arm is accepted, which is the defect.
/// INV-271-ENTITLEMENT. A Freeze that names no reservation the transaction
/// actually consumes must reject.
///
/// It is driven on the TARGET wire with a well-formed reveal whose
/// `commitment_ref` is simply not among the inputs, so `own_commitment` finds
/// nothing and the rule refuses. That is a verdict from the entitlement leg
/// itself — not a decoder bounce, which is what a base-wire redeemer would
/// produce now that the wire carries a reveal, and which would prove only that
/// two record shapes differ.
test s254_e_freeze_without_commitment_rejects() fail {
  let tip = enf_vec.lag_freeze_tip
  run_s254e(
    s254e_arm_redeemer(
      r2_hunter,
      s254e_reveal(s254e_absent_commitment_ref, s254e_nonce, 2),
    ),
    freeze_own_ref,
    s254e_entitled_arm_tx(),
  )
}

/// INV-271-ENTITLEMENT. The substitution attack in its strongest form.
///
/// The attacker observes the honest hunter's Freeze, rebuilds the whole arm
/// naming ITSELF in both the redeemer and the ARMED datum, and points the
/// reveal at the honest hunter's real, matured, authentic commitment. Nothing
/// is internally inconsistent: the evidence is genuine, the commitment is
/// genuine, the marker burns, the deposit refunds. The single fact that stops
/// it is that the reservation names a different payee — which is exactly the
/// leg a consent check cannot supply, and why
/// `s254_e_signer_only_mutant_accepts_substitution` exists beside it.
test s254_e_freeze_substituted_payee_rejects() fail {
  let tip = enf_vec.lag_freeze_tip
  run_s254e(
    s254e_entitled_arm_redeemer(s254e_attacker),
    freeze_own_ref,
    s254e_arm_tx_with(
      s254e_freeze_commitment(r2_hunter),
      s254e_commitment_ref,
      s254e_attacker,
      tip,
    ),
  )
}

/// INV-271-SCOPE. The commitment was opened over the digest of actual
/// evidence E; the transaction supplies a mutated E'. Entitlement is derived
/// from the COMPLETE actual payload, so the match must break.
test s254_e_freeze_actual_evidence_digest_rejects_substitution() fail {
  let tip = enf_vec.lag_freeze_tip
  let mutated = EnforcementEvidence {
    ..enf_vec.lag_freeze_wire,
    native_sn: enf_vec.lag_freeze_wire.native_sn + 1,
  }
  let scope = s254e_scope(
    freeze_own_ref,
    S254EFreezeEntitlement,
    s254e_marker(s254e_seed_ref),
    0,
  )
  let commitment = s254e_commitment(
    scope,
    s254e_evidence_digest(mutated),
    r2_hunter,
    s254e_nonce,
  )
  run_s254e(
    s254e_entitled_arm_redeemer(r2_hunter),
    freeze_own_ref,
    s254e_arm_tx_with(commitment, s254e_commitment_ref, r2_hunter, tip),
  )
}

/// INV-271-AGE. A commitment opened in the very slot it is revealed in is not
/// mature: `eligible_after` is `commit_upper + 1`.
test s254_e_same_slot_commit_reveal_rejects() fail {
  let tip = enf_vec.lag_freeze_tip
  let scope = s254e_scope(
    freeze_own_ref,
    S254EFreezeEntitlement,
    s254e_marker(s254e_seed_ref),
    r2_arm_upper,
  )
  let commitment = s254e_commitment(
    scope,
    s254e_evidence_digest(enf_vec.lag_freeze_wire),
    r2_hunter,
    s254e_nonce,
  )
  run_s254e(
    s254e_entitled_arm_redeemer(r2_hunter),
    freeze_own_ref,
    s254e_arm_tx_with(commitment, s254e_commitment_ref, r2_hunter, tip),
  )
}

/// INV-271-SCOPE cross product: checkpoint outref, policy, network, action,
/// actual evidence digest, marker, payee and nonce are mutated INDEPENDENTLY,
/// each starting from the otherwise-entitled settlement. Every one must break
/// the hash match on its own.
test s254_e_scope_cross_product_rejects() fail {
  let tip = enf_vec.lag_freeze_tip
  let marker = s254e_marker(s254e_seed_ref)
  let digest = s254e_evidence_digest(enf_vec.lag_freeze_wire)
  let honest = s254e_scope(freeze_own_ref, S254EFreezeEntitlement, marker, 0)
  let mutants: List<S254ECommitment> = [
    s254e_commitment(
      S254EScope { ..honest, checkpoint_ref: convict_own_ref },
      digest,
      r2_hunter,
      s254e_nonce,
    ),
    s254e_commitment(
      S254EScope { ..honest, checkpoint_policy: hp_policy },
      digest,
      r2_hunter,
      s254e_nonce,
    ),
    s254e_commitment(
      S254EScope { ..honest, network: network_id + 1 },
      digest,
      r2_hunter,
      s254e_nonce,
    ),
    s254e_commitment(
      S254EScope { ..honest, action: S254EConvictEntitlement },
      digest,
      r2_hunter,
      s254e_nonce,
    ),
    s254e_commitment(
      S254EScope { ..honest, marker: s254e_marker(s254e_losing_commitment_ref) },
      digest,
      r2_hunter,
      s254e_nonce,
    ),
    s254e_commitment(honest, digest, s254e_attacker, s254e_nonce),
    s254e_commitment(honest, digest, r2_hunter, s254e_other_nonce),
  ]
  // Every independent mutation must be rejected; a single acceptance makes
  // the whole row fail.
  list.any(
    mutants,
    fn(commitment) {
      run_s254e(
        s254e_entitled_arm_redeemer(r2_hunter),
        freeze_own_ref,
        s254e_arm_tx_with(commitment, s254e_commitment_ref, r2_hunter, tip),
      )
    },
  )
}

/// INV-271-RACE. Two commitments race for one checkpoint. Settlement is the
/// transaction ordering of the unique checkpoint spend and nothing else: the
/// loser cannot redirect the winner's value, so a reveal naming the LOSING
/// commitment while paying the winner's payee must reject.
test s254_e_first_valid_reveal_wins_checkpoint_spend() fail {
  let tip = enf_vec.lag_freeze_tip
  let winner = s254e_freeze_commitment(r2_hunter)
  let loser_scope = s254e_scope(
    freeze_own_ref,
    S254EFreezeEntitlement,
    s254e_marker(s254e_losing_commitment_ref),
    0,
  )
  let loser = s254e_commitment(
    loser_scope,
    s254e_evidence_digest(enf_vec.lag_freeze_wire),
    s254e_attacker,
    s254e_other_nonce,
  )
  let S254ECommitmentV1 { marker: winner_marker, .. } = winner
  let base = s254e_arm_tx_with(winner, s254e_commitment_ref, r2_hunter, tip)
  // The losing commitment is also present, but the reveal names it while the
  // ARMED datum and refund still name the winner's payee.
  run_s254e(
    s254e_arm_redeemer(
      r2_hunter,
      s254e_reveal(s254e_losing_commitment_ref, s254e_other_nonce, 2),
    ),
    freeze_own_ref,
    Transaction {
      ..base,
      inputs: list.concat(
        base.inputs,
        [s254e_commitment_input(s254e_losing_commitment_ref, loser)],
      ),
      mint: s254e_marker_burn(winner_marker),
    },
  )
}

/// INV-271-VALUE. The commitment deposit is refunded exactly once to the
/// committed payee and the checkpoint reserve is untouched by it. Draining the
/// refund to the attacker must reject.
/// INV-271-VALUE, at the layer the CHECKPOINT actually owns.
///
/// The reservation must be retired exactly once by the settling transaction:
/// burning nothing would leave a spent commitment alive to settle again, and
/// burning two would consume value that was never reserved. Both must reject.
///
/// Scope note, stated rather than implied: the destination of the commitment
/// DEPOSIT REFUND is not a checkpoint rule. It is enforced by the commitment
/// program's own `validate_commitment_reveal`, which pins
/// `exact_payout(tx, refund_index, payee_pkh, deposit)` against the committed
/// payee. That leg is covered by the adopted component's own suite, which ships
/// byte-identically. Asserting it here would have tested the wrong program — the
/// checkpoint accepts a misdirected refund because refunds are none of its
/// business, and an earlier version of this row failed for exactly that reason.
test s254_e_commitment_refund_and_bounties_conserve_value() fail {
  let tip = enf_vec.lag_freeze_tip
  let commitment = s254e_freeze_commitment(r2_hunter)
  let S254ECommitmentV1 { marker, .. } = commitment
  let honest = s254e_arm_tx_with(
    commitment,
    s254e_commitment_ref,
    r2_hunter,
    tip,
  )
  list.any(
    [
      // settle while leaving the reservation unburned
      Transaction { ..honest, mint: zero },
      // retire more than was ever reserved
      Transaction {
        ..honest,
        mint: from_asset(s254e_commit_policy, marker, -2),
      },
      // redirect the hunter bounty: the ARMED successor names the attacker
      // while the reveal still proves entitlement for the committed hunter
      s254e_arm_tx_with(commitment, s254e_commitment_ref, s254e_attacker, tip),
    ],
    fn(tx) {
      run_s254e(s254e_entitled_arm_redeemer(r2_hunter), freeze_own_ref, tx)
    },
  )
}

// --- Consent without a fresh-signature veto -----------------------------

/// INV-271-CONSENT. Claim pays the hunter recorded in the ARMED datum with an
/// EMPTY signatory set: the hunter's consent was given when the commitment was
/// opened, and no party may acquire a veto by withholding a fresh signature.
/// This passes at base and must keep passing.
test s254_e_claim_uses_stored_hunter_without_fresh_signature() {
  let tx = r2_claim_tx(enf_vec.lag_freeze_tip, r2_deadline)
  and {
    tx.extra_signatories == [],
    run_r2(r2_claim_redeemer(0), tx),
  }
}

/// INV-271-CONSENT. The ARMED hunter share on conviction is likewise derived
/// from stored consent, with no fresh hunter signature.
test s254_e_convict_armed_uses_stored_hunter_without_fresh_signature() {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  let tx = s254e_with_convict_commitment(
    r3_armed_tx_with(
      tip,
      evidence,
      r3_convictor,
      r2_hunter,
      from_lovelace(d_reg),
      from_lovelace(r2_freeze_bond),
      NoDatum,
      NoDatum,
      r3_terminal_value(tip),
    ),
    s254e_convict_commitment(convict_own_ref, r3_convictor),
  )
  and {
    // The CONVICTOR earned its share through a commitment; the HUNTER share is
    // paid from stored ARMED consent with no signature from anyone at all.
    tx.extra_signatories == [],
    run_s254e(s254e_convict_redeemer(r3_convictor, 0, 1), convict_own_ref, tx),
  }
}

// --- Convict entitlement across ACTIVE / ARMED / FROZEN -----------------

fn s254e_convict_commitment(
  checkpoint_ref: OutputReference,
  payee_pkh: ByteArray,
) -> S254ECommitment {
  let scope = s254e_scope(
    checkpoint_ref,
    S254EConvictEntitlement,
    s254e_marker(s254e_seed_ref),
    0,
  )
  s254e_commitment(
    scope,
    s254e_evidence_digest(enf_vec.fork_witnessed_convict_wire),
    payee_pkh,
    s254e_nonce,
  )
}

fn s254e_convict_redeemer(
  convictor_pkh: ByteArray,
  convictor_index: Int,
  hunter_index: Int,
) -> S254ESpendRedeemer {
  S254EConvict {
    evidence: enf_vec.fork_witnessed_convict_wire,
    convictor_pkh,
    convictor_output_index: convictor_index,
    hunter_output_index: hunter_index,
    reveal: s254e_reveal(s254e_commitment_ref, s254e_nonce, 3),
  }
}

fn s254e_with_convict_commitment(
  base: Transaction,
  commitment: S254ECommitment,
) -> Transaction {
  let S254ECommitmentV1 { marker, payee_pkh, .. } = commitment
  Transaction {
    ..base,
    validity_range: interval.between(s254e_commit_min_age, r2_arm_upper),
    inputs: list.concat(
      base.inputs,
      [s254e_commitment_input(s254e_commitment_ref, commitment)],
    ),
    outputs: list.concat(base.outputs, [s254e_refund_output(payee_pkh)]),
    mint: s254e_marker_burn(marker),
  }
}

/// INV-271-ENTITLEMENT over ACTIVE conviction: the attacker names itself as
/// convictor on someone else's witnessed fork, and points the reveal at the
/// honest convictor's real matured reservation. The conviction itself is
/// genuine and every other leg is satisfied; only the committed payee differs.
test s254_e_convict_active_substituted_payee_rejects() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  run_s254e(
    s254e_convict_redeemer(s254e_attacker, 0, 0),
    convict_own_ref,
    s254e_with_convict_commitment(
      r3_active_tx_with(
        tip,
        evidence,
        s254e_attacker,
        from_lovelace(d_reg + r2_freeze_bond),
        NoDatum,
        r3_terminal_value(tip),
      ),
      s254e_convict_commitment(convict_own_ref, r3_convictor),
    ),
  )
}

/// INV-271-ENTITLEMENT over ARMED conviction. The stored hunter share is
/// untouched; only the convictor position is stolen.
test s254_e_convict_armed_substituted_payee_rejects() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  run_s254e(
    s254e_convict_redeemer(s254e_attacker, 0, 1),
    convict_own_ref,
    s254e_with_convict_commitment(
      r3_armed_tx_with(
        tip,
        evidence,
        s254e_attacker,
        r2_hunter,
        from_lovelace(d_reg),
        from_lovelace(r2_freeze_bond),
        NoDatum,
        NoDatum,
        r3_terminal_value(tip),
      ),
      s254e_convict_commitment(convict_own_ref, r3_convictor),
    ),
  )
}

/// INV-271-ENTITLEMENT over FROZEN conviction.
test s254_e_convict_frozen_substituted_payee_rejects() fail {
  let tip = enf_vec.fork_witnessed_convict_tip
  let evidence = enf_vec.fork_witnessed_convict_wire
  run_s254e(
    s254e_convict_redeemer(s254e_attacker, 0, 0),
    convict_own_ref,
    s254e_with_convict_commitment(
      r3_frozen_tx_with(
        tip,
        evidence,
        s254e_attacker,
        from_lovelace(d_reg),
        NoDatum,
        r3_terminal_value(tip),
      ),
      s254e_convict_commitment(convict_own_ref, r3_convictor),
    ),
  )
}

// --- Calibration: consent is not entitlement ----------------------------

/// The superseded signer-only design, expressed exactly: the payee must sign.
fn s254e_signer_only_entitled(payee_pkh: ByteArray, tx: Transaction) -> Bool {
  list.has(tx.extra_signatories, payee_pkh)
}

/// CALIBRATION CONTROL — this must ACCEPT, now and forever.
///
/// The attacker signs as itself and names itself, so a signer-only rule is
/// fully satisfied by the substitution attack. This is what proves the other
/// rows are not satisfiable by adding a signature check: consent establishes
/// that a party agrees to be paid, never that it earned the payment. Only the
/// prior, matured, hash-committed reservation distinguishes the two.
test s254_e_signer_only_mutant_accepts_substitution() {
  let tip = enf_vec.lag_freeze_tip
  let honest = s254e_arm_tx_with(
    s254e_freeze_commitment(r2_hunter),
    s254e_commitment_ref,
    s254e_attacker,
    tip,
  )
  let attacker_signed = Transaction {
    ..honest,
    extra_signatories: [s254e_attacker],
  }
  and {
    // the signer-only rule accepts the attacker outright
    s254e_signer_only_entitled(s254e_attacker, attacker_signed),
    // and the commitment on record names a different payee entirely
    when s254e_freeze_commitment(r2_hunter) is {
      S254ECommitmentV1 { payee_pkh, .. } -> payee_pkh != s254e_attacker
    },
  }
}

// --- Counterfeit family policy ------------------------------------------

/// An arm carrying a STRUCTURALLY PERFECT commitment parked at a foreign
/// script.
///
/// Everything the settlement rule reads is right: the scope names this
/// checkpoint, this action and the digest of this actual evidence; the payee is
/// the party being paid; the reservation is already mature and unexpired; the
/// UTxO holds exactly its own seed-derived marker plus the applied deposit; the
/// marker is burned; the deposit is refunded. The one thing wrong with it is
/// where it lives — which is the whole of `INV-271-COMMITMENT-POLICY-AUTHENTICITY`.
fn s254e_counterfeit_arm_tx() -> Transaction {
  let commitment = s254e_freeze_commitment(s254e_attacker)
  let S254ECommitmentV1 { marker, payee_pkh, .. } = commitment
  let base = r2_arm_tx_with(
    enf_vec.lag_freeze_tip,
    r2_surplus_value(enf_vec.lag_freeze_tip),
    s254e_attacker,
    r2_deadline,
    interval.between(s254e_commit_min_age, r2_arm_upper),
  )
  Transaction {
    ..base,
    inputs: list.concat(
      base.inputs,
      [
        s254e_commitment_input_at(
          s254e_foreign_commit_policy,
          s254e_commitment_ref,
          commitment,
        ),
      ],
    ),
    outputs: list.concat(base.outputs, [s254e_refund_output(payee_pkh)]),
    mint: s254e_marker_burn_at(s254e_foreign_commit_policy, marker),
  }
}

/// The same release magnitudes, pinned to the FOREIGN script instead. This is
/// the un-pinned mutant expressed exactly: if the family policy were not
/// consulted, this field could not change any verdict.
const s254e_foreign_family: CommitmentFamily =
  CommitmentFamily {
    policy: s254e_foreign_commit_policy,
    parameters: CommitmentParameters {
      network: network_id,
      commit_min_age: 1,
      commitment_lifetime: s254e_applied_test_lifetime,
      commit_deposit: s254e_commit_deposit,
    },
  }

/// INV-271-COMMITMENT-POLICY-AUTHENTICITY, proved BOTH ways in one row.
///
/// The first conjunct is the calibration: applied against a family pinned to
/// the script the counterfeit actually sits at, the shipped shared rule ACCEPTS
/// it. So no other leg objects — not the scope, not the payee, not the age, not
/// the expiry, not the marker burn — and the fixture is not quietly broken.
///
/// The second conjunct is the property: the identical transaction, judged by
/// the identical function, is REFUSED once the applied family is the real one.
/// Nothing changes between the two calls except the pinned policy, so the
/// verdict turns on the pin and on nothing else. Neither call is a decoder,
/// setup, missing-input or value-shape rejection: both reach the rule and
/// return a Bool.
test s254_e_counterfeit_commitment_policy_rejects() {
  let tx = s254e_counterfeit_arm_tx()
  let reveal = s254e_live_reveal(s254e_commitment_ref, s254e_nonce, 2)
  and {
    validate_freeze_entitlement(
      s254e_foreign_family,
      enf_vec.lag_freeze_wire,
      s254e_attacker,
      reveal,
      freeze_own_ref,
      tx,
    ),
    !validate_freeze_entitlement(
      applied_commitment,
      enf_vec.lag_freeze_wire,
      s254e_attacker,
      reveal,
      freeze_own_ref,
      tx,
    ),
  }
}

/// The same counterfeit, refused by the APPLIED PROGRAM rather than by the
/// shared function in isolation. This is what ties the row above to the
/// bytecode that actually ships.
test s254_e_counterfeit_commitment_policy_rejected_by_applied_checkpoint() fail {
  run_s254e(
    s254e_entitled_arm_redeemer(s254e_attacker),
    freeze_own_ref,
    s254e_counterfeit_arm_tx(),
  )
}

// --- Both enforcement actions under one shared rule ---------------------

/// INV-271-PARITY, split side. Freeze and Convict entitlement are ONE rule
/// applied to two actions, so the entitled settlement must be admitted on both
/// of the split family's enforcement paths under the same shared predicate.
///
/// The cross-FAMILY half of INV-271-PARITY — this validator and the combined
/// register reaching the same verdict on ONE transaction — lives in
/// `s254_e_split_and_combined_mirror_agree` in `checkpoint_register_tests.ak`,
/// which is the only module where both families are in scope.
test s254_e_freeze_and_convict_share_one_entitlement_rule() {
  let convict_tip = enf_vec.fork_witnessed_convict_tip
  let convict_evidence = enf_vec.fork_witnessed_convict_wire
  let convict_base = r3_active_tx_with(
    convict_tip,
    convict_evidence,
    r3_convictor,
    from_lovelace(d_reg + r2_freeze_bond),
    NoDatum,
    r3_terminal_value(convict_tip),
  )
  and {
    run_s254e(
      s254e_entitled_arm_redeemer(r2_hunter),
      freeze_own_ref,
      s254e_entitled_arm_tx(),
    ),
    run_s254e(
      s254e_convict_redeemer(r3_convictor, 0, 0),
      convict_own_ref,
      s254e_with_convict_commitment(
        convict_base,
        s254e_convict_commitment(convict_own_ref, r3_convictor),
      ),
    ),
  }
}

/// The applied commitment FAMILY these fixtures deploy under.
///
/// `policy` is release identity: the commitment program whose reservations this
/// checkpoint honours, and the pin that makes a commitment-shaped datum at any
/// other script counterfeit (`INV-271-COMMITMENT-POLICY-AUTHENTICITY`). The
/// nested magnitudes are explicit, finite, at or above the mandated one-slot
/// age and the 5 ADA deposit floor — and deliberately not a published protocol
/// default.
const applied_commitment: CommitmentFamily =
  CommitmentFamily {
    policy: s254e_commit_policy,
    parameters: CommitmentParameters {
      network: network_id,
      commit_min_age: 1,
      commitment_lifetime: s254e_applied_test_lifetime,
      commit_deposit: s254e_commit_deposit,
    },
  }
