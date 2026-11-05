//// #345 — the one-step freeze: the deployment, the transactions and the
//// evidence the freeze tests run over.
////
//// A freeze spends a live, unfrozen, unpoisoned checkpoint whose pool is
//// below the premium, on the strength of the controller's own later
//// witnessed rotation. The successor is the same datum with `frozen` set;
//// the hunter receives the freeze bond.
////
//// Every amount is arithmetic over the Lean's parameters and the pool, never
//// read back from the code under test: one Lean unit is `unit` lovelace, so
//// `P = 2`, `B = 5`, `D = 1000` are `premium`, `freeze_bond`, `d_reg`.
//// The rotation evidence is the shared Advance vector, because the freeze
//// runs the unchanged advance predicate over it.

use aiken/builtin
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cage_context.{input_at, out_ref, spend_context}
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, Withdraw,
}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/advance_vectors as advance_vec
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, KeyMaterial, KeyStateView, Live, TerminationPending,
}
use cardano_keri/checkpoint/message.{SpentCheckpoint, qb64_aid}
use cardano_keri/checkpoint/observer.{
  FreezeEvidence, ObserverClaim, ObserverEnvelope,
}
use cardano_keri/checkpoint/retired_layout.{retired_layout}
use cardano_keri/checkpoint/threshold.{Unweighted}

// ---------------------------------------------------------------------
// The deployment
// ---------------------------------------------------------------------

pub const network_id: Int = 1

pub const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

pub const migration_hash: PolicyId =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

pub const lifecycle_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub const advance_hash: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

pub const enforcement_hash: PolicyId =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

pub const entitlement_hash: PolicyId =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

/// One Lean unit, in lovelace.
pub const unit: Int = 1_000_000

/// The Lean parameters, as lovelace (`Mc` is the registry's minimum ADA).
pub const mc: Int = 2_000_000

pub const d_reg: Int = 1_000_000_000

pub const freeze_bond: Int = 5_000_000

pub const premium: Int = 2_000_000

/// What a live, unfrozen checkpoint holds before its pool.
pub const floor_unfrozen: Int = 1_007_000_000

/// What a live, frozen checkpoint holds before its pool.
pub const floor_frozen: Int = 1_002_000_000

pub const registered_at: Int = 1_800_000_000_000

pub const hunter_pkh: ByteArray =
  #"54545454545454545454545454545454545454545454545454545454"

pub const refund_pkh: ByteArray =
  #"53535353535353535353535353535353535353535353535353535353"

pub const other_hunter_pkh: ByteArray =
  #"52525252525252525252525252525252525252525252525252525252"

/// The stable observer action tag of Freeze; the Advance tag is 1.
pub const freeze_tag: Int = 2

pub const advance_tag: Int = 1

// ---------------------------------------------------------------------
// Wire shapes
// ---------------------------------------------------------------------

/// The redeemer of the spending arm: constructor index three, the hunter's
/// output index.
pub fn freeze_redeemer(hunter_output_index: Int) -> Data {
  let index: Data = hunter_output_index
  builtin.constr_data(3, [index])
}

// ---------------------------------------------------------------------
// The spent checkpoint and the rotation evidence
// ---------------------------------------------------------------------

pub const spent: SpentCheckpoint = advance_vec.pos_adv_wit_2key_spent

pub const rotated: KeyStateView = advance_vec.pos_adv_wit_2key_created

pub const rotation: AdvanceEvidence = advance_vec.pos_adv_wit_2key_evidence

pub fn spent_ref() -> OutputReference {
  out_ref(spent.txid, spent.index)
}

pub fn keys_of(d: KeyStateView) -> KeyMaterial {
  KeyMaterial {
    cur_keys: d.cur_keys,
    cur_threshold: d.cur_threshold,
    next_keys: d.next_keys,
    next_threshold: d.next_threshold,
    witnesses: d.witnesses,
    toad: d.toad,
  }
}

