//// S0-M06 — Tx-A staging / proof-token policy.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use cardano_keri/m12/staging.{validate_staging_token}

pub type StagingRedeemer {
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  off_i: Int,
  off_d: Int,
}

validator s0_staging_proof_token {
  mint(redeemer: StagingRedeemer, policy_id: PolicyId, tx: Transaction) {
    validate_staging_token(
      redeemer.raw_event,
      redeemer.cesr_aid,
      redeemer.off_i,
      redeemer.off_d,
      policy_id,
      tx,
    )
  }

  else(_) {
    fail
  }
}
