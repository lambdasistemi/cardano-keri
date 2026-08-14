# spec — #289 derive Lean bridge elaboration order from module imports

Issue: https://github.com/lambdasistemi/cardano-keri/issues/289
Parent: #190. Blocks #246.

## Problem

`offchain/blaster/elaborate-ilean-root.sh` compiles the tracked `KeriBlaster`
modules in lexical `sort` order. Lexical order is a coordinate order; it carries
no dependency information and has been a valid topological order only by
coincidence.

The coincidence has broken. `Entitlement`, `Migration`, and `RegisterArity`
each declare `import KeriBlaster.S2Cek` and sort before `S2Cek`, so
`S2Cek.olean` is absent from the output root when `Entitlement.lean`
elaborates. The re-elaboration reports
`outcome=COULD-NOT-EVALUATE layer=build-root-provenance` and is RED.

This was predicted in writing by residual `T246-F5` before it fired.

## P1 user story

As a baseline verifier, I run the flake-owned source re-elaboration and observe
every tracked `KeriBlaster` module compile after its declared local
dependencies, regardless of lexical filename order.

## Requirements

- **R1** Compile order is a topological order of the relation "module A declares
  an import of local module B", restricted to the tracked input set.
- **R2** The derived order is a pure function of the input set: identical across
  runs and across permuted argument order.
- **R3** A declared local `KeriBlaster.*` import with no tracked source in the
  input set aborts before any elaboration, non-zero, with its own distinct
  diagnostic layer token.
- **R4** A dependency cycle among tracked modules aborts before any elaboration,
  non-zero, with its own distinct diagnostic layer token, naming the
  participants.
- **R5** The aggregate root `KeriBlaster.lean` continues to compile last and is
  excluded from the derived order, as today.
- **R6** No tracked Lean source file changes.
- **R7** The flake-owned source-reelaboration passes from the exact committed
  tree and records the gate and tree identity.

## Rejection behavior

`COULD-NOT-EVALUATE` is RED everywhere in this ticket. R3 and R4 are aborts,
not warnings and not partial runs: elaborating a subset while a declared
dependency is unresolved is the specific outcome they forbid.

The three diagnostic classes must be mutually distinguishable by their `layer=`
token. The existing `layer=build-root-provenance` is not available to either
new class.

## Observable success

The flake-owned runner (`nix run .#blaster` from `offchain/`) exits zero on the
committed tree, its pre-existing `PASS:` stages all still present, plus the new
ordering controls' evidence lines.

## Non-goals

- Changing validator theorem statements or any tracked Lean bridge source.
- Changing #246's compiled-denominator, producer-identity, Variant-E,
  reconciliation, or limitations contracts.
- A repository-wide Lean dependency manager. The derived order is scoped to the
  tracked bridge set inside this one script.
- Any script unrelated to the elaborator and its proof.
