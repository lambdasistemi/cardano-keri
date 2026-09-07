# Specification — #375 scenario DSL

Artifact ceiling: 8,000 bytes and 170 lines.

## Outcome

A story author can write, load, play, and export checkpoint or registry
simulator stories in one documented human-targeted DSL. The existing 30 JSON
scenario files remain the acceptance-gate inputs and are reproduced without
semantic loss.

## Requirements

- **REQ-375-01 — one grammar:** exactly one tracked
  `simulator/scenario-dsl.mjs` source owns grammar, parsing, validation, and
  serialization for both simulator families. Pages and tools do not carry a
  separately maintained parser.
- **REQ-375-02 — versioned consumer contract:** the module exports a
  machine-readable `GRAMMAR_VERSION` and a consumer assertion that fails
  closed when the imported version differs from the version expected by the
  consumer.
- **REQ-375-03 — runnable compiler:** a documented Node command compiles DSL
  to JSON and JSON to DSL for checkpoint and registry scenarios, exits
  non-zero on refusal, and does not modify the checked-in JSON unless an
  explicit output path is supplied.
- **REQ-375-04 — full corpus:** checked-in DSL sources represent all 15
  checkpoint and all 15 registry scenarios. Compiling them preserves every
  JSON value, including `expect`, `flow`, `exhibits`, forks, evidence changes,
  final-state assertions, and narrative metadata.
- **REQ-375-05 — denominators:** permanent checks discover rather than list
  the source extent, require exactly 30 non-empty scenarios, and report 104
  checkpoint plus 115 registry replayed story steps. Empty or truncated input
  is a refusal, not GREEN.
- **REQ-375-06 — direct play:** each simulator page accepts pasted text and a
  local DSL file, parses it through the shared grammar source, and plays it
  through the same story/tree/checker path used by embedded JSON. Tree, forks,
  lamps, flows, and Lean-corpus verdicts match the compiled JSON version.
- **REQ-375-07 — current-branch export:** free play exposes copy and download
  actions for the branch selected by the current cursor. The exported DSL
  recompiles to the same ordered branch, including parameter, evidence, time,
  action, expectation, flow, and exhibit observations needed for replay.
- **REQ-375-08 — fail closed:** malformed or unsupported DSL produces a
  non-zero CLI result and a diagnostic containing the source file and exact
  line. A page shows the same diagnostic and admits no origin, step, or partial
  story from the refused source.
- **REQ-375-09 — human use:** the grammar documentation contains a complete
  checkpoint example, a complete registry example, field meanings, quoting
  rules, comments, forks, and copy/paste plus file workflows.
- **REQ-375-10 — generated-page integrity:** both source pages, their
  published copies, and the stored page-template identity remain generated
  and byte-consistent under the existing build checks.

## Invariants and executable meaning

- **INV-375-ONE:** changing the grammar version while a consumer still
  asserts the prior version makes that consumer fail. A scratch mutation must
  demonstrate the failure.
- **INV-375-LOSSLESS:** for every discovered scenario, DSL to JSON is deeply
  equal to the checked-in JSON and JSON to DSL to JSON is deeply equal again.
  Independently removing each of `expect`, `flow`, and `exhibits` must make
  the comparator fail.
- **INV-375-EXTENT:** GREEN reports 30 scenarios, checkpoint steps 104, and
  registry steps 115. Empty and one-file-short scratch inputs must fail the
  extent guard.
- **INV-375-PLAY:** importing each DSL source into its actual page yields the
  same rendered tree and branch selection, lamp/exhibit set, flows, and Lean
  verdicts as its checked-in JSON counterpart.
- **INV-375-EXPORT:** a free-play branch containing time, evidence, an accepted
  action, and a forked continuation can be exported by both copy and download;
  recompilation and replay reproduce that selected branch.
- **INV-375-ATOMIC:** malformed input at the beginning and after at least one
  valid construct fails with file:line, returns no scenario, and leaves the
  prior page tree unchanged.
- **INV-375-RUNNABLE:** the documented compiler command is invoked by the
  permanent gate against real checked-in sources and produces JSON accepted by
  the existing scenario checkers.
- **INV-375-SCOPE:** no Lean, Haskell, offchain, CI workflow, corpus verdict,
  or forbidden meeting artifact changes occur.

## Acceptance mapping

1. Grammar and 30-scenario round-trip: REQ-375-01 through REQ-375-05;
   INV-375-ONE, INV-375-LOSSLESS, INV-375-EXTENT, INV-375-RUNNABLE.
2. Direct simulator play: REQ-375-06 and REQ-375-10; INV-375-PLAY.
3. Free-play branch export: REQ-375-07; INV-375-EXPORT.
4. Malformed input refusal: REQ-375-08; INV-375-ATOMIC.

## Non-goals

No Lean/model, Haskell, `ckeri`, devnet/preprod, gate-semantics, corpus-verdict,
or new-story work. JSON remains the input consumed by the existing scenario
gates.
