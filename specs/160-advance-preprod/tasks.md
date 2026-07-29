# Story 160 tasks

- [x] T160-S0 Verify #159 closed after PR #172, clean its merged worktree and
  branch, create the isolated #160 branch, and start the inherited `just ci`
  baseline.
- [x] T160-S1 RED/GREEN genuine keripy 1.3.5 multi-message KEL parsing for a
  witnessed 2-of-5 rotation: event bytes, offsets, lineage, native signatures,
  witness delta, receipts, and successor state.
- [x] T160-S2 RED/GREEN exact ACTIVE checkpoint decoding and deterministic
  binary `AdvanceMessage` signing packages, including indexed controller
  signature ingestion and verification.
- [x] T160-S3 RED/GREEN the `opt-env-conf` `advance` surface and exact
  `cardano-cli` thin-spend plus `observer-advance` reference transaction plan.
- [x] T160-S4 Prove under-signed, under-witnessed, and stale replay packages
  fail at the applied validator boundary while complete evidence settles.
- [x] T160-S5 Run the full inception→register→rotate→advance preprod journey,
  capture the raw transcript with settled txids, and verify seq-1 status.
- [x] T160-S6 Add the rotate guide, transcript/package integrity CI, and embed
  the committed raw full-journey transcript byte-for-byte in the PR body.
- [ ] T160-S7 Run `./gate.sh`, push, wait for all GitHub checks, audit PR
  metadata/worktree cleanliness, and park for operator merge.
