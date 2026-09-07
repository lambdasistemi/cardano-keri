# Spec — #355 user guide rewritten from the stories (M1 return)

## User stories

- A newcomer reads one page per story family — register, rotate, poison,
  close and reopen, hunters, the consumer checklist — written in the
  stories' words, and each page links the simulation of its story.
- A returning reader finds the old freeze and conviction pages gone, with
  no dangling links, and the story ladder kept explicitly as history.
- Every reader can tell what ships on preprod today from the accepted
  design (D-036–D-040): no page describes unbuilt design as usable.

## Requirements

- R355-01 (deleted-set): `docs/user/freeze-lifecycle.md`,
  `docs/user/conviction.md`, `docs/architecture/lifecycle-and-bonds.md`
  are deleted; no inbound links remain; `mkdocs.yml` nav is clean.
- R355-02 (rewritten): `index`, `roadmap`, `story-ladder` (as history),
  `why-cardano`, `super-watcher`, `trust-model`, `user-experience`,
  `identity-ops`, `overview`, `system` describe the current machine.
- R355-03 (amended, 19 pages + `design/registry-as-mpfs.md` surveyed):
  `architecture/observer-architecture.md`, `veridian-bridge.md`,
  `amaru-integration.md`, `design/operational.md`, `aid-model.md`,
  `defi-gate.md`, `record-cursor-projection-fidelity.md`,
  `design/business-cases/*`, `user/*` (register, close, rotate, follower,
  query-endpoint, m1-preprod-deployment, discovery-endpoint-board),
  `blog/self-certifying-identities-on-cardano.md`,
  `identity-on-cardano/PROMPT.md`, `vetting/*` are consistent with the
  current machine or explicitly marked otherwise.
- R355-04 (machine truth): prose matches `lean/CardanoKeri/Checkpoint.lean`
  on `main`: active / parked-with-hash / convicted; no withdraw; reap by
  the next keys naming payee and refund; deposit is the unfreeze; poison
  epoch-local cleared by rotation; conviction the only terminal state;
  close answers to the next keys.
- R355-05 (no internal shorthand): no epic codes (`K0`–`K10`), no role,
  pane, runtime, or orchestration vocabulary anywhere in `docs/`.
- R355-06 (ships vs designed): every touched page states what ships versus
  the accepted design, following the four existing `!!! note "What ships…"`
  pages (`architecture/lifecycle-and-bonds.md`, `architecture/overview.md`,
  `user/close.md`, `index.md` on main).
- R355-07 (story↔simulation): each story-family page links its simulation:
  `simulator/index.html` (checkpoint) and `simulator/registry/index.html`
  (registry), as local relative links — never the stale pr-317 preview URL.

## Rejection behavior

- A page that builds yet describes the retired freeze/bond/convict machine
  is wrong, even with `mkdocs build --strict` exit 0.
- A page that presents accepted design as usable today is wrong.
- Any occurrence of internal shorthand fails the slice.

## Observable success

- `mkdocs build --strict` exit 0; lychee `docs` clean (CI commands).
- INV-355-01…06 all hold on the final tree (see plan.md).
