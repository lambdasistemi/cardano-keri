//// Test-only minting policy: seeded holding, not a registration journey.
////
//// It lets the connected tests put a representative token (and rivals of it)
//// on a holding output at the test application credential. It checks nothing
//// and is never part of the registry; the genuine registration journey
//// belongs to #324. Not for mainnet.

use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}

validator consumer_seed_policy {
  mint(_redeemer: Data, _policy_id: PolicyId, _tx: Transaction) {
    True
  }

  else(_) {
    fail
  }
}
