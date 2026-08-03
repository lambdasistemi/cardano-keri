# Spec — #177 one production query command across three backends

Story 3 of epic #171. The local read engine from #188 and the hosted HTTP
contract from #176 become implementations behind the released `ckeri` binary.
This ticket is also the retirement boundary for the temporary
`ckeri-follower` executable: its four data capabilities survive on production
`ckeri`, but its interactive shell affordances and rough presentation do not.
The complete inherited boundary is frozen in
`follower-capability-inventory.md`.

## User story

**As a person with an installed `ckeri` binary, I can ask for an AID's current
checkpoint from a local follower store, the hosted ckeri.dev endpoint, or
Koios. The result identifies its source and freshness, and an unavailable,
malformed, stale, or incoherent source fails closed instead of presenting an
answer as current.**

The no-node journey is this exact command shape:

```sh
ckeri status --aid E... --endpoint https://ckeri.dev.plutimus.com
```

`--endpoint` is an ergonomic selector for the endpoint backend. The fully
explicit equivalent is:

```sh
ckeri status --aid E... --backend endpoint \
  --endpoint https://ckeri.dev.plutimus.com
```

## Public CLI contract

`status` accepts the AID through `--aid` / `CKERI_AID` / YAML `aid`; the old
undocumented positional form is not retained. Backend selection is available
through `--backend` / `CKERI_BACKEND` / YAML `backend` with values `local`,
`endpoint`, and `koios`. Selection rules are deterministic:

- `--endpoint URL` with no explicit backend selects `endpoint`, preserving the
  producer handoff from #176;
- otherwise the default is `koios`, preserving the released command's current
  no-configuration behavior;
- `local` requires `--store PATH`; `endpoint` requires `--endpoint URL`;
- flags for a different backend are rejected instead of silently ignored.

The same backend abstraction exposes checkpoint-by-AID, authenticated
board-by-witness, and watchability operations. The production CLI uses those
operations for `status`; existing production `board list` remains available.
If a selected upstream cannot supply a requested operation coherently, it
returns a named unsupported-capability error. It must never fall through to
another backend.

Every successful status output has one stable rendered envelope containing:

- `source`: `local`, the endpoint base URL, or the Koios base URL;
- `as_of_slot`: the slot that bounds the returned data;
- `tip_lag_slots`: a non-negative lag from an observed tip;
- the requested AID and current checkpoint result;
- watchability fields when the selected backend can derive them from the same
  coherent observation.

Human-readable output may preserve the released checkpoint detail, but the
three adapters feed the same typed view and renderer. Backend-specific JSON or
the old shell's labels may not leak through.

## Functional requirements

**FR-1 — one interface, three adapters.** Define one typed query interface for
checkpoint, board, and watchability reads plus provenance/freshness. Local,
HTTP endpoint, and Koios adapters implement it. CLI dispatch selects exactly
one adapter before executing a read.

**FR-2 — local coherence.** A local composed answer obtains payload and
`as_of_slot` inside one `kv-transactions` transaction, using the #188/#176
query primitives. The observed tip may veto publication and calculate lag but
may not replace the store watermark. No derived cache, secondary mutable map,
or file is introduced outside the engine transaction.

**FR-3 — endpoint contract consumer.** The endpoint adapter consumes the exact
#176 routes and snake-case JSON. It validates identifiers, HTTP status, payload
shape, echoed identifier, `as_of_slot`, and `tip_lag_slots`. A 503, malformed
body, mismatched AID, impossible freshness value, or unavailable required
operation is a closed error with no partial status output.

**FR-4 — Koios provenance.** Refactor the existing Koios lookup rather than
duplicating it. A successful answer must derive an honest `as_of_slot` from
the records supporting that answer and compare it with a freshly observed
Koios tip. If the supporting calls cannot be bounded into one coherent
observation, or freshness cannot be established, fail closed. Do not label
request time or the tip itself as the data slot.

**FR-5 — no implicit fallback.** Network errors, stale sources, decoding
errors, missing provenance, and unsupported capabilities are errors from the
chosen backend. They never trigger local/endpoint/Koios fallback.

**FR-6 — fork retirement without capability loss.** Remove the
`ckeri-follower` Cabal executable, flake package/app/check, interactive shell
entry point, completion/history, and fork-only tests/docs/cast claims. Keep the
transactional follower/store, read codecs, query types, HTTP producer, and any
local adapter code used by
`ckeri` or `ckeri-query`. Production `ckeri` exposes the inherited `status`,
`list`, `checkpoint`, and `payer` capabilities through the typed backend seam;
a selected backend that cannot supply one fails with a named unsupported
capability and never falls through. Released artifacts remain the packaged
`ckeri` runner and its AppImage/DEB/RPM outputs; the hosted producer remains
`ckeri-query`.

