# Tasks — #259 flake-lock enforcement

Artifact ceiling: 4,000 bytes and 100 lines.

Boxes are stamped only by the ticket owner after the immutable gate and fresh
independent audit accept the exact candidate.

## S259-1 — uniform lock enforcement

- [ ] **T259-S1-01** Add **MOD-259-GUARD** with fail-closed declared/locked
  reconciliation, invocation classification, caller parity, positive counts,
  and permanent negative controls.
- [ ] **T259-S1-02** Apply `--no-write-lock-file` to every classified primary
  offchain invocation in the root justfile and preserve all existing recipes.
- [ ] **T259-S1-03** Reach the shared guard from root `just ci` and enforce the
  post-gate unchanged-lock assertion.
- [ ] **T259-S1-04** Apply no-write semantics to every direct primary-offchain
  invocation in `.github/workflows/ci.yml` and add its required shared-guard
  step.
- [ ] **T259-S1-05** Delete the `deployPreprod` lock node as a controlled
  mutation, retain the RED receipt, restore the exact lock blob, and retain
  GREEN evidence.
- [ ] **T259-S1-06** Complete the advisory sweep and retain the final
  justfile/workflow census and onchain-gap report.

## Orchestrator-owned acceptance

- [ ] **T259-O-01** Verify the candidate touches every file named by any audit
  finding before authorizing a repair.
- [ ] **T259-O-02** Run a fresh detached-worktree Codex audit against the exact
  candidate, immutable gate, mandate hashes, and full invariant matrix.
- [ ] **T259-O-03** Stamp accepted tasks only after audit PASS, prove the final
  tree equals the audited candidate plus this task stamp, and run fresh final
  receipts for the immutable gate and root `just ci`.
- [ ] **T259-O-04** Push only the accepted final SHA, refresh the issue-linked
  PR, require green CI, and hand off ready-for-review without merging.
