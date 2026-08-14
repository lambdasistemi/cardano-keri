//// #136 — real-script tests for the register-only checkpoint vertical.

use aiken/cbor
use aiken/collection/list
use aiken/interval
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{Address, Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
  placeholder,
}
use cardano_keri/bounty_commitment.{
  BountyAction, BountyCommitment, BountyCommitmentV1, BountyRevealV1,
  BountyScope, CommitmentFamily, CommitmentParameters, ConvictEntitlement,
  FreezeEntitlement, commitment_domain, commitment_hash, commitment_preimage,
  commitment_schema, marker_name,
}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/advance_vectors as advance_vec
use cardano_keri/checkpoint/close.{CloseEvidence}
use cardano_keri/checkpoint/close_vectors as close_vec
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence}
use cardano_keri/checkpoint/enforcement_vectors as enforcement_vec
use cardano_keri/checkpoint/entitlement.{
  EnforcementProofV1, enforcement_evidence_digest,
}
use cardano_keri/checkpoint/freeze_bond.{ArmedV1, ArmedV2}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_freeze, observe_migration, observe_register, observe_response_advance,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/role.{Active, Armed, Frozen}
use cardano_keri/checkpoint/threshold.{Unweighted}
use cardano_keri/migration/checkpoint.{
  MigrateInProof, MigrateOutProof, MigrationProof,
} as migration_checkpoint
use cardano_keri/migration/checkpoint_vectors as mig_vec
use cardano_keri/migration/types.{
  CheckpointActive, MigrationAuthorization, MigrationPredecessor,
  MigrationTarget,
}
use checkpoint.{Freeze as SplitFreeze}
use checkpoint_observer
use checkpoint_register.{
  Advance, ClaimFreeze, Close, CloseBurn, Convict, ConvictBurn, Freeze, Register,
}

/// The applied network these fixtures deploy under, matching the `network_id`
/// argument every applied register in this module is built with.
const network_id: Int = 1

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

/// The promoted #254 migration observer this applied program requires for a
/// migrate arm. These regression tests exercise the pre-migration lifecycle,
/// which never withdraws under it.
const migration_hash: PolicyId =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const lifecycle_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const advance_hash: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const enforcement_hash: PolicyId =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const entitlement_hash: PolicyId =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

const freeze_window: Int = 10_000

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
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    0,
    d_reg,
    freeze_bond,
    freeze_window,
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
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    CloseBurn { checkpoint_ref: close_own_ref() },
    policy,
    tx,
  ) && checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
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
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Advance,
    rotate_ref(spent),
    tx,
  ) && advance_predicate(spent, created, evidence) == AdvancePredicateValid
}

test rotate_small_rejects_missing_advance_observer() fail {
  let spent = advance_vec.pos_adv_wit_2key_spent
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
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
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Advance,
    rotate_ref(spent),
    with_advance_observer(
      Transaction { ..tx, outputs: [changed_successor] },
      advance_envelope(spent, advance_vec.pos_adv_wit_2key_evidence),
    ),
  )
}

// ---------------------------------------------------------------------
// #137 RED — thin Freeze + enforcement observer, followed by an ARMED
// response through the already-open Advance observer.
// ---------------------------------------------------------------------

const freeze_upper: Int = 1_000

const freeze_deadline: Int = freeze_upper + freeze_window

const hunter: ByteArray =
  #"42424242424242424242424242424242424242424242424242424242"

fn freeze_ref() -> OutputReference {
  out_ref(seed_tx_id, 8)
}

fn freeze_value(tip: CheckpointDatumV1) -> Value {
  from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
}

// ---------------------------------------------------------------------
// #254 S254-E — the entitled combined family.
//
// The combined register delegates the entitlement verdict to the shared
// enforcement observer, which is the only party holding the complete actual
// evidence. These fixtures build genuine reservations from the ADOPTED
// component types rather than test-side mirrors: the wire-shape parity control
// lives in `checkpoint_tests.ak`, so what this module owes is the real
// combined path, executed for real.
// ---------------------------------------------------------------------

/// The release commitment family this applied register honours. The policy is
/// the identity of the commitment program; a reservation at any other script is
/// counterfeit (`INV-271-COMMITMENT-POLICY-AUTHENTICITY`).
const commit_policy: PolicyId =
  #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

/// An EXPLICIT applied lifetime. Finite, at or above the mandated one-slot age,
/// and deliberately not a published protocol default: the superseded
/// 10,000-slot constant is never recreated, not even test-side.
const applied_lifetime: Int = 4_321

const applied_deposit: Int = 5_000_000

const commitment_family: CommitmentFamily =
  CommitmentFamily {
    policy: commit_policy,
    parameters: CommitmentParameters {
      network: network_id,
      commit_min_age: 1,
      commitment_lifetime: applied_lifetime,
      commit_deposit: applied_deposit,
    },
  }

const commit_seed_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 91 }

const commitment_ref: OutputReference =
  OutputReference { transaction_id: seed_tx_id, output_index: 92 }

const commit_nonce: ByteArray =
  #"6e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e63656e6f6e6365000f"

/// The commitment an honest hunter or convictor opened over THIS checkpoint,
/// THIS action, and the digest of THIS actual evidence.
fn commitment_for(
  checkpoint_ref: OutputReference,
  action: BountyAction,
  payee_pkh: ByteArray,
  evidence: EnforcementEvidence,
) -> BountyCommitment {
  let marker = marker_name(commit_seed_ref)
  let scope = BountyScope {
    domain: commitment_domain,
    schema: commitment_schema,
    network: network_id,
    checkpoint_policy: policy,
    checkpoint_ref,
    action,
    marker,
    commit_upper: 0,
    eligible_after: 1,
    expires_at: applied_lifetime,
  }
  BountyCommitmentV1 {
    scope,
    payee_pkh,
    hash: commitment_hash(
      commitment_preimage(
        scope,
        enforcement_evidence_digest(evidence),
        payee_pkh,
        commit_nonce,
      ),
    ),
    marker,
  }
}

