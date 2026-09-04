# Implementation plan

## P1 — retire the shadow specification

Delete the three legacy Lean modules and remove their root imports. Preserve
the live Checkpoint, Registry, Cage, and Samaritan imports unchanged.

## P2 — make retirement mechanically observable

Replace the legacy live-mapping CSV with a 21-row retirement ledger. Update the
traceability driver and Lean CI wording/invocation so it validates the ledger's
discovered extent, unique IDs, exact status, owner link, and lack of stale
sentinels. The compiler remains the authority for dependency closure.

## P3 — align documentation

Rewrite only documentation that names the deleted modules or their obsolete
21-goal surface. Point readers to `Checkpoint.lean`, `CheckpointGoals.lean`,
`CHECKPOINT-MUTANTS.md`, and the checkpoint simulator.

## P4 — accept

Run the frozen disposition gate, obtain one fresh Codex-high audit, stamp the
task record after acceptance, squash through the commit owner, rerun the gate
on the exact final tree, push, and wait for remote CI before readiness.

## Fence

Implementation may touch the three deleted files, `lean/CardanoKeri.lean`,
`lean/traceability.csv`, `lean/README.md`, the traceability driver, Lean CI
references, and directly affected documentation. It may not modify the live
model/proofs, mutation campaigns, simulator behavior, on-chain/off-chain code,
or create the #368 audit report.

