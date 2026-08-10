# Tasks — #240 local-only write tier

Artifact ceiling: 6,000 bytes and 150 lines.

Boxes are stamped only by the ticket owner after a fresh auditor accepts the
exact candidate. Tests are RED before production changes. All tasks belong to
the single OWNER slice **S240-1**.

## Phase 1 — proof foundation

- [x] **T240-S1-01 [US3]** Generate and retain the base-`5bf8498` normalized
  snapshot and canonical transaction-body/ID oracle for every write transaction
  shape using fixed fixtures; record both revision and fixture hashes under the
  ticket runtime root.
- [x] **T240-S1-02 [US1]** Add RED component-boundary and CLI-surface checks that
  reject provider dependencies/imports/settings on the write path, with exact
  source paths in `offchain/cardano-keri.cabal`, `offchain/cli`, and focused
  tests.
- [x] **T240-S1-03 [US2]** Add RED local runner/reference/settlement properties
  covering one transaction per program, no mid-build query, exact reference
  derivation, and temporal observer semantics under `offchain/query-test` and
  `offchain/deployment-test`.

## Phase 2 — provider-free boundary and local capabilities

- [x] **T240-S1-04 [US1]** Split write composition from provider-backed read
  composition in `offchain/cardano-keri.cabal` and `offchain/cli`, leaving the
  write component without Koios or HTTP dependencies.
- [x] **T240-S1-05 [US1]** Replace write-facing provider fields with local
  opt-env-conf store settings in `offchain/cli/Cardano/KERI/Deployment/CLI.hs`
  and its CLI tests; keep read-only provider settings downstream.
- [x] **T240-S1-06 [US2]** Implement bracketed local query scope and exact
  derived reference-script resolution in `offchain/indexer` using existing
  follower-held live outputs and #257 result types.
- [x] **T240-S1-07 [US1]** Implement follower-backed asset, reference, and
  transaction-id settlement probes in `offchain/indexer`/provider-neutral
  settlement ownership without adding a snapshot operation.

## Phase 3 — migrate every write acquisition family

- [x] **T240-S1-08 [US1]** Migrate Registration snapshots and settlement to the
  local interpreter/runtime in `offchain/cli/Cardano/KERI/Deployment/CLI.hs`;
  prove exact source/atomicity and transaction parity.
- [x] **T240-S1-09 [US1]** Migrate current-checkpoint consumers for advance and
  close, including payer/reference inputs and settlement, to one local snapshot
  per build phase; prove both command transaction shapes retain parity.
- [x] **T240-S1-10 [US1]** Migrate Publisher/deploy payer and reference reads
  plus settlement to the local runtime, taking a fresh atomic snapshot per
  published transaction; prove deployment transaction parity.
- [x] **T240-S1-11 [US1]** Migrate endpoint-board deploy/post/update/retire
  payer, catalog, reference, and settlement reads to local snapshots; prove
  post/update/retire transaction parity while leaving board list read-only.

## Phase 4 — permanent proof and acceptance

- [x] **T240-S1-12 [US3]** Compare candidate normalized snapshots and canonical
  transaction bodies/IDs against every base oracle artifact; retain hash-bound
  parity receipts and make mismatch RED.
- [x] **T240-S1-13 [US1]** Add the flake-owned `local-write-path-check`, root
  recipe, non-zero coverage counts, component census, and `ci-offchain` wiring
  in `offchain/flake.nix` and `justfile`, preserving #259 no-write semantics.
- [x] **T240-S1-14 [US1]** Reintroduce one provider dependency/call as a
  controlled mutation, retain compiled RED, restore the candidate, rerun the
  same instrument GREEN, and verify the mutation is absent.
- [x] **T240-S1-15 [US1]** Run the focused per-family verifications and
  `just ci-offchain`, return one clean candidate with receipt and handoff, and
  report the advisory full write-reachability sweep.

## Orchestrator-owned acceptance

- [x] **T240-O-01** Verify the commit owner is parked/clean, dispatch a fresh
  Codex auditor at the exact candidate, and require a hash-bound verdict for
  every blocking invariant.
- [x] **T240-O-02** Stamp accepted task boxes only after audit pass; authorize
  the commit owner to create the one final conventional behavior commit.
- [ ] **T240-O-03** Prove the final tree equals the audited candidate plus only
  this task stamp, run commit/focused/offchain gates through quiet receipts,
  then run root `just ci` once before push.
- [ ] **T240-O-04** Push only the accepted SHA, refresh the issue-linked draft
  PR, verify CI and the `/` disk delta, then mark ready for external review.

## Dependencies and execution

Proof foundation precedes production changes. The component boundary precedes
write migration. Local reference and settlement capabilities precede their
consumers. All transaction-family migrations precede cross-revision parity,
mutation proof, and the final gate. One Claude commit owner owns the complete
slice; fresh Codex auditors certify submissions, so repair and certification
never share a seat.
