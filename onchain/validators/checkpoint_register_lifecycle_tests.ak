//// #339 — the register-only checkpoint program writes and reads the version 2
//// datum. Register writes `Live`, Advance rotates it and pays the premium,
//// Convict writes `TerminationPending` and pays out; version 1 is refused.
////
//// Every expected amount below is spelled as arithmetic over the Lean's
//// parameters (`Mc`, `D`, `B`, `P`) and the pool, never read back from the
//// code under test. Each refusal is a transaction identical to an accepted
//// one in every respect but the single thing it is about.

use aiken/builtin
use aiken/collection/list
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/primitive/bytearray
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{
  Address, Credential, Script, from_script, from_verification_key,
  with_delegation_key, with_delegation_script,
}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptPurpose,
  Transaction, Withdraw,
}
use cardano_keri/bounty_commitment.{
  BountyAction, BountyCommitment, BountyCommitmentV1, BountyRevealV1,
  BountyScope, CommitmentFamily, CommitmentParameters, ConvictEntitlement,
  commitment_domain, commitment_hash, commitment_preimage, commitment_schema,
  marker_name,
}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/advance_vectors as advance_vec
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, CheckpointDatumV2, KeyMaterial, Live, TerminationPending,
  V1, V2,
}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence}
use cardano_keri/checkpoint/enforcement_vectors as enforcement_vec
use cardano_keri/checkpoint/entitlement.{
  EnforcementProofV1, enforcement_evidence_digest,
}
use cardano_keri/checkpoint/message.{
  SpentCheckpoint, deriveAidAssetName, qb64_aid,
}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint_observer
use checkpoint_register

// ---------------------------------------------------------------------
// The deployment these fixtures run under
// ---------------------------------------------------------------------

const network_id: Int = 1

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

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

/// The Lean parameters, as lovelace.
const mc: Int = 2_000_000

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

const premium: Int = 2_000_000

/// What a live, unfrozen checkpoint holds before its pool.
const floor_unfrozen: Int = 1_007_000_000

/// What a live, frozen checkpoint holds before its pool.
const floor_frozen: Int = 1_002_000_000

/// The registration's upper validity bound, in POSIX milliseconds.
const registered_at: Int = 1_800_000_000_000

const hunter_pkh: ByteArray =
  #"54545454545454545454545454545454545454545454545454545454"

const refund_pkh: ByteArray =
  #"53535353535353535353535353535353535353535353535353535353"

const refund_stake_pkh: ByteArray =
  #"55555555555555555555555555555555555555555555555555555555"

const convictor: ByteArray =
  #"51515151515151515151515151515151515151515151515151515151"

const other_recipient: ByteArray =
  #"52525252525252525252525252525252525252525252525252525252"

test fixture_amounts_are_the_lean_arithmetic() {
  and {
    floor_unfrozen == mc + d_reg + freeze_bond,
    floor_frozen == mc + d_reg,
    bytearray.length(refund_pkh) == 28,
    bytearray.length(refund_stake_pkh) == 28,
    bytearray.length(hunter_pkh) == 28,
    bytearray.length(convictor) == 28,
  }
}

// ---------------------------------------------------------------------
// Wire helpers
// ---------------------------------------------------------------------

/// The ledger bytes of an enterprise key address on the applied network.
fn refund_enterprise_key() -> ByteArray {
  bytearray.concat(#"61", refund_pkh)
}

fn spend_data(index: Int, fields: List<Data>) -> Data {
  builtin.constr_data(index, fields)
}

/// `Advance { payee_output_index }`.
fn advance_redeemer(payee_output_index: Int) -> Data {
  let index: Data = payee_output_index
  spend_data(0, [index])
}

/// `Convict { convictor_pkh, convictor_output_index }`.
fn convict_redeemer(output_index: Int) -> Data {
  let pkh: Data = convictor
  let index: Data = output_index
  spend_data(1, [pkh, index])
}

fn run_mint(redeemer: Data, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.mint(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    redeemer,
    policy,
    tx,
  )
}

fn run_spend(redeemer: Data, own_ref: OutputReference, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    None,
    redeemer,
    own_ref,
    tx,
  )
}

fn keys_of(d: CheckpointDatumV1) -> KeyMaterial {
  KeyMaterial {
    cur_keys: d.cur_keys,
    cur_threshold: d.cur_threshold,
    next_keys: d.next_keys,
    next_threshold: d.next_threshold,
    witnesses: d.witnesses,
    toad: d.toad,
  }
}

/// A live version 2 checkpoint for a key state taken from the shared vectors:
/// `sn` is the key state's sequence number and `epoch` its rotation count.
fn live(
  d: CheckpointDatumV1,
  poisoned: Bool,
  frozen: Bool,
  refund_to: ByteArray,
) -> CheckpointDatumV2 {
  Live {
    aid: qb64_aid(d.cesr_aid),
    sn: d.native_sn,
    epoch: d.seq,
    poisoned,
    frozen,
    born_at: registered_at,
    refund_to,
    keys: keys_of(d),
  }
}

fn pending(d: CheckpointDatumV1) -> CheckpointDatumV2 {
  TerminationPending {
    aid: qb64_aid(d.cesr_aid),
    sn: d.native_sn,
    epoch: d.seq,
    keys: keys_of(d),
  }
}

/// The fields of a `Live` datum, in a record whose fields can be replaced one
/// at a time.
type Parts {
  aid: ByteArray,
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
  keys: KeyMaterial,
}

fn parts(d: CheckpointDatumV2) -> Parts {
  expect Live { aid, sn, epoch, poisoned, frozen, born_at, refund_to, keys } = d
  Parts { aid, sn, epoch, poisoned, frozen, born_at, refund_to, keys }
}

fn from_parts(p: Parts) -> CheckpointDatumV2 {
  Live {
    aid: p.aid,
    sn: p.sn,
    epoch: p.epoch,
    poisoned: p.poisoned,
    frozen: p.frozen,
    born_at: p.born_at,
    refund_to: p.refund_to,
    keys: p.keys,
  }
}

/// The fields of a `TerminationPending` datum.
type PendingParts {
  aid: ByteArray,
  sn: Int,
  epoch: Int,
  keys: KeyMaterial,
}

fn pending_parts(d: CheckpointDatumV2) -> PendingParts {
  expect TerminationPending { aid, sn, epoch, keys } = d
  PendingParts { aid, sn, epoch, keys }
}

fn from_pending_parts(p: PendingParts) -> CheckpointDatumV2 {
  TerminationPending { aid: p.aid, sn: p.sn, epoch: p.epoch, keys: p.keys }
}

fn v2_data(d: CheckpointDatumV2) -> Data {
  let data: Data = V2(d)
  data
}

