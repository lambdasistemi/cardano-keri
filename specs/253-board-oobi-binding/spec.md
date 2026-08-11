# Spec — #253 bind endpoint-board registration authority

Artifact ceiling: 8,000 bytes and 180 lines.

## Outcome

Every endpoint-board Post, Update, and V1-to-V2 migration carries a one-use
authorization signed by the witness key. The authorization binds the exact
endpoint bytes to the Cardano lifecycle owner, a monotonic board sequence, and
a consumed output-reference nonce. A copied KERI endpoint record is therefore
not a transferable registration credential.

The original KERI `/loc/scheme` signature remains unchanged and continues to
authenticate the endpoint event. The new board authorization is a second,
domain-separated witness signature over Cardano projection context; it does
not originate or modify KERI identity state.

## User stories

- **US-253-01:** A witness can designate the Cardano key that owns one board
  lineage without a mempool observer substituting its own key hash.
- **US-253-02:** A witness can advance a listing and know that an authorization
  for an older generation cannot restore the superseded endpoint.
- **US-253-03:** A follower can verify both the KERI endpoint event and its
  current board authorization, while retaining the existing witness/AID/URL
  view.
- **US-253-04:** The three preprod V1 witness records move to V2 through the
  supported board migration, preserving their records and custody instead of
  being abandoned or recreated by a bare deployment.

## Functional requirements

- **RQ-253-01 — two signatures, two roles:** `endpoint_signature` continues to
  verify over `endpoint_record`. `authorization_signature` verifies over the
  canonical **DAT-253-AUTHORIZATION** under the same `witness_key`. Neither
  signature substitutes for the other.
- **RQ-253-02 — exact binding:** **DAT-253-AUTHORIZATION** covers its domain,
  the V2 policy id, witness key, exact endpoint record bytes, owner key hash,
  sequence, and nonce. Any change to any field invalidates the authorization.
- **RQ-253-03 — one-use Post:** a normal Post has sequence zero, its nonce names
  a consumed input carrying no endpoint-board marker from any supported version,
  and its output is valid only with both witness signatures. Reusing the same
  signed Post after its nonce is spent is rejected.
- **RQ-253-04 — ordered Update:** an Update keeps the marker witness key,
  requires the old Cardano owner, sets sequence to exactly `old + 1`, and sets
  the new nonce to the exact spent board output reference. The replacement has
  fresh witness authorization over its endpoint, owner, sequence, and nonce.
- **RQ-253-05 — authorized custody transfer:** an Update may change the owner
  only when the old owner authorizes the spend and the witness authorization
  names the new owner. Merely copying endpoint evidence cannot seize custody.
- **RQ-253-06 — unchanged retirement:** Retire remains authorized by the owner
  recorded in the consumed V2 datum and retains the exact burn and refund
  guarantees. It creates no successor authorization.
- **RQ-253-07 — explicit version wire:** V1 keeps its released constructor and
  four fields for decoding and migration. Current V2 outputs use the distinct
  **DAT-253-DATUM-V2** constructor; a V1 datum is never accepted as new V2
  state.
- **RQ-253-08 — migration, not redeployment:** each live V1 record moves in one
  linked V1-to-V2 transaction through the mechanism supplied by #254. The V2
  successor preserves witness key, exact endpoint bytes, endpoint signature,
  owner, and board deposit; starts sequence zero; uses the consumed V1 out-ref
  as nonce; and requires a fresh V2 authorization signature.
- **RQ-253-09 — fail-closed readers:** a malformed or unauthenticated V2 row
  fails the complete catalog read with its out-ref and reason. Readers never
  report `verified` after checking only the KERI signature.
- **RQ-253-10 — duplicate policy unchanged:** global witness uniqueness remains
  unenforced. Every duplicate needs its own unspent nonce and witness
  authorization, and sequence orders only one out-ref lineage.
- **RQ-253-11 — formal target continuity:** the new authorization, replay, and
  migration properties remain in the endpoint-board compiled-UPLC target used
  by M8; a validator version change must not silently remove that target.

## Binding rationale

| Bound value | Attack rejected |
|---|---|
| `owner_key_hash` | Custody substitution: an observer cannot pair a genuine endpoint with its own lifecycle key. |
| `sequence` | Stale replacement: an old endpoint authorization cannot satisfy the next generation of the same lineage. |
| consumed `nonce` | Cross-transaction replay: sequence-zero Posts and same-generation evidence cannot be reused to create another live lineage or resurrect a retired one. |
| exact `endpoint_record` | Record substitution: authorization for one genuine endpoint cannot bless another endpoint event from the same witness. |
| domain and V2 policy id | Cross-protocol and cross-validator reuse: a signature made for another purpose or board version is not valid here. |
| `witness_key` | The signed envelope states the marker identity that the policy and verifier bind to the signature key. |

## Invariants

- **INV-253-SIGNED-FIELDS [BLOCKING]:** every accepted V2 state has a valid
  authorization signature over every field in **DAT-253-AUTHORIZATION**.
- **INV-253-OWNER [BLOCKING]:** changing the bound owner without a new valid
  witness authorization is rejected on Post, Update, and migration.
- **INV-253-SEQUENCE [BLOCKING]:** Post and migration start at zero; every
  Update advances exactly one; stale, skipped, or negative sequence is rejected.
- **INV-253-NONCE [BLOCKING]:** Post consumes its named nonce; Update and
  migration bind the exact predecessor out-ref; an authorization cannot create
  two accepted successors.
- **INV-253-WITNESS-AUTH [BLOCKING]:** no V2 registration exists with only a
  valid KERI endpoint signature or only Cardano owner authority.
- **INV-253-MIGRATION [BLOCKING]:** one accepted V1 input yields exactly one
  linked V2 successor with preserved record, owner, and deposit, and the V1
  marker is no longer current.

## Rejection behavior

Validation rejects wrong domains or policies, crossed witness keys, altered
endpoint bytes, substituted owners, wrong sequence, missing or non-consumed
nonces, reused predecessor references, malformed signatures, V1 state at the
V2 address, and migration successors that lose or duplicate record/value
continuity.

## Observable acceptance

1. A genuine Post and ordered Update are accepted with both signatures.
2. Owner substitution, stale endpoint resurrection, and exact authorization
   replay each fail under a permanent negative property that is demonstrated
   able to fail against the corresponding weakened validator.
3. Removing the board authorization while retaining a valid endpoint signature
   is rejected.
4. All three preprod V1 records migrate through #254's version vehicle, and a
   read across the cutover reports one current V2 successor per migrated V1
   record with preserved endpoint, owner, and deposit.
5. V2 consumers verify both signatures and retain compatible witness/AID/URL,
   owner, out-ref, deposit, and watchability behavior.

## Scope

Included: V2 board wire/authentication rules, producer and reader contract
changes, permanent security properties, #254 board-migration requirements,
the three-record preprod transition, and the consumer seam with #171.

Excluded: changing KERI endpoint-event semantics, global board uniqueness,
checkpoint migration internals owned by #254, and enforcement payee
authentication from #271. The latter may share a validator release/cutover but
has no board authorization code or invariant in common with this change.
