//// Schema-layer enforcement predicate ex-unit measurements (#106 Slice 6).
////
//// Mirrors the spike-88 `measurements.ak` pattern: each `test measure_*` runs a
//// real enforcement predicate on a committed keripy fixture vector
//// (`enforcement_vectors.ak`), so `aiken check --plain-numbers` reports the
//// mem/cpu of the SCHEMA-LAYER predicate only — per-signature
//// `verify_ed25519_signature`, per-revealed-key `next_key_digest` (blake3,
//// freeze), threshold `evaluate`, and the list comparisons. The full
//// SAID-recomputation / CESR-slice spend-context cost is #24/#109's and is NOT
//// measured here (the predicates take already-decoded evidence). See
//// `specs/106-enforcement/MEASUREMENTS.md` for the reported cells + budget verdict.

use cardano_keri/checkpoint/enforcement.{
  ConvictValid, FreezeValid, convict_predicate, freeze_predicate,
}
use cardano_keri/checkpoint/enforcement_vectors as vec

// fork — 1 controller key (convict): 1 `verify_ed25519_signature` over
// `event_bytes` + the same-reveal / forward-commitment list comparisons.
test measure_convict_fork() {
  convict_predicate(vec.fork_convict_tip, vec.fork_convict_evidence) == ConvictValid
}

// honest_2key — 2 controllers, witnessless freeze: 2 controller sig verifies + 2
// `next_key_digest` (blake3 over the 44-byte qb64) + `evaluate` (Unweighted 2).
test measure_freeze_honest2() {
  freeze_predicate(vec.honest2_freeze_tip, vec.honest2_freeze_evidence) == FreezeValid
}

// lag — 1 controller + 1 witness receipt, witnessed freeze: 1 controller sig +
// 1 `next_key_digest` + `evaluate` (Unweighted 1) + 1 witness sig verify.
test measure_freeze_lag() {
  freeze_predicate(vec.lag_freeze_tip, vec.lag_freeze_evidence) == FreezeValid
}

// honest_7key — 3 revealed of 7 committed, GLEIF 3-of-7 reserve freeze: 3
// controller sig verifies + 3 `next_key_digest` (blake3) + `evaluate` over a
// 7-position weighted threshold.
test measure_freeze_honest7() {
  freeze_predicate(vec.honest7_freeze_tip, vec.honest7_freeze_evidence) == FreezeValid
}
