//// The example relying contract (#343 slice 2) against hand-built
//// transactions: test interpretation, not the registry byte layout. The
//// expected representative asset is written out from the declared layout of
//// `consumer_test_interpretation`, not read from the predicate.

use aiken/crypto.{blake2b_256}
use aiken/interval.{
  Finite, Interval, IntervalBound, NegativeInfinity, PositiveInfinity,
}
use aiken/primitive/bytearray
use cardano/address.{Address, Script}
use cardano/assets.{from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/consumer.{
  Absent, Context, Convicted, DecodedDatum, Hash, Live, Params, Parked, Present,
  PublishedRelease, State, TerminationPending,
}
use consumer_example

const app_credential: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const state_policy: ByteArray =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const seed_tx: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const rival_seed_tx: ByteArray =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

fn context() -> Context {
  Context {
    network: 0,
    release: PublishedRelease {
      application_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      application_credential: Script(app_credential),
      state_program: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      state_policy,
    },
    seed: OutputReference { transaction_id: seed_tx, output_index: 0 },
    aid: 42,
  }
}

fn params() -> Params {
  Params { d: 3, b: 2, p: 1, w: 1 }
}

fn be8(n: Int) -> ByteArray {
  bytearray.from_int_big_endian(n, 8)
}

/// The declared layout, written out: hash of 0x01 ++ policy ++ registry name ++ key.
fn representative_name(tx: ByteArray) -> ByteArray {
  let registry_name = blake2b_256(
    bytearray.concat(#"00", bytearray.concat(tx, be8(0))),
  )
  blake2b_256(
    bytearray.concat(
      #"01",
      bytearray.concat(state_policy, bytearray.concat(registry_name, be8(42))),
    ),
  )
}

fn live(born_at: Int) -> State {
  Present(
    Live {
      sn: 0,
      epoch: 0,
      poisoned: False,
      frozen: False,
      born_at,
      refund_to: 7,
      pool: 5,
    },
  )
}

fn holding(name: ByteArray, quantity: Int, state: State) -> Output {
  let datum: Data = DecodedDatum { aid: 42, state }
  Output {
    address: Address {
      payment_credential: Script(app_credential),
      stake_credential: None,
    },
    value: from_lovelace(3000000) |> assets.add(state_policy, name, quantity),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn reference(index: Int, output: Output) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: #"0101010101010101010101010101010101010101010101010101010101010101",
      output_index: index,
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

fn spend(refs: List<Input>, validity: Interval<Int>) -> Bool {
  consumer_example.consumer_example.spend(
    context(),
    params(),
    None,
    Void,
    OutputReference {
      transaction_id: #"0202020202020202020202020202020202020202020202020202020202020202",
      output_index: 0,
    },
    Transaction {
      ..placeholder,
      reference_inputs: refs,
      validity_range: validity,
    },
  )
}

fn intended() -> ByteArray {
  representative_name(seed_tx)
}

test accepts_the_eligible_holding() {
  spend([reference(0, holding(intended(), 1, live(0)))], from(1000))
}

test accepts_when_the_eligible_holding_is_among_others() {
  let noise = Output {
    address: Address {
      payment_credential: Script(
        #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      ),
      stake_credential: None,
    },
    value: from_lovelace(2000000),
    datum: NoDatum,
    reference_script: None,
  }
  spend(
    [reference(1, noise), reference(0, holding(intended(), 1, live(0)))],
    from(1000),
  )
}

test refuses_a_rival_registrys_token() {
  !spend(
    [reference(0, holding(representative_name(rival_seed_tx), 1, live(0)))],
    from(1000),
  )
}

test refuses_quantity_two() {
  !spend([reference(0, holding(intended(), 2, live(0)))], from(1000))
}

test refuses_parked_and_pending_and_retired_states() {
  !spend(
    [reference(0, holding(intended(), 1, Parked(Hash { epoch: 0, sn: 0 })))],
    from(1000),
  ) && !spend(
    [
      reference(
        0,
        holding(intended(), 1, TerminationPending(Hash { epoch: 0, sn: 0 })),
      ),
    ],
    from(1000),
  ) && !spend([reference(0, holding(intended(), 1, Convicted))], from(1000)) && !spend(
    [reference(0, holding(intended(), 1, Absent))],
    from(1000),
  )
}

test refuses_a_juvenile_holding() {
  !spend([reference(0, holding(intended(), 1, live(1000)))], from(1000))
}

test refuses_without_a_reference_input() {
  !spend([], from(1000))
}

test refuses_without_a_finite_lower_bound() fail {
  expect _verdict: Bool = spend(
    [reference(0, holding(intended(), 1, live(0)))],
    Interval {
      lower_bound: IntervalBound {
        bound_type: NegativeInfinity,
        is_inclusive: True,
      },
      upper_bound: IntervalBound {
        bound_type: PositiveInfinity,
        is_inclusive: True,
      },
    },
  )
  True
}
