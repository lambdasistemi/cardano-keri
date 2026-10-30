//// The example relying contract on the concrete identity bytes (#343)
//// against hand-built transactions, for the Lean vectors: concrete identity
//// bytes, test datum decoder. The expected assets are the Lean's, from the
//// generated vectors, not read from the predicate.

use aiken/interval.{Finite, Interval, IntervalBound, PositiveInfinity}
use cardano/address.{Address, Script}
use cardano/assets.{from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/consumer.{Context, DecodedDatum, Live, Params, Present, Token}
use cardano_keri/consumer_identity_check.{IdentityVector, context_of}
use cardano_keri/consumer_identity_vectors.{
  vector_other_state_policy, vector_rival_seed_output_index,
  vector_rival_seed_transaction, vector_transferable_aid,
}
use consumer_identity_example

fn params() -> Params {
  Params { d: 3, b: 2, p: 1, w: 1 }
}

fn holding(t: Token, quantity: Int, aid: Int) -> Output {
  let datum: Data = DecodedDatum {
    aid,
    state: Present(
      Live {
        sn: 0,
        epoch: 0,
        poisoned: False,
        frozen: False,
        born_at: 0,
        refund_to: 7,
        pool: 5,
      },
    ),
  }
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
/// with a holding of `asset` as its only reference input.
fn spends(v: IdentityVector, asset: Token, quantity: Int) -> Bool {
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
      reference_inputs: [reference(holding(asset, quantity, context.aid))],
      validity_range: from(1000),
    },
  )
}

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
