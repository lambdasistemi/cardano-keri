# Spec — #253 bind endpoint-board registration authority

Artifact ceiling: 8,000 bytes and 180 lines.

## Outcome

Every endpoint-board Post, Update, and legacy-to-successor migration carries a
one-use authorization signed by the witness key. The authorization binds the
exact endpoint bytes to the Cardano lifecycle owner and a consumed
output-reference nonce. A copied KERI endpoint record is therefore not a
transferable registration credential.

The original KERI `/loc/scheme` signature remains unchanged and continues to
authenticate the endpoint event. The board authorization is a second,
domain-separated witness signature over Cardano projection context; it does
not originate or modify KERI identity state.

## User stories

- **US-253-01:** A witness can designate the Cardano key that owns one board
  lineage without a mempool observer substituting its own key hash.
- **US-253-02:** A witness can authorize exactly one Post or successor tied to
  one consumed out-ref, so replay cannot create another live lineage or
  resurrect a retired one.
- **US-253-03:** A follower can verify both the KERI endpoint event and its
  current board authorization while retaining the existing witness/AID/URL
  view.
- **US-253-04:** The three preprod legacy witness records move through the
  supported board migration, preserving record and custody rather than being
  abandoned or recreated by a bare deployment.

## Functional requirements

- **RQ-253-01 — two signatures, two roles:** `endpoint_signature` verifies over
  `endpoint_record`. `authorization_signature` verifies over canonical
  **DAT-253-AUTHORIZATION** under the same `witness_key`. Neither substitutes
  for the other.
- **RQ-253-02 — exact binding:** **DAT-253-AUTHORIZATION** covers its stable
  domain, target policy id, witness key, exact endpoint bytes, owner key hash,
  and nonce. Any field mutation invalidates the authorization.
- **RQ-253-03 — one-use Post:** a Post's nonce names a consumed input carrying
  no marker under the target or its applied predecessor policy. Its output is valid only with
  both witness signatures. Reusing the signed Post after that nonce is spent
  is rejected.
- **RQ-253-04 — predecessor-bound Update:** an Update keeps the marker witness
  key, requires the recorded Cardano owner, creates exactly one successor, and
  sets the new nonce to the exact spent board out-ref. The successor has fresh
  witness authorization over its endpoint, owner, and nonce.
- **RQ-253-05 — authorized custody transfer:** an Update may change owner only
  when the recorded owner authorizes the spend and the witness authorization
  names the new owner. Copying endpoint evidence cannot seize custody.
- **RQ-253-06 — unchanged retirement:** Retire remains authorized by the owner
  recorded in the consumed authorized datum and retains the exact burn and
  refund guarantees. It creates no successor authorization.
- **RQ-253-07 — structural wire and release identity:** legacy data remains
  decodable only as constructor 0 with four frozen fields. Current authorized
  data is constructor 0 with six fields. The matched applied policy hash and
  registered release select semantics; no datum version, version-only
  constructor, stored origin, or promoted version exists.
- **RQ-253-08 — migration, not redeployment:** each live legacy record moves in
  one atomic transaction through #254. The successor preserves witness key,
  exact endpoint bytes/signature, owner, and deposit; binds the legacy out-ref
  as its nonce; and requires fresh target authorization.
- **RQ-253-09 — fail-closed readers:** an unknown applied hash, malformed
  authorized row, failed signature, or incomplete migration transaction fails
  the complete catalog read with out-ref and reason. Endpoint-only verification
  is never reported as fully verified.
- **RQ-253-10 — duplicate policy unchanged:** witness uniqueness remains
  unenforced. Every duplicate needs its own consumed nonce and witness
  authorization. Transaction history, not a stored counter, orders a lineage.
- **RQ-253-11 — formal target continuity:** authorization, replay, and migration
  properties remain in the compiled endpoint-board target used by M8; a policy
  hash change must not silently remove that target.

## Retained-field demonstrations

| Bound value | Attack rejected when retained |
|---|---|
| `owner_key_hash` | Custody substitution: a genuine authorization for owner `O` cannot be copied into a datum naming attacker `A`, who could otherwise Update or Retire it. |
| consumed `nonce` | Cross-transaction replay/resurrection: one witness approval cannot create a second live record by consuming `U2` instead of the authorized `U1`, nor reappear after retirement. |
| exact `endpoint_record` | Record substitution: authorization for one genuine endpoint cannot bless another endpoint event from the same witness. |
| stable domain | Cross-protocol reuse: a signature for another cardano-keri purpose cannot become a board authorization. |
| target policy id | Cross-validator reuse: a signature for one applied board policy cannot authorize another. |
| `witness_key` | Marker/key substitution: the signed identity must equal the marker asset name and both verification keys. |

`sequence` is cut because exact predecessor nonce plus transaction history
reject every stale-predecessor attack it rejected. The cut is conditional:
weakening exact nonce reopens sequence. A datum version/tag is cut because no
consumer reads it; structural shape plus applied hash distinguish releases.

## Invariants

- **INV-253-SIGNED-FIELDS [BLOCKING]:** every accepted authorized state has a
  valid witness signature over every retained authorization field.
- **INV-253-OWNER [BLOCKING]:** changing the bound owner without fresh witness
  authorization rejects on Post, Update, and migration.
- **INV-253-NONCE [BLOCKING]:** Post consumes its named nonce; Update and
  migration bind the exact predecessor out-ref; one authorization cannot make
  two accepted successors.
- **INV-253-WITNESS-AUTH [BLOCKING]:** no authorized registration exists with
  only a valid KERI endpoint signature or only Cardano owner authority.
- **INV-253-MIGRATION [BLOCKING]:** one accepted legacy input yields exactly
  one transaction-linked successor with preserved record, owner, and deposit,
  and the predecessor marker is no longer current.

## Rejection behavior

Validation rejects wrong domains or policies, crossed witness keys, altered
endpoint bytes, substituted owners, missing/non-consumed nonces, reused or
wrong predecessor references, malformed signatures, a legacy shape at the
target policy, and migration successors that lose or duplicate record/value.

## Observable acceptance

1. A genuine Post and predecessor-bound Update are accepted with both
   signatures.
2. Custody substitution and exact authorization replay/resurrection fail under
   permanent negative properties demonstrated against weakened validators.
3. Removing board authorization while retaining a valid endpoint signature is
   rejected.
4. All three preprod legacy records migrate through #254; a cross-cutover read
   reports one current successor per source with endpoint, owner, and deposit
   preserved.
5. Consumers verify both signatures and retain compatible witness/AID/URL,
   owner, out-ref, deposit, and watchability behavior without exposing a datum
   version or sequence.

## Scope

Included: authorized board wire rules, producer and reader contract changes,
permanent security properties, #254 board-migration requirements, the
three-record preprod transition, and the consumer seam with #171.

Excluded: changing KERI endpoint-event semantics, global board uniqueness,
checkpoint migration internals owned by #254, and enforcement payee
authentication from #271. The latter may share a release/cutover but has no
board authorization invariant in common with this change.
