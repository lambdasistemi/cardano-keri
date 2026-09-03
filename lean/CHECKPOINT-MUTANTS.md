# Checkpoint machine — mutation campaign, 2026-09-03 (second slice: D-036, D-037, D-038)

The lean4 rule: a passing build proves nothing about whether a theorem
constrains the definition it names. So each guard or effect below was
broken in a scratch copy of `CardanoKeri/Checkpoint.lean`, the model
rebuilt (it must still compile, or the red is for the wrong reason), and
`CardanoKeri/CheckpointGoals.lean` rebuilt, requiring red. `stepFn` is left
intact, so `T7_step_iff_stepFn` reds on every `Step` mutant; a mutant counts
as caught only when a theorem other than T7 reds as well. 26 mutants:
24 red for the right reason, 2 survivors, both expected and
recorded below with the reason. The campaign ended at its set point (one
mutant per guard or effect the slice added or amended, the six legacy guards
of the first campaign re-run on the new model, the auditor's four rows as a
floor); it does not claim there are no other survivors.

| Mutant | What it breaks | Theorems that caught it (T7 aside) |
|---|---|---|
| M1-freeze-without-short-pool | a freeze lands while the pool still covers the premium | T15_b_leaves_only_by_freeze_or_withdraw, T5_freeze_enabled |
| M2-withdraw-pays-old-address | a withdrawal pays the datum address, ignoring the signed new one | T16_withdraw_destination |
| M3-second-poison-allowed | a second poison in one epoch lands | T4_poisoned_blocks_quorum_and_freeze, T5_poison_enabled |
| M4-topup-resets-juvenility | a top-up restarts juvenility | T14_pool_increases_only_by_topup |
| M5-convict-without-proof | a conviction needs no duplicity proof | T12_convict_exact, T5_convict_enabled |
| M6-freeze-takes-dreg | a freeze takes the conviction bond as well | T15_b_leaves_only_by_freeze_or_withdraw, T16_payments_are_named, T6_component_conservation, T6_dreg_never_a_fee |
| M7-close-intent-weakened | a close signed as a keep counts as the close intent | T16_close_destination, T5_close_enabled, T6_intent_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M8-close-pays-old-address | a close pays the datum address, ignoring the signed new one | T16_close_destination |
| M9-close-tombstone-old-epoch | the tombstone records the epoch the close left, not the one it opened | T16_close_destination, T2_close_and_reopen_open_epochs, T5_close_enabled |
| M10-reopen-stale | a reopen at the tombstone’s own sequence lands | T1_reopen_strict, T5_reopen_enabled, T8_closed_only_reopens, T8_only_convicted_is_terminal |
| M11-reopen-same-epoch | a reopen keeps the tombstone’s epoch | T2_close_and_reopen_open_epochs, T8_closed_only_reopens |
| M12-reopen-not-juvenile | a reopen does not restart juvenility | T10_reopen_is_juvenile, T8_closed_only_reopens |
| M13-reopen-without-bond | a reopen brings no conviction bond | T10_reopen_is_juvenile, T6_component_conservation, T8_closed_only_reopens |
| M14-withdraw-unsigned | a withdrawal signed as a keep (or nothing, with no address) lands | T5_every_bond_option, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M15-deposit-unsigned | a deposit signed as a keep (or nothing) lands | T5_every_bond_option, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M16-new-address-unsigned-paid | a paid keep moves the refund address with no signature on it | T5_every_bond_option, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M17-new-address-unsigned-unpaid | an unpaid keep moves the refund address with no signature on it | T5_every_bond_option, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M18-intentOk-any-none-free | every intent without an address is the empty message | T6_intent_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M19-close-does-not-touch-leaf | the partition says a close leaves the leaf | T8_edges_leave_the_leaf |
| M20-rotate-touches-leaf | the partition says a rotation changes the leaf (the auditor’s rotateTouchesLeaf) | T8_edges_leave_the_leaf |
| M21-leaf-stale-on-set | Sys.set moves the state and leaves the leaf as it was | T8_edges_leave_the_leaf, T8_leaf_agrees_with_state |
| M22-closed-leaf-reads-live | the leaf of a closed state reads live | T8_closed_leaf_is_the_tombstone, T8_edges_leave_the_leaf, T8_mint_once |
| M23-poisonAfter-reopen-keeps | the poison fold does not clear at a reopen | trace_poison_fold |
| M24-consumableStateB-drops-poison | the consumer’s program ignores the poison bit (the auditor’s dropPoisonConjunct) | consumableStateB_iff |

## Survivors, named

- **M25-register-without-absence-proof** — SysStep.register needs no absence proof (expected survivor: implied by leaf agreement, T8a).
- **M26-reopen-actor-anyone** — Action.actor classifies a reopen as anyone (the auditor’s reopenAnyone; expected survivor: no statement names the actor of a reopen).

