# Plan

Ceiling: 75 lines / 6 KiB.

## Strategy

DEC-364-STEPFN keeps the executable functions authoritative and adds a
backward theorem boundary around each live branch. The implementation is one
bisect-safe OWNER slice because theorem signatures, proofs, inventory coverage,
and mutation sensitivity form one acceptance unit.

## Slice S364-INV

1. Preserve the base `R*` statement digest and the live branch denominator.
2. Record DEC-364-STEPFN in the Registry module header.
3. Add the twelve public bidirectional inversion theorems named in the
   functions model, without changing executable behavior.
4. Add a permanent branch-derived coverage and self-falsification instrument
   within the owned Lean proof surface.
5. Prove clean compilation, exact denominator coverage, mutation sensitivity,
   axiom cleanliness, and forbidden-scope preservation.

## Boundaries

- Owned production/proof scope: `lean/CardanoKeri/Registry.lean`,
  `lean/CardanoKeri/RegistryGoals.lean`, and only a Step-decision record or
  inversion theorem in `lean/CardanoKeri/Cage.lean`.
- Read-only: `lean/CardanoKeri.lean`, Lake/toolchain files, `lean/mutants/**`,
  every Checkpoint/Lifecycle/Samaritan file, simulator and on-chain trees.
- No statement rescue, new axioms, merge, or push by delegated seats.

## Verification

- Frozen ticket gate from the runtime root, hash-bound before dispatch.
- Repository Lean CI command: `cd lean && nix shell --no-write-lock-file
  ../offchain#lean --command lake build`.
- Clean-`.lake` theorem-qualified `#print axioms` for each new theorem.
- Base-to-candidate digest equality for existing `R*` declarations.
- Four required self-falsification classes with real exits and frozen receipts.
