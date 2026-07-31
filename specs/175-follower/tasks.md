# Tasks — #175 the follower library

One `## Slice` section per bisect-safe commit. Boxes are checked by the ticket
orchestrator when the slice is accepted, in the same amended commit.

## Slice 0 — fork-spike (investigation; no commit)

- [X] T175-S0-1 Build a scratch harness under `.llm/175-fork-spike/` that starts the
      pinned devnet with a private `TMPDIR`, follows it over N2C, and records
      `(slot, block hash)` per block
- [X] T175-S0-2 Settle a transaction on chain A at a slot `> P`, snapshot the node db at
      P, rewind, restart, and reconnect without resubmitting that transaction
- [X] T175-S0-3 Record a decisive verdict (PROVED / DISPROVED / INCONCLUSIVE) in
      `.llm/175-fork-spike/REPORT.md` with reproduction commands and raw evidence copied
      out of the devnet tmpdir before the bracket exits
- [X] T175-S0-4 Navigator independently re-runs the decisive command and signs off
- [X] T175-S0-5 Orchestrator reports the verdict to the epic owner (A-001: on failure it
      goes back to the epic; there is no auto-fallback to a weaker criterion)

## Slice 1 — codecs

- [X] T175-S1-1 Add the `indexer` sublibrary to `offchain/cardano-keri.cabal` (deps on
      `cardano-node-clients:{utxo-indexer-lib,block-indexer}`, `cardano-keri`,
      `cardano-keri:deployment`) plus its test-suite wiring
- [X] T175-S1-2 RED: unit tests for `Cardano.KERI.Indexer.Codecs` — a synthetic
      cardano-ledger `TxOut` carrying the checkpoint asset and inline datum decodes to a
      `CheckpointRecord`; wrong policy, absent datum, undecodable datum, and a
      multi-candidate output are each rejected
- [X] T175-S1-3 RED: a golden test over a **real preprod checkpoint output** captured from
      the live M1 deployment (address/policy in `deploy/preprod/m1-manifest.json`, settled
      txids in `deploy/preprod/m1-*-acceptance.txt`), committed as a fixture
- [X] T175-S1-4 GREEN: implement `Cardano.KERI.Indexer.Codecs`
- [X] T175-S1-5 Module header names the upstream modules consumed (FR-11)
- [X] T175-S1-7 Wire `indexer-tests` into the gate: `offchain/flake.nix` exe+runner+check+app
      mirroring `deployment-tests`, and a `justfile` `indexer-unit` recipe added to
      `ci-offchain` (flake.lock and every pin untouched)
- [X] T175-S1-8 PROVE the wiring: break one indexer test on purpose, observe `just ci-offchain`
      go RED naming that test, restore, then full `./gate.sh` green — both transcripts in WIP.md
- [X] T175-S1-6 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 2 — read primitives

- [X] T175-S2-1 RED: tests for `Cardano.KERI.Indexer.Reads` over `withInMemoryIndexer`
      seeded through the real handler path — create/spend sequences in, expected
      `liveCheckpoints` / `checkpointForAid` out
- [X] T175-S2-2 RED: negative control — a non-checkpoint UTxO at the checkpoint address
      must not appear in the view; a spent checkpoint must disappear
- [X] T175-S2-3 GREEN: implement `liveCheckpoints`, `checkpointForAid`, `storePoint` over
      `snapshotAt`
- [X] T175-S2-5 `payerUtxos`: raw `(TxIn, TxOut)` at a funding address, shaped for a coin
      selector (FR-9b) — created returned, spent gone, other-address absent, no decoding or
      checkpoint-flavoured wrapping, same no-cached-state rule
- [X] T175-S2-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 3 — follower configuration + CLI config

- [X] T175-S3-1 RED: tests asserting the assembled `ChainSyncConfig` takes its interest
      set from the manifest checkpoint address, its start point from the deployment slot,
      and `k` from network params — not from defaults
