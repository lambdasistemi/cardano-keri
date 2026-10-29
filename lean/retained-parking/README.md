# Verify retained parking and associated retirement

The current campaigns execute the actual model definitions and complete finite
fixtures. Each subject must compile against an unchanged baseline and its
mutant before execution. Only its bound runtime assertion counts as a kill.
A proof failure, missing import, timeout or unrelated error is not a kill.

| Campaign | Cases | Evidence |
| --- | --- | --- |
| `checkpoint-atoms.json` | 39 | Local decidable mirror and observation mutations; complete result checks |
| `checkpoint-mutants.json` | 11 | Retained output, parked/pending refusal, pending keys and addressed close flows |
| `registry-mutants.json` | 19 | Token/output/minimum ADA, exact revival/authorization, custody tails, binding domain, generation and plugin |
| `samaritan-mutants.json` | 4 | Actual constructor domain, request funding, premium and external fee |

The economic campaign compiles the exact definition prefix of `Samaritan.lean`
without its proof suffix. It tests definitions, not whether a modified proof
script happens to elaborate. The full unmodified module is built and audited
separately. Whole-pending tail mutations are detected by reconstruction refusal;
they demonstrate lost valid execution, not acceptance of a malformed successor.

Run each with the project compiler and a fresh, nonexistent receipt directory:

```sh
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Registry
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Checkpoint
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Checkpoint checkpoint-atoms.json
node lean/retained-parking/run-registry-mutants.mjs RECEIPTS Samaritan
```

Set `LEAN_BIN` to the project's pinned compiler if it is not on PATH. Each run
records exact sources, commands, model/subject compilation, exits and bound
failures. Finite mutation coverage does not prove that no other fault survives.

The two `run-system-implementation-mutants.mjs` cases alter the JavaScript
certificate adapter: consuming another request and replacing the stored context.
They are implementation mutants. The separate foreign-context receipt controls
are type-interface checks. Neither category is counted as a Lean model mutant.

`ReviewedContracts.lean` checks all 106 revised exact contracts and
`PreservedContracts.lean` checks 74 preserved contracts. `theorem-stories.json`
binds 312 lifecycle/transport theorem identities, their source narratives,
complete formal Given/Then and source hashes. `story-bindings.mjs` rejects drift;
compilation remains the authority on the propositions and axiom closure.

The earlier mutation ledgers and receipts remain historical at their recorded
revisions. In particular, their 79-atom/20-theorem denominator is not a fresh
result for this revision. The parked-leaf and close-leaf faults change direction:
parking now keeps the active key and close leaves it unchanged. The old
system-revival parked-leaf guard has no current counterpart; exact stored-origin
and pending-request completion have separate actual-system evidence.

Production validators and builders require their own two implementation layers
and independent acceptance. These model and simulator checks do not supply it.
