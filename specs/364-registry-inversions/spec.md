# Registry inversion surface

Ceiling: 90 lines / 7 KiB.

## Outcome

An auditor can invert every successful Registry transition through a public,
bidirectional theorem and recover the exact executable guards, input binding,
value routing, and successor state. The same equivalence exposes refusal when
those conditions do not hold.

## Decision

DEC-364-STEPFN: retain `stepFn` and `processBody` as the sole transition
semantics. Do not add an inductive `Step`: duplicating twelve executable branch
surfaces would create a second semantics whose correspondence becomes an
ongoing obligation without improving the backward interface. The public
inversion surface is the twelve `*_iff` theorems in INV-364-DENOM below.
`ReachFar` remains stated over `stepFn`; no replay or reachability definition
changes.

## Requirements

- REQ-364-01: Record DEC-364-STEPFN in the `Registry.lean` module header and
  name the twelve public inversion theorems as the admission/refusal surface.
- REQ-364-02: Each `stepFn` inversion binds the exact action, source lookup or
  state shape, every Boolean/phase/generation/plugin/nonempty guard, the exact
  returned `Flow`, and all changed and preserved successor fields.
- REQ-364-03: Each `processBody` inversion binds the request operation, exact
  leaf/checkpoint/evidence guards, value routing, token evolution, and all
  changed and preserved accumulator fields.
- REQ-364-04: The finite denominator is derived from the live executable
  branches and reports 12/12, with no missing, duplicate, wrong-branch, or
  compiled-surface omission.
- REQ-364-05: The gate proves sensitivity to missing, duplicate, wrong-branch,
  and dropped-guard faults with compile-valid mutations and real non-zero exits.
- REQ-364-06: `lake build` is green; no `sorry`, `admit`, or `sorryAx` occurs in
  scope; every new public theorem has a clean theorem-qualified axiom receipt.
- REQ-364-07: Existing `R*` theorem statements are byte-identical to the base.

## Invariant denominator

INV-364-DENOM (blocking, 12/12):

- Action: `contribute`, `fold`, `retract`, `reap`, `pause`, `resume`,
  `convictCkpt`.
- Body operation: `register`, `revive`, `goDormant`, `goConvicted`, `convict`.

INV-364-BIND (blocking): every row's equivalence is sensitive to each guard
and externally observable effect licensed by its executable branch.

INV-364-WIRING (blocking): every row is public through the compiled
`CardanoKeri` library and bound to its intended constructor, not merely present
as source text.

INV-364-PRESERVE (blocking): no accepted `R*` statement, `ReachFar`, shared
import file, Checkpoint/Lifecycle/Samaritan file, simulator, or on-chain artifact
changes.

## Non-goals

Plugin-cage behavior, simulator/on-chain behavior, Checkpoint/Samaritan/
Lifecycle semantics, new axioms, and rewording accepted `R*` statements.