- [X] T175-S3-2 RED: opt-env-conf parser tests over argv and env for socket path, network
      magic, `k`, start point, store path
- [X] T175-S3-3 GREEN: implement `Cardano.KERI.Indexer.Follower` and
      `Cardano.KERI.Indexer.Config`
- [X] T175-S3-5 Funding addresses (PLURAL, opt-env-conf) join the interest set alongside
      the manifest checkpoint address (FR-9b)
- [X] T175-S3-6 An OPTIONAL configured board address joins the same list (endpoint board
      released 2026-07-29: policy 54494f8a.., addr_test1wp2yjnu2..) — bound by config, NEVER
      as a constant. No schema parsing, no fixture, no board step in the journey: board
      record reads are #176, where board records can actually exist
- [X] T175-S3-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 3b — prove the mandatory flag is actually mandatory (micro-slice)

- [X] T175-S3b-1 RED: parsing an `IndexerConfig` WITHOUT `--byron-epoch-slots` must FAIL.
      Navigator finding at slice-3 COMPLETE: the fix replaced an invented constant with a
      mandatory field, but nothing asserts the mandatory-ness — a later `Opt.value` would
      silently reinstate a guessed default and no test would notice. The repair is only as
      durable as the check that protects it
- [X] T175-S3b-2 GREEN/verify + `./gate.sh`; its own bisect-safe commit, `Tasks:` trailer

## Slice 4 — rollback exactness property (acceptance heart)

- [X] T175-S4-1 RED: property over a real store — generate a block sequence with a fork;
      `follow → rollback → follow winning branch` yields a store byte-equal to following
      the winning chain from the start, and an equal derived view
- [X] T175-S4-2 Demonstrate the property is **able to fail**: seed a mutation (e.g. drop
      one inverse) and record it turning the property red; the demonstration ships with
      the slice
- [X] T175-S4-3 GREEN: whatever wiring the property needs (no engine code — the engine
      already owns the inverse)
- [X] T175-S4-4 The property's comment states the inheritance argument: the engine owns
      the inverse and our view is a pure function of the store (A-002)
- [X] T175-S4-5 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 5 — resume regression guard

- [X] T175-S5-1 RED: resume candidates are offered newest-first over the composed system
      (mpfs #355 guarded, not re-implemented)
- [X] T175-S5-2 RED: a restart resumes from the persisted point, not the configured start
      point and not genesis
- [X] T175-S5-3 GREEN: wiring as needed
- [X] T175-S5-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Slice 6 — retired fork-drill live leg

- [X] T175-S6-1 **RETIRED** — S0 no longer shapes acceptance; the local drill
      duplicated upstream behavior. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-2 **RETIRED** — the fork-drill RED/GREEN is removed with the
      consumer-local harness. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-2a **RETIRED** — the `cardano-node-clients#197` signalling seam
      existed only for the fork drill. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-2b **RETIRED** — the midway-stop negative control existed only
      for the fork drill's process manipulation. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-2d **RETIRED** — the independent snapshot/private-root control
      existed only for the fork drill. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-2c **RETIRED** — node-down and rollback-observed assertions
      existed only for the fork drill. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-3 **RETIRED** — S0/fork-drill evidence is preserved on the archive
      branch and upstream issues, not landed in this PR. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-5 **RETIRED AS WRITTEN** — `ci-live` is retained below for the
      minimal SC-1 smoke, but no longer runs or gates a fork drill. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-6 **RETIRED AS WRITTEN** — the fork-drill private-root machinery
      is removed; the retained smoke still uses a private `/code/tmp` root.
      Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6-4 **RETIRED** — no fork-drill commit lands. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).

## Slice 6b — retired fork/restart vertical journey