**FR-7 — no leak and no loss.** Preserve the capabilities, not the REPL:
`status`, `list`, `checkpoint`, and `payer` are reachable from packaged
`ckeri` using opt-env-conf settings, typed results, and production renderers.
`help` and `quit` do not become top-level commands; prompt text, completion,
history, progress-loop framing, and the fork's ad-hoc rendering do not leak.
Standard CLI `--help` remains. The no-loss and no-leak gates are separately
proved able to fail by disconnecting one retained verb and by adding one
forbidden affordance, then restoring both mutations.

**FR-8 — executable checks.** Deterministic tests exercise the real CLI parser
and each adapter with controlled boundaries. They cover configuration
precedence, endpoint shorthand, mismatched flags, source/freshness rendering,
no fallback, malformed/stale responses, local rollback coherence, and honest
Koios provenance. A wiring guard proves the adapter tests fail when CLI
dispatch is deliberately disconnected.

**FR-9 — documentation and transcripts.** Document installable `ckeri`
commands for all three tiers and the freshness/error model. Preserve raw,
UTC-dated, operator-identified transcripts for one AID through local,
`https://ckeri.dev.plutimus.com`, and Koios. Each transcript records the exact
command, binary provenance, backend source, raw output, and exit status. Never
fabricate parity when a tier honestly fails closed.

**FR-10 — post-retirement hosted board enumeration.** After the capability-safe
fork retirement is accepted, amend #176's registered hosted read surface with
`GET /board`. A successful response has top-level `as_of_slot`,
`tip_lag_slots`, and `board`; `board` is an array in the authenticated
catalog's deterministic output-reference order. Every entry contains
`witness_key`, `aid`, `scheme`, `url`, `tx_id`, `output_index`, `lovelace`, and
`owner_key_hash`. An empty catalog is `[]`. The catalog and transactional
watermark come from one existing `boardTx`; readiness is sampled afterward.
One forged or malformed record returns HTTP 500 with no partial catalog, and
failed readiness returns the common HTTP 503 envelope with no `board` field.

**FR-11 — amended surface enforcement.** `GET /board`, `BoardListResponse`, and
`BoardListEntry` join the committed OpenAPI document and its encoder-derived
field-set drift check. The check must be observed red against an intentionally
drifted list response shape before restoration, then green with the route,
response encoder, OpenAPI contract, HTTP golden, and user documentation in
agreement. Landing publishes `NOTE RELEASE: <amended surface> at <commit>` so
the registry is updated before #162 binds.

## Acceptance

Deterministic acceptance proves:

1. the packaged binary help exposes `status --aid`, backend selection, endpoint
   shorthand, and backend-specific configuration through opt-env-conf;
2. all three adapters produce the common typed result and renderer, while
   malformed/stale/incoherent inputs fail closed without fallback;
3. local mutation and rollback are visible immediately and the reported
   `as_of_slot` is the transactional store watermark;
4. endpoint goldens match #176 and reject identifier/freshness drift;
5. Koios evidence derives its data slot from supporting records and rejects an
   answer when a coherent bound cannot be proven;
6. a deliberate dispatch disconnection makes the wiring test red before
   restoration;
7. `ckeri-follower` is absent from Cabal, flake packages/apps/checks, and
   installed artifacts, while the committed inventory and packaged help prove
   all four retained capabilities are reachable;
8. independent no-loss and no-leak mutations each make their named gate red,
   and neither mutation remains;
9. focused gates and a fresh `just ci` pass at the accepted commit.
10. `GET /board` returns the full authenticated catalog with the same
    transactional freshness claim as single-record lookup, and its HTTP and
    OpenAPI drift checks are independently proven able to fail.

Live acceptance runs the built production binary against local, hosted, and
Koios tiers for the same AID and preserves the truthful transcripts. It does
not restart or mutate the hosted service or its infrastructure.

## Success criteria

- A laptop user without a node can run
  `ckeri status --aid E... --endpoint https://ckeri.dev.plutimus.com`.
- Selecting a backend changes only the source, not the meaning or rendering of
  the answer.
- Every published answer carries honest source and freshness; uncertainty is
  an error.
- The temporary follower fork is gone and no dependency on it remains hidden.
- The PR is green and ready for review, but is not merged by this ticket owner.
