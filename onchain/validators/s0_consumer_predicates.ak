//// S0-M08 — compiled measurement host for S0-M07.

use aiken/interval
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/consumer_predicates.{cursor_policy_allows}
use cardano_keri/m12/types.{CursorPolicy, CursorState}

pub type PredicateRedeemer {
  policy: CursorPolicy,
}

validator s0_consumer_predicates {
  spend(
    maybe_datum: Option<CursorState>,
    redeemer: PredicateRedeemer,
    _self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(cursor) = maybe_datum
    expect interval.Finite(now) = tx.validity_range.lower_bound.bound_type
    cursor_policy_allows(redeemer.policy, cursor, now)
  }

  else(_) {
    fail
  }
}
