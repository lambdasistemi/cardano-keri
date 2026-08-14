# Plan

## Scope

One bisect-safe off-chain E2E slice wires the already-merged #271 commitment
and #254 entitlement helpers into the existing checkpoint devnet harness.

## Strategy

- Extend the E2E environment to retain the applied #271 commitment family and
  live script material needed by the stories.
- Add one private E2E boundary responsible for opening a commitment, observing
  its resolved output, advancing to its eligibility slot, and producing the
  entitled enforcement plan through `prepareBountyCommitment` and
  `prepareEntitledEnforcement`.
- Route every Freeze and Convict attempt in #137, #138, and #151 through that
  boundary so negative evidence rows still reach the enforcement predicate
  they are intended to test.
- Restore the three Hspec rows to `around stagedCheckpointDevnet` execution.

## Live boundaries

- A real protocol-11 `cardano-node` receives the opening and settlement
  transactions.
- The commitment output, marker, datum, and maturity are observed from chain
  state rather than reconstructed as a reveal-only fixture.
- The existing entitlement observer reference remains the checkpoint
  transaction's live authentication boundary.

## Slice

**S280-1 — Open, mature, and reveal**

Owned implementation paths:

- `offchain/e2e/CheckpointE2ESpec.hs`
- `offchain/e2e/CheckpointTxBuilder.hs`

Forbidden paths: all `onchain/` paths, dependency manifests, generated
blueprints, and production validators.

Verification: the immutable slice gate runs the non-pending wiring assertion,
`just e2e`, and `just ci` in that order.

## Stop condition

If a deployed validator or any path under `onchain/` must change, stop and
escalate to the #274 owner for a TIER-1 re-cut.

## Output ceiling

This artifact is limited to 70 lines and 6 KiB.
