//// S0-M06 — staging / proof-token skeleton.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use cardano_keri/m12/staging.{validate_staging_token}
use cardano_keri/m12/types.{ParsedEvent}

pub type StagingRedeemer {
  raw_event: ByteArray,
  claimed: ParsedEvent,
}

validator s0_staging_proof_token {
  mint(redeemer: StagingRedeemer, policy_id: PolicyId, tx: Transaction) {
    validate_staging_token(redeemer.raw_event, redeemer.claimed, policy_id, tx)
  }

  else(_) {
    fail
  }
}
