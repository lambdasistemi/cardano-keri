# Plan — #363 Checkpoint constructor inversions

Artifact ceiling: 6,000 bytes and 130 lines.

## Strategy

Add one public constructor-`iff` theorem per compiled `Checkpoint.Step`
constructor. Keep constructor indices on the theorem's transition side and
the constructor proof premises on the proposition side, so case splitting is
both readable and exact. Add a compiled-surface coverage mechanism beside the
theorems that derives `Step`'s constructor set, binds each inversion to one
constructor, validates its canonical type, and fails compilation on any gap or
collision.

The ignored ticket gate builds from the repository's pinned Lean Nix shell,
loads the public `CardanoKeri` surface, obtains the live inventory, exercises
the coverage mechanism, checks each new theorem's axioms, and proves existing
ratified statement/transition blobs unchanged. Runtime mutation work occurs in
fresh scratch copies and is never committed.

## Slice S363-1 — all Checkpoint inversions

This is one structural slice because the denominator and checker are one
atomic contract. Partial constructor coverage is not releasable.

Implementation may add inversion theorems and the coverage mechanism only in
`lean/CardanoKeri/Checkpoint.lean` and
`lean/CardanoKeri/CheckpointGoals.lean`. Prefer theorem placement in
`CheckpointGoals.lean`; use `Checkpoint.lean` only for strictly additive
declaration support required by the compiled coverage mechanism. Do not alter
`Step`, `stepFn`, existing declarations, statements, imports, or toolchain.

## Verification order

1. Establish baseline build and immutable base hashes.
2. Freeze the ticket gate and observe RED on the missing inversion surface.
3. Commit a complete RED proof/coverage bundle before implementation.
4. Add all inversions and coverage support; run focused then full Lean build.
5. In fresh scratch copies, run the six required single-class falsifications,
   requiring compile-valid setup and intended checker RED, then restore GREEN.
6. From a clean `.lake`, run theorem-qualified axiom checks over the derived
   inversion inventory and reject `sorryAx`, `Classical.choice`, or any axiom
   outside `propext` and `Quot.sound`.
7. Freeze the candidate for a fresh read-only audit; after acceptance only the
   ticket owner stamps tasks and the commit owner creates the final squash.

## Risks and controls

- A handwritten list drifts when `Step` grows: inventory is read from the
  compiled inductive and guarded non-empty.
- Names and counts agree while a theorem is wrong: the checker validates the
  constructor binding and canonical theorem type.
- A dropped guard leaves a true weaker theorem: exact-premise validation plus
  the dropped-guard mutation rejects it.
- A theorem exists but is not public: acceptance imports only `CardanoKeri`.
- A build accepts `sorry`: warning scan and per-theorem axiom output are both
  required from a clean build tree.
- Mutation evidence is wrong-reason RED: each mutation proves one intended
  edit, successful model compilation where applicable, and checker-specific
  failure before it is counted.

## Artifact measurements

Provider token counts are recorded by the executing seat when available.
Actual bytes and lines are measured before mandate freeze and dispatch.