/// An authentic commitment UTxO at the FAMILY policy: exactly its own
/// seed-derived marker plus the applied deposit, and nothing else.
fn commitment_input_at(script: PolicyId, commitment: BountyCommitment) -> Input {
  let BountyCommitmentV1 { marker, .. } = commitment
  let datum: Data = commitment
  input_at(
    commitment_ref,
    Output {
      address: from_script(script),
      value: from_lovelace(applied_deposit)
        |> merge(from_asset(script, marker, 1)),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  )
}

/// Attach a reservation to an enforcement transaction without disturbing what
/// the row under test is about.
///
/// The validity range keeps its exact UPPER endpoint — that is what anchors the
/// stored ARMED deadline, and what the raw-exclusive rows are about — while the
/// lower endpoint moves up to the maturity slot, because a commitment revealed
/// in the slot it was opened in is not aged. The marker burn is merged into the
/// existing mint rather than replacing it, so the AID burn a conviction already
/// carries survives.
fn with_reservation(
  base: Transaction,
  script: PolicyId,
  commitment: BountyCommitment,
) -> Transaction {
  let BountyCommitmentV1 { marker, payee_pkh, scope, .. } = commitment
  // A reveal must land inside the reservation's window, so an unbounded range
  // has to acquire a finite upper endpoint. Rows that already declare one keep
  // it exactly: it is what anchors the stored ARMED deadline.
  let upper = when base.validity_range.upper_bound.bound_type is {
    interval.Finite(_) -> base.validity_range.upper_bound
    _ ->
      interval.IntervalBound {
        bound_type: interval.Finite(scope.expires_at),
        is_inclusive: True,
      }
  }
  Transaction {
    ..base,
    validity_range: interval.Interval {
      lower_bound: interval.IntervalBound {
        bound_type: interval.Finite(1),
        is_inclusive: True,
      },
      upper_bound: upper,
    },
    inputs: list.concat(base.inputs, [commitment_input_at(script, commitment)]),
    outputs: list.concat(
      base.outputs,
      [convict_payout(payee_pkh, applied_deposit)],
    ),
    mint: base.mint |> merge(from_asset(script, marker, -1)),
  }
}

fn reveal_for() -> BountyRevealV1 {
  BountyRevealV1 { commitment_ref, nonce: commit_nonce, refund_index: 0 }
}

/// The enforcement observer payload: actual evidence, the payee this
/// enforcement pays, and the reservation that earns it.
fn enforcement_proof(
  evidence: EnforcementEvidence,
  payee_pkh: ByteArray,
) -> EnforcementProofV1 {
  EnforcementProofV1 { evidence, payee_pkh, reveal: reveal_for() }
}

fn freeze_envelope_for(
  evidence: EnforcementEvidence,
  payee_pkh: ByteArray,
) -> ObserverEnvelope {
  let payload: Data = enforcement_proof(evidence, payee_pkh)
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_freeze,
      checkpoint_policy: policy,
      own_ref: Some(freeze_ref()),
    },
    payload,
  }
}

fn freeze_envelope(evidence: EnforcementEvidence) -> ObserverEnvelope {
  freeze_envelope_for(evidence, hunter)
}

fn freeze_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  next_hunter: ByteArray,
  successor_value: Value,
) -> Transaction {
  let own_input = input_at(
    freeze_ref(),
    Output {
      address: role.address(policy, Active),
      value: freeze_value(tip),
      datum: InlineDatum(V1(tip)),
      reference_script: None,
    },
  )
  // The successor a freeze PRODUCES is the lean `ArmedV2`, because that is
  // what the combined mirror now writes. The ARMED states this module
  // CONSUMES elsewhere stay `ArmedV1` on purpose: the legacy constructor must
  // keep decoding and reading identically through the shared accessors, which
  // is the whole point of keeping one `ArmedDatum` sum (A-001).
  let armed = Output {
    address: role.address(policy, Armed),
    value: successor_value,
    datum: InlineDatum(
      ArmedV2 {
        checkpoint: tip,
        hunter_pkh: next_hunter,
        deadline: freeze_deadline,
      },
    ),
    reference_script: None,
  }
  let tx = spend_context(
    [own_input],
    [],
    [armed],
    zero,
    [],
    interval.between(0, freeze_upper),
    0,
  )
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  let envelope = freeze_envelope_for(evidence, next_hunter)
  let redeemer: Data = envelope
  // Both observers withdraw the same envelope. Neither half alone
  // authorizes the settlement; the register binds the pair.
  with_reservation(
    Transaction {
      ..tx,
      withdrawals: [
        Pair(enforcement_credential, 0), Pair(entitlement_credential, 0),
      ],
      redeemers: [
        Pair(Withdraw(enforcement_credential), redeemer),
        Pair(Withdraw(entitlement_credential), redeemer),
      ],
    },
    commit_policy,
    commitment_for(freeze_ref(), FreezeEntitlement, next_hunter, evidence),
  )
}

fn freeze_tx(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
) -> Transaction {
  freeze_tx_with(tip, evidence, hunter, freeze_value(tip))
}

fn run_freeze_small(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  tx: Transaction,
) -> Bool {
  let envelope = freeze_envelope(evidence)
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Freeze { hunter_pkh: hunter },
    freeze_ref(),
    tx,
  ) && checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    envelope,
    0,
    tx,
  ) && checkpoint_observer.observer_entitlement.withdraw(
    0,
    commitment_family,
    envelope,
    0,
    tx,
  ) && tip == tip
}

test freeze_small_accepts_genuine_witnessed_later_rotation() {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  run_freeze_small(tip, evidence, freeze_tx(tip, evidence))
}

