# Modules model — #374 headless simulator backends

Artifact ceiling: 4,500 bytes and 110 lines.

## MOD-374-CK-BACKEND — checkpoint session-tree backend

- Sole owner outside the checkpoint core of checkpoint story-tree construction,
  branch selection, free-play offers/dry-runs/moves, and evidence-tree changes.
- Depends on the checkpoint core and released checked-in scenario/corpus inputs;
  it has no page, DOM, storage, clock, network, or animation dependency.

## MOD-374-RG-BACKEND — registry session-tree backend

- Owns the equivalent registry behavior over the registry core and registry
  scenario/corpus inputs.
- Shares only the public capability shape with **MOD-374-CK-BACKEND**; neither
  backend depends on or implements the other machine.

## MOD-374-CLI — Node adapters

- One adapter per backend owns argument validation, trunk/fork cursor selection,
  deterministic JSON projection, stdout/stderr, and process exit status.
- Depends on its backend and never reconstructs tree or machine semantics.

## MOD-374-PAGES — render adapters

- Each page owns DOM events, selection controls, rendering, animation, and human
  messages over its backend's tree/session values.
- Consumes a generated backend slice and does not retain a second behavioral
  transcription.

## MOD-374-BUILD — source/page reconciliation

- Each existing build script reconciles core, scenarios, corpus, released DSL,
  backend slice, source page, and published copy.
- `--check` owns executable stale, forked, and missing-backend refusal signals;
  it does not define backend behavior.

## MOD-374-PROOF — ticket proof boundary

- Discovers story/fork extent and crosses backend imports, both core families,
  CLI projections, build reconciliation, and page minidom execution.
- Owns negative controls for extent, refusal paths, browser-global purity, and
  backend-slice drift. It changes no existing scenario-gate semantics.

## Dependency edges

- **EDGE-374-01:** backend → existing matching core and checked-in data;
  never backend → page.
- **EDGE-374-02:** CLI → backend; no direct core/session-tree reimplementation.
- **EDGE-374-03:** page render adapter → generated backend slice → core.
- **EDGE-374-04:** build reconciles tracked sources into pages/docs; production
  modules never depend on proof code.
- **EDGE-374-05:** both backends consume released grammar/data contracts without
  introducing a shared machine or a second parser.

## Promotion ruling

The stable consumer surface remains the two named modules in `simulator/`.
No package, offchain, `ckeri`, or shared-machine promotion is authorized.

