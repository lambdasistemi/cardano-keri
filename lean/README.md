# Lean model of the M1 checkpoint lifecycle — Checkpoint is the sole spec (#366)

A standalone Lake project (Lean 4, `v4.27.0`, **zero dependencies** — Lean
core only) that models the M1 checkpoint lifecycle as **the on-chain
validator's transition system** and proves the M1 invariants. Per
[DISP-366-DELETE](https://github.com/lambdasistemi/cardano-keri/issues/366#issuecomment-5543757547),
`CardanoKeri.Checkpoint` is the sole compiled lifecycle specification.

Live surface (no semantic change in this disposition):

- `CardanoKeri/Checkpoint.lean` — states, actions, guards, `stepFn`, `Trace`,
  `replay`, `Sys` (the accepted D-036…D-040 machine).
- `CardanoKeri/CheckpointGoals.lean` — the checkpoint theorems
  (`step_iff_stepFn`, `trace_iff_replay`, T1–T16 family), fully proved.
- `CardanoKeri/Registry.lean`, `RegistryGoals.lean`, `Cage.lean`,
  `Samaritan.lean` — registry/cage/reaper surface, fully proved.
- `CHECKPOINT-MUTANTS.md` — finite mutation campaign for the checkpoint machine.
- `CheckpointTraceDriver.lean` — corpus producer for
  `simulator/checkpoint-simulator.html`.

## Retirement of the pre-D-036 Lifecycle machine (#366)

`CardanoKeri/Lifecycle.lean`, `CardanoKeri/Goals.lean`, and
`CardanoKeri/Invariants.lean` (the pre-D-036 freeze/bond machine and its 21
theorems) are retired and removed from the compiled surface. The historical
21-theorem extent is frozen at base `9b2e6b8` and recorded one-to-one in
`traceability.csv` as explicit `RETIRED` rows bound to the owner ruling.
`scripts/check-lean-traceability.sh` enforces the ledger, clean-build/compiled
absence, and live proof trust.

## Build

```
cd lean
lake build          # with elan: picks up lean-toolchain (v4.27.0)
# without elan:
nix shell nixpkgs#lean4 -c lake build
```

The build passes with **zero `sorry`**. No `axiom` declarations anywhere:
`#print axioms` on every live theorem reports at most `propext` and
`Quot.sound` (both Lean core) or no axioms.

## The registry machine (#316)

`CardanoKeri/Registry.lean` models the AID registry of D-024 as a cage of
cardano-mpfs-onchain on the plugin path, after the rulings of 2026-09-02/03:
leaves active / dormant / convicted, checkpoints live / parked / tombstone,
requests as inbox UTxOs, a permissionless fold at a named generation, the
reap of a bondless checkpoint into a permanent go-request, revival by a
rotation from the recorded key state; one executable `stepFn`, `replay`,
`ReachFar` and the invariant `Inv` (an active leaf's token is the token of its
checkpoint). `CardanoKeri/RegistryGoals.lean` proves R1–R14, R14 at any
position of any batch against the accumulator the fold reached
(`R14_convict_at_position`); `CardanoKeri/Cage.lean` is the generic mpfs cage (authorization mode,
plugin, value mode) with the registry as its delegated instantiation and the
divergence from the cage as shipped as theorems; `CardanoKeri/Samaritan.lean`
proves the reaper never loses. No `sorry`, standard axioms only. The
mutation campaign is `REGISTRY-MUTANTS.md`; the design note is
`docs/design/registry-as-mpfs.md`. `RegistryTraceDriver.lean` is the corpus
producer for `simulator/registry-simulator.html`.
