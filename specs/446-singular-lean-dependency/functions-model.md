# Functions model

This ticket introduces no Cardano KERI production function or changes to an
existing signature. It adds one proof-bearing check declaration:

| ID | Name | Arguments | Result |
|---|---|---|---|
| F-446-BIND | `CardanoKeri.singular_step_binding` | none | Equality between the released `Singular.step` result for the frozen escape fixture and the exact completion-only-custody error. |

`lean/CardanoKeri/SingularBinding.lean` imports released `Singular` and contains
the equality plus a guard over the same fixture; `lean/CardanoKeri.lean` imports
that module. A gate probe supplies R-446-CONTROL's other action. The traceability
script changes only by the gate's frozen patch: a checked temporary-file
producer replaces process substitution while the four-module inventory and
trust-policy bytes remain unchanged.

## Ceiling

This file is limited to 1 KiB and 30 lines.
