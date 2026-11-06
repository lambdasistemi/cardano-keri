//// #345 — the deposit option of Advance: the transactions and the evidence
//// the deposit tests run over.
////
//// A deposit Advance lands the controller's witnessed rotation and restores
//// the freeze bond: the successor is unfrozen and holds the bond again, and
//// the new keys of the rotation signed an intent that names this rotation,
//// this output and this amount. Two layers share these builders:
////
//// - the vector layer runs the spend arm alone over the rows of the Lean
////   deposit vectors (`deposit_vectors`), with a successor datum whose keys
////   are the row's test keys, because what it judges is the intent and the
////   signatures, not the rotation evidence;
//// - the connected layer runs the spend arm and the rotation observer over one
////   transaction, with the rotation of the Advance vector `adv_wit_2key`
////   (the freeze fixture's spent checkpoint and rotation), because what it
////   judges is the join: the signers are the keys the observer proved.
////
//// Every amount is arithmetic over the Lean's parameters and the pool, never
//// read back from the code under test.

use aiken/builtin
use aiken/collection/list
use aiken/interval
use cage_context.{input_at, out_ref, spend_context}
use cardano/address.{Script, from_script}
use cardano/assets.{Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, Withdraw,
}
use cardano_keri/checkpoint/advance.{AdvanceEvidence}
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, KeyMaterial, Live, TerminationPending,
}
use cardano_keri/checkpoint/deposit_vectors as vec
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance,
}
use cardano_keri/checkpoint/threshold.{Threshold, Unweighted}
use freeze_fixture.{
  Parts, advance_hash, floor_frozen, floor_unfrozen, from_parts, hunter_pkh,
  keys_of, live, live_marked, mc, network_id, paid, parts, policy, premium,
  rotated, rotation, spent, spent_ref, token_value, unevidenced, unit, v2_data,
}

/// A deposit or keep Advance ready to run: the applied network, the spent
/// output, the spend redeemer, the observer's envelope and the transaction.
/// The tests run it, because only they may call the validators.
pub type Case {
  network: Int,
  own_ref: OutputReference,
  redeemer: Data,
  observed: ObserverEnvelope,
  tx: Transaction,
}

// ---------------------------------------------------------------------
// Wire shapes
// ---------------------------------------------------------------------

/// `BondOp.Keep`: constructor zero.
pub fn bond_keep() -> Data {
  builtin.constr_data(0, [])
}

/// `BondOp.Deposit { signatures }`: constructor one, the signatures as pairs
/// of a position in the successor's current keys and the signature bytes.
pub fn bond_deposit(signatures: List<(Int, ByteArray)>) -> Data {
  let sigs: Data = signatures
  builtin.constr_data(1, [sigs])
}

/// `Advance { payee_output_index, bond }`: spend constructor zero.
pub fn advance_redeemer(payee_output_index: Int, bond: Data) -> Data {
  let index: Data = payee_output_index
  builtin.constr_data(0, [index, bond])
}

/// The signatures of a case of the connected rotation, by name.
pub fn signed(name: String) -> List<(Int, ByteArray)> {
  expect Some(case) = list.find(vec.fixture, fn(c) { c.name == name })
  case.signatures
}

// ---------------------------------------------------------------------
// The vector layer: the spend arm alone, one row
// ---------------------------------------------------------------------

/// Not read: the spend arm only checks the claim's action, policy and output.
fn unread_payload() -> Data {
  builtin.i_data(0)
}

const vector_asset: ByteArray =
  #"a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5"

fn vector_spent_keys() -> KeyMaterial {
  KeyMaterial {
    cur_keys: vec.old_keys,
    cur_threshold: Unweighted(2),
    next_keys: vec.new_keys,
    next_threshold: Unweighted(2),
    witnesses: [],
    toad: 0,
  }
}

fn vector_new_keys(threshold: Threshold) -> KeyMaterial {
  KeyMaterial {
    cur_keys: vec.new_keys,
    cur_threshold: threshold,
    next_keys: vec.new_keys,
    next_threshold: Unweighted(2),
    witnesses: [],
    toad: 0,
  }
}

pub fn vector_old(s: vec.Spent, f: vec.Facts) -> CheckpointDatumV2 {
  Live {
    aid: f.aid,
    sn: s.sn,
    epoch: s.epoch,
    poisoned: s.poisoned,
    frozen: s.frozen,
    born_at: s.born_at,
    refund_to: s.refund_to,
    topped_up: s.topped_up,
    keys: vector_spent_keys(),
  }
}