/// The SPLIT checkpoint program, applied with the same release family, judging
/// a transaction built for the combined register.
///
/// The two families divide the work differently — the split program carries the
/// evidence and the reveal in its own redeemer and settles alone; the combined
/// register delegates the verdict to the shared observer and keeps the value —
/// but they are the same rule, so one transaction cannot satisfy one and not
/// the other.
fn run_freeze_split(evidence: EnforcementEvidence, tx: Transaction) -> Bool {
  let redeemer: Data = SplitFreeze {
    evidence,
    hunter_pkh: hunter,
    reveal: reveal_for(),
  }
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    freeze_bond,
    freeze_window,
    commitment_family,
    None,
    redeemer,
    freeze_ref(),
    tx,
  )
}

/// INV-271-PARITY across FAMILIES. One transaction, two applied programs, one
/// verdict.
///
/// This is the row the name promises: the left conjunct runs the real combined
/// register together with its real shared observer, and the right conjunct runs
/// the real split checkpoint program — over the identical transaction, with the
/// identical applied commitment family. A rule that drifted between the two
/// families would show up here as one side accepting and the other refusing,
/// which no amount of running the same family twice could ever detect.
test s254_e_split_and_combined_mirror_agree() {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let tx = freeze_tx(tip, evidence)
  and {
    run_freeze_small(tip, evidence, tx),
    run_freeze_split(evidence, tx),
  }
}

/// The parity row is only worth its name if it CAN disagree. The same split
/// program, applied to a family pinned somewhere else, refuses the very
/// transaction the combined family just accepted — so the conjunction above is
/// not two copies of one tautology.
test s254_e_split_and_combined_mirror_agree_can_disagree() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let redeemer: Data = SplitFreeze {
    evidence,
    hunter_pkh: hunter,
    reveal: reveal_for(),
  }
  checkpoint.checkpoint.spend(
    0,
    hp_policy,
    network_id,
    d_reg,
    freeze_bond,
    freeze_window,
    CommitmentFamily {
      ..commitment_family,
      policy: #"f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0",
    },
    None,
    redeemer,
    freeze_ref(),
    freeze_tx(tip, evidence),
  )
}

test freeze_small_rejects_missing_enforcement_observer() fail {
  let tip = enforcement_vec.lag_freeze_tip
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Freeze { hunter_pkh: hunter },
    freeze_ref(),
    spend_context(
      [
        input_at(
          freeze_ref(),
          Output {
            address: role.address(policy, Active),
            value: freeze_value(tip),
            datum: InlineDatum(V1(tip)),
            reference_script: None,
          },
        ),
      ],
      [],
      [],
      zero,
      [],
      interval.between(0, freeze_upper),
      0,
    ),
  )
}

test freeze_small_rejects_below_prior_controller_threshold() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = EnforcementEvidence {
    ..enforcement_vec.lag_freeze_wire,
    ctrl_sigs: [],
  }
  run_freeze_small(tip, evidence, freeze_tx(tip, evidence))
}

test freeze_small_rejects_insufficient_witness_receipts() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = EnforcementEvidence {
    ..enforcement_vec.lag_freeze_wire,
    wit_sigs: [],
  }
  run_freeze_small(tip, evidence, freeze_tx(tip, evidence))
}

test freeze_small_rejects_crossed_aid() fail {
  let tip = CheckpointDatumV1 {
    ..enforcement_vec.lag_freeze_tip,
    cesr_aid: #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  }
  let evidence = enforcement_vec.lag_freeze_wire
  run_freeze_small(tip, evidence, freeze_tx(tip, evidence))
}

test freeze_small_rejects_changed_successor_value() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let changed = from_lovelace(min_ada + d_reg + freeze_bond + 1)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
  run_freeze_small(
    tip,
    evidence,
    freeze_tx_with(tip, evidence, hunter, changed),
  )
}

fn armed_rotate_tx(
  spent: SpentCheckpoint,
  created: CheckpointDatumV1,
  upper: Int,
) -> Transaction {
  let value = from_lovelace(min_ada + d_reg + freeze_bond)
    |> merge(from_asset(policy, spent.aid_asset_name, 1))
  let own_input = input_at(
    rotate_ref(spent),
    Output {
      address: role.address(policy, Armed),
      value,
      datum: InlineDatum(
        ArmedV1 {
          checkpoint: rotate_old(spent),
          hunter_pkh: hunter,
          deadline: freeze_deadline,
        },
      ),
      reference_script: None,
    },
  )
  let successor = Output {
    address: role.address(policy, Active),
    value,
    datum: InlineDatum(V1(created)),
    reference_script: None,
  }
  let envelope = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_response_advance,
      checkpoint_policy: policy,
      own_ref: Some(rotate_ref(spent)),
    },
    payload: advance_vec.pos_adv_wit_2key_evidence,
  }
  with_advance_observer(
    spend_context(
      [own_input],
      [],
      [successor],
      zero,
      [],
      interval.between(0, upper),
      0,
    ),
    envelope,
  )
}

fn run_armed_response(upper: Int) -> Bool {
  let spent = advance_vec.pos_adv_wit_2key_spent
  let created = advance_vec.pos_adv_wit_2key_created
  let evidence = advance_vec.pos_adv_wit_2key_evidence
  let tx = armed_rotate_tx(spent, created, upper)
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Advance,
    rotate_ref(spent),
    tx,
  ) && advance_predicate(spent, created, evidence) == AdvancePredicateValid
}

test freeze_small_accepts_response_advance_before_deadline() {
  run_armed_response(freeze_deadline - 1)
}

test freeze_small_rejects_response_advance_at_deadline() fail {
  run_armed_response(freeze_deadline)
}

// ---------------------------------------------------------------------
// #138 RED — timeout ClaimFreeze pays exactly B to the recorded hunter,
// then ordinary Advance thaws FROZEN by re-posting B.
// ---------------------------------------------------------------------

const wrong_hunter: ByteArray =
  #"43434343434343434343434343434343434343434343434343434343"

