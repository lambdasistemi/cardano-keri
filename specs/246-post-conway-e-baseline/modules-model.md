# #246 modules model

Sits above `data-model.md` and `functions-model.md` and references them rather
than restating their contents.

## Changed responsibilities

| ID | Component | Responsibility | Change |
|---|---|---|---|
| M-01 | `offchain/flake.nix` blaster wiring | Owns hermetic artifact production, binds upstream pin identity from the locked inputs, and is the only surface that composes the runnable blaster command. | Gains the compatibility-audit surface and its two controls as part of the single runner the gate executes. |
| M-02 | `offchain/blaster/` tracked bridge contracts | Owns the tracked, reviewable statements of what the bridge must satisfy — the peer of the existing extraction and S2 contract scripts. | Gains the compatibility-audit contract and its seeded-retired-reference control. |
| M-03 | `offchain/blaster/KeriBlaster/` Lean bridge source | Owns the proof surface that references the pinned upstream packages. | Slice A: read-only subject of the audit, semantics unchanged. Any repair it needs becomes a new frozen source identity before Slice B measures anything. |
| M-04 | `offchain/flake.lock` | Owns resolved upstream identity for every declared input. | Brought into sync with its flake so evaluation from a clean checkout is non-mutating. |

## Dependency direction

```
flake blaster wiring (M-01)
  ├── locked inputs ......... pin identity        (authority for M-04)
  ├── tracked bridge contracts (M-02)
  │     └── reads ........... tracked bridge source (M-03)
  └── pinned upstream Lean packages ... resolution target
```

The audit surface depends on locked inputs, tracked bridge source, and the
pinned upstream packages. It must **not** depend on the blueprint, the
extracted programs, or any evidence artifact: it is an instrument about
*source compatibility*, and a dependency on evidence would let a broken bridge
be reported through output it had already produced.

Nothing outside the blaster wiring may consume the audit, and the audit may not
be routed into `checks.e2e`, `ckeriRunner`, or `packages.ckeri`.

## Placement

No new top-level component is promoted. The audit is placed with the existing
tracked bridge contracts (M-02) because that is the nearest stable owner of
"statements the bridge must satisfy", and its wiring is placed in M-01 because
pin identity is only available there.

The controls are part of the audit's own surface, not siblings of it. A control
that can be dropped without dropping the audit is outside the mechanism it is
supposed to guard.

## Ownership fence for Slice A

Writable: `offchain/flake.nix`, `offchain/flake.lock`, and new or changed files
under `offchain/blaster/` other than the Lean sources under
`offchain/blaster/KeriBlaster/` and `offchain/blaster/KeriBlaster.lean`, which
are read-only in this slice except for the seeded control's own owned artefact.

Forbidden: `onchain/`, `lean/`, `offchain/` Haskell sources, `deploy/`,
`docs/`, `.github/`, every other `specs/` directory, and any change that routes
the baseline artifact into a live consumer.
