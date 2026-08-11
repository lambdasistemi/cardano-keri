# Data model — #253 board OOBI binding

Artifact ceiling: 7,000 bytes and 175 lines.

This model owns changed wire/data shapes, relationships, validation, and state
invariants. Placement is in `modules-model.md`; signatures are in
`functions-model.md`.

## Versioned board datum

### DAT-253-DATUM-V1 — legacy `BoardDatumV1`

Constructor 0 remains exactly:

```text
Constr 0
  [ B witness_key
  , B endpoint_record
  , B endpoint_signature
  , B owner_key_hash
  ]
```

It is accepted only as a source under the deployed V1 policy and migration
decoder. It is never emitted or accepted as a current V2 output.

### DAT-253-DATUM-V2 — current `BoardDatumV2`

Constructor 1 is:

```text
Constr 1
  [ B witness_key
  , B endpoint_record
  , B endpoint_signature
  , B owner_key_hash
  , I sequence
  , Constr 0 [ B nonce_tx_id, I nonce_output_index ]
  , B authorization_signature
  ]
```

Field constraints:

| Field | Constraint and meaning |
|---|---|
| `witness_key` | Exactly 32 bytes; equals the marker asset name and verifies both signatures. |
| `endpoint_record` | Non-empty exact serialized KERI `/loc/scheme` reply event. |
| `endpoint_signature` | Exactly 64 bytes; verifies over `endpoint_record` under `witness_key`. |
| `owner_key_hash` | Exactly 28 bytes; controls Update/Retire and is bound by witness authorization. |
| `sequence` | Non-negative; zero at Post/migration and exactly predecessor plus one at Update. |
| `authorization_nonce` | A valid ledger output reference; consumed non-board Post input or exact board predecessor out-ref. |
| `authorization_signature` | Exactly 64 bytes; verifies over canonical **DAT-253-AUTHORIZATION** under `witness_key`. |

## Signed authorization

### DAT-253-AUTHORIZATION — `BoardAuthorizationV2`

The signature message is canonical Plutus Data CBOR for constructor 0 with
this exact field order:

```text
Constr 0
  [ B "cardano-keri/endpoint-board/authorization/v2"
  , B board_policy_id
  , B witness_key
  , B endpoint_record
  , B owner_key_hash
  , I sequence
  , Constr 0 [ B nonce_tx_id, I nonce_output_index ]
  ]
```

The validator reconstructs `board_policy_id` from its own policy identity and
all other fields from the proposed V2 datum plus trusted spend context. The
producer signs exactly these bytes; the reader reconstructs the same bytes
from the datum and policy/version locator. No JSON, text rendering, endpoint
signature bytes, or caller-provided preimage is accepted as a substitute.

Relationships:

- **DATA-INV-253-01:** datum witness key = marker asset name = authorization
  witness key = endpoint-signature verification key.
- **DATA-INV-253-02:** authorization endpoint bytes equal the datum endpoint
  bytes that the independent endpoint signature authenticates.
- **DATA-INV-253-03:** authorization policy id is the policy that controls the
  V2 marker, preventing use at another board version.
- **DATA-INV-253-04:** authorization nonce is present in consumed inputs for
  Post; equals the spent board out-ref for Update and V1-to-V2 migration.

## Lifecycle state

### DAT-253-LINEAGE — board record lineage

A lineage is identified operationally by its current output reference and
predecessor chain, not globally by witness key because valid duplicates remain
allowed.

- Post creates sequence 0 from a consumed non-board nonce.
- Update consumes the current output, creates one successor at sequence +1,
  and uses the consumed current out-ref as successor nonce.
- Retire consumes the current output and creates no successor.
- Migration consumes one V1 output, creates one V2 sequence-0 successor, and
  uses the consumed V1 out-ref as successor nonce.

There is at most one accepted successor per consumed predecessor reference.
Distinct lineages for the same witness require distinct one-use Post nonces.

### DAT-253-MIGRATION-LINK — V1-to-V2 continuity

Fields/relations observed from one transaction:

- source validator version and policy id;
- exact V1 source output reference;
- destination validator version and policy id;
- exact V2 successor output reference;
- preserved witness key, endpoint record, endpoint signature, owner key hash,
  and lovelace deposit;
- V2 sequence zero and nonce equal to the V1 source out-ref;
- old marker retired/burned and exactly one new marker minted.

The link is invalid if either endpoint is absent, ambiguous, crossed with
another record, or accepted by only one side's policy.

## Promoted consumer view

### DAT-253-BOARD-ENTRY — authenticated `BoardEntry`

Retains existing witness key, parsed AID, scheme, URL, transaction id, output
index, lovelace, and owner key hash. Adds:

- `boardValidatorVersion`: V1 or V2;
- `boardSequence`: absent for unmigrated V1, present and non-negative for V2.

V2 construction requires successful endpoint and authorization verification.
Raw nonce/signature values need not enter public query JSON. During cutover,
version-aware locators may read both policies; spent V1 predecessors are not
current and migration successors are not counted as duplicates of them.

## Redeemer compatibility

- Normal V2 `Post`, `Burn`, `Update`, and `Retire` preserve the V1 constructor
  meanings and required fields.
- #254 supplies a distinct version-migration action/context naming the source
  version and out-ref. Its constructor allocation becomes shared protocol data
  before implementation.
- Migration cannot use ordinary `Post`, because ordinary Post carries no claim
  of V1 field/value continuity.
