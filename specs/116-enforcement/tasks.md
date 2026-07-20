# Tasks: enforcement wiring — unicity redesign (#116)

Completed boxes in S1–S6 record commits already present in history. A-009
supersedes the behavior of S3, S5, and S6 without rewriting those commits;
current acceptance requires the open corrective slices S7–S10.

## Slice 1 — keripy enforcement offsets (FROZEN)

- [X] T116-S1 Export `t/i/s/d/k/kt/n/nt/bt` offsets from
      `offchain/test/keri-fixtures/gen_fixtures.py` and its fixtures.
- [X] T116-S1 Prove existing event bytes, controller signatures, and witness
      receipts are byte-unchanged; regeneration is drift-stable.
- [X] T116-S1 Gate green; committed with exactly `Tasks: T116-S1`.

## Slice 2 — wire binding and predicate corrections (FROZEN)

- [X] T116-S2 Haskell/Aiken EE0–EE9 binding and shared vectors in
      `offchain/lib/Cardano/KERI/AID/Checkpoint/Enforcement.hs` and
      `onchain/lib/cardano_keri/checkpoint/enforcement.ak`.
- [X] T116-S2 Count distinct witness indices and include `kt` as a Convict
      conflict axis; duplicate-receipt and kt-only RED vectors pass.
- [X] T116-S2 Gate green; committed with exactly `Tasks: T116-S2`.

## Slice 3 — mint-once registration registry (COMPLETED, SUPERSEDED BY S7/S8)

- [X] T116-S3 Delivered shared append-on-registration model, bootstrap,
      Register/RecordRegistration coupling, and U1–U5 vectors in the original
      S3 files; A-009 rejects the resulting hot-path singleton write.
- [X] T116-S3 Gate green at the historical commit; committed with exactly
      `Tasks: T116-S3`.

## Slice 4 — Freeze and thaw (FROZEN)

- [X] T116-S4 ACTIVE Freeze binds evidence and preserves exact datum/value at
      FROZEN; ordinary Advance admits ACTIVE|FROZEN and returns ACTIVE in
      `onchain/validators/checkpoint.ak`.
- [X] T116-S4 W/R/F12-L/T1 boundary negatives and lifecycle regressions pass.
- [X] T116-S4 Gate green; committed with exactly `Tasks: T116-S4`.

## Slice 5 — terminal Convict (COMPLETED, SUPERSEDED BY S9)

- [X] T116-S5 Delivered ACTIVE|FROZEN Convict and F11-terminal tombstone in
      `onchain/validators/checkpoint.ak`; A-009 supersedes its mint-nothing and
      free-change deposit behavior.
- [X] T116-S5 Gate green at the historical commit; committed with exactly
      `Tasks: T116-S5`.

## Slice 6 — original measurements (COMPLETED, SUPERSEDED BY S10)

- [X] T116-S6 Delivered the original live-path matrix in
      `specs/116-enforcement/MEASUREMENTS.md`; its append-Register and old
      Convict rows remain historical only.
- [X] T116-S6 Gate green at the historical commit; committed with exactly
      `Tasks: T116-S6`.

## Slice 7 — reference-read Register and MPF absence

- [ ] T116-S7 Add the pinned, source-controlled v2.0.0 public `excludes` patch
      at `onchain/patches/mpf-v2.0.0-excludes.patch` and make every Aiken gate
      path apply/assert it idempotently through `justfile`.
- [ ] T116-S7 Convert Register in `onchain/validators/checkpoint.ak` to bind the
      named live REGISTRY reference by exact address + quantity-one thread +
      inline root and prove absence with one traversal; remove
      `RecordRegistration` and every per-registration list write.
- [ ] T116-S7 Regenerate Haskell/Aiken unicity vectors and pass U1–U3 in the
      unicity, registry, checkpoint, and measurement test modules, including
      same-root concurrent absent registration and stale/present negatives;
      add `check-unicity-vectors` to aggregate `just ci` drift enforcement.
- [ ] T116-S7 Full gate green; commit exactly
      `feat(116): make registration read the conviction root` with exactly
      `Tasks: T116-S7`.

## Slice 8 — conviction-list bootstrap and parameter floor

