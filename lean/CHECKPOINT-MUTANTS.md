# Checkpoint machine — mutation campaign, 2026-09-04 (third slice: D-039, D-040)

The lean4 rule: a passing build proves nothing about whether a theorem
constrains the definition it names. So each guard or effect below was
broken in a scratch copy of `CardanoKeri/Checkpoint.lean`, the model
rebuilt (it must still compile, or the red is for the wrong reason), and
`CardanoKeri/CheckpointGoals.lean` rebuilt, requiring red. `stepFn` is left
intact, so `T7_step_iff_stepFn` reds on every `Step` mutant, and
`T9_juvenility_is_consumer_only` reds on every mutant that changes a
constructor's arity (its proof names every constructor); a mutant counts
as caught only when a theorem other than those two reds as well. 40
mutants: 40 red for the right reason. The campaign ended at its set point
(one mutant per guard or effect the slice added or amended, the statement
auditor's rows as a floor — `reopenSame`, `closeOldEpoch`, `rotatedAges`,
`depositFullAges`, `dropCloseUnpaid`, `closePayeeBypass`,
`closeWrongHunter`, `closeNoRotation`, `closeWrongHash` — and the legacy
guards of the earlier campaigns re-run on the new model); it does not claim
there are no other survivors.

The instrument applies each mutant by exact text replacement and refuses a
needle that does not apply exactly once; an identity control (needle equal
to its replacement) is run first and must survive, so the instrument is
shown able to report a survivor. Instrument and raw logs:
`/tmp/projects/cardano-keri/owner/commit-owner-slice3-fable/handoffs/slice3-evidence/campaign/`.

