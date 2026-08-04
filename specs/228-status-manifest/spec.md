# Specification: installed `status` manifest error (#228)

## User outcome

A release user running `ckeri status` outside a source checkout must never see a bare `withBinaryFile` exception caused by the checkout-relative board-manifest default. If the selected backend needs local manifests, the command must fail concisely and name the missing option and path. Supplying the published manifests must preserve the existing status report, including `watchable n/m` exactly.

## Requirements

- **FR-228-1:** For a local or Koios query backend, failure to open the checkpoint manifest must be reported through the normal `ckeri:` error surface and name `--manifest` plus the resolved path.
- **FR-228-2:** Failure to open the endpoint-board manifest must be reported through the normal `ckeri:` error surface and name `--board-manifest` plus the resolved path.
- **FR-228-3:** Missing-manifest diagnostics must tell the user to pass the corresponding option; they must not expose a raw `withBinaryFile` exception as the whole message.
- **FR-228-4:** A valid board manifest remains required for local/Koios watchability and produces the unchanged `watchable <listed>/<declared>` field.
- **FR-228-5:** The hosted `--endpoint` backend remains checkout-independent and must not attempt to read either manifest.
- **FR-228-6:** The regression proof must invoke the packaged `ckeri` entrypoint from a temporary working directory with no `deploy/` tree. A pure parser or unit-only proof is insufficient.

## Rejection behavior

Malformed manifests remain rejected by their existing validation messages. An explicitly supplied nonexistent path receives the same named diagnostic as the absent installed default. This slice does not silently omit watchability, fetch release assets, or derive board metadata from Koios.

## Checkout-relative default audit

The production CLI contains these same-class defaults:

| Surface | Relative input defaults | Disposition |
|---|---|---|
| `status`, `list`, `checkpoint`, `payer` with local/Koios | `deploy/preprod/m1-manifest.json`, `deploy/preprod/board-manifest.json` | In scope through the shared manifest loader; all receive named errors. |
| `manifest verify` | M1 manifest and source repo `.` | Checkout-oriented verification command; report separately, no behavior change in this micro-slice. |
| `register` | M1 and board manifests | Same installed-release usability class, but transaction flow is outside this read-only status slice; report separately. |
| `advance`, `close` | M1 manifest | Same installed-release usability class; report separately. |
| `board list/post/update/retire` | board manifest | Same installed-release usability class; report separately. |
| `deploy`, `board deploy` | source repo `.` input and relative output path | Checkout-oriented provenance input; report separately, with no behavior change in this micro-slice. The output default itself has no missing-checkout crash dependency. |

The PR body must retain this inventory so the audit is visible even though the micro-slice changes only the shared read-query loader.

## Observable acceptance

From a temporary directory containing no `deploy/`, a packaged command with an absolute valid M1 manifest and no board-manifest option exits nonzero, prints a single concise `ckeri:` diagnostic naming `--board-manifest` and `deploy/preprod/board-manifest.json`, and does not emit a raw unlabelled exception. A command supplied both valid manifests still renders `watchable n/m`. The focused packaged smoke and full repository gate both pass.
