# #280 — Live E2E entitlement wiring

Parent: #274

## Outcome

The live-node checkpoint suite executes, rather than pends, the complete #137,
#138, and #151 stories. Every Freeze or Convict reveal exercised by those
stories is backed by an authentic #271 bounty commitment that was opened in an
earlier transaction and matured past the one-slot minimum age.

## Requirements

- **R280-001 — Execute the stories.** `CheckpointE2ESpec` runs #137, #138, and
  #151 under `stagedCheckpointDevnet`; no #280 pending annotation remains.
- **R280-002 — Open before reveal.** Each attempted Freeze or Convict
  settlement resolves an on-chain #271 commitment opened before the evidence
  is revealed. A synthetic or reveal-time commitment is rejected.
- **R280-003 — Bind the entitlement.** The opening binds the exact checkpoint
  output, enforcement action, beneficiary, evidence digest, and hidden nonce
  later supplied to the reveal.
- **R280-004 — Mature the commitment.** The reveal validity interval starts at
  or after the commitment's stored eligibility slot, strictly after the
  opening's upper slot.
- **R280-005 — Preserve story meaning.** #137 rejects stale Freeze replay and
  settles two Freeze/response rounds; #138 claims an unanswered delay bond and
  thaws; #151 convicts ACTIVE, ARMED, and FROZEN checkpoints.
- **R280-006 — Stay reversible.** Changes are confined to off-chain E2E test
  wiring. Any required edit under `onchain/` stops this ticket for a TIER-1
  re-cut.

## Invariants

- **INV-280-LIVE-OPEN (BLOCKING):** every enforcement reveal consumes an
  authentic commitment output created by an earlier submitted transaction.
  Failure means the story can manufacture entitlement at reveal time.
- **INV-280-BINDING (BLOCKING):** opening and reveal agree on checkpoint,
  action, payee, evidence digest, and nonce. Failure reaches chain state or
  money under a mismatched entitlement.
- **INV-280-MATURE (BLOCKING):** the settlement interval is wholly at or after
  the stored eligibility slot. Failure bypasses the pre-reveal age.
- **INV-280-STORIES (ADVISORY):** all three named Hspec rows execute and pass;
  pending or absent rows are not success.
- **INV-280-SCOPE (BLOCKING):** the PR changes no path under `onchain/`.

## Acceptance

`just e2e` exits zero with #137, #138, and #151 executed, then `just ci` exits
zero. GitHub CI is green at the reported head SHA.

## Output ceiling

This artifact is limited to 90 lines and 8 KiB.
