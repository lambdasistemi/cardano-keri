//// S0-M03 — validator-derived cursor skeleton.

use aiken/interval
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/cursor.{derive_cursor}
use cardano_keri/m12/types.{CursorState, HistoricalProof, ParsedEvent}

pub type CursorRedeemer {
  event: ParsedEvent,
  proof: HistoricalProof,
}

validator s0_cursor {
  spend(
    maybe_datum: Option<CursorState>,
    redeemer: CursorRedeemer,
    _self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(old) = maybe_datum
    expect interval.Finite(now) = tx.validity_range.lower_bound.bound_type
    expect Some(new) = derive_cursor(old, redeemer.event, redeemer.proof, now)
    new.last_moved_slot == now
  }

  else(_) {
    fail
  }
}
