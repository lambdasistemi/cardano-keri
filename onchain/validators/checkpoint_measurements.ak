//// T116-R4 final checkpoint measurements.
////
//// The exact six full-validator ACCEPT contexts use committed generated KERI
//// evidence, including the real 2-key and GLEIF-shaped 7-key Arm wires and the
//// witnessed-fork Convict wire. Convict inputs carry conservative surplus
//// change in addition to the protected reserves. `just measure-checkpoint`
//// enforces these titles and the 25%-headroom caps.

use aiken/collection/list
use aiken/interval
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{
  Address, Credential, Script, from_script, from_verification_key,
}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
}
use cardano_keri/checkpoint/advance_vectors as adv_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence, TombstoneV1}
use cardano_keri/checkpoint/enforcement_vectors as enf_vec
use cardano_keri/checkpoint/freeze_bond.{ArmedV1}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_convict, observe_freeze,
  observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/role.{Armed, Frozen, Tombstone}
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint.{
  ClaimFreeze, Convict, Freeze, MintRedeemer, Register, SpendRedeemer,
}

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

/// Must equal the shared vectors' `checkpoint_policy_id` (the R7
/// signatures bind it via the reconstructed preimage).
const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

/// The R1 observer deployment: the checkpoint is parameterized by the applied
/// The family-split observers (A-004): the checkpoint is parameterized by
/// both observer hashes. These fixtures stand in for those hashes in the
/// measurement contexts. Register selects lifecycle; Freeze/Convict select
/// enforcement; ClaimFreeze needs neither.
const lifecycle_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const advance_hash: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const enforcement_hash: PolicyId =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

const freeze_window: Int = 500

const hunter_pkh: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

/// Couple an evidence-bearing measurement transaction to a family observer: a
/// zero-lovelace withdrawal of that family credential plus a matching
/// Withdraw-purpose redeemer carrying the envelope (claim + opaque payload).
/// The checkpoint ran-check reads only the claim.
fn with_observer_coupling(
  tx: Transaction,
  family_hash: PolicyId,
  action: Int,
  own_ref: Option<OutputReference>,
  payload: Data,
) -> Transaction {
  let credential: Credential = Script(family_hash)
  let claim = ObserverClaim { action, checkpoint_policy: policy, own_ref }
  let envelope = ObserverEnvelope { claim, payload }
  let rdm_data: Data = envelope
  Transaction {
    ..tx,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), rdm_data)],
  }
}

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

const register_surplus: Int = 42_000_000

const tx_2key: Transaction =
  with_observer_coupling(
    register_tx(
      vec.pos_2key_datum,
      min_ada + d_reg + freeze_bond,
      vec.pos_2key_evidence,
    ),
    lifecycle_hash,
    observe_register,
    None,
    vec.pos_2key_evidence,
  )

const redeemer_2key: MintRedeemer = Register

const tx_7key: Transaction =
  with_observer_coupling(
    register_tx(
      vec.pos_7key_datum,
      min_ada + d_reg + freeze_bond + register_surplus,
      vec.pos_7key_evidence,
    ),
    lifecycle_hash,
    observe_register,
    None,
    vec.pos_7key_evidence,
  )

const redeemer_7key: MintRedeemer = Register

const tx_witnessed: Transaction =
  with_observer_coupling(
    register_tx(
      vec.pos_witnessed_datum,
      min_ada + d_reg + freeze_bond + register_surplus,
      vec.pos_witnessed_evidence,
    ),
    lifecycle_hash,
    observe_register,
    None,
    vec.pos_witnessed_evidence,
  )

const redeemer_witnessed: MintRedeemer = Register

test measure_checkpoint_register_2key() {
  checkpoint.checkpoint.mint(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    redeemer_2key,
    policy,
    tx_2key,
  )
}

test measure_checkpoint_register_witnessed() {
  checkpoint.checkpoint.mint(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    redeemer_witnessed,
    policy,
    tx_witnessed,
  )
}

test measure_checkpoint_register_7key() {
  checkpoint.checkpoint.mint(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    redeemer_7key,
    policy,
    tx_7key,
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
  from_lovelace(advance_deposit + freeze_bond)
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
        address: role.address(policy, Armed),
        value,
        datum: InlineDatum(
          ArmedV1 { checkpoint: d, hunter_pkh, deadline: 1_000 + freeze_window },
        ),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.between(0, 1_000),
    0,
  )
}

const own_ref_freeze_2key: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 7 }

const tx_freeze_2key: Transaction =
  with_observer_coupling(
    freeze_measurement_tx(own_ref_freeze_2key, enf_vec.honest2_freeze_tip),
    enforcement_hash,
    observe_freeze,
    Some(own_ref_freeze_2key),
    honest2_freeze_wire,
  )

const own_ref_freeze_7key: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 5 }

const tx_freeze_7key: Transaction =
  with_observer_coupling(
    freeze_measurement_tx(own_ref_freeze_7key, enf_vec.honest7_freeze_tip),
    enforcement_hash,
    observe_freeze,
    Some(own_ref_freeze_7key),
    honest7_freeze_wire,
  )

test measure_checkpoint_arm_2key() {
  checkpoint.checkpoint.spend(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Freeze { hunter_pkh },
    own_ref_freeze_2key,
    tx_freeze_2key,
  )
}

