# Tasks: reopen #116 — freeze-bond state core

A-014 ratified this packet and the epic owner reopened #116. Behavior slices
are RED -> GREEN; measurement and documentation slices are separately gated
driver/navigator commits. Every commit uses the exact `Tasks:` trailer shown
in `plan.md`.

## Dependency barrier

- [X] T116-R0 Epic owner reopens #116, creates its branch from then-current
      `origin/main`, installs `gate.sh`, and confirms no #114/#115/#117 pair is
      dispatched ahead of this dependency.
- [X] T116-R0 Record **NO DEPLOY**: final #116 intentionally closes Register,
      all Advance roles, and Close until the owning tickets land.

## Slice R1 — schema and parity foundation

- [X] T116-R1 RED: add failing Haskell tests for `B` floor/one-below,
      positive `W_freeze`, exact role values, version-tagged
      `ArmedV1 { checkpoint : CheckpointDatumV1, hunter_pkh, deadline }`
      codec/hunter width, finite arm upper endpoint `u`, `u+W_freeze`, and
      ARMED role `0x02`.
- [X] T116-R1 GREEN: implement the smallest Haskell/Aiken freeze-bond model,
      role/datum codec, raw-bound endpoint helpers, generator, and generated
      vectors; wire cabal/Main/just drift gates without inventing a normalized
      "greatest included" time.
- [X] T116-R1 Prove old role hashes and CheckpointDatumV1/TombstoneV1 bytes are
      unchanged, no validator dispatch changed, full gate green, and commit
      exactly `feat(116): model freeze-bond state and deadline` with exactly
      `Tasks: T116-R1`.

## Slice R2 — arm and claim

- [X] T116-R2 RED: full validator contexts expose old arity/direct Freeze,
      absent Claim, invalid time/value/beneficiary cases, and required staging
      closures.
- [X] T116-R2 GREEN: apply `B`/`W_freeze`, classify the exact ArmedV1 wrapper,
      wire ACTIVE->ARMED with complete input Value and
      `deadline=u+W_freeze`, then
      ARMED->FROZEN Claim at lower endpoint `>= deadline` with named exact `B`
      hunter output and continuing Value equal to input minus `B` lovelace;
      close Register/Advance/Convict/Close.
- [X] T116-R2 Preserve unchanged enforcement evidence/predicate, extra
      unrelated inputs, token continuity, minimum ADA, `D_reg`, donated
      surplus/assets, no own-policy mint/burn, and reject every wrong
      role/datum/output/time/value axis.
- [X] T116-R2 Vector the normative bounded-interference family: one Arm per
      behind state, repeated Arm rejection, no early Claim or proof-free
      #116 mutation during the exclusive `W_freeze` window, and exact/late
      Claim boundaries; reserve ordinary Advance for #115.
- [X] T116-R2 Keep stable full-context Arm/Claim test identifiers for the R4
      Lean traceability map; do not claim the abstract model covers datum,
      address, or real-Value axes that these contexts prove.
- [X] T116-R2 Full gate green; commit exactly
      `feat(116): wire armed freeze and bond claim` with exactly
      `Tasks: T116-R2`.

## Slice R3 — conviction routing

- [X] T116-R3 RED: pin staging-closed Convict plus wrong convictor/hunter,
      output-index reuse, under/over-payment, extra-asset/datum, and retained
      bond/deposit negatives.
- [X] T116-R3 GREEN: reopen ACTIVE/ARMED/FROZEN Convict with exact unchanged
      TombstoneV1 and dedicated enterprise outputs (`D+B`, `D`+`B`, or `D`)
      using distinct ARMED indices.
- [X] T116-R3 Preserve EE binding, conflict axes, witness distinctness,
      terminal token, allowed re-registration, and benign self-conviction;
      prove protected `D_reg`/`B` cannot remain free change while unreserved
      surplus may remain ordinary transaction change.
- [X] T116-R3 Keep stable full-context Convict/value-routing identifiers for
      R4 traceability without changing the Lean theorem inventory.
- [X] T116-R3 Full gate green; commit exactly
      `feat(116): route conviction deposits and freeze bonds` with exactly
      `Tasks: T116-R3`.

## Slice R4 — Lean traceability and measurements

