# Tasks — #175 the follower library

One `## Slice` section per bisect-safe commit. Boxes are checked by the ticket
orchestrator when the slice is accepted, in the same amended commit.

## Slice 0 — fork-spike (investigation; no commit)

- [ ] T175-S0-1 Build a scratch harness under `.llm/175-fork-spike/` that starts the
      pinned devnet with a private `TMPDIR`, follows it over N2C, and records
      `(slot, block hash)` per block
- [ ] T175-S0-2 Settle a transaction on chain A at a slot `> P`, snapshot the node db at
      P, rewind, restart, and reconnect without resubmitting that transaction
- [ ] T175-S0-3 Record a decisive verdict (PROVED / DISPROVED / INCONCLUSIVE) in
      `.llm/175-fork-spike/REPORT.md` with reproduction commands and raw evidence copied
      out of the devnet tmpdir before the bracket exits
- [ ] T175-S0-4 Navigator independently re-runs the decisive command and signs off
- [ ] T175-S0-5 Orchestrator reports the verdict to the epic owner (A-001: on failure it
      goes back to the epic; there is no auto-fallback to a weaker criterion)

## Slice 1 — codecs

- [ ] T175-S1-1 Add the `indexer` sublibrary to `offchain/cardano-keri.cabal` (deps on
      `cardano-node-clients:{utxo-indexer-lib,block-indexer}`, `cardano-keri`,
      `cardano-keri:deployment`) plus its test-suite wiring
- [ ] T175-S1-2 RED: unit tests for `Cardano.KERI.Indexer.Codecs` — a synthetic
      cardano-ledger `TxOut` carrying the checkpoint asset and inline datum decodes to a
      `CheckpointRecord`; wrong policy, absent datum, undecodable datum, and a
      multi-candidate output are each rejected
- [ ] T175-S1-3 RED: a golden test over a **real preprod checkpoint output** captured from
      the live M1 deployment (address/policy in `deploy/preprod/m1-manifest.json`, settled
      txids in `deploy/preprod/m1-*-acceptance.txt`), committed as a fixture
- [ ] T175-S1-4 GREEN: implement `Cardano.KERI.Indexer.Codecs`
- [ ] T175-S1-5 Module header names the upstream modules consumed (FR-11)
- [ ] T175-S1-7 Wire `indexer-tests` into the gate: `offchain/flake.nix` exe+runner+check+app
      mirroring `deployment-tests`, and a `justfile` `indexer-unit` recipe added to
      `ci-offchain` (flake.lock and every pin untouched)
- [ ] T175-S1-8 PROVE the wiring: break one indexer test on purpose, observe `just ci-offchain`
      go RED naming that test, restore, then full `./gate.sh` green — both transcripts in WIP.md
- [ ] T175-S1-6 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 2 — read primitives

- [ ] T175-S2-1 RED: tests for `Cardano.KERI.Indexer.Reads` over `withInMemoryIndexer`
      seeded through the real handler path — create/spend sequences in, expected
      `liveCheckpoints` / `checkpointForAid` out
- [ ] T175-S2-2 RED: negative control — a non-checkpoint UTxO at the checkpoint address
      must not appear in the view; a spent checkpoint must disappear
- [ ] T175-S2-3 GREEN: implement `liveCheckpoints`, `checkpointForAid`, `storePoint` over
      `snapshotAt`
- [ ] T175-S2-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 3 — follower configuration + CLI config

- [ ] T175-S3-1 RED: tests asserting the assembled `ChainSyncConfig` takes its interest
      set from the manifest checkpoint address, its start point from the deployment slot,
      and `k` from network params — not from defaults
- [ ] T175-S3-2 RED: opt-env-conf parser tests over argv and env for socket path, network
      magic, `k`, start point, store path
- [ ] T175-S3-3 GREEN: implement `Cardano.KERI.Indexer.Follower` and
      `Cardano.KERI.Indexer.Config`
- [ ] T175-S3-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 4 — rollback exactness property (acceptance heart)

- [ ] T175-S4-1 RED: property over a real store — generate a block sequence with a fork;
      `follow → rollback → follow winning branch` yields a store byte-equal to following
      the winning chain from the start, and an equal derived view
- [ ] T175-S4-2 Demonstrate the property is **able to fail**: seed a mutation (e.g. drop
      one inverse) and record it turning the property red; the demonstration ships with
      the slice
- [ ] T175-S4-3 GREEN: whatever wiring the property needs (no engine code — the engine
      already owns the inverse)
- [ ] T175-S4-4 The property's comment states the inheritance argument: the engine owns
      the inverse and our view is a pure function of the store (A-002)
- [ ] T175-S4-5 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 5 — resume regression guard

- [ ] T175-S5-1 RED: resume candidates are offered newest-first over the composed system
      (mpfs #355 guarded, not re-implemented)
- [ ] T175-S5-2 RED: a restart resumes from the persisted point, not the configured start
      point and not genesis
- [ ] T175-S5-3 GREEN: wiring as needed
- [ ] T175-S5-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 6 — the live leg (shape set by Slice 0's verdict)

- [ ] T175-S6-1 Shape confirmed with the epic owner against the S0 verdict
- [ ] T175-S6-2 RED/GREEN per that shape
- [ ] T175-S6-2a Workaround for cardano-node-clients#197 behind ONE named function with the
      issue number in its haddock (one seam, not a smear)
- [ ] T175-S6-2b Prove no orphaned node process is left when the test fails MID-WAY, not
      only when it passes
- [ ] T175-S6-2d The private-tmp guard must compare against an INDEPENDENT reference (a
      private root exported OUTSIDE the shell and never re-derived from `$TMPDIR` inside
      it), so a node landing on the shared `/tmp/cardano-e2e` path still trips it; prove
      it fails by running once with a deliberately mismatched root
- [ ] T175-S6-2c Assert the node is actually DOWN before touching the db, and that the
      rollback was actually OBSERVED — the test must fail loudly if the workaround stops
      working, never report a green rollback that never happened
- [ ] T175-S6-3 Evidence recorded in the PR body whichever way S0 landed (A-001)
- [ ] T175-S6-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 7 — docs

- [ ] T175-S7-1 `docs/` page: what the follower indexes, running it from a node socket
      alone, the rollback guarantee and why a derived view has it, what it does not do
- [ ] T175-S7-2 The D1 decision trail, citing `lambdasistemi/cardano-node-clients#195`
      and the scale trigger for revisiting
- [ ] T175-S7-3 Page registered in `mkdocs.yml`
- [ ] T175-S7-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Orchestrator-owned (no pair)

- [ ] T175-S8-1 PR body written for a human reader: what this makes possible, a prose
      chapter per landed slice, no raw hash dumps in prose, normative detail quarantined
      in a technical appendix
- [ ] T175-S8-2 Deliverables re-checked against the epic's patched list (codecs, reads,
      follower config, CLI, docs, rollback property, resume test, live leg)
- [ ] T175-S8-3 Final gate green at HEAD; `COMPLETE` logged with PR URL, head SHA and
      gate evidence; merge requested through the epic owner (never self-merged)
