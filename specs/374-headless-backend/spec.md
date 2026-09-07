# Specification — #374 headless simulator backends

Artifact ceiling: 8,000 bytes and 170 lines.

## Outcome

A Node consumer can import either simulator's session-tree behavior and replay
an existing story trunk or fork, or perform free-play moves, without creating a
browser. The single-file pages render that same backend state.

## Requirements

- **REQ-374-01 — checkpoint backend:**
  `simulator/checkpoint-simulator-backend.mjs` imports the existing checkpoint
  core and exposes `playStory`, `playChallenge`, `offersFor`, `dryRun`,
  `submit`, `moveSlot`, and evidence add/remove operations.
- **REQ-374-02 — registry backend:**
  `simulator/registry-simulator-backend.mjs` exposes the same capability shape
  over the existing registry core. Machine-specific values remain distinct.
- **REQ-374-03 — pure boundary:** importing or calling a backend requires no
  DOM, browser storage, network, ambient clock, animation timer, or rendering
  object. Results depend only on explicit arguments and checked-in story/core
  inputs.
- **REQ-374-04 — complete tree:** story replay preserves the origin, visible
  trunk steps, every fork departure and fork step, branch identity, cursor
  selection, records, flows, sessions, and theorem/lamp observations. Hidden
  scenario control steps do not become visible tree nodes.
- **REQ-374-05 — free play:** offers, dry runs, submissions, slot moves, and
  evidence changes use the same core entry points and refusal vocabulary as
  story replay. Refused submissions remain observable records without changing
  machine state.
- **REQ-374-06 — Node CLI:** each `*-simulator-cli.mjs` accepts `--story N`,
  optional `--fork ID`, `--to-end`, and `--json`; it emits a deterministic
  machine-readable selected-path snapshot and exits non-zero for invalid
  arguments, absent stories/forks, or backend failures.
- **REQ-374-07 — generated backend integrity:** each simulator build owns one
  `@@BACKEND@@` source-to-page reconciliation. `--check` fails for a missing,
  stale, separately edited, or forked backend slice and keeps the published
  docs page byte-identical.
- **REQ-374-08 — render-only page:** the checkpoint and registry pages delegate
  session-tree behavior to their generated backend slice. DOM, canvas/SVG,
  animation, user-event wiring, and messages remain page responsibilities.
- **REQ-374-09 — preserved corpus:** all checked-in scenario, corpus, clause,
  DSL, and pure core bytes remain unchanged. Both pages retain their existing
  tree/fork behavior and `?selftest=1` minidom smoke.
- **REQ-374-10 — stable consumer surface:** the two backend module paths and
  named operations above are documented for #376. No rename or incompatible
  result-shape change is accepted without an epic ruling.

## Invariants and executable meaning

- **INV-374-PURE:** importing both backends under plain Node with browser and
  timer globals poisoned succeeds; exercised story and free-play operations do
  not touch them.
- **INV-374-PARITY:** for both families, every discovered story's trunk and
  every discovered fork replay through the backend with the existing scenario
  checker reporting no new mismatch; selected-path records, flows, states,
  lamps, and verdicts equal the page-facing representation.
- **INV-374-EXTENT:** proof discovers 15 checkpoint plus 15 registry stories,
  104 plus 115 scenario steps, and every fork. Discovered equals executed and
  zero or a one-item-short scratch extent is RED; GREEN prints both values.
- **INV-374-FREE:** at least one accepted action, one refused action, one slot
  move, one evidence addition, and one evidence removal per family crosses the
  public backend boundary and proves caller-visible state/record behavior.
- **INV-374-CLI:** the documented story-1 trunk commands and at least one
  discovered real fork per family execute without browser globals; invalid
  story and fork controls fail by their intended diagnostics.
- **INV-374-BUILD:** each real `--check` reports backend parity; scratch copies
  with a changed backend slice and with a missing backend slice both exit
  non-zero naming `backend`, while unchanged scratch copies pass.
- **INV-374-RENDER:** both existing scenario gates and minidom selftests reach
  the generated backend/page seam. Registry remains GREEN at 26 checks/115
  steps; DSL remains GREEN at 30/104/115. Checkpoint retains exactly its frozen
  pre-existing 25-item/104-step/42-problem signature.
- **INV-374-SCOPE:** no forbidden path changes; no second grammar/parser,
  scenario ending, core semantic change, or devnet claim enters the candidate.

## Acceptance mapping

1. Backend modules and stable surface: REQ-374-01..05, REQ-374-10;
   INV-374-PURE, INV-374-PARITY, INV-374-FREE.
2. Headless trunk/fork replay: REQ-374-04, REQ-374-06;
   INV-374-EXTENT, INV-374-CLI.
3. Generated pages and unchanged behavior: REQ-374-07..09;
   INV-374-BUILD, INV-374-RENDER, INV-374-SCOPE.

## Non-goals

No Lean, Haskell/offchain, devnet, shipped `ckeri`, new story, story-ending,
core-machine, machine-unification, scene/SVG, animation, or gate-semantics work.

