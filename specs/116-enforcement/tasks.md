# Tasks: enforcement wiring (#116)

## Slice 1 — keripy enforcement offsets

- [X] T116-S1 Export `t/i/s/d/k/kt/n/nt/bt` offsets for fork,
      fork-witnessed, and lag evidence from the hermetic generator.
- [X] T116-S1 Prove existing event bytes, controller signatures, and witness
      receipts are byte-unchanged; regeneration is drift-stable.
- [X] T116-S1 Gate green; commit with exactly `Tasks: T116-S1`.

## Slice 2 — wire binding and predicate corrections

- [X] T116-S2 Haskell `EnforcementEvidence` + EE0–EE9 binding (including the
      1024-byte V1 cap) to decoded
      `EventEvidence`; no `said_blank` or SAID recomputation.
- [X] T116-S2 Haskell predicates count distinct witness indices and treat `kt`
      as a Convict conflict axis; RED vectors include duplicate receipt and
      kt-only conflict.
- [X] T116-S2 Aiken mirror + shared generated vectors; byte- and verdict-parity
      for positives and every wire mutation.
- [X] T116-S2 Gate green; commit with exactly `Tasks: T116-S2`.

## Slice 3 — mint-once MPFS registry

- [X] T116-S3 Shared unicity model/vectors: registry thread-name, role hashes,
      set key/marker, empty root, and valid/invalid absence transitions at
      declared proof depths.
- [X] T116-S3 `BootstrapRegistry` consumes the applied `registry_seed`, mints
      one permanently-caged thread token, and creates one empty REGISTRY state.
- [X] T116-S3 Register atomically consumes/continues the registry state and
      inserts `deriveAidAssetName(D.cesr_aid)`; `RecordRegistration` requires
      the paired exact Register mint.
- [X] T116-S3 U1–U5 full-context vectors: absent/wrong gate, bad proof/root,
      stale race, duplicate mint, reservation attempt, thread escape/burn, and
      second bootstrap; existing R1–R8 regressions green.
- [X] T116-S3 Gate green; commit with exactly `Tasks: T116-S3`.

## Slice 4 — Freeze and thaw

- [X] T116-S4 ACTIVE Freeze wire evidence invokes EE0–EE9 +
      `freeze_predicate`; exact FROZEN address, same complete value/token, and
      byte-identical V1 datum required.
- [X] T116-S4 Advance accepts ACTIVE or FROZEN input and always returns ACTIVE;
      no standalone thaw, no TOMBSTONE/REGISTRY/unknown-role admission.
- [X] T116-S4 W/R/F12-L/T1 transaction-boundary negatives and Register/Advance
      regressions green.
- [X] T116-S4 Gate green; commit with exactly `Tasks: T116-S4`.

## Slice 5 — Convict and tombstone terminality

- [ ] T116-S5 ACTIVE|FROZEN Convict invokes EE0–EE9 + `convict_predicate` and
      creates the exact TOMBSTONE token/record/min-ADA-only output.
- [ ] T116-S5 Registration deposit remainder is released from state as bounty;
      own-policy mint/burn and retained extra value reject.
- [ ] T116-S5 F1b/F3b/F11/F13-L full-context vectors, including every redeemer
      against TOMBSTONE and post-conviction re-registration.
- [ ] T116-S5 Close remains fail-closed; Register/Advance/Freeze regressions
      green.
- [ ] T116-S5 Gate green; commit with exactly `Tasks: T116-S5`.

## Slice 6 — final measurement evidence

- [ ] T116-S6 Measure Freeze lag/2-key/7-key and witnessed Convict from ACTIVE
      and FROZEN on the real handler ACCEPT paths.
- [ ] T116-S6 Measure registry bootstrap and aggregate Register +
      RecordRegistration at 2-key/witnessed/7-key and MPFS depths 0/8/16.
- [ ] T116-S6 Record raw memory/CPU, percentages, methodology, and the SAID
      non-recomputation comparison in `MEASUREMENTS.md`.
- [ ] T116-S6 ≥25.00% headroom on both axes for every required cell, or STOP +
      epic Q-file before commit; no weakened checks or depth substitution.
- [ ] T116-S6 Gate green; commit with exactly `Tasks: T116-S6`.

## Orchestrator finalization

- [ ] Spec checkpoint ratified by epic-owner A-file before `gate.sh` creation or
      Slice 1 dispatch.
- [ ] Every slice accepted by full-file orchestrator review + fresh `./gate.sh`
      before its task boxes are checked and branch is pushed.
- [ ] Finalization audit proves task-trailer bijection, no uncommitted changes,
      current HEAD pushed, PR body/checklist current, and CI green.
- [ ] BLOCKED mark-ready Q-file answered by epic owner before `gh pr ready`;
      orchestrator never merges.
