# Tasks: enforcement wiring — conviction as penalty and record (#116)

Completed boxes record commits already in branch history. A-010 restores S5's
simple Convict behavior, supersedes S3/S6, and reduces current acceptance to
two corrective slices: S7 deletion/fixed bond and S8 measurements.

## Slice 1 — keripy enforcement offsets (FROZEN)

- [X] T116-S1 Export `t/i/s/d/k/kt/n/nt/bt` offsets and preserve existing event
      bytes, controller signatures, and witness receipts.
- [X] T116-S1 Regeneration is drift-stable; full gate green; committed with
      exactly `Tasks: T116-S1`.

## Slice 2 — wire binding and predicate corrections (FROZEN)

- [X] T116-S2 Land shared Haskell/Aiken EE0–EE9 binding and vectors.
- [X] T116-S2 Count distinct witness indices and include `kt` as a Convict
      conflict axis; gate green; committed with exactly `Tasks: T116-S2`.

## Slice 3 — registration registry (COMPLETED, SUPERSEDED BY A-010)

- [X] T116-S3 Historical commit delivered append-on-Register MPFS unicity;
      A-010 requires its complete deletion in S7.
- [X] T116-S3 Historical gate green; committed with exactly `Tasks: T116-S3`.

## Slice 4 — Freeze and thaw (FROZEN)

- [X] T116-S4 ACTIVE Freeze preserves exact datum/value at FROZEN; ordinary
      Advance admits ACTIVE|FROZEN and returns ACTIVE.
- [X] T116-S4 W/R/F12-L/T1 regressions and full gate pass; committed with
      exactly `Tasks: T116-S4`.

## Slice 5 — sovereign Convict (RESTORED/FROZEN BY A-010)

- [X] T116-S5 ACTIVE|FROZEN Convict binds live evidence, writes the exact
      token-scoped tombstone, releases the bond from script custody, and keeps
      F11 fail-closed.
- [X] T116-S5 Full gate green; committed with exactly `Tasks: T116-S5`.

## Slice 6 — registry-era measurements (COMPLETED, SUPERSEDED BY A-010)

- [X] T116-S6 Historical Register/Freeze/Convict/registry matrix recorded;
      final acceptance is replaced by S8.
- [X] T116-S6 Historical gate green; committed with exactly `Tasks: T116-S6`.

## Slice 7 — delete unicity and fix registration bonds

- [ ] T116-S7 RED proves registry-free Register and post-conviction same-AID
      re-registration fail on the delivered S3 design, while an applied
      `d_reg = 4_999_999` is not yet rejected.
- [ ] T116-S7 Delete the Haskell/Aiken unicity model, generator, vectors,
      registry tests, recipes, cabal/test wiring, bootstrap/thread/redeemer,
      applied seed parameter, and REGISTRY role without weakening other gates.
- [ ] T116-S7 Preserve #114 R1–R8 with `Register { evidence }`, enforce the
      deployment-fixed `d_reg >= 5_000_000` before mint and spend dispatch,
      share the floor predicate and generated boundary values across Haskell/
      Aiken, and pass fresh/repeated underfunding negatives plus duplicate/
      re-registration positives at the reference 1,000 ADA fixture value.
- [ ] T116-S7 Preserve S1/S2/S4/S5, Close fail-closed, and retained role bytes;
      prove net LOC decreases; full gate green; commit exactly
      `refactor(116): drop unicity and fix registration bonds` with exactly
      `Tasks: T116-S7`.

## Slice 8 — replacement sovereign-path measurements

- [ ] T116-S8 Measure final Register (2-key/witnessed/7-key), Freeze
      (lag/2-key/7-key), Convict (ACTIVE/FROZEN), and FROZEN→ACTIVE Advance
      ACCEPT paths with `d_reg = 1_000_000_000`.
- [ ] T116-S8 Replace registry-era acceptance tables in
      `specs/116-enforcement/MEASUREMENTS.md`; retain a concise superseded note,
      raw units, percentages, methodology, and the SAID comparison.
- [ ] T116-S8 Every final row retains at least 25.00% memory and CPU headroom,
      or STOP and open an epic Q-file; no weakened fixture or live-node claim.
- [ ] T116-S8 Full gate green; commit exactly
      `test(116): remeasure sovereign enforcement` with exactly
      `Tasks: T116-S8`.

## Orchestrator lifecycle

- [X] A-010 consumed; A-009 withdrawn; Q-010 closed with self-conviction as a
      benign documented residual and zero added mechanism.
- [ ] Q-011 ratifies the simplified spec, two-slice plan, and task coverage
      before any code dispatch.
- [ ] Each corrective slice is accepted by full-file owner review plus a fresh
      `./gate.sh` before task boxes are checked and the amended commit is pushed.
- [ ] Finalization requires a new explicit epic-owner mark-ready ruling;
      current scope does not drop `gate.sh`, mark ready, merge, or re-finalize.
