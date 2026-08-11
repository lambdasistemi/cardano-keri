# Tasks — #232 bounded phase-2 collateral loss

Artifact ceiling: 5,000 bytes and 140 lines.

## S232-1 — bounded collateral safety boundary

- [ ] **T232-S1-01** Add the fixed 5,000,000-lovelace collateral contract and
  typed collateral-safety failures to the shared transaction runtime.
- [ ] **T232-S1-02** Add exact final-body validation for protocol arithmetic,
  absolute ceiling, input identity/disjointness, return destination/value,
  min-UTxO validity, and conservation.
- [ ] **T232-S1-03** Add a Plutus build kernel that owns collateral resolution,
  explicit funding-address return, validation, and pre-sign rejection.
- [ ] **T232-S1-04** Migrate registration premint/register to the bounded kernel.
- [ ] **T232-S1-05** Migrate advance with both observer-registration branches to
  the bounded kernel.
- [ ] **T232-S1-06** Migrate close while keeping collateral return distinct from
  its ordinary change address.
- [ ] **T232-S1-07** Migrate endpoint-board post/update/retire while keeping
  collateral return distinct from ordinary change.
- [ ] **T232-S1-08** Retain script-free Publisher behavior with absent
  collateral fields.
- [ ] **T232-S1-09** Add permanent shared-kernel and per-verb assertions that
  state and enforce the 5,000,000-lovelace maximum.
- [ ] **T232-S1-10** Add named fail-closed cases for missing, oversized,
  underfunded, non-returning, misdirected, and inconsistent collateral.
- [ ] **T232-S1-11** Demonstrate cap-removal RED and restored GREEN with retained
  hash-bound receipts.
- [ ] **T232-S1-12** Preserve #240 no-provider and #262 sole-route proofs and run
  focused gates, `ci-offchain`, final root `just ci`, format, and hlint within
  the build budget.

## Orchestration

- [ ] **O-232-01** Freeze mandate, gate, negative controls, fences, campaign
  ledger, and owner packet.
- [ ] **O-232-02** Accept a hash-bound owner submission through a fresh
  independent auditor with every blocking campaign row terminal.
- [ ] **O-232-03** Stamp tasks, create the predetermined final commit, and verify
  the audited tree plus only this task stamp.
- [ ] **O-232-04** Push the exact verified SHA, refresh the draft PR, complete
  finalization audit, and hand off ready for review.