- [X] T116-R4 RED: add direct QuickCheck properties for the nine
      per-transition Lean goals and monadic state-machine properties for the
      eight trace/reachability goals, named from corresponding
      `Invariants.lean` seeds; observe failure against the missing pure mirror.
- [X] T116-R4 GREEN: give every Lean `Step` constructor a separately named
      pure Haskell mirror function plus a total dispatcher; add the matching
      Aiken model, generate shared theorem/verdict vectors from Haskell,
      consume them in named Aiken tests, and wire cabal/Main/just test plus
      regeneration gates without opening staged live dispatch.
- [X] T116-R4 Check in `lean/traceability.csv` with four honest-limit `#`
      header statements, the exact three-column data header, and exactly one
      fully populated row per theorem extracted from `Goals.lean`; add
      `scripts/check-lean-traceability.sh` and normal-CI wiring that rejects
      theorem/map cardinality or name drift, duplicate/blank/extra rows,
      nonexistent mapped Haskell properties/Aiken tests, or vector drift.
- [X] T116-R4 Measure full 2-key/7-key Arm, Claim, and ACTIVE/ARMED/FROZEN
      Convict ACCEPT contexts, including conservative-surplus cases; record
      raw memory/CPU, use, and headroom in
      `specs/116-freeze-bond/MEASUREMENTS.md`.
- [X] T116-R4 HARD STOP if any row has less than 25.00% headroom on either
      axis; do not weaken evidence, signers, receipts, event size, or handler.
- [X] T116-R4 Audit exact applied arity, generated parity/drift, staging-closed
      Register/Advance, no registry/batcher/sequencer, 17/17 executable
      theorem rows, and full gate.
- [X] T116-R4 Commit exactly
      `test(116): trace and measure freeze-bond state paths` with
      exactly `Tasks: T116-R4`.

## Slice R5 — freeze lifecycle documentation

- [X] T116-R5 Driver/navigator update only the #116-owned freeze fragments in
      `docs/design/trust-model.md`,
      `docs/blog/self-certifying-identities-on-cardano.md`, and
      `docs/milestones-deck/index.html`.
- [X] T116-R5 Explain ARMED `0x02`, raw validity-range deadlines, exact
      B/D_reg claims, permissionless response/thaw, the economic (not
      cryptographic or bounty-paid) incentive, and donated third-party funds.
- [X] T116-R5 Make the two-invariant theorem the centerpiece: M1 blog central
      argument + state machine + per-move adversarial table; trust-model
      normative advance-totality/bounded-interference rules; deck one-liner
      “anyone can project the public truth; no one can lie about it or lock you
      out of it.”
- [X] T116-R5 State held #117 as CLOSING `0x03` with distinct `W_close`,
      mandatory one-tx ordinary Advance-void, and no cryptographic
      express-close; never reuse `W_freeze` for Close, and leave #114
      registration/#115 normal-advance fragments untouched.
- [X] T116-R5 Run `mkdocs build --strict`, lychee, and the full gate; commit
      exactly `docs(116): explain the bonded freeze lifecycle` with exactly
      `Tasks: T116-R5`.

## Slice R6 — staged checkpoint devnet boundary

- [ ] T116-R6 Extend `offchain/e2e` with production-shaped checkpoint builders
      for Register, Arm, Advance response, Claim, Thaw, and Close, following
      the existing `CageTxBuilder`/`withDevnet` pattern and real validity-range
      slot-to-POSIX-ms conversion.
- [ ] T116-R6 Run a real-node fail-closed staging smoke that submits Register,
      Advance, and Close to the applied #116 validator and asserts all three
      are rejected by the ledger.
- [ ] T116-R6 Check in compiled, named Arm->response-before-deadline and
      Arm->Claim-at/after-deadline->Thaw scenarios as explicitly pending on
      #114 Register and #115 Advance; never use a fixture validator, bypass
      mint, injected state, or mock to manufacture a positive result.
- [ ] T116-R6 Wire the existing cabal/Nix/CI E2E surface so the staging smoke
      runs in the established `E2E (withDevnet)` path and the future scenarios
      cannot silently stop compiling.
- [ ] T116-R6 Run the targeted real-node smoke and full gate; commit exactly
      `test(116): stage checkpoint lifecycle on devnet` with exactly
      `Tasks: T116-R6`, then park for epic-owner acceptance. Do not deploy,
      dispatch #117, mark ready, or merge without instruction.
