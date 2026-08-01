# Spec — #176 the hosted query endpoint

Story 2 of epic #171. This ticket turns the in-process follower delivered by
#175/#188 into a public read-only service. It is the producer of the HTTP
contract; #177 is the consumer that later binds `ckeri status --endpoint` to
that contract.

## User story

**As a person with a laptop and no Cardano node or local index, I can ask a
public endpoint for an AID's current checkpoint, a witness's authenticated
board record, and whether all witnesses declared by that checkpoint are
listed. Every answer says which indexed slot it came from and how far that slot
lags the observed chain tip, so a stale answer cannot masquerade as current.**

## Public HTTP contract

The first stable surface is deliberately small and unversioned; these exact
paths and snake-case JSON field names are the registry contract consumed by
#177:

- `GET /ready`
- `GET /checkpoint/{aid}` where `aid` is a self-addressing CESR E-code
- `GET /board/{witness_key}` where `witness_key` is a CESR B-code
- `GET /watchability/{aid}`
- `GET /swagger.json`
- `GET /swagger-ui`

Unknown but well-formed checkpoint or board identifiers return HTTP 200 with a
`null` payload. Malformed CESR identifiers return HTTP 400. Unexpected internal
failures return HTTP 500 without exposing internals.

`/ready` always returns HTTP 200 and this exact shape:

```json
{
  "ready": true,
  "as_of_slot": 129600000,
  "tip_lag_slots": 3,
  "upstream": "connected",
  "reason": null
}
```

`ready` is true only when the store has a transactional watermark, upstream is
connected, a tip is known, and `tip_lag_slots <= 60`. The nullable freshness
fields honestly describe cold start. `reason` is non-null when disconnected or
not yet ready.

Successful data reads return HTTP 200 with freshness beside an
endpoint-specific payload, matching the issue's acceptance transcript:

```json
{
  "aid": "E...",
  "as_of_slot": 129600000,
  "tip_lag_slots": 3,
  "checkpoint": {}
}
```

The complete top-level shapes are:

- checkpoint: top-level `aid`, `as_of_slot`, `tip_lag_slots`, and `checkpoint`;
  the nullable `checkpoint` contains `tx_id`, `output_index`, `sequence`,
  `native_sequence`, `current_keys`, `current_threshold`, `next_key_digests`,
  `next_threshold`, `witnesses`, and `witness_threshold`;
- board: top-level `witness_key`, `as_of_slot`, `tip_lag_slots`, and `board`;
  the nullable `board` contains `aid`, `scheme`, `url`, `tx_id`,
  `output_index`, `lovelace`, and `owner_key_hash`;
- watchability: top-level `aid`, `as_of_slot`, `tip_lag_slots`, and
  `watchability`; `watchability` contains `checkpoint_present`,
  `witnesses_declared`, `witnesses_listed`, and `missing_witnesses`.

CESR values are rendered in their canonical qualified-base64 form. Transaction
ids and owner key hashes are lowercase hex. Thresholds preserve their actual
weighted/unweighted datum shape: an unweighted threshold is
`{"type":"unweighted","value":1}`; a weighted threshold is
`{"type":"weighted","clauses":[[{"numerator":1,"denominator":2}]]}`.

When readiness is false, every data path fails closed with HTTP 503 and the
same readiness object as `/ready`, plus `error: "service_unavailable"`; it does
not include `checkpoint`, `board`, or `watchability`. This prevents previously
decoded data from being mistaken for a current answer.

## Functional requirements

**FR-1 — one follower, one process.** `ckeri-query` extends the merged follower
composition. It opens one RocksDB indexer, passes the same `IndexerHandle` and
transaction runner to the chain-sync follower and HTTP application, links
follower failure into the process lifetime, and runs Warp in the foreground.
There is no second follower and no separate query database.

**FR-2 — one transaction per composed response.** Each data request reads its
checkpoint/board inputs and the rollback-log watermark in one
`kv-transactions` transaction. Watchability reads both addresses in that same
transaction. No response stitches together separately committed snapshots.

**FR-3 — provenance comes from the store.** `as_of_slot` is the latest
rollback-log slot observed inside the same transaction as the returned data.
It is not `Readiness.rProcessedSlot`: upstream updates that TVar after commits
and retains it across disconnects, while rollback changes the store first.
The tip is sampled after the transaction only to calculate lag. A disconnect,
unknown tip, store watermark ahead of the sampled tip, or lag over 60 makes the
request unavailable rather than publishing a dubious freshness claim.

**FR-4 — no derived state outside the engine transaction.** The HTTP layer is a
pure decoder/renderer over fresh transactional reads. It owns no cache, memo,
secondary index, mutable map, `IORef`, `MVar`, `TVar`, or derived file. A
rollback therefore invalidates the answer by construction, not by TTL or an
auxiliary invalidation path.

