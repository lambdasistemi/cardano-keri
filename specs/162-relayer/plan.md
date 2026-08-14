# Technical plan

## Shape

Implement one slice, `S162-1`, over existing follower/query, KEL verification,
and deployment transaction services. Keep networking at the edge, chain reads
inside snapshot programs, and transaction construction behind a reusable
advance service. Do not add a database or shell out to external chain tools.

## Runtime sequence

1. Start the existing follower and obtain its `QueryHandle` through a promoted
   callback helper so the relayer and follower share one RocksDB runner.
2. Require the same connected/fresh readiness predicate used by the query
   server. In one read transaction obtain the watermark, live checkpoints, and
   authenticated board catalog.
3. For each checkpoint, match a board witness. Only if the valid catalog lacks
   a match, consult the explicitly configured OOBI list. Select one endpoint.
4. Fetch the KEL from the standard keripy witness query route, bounded by status,
   media type, redirects, timeout, and response size.
5. Parse and verify exactly the immediate next rotation against the checkpoint.
   Preserve its native controller signatures for the existing Plutus witness.
6. Before building, require readiness again and run one final snapshot program
   that reacquires the current checkpoint, selected endpoint identity, exact
   active output, reference scripts, and payer UTxOs. Abort if the endpoint or
   predecessor changed.
7. Use a promoted in-process `submitAdvance` service to build, submit, and await
   settlement. Never ask for an external signature file.
8. Reacquire after success or any submission/settlement/race error; classify
   exact candidate/current datum and log the current checkpoint transaction id.
9. Advance at most once, then return to polling. On process restart, repeat from
   chain/follower state with no relayer-owned cursor.

## Refactors, not copies

- Promote a follower-scoped query-handle helper from indexer application
  wiring; do not double-open RocksDB through `withLocalQueryScope`.
- Promote the query server's exact readiness sample/predicate for reuse.
- Promote the write-composition live advance/settlement service currently used
  by the manual deployment CLI.
- Extend KEL parsing with an immediate-next-rotation entry point; do not broaden
  this ticket into #220's standalone verification interface.

## Atomicity boundary

Network fetch occurs between two snapshots and is never trusted as current.
Only the second snapshot supplies transaction inputs. Its program atomically
joins candidate predecessor, endpoint identity, active output, reference
scripts, payer inputs, and watermark. A changed endpoint or datum invalidates
the fetched candidate and causes a new cycle. Readiness is checked after each
snapshot, so disconnect/staleness fails closed.

## Live-boundary proof

Add a genuine devnet journey using the production `ckeri relayer run` command,
a real authenticated endpoint-board output, and a loopback Warp server that
implements the keripy-compatible `/query` response with a genuinely signed KEL.
The journey must prove:

- discovery → fetch → verification → in-process submission → settlement/log;
- kill/restart at a blocked HTTP boundary, then one advance and no duplicate;
- two production relayers race, one transition and one `already-current`;
- forged board and forged KEL stop before transaction construction.

Wire this journey into `offchain/flake.nix` so existing `just e2e` runs it and
the existing Linux unit-test check built by `just ci` depends on it. This avoids
editing the root `justfile`, which is outside the owned surface, while making
the real journey unavoidable in the exact final gate.

## Permanent verification

- Deployment KEL tests: parser/authentication/continuity negatives.
- CLI tests: parsing, discovery selection, fallback downgrade prevention,
  final-snapshot/race classification, and stable logs.
- E2E: the four live-boundary behaviors above with required `#162 relayer`
  labels and non-zero Hspec counts.
- Documentation: new `docs/user/run-a-relayer.md` in `mkdocs.yml` navigation.

Commands, each after host preflight:

1. `just deployment-unit "#162 relayer"`
2. `just backend-check`
3. `just e2e`
4. `just ci` from the repository root

The ignored gate refuses vacuous selection by checking non-zero examples and
required labels. The root intentionally has no flake; `just ci` is the canonical
aggregate and must not be wrapped in `nix develop`. Every new positive test gets
a seeded failure or negative control before production implementation.

## Delivery order

Baseline must pass once before tracked planning. The ticket owner then copies
this mandate to `specs/162-relayer/`, opens the draft PR, commits planning,
freezes/falsifies the ignored gate, and launches exactly one Grok 4.6 xhigh
commit owner. The owner performs RED → RED commit → GREEN → proof commits but
does not push. Tier-2 CI is audit; there is no auditor or draft child.

## Operational limits

No ambient credentials, production keys, or secret-bearing deployment config
may enter the owner pane. No builds overlap foreign realization. A machine
event (missing Nix store, untouched broken recipe, or hang with no collector)
is preserved and not retried. The owner ceiling is 20 changed tracked files and
3,200 changed lines; exceeding either requires a ticket-owner challenge.
