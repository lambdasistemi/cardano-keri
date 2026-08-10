# Modules model — #262 ChainQuery-only write acquisition

Artifact ceiling: 5,000 bytes and 130 lines.

## Changed responsibilities

### MOD-262-QUERY — provider-neutral algebra

- Extends the #257 operation vocabulary with exact-output and board-with-output
  reads.
- Owns the exact output locator and reuses **DAT-257-ASSET-OUTPUT** as the one
  neutral spendable-output representation.
- Keeps the interpreter abstract and exhaustively dispatches every operation.
- Has no store, HTTP, node runtime, URL, token, or provider-selection input.

### MOD-262-LOCAL — indexer interpreter

- Privately owns raw store transactions and decoding for all build-phase
  operations.
- Produces `ChainAssetUtxo` for exact rows and board/output pairs from one open
  store transaction.
- Exports the local algebra runner/interpreter boundary, not raw
  build-acquisition functions to write composition.

### MOD-262-KOIOS — provider interpreter

- Accounts explicitly for both new operations and returns the same neutral
  results or a named unsupported-operation failure.
- Never participates in write composition and never falls back to local.

### MOD-262-COMPOSITION — write orchestration

- Builds one `ChainQuery` program per transaction build phase and consumes only
  resolved neutral values plus pure ledger reconstruction.
- Cannot import or call raw local-store `Transaction` acquisition functions.
- Keeps post-submit settlement polling as a separate temporal capability.

### MOD-262-PROOF — lasting route/disposition proof

- Extends the #240 and #257 focused checks with an executing source/component
  boundary that detects any direct build-acquisition reintroduction.
- Changes the #240 deferral detector into a closure detector in the same
  behavior commit and retains both negative controls.

## Dependency direction

- **EDGE-262-01:** write composition → provider-neutral query and pure ledger
  reconstruction.
- **EDGE-262-02:** local indexer → provider-neutral query.
- **EDGE-262-03:** Koios interpreter → provider-neutral query.
- **EDGE-262-04:** no provider-neutral query or write-builder dependency on a
  concrete interpreter.
- **EDGE-262-05:** no write-composition dependency on raw local acquisition
  exports; concrete interpreter construction remains at the CLI boundary.

## Promotion decision

- **PROMOTE-262-01:** reuse `ChainAssetUtxo`; do not promote `TxOut ConwayEra`
  into the provider interchange contract and do not introduce another output
  DTO.
- **PROMOTE-262-02:** add a validated exact-output locator to the neutral query
  component because both interpreters and programs must agree on it.
- **PROMOTE-262-03:** retain ledger reconstruction in the existing neutral
  conversion module and authenticated summaries in their current owner.
