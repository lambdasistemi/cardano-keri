# Functions model — #253 board OOBI binding

Artifact ceiling: 6,000 bytes and 155 lines.

Only new or changed public signatures are modeled here. Types and wire shapes
are in `data-model.md`; ownership is in `modules-model.md`.

## Canonical authorization

- **FUN-253-AUTH-RECONSTRUCT:** `reconstructBoardAuthorization policyId datumV2 -> BoardAuthorizationV2`
- **FUN-253-AUTH-BYTES:** `boardAuthorizationBytes authorization -> ByteArray`
- **FUN-253-AUTH-VERIFY:** `verifyBoardAuthorization policyId datumV2 -> Bool`

Constraints:

- reconstruction accepts the trusted policy id and typed V2 datum, never a
  caller-supplied preimage;
- bytes are canonical Plutus Data CBOR for **DAT-253-AUTHORIZATION**;
- verification uses `datumV2.witness_key` and
  `datumV2.authorization_signature` and does not replace endpoint-signature
  verification.

## Validator predicates

- **FUN-253-DATUM-AUTHENTIC:** `datumIsAuthentic expectedKey policyId datumV2 -> Bool`
- **FUN-253-POST:** `validatePost policyId transaction -> Bool`
- **FUN-253-UPDATE:** `validateUpdate inputOutput policyId ownRef oldDatum transaction -> Bool`
- **FUN-253-MIGRATE:** `validateBoardMigration migrationContext transaction -> Bool`

Constraints:

- `datumIsAuthentic` validates both signatures, all field widths, non-negative
  sequence, expected key, and the exact authorization policy;
- Post accepts only sequence zero and requires the datum nonce among consumed
  inputs with no endpoint-board marker under any supported version;
- Update requires the old owner, one successor, exact marker/deposit, sequence
  `old + 1`, nonce equal to `ownRef`, and fresh successor authenticity;
- migration enforces **DAT-253-MIGRATION-LINK** and does not delegate its
  continuity checks to ordinary Post.

Retire's signature is unchanged; it continues to consume the typed current
datum and enforce old-owner, burn, and refund rules.

## Producer and codec surface

- **FUN-253-DECODE-DATUM:** `decodeBoardDatum boardVersion policyId plutusData -> Either BoardDecodeError VersionedBoardDatum`
- **FUN-253-AUTH-PAYLOAD:** `mkBoardAuthorizationPayload policyId witnessKey endpointRecord ownerKeyHash sequence nonce -> BoardAuthorizationPayload`
- **FUN-253-ATTACH-AUTH:** `attachBoardAuthorization payload signature -> Either BoardAuthorizationError BoardDatumV2`
- **FUN-253-RESOLVE-CATALOG:** `resolveBoardCatalog boardLocators chainOutputs -> Either String [BoardEntry]`

Constraints:

- V1 decoding preserves the frozen four-field wire but never promotes it as
  authenticated V2;
- payload construction returns exact signable CBOR plus typed fields so an
  external witness signer can confirm what it signs;
- attaching rejects a signature that does not verify before a plan is built;
- catalog resolution chooses policy/version from the matched locator, verifies
  every applicable signature, and retains all-or-nothing error behavior.

## Transaction planning

- **FUN-253-POST-PLAN:** `mkBoardPostPlan manifest ownerAddress deposit nonceInput authorizedDatum -> Either String BoardPostPlan`
- **FUN-253-UPDATE-PLAN:** `mkBoardUpdatePlan manifest ownerAddress entry authorizedSuccessor -> Either String BoardUpdatePlan`
- **FUN-253-MIGRATION-PLAN:** `mkBoardMigrationPlan migrationManifest ownerAddress legacyEntry authorizedSuccessor -> Either String BoardMigrationPlan`

Constraints:

- Post includes and consumes the exact selected nonce input named by the signed
  datum; funding selection cannot silently replace it;
- Update derives sequence and nonce from the selected current `BoardEntry` and
  rejects a pre-signed successor that differs;
- migration accepts only V2 sequence zero with nonce equal to the selected V1
  out-ref and preserves every **DAT-253-MIGRATION-LINK** field;
- plans consume resolved values and signatures and never access witness private
  key material or query the chain while constructing a transaction.

## Consumer/query compatibility

- **FUN-253-BOARD-DATA:** `boardDataOf authenticatedBoardEntry -> BoardData`
- **FUN-253-BOARD-LIST:** `boardListEntryOf authenticatedBoardEntry -> BoardListEntry`

Constraints:

- both surfaces retain all existing fields and add validator version and
  sequence;
- no public response can be constructed directly from an unverified raw V2
  datum;
- watchability continues to consume authenticated entries and count distinct
  witness keys, not versions, lineages, or sequence values.
