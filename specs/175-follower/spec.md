# Spec — #175 the follower library: indexed checkpoint state with exact rollback

Story 1 of epic #171 (the indexer), milestone M1. Blocks #176, #177, and the
relayer (#162) / hunter (#163, #164), which consume this library in-process.

## The problem in one paragraph

Asking a Cardano node "what UTxOs sit at this address?" over its local socket
walks the whole UTxO set: it stalls the node and does not scale. So every
watcher of our checkpoints needs its own indexed copy of the chain state it
cares about — a component that follows the chain block by block and keeps a
local table of the checkpoints that are live right now. Following forward is the
easy half. Cardano chains fork, and a block we already recorded can be un-made;
if our table keeps a record the canonical chain no longer contains, every
watcher built on it inherits a lie.

## P1 user story

**As a watcher process (relayer, hunter, or the future hosted endpoint), I want
an in-process library that follows preprod from the deployment slot over a node
socket alone and keeps a live table of current checkpoints, so that I can answer
"what is the current checkpoint for this AID?" without querying the node's UTxO
set — and so that when the chain forks, my table converges on the canonical
chain with no stale record surviving.**

## User stories

- **US-1 (follow)** — As a watcher, I start the follower with nothing but a node
  socket path, a network magic, and the deployment manifest, and it indexes
  every checkpoint UTxO from the deployment slot forward.
- **US-2 (read)** — As a watcher, I look up the current checkpoint for an AID,
  and enumerate all live checkpoints, from the local store, with no node round
  trip.
- **US-3 (rollback)** — As a watcher, when the chain rolls back, my store ends
  up exactly as if I had followed the winning chain from the start.
- **US-4 (restart)** — As an operator, I restart the follower and it resumes
  from its persisted point instead of replaying from genesis.
- **US-5 (bounded volatility)** — As an operator, I can see how far back the
  follower can still unwind, and that window is bounded by the security
  parameter `k`.
- **US-6 (run it)** — As a watcher-author reading the docs, I can run the
  follower against my own node from the documented CLI config alone.

## Functional requirements

**FR-1 — Chain-sync bring-up is consumed, not written.** The library brings the
follower up through `Cardano.Node.Client.UTxOIndexer.Follower.withChainSyncFollower`
with `ChainSyncConfig{csStartPoint = deployment slot, csSecurityParamK = network
k, csReconnectPolicy}`. This repo contributes no chain-sync client, no reconnect
loop, and no rollback engine.

**FR-2 — We configure the upstream handler; we do not write one (design D1,
ruled by the epic in A-002).** The follower registers
`liveUtxoHandler (IndexAddressSet {checkpoint address}) :| []`, so the upstream
store holds exactly the live UTxOs at the checkpoint address — which *is* the
live-checkpoint set. This repo writes no `IndexerHandler`: the upstream seam
(`csHandlers :: NonEmpty (IndexerHandler Cols [UtxoOp])`) is monomorphic in both
the closed `Cols` GADT and the `[UtxoOp]` inverse, so a KERI-owned column is not
reachable through it. See "The D1 ruling" below.

**FR-3 — Checkpoint recognition is a decode, at read time.** An indexed output
is a checkpoint when it carries an asset of the manifest's
`checkpoint.policy_id` whose asset name is the AID-derived name
(`deriveAidAssetName`) and whose inline datum decodes as
`CheckpointDatum = V1 CheckpointDatumV1`. Recognition decodes the serialised
`TxOut` the upstream store already keeps in `AddressIndex`. The upstream
`InterestSet` being address-only is an exact fit — our filter genuinely is an
address — so it is not extended.

**FR-4 — Live-checkpoint view.** For each live checkpoint the library yields the
`TxIn` carrying it, its address, its value, and its decoded `CheckpointDatumV1`
(which carries `cdSeq`, `cdNativeSn`, keys, witnesses, thresholds). The view is
derived by prefix-scanning `AddressIndex` at the checkpoint address — upstream
documents that scan as an intended use ("cursor prefix-scan by address yields
`(TxIn, TxOut)` pairs directly"). Spending a carrying UTxO without recreating it
(close/seize/burn) removes it from the store, and therefore from the view, with
no code of ours involved.

**FR-5 — One block, one transaction.** Every mutation for a block commits in a
single store transaction together with its rollback point. Under D1 this is
upstream's invariant, not one we implement: `liveUtxoHandler`'s inverse batch is
the sole input to the engine's rollback. We must not add any state that lives
outside that transaction — no side cache, no derived file, nothing that a
rollback would leave stale. The read path holds no state at all, which is what
makes this true by construction.

**FR-6 — Exact rollback.** After unwinding to a target slot, the store equals
the store produced by following the winning chain from the start — equality over
the full column contents, not a spot check — and therefore the derived view
equals it too. Under D1 the exactness is *inherited*: the engine owns the
inverse, and our view is a pure function of the store, so a correct store
necessarily yields a correct view. That inheritance argument must be visible to
a reader in the docs page and in the property's own comment; it is not to be
taken on faith.

**FR-7 — Resume.** On restart the follower offers chain-sync intersection
candidates **newest-first** (the mpfs #355 contract, already implemented
upstream as `getResumePoints`) and resumes from the persisted point.
`csStartPoint` is a cold-boot start only: once a store has retained rollback
rows, warm boot offers only `getResumePoints`. A young store whose retained
rows do not intersect the node fails closed; it does not silently reuse
`csStartPoint`. This operator-visible semantic is tracked in
[`cardano-node-clients#198`](https://github.com/lambdasistemi/cardano-node-clients/issues/198).

**FR-8 — Volatile window.** The number of retained rollback entries is
observable and bounded by `csSecurityParamK`.

**FR-9 — Read primitives.** `checkpointForAid`, `liveCheckpoints`, and the
store's current point/tip, exposed as pure store reads usable in-process by
#176 and #177 without a socket.

**FR-9b — Payer UTxOs are a third indexed pattern.** Funding addresses —
**plural**, via opt-env-conf, since an operator may fund from more than one —
join the interest set, and their live UTxOs are readable through the same store
and the same no-cached-state rule. Motivation: the relayer and hunter do not only
watch, they **act**, and building a transaction needs inputs for fees, collateral
and min-ADA. Today `Deployment.Publisher` obtains those by shelling out to
`cardano-cli query utxo`, i.e. `GetUTxOByAddress` over N2C — the exact query this
epic exists to eliminate, surviving on preprod only because our funding addresses
are tiny. The read returns raw `(TxIn, TxOut)` pairs shaped for a coin selector.
**Rewiring `Publisher` or any transaction builder off `cardano-cli` is NOT this
story** — that is story 4 (#181), and those are the producer lane's surfaces.
This story provides the data and proves it readable.

**FR-10 — CLI config via opt-env-conf.** Socket path, network magic, `k`, start
point, and store path are declared with `opt-env-conf`, consistent with
`Cardano.KERI.Deployment.CLI`.

**FR-11 — Provenance in the source.** Every module header names the upstream
modules it consumes.

**FR-12 — Docs.** A `docs/` page: "the follower — indexed chain state from a
node socket", covering what it indexes, how to run it with nothing but a node
socket, what rollback guarantees it gives, and what it deliberately does not do.

## Acceptance model

This is a library ticket. KERI owns the derived view, its codecs and reads, the
follower configuration, and proof that those pieces compose across one real
node-socket boundary. The upstream follower owns transactional rollback,
retention, intersection, and restart behavior.

The acceptance evidence is therefore:

1. property and unit tests over the real upstream store/handler path, proving
   the KERI-derived view has the same exactness as the rolled-back store;
2. one live composition smoke: devnet up → post a real checkpoint registration
   → follow it over a real N2C socket → read it back from the follower store and
   match the datum;
3. an explicit `ci-live` recipe whose wiring is proved by deliberately breaking
   the live test and capturing a non-zero run before restoring it.

The retired consumer-local fork drill is not acceptance. It duplicated the
upstream rollback engine in the wrong repository and used `csStartPoint` as if
it were a warm-boot fallback. The audit and follow-ups are recorded in
[`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29),
[`cardano-node-clients#197`](https://github.com/lambdasistemi/cardano-node-clients/issues/197),
and
[`cardano-node-clients#198`](https://github.com/lambdasistemi/cardano-node-clients/issues/198).

## Success criteria

- **SC-1** — The follower indexes a checkpoint UTxO from a **real `cardano-node`
  over a real N2C socket**, starting from a configured start point rather than
  genesis. **Execution path: a devnet the test itself posts a real checkpoint
  registration to**, reusing the existing live-boundary machinery
  (`CheckpointTxBuilder.stagedCheckpointDevnet`, already used by the #136
  register vertical and the #114 lifecycle boundary). Real node, real socket,
  real script execution, real checkpoint transaction, no third party.
  **Koios must not appear anywhere in SC-1's proof.** A follower whose
  "real node" leg leans on a third-party HTTP index proves the opposite of this
  story — the whole point is that a watcher needs nothing but a node socket.
  Koios is legitimate only for sourcing the *golden fixture's* content (SC-2's
  decoder input), which is not an acceptance path.
  **Residual gap, recorded not hidden**: this proves a devnet node, not preprod.
  A preprod socket DOES exist on this host (`/code/cardano-preprod/ipc/node.socket`,
  verified; the documented `/node/preprod/...` path is stale docs), but the
  deterministic acceptance path is the devnet that posts its own checkpoint.
- **SC-2 (the heart)** — Rollback exactness is proved as a **property** in the
  `ChainFollower.Laws` / mpfs `ArmageddonSpec` shape, over a real store:
  for a generated block sequence with a fork, `follow-then-rollback` and
  `follow-the-winning-chain-only` produce byte-equal store contents.
- **SC-3** — KERI does not re-prove the upstream rollback engine with a local
  live fork drill. Exactness is inherited because the derived view is a pure
  read of the store that upstream rolls back transactionally. The retired
  drill and the no-action audit are preserved in
  [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- **SC-4** — A restart mid-follow resumes from the persisted point; a test
  asserts the offered intersection candidates are newest-first (#355 not
  re-made). The test and docs also state that `csStartPoint` is cold-only and a
  young warm store can fail closed when none of its retained rows intersects.
- **SC-5** — Retained rollback entries stay bounded by `k` across a follow run.
- **SC-6** — A second pattern (the endpoint board) can be added **without any
  new handler and without reshaping the store**: its address joins the
  follower's interest set, and it brings its own codecs and read primitives
  alongside the checkpoint ones. Nothing about the checkpoint path has to move.
  This is a stronger claim than "another handler can be registered" — that
  mechanism is provably unavailable, since a second handler would still have to
  be an `IndexerHandler Cols [UtxoOp]` writing into a closed GADT with no board
  column, and it needs no upstream capability at all.
  *Honest edge*: this holds while the board is identifiable by address. If #165
  lands a board that is policy-identifiable across arbitrary addresses, the
  fallback is `IndexAll` with the same read-time discrimination — a larger store,
  but still no new handler and still no store reshaping. Either way the seam
  holds; only the interest set changes.
- **SC-7** — Any upstream capability gap is either shown unnecessary **with
  evidence in the PR** or landed as a linked `cardano-node-clients` PR with MPFS
  E2E evidence — never forked into this repo.
- **SC-8** — Docs page ships in this PR; CLI config via opt-env-conf; `ci-live`
  executes the live smoke and is demonstrated able to go red; every commit is
  bisect-safe with a `Tasks:` trailer; `./gate.sh` and the flake checks are
  green.

### The D1 ruling (epic A-002, 2026-07-29)

The story was written expecting this repo to own an `IndexerHandler` and its
exact inverse. Measurement showed that is not reachable through the upstream
follower: `ChainSyncConfig.csHandlers` is typed
`NonEmpty (IndexerHandler Cols [UtxoOp])` — monomorphic in both the closed
four-constructor `Cols` GADT and the `[UtxoOp]` inverse payload. A second
consumer had already hit the same wall: cardano-mpfs-offchain hand-rolled a
321-line `CageFollower` rather than use `withChainSyncFollower`.

Three designs were put to the epic owner: **D1** a derived view over the
upstream UTxO store; **D2** the mpfs shape, copying the bring-up glue into this
repo; **D3** generalising the seam upstream and consuming it. The ruling was
**D1** — D2 forks glue the standing reuse rule forbids, and D3 would put this
story behind another repo's PR for a capability D1 does not need. The gap is on
record upstream as `lambdasistemi/cardano-node-clients#195` (a record, not a
scheduling request; this story is not blocked on it).

**What D1 gives up, deliberately:** no AID-keyed column and no precomputed
index. `checkpointForAid` decodes the live checkpoint set per read. At M1 scale
(tens to hundreds of registered AIDs, each one small) that is not a cost worth
engineering around. The trigger for revisiting is a read path where the live set
no longer fits comfortably in one scan — order 10⁴ live checkpoints, or a
consumer needing a non-AID key (for example "board by witness key" in #176). At
that point the answer is D3 upstream, **not** a local index bolted onto a
derived view; #176 and #177 should not rediscover this from scratch.

### Survey results that retire two planned criteria

Both were measured during intake, against the **pinned** revisions rather than
local branch tips:

- The `cardano-node-clients` pin `a10cdb73` **already contains the block-indexer
  handler split** (`lib-block-indexer/` at the pin is byte-identical to the
  local branch tip; `a10cdb73` was `origin/main` until 2026-07-29). **No pin
  bump slice is required by this story.**
- `InterestSet` being address-only is **not** a blocker — under D1 it is an
  exact fit. Checkpoints live at one address, so the address interest set is the
  coarse filter, and `AddressIndex` keeps each output's full serialised `TxOut`;
  policy and asset-name discrimination happen when we decode in the read path.
  **No upstream `InterestSet` extension is proposed.**
  The irony is worth recording: the address-only shape we first read as a
  limitation needing an upstream extension turns out to fit **all three**
  patterns exactly — checkpoints, the future endpoint board, and now the payer's
  funding addresses. `IndexAddressSet` is literally "index the UTxOs at these
  addresses", which is what every one of them wants.

## Non-goals

- No new binary. The hosted daemon is #176; `ckeri` backend selection is #177.
- No query API surface, no HTTP, no deployment/infrastructure change.
- No board (endpoint-board) indexing. #165 has not landed and its address/policy
  **must not be invented**; this story only guarantees the board can be added
  later by extending the interest set and bringing its own codecs and reads —
  no new handler, no store reshaping (SC-6).
- No replacement of the existing Koios path (`Deployment.ChainIndex` /
  `.CheckpointIndex`) — that becomes a backend tier in #177.

## Closed and deferred axes

| Axis | Ruling |
|---|---|
| Store | RocksDB, inherited from the upstream follower stack |
| Consumer-local live fork drill | Retired; upstream audit closed with no action in `chain-follower#29` |
| `csStartPoint` warm fallback | Not supported; cold-only semantics and young-store diagnostics tracked in `cardano-node-clients#198` |
| Endpoint-board address & policy | Out of scope by design (SC-6) |

## Upstream consumed (the reuse contract)

| Module | Consumed for |
|---|---|
| `ChainFollower.Runner`, `.Rollbacks.*`, `.Laws` | rollback state machine, Lean-proved laws mirrored as properties |
| `Cardano.Node.Client.BlockIndexer.Engine` | slot watermarks, rollback log, phase, replay classification |
| `Cardano.Node.Client.BlockIndexer.Handler` | `IndexerHandler` — our one extension point |
| `Cardano.Node.Client.UTxOIndexer.Follower` | `withChainSyncFollower`, `ChainSyncConfig`, `coldBootResumePoints` |
| `Cardano.Node.Client.UTxOIndexer.BlockExtract` / `.IndexerOp` | block → `[UtxoOp]` extraction |
| `Cardano.Node.Client.N2C.ChainSync` / `.Reconnect` | transport and reconnect |
| `Cardano.MPFS.Indexer.*` (shape reference, not a dependency) | columns/codecs/handler/reads layering; `ResumeSpec`, `ArmageddonSpec` test shapes |
