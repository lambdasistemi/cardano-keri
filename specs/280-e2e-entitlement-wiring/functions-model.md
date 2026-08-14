# Functions model

## FN-280-PREPARE-LIVE-ENTITLEMENT

Private harness operation.

- Inputs: `CheckpointEnv`, resolved checkpoint `TxIn`/`TxOut`,
  `BountyAction`, complete `EnforcementEvidence`, beneficiary `ByteString`, and
  nonce `ByteString`.
- Result: `IO EntitledEnforcementPlan`.
- Effects: submit one opening transaction, resolve its output, wait until the
  stored eligibility slot, and derive the result through
  `prepareBountyCommitment` followed by `prepareEntitledEnforcement`.
- Constraint: it may not synthesize `ResolvedCommitment` without observing the
  submitted output on chain.

## Existing scenario signatures

The signatures of `productionRegisterFreezeScenario`,
`productionRegisterSeizeScenario`, and `productionRegisterConvictScenario`
remain `CheckpointEnv -> IO ()`. `setupCheckpointEnv` and `mkCheckpointEnv`
retain their existing argument and result types while populating DM-280-ENV.

## Output ceiling

This artifact is limited to 55 lines and 5 KiB.