- [X] T175-S6b-1 **RETIRED AS WRITTEN** — only the registration → real socket →
      read-back prefix is retained below; the broader journey duplicated
      upstream behavior. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-2 **RETIRED** — live kill/restart re-proved upstream resume
      machinery. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-3 **RETIRED** — live rewind/fork/store-absence belongs to the
      upstream rollback engine. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-3b **RETIRED AS A LIVE-FORK STEP** — payer UTxOs remain covered
      by the library read-path tests and docs. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-3c **RETIRED** — crash-mid-block atomicity is an upstream engine
      invariant, not a KERI consumer-local live proof. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-4 **RETIRED AS WRITTEN** — only the retained `ci-live` smoke must
      now be demonstrated able to fail. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-5 **RETIRED** — the fork-journey transcript lives on the archive
      branch and upstream record, not in the delivery PR. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6b-6 **RETIRED** — no vertical fork-journey commit lands. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).

## Slice 6c — retired preprod recognition measurement

- [X] T175-S6c-1 **RETIRED** — an uncontrolled preprod measurement is not
      acceptance for this deterministic library ticket. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6c-2 **RETIRED** — no preprod measurement transcript is required.
      Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6c-3 **RETIRED** — the preprod measurement is removed rather than
      conditionally excluded from `ci-live`. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6c-4 **RETIRED** — no preprod handshake is attempted in this ticket.
      Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S6c-5 **RETIRED** — #176 inherits the documented follower contract,
      not an uncontrolled measurement. Audit:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).

## Slice 6d — retained live composition smoke

- [X] T175-S6d-1 Minimal live test: devnet up → real checkpoint registration →
      production follower over the real node socket → read back matching datum.
- [X] T175-S6d-2 Remove every fork-drill-only helper, recorder, negative
      control, signalling seam, raw evidence file, and build/dependency wiring.
- [X] T175-S6d-3 Add `just ci-live` that executes the smoke and fails explicitly
      on unsupported platforms; do not hide it behind a platform conditional.
- [X] T175-S6d-4 Demonstrate `ci-live` can go red by intentionally breaking the
      live assertion, capturing the non-zero transcript, then restore and run it
      green.
- [X] T175-S6d-5 Live runs use a private root under
      `/code/tmp/cardano-keri-175/`; `dist-newstyle/` remains unstaged.
- [X] T175-S6d-6 `./gate.sh` and the named flake checks are green; one commit
      with a `Tasks:` trailer.

## Slice 7 — docs

- [X] T175-S7-1 `docs/` page: what the follower indexes, running it from a node socket
      alone, payer UTxOs, the rollback guarantee and why a derived view has it,
      and what it does not do
- [X] T175-S7-2 The D1 decision trail and scale trigger for revisiting, plus the
      cold-only `csStartPoint` and young-store fail-closed semantics citing
      `lambdasistemi/cardano-node-clients#198`
- [X] T175-S7-3 Page registered in `mkdocs.yml`
- [X] T175-S7-4 `./gate.sh` green; one commit, `Tasks:` trailer

## Orchestrator-owned (no pair)

- [X] T175-S8-1 PR body written for a human reader: what this makes possible, a prose
      chapter per landed slice, no raw hash dumps in prose, normative detail quarantined
      in a technical appendix
- [X] T175-S8-1b **RETIRED** — do not land `specs/175-follower/evidence/`;
      raw fork-drill evidence is preserved on the archive branch and in the
      upstream record:
      [`chain-follower#29`](https://github.com/lambdasistemi/chain-follower/issues/29).
- [X] T175-S8-2 Deliverables re-checked against the epic's patched list (codecs, reads,
      follower config, CLI, docs, rollback property, resume test, retained live
      composition smoke)
- [X] T175-S8-2b Restore `gate.sh` to `just ci` in its own `chore:` commit at finalize, and
      say WHY in the message ("`ci-live` remains available in the justfile for the next
      ticket with live acceptance") — a future reader finding a bare restore commit will
      suspect the gate was weakened to get green, which is the opposite of what happened
- [X] T175-S8-3 Final gate green at HEAD; `COMPLETE` logged with PR URL, head SHA and
      gate evidence; merge requested through the epic owner (never self-merged)
