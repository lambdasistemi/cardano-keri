# Plan — #253 bind endpoint-board registration authority

Artifact ceiling: 11,000 bytes and 210 lines.

## Source-derived strategy

The current predicate verifies the KERI signature over `endpoint_record` only
(`onchain/validators/endpoint_board.ak:25-34`). Post accepts that datum without
transaction-bound witness authorization (`endpoint_board.ak:63-75`), and
Update reuses the same predicate after checking only the old Cardano owner
(`endpoint_board.ak:101-119`). The released V1 wire has no sequence or nonce
(`onchain/lib/cardano_keri/endpoint_board_types.ak:10-16`).

Keep that KERI signature and add **DAT-253-AUTHORIZATION** plus
`authorization_signature`. This preserves the endpoint event's standard KERI
meaning while making Cardano custody and currency an explicit witness-approved
projection. Canonical Plutus Data CBOR follows the repository's existing
domain-separated signed-message convention (`onchain/lib/cardano_keri/checkpoint/close.ak:18-64,85-92`).

The nonce is a consumed `OutputReference`, not caller-chosen inert bytes. A
normal Post binds one selected spend input; Update binds the board `own_ref`
already supplied to the spend handler (`endpoint_board.ak:154-166`); migration
binds the consumed V1 board out-ref. Ledger consumption supplies the one-use
property, while sequence supplies lineage order.

## Compatibility and wire transition

- Preserve V1 constructor 0 and its exact four fields as a legacy decode and
  migration source. The released schema remains historically true.
- Emit only **DAT-253-DATUM-V2** constructor 1 at the V2 policy/address.
- Preserve the marker asset name as the raw witness key and preserve the
  endpoint signature over the endpoint event.
- Keep normal Post, Burn, Update, and Retire meanings. #254 supplies a distinct
  version-migration action/context so migration cannot be mistaken for an
  ordinary unlinked Post.
- Existing V1 signatures are insufficient for V2 because they never approved
  the owner, sequence, or nonce. Each of the three live witnesses must provide
  one fresh board-authorization signature for cutover; the exact endpoint bytes
  and original endpoint signature are otherwise carried unchanged.

## Dependency contract for #254

The board version vehicle supplied by #254 must satisfy all of the following
before V2 activation:

- **DEP-253-254-01:** identify source and destination board versions and bind
  the exact consumed V1 out-ref to the V2 successor on chain.
- **DEP-253-254-02:** make the transition atomic: consume and retire/burn one V1
  marker while minting exactly one V2 marker for the same witness key; an
  ordinary V2 Post cannot claim migration continuity.
- **DEP-253-254-03:** require the V1 recorded owner under the V1 lifecycle rule
  and require V2 witness authorization whose nonce is that V1 out-ref.
- **DEP-253-254-04:** require equality of witness key, endpoint bytes, endpoint
  signature, owner key hash, and board deposit between the decoded V1 source
  and V2 successor; map the legacy record to V2 sequence zero.
- **DEP-253-254-05:** expose a verifiable predecessor/successor version link to
  readers and reject unauthorized, replayed, one-to-many, many-to-one, or bare
  redeployment transitions.
- **DEP-253-254-06:** support the actual combined V1 burn/retire constraints;
  the migration must be valid under both deployed V1 and new V2 policies, not
  only under a model of the new policy.
- **DEP-253-254-07:** keep the endpoint board in the migration and M8
  compiled-UPLC proof targets, and carry all three live preprod records through
  the controlled cutover.

These are observable requirements on #254's mechanism; its checkpoint datum,
governance, and general version-family design remain owned by #254.

## Consumer impact draft for #171

The producer proposes the following cross-seam contract for agreement before
implementation:

- Board locators become version-aware and can query the V1 and V2 policy/address
  set during cutover; after an atomic migration, only the unspent V2 successor
  is current.
- `resolveBoardCatalog` currently accepts only `Constr 0` and verifies the
  endpoint signature (`offchain/deployment/Cardano/KERI/Deployment/EndpointBoard.hs:135-186`).
  It must decode V1/V2 by policy/version, verify both V2 signatures, and keep
  its all-or-nothing failure behavior.
- `BoardEntry` keeps witness key, AID, scheme, URL, out-ref, lovelace, and owner
  (`offchain/query/Cardano/KERI/ChainQuery/Types.hs:378-395`) and adds validator
  version and sequence. Nonce and raw authorization may remain verification
  internals unless a consumer demonstrates a public need.
- Existing query JSON fields stay stable. `validator_version` and `sequence`
  are additive fields; watchability remains one per witness regardless of
  duplicates. Query schema/docs must not label a V2 row verified unless both
  signatures passed.
- During cutover, a V1 predecessor and its V2 successor are one migration
  lineage, never two current records. Unrelated valid duplicates remain
  visible under the existing policy.

