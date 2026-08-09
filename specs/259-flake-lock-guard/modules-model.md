# Modules model — #259 flake-lock enforcement

Artifact ceiling: 4,000 bytes and 100 lines.

This model owns changed responsibilities and dependency direction. Data is in
`data-model.md`; command signatures are in `functions-model.md`.

## MOD-259-GUARD — repository flake-lock guard

- Owns reconciliation of direct primary-offchain declarations with the
  committed root lock map.
- Owns classification of primary-offchain Nix invocations in the root
  justfile and GitHub CI workflow.
- Owns caller-parity and positive-evidence reporting.
- Is read-only over repository source and fails closed on malformed or
  unclassifiable in-scope input.
- Does not regenerate a lock, invoke formatting, or own build behavior.

## MOD-259-JUST — root local gate

- Applies no-write semantics to every classified primary-offchain invocation.
- Reaches **MOD-259-GUARD** from root `just ci`.
- Owns the post-complete-gate assertion that `offchain/flake.lock` is
  unchanged.
- Does not duplicate guard classification or declaration/lock comparison.

## MOD-259-WORKFLOW — GitHub CI gate

- Applies no-write semantics to every direct primary-offchain invocation in
  `.github/workflows/ci.yml`.
- Reaches **MOD-259-GUARD** as a required CI step.
- Does not treat a separate checkout's cleanliness as proof about another
  job; no-write evaluation and the shared source guard are the workflow
  enforcement.

## Dependency edges

- **EDGE-259-01:** `MOD-259-JUST` depends on `MOD-259-GUARD`.
- **EDGE-259-02:** `MOD-259-WORKFLOW` depends on `MOD-259-GUARD`.
- **EDGE-259-03:** the guard reads the justfile, CI workflow,
  `offchain/flake.nix`, and `offchain/flake.lock`; none depends back on guard
  internals.

## Mechanical boundaries

- One guard implementation and two durable callers.
- No tracked lock or flake change in the candidate.
- No production changes outside the owned paths in `plan.md`.
