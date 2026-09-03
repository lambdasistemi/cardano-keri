# Registry machine — mutation campaign, rerun 2026-09-03 (evening)

The lean4 rule: a passing build proves nothing about whether a theorem
constrains the definition it names. Each guard below was broken in a scratch
copy of `CardanoKeri/Registry.lean`, the model rebuilt (it must still
compile, or the red is for the wrong reason), and
`CardanoKeri/RegistryGoals.lean` and `CardanoKeri/Cage.lean` rebuilt,
requiring red. Twenty-two mutants, twenty-two reds, all for the right
reason, on the tree after the audit of 2026-09-03 (`Inv.activeCkpt` binds the
leaf's token; `R14_convict_in_batch_needs_proof`, `R14_convict_at_position`).

History: the first run (before R14) had two survivors — a conviction of a
dormant AID without a duplicity proof and a conviction of a checkpoint
without one; `R14_*` were added and the campaign rerun to 20/20. This rerun
adds M21 and M22 for the token binding (audit major 2): a registration that
mints a checkpoint with another token, and a pause that changes the token,
both caught by the strengthened invariant.

| Mutant | Guard broken | Theorems that caught it |
|---|---|---|
| M1 | register without the absence proof | `processOne_inv` (R1 via `inv_step`), `processOne_leaf_mono`, `processOne_register_registered` (R1d, R3b) |
| M2 | register without the inception evidence | `processOne_inv`, `processOne_leaf_mono`, `processOne_register_registered` |
| M3 | revive without a rotation from `k` | `processOne_inv` |
| M4 | revive minting beside an existing checkpoint | `processOne_inv` |
| M5 | a go-request applied to a dormant leaf | `processOne_inv`, `processOne_leaf_mono` |
| M6 | convict a dormant AID without a proof | `R14_convict_dormant_needs_proof`, `R14_convict_in_batch_needs_proof` |
| M7 | reject a go-request | `rejectOne_go` (R9d), `rejectOne_inv`, `R9_reject_enabled` |
| M8 | reject in phase 1 | `rejectOne_go`, `rejectOne_inv`, `R9_reject_enabled`, `R9_reject_needs_rejectable` |
| M9 | process outside phase 1 | `processOne_inv`, `processOne_leaf_mono`, `processOne_register_registered`, `R14_convict_dormant_needs_proof`, `R14_convict_at_position` |
| M10 | fold without the generation check | `R7_stale_fold_refused`, `R7_one_fold_per_generation` |
| M11 | empty fold accepted | `R8_empty_fold_refused` |
| M12 | plugin swap accepted | `R8_plugin_swap_refused` |
| M13 | fold does not advance the generation | `inv_step`, `R6_fold_advances`, `R9_reject_enabled` |
| M14 | retract in any phase | `inv_step` (a go-request would be retractable), `R9_retract_needs_phase2` |
| M15 | reap a live checkpoint | `R13_live_never_reaped` |
| M16 | a stranger reaps before the grace window | `R13_parked_needs_grace`, `R13_parked_after_grace`, `R13_owner_reaps_early` |
| M17 | the go-request dated `now` instead of `far` | `inv_step` (goFar), `R13_tomb_reaped`, `R13_parked_after_grace`, `R13_owner_reaps_early` |
| M18 | the reap keeps the checkpoint | `inv_step` (goNoCkpt), `R13_*` |
| M19 | convict a checkpoint without a proof | `R14_convictCkpt_needs_proof` |
| M20 | a go-request posted by hand | `inv_step` (goFar, goUnique) |
| M21 | a registration mints a checkpoint with another token than the leaf's | `processOne_inv` (activeCkpt) |
| M22 | a pause changes the checkpoint's token | `inv_step` (activeCkpt via `inv_replace_ckpt`) |

Not mutated on its own: `applyBatch_append` is a lemma about the fold's
shape, not a guard; M9 exercises it through `R14_convict_at_position`.

Raw log (the `[RegistryGoals:…]` lists are the failing lines):

```
M1-register-without-absence-proof: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono processOne_register_registered [RegistryGoals:445,930,1052] )
M2-register-without-inception: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono processOne_register_registered [RegistryGoals:445,930,1051] )
M3-revive-without-rotation: RED for the right reason (model compiles; failing:processOne_inv [RegistryGoals:499] )
M4-revive-mints-beside-a-checkpoint: RED for the right reason (model compiles; failing:processOne_inv [RegistryGoals:499] )
M5-go-on-a-dormant-leaf: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono [RegistryGoals:556,960] )
M6-convict-dormant-without-proof: RED for the right reason (model compiles; failing:R14_convict_dormant_needs_proof R14_convict_in_batch_needs_proof [RegistryGoals:1618,1645] )
M7-reject-a-go-request: RED for the right reason (model compiles; failing:R9_reject_enabled [RegistryGoals:627,1061,1397,1401] rejectOne_go rejectOne_inv )
M8-reject-in-phase-1: RED for the right reason (model compiles; failing:R9_reject_enabled R9_reject_needs_rejectable [RegistryGoals:627,1061,1396,1401,1409] rejectOne_go rejectOne_inv )
M9-process-outside-phase-1: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono processOne_register_registered R14_convict_at_position R14_convict_dormant_needs_proof [RegistryGoals:443,497,552,562,574,924,939,953,967,983,1051,1617,1693] )
M10-fold-without-generation-check: RED for the right reason (model compiles; failing:R7_one_fold_per_generation R7_stale_fold_refused [RegistryGoals:1353,1365] )
M11-empty-fold-accepted: RED for the right reason (model compiles; failing:R8_empty_fold_refused [RegistryGoals:1370] )
M12-plugin-swap-accepted: RED for the right reason (model compiles; failing:R8_plugin_swap_refused [RegistryGoals:1375] )
M13-fold-does-not-advance-generation: RED for the right reason (model compiles; failing:inv_step R6_fold_advances R9_reject_enabled [RegistryGoals:802,1346,1400] )
M14-retract-in-any-phase: RED for the right reason (model compiles; failing:inv_step R9_retract_needs_phase2 [RegistryGoals:791,1390] )
M15-reap-a-live-checkpoint: RED for the right reason (model compiles; failing:R13_live_never_reaped [RegistryGoals:1548] )
M16-reap-before-grace-by-a-stranger: RED for the right reason (model compiles; failing:R13_owner_reaps_early R13_parked_after_grace R13_parked_needs_grace [RegistryGoals:1568,1581,1593] )
M17-go-request-dated-now: RED for the right reason (model compiles; failing:inv_step R13_owner_reaps_early R13_parked_after_grace R13_tomb_reaped [RegistryGoals:825,828,831,838,851,1558,1580,1592] )
M18-reap-keeps-the-checkpoint: RED for the right reason (model compiles; failing:inv_step R13_owner_reaps_early R13_parked_after_grace R13_tomb_reaped [RegistryGoals:819,820,827,832,835,853,1558,1580,1592] )
M19-convictCkpt-without-proof: RED for the right reason (model compiles; failing:R14_convictCkpt_needs_proof [RegistryGoals:1602,1603] )
M20-contribute-a-go-request: RED for the right reason (model compiles; failing:inv_step [RegistryGoals:744,757,759,764] )
M21-register-mints-another-token: RED for the right reason (model compiles; failing:processOne_inv [RegistryGoals:461] )
M22-pause-changes-the-token: RED for the right reason (model compiles; failing:inv_step [RegistryGoals:876] )
```

Axioms (`#print axioms` over every theorem of `RegistryGoals.lean`,
`Cage.lean` and `Samaritan.lean`): 111 theorems; 64 use `propext`, 46 use
`propext` and `Quot.sound`, 1 uses no axiom; no `Classical.choice`, no
`sorryAx`.