fn claim_tx_with(
  tip: CheckpointDatumV1,
  payout_hunter: ByteArray,
  payout_lovelace: Int,
  lower: Int,
  frozen_value: Value,
) -> Transaction {
  let own_input = input_at(
    freeze_ref(),
    Output {
      address: role.address(policy, Armed),
      value: freeze_value(tip),
      datum: InlineDatum(
        ArmedV1 {
          checkpoint: tip,
          hunter_pkh: hunter,
          deadline: freeze_deadline,
        },
      ),
      reference_script: None,
    },
  )
  let payout = Output {
    address: from_verification_key(payout_hunter),
    value: from_lovelace(payout_lovelace),
    datum: NoDatum,
    reference_script: None,
  }
  let frozen = Output {
    address: role.address(policy, Frozen),
    value: frozen_value,
    datum: InlineDatum(V1(tip)),
    reference_script: None,
  }
  spend_context(
    [own_input],
    [],
    [payout, frozen],
    zero,
    [],
    interval.between(lower, lower + 1_000),
    0,
  )
}

fn claimed_value(tip: CheckpointDatumV1) -> Value {
  from_lovelace(min_ada + d_reg)
    |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1))
}

fn run_claim_small(tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    ClaimFreeze { hunter_output_index: 0 },
    freeze_ref(),
    tx,
  )
}

test seize_delay_accepts_claim_at_deadline() {
  let tip = enforcement_vec.lag_freeze_tip
  run_claim_small(
    claim_tx_with(tip, hunter, freeze_bond, freeze_deadline, claimed_value(tip)),
  )
}

test seize_delay_rejects_early_claim() fail {
  let tip = enforcement_vec.lag_freeze_tip
  run_claim_small(
    claim_tx_with(
      tip,
      hunter,
      freeze_bond,
      freeze_deadline - 1,
      claimed_value(tip),
    ),
  )
}

test seize_delay_rejects_wrong_hunter() fail {
  let tip = enforcement_vec.lag_freeze_tip
  run_claim_small(
    claim_tx_with(
      tip,
      wrong_hunter,
      freeze_bond,
      freeze_deadline,
      claimed_value(tip),
    ),
  )
}

test seize_delay_rejects_non_exact_hunter_payout() fail {
  let tip = enforcement_vec.lag_freeze_tip
  run_claim_small(
    claim_tx_with(
      tip,
      hunter,
      freeze_bond + 1,
      freeze_deadline,
      claimed_value(tip),
    ),
  )
}

fn thaw_tx_with(
  spent: SpentCheckpoint,
  created: CheckpointDatumV1,
  successor_lovelace: Int,
) -> Transaction {
  let own_input = input_at(
    rotate_ref(spent),
    Output {
      address: role.address(policy, Frozen),
      value: from_lovelace(min_ada + d_reg)
        |> merge(from_asset(policy, spent.aid_asset_name, 1)),
      datum: InlineDatum(V1(rotate_old(spent))),
      reference_script: None,
    },
  )
  let successor = Output {
    address: role.address(policy, Active),
    value: from_lovelace(successor_lovelace)
      |> merge(from_asset(policy, spent.aid_asset_name, 1)),
    datum: InlineDatum(V1(created)),
    reference_script: None,
  }
  with_advance_observer(
    spend_context(
      [own_input],
      [],
      [successor],
      zero,
      [],
      interval.everything,
      0,
    ),
    advance_envelope(spent, advance_vec.pos_adv_wit_2key_evidence),
  )
}

fn run_thaw_small(successor_lovelace: Int) -> Bool {
  let spent = advance_vec.pos_adv_wit_2key_spent
  let created = advance_vec.pos_adv_wit_2key_created
  let evidence = advance_vec.pos_adv_wit_2key_evidence
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Advance,
    rotate_ref(spent),
    thaw_tx_with(spent, created, successor_lovelace),
  ) && advance_predicate(spent, created, evidence) == AdvancePredicateValid
}

test seize_delay_accepts_thaw_with_reposted_bond() {
  run_thaw_small(min_ada + d_reg + freeze_bond)
}

test seize_delay_rejects_thaw_without_exact_bond() fail {
  run_thaw_small(min_ada + d_reg + freeze_bond - 1)
}

// ---------------------------------------------------------------------
// #151 RED — witnessed conviction burns the AID token and atomically
// distributes the complete source-state reserve. These tests compose the
// applied checkpoint mint/spend validators with the applied enforcement
// observer; the Convict constructors and action are deliberately absent
// until GREEN.
// ---------------------------------------------------------------------

const convictor: ByteArray =
  #"51515151515151515151515151515151515151515151515151515151"

const other_recipient: ByteArray =
  #"52525252525252525252525252525252525252525252525252525252"

fn convict_ref() -> OutputReference {
  out_ref(seed_tx_id, 15)
}

fn crossed_convict_ref() -> OutputReference {
  out_ref(seed_tx_id, 16)
}

