# Plan — #176 the hosted query endpoint

## Architecture

The service is a thin HTTP composition over the already merged follower and
upstream transactional store. `ckeri-query` replaces the interactive shell as
the foreground action; it does not duplicate the follower. The production
bracket is:

```text
withRocksDBIndexerRunner
  └─ withChainSyncFollower (same IndexerHandle)
       ├─ linked follower async
       └─ Warp HTTP app (same transaction runner + FollowerHandle)
```

The query layer receives a rank-n transaction runner and builds each response
inside one transaction. It uses upstream `IndexerProvider` address reads and
the rollback column's latest entry for the watermark. Only after that snapshot
commits does it sample follower readiness to decide whether the result may be
published and to derive tip lag. If readiness is not trustworthy, the decoded
result is discarded and the route returns 503.

The board codec reuses the existing frozen `EndpointBoard` validation semantics
while adapting indexed ledger outputs instead of Koios JSON. There is no new
storage handler or derived index. The board address is already included in the
follower interest set by configuration.

## Load-bearing invariants

1. one process owns one follower, one RocksDB store, and one HTTP server;
2. response data and `as_of_slot` come from exactly one store transaction;
3. readiness can veto publishing a snapshot but can never supply its watermark;
4. no KERI-owned state survives between HTTP requests;
5. a malformed current board output invalidates the catalog rather than
   yielding a partial answer;
6. public JSON/OpenAPI drift is caught by an executable golden;
7. deployment state is reproducible from `/code/infrastructure` alone.

## Slice 1 — transactional HTTP service and frozen contract

PAIR implementation. Add HTTP API/types/server modules, indexed board decoding,
transaction-scoped query primitives, and `ckeri-query`. Extend the existing app
composition to expose the runner without changing `ckeri-follower` behavior.
Add Servant/Warp/OpenAPI dependencies, exact response goldens, focused tests,
the generated Swagger artifact, and flake package/app/check/image wiring.

Expected implementation surface:

- `offchain/indexer/Cardano/KERI/Indexer/Query/{API,Server,Types}.hs`;
- `offchain/indexer/Cardano/KERI/Indexer/Board.hs`;
- transaction-aware additions in `Indexer.Reads` and `Indexer.App`;
- `offchain/app/CkeriQuery.hs`;
- focused modules under `offchain/indexer-test/` and golden JSON fixtures;
- `offchain/cardano-keri.cabal`, `offchain/flake.nix`, and `justfile`;
- generated `docs/assets/swagger/query-api.json`.

The immutable slice gate runs the focused application contract check, validates
the committed OpenAPI artifact, invokes the executable and Nix image/check, and
rejects mutable cache primitives in the HTTP modules. It is falsified before
dispatch by the missing focused recipe. The PAIR must additionally demonstrate
the field-drift golden goes red and restore it before proposing the candidate.

Bisect condition: the slice commit contains a runnable `ckeri-query`, all
focused and repository tests are green, and the task boxes for the slice are
stamped in that same commit.

## Slice 2 — user documentation and reproducible live acceptance helper

PAIR implementation after Slice 1 acceptance. Add “the query endpoint —
checkpoint answers without a node”, MkDocs navigation, public curl examples,
the exact schema/freshness semantics, deployment configuration, and an
operator script that records the public journey without fabricating output.
The helper may invoke curl, Docker read/stop/start for the exact upstream
container, and the NixOS rebuild command; it may not bring up the service with
an imperative compose command.

Expected repository surface:

- `docs/user/query-endpoint.md`;
- `mkdocs.yml`;
- `scripts/check-query-endpoint-preprod.sh` (or an equivalently named helper);
- a committed acceptance transcript under `deploy/preprod/` produced by the
  final service and clearly dated/provenanced.

Bisect condition: docs build, curl commands match the golden contract, the
helper has static and shell checks, and no claimed live transcript is committed
until it has actually run against the deployed release.

## Slice 3 — declarative host deployment and public journey

The ticket orchestrator prepares a separate clean infrastructure worktree; the
PAIR implements the declarative service in `/code/infrastructure` on its own
branch/PR. The cardano-keri feature commit is consumed as a fixed flake input.
The development host configuration declares:

- a Compose source owned by Nix for `ckeri-query`;
- a fixed image loaded from the cardano-keri flake output;
- `/code/cardano-preprod/ipc/node.socket` mounted read/write only as required by
  the node client, and a persistent `/code/ckeri-query/store`;
- the existing external `web` network and Traefik labels for
  `ckeri.dev.plutimus.com` with TLS;
- restart policy and an HTTP process-health probe that does not restart the
  service merely because upstream is degraded;
- a systemd lifecycle activated by `nixos-rebuild switch`.

After infrastructure review, run the live acceptance in the exact order from
the spec. Preserve raw curl/rebuild/container evidence in the ticket runtime
and commit only the concise truthful transcript. The upstream disruption is
limited to the exact `cardano-preprod` container and is restored even if an
assertion fails.

## Contract registration and ordering

The Slice 1 contract commit is pushed and the ticket STATUS receives:

```text
NOTE RELEASE: query endpoint HTTP contract at <commit-or-PR-url>
```

before #177 starts binding. Documentation and deployment consume that frozen
surface. Any later field/path change requires the executable golden and
OpenAPI artifact to change together and a new release note to the epic owner.

## Verification

Focused deterministic commands:

- `just query-endpoint-check`;
- `./gate.sh`;
- build the named flake query checks and OCI image;
- deliberate golden field rename, expected non-zero, then restore and green;
- static cache guard with its own positive-control fixture.

Live commands:

- public `curl` contract checks from a context with no node socket/store;
- exact upstream stop → 503/degraded → upstream start → recovery;
- declarative NixOS rebuild → endpoint recovery, with no manual service bring-up.

Final acceptance independently reads both repository diffs, PR metadata,
committed evidence, signature/check status, and runs the immutable gate at the
accepted head. Neither PR is merged by this ticket owner.

## Risks and controls

- **False provenance from readiness:** source watermark only from the rollback
  column in the data transaction; test readiness deliberately ahead after
  rollback.
- **Split snapshots:** count runner calls and make watchability read both
  addresses in one transaction.
- **Accidental cache:** static guard plus a mutate/rollback/re-read test; no
  mutable state in query modules.
- **Partial board truth:** one invalid current board output makes the whole
  board query fail closed.
- **Contract drift before #177:** response goldens run against the app and are
  deliberately proven red on a renamed freshness field.
- **Imperative deployment residue:** accept only Nix-owned Compose/systemd
  configuration and prove rebuild recovery.
- **Shared-host disruption:** resolve the exact container and socket before any
  stop, use a cleanup trap, and keep the outage bounded to the acceptance run.

