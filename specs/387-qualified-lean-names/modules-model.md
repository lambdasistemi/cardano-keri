# Modules model

Artifact ceiling: 2,000 bytes / 60 lines.

| ID | Component | Changed responsibility | Dependency direction |
|---|---|---|---|
| M387-01 | checkpoint scenario gate | Derive one theorem inventory, partition it by the `Step` constructor inversion criterion, and apply exact agreement within both classes | Reads frozen Lean `Step` and `CheckpointGoals.lean`; depends on the existing declaration-span parser and simulator core metadata |
| M387-02 | scenario-gate selftest | Demonstrate dotted discovery, observable and inversion substitution, inversion removal, invalid proof-only entry, and preserved removed-thing rejection | Exercises M387-01 through scratch inputs; never changes authoritative Lean or core files |
| M387-03 | sweep handoff | Classify repository-wide extraction/comparison hits without widening the repair | Depends on source inventory only; no production consumer depends on it |

`M387-01` remains tooling. It does not own Lean semantics, simulator machine
behavior, stories, generated pages or the scenario DSL.
