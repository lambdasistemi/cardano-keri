# Data model — S2 witness-mode

Fields, relationships, validation and state invariants. The manifest is the machine-checked
contract; `s2w-no-b-v1.1` reads exactly these fields.

## `txb-manifest.json`

| field | type | validation |
|---|---|---|
| `schema_version` | int | `1` |
| `authority.a018_final_sha256` | hex64 | exactly the A-018 final SHA |
| `surface_b.status` | enum | `ARCHIVED_RED`, the only permitted value |
| `surface_b.evidence_sha256` | hex64 | exactly the archived-RED source hash |
| `aiken_digest` | hex64 | equals line 9 of the candidate's own `scripts/s0/measure-family.sh` |
| `witness_mode` | enum | `REFERENCE` \| `INLINE` — the production selection |
| `witness_mode_determination.evidence` | non-empty string | what the verdict was read from |
| `reference_control.example` | string | `witness-mode/REFERENCE` |
| `inline_control.example` | string | `witness-mode/INLINE` |
| `inline_control.preserved` | bool | `true` |
| `inline_control.executed` | bool | `true`, and corroborated by the focused log |
| `inline_control.measured_tx_bytes` | positive int | serialized size of the INLINE rendering |
| `protocol.package` / `.package_tarball_sha256` / `.snapshot` | string / hex64 / string | non-empty; the pin provenance |
| `protocol.max_ref_script_size_per_tx` | int | `204800` |
| `protocol.ref_script_cost_stride` | int | `25600` |
| `protocol.ref_script_cost_multiplier` | number | `1.2` |
| `protocol.min_fee_ref_script_cost_per_byte` | int | `44` |
| `scripts[]` | `{role, bytes}` | measured on this ancestry |
| `aggregate.limit_name` | string | `maxRefScriptSizePerTx` |
| `aggregate.limit_bytes` | int | `204800` |
| `aggregate.ref_script_bytes` | int | **must equal** `Σ scripts[].bytes` |
| `envelope.limit_name` | non-empty string | must differ from `aggregate.limit_name` |
| `envelope.limit_bytes` | positive int | must differ from `aggregate.limit_bytes` |
| `envelope.limit_provenance` | non-empty string | names the ledger/genesis/parameter source |
| `envelope.programs[]` | see below | at least one row |
| `fee_boundary` | map int→int | keys `25599 25600 25601 25617 26448` |
| `residuals[]` | see below | both residuals present |
| `integration.origin_main_sha` | hex40 | equals live `refs/remotes/origin/main`, and an ancestor of HEAD |
| `integration.measured_source_set_sha256` | hex64 | digest of the measured source set as it now stands |
| `caveats[]` | strings | includes `size-only; transaction-fit unproven` |

### `envelope.programs[]`

`{role, program_bytes, creation_tx_bytes, signed, verdict}`.

- `signed` must be `true` — an unsigned body is not an envelope measurement, because witnesses are
  part of what has to fit;
- `creation_tx_bytes > program_bytes`, else the row is measuring the program, not the transaction;
- `verdict` is `FIT` or `EXCEED` and is **re-derived** from `creation_tx_bytes` against
  `envelope.limit_bytes`. A stated verdict that contradicts its own numbers is rejected.

### `residuals[]`

- `{id: "A3-F1", status: "ADVISORY", detail: …}` — the detail must name the
  `AIKEN_EXPECTED_VERSION` seam the shipped harness does not observe;
- `{id: "F1-ERROR-CLASSIFICATION", status: "OPEN", classification: "fail-closed safety held; error
  classification diverged"}` — verbatim.

## Forbidden shapes

- any key named `surface_b_sha`, at any depth;
- any 40-hex commit id anywhere in the `surface_b` subtree, under any key — renaming the field does
  not make a no-B commit into a Surface-B SHA;
- the string `surface_b_sha` in the report;
- a `fee_boundary` the pinned parameters cannot produce, or one whose 25,599/25,600/25,601 triple
  hides the stride boundary.

## State invariants

The manifest describes exactly one candidate tree. `integration.*` binds it to that tree, so a
manifest that survives a rebase or an `origin/main` advance without regeneration is stale by
construction and the gate says so.
