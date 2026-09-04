# Functions model

Ceiling: 70 lines / 6 KiB.

All rows are public theorems returning `Iff`. Their left side is successful
evaluation of the named executable branch to explicit result arguments; their
right side contains the exact source bindings, guards, and result equalities.

| ID | Public theorem | Explicit arguments | Result |
|---|---|---|---|
| FN-364-A1 | `stepFn_contribute_iff` | `p env aid owner submittedAt op now s f s'` | `Prop` (`Iff`) |
| FN-364-A2 | `stepFn_fold_iff` | `p env folder gen plugin batch now s f s'` | `Prop` (`Iff`) |
| FN-364-A3 | `stepFn_retract_iff` | `p env req now s f s'` | `Prop` (`Iff`) |
| FN-364-A4 | `stepFn_reap_iff` | `p env reaper aid now s f s'` | `Prop` (`Iff`) |
| FN-364-A5 | `stepFn_pause_iff` | `p env aid now s f s'` | `Prop` (`Iff`) |
| FN-364-A6 | `stepFn_resume_iff` | `p env aid now s f s'` | `Prop` (`Iff`) |
| FN-364-A7 | `stepFn_convictCkpt_iff` | `p env aid now s f s'` | `Prop` (`Iff`) |
| FN-364-B1 | `processBody_register_iff` | `p env acc request acc'` with `request.op = register` | `Prop` (`Iff`) |
| FN-364-B2 | `processBody_revive_iff` | `p env acc request acc'` with `request.op = revive` | `Prop` (`Iff`) |
| FN-364-B3 | `processBody_goDormant_iff` | `p env acc request keyState acc'` with `request.op = goDormant keyState` | `Prop` (`Iff`) |
| FN-364-B4 | `processBody_goConvicted_iff` | `p env acc request acc'` with `request.op = goConvicted` | `Prop` (`Iff`) |
| FN-364-B5 | `processBody_convict_iff` | `p env acc request acc'` with `request.op = convict` | `Prop` (`Iff`) |

Signature constraints: theorem names and branch bindings are unique; the
equivalence must permit both successful inversion and refusal by negation; no
existing `R*` signature changes.