fn convict_payout(recipient: ByteArray, lovelace: Int) -> Output {
  Output {
    address: from_verification_key(recipient),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn convict_envelope_for(
  action: Int,
  own_ref: OutputReference,
  evidence: EnforcementEvidence,
  payee_pkh: ByteArray,
) -> ObserverEnvelope {
  let payload: Data = enforcement_proof(evidence, payee_pkh)
  ObserverEnvelope {
    claim: ObserverClaim {
      action,
      checkpoint_policy: policy,
      own_ref: Some(own_ref),
    },
    payload,
  }
}

fn convict_envelope_at(
  action: Int,
  own_ref: OutputReference,
  evidence: EnforcementEvidence,
) -> ObserverEnvelope {
  convict_envelope_for(action, own_ref, evidence, convictor)
}

fn convict_context(
  input_address: Address,
  input_datum: Data,
  input_lovelace: Int,
  tip: CheckpointDatumV1,
  outputs: List<Output>,
  mint: Value,
  action: Int,
  evidence: EnforcementEvidence,
) -> Transaction {
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  let own_input = input_at(
    convict_ref(),
    Output {
      address: input_address,
      value: from_lovelace(input_lovelace)
        |> merge(from_asset(policy, aid_name, 1)),
      datum: InlineDatum(input_datum),
      reference_script: None,
    },
  )
  let tx = spend_context(
    [own_input],
    [],
    outputs,
    mint,
    [],
    interval.everything,
    0,
  )
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  let envelope = convict_envelope_at(action, convict_ref(), evidence)
  let observer_redeemer: Data = envelope
  with_reservation(
    Transaction {
      ..tx,
      withdrawals: [
        Pair(enforcement_credential, 0), Pair(entitlement_credential, 0),
      ],
      redeemers: [
        Pair(Withdraw(enforcement_credential), observer_redeemer),
        Pair(Withdraw(entitlement_credential), observer_redeemer),
      ],
    },
    commit_policy,
    commitment_for(convict_ref(), ConvictEntitlement, convictor, evidence),
  )
}

fn active_convict_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  payout_lovelace: Int,
  mint: Value,
  action: Int,
) -> Transaction {
  convict_context(
    role.address(policy, Active),
    V1(tip),
    min_ada + d_reg + freeze_bond,
    tip,
    [convict_payout(convictor, payout_lovelace)],
    mint,
    action,
    evidence,
  )
}

fn active_convict_tx(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
) -> Transaction {
  active_convict_tx_with(
    tip,
    evidence,
    min_ada + d_reg + freeze_bond,
    from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    observe_convict,
  )
}

fn armed_convict_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  convictor_lovelace: Int,
  payout_hunter: ByteArray,
  hunter_lovelace: Int,
) -> Transaction {
  convict_context(
    role.address(policy, Armed),
    ArmedV1 { checkpoint: tip, hunter_pkh: hunter, deadline: freeze_deadline },
    min_ada + d_reg + freeze_bond,
    tip,
    [
      convict_payout(convictor, convictor_lovelace),
      convict_payout(payout_hunter, hunter_lovelace),
    ],
    from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    observe_convict,
    evidence,
  )
}

fn armed_convict_tx(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
) -> Transaction {
  armed_convict_tx_with(tip, evidence, min_ada + d_reg, hunter, freeze_bond)
}

fn frozen_convict_tx_with(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  payout_lovelace: Int,
) -> Transaction {
  convict_context(
    role.address(policy, Frozen),
    V1(tip),
    min_ada + d_reg,
    tip,
    [convict_payout(convictor, payout_lovelace)],
    from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    observe_convict,
    evidence,
  )
}

fn frozen_convict_tx(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
) -> Transaction {
  frozen_convict_tx_with(tip, evidence, min_ada + d_reg)
}

fn run_convict_with_action(
  tx: Transaction,
  evidence: EnforcementEvidence,
  action: Int,
  convictor_output_index: Int,
  hunter_output_index: Int,
) -> Bool {
  let envelope = convict_envelope_at(action, convict_ref(), evidence)
  checkpoint_register.checkpoint_register.mint(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    ConvictBurn { checkpoint_ref: convict_ref() },
    policy,
    tx,
  ) && checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Convict {
      convictor_pkh: convictor,
      convictor_output_index,
      hunter_output_index,
    },
    convict_ref(),
    tx,
  ) && checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    envelope,
    0,
    tx,
  ) && checkpoint_observer.observer_entitlement.withdraw(
    0,
    commitment_family,
    envelope,
    0,
    tx,
  )
}

fn run_convict(
  tx: Transaction,
  evidence: EnforcementEvidence,
  convictor_output_index: Int,
  hunter_output_index: Int,
) -> Bool {
  run_convict_with_action(
    tx,
    evidence,
    observe_convict,
    convictor_output_index,
    hunter_output_index,
  )
}

test convict_small_accepts_active_exact_burn_and_full_reserve_payout() {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(active_convict_tx(tip, evidence), evidence, 0, 0)
}

test convict_small_accepts_armed_exact_split_to_convictor_and_recorded_hunter() {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(armed_convict_tx(tip, evidence), evidence, 0, 1)
}

test convict_small_accepts_frozen_without_recreating_delay_bond() {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(frozen_convict_tx(tip, evidence), evidence, 0, 0)
}

test convict_small_accepts_surplus_lovelace_as_ordinary_change() {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  let surplus = 17
  let tx = convict_context(
    role.address(policy, Active),
    V1(tip),
    min_ada + d_reg + freeze_bond + surplus,
    tip,
    [
      convict_payout(convictor, min_ada + d_reg + freeze_bond),
      convict_payout(other_recipient, surplus),
    ],
    from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    observe_convict,
    evidence,
  )
  run_convict(tx, evidence, 0, 0)
}

test convict_small_rejects_active_non_exact_payout() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  let tx = active_convict_tx_with(
    tip,
    evidence,
    min_ada + d_reg + freeze_bond - 1,
    from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    observe_convict,
  )
  run_convict(tx, evidence, 0, 0)
}

test convict_small_rejects_armed_non_exact_hunter_bond() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(
    armed_convict_tx_with(
      tip,
      evidence,
      min_ada + d_reg,
      hunter,
      freeze_bond - 1,
    ),
    evidence,
    0,
    1,
  )
}

test convict_small_rejects_armed_hunter_redirection() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(
    armed_convict_tx_with(
      tip,
      evidence,
      min_ada + d_reg,
      other_recipient,
      freeze_bond,
    ),
    evidence,
    0,
    1,
  )
}

test convict_small_rejects_armed_reused_payout_index() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(armed_convict_tx(tip, evidence), evidence, 0, 0)
}

test convict_small_rejects_frozen_second_delay_bond() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  run_convict(
    frozen_convict_tx_with(tip, evidence, min_ada + d_reg + freeze_bond),
    evidence,
    0,
    0,
  )
}

test convict_small_rejects_missing_token_burn() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  let tx = active_convict_tx_with(
    tip,
    evidence,
    min_ada + d_reg + freeze_bond,
    zero,
    observe_convict,
  )
  run_convict(tx, evidence, 0, 0)
}

