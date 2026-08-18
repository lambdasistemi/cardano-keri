//// S0-M03 — validator-derived cursor skeleton (Tx-B).

use aiken/interval
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/cursor.{derive_cursor}
use cardano_keri/m12/types.{CursorState, HistoricalProof}

pub type CursorRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
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
    expect Some(new) = derive_cursor(
      old,
      redeemer.raw_event,
      redeemer.cesr_aid,
      redeemer.proof_policy,
      redeemer.proof,
      now,
      tx,
    )
    new.last_moved_slot == now
  }

  else(_) {
    fail
  }
}
