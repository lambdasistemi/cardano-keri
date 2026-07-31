# The follower — indexed chain state from a node socket

Asking a Cardano node "what UTxOs sit at this address?" over its local socket
walks the whole UTxO set: it stalls the node and does not scale. The follower
library is what every watcher process (relayer, hunter, and the future hosted
endpoint) uses instead — an in-process component that follows the chain block
by block over a **node socket alone** and keeps a local table of the
checkpoints that are live right now, converging on the canonical chain when
the chain forks.

## What it indexes

The follower registers exactly one interest-set entry, the deployment's
checkpoint address, with the upstream
`Cardano.Node.Client.UTxOIndexer.Follower.withChainSyncFollower` bring-up. The
upstream store then holds the live UTxOs at that address — which *is* the
live-checkpoint set. An indexed output is recognised as a checkpoint at read
time, not at index time: it carries an asset of the manifest's checkpoint
policy id whose asset name is the AID-derived name, and whose inline datum
decodes as `CheckpointDatumV1`. This repo owns the derived view
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

**Rollback exactness is inherited, not re-proved.** Every mutation for a
block commits in one store transaction together with its rollback point —
that is the upstream engine's invariant, not one this repo implements. Since
the derived checkpoint view is a pure function of that store, and the store
is provably exact after an unwind (proved upstream as a property, mirrored
here over the real store), the view is exact too, by construction: there is
no side cache, no derived file, and nothing that a rollback could leave
stale. A consumer-local live fork drill that tried to re-prove this by
snapshotting and restoring a real node's database duplicated the upstream
rollback engine in the wrong repository; it has been retired (see
[`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29)).

## Running it: node socket, network magic, start point

The follower is configured entirely through `opt-env-conf` — a socket path,
a network magic, the Byron epoch size, the security parameter `k`, a store
path, and an optional cold-boot start point (`--start-slot` /
`--start-block-hash`, or `CKERI_START_SLOT` / `CKERI_START_BLOCK_HASH`).
Nothing else is required: no HTTP index, no third-party service, no
extra credential. Point it at any reachable `cardano-node` N2C socket
(`CKERI_NODE_SOCKET`) and it indexes forward from either genesis or the
configured point.

```console
$ ckeri-follower \
    --node-socket /path/to/node.socket \
    --network-magic 1 \
    --byron-epoch-slots 21600 \
    --security-param-k 2160 \
    --store-path ./follower-store \
    --start-slot <deployment-slot> \
    --start-block-hash <deployment-block-hash>
```

### Cold-only start point — the young-store fail-closed case

`--start-slot`/`--start-block-hash` is a **cold-boot start only**. Once the
store has retained rollback rows from a prior run, a warm boot offers only
the store's own `getResumePoints` — the persisted intersection candidates,
newest first — and resumes from there, ignoring the configured start point.
A *young* warm store, whose few retained rows do not intersect the node
(for example, after the node itself was rolled back further than the
store's retention), **fails closed**: it does not silently fall back to
re-using the configured cold-boot point. This is an operator-visible gap in
the upstream follower's warm-boot contract, tracked upstream as
[`cardano-node-clients#198`](https://github.com/lambdasistemi/cardano-node-clients/issues/198)
— not something this repo works around locally. If you hit it, the correct
recovery is a fresh store with a `--start-slot`/`--start-block-hash` cold
boot, not a patched warm-boot fallback.

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
- No HTTP index, no Koios, no third-party data source of any kind.
- No node database snapshot/restore, no process signalling, and no
  hand-rolled N2C chain-sync recorder/intersector — the retired
  consumer-local fork drill duplicated upstream machinery this repo does
  not own; its audit and follow-ups are recorded in
  [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29)
  and [`cardano-node-clients#197`](https://github.com/lambdasistemi/cardano-node-clients/issues/197).
- No new binary and no query API surface. The hosted daemon and `ckeri`
  backend selection are separate stories.

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
