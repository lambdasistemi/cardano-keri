//// Example relying contract for the consumer predicate (#343): the Lean
//// concrete identity bytes (`consumer_identity_bytes`) and the Lean datum
//// decoder (`consumer_checkpoint_datum`). Not for mainnet.
////
//// The registry name, the active name and the representative asset a holding
//// must carry are computed here from the state policy, the seed and the AID
//// the contract fixes, byte for byte as the Lean model computes them.
////
//// Declared limits:
////   - the environment is the context itself: a script cannot observe the
////     network or resolve a release;
////   - `now` is the lower bound of the transaction validity interval; a
////     transaction without a finite lower bound is refused;
////   - the holding is any reference input satisfying the predicate;
////   - the pool and the bond amounts are held in the output's value and are
////     not read from it (the datum decodes with a pool of 0).

use aiken/collection/list
use aiken/interval.{Finite}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/consumer.{Context, Environment, Params, consumable_holding}
use cardano_keri/consumer_checkpoint_datum as decoder
use cardano_keri/consumer_identity_bytes as concrete

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
