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
  InlineDatum, Input, NoDatum, Output, OutputReference, Spend, Transaction,
  placeholder,
}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/advance_vectors as adv_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, TombstoneV1}
use cardano_keri/checkpoint/enforcement_vectors as enf_vec
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/role.{Active, Frozen, Registry, Tombstone}
use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}
use cardano_keri/checkpoint/unicity.{RegistryDatumV1}
use cardano_keri/checkpoint/unicity_vectors as uni
use checkpoint.{Advance, Close, RecordRegistration, Register}

/// Test-side encoding of the ratified Slice-4 spend redeemer. Keeping this
/// local makes the RED diff test-only while still exercising the real handler's
/// `Data` decoder; GREEN changes the live `SpendRedeemer` to this exact shape.
type Slice4SpendRedeemer {
  Slice4Advance { evidence: AdvanceEvidence }
  Slice4Freeze { evidence: EnforcementEvidence }
  Slice4Convict
  Slice4RecordRegistration
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
  Slice5RecordRegistration
  Slice5Close
}

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

const registry_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 9 }

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

fn registry_value() -> Value {
  from_lovelace(min_ada)
    |> merge(from_asset(policy, uni.registry_thread_name, 1))
}

fn registry_output(root: ByteArray) -> Output {
  Output {
    address: role.address(policy, Registry),
    value: registry_value(),
    datum: InlineDatum(RegistryDatumV1 { root }),
    reference_script: None,
  }
}

fn gated_register_tx(
  old_root: ByteArray,
  new_root: ByteArray,
  tx: Transaction,
) -> Transaction {
  let registry_input = input_at(registry_ref, registry_output(old_root))
  let registry_redeemer: Data = RecordRegistration
  Transaction {
    ..tx,
    inputs: list.concat(tx.inputs, [registry_input]),
    outputs: list.concat(tx.outputs, [registry_output(new_root)]),
    redeemers: [Pair(Spend(registry_ref), registry_redeemer)],
  }
}

fn registration_key(e: RegistrationEvidence) -> ByteArray {
  if e == vec.pos_7key_evidence {
    deriveAidAssetName(vec.pos_7key_datum.cesr_aid)
  } else if e == vec.pos_witnessed_evidence {
    deriveAidAssetName(vec.pos_witnessed_datum.cesr_aid)
  } else if e == vec.pos_weighted_evidence {
    deriveAidAssetName(vec.pos_weighted_datum.cesr_aid)
  } else {
    deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  }
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
  let key = registration_key(e)
  let old_root = unicity.empty_root()
  let new_root = unicity.insert_registered(old_root, key, [])
  run_register_at(e, old_root, new_root, tx)
}

fn run_register_at(
  e: RegistrationEvidence,
  old_root: ByteArray,
  new_root: ByteArray,
  tx: Transaction,
) -> Bool {
  checkpoint.checkpoint.mint(
    0,
    hp_policy,
    network_id,
    d_reg,
    uni.registry_seed,
    Register { evidence: e, registry_ref, absence_proof: [] },
    policy,
    gated_register_tx(old_root, new_root, tx),
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

/// U5: replaying the same AID registration from the same implicit empty
/// registry state must reject. This is the validator-level regression that
/// exposes the pre-#116 gap: the current Register handler has no registry
/// input or absence transition, so this duplicate still succeeds.
test reject_u5_duplicate_registration_without_registry_gate() fail {
  let key = deriveAidAssetName(vec.pos_2key_datum.cesr_aid)
  let present_root = unicity.insert_registered(unicity.empty_root(), key, [])
  run_register_at(
    vec.pos_2key_evidence,
    present_root,
    present_root,
    register_tx(
      vec.pos_2key_datum,
      vec.pos_2key_lovelace,
      vec.pos_2key_evidence,
    ),
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
    uni.registry_seed,
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
const advance_deposit: Int = 7_000_000

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
    uni.registry_seed,
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

test accept_advance_wit_2key() {
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

test accept_advance_wit_7key() {
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

test accept_advance_keep() {
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

test accept_advance_downgrade() {
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
test accept_advance_extra_input() {
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
test t116_s4_accept_freeze_lag_real_wire() {
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_tx(enf_vec.lag_freeze_tip),
  )
}

test t116_s4_accept_advance_thaw_from_frozen() {
  let spent = adv_vec.pos_adv_wit_2key_spent
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    advance_tx_from(
      spent,
      old_adv_wit_2key,
      adv_vec.pos_adv_wit_2key_created,
      role.address(policy, Frozen),
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

test t116_s4_reject_freeze_from_registry_role() fail {
  let tip = enf_vec.lag_freeze_tip
  let value = freeze_value(tip)
  run_freeze(
    enf_vec.lag_freeze_wire,
    freeze_own_ref,
    freeze_context(
      tip,
      role.address(policy, Registry),
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
      RegistryDatumV1 { root: unicity.empty_root() },
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

test t116_s4_reject_advance_from_registry() fail {
  let spent = adv_vec.pos_adv_wit_2key_spent
  run_advance(
    Advance { evidence: adv_vec.pos_adv_wit_2key_evidence },
    advance_own_ref(spent),
    advance_tx_from(
      spent,
      old_adv_wit_2key,
      adv_vec.pos_adv_wit_2key_created,
      role.address(policy, Registry),
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
// T116-S5 RED — witnessed Convict, bounty release, exact TombstoneV1,
// pre-dispatch terminality, and post-conviction mint-once unicity. Every
// boundary test drives the real five-argument applied checkpoint handler.
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
test t116_s5_accept_convict_from_active_real_witnessed_wire() {
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

test t116_s5_accept_convict_from_frozen_real_witnessed_wire() {
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
      RegistryDatumV1 { root: unicity.empty_root() },
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

test t116_s5_f11_reject_record_registration_from_terminal_tombstone() fail {
  let redeemer: Data = Slice5RecordRegistration
  run_advance(redeemer, convict_own_ref, terminal_tombstone_tx())
}

test t116_s5_f11_reject_close_from_terminal_tombstone() fail {
  let redeemer: Data = Slice5Close
  run_advance(redeemer, convict_own_ref, terminal_tombstone_tx())
}

// U5 post-conviction re-registration: the transaction includes the same-AID
// tombstone and invokes the live mint handler, but the permanent registry root
// already contains the AID key, so the re-mint cannot validate.
test t116_s5_reject_u5_post_conviction_same_aid_register() fail {
  let d = vec.pos_2key_datum
  let key = deriveAidAssetName(d.cesr_aid)
  let present_root = unicity.insert_registered(unicity.empty_root(), key, [])
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
  let tx = register_tx(d, vec.pos_2key_lovelace, vec.pos_2key_evidence)
  run_register_at(
    vec.pos_2key_evidence,
    present_root,
    present_root,
    Transaction { ..tx, inputs: list.concat(tx.inputs, [tombstone]) },
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
