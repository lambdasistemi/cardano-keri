# Issue 365 implementation plan

Artifact ceiling: 5,000 bytes / 120 lines.

## Strategy

Treat mutation adequacy as a reconciliation between two frozen ledgers and one
observed campaign. The semantic-atom ledger is the security/design denominator;
the Cage/Samaritan theorem inventory is the non-vacuity denominator. A single
runner executes exact compile-valid edits in isolated copies, attributes RED to
named non-structural theorems, and generates both human receipts from its raw
machine-readable results.

## Ordered slices

1. **S365-P1 Contract.** Freeze the mandate, atom ledger, theorem-row inventory,
   and falsified runtime gate on `9b2e6b8`.
2. **S365-P2 Campaign.** Extend the mutation runner and specifications to cover
   legacy Checkpoint/Registry rows plus Cage/Samaritan atoms and theorem-row
   witnesses. Regenerate receipts from one run.
3. **S365-P3 Audit.** Submit the clean committed candidate to one fresh
   alternate-family auditor; allow at most one findings repair and a second
   fresh audit.
4. **S365-P4 Merged rerun.** Await the epic-owner C1+C2 release, rebase through
   the git workflow, rerun the full campaign and clean-`.lake` checks, refresh
   receipts, audit the fresh submission as required, and finalize the PR.

## Constraints

- `Cage.lean`, `Samaritan.lean`, `Checkpoint.lean`, `Registry.lean`, and ratified
  theorem statements are read-only campaign subjects.
- New guarantee theorems are out of scope; executable witnesses may be added
  only inside the mutation harness.
- Lifecycle deletion belongs to C4.
- The runner's finite operator set is: guard relax/delete, liveness force-false,
  evidence swap, effect omit/retain/stale/swap/misdirect, refusal or terminal
  edge removal/invention, and one-sided correspondence break.
- Initial campaign budget: one identity control plus one build pair per frozen
  blocking atom and at least one witness/kill observation per theorem row.
  Stop at the frozen denominator; equivalent or shadowed rows are replaced or
  marked `BLOCKED`, never discounted silently.

## Verification

The immutable runtime gate performs executable inventory reconciliation, the
full campaign, generated-receipt comparison, a clean-`.lake` axiom account, and
`lake build`. Final acceptance additionally verifies exact rebased provenance,
clean index/tree, commit gate, pushed SHA, remote CI, and finalization audit.