/// The successor a deposit of this row writes: unfrozen, unpoisoned, the
/// rotation's sequence number and epoch, the test keys at the row's threshold.
pub fn vector_new(
  s: vec.Spent,
  f: vec.Facts,
  new_sn: Int,
  threshold: Threshold,
) -> CheckpointDatumV2 {
  Live {
    aid: f.aid,
    sn: new_sn,
    epoch: s.epoch + 1,
    poisoned: False,
    frozen: False,
    born_at: s.born_at,
    refund_to: s.refund_to,
    topped_up: False,
    keys: vector_new_keys(threshold),
  }
}

fn spent_floor(s: vec.Spent) -> Int {
  if s.frozen {
    floor_frozen
  } else {
    floor_unfrozen
  }
}

/// A deposit over a row: the spent output holds its floor and the row's pool,
/// the successor holds the unfrozen floor and what is left of the pool after
/// the premium, which is paid to the second output when the pool covers it.
pub fn vector_case(
  s: vec.Spent,
  f: vec.Facts,
  new_sn: Int,
  threshold: Threshold,
  signatures: List<(Int, ByteArray)>,
) -> Case {
  let own_ref = out_ref(f.tx_id, f.output_index)
  let observed = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_advance,
      checkpoint_policy: f.policy,
      own_ref: Some(own_ref),
    },
    payload: unread_payload(),
  }
  let input = input_at(
    own_ref,
    Output {
      address: from_script(f.policy),
      value: from_lovelace(spent_floor(s) + s.pool)
        |> merge(from_asset(f.policy, vector_asset, 1)),
      datum: InlineDatum(v2_data(vector_old(s, f))),
      reference_script: None,
    },
  )
  let successor = Output {
    address: from_script(f.policy),
    value: from_lovelace(successor_value(s.pool))
      |> merge(from_asset(f.policy, vector_asset, 1)),
    datum: InlineDatum(v2_data(vector_new(s, f, new_sn, threshold))),
    reference_script: None,
  }
  let base = spend_context(
    [input],
    [],
    [successor, ..payees(s.pool)],
    zero,
    [],
    interval.everything,
    0,
  )
  let credential = Script(advance_hash)
  let envelope: Data = observed
  Case {
    network: f.network_id,
    own_ref,
    redeemer: advance_redeemer(1, bond_deposit(signatures)),
    observed,
    tx: Transaction {
      ..base,
      withdrawals: [Pair(credential, 0)],
      redeemers: [Pair(Withdraw(credential), envelope)],
    },
  }
}

// ---------------------------------------------------------------------
// The connected layer: the spend arm and the observer, one transaction
// ---------------------------------------------------------------------

/// The envelope of the rotation observer for an Advance.
pub fn advance_envelope(evidence: AdvanceEvidence) -> ObserverEnvelope {
  let payload: Data = evidence
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_advance,
      checkpoint_policy: policy,
      own_ref: Some(spent_ref()),
    },
    payload,
  }
}

/// The spent checkpoint of the connected rotation: live, with the given flags.
pub fn old_datum(poisoned: Bool, frozen: Bool) -> CheckpointDatumV2 {
  live(poisoned, frozen)
}

/// The successor the connected rotation writes: the rotated keys and sequence
/// number, one more epoch, the spent checkpoint's birth and refund address.
pub fn new_datum(frozen: Bool) -> CheckpointDatumV2 {
  let old = parts(live(False, False))
  Live {
    aid: old.aid,
    sn: rotated.native_sn,
    epoch: rotated.seq,
    poisoned: False,
    frozen,
    born_at: old.born_at,
    refund_to: old.refund_to,
    topped_up: False,
    keys: keys_of(rotated),
  }
}

