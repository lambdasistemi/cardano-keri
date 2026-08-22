//// S0-M04 — lineage genesis / successor / close skeleton.

use aiken/primitive/bytearray
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/lineage.{validate_lineage_transition}
use cardano_keri/m12/types.{LineageAction, LineageState}

pub type LineageRedeemer {
  action: LineageAction,
}

validator s0_lineage {
  spend(
    maybe_datum: Option<LineageState>,
    redeemer: LineageRedeemer,
    _self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(new) = validate_lineage_transition(
      maybe_datum,
      redeemer.action,
      tx,
    )
    and {
      bytearray.length(new.event_root) == 32,
      bytearray.length(new.occupancy_root) == 32,
      bytearray.length(new.cursor.keys_digest) > 0 || new.closed,
    }
  }

  else(_) {
    fail
  }
}
