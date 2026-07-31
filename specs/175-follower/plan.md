# Plan — #175 the follower library

Design: **D1** (epic ruling A-002) — a derived view over the upstream UTxO store.
See `spec.md` § "The D1 ruling" for why, and what it gives up.

## Shape of the deliverable

A new `indexer` sublibrary inside `offchain/`, sibling to the existing
`deployment` sublibrary, consumable in-process by #176 (hosted daemon) and #177
(`ckeri` backends).

```
offchain/indexer/Cardano/KERI/Indexer/
  Codecs.hs     -- serialised TxOut -> CheckpointRecord (AID, datum, value, txin)
  Reads.hs      -- checkpointForAid, liveCheckpoints, storePoint
  Follower.hs   -- ChainSyncConfig assembly; liveUtxoHandler (IndexAddressSet ..)
  Config.hs     -- opt-env-conf parser for socket/magic/k/start/store path
```

Nothing under `offchain/lib/` (the pure KERI library) changes: `Checkpoint.Datum`
already decodes `CheckpointDatumV1`, and `Checkpoint.Message.deriveAidAssetName`
already derives the asset name. `Deployment.Manifest` already carries the
checkpoint address and policy id. We consume all three.

## Upstream consumed (nothing here is reimplemented)

| We call | For |
|---|---|
| `UTxOIndexer.Follower.withChainSyncFollower`, `ChainSyncConfig` | bring-up, reconnect, resume |
| `UTxOIndexer.Indexer.liveUtxoHandler`, `InterestSet (IndexAddressSet ..)` | the storage handler and its address filter |
| `UTxOIndexer.Indexer.snapshotAt :: Address -> IO [(TxIn, TxOut)]` | the `AddressIndex` prefix scan our reads sit on |
| `UTxOIndexer.Indexer.withInMemoryIndexer` / `withRocksDBIndexer` | test store / production store |
| `UTxOIndexer.Indexer.getResumePoints` | newest-first resume candidates (mpfs #355, already fixed upstream) |
| `BlockIndexer.Engine`, `ChainFollower.Runner`/`.Rollbacks` | watermarks, rollback log, phase — never touched by us |

## Storage

Not our choice and not our axis: D1 reads the upstream store, which is
`rocksdb-kv-transactions` (in-memory backend for tests, RocksDB for production).
The desk's sqlite-vs-RocksDB question does not gate this story — see spec.md.

## Slices (one bisect-safe commit each)

**S0 — `fork-spike` (historical investigation, retired).** The spike and later
fork-drill work established that the consumer-local harness duplicated
upstream behavior and misused the cold-only `csStartPoint` as a warm fallback.
Its raw evidence is preserved on `archive/175-fork-drill-harness`; the audit
closed with no action in
[`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
No part of S0 gates this library ticket.

**S1 — codecs.** `Cardano.KERI.Indexer.Codecs`: decode a serialised ledger
`TxOut` into `Maybe CheckpointRecord` — AID recovered from the asset name under
the manifest policy, `CheckpointDatumV1` from the inline datum, plus value and
address. Rejects: wrong policy, no datum, undecodable datum, an output carrying
several candidate assets. Creates the `indexer` sublibrary and its test-suite
wiring.
*Proof*: unit tests over (a) a synthetic `TxOut` built with cardano-ledger and
(b) **a real preprod checkpoint output** captured from the live M1 deployment
(`deploy/preprod/m1-manifest.json`: address `addr_test1wqxpds…`, policy
`0c16c12c…`; the settled txids are in `deploy/preprod/m1-*-acceptance.txt`).
A decoder proven only on bytes we generated ourselves is not proven.

**S2 — reads.** `Cardano.KERI.Indexer.Reads`: `payerUtxos` (raw `(TxIn, TxOut)` at a
funding address, shaped for a coin selector — see FR-9b), `liveCheckpoints` (prefix scan at
the checkpoint address, decode, drop non-checkpoints) and `checkpointForAid`.
*Proof*: unit tests over `withInMemoryIndexer` seeded through the real handler
path — create/spend sequences in, expected view out. Includes the negative
control: a non-checkpoint UTxO at the same address must not appear.

**S3 — follower config + CLI.** `Cardano.KERI.Indexer.Follower` assembles
`ChainSyncConfig` (`csInterestSet = IndexAddressSet {manifest checkpoint address + the configured
funding addresses}` (FR-9b: plural funding addresses via opt-env-conf), `csHandlers = liveUtxoHandler that :| []`, `csStartPoint` from the
deployment slot, `csSecurityParamK` from network params) and
`Cardano.KERI.Indexer.Config` declares socket/magic/k/start/store-path via
opt-env-conf, matching `Deployment.CLI` conventions.
*Proof*: unit tests asserting the assembled config's interest set, start point
and `k` come from the manifest/params rather than defaults; opt-env-conf parser
tests over argv/env.

**S4 — rollback exactness property (the acceptance heart).** A property in the
`ArmageddonSpec` shape over a real store: generate a block sequence with a fork,
apply `follow → rollback → follow the winning branch`, and assert the store —
and therefore `liveCheckpoints` — is byte-equal to following the winning chain
from the start. The property's comment must state the inheritance argument
(engine owns the inverse; our view is a pure function of the store), per A-002.
*Proof of the proof*: the property must be shown able to fail — a seeded
mutation (e.g. skipping one inverse) must turn it red, and that demonstration is
part of the slice, not an afterthought.

**S5 — resume regression guard.** Assert resume candidates are offered
newest-first over the composed system, and that a restart resumes from the
persisted point rather than the start point. This guards mpfs #355 against
regression rather than re-implementing its fix.
*Proof*: unit test over a seeded rollback log; restart test over an in-memory
store re-opened.

**S6 — retained live composition smoke.** Over one private devnet, the test
posts a real checkpoint registration through
`CheckpointTxBuilder.stagedCheckpointDevnet`, starts the production follower
from the configured point using only the real N2C socket, then reads the
checkpoint from the follower store and matches the registered datum. Koios and
all mocks are forbidden from this path.

The smoke deliberately stops there. Node database snapshot/restore, process
signalling, N2C recorders, fork observation, restart, and the preprod
measurement are retired. Those mechanisms tested the upstream follower rather
than KERI's composition and are recorded in
[`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).

Add a named `just ci-live` recipe that executes this smoke. It must not be
hidden by a platform conditional: unsupported platforms fail with a clear
message rather than silently omitting the proof. Demonstrate the recipe's
wiring by intentionally breaking the live assertion, running `just ci-live`,
and capturing the expected non-zero transcript before restoring the test and
capturing a green run. Live runs use a private `TMPDIR` under
`/code/tmp/cardano-keri-175/`.

**S7 — docs.** `docs/` page "the follower — indexed chain state from a node
socket": what it indexes, how to run it with nothing but a node socket, the
rollback guarantee *and why a derived view has it*, what it deliberately does
not do, payer UTxOs, and the D1 decision trail. It also states the cold-only
`csStartPoint` semantics and young-store fail-closed case, citing
[`cardano-node-clients#198`](https://github.com/lambdasistemi/cardano-node-clients/issues/198),
and registers the page in `mkdocs.yml`.

## Ordering and independence

S1 → S2 → S3 are a chain (codecs feed reads feed the configured follower).
S4 depends on S2. S5 is independent of S4 and could swap with it. The retained
S6 smoke depends on S3. S7 last, so it documents what actually shipped.

## Gate

`./gate.sh` (already tracked at repo HEAD) runs `just ci` = `ci-onchain`,
`ci-blake3`, `ci-offchain`. Slices touching only `offchain/` still run the whole
gate before I accept them.

`just ci` does not run the live-boundary suite. The retained smoke therefore has
its own explicit `just ci-live` acceptance command. The final tracked
`gate.sh` is restored to `just ci`; ticket acceptance runs both commands and
keeps the intentional RED transcript as proof that `ci-live` is wired.

## Where the live leg physically lives

`CheckpointTxBuilder` (including `stagedCheckpointDevnet`) is an `other-module`
of the **`e2e-tests` test-suite**, not of any library. The minimal follower
smoke therefore lives inside `offchain/e2e/`, is registered in `e2e-main.hs`
and the suite's `other-modules`, and adds only the dependencies needed by that
composition.

## The failure class this story is most exposed to

The remaining live criterion is prone to one specific bug: **a green signal
that does not entail the mechanism it is taken to prove.** SC-1 must cross the
real node socket, and `ci-live` must be shown able to fail. A compiled-but-never
executed test is not evidence.

The standing question for every check in every remaining slice: **if the
mechanism were broken, would this signal still be green?** If yes, the check is
not evidence yet, whatever colour it reports.

## Risks

- **Host sharing**: the devnet tmpdir is a fixed path shared with any other lane
  on this machine; runs must use a private `TMPDIR`.
- **Read cost**: `checkpointForAid` decodes the live set per read. Acceptable at
  M1 scale; the revisit trigger is recorded in spec.md so #176/#177 inherit it.
