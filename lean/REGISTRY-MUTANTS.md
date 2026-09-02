# Registry machine — mutation campaign, 2026-09-02

The lean4 rule: a passing build proves nothing about whether a theorem
constrains the definition it names. Each guard below was broken in a scratch
copy of `CardanoKeri/Registry.lean`, the model rebuilt (it must still
compile, or the red is for the wrong reason), and
`CardanoKeri/RegistryGoals.lean` rebuilt, requiring red. Eleven mutants,
eleven reds, all for the right reason.

| Mutant | Guard broken | Theorems that caught it |
|---|---|---|
| M1 | process without the absence proof | `applyBatch_inv` (R1, R2 via `inv_step`), `applyBatch_process_registered` (R1c, R3b), `R4_reregistrable` |
| M2 | close keeps the row | `inv_step` (R1), `R4_close_deletes_row`, `R12` |
| M3 | convict deletes the row | `inv_step` (R1), `R12` |
| M4 | fold without the generation check | `R7_stale_fold_refused`, `R7_one_fold_per_generation` |
| M5 | empty fold accepted | `R8_empty_fold_refused` |
| M6 | plugin swap accepted | `R8_plugin_swap_refused` |
| M7 | reject in phase 1 | `R9_reject_needs_rejectable` |
| M8 | retract in any phase | `R9_retract_needs_phase2` |
| M9 | process outside phase 1 | `applyBatch_inv`, `applyBatch_process_registered`, `R4_reregistrable`, `R9_process_needs_phase1` |
| M10 | convict without a proof | `inv_step` |
| M11 | fold does not advance the generation | `R4_reregistrable`, `R6_fold_advances`, `R9_reject_enabled` |

Raw log:

```
M1-process-without-absence-proof: RED for the right reason (model compiles; failing:applyBatch_inv applyBatch_process_registered R4_reregistrable )
M2-close-keeps-the-row: RED for the right reason (model compiles; failing:inv_step R12_row_enters_only_by_fold R12_row_leaves_only_by_close R4_close_deletes_row )
M3-convict-deletes-the-row: RED for the right reason (model compiles; failing:inv_step R12_row_enters_only_by_fold R12_row_leaves_only_by_close )
M4-fold-without-generation-check: RED for the right reason (model compiles; failing:R7_one_fold_per_generation R7_stale_fold_refused )
M5-empty-fold-accepted: RED for the right reason (model compiles; failing:R8_empty_fold_refused )
M6-plugin-swap-accepted: RED for the right reason (model compiles; failing:R8_plugin_swap_refused )
M7-reject-in-phase-1: RED for the right reason (model compiles; failing:R9_reject_needs_rejectable )
M8-retract-in-any-phase: RED for the right reason (model compiles; failing:R9_retract_needs_phase2 )
M9-process-outside-phase-1: RED for the right reason (model compiles; failing:applyBatch_inv applyBatch_process_registered R4_reregistrable R9_process_needs_phase1 )
M10-convict-without-proof: RED for the right reason (model compiles; failing:inv_step )
M11-fold-does-not-advance-generation: RED for the right reason (model compiles; failing:R4_reregistrable R6_fold_advances R9_reject_enabled )
```

M10 is caught only through `inv_step`'s `convict` case, which needs
`aid ∈ s.live` from the guard conjunction it destructures; no theorem states
"convict needs a proof" by name. A `R3_convict_needs_proof` on the shape of
`R9_reject_needs_rejectable` would name it. Recorded, not added: the
statement set was frozen for the audit.

Axioms (`#print axioms` over every declaration of `RegistryGoals.lean`):
49 declarations; 6 use `propext`, 33 use `propext` and `Quot.sound`, 10 use
`propext`, `Classical.choice` and `Quot.sound`; no `sorryAx`.