/// A transaction of the connected layer: the spent output holds
/// `input_lovelace`, the successor `successor_lovelace`, `others` follow the
/// successor, and `mint` is what the transaction mints.
pub fn connected_tx(
  old: CheckpointDatumV2,
  input_lovelace: Int,
  new: CheckpointDatumV2,
  successor_lovelace: Int,
  others: List<Output>,
  mint: Value,
  observed: ObserverEnvelope,
) -> Transaction {
  let own_input = input_at(
    spent_ref(),
    Output {
      address: from_script(policy),
      value: token_value(input_lovelace),
      datum: InlineDatum(v2_data(old)),
      reference_script: None,
    },
  )
  let successor = Output {
    address: from_script(policy),
    value: token_value(successor_lovelace),
    datum: InlineDatum(v2_data(new)),
    reference_script: None,
  }
  let base = spend_context(
    [own_input],
    [],
    [successor, ..others],
    mint,
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

pub fn connected_case(
  redeemer: Data,
  observed: ObserverEnvelope,
  tx: Transaction,
) -> Case {
  Case { network: network_id, own_ref: spent_ref(), redeemer, observed, tx }
}

/// What the spent and the successor outputs hold, for an Advance of a
/// checkpoint with `pool` above its floor that pays `paid_premium`.
pub fn spent_value(frozen: Bool, pool: Int) -> Int {
  pool + if frozen {
    floor_frozen
  } else {
    floor_unfrozen
  }
}

/// The lovelace of the successor of a deposit: the unfrozen floor and the pool
/// that is left after the premium, if it is paid.
pub fn successor_value(pool: Int) -> Int {
  floor_unfrozen + if pool >= premium {
    pool - premium
  } else {
    pool
  }
}

/// The premium payee output, when the pool covers the premium.
pub fn payees(pool: Int) -> List<Output> {
  if pool >= premium {
    [paid(hunter_pkh, premium)]
  } else {
    []
  }
}

/// The honest deposit of the connected rotation for a checkpoint with these
/// flags and this pool: the observer's evidence is the rotation, the
/// signatures are the named case of the rotation's new keys.
pub fn honest(poisoned: Bool, frozen: Bool, pool: Int, intent: String) -> Case {
  let observed = advance_envelope(rotation)
  connected_case(
    advance_redeemer(1, bond_deposit(signed(intent))),
    observed,
    connected_tx(
      old_datum(poisoned, frozen),
      spent_value(frozen, pool),
      new_datum(False),
      successor_value(pool),
      payees(pool),
      zero,
      observed,
    ),
  )
}

// ---------------------------------------------------------------------
// The Lean corpus, in these amounts
// ---------------------------------------------------------------------

/// One cell of the Lean corpus's boundary grid: the deposit rotation of a
/// present state whose flags, pool and sequence-number relation are given.
///
/// - `topped_up`: the state's top-up mark; the rotation clears it
/// - `pool_units`: the Lean pool, scaled by `unit`
/// - `sn_relation`: the requested sequence number against the state's own,
///   negative (earlier), zero (equal) or positive (later); the later case is
///   the genuine rotation, the other two re-label the spent checkpoint so the
///   same genuine rotation is no longer later than it
/// - `rotation_evidenced`: the model's `rotationTo` holds; when it does not,
///   the evidence carries no signature and no receipt
/// - `authorized`: the model's `depositAuthorized` holds; when it does not, the
///   new keys signed the intent of another sequence number
pub fn corpus_deposit(
  poisoned: Bool,
  frozen: Bool,
  topped_up: Bool,
  pool_units: Int,
  sn_relation: Int,
  rotation_evidenced: Bool,
  authorized: Bool,
) -> Case {
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
  let evidence = if rotation_evidenced {
    rotation
  } else {
    unevidenced()
  }
  let intent = if authorized {
    if frozen {
      @"frozen"
    } else {
      @"unfrozen"
    }
  } else {
    @"other-sn"
  }
  let observed = advance_envelope(evidence)
  connected_case(
    advance_redeemer(1, bond_deposit(signed(intent))),
    observed,
    connected_tx(
      from_parts(old),
      spent_value(frozen, pool),
      new_datum(False),
      successor_value(pool),
      payees(pool),
      zero,
      observed,
    ),
  )
}

/// The corpus's termination-pending cell: nothing live to rotate.
pub fn corpus_deposit_pending(
  rotation_evidenced: Bool,
  authorized: Bool,
) -> Case {
  let evidence = if rotation_evidenced {
    rotation
  } else {
    unevidenced()
  }
  let intent = if authorized {
    @"frozen"
  } else {
    @"other-sn"
  }
  let observed = advance_envelope(evidence)
  connected_case(
    advance_redeemer(1, bond_deposit(signed(intent))),
    observed,
    connected_tx(
      pending_data_datum(),
      mc,
      new_datum(False),
      floor_unfrozen,
      [],
      zero,
      observed,
    ),
  )
}

fn pending_data_datum() -> CheckpointDatumV2 {
  TerminationPending {
    aid: qb64_aid(spent.cesr_aid),
    sn: spent.native_sn,
    epoch: spent.seq,
  }
}