test convict_small_rejects_token_bearing_successor_output() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  let tx = active_convict_tx(tip, evidence)
  expect [payout] = tx.outputs
  let token_bearing = Output {
    ..payout,
    value: payout.value
      |> merge(from_asset(policy, deriveAidAssetName(tip.cesr_aid), 1)),
  }
  run_convict(Transaction { ..tx, outputs: [token_bearing] }, evidence, 0, 0)
}

test convict_small_rejects_unwitnessed_conflict_at_applied_observer() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  expect tip.toad == 1
  let evidence = EnforcementEvidence {
    ..enforcement_vec.fork_witnessed_convict_wire,
    wit_sigs: [],
  }
  let tx = active_convict_tx(tip, evidence)
  checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    convict_envelope_at(observe_convict, convict_ref(), evidence),
    0,
    tx,
  )
}

test convict_small_rejects_recorded_event_without_conflict_at_applied_observer() fail {
  let tip = enforcement_vec.fork_witnessed_honest_tip
  let evidence = enforcement_vec.fork_witnessed_honest_wire
  let tx = active_convict_tx(tip, evidence)
  checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    convict_envelope_at(observe_convict, convict_ref(), evidence),
    0,
    tx,
  )
}

test convict_small_rejects_freeze_action_tag_for_convict_spend() fail {
  let tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  let tx = active_convict_tx_with(
    tip,
    evidence,
    min_ada + d_reg + freeze_bond,
    from_asset(policy, deriveAidAssetName(tip.cesr_aid), -1),
    observe_freeze,
  )
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Convict {
      convictor_pkh: convictor,
      convictor_output_index: 0,
      hunter_output_index: 0,
    },
    convict_ref(),
    tx,
  )
}

test convict_small_rejects_crossed_observer_and_spend_own_refs() fail {
  let evidence_tip = enforcement_vec.fork_witnessed_convict_tip
  let evidence = enforcement_vec.fork_witnessed_convict_wire
  let spent_tip = enforcement_vec.lag_freeze_tip
  let evidence_aid_name = deriveAidAssetName(evidence_tip.cesr_aid)
  let spent_aid_name = deriveAidAssetName(spent_tip.cesr_aid)
  expect evidence_aid_name != spent_aid_name
  let evidence_input = input_at(
    convict_ref(),
    Output {
      address: role.address(policy, Active),
      value: from_lovelace(min_ada + d_reg + freeze_bond)
        |> merge(from_asset(policy, evidence_aid_name, 1)),
      datum: InlineDatum(V1(evidence_tip)),
      reference_script: None,
    },
  )
  let spent_input = input_at(
    crossed_convict_ref(),
    Output {
      address: role.address(policy, Active),
      value: from_lovelace(min_ada + d_reg + freeze_bond)
        |> merge(from_asset(policy, spent_aid_name, 1)),
      datum: InlineDatum(V1(spent_tip)),
      reference_script: None,
    },
  )
  let evidence_change = Output {
    address: from_verification_key(other_recipient),
    value: from_lovelace(min_ada + d_reg + freeze_bond)
      |> merge(from_asset(policy, evidence_aid_name, 1)),
    datum: NoDatum,
    reference_script: None,
  }
  let base = spend_context(
    [evidence_input, spent_input],
    [],
    [convict_payout(convictor, min_ada + d_reg + freeze_bond), evidence_change],
    from_asset(policy, spent_aid_name, -1),
    [],
    interval.everything,
    0,
  )
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  let envelope = convict_envelope_at(observe_convict, convict_ref(), evidence)
  let observer_redeemer: Data = envelope
  let tx = Transaction {
    ..base,
    withdrawals: [
      Pair(enforcement_credential, 0), Pair(entitlement_credential, 0),
    ],
    redeemers: [
      Pair(Withdraw(enforcement_credential), observer_redeemer),
      Pair(Withdraw(entitlement_credential), observer_redeemer),
    ],
  }
  checkpoint_register.checkpoint_register.mint(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    ConvictBurn { checkpoint_ref: crossed_convict_ref() },
    policy,
    tx,
  ) && checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Convict {
      convictor_pkh: convictor,
      convictor_output_index: 0,
      hunter_output_index: 0,
    },
    crossed_convict_ref(),
    tx,
  ) && checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    envelope,
    0,
    tx,
  )
}

test freeze_small_rejects_convict_action_tag() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let base = freeze_tx(tip, evidence)
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  let envelope = convict_envelope_at(observe_convict, freeze_ref(), evidence)
  let observer_redeemer: Data = envelope
  let tx = Transaction {
    ..base,
    withdrawals: [
      Pair(enforcement_credential, 0), Pair(entitlement_credential, 0),
    ],
    redeemers: [
      Pair(Withdraw(enforcement_credential), observer_redeemer),
      Pair(Withdraw(entitlement_credential), observer_redeemer),
    ],
  }
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Freeze { hunter_pkh: hunter },
    freeze_ref(),
    tx,
  )
}

// ---------------------------------------------------------
// #254 repair: transaction-boundary and lifecycle properties
// ---------------------------------------------------------
//
// Submission 1 proved the migration rules as pure functions and proved the
// compiled observer refuses two mutants. Neither reaches the composition an
// actual migration transaction has to satisfy, and that gap is what the
// independent audit found. These controls run the real applied programs over
// real transactions.

const mig_source_policy: PolicyId = mig_vec.fixture_source_policy

const mig_target_policy: PolicyId = mig_vec.fixture_target_policy

/// The exact source projection the generator signed over.
fn mig_source_datum() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: mig_vec.fixture_cesr_aid,
    cur_keys: [
      mig_vec.fixture_ctrl_key_0,
      mig_vec.fixture_ctrl_key_1,
      mig_vec.fixture_ctrl_key_2,
    ],
    cur_threshold: Unweighted(2),
    next_keys: [mig_vec.fixture_next_key_0, mig_vec.fixture_next_key_1],
    next_threshold: Unweighted(1),
    witnesses: [mig_vec.fixture_witness_key],
    toad: 1,
    seq: 7,
    native_sn: 4,
  }
}