| Mutant | What it breaks | Theorems that caught it (T7, T9 aside) |
|---|---|---|
| M1-freeze-without-short-pool | a freeze lands while the pool still covers the premium | T15_b_leaves_only_by_freeze, T5_freeze_enabled |
| M2-second-freeze | a freeze lands on a frozen checkpoint, paying the bond twice | T5_freeze_enabled, T6_component_conservation |
| M3-second-poison-allowed | a second poison in one epoch lands | T4_poisoned_blocks_quorum_and_freeze, T5_poison_enabled |
| M4-topup-resets-juvenility | a top-up restarts juvenility | T14_pool_increases_only_by_topup |
| M5-convict-without-proof | a conviction of a present checkpoint needs no duplicity proof | T12_convict_exact, T5_convict_enabled |
| M6-convictParked-without-proof | a conviction of a parked identity needs no duplicity proof | T12_convict_parked_exact, T5_convict_parked_enabled, T8_parked_only_revives_or_convicts |
| M7-convictParked-pays | a conviction of a parked identity pays the convictor a bond nothing holds | T12_convict_parked_exact, T16_payments_are_named, T5_convict_parked_enabled, T6_component_conservation, T6_dreg_never_a_fee, T8_parked_only_revives_or_convicts |
| M8-convict-drops-freeze-bond | a conviction returns the pool but not the freeze bond | T12_convict_exact, T6_component_conservation |
| M9-deposit-no-refill | a deposit leaves the freeze bit as it was | T5_deposit_on_full_is_keep, T6_component_conservation |
| M10-deposit-resets-juvenility | a deposit restarts juvenility (the auditor's depositFullAges) | T10_only_deposit_restores, T5_deposit_on_full_is_keep |
| M11-deposit-brings-B-always | a deposit brings the whole freeze bond even when it is held | T5_deposit_on_full_is_keep, T6_component_conservation |
| M12-deposit-unsigned | a deposit signed as a keep (or nothing) lands | T5_every_bond_option, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M13-new-address-unsigned-paid | a paid keep moves the refund address with no signature on it | T5_every_bond_option, T5_keep_is_rotated, T5_keep_needs_no_intent, T6_intent_requires_new_keys, T6_refund_change_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M14-intentOk-any-none-free | every intent without an address is the empty message | T16_copied_reap_refused, T6_intent_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M15-reopen-stale | a revival at the parked sequence lands (the auditor's reopenSame) | T1_close_rotation_cannot_revive, T1_reopen_strict, T5_reopen_enabled, T8_only_convicted_is_terminal, T8_parked_only_revives_or_convicts, T8_parked_returns_only_by_revival |
| M16-reopen-wrong-key-state | a revival presents a rotation from the epoch after the parked one | T4_current_key_thief_cannot_revive, T5_reopen_enabled, T8_only_convicted_is_terminal, T8_parked_only_revives_or_convicts, T8_parked_returns_only_by_revival |
| M17-reopen-same-epoch | a revival keeps the parked epoch | T2_close_and_reopen_open_epochs, T8_parked_only_revives_or_convicts |
| M18-reopen-not-juvenile | a revival does not restart juvenility | T10_reopen_is_juvenile, T6_dreg_enters_only_at_birth, T8_parked_only_revives_or_convicts |
| M19-reopen-frozen | a revival marks the checkpoint frozen | T10_reopen_is_juvenile, T6_component_conservation, T6_dreg_enters_only_at_birth, T8_parked_only_revives_or_convicts |
| M20-reopen-without-bond | a revival brings no conviction bond | T10_reopen_is_juvenile, T6_component_conservation, T8_parked_only_revives_or_convicts |
| M21-close-old-epoch | the parked hash records the epoch the close left (the auditor's closeOldEpoch) | T16_close_destination, T16_parked_hash_is_the_closed_checkpoints, T2_close_and_reopen_open_epochs, T5_close_enabled |
| M22-close-wrong-hash | the parked hash records the sequence the close left (the auditor's closeWrongHash) | T16_close_destination, T16_parked_hash_is_the_closed_checkpoints, T1_close_rotation_cannot_revive, T2_close_and_reopen_open_epochs, T5_close_enabled |
| M23-close-payee-bypass | the close's signature is checked against a fixed payee: the copied reap lands (the auditor's closePayeeBypass) | T16_close_destination, T16_copied_reap_refused, T5_close_enabled, T6_intent_requires_new_keys |
| M24-close-intent-weakened | a close signed as a keep counts as the close intent | T16_close_destination, T16_copied_reap_refused, T5_close_enabled, T6_intent_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M25-close-premium-to-refund-address | the close pays the premium to the refund address, ignoring the signed payee (the auditor's closeWrongHunter) | T16_close_destination, T16_copied_reap_refused |
| M26-close-pays-old-address | a close pays the datum address, ignoring the signed new one | T16_close_destination |
| M27-close-premium-not-deducted | a paid close pays the premium and still refunds the whole pool | T16_close_destination, T16_parked_hash_is_the_closed_checkpoints, T6_component_conservation |
| M28-close-without-rotation | a close needs no witnessed rotation (the auditor's closeNoRotation) | T16_close_destination, T16_close_needs_rotation, T16_copied_reap_refused, T16_parked_hash_is_the_closed_checkpoints, T4_current_key_thief_cannot_park, T5_close_enabled, T6_intent_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M29-close-drops-unpaid | the unpaid close is gone: a close with a short pool is refused (the auditor's dropCloseUnpaid) | T5_close_enabled |
| M30-rotated-ages | the keep-shaped helper restarts juvenility (the auditor's rotatedAges) | T5_deposit_on_full_is_keep, T5_keep_is_rotated |
| M31-premium-always | the premium helper pays even when the pool does not cover it | T16_close_destination, T5_deposit_on_full_is_keep, T5_keep_is_rotated |
| M32-leaf-parked-reads-active | the leaf of a parked state reads active | T8_edges_leave_the_leaf, T8_leaf_states, T8_mint_once, T8_utxo_iff_active |
| M33-leaf-convicted-reads-parked | the leaf of a convicted state reads parked | T8_edges_leave_the_leaf, T8_leaf_states |
| M34-sysstep-reopen-without-parked-leaf | SysStep.reopen needs no parked leaf | T8_leaf_never_absent_again, T8_sysstep_partition |
| M35-close-does-not-touch-leaf | the partition says a close leaves the leaf | T8_edges_leave_the_leaf |
| M36-bHeld-inverted | the freeze bond is held exactly when frozen | T10_bonds_are_observable, T10_only_deposit_restores, T15_b_returns_only_by_deposit, T5_deposit_on_full_is_keep, T6_component_conservation |
| M37-consumableB-drops-frozen | the consumer's program ignores the freeze bit | consumableStateB_iff |
| M38-parked-holds-dreg | a parked identity holds the conviction bond | T10_bonds_are_observable, T10_parked_holds_nothing, T16_parked_hash_is_the_closed_checkpoints, T6_component_conservation, T6_dreg_never_a_fee |
| M39-thief-parks | a close needs no rotation and no intent: the current keys alone burn the UTxO | T16_close_destination, T16_close_needs_rotation, T16_copied_reap_refused, T16_parked_hash_is_the_closed_checkpoints, T4_current_key_thief_cannot_park, T5_close_enabled, T6_intent_requires_new_keys, T6_relayer_cannot_park_age_or_close |
| M40-poisonAfter-reopen-keeps | the poison fold does not clear at a revival | trace_poison_fold |

## What the campaign does not establish

Forty mutants caught says these forty are caught, not that no other
survives. Two facts a reader of the theorems should know: `T7` and `T9`
red on almost every `Step` mutant for structural reasons (the mirror and
the constructor enumeration) and are never counted; the identity control
survived, as it must.

Axioms (`#print axioms` over all 74 theorems, taken on a clean build — a
fresh copy of `lean/` without `.lake`, never a worktree's cache after a
mutant campaign): 55 use propext only, 18 use propext and Quot.sound, 1
uses none (`T8_reopen_actor_is_proof`); total 74; sorryAx: 0;
Classical.choice: 0.
