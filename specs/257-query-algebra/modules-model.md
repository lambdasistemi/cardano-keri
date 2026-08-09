# Modules model — #257 one chain-query algebra

Artifact ceiling: 6,000 bytes and 150 lines.

This model owns changed responsibilities and dependency direction. Data shapes
are in `data-model.md`; signatures are in `functions-model.md`.

## Components and modules

### MOD-257-QUERY — provider-neutral `chain-query` component

- Owns the minimal free query program, smart operations, query errors, provider
  provenance, consistency claims, locators, promoted result types, and
  slot/hash watermark.
- Has no HTTP, RocksDB, node runtime, executable settings, URL, or token
  responsibility.
- Is the nearest stable upstream owner of types currently trapped in the
  concrete `Deployment.ChainIndex` module but shared by builders and both
  interpreters.
- Exposes a stable `Cardano.KERI.ChainQuery` surface; internal type separation
  is allowed without enlarging the public capability.

### MOD-257-DEPLOYMENT — provider-neutral builder component

- Continues to own registration, advance, close, board-transaction, publication,
  manifest, and transaction-runtime planning/building behavior.
- Depends on **MOD-257-QUERY** for resolved domain values only.
- Does not own Koios HTTP calls, interpreter construction, local store access,
  or provider selection.
- Builder modules cannot name concrete interpreter modules because Cabal does
  not expose a dependency edge to them.

### MOD-257-KOIOS — concrete `chain-query-koios` component

- Owns the legacy Koios HTTP client, endpoint response decoding, configuration,
  operation translation, and explicit sequential/non-atomic consistency claim.
- Depends downstream on **MOD-257-QUERY** and may reuse provider-neutral decode
  functions from **MOD-257-DEPLOYMENT**.
- Retains `queryAssetHistory` only for the #177 read-backend behavior that still
  consumes it. Removes dead exported historical operations when no caller
  remains.
- Never calls a local or future interpreter as fallback.

### MOD-257-LOCAL — indexer interpreter

- Lives in the existing indexer component and owns translation from a whole
  query program to existing `Indexer.Query.Tx` primitives.
- Reads the corresponding rollback entry for the slot/hash watermark and calls
  the supplied store transaction runner once per program.
- Owns no provider selection and exposes no mid-program `IO` escape.

### MOD-257-COMPOSITION — CLI/runtime composition

- Lives in the downstream CLI component and owns interpreter selection,
  construction from settings, and registration's end-to-end orchestration.
- Owns legacy executable-facing modules that currently make deployment depend
  on Koios or live node details; their public module names may remain stable
  after component ownership changes.
- Constructs one snapshot interpreter and one separate settlement observer for
  a write journey.
- Does not add fallback or multi-provider composition.

### MOD-257-FOCUSED-GATE — lasting focused recipe

- The root justfile owns `query-algebra-check` as the named deterministic gate
  for the algebra, component boundary, both interpreters, and registration
  wiring.
- The ignored ticket `gate.sh` invokes it before full root `just ci`; `gate.sh`
  is not committed.

## Dependency edges

- **EDGE-257-01:** deployment → chain-query.
- **EDGE-257-02:** chain-query-koios → chain-query.
- **EDGE-257-03:** chain-query-koios → deployment only for neutral decoders,
  never for builder callbacks.
- **EDGE-257-04:** indexer → chain-query and deployment.
- **EDGE-257-05:** cli → chain-query, chain-query-koios, deployment, and indexer.
- **EDGE-257-06:** no edge from chain-query or deployment to either concrete
  interpreter.

## Promotion decisions

- **PROMOTE-257-01:** Chain asset/output, reference-output, current-checkpoint,
  board-entry, locator, watermark, provenance, and consistency types move to
  **MOD-257-QUERY** when both programs/builders and interpreters require them.
- **PROMOTE-257-02:** HTTP response-only and historical #177 types remain in
  **MOD-257-KOIOS**.
- **PROMOTE-257-03:** Store handles, columns, rollback records, and readiness
  remain in **MOD-257-LOCAL**.
- **PROMOTE-257-04:** Transaction plans, ledger build inputs, and settlement
  timeouts remain in **MOD-257-DEPLOYMENT**.

## Mechanical boundary checks

- Cabal must compile deployment without a concrete interpreter dependency.
- Deployment sources must not import the concrete Koios or local interpreter
  modules.
- Query sources must not contain provider configuration or store handles.
- Concrete interpreters may import the algebra; the reverse imports are
  forbidden.
