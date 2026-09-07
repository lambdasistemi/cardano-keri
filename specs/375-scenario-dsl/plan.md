# Plan — #375 scenario DSL

Artifact ceiling: 7,000 bytes and 150 lines.

## Constraints

- Base and pre-slice SHA: `9b2e6b88937707cc2c571ae1e9e5f112dc248a30`.
- Branch/worktree: `issue-375-scenario-dsl` at
  `/code/cardano-keri-375-dsl`.
- Existing JSON remains authoritative gate input and must remain semantically
  identical to compilation from the DSL sources.
- The two pages remain zero-network single-file artifacts. Shared DSL logic is
  generated from `simulator/scenario-dsl.mjs`; page-local parser forks are
  forbidden.
- No Haskell files are owned, so `just ci` is out of scope.

## Strategy

One OWNER slice crosses the complete authoring seam: shared grammar and Node
compiler, the 30 lossless sources, generated page integration for paste/file
load and branch copy/download, permanent executable controls, and docs. Keeping
this as one audited slice prevents accepting a grammar whose page/export
consumer contract has not yet been exercised.

The DSL representation is lossless over both existing scenario shapes while
presenting story structure as named, line-oriented sections. Validation is
whole-document and returns either one complete typed scenario or a located
diagnostic. Both pages receive generated shared-parser code through their
existing deterministic build boundary and feed parsed values into their
existing story execution path.

## Owned paths

- `simulator/scenario-dsl.mjs`
- `simulator/scenario-dsl-cli.mjs`
- `simulator/scenario-dsl-gate.mjs`
- DSL scenario sources beneath the two existing scenario directories
- `simulator/SCENARIO-DSL.md` and relevant `simulator/README.md` references
- checkpoint and registry simulator pages, build scripts, page-template assets,
  minimal-DOM support, and byte-identical published page copies required by
  the load/export controls
- `specs/375-scenario-dsl/**`

Checked-in JSON may be regenerated only when the result is byte-comparable to
its prior semantic value; no semantic JSON delta is accepted.

## Forbidden paths and effects

- `lean/**`, `offchain/**`, `.github/workflows/ci.yml`
- `scripts/check-lean-traceability.sh`, `specs/36[3468]-*`
- `meetings/veridian-amaru/**`, `/code/cardano-keri/.orch/window-brief.md`
- corpus semantic changes, new scenarios, Haskell or shipped `ckeri` changes
- merge, force-push, sibling contact, or non-draft PR transition

## Verification order

Cheap syntax and focused DSL controls run first. The outer ticket gate then
runs both existing scenario gates and both build checks and requires their
non-empty baseline denominators. The permanent DSL control must exercise all
invariants and demonstrate each negative-control class on scratch artifacts.

Exact ticket commands:

1. `node simulator/checkpoint-simulator-scenario-gate.mjs`
2. `node simulator/registry-simulator-scenario-gate.mjs`
3. `node simulator/checkpoint-simulator-build.mjs --check`
4. `node simulator/registry-simulator-build.mjs --check`

Baseline at the frozen base: commands 1–4 exit 0; command 1 reports 104 story
steps and command 2 reports 115 story steps.

## Slice

- **S375-1 / T375-01..T375-08:** deliver all requirements and invariants as
  one bisect-safe behavior commit, independently audited before task stamping.

The final subject is `feat(simulator): add scenario DSL`; its body explains
the shared versioned grammar, lossless corpus, page load/export, and failure
controls, ending with `Tasks: T375-01, T375-02, T375-03, T375-04, T375-05,
T375-06, T375-07, T375-08`.

## Residual-risk focus for audit

The auditor must inspect unknown/duplicate-field refusal, line attribution,
large exact integers, quotes and multiline prose, branch selection, evidence
and time nodes in free play, browser copy/download fallbacks, generated-source
drift, and whether any check can pass over an empty/truncated extent.
