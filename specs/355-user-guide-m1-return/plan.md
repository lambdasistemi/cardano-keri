# Plan — #355

## Strategy

One OWNER slice (S1): prose needs semantic judgment against the Lean model,
so no LIGHT topology. Rebase the inherited branch onto current `origin/main`,
finish the remaining survey, fix staleness the rebase exposes, then gate +
fresh audit + draft PR.

## Inheritance (verified 2026-09-07, not trusted)

- Branch `docs/355-m1-return` at `c6692c0`: 6 commits. Rewritten: `index`,
  `why-cardano`, `roadmap`, `story-ladder`, `design/super-watcher`,
  `design/trust-model`, `design/user-experience`,
  `architecture/identity-ops`, `architecture/overview`,
  `architecture/system`. Deleted: the R355-01 triple plus nav entries.
  Amended: `design/key-compromise.md`, `design/vlei.md`,
  `architecture/value-auth.md`.
- `main` moved since the fork: third design slice landed (D-036–D-040,
  74 theorems), `design/registry-as-mpfs.md` added with nav entry, the
  registry simulator landed at `simulator/registry/index.html`, and four
  pages gained `!!! note "What ships…"` notes (the R355-06 pattern).
- Known staleness in the branch: `index.md` still links the pr-317 preview
  URL for the registry simulator and cites 62 theorems.

## Rebase rules (conflict policy)

- Keep all three deletions. `main` touched the deleted pages only to add
  ships-notes; those notes vanish with the pages by intent.
- `docs/index.md`, `architecture/overview.md`: re-apply the branch rewrite
  on top of current main, preserving main's ships-vs-designed notes and
  registry-simulator local link (reworded into the rewritten page as needed).
- `mkdocs.yml`: keep branch deletions, absorb main's
  `design/registry-as-mpfs.md` nav entry and local registry simulator entry.
- Never revert edits by other lanes; conflicting intent beyond this policy
  is an escalation (Q/A), not a unilateral rewrite.

## Slices

- S1 `remainder`: T355-01 rebase; T355-02 remaining survey; T355-03 stale
  refs; T355-04 gate green + draft PR. Single commit-owner campaign, max
  two audited submissions, one repair bounce.

## Invariants and evidence

| ID | Statement | Evidence |
|---|---|---|
| INV-355-01 | R355-01 deleted-set holds | gate: files absent, `grep -r` for basenames finds no inbound links, `mkdocs build --strict` exit 0 |
| INV-355-02 | Prose matches Checkpoint.lean D-036–D-040 | fresh auditor semantic check per page (no executable gate exists for meaning) |
| INV-355-03 | No internal shorthand in `docs/` | gate grep for `K[0-9]\b`, `pane`, `runtime root`, `orchestrat` fails clean (zero hits); auditor spot-checks wording |
| INV-355-04 | Ships-vs-designed stated on every touched page | auditor checks each touched page names both states, following the four-note pattern |
| INV-355-05 | Every story-family page links its local simulator | gate grep: each of the six family pages contains `simulator/`; no `preview.dev.plutimus.com` URL remains in `docs/` |
| INV-355-06 | CI docs legs green | `mkdocs build --strict` exit 0; lychee `docs` with CI flags, zero errors |

## Budgets

- Owner: one campaign, ≤2 submissions. Auditor: blind semantic pass over
  the candidate diff + gate rerun. No push authority for any child.
