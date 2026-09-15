# Functions model

This ticket introduces no Cardano KERI production function or changes to an
existing signature. It adds one proof-bearing check declaration:

| ID | Name | Arguments | Result |
|---|---|---|---|
| F-442-BIND | `CardanoKeri.singular_step_binding` | none | Equality between the released `Singular.step` result for the frozen escape fixture and the exact completion-only-custody error. |

The declaration is imported by the default Cardano KERI root. Its body and
the accompanying executable assertion belong to the commit owner. A separate
gate probe supplies the distinct well-typed action control required by
R-442-CONTROL.

## Ceiling

This file is limited to 1 KiB and 30 lines.