/// The key state the spent checkpoint declares: the rotation's predecessor.
pub fn spent_keys() -> KeyMaterial {
  KeyMaterial {
    cur_keys: [
      #"bf1145e4449d74e9f09bd6aaffcbcd295f2a82e9fcbb5689c5346b3c274bccbb",
      #"95d507a9923dc62701d5619c117a3cbb8ae91cfe3f99e96cc0ae986cb52b586d",
    ],
    cur_threshold: Unweighted(2),
    next_keys: spent.next_keys,
    next_threshold: spent.next_threshold,
    witnesses: spent.witnesses,
    toad: 2,
  }
}

/// The spent checkpoint as a live version 2 datum, the top-up mark clear.
pub fn live(poisoned: Bool, frozen: Bool) -> CheckpointDatumV2 {
  live_marked(poisoned, frozen, False)
}

/// The spent checkpoint as a live version 2 datum with the top-up mark given.
pub fn live_marked(
  poisoned: Bool,
  frozen: Bool,
  topped_up: Bool,
) -> CheckpointDatumV2 {
  Live {
    aid: qb64_aid(spent.cesr_aid),
    sn: spent.native_sn,
    epoch: spent.seq,
    poisoned,
    frozen,
    born_at: registered_at,
    refund_to: bytearray.concat(#"61", refund_pkh),
    topped_up,
    keys: spent_keys(),
  }
}

/// The fields of a `Live` datum, in a record whose fields can be replaced one
/// at a time.
pub type Parts {
  aid: ByteArray,
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
  topped_up: Bool,
  keys: KeyMaterial,
}

pub fn parts(d: CheckpointDatumV2) -> Parts {
  expect  
      Live {
        aid,
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up,
        keys,
      }
    = d
  Parts {
    aid,
    sn,
    epoch,
    poisoned,
    frozen,
    born_at,
    refund_to,
    topped_up,
    keys,
  }
}

pub fn from_parts(p: Parts) -> CheckpointDatumV2 {
  Live {
    aid: p.aid,
    sn: p.sn,
    epoch: p.epoch,
    poisoned: p.poisoned,
    frozen: p.frozen,
    born_at: p.born_at,
    refund_to: p.refund_to,
    topped_up: p.topped_up,
    keys: p.keys,
  }
}

pub fn v2_data(d: CheckpointDatumV2) -> Data {
  datum.write(d)
}

/// The retired version 1 record of the spent key state.
pub fn v1_data() -> Data {
  retired_layout(
    KeyStateView {
      cesr_aid: spent.cesr_aid,
      cur_keys: spent_keys().cur_keys,
      cur_threshold: spent_keys().cur_threshold,
      next_keys: spent.next_keys,
      next_threshold: spent.next_threshold,
      witnesses: spent.witnesses,
      toad: 2,
      seq: spent.seq,
      native_sn: spent.native_sn,
    },
  )
}

pub fn pending_data() -> Data {
  v2_data(
    TerminationPending {
      aid: qb64_aid(spent.cesr_aid),
      sn: spent.native_sn,
      epoch: spent.seq,
    },
  )
}

// ---------------------------------------------------------------------
// Evidence variants: the honest rotation with one thing taken away
// ---------------------------------------------------------------------

/// Only the first controller signature: the current threshold is two.
pub fn under_signed() -> AdvanceEvidence {
  AdvanceEvidence { ..rotation, ctrl_sigs: list.take(rotation.ctrl_sigs, 1) }
}

/// Only the first witness receipt: the witness threshold is two.
pub fn under_receipted() -> AdvanceEvidence {
  AdvanceEvidence {
    ..rotation,
    wit_receipts: list.take(rotation.wit_receipts, 1),
  }
}

/// No signature and no receipt at all.
pub fn unevidenced() -> AdvanceEvidence {
  AdvanceEvidence { ..rotation, ctrl_sigs: [], wit_receipts: [] }
}

/// The first controller signature with its first byte replaced.
pub fn forged() -> AdvanceEvidence {
  expect [(index, signature), ..rest] = rotation.ctrl_sigs
  let damaged = bytearray.push(
    bytearray.drop(signature, 1),
    if bytearray.at(signature, 0) == 0 {
      1
    } else {
      0
    },
  )
  AdvanceEvidence { ..rotation, ctrl_sigs: [(index, damaged), ..rest] }
}

// ---------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------

pub fn token_value(lovelace: Int) -> Value {
  from_lovelace(lovelace) |> merge(from_asset(policy, spent.aid_asset_name, 1))
}

pub fn paid(recipient: ByteArray, lovelace: Int) -> Output {
  Output {
    address: from_verification_key(recipient),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

/// The observer envelope of a freeze: `action`, the policy, the spent output
/// and the payload over the rotation's key state.
pub fn envelope(
  action: Int,
  own_ref: OutputReference,
  evidence: AdvanceEvidence,
  rotated_sn: Int,
) -> ObserverEnvelope {
  let payload: Data = FreezeEvidence {
    rotated_keys: keys_of(rotated),
    rotated_sn,
    rotation: evidence,
  }
  ObserverEnvelope {
    claim: ObserverClaim {
      action,
      checkpoint_policy: policy,
      own_ref: Some(own_ref),
    },
    payload,
  }
}

pub fn honest_envelope() -> ObserverEnvelope {
  envelope(freeze_tag, spent_ref(), rotation, rotated.native_sn)
}

pub fn envelope_with(evidence: AdvanceEvidence) -> ObserverEnvelope {
  envelope(freeze_tag, spent_ref(), evidence, rotated.native_sn)
}

/// A freeze: the spent output holds `input_lovelace`, the successor
/// `successor_lovelace`, and `others` follow the successor in the outputs.
pub fn freeze_tx(
  old: Data,
  new: Data,
  input_lovelace: Int,
  successor_lovelace: Int,
  others: List<Output>,
  observed: ObserverEnvelope,
) -> Transaction {
  let own_input = input_at(
    spent_ref(),
    Output {
      address: from_script(policy),
      value: token_value(input_lovelace),
      datum: InlineDatum(old),
      reference_script: None,
    },
  )
  let successor = Output {
    address: from_script(policy),
    value: token_value(successor_lovelace),
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
  let redeemer: Data = observed
  Transaction {
    ..base,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

/// A freeze ready to run: the hunter's output index, the observer's envelope
/// and the transaction. The tests run it, because only they may call the
/// validators.
pub type Freeze {
  hunter_output_index: Int,
  observed: ObserverEnvelope,
  tx: Transaction,
}

/// The honest freeze of an unfrozen, unpoisoned checkpoint holding `pool`
/// above its floor: the hunter output is the second output.
pub fn honest_tx(pool: Int) -> Transaction {
  freeze_tx(
    v2_data(live(False, False)),
    v2_data(live(False, True)),
    floor_unfrozen + pool,
    floor_frozen + pool,
    [paid(hunter_pkh, freeze_bond)],
    honest_envelope(),
  )
}

pub fn honest_case(pool: Int) -> Freeze {
  Freeze {
    hunter_output_index: 1,
    observed: honest_envelope(),
    tx: honest_tx(pool),
  }
}

/// `Advance { payee_output_index, bond: Keep }`: constructor index zero, the
/// keep option (constructor zero) after the payee output index.
pub fn advance_redeemer(payee_output_index: Int) -> Data {
  let index: Data = payee_output_index
  builtin.constr_data(0, [index, builtin.constr_data(0, [])])
}

/// The honest freeze with the successor datum and its value replaced.
pub fn into_case(new: CheckpointDatumV2, successor_lovelace: Int) -> Freeze {
  Freeze {
    hunter_output_index: 1,
    observed: honest_envelope(),
    tx: freeze_tx(
      v2_data(live(False, False)),
      v2_data(new),
      floor_unfrozen + 1_000_000,
      successor_lovelace,
      [paid(hunter_pkh, freeze_bond)],
      honest_envelope(),
    ),
  }
}

/// The honest freeze with the outputs after the successor replaced.
pub fn paying_case(hunter_output_index: Int, others: List<Output>) -> Freeze {
  Freeze {
    hunter_output_index,
    observed: honest_envelope(),
    tx: freeze_tx(
      v2_data(live(False, False)),
      v2_data(live(False, True)),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      others,
      honest_envelope(),
    ),
  }
}

/// The honest freeze with the observer's evidence replaced.
pub fn observing_case(evidence: AdvanceEvidence) -> Freeze {
  let observed = envelope_with(evidence)
  Freeze {
    hunter_output_index: 1,
    observed,
    tx: freeze_tx(
      v2_data(live(False, False)),
      v2_data(live(False, True)),
      floor_unfrozen + 1_000_000,
      floor_frozen + 1_000_000,
      [paid(hunter_pkh, freeze_bond)],
      observed,
    ),
  }
}

/// The honest freeze of the given spent datum, whose successor is given too,
/// each holding the lovelace stated.
pub fn spending_case(
  old: CheckpointDatumV2,
  input_lovelace: Int,
  successor: CheckpointDatumV2,
  successor_lovelace: Int,
) -> Freeze {
  Freeze {
    hunter_output_index: 1,
    observed: honest_envelope(),
    tx: freeze_tx(
      v2_data(old),
      v2_data(successor),
      input_lovelace,
      successor_lovelace,
      [paid(hunter_pkh, freeze_bond)],
      honest_envelope(),
    ),
  }
}

// ---------------------------------------------------------------------
// The Lean corpus, in these amounts
// ---------------------------------------------------------------------

/// One cell of the Lean corpus's boundary grid: the freeze of a present state
/// whose flags, pool and sequence-number relation are given.
///
/// - `topped_up`: the state's top-up mark; a freeze keeps it
/// - `pool_units`: the Lean pool, scaled by `unit`
/// - `sn_relation`: the requested sequence number against the state's own,
///   negative (earlier), zero (equal) or positive (later); the later case is
///   the genuine rotation, the other two re-label the spent checkpoint so the
///   same genuine rotation is no longer later than it
/// - `rotation_evidenced`: the model's `rotationTo` holds; when it does not,
///   the evidence carries no signature and no receipt
pub fn corpus_freeze(
  poisoned: Bool,
  frozen: Bool,
  topped_up: Bool,
  pool_units: Int,
  sn_relation: Int,
  rotation_evidenced: Bool,
) -> Freeze {
  let pool = pool_units * unit
  let spent_sn = if sn_relation > 0 {
    spent.native_sn
  } else if sn_relation == 0 {
    rotated.native_sn
  } else {
    rotated.native_sn + 1
  }
  let old = Parts {
    ..parts(live_marked(poisoned, frozen, topped_up)),
    sn: spent_sn,
  }
  let floor = if frozen {
    floor_frozen
  } else {
    floor_unfrozen
  }
  let evidence = if rotation_evidenced {
    rotation
  } else {
    unevidenced()
  }
  let observed = envelope_with(evidence)
  Freeze {
    hunter_output_index: 1,
    observed,
    tx: freeze_tx(
      v2_data(from_parts(old)),
      v2_data(from_parts(Parts { ..old, frozen: True })),
      floor + pool,
      floor_frozen + pool,
      [paid(hunter_pkh, freeze_bond)],
      observed,
    ),
  }
}

/// The corpus's termination-pending cell: nothing live to freeze.
pub fn corpus_freeze_pending(rotation_evidenced: Bool) -> Freeze {
  let evidence = if rotation_evidenced {
    rotation
  } else {
    unevidenced()
  }
  let observed = envelope_with(evidence)
  Freeze {
    hunter_output_index: 1,
    observed,
    tx: freeze_tx(
      pending_data(),
      v2_data(live(False, True)),
      mc,
      floor_frozen,
      [paid(hunter_pkh, freeze_bond)],
      observed,
    ),
  }
}
