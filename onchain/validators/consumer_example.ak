//// Example relying contract for the consumer predicate (#343): placeholder
//// that spends nothing, replaced by the predicate-backed validator.

use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/consumer.{Context, Params}

validator consumer_example(_context: Context, _params: Params) {
  spend(
    _datum: Option<Data>,
    _redeemer: Data,
    _self: OutputReference,
    _tx: Transaction,
  ) {
    False
  }

  else(_) {
    fail
  }
}
