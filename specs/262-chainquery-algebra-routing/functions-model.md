# Functions model — #262 ChainQuery-only write acquisition

Artifact ceiling: 5,000 bytes and 130 lines.

Only changed public signatures are modeled. Module ownership is in
`modules-model.md`; data and invariants are in `data-model.md`.

## Program construction

- **FUN-262-OUTPUT:** `outputAt outputLocator -> ChainQuery ChainAssetUtxo`
- **FUN-262-BOARD-OUTPUTS:** `boardCatalogWithOutputs boardLocator -> ChainQuery [(BoardEntry, ChainAssetUtxo)]`

Constraints:

- smart constructors validate concrete locators eagerly;
- arguments and results carry no provider setting or effect handle;
- exact output absence or duplication is an operation error, not `Maybe`;
- board/output results are all-or-nothing and identity-consistent.

## Interpreter assembly and dispatch

- **FUN-262-INTERPRETER:** `chainQueryInterpreter current live references board boardOutputs payer outputAt watermark source consistency -> ChainQueryInterpreter effect`
- **FUN-262-LOCAL-OUTPUT:** `localOutputAt outputLocator -> StoreTransaction (Either ChainQueryError ChainAssetUtxo)`
- **FUN-262-LOCAL-BOARD-OUTPUTS:** `localBoardCatalogWithOutputs boardLocator -> StoreTransaction (Either ChainQueryError [(BoardEntry, ChainAssetUtxo)])`

Constraints:

- the abstract factory is the only interpreter constructor;
- dispatch is exhaustive and selects no provider;
- local operations remain private implementation details;
- every test and concrete interpreter supplies explicit handlers.

## Write programs

- **FUN-262-BOARD-WRITE-PROGRAM:** `boardWriteProgram endpointBoardInfo fundingAddress -> ChainQuery resolvedBoardWriteInputs`
- **FUN-262-BOARD-CATALOG-PROGRAM:** `boardCatalogProgram endpointBoardInfo fundingAddress -> ChainQuery resolvedBoardCatalogInputs`
- **FUN-262-PUBLISH-PROGRAM:** `publishProgram fundingAddress -> ChainQuery resolvedFundingInputs`
- **FUN-262-CHECKPOINT-PROGRAM:** `activeCheckpointProgram checkpointLocator aid -> ChainQuery ActiveCheckpoint`
- **FUN-262-SUBMIT-PROGRAM:** `activeCheckpointSubmitProgram checkpointLocator manifest aid fundingAddress -> ChainQuery resolvedSubmitInputs`

Constraints:

- each caller invokes the local runner once per build phase;
- later exact-output locators may be derived from earlier program results;
- ledger conversion is pure after interpretation;
- builders receive resolved values and perform no chain query.

Signature spellings may use existing domain result names; the argument/result
relationships and effects above are fixed.
