//// #346 / #522 — the bounded top-up: the transactions and the datums the
//// top-up tests run over.
////
//// A top-up spends a live checkpoint whose top-up mark is clear and returns it
//// with the mark set and the pool grown by an amount of at least the premium.
//// No signature, no observer, no validity range is involved.
////
//// The datums are built here as `Data`, field by field, beside the typed
//// `Live` the validator uses. The wire layout is the Lean's version 2 live
//// datum: constructor 0 of nine fields, `topped_up` at index 7, before the key
//// material. A test that builds the datum by hand cannot agree with the
//// validator by sharing its code.
////
//// Every amount is arithmetic over the Lean's parameters and the pool, never
//// read back from the code under test: one Lean unit is `unit` lovelace.

use aiken/builtin
use aiken/collection/list
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/primitive/bytearray
use cage_context.{
  input_at, min_ada, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{Address, Script, from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, Withdraw,
}
use cardano_keri/checkpoint/datum.{KeyMaterial}
use cardano_keri/checkpoint/message.{deriveAidAssetName, qb64_aid}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as reg_vec
use cardano_keri/checkpoint/threshold.{Unweighted}
use deposit_fixture
use freeze_fixture.{
  Freeze, advance_hash, floor_frozen, floor_unfrozen, freeze_bond, freeze_tx,
  honest_envelope, hunter_pkh, keys_of, lifecycle_hash, mc, paid, policy,
  premium, refund_pkh, registered_at, rotated, rotation, spent, spent_keys,
  spent_ref, token_value, unit,
}

// ---------------------------------------------------------------------
// The version 2 live datum, built field by field
// ---------------------------------------------------------------------

/// The fields of a live datum, in a record whose fields can be replaced one at
/// a time.
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

/// The checkpoint the tests spend: the shared rotation vector's predecessor,
/// with the flags given.
pub fn base(poisoned: Bool, frozen: Bool, topped_up: Bool) -> Parts {
  Parts {
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

/// A Plutus Boolean: `False` is constructor 0, `True` constructor 1.
pub fn flag(b: Bool) -> Data {
  if b {
    builtin.constr_data(1, [])
  } else {
    builtin.constr_data(0, [])
  }
}

/// The nine fields of a live datum, in wire order.
pub fn nine_fields(p: Parts) -> List<Data> {
  let aid: Data = p.aid
  let sn: Data = p.sn
  let epoch: Data = p.epoch
  let born_at: Data = p.born_at
  let refund_to: Data = p.refund_to
  let keys: Data = p.keys
  [
    aid,
    sn,
    epoch,
    flag(p.poisoned),
    flag(p.frozen),
    born_at,
    refund_to,
    flag(p.topped_up),
    keys,
  ]
}

/// An inline datum: `Constr 1 [<datum>]` around a live datum of the fields given.
pub fn live_of(fields: List<Data>) -> Data {
  builtin.constr_data(1, [builtin.constr_data(0, fields)])
}

/// The version 2 live datum of nine fields.
pub fn nine_data(p: Parts) -> Data {
  live_of(nine_fields(p))
}

/// The retired width: the same datum without `topped_up`.
pub fn eight_data(p: Parts) -> Data {
  let fields = nine_fields(p)
  live_of(list.concat(list.take(fields, 7), list.drop(fields, 8)))
}

/// One field too many, after the key material.
pub fn ten_data(p: Parts) -> Data {
  let extra: Data = 0
  live_of(list.concat(nine_fields(p), [extra]))
}

/// The same datum with `topped_up` replaced by an arbitrary `Data`.
pub fn marked_with(p: Parts, mark: Data) -> Data {
  live_of(
    list.indexed_map(
      nine_fields(p),
      fn(i, f) {
        if i == 7 {
          mark
        } else {
          f
        }
      },
    ),
  )
}

/// The termination-pending datum: three fields, unchanged by the top-up.
pub fn pending_data() -> Data {
  freeze_fixture.pending_data()
}

/// The key material with its current threshold replaced.
pub fn other_keys() -> KeyMaterial {
  KeyMaterial { ..spent_keys(), cur_threshold: Unweighted(1) }
}

// ---------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------

/// The redeemer of the spending arm: constructor index four, the amount.
pub fn topup_redeemer(amount: Int) -> Data {
  let a: Data = amount
  builtin.constr_data(4, [a])
}

/// The held lovelace of a live checkpoint with the flag given and `pool` above
/// its floor.
pub fn held(frozen: Bool, pool: Int) -> Int {
  pool + if frozen {
    floor_frozen
  } else {
    floor_unfrozen
  }
}

pub fn script_output(value: Value, datum: Data) -> Output {
  Output {
    address: from_script(policy),
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

/// The funding input: anyone's key, holding the amount and a margin.
pub fn payer_input(lovelace: Int) -> Input {
  input_at(
    out_ref(seed_tx_id, 7),
    Output {
      address: from_verification_key(
        #"61616161616161616161616161616161616161616161616161616161",
      ),
      value: from_lovelace(lovelace),
      datum: NoDatum,
      reference_script: None,
    },
  )
}

/// A top-up as the tests present it: the redeemer's amount and the
/// transaction. Only the tests may call the validators.
pub type TopUp {
  amount: Int,
  tx: Transaction,
}

/// A transaction spending the checkpoint output `own` (and whatever `inputs`
/// follow), producing `outputs`, minting `mint`, valid over `range`, with
/// `signers` as extra signatories.
pub fn tx_of(
  own: Output,
  inputs: List<Input>,
  outputs: List<Output>,
  mint: Value,
  signers: List<ByteArray>,
  range: Interval<Int>,
) -> Transaction {
  spend_context(
    [input_at(spent_ref(), own), ..inputs],
    [],
    outputs,
    mint,
    signers,
    range,
    0,
  )
}

/// The honest top-up of `old` into `new`: the spent output holds
/// `input_lovelace`, the successor `successor_lovelace`; `others` follow the
/// successor in the outputs.
pub fn topup_between(
  amount: Int,
  old: Data,
  new: Data,
  input_lovelace: Int,
  successor_lovelace: Int,
  others: List<Output>,
) -> TopUp {
  TopUp {
    amount,
    tx: tx_of(
      script_output(token_value(input_lovelace), old),
      [payer_input(amount + 3_000_000)],
      [script_output(token_value(successor_lovelace), new), ..others],
      zero,
      [],
      interval.everything,
    ),
  }
}

/// The honest top-up of a fresh checkpoint with the flags given and `pool`
/// above its floor: the successor is the same datum with the mark set and holds
/// `amount` more.
pub fn honest_case(
  poisoned: Bool,
  frozen: Bool,
  pool: Int,
  amount: Int,
) -> TopUp {
  topup_between(
    amount,
    nine_data(base(poisoned, frozen, False)),
    nine_data(base(poisoned, frozen, True)),
    held(frozen, pool),
    held(frozen, pool + amount),
    [],
  )
}

/// The honest top-up of an unfrozen, unpoisoned checkpoint with a pool of one
/// unit, by the premium.
pub fn honest() -> TopUp {
  honest_case(False, False, unit, premium)
}

/// The honest top-up with the successor datum replaced.
pub fn into_case(new: Data) -> TopUp {
  topup_between(
    premium,
    nine_data(base(False, False, False)),
    new,
    held(False, unit),
    held(False, unit + premium),
    [],
  )
}

/// The honest top-up with the spent datum replaced.
pub fn from_case(old: Data) -> TopUp {
  topup_between(
    premium,
    old,
    nine_data(base(False, False, True)),
    held(False, unit),
    held(False, unit + premium),
    [],
  )
}

/// The honest top-up with the successor's lovelace replaced.
pub fn valued_case(successor_lovelace: Int) -> TopUp {
  topup_between(
    premium,
    nine_data(base(False, False, False)),
    nine_data(base(False, False, True)),
    held(False, unit),
    successor_lovelace,
    [],
  )
}

/// The honest top-up with the successor's value replaced.
pub fn valued_with(value: Value) -> TopUp {
  let h = honest()
  TopUp {
    ..h,
    tx: Transaction {
      ..h.tx,
      outputs: [script_output(value, nine_data(base(False, False, True)))],
    },
  }
}

/// The honest top-up with the outputs after the successor replaced.
pub fn outputs_after(others: List<Output>) -> TopUp {
  topup_between(
    premium,
    nine_data(base(False, False, False)),
    nine_data(base(False, False, True)),
    held(False, unit),
    held(False, unit + premium),
    others,
  )
}

/// The honest top-up with the inputs after the checkpoint input replaced.
pub fn inputs_after(inputs: List<Input>) -> TopUp {
  let h = honest()
  TopUp {
    ..h,
    tx: Transaction {
      ..h.tx,
      inputs: [
        input_at(
          spent_ref(),
          script_output(
            token_value(held(False, unit)),
            nine_data(base(False, False, False)),
          ),
        ),
        ..inputs
      ],
    },
  }
}

/// The honest top-up with the mint field replaced.
pub fn minting(mint: Value) -> TopUp {
  let h = honest()
  TopUp { ..h, tx: Transaction { ..h.tx, mint } }
}

/// The honest top-up over another validity range.
pub fn within(range: Interval<Int>) -> TopUp {
  let h = honest()
  TopUp { ..h, tx: Transaction { ..h.tx, validity_range: range } }
}

/// The honest top-up with other extra signatories.
pub fn signed_by(signers: List<ByteArray>) -> TopUp {
  let h = honest()
  TopUp { ..h, tx: Transaction { ..h.tx, extra_signatories: signers } }
}

/// The honest top-up with an observer withdrawal attached: not required, and
/// not refused when present.
pub fn with_withdrawal() -> TopUp {
  let h = honest()
  let credential = Script(advance_hash)
  TopUp {
    ..h,
    tx: Transaction {
      ..h.tx,
      withdrawals: [Pair(credential, 0)],
      redeemers: [Pair(Withdraw(credential), builtin.constr_data(0, []))],
    },
  }
}

/// The honest top-up with the checkpoint input held at `address`.
pub fn held_at(address: Address) -> TopUp {
  let h = honest()
  TopUp {
    ..h,
    tx: Transaction {
      ..h.tx,
      inputs: [
        input_at(
          spent_ref(),
          Output {
            address,
            value: token_value(held(False, unit)),
            datum: InlineDatum(nine_data(base(False, False, False))),
            reference_script: None,
          },
        ),
        payer_input(premium + 3_000_000),
      ],
    },
  }
}

/// A second checkpoint input of the same policy: another AID's token, held at
/// the checkpoint address.
pub fn second_checkpoint_input() -> Input {
  input_at(
    out_ref(seed_tx_id, 9),
    script_output(
      from_lovelace(floor_unfrozen + unit)
        |> merge(
            from_asset(
              policy,
              #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
              1,
            ),
          ),
      nine_data(base(False, False, False)),
    ),
  )
}

/// A second checkpoint output of the same policy.
pub fn second_checkpoint_output() -> Output {
  script_output(
    from_lovelace(floor_unfrozen + unit)
      |> merge(
          from_asset(
            policy,
            #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
            1,
          ),
        ),
    nine_data(base(False, False, True)),
  )
}

/// The checkpoint token's asset name.
pub fn token_name() -> ByteArray {
  spent.aid_asset_name
}

pub fn other_policy() -> PolicyId {
  #"99999999999999999999999999999999999999999999999999999999"
}

/// A key's enterprise output paying `lovelace`, the shape any payer's change
/// takes.
pub fn change(lovelace: Int) -> Output {
  paid(#"61616161616161616161616161616161616161616161616161616161", lovelace)
}

// ---------------------------------------------------------------------
// The registration: the pool starts at one premium or more
// ---------------------------------------------------------------------

/// The hash-proof policy the registration burns a token of.
pub const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const reg_digest: ByteArray = reg_vec.pos_2key_datum.cesr_aid

pub const reg_evidence: RegistrationEvidence = reg_vec.pos_2key_evidence

pub fn reg_name() -> ByteArray {
  deriveAidAssetName(reg_digest)
}

pub fn reg_proof_name() -> ByteArray {
  proof_token_name(reg_evidence.event_bytes, reg_digest)
}

/// The facts a registration writes, with the top-up mark given.
pub fn registered_parts(topped_up: Bool) -> Parts {
  Parts {
    aid: qb64_aid(reg_digest),
    sn: 0,
    epoch: 0,
    poisoned: False,
    frozen: False,
    born_at: registered_at,
    refund_to: bytearray.concat(#"61", refund_pkh),
    topped_up,
    keys: KeyMaterial {
      cur_keys: reg_vec.pos_2key_datum.cur_keys,
      cur_threshold: reg_vec.pos_2key_datum.cur_threshold,
      next_keys: reg_vec.pos_2key_datum.next_keys,
      next_threshold: reg_vec.pos_2key_datum.next_threshold,
      witnesses: reg_vec.pos_2key_datum.witnesses,
      toad: reg_vec.pos_2key_datum.toad,
    },
  }
}

pub fn register_envelope() -> ObserverEnvelope {
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_register,
      checkpoint_policy: policy,
      own_ref: None,
    },
    payload: reg_evidence,
  }
}

/// A validity range whose upper bound is `hi`, exclusive.
pub fn upto(hi: Int) -> Interval<Int> {
  Interval {
    lower_bound: IntervalBound {
      bound_type: Finite(hi - 10_000),
      is_inclusive: True,
    },
    upper_bound: IntervalBound { bound_type: Finite(hi), is_inclusive: False },
  }
}

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

/// A registration writing `datum` into an output holding `lovelace`.
pub fn register_with(datum: Data, lovelace: Int) -> Transaction {
  let name = reg_name()
  let proof_name = reg_proof_name()
  let state_output = Output {
    address: from_script(policy),
    value: from_lovelace(lovelace) |> merge(from_asset(policy, name, 1)),
    datum: InlineDatum(datum),
    reference_script: None,
  }
  let base = spend_context(
    [proof_input(proof_name)],
    [],
    [state_output],
    from_asset(policy, name, 1)
      |> merge(from_asset(hp_policy, proof_name, -1)),
    [],
    upto(registered_at),
    0,
  )
  let credential = Script(lifecycle_hash)
  let redeemer: Data = register_envelope()
  Transaction {
    ..base,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

/// The honest registration of a pool of `pool0` lovelace above the floor.
pub fn registered_with_pool(pool0: Int) -> Transaction {
  register_with(nine_data(registered_parts(False)), floor_unfrozen + pool0)
}

// ---------------------------------------------------------------------
// The rotation: the mark is cleared
// ---------------------------------------------------------------------

/// The bond option: keep, or deposit.
pub type Bond {
  Keep
  Deposit
}

/// A rotation ready to run: the spend redeemer, the observer's envelope, the
/// transaction.
pub type Rotation {
  redeemer: Data,
  observed: ObserverEnvelope,
  tx: Transaction,
}

/// The successor the rotation of the shared vector writes, flags and mark as
/// given: the rotated keys and sequence number, one more epoch.
pub fn rotated_parts(frozen: Bool, topped_up: Bool) -> Parts {
  Parts {
    ..base(False, frozen, topped_up),
    sn: rotated.native_sn,
    epoch: rotated.seq,
    keys: keys_of(rotated),
  }
}

/// A rotation of the checkpoint with the flags and mark given and `pool` above
/// its floor, paying the premium when the pool covers it; the successor
/// carries `new_mark`.
pub fn rotation_case(
  bond: Bond,
  frozen: Bool,
  pool: Int,
  old_mark: Bool,
  new_mark: Bool,
) -> Rotation {
  let observed = deposit_fixture.advance_envelope(rotation)
  let successor_frozen = when bond is {
    Keep -> frozen
    Deposit -> False
  }
  let paid_premium = pool >= premium
  let pool_after = if paid_premium {
    pool - premium
  } else {
    pool
  }
  let intent = if frozen {
    @"frozen"
  } else {
    @"unfrozen"
  }
  let redeemer = when bond is {
    Keep -> deposit_fixture.advance_redeemer(1, deposit_fixture.bond_keep())
    Deposit ->
      deposit_fixture.advance_redeemer(
        1,
        deposit_fixture.bond_deposit(deposit_fixture.signed(intent)),
      )
  }
  let own_input = input_at(
    spent_ref(),
    script_output(
      token_value(held(frozen, pool)),
      nine_data(base(False, frozen, old_mark)),
    ),
  )
  let successor = script_output(
    token_value(held(successor_frozen, pool_after)),
    nine_data(rotated_parts(successor_frozen, new_mark)),
  )
  let payees = if paid_premium {
    [paid(hunter_pkh, premium)]
  } else {
    []
  }
  let context = spend_context(
    [own_input],
    [],
    [successor, ..payees],
    zero,
    [],
    interval.everything,
    0,
  )
  let credential = Script(advance_hash)
  let envelope_data: Data = observed
  Rotation {
    redeemer,
    observed,
    tx: Transaction {
      ..context,
      withdrawals: [Pair(credential, 0)],
      redeemers: [Pair(Withdraw(credential), envelope_data)],
    },
  }
}

/// The honest freeze of a checkpoint with the mark given and a pool below the
/// premium; the successor carries `new_mark`.
pub fn freeze_case(old_mark: Bool, new_mark: Bool) -> Freeze {
  let pool = unit
  Freeze {
    hunter_output_index: 1,
    observed: honest_envelope(),
    tx: freeze_tx(
      nine_data(base(False, False, old_mark)),
      nine_data(base(False, True, new_mark)),
      floor_unfrozen + pool,
      floor_frozen + pool,
      [paid(hunter_pkh, freeze_bond)],
      honest_envelope(),
    ),
  }
}

/// The honest top-up with the checkpoint input carrying no datum.
pub fn without_datum() -> TopUp {
  let h = honest()
  TopUp {
    ..h,
    tx: Transaction {
      ..h.tx,
      inputs: [
        input_at(
          spent_ref(),
          Output {
            address: from_script(policy),
            value: token_value(held(False, unit)),
            datum: NoDatum,
            reference_script: None,
          },
        ),
      ],
    },
  }
}

// ---------------------------------------------------------------------
// The Lean corpus, in these amounts
// ---------------------------------------------------------------------

/// One cell of the Lean corpus's boundary grid: the top-up of a live state
/// whose flags, pool and top-up mark are given, by `amount_units`. The
/// successor is always the state grown by the amount with the mark set, so a
/// refused cell is refused by the model's guard and by nothing else.
pub fn corpus_topup(
  poisoned: Bool,
  frozen: Bool,
  pool_units: Int,
  marked: Bool,
  amount_units: Int,
) -> TopUp {
  let pool = pool_units * unit
  let amount = amount_units * unit
  topup_between(
    amount,
    nine_data(base(poisoned, frozen, marked)),
    nine_data(base(poisoned, frozen, True)),
    held(frozen, pool),
    held(frozen, pool + amount),
    [],
  )
}

/// The corpus's termination-pending cell: nothing live to top up.
pub fn corpus_topup_pending(amount_units: Int) -> TopUp {
  let amount = amount_units * unit
  topup_between(
    amount,
    pending_data(),
    nine_data(base(False, False, True)),
    mc,
    held(False, amount),
    [],
  )
}

/// The registration of a first pool of `pool0_units`.
pub fn corpus_register(pool0_units: Int) -> Transaction {
  registered_with_pool(pool0_units * unit)
}
