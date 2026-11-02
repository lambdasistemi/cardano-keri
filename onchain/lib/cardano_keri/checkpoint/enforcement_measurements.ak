//// Schema-layer enforcement predicate ex-unit measurements (#106 Slice 6).
////
//// Mirrors the spike-88 `measurements.ak` pattern: each `test measure_*` runs a
//// real enforcement predicate on a committed keripy fixture vector
//// (`enforcement_vectors.ak`), so `aiken check --plain-numbers` reports the
//// mem/cpu of the SCHEMA-LAYER predicate only — per-signature
//// `verify_ed25519_signature`, threshold `evaluate`, and the list comparisons. The full
//// SAID-recomputation / CESR-slice spend-context cost is #24/#109's and is NOT
//// measured here (the predicates take already-decoded evidence). See
//// `specs/106-enforcement/MEASUREMENTS.md` for the reported cells + budget verdict.

use cardano_keri/checkpoint/enforcement.{ConvictValid, convict_predicate}
use cardano_keri/checkpoint/enforcement_vectors as vec

// fork — 1 controller key (convict): 1 `verify_ed25519_signature` over
// `event_bytes` + the same-reveal / forward-commitment list comparisons.
test measure_convict_fork() {
  convict_predicate(vec.fork_convict_tip, vec.fork_convict_evidence) == ConvictValid
}
