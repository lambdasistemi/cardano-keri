# Data model — #257 one chain-query algebra

Artifact ceiling: 6,000 bytes and 160 lines.

This model owns new or promoted data, relationships, validation, and state
invariants. Module placement is in `modules-model.md`; callable signatures are
in `functions-model.md`.

## Algebra and execution data

### DAT-257-PROGRAM — `ChainQuery operationResult`

A provider-neutral free program over **DAT-257-OP**. Its type parameter is the
program result. It contains no provider configuration or effect handle.

### DAT-257-OP — `ChainQueryF next`

Exactly five snapshot operation families:

- current checkpoint/live checkpoint set, identified by
  **DAT-257-CHECKPOINT-LOCATOR**;
- deployed reference scripts, identified by reference script hashes;
- authenticated board catalog, identified by **DAT-257-BOARD-LOCATOR**;
- payer UTxOs, identified by a non-empty set of ledger addresses;
- store watermark.

Each family carries its typed continuation and nothing provider-specific.
Settlement is deliberately absent.

### DAT-257-RESULT — `QuerySnapshot value`

Fields:

- `snapshotValue`: the resolved program value;
- `snapshotWatermark`: **DAT-257-WATERMARK**;
- `snapshotSource`: **DAT-257-SOURCE**;
- `snapshotConsistency`: **DAT-257-CONSISTENCY**.

For local results, value and watermark share one store transaction. For Koios,
the watermark is the honest bound derivable from supporting responses and the
consistency field prevents an atomic interpretation.

### DAT-257-WATERMARK — `ChainWatermark`

Fields:

- `watermarkSlot`: ledger slot;
- `watermarkBlockHash`: the block hash recorded for that slot.

The cold-store case is explicit and distinct from a populated watermark.
Slot and hash must come from one rollback-column entry for local execution.

### DAT-257-SOURCE — `QuerySource`

Closed current variants: local store and Koios. A future Blockfrost variant can
be added with its interpreter without changing the operation families.

### DAT-257-CONSISTENCY — `SnapshotConsistency`

Closed variants:

- atomic local store transaction;
- legacy sequential provider observation.

The sequential variant is consumer-visible and cannot be rendered or pattern
matched as atomic.

## Query identities and promoted results

### DAT-257-CHECKPOINT-LOCATOR — `CheckpointLocator`

Fields identify the checkpoint policy, checkpoint asset, and checkpoint address
needed by both interpreters. The AID is supplied separately for a
single-current-checkpoint read. All identifiers are validated before a program
reaches an interpreter.

### DAT-257-BOARD-LOCATOR — `BoardLocator`

Fields identify the endpoint-board policy and marker address. The resulting
catalog remains authenticated and all-or-nothing.

### DAT-257-ASSET-OUTPUT — `ChainAssetUtxo`

Promoted shared chain-output view: transaction id, output index, address,
lovelace, datum, assets, and optional reference-script information needed by
existing consumers. Provider-only response fields do not enter this type.

### DAT-257-REFERENCE — `ChainReference`

Promoted resolved reference-script output: script hash and output reference,
with enough ledger output data for a transaction builder to validate and use
the reference.

### DAT-257-CHECKPOINT — `ActiveCheckpoint`

Promoted current checkpoint view already consumed by advance/status logic. Its
identity and decoded datum retain existing validation and uniqueness rules.

### DAT-257-BOARD — `BoardEntry`

Promoted authenticated endpoint-board record with its output reference. A
catalog containing one malformed or unauthenticated row is rejected wholly.

## Registration data

### DAT-257-REGISTRATION-SNAPSHOT — `RegistrationSnapshot`

Named resolved input for one registration phase. It contains only the current
checkpoint evidence, board catalog, required references, payer UTxOs, and the
query result metadata needed by that phase. It contains no interpreter,
provider settings, or settlement function.

A new snapshot is required after a submitted transaction changes spendable
state. A builder consumes one snapshot without querying during construction.

### DAT-257-SETTLEMENT — `SettlementObserver effect`

A separate temporal capability value with provider-specific construction. Its
observations and timeout errors are not **DAT-257-OP** values and carry no claim
that repeated polls form a snapshot.

## Errors and validation

### DAT-257-ERROR — `ChainQueryError`

Named variants cover unsupported operation, provider failure, decoding or
authentication failure, incoherent/missing watermark, ambiguous current state,
and invalid locator. Errors preserve source identity and never trigger fallback.

Validation invariants:

- **DATA-INV-257-01:** operation locators are canonical and non-empty before
  interpretation;
- **DATA-INV-257-02:** a populated local watermark always has both slot and
  block hash from one stored point;
- **DATA-INV-257-03:** a successful snapshot always states source and
  consistency;
- **DATA-INV-257-04:** registration snapshot values all belong to the same
  program result; no ambient query fills a missing field;
- **DATA-INV-257-05:** settlement values cannot inhabit the free operation
  functor.
