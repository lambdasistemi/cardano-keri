# Tasks — R1 event-derived MPF key

One OWNER slice: `R1-S01`. The ticket owner checks these only after a fresh
auditor passes the exact candidate.

- [ ] **T001** Declare relied-on legacy invariants, then commit one complete
  assertion-level RED bundle for R1-I01–R1-I12.
- [ ] **T002** Establish R1-M01 and R1-F01/F02/F03 with the exact V1 preimage,
  qualified values, canonical sequence integer, and fail-closed boundary.
- [ ] **T003** Carry R1-D04 through verified record binding and insert the
  verified SAID at that derived key.
- [ ] **T004** Narrow `HistoricalProof` to the sibling proof and remove all
  reads of `key`, `location`, and `prior_snapshot_digest`.
- [ ] **T005** Preserve cursor and S0 validator reachability without restoring
  removed proof authority or deciding R2/R3 semantics.
- [ ] **T006** Pin independent accepted vectors for every supported CESR code
  and both prior constructors.
- [ ] **T007** Permanently kill the `i`, numeric-`s`, prior-tag, `p`, `d`,
  domain, constructor-order, and submitter-key mutation classes.
- [ ] **T008** Prove two rival SAIDs at one location coexist and remain
  retrievable.
- [ ] **T009** Supply the measured-source recipe/manifest and changed
  non-onchain flake-input declaration required by the frozen gate.
- [ ] **T010** Produce a clean local candidate, compact invariant receipt, and
  frozen handoff; run only separately authorized build and CI legs.
- [ ] **T011** Close F1 with a deployment-fixed append proof policy following
  the existing `checkpoint_observer` precedent and a permanent caller-policy
  negative property.
- [ ] **T012** Close F2 with distinct staging `i`/`d` handling and a
  present-prior rival proof where both events independently cross raw decode,
  staging, provenance, binding, and validator append, both MPF entries are
  independently retrieved, and the dressed sources are genuinely rival; a
  lower-helper shortcut or `d`-only source change is not acceptance evidence.
- [ ] **T013** Close F3 with manifest-derived accepted-code coverage and prove
  the future-code-plus-dead-string negative control goes RED.
- [ ] **T014** Re-measure the parameterized append member, supersede its stale
  S0 size row with exact source identity, and retain the size-only caveat.
- [ ] **T015** Preserve the carried KILLED evidence for R1-I02--I06/I10 and
  terminally audit every remaining row over the full `84e3b715..candidate`
  delta; prior green receipts are context only.
- [ ] **T016** Preflight every gate, wrapper, and audit instrument with visible
  normal cleanup, body-failure cleanup, and seeded teardown failure before its
  semantic verdict is trusted.
