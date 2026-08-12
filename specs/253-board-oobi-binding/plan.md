# Plan — #253 bind endpoint-board registration authority

Artifact ceiling: 11,000 bytes and 210 lines.

## Source-derived strategy

The deployed predicate verifies only the KERI signature over
`endpoint_record`; Post has no transaction-bound witness authorization and
Update checks only the recorded Cardano owner. Keep that KERI signature and
add **DAT-253-AUTHORIZATION** plus `authorization_signature`.

Canonical Plutus Data CBOR follows the existing domain-separated signed-message
convention. The nonce is a consumed `OutputReference`, not inert caller bytes.
Post binds one selected ordinary spend input; Update binds the exact board
`own_ref`; migration binds the consumed legacy board out-ref. Ledger
consumption gives one-use authorization, and transaction history gives lineage
order. A stored sequence adds no rejection while exact nonce remains enforced,
so it is deleted.

## Compatibility and wire transition

- Preserve the legacy constructor 0 with its exact four fields for historical
  decoding and migration only.
- Emit the authorized target as constructor 0 with six fields: witness,
  endpoint bytes, endpoint signature, owner, nonce, authorization signature.
- Route decoding through the applied policy hash and release registry, then
  require the release's exact structural shape. Unknown hashes fail closed.
- Preserve marker asset name as raw witness key and preserve the endpoint
  signature over the endpoint event.
- Keep normal Post, Burn, Update, and Retire meanings. #254 supplies atomic
  migration entry/exit tied to the applied predecessor policy.
- Existing legacy signatures are insufficient because they did not approve
  owner and nonce. Each live witness supplies fresh board authorization for
  cutover; endpoint bytes/signature remain unchanged.
- Store no datum version, version-only constructor, sequence, or origin. Do not
  promote any of them into consumer types or JSON.

## Revised dependency contract for #254

This `DEP-253-254` contract supersedes clauses `DEP-253-254-01` through `-07`:

1. Source and destination are identified by applied script/policy hash and the
   off-chain release registry. The successor pins the exact predecessor policy
   and consumes the named predecessor out-ref. No datum version is stored.
2. One transaction spends and retires/burns one deployed marker, mints one
   same-witness successor marker, and confines it to one output.
3. The recorded source owner authorizes the spend, and target witness
   authorization binds a nonce equal to the exact source out-ref. Custody
   substitution and replay remain permanent RED controls.
4. Witness key, endpoint bytes/signature, owner, and deposit are preserved. The
   target uses the structurally distinct six-field authorized datum without a
   sequence field or version-only constructor.
5. Readers derive predecessor/successor from the atomic transaction. Unknown
   hashes and incomplete transactions fail closed; no origin or version is
   promoted.
6. Both deployed source Retire/burn constraints and target policy accept the
   same transaction.
7. Board migration remains in M8 with the all-three-record cutover proof.

#254 owns its generic migration mechanics, registry, and checkpoint design; it
cannot waive the target board authentication supplied here.

## Consumer impact draft for #171

- Board locators become registry-backed applied-policy/address sets during
  cutover. The matched release entry selects the exact decoder and target
  policy used for authorization verification.
- `resolveBoardCatalog` preserves all-or-nothing failure. It decodes legacy or
  authorized shapes only under known policies, verifies both target signatures,
  and rejects unknown hashes and incomplete migration edges.
- `BoardEntry` retains witness key, AID, scheme, URL, out-ref, lovelace, and
  owner. The matched policy/release identity may remain authenticated internal
  provenance because registry lookup and authorization verification consume
  it; no public datum-version or sequence field is added.
- Existing query JSON remains stable. During cutover, a spent predecessor and
  its atomic successor are one lineage, never two current records. Unrelated
  valid duplicates remain visible.

## Ordered slices

### S253-1 — canonical authorization and codecs (accepted foundation)

The accepted slice added canonical authorization, cross-language vectors,
producer payload/signature inputs, and fail-closed codec groundwork. It used
the pre-amendment sequence/version shape; S253-2 must slim this surface before
wiring it into a validator.

