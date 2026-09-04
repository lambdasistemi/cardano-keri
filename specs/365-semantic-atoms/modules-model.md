# Issue 365 modules model

Artifact ceiling: 3,500 bytes / 90 lines.

| ID | Component | Responsibility | Dependency direction |
|---|---|---|---|
| M365-01 | semantic atom ledger | Frozen ruling-to-model-to-theorem denominator and severity | Authority input; depends on ratified rulings and current model only |
| M365-02 | mutation specification | Exact single-edit identity and operator for every atom | Depends on M365-01; never on generated receipts |
| M365-03 | mutation runner | Isolated application, compile check, theorem/witness execution, attribution, cleanup | Depends on M365-01/M365-02 and read-only Lean subjects |
| M365-04 | theorem-row inventory | Dynamic inventory of Cage/Samaritan theorem declarations and observed witness/kill result | Derived from compiled declarations, reconciled against campaign output |
| M365-05 | campaign evidence | Raw immutable event stream and machine-readable atom/theorem result tables | Emitted only by M365-03 |
| M365-06 | generated receipts | Human Checkpoint and Registry campaign reports, with Cage/Samaritan sections | Pure rendering of M365-05; no hand-authored verdicts |
| M365-07 | runtime gate | Reconcile declared and observed extents, rerun campaign/build/axioms, compare receipts | Depends on all prior components; is untracked and read-only to workers |

Production Lean models and ratified theorem statements are subjects, not owned
components. The harness may import them but must not move guards, effects, or
statements to make a mutant fail.