test measure_checkpoint_arm_7key() {
  checkpoint.checkpoint.spend(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Freeze { hunter_pkh },
    own_ref_freeze_7key,
    tx_freeze_7key,
  )
}

const own_ref_freeze_lag: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 8 }

fn freeze_lag_value() -> Value {
  from_lovelace(advance_deposit + freeze_bond)
    |> merge(
        from_asset(
          policy,
          deriveAidAssetName(enf_vec.lag_freeze_tip.cesr_aid),
          1,
        ),
      )
}

const tx_claim: Transaction =
  spend_context(
    [
      input_at(
        own_ref_freeze_lag,
        Output {
          address: role.address(policy, Armed),
          value: freeze_lag_value(),
          datum: InlineDatum(
            ArmedV1 {
              checkpoint: enf_vec.lag_freeze_tip,
              hunter_pkh,
              deadline: 1_000 + freeze_window,
            },
          ),
          reference_script: None,
        },
      ),
    ],
    [],
    [
      Output {
        address: from_verification_key(hunter_pkh),
        value: from_lovelace(freeze_bond),
        datum: NoDatum,
        reference_script: None,
      },
      Output {
        address: role.address(policy, Frozen),
        value: freeze_lag_value() |> merge(from_lovelace(-freeze_bond)),
        datum: InlineDatum(V1(enf_vec.lag_freeze_tip)),
        reference_script: None,
      },
    ],
    zero,
    [],
    interval.after(1_000 + freeze_window),
    0,
  )

test measure_checkpoint_claim() {
  checkpoint.checkpoint.spend(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    ClaimFreeze { hunter_output_index: 0 },
    own_ref_freeze_lag,
    tx_claim,
  )
}

// ---------------------------------------------------------------------
// Full final Convict measurements: one witnessed-fork wire on each admitted
// live role. Protected reserves are paid exactly; unrelated surplus becomes
// ordinary change and is deliberately present in every context.
// ---------------------------------------------------------------------

const own_ref_convict_witnessed: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 6 }

const convictor_pkh: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const change_pkh: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const conservative_surplus: Int = 42_000_000

fn convict_witnessed_input_value(protected: Int) -> Value {
  from_lovelace(min_ada + protected + conservative_surplus)
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

fn exact_payout(pkh: ByteArray, lovelace: Int) -> Output {
  Output {
    address: from_verification_key(pkh),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn convict_witnessed_tx(
  input_address: Address,
  input_datum: Data,
  protected: Int,
  protected_outputs: List<Output>,
) -> Transaction {
  spend_context(
    [
      input_at(
        own_ref_convict_witnessed,
        Output {
          address: input_address,
          value: convict_witnessed_input_value(protected),
          datum: InlineDatum(input_datum),
          reference_script: None,
        },
      ),
    ],
    [],
    list.concat(
      protected_outputs,
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
        exact_payout(change_pkh, conservative_surplus),
      ],
    ),
    zero,
    [],
    interval.everything,
    0,
  )
}

const tx_convict_witnessed_active: Transaction =
  with_observer_coupling(
    convict_witnessed_tx(
      from_script(policy),
      V1(enf_vec.fork_witnessed_convict_tip),
      d_reg + freeze_bond,
      [exact_payout(convictor_pkh, d_reg + freeze_bond)],
    ),
    enforcement_hash,
    observe_convict,
    Some(own_ref_convict_witnessed),
    enf_vec.fork_witnessed_convict_wire,
  )

const tx_convict_witnessed_armed: Transaction =
  with_observer_coupling(
    convict_witnessed_tx(
      role.address(policy, Armed),
      ArmedV1 {
        checkpoint: enf_vec.fork_witnessed_convict_tip,
        hunter_pkh,
        deadline: 1_000 + freeze_window,
      },
      d_reg + freeze_bond,
      [
        exact_payout(convictor_pkh, d_reg),
        exact_payout(hunter_pkh, freeze_bond),
      ],
    ),
    enforcement_hash,
    observe_convict,
    Some(own_ref_convict_witnessed),
    enf_vec.fork_witnessed_convict_wire,
  )

const tx_convict_witnessed_frozen: Transaction =
  with_observer_coupling(
    convict_witnessed_tx(
      role.address(policy, Frozen),
      V1(enf_vec.fork_witnessed_convict_tip),
      d_reg,
      [exact_payout(convictor_pkh, d_reg)],
    ),
    enforcement_hash,
    observe_convict,
    Some(own_ref_convict_witnessed),
    enf_vec.fork_witnessed_convict_wire,
  )

fn convict_redeemer(
  convictor_output_index: Int,
  hunter_output_index: Int,
) -> SpendRedeemer {
  Convict { convictor_pkh, convictor_output_index, hunter_output_index }
}

test measure_checkpoint_convict_active() {
  checkpoint.checkpoint.spend(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    convict_redeemer(0, 0),
    own_ref_convict_witnessed,
    tx_convict_witnessed_active,
  )
}

test measure_checkpoint_convict_armed() {
  checkpoint.checkpoint.spend(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    convict_redeemer(0, 1),
    own_ref_convict_witnessed,
    tx_convict_witnessed_armed,
  )
}

test measure_checkpoint_convict_frozen() {
  checkpoint.checkpoint.spend(
    0,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    convict_redeemer(0, 0),
    own_ref_convict_witnessed,
    tx_convict_witnessed_frozen,
  )
}
