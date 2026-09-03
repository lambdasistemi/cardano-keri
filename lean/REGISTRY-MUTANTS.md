# Registry machine — mutation campaign, 2026-09-03

The lean4 rule: a passing build proves nothing about whether a theorem
constrains the definition it names. Each guard below was broken in a scratch
copy of `CardanoKeri/Registry.lean`, the model rebuilt (it must still
compile, or the red is for the wrong reason), and
`CardanoKeri/RegistryGoals.lean` and `CardanoKeri/Cage.lean` rebuilt,
requiring red. Twenty mutants, twenty reds, all for the right reason.

The first run of this campaign, before R14 existed, had two survivors — a
conviction of a dormant AID without a duplicity proof, and a conviction of a
checkpoint without one. Nothing named those guards. `R14_convict_dormant_needs_proof`
and `R14_convictCkpt_needs_proof` were added and the campaign rerun; the
table is the rerun.

| Mutant | Guard broken | Theorems that caught it |
|---|---|---|
| M1 | register without the absence proof | `processOne_inv` (R1 via `inv_step`), `processOne_leaf_mono`, `processOne_register_registered` (R1d, R3b) |
| M2 | register without the inception evidence | `processOne_inv`, `processOne_leaf_mono`, `processOne_register_registered` |
| M3 | revive without a rotation from `k` | `processOne_inv` |
| M4 | revive minting beside an existing checkpoint | `processOne_inv` |
| M5 | a go-request applied to a dormant leaf | `processOne_inv`, `processOne_leaf_mono` |
| M6 | convict a dormant AID without a proof | `R14_convict_dormant_needs_proof` |
| M7 | reject a go-request | `rejectOne_go` (R9d), `rejectOne_inv`, `R9_reject_enabled` |
| M8 | reject in phase 1 | `rejectOne_go`, `rejectOne_inv`, `R9_reject_enabled`, `R9_reject_needs_rejectable` |
| M9 | process outside phase 1 | `processOne_inv`, `processOne_leaf_mono`, `processOne_register_registered`, `R14_convict_dormant_needs_proof` |
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

Raw log (the `[RegistryGoals:…]` lists are the failing lines; line 182 in
every row is a linter warning on the scratch copy, since fixed, not an error):

```
M1-register-without-absence-proof: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono processOne_register_registered [RegistryGoals:182,445,926,1048] )
M2-register-without-inception: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono processOne_register_registered [RegistryGoals:182,445,926,1047] )
M3-revive-without-rotation: RED for the right reason (model compiles; failing:processOne_inv [RegistryGoals:182,499] )
M4-revive-mints-beside-a-checkpoint: RED for the right reason (model compiles; failing:processOne_inv [RegistryGoals:182,499] )
M5-go-on-a-dormant-leaf: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono [RegistryGoals:182,556,956] )
M6-convict-dormant-without-proof: RED for the right reason (model compiles; failing:R14_convict_dormant_needs_proof [RegistryGoals:182,1614] )
M7-reject-a-go-request: RED for the right reason (model compiles; failing:R9_reject_enabled [RegistryGoals:182,627,1057,1393,1397] rejectOne_go rejectOne_inv )
M8-reject-in-phase-1: RED for the right reason (model compiles; failing:R9_reject_enabled R9_reject_needs_rejectable [RegistryGoals:182,627,1057,1392,1397,1405] rejectOne_go rejectOne_inv )
M9-process-outside-phase-1: RED for the right reason (model compiles; failing:processOne_inv processOne_leaf_mono processOne_register_registered R14_convict_dormant_needs_proof [RegistryGoals:182,443,497,552,562,574,920,935,949,963,979,1047,1613] )
M10-fold-without-generation-check: RED for the right reason (model compiles; failing:R7_one_fold_per_generation R7_stale_fold_refused [RegistryGoals:182,1349,1361] )
M11-empty-fold-accepted: RED for the right reason (model compiles; failing:R8_empty_fold_refused [RegistryGoals:182,1366] )
M12-plugin-swap-accepted: RED for the right reason (model compiles; failing:R8_plugin_swap_refused [RegistryGoals:182,1371] )
M13-fold-does-not-advance-generation: RED for the right reason (model compiles; failing:inv_step R6_fold_advances R9_reject_enabled [RegistryGoals:182,798,1342,1396] )
M14-retract-in-any-phase: RED for the right reason (model compiles; failing:inv_step R9_retract_needs_phase2 [RegistryGoals:182,787,1386] )
M15-reap-a-live-checkpoint: RED for the right reason (model compiles; failing:R13_live_never_reaped [RegistryGoals:182,1544] )
M16-reap-before-grace-by-a-stranger: RED for the right reason (model compiles; failing:R13_owner_reaps_early R13_parked_after_grace R13_parked_needs_grace [RegistryGoals:182,1564,1577,1589] )
M17-go-request-dated-now: RED for the right reason (model compiles; failing:inv_step R13_owner_reaps_early R13_parked_after_grace R13_tomb_reaped [RegistryGoals:182,821,824,827,834,847,1554,1576,1588] )
M18-reap-keeps-the-checkpoint: RED for the right reason (model compiles; failing:inv_step R13_owner_reaps_early R13_parked_after_grace R13_tomb_reaped [RegistryGoals:182,815,816,823,828,831,849,1554,1576,1588] )
M19-convictCkpt-without-proof: RED for the right reason (model compiles; failing:R14_convictCkpt_needs_proof [RegistryGoals:182,1598,1599] )
M20-contribute-a-go-request: RED for the right reason (model compiles; failing:inv_step [RegistryGoals:182,740,753,755,760] )
```

Axioms (`#print axioms` over every theorem of `RegistryGoals.lean`,
`Cage.lean` and `Samaritan.lean`): 107 theorems; 61 use `propext`, 46 use
`propext` and `Quot.sound`; no `Classical.choice`, no `sorryAx`.