Bisect condition met at `82b790f265eeb1c5ce786eadb31ee68c17a82757`:
no deployed policy changed and the authorization field mutant class was killed.

### S253-2 — slim authorization, validator, and transaction paths

Delete sequence and version-only wire/API state. Freeze new six-field datum and
six-field signed-message vectors, then enforce Post/Update/Retire, exact consumed
nonce, marker/policy binding, owner authority, unique successor, and both
signatures. Add separately named target-policy planners that select and consume
the declared Post nonce and derive the Update nonce from the spent board
out-ref. The existing deployed-policy planners and their run functions remain
byte-compatible: they target the immutable four-field legacy policy and cannot
emit the authorized target datum.

Bisect condition: the target policy is reproducible and custody-substitution,
replay/resurrection, endpoint-only, shape, and lifecycle properties pass; no
live record moves without S253-3.

### S253-3 — migration, consumer seam, and cutover evidence

Integrate #254's applied-hash transition, registry-backed catalog behavior, and
the three-record preprod migration. Record transaction-derived predecessor and
successor references and prove endpoint, owner, deposit, authorization, and
current-set continuity. Wire the additive target planners into CLI/local-write
composition only after the target release entry exists; no S253-2 command is
allowed to point the deployed legacy policy at the six-field datum.

Bisect condition: every legacy record has one settled successor, consumers show
only current state, and the compiled target includes the new properties.

## Declared invariant campaign

Runtime ledger: `/tmp/ms-keri-1/e274/cardano-keri-253/evidence/campaign-ledger.md`.
Build accounting is retained there; interpreted or typecheck-only work does not
spend the build budget.

| Invariant row | Severity | Required killing class |
|---|---|---|
| INV-253-SIGNED-FIELDS | BLOCKING | Omit/alter each retained signed field while the rest stays valid. |
| INV-253-OWNER | BLOCKING | Substitute custody owner on Post, Update, or migration. |
| INV-253-NONCE | BLOCKING | Reuse authorization, omit consumed nonce, or bind the wrong predecessor. |
| INV-253-WITNESS-AUTH | BLOCKING | Accept endpoint-only or owner-only authority. |
| INV-253-MIGRATION | BLOCKING | Lose/cross/duplicate a preserved field or transaction edge. |

The former sequence row is retired by accepted necessity analysis, conditional
on exact nonce. A row becomes `KILLED` only with a named mutant, failure-evidence
hash, and permanent property. No quiet tail or exhausted budget closes an OPEN
BLOCKING row.

## Verification contract

- Demonstrate RED for custody substitution, nonce replay/resurrection,
  endpoint-only registration, wrong structural shape, and broken migration
  continuity against named weakened variants before relying on GREEN.
- Assert exact producer, on-chain reconstruction, and reader bytes through
  frozen cross-language vectors for every retained signed field.
- Cross the real transaction boundary for Post, Update, and migration; unit-only
  success does not establish consumption or atomic linkage.
- Run focused board checks, the complete repository gate, compiled-target
  checks, and the settled preprod cutover in the authorized build environment.

## Risks and controls

- **Two signatures are conflated:** distinct fields and errors preserve KERI
  endpoint authenticity versus board-context authorization.
- **Nonce is merely stored:** Post requires the named consumed input; Update
  and migration require exact equality with the spent predecessor out-ref.
- **Legacy shape appears current:** applied policy selects the decoder and each
  release requires an exact field count; four-field data rejects at target.
- **Policy label is trusted:** authorization uses applied policy id; labels are
  registry metadata only.
- **Migration strands live records:** activation is gated by #254 and fresh
  authorizations for all three preprod witnesses.
- **Target datum is sent to the deployed policy:** legacy planner names and
  behavior remain unchanged; additive target planners accept a resolved target
  locator and S253-3 alone wires them to the release registry and CLI.
- **Consumers trust endpoint-only evidence:** authorized catalog verification
  is all-or-nothing and unknown release hashes fail closed.

## Artifact measurements

Actual byte and line counts are measured from the amended planning tree before
publication and must remain under the ceilings stated in each artifact.
