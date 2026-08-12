# Tasks — #253 board OOBI binding

Artifact ceiling: 6,000 bytes and 145 lines.

Boxes are checked only after exact behavior and permanent properties are
independently accepted. S253-1 checkmarks record its accepted historical slice;
S253-2 explicitly amends its superseded sequence/version shape.

## S253-1 — canonical authorization and codecs (accepted foundation)

- [x] **T253-S1-01** Add canonical authorization and legacy/target codec
  groundwork with frozen cross-language vectors.
- [x] **T253-S1-02** Implement authorization reconstruction, canonical bytes,
  and verification in shared on-chain/off-chain surfaces.
- [x] **T253-S1-03** Preserve endpoint verification separately and require both
  signatures before target promotion.
- [x] **T253-S1-04** Add producer payload/signature handling without witness
  private key material.
- [x] **T253-S1-05** Demonstrate the signed-field mutant class can fail and
  record immutable audit evidence.

## S253-2 — slim authorization, validator, and transaction paths

- [ ] **T253-S2-01** Delete sequence from datum, authorization, codecs, producer,
  reader, vectors, and tests; delete the version-only constructor/API and use
  exact four-field legacy versus six-field authorized structural decoding under
  the matched applied policy.
- [ ] **T253-S2-02** Freeze the stable non-versioned domain and exact six-field
  authorization bytes in Aiken/Haskell vectors; prove every retained field is
  observed and both signatures remain independent.
- [ ] **T253-S2-03** Enforce target Post with exact policy/marker binding, both
  signatures, one consumed named nonce, and rejection when the nonce input
  carries a marker under the target or applied predecessor policy.
- [ ] **T253-S2-04** Enforce Update with recorded-owner authority, exact
  predecessor nonce, one confined successor, preserved marker/deposit, and
  fresh successor authorization.
- [ ] **T253-S2-05** Preserve Retire's recorded-owner, burn, and exact-refund
  guarantees for the authorized target shape.
- [ ] **T253-S2-06** Update Post/Update planners to consume and cross-check the
  signed nonce rather than selecting a different input afterward.
- [ ] **T253-S2-07** Permanently kill custody-substitution, wrong/missing/reused
  nonce replay/resurrection, endpoint-only, wrong-shape, and lifecycle mutant
  classes for owner, nonce, and witness-auth invariants.
- [ ] **T253-S2-08** Keep target board properties in M8's compiled target and
  preserve reproducible policy/manifest checks.

## S253-3 — migration, consumer seam, and preprod cutover

- [ ] **T253-S3-01** Integrate the revised `DEP-253-254` applied-hash contract.
- [ ] **T253-S3-02** Implement one atomic legacy-to-target transition with
  source-out-ref nonce, fresh authorization, and preserved record, owner, and
  deposit under both policy arms.
- [ ] **T253-S3-03** Make catalog resolution registry-backed and fail closed for
  unknown hashes or incomplete transaction edges without promoting version or
  origin.
- [ ] **T253-S3-04** Preserve the existing public board-entry/query fields and
  watchability contract without adding version or sequence.
- [ ] **T253-S3-05** Kill crossed-field, dropped-value, wrong-policy,
  split-transaction, replay, and one-to-many migration mutants.
- [ ] **T253-S3-06** Migrate all three live preprod legacy records and record
  settled transaction-derived predecessor/successor facts.
- [ ] **T253-S3-07** Verify the final current catalog contains three
  authenticated successors and no spent predecessor is current.

## Release acceptance

- [ ] **T253-A-01** Confirm #171 agrees on registry-backed locators,
  applied-policy decoder selection, verification ownership, and atomic cutover
  semantics with no public version/sequence additions.
- [ ] **T253-A-02** Require every BLOCKING invariant row to terminate as
  `KILLED` or `BLOCKED`; budget exhaustion cannot close an OPEN row.
- [ ] **T253-A-03** Verify exact accepted tree, focused properties, repository
  gate, compiled target, and clean index with hash-bound receipts.
- [ ] **T253-A-04** Publish target applied hash/address/schema and migration
  facts only after three-record cutover and consumer checks complete.
