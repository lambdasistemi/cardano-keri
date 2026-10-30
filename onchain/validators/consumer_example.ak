//// Example relying contract for the consumer predicate (#343).
////
//// A spending validator parameterised by the consumer context (network,
//// release, seed, AID) and the checkpoint parameters. It spends only if some
//// reference input of the transaction is a consumable holding for that
//// context, using the declared test interpretation: test interpretation, not
//// the registry byte layout.
////
//// Declared limits of this example:
////   - the environment is the context itself: a script cannot observe the
////     network or resolve a release, so the network and release it is
////     parameterised with stand for the trusted integration's observation;
////   - `now` is the lower bound of the transaction validity interval, in the
////     same time unit as the datum's `born_at` and the parameter `w`; a
////     transaction without a finite lower bound is refused;
////   - the holding is any reference input satisfying the predicate; others
////     are skipped at the credential clause.

use aiken/collection/list
use aiken/interval.{Finite}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/consumer.{Context, Environment, Params, consumable_holding}
use cardano_keri/consumer_test_interpretation as interpretation

/// The earliest time the transaction can be valid at; the chain is at or past it.
fn now_of(tx: Transaction) -> Int {
  expect Finite(lower) = tx.validity_range.lower_bound.bound_type
  if tx.validity_range.lower_bound.is_inclusive {
    lower
  } else {
    lower + 1
  }
}

validator consumer_example(context: Context, params: Params) {
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
          interpretation.hash,
          interpretation.code,
          interpretation.key_of,
          interpretation.decode,
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
