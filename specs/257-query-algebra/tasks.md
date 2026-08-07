# Tasks — #257 one chain-query algebra

Artifact ceiling: 6,000 bytes and 150 lines.

Boxes are stamped only by the ticket orchestrator after the immutable gate and
independent auditor accept the exact candidate. The commit owner records RED,
GREEN, and mutation receipts in its append-only status.

## S257-1 — algebra and component boundary

- [ ] **T257-S1-01** Add the provider-neutral `chain-query` component and the
  operation/program surface from **DAT-257-OP** and **FUN-257-CURRENT** through
  **FUN-257-WATERMARK**.
- [ ] **T257-S1-02** Promote only the shared result/locator types named by
  **PROMOTE-257-01**; keep provider-only historical response types downstream.
- [ ] **T257-S1-03** Move Koios implementation and provider construction to
  **MOD-257-KOIOS**, preserving supported behavior and explicit source errors.
- [ ] **T257-S1-04** Move executable/runtime composition ownership to
  **MOD-257-COMPOSITION** so deployment has no concrete-provider dependency.
- [ ] **T257-S1-05** Remove dead exported `queryScriptRedeemers` and
  `queryTransactionUtxos`; retain `queryAssetHistory` only for its live #177
  read-backend caller.
- [ ] **T257-S1-06** Add `query-algebra-check` and make its component/import
  guard fail for a deliberate forbidden builder dependency before restoration.

## S257-2 — local whole-program transaction

- [ ] **T257-S2-01** Implement **FUN-257-LOCAL-TRANSLATE** from the free program
  to existing `Indexer.Query.Tx` primitives without an `IO` escape.
- [ ] **T257-S2-02** Extend **FUN-257-WATERMARK-TX** to return the matching stored
  slot/hash point and preserve the explicit cold-store case.
- [ ] **T257-S2-03** Instrument the local runner and prove one whole program
  causes exactly one existing transaction-runner invocation.
- [ ] **T257-S2-04** Add the concurrent block-application property for
  **INV-257-ATOMIC** and **INV-257-WATERMARK**.
- [ ] **T257-S2-05** Apply an intentional split-run mutation, capture the named
  property failure outside Git, restore it, and record red/green receipt hashes.

## S257-3 — registration end to end

- [ ] **T257-S3-01** Define **DAT-257-REGISTRATION-SNAPSHOT** and
  **FUN-257-REGISTRATION-PROGRAM** for registration's current-state inputs.
- [ ] **T257-S3-02** Replace registration query callback/provider parameter
  threading with one interpreter selected at **MOD-257-COMPOSITION**.
- [ ] **T257-S3-03** Change premint/register builder boundaries to consume named
  resolved snapshots and prove they perform no mid-build query.
- [ ] **T257-S3-04** Supply settlement only through **FUN-257-OBSERVE** after
  submission, preserving timeout and existing production-default behavior.
- [ ] **T257-S3-05** Assert Koios registration snapshots expose legacy
  sequential consistency and never atomic-local consistency.
- [ ] **T257-S3-06** Pass focused regression coverage, `query-algebra-check`, and
  the immutable gate; return one squashed candidate commit with task trailers.

## Orchestrator-owned acceptance

- [ ] **T257-O-01** Verify Slice 0 inventory evidence and #241 disposition remain
  accurate at the candidate revision.
- [ ] **T257-O-02** Run a fresh detached-worktree commit audit against the exact
  candidate and frozen gate/model hashes.
- [ ] **T257-O-03** Stamp accepted task boxes without changing behavior, run the
  final receipt-backed immutable gate and full root `just ci`, and require an
  empty worktree.
- [ ] **T257-O-04** Push only the accepted SHA, keep the issue-linked PR draft
  until all checks are green, then mark ready for review without merging.
