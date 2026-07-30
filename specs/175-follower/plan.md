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

**S0 — `fork-spike` (investigation, no commit).** Time-boxed feasibility spike
authorised by A-001: can a real node be made to serve a rollback onto a
divergent chain? Evidence lands in `.llm/175-fork-spike/REPORT.md`; the outcome
decides S6 and, if it fails, goes back to the epic (no auto-fallback).
*Dispatched first because it is the only unknown and it gates nothing else.*

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

**S6 — the live leg.** Two things are proved here over one devnet, both with a
real node and a real N2C socket and neither touching Koios:

- **SC-1 (indexing over a socket)** — the test posts a real checkpoint
  registration to a devnet via the existing
  `CheckpointTxBuilder.stagedCheckpointDevnet` machinery (already used by the
  #136 register vertical and the #114 lifecycle boundary), the follower attaches
  to that devnet's socket from a configured start point, and
  `checkpointForAid` returns the checkpoint the test just posted. This is the
  named execution path for SC-1; the residual devnet-vs-preprod gap is recorded
  in spec.md and is explicitly not claimed.
- **The fork drill** — shape determined by S0's verdict. If S0 PROVED: the
  rewind drill as a live-boundary test. If S0 DISPROVED or INCONCLUSIVE: back to
  the epic owner (A-001 is explicit — no auto-fallback to a weaker criterion).

Both legs run on a **private `TMPDIR` under `/code/tmp/cardano-keri-175/`** — desk
convention (A-003 + A-007), not `/tmp`. One move fixes two things: the fixed-path
collision becomes impossible, and node databases stop landing on a 95%-full root
(`/` has 24G free; `/code` has 402G).

### S6 ships an upstream workaround — three binding conditions

`withRestartableCardanoNode` exposes `restart` as an **atomic** stop+start: no
split, no hook between termination and spawn, so there is no supported way to
mutate the node's database while it is down. The drill needs exactly that, so S6
signals the bracket-owned node process directly. The gap is filed upstream as
**`lambdasistemi/cardano-node-clients#197`** and the epic ruled S6 ships with the
workaround rather than waiting (the same reasoning that ruled out D3: no putting
this story behind another repo's PR — and here the workaround lives in test code,
so its blast radius is a test, not the library our consumers link).

Binding conditions on the implementation:

**(a) One seam, not a smear.** The workaround lives behind a single named
function carrying `#197` in its haddock, so replacing it when the upstream seam
lands is a one-place change. Signalling logic appearing in more than one place is
wrong by construction.

**(b) No leaked node.** Prove the harness leaves no orphaned node process when the
test fails **mid-way**, not only when it passes. This host is measurably
saturated; a leaked devnet node is precisely the contention we are currently the
victim of, authored by us. A failing test that poisons the host for every other
lane is worse than a failing test.

**(c) It must fail loudly if the workaround stops working.** S6 is directly
exposed to the failure class named above. If the signal ever fails to stop the
node — an upstream lifecycle change, a race, a permissions difference — the test
must **not** quietly continue and report a green rollback that never happened.
So: assert the node is actually **down** before touching the database, and assert
the rollback was actually **observed** rather than inferred from the test reaching
its end. *If the workaround were broken, would this test still be green?* If yes,
it is not finished.

**S6c — preprod recognition measurement (supplementary evidence, non-gating).**
Authorised by the epic (A-008) as a time-boxed measurement, not a criterion:
connect to the real preprod socket `/code/cardano-preprod/ipc/node.socket`,
follow from the manifest deployment point (`csStartPoint` — no genesis walk),
and report the wall-clock to reach the live checkpoint `2f2d0cdf…#0` that this
project did not create.

*Standing conditions*: **SC-1 does not move in either direction** — devnet stays
the acceptance leg, because only a devnet can post its own checkpoint and be
forked; this is complementary evidence, never a replacement. **Non-gating
permanently**: it depends on a live socket and a chain state nobody controls, so
it must never enter `gate.sh` or `ci-live`. Store under
`/code/tmp/cardano-keri-175/`, cleaned up pass or fail. **The first decisive
obstacle stops the run** — in particular a protocol-version failure at the
handshake is not a bug to work around but a FINDING about registered contract 2
(N2C protocol version): Q-file it immediately, because a version bump is its own
bisect-safe slice by standing contract. If the measurement says hours, drop it
and record "deliberately declined, measured at N".

*Why it matters beyond this story*: it is the earliest live exercise of contract
2 against the real preprod node, which otherwise stays untested until #176 puts
its daemon on this same socket. Either outcome de-risks #176 — a clean follow
proves the stack, a handshake failure surfaces a contract problem while it is
still cheap. The S6 evidence must say so, so #176 planner inherits it.

**S6b — the vertical journey (the acceptance artefact).** One readable test that
runs SC-0 end to end for a single identity, no layer mocked: devnet up → the test
posts a real checkpoint registration → follower starts from the deployment slot
with only the socket → the watcher reads the current checkpoint and its slot →
follower killed and restarted, resuming without genesis replay and answering
identically → node rewound and forked, after which the pre-fork record is gone
with no stale record anywhere in the store.

*Placement, which the epic left to me*: **its own slice, immediately after S6**,
not folded into it. S6 establishes the fork-drill *mechanism* (with the #197
workaround and its three conditions); S6b *composes* the parts into the user's
story. Keeping them separate means each commit stays a clean vertical and a
failure in the mechanism work does not block the journey's own review — and the
journey reads as one narrative rather than as an appendix to a harness change.

*Proof of the proof*: the journey must be able to fail for the right reason at
each step. In particular step 5 must assert the **absence** of the pre-fork
record by scanning the store, not merely that a read returns the new value — an
assertion that only checks the new answer would pass with a stale record sitting
beside it, which is the exact failure this story exists to prevent.

**S7 — docs.** `docs/` page "the follower — indexed chain state from a node
socket": what it indexes, how to run it with nothing but a node socket, the
rollback guarantee *and why a derived view has it*, what it deliberately does
not do, and the D1 decision trail including
`lambdasistemi/cardano-node-clients#195`. Also registers the page in
`mkdocs.yml`.

## Ordering and independence

S1 → S2 → S3 are a chain (codecs feed reads feed the configured follower).
S4 depends on S2. S5 is independent of S4 and could swap with it. S6 depends on
S0's verdict and on S3. S7 last, so it documents what actually shipped.

S0 runs concurrently with S1's preparation because it shares no files.

## Gate

`./gate.sh` (already tracked at repo HEAD) runs `just ci` = `ci-onchain`,
`ci-blake3`, `ci-offchain`. Slices touching only `offchain/` still run the whole
gate before I accept them.

**`just ci` does not run the live-boundary e2e suite.** `ci-offchain` covers
builds, unit and deployment tests, lint, format, the devshell build and the
vector checks; the `e2e` / `e2e-checkpoint` targets are separate, Linux-only, and
gated behind the `build-node-tools` flag. So for S6 — the one slice whose entire
point is the live leg — **"gate green" would not mean "the live test ran"**. That
is the same shape as a criterion that passes without the mechanism working, one
level up, so it is called out rather than left implicit:

- S6 runs its live check **explicitly** (`just e2e` or the specific devnet
  check). **Acceptance rests on the evidence, not on the gate** (epic ruling,
  NOTE-008). The PR must carry, standing on its own:
  - the exact command invoked, **verbatim**, so a reader can re-run it;
  - its **output** — the run showing a real checkpoint transaction posted to the
    devnet and the follower indexing it from the socket — committed or linked,
    **not summarised**;
  - a STATUS line recording the run, **distinct from the gate's**;
  - evidence **dated after the final code change it covers**. Evidence captured
    before the last edit does not describe the artifact being shipped, so the
    capture is the last thing done in the slice.
  A `GATE-PASS` line alone is not acceptance for S6.
- Whether the live e2e should join `just ci` repo-wide is a **policy question for
  the epic/desk**, not something this story decides — it would make every future
  PR pay a slow Linux-only suite.

## Where the live leg physically lives

`CheckpointTxBuilder` (including `stagedCheckpointDevnet`) is an `other-module`
of the **`e2e-tests` test-suite**, not of any library — verified in
`offchain/cardano-keri.cabal`. So S6's spec module is added **inside
`offchain/e2e/`**, registered in `e2e-main.hs` and the suite's `other-modules`,
with the `indexer` sublibrary added to that suite's `build-depends`. S6 therefore
owns `offchain/e2e/**`, which slices 1-3 are explicitly forbidden from touching.

## The failure class this story is most exposed to

Almost every criterion here is "prove that a thing really happened against a real
system", which makes this ticket unusually prone to one specific bug: **a green
signal that does not entail the mechanism it is taken to prove.** It has already
appeared three times in one morning:

1. a spike PROVED bar that a rewound devnet could satisfy while re-forging
   byte-identical blocks — no fork actually demonstrated (caught by the
   navigator, before any harness was built);
2. SC-1 satisfiable through Koios — a "real node" leg proved by a third-party
   HTTP index, the one dependency this story exists to remove (caught by the
   epic owner);
3. `GATE-PASS` not entailing that the live suite ran at all (caught here).

The standing question for every check in every remaining slice: **if the
mechanism were broken, would this signal still be green?** If yes, the check is
not evidence yet, whatever colour it reports.

## Risks

- **The live leg (S6) is the only genuinely unknown scope.** Everything else is
  specified work against measured upstream APIs.
- **Host sharing**: the devnet tmpdir is a fixed path shared with any other lane
  on this machine; runs must use a private `TMPDIR`.
- **Read cost**: `checkpointForAid` decodes the live set per read. Acceptable at
  M1 scale; the revisit trigger is recorded in spec.md so #176/#177 inherit it.