**FR-5 — checkpoint lookup.** The endpoint scans the configured checkpoint
address in the upstream index, decodes the current authenticated checkpoint
records, and selects the requested AID. It does not query the node UTxO set.

**FR-6 — authenticated board lookup.** The endpoint scans the configured board
address and validates the frozen board marker, datum, KERI event, and signature
using the existing `Cardano.KERI.Deployment.EndpointBoard` semantics. A forged
or malformed output fails the entire board view closed; a partial catalog is
never returned. Koios is absent from the serving path.

**FR-7 — watchability.** For the requested checkpoint, the endpoint compares
the datum's declared witness keys with the current authenticated board catalog.
Duplicates do not inflate `witnesses_listed`; missing keys are returned in
canonical B-code form. With no current checkpoint it returns
`checkpoint_present: false`, zero counts, and an empty missing list.

**FR-8 — bounded M1 scan, no local index.** The current deployment has one
checkpoint address and one board address with a small live set. A witness-key
lookup scans only the already address-filtered board set inside the store
transaction. This needs no upstream capability extension at M1. The #175 scale
trigger remains: around 10^4 live outputs or measured latency that makes the
scan unsuitable requires a general upstream indexed seam, never a KERI-local
cache.

**FR-9 — configuration.** `ckeri-query` reuses `FollowerSettings` and adds an
opt-env-conf listen port (`--port`, `CKERI_PORT`, default 8080). The query
binary requires the inherited `--board-address` / `CKERI_BOARD_ADDRESS`
setting even though the general follower keeps it optional; it is never
compiled in as a preprod constant.

**FR-10 — executable and container.** The flake exposes the executable as
`packages.<system>.ckeri-query`, `apps.<system>.ckeri-query`, and a Linux OCI
image suitable for declarative deployment. The image contains the executable
and CA/runtime material only; its store and node socket are mounted.

**FR-11 — executable contract check.** A deterministic test starts the real WAI
application over an in-memory upstream indexer and compares complete response
JSON to committed goldens. It covers payload and freshness fields for all four
routes, 400/503 behavior, and OpenAPI drift. The proof record includes an
intentional field rename that makes the contract check fail before restoration.

**FR-12 — documentation.** The docs page is titled “the query endpoint —
checkpoint answers without a node”. It documents the public URL, curl examples,
freshness/fail-closed semantics, all response fields, configuration, and the
producer/consumer boundary with #177.

**FR-13 — declarative hosted service.** `/code/infrastructure` declares the
image, mounted `/code/cardano-preprod/ipc/node.socket`, persistent RocksDB
directory, restart policy, Traefik route/TLS, and service lifecycle for
`https://ckeri.dev.plutimus.com`. No hand-run container is part of the deployed
state.

## Acceptance

Deterministic acceptance proves the invariant at the application seam:

1. seed a checkpoint and authenticated board record through the real in-memory
   indexer, start the WAI application, and compare exact response goldens;
2. mutate the store, repeat the request, and observe the new answer;
3. roll back, while deliberately leaving readiness's processed slot ahead, and
   observe that the response both loses the abandoned data and reports the
   lower transactional `as_of_slot`;
4. count transaction-runner invocations and prove each composed response uses
   exactly one store transaction;
5. disconnect or exceed 60 slots and observe 503 with no endpoint payload;
   reconnect and recover through the same process;
6. rename one golden field, observe the contract test red, then restore it.

Live acceptance then proves the production boundary:

1. declaratively deploy on the development/preprod host behind Traefik;
2. from a machine/process with no node socket or local store, `curl` the public
   endpoint and answer whether an M1 identity's checkpoint is current;
3. stop the exact `cardano-preprod` upstream container and observe public data
   routes fail closed while `/ready` visibly reports degraded;
4. restart upstream and observe automatic recovery without restarting the
   query service;
5. run the host's declarative rebuild and observe the endpoint returns without
   a manual compose/container command.

Per A-001, `ckeri status --endpoint` is explicitly re-assigned to #177. The #176
PR names that moved journey step rather than silently dropping it.

## Success criteria

- A stranger with only curl can query the public HTTPS endpoint and interpret
  both the answer and its freshness.
- Rollback and readiness-skew tests prove `as_of_slot` comes from the same store
  transaction as the data; no stale cache survives.
- Authenticated board lookup and watchability are served without Koios or a
  node query.
- Contract goldens are executed against the application and demonstrated able
  to fail on field drift.
- `./gate.sh`, the named flake checks, and the live acceptance journey are green.
- Infrastructure is committed declaratively and rebuild recovery is observed.
- The endpoint contract is posted as `NOTE RELEASE: ... at <commit-or-url>`
  before #177 binds.