fn v1_data(d: CheckpointDatumV1) -> Data {
  let data: Data = V1(d)
  data
}

fn token_value(lovelace: Int, name: ByteArray) -> Value {
  from_lovelace(lovelace) |> merge(from_asset(policy, name, 1))
}

fn paid(recipient: ByteArray, lovelace: Int) -> Output {
  Output {
    address: from_verification_key(recipient),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

// ---------------------------------------------------------------------
// V1 V2 — Register
// ---------------------------------------------------------------------

const reg_digest: ByteArray = vec.pos_2key_datum.cesr_aid

const reg_evidence: RegistrationEvidence = vec.pos_2key_evidence

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

/// A validity range whose upper bound is `hi`.
fn upto(hi: Int, inclusive: Bool) -> Interval<Int> {
  Interval {
    lower_bound: IntervalBound {
      bound_type: Finite(hi - 10_000),
      is_inclusive: True,
    },
    upper_bound: IntervalBound {
      bound_type: Finite(hi),
      is_inclusive: inclusive,
    },
  }
}

/// The datum a registration must write for the shared inception vector.
fn registered(refund_to: ByteArray, born_at: Int) -> CheckpointDatumV2 {
  Live {
    aid: qb64_aid(reg_digest),
    sn: 0,
    epoch: 0,
    poisoned: False,
    frozen: False,
    born_at,
    refund_to,
    keys: keys_of(vec.pos_2key_datum),
  }
}

fn register_envelope(evidence: RegistrationEvidence) -> ObserverEnvelope {
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_register,
      checkpoint_policy: policy,
      own_ref: None,
    },
    payload: evidence,
  }
}

