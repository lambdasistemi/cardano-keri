# Plan — #374 headless simulator backends

Artifact ceiling: 7,000 bytes and 150 lines.

## Frozen context

- Base: `370a23b64a581c7ad80681700a459372b8005ba9`.
- Branch/worktree: `issue-374-headless-backend` at
  `/code/cardano-keri-374-backend`.
- Grammar v1 is consumed from `simulator/scenario-dsl.mjs`; no parser copy is
  permitted.
- Baseline checkpoint scenario gate is the known pre-existing RED:
  25 items, 104 story steps, 42 problems. Registry is GREEN at 26 checks/115
  steps and DSL is GREEN at 30 scenarios, 104/115 steps.
- No Haskell files are owned, so `just ci` is out of scope.

## Strategy

One OWNER slice extracts each page's session-tree and free-play behavior into a
plain-Node module over its existing pure core. The two modules share a public
capability vocabulary but no machine implementation. Each page embeds the
corresponding backend implementation through a generated `@@BACKEND@@` slice
and retains only browser rendering, animation, and event adaptation.

The CLI is a thin adapter over the backend. Its JSON projection is deterministic
and includes enough selected-path state to compare records, flows, lamps, and
verdicts across trunk and fork replay. Build checks reconcile backend source,
source page, and published page and exercise can-fail scratch controls.

## Owned paths

- `simulator/checkpoint-simulator-backend.mjs`
- `simulator/registry-simulator-backend.mjs`
- `simulator/checkpoint-simulator-cli.mjs`
- `simulator/registry-simulator-cli.mjs`
- `@@BACKEND@@` integration in both simulator build scripts and pages
- page refactor strictly required to delegate non-rendering behavior
- corresponding byte-identical published page copies
- `specs/374-headless-backend/**`

## Forbidden paths and effects

- `lean/**`, `offchain/**`, `specs/36*/**`, `specs/375-*/**`
- `simulator/scenario-dsl*.mjs`, scenario directories, corpus/clauses JSON
- pure simulator cores, scene/SVG/animation assets and behavior
- `meetings/veridian-amaru/**`, `/code/cardano-keri/.orch/window-brief.md`
- new stories/endings, parser forks, devnet claims, merge, or force-push

## Verification order

After each implementation commit, run the two build checks and Node backend/CLI
controls first, then the exact frozen command set. A change in any digit of the
checkpoint 25/104/42 signature stops the campaign even if the count improves.

Exact ticket commands:

1. `node simulator/checkpoint-simulator-scenario-gate.mjs`
2. `node simulator/registry-simulator-scenario-gate.mjs`
3. `node simulator/scenario-dsl-gate.mjs`
4. `node simulator/checkpoint-simulator-build.mjs --check`
5. `node simulator/registry-simulator-build.mjs --check`
6. `node simulator/checkpoint-simulator-cli.mjs --story 1 --to-end --json`
7. `node simulator/registry-simulator-cli.mjs --story 1 --to-end --json`

The immutable ticket gate additionally exercises public imports, discovered
story/fork extent, free-play caller-visible behavior, CLI refusal controls, and
scratch `@@BACKEND@@` drift/missing-slice controls. Every count-based verdict
states discovered/executed equality and refuses zero.

## Slice

- **S374-1 / T374-01..T374-07:** deliver both backend modules, both CLIs,
  generated backend/page integrity, render-only delegation, permanent controls,
  and consumer documentation as one bisect-safe behavior commit.

Final subject: `feat(simulator): add headless backends`. The body names the two
stable import/CLI surfaces, parity and failure controls, and ends with
`Tasks: T374-01, T374-02, T374-03, T374-04, T374-05, T374-06, T374-07`.

## Audit focus

Audit import purity, tree/fork departure indices, hidden steps, branch cursor
selection, refusal records, evidence/world forks, free-play mutation aliasing,
scenario/corpus byte identity, CLI error exits and JSON determinism, generated
slice reachability, build negative controls, and exact baseline denominators.

