# Query identity status through three backends

The production `ckeri status` command can read one AID from a local follower
store, the hosted ckeri.dev endpoint, or Koios. Backend selection is part of
the next release: the installed v0.1.1 binary predates this interface. The
acceptance record for this change uses a freshly built production-package
candidate, not the older installed release.

## Retained query commands

Production `ckeri` keeps `status`, `list`, `checkpoint`, and `payer`. They all
use the same backend selection and freshness rules:

```console
ckeri status --aid E... --backend local --store /path/to/follower-store
ckeri status --aid E... --endpoint https://ckeri.dev.plutimus.com
ckeri status --aid E... --backend koios
```

- `status --aid AID` combines the checkpoint and witness-watchability view.
- `list` lists every live checkpoint visible to the selected backend; it does
  not take an AID.
- `checkpoint --aid AID` returns the selected AID's checkpoint without the
  watchability view.
- `payer --address ADDRESS` lists current UTxOs for one Bech32 payer address.

For example:

```console
ckeri list --backend local --store /path/to/follower-store \
  --manifest /absolute/path/to/m1-manifest.json \
  --board-manifest /absolute/path/to/board-manifest.json
ckeri checkpoint --aid E... --endpoint https://ckeri.dev.plutimus.com
ckeri payer --address addr_test1... --backend koios \
  --manifest /absolute/path/to/m1-manifest.json \
  --board-manifest /absolute/path/to/board-manifest.json
```

Local and Koios reads also need the checkpoint and board manifests. An
installed setup can provide them as `CKERI_MANIFEST` and
`CKERI_BOARD_MANIFEST`, in YAML as `manifest` and `board-manifest`, or with
both explicit absolute settings:

```console
--manifest /absolute/path/to/m1-manifest.json \
--board-manifest /absolute/path/to/board-manifest.json
```

The endpoint shorthand needs neither manifest and selects `endpoint` when no
explicit backend is present. Otherwise the default backend is `koios`.
Configuration precedence is command-line flags, then environment variables,
then YAML, then defaults. `--aid`/`CKERI_AID`/YAML `aid` and
`--backend`/`CKERI_BACKEND`/YAML `backend` follow that same order. A setting
for another backend is rejected; it is never silently ignored.

Backend availability is explicit:

| Capability | Local store | Hosted endpoint | Koios |
| --- | --- | --- | --- |
| `status` | supported | supported | supported |
| `list` | supported | unsupported: the #176 endpoint has no listing route | supported |
| `checkpoint` | supported | supported through the strict #176 checkpoint route | supported |
| `payer` | supported | unsupported: the #176 endpoint has no payer-UTxO route | supported |

An unsupported endpoint operation exits non-zero with a named `unsupported:`
error. It does not retry through local or Koios. Use `--backend local` with a
store for all four offline queries, or `--backend koios` for all four remote
queries. Use the endpoint shorthand only for `status` and `checkpoint`.

## Source, freshness, and errors

All successful backends render the same one-line result beginning with
`source`, `as_of_slot`, `tip_lag_slots`, and `aid`.

- Local reads obtain the checkpoint and `as_of_slot` store watermark inside
  one RocksDB transaction. If no independently observed tip accompanies the
  store, `tip_lag_slots` is honestly `unknown`; it is not borrowed from a
  network backend. The operator remains responsible for the follower store's
  recency.
- Endpoint reads name the exact endpoint URL. The slot and lag come from the
  validated endpoint response for that AID.
- Koios reads derive `as_of_slot` from the transaction that created the
  supporting live checkpoint output, then compare it with a freshly observed
  Koios tip. Request time and the tip itself are not used as the data slot.

An unavailable source, malformed response, mismatched AID, missing
provenance, incoherent result, or unsupported operation fails closed. The
selected backend never falls back to either of the other two, so an error
cannot be presented as another tier's answer.

## Recorded acceptance journey

The same AID,
`EBLf6spqM8kXCvklb99ObwQUuDzNDOMEne_GFypp52vi`, was queried exactly once
through each backend with the package candidate built from accepted source
commit `0a8ed57`. All three returned success:

| Backend | Source | `as_of_slot` | `tip_lag_slots` |
| --- | --- | ---: | ---: |
| Local | `local` | 129885696 | `unknown` |
| Endpoint | `https://ckeri.dev.plutimus.com` | 130014782 | 0 |
| Koios | `https://preprod.koios.rest/api/v1` | 129619971 | 394811 |

The concise, CI-validated provenance record is
`deploy/preprod/m1-backend-status-acceptance.txt`. It records UTC time,
operator, host/pane, `/tmp` working directory, exact
binary and SHA-256, exact commands, source-store/copy hashes, raw filenames,
raw hashes, exit status, and result. Ticket-runtime raw files remain direct
stdout-and-stderr capture bytes and are reconciled separately by the Slice 2
gate.

The earlier pre-capability raw captures are preserved unchanged under the
ticket runtime's `live/superseded-pre-capability-20260802T1652Z/` directory;
they are not evidence for this final candidate.

## What fork retirement kept and dropped

The temporary `ckeri-follower` executable is retired, but its useful query
capabilities are not: production `ckeri` keeps `status`, `list`, `checkpoint`,
and `payer`. The migration drops interactive `help` and `quit`, together with
the old prompt, completion/history, progress framing, and ad-hoc shell rendering.

The transactional store and query engine remain behind typed backend adapters.
The retained operations are reachable through the packaged production
executable, with explicit selection, uniform output, and closed errors instead
of an epic-only interactive fork.
