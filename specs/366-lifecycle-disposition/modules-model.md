# Modules model

| ID | Module | Responsibility after #366 | Allowed change |
|---|---|---|---|
| M366-1 | `CardanoKeri.lean` | Public compiled Lean root | Drop only the three retired imports |
| M366-2 | `CardanoKeri.Checkpoint*` | Sole accepted checkpoint lifecycle and theorem surface | No semantic edit |
| M366-3 | `traceability.csv` | Historical retirement ledger for the deleted 21-theorem surface | Replace live/PENDING mappings with owner-bound retirement rows |
| M366-4 | traceability/CI driver | Executable retirement-ledger, clean-build, and proof-trust enforcement | Replace obsolete 21-live-theorem assumptions |
| M366-5 | Lean/docs references | Explain the sole live specification and historical retirement | Reference-only edits |

The ignored root `gate.sh` and `/tmp/epic-367/to-366` evidence are
ticket-owner runtime artifacts, not shipped modules.

