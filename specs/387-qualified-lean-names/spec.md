# Qualified Lean declaration identities

Issue: #387  
Artifact ceiling: 4,000 bytes / 100 lines.

## Outcome

The checkpoint scenario gate treats every theorem in
`CheckpointGoals.lean` as its complete declaration identity, so the thirteen
`Step.*_iff` theorems participate independently in checker-row, lamp and
falsifier reconciliation. A same-size but different identity set is rejected.

## Requirements

- **R387-01 Exact declaration inventory (ADVISORY).** Derive the theorem
  inventory from the gate's declaration-span parser rather than a second
  identifier regex. Preserve all 87 current theorem identities, including the
  thirteen distinct dotted `Step.*_iff` names, and reject an empty or duplicate
  inventory.
- **R387-02 Exact agreement (ADVISORY).** Declaration, checker-row and lamp
  identities agree by exact unique membership. Cardinality may be reported but
  cannot establish agreement. Lamp multiplicity remains exactly one per
  declaration.
- **R387-03 Falsifiable controls (ADVISORY).** Permanent executing controls show
  that a dotted theorem is discovered and matched, a same-count identity
  substitution is rejected for identity mismatch, and the existing
  removed-row/removed-lamp/removed-falsifier controls still reject for their
  intended reasons. Each control is observed RED before the repair's GREEN.
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
  problems: 13 missing checker rows, 13 zero-lamp rows, 3 aggregate theorem-row
  problems, and 13 missing-falsifier rows.

All six requirements are acceptance-blocking despite their mutation-campaign
severity: this tool does not directly write chain state, money or signatures.

## Rejection behavior

Missing, duplicate, truncated or substituted identities make the gate exit
nonzero with a diagnostic naming the mismatched identity class. A setup failure
is distinct from a semantic rejection.

## Verification

`node simulator/checkpoint-simulator-scenario-gate.mjs` and `--selftest` both
exit 0 on the repaired candidate; `just ci` remains green. Exact candidate and
scope are independently audited before acceptance.
