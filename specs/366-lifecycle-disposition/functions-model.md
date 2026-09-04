# Functions model

No production Lean function signature changes. The live `Step`, `stepFn`,
`step_iff_stepFn`, `Trace`, `replay`, and `trace_iff_replay` surfaces remain
owned by `CardanoKeri.Checkpoint`.

## Executable driver contract

The disposition checker accepts the repository root and base revision, then:

1. derives the historical theorem inventory from the frozen base;
2. reconciles it exactly with the retirement CSV;
3. proves the three retired modules are absent from a clean module search;
4. clean-builds the public Lean root;
5. derives the live theorem inventory and checks every theorem's axioms.

It exits non-zero on an empty denominator, missing/duplicate/extra row, stale
sentinel, wrong decision link, importable retired module, build failure,
`sorryAx`, or unapproved axiom. A source-text scan may locate a reference but
cannot close compiled absence by itself.

