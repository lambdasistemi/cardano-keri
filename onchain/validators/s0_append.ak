//// S0-M02 — append-only record skeleton.

use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/record.{apply_record_append}
use cardano_keri/m12/types.{HistoricalProof, ParsedEvent, RecordState}

pub type AppendRedeemer {
  event: ParsedEvent,
  proof: HistoricalProof,
}

validator s0_append {
  spend(
    maybe_datum: Option<RecordState>,
    redeemer: AppendRedeemer,
    _self: OutputReference,
    _tx: Transaction,
  ) {
    expect Some(old) = maybe_datum
    expect Some(new) = apply_record_append(old, redeemer.event, redeemer.proof)
    new.event_count == old.event_count + 1
  }

  else(_) {
    fail
  }
}
