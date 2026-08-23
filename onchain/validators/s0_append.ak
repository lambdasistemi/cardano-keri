//// S0-M02 — append-only record skeleton (Tx-B).
////
//// The staging proof policy is an applied validator parameter, matching
//// `checkpoint_observer.observer_lifecycle`'s `hash_proof_policy`. It is
//// not redeemer data. Closes audit F1 on rejected candidate
//// `224177c969fd7847d2519faa9d1dfaf6803ffa3b` (report
//// `f78713d4c887e5e0525b4987815f08faad3550f84c1103cce77487fa21823547`).

use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/m12/record.{apply_record_append}
use cardano_keri/m12/types.{HistoricalProof, RecordState}

pub type AppendRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof: HistoricalProof,
}

validator s0_append(staging_proof_policy: PolicyId) {
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
      staging_proof_policy,
      redeemer.proof,
      tx,
    )
    new.event_count == old.event_count + 1
  }

  else(_) {
    fail
  }
}
