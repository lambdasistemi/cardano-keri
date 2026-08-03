# The query endpoint — checkpoint answers without a node

`ckeri-query` is a hosted, read-only HTTP service that answers checkpoint,
board, and watchability questions about M1 identities directly from the
indexed chain state. A person with only `curl` — no Cardano node, no local
RocksDB store, no Koios key — can ask the public endpoint whether an AID's
checkpoint is current and get back an answer that says exactly which indexed
chain slot it came from and how stale that slot is.

The production instance is:

```text
https://ckeri.dev.plutimus.com
```

## Routes

| Method | Path | Always 200? | Description |
| --- | --- | --- | --- |
| `GET` | `/ready` | yes | Service and freshness status |
| `GET` | `/checkpoint/{aid}` | no (503 when not ready) | Current authenticated checkpoint for an AID |
| `GET` | `/board` | no (503 when not ready) | Complete authenticated endpoint-board catalog |
| `GET` | `/board/{witness_key}` | no (503 when not ready) | Authenticated endpoint-board record for a witness key |
| `GET` | `/watchability/{aid}` | no (503 when not ready) | Whether a checkpoint's declared witnesses are all listed on the board |
| `GET` | `/swagger.json` | yes | Machine-readable OpenAPI document |
| `GET` | `/swagger-ui` | yes | Interactive Swagger UI over `/swagger.json` |

`{aid}` is a self-addressing CESR E-code identifier. `{witness_key}` is a
non-transferable Ed25519 CESR B-code key. Both are the qualified-base64
(qb64) form ckeri itself prints — the same strings you already see from
`ckeri status` or a registration transcript.

## `GET /ready`

Always returns HTTP 200 with this exact shape:

```json
{
  "ready": true,
  "as_of_slot": 129921673,
  "tip_lag_slots": 0,
  "upstream": "connected",
  "reason": null
}
```

```console
$ curl -s https://ckeri.dev.plutimus.com/ready | jq
```

`ready` is `true` only when all of the following hold at once: the store has
a transactional watermark, the upstream node connection is up, a chain tip is
known, and `tip_lag_slots <= 60`. `reason` explains why the service is not
ready when it isn't (for example `"upstream disconnected"` or `"tip lag
exceeds the 60-slot freshness threshold"`); it is `null` when ready.

## `GET /checkpoint/{aid}`

```console
$ curl -s https://ckeri.dev.plutimus.com/checkpoint/E... | jq
```

```json
{
  "aid": "E...",
  "as_of_slot": 129921673,
  "tip_lag_slots": 0,
  "checkpoint": {
    "tx_id": "ccf10efe3b90833374cf712fdbe2b246f88aadf34c170c9074d16754cdf5c6f2",
    "output_index": 0,
    "sequence": 1,
    "native_sequence": 1,
    "current_keys": ["D...", "D...", "D...", "D...", "D..."],
    "current_threshold": { "type": "unweighted", "value": 2 },
    "next_key_digests": ["E...", "E...", "E..."],
    "next_threshold": { "type": "unweighted", "value": 2 },
    "witnesses": ["B...", "B...", "B..."],
    "witness_threshold": 2
  }
}
```

Substitute the AID you want to look up for `E...`. An unknown but
well-formed AID returns HTTP 200 with `"checkpoint": null` — a `null`
payload is a real answer ("no current checkpoint exists for this identity"),
not an error. A malformed CESR identifier (wrong code, wrong length, invalid
base64) returns HTTP 400:

```json
{ "error": "malformed_identifier" }
```

`tx_id` and `owner_key_hash` (board only) render as lowercase hex; every
other CESR value renders in canonical qualified-base64 form. A threshold
preserves its actual weighted or unweighted shape: an unweighted threshold is
`{"type":"unweighted","value":N}`; a weighted threshold is
`{"type":"weighted","clauses":[[{"numerator":1,"denominator":2}, ...]]}`.

## `GET /board/{witness_key}`

```console
$ curl -s https://ckeri.dev.plutimus.com/board/B... | jq
```

```json
{
  "witness_key": "B...",
  "as_of_slot": 129921673,
  "tip_lag_slots": 0,
  "board": {
    "aid": "E...",
    "scheme": "https",
    "url": "https://witness.example/",
    "tx_id": "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c",
    "output_index": 0,
    "lovelace": 5000000,
    "owner_key_hash": "3d18237dc14be14284d775a5766016c7c4c432dedce287011701c6c7"
  }
}
```

An unknown witness key returns HTTP 200 with `"board": null`. The board
record is only served after the endpoint independently validates the frozen
board marker, datum, KERI event, and signature — a forged or malformed
output fails the entire lookup closed rather than returning a partial or
untrusted catalog. Koios is not part of this serving path.

## `GET /board`

```console
$ curl -s https://ckeri.dev.plutimus.com/board | jq
```

```json
{
  "as_of_slot": 129921673,
  "tip_lag_slots": 0,
  "board": [
    {
      "witness_key": "B...",
      "aid": "E...",
      "scheme": "https",
      "url": "https://witness.example/",
      "tx_id": "5c98bb45cc3e0879a63aa5807dff7f3809ae934ccbcac54f547c189bb4e8701c",
      "output_index": 0,
      "lovelace": 5000000,
      "owner_key_hash": "3d18237dc14be14284d775a5766016c7c4c432dedce287011701c6c7"
    }
  ]
}
```

The array contains every current authenticated record in deterministic
output-reference order; an empty catalog is `"board": []`. The complete
catalog and `as_of_slot` come from one store transaction. As with the
single-record route, one forged or malformed output fails the whole response
closed with HTTP 500 rather than returning a partial catalog.

