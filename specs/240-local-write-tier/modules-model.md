# Modules model — #240 local-only write tier

Artifact ceiling: 6,000 bytes and 150 lines.

This model owns changed responsibilities and dependency direction. Data shapes
are in `data-model.md`; signatures are in `functions-model.md`.

## MOD-240-WRITE-COMPOSITION — provider-free write CLI component

- **Status:** new component; receives the existing write command module.
- **Responsibility:** write settings, local store lifetime, #257 program
  composition, resolved builder inputs, node-runtime orchestration, and local
  settlement selection.
- **Owns abstractions:** **DAT-240-LOCAL-SETTINGS** and
  **DAT-240-WRITE-RUNTIME**.
- **Upstream dependencies:** provider-neutral `deployment` and `chain-query`,
  plus local `indexer` and ledger/node runtime libraries.
- **Downstream consumers:** **MOD-240-CLI** and the installed `ckeri` command.
- **Forbidden dependencies:** `chain-query-koios`, provider HTTP packages,
  provider configuration/token types, provider callbacks, and read-backend
  selection.

## MOD-240-CLI — top-level and read-provider composition

- **Status:** changed existing `cli` component.
- **Responsibility:** command dispatch plus read-only local/endpoint/Koios
  backend selection.
- **Owns abstractions:** no write data or function surface.
- **Upstream dependencies:** **MOD-240-WRITE-COMPOSITION**, read backend modules,
  and concrete provider components.
- **Downstream consumers:** installed `ckeri` executable.
- **Forbidden dependencies:** no edge from **MOD-240-WRITE-COMPOSITION** back to
  this component.

## MOD-240-LOCAL — local chain-query interpreter and temporal observers

- **Status:** changed existing indexer component.
- **Responsibility:** translate #257 operations to one store transaction,
  derive reference outputs from follower-held live rows, and expose separate
  follower-backed settlement probes.
- **Owns abstractions:** **DAT-240-LOCAL-SCOPE**,
  **DAT-240-REFERENCE-RESOLUTION**, and **DAT-240-SETTLEMENT-PROBES**.
- **Upstream dependencies:** `chain-query`, indexer columns/transactions, and
  provider-neutral ledger decoders.
- **Downstream consumers:** **MOD-240-WRITE-COMPOSITION** and existing local
  read composition.
- **Forbidden dependencies:** provider clients/settings, HTTP, node lookup as a
  substitute for stored rows, or a fallback interpreter.

## MOD-240-QUERY — existing provider-neutral algebra

- **Status:** stable owner with narrowly changed settlement vocabulary only if
  a generic transaction-id observer must be public.
- **Responsibility:** retain exactly #257's snapshot operations and keep
  settlement temporally separate.
- **Owns abstractions:** existing `ChainQuery`, `QuerySnapshot`, and settlement
  types; any **DAT-240-TRANSACTION-SETTLEMENT** promotion justified by both
  close and board consumers.
- **Upstream dependencies:** stable domain/ledger types only.
- **Downstream consumers:** **MOD-240-LOCAL**, **MOD-240-WRITE-COMPOSITION**, and
  the legacy provider interpreter.
- **Forbidden dependencies:** local store handles, URLs/tokens, HTTP, node
  runtime, or write settings.

## MOD-240-DEPLOYMENT — provider-neutral builders

- **Status:** existing owner; signatures change only where an ambient query
  callback is replaced by a resolved value or temporal capability.
- **Responsibility:** transaction plans/builders and provider-neutral timeout
  loops.
- **Owns abstractions:** existing publish, registration, advance, close, and
  board plans/configuration.
- **Upstream dependencies:** **MOD-240-QUERY** resolved types only.
- **Downstream consumers:** **MOD-240-WRITE-COMPOSITION**.
- **Forbidden dependencies:** every concrete interpreter, store handle,
  provider setting, and query action during a build.

## MOD-240-FOCUSED-GATE — lasting local-write-path proof

- **Status:** new flake-owned check and root recipe.
- **Responsibility:** execute non-zero verb coverage, component-boundary
  compilation, local runner/snapshot checks, parity goldens, settlement
  behavior, and provider reachability census.
- **Upstream dependencies:** candidate source and focused test executables.
- **Downstream consumers:** `ci-offchain`, the ignored ticket gate, and CI.
- **Forbidden dependencies:** mutable lock evaluation, network provider access,
  hand-authored success receipts, and skipped/zero-test success.

## Dependency edges

- **EDGE-240-01:** write-composition → deployment, chain-query, indexer.
- **EDGE-240-02:** cli → write-composition and concrete read providers.
- **EDGE-240-03:** indexer → chain-query; never the reverse.
- **EDGE-240-04:** no write-composition/deployment → provider component edge.
- **EDGE-240-05:** focused gate → all blocking invariant instruments.

## Promotions

- **PROMOTE-240-01:** transaction-id settlement vocabulary may move from CLI
  local helpers to `chain-query` only if close and board share the same public
  temporal contract; it remains absent from the snapshot functor.
- No provider response type, store handle, or write setting is promoted into
  the provider-neutral algebra.
