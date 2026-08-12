# Modules model — #253 board OOBI binding

Artifact ceiling: 6,000 bytes and 145 lines.

This model owns changed responsibilities and dependency direction. Data shapes
are in `data-model.md`; callable signatures are in `functions-model.md`.

## Components and modules

### MOD-253-BOARD-TYPES — shared board authorization protocol

- Owns the frozen legacy shape, authorized target shape, stable authorization
  domain/preimage, nonce, and normal lifecycle redeemers.
- Preserves exact constructor/field shape as protocol data. It owns no datum
  version, version-only constructor, sequence, or origin field.
- Is shared by validator vectors and off-chain codecs; consumers do not define
  private approximations.

### MOD-253-BOARD-VALIDATOR — target mint/spend validator

- Reconstructs **DAT-253-AUTHORIZATION** from its applied policy identity and
  **DAT-253-AUTHORIZED-DATUM**, then verifies both witness signatures.
- Owns consumed nonce, marker/value, recorded-owner, unique-successor, and
  lifecycle validation.
- Accepts only the authorized target shape. It depends on
  **MOD-253-BOARD-TYPES** and #254's migration context, not Haskell codecs.

### MOD-253-MIGRATION — #254 applied-hash vehicle

- Owns the atomic transaction from one consumed predecessor policy/out-ref to
  one target successor under its applied predecessor-policy parameter.
- Supplies the revised `DEP-253-254` contract in `plan.md`.
- Owns no endpoint semantics and cannot waive target witness authorization.

### MOD-253-BOARD-CODEC — producer/reader protocol codec

- Owns canonical authorization bytes, structural datum decoding under a matched
  release policy, and independent endpoint/authorization verification.
- Retains fail-closed whole-catalog semantics and yields
  **DAT-253-BOARD-ENTRY** only after all applicable checks pass.
- Depends on protocol data and applied-policy registry entries, never CLI
  settings or a concrete chain provider.

### MOD-253-BOARD-TRANSACTION — board transaction planning

- Owns Post nonce selection/consumption, Update predecessor binding, authorized
  datum construction, owner requirements, and migration plan inputs.
- Receives an externally produced witness authorization; it never accesses the
  witness private key.
- Depends on **MOD-253-BOARD-CODEC** and resolved inputs, with no query during
  transaction construction.

### MOD-253-CONSUMERS — catalog/query/watchability consumers

- Consume authenticated **DAT-253-BOARD-ENTRY** values without reimplementing
  datum or signature verification.
- Preserve witness/AID/URL, owner, out-ref, deposit, duplicate, and watchability
  behavior. No version or sequence is added to the public view.
- Resolve releases by applied policy hash through #254's registry and derive
  migration lineage from atomic transaction history.

### MOD-253-PROOF — lasting security and cutover evidence

- Owns retained-field mutation, custody substitution, replay, dual-signature,
  lifecycle, and migration-continuity properties plus frozen vectors.
- Keeps the board in the compiled target and records settled transaction edges
  for all three preprod records.

## Dependency edges

- **EDGE-253-01:** validator and codec → shared board protocol.
- **EDGE-253-02:** migration → shared protocol; target validator → migration
  context only at the dedicated migration arm.
- **EDGE-253-03:** transaction planning → codec and provider-neutral resolved
  chain values.
- **EDGE-253-04:** consumers → authenticated entry and release registry;
  consumers do not depend on raw datum layout.
- **EDGE-253-05:** proof → real validator, codec, transaction, and migration
  boundaries; production never depends on proof modules.

## Promotion decisions

- **PROMOTE-253-01:** the stable domain, authorization preimage, nonce, and
  exact legacy/authorized shapes live in the shared protocol owner because
  Aiken and Haskell must agree byte-for-byte.
- **PROMOTE-253-02:** applied release identities live only in #254's registry;
  they are lookup input, not copied into datum or promoted entry fields.
- **PROMOTE-253-03:** raw nonce and authorization signature remain codec-level
  verification data unless #171 demonstrates a public consumer.
- **PROMOTE-253-04:** witness-key custody remains outside transaction planning;
  only payload bytes and a signature cross in.

## Forbidden restoration

No S253-2 implementation may restore sequence, datum version/tag, stored
origin, or a promoted version field without a newly demonstrated attack or
named consumer read and a re-authorized mandate.
