# Tasks — #253 board OOBI binding

Artifact ceiling: 6,000 bytes and 145 lines.

Boxes are checked only after the exact behavior and its permanent properties
are independently accepted. Verification evidence records named invariant rows
and immutable artifact hashes.

## S253-1 — canonical authorization and codecs

- [ ] **T253-S1-01** Add **DAT-253-AUTHORIZATION** and the versioned V1/V2 datum
  protocol with frozen constructor, field-order, and domain vectors.
- [ ] **T253-S1-02** Implement **FUN-253-AUTH-RECONSTRUCT** through
  **FUN-253-AUTH-VERIFY** in the shared on-chain/off-chain contract surfaces.
- [ ] **T253-S1-03** Preserve endpoint-signature verification separately and
  require both signatures before promoting a V2 **DAT-253-BOARD-ENTRY**.
- [ ] **T253-S1-04** Add producer payload/signature handling without importing
  or storing witness private key material.
- [ ] **T253-S1-05** Demonstrate the **INV-253-SIGNED-FIELDS** mutant class can
  fail for every ordered field and record its evidence in the campaign ledger.

## S253-2 — V2 validator and transaction paths

- [ ] **T253-S2-01** Enforce V2 Post sequence zero, consumed nonce, exact
  marker/policy binding, and both witness signatures.
- [ ] **T253-S2-02** Enforce Update old-owner authority, exact sequence advance,
  predecessor nonce, one successor, and fresh successor authorization.
- [ ] **T253-S2-03** Preserve Retire's owner, burn, and exact-refund guarantees
  for V2 state.
- [ ] **T253-S2-04** Update Post/Update plans to consume and cross-check the
  signed nonce/sequence rather than selecting different inputs afterward.
- [ ] **T253-S2-05** Kill the owner-substitution, stale-resurrection,
  nonce-replay, and endpoint-only authorization mutant classes for
  **INV-253-OWNER**, **INV-253-SEQUENCE**, **INV-253-NONCE**, and
  **INV-253-WITNESS-AUTH**.
- [ ] **T253-S2-06** Keep the V2 endpoint-board properties in the M8
  compiled-UPLC target and preserve reproducible policy/manifest checks.

## S253-3 — migration, consumer seam, and preprod cutover

- [ ] **T253-S3-01** Integrate the #254 action/context satisfying
  **DEP-253-254-01** through **DEP-253-254-07**.
- [ ] **T253-S3-02** Implement one-to-one V1-to-V2 continuity with V2 sequence
  zero, legacy out-ref nonce, fresh witness authorization, and preserved record,
  owner, and deposit.
- [ ] **T253-S3-03** Make board locators/readers version-aware and retain
  fail-closed whole-catalog authentication across the transition.
- [ ] **T253-S3-04** Add validator version and sequence to the promoted entry and
  query contract without removing existing fields or changing watchability.
- [ ] **T253-S3-05** Kill the crossed-field, dropped-value, replay, and
  one-to-many migration mutant classes for **INV-253-MIGRATION**.
- [ ] **T253-S3-06** Migrate the three live preprod V1 records through the
  supported version transition and record settled predecessor/successor facts.
- [ ] **T253-S3-07** Verify the final current catalog contains the three
  authenticated V2 successors and no spent V1 predecessor is reported current.

## Release acceptance

- [ ] **T253-A-01** Confirm the #171 consumer contract agrees on version-aware
  locators, additive query fields, verification ownership, and cutover current
  semantics.
- [ ] **T253-A-02** Require every BLOCKING invariant row to terminate as
  `KILLED` or `BLOCKED`; neither tail-stop nor budget exhaustion may close an
  `OPEN` row.
- [ ] **T253-A-03** Verify the exact accepted tree, focused board properties,
  complete repository gate, compiled-UPLC target, and clean index with
  hash-bound receipts.
- [ ] **T253-A-04** Publish the V2 policy/address/schema and migration facts only
  after the three-record cutover and consumer checks are complete.
