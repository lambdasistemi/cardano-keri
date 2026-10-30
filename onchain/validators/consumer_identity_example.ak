//// Example relying contract for the consumer predicate on the concrete
//// identity bytes (#343): `consumer_example` with the Lean concrete
//// interpretation (`consumer_identity_bytes`) in place of the declared test
//// layout. Not for mainnet.
////
//// The registry name, the active name and the representative asset a holding
//// must carry are computed here from the state policy, the seed and the AID
//// the contract fixes, byte for byte as the Lean model computes them.
////
//// Declared limits, as for `consumer_example`:
////   - the datum decoder stays the declared test choice
////     (`consumer_test_interpretation.decode`); the Lean keeps it an input;
////   - the environment is the context itself: a script cannot observe the
////     network or resolve a release;
////   - `now` is the lower bound of the transaction validity interval; a
////     transaction without a finite lower bound is refused;
////   - the holding is any reference input satisfying the predicate.

use aiken/collection/list
use aiken/interval.{Finite}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/consumer.{Context, Environment, Params, consumable_holding}
use cardano_keri/consumer_identity_bytes as concrete
use cardano_keri/consumer_test_interpretation as decoder

/// The earliest time the transaction can be valid at; the chain is at or past it.
fn now_of(tx: Transaction) -> Int {
  expect Finite(lower) = tx.validity_range.lower_bound.bound_type
  if tx.validity_range.lower_bound.is_inclusive {
    lower
  } else {
    lower + 1
  }
}

validator consumer_identity_example(context: Context, params: Params) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _self: OutputReference,
    tx: Transaction,
  ) {
    let environment = Environment {
      network: context.network,
      release: Some(context.release),
    }
    let now = now_of(tx)
    list.any(
      tx.reference_inputs,
      fn(input) {
        consumable_holding(
          concrete.hash,
          concrete.code,
          concrete.key_of,
          decoder.decode,
          context,
          environment,
          params,
          now,
          input.output,
        )
      },
    )?
  }

  else(_) {
    fail
  }
}
