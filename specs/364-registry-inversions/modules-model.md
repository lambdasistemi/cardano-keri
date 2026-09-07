# Modules model

Ceiling: 45 lines / 4 KiB.

| ID | Module | Responsibility change | Dependency direction |
|---|---|---|---|
| MOD-364-REG | `CardanoKeri.Registry` | Record DEC-364-STEPFN beside the authoritative executable model; no semantic change. | Owns data and executable functions; depends on no proof module. |
| MOD-364-GOALS | `CardanoKeri.RegistryGoals` | Own the complete public backward theorem surface and its permanent completeness instrument. | Imports Registry and proves facts about it; executable code never depends on Goals. |
| MOD-364-CAGE | `CardanoKeri.Cage` | Optional inversion/decision wording only if required to expose the already-delegated Registry body; no cage behavior change. | May consume Registry; must not redefine Registry semantics. |

Data rows: DATA-364-RESULT, DATA-364-DENOM. Function rows: FN-364-A1 through
FN-364-A7 and FN-364-B1 through FN-364-B5.
