# The follower — indexed chain state from a node socket

Asking a Cardano node "what UTxOs sit at this address?" over its local socket
walks the whole UTxO set: it stalls the node and does not scale. The follower
library is what every watcher process (relayer, hunter, and the future hosted
endpoint) uses instead — an in-process component that follows the chain block
by block over a **node socket alone** and keeps a local table of the
checkpoints that are live right now, converging on the canonical chain when
the chain forks.

## What it indexes

The follower always registers the deployment's checkpoint address, plus every
configured funding address and the optional board address, with the upstream
`Cardano.Node.Client.UTxOIndexer.Follower.withChainSyncFollower` bring-up. The
upstream store then holds the live UTxOs at those addresses. The UTxOs at the
checkpoint address are the live-checkpoint candidates. An indexed output is
recognised as a checkpoint at read time, not at index time: it carries an asset
of the manifest's checkpoint policy id whose asset name is the AID-derived
name, and whose inline datum decodes as `CheckpointDatumV1`. This repo owns the
derived view
(`Cardano.KERI.Indexer.Reads`) and its codecs
(`Cardano.KERI.Indexer.Codecs`); it does not own chain-sync, the reconnect
loop, or the rollback engine — those are consumed from
`cardano-node-clients`, not written here.

## The D1 derived-view decision

Story #175 was written expecting this repo to own an `IndexerHandler` and
its exact inverse (the code that decides what a block adds and removes from
the store). Measurement showed that seam is not reachable: the upstream
follower's `ChainSyncConfig.csHandlers` is typed
`NonEmpty (IndexerHandler Cols [UtxoOp])`, monomorphic in a closed
four-constructor `Cols` GADT and a fixed inverse payload. A second consumer
(`cardano-mpfs-offchain`) hit the same wall and hand-rolled a 321-line
follower rather than reuse the upstream one.

The ruling (design **D1**) is: index every checkpoint-address UTxO with the
upstream's existing `liveUtxoHandler`, and derive the checkpoint-shaped view
as a pure read over that store. `Cardano.KERI.Indexer.Reads.checkpointForAid`
decodes the live checkpoint set on every read rather than maintaining a
precomputed AID-keyed index — at M1 scale (tens to hundreds of registered
AIDs) that is not a cost worth engineering around.

**Rollback exactness is inherited and verified at the KERI seam.** Every
mutation for a block commits in one store transaction together with its
rollback point. The upstream engine owns that boundary; KERI registers only
its upstream `liveUtxoHandler` inside it and derives checkpoint and payer
views directly from the committed store. A deterministic test first proves
its instrument by putting the crash outside that transaction and observing
partial derived state with no rollback point. It then injects the same failure
as a second handler inside KERI's production composition and observes an
empty store, empty derived views, and no rollback point. The succeeding run
commits all three together. There is no KERI side cache, derived file, memo,
or `IORef` that could survive the failed transaction or a rollback.

