# Modules model

## MOD-280-SPEC — `CheckpointE2ESpec`

Responsibility: expose #137, #138, and #151 as live `stagedCheckpointDevnet`
stories and preserve their existing scenario ownership in
`CheckpointTxBuilder`.

Depends on: MOD-280-HARNESS.

## MOD-280-HARNESS — `CheckpointTxBuilder`

Responsibility: deploy and retain the applied #271 commitment program for the
devnet, open and resolve authentic commitments, wait for eligibility, prepare
entitled enforcement plans, and feed those plans into the existing Freeze and
Convict transaction builders.

Depends on the stable production owners:

- `Cardano.KERI.Deployment.Script` for the applied commitment family;
- `Cardano.KERI.AID.Checkpoint.BountyCommitment` for commitment planning;
- `Cardano.KERI.AID.Checkpoint.Entitlement` for reveal planning.

It must not duplicate commitment or entitlement predicates and must not move
their ownership into the E2E harness.

## Direction

The test specification calls the harness; the harness calls production
off-chain helpers; neither layer edits or redefines the on-chain programs.

## Output ceiling

This artifact is limited to 60 lines and 5 KiB.
