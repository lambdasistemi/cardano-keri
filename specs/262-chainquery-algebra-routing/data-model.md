# Data model — #262 ChainQuery-only write acquisition

Artifact ceiling: 5,000 bytes and 130 lines.

## New data

### DAT-262-OUTPUT-LOCATOR — `OutputLocator`

Fields:

- `outputLocatorTxId`: canonical lowercase 32-byte transaction-id hex;
- `outputLocatorIndex`: ledger-valid non-negative output index.

The value is provider-neutral and validated eagerly before interpretation.

## Reused data

### DAT-262-SPENDABLE-OUTPUT — existing `ChainAssetUtxo`

The sole cross-provider spendable-output representation. It carries output
identity, address, lovelace, every native asset, inline datum JSON, and optional
reference-script identity/type/bytes. Pure fail-closed reconstruction produces
the Conway `TxIn` and `TxOut` used by a builder.

No second output DTO or embedded provider response is introduced.

### DAT-262-BOARD-OUTPUT — `(BoardEntry, ChainAssetUtxo)`

One authenticated board summary paired with the complete neutral output from
the exact same transaction id/index. The operation returns an all-or-nothing
list: every catalog entry has exactly one pair and no returned pair disagrees
with its `BoardEntry` identity.

### DAT-262-CHECKPOINT-OUTPUT

The existing `ActiveCheckpoint` remains a deliberate authenticated summary.
Programs derive **DAT-262-OUTPUT-LOCATOR** from it and resolve the spendable
row separately inside the same monadic `ChainQuery` program. This preserves
summary ownership while ensuring both values share one local snapshot.

## State invariants

- **DATA-INV-262-01:** an invalid exact-output locator creates no operation and
  causes no interpreter effect.
- **DATA-INV-262-02:** exact-output success identifies one and only one live
  row and preserves all reconstruction data used by the builder.
- **DATA-INV-262-03:** every board entry/output pair has equal transaction id
  and index and belongs to one all-or-nothing catalog observation.
- **DATA-INV-262-04:** local program value and watermark are produced inside
  one store transaction, including programs whose later locator is derived
  from an earlier operation result.
- **DATA-INV-262-05:** provider source and consistency remain explicit; no
  operation falls through to another interpreter.
