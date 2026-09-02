# Checkpoint machine — mutation campaign, 2026-09-02

The lean4 rule: a passing build proves nothing about whether a theorem
constrains the definition it names. So each guard below was broken in
`CardanoKeri/Checkpoint.lean`, the model rebuilt (it must still compile, or
the red is for the wrong reason), and `CardanoKeri/CheckpointGoals.lean`
rebuilt, requiring red. Eight mutants, eight reds, all for the right reason.
`T7_step_iff_stepFn` reds on every mutant because `stepFn` was left intact;
`T9` and the `T5` enabled-theorems red where a constructor's arity changed.

| Mutant | Guard broken | Theorems that caught it |
|---|---|---|
| M1 | close enabled while poisoned | T16a, T4a |
| M2 | freeze without a short pool | T15a |
| M3 | withdraw pays the old refund address | T16b |
| M4 | a second poison in one epoch | T4a |
| M5 | top-up resets juvenility | T14b |
| M6 | a relayer moves the refund address | T6d |
| M7 | conviction without a duplicity proof | T12b |
| M8 | freeze takes the conviction bond too | T6b, T16c, T15a |

Raw log:

```
M1-close-while-poisoned: RED for the right reason (model compiles; failing: T16_close_destination T4_poisoned_blocks_quorum_and_freeze T5_close_enabled T7_step_iff_stepFn T9_juvenility_is_consumer_only )
M2-freeze-without-short-pool: RED for the right reason (model compiles; failing: T15_b_leaves_only_by_freeze_or_withdraw T5_freeze_enabled T7_step_iff_stepFn T9_juvenility_is_consumer_only )
M3-withdraw-pays-old-refund: RED for the right reason (model compiles; failing: T16_withdraw_destination T7_step_iff_stepFn )
M4-second-poison-allowed: RED for the right reason (model compiles; failing: T4_poisoned_blocks_quorum_and_freeze T5_poison_enabled T7_step_iff_stepFn T9_juvenility_is_consumer_only )
M5-topup-resets-juvenility: RED for the right reason (model compiles; failing: T14_pool_increases_only_by_topup T7_step_iff_stepFn )
M6-relayer-moves-refund: RED for the right reason (model compiles; failing: T5_every_bond_option T6_refund_change_requires_new_keys T7_step_iff_stepFn T9_juvenility_is_consumer_only )
M7-convict-without-proof: RED for the right reason (model compiles; failing: T12_convict_exact T5_convict_enabled T7_step_iff_stepFn T9_juvenility_is_consumer_only )
M8-freeze-touches-dreg: RED for the right reason (model compiles; failing: T15_b_leaves_only_by_freeze_or_withdraw T16_payments_are_named T6_dreg_never_a_fee T7_step_iff_stepFn )
```

Axioms: 45 theorems; 20 use none, 16 use propext, 9 use propext and Quot.sound; no sorryAx.
