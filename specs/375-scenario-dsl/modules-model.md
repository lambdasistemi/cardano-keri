# Modules model — #375 scenario DSL

Artifact ceiling: 4,500 bytes and 110 lines.

This model owns changed responsibilities and dependency direction. Data is in
`data-model.md`; callable boundaries are in `functions-model.md`.

## MOD-375-GRAMMAR — shared scenario DSL module

- Sole owner of the grammar version, parser, whole-document validation,
  JSON-scenario conversion, and canonical DSL serialization for checkpoint
  and registry stories.
- Exposes the explicit version assertion consumed by external path importers.
- Has no DOM, simulator-core, filesystem, or process dependency.

## MOD-375-CLI — runnable compiler adapter

- Owns Node argument, file/stdin, stdout/output-file, exit-status, and
  file:line diagnostic behavior.
- Depends on **MOD-375-GRAMMAR** and never implements grammar rules.
- Does not mutate repository scenario JSON implicitly.

## MOD-375-SOURCES — authored DSL corpus

- Owns one human-authored DSL representation for each discovered checked-in
  checkpoint and registry JSON scenario.
- Depends only on the grammar contract; generated JSON does not depend on page
  code.

## MOD-375-PAGES — checkpoint and registry page adapters

- Own paste/file admission, user diagnostics, story selection, and copy/download
  export controls for each page's existing tree/session.
- Consumes generated **MOD-375-GRAMMAR** code and each page's existing story
  runner; owns no parser copy and no machine semantics.
- Admits a parsed story atomically only after complete validation.

## MOD-375-BUILD — deterministic page generation

- Reconciles the shared grammar source, core slices, JSON scenarios, corpus,
  page template, and published copies.
- Fails on a stale, missing, or separately edited shared-parser slice.
- Does not define grammar behavior.

## MOD-375-PROOF — permanent scenario DSL gate

- Discovers both source corpora and crosses grammar, CLI, existing scenario
  checker, real page, branch exporter, build, and consumer-version boundaries.
- Owns executable failure controls for field loss, malformed atomic refusal,
  denominator emptiness/truncation, page drift, export drift, and consumer
  version mismatch.
- Reports scenario and replay-step denominators in every GREEN result.

## Dependency edges

- **EDGE-375-01:** CLI, pages, build, and proof depend on the one grammar
  module; the grammar depends on none of them.
- **EDGE-375-02:** DSL sources compile through the grammar to the existing JSON
  scenario/checker boundary.
- **EDGE-375-03:** page adapters depend on existing page session/tree and story
  runners without changing the simulator cores.
- **EDGE-375-04:** proof crosses sources → grammar → JSON/checker and pages →
  export → grammar → checker; production modules never depend on proof code.

## Promotion ruling

The grammar remains at `simulator/scenario-dsl.mjs`, the path named by the
epic contract. Consumers import that path and assert the version they were
built against. No package-level or Haskell promotion is authorized.
