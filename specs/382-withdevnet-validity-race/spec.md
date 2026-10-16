# Issue 382 — withDevnet validity race

Artifact ceiling: 6,000 bytes / 140 lines.

## Outcome

The live `withDevnet` smoke remains trustworthy on a loaded runner: a
transaction that expires between construction and submission is identified as
harness timing, refreshed once through the same production-shaped path, and
submitted successfully. A validator or other ledger rejection remains a domain
failure and is never hidden by the timing recovery.

## Requirements

- **R382-01 Forced reproduction.** A deterministic injected delay of 25 devnet
  slots reaches the real transaction-submission boundary and makes the
  pre-repair code fail with `OutsideValidityIntervalUTxO`. Setup failure, a
  synthetic classifier-only test, or an assertion that a hook exists is not
  reproduction.
- **R382-02 Exact recovery.** The repaired harness may retry once only when the
  node's rejection is `OutsideValidityIntervalUTxO`. The retry rebuilds the
  transaction from a fresh node-derived validity plan; it does not resubmit the
  expired bytes.
- **R382-03 No blanket retry.** Every other Phase-1 rejection, every Phase-2
  validator rejection, and every exception remains terminal on the first
  attempt. An executable negative control proves a domain refusal is submitted
  exactly once.
- **R382-04 Distinct diagnostics.** Output identifies timing expiry separately
  from domain refusal without requiring the reader to inspect the raw ledger
  error. The timing line includes the scenario label and attempt number; the
  final result states whether recovery succeeded or failed.
- **R382-05 Numerical policy.** The harness names its numerical validity policy
  and rationale. The forced delay is 25 slots: greater than the existing
  20-slot window and the observed 15-slot miss. The ordinary plan remains
  inside the pinned node's 30-slot forecast; recovery obtains a fresh plan
  rather than widening past that forecast.
- **R382-06 Coverage preserved.** The existing cage and six checkpoint
  `withDevnet` examples still run. Checkpoint, cage, validator, on-chain,
  scenario, and devnet semantics do not change.
- **R382-07 Permanent evidence.** The deterministic expiry control and the
  non-expiry no-retry control run in the repository gate. The full live smoke
  and `just ci` are green on the final candidate.

## Invariants

- **INV-382-EXPIRY-RECOVERY (BLOCKING):** one actual
  `OutsideValidityIntervalUTxO` caused by the 25-slot pre-submit delay leads to
  exactly one fresh rebuild and a successful submission.
- **INV-382-RETRY-NARROW (BLOCKING):** a rejection not classified as validity
  expiry performs zero rebuilds and zero retry submissions.
- **INV-382-DIAGNOSTIC (BLOCKING):** timing-expiry and domain-rejection paths
  emit different stable verdicts, each carrying the scenario label.
- **INV-382-MARGIN (BLOCKING):** the named window/delay/retry numbers and their
  30-slot-forecast / 15-slot-observation rationale are enforced by executable
  boundary controls, not comments alone.
- **INV-382-SCOPE (BLOCKING):** no checkpoint, cage, validator, on-chain,
  scenario, or devnet behavior changes; all pre-existing smoke examples remain
  discoverable and execute.

## Acceptance

Retain one pre-repair forced-expiry receipt and one post-repair receipt for the
same 25-slot control. The post-repair run must show the timing-specific first
rejection, one fresh retry, and success. A separate negative control must show
a genuine domain refusal and a single submission. The ordinary live E2E smoke,
`just ci`, format, lint, commit gate, remote CI, and finalization audit must all
pass on the exact pushed SHA. No merge is authorized.
