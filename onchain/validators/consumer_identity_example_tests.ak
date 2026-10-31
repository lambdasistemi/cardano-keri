//// The example relying contract on the concrete identity bytes and the Lean
//// datum decoder (#343) against hand-built transactions, for the Lean vectors.
//// The expected assets are the Lean's, from the generated vectors, not read
//// from the predicate; the datums are version 2 datums written field by field
//// from the Lean layout.

use aiken/interval.{Finite, Interval, IntervalBound, PositiveInfinity}
use cardano/address.{Address, Script}
use cardano/assets.{from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/consumer.{Context, Params, Token}
use cardano_keri/consumer_checkpoint_datum_check.{
  live_datum, pending_datum, version_one_datum,
}
use cardano_keri/consumer_identity_check.{IdentityVector, context_of}
use cardano_keri/consumer_identity_vectors.{
  vector_other_aid_same_registry, vector_other_state_policy,
  vector_rival_seed_output_index, vector_rival_seed_transaction,
  vector_transferable_aid,
}
use consumer_identity_example

fn params() -> Params {
  Params { d: 3, b: 2, p: 1, w: 1 }
}

fn holding(t: Token, quantity: Int, datum: Data) -> Output {
  Output {
    address: Address {
      payment_credential: Script(
        #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      stake_credential: None,
    },
    value: from_lovelace(3000000) |> assets.add(t.policy, t.name, quantity),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn reference(output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0101010101010101010101010101010101010101010101010101010101010101",
      output_index: 0,
    },
    output,
  }
}

fn from(lower: Int) -> Interval<Int> {
  Interval {
    lower_bound: IntervalBound { bound_type: Finite(lower), is_inclusive: True },
    upper_bound: IntervalBound {
      bound_type: PositiveInfinity,
      is_inclusive: True,
    },
  }
}

/// The contract that fixes the vector's state policy, seed and AID, spending
/// with a holding of `asset` carrying `datum` as its only reference input,
/// at a time past the holding's juvenility window.
fn spends_with(
  v: IdentityVector,
  asset: Token,
  quantity: Int,
  datum: Data,
) -> Bool {
  let context: Context = context_of(v)
  consumer_identity_example.consumer_identity_example.spend(
    context,
    params(),
    None,
    Void,
    OutputReference {
      transaction_id: #"0202020202020202020202020202020202020202020202020202020202020202",
      output_index: 0,
    },
    Transaction {
      ..placeholder,
      reference_inputs: [reference(holding(asset, quantity, datum))],
      validity_range: from(1000),
    },
  )
}

/// The same, for the genuine version 2 live datum of the contract's AID.
fn spends(v: IdentityVector, asset: Token, quantity: Int) -> Bool {
  spends_with(v, asset, quantity, live_datum(v.aid, 0))
}

/// Lean `written_holding_iff`: a genuine holding with a written, consumable datum is accepted.
test accepts_the_holding_named_by_the_concrete_bytes() {
  let v = vector_transferable_aid()
  spends(v, v.asset, 1)
}

test refuses_a_rival_seeds_holding() {
  let v = vector_transferable_aid()
  spends(v, v.asset, 1) && !spends(v, vector_rival_seed_output_index().asset, 1) && !spends(
    v,
    vector_rival_seed_transaction().asset,
    1,
  )
}

test refuses_another_state_policys_holding() {
  let v = vector_transferable_aid()
  spends(v, v.asset, 1) && !spends(v, vector_other_state_policy().asset, 1)
}

test refuses_quantity_two() {
  let v = vector_transferable_aid()
  spends(v, v.asset, 1) && !spends(v, v.asset, 2)
}

/// Lean `written_holding_iff`: a written datum of a state that is not consumable is refused.
test refuses_a_holding_with_termination_pending() {
  let v = vector_transferable_aid()
  spends(v, v.asset, 1) && !spends_with(v, v.asset, 1, pending_datum(v.aid))
}

/// Lean `version_one_holding_refused`.
test refuses_a_holding_with_a_version_one_datum() {
  let v = vector_transferable_aid()
  spends(v, v.asset, 1) && !spends_with(v, v.asset, 1, version_one_datum(v.aid))
}

test refuses_a_holding_for_another_aid() {
  let v = vector_transferable_aid()
  let other = vector_other_aid_same_registry()
  spends(v, v.asset, 1) && !spends_with(v, v.asset, 1, live_datum(other.aid, 0))
}