The absence proof `habs` of `SysStep.register` is implied by leaf agreement
(`T8_leaf_agrees_with_state`): a registration is a `Step` from `absent`,
and an absent state has an absent leaf, so no theorem needs the guard — it
is the registry's own check (the MPFS absence proof), not a fact the machine
adds. No statement names the actor of a reopen; the auditor probed the
`Action.actor` boundary outside the 58 rows and the simulator's tags read
it. Both are recorded in `LEAN-CLARITY.md`.

## Raw log

```
M1-freeze-without-short-pool: RED for the right reason (failing: T15_b_leaves_only_by_freeze_or_withdraw T5_freeze_enabled T7_step_iff_stepFn)
M2-withdraw-pays-old-address: RED for the right reason (failing: T16_withdraw_destination T7_step_iff_stepFn)
M3-second-poison-allowed: RED for the right reason (failing: T4_poisoned_blocks_quorum_and_freeze T5_poison_enabled T7_step_iff_stepFn)
M4-topup-resets-juvenility: RED for the right reason (failing: T14_pool_increases_only_by_topup T7_step_iff_stepFn)
M5-convict-without-proof: RED for the right reason (failing: T12_convict_exact T5_convict_enabled T7_step_iff_stepFn)
M6-freeze-takes-dreg: RED for the right reason (failing: T15_b_leaves_only_by_freeze_or_withdraw T16_payments_are_named T6_component_conservation T6_dreg_never_a_fee T7_step_iff_stepFn)
M7-close-intent-weakened: RED for the right reason (failing: T16_close_destination T5_close_enabled T6_intent_requires_new_keys T6_relayer_cannot_park_age_or_close T7_step_iff_stepFn)
M8-close-pays-old-address: RED for the right reason (failing: T16_close_destination T7_step_iff_stepFn)
M9-close-tombstone-old-epoch: RED for the right reason (failing: T16_close_destination T2_close_and_reopen_open_epochs T5_close_enabled T7_step_iff_stepFn)
M10-reopen-stale: RED for the right reason (failing: T1_reopen_strict T5_reopen_enabled T7_step_iff_stepFn T8_closed_only_reopens T8_only_convicted_is_terminal)
M11-reopen-same-epoch: RED for the right reason (failing: T2_close_and_reopen_open_epochs T7_step_iff_stepFn T8_closed_only_reopens)
M12-reopen-not-juvenile: RED for the right reason (failing: T10_reopen_is_juvenile T7_step_iff_stepFn T8_closed_only_reopens)
M13-reopen-without-bond: RED for the right reason (failing: T10_reopen_is_juvenile T6_component_conservation T7_step_iff_stepFn T8_closed_only_reopens)
M14-withdraw-unsigned: RED for the right reason (failing: T5_every_bond_option T6_intent_requires_new_keys T6_refund_change_requires_new_keys T6_relayer_cannot_park_age_or_close T7_step_iff_stepFn)
M15-deposit-unsigned: RED for the right reason (failing: T5_every_bond_option T6_intent_requires_new_keys T6_refund_change_requires_new_keys T6_relayer_cannot_park_age_or_close T7_step_iff_stepFn)
M16-new-address-unsigned-paid: RED for the right reason (failing: T5_every_bond_option T6_intent_requires_new_keys T6_refund_change_requires_new_keys T6_relayer_cannot_park_age_or_close T7_step_iff_stepFn)
M17-new-address-unsigned-unpaid: RED for the right reason (failing: T5_every_bond_option T6_intent_requires_new_keys T6_refund_change_requires_new_keys T6_relayer_cannot_park_age_or_close T7_step_iff_stepFn)
M18-intentOk-any-none-free: RED for the right reason (failing: T6_intent_requires_new_keys T6_relayer_cannot_park_age_or_close)
M19-close-does-not-touch-leaf: RED for the right reason (failing: T8_edges_leave_the_leaf)
M20-rotate-touches-leaf: RED for the right reason (failing: T8_edges_leave_the_leaf)
M21-leaf-stale-on-set: RED for the right reason (failing: T8_edges_leave_the_leaf T8_leaf_agrees_with_state)
M22-closed-leaf-reads-live: RED for the right reason (failing: T8_closed_leaf_is_the_tombstone T8_edges_leave_the_leaf T8_mint_once)
M23-poisonAfter-reopen-keeps: RED for the right reason (failing: trace_poison_fold)
M24-consumableStateB-drops-poison: RED for the right reason (failing: consumableStateB_iff)
M25-register-without-absence-proof: SURVIVED (goals still green)
M26-reopen-actor-anyone: SURVIVED (goals still green)
```

Axioms (`#print axioms` over all 58 theorems): 41 use propext only, 17 use propext and Quot.sound; sorryAx: 0.
Instrument: the campaign script applies each mutant by exact text replacement (it refuses a needle that does not apply), builds `CardanoKeri.Checkpoint` then `CardanoKeri.CheckpointGoals`, and reads the failing theorem names off the error lines.