- [ ] T116-S8 Replace registration-era labels with `conviction_seed`,
      `BootstrapConvictionList`, `ConvictionListDatumV1`, and the ratified
      conviction thread/marker domains across the Haskell model, generator,
      Aiken unicity module, validator, and tests.
- [ ] T116-S8 Add BOUNTY role tag `0x03`, `BountyClaimDatumV1`, and the unique
      `(domain, cesr_aid, checkpoint_ref)` right derivation to shared Haskell/
      Aiken vectors without changing existing role bytes.
- [ ] T116-S8 Keep `d_reg` a generic validator parameter, enforce the
      5,000,000-lovelace mechanical floor at every entry point, and pass the
      4,999,999 applied-parameter negative plus one-below-deposit negative;
      use the non-normative 1,000 ADA reference for ordinary fixtures and never
      hardcode either value as the deployed security choice.
- [ ] T116-S8 Pass U4 one-shot/empty/bootstrap/thread confinement and all S7
      registration regressions; full gate green; commit exactly
      `feat(116): bootstrap the parameterized conviction list` with exactly
      `Tasks: T116-S8`.

## Slice 9 — sovereign Convict plus Finalize/Redeem

- [ ] T116-S9 Rework Convict in `onchain/validators/checkpoint.ak` to use the
      applied `d_reg`, mint exactly one unique bearer right, keep the F11
      tombstone floor/token terminal, and create a dedicated BOUNTY claim that
      backs the whole checkpoint surplus with separately funded min-ADA/fees.
- [ ] T116-S9 Implement absent-mode Finalize as a welded right burn + claim
      spend + exact payout + live REGISTRY consume/insert/successor, and
      present-mode Redeem as the same burn/claim/payout against exact
      reference-read membership with no root write.
- [ ] T116-S9 Pass B1/B2, P1–P3, X1/X2, F11, and F13-L full-context tests in
      `onchain/validators/checkpoint_registry_tests.ak` and
      `onchain/validators/checkpoint_tests.ak`, including multi-right same-AID,
      different bearers, retry after first insertion, and replay rejection.
- [ ] T116-S9 Preserve Freeze/thaw, R1–R8, roles, distinct receipts, `kt`, and
      Close fail-closed; full gate green; commit exactly
      `feat(116): weld conviction bounties to finalization` with exactly
      `Tasks: T116-S9`.

## Slice 10 — replacement measurements

- [ ] T116-S10 Measure complete ACCEPT transactions in
      `onchain/validators/checkpoint_measurements.ak`: Freeze; Convict with
      right/claim; bootstrap; reference-read Register at depths 0/8/16; absent
      Finalize and present Redeem at depths 0/8/16 for one and multiple rights,
      all with reference `d_reg = 1_000_000_000` lovelace.
- [ ] T116-S10 Retain old S6 rows as superseded history and record raw totals,
      percentages, methodology, script-execution sums, headroom, and the SAID
      non-recomputation comparison in `specs/116-enforcement/MEASUREMENTS.md`.
- [ ] T116-S10 Every required cell retains at least 25.00% memory and CPU
      headroom, or STOP and open an epic Q-file before commit; no weakened
      fixture, depth substitution, or live-node overclaim.
- [ ] T116-S10 Full gate green; commit exactly
      `test(116): remeasure lazy conviction enforcement` with exactly
      `Tasks: T116-S10`.

## Orchestrator lifecycle

- [X] A-009 ratifies live-root binding, sovereign BOUNTY custody, two-mode
      cash-out, the unsharded list, and parameterized `d_reg` with a 5,000,000-
      lovelace mechanical floor; the operator has since confirmed contract-
      deployment selection and a non-normative 1,000 ADA reference value.
- [ ] Every corrective slice S7–S10 is accepted by full-file orchestrator
      review plus a fresh `./gate.sh` before its boxes are checked and its
      amended commit is pushed.
- [ ] A future finalization audit proves task-trailer bijection, clean/pushed
      HEAD, current PR body, and final CI green while preserving `d_reg` as a
      contract-deployment parameter rather than a compiled security constant.
- [ ] Finalization requires a new explicit epic-owner mark-ready ruling before
      `gh pr ready`; this redesign pass does not drop `gate.sh`, mark ready,
      merge, or re-finalize PR #121.
