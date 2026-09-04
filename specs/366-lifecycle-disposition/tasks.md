# Tasks

## Lifecycle disposition

- [ ] **T366-001** Delete the three superseded Lifecycle modules and remove
  their public-root imports.
- [ ] **T366-002** Convert all 21 historical traceability rows to explicit,
  owner-linked retirement records with no stale `PENDING`.
- [ ] **T366-003** Update the traceability/CI driver and direct documentation
  references to the sole live Checkpoint machine.

## Verification and acceptance

- [ ] **T366-004** Prove the exact gate RED on the undisposed base, then GREEN
  on the candidate: clean build, compiled retired-import rejection, complete
  retirement ledger, zero proof escapes, and axiom-clean live theorems.
- [ ] **T366-005** Pass a fresh Codex-high commit audit and final exact-tree,
  local-gate, remote-CI, and PR-readiness checks.