fn mig_source_ref() -> OutputReference {
  OutputReference {
    transaction_id: mig_vec.fixture_source_txid,
    output_index: 1,
  }
}

fn mig_predecessor() -> MigrationPredecessor {
  MigrationPredecessor {
    predecessor_policy: mig_source_policy,
    predecessor_ref: mig_source_ref(),
  }
}

fn mig_target() -> MigrationTarget {
  MigrationTarget {
    target_policy: mig_target_policy,
    target_role: CheckpointActive,
    target_address: from_script(mig_target_policy),
    legacy_refund_address: None,
  }
}

/// The controller-signed package. `signed_state` is what the quorum actually
/// put its signatures over, which is the whole subject of the replay control.
fn mig_authorization(signed_state: Data) -> MigrationAuthorization {
  MigrationAuthorization {
    domain: mig_vec.golden_migration_domain,
    network_id: 1,
    source: mig_predecessor(),
    source_role: CheckpointActive,
    source_state: signed_state,
    target: mig_target(),
    controller_signatures: [
      (0, mig_vec.fixture_sig_0),
      (1, mig_vec.fixture_sig_1),
    ],
  }
}

fn mig_signed_state() -> Data {
  expect Some(state) = cbor.deserialise(mig_vec.golden_source_state)
  state
}

const mig_protected: Int = min_ada + d_reg + freeze_bond

fn mig_source_input(carried: CheckpointDatumV1) -> Input {
  input_at(
    mig_source_ref(),
    Output {
      address: from_script(mig_source_policy),
      value: from_lovelace(mig_protected)
        |> merge(
            from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, 1),
          ),
      datum: InlineDatum(V1(carried)),
      reference_script: None,
    },
  )
}

fn mig_successor_output(carried: CheckpointDatumV1) -> Output {
  Output {
    address: from_script(mig_target_policy),
    value: from_lovelace(mig_protected)
      |> merge(from_asset(mig_target_policy, mig_vec.fixture_aid_asset_name, 1)),
    datum: InlineDatum(V1(carried)),
    reference_script: None,
  }
}

fn mig_replacement_mint() -> Value {
  from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, -1)
    |> merge(from_asset(mig_target_policy, mig_vec.fixture_aid_asset_name, 1))
}

/// The claim names the policy of the program that is asking. Migrate-out is
/// asked by the source generation, migrate-in by the target generation, so the
/// two directions carry different policies and different applied observers.
fn mig_envelope(
  claim_policy: PolicyId,
  proof: MigrationProof,
) -> ObserverEnvelope {
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_migration,
      checkpoint_policy: claim_policy,
      own_ref: Some(mig_source_ref()),
    },
    payload: proof,
  }
}

/// Run the promoted observer of one generation over a real transaction.
fn run_migration_observer(
  claim_policy: PolicyId,
  proof: MigrationProof,
  tx: Transaction,
) -> Bool {
  checkpoint_observer.observer_migration.withdraw(
    mig_source_policy,
    mig_envelope(claim_policy, proof),
    0,
    tx,
  )
}

/// The successor program observes an entry under the target policy.
fn run_migrate_in(proof: MigrationProof, tx: Transaction) -> Bool {
  run_migration_observer(mig_target_policy, proof, tx)
}

/// The source program observes its own exit under the source policy.
fn run_migrate_out(proof: MigrationProof, tx: Transaction) -> Bool {
  run_migration_observer(mig_source_policy, proof, tx)
}

