# Tasks — #262 ChainQuery-only write acquisition

Artifact ceiling: 5,000 bytes and 140 lines.

## S262-1 — algebra-only write acquisition

- [ ] **T262-S1-01** Add and test the validated exact-output locator.
- [ ] **T262-S1-02** Add exact-output and board-with-output program families,
  functor mapping, factory fields, and exhaustive dispatch.
- [ ] **T262-S1-03** Repair every concrete and test interpreter construction
  site explicitly.
- [ ] **T262-S1-04** Implement local neutral output decoding and exact-output
  lookup behind the local interpreter only.
- [ ] **T262-S1-05** Implement the all-or-nothing local board/output operation
  with identity pairing and fail-closed decoding.
- [ ] **T262-S1-06** Account explicitly for both operations in the Koios
  interpreter without introducing write-path provider reachability or
  fallback.
- [ ] **T262-S1-07** Replace board post/update/retire build bundles with one
  composed algebra program per verb.
- [ ] **T262-S1-08** Replace publication and signing-package checkpoint reads
  with local-interpreted algebra programs.
- [ ] **T262-S1-09** Replace advance and close submit bundles with one monadic
  algebra program that derives the exact checkpoint locator inside the same
  snapshot.
- [ ] **T262-S1-10** Withdraw raw build-acquisition exports and eliminate every
  direct write-composition `Transaction` route.
- [ ] **T262-S1-11** Add the permanent sole-route property; demonstrate a
  direct-acquisition mutation RED and restored GREEN with retained receipt.
- [ ] **T262-S1-12** Change #240's executing deferred-disposition check into a
  met-disposition check; demonstrate restored-deferral RED and GREEN.
- [ ] **T262-S1-13** Preserve #240's provider boundary, atomic snapshot,
  acquisition parity, fail-closed decode, and focused non-zero coverage.
- [ ] **T262-S1-14** Run focused gates, `ci-offchain`, final root `just ci`,
  format/hlint, and exact path/tree verification within budget.

## Orchestration

- [ ] **O-262-01** Freeze mandate, gate, negative controls, fences, and owner
  packet.
- [ ] **O-262-02** Accept a hash-bound owner submission through a fresh
  independent auditor with every blocking campaign row terminal.
- [ ] **O-262-03** Stamp tasks, create the predetermined final commit, and
  verify the audited tree plus only this task stamp.
- [ ] **O-262-04** Push the exact verified SHA, refresh the draft PR, complete
  finalization audit, and hand off ready for review.
