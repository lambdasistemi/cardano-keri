# Plan: preserve qualified Lean identities

Artifact ceiling: 3,000 bytes / 80 lines.

## Strategy

Reuse the scenario gate's existing declaration-span inventory as the single
source of theorem identities. Reconcile the derived declarations, step-record
checker rows and lamp entries by exact unique membership, while retaining the
one-lamp-per-declaration multiplicity rule. Extend the existing selftest with
identity-sensitive controls and leave the Lean/model/story inputs untouched.

This follows the repair shape already shipped in `lean/mutants/run.sh`: derive
complete names, reject duplicate inputs, compare exact identities, and prove a
same-count substitution fails.

## Ordered slice

1. Freeze the historical/current RED signature and repository sweep inventory.
2. Commit an executable RED bundle for R387-01 through R387-03.
3. Repair the shared declaration inventory and every consumer in the scenario
   gate; update its command account only if needed.
4. Run the focused production gate, its full selftest, and the full repository
   CI; report the 42-problem disappearance item by item.
5. Freeze the candidate for independent audit, accept or authorize one bounded
   repair, stamp tasks, push, and stop ready for project-owner merge authority.

## Boundaries

The ticket owner owns this record, gates, acceptance, PR metadata and push. A
distinct-family commit owner owns RED, implementation, tests and local commits.
Fresh auditors are read-only. No role may modify Lean declarations, simulator
machine cores, story JSON or the scenario DSL.

## Failure modes

The change alters parsing/reconciliation failure reporting only. It acquires no
resource, starts no thread, changes no synchronization primitive and removes no
degradation path. File-read/setup failures must remain distinguishable from an
identity mismatch.