// INV-254-REPLAY — the signed projection must be the consumed projection.
//
// The package below is genuinely controller-signed and its quorum verifies:
// the signatures really do cover `golden_source_state`. What differs is the
// state the transaction actually consumes and lands. Nothing about the
// message bytes is wrong, so a message-inequality control cannot see this;
// only the transaction boundary can.
test migration_boundary_rejects_signed_state_mismatch() fail {
  let consumed = CheckpointDatumV1 { ..mig_source_datum(), seq: 23 }
  let tx = spend_context(
    [mig_source_input(consumed)],
    [],
    [mig_successor_output(consumed)],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_in(
    MigrateInProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// The same transaction with the signed and consumed projections agreeing is
// accepted, so the control above rejects for the mismatch and not because the
// fixture is unsatisfiable.
test migration_boundary_accepts_matching_signed_state() {
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_in(
    MigrateInProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// INV-254-VALUE — migrate-out is inseparable from its successor.
//
// A controller-authorized exit that burns the source token and creates no
// successor destroys the identity. The burn is exactly the authorized one, so
// only successor composition can refuse this.
test migration_boundary_rejects_migrate_out_without_successor() fail {
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [],
    from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, -1),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// A redirected successor is the same class: the value leaves the family.
test migration_boundary_rejects_migrate_out_redirected_successor() fail {
  let elsewhere = Output {
    ..mig_successor_output(mig_source_datum()),
    address: from_verification_key(owner_vkh),
  }
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [elsewhere],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// The composed migrate-out is accepted, so the two controls above are not
// passing because migrate-out rejects everything.
test migration_boundary_accepts_composed_migrate_out() {
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// Cut by epic ruling NOTE-006 (2026-08-12), sha256
// 1ef670c52897ebdda575805ac8a4fcf011bcc3749a3d5632c6d5c196a588c4d1:
//
//   migration_lifecycle_native_register_is_version_one_no_origin
//   migration_lifecycle_migrated_row_advances_retaining_origin
//   migration_lifecycle_advance_may_not_rewrite_origin
//
// These asserted that a datum-carried generation integer and a stored
// predecessor back-pointer survive ordinary lifecycle transitions. Both
// fields are CUT:
// the script hash already identifies the validator, and the migration
// transaction — spend the predecessor, burn its token, mint the successor,
// atomically — is a more durable lineage record than a datum field no M1
// consumer reads. Audit finding 3 was the sync-gap between that integer and
// the hash, so the cut dissolves the finding rather than repairing it.
//
// This is a ruling-driven feature cut, not a test evasion. The properties
// were genuinely RED against `0e6b445` and were not made to pass; the
// behaviour they demanded is no longer wanted. Their value/replay siblings
// above survive untouched, and those carry 2 of the 3 audit findings.

// The lean lineage edge, at the transaction boundary.
//
// Release identity is the applied successor hash and there is no stored
// back-pointer, so the only thing that ties a successor to its predecessor is
// that this transaction genuinely spends it. These four controls are that
// property; each is paired with the accepting case above, which is what keeps
// them from passing vacuously.

test migration_boundary_rejects_wrong_predecessor_policy() fail {
  // The successor program accepts exactly one predecessor policy. A package
  // naming another family is refused even though a real output is spent.
  let foreign = MigrationAuthorization {
    ..mig_authorization(mig_signed_state()),
    source: MigrationPredecessor {
      predecessor_policy: mig_target_policy,
      predecessor_ref: mig_source_ref(),
    },
  }
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_in(MigrateInProof { authorization: foreign }, tx)
}

test migration_boundary_rejects_wrong_predecessor_outref() fail {
  // The signed output and the consumed output must be the same output.
  let elsewhere = MigrationAuthorization {
    ..mig_authorization(mig_signed_state()),
    source: MigrationPredecessor {
      predecessor_policy: mig_source_policy,
      predecessor_ref: OutputReference {
        transaction_id: mig_vec.fixture_mutant_txid,
        output_index: 1,
      },
    },
  }
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_in(MigrateInProof { authorization: elsewhere }, tx)
}

test migration_boundary_rejects_missing_predecessor_input() fail {
  // Minting a successor while consuming nothing has no lineage at all.
  let tx = spend_context(
    [],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_in(
    MigrateInProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

test migration_boundary_rejects_split_transition() fail {
  // Splitting the move across two transactions is exactly what the atomic
  // edge forbids: this one mints the successor without burning the source,
  // which is what the second half of a split would look like.
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    from_asset(mig_target_policy, mig_vec.fixture_aid_asset_name, 1),
    [],
    interval.everything,
    0,
  )
  run_migrate_in(
    MigrateInProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// ---------------------------------------------------------
// #254 A-002 — paired observer binding on the combined register
// ---------------------------------------------------------

fn register_freeze_spend(tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    Freeze { hunter_pkh: hunter },
    freeze_ref(),
    tx,
  )
}

fn freeze_tx_with_observers(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  withdrawals,
  redeemers,
) -> Transaction {
  let base = freeze_tx(tip, evidence)
  Transaction { ..base, withdrawals, redeemers }
}

test s254_e_register_missing_enforcement_observer_rejects() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let envelope = freeze_envelope(evidence)
  let redeemer: Data = envelope
  let entitlement_credential = Script(entitlement_hash)
  register_freeze_spend(
    freeze_tx_with_observers(
      tip,
      evidence,
      [Pair(entitlement_credential, 0)],
      [Pair(Withdraw(entitlement_credential), redeemer)],
    ),
  )
}

test s254_e_register_missing_entitlement_observer_rejects() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let envelope = freeze_envelope(evidence)
  let redeemer: Data = envelope
  let enforcement_credential = Script(enforcement_hash)
  register_freeze_spend(
    freeze_tx_with_observers(
      tip,
      evidence,
      [Pair(enforcement_credential, 0)],
      [Pair(Withdraw(enforcement_credential), redeemer)],
    ),
  )
}

test s254_e_register_paired_observers_different_reveal_rejects() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let honest = freeze_envelope(evidence)
  let honest_proof = enforcement_proof(evidence, hunter)
  let BountyRevealV1 { commitment_ref, refund_index, .. } = honest_proof.reveal
  let mutant_payload: Data = EnforcementProofV1 {
    ..honest_proof,
    reveal: BountyRevealV1 {
      commitment_ref,
      nonce: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01",
      refund_index,
    },
  }
  let mutant = ObserverEnvelope { claim: honest.claim, payload: mutant_payload }
  expect honest.payload != mutant.payload
  let honest_redeemer: Data = honest
  let mutant_redeemer: Data = mutant
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  register_freeze_spend(
    freeze_tx_with_observers(
      tip,
      evidence,
      [Pair(enforcement_credential, 0), Pair(entitlement_credential, 0)],
      [
        Pair(Withdraw(enforcement_credential), honest_redeemer),
        Pair(Withdraw(entitlement_credential), mutant_redeemer),
      ],
    ),
  )
}

test s254_e_register_paired_observers_different_evidence_rejects() fail {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  let honest = freeze_envelope(evidence)
  let honest_proof = enforcement_proof(evidence, hunter)
  let mutant_payload: Data = EnforcementProofV1 {
    ..honest_proof,
    evidence: EnforcementEvidence { ..evidence, wit_sigs: [] },
  }
  let mutant = ObserverEnvelope { claim: honest.claim, payload: mutant_payload }
  expect honest.payload != mutant.payload
  let honest_redeemer: Data = honest
  let mutant_redeemer: Data = mutant
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  register_freeze_spend(
    freeze_tx_with_observers(
      tip,
      evidence,
      [Pair(enforcement_credential, 0), Pair(entitlement_credential, 0)],
      [
        Pair(Withdraw(enforcement_credential), honest_redeemer),
        Pair(Withdraw(entitlement_credential), mutant_redeemer),
      ],
    ),
  )
}

test s254_e_register_paired_observers_same_envelope_accepts() {
  let tip = enforcement_vec.lag_freeze_tip
  let evidence = enforcement_vec.lag_freeze_wire
  register_freeze_spend(freeze_tx(tip, evidence))
}