A consumer-local live fork drill that tried to re-prove the engine by
snapshotting and restoring a real node's database duplicated upstream
machinery in the wrong repository; it has been retired (see
[`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29)).

## Configuring the library

A host creates an `IndexerConfig`, passes it with the deployment `Manifest` to
`Cardano.KERI.Indexer.Follower.mkChainSyncConfig`, opens the configured store
with the upstream indexer, and supplies both to
`withChainSyncFollower`.
[`cardano-keri#188`](https://github.com/lambdasistemi/cardano-keri/issues/188)
built exactly this composition into a runnable proof; the hosted `ckeri-query`
service (#176) and the packaged `ckeri status` command's local backend (#177)
are its production consumers today.

`IndexerConfig` has an `opt-env-conf` surface for the node socket, network
magic, Byron epoch size, security parameter `k`, store path, funding
addresses, optional board address, and optional cold-boot start point. Its
start point uses the paired `--start-slot` / `--start-block-hash` options or
`CKERI_START_SLOT` / `CKERI_START_BLOCK_HASH`; the socket environment field is
`CKERI_NODE_SOCKET`. A host needs no HTTP index, third-party service, or extra
credential: it points the library at a reachable `cardano-node` N2C socket,
and the follower indexes from genesis or the configured cold start.

### Cold-only start point — the young-store fail-closed case

`--start-slot`/`--start-block-hash` is a **cold-boot start only**. Once the
store has retained rollback rows from a prior run, a warm boot offers only
the store's own `getResumePoints` — the persisted intersection candidates,
newest first — and resumes from there, ignoring the configured start point.
A *young* warm store, whose few retained rows do not intersect the node
(for example, after the node itself was rolled back further than the
store's retention), **fails closed**: it does not silently fall back to
re-using the configured cold-boot point. This is correct but underdocumented
upstream warm-boot behaviour, tracked for documentation and clearer
diagnostics as
[`cardano-node-clients#198`](https://github.com/lambdasistemi/cardano-node-clients/issues/198)
— not a request for a behaviour change and not something this repo works
around locally. If you hit it, the safe recovery is a fresh store with a
configured cold start, not a warm-boot fallback that the store cannot justify.

## Reading it: no node round trip

Once running, a consumer reads the local store directly:

- `checkpointForAid` — the current checkpoint for one AID, or `Nothing`;
- `liveCheckpoints` / `liveCheckpointsWithRejects` — every live checkpoint,
  the latter also returning outputs that failed to decode and why;
- `storePoint` — the store's current chain point, when non-empty;
- `payerUtxos` — every live UTxO at an operator-controlled funding address.

### Payer / funding UTxOs

The relayer and the hunter do not only watch — they **act**, and building a
transaction needs inputs for fees, collateral, and min-ADA. Today
`Deployment.Publisher` sources those by shelling out to
`cardano-cli query utxo` (`GetUTxOByAddress` over N2C) — the exact
node round trip this library exists to eliminate, tolerable today only
because the funding addresses are small. Funding addresses join the
follower's interest set the same way the checkpoint address does — operators
may configure more than one — and `payerUtxos` returns the raw
`(TxIn, TxOut)` pairs a coin selector needs. Rewiring `Publisher` (or any
transaction builder) off `cardano-cli` is a separate story; this library only
provides the data and proves it readable.

## What it deliberately does not do

- No chain-sync client, reconnect loop, or rollback engine of its own —
  those are `cardano-node-clients` responsibilities, consumed not written.
- No HTTP index, no Koios, no third-party data source of any kind. The
  packaged `ckeri status` command's local backend is a thin batch reader
  over this library's store, added separately in `specs/177-backends`.
- No node database snapshot/restore, no process signalling, and no
  hand-rolled N2C chain-sync recorder/intersector — the retired
  consumer-local fork drill duplicated upstream machinery this repo does
  not own; its audit and follow-ups are recorded in
  [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29)
  and [`cardano-node-clients#197`](https://github.com/lambdasistemi/cardano-node-clients/issues/197).
- No standalone interactive process of its own: the temporary follower
  executable and its interactive local-store prompt existed only while
  story #175/#188 needed a runnable proof and have been retired now that the
  packaged `ckeri status` command and the hosted `ckeri-query` service (#176)
  are the production surfaces reading this store.

## Proof: the live composition smoke

Unit and property tests exercise the derived view and rollback exactness
against the real upstream store and handler path, without a live node. One
additional live-boundary smoke closes the gap those tests cannot see: it
brings up a real `cardano-node` devnet, posts a real checkpoint registration
transaction, starts the production follower — the same
`Cardano.KERI.Indexer.Follower.mkChainSyncConfig` +
`withChainSyncFollower` composition described above — from a configured,
non-`Origin` point over the real N2C socket the devnet exposes, and reads the
registered checkpoint back through `checkpointForAid`, asserting the decoded
datum matches what was registered. No Koios, no mock follower, no seeded
store: the read genuinely comes from the node the test itself drove.

Run it explicitly with:

```console
$ just ci-live
```

`ci-live` is Linux/x86_64-only (it spawns a real `cardano-node`); on any
other platform it fails immediately with an explicit unsupported-platform
message rather than silently doing nothing. It is proved able to fail: the
live datum assertion was deliberately broken, `just ci-live` was run and
captured a non-zero exit against the full live path, and only then was the
correct assertion restored and the same command captured green.
