# Modules model — #253 board OOBI binding

Artifact ceiling: 6,000 bytes and 145 lines.

This model owns changed responsibilities and dependency direction. Data shapes
are in `data-model.md`; callable signatures are in `functions-model.md`.

## Components and modules

### MOD-253-BOARD-TYPES — shared versioned board protocol

- Owns the legacy V1 decode shape, current V2 datum, authorization preimage,
  domain constant, and normal lifecycle redeemers.
- Preserves constructor/field identity as protocol data; no consumer defines a
  private approximation of either version.
- Is the nearest stable owner shared by validator vectors and off-chain codecs.

### MOD-253-BOARD-VALIDATOR — V2 mint/spend validator

- Reconstructs **DAT-253-AUTHORIZATION** from trusted policy/transaction
  context and **DAT-253-DATUM-V2**, then verifies both witness signatures.
- Owns genesis sequence, successor sequence, consumed nonce, marker/value,
  owner, and lifecycle validation.
- Accepts only V2 current outputs. It depends on **MOD-253-BOARD-TYPES** and the
  migration context exposed by **MOD-253-MIGRATION**, not on Haskell codecs.

### MOD-253-MIGRATION — #254 board version vehicle

- Owns the version transition action and the on-chain link from one consumed
  V1 record to one V2 successor.
- Supplies the exact source version/policy/out-ref context required by
  **DEP-253-254-01** through **DEP-253-254-07**.
- Owns no endpoint semantics and cannot waive V2 witness authorization.

### MOD-253-BOARD-CODEC — producer/reader protocol codec

- Owns canonical V2 authorization bytes, version-aware datum decoding, and
  independent endpoint/authorization verification.
- Retains fail-closed whole-catalog semantics and yields the promoted
  **DAT-253-BOARD-ENTRY** only after all checks pass.
- Depends on stable protocol/domain data, never on CLI settings or a concrete
  chain provider.

### MOD-253-BOARD-TRANSACTION — board transaction planning

- Owns Post nonce selection/consumption, Update predecessor binding, V2 datum
  construction, owner requirements, and migration plan inputs.
- Receives an externally produced witness authorization; it does not own or
  access the witness's private KERI key.
- Depends on **MOD-253-BOARD-CODEC** and resolved chain inputs, with no query
  during transaction construction.

### MOD-253-CONSUMERS — catalog/query/watchability consumers

- Consume authenticated **DAT-253-BOARD-ENTRY** values without reimplementing
  datum or signature verification.
- Preserve existing witness/AID/URL, owner, out-ref, deposit, duplicate, and
  watchability behavior while carrying validator version and sequence.
- Query JSON adds version/sequence without removing or renaming existing fields.

### MOD-253-PROOF — lasting security and cutover evidence

- Owns focused field-mutation, substitution, replay, authorization, and
  migration-continuity properties plus frozen cross-language vectors.
- Keeps the endpoint board in the compiled-UPLC target and records settled
  V1/V2 predecessor/successor facts for the three-record preprod transition.

## Dependency edges

- **EDGE-253-01:** validator and codec → shared board protocol.
- **EDGE-253-02:** migration → shared protocol; V2 validator → migration context.
- **EDGE-253-03:** transaction planning → codec and provider-neutral resolved
  chain values.
- **EDGE-253-04:** catalog/query/watchability → authenticated board entry;
  consumers do not depend on raw Plutus datum layout.
- **EDGE-253-05:** proof coverage → real validator, codec, transaction, and
  migration boundaries; production modules never depend on proof modules.

## Promotion decisions

- **PROMOTE-253-01:** V1/V2 wire tags and V2 authorization domain/preimage move
  to the shared protocol owner because Aiken and Haskell must agree exactly.
- **PROMOTE-253-02:** board validator version and sequence join the promoted
  board-entry view because query and write consumers need them.
- **PROMOTE-253-03:** raw nonce and authorization signature remain codec-level
  verification data unless the #171 consumer contract identifies a public use.
- **PROMOTE-253-04:** witness key custody and signature production remain
  outside transaction planning; only payload bytes and a signature cross in.
