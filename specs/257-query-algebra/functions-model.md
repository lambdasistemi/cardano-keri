# Functions model — #257 one chain-query algebra

Artifact ceiling: 6,000 bytes and 150 lines.

Only new or changed public signatures are modeled here. Types are defined in
`data-model.md`; component ownership is defined in `modules-model.md`.

## Program construction

- **FUN-257-CURRENT:** `currentCheckpoint checkpointLocator aid -> ChainQuery (Maybe ActiveCheckpoint)`
- **FUN-257-LIVE:** `liveCheckpoints checkpointLocator -> ChainQuery [ActiveCheckpoint]`
- **FUN-257-REFERENCES:** `referenceScripts scriptHashes -> ChainQuery [ChainReference]`
- **FUN-257-BOARD:** `boardCatalog boardLocator -> ChainQuery [BoardEntry]`
- **FUN-257-PAYER:** `payerUtxos payerAddresses -> ChainQuery [ChainAssetUtxo]`
- **FUN-257-WATERMARK:** `storeWatermark -> ChainQuery ColdOr ChainWatermark`

Constraints:

- arguments are provider-neutral validated values;
- each signature's Haddock names its current consumer;
- no signature accepts an interpreter, URL, token, store handle, `IO` callback,
  or settlement observer.

## Interpreter values

- **FUN-257-RUN:** `runChainQuery interpreter program -> effect (Either ChainQueryError (QuerySnapshot result))`
- **FUN-257-LOCAL-CONSTRUCT:** `localQueryInterpreter localQueryHandle -> ChainQueryInterpreter IO`
- **FUN-257-KOIOS-CONSTRUCT:** `koiosQueryInterpreter koiosConfig -> ChainQueryInterpreter IO`

Constraints:

- `runChainQuery` selects no provider; the supplied interpreter is the only
  execution authority;
- the local constructor accepts the existing transaction runner and store
  identity required by `Indexer.Query.Tx`;
- the Koios constructor is the only query-algebra boundary accepting Koios URL
  or token settings;
- unsupported operations return **DAT-257-ERROR**, never fallback.

## Local translation

- **FUN-257-LOCAL-TRANSLATE:** `interpretLocalProgram localQueryHandle program -> StoreTransaction (Either ChainQueryError result)`
- **FUN-257-WATERMARK-TX:** `watermarkTx -> StoreTransaction ColdOr ChainWatermark`

Constraints:

- the public local runner invokes the existing `RunTransaction` exactly once
  for the whole translated program;
- every local smart operation composes inside that transaction;
- `watermarkTx` returns slot and matching stored block hash from one entry.

## Registration proof verb

- **FUN-257-REGISTRATION-PROGRAM:** `registrationSnapshotProgram registrationQueryRequest -> ChainQuery RegistrationSnapshot`
- **FUN-257-REGISTER-PREFLIGHT:** `registerPreflight registrationSnapshot inceptionExport registrationPolicy -> Either String ()`
- **FUN-257-PREMINT:** `premintOne registerConfig registrationPlan registrationSnapshot observerRegistrationRequired -> IO (Either RegistrationError TxId)`
- **FUN-257-REGISTER:** `registerOne registerConfig registrationPlan registrationSnapshot proofInput -> IO (Either RegistrationError TxId)`

Constraints:

- `registrationSnapshotProgram` includes the watermark and every current-state
  read needed for its named phase;
- `RegisterConfig` retains transaction runtime and fixed build policy but has no
  concrete provider, query callback, URL, or token field;
- `premintOne` and `registerOne` receive resolved snapshot inputs and perform no
  query while building;
- a state change between phases requires a newly interpreted snapshot program.

## Settlement

- **FUN-257-OBSERVE:** `observeSettlement settlementObserver settlementTarget timeoutPolicy -> effect (Either SettlementError SettlementObservation)`

Constraints:

- this signature is not a `ChainQuery` operation;
- polling may be sequential and temporal and makes no snapshot-consistency
  claim;
- registration invokes it only after submission and does not use it to fill a
  builder snapshot.

## Compatibility

Existing provider-specific query names may remain as internal adapter helpers
inside **MOD-257-KOIOS**, but no builder-facing signature exposes them. Public
compatibility re-exports must not recreate an upstream concrete-provider
dependency.
