# Qualified Lean declaration identities

Issue: #387  
Mandate: R387-v2 (A-001)
Artifact ceiling: 4,000 bytes / 100 lines.

## Outcome

The checkpoint scenario gate preserves every theorem's complete declaration
identity, then derives two disjoint classes. The 74 simulator-observable
properties reconcile exactly with core checker rows, lamps and falsifiers. The
13 `Step.<constructor>_iff` inversions reconcile exactly with the constructors
derived from the Lean `Step` inductive. Same-size different sets are rejected.

This classification records rather than closes a real coverage gap: the 13
inversion theorems have no simulator-observable checker row, lamp or falsifier.
Whether they should become observable is outside this ticket.

## Requirements

- **R387-01 Exact declaration inventory (ADVISORY).** Derive the theorem
  inventory from the gate's declaration-span parser rather than a second
  identifier regex. Preserve all 87 current theorem identities, including the
  thirteen distinct dotted `Step.*_iff` names, and reject an empty or duplicate
  inventory.
- **R387-02 Derived classes and exact agreement (ADVISORY).** Derive the
  proof-only class, never enumerate it: its members are exactly the theorem
  identities `Step.<constructor>_iff` obtained by joining the theorem inventory
  to constructor names parsed from the Lean `Step` inductive. The two classes
  are disjoint and exhaustive over all 87 declarations. The 74 observable
  identities agree exactly with checker rows, lamps and falsifiers; the 13
  proof-only identities agree exactly with the separately derived constructor
  inversion set. Lamp multiplicity remains exactly one per observable member.
- **R387-03 Falsifiable controls (ADVISORY).** Permanent executing controls show
  dotted discovery; same-count observable substitution rejection; inversion
  substitution rejection; inversion removal rejection; rejection when a
  nonmatching theorem is made to enter the proof-only class; and retained
  removed-row/removed-lamp/removed-falsifier rejection. Moving an identity
  across the class boundary without satisfying the criterion is RED. Each
  control is observed RED before the repair's GREEN.
- **R387-04 Scope (ADVISORY).** Production changes are confined to
  `simulator/checkpoint-simulator-scenario-gate.mjs` and, if its command/control
  account changes, `simulator/README.md`. Do not change Lean, simulator cores,
  story JSON, scenario DSL, generated HTML or other shipped artifacts.
- **R387-05 Sweep (ADVISORY).** Inventory repository identifier extractions
  whose character classes omit `.`, and identity/set checks that accept by
  count rather than members. Classify each hit and report it even when outside
  this ticket's repair fence.
- **R387-06 Historical explanation (ADVISORY).** Retain evidence that the gate
  is green at `9b2e6b8`, red from `dc2e7a5`, and current `main` has exactly 42
  problems: 1 duplicate-inventory diagnostic, 13 missing checker rows, 13
  zero-lamp rows, 2 unclaimed guard hypotheses, and 13 missing-falsifier rows.

All six requirements are acceptance-blocking despite their mutation-campaign
severity: this tool does not directly write chain state, money or signatures.

## Rejection behavior

Missing, duplicate, truncated, substituted or misclassified identities make
the gate exit nonzero with a diagnostic naming the mismatched identity class.
A setup failure is distinct from a semantic rejection.

## Verification

`node simulator/checkpoint-simulator-scenario-gate.mjs` and `--selftest` both
exit 0 on the repaired candidate; `just ci` remains green. Exact candidate and
scope are independently audited before acceptance.
