# Tasks — #232 bounded phase-2 collateral loss

Artifact ceiling: 5,000 bytes and 140 lines.

## S232-1 — bounded collateral safety boundary

- [x] **T232-S1-01** Add the fixed 5,000,000-lovelace collateral contract and
  typed collateral-safety failures to the shared transaction runtime.
- [x] **T232-S1-02** Add exact final-body validation for protocol arithmetic,
  absolute ceiling, input identity/disjointness, return destination/value,
  min-UTxO validity, and conservation.
- [x] **T232-S1-03** Add a Plutus build kernel that owns collateral resolution,
  explicit funding-address return, validation, and pre-sign rejection.
- [x] **T232-S1-04** Migrate registration premint/register to the bounded kernel.
- [x] **T232-S1-05** Migrate advance with both observer-registration branches to
  the bounded kernel.
- [x] **T232-S1-06** Migrate close while keeping collateral return distinct from
  its ordinary change address.
- [x] **T232-S1-07** Migrate endpoint-board post/update/retire while keeping
  collateral return distinct from ordinary change.
- [x] **T232-S1-08** Retain script-free Publisher behavior with absent
  collateral fields.
- [x] **T232-S1-09** Add permanent shared-kernel and per-verb assertions that
  state and enforce the 5,000,000-lovelace maximum.
- [x] **T232-S1-10** Add named fail-closed cases for missing, oversized,
  underfunded, non-returning, misdirected, and inconsistent collateral.
- [x] **T232-S1-11** Demonstrate cap-removal RED and restored GREEN with retained
  hash-bound receipts.
- [x] **T232-S1-12** Preserve #240 no-provider and #262 sole-route proofs and run
  focused gates, `ci-offchain`, final root `just ci`, format, and hlint within
  the build budget.

## Orchestration

- [x] **O-232-01** Freeze mandate, gate, negative controls, fences, campaign
  ledger, and owner packet.
- [x] **O-232-02** Accept a hash-bound owner submission through a fresh
  independent auditor with every blocking campaign row terminal.
- [x] **O-232-03** Stamp tasks, create the predetermined final commit, and verify
  the audited tree plus only this task stamp.
- [x] **O-232-04** Hand off the exact verified SHA with a coherent PR body,
  ready for review. Pushing it and refreshing the remote draft PR remain the
  operator's explicit decision and are deliberately not performed here.

## Status

Local implementation, independent audit, and finalization are complete and
unpushed. The audited candidate is `bfbdf8743b3869afaf81bfcb3455441b8a529300`;
the second independent audit passed it with all five blocking rows KILLED, zero
findings, and no residuals. The worst case a phase-2 script failure can now
cost is **5,000,000 lovelace**.
