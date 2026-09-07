# Data model

Ceiling: 45 lines / 4 KiB.

| ID | Data abstraction | Relationship / invariant |
|---|---|---|
| DATA-364-RESULT | Successful transition result | A `Flow × Sys` returned by `stepFn`, or an `Acc` returned by `processBody`, is related bidirectionally to the exact branch inputs, guards, and output equalities. No new runtime data is introduced. |
| DATA-364-DENOM | Live inversion denominator | The seven `Action` alternatives and five `Op` alternatives discovered from the executable definitions form a nonempty, exact 12-row set. Each row maps one-to-one to one public compiled theorem. |
| DATA-364-BASE | Accepted statement baseline | The ordered names and declaration text of existing public `R*` theorems at base `9b2e6b88937707cc2c571ae1e9e5f112dc248a30`; its digest must remain unchanged. |

Validation constraints: denominator names are unique; row-to-constructor mapping
is exact; result equalities include every observable `Flow`, `Sys`, or `Acc`
field changed by the branch; no theorem relies on a new axiom.
