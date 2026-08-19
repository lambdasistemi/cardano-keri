# Plan — S2 witness-mode, no-B recut

## Ancestry

Branch `ms11/s2-no-b` from the ruled main snapshot `77e392dd33f62f50a7b5cc5b5fd9214a507244bb`, with
the accepted S0 head `137edef07917d493914e73e69b72839b2c833b50` integrated at
`260c072c3d7ff415223ce8c8defa17d8db7d965f` (automatic merge, no conflicts, no product edit). The two
are divergent — merge-base `ae99e35e6aee577ccfc61a62f8a72f6067c1154b` — so the integration is
explicit, not implied.

## Seed, and what the seed is not

The old lane's provisional diff `c73fedc..9049f37` (sha256
`57e14f888ded15b6a7fc927a89e23b68c96cf569bbcf4282cf2ca0e3866f708c`, 7 paths) may be read or
replayed as an implementation seed under A-018-REV1. It carries **no acceptance by identity**: every
conflict is resolved on this ancestry and every gate, baseline, audit and CI check reruns against
the resulting SHA.

Known seed defects that must not survive replay:

- its manifest carries `surface_b_sha` — forbidden, and killed three ways by the gate;
- its report and manifest are old-ancestry and provisional throughout;
- it measures a transaction size but has **no signed per-program creation-transaction envelope**,
  which is the substance of `S2W-R6`;
- `append`/`cursor` figures depended on the unmerged decoder copy. `18,732` and `14,876` are not
  current-main facts.

Expected replay conflicts, from the old lane's terminal handoff: `Fixtures.hs` (`testPParams` gains
the pinned fee parameter — a *shared* record, so reapply against the then-current shape), the cabal
exports/dependencies, `Main.hs` suite wiring, and the report/manifest schema.

Safe seed order: S0 integration (done) → RED tests → production, fixture and report replay with an
explicit archived-RED Surface-B object.

## Constraints

- Percentages truncate; no half-up rounding.
- The S0 binary-content pin, not the version string, is the toolchain control: residual `A3-F1`
  leaves the shipped harness blind to the `AIKEN_EXPECTED_VERSION` seam.
- Two-token interlock on every cold realization: programme `/tmp/ms-keri-11/BUILD-TOKEN` first,
  then host `/tmp/machine/BUILD-TOKEN`, through the runtime wrapper
  (sha256 `4948acc1813649a5eade505508f637bc5415619865bdcd6a533baa562065068b`). Hooks re-verified
  hook-free in this worktree; a commit therefore takes no token while that holds, and `--no-verify`
  is never used.

## Slices

One bisect-safe behavior slice, `s2w-witness-mode`, in `OWNER` topology. The four DESIGN-NOTE-001
requirements are **not** absorbed; their decomposition comes from the milestone owner afterwards.

## Topology

Ticket owner Claude Opus 5 `[1m]` high (`%6752`) → commit owner fresh Codex `gpt-5.6-sol` high →
fresh final auditor Claude Opus 5 `[1m]` high, read-only, sequential after the owner parks.
Alternation holds at both edges. Barred: grok, AGY, Qwen, any family substitution; no inline or
self audit. `draft=NONE`.

## Gate

`s2w-no-b-v1.1`, frozen.

- gate sha256 `f1fb04664637faa7997334d7a6dafbd0373798c7daf72b55acdee6bf1be1f12d`
- inputs sha256 `383161e0b8138e69fbf13d2995c143233b95c4a7fd00be681c55f3b7603857bc`
- falsification: 58 assertions, 42 kills over 40 distinct causes, 16 positive controls, 0 defects
- pre-implementation RED, then post-integration RED advancing to the next unmet obligation

`v1` was desk-verified by the milestone owner (A-001, sha256
`90e16da6947a1869e82bfcd3eaec10197df5122eb07349d1d8bf897d594d1b9f`) and remains frozen evidence at
sha256 `2787569179229caee06ae8d532c021d72d70ab4f10489bf49af8ab60f4e7c6e3`. It enforced provenance for
`.protocol` but not for the candidate-declared envelope limit — a gap I found by reading the frozen
bytes and raised in `Q-002`. A-002 (sha256
`f8a523038bb484887431c0173e91e26030112099d0be4c607284e608eda260f9`) corrected the record and granted
v1.1: exactly one added assertion, `envelope.limit_provenance`, with its own right-cause kill. The
cause-set delta was computed mechanically — one cause added, none lost.

## Live boundary

None in this slice. Every measurement is over constructed transactions against pinned protocol
parameters; no node, preprod or mainnet contact. The honest limit of that is stated in the report:
a constructed signed transaction proves envelope size, not acceptance by a live ledger.

## Final re-integration

Before acceptance: fetch, integrate then-current `origin/main`, regenerate every byte-dependent
baseline, rerun the complete gate, re-audit, rerun CI. Drift changes the candidate SHA and therefore
requires a fresh audit — the gate fails closed on `origin/main` drift rather than trusting anyone to
remember.
