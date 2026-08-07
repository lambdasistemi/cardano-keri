# Plan — #257 one chain-query algebra

Artifact ceiling: 8,000 bytes and 190 lines.

## Strategy

Promote the shared query vocabulary to a small public `chain-query` Cabal
component. The existing deployment component, which owns transaction builders,
depends only on this provider-neutral component. Concrete Koios code moves to a
downstream `chain-query-koios` component; the local interpreter remains in the
downstream indexer component. Executable composition depends on all selected
tiers and constructs exactly one interpreter value.

The free program is the composition boundary. The local interpreter translates
all operations into the composable reads already in
`Cardano.KERI.Indexer.Query.Tx`, adds the store slot/hash watermark, and runs the
translated program once. The Koios interpreter translates the same operations
to its existing HTTP calls and marks the result legacy sequential. Settlement
polling is supplied separately.

Registration is the proof write verb. Its preflight and each build phase receive
named resolved snapshot values. The state-changing gap between premint and
register permits a fresh program, but each program is internally one-provider
and, for local, one-transaction. No builder performs a query during construction.

## Dependency direction

`chain-query` owns provider-neutral operations, locators, promoted result types,
watermark and consistency metadata. It depends on stable core/ledger types only.

`deployment` owns pure plans and builders and depends on `chain-query`. It has no
dependency on `chain-query-koios`, `indexer`, RocksDB, or HTTP client packages.

`chain-query-koios` depends on `chain-query` and any provider-neutral deployment
decoders it needs. It owns Koios configuration, JSON/HTTP translation, and
legacy sequential semantics.

`indexer` depends on `chain-query` and `deployment`. It owns the RocksDB
interpreter and reuses `Indexer.Query.Tx`; neither upstream component depends
back on it.

`cli` is the composition root. Legacy modules that construct Koios/node runtime
values move to this downstream component even if their public module names stay
stable. It depends on the two interpreter components and on deployment.

This graph is the enforcement for **INV-257-BUILDER**. A builder import of a
concrete interpreter cannot compile because its component lacks that dependency.

## Ordered slices

### S257-1 — algebra and component boundary

Add the provider-neutral component and promote only the shared query domain
types. Separate the legacy Koios implementation from deployment, relocate
composition-owned modules downstream, and leave all packages buildable. Add the
focused recipe and mechanical dependency/import guard.

Bisect condition: common programs and Koios interpreter compile, builder modules
depend only on `chain-query`, current Koios behavior remains covered, and no
local or registration behavior is claimed yet.

### S257-2 — local whole-program transaction

Add the indexer interpreter by translating the free program to the existing
store transaction primitives. Extend the watermark to include the corresponding
block hash. Add invocation-count and concurrent block-application coverage, and
record the intentional split-run mutation making the atomicity property fail.

Bisect condition: every local program runs once through the store runner, rows
and watermark remain coherent during concurrent application, and Koios behavior
from S257-1 remains unchanged.

### S257-3 — registration end to end

Replace registration's ad-hoc query callback slots and provider parameters with
one selected interpreter, named resolved snapshots, and a separate settlement
observer. Preserve the existing production default and submission behavior;
#240 later changes provider selection for the remaining write surface.

Bisect condition: registration preflight and build inputs flow through the
algebra, builders have no concrete provider edge or query callback, settlement
remains temporal, and focused/full gates pass.

The commit owner may use intermediate local commits for these bisect points but
returns one ticket candidate commit after squashing its owned behavior onto the
frozen planning base.

## Verification contract

- RED before implementation: the immutable gate fails on the absent
  `query-algebra-check` recipe at the frozen planning base.
- RED for atomicity: an intentional local split-run mutation causes the named
  concurrent property to fail and its receipt is recorded outside Git.
- GREEN: focused algebra/interpreter/registration examples, Cabal component
  guard, runner invocation count, and concurrent property all pass.
- Regression: existing Koios, deployment, indexer, and CLI examples remain
  green.
- Full: `./gate.sh` runs `just query-algebra-check` and root `just ci` from the
  candidate, with receipt-backed evidence and an empty worktree afterward.

## Risks and controls

- **Type promotion creates a dependency cycle:** shared result and locator types
  move to the nearest stable upstream owner; concrete decoding stays downstream.
- **A free program hides multiple local transactions:** the only local runner
  entry accepts a whole program; runner-count instrumentation and concurrent
  mutation coverage enforce one invocation.
- **Watermark slot/hash drift:** both fields come from the same rollback-column
  entry in the program transaction, never readiness state or wall clock.
- **Koios looks atomic through a common type:** consistency metadata is required
  and asserted at registration's consumer boundary.
- **Settlement leaks into snapshots:** the settlement capability has a separate
  type and runner and is absent from the operation functor.
- **Component movement breaks installed CLI behavior:** keep public command and
  module names where practical, then run existing parser/composition coverage
  and the full package gate.
- **Scope expands into #240:** migrate only registration as the proof verb; do
  not remove Koios from the rest of the write surface here.

## Artifact measurements

Provider-reported token counts are unavailable for local files.

| Artifact | Ceiling bytes / lines | Actual bytes / lines |
|---|---:|---:|
| `spec.md` | 8,000 / 180 | 6,555 / 121 |
| `plan.md` | 8,000 / 190 | 6,465 / 131 |
| `modules-model.md` | 6,000 / 150 | 4,614 / 101 |
| `data-model.md` | 6,000 / 160 | 5,198 / 141 |
| `functions-model.md` | 6,000 / 150 | 3,959 / 86 |
| `tasks.md` | 6,000 / 150 | 3,598 / 64 |
