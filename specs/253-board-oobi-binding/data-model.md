# Data model — #253 board OOBI binding

Artifact ceiling: 7,000 bytes and 175 lines.

## Board datum shapes

### DAT-253-LEGACY-DATUM — frozen legacy source

Under the registered deployed policy, constructor 0 remains exactly:

```text
Constr 0
  [ B witness_key
  , B endpoint_record
  , B endpoint_signature
  , B owner_key_hash
  ]
```

It is accepted only as historical data or a migration source. It is never
emitted or accepted as current state under the target policy.

### DAT-253-AUTHORIZED-DATUM — current target datum

Under the registered target policy, constructor 0 is structurally distinct:

```text
Constr 0
  [ B witness_key
  , B endpoint_record
  , B endpoint_signature
  , B owner_key_hash
  , Constr 0 [ B nonce_tx_id, I nonce_output_index ]
  , B authorization_signature
  ]
```

| Field | Constraint and meaning |
|---|---|
| `witness_key` | Exactly 32 bytes; equals marker name and verifies both signatures. |
| `endpoint_record` | Non-empty exact serialized KERI `/loc/scheme` reply event. |
| `endpoint_signature` | Exactly 64 bytes; verifies over `endpoint_record`. |
| `owner_key_hash` | Exactly 28 bytes; controls Update/Retire and is witness-bound. |
| `authorization_nonce` | Valid out-ref; consumed Post input or exact board predecessor. |
| `authorization_signature` | Exactly 64 bytes; verifies canonical **DAT-253-AUTHORIZATION**. |

There is no datum version/tag, stored origin, or sequence. Decoder selection is
by matched applied policy; exact field count rejects the other release's shape.

## Signed authorization

### DAT-253-AUTHORIZATION — `BoardAuthorization`

Canonical Plutus Data CBOR is constructor 0 with exact order:

```text
Constr 0
  [ B "cardano-keri/endpoint-board/authorization"
  , B board_policy_id
  , B witness_key
  , B endpoint_record
  , B owner_key_hash
  , Constr 0 [ B nonce_tx_id, I nonce_output_index ]
  ]
```

The validator reconstructs `board_policy_id` from its own applied identity and
the remaining fields from the proposed datum and trusted transaction context.
Producer and reader reconstruct the same bytes. JSON, text, endpoint-signature
bytes, and caller-provided preimages are not substitutes.

Relationships:

- **DATA-INV-253-01:** datum witness = marker name = authorization witness =
  both signature verification keys.
- **DATA-INV-253-02:** authorization endpoint bytes equal the independently
  endpoint-signed datum bytes.
- **DATA-INV-253-03:** authorization policy id is the applied target marker
  policy, preventing cross-validator reuse.
- **DATA-INV-253-04:** nonce is a consumed input for Post and equals the spent
  board out-ref for Update and migration.

## Lifecycle state

### DAT-253-LINEAGE — transaction-derived board lineage

A lineage is identified by its current out-ref and predecessor transactions,
not witness key, counter, or stored origin because valid duplicates remain
allowed.

- Post consumes one named non-board nonce and creates one authorized output.
- Update consumes current output, creates exactly one authorized successor,
  and uses the consumed current out-ref as successor nonce.
- Retire consumes current output and creates no successor.
- Migration consumes one legacy output, creates exactly one authorized
  successor, and uses the legacy out-ref as successor nonce.

Ledger consumption permits at most one accepted successor per predecessor.
Distinct same-witness lineages require distinct one-use Post nonces.

### DAT-253-MIGRATION-LINK — applied-hash continuity

Observed from one atomic transaction plus release registry:

- registered source and target applied policy hashes;
- exact legacy source and authorized successor out-refs;
- preserved witness, endpoint bytes/signature, owner, and deposit;
- successor nonce equal to the source out-ref;
- source marker retired/burned and exactly one same-name target marker minted
  and confined.

The target policy is applied with the accepted predecessor policy. The link is
invalid if either side is absent, ambiguous, crossed, split across
transactions, or accepted by only one policy.

## Promoted consumer view

### DAT-253-BOARD-ENTRY — authenticated `BoardEntry`

Retains witness key, parsed AID, scheme, URL, transaction id, output index,
lovelace, and owner key hash. Construction under the target policy requires
both signatures. Raw nonce/signature and matched release identity remain
verification provenance unless a consumer demonstrates a public need.

During cutover, registry-backed locators read registered policies; spent
predecessors are not current and atomic successors are not duplicate current
records. Unknown policies and incomplete transaction edges fail closed.

### DAT-253-TARGET-LOCATOR — resolved authorized target

A provider-neutral planning input contains the target applied policy id,
script address, and reference-script out-ref resolved from #254's registry.
It contains no release label, datum version, predecessor origin, or live query
handle. S253-2 tests may construct it directly; S253-3 supplies it through
registry-backed CLI/local-write composition.

## Redeemer compatibility

- Target `Post`, `Burn`, `Update`, and `Retire` preserve legacy constructor
  meanings and required fields.
- #254 supplies migration entry/exit context bound to the applied predecessor
  policy and exact source out-ref.
- Migration cannot be an ordinary Post because it additionally claims source
  field/value continuity and must satisfy both policy arms atomically.
