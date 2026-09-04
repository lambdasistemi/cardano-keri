# Issue 365 functions model

Artifact ceiling: 3,500 bytes / 90 lines.

| ID | Function | Signature-level contract |
|---|---|---|
| F365-01 | `list` | `() -> inventory`; emit the frozen atom IDs and dynamically discovered Cage/Samaritan theorem rows without running builds |
| F365-02 | `runCampaign` | `(sourceRoot, workRoot, ledger, mutantSpecs, budget) -> CampaignEvidence`; isolate inputs, run identity then exact mutants/witnesses, and retain raw evidence |
| F365-03 | `applyOne` | `(cleanCopy, mutant) -> AppliedEdit`; require exactly one original occurrence and bind the resulting target blob |
| F365-04 | `classifyOne` | `(mutant, modelBuild, theoremBuild) -> AtomResult`; count only compile-valid owning-theorem RED and preserve structural/excluded failures separately |
| F365-05 | `witnessTheorem` | `(theoremRow, witness) -> TheoremResult`; execute a reachable antecedent and bind it to a relevant killed mutant |
| F365-06 | `renderReceipts` | `(CampaignEvidence) -> (CheckpointReceipt, RegistryReceipt)`; deterministic rendering with independent denominators and raw-log identity |
| F365-07 | `checkAxioms` | `(cleanSource, theoremInventory) -> AxiomReceipt`; rebuild without `.lake`, print theorem-qualified axioms, reject `sorryAx` |

Names may follow existing shell conventions, but the argument/result boundaries
and effects above are fixed. No function edits production models or theorem
statements in the authoritative worktree.
