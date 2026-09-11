# NON-REALIZING FALSIFICATION PLAN — witness-recut gate (design, pre-freeze)

Authority: A-026 §1 gate contract. Every control below gets a synthetic
right-cause kill provable WITHOUT realization (git-object and jq-level
mutations in disposable clones), plus a positive control. The realizing
legs (packaged mirror, full CI) list their kill shapes for the
post-release falsification run.

| control | kill (non-realizing) | right cause |
|---|---|---|
| CI-S2W-C head/tree print+verify | doctor a receipt naming the BASE head; gate must reject | `receipt-head-mismatch` |
| CI-S2W-C tree | doctor tree field only | `receipt-tree-mismatch` |
| CI-S2W-D dirty refusal | run contract prefix with one staged + one unstaged + one untracked file (three separate kills) | `dirty-worktree` / `dirty-index` / `untracked-present` |
| manifest/tree binding | disposable clone: touch one byte under a measured path WITHOUT re-deriving digest; gate recomputes and fails | `measured-source-set-drift` |
| manifest narrowing bar | shrink MEASURED_SOURCE_PATHS in a disposable gate copy; self-test must detect contract-constant drift vs frozen inputs | `measured-paths-narrowed` |
| bundle binding | edit one mandate doc without re-deriving bundle hash | `mandate-bundle-drift` |
| bundle recipe executability | delete/rename the recipe script | `bundle-recipe-missing` |
| CI-S2W-E | reintroduce a `../` literal in a disposable flake copy (static scan leg) | `path-literal-outside-inputs` |
| prefix-after-commit ordering | receipts must carry commit timestamp ≤ prefix timestamp; doctor the order | `proof-before-commit` |
| S0 equivalence | doctor the equivalence evidence tree hash | `s0-equivalence-mismatch` |
| inherited invariant battery | carry the s2w kill classes (witness-mode, pinned-protocol+provenance incl. envelope.limit_provenance, fee-boundary oracle, envelope-vs-aggregate, ARCHIVED_RED object, residual labeling, ancestry) — each with its existing right-cause string, re-authored fresh |

Positive controls: one fully-valid fixture per control class; the frozen
self-test reports kills+controls with zero defects and a cause-set
manifest for comm-delta verification at the desk.

Realizing legs (post-release only): packaged mirror = verbatim
Build-Gate attr set at authoring time (re-snapshot at freeze); dual e2e
NAMED as a residual if unmirrored; full CI; per-leg pre-command predicate
proof INSIDE the wrapper invocation path (campaign bar as parameter —
closes the wrapper residual).

Desk verification bar (what I will run before write-authorization):
hashes+manifest; self-test from my env; cause-set comm delta; contract
prefix RED right-cause on the fresh worktree pre-implementation;
dirty-tree kills live; receipt head/tree kills live.
