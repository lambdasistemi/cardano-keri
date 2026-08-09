# Plan — #259 flake-lock enforcement

Artifact ceiling: 6,000 bytes and 150 lines.

## Strategy

Deliver one OWNER slice because source-population classification, workflow
reachability, and fail-closed shell behavior need semantic review beyond a
mechanical candidate gate.

The slice applies the repository's existing `--no-write-lock-file` convention
uniformly to the primary offchain flake population. A shared, non-mutating
repository guard owns declared-versus-locked reconciliation, invocation
coverage, positive evidence counts, and caller-parity checks. Root `just ci`
and GitHub CI both reach that guard. The root gate additionally asserts the
lock unchanged after all CI dependencies complete.

## Frozen state

- Base: `eb31b2e49be1652256ed38343693e6a319fc4fed`.
- `deployPreprod` is already present in the committed lock after #257.
- Primary offchain direct-input sweep: 17 declared and 17 root-lock entries;
  no other missing direct input found at planning time.
- Justfile census: 35 primary-offchain invocations; 9 contain the no-write
  flag and 26 do not. The issue's 37 / 9 / 28 count predates the #257 merge;
  three mechanical recounts at this frozen base agree on 35 / 9 / 26.
- `onchain/` has no flake/lock pair, so it has no analogous declared/unlocked
  input gap. Auxiliary fixture and spike flakes are outside this ticket's
  primary-offchain contract.

## Component direction

The repository guard in **MOD-259-GUARD** is the single policy owner.
**MOD-259-JUST** and **MOD-259-WORKFLOW** depend on it and may not duplicate its
classification rules. The guard observes committed source and returns a
process verdict; it never writes the lock or source files.

## Slice S259-1 — uniform enforcement and parity

1. Establish RED from the frozen immutable gate before implementation.
2. Add the permanent guard and its fail-capable controls.
3. Apply no-write semantics to the full primary-offchain invocation
   population in the justfile and CI workflow.
4. Wire both gate surfaces to the shared guard and enforce the post-`just ci`
   lock-diff postcondition.
5. Delete the `deployPreprod` lock node only as a controlled mutation, capture
   RED, restore the exact tracked blob, capture GREEN, and prove the worktree
   clean.
6. Run full root `just ci`, workflow-parity verification, and fresh audit.

Intermediate proof and implementation commits remain local. The commit owner
returns one candidate and, after acceptance/task stamping, one conventional
final commit.

## Owned and forbidden paths

Owned production paths:

- `justfile`;
- `.github/workflows/ci.yml`;
- `scripts/check-flake-lock-guard.sh` and narrowly related script fixtures.

Mutation-only path:

- `offchain/flake.lock` — restore the exact base blob before any candidate
  commit or GREEN claim.

Forbidden:

- `offchain/flake.nix`;
- all Haskell, Cabal, Aiken, deployment, release, auxiliary-flake, and `docs/`
  paths;
- committed evidence or `gate.sh`.

## Verification contract

- Initial RED: the immutable gate fails on the absent shared guard at the
  frozen planning base.
- Policy negative controls: known incomplete-lock and unguarded-invocation
  inputs make the permanent guard fail for the intended classification.
- Required mutation: remove only the `deployPreprod` lock node, run the named
  gate path with no-write semantics, retain RED, restore the exact blob, retain
  GREEN.
- Parity: independently show both root `just ci` and CI workflow reach the
  shared guard and that all classified invocations are guarded.
- Final: run the immutable gate from repository root, require exit 0 and an
  empty tracked worktree afterward.

`GATE-INCOMPLETE` is distinct from `GATE-FAIL`. The campaign build budget is
8; exhaustion requires escalation and no ninth build.

## Risks and controls

- **Scanner false zero:** permanent positive-control fixtures and non-zero
  emitted counts prove the scanner observed known invocations and inputs.
- **Workflow/local drift:** both callers share one guard; caller reachability
  is itself asserted.
- **Mutation residue:** bind the original lock blob, restore it exactly, and
  reject any candidate containing a lock diff.
- **Remote-flake overreach:** classify only the primary offchain flake; do not
  require a local lock flag for unrelated remote shells or auxiliary flakes.
- **Green without evaluation:** evaluation failure is incomplete/RED and the
  evidence receipt records the actual exit.

## Artifact measurements

Provider-reported token counts are unavailable for local files.

| Artifact | Ceiling bytes / lines | Actual bytes / lines |
|---|---:|---:|
| `spec.md` | 6,000 / 140 | 4,104 / 89 |
| `plan.md` | 6,000 / 150 | 4,900 / 116 |
| `modules-model.md` | 4,000 / 100 | 1,899 / 48 |
| `data-model.md` | 4,000 / 110 | 1,928 / 52 |
| `functions-model.md` | 3,000 / 90 | 1,164 / 39 |
| `tasks.md` | 4,000 / 100 | 1,834 / 36 |
