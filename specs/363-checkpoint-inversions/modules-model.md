# Modules model — #363 Checkpoint constructor inversions

Artifact ceiling: 3,500 bytes and 80 lines.

## MOD-363-MODEL — `CardanoKeri.Checkpoint`

Retains sole ownership of the `Step` inductive and its constructors. This
ticket changes no production transition, action, state, flow, executable
mirror, or import dependency. Strictly additive declaration support for the
coverage mechanism is permitted only if it cannot alter those definitions.

## MOD-363-GOALS — `CardanoKeri.CheckpointGoals`

Owns the public inversion theorems and their compiled coverage mechanism.
Every theorem is exported through the existing `CardanoKeri` import root. The
mechanism derives the constructor denominator from **MOD-363-MODEL**, binds one
inversion to each constructor, validates its exact constructor-`iff` shape,
and emits a non-vacuous coverage receipt.

## MOD-363-RUNTIME-GATE — ignored ticket evidence

The root `gate.sh` and its frozen runtime copy invoke the pinned Lean shell,
public-surface coverage, mutation self-falsification evidence, clean axiom
checks, and immutable-base blob checks. They are never committed or imported
by production code.

## Dependency direction

`CheckpointGoals` depends on `Checkpoint`; neither gains a dependency on
Registry, Lifecycle, Cage, Samaritan, simulator, on-chain, or runtime gate
artifacts. `CardanoKeri.lean` remains unchanged and continues to export the
goals module through its existing import.