/// A registration transaction. `name` is the minted token's name and
/// `proof_name` the burnt hash-proof token's: both honest by default.
fn register_tx(
  datum: Data,
  lovelace: Int,
  name: ByteArray,
  proof_name: ByteArray,
  evidence: RegistrationEvidence,
  range: Interval<Int>,
) -> Transaction {
  let state_output = Output {
    address: from_script(policy),
    value: token_value(lovelace, name),
    datum: InlineDatum(datum),
    reference_script: None,
  }
  let base = spend_context(
    [proof_input(proof_name)],
    [],
    [state_output],
    from_asset(policy, name, 1) |> merge(from_asset(hp_policy, proof_name, -1)),
    [],
    range,
    0,
  )
  let credential = Script(lifecycle_hash)
  let redeemer: Data = register_envelope(evidence)
  Transaction {
    ..base,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

fn run_register_tx(tx: Transaction, evidence: RegistrationEvidence) -> Bool {
  let register: Data = builtin.constr_data(0, [])
  run_mint(register, tx) && checkpoint_observer.observer_lifecycle.withdraw(
    0,
    hp_policy,
    d_reg,
    register_envelope(evidence),
    0,
    tx,
  )
}

fn honest_name() -> ByteArray {
  deriveAidAssetName(reg_digest)
}

fn honest_proof() -> ByteArray {
  proof_token_name(reg_evidence.event_bytes, reg_digest)
}

fn register_with(
  datum: CheckpointDatumV2,
  lovelace: Int,
  range: Interval<Int>,
) -> Bool {
  run_register_tx(
    register_tx(
      v2_data(datum),
      lovelace,
      honest_name(),
      honest_proof(),
      reg_evidence,
      range,
    ),
    reg_evidence,
  )
}

fn register_honest() -> Bool {
  register_with(
    registered(refund_enterprise_key(), registered_at),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_writes_live_with_the_lean_initial_facts() {
  register_honest()
}

test register_accepts_an_inclusive_upper_bound() {
  register_with(
    registered(refund_enterprise_key(), registered_at),
    floor_unfrozen,
    upto(registered_at, True),
  )
}

test register_books_the_excess_as_the_initial_pool() {
  register_with(
    registered(refund_enterprise_key(), registered_at),
    floor_unfrozen + 17,
    upto(registered_at, False),
  )
}

test register_refuses_a_carrier_short_by_one_lovelace() fail {
  register_with(
    registered(refund_enterprise_key(), registered_at),
    floor_unfrozen - 1,
    upto(registered_at, False),
  )
}

test register_refuses_born_at_other_than_the_upper_bound() fail {
  register_with(
    registered(refund_enterprise_key(), registered_at + 1),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_born_at_at_the_lower_bound() fail {
  register_with(
    registered(refund_enterprise_key(), registered_at - 10_000),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_an_unbounded_upper_bound() fail {
  register_with(
    registered(refund_enterprise_key(), registered_at),
    floor_unfrozen,
    interval.after(registered_at - 10_000),
  )
}

test register_refuses_a_nonzero_sn() fail {
  let datum = registered(refund_enterprise_key(), registered_at)
  register_with(
    from_parts(Parts { ..parts(datum), sn: 1 }),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_a_nonzero_epoch() fail {
  let datum = registered(refund_enterprise_key(), registered_at)
  register_with(
    from_parts(Parts { ..parts(datum), epoch: 1 }),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_a_poisoned_start() fail {
  let datum = registered(refund_enterprise_key(), registered_at)
  register_with(
    from_parts(Parts { ..parts(datum), poisoned: True }),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_a_frozen_start() fail {
  let datum = registered(refund_enterprise_key(), registered_at)
  register_with(
    from_parts(Parts { ..parts(datum), frozen: True }),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_a_termination_pending_start() fail {
  register_with(
    pending(vec.pos_2key_datum),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_keys_that_are_not_well_formed() fail {
  let datum = registered(refund_enterprise_key(), registered_at)
  let keys = parts(datum).keys
  register_with(
    from_parts(
      Parts {
        ..parts(datum),
        keys: KeyMaterial { ..keys, toad: keys.toad + 5 },
      },
    ),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

fn register_with_aid_text(text: ByteArray) -> Bool {
  let datum = registered(refund_enterprise_key(), registered_at)
  register_with(
    from_parts(Parts { ..parts(datum), aid: text }),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_accepts_the_aid_text_the_event_carries() {
  register_with_aid_text(qb64_aid(reg_digest))
}

test register_refuses_an_aid_text_one_character_short() fail {
  register_with_aid_text(bytearray.drop(qb64_aid(reg_digest), 1))
}

test register_refuses_an_aid_text_one_character_long() fail {
  register_with_aid_text(bytearray.concat(qb64_aid(reg_digest), "A"))
}

test register_refuses_an_aid_with_another_derivation_code() fail {
  register_with_aid_text(
    bytearray.push(bytearray.drop(qb64_aid(reg_digest), 1), 68),
  )
}

test register_refuses_an_aid_with_a_character_outside_base64url() fail {
  register_with_aid_text(
    bytearray.concat(bytearray.take(qb64_aid(reg_digest), 20), "+")
      |> bytearray.concat(bytearray.drop(qb64_aid(reg_digest), 21)),
  )
}

test register_refuses_an_aid_whose_padding_is_not_zero() fail {
  // The second character stands for the top bits of the byte that must be
  // zero: 'Q' = 16 puts a one in them.
  register_with_aid_text(
    bytearray.take(qb64_aid(reg_digest), 1)
      |> bytearray.concat("Q")
      |> bytearray.concat(bytearray.drop(qb64_aid(reg_digest), 2)),
  )
}

test register_refuses_an_aid_the_event_does_not_carry() fail {
  // A well formed AID of another digest, with the token and the hash proof
  // honestly derived for that other digest: only the event's `i` differs.
  let other = enforcement_vec.fork_convict_tip.cesr_aid
  let datum = registered(refund_enterprise_key(), registered_at)
  run_register_tx(
    register_tx(
      v2_data(from_parts(Parts { ..parts(datum), aid: qb64_aid(other) })),
      floor_unfrozen,
      deriveAidAssetName(other),
      proof_token_name(reg_evidence.event_bytes, other),
      reg_evidence,
      upto(registered_at, False),
    ),
    reg_evidence,
  )
}

test register_names_the_token_over_the_raw_digest_not_the_text() fail {
  // The same registration with the token named over the 44 text bytes.
  let text_name = deriveAidAssetName(qb64_aid(reg_digest))
  expect text_name != honest_name()
  run_register_tx(
    register_tx(
      v2_data(registered(refund_enterprise_key(), registered_at)),
      floor_unfrozen,
      text_name,
      honest_proof(),
      reg_evidence,
      upto(registered_at, False),
    ),
    reg_evidence,
  )
}

test register_burns_the_hash_proof_named_over_the_raw_digest() fail {
  let text_proof = proof_token_name(
    reg_evidence.event_bytes,
    qb64_aid(reg_digest),
  )
  expect text_proof != honest_proof()
  run_register_tx(
    register_tx(
      v2_data(registered(refund_enterprise_key(), registered_at)),
      floor_unfrozen,
      honest_name(),
      text_proof,
      reg_evidence,
      upto(registered_at, False),
    ),
    reg_evidence,
  )
}

test register_refuses_a_version_1_datum() fail {
  let v1 = vec.pos_2key_datum
  run_register_tx(
    register_tx(
      v1_data(v1),
      floor_unfrozen,
      honest_name(),
      honest_proof(),
      reg_evidence,
      upto(registered_at, False),
    ),
    reg_evidence,
  )
}

// ---------------------------------------------------------------------
// V2 — refund_to is a payable address, fixed for life
// ---------------------------------------------------------------------

fn register_refund(refund_to: ByteArray) -> Bool {
  register_with(
    registered(refund_to, registered_at),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test refund_accepts_a_base_address_of_two_keys() {
  register_refund(
    #"01" |> bytearray.concat(refund_pkh) |> bytearray.concat(refund_stake_pkh),
  )
}

test refund_accepts_a_base_address_of_a_script_and_a_key() {
  register_refund(
    #"11" |> bytearray.concat(refund_pkh) |> bytearray.concat(refund_stake_pkh),
  )
}

test refund_accepts_a_base_address_of_a_key_and_a_script() {
  register_refund(
    #"21" |> bytearray.concat(refund_pkh) |> bytearray.concat(refund_stake_pkh),
  )
}

test refund_accepts_a_base_address_of_two_scripts() {
  register_refund(
    #"31" |> bytearray.concat(refund_pkh) |> bytearray.concat(refund_stake_pkh),
  )
}

test refund_accepts_an_enterprise_script_address() {
  register_refund(bytearray.concat(#"71", refund_pkh))
}

test refund_refuses_a_pointer_address() fail {
  register_refund(
    bytearray.concat(#"41", refund_pkh) |> bytearray.concat(#"010203"),
  )
}

test refund_refuses_a_script_pointer_address() fail {
  register_refund(
    bytearray.concat(#"51", refund_pkh) |> bytearray.concat(#"010203"),
  )
}

test refund_refuses_a_byron_address() fail {
  register_refund(bytearray.concat(#"82", refund_pkh))
}

test refund_refuses_a_reward_address() fail {
  register_refund(bytearray.concat(#"e1", refund_pkh))
}

test refund_refuses_an_address_of_the_other_network() fail {
  register_refund(bytearray.concat(#"60", refund_pkh))
}

test refund_refuses_a_base_address_of_the_other_network() fail {
  register_refund(
    #"00" |> bytearray.concat(refund_pkh) |> bytearray.concat(refund_stake_pkh),
  )
}

test refund_refuses_an_enterprise_address_one_byte_short() fail {
  register_refund(bytearray.concat(#"61", bytearray.take(refund_pkh, 27)))
}

test refund_refuses_an_enterprise_address_one_byte_long() fail {
  register_refund(
    bytearray.concat(#"61", refund_pkh) |> bytearray.concat(#"00"),
  )
}

test refund_refuses_a_base_address_one_byte_short() fail {
  register_refund(
    #"01"
      |> bytearray.concat(refund_pkh)
      |> bytearray.concat(bytearray.take(refund_stake_pkh, 27)),
  )
}

test refund_refuses_an_empty_address() fail {
  register_refund(#"")
}

// ---------------------------------------------------------------------
// V3 — Advance writes Live.rotated with the premium
// ---------------------------------------------------------------------

const spent: SpentCheckpoint = advance_vec.pos_adv_wit_2key_spent

const created: CheckpointDatumV1 = advance_vec.pos_adv_wit_2key_created

const adv_evidence: AdvanceEvidence = advance_vec.pos_adv_wit_2key_evidence

fn adv_old_v1() -> CheckpointDatumV1 {
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

fn adv_old(poisoned: Bool, frozen: Bool) -> CheckpointDatumV2 {
  live(adv_old_v1(), poisoned, frozen, refund_enterprise_key())
}

/// The successor the rotation must write: the rotation's key state, the
/// epoch one higher, no poison, everything else copied.
fn adv_new(frozen: Bool) -> CheckpointDatumV2 {
  live(created, False, frozen, refund_enterprise_key())
}

fn adv_ref() -> OutputReference {
  out_ref(spent.txid, spent.index)
}

fn advance_envelope() -> ObserverEnvelope {
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_advance,
      checkpoint_policy: policy,
      own_ref: Some(adv_ref()),
    },
    payload: adv_evidence,
  }
}

/// A rotation: the spent output holds `input_lovelace`, the successor
/// `successor_lovelace`, and `others` follow the successor in the outputs.
fn advance_tx(
  old: Data,
  new: Data,
  input_lovelace: Int,
  successor_lovelace: Int,
  others: List<Output>,
) -> Transaction {
  let own_input = input_at(
    adv_ref(),
    Output {
      address: from_script(policy),
      value: token_value(input_lovelace, spent.aid_asset_name),
      datum: InlineDatum(old),
      reference_script: None,
    },
  )
  let successor = Output {
    address: from_script(policy),
    value: token_value(successor_lovelace, spent.aid_asset_name),
    datum: InlineDatum(new),
    reference_script: None,
  }
  let base = spend_context(
    [own_input],
    [],
    [successor, ..others],
    zero,
    [],
    interval.everything,
    0,
  )
  let credential = Script(advance_hash)
  let redeemer: Data = advance_envelope()
  Transaction {
    ..base,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

fn run_advance(payee_output_index: Int, tx: Transaction) -> Bool {
  run_spend(advance_redeemer(payee_output_index), adv_ref(), tx) && checkpoint_observer.observer_advance.withdraw(
    0,
    advance_envelope(),
    0,
    tx,
  )
}

/// An honest rotation of an unfrozen checkpoint holding `pool` above its floor.
fn rotate_unfrozen(
  pool: Int,
  successor_lovelace: Int,
  others: List<Output>,
) -> Bool {
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(False, False)),
      v2_data(adv_new(False)),
      floor_unfrozen + pool,
      successor_lovelace,
      others,
    ),
  )
}

test advance_pays_the_premium_when_the_pool_covers_it() {
  rotate_unfrozen(
    3_000_000,
    floor_unfrozen + 1_000_000,
    [paid(hunter_pkh, premium)],
  )
}

test advance_pays_the_premium_when_the_pool_equals_it() {
  rotate_unfrozen(premium, floor_unfrozen, [paid(hunter_pkh, premium)])
}

test advance_pays_more_than_the_premium_to_the_payee() {
  rotate_unfrozen(
    3_000_000,
    floor_unfrozen + 1_000_000,
    [paid(hunter_pkh, premium + 5)],
  )
}

test advance_pays_nothing_when_the_pool_is_below_the_premium() {
  rotate_unfrozen(premium - 1, floor_unfrozen + premium - 1, [])
}

test advance_with_an_empty_pool_pays_nothing() {
  rotate_unfrozen(0, floor_unfrozen, [])
}

test advance_clears_the_poison() {
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(True, False)),
      v2_data(adv_new(False)),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_of_a_frozen_checkpoint_keeps_it_frozen_and_holds_no_bond() {
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(False, True)),
      v2_data(adv_new(True)),
      floor_frozen + 3_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_refuses_a_premium_paid_one_lovelace_short() fail {
  rotate_unfrozen(
    3_000_000,
    floor_unfrozen + 1_000_000,
    [paid(hunter_pkh, premium - 1)],
  )
}

test advance_refuses_a_paid_rotation_that_does_not_debit_the_pool() fail {
  rotate_unfrozen(
    3_000_000,
    floor_unfrozen + 3_000_000,
    [paid(hunter_pkh, premium)],
  )
}

test advance_refuses_a_debit_when_the_pool_is_below_the_premium() fail {
  // Nothing is paid, so nothing may leave: the successor holds the same pool.
  rotate_unfrozen(premium - 1, floor_unfrozen, [])
}

test advance_refuses_a_successor_one_lovelace_above() fail {
  rotate_unfrozen(
    3_000_000,
    floor_unfrozen + 1_000_001,
    [paid(hunter_pkh, premium)],
  )
}

test advance_refuses_a_successor_one_lovelace_below() fail {
  rotate_unfrozen(
    3_000_000,
    floor_unfrozen + 999_999,
    [paid(hunter_pkh, premium)],
  )
}

test advance_refuses_an_input_below_its_floor() fail {
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(False, False)),
      v2_data(adv_new(False)),
      floor_unfrozen - 1,
      floor_unfrozen - 1,
      [],
    ),
  )
}

test advance_refuses_a_payee_that_is_the_successor_itself() fail {
  run_advance(
    0,
    advance_tx(
      v2_data(adv_old(False, False)),
      v2_data(adv_new(False)),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [],
    ),
  )
}

test advance_refuses_a_paid_rotation_with_no_payee_output() fail {
  run_advance(
    7,
    advance_tx(
      v2_data(adv_old(False, False)),
      v2_data(adv_new(False)),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

fn rotate_into(new: CheckpointDatumV2) -> Bool {
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(False, False)),
      v2_data(new),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_writes_the_successor_the_tests_below_perturb() {
  rotate_into(adv_new(False))
}

test advance_refuses_a_changed_aid() fail {
  let base = parts(adv_new(False))
  rotate_into(
    from_parts(
      Parts { ..base, aid: qb64_aid(enforcement_vec.fork_convict_tip.cesr_aid) },
    ),
  )
}

test advance_refuses_a_changed_born_at() fail {
  let base = parts(adv_new(False))
  rotate_into(from_parts(Parts { ..base, born_at: registered_at + 1 }))
}

test advance_refuses_a_changed_refund_address() fail {
  let base = parts(adv_new(False))
  rotate_into(
    from_parts(
      Parts { ..base, refund_to: bytearray.concat(#"61", other_recipient) },
    ),
  )
}

test advance_refuses_a_changed_frozen_flag() fail {
  // The successor holds exactly what its own (frozen) facts say, so only the
  // copy rule can refuse it.
  let base = parts(adv_new(False))
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(False, False)),
      v2_data(from_parts(Parts { ..base, frozen: True })),
      floor_unfrozen + 3_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_refuses_a_poisoned_successor() fail {
  let base = parts(adv_new(False))
  rotate_into(from_parts(Parts { ..base, poisoned: True }))
}

test advance_refuses_an_epoch_that_skips() fail {
  let base = parts(adv_new(False))
  rotate_into(from_parts(Parts { ..base, epoch: base.epoch + 1 }))
}

test advance_refuses_a_sequence_number_that_does_not_move() fail {
  let base = parts(adv_new(False))
  rotate_into(from_parts(Parts { ..base, sn: parts(adv_old(False, False)).sn }))
}

test advance_refuses_a_termination_pending_successor() fail {
  rotate_into(pending(created))
}

test advance_refuses_a_version_1_successor() fail {
  run_advance(
    1,
    advance_tx(
      v2_data(adv_old(False, False)),
      v1_data(created),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_refuses_a_version_1_input() fail {
  // The accepted paid rotation with the spent datum alone replaced by the
  // version 1 record of the same key state.
  run_advance(
    1,
    advance_tx(
      v1_data(adv_old_v1()),
      v2_data(adv_new(False)),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_refuses_a_termination_pending_input() fail {
  // The accepted paid rotation with the spent datum alone replaced by the
  // pending termination of the same key state.
  run_advance(
    1,
    advance_tx(
      v2_data(pending(adv_old_v1())),
      v2_data(adv_new(False)),
      floor_unfrozen + 3_000_000,
      floor_unfrozen + 1_000_000,
      [paid(hunter_pkh, premium)],
    ),
  )
}

test advance_refuses_a_missing_advance_observer() fail {
  let tx = advance_tx(
    v2_data(adv_old(False, False)),
    v2_data(adv_new(False)),
    floor_unfrozen + 3_000_000,
    floor_unfrozen + 1_000_000,
    [paid(hunter_pkh, premium)],
  )
  run_spend(
    advance_redeemer(1),
    adv_ref(),
    Transaction { ..tx, withdrawals: [], redeemers: [] },
  )
}

// ---------------------------------------------------------------------
// V4 V5 — Convict writes TerminationPending and pays out
// ---------------------------------------------------------------------

const commit_policy: PolicyId =
  #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

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

/// Attach the convictor's matured reservation: the validity range reaches the
/// maturity slot, the reservation is spent, its marker burnt, and its deposit
/// returned to the convictor in the last output.
fn with_reservation(
  base: Transaction,
  script: PolicyId,
  commitment: BountyCommitment,
) -> Transaction {
  let BountyCommitmentV1 { marker, payee_pkh, scope, .. } = commitment
  Transaction {
    ..base,
    validity_range: Interval {
      lower_bound: IntervalBound { bound_type: Finite(1), is_inclusive: True },
      upper_bound: IntervalBound {
        bound_type: Finite(scope.expires_at),
        is_inclusive: True,
      },
    },
    inputs: list.concat(base.inputs, [commitment_input_at(script, commitment)]),
    outputs: list.concat(base.outputs, [paid(payee_pkh, applied_deposit)]),
    mint: base.mint |> merge(from_asset(script, marker, -1)),
  }
}

fn reveal_for() -> BountyRevealV1 {
  BountyRevealV1 { commitment_ref, nonce: commit_nonce, refund_index: 0 }
}

fn convict_ref() -> OutputReference {
  out_ref(seed_tx_id, 15)
}

fn convict_envelope(evidence: EnforcementEvidence) -> ObserverEnvelope {
  convict_envelope_naming(convict_ref(), evidence)
}

/// The envelope whose claim names the input `named`.
fn convict_envelope_naming(
  named: OutputReference,
  evidence: EnforcementEvidence,
) -> ObserverEnvelope {
  let payload: Data = EnforcementProofV1 {
    evidence,
    payee_pkh: convictor,
    reveal: reveal_for(),
  }
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_convict,
      checkpoint_policy: policy,
      own_ref: Some(named),
    },
    payload,
  }
}

const tip: CheckpointDatumV1 = enforcement_vec.fork_witnessed_convict_tip

const wire: EnforcementEvidence = enforcement_vec.fork_witnessed_convict_wire

fn tip_name() -> ByteArray {
  deriveAidAssetName(tip.cesr_aid)
}

/// A conviction of the checkpoint holding `input_lovelace`: the outputs are
/// given in order, the reservation's deposit return follows them.
fn convict_tx(
  input_datum: Data,
  input_lovelace: Int,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  convict_tx_of(tip, wire, input_datum, input_lovelace, outputs, mint)
}

fn convict_tx_of(
  tip_of: CheckpointDatumV1,
  wire_of: EnforcementEvidence,
  input_datum: Data,
  input_lovelace: Int,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  convict_tx_naming(
    convict_ref(),
    tip_of,
    wire_of,
    input_datum,
    input_lovelace,
    outputs,
    mint,
  )
}

/// The same, for a conviction of the checkpoint with key state `tip_of`
/// under the evidence `wire_of`.
fn convict_tx_naming(
  named: OutputReference,
  tip_of: CheckpointDatumV1,
  wire_of: EnforcementEvidence,
  input_datum: Data,
  input_lovelace: Int,
  outputs: List<Output>,
  mint: Value,
) -> Transaction {
  let own_input = input_at(
    convict_ref(),
    Output {
      address: from_script(policy),
      value: token_value(input_lovelace, deriveAidAssetName(tip_of.cesr_aid)),
      datum: InlineDatum(input_datum),
      reference_script: None,
    },
  )
  let base = spend_context(
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
  let observer_redeemer: Data = convict_envelope_naming(named, wire_of)
  with_reservation(
    Transaction {
      ..base,
      withdrawals: [
        Pair(enforcement_credential, 0), Pair(entitlement_credential, 0),
      ],
      redeemers: [
        Pair(Withdraw(enforcement_credential), observer_redeemer),
        Pair(Withdraw(entitlement_credential), observer_redeemer),
      ],
    },
    commit_policy,
    commitment_for(named, ConvictEntitlement, convictor, wire_of),
  )
}

fn run_convict(convictor_output_index: Int, tx: Transaction) -> Bool {
  let envelope = convict_envelope(wire)
  run_spend(convict_redeemer(convictor_output_index), convict_ref(), tx) && checkpoint_observer.observer_enforcement.withdraw(
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

fn pending_output(datum: Data, lovelace: Int, name: ByteArray) -> Output {
  Output {
    address: from_script(policy),
    value: token_value(lovelace, name),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

const convict_pool: Int = 3_000_000

/// The honest conviction of an unfrozen checkpoint holding `convict_pool`:
/// the pending output keeps the token and `Mc`, the convictor receives `D`,
/// the refund address receives `B` and the pool.
fn convict_unfrozen(pending_datum: Data, outputs: List<Output>) -> Bool {
  convict_unfrozen_from(
    v2_data(live(tip, False, False, refund_enterprise_key())),
    pending_datum,
    outputs,
  )
}

/// The same conviction of an unfrozen checkpoint, the spent datum given.
fn convict_unfrozen_from(
  input_datum: Data,
  pending_datum: Data,
  outputs: List<Output>,
) -> Bool {
  run_convict(
    1,
    convict_tx(
      input_datum,
      floor_unfrozen + convict_pool,
      [pending_output(pending_datum, mc, tip_name()), ..outputs],
      zero,
    ),
  )
}

fn honest_pending() -> Data {
  v2_data(pending(tip))
}

fn honest_payouts() -> List<Output> {
  [paid(convictor, d_reg), paid(refund_pkh, freeze_bond + convict_pool)]
}

test convict_writes_termination_pending_and_pays_both_parties() {
  convict_unfrozen(honest_pending(), honest_payouts())
}

test convict_refunds_the_surplus_to_the_refund_address() {
  convict_unfrozen(
    honest_pending(),
    [paid(convictor, d_reg), paid(refund_pkh, freeze_bond + convict_pool + 9)],
  )
}

test convict_of_a_frozen_checkpoint_refunds_only_the_pool() {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, True, refund_enterprise_key())),
      floor_frozen + convict_pool,
      [
        pending_output(honest_pending(), mc, tip_name()),
        paid(convictor, d_reg),
        paid(refund_pkh, convict_pool),
      ],
      zero,
    ),
  )
}

test convict_of_a_poisoned_checkpoint_pays_the_same() {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, True, False, refund_enterprise_key())),
      floor_unfrozen + convict_pool,
      [pending_output(honest_pending(), mc, tip_name())]
        |> list.concat(honest_payouts()),
      zero,
    ),
  )
}

test convict_refunds_a_script_base_address_by_its_ledger_bytes() {
  let refund_to = #"31"
    |> bytearray.concat(refund_pkh)
    |> bytearray.concat(refund_stake_pkh)
  let refund_address = from_script(refund_pkh)
    |> with_delegation_script(refund_stake_pkh)
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_to)),
      floor_unfrozen + convict_pool,
      [
        pending_output(honest_pending(), mc, tip_name()),
        paid(convictor, d_reg),
        Output {
          address: refund_address,
          value: from_lovelace(freeze_bond + convict_pool),
          datum: NoDatum,
          reference_script: None,
        },
      ],
      zero,
    ),
  )
}

test convict_refunds_a_key_base_address_by_its_ledger_bytes() {
  let refund_to = #"01"
    |> bytearray.concat(refund_pkh)
    |> bytearray.concat(refund_stake_pkh)
  let refund_address = from_verification_key(refund_pkh)
    |> with_delegation_key(refund_stake_pkh)
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_to)),
      floor_unfrozen + convict_pool,
      [
        pending_output(honest_pending(), mc, tip_name()),
        paid(convictor, d_reg),
        Output {
          address: refund_address,
          value: from_lovelace(freeze_bond + convict_pool),
          datum: NoDatum,
          reference_script: None,
        },
      ],
      zero,
    ),
  )
}

test convict_refuses_a_burnt_token() fail {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_enterprise_key())),
      floor_unfrozen + convict_pool,
      honest_payouts(),
      from_asset(policy, tip_name(), -1),
    ),
  )
}

test convict_refuses_a_token_that_leaves_the_checkpoint_address() fail {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_enterprise_key())),
      floor_unfrozen + convict_pool,
      [
        Output {
          ..pending_output(honest_pending(), mc, tip_name()),
          address: from_verification_key(other_recipient),
        },
        ..honest_payouts()
      ],
      zero,
    ),
  )
}

test convict_refuses_a_pending_output_holding_one_lovelace_more() fail {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_enterprise_key())),
      floor_unfrozen + convict_pool,
      [pending_output(honest_pending(), mc + 1, tip_name()), ..honest_payouts()],
      zero,
    ),
  )
}

test convict_refuses_a_pending_output_holding_one_lovelace_less() fail {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_enterprise_key())),
      floor_unfrozen + convict_pool,
      [pending_output(honest_pending(), mc - 1, tip_name()), ..honest_payouts()],
      zero,
    ),
  )
}

fn convict_into(datum: CheckpointDatumV2) -> Bool {
  convict_unfrozen(v2_data(datum), honest_payouts())
}

test convict_refuses_a_pending_datum_of_another_aid() fail {
  let base = pending_parts(pending(tip))
  convict_into(
    from_pending_parts(
      PendingParts {
        ..base,
        aid: qb64_aid(enforcement_vec.fork_convict_tip.cesr_aid),
      },
    ),
  )
}

test convict_refuses_a_pending_datum_with_another_sn() fail {
  let base = pending_parts(pending(tip))
  convict_into(from_pending_parts(PendingParts { ..base, sn: base.sn + 1 }))
}

test convict_refuses_a_pending_datum_with_another_epoch() fail {
  let base = pending_parts(pending(tip))
  convict_into(
    from_pending_parts(PendingParts { ..base, epoch: base.epoch + 1 }),
  )
}

test convict_refuses_a_pending_datum_with_other_keys() fail {
  let base = pending_parts(pending(tip))
  convict_into(
    from_pending_parts(
      PendingParts {
        ..base,
        keys: KeyMaterial { ..base.keys, toad: base.keys.toad + 1 },
      },
    ),
  )
}

test convict_refuses_a_live_datum_on_the_output() fail {
  convict_into(live(tip, False, False, refund_enterprise_key()))
}

test convict_refuses_a_version_1_datum_on_the_output() fail {
  convict_unfrozen(v1_data(tip), honest_payouts())
}

test convict_refuses_a_convictor_paid_one_lovelace_short() fail {
  convict_unfrozen(
    honest_pending(),
    [paid(convictor, d_reg - 1), paid(refund_pkh, freeze_bond + convict_pool)],
  )
}

test convict_refuses_a_convictor_paid_one_lovelace_over() fail {
  convict_unfrozen(
    honest_pending(),
    [paid(convictor, d_reg + 1), paid(refund_pkh, freeze_bond + convict_pool)],
  )
}

test convict_refuses_a_refund_one_lovelace_short() fail {
  convict_unfrozen(
    honest_pending(),
    [paid(convictor, d_reg), paid(refund_pkh, freeze_bond + convict_pool - 1)],
  )
}

test convict_refuses_a_refund_to_another_address() fail {
  convict_unfrozen(
    honest_pending(),
    [paid(convictor, d_reg), paid(other_recipient, freeze_bond + convict_pool)],
  )
}

test convict_refuses_a_missing_refund() fail {
  convict_unfrozen(honest_pending(), [paid(convictor, d_reg)])
}

test convict_refuses_to_pay_the_refund_from_the_convictors_output() fail {
  // One output at the convictor's address cannot serve both payouts.
  let refund_to = bytearray.concat(#"61", convictor)
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, False, refund_to)),
      floor_unfrozen + convict_pool,
      [
        pending_output(honest_pending(), mc, tip_name()),
        paid(convictor, d_reg + freeze_bond + convict_pool),
      ],
      zero,
    ),
  )
}

test convict_refuses_a_version_1_input() fail {
  // The accepted conviction with the spent datum alone replaced by the
  // version 1 record of the same key state.
  convict_unfrozen_from(v1_data(tip), honest_pending(), honest_payouts())
}

test convict_refuses_a_termination_pending_input() fail {
  // The accepted conviction with the spent datum alone replaced by the
  // pending termination of the same key state.
  convict_unfrozen_from(honest_pending(), honest_pending(), honest_payouts())
}

test the_burning_mint_redeemer_is_gone() fail {
  // `ConvictBurn { checkpoint_ref }`, constructor 1 of the former mint
  // redeemer.
  let ref: Data = convict_ref()
  run_mint(
    builtin.constr_data(1, [ref]),
    convict_tx(
      v2_data(live(tip, False, False, refund_enterprise_key())),
      floor_unfrozen + convict_pool,
      honest_payouts(),
      from_asset(policy, tip_name(), -1),
    ),
  )
}

// ---------------------------------------------------------------------
// One payee or refund output cannot be counted for two checkpoints
// ---------------------------------------------------------------------

const spent_b: SpentCheckpoint = advance_vec.pos_adv_wit_7key_spent

const created_b: CheckpointDatumV1 = advance_vec.pos_adv_wit_7key_created

fn rotation_io(
  ref: OutputReference,
  name: ByteArray,
  old: CheckpointDatumV2,
  new: CheckpointDatumV2,
  input_lovelace: Int,
  successor_lovelace: Int,
) -> (Input, Output) {
  (
    input_at(
      ref,
      Output {
        address: from_script(policy),
        value: token_value(input_lovelace, name),
        datum: InlineDatum(v2_data(old)),
        reference_script: None,
      },
    ),
    Output {
      address: from_script(policy),
      value: token_value(successor_lovelace, name),
      datum: InlineDatum(v2_data(new)),
      reference_script: None,
    },
  )
}

// Two checkpoints rotate in one transaction, each with a premium to pay and
// each pointing at the one output that pays a single premium. The advance
// observer is withdrawn once, for the first checkpoint's rotation.
test two_rotations_cannot_share_one_payee_output() fail {
  let ref_b = out_ref(spent_b.txid, 5)
  let old_b_v1 = CheckpointDatumV1 {
    ..adv_old_v1(),
    cesr_aid: spent_b.cesr_aid,
  }
  let (input_a, successor_a) = rotation_io(
    adv_ref(),
    spent.aid_asset_name,
    adv_old(False, False),
    adv_new(False),
    floor_unfrozen + 3_000_000,
    floor_unfrozen + 1_000_000,
  )
  let (input_b, successor_b) = rotation_io(
    ref_b,
    spent_b.aid_asset_name,
    live(old_b_v1, False, False, refund_enterprise_key()),
    live(created_b, False, False, refund_enterprise_key()),
    floor_unfrozen + 3_000_000,
    floor_unfrozen + 1_000_000,
  )
  let base = advance_tx(
    v2_data(adv_old(False, False)),
    v2_data(adv_new(False)),
    floor_unfrozen + 3_000_000,
    floor_unfrozen + 1_000_000,
    [],
  )
  let tx = Transaction {
    ..base,
    inputs: [input_a, input_b],
    outputs: [successor_a, successor_b, paid(hunter_pkh, premium)],
  }
  run_spend(advance_redeemer(2), adv_ref(), tx) && run_spend(
    advance_redeemer(2),
    ref_b,
    tx,
  ) && checkpoint_observer.observer_advance.withdraw(
    0,
    advance_envelope(),
    0,
    tx,
  )
}

// Two checkpoints are convicted in one transaction with one refund output
// that holds what a single refund requires. The enforcement and entitlement
// observers are withdrawn once, for the first checkpoint's conviction.
test two_convictions_cannot_share_one_refund_output() fail {
  let ref_b = out_ref(seed_tx_id, 16)
  let tip_b = enforcement_vec.fork_convict_tip
  let name_b = deriveAidAssetName(tip_b.cesr_aid)
  let base = convict_tx(
    v2_data(live(tip, False, False, refund_enterprise_key())),
    floor_unfrozen + convict_pool,
    [
      pending_output(honest_pending(), mc, tip_name()),
      pending_output(v2_data(pending(tip_b)), mc, name_b),
      paid(convictor, d_reg),
      paid(convictor, d_reg),
      paid(refund_pkh, freeze_bond + convict_pool),
    ],
    zero,
  )
  let input_b = input_at(
    ref_b,
    Output {
      address: from_script(policy),
      value: token_value(floor_unfrozen + convict_pool, name_b),
      datum: InlineDatum(
        v2_data(live(tip_b, False, False, refund_enterprise_key())),
      ),
      reference_script: None,
    },
  )
  let tx = Transaction { ..base, inputs: [input_b, ..base.inputs] }
  let envelope = convict_envelope(wire)
  run_spend(convict_redeemer(2), convict_ref(), tx) && run_spend(
    convict_redeemer(3),
    ref_b,
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

// ---------------------------------------------------------------------
// The two observers a conviction composes
// ---------------------------------------------------------------------

fn honest_convict_tx() -> Transaction {
  convict_tx(
    v2_data(live(tip, False, False, refund_enterprise_key())),
    floor_unfrozen + convict_pool,
    [pending_output(honest_pending(), mc, tip_name()), ..honest_payouts()],
    zero,
  )
}

fn spend_convict(tx: Transaction) -> Bool {
  run_spend(convict_redeemer(1), convict_ref(), tx)
}

fn with_observers(
  tx: Transaction,
  withdrawals: List<Pair<Credential, Int>>,
  redeemers: List<Pair<ScriptPurpose, Data>>,
) -> Transaction {
  Transaction { ..tx, withdrawals, redeemers }
}

test convict_accepts_paired_observers_with_the_same_envelope() {
  spend_convict(honest_convict_tx())
}

test convict_refuses_a_missing_enforcement_observer() fail {
  let redeemer: Data = convict_envelope(wire)
  let entitlement_credential = Script(entitlement_hash)
  spend_convict(
    with_observers(
      honest_convict_tx(),
      [Pair(entitlement_credential, 0)],
      [Pair(Withdraw(entitlement_credential), redeemer)],
    ),
  )
}

test convict_refuses_a_missing_entitlement_observer() fail {
  let redeemer: Data = convict_envelope(wire)
  let enforcement_credential = Script(enforcement_hash)
  spend_convict(
    with_observers(
      honest_convict_tx(),
      [Pair(enforcement_credential, 0)],
      [Pair(Withdraw(enforcement_credential), redeemer)],
    ),
  )
}

fn spend_with_two_envelopes(
  enforcement_envelope: ObserverEnvelope,
  entitlement_envelope: ObserverEnvelope,
) -> Bool {
  let enforcement_redeemer: Data = enforcement_envelope
  let entitlement_redeemer: Data = entitlement_envelope
  let enforcement_credential = Script(enforcement_hash)
  let entitlement_credential = Script(entitlement_hash)
  spend_convict(
    with_observers(
      honest_convict_tx(),
      [Pair(enforcement_credential, 0), Pair(entitlement_credential, 0)],
      [
        Pair(Withdraw(enforcement_credential), enforcement_redeemer),
        Pair(Withdraw(entitlement_credential), entitlement_redeemer),
      ],
    ),
  )
}

test convict_refuses_paired_observers_with_different_reveals() fail {
  let honest = convict_envelope(wire)
  expect proof: EnforcementProofV1 = honest.payload
  let other_reveal = BountyRevealV1 {
    ..proof.reveal,
    nonce: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01",
  }
  let changed_payload: Data = EnforcementProofV1 {
    ..proof,
    reveal: other_reveal,
  }
  let changed = ObserverEnvelope {
    claim: honest.claim,
    payload: changed_payload,
  }
  expect honest.payload != changed.payload
  spend_with_two_envelopes(honest, changed)
}

test convict_refuses_paired_observers_with_different_evidence() fail {
  let honest = convict_envelope(wire)
  expect proof: EnforcementProofV1 = honest.payload
  let changed_payload: Data = EnforcementProofV1 {
    ..proof,
    evidence: EnforcementEvidence { ..wire, wit_sigs: [] },
  }
  let changed = ObserverEnvelope {
    claim: honest.claim,
    payload: changed_payload,
  }
  expect honest.payload != changed.payload
  spend_with_two_envelopes(honest, changed)
}

test enforcement_observer_accepts_the_witnessed_fork_over_a_live_checkpoint() {
  checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    convict_envelope(wire),
    0,
    honest_convict_tx(),
  )
}

test enforcement_observer_refuses_a_conflict_without_its_witness_receipts() fail {
  let unwitnessed = EnforcementEvidence { ..wire, wit_sigs: [] }
  checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    convict_envelope(unwitnessed),
    0,
    honest_convict_tx(),
  )
}

test enforcement_observer_refuses_a_recorded_event_that_conflicts_with_nothing() fail {
  let honest_tip = enforcement_vec.fork_witnessed_honest_tip
  let honest_wire = enforcement_vec.fork_witnessed_honest_wire
  let tx = convict_tx_of(
    honest_tip,
    honest_wire,
    v2_data(live(honest_tip, False, False, refund_enterprise_key())),
    floor_unfrozen + convict_pool,
    [
      pending_output(
        v2_data(pending(honest_tip)),
        mc,
        deriveAidAssetName(honest_tip.cesr_aid),
      ),
      ..honest_payouts()
    ],
    zero,
  )
  checkpoint_observer.observer_enforcement.withdraw(
    0,
    commitment_family,
    convict_envelope(honest_wire),
    0,
    tx,
  )
}

test convict_of_a_frozen_checkpoint_with_an_empty_pool_needs_no_refund_output() {
  run_convict(
    1,
    convict_tx(
      v2_data(live(tip, False, True, refund_enterprise_key())),
      floor_frozen,
      [pending_output(honest_pending(), mc, tip_name()), paid(convictor, d_reg)],
      zero,
    ),
  )
}

test register_refuses_evidence_without_the_controller_signatures() fail {
  let unsigned = RegistrationEvidence { ..reg_evidence, ctrl_sigs: [] }
  run_register_tx(
    register_tx(
      v2_data(registered(refund_enterprise_key(), registered_at)),
      floor_unfrozen,
      honest_name(),
      honest_proof(),
      unsigned,
      upto(registered_at, False),
    ),
    unsigned,
  )
}

test register_refuses_well_formed_keys_that_the_event_does_not_carry() fail {
  let datum = registered(refund_enterprise_key(), registered_at)
  let keys = parts(datum).keys
  expect [_, second, ..] = keys.cur_keys
  let other_first = #"0101010101010101010101010101010101010101010101010101010101010101"
  expect other_first != second
  register_with(
    from_parts(
      Parts {
        ..parts(datum),
        keys: KeyMaterial { ..keys, cur_keys: [other_first, second] },
      },
    ),
    floor_unfrozen,
    upto(registered_at, False),
  )
}

test register_refuses_a_born_at_below_zero() fail {
  // The upper bound and born_at agree, so only the datum's own validity can
  // refuse it.
  register_with(
    registered(refund_enterprise_key(), -5),
    floor_unfrozen,
    upto(-5, False),
  )
}

// ---------------------------------------------------------------------
// The observation must name the input being spent
// ---------------------------------------------------------------------

/// An input that is not the checkpoint, carrying the datum a decoy needs.
fn decoy_input(
  ref: OutputReference,
  address: Address,
  datum: Data,
  lovelace: Int,
) -> Input {
  input_at(
    ref,
    Output {
      address,
      value: from_lovelace(lovelace),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  )
}

// The accepted paid rotation of the checkpoint, with one input added that is
// not the checkpoint: a key-address output whose datum is the same live
// checkpoint, and the advance envelope names that input. The evidence is a
// valid rotation of what the decoy declares, so only the comparison between
// the envelope and the spent input can refuse it.
test advance_refuses_an_observation_of_another_input() fail {
  let decoy_ref = out_ref(seed_tx_id, 77)
  let decoy = decoy_input(
    decoy_ref,
    from_verification_key(owner_vkh),
    v2_data(adv_old(False, False)),
    floor_unfrozen + 3_000_000,
  )
  let base = advance_tx(
    v2_data(adv_old(False, False)),
    v2_data(adv_new(False)),
    floor_unfrozen + 3_000_000,
    floor_unfrozen + 1_000_000,
    [paid(hunter_pkh, premium)],
  )
  let envelope = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_advance,
      checkpoint_policy: policy,
      own_ref: Some(decoy_ref),
    },
    payload: adv_evidence,
  }
  let redeemer: Data = envelope
  let credential = Script(advance_hash)
  let tx = Transaction {
    ..base,
    inputs: [decoy, ..base.inputs],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
  run_spend(advance_redeemer(1), adv_ref(), tx) && checkpoint_observer.observer_advance.withdraw(
    0,
    envelope,
    0,
    tx,
  )
}

// The accepted conviction with one input added at the checkpoint address that
// holds no token and declares the same live checkpoint; both observers name it
// and its reservation is scoped to it.
test convict_refuses_an_observation_of_another_input() fail {
  let decoy_ref = out_ref(seed_tx_id, 78)
  let decoy = decoy_input(
    decoy_ref,
    from_script(policy),
    v2_data(live(tip, False, False, refund_enterprise_key())),
    floor_unfrozen + convict_pool,
  )
  let base = convict_tx_naming(
    decoy_ref,
    tip,
    wire,
    v2_data(live(tip, False, False, refund_enterprise_key())),
    floor_unfrozen + convict_pool,
    [pending_output(honest_pending(), mc, tip_name()), ..honest_payouts()],
    zero,
  )
  let tx = Transaction { ..base, inputs: [decoy, ..base.inputs] }
  let envelope = convict_envelope_naming(decoy_ref, wire)
  run_spend(convict_redeemer(1), convict_ref(), tx) && checkpoint_observer.observer_enforcement.withdraw(
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
