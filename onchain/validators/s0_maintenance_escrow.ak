//// S0-M05 — maintenance escrow skeleton.

use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/escrow.{validate_escrow_transition}
use cardano_keri/m12/types.{EscrowAction, EscrowState, EvidenceGrade}

pub type EscrowRedeemer {
  action: EscrowAction,
  grade: EvidenceGrade,
}

validator s0_maintenance_escrow {
  spend(
    maybe_datum: Option<EscrowState>,
    redeemer: EscrowRedeemer,
    _self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(old) = maybe_datum
    validate_escrow_transition(old, redeemer.action, redeemer.grade, tx)
  }

  else(_) {
    fail
  }
}