## Ordered slices

### S253-1 — canonical authorization and codecs

Add the versioned data/authentication model, canonical CBOR vectors, producer
payload/signature inputs, and fail-closed V1/V2 reader codecs. Preserve
independent endpoint-signature verification and prove every signed field is
observed.

Bisect condition: no deployed policy changes; producer/reader code agrees on
the exact V2 bytes and field mutation properties are red under a weakened
authorization predicate.

### S253-2 — V2 validator and transaction paths

Enforce V2 Post/Update/Retire rules, consumed nonce semantics, exact sequence,
and fresh witness authorization. Transaction planning selects and consumes the
declared Post nonce and uses the spent board out-ref for Update.

Bisect condition: the V2 policy is reproducible and all binding/replay
properties pass, but no live record is moved without S253-3.

### S253-3 — migration, consumer seam, and cutover evidence

Integrate #254's board transition, version-aware catalog/query behavior, and
the three-record preprod migration. Record predecessor/successor references and
prove endpoint, owner, value, authorization, and current-set continuity.

Bisect condition: every V1 record has one settled V2 successor, consumers show
only current state, and the compiled-UPLC target includes the new properties.

## Declared invariant campaign

Runtime ledger path: `$TICKET_RUNTIME_ROOT/campaign-ledger.md`; verification
configuration must resolve the variable to an absolute retained path before a
campaign starts. Initial accounting is `builds_spent=0` and `builds_budget=3`
build-consuming verification runs. Read-only inspection, typecheck-only work,
and interpreted instruments do not spend this build budget.

| Invariant row | Severity | Initial state | Required killing class |
|---|---|---|---|
| INV-253-SIGNED-FIELDS | BLOCKING | OPEN | Omit or alter each signed field while keeping the rest valid. |
| INV-253-OWNER | BLOCKING | OPEN | Substitute custody owner on Post, Update, and migration. |
| INV-253-SEQUENCE | BLOCKING | OPEN | Reuse stale sequence, skip a generation, or use nonzero genesis. |
| INV-253-NONCE | BLOCKING | OPEN | Reuse a spent nonce or bind a nonce absent from consumed inputs. |
| INV-253-WITNESS-AUTH | BLOCKING | OPEN | Accept endpoint-only or owner-only authority. |
| INV-253-MIGRATION | BLOCKING | OPEN | Lose/cross/duplicate a preserved V1 field or predecessor link. |

A row becomes `KILLED` only with a named mutant, failure evidence hash, and a
permanent property that kills its class. `BLOCKED` names the exact unavailable
fact. No row is eligible for `RESIDUAL` because every row reaches chain state
or a signature. The campaign ends when all rows are terminal. A tail round or
exhausted budget cannot close over any `OPEN` BLOCKING row; it records an
overrun and requires a higher-scope decision before further builds.

## Verification contract

- Demonstrate RED for custody substitution, stale resurrection, nonce replay,
  endpoint-only registration, and broken migration continuity against named
  weakened variants before relying on GREEN.
- Assert the exact signed bytes from producer, on-chain reconstruction, and
  reader verification agree through frozen vectors.
- Cross the real transaction boundary for Post, Update, and V1-to-V2 migration;
  unit-only success does not establish nonce consumption or version linkage.
- Run focused board checks, the complete repository gate, compiled-UPLC checks,
  and the settled preprod cutover in the authorized build environment.

## Risks and controls

- **Two signatures are conflated:** distinct data fields and verification
  errors preserve KERI-event authenticity versus board-context authorization.
- **A nonce is merely stored:** validation requires membership in consumed
  inputs or equality to the exact spent predecessor out-ref.
- **Sequence is treated globally:** it is scoped to one record lineage;
  duplicates remain independent and visible.
- **Legacy data appears valid at V2:** constructor and policy/version checks
  reject V1 as V2 current state.
- **Migration strands live records:** V2 activation is gated by #254 and fresh
  authorizations for all three preprod witnesses.
- **Consumers silently trust endpoint-only evidence:** V2 catalog verification
  is all-or-nothing and exposes version/sequence at the query seam.

## Artifact measurements

Provider-reported token counts are unavailable for local files. Actual byte and
line counts are measured from the planning tree before publication.

| Artifact | Ceiling bytes / lines | Actual bytes / lines |
|---|---:|---:|
| `spec.md` | 8,000 / 180 | 7,772 / 132 |
| `plan.md` | 11,000 / 210 | 9,979 / 187 |
| `modules-model.md` | 6,000 / 145 | 4,282 / 88 |
| `data-model.md` | 7,000 / 175 | 5,495 / 148 |
| `functions-model.md` | 6,000 / 155 | 4,429 / 90 |
| `tasks.md` | 6,000 / 145 | 3,781 / 69 |
