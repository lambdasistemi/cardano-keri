# Issue 382 implementation plan

Artifact ceiling: 4,000 bytes / 100 lines.

## Strategy

Keep the fix inside the offchain live-test harness. Separate submission outcome
classification from retry policy, and make the retry accept a rebuild action so
expired bytes cannot be resubmitted. Preserve the existing node-derived
20-slot ordinary plan: it sits inside the pinned node's 30-slot forecast with
10 slots of forecast headroom. Cover runner delay by refreshing once on the
exact expiry verdict, not by widening beyond the forecast or retrying arbitrary
failures.

Use a 25-slot delay in the forced control. It exceeds both the 20-slot plan and
the observed 15-slot late submission, while remaining a small deterministic
addition to one live smoke path. The control must observe the node's actual
`OutsideValidityIntervalUTxO`, then exercise the same rebuild-and-submit path
that ordinary scenarios use.

## Ordered slices

1. **S382-P1 Contract.** Freeze this mandate and an ignored ticket gate on
   `4b9e4800c9546608e9ea5e0a14116f7210ff361c`.
2. **S382-P2 Harness repair.** First commit the deterministic RED proof. Then
   implement exact rejection classification, one fresh rebuild on expiry,
   distinct diagnostics, and permanent controls without changing domain code.
3. **S382-P3 Audit.** Run fresh alternate-family inspectors over provenance,
   semantics/failure modes, and mutation adequacy. Allow at most one
   adjudicated repair batch and one fresh delta inspection.
4. **S382-P4 Delivery.** Stamp tasks, create the final commit, run the ignored
   gate on the exact tree, push, refresh the draft PR, wait for green CI, run
   finalization audit, and mark ready without merging.

## Constraints

- OWNER topology; live-boundary semantics and error classification require
  independent review.
- Writable production/proof fence: `offchain/e2e/` and, only if needed to wire
  the permanent check, the existing offchain E2E component stanza and `justfile`.
- Read-only/forbidden: `onchain/`, checkpoint/cage/validator behavior, scenario
  semantics, genesis/devnet fixtures, unrelated tests, dependencies, and CI
  workflow topology.
- No blanket retry, suite-level retry, or retry of unchanged transaction bytes.
- The 25-slot injection is test-only and applies to a bounded named control; it
  must not slow every transaction or alter ordinary production-shaped runs.

## Verification

The commit owner retains the pre-fix RED and post-fix GREEN output for the same
forced control, plus a no-retry domain-refusal control. The frozen slice gate
runs the live expiry control, the ordinary live E2E suite, and full local CI.
Fresh inspectors independently execute the gate and can-fail controls before
ticket-owner acceptance.
