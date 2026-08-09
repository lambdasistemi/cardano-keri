# Specification — #259 flake-lock enforcement

Artifact ceiling: 6,000 bytes and 140 lines.

## Outcome

The repository rejects a declared-but-unlocked offchain flake input without
rewriting `offchain/flake.lock`, and the same rejection policy governs the
root local gate and GitHub CI.

## User stories

### US-259-01 — immutable dependency evaluation

As a contributor, I need gate-time Nix evaluation to fail when the committed
offchain lock is incomplete, so a green run always describes committed input
pins rather than a silently repaired working tree.

Acceptance:

- every direct input declared by `offchain/flake.nix` is represented by the
  committed root input map in `offchain/flake.lock`;
- every in-scope invocation passes `--no-write-lock-file`;
- a full root `just ci` run asserts that the committed lock stayed unchanged.

### US-259-02 — local/workflow parity

As a maintainer, I need one durable guard contract on both the root gate and
`.github/workflows/ci.yml`, so neither lane can lose enforcement unnoticed.

Acceptance:

- the shared guard is reached from both surfaces;
- the guard distinguishes an incomplete lock, an unguarded invocation, and an
  unexpected lock diff from success;
- deleting the `deployPreprod` lock node makes the guard/gate RED, restoration
  returns it GREEN, and both receipts are retained outside Git.

## Requirements

- **REQ-259-01:** Compare the direct declared input names of the primary
  offchain flake with its committed root lock-input map and fail on any missing
  declaration.
- **REQ-259-02:** Cover every justfile invocation that evaluates the primary
  offchain flake, including invocations reached by root `just ci`; the frozen
  base census is 35 invocations, 9 guarded and 26 unguarded.
- **REQ-259-03:** Cover direct primary-offchain-flake evaluation in
  `.github/workflows/ci.yml`; remote `nix shell` calls and the independent
  BLAKE3 spike flake are outside this offchain-lock population.
- **REQ-259-04:** Use Nix's existing `--no-write-lock-file` behavior. Do not
  regenerate, normalize, or update the lock as part of checking it.
- **REQ-259-05:** After root `just ci`, require
  `offchain/flake.lock` to be byte-for-byte unchanged and fail the gate on a
  diff.
- **REQ-259-06:** Invoke the same shared guard from root `just ci` and GitHub
  CI, and make loss of either caller detectable.
- **REQ-259-07:** A passing guard emits counts for declared inputs and covered
  invocations so execution is distinguishable from a skipped check.
- **REQ-259-08:** Preserve all raw RED/GREEN and final-gate evidence under the
  ticket runtime root; no evidence file is committed.

## Invariants

- **DATA-INV-259-01 (BLOCKING):** every direct input declared in
  `offchain/flake.nix` is locked in committed `offchain/flake.lock`.
- **INV-259-NOWRITE (BLOCKING):** every primary-offchain Nix invocation in the
  justfile/CI gate population passes `--no-write-lock-file`.
- **INV-259-ASSERT (BLOCKING):** root `just ci` asserts the lock unchanged
  after its complete run and propagates assertion failure.
- **INV-259-FALSIFIABLE (BLOCKING):** removal of the `deployPreprod` lock node
  produces a retained RED receipt before restoration and retained GREEN.
- **INV-259-PARITY (BLOCKING):** the shared guard is durably called by both
  root `just ci` and `.github/workflows/ci.yml`.
- **INV-259-SWEEP (ADVISORY):** report other direct unlocked offchain inputs
  and whether `onchain/` has the same flake/lock gap.

## Scope

Production scope is limited to the root gate definition, GitHub CI workflow,
and a repository guard under `scripts/`. `offchain/flake.lock` is mutation
input only and must finish identical to the frozen base. `offchain/flake.nix`,
Haskell/Aiken sources, release workflows, auxiliary flakes, and `docs/` are
forbidden unless a ticket-owner-approved contract revision says otherwise.

## Rejection behavior

Missing lock input, incomplete source coverage, absent caller parity, a Nix
lock write attempt, or any post-gate lock diff exits non-zero. An inability to
evaluate is `GATE-INCOMPLETE`, never success.