## `GET /watchability/{aid}`

```console
$ curl -s https://ckeri.dev.plutimus.com/watchability/E... | jq
```

```json
{
  "aid": "E...",
  "as_of_slot": 129921673,
  "tip_lag_slots": 0,
  "watchability": {
    "checkpoint_present": true,
    "witnesses_declared": 3,
    "witnesses_listed": 3,
    "missing_witnesses": []
  }
}
```

This compares the checkpoint's declared witness set against the current
authenticated endpoint board and reports how many declared witnesses are
actually discoverable. Unlike `/checkpoint` and `/board`, `watchability` is
never `null`: with no current checkpoint it reports
`"checkpoint_present": false`, zero counts, and an empty
`missing_witnesses` list rather than omitting the field.

## Freshness and provenance — what `as_of_slot` actually promises

Every data response carries `as_of_slot` and `tip_lag_slots` beside its
payload, and `/ready` carries the same pair at top level. This is not
decoration — it is a provenance claim about the chain state behind the
answer, and it means something specific:

`as_of_slot` is the latest rollback-log slot observed **inside the same
store transaction** that read the checkpoint, board, or watchability data.
It is deliberately not the follower's internally tracked "last processed
slot": that counter advances after each commit and is retained across a
disconnect, so it can read as fresher than the store actually is right after
a rollback. Sourcing freshness from the transactional watermark instead means
a rollback invalidates the freshness claim by the same mechanism that
invalidates the data — there is no window where a stale answer carries an
optimistic slot number.

`tip_lag_slots` is computed by sampling the observed chain tip **after** that
transaction commits, purely to measure lag; it never gates which data was
read. When the store watermark is momentarily ahead of the sampled tip, or no
tip has been observed yet, or the upstream node is disconnected, or the lag
exceeds 60 slots, the service reports itself not ready rather than publish a
freshness number it cannot stand behind.

## Fail-closed semantics

When `/ready` would report `ready: false`, every data route (`/checkpoint`,
both `/board` forms, `/watchability`) fails closed with **HTTP 503** and the same
readiness fields, plus an explicit error tag — never a stale or partial
payload:

```console
$ curl -si https://ckeri.dev.plutimus.com/checkpoint/E... 
HTTP/2 503
content-type: application/json
```

```json
{
  "ready": false,
  "as_of_slot": 129921603,
  "tip_lag_slots": null,
  "upstream": "disconnected",
  "reason": "upstream disconnected",
  "error": "service_unavailable"
}
```

The 503 body never includes `checkpoint`, `board`, or `watchability` — not
even as `null` — so a client cannot mistake a service-unavailable envelope
for a data response with an empty payload. An unexpected internal failure
(never an expected fail-closed condition) returns HTTP 500 with
`{"error":"internal_error"}` and no other detail.

## Configuration

`ckeri-query` is an `opt-env-conf` binary: every setting has a command-line
flag and a `CKERI_*` environment variable.

| Flag | Env | Default | Notes |
| --- | --- | --- | --- |
| `--node-socket` | `CKERI_NODE_SOCKET` | — | Cardano node socket path |
| `--network-magic` | `CKERI_NETWORK_MAGIC` | — | Cardano network magic |
| `--byron-epoch-slots` | `CKERI_BYRON_EPOCH_SLOTS` | — | Byron epoch size for the node-to-client codec |
| `--security-param-k` | `CKERI_SECURITY_PARAM_K` | — | Rollback-window security parameter |
| `--start-slot` / `--start-block-hash` | `CKERI_START_SLOT` / `CKERI_START_BLOCK_HASH` | origin | Follower start point |
| `--store-path` | `CKERI_STORE_PATH` | — | RocksDB indexer directory |
| `--manifest-path` | `CKERI_MANIFEST_PATH` | — | Deployment manifest JSON path |
| `--board-address` | `CKERI_BOARD_ADDRESS` | — | Endpoint-board address; **mandatory for `ckeri-query`** |
| `--port` | `CKERI_PORT` | `8080` | HTTP listen port |

`--board-address`/`CKERI_BOARD_ADDRESS` is optional in the general follower
configuration, but `ckeri-query` refuses to start without it: `/board` and
`/watchability` have nothing to authenticate against otherwise, and the
binary fails fast with a concise message rather than silently serving an
endpoint that can never answer those routes.

## One process, no derived state

`ckeri-query` is a single OS process. It opens exactly one RocksDB store
through `withRocksDBIndexerRunner`, hands the resulting handle and
transaction runner to both `withChainSyncFollower` (the chain-sync consumer)
and the HTTP application, and links the follower's async before it starts
serving — a follower failure takes the whole process down rather than
leaving a server answering from a store nothing is updating any more. There
is no second follower, no separate query database, and no replication lag
between "what was indexed" and "what the endpoint can see".

The HTTP layer itself owns no cache: no memo table, no secondary index, no
`IORef`, `MVar`, or `TVar` holding decoded data. Every response is a pure
decode of a fresh read inside one `kv-transactions` transaction — for
`/checkpoint` and `/board` that is one transaction; for `/watchability` the
same transaction reads both the checkpoint and the board catalog. There is
no rollback-invalidation logic to get wrong, because there is no derived
state to invalidate: a rollback simply changes what the next transaction
reads.

## What this endpoint does not do

`ckeri status --aid E... --endpoint https://ckeri.dev.plutimus.com` now
consumes this contract through the production CLI, delivered by
[#177](https://github.com/lambdasistemi/cardano-keri/issues/177). It validates
the checkpoint and watchability responses, including their echoed identity
and shared freshness envelope, and fails closed without falling back to a
local store or Koios.
