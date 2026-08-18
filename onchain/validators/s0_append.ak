//// S0-M02 — append-only record skeleton (Tx-B).

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/record.{apply_record_append}
use cardano_keri/m12/types.{HistoricalProof, RecordState}

pub type AppendRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
  proof: HistoricalProof,
}

validator s0_append {
  spend(
    maybe_datum: Option<RecordState>,
    redeemer: AppendRedeemer,
    _self: OutputReference,
    tx: Transaction,
  ) {
    expect Some(old) = maybe_datum
    expect Some(new) = apply_record_append(
      old,
      redeemer.raw_event,
      redeemer.cesr_aid,
      redeemer.proof_policy,
      redeemer.proof,
      tx,
    )
    new.event_count == old.event_count + 1
  }

  else(_) {
    fail
  }
}
