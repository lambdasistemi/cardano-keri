# Functions model — #253 board OOBI binding

Artifact ceiling: 6,000 bytes and 155 lines.

Only changed public signatures are modeled. Wire shapes are in
`data-model.md`; ownership is in `modules-model.md`.

## Canonical authorization

- **FUN-253-AUTH-RECONSTRUCT:** `reconstructBoardAuthorization policyId authorizedDatum -> BoardAuthorization`
- **FUN-253-AUTH-BYTES:** `boardAuthorizationBytes authorization -> ByteArray`
- **FUN-253-AUTH-VERIFY:** `verifyBoardAuthorization policyId authorizedDatum -> Bool`

Constraints:

- reconstruction accepts trusted applied policy id and typed authorized datum,
  never a caller preimage;
- bytes are canonical Plutus Data CBOR for **DAT-253-AUTHORIZATION**;
- verification uses datum witness/signature and remains independent from
  endpoint-signature verification;
- no sequence or version enters any signature or return type.

## Validator predicates

- **FUN-253-DATUM-AUTHENTIC:** `datumIsAuthentic expectedKey policyId authorizedDatum -> Bool`
- **FUN-253-POST:** `validatePost predecessorPolicy policyId transaction -> Bool`
- **FUN-253-UPDATE:** `validateUpdate inputOutput policyId ownRef oldDatum transaction -> Bool`
- **FUN-253-MIGRATE:** `validateBoardMigration migrationContext transaction -> Bool`

Constraints:

- `datumIsAuthentic` validates both signatures, field widths, expected witness,
  and exact target policy;
- Post requires datum nonce among consumed inputs and rejects a nonce input
  carrying a marker under the target or applied predecessor policy;
- Update requires recorded owner, one confined successor, exact marker/deposit,
  nonce equal to `ownRef`, and fresh successor authenticity;
- migration enforces **DAT-253-MIGRATION-LINK** and cannot delegate continuity
  to ordinary Post.

Retire continues to consume typed current datum and enforce recorded owner,
burn, and refund rules.

## Producer and codec surface

- **FUN-253-DECODE-LEGACY:** `decodeLegacyBoardDatum plutusData -> Either BoardDecodeError LegacyBoardDatum`
- **FUN-253-DECODE-AUTHORIZED:** `decodeAuthorizedBoardDatum policyId plutusData -> Either BoardDecodeError AuthorizedBoardDatum`
- **FUN-253-AUTH-PAYLOAD:** `mkBoardAuthorizationPayload policyId witnessKey endpointRecord ownerKeyHash nonce -> BoardAuthorizationPayload`
- **FUN-253-ATTACH-AUTH:** `attachBoardAuthorization payload signature -> Either BoardAuthorizationError AuthorizedBoardDatum`
- **FUN-253-RESOLVE-CATALOG:** `resolveBoardCatalog releaseRegistry chainTransactions -> Either String [BoardEntry]`

Constraints:

- the matched release selects one exact decoder; legacy four-field data is not
  promoted under target policy and authorized six-field data is not accepted
  under legacy policy;
- payload returns exact signable CBOR and typed fields for an external signer;
- attaching verifies the signature before a plan is built;
- catalog resolution verifies every applicable signature, derives migration
  edges atomically, and retains all-or-nothing errors for unknown/incomplete
  data.

## Transaction planning

- **FUN-253-POST-PLAN:** `mkAuthorizedBoardPostPlan target ownerAddress deposit nonceInput authorizedDatum -> Either String AuthorizedBoardPostPlan`
- **FUN-253-UPDATE-PLAN:** `mkAuthorizedBoardUpdatePlan target ownerAddress entry authorizedSuccessor -> Either String AuthorizedBoardUpdatePlan`
- **FUN-253-POST-RUN:** `runAuthorizedBoardPostTransaction config plan nonceInput fundingInputs -> IO (Either BoardError BoardResult)`
- **FUN-253-UPDATE-RUN:** `runAuthorizedBoardUpdateTransaction config plan fundingInputs boardInput -> IO (Either BoardError BoardResult)`
- **FUN-253-MIGRATION-PLAN:** `mkBoardMigrationPlan migrationManifest ownerAddress legacyEntry authorizedSuccessor -> Either String BoardMigrationPlan`

Constraints:

- Post includes and consumes the exact selected nonce named by signed datum;
  the supplied `nonceInput` out-ref must match the plan and funding selection
  cannot replace or omit it;
- Update derives nonce from selected current entry and rejects any pre-signed
  successor that differs;
- migration requires nonce equal to legacy out-ref and preserves every
  **DAT-253-MIGRATION-LINK** field;
- plans never access witness private material or query during construction.
- Existing `mkBoardPostPlan`, `mkBoardUpdatePlan`, and `runBoard*Transaction`
  legacy surfaces keep their signatures and four-field deployed-policy
  behavior. They are not aliases for the authorized target functions. CLI and
  local-write routing to the new functions belongs to S253-3 after registry
  resolution supplies `ResolvedBoardTarget`.

## Consumer/query compatibility

- **FUN-253-BOARD-DATA:** `boardDataOf authenticatedBoardEntry -> BoardData`
- **FUN-253-BOARD-LIST:** `boardListEntryOf authenticatedBoardEntry -> BoardListEntry`

Constraints:

- both surfaces retain existing fields with no added version or sequence;
- no public response is constructed directly from unverified authorized data;
- watchability counts distinct witness keys, not releases or lineages.
