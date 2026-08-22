//// S0-M09 — adopted reference-cursor consumer skeleton.

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/reference_consumer.{validate_reference_consumer}
use cardano_keri/m12/types.{CursorPolicy}

pub type ReferenceConsumerRedeemer {
  policy: CursorPolicy,
  expected_lineage: PolicyId,
}

validator s0_reference_cursor_consumer {
  spend(
    _maybe_datum: Option<Data>,
    redeemer: ReferenceConsumerRedeemer,
    _self: OutputReference,
    tx: Transaction,
  ) {
    validate_reference_consumer(redeemer.policy, redeemer.expected_lineage, tx)
  }

  else(_) {
    fail
  }
}
