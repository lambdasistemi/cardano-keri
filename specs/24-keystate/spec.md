# Spec: identity key-state UTxO + permissionless pre-rotation (list-shaped KeyState)

!!! warning "Historical & non-normative: the single-MPF identity-registry storage/discovery here is the rejected Candidate-B lineage (#92)"
    **Normative status of this document (read this first).** The **physical storage
    and discovery** layer described below — the **standalone single/shared
    identity-registry UTxO**, the **MPF identity trie** keyed by `trie_key`, the
    **depth-10 sliding `root_window`**, and **`identity_root` inclusion proofs**
    (including the A12 registry-contention read) — is
    **historical, non-normative, and superseded wholesale**
    for **current-authority storage and discovery**
    by the **sovereign per-AID checkpoint contract**. It is retained only per
    constitution I (superseded analyses are annotated, never deleted) as the
    **rejected Candidate-B lineage**; nothing in the `RegistryDatum` / `trie_key` /
    `identity_root` / `root_window` body below may be read as current normative
    design.

    **Current normative authority (what replaces it).** Per
    `specs/92-checkpoint-contention/DECISION.md` (Candidate A), each AID's current
    authority lives in its
    **own sovereign, per-AID, quantity-one uniquely-tokenized checkpoint UTxO** —
    asset id `(checkpoint_policy_id, aid_asset_name)`, current weighted key state in
    the inline `CheckpointDatumV1`, normal rotation a `delta = 0` continuing-output
    transition (`seq + 1`). **Currentness = the unspent checkpoint tip**; discovery
    is a **generic exact-asset `(policy_id, asset_name)` lookup**. The index /
    candidate outref is a **liveness hint only**, and is
    **re-validated against the ledger** — never an authoritative registry root — so
    a stale index answer yields retry/failure, not forged authority. This removes
    cross-AID contention on the
    per-AID current-authority storage/rotation path: because each AID advances only
    through its **own** quantity-one checkpoint UTxO, an unrelated or hostile AID
    cannot contend for, consume, serialize, or delay that AID's checkpoint UTxO or
    its rotation throughput, and the A12 single-UTxO contention residual on this
    path falls away. It does **not** make an AID immune to every hostile actor: the
    **emergency freeze (R-FRZ) remains a separate, shared, attacker-contendable
    residual** — re-cutting it sovereign is a named downstream dependency.

    **Frozen wire contract (the schema the recut implements).** The
    `CheckpointDatumV1` datum, the `Threshold` sum + F18 rule table, both message
    domains (`InceptionMessage` / `AdvanceMessage`), the seven F10 advance
    equalities (incl. the revealed-successor authorization), and the pinned
    `deriveAidAssetName` / `CHECKPOINT_ASSET_DOMAIN_TAG` locator derivation are
    frozen in `specs/68-keystate-shape/spec.md` ("The frozen surface" +
    "Downstream obligation for #24"); #24 imports those types verbatim and does
    **not** re-derive the shape.

    **Downstream #24 obligation (the mechanical recut).** The mechanical recut of
    these validators onto the frozen #68 contract — deleting the standalone MPF
    identity-registry / `identity_root` / `root_window` / depth-10 `trie_key` path
    from this document — is the downstream #24 deliverable, not performed here. In
    short: this **mechanical recut is downstream #24**, not part of this record.

    **Reusable analysis, identified separately (still valid).** Independent of the
    rejected storage/discovery layer above, the **list-shaped, threshold-capable
    `KeySet` / `KeyState` shape**, the **KERI alignment** (qb64 digest preimage,
    weighted-threshold mapping), and the **permissionless pre-rotation** analysis
    **remain valid and unchanged** — this is the current weighted key state the
    per-AID `CheckpointDatumV1` now carries, not a store keyed into a shared trie.

    **Delegation boundary (#68/#81, 2026-07-15):** V1 accepts independent
    `icp` AIDs only, rejects `dip` / `drt`, and its `CheckpointDatumV1` has no
    passive `delegator` / `di` field. Cooperative KERI delegation is a separately
    versioned proof protocol because `di` alone does not prove the recursive parent
    anchors. Any contrary `delegator` shape in older revisions of this spec is
    superseded by `specs/68-keystate-shape/delegation-boundary-decision.md`.

Issue: https://github.com/lambdasistemi/cardano-keri/issues/24
Epic: https://github.com/lambdasistemi/cardano-keri/issues/21
Ratified design inputs: `docs/design/business-cases/index.md` (factored-core
item 1), `docs/design/aid-model.md`, `docs/architecture/identity-ops.md`,
`docs/architecture/value-auth.md`, `specs/23-identity-auth/spec.md`.

## Problem

Identity key-state anchoring and rotation must live on a **standalone identity
UTxO** so that recovery from key theft never depends on oracle liveness: every
identity operation is authorized by cryptographic material alone (signatures,
preimages, proofs), never by an operator key
(`docs/architecture/identity-ops.md`).

The business-case factoring ratified a scope change
(`docs/design/business-cases/index.md`, factored-core item 1): every case has
organizational actors whose AIDs are **k-of-n weighted multisig**. Because
the KeyState must be **list-shaped and threshold-capable from v1**. A single
key is the 1-of-1 degenerate case. V1 supports independent AIDs only; it does
not reserve unchecked delegation metadata.

This spec freezes that shape. Everything in **The frozen surface** is protocol
surface per constitution principle III: it changes only by introducing a new
versioned identifier, never silently — even pre-deployment.

## Scope

In scope (this issue):

- The `KeyState` / `IdentityLeaf` types and their canonical CBOR layouts.
- `trie_key` derivation from inception material.
- The identity registry validator: standalone UTxO + thread token, MPF
  identity trie, sliding root window.
- **Inception** and **Rotation** operations, threshold-generalized from the
  singleton illustrations in `docs/architecture/identity-ops.md`.
- The read-only reference shape consumed by cage `Modify` (CIP-31), and the
  threshold-aware rework of #23's `OwnerAuth` that the list shape forces.

Out of scope, with stated boundaries:

- **Close, duplicity freeze, emergency freeze** — the same threshold
  generalization applies (signatures-meeting-threshold replace the single
  signature; emergency freeze reveals next-set members instead of the single
  next key), but implementation lands with the lifecycle ticket (#26). Their
  message layouts are constrained by this spec's KeySet commitments; see Open
  Questions Q6.
- **Legacy-leaf migration policy** (#26): leaves written under #23's
  singleton convention (`owner_aid → blake2b_256(owner_key)`) coexist with
  `IdentityLeaf` values until migrated. This spec defines the new leaf value
  only; the migration/coexistence policy is #26's deliverable.
- The detached-signature envelope (#39) — consumes `KeySet` verification
  defined here but specifies its own message.

## The frozen surface

### KeySet — the threshold shape

```aiken
pub type WeightedKeyDigest {
  key_digest : ByteArray   -- blake2b_256(qb64(pubkey)), 32 bytes —
                           -- KEL-aligned, see "KERI alignment"
  weight     : Int         -- >= 1
}

pub type KeySet {
  threshold : Int                     -- >= 1, <= sum(weights)
  keys      : List<WeightedKeyDigest> -- non-empty, no duplicate digests,
                                      -- length <= max_keys (Q2)
}
```

A `KeySet` stores **per-key digests, not raw keys**. Rationale:

1. **Consistency with #23.** The shipped convention
   (`specs/23-identity-auth/spec.md`, "Identity Trie Convention") already
   stores `blake2b_256(owner_key)` and has the redeemer supply the raw key
   with a preimage check. The list shape generalizes that pattern instead of
   introducing a second one.
2. **KEL recomputability at seq 0** (`docs/design/aid-model.md`, "Seq-0
   binding gap"). KERI inception events expose the *next* commitment as
   per-key digests plus a threshold — never raw next keys (verified: ToIP
   KERI spec, "Next key digest list field" — `n` is "a list of strings that
   are each a fully qualified digest of a public key"). If the Cardano
   commitment is a digest over `{threshold, per-key digests}`, an off-chain
   verifier can recompute it from public KEL data at seq 0. A digest over raw
   keys would be unverifiable until first rotation.
3. **Partial reveal at rotation.** Only the members that actually sign reveal
   their raw keys; the rest stay digest-committed (see Rotation).

Satisfaction rule (used by every operation):

> A set of signatures satisfies a `KeySet` iff each signature verifies under
> a raw key whose qualified digest — `blake2b_256(qb64(key))`, see "KERI
> alignment" — equals a distinct `key_digest` in the set,
> the signature list is indexed strictly increasing (no duplicates), and the
> sum of the matched `weight`s is `>= threshold`.

Well-formedness (enforced on-chain wherever a `KeySet` appears in clear —
inception `cur_set`, rotation reveal):

- `threshold >= 1`
- every `weight >= 1`
- `threshold <= sum(weights)` — otherwise the set is permanently
  unsatisfiable
- `keys` non-empty, no duplicate `key_digest` (duplicate digests would let
  one key's weight count twice)
- `length(keys) <= max_keys` (Q2)

### KERI alignment (v1, normative)

Verified against the ToIP KERI specification
(https://trustoverip.github.io/tswg-keri-specification/), 2026-07-07.

**Next commitment shape.** The KEL exposes the next commitment as the `n`
field — a list of fully qualified digests of public keys — plus the `nt`
threshold; never raw next keys ("Next key digest list field"). The seq-0
recomputability premise of this spec holds.

**Digest preimage.** A KEL next-key digest is computed over the **CESR
text-domain qualified form (qb64) of the public key, not its raw bytes**.
Established by cryptographically reproducing the spec's own worked example:
all three `n` entries of the example inception event equal
`E‑code(blake3_256(qb64(key)))`, and none equals
`E‑code(blake3_256(raw key))` (three exact-match test vectors). Therefore v1
defines

```
qb64(k)    = "D" ++ b64url(0x00 ++ k)[1..]    -- 44 ASCII chars, code "D"
key_digest = blake2b_256(qb64(k))
```

so that, under F-prefix (Blake2b-256) KEL digests, `key_digest` equals the
KEL `n` entry's raw digest value byte-for-byte, and `next_digest` is
recomputable from public KEL data at seq 0. A digest over raw key bytes
would break this permanently: at seq 0 the raw next keys are secret, so no
off-chain mapping could bridge the two digest families. On-chain preimage
checks (inception I4, rotation R4) reconstruct `qb64(raw_key)` from the
supplied raw key before digesting — a fixed 33-byte-to-44-char Base64url
encoding, constant cost per signature. The #23 pattern (digest committed,
raw key supplied per-operation with a preimage check) is unchanged; only the
preimage moves from the raw key to its qualified form.

**Threshold forms and the v1 mapping.** `kt`/`nt` are either a hex-encoded
non-negative integer, or a *fractionally weighted threshold*: a list of one
or more clauses of rational fractions, logically ANDed, each clause
satisfied when the weights corresponding to verified signatures sum to at
least 1; a weight may itself be a nested weighted list ("Fractionally
weighted threshold"). v1 maps the KERI subset onto `KeySet`
deterministically:

| KERI form | v1 `KeySet` |
|---|---|
| hex integer `m`, key list length `n` | `n` keys of weight 1, `threshold = m` |
| single clause `[f1..fn]`, no nesting, all `fi > 0` | reduce each `fi` to lowest terms, `L = lcm(denominators)`; `weight_i = fi·L`, `threshold = L`; no further reduction |
| multi-clause, nested, or zero weights | **out of v1 scope** — the SDK refuses to incept or mirror; clause support is a v2 `KeySet` shape behind a new version tag |

The single-clause mapping is exact (a clause sums to ≥ 1 iff the scaled
integer weights sum to ≥ L — rational arithmetic, no rounding) and canonical
(reduce-then-lcm makes `keyset_commit` independent of how the source wrote
equivalent fractions). Zero weights occur in KERI only in reserve/custodial
rotation patterns, which v1 also excludes (see the KERI subset restriction
under Rotation).

### KeySet commitment

```
keyset_commit(s) = blake2b_256(cbor(s))
```

where `cbor` is canonical CBOR per `docs/design/aid-model.md` ("CBOR
determinism"), and the bytes are produced by the *script's own serialization*
of the structured value — never accepted as caller-supplied opaque bytes
(kills encoding-malleability, see attack A8).

### KeyState and IdentityLeaf

```aiken
pub type KeyState {
  cur_set     : KeySet             -- current signing set, in clear (digest form)
  next_digest : ByteArray          -- keyset_commit(next KeySet), opaque until rotation
  seq         : Int                -- monotonic, starts at 0
  cesr_aid    : ByteArray          -- 32 bytes, metadata only, never verified on-chain
  deposit     : Lovelace           -- locked at inception, immutable
}

pub type IdentityLeaf {
  key_state : KeyState
  status    : Active | FrozenFatal(DuplicityProof) | Closed
}
```

Field rationale (nothing here is retrofittable):

- `cur_set` — in clear so that any verifier (rotation, cage `Modify`, #39
  envelope) resolves the live signing policy from an inclusion proof alone.
  Replaces the singleton `cur_pubkey` of `docs/design/aid-model.md`; the raw
  key is supplied per-operation in the redeemer with a preimage check
  (pattern from #23).
- `next_digest` — the pre-rotation commitment, now to a whole `KeySet`.
  Opaque on-chain; recomputable off-chain from public KEL data (`n` + next
  threshold) under the digest-agility mandate.
- `seq` — monotonic rotation counter; freeze-marker expiry and verifier
  resynchronization key on it (`docs/architecture/identity-ops.md`).
- `cesr_aid` — controller-asserted hint for off-chain correlation, exactly as
  in `docs/design/aid-model.md`; signed inside `inc_msg` to prevent front-run
  metadata poisoning, never verified on-chain.
- `deposit` — anti-spam bond, returned on Close, kept on `FrozenFatal`.

### trie_key derivation — v1, frozen

```
cur_commit = keyset_commit(cur_set)                    -- at inception
trie_key   = blake2b_256(cbor({
  domain      : "cardano-keri/trie-key/v1",
  cur_commit  : ByteArray[32],
  next_digest : ByteArray[32]
}))
```

Derived from inception material only; never changes across rotations
(stability property of `docs/design/aid-model.md`). The 1-of-1 singleton is
not special-cased: it is a `KeySet` with one key of weight 1 and threshold 1.

This supersedes the illustrative singleton derivation
`blake2b_256(cbor({cur_pubkey, next_digest}))` in `docs/design/aid-model.md`
in three ways: a domain tag is added, the key material is committed via
and `cur_commit` enters the preimage. The docs re-vet (#15) must
reconcile the docs to this normative layout.

**Versioning story (constitution III):** the domain tag
`cardano-keri/trie-key/v1` freezes this layout. Any change to `KeySet`,
`KeyState`-relevant commitments, or this preimage introduces
`.../trie-key/v2` alongside regenerated vectors; v1 identities remain
resolvable under v1 rules forever. The same applies to the operation message
tags below. The singleton layouts previously illustrated in
`docs/architecture/identity-ops.md` were never deployed; v1 as defined here
is the first deployed version and the docs are updated rather than a v2
minted (Q5 ratifies this).

## Registry UTxO

A standalone validator + thread token (minted once at registry genesis),
independent of any value cage:

```aiken
pub type RegistryDatum {
  identity_root : ByteArray        -- current MPF root of the identity trie
  root_window   : List<ByteArray>  -- sliding window of recent roots, depth 10
}
```

- Every operation spends the registry UTxO, applies one MPF update
  (`aiken-lang/merkle-patricia-forestry`), and pushes the new root onto the
  window (oldest dropped at depth) — window semantics per
  `docs/architecture/value-auth.md` ("Window root selection", depth 10).
- Value cages take the registry UTxO as a **CIP-31 reference input** and
  accept inclusion proofs against any root in the window.
- No oracle key appears anywhere in this validator. Liveness is
  permissionless: any party holding valid material can submit.

Cost shape: one operation = one MPF update against the registry trie —
O(log |identities|) hashing from proof depth, **independent of how many value
leaves the AID owns in any cage** (the issue's O(1) claim, made precise).

## Operations

Both messages are canonical CBOR with domain separation and full context
binding (network, registry policy, thread token) per
`docs/architecture/identity-ops.md`. Signatures are raw Ed25519 over the
message bytes as reconstructed by the script.

### Inception

Redeemer: `{ cur_set, next_digest, cesr_aid, absence_proof,
sigs: List<(Int, RawKey, Sig)> }`.

```
inc_msg = cbor({
  domain               : "cardano-keri/inception/v1",
  network_id           : NetworkId,
  registry_policy_id   : PolicyId,
  registry_thread_token: AssetName,
  trie_key             : ByteArray[32],
  cur_commit           : ByteArray[32],
  next_digest          : ByteArray[32],
  cesr_aid             : ByteArray[32],
  identity_root        : ByteArray[32]
})
```

On-chain checks:

1. `cur_set` well-formed (rules above); the attested inception event type is
   non-delegated `icp` (V1 rejects `dip`).
2. `trie_key` recomputed by the script from `keyset_commit(cur_set)`,
   `next_digest` — never taken from the redeemer.
3. Absence proof: `trie_key` not in the trie — any leaf, including `Closed`
   and `FrozenFatal` tombstones, blocks (re-)registration.
4. Signatures satisfy `cur_set` over `inc_msg` (satisfaction rule): each
   `(index, raw_key, sig)` has
   `blake2b_256(qb64(raw_key)) == keys[index].key_digest`,
   indices strictly increasing, `Ed25519.verify(raw_key, inc_msg, sig)`,
   matched weights sum `>= threshold`.
5. Deposit locked `>= deposit_amount`, recorded in `KeyState.deposit`.
6. Leaf inserted with `seq = 0`, `status = Active`; new root pushed onto the
   window.

### Rotation

Redeemer: `{ trie_key, inclusion_proof, reveal_set_digests : KeySet,
new_next_digest, seq_to, sigs: List<(Int, RawKey, Sig)> }`.

`reveal_set_digests` is the full pre-committed structure in digest form (the
preimage of `next_digest`); raw keys are supplied **only for the signing
indices** — partial reveal.

```
rot_msg = cbor({
  domain               : "cardano-keri/rotation/v1",
  network_id           : NetworkId,
  registry_policy_id   : PolicyId,
  registry_thread_token: AssetName,
  trie_key             : ByteArray[32],
  reveal_commit        : ByteArray[32],   -- keyset_commit(reveal_set_digests)
  new_next             : ByteArray[32],   -- keyset_commit of the new next KeySet
  seq_to               : Int
})
```

On-chain checks:

1. Inclusion proof: `trie_key → leaf` against the current `identity_root`,
   `leaf.status == Active`.
2. **Commitment reveal:** `keyset_commit(reveal_set_digests) ==
   leaf.key_state.next_digest`, and `reveal_set_digests` is well-formed
   (threshold/weight rules). A malformed pre-committed set is unrotatable —
   see attack A5.
3. `seq_to == leaf.key_state.seq + 1`.
4. Signatures satisfy `reveal_set_digests` over `rot_msg`: for each signing
   `(index, raw_key, sig)`, `blake2b_256(qb64(raw_key)) ==
   reveal_set_digests.keys[index].key_digest`, indices strictly increasing,
   Ed25519 verifies, weights sum `>= reveal_set_digests.threshold`. The
   threshold met is the one **pre-committed in the previous event** — the
   owner rotates under the policy they promised, and the signature binds the
   `new_next` the owner actually chose (the preimage check alone is not
   authorization: `docs/architecture/identity-ops.md`, rotation danger note).
5. `mpf.update` of the leaf: `cur_set = reveal_set_digests`,
   `next_digest = new_next`, `seq = seq_to`; `cesr_aid`, `deposit`,
   unchanged; new root pushed onto the window.

Pre-rotation preserved: theft of every raw current key (a full quorum) yields
neither the preimage of `next_digest` nor signatures under the next set.

**KERI subset restriction (verified: ToIP spec, "Indexed signatures";
"Partial, Reserve, and Custodial rotations").** A full KERI rotation event
must satisfy *two* thresholds — the prior next threshold over the prior next
key digest list *and* the new current signing threshold over the rotation
event's own key list, which KERI allows to differ from the pre-committed set
(reserve/custodial rotations may add keys or change weights at rotation
time). v1 pins `cur_set := reveal_set_digests` — the new current set *is*
the pre-committed set — so the two KERI thresholds coincide and check R4
satisfies both. Consequence: KELs using reserve/custodial rotation are
outside the v1 mirror scope; the SDK refuses them, like the threshold forms
excluded in "KERI alignment".

## Interaction with #23 (cage `Modify`)

`specs/23-identity-auth/spec.md` shipped a **singleton** identity convention:
`identity_root[owner_aid] = blake2b_256(owner_key)`, with `OwnerAuth`
carrying one raw key and one signature. This spec changes the leaf value to
`IdentityLeaf` (hash of its canonical CBOR as the MPF value), so `OwnerAuth`
must become threshold-aware in the same change:

```aiken
pub type OwnerAuth {
  owner_trie_key : ByteArray
  identity_proof : Proof                     -- identity_root[trie_key] = blake2b_256(cbor(leaf))
  leaf           : IdentityLeaf              -- supplied in clear, hash-checked
  sigs           : List<(Int, ByteArray, ByteArray)>  -- (index, raw key, sig)
}
```

Cage-side checks replace #23's steps 1–2: inclusion of the leaf value hash,
`status == Active`, and signatures satisfying `leaf.key_state.cur_set` over
the #23 value-write message (domain `cardano-keri/value-write/v1`,
unchanged). Freeze-marker checking stays as specified in
`docs/architecture/value-auth.md`.

This is a **breaking change to a merged spec's convention** before any
mainnet deployment; #23's spec gets a superseding note, per constitution I
(superseded analyses annotated, never deleted).

## Attack analysis

- **A1 — stolen full current quorum.** Attacker holds every current private
  key. Rotation requires the preimage structure of `next_digest` *and*
  signatures under next-set keys (check R2+R4): fails. Attacker can authorize
  value-writes until response; the owner's countermeasure is emergency freeze
  (next-key possession) then rotation — unchanged from
  `docs/architecture/identity-ops.md`, now with thresholds.
- **A2 — oracle censorship of rotation.** No oracle key is checked anywhere
  in the registry validator; any party can submit the rotation transaction.
  Censorship would require chain-level censorship. Demo obligation in
  acceptance.
- **A3 — rotation replay.** `rot_msg` binds network, registry policy id,
  thread token, `trie_key`, `seq_to`, and `new_next`. Same-registry replay
  fails on seq monotonicity (R3); cross-registry and cross-network replay
  fail on the bound identifiers; cross-protocol reuse fails on the domain
  tag.
- **A4 — threshold/weight edge cases.** Zero or negative weights, threshold
  0, `threshold > sum(weights)`, duplicate key digests, duplicate signature
  indices, empty key list — each rejected by well-formedness or the
  strictly-increasing-index rule, at inception (I1) and at reveal (R2).
- **A5 — malformed next commitment (self-brick).** `next_digest` is opaque at
  commitment time; a pre-committed set that is malformed (e.g.
  `threshold > sum(weights)`) is detected only at rotation, which then always
  fails — the identity can never rotate again (it can still Close). This is
  equivalent in severity to losing the next keys and is the owner's own
  failure; the off-chain SDK MUST validate the next set before committing.
  No on-chain mitigation exists without revealing the set early, which would
  destroy pre-rotation. Accepted risk, documented.
- **A6 — `next_digest` grinding / structure disclosure.** The commitment
  preimage (per-key digests + threshold) becomes public in the KEL by design
  (seq-0 recomputability). Knowing it yields nothing: satisfying a rotation
  still requires raw-key preimages of the digests and private-key signatures.
- **A7 — delegated-event confusion.** V1 registration rejects `dip`, and the
  advance path rejects `drt` / delegated recovery. A future delegated-AID
  version cannot be activated by supplying metadata to the V1 validator.
- **A8 — encoding malleability.** All hashed/signed material is serialized by
  the script from structured values (canonical CBOR); caller-supplied bytes
  are never hashed directly. Non-canonical encodings of the same logical set
  therefore cannot produce alternative commitments or signatures. MPF node
  domain separation per `docs/design/aid-model.md` covers the trie itself.
- **A9 — inception front-running / squatting.** Copying in-flight inception
  material requires reproducing threshold signatures over an `inc_msg` that
  binds `cesr_aid` and `trie_key`: collapses to key theft
  (`docs/design/aid-model.md`, front-run-proof property, unchanged by the
  list shape). First-party `cesr_aid` squatting remains defended off-chain
  only (KEL-derived resolution) — unchanged.
- **A10 — partial-reveal confusion.** A signer cannot claim another member's
  slot: the per-index preimage check binds each raw key to a specific
  committed digest, and indices are strictly increasing.
- **A11 — stale-root proofs at the cage.** A rotated-away `cur_set` remains
  provable against old roots for the window's lifetime (depth × write
  cadence). Accepted freshness floor per `docs/architecture/value-auth.md`;
  the emergency freeze registry (separate UTxO, checked alongside) covers the
  theft case inside that window.
- **A12 — registry contention griefing.** All identity ops serialize on one
  UTxO; an attacker can race honest rotations by spamming valid ops
  (inceptions cost a deposit; own-identity rotations are free). Effect is
  delay, not forgery. Mitigation is the MPFS snapshot-and-rebuild submission
  pattern (`docs/architecture/amaru-integration.md`) and, if griefing proves
  real, fee/deposit tuning — flagged, not solved here (Q4).

## Degenerate and migration cases

- **1-of-1 singleton:** one key, weight 1, threshold 1. All checks reduce to
  the singleton illustrations in `docs/architecture/identity-ops.md`; no
  special code path.
- **Legacy #23 leaves:** value bytes under the old convention hash
  differently from `IdentityLeaf` values; the two cannot be confused by
  construction. Coexistence/migration policy (End/GC restriction,
  legacy-leaf policy) is #26; this spec only guarantees the new value shape
  is disjoint.

## Acceptance criteria

Per constitution II, all cross-layer vectors come from `offchain`
`gen-vectors`; Aiken tests consume them verbatim.

1. A 2-of-3 weighted AID (weights 1/1/1, threshold 2) incepts, authorizes a
   cage leaf write (threshold `OwnerAuth`), and self-rotates — no oracle
   signature anywhere in the identity path (M1 demo #44 substrate).
2. Censorship demo: with the oracle offline, the rotation still lands.
3. Below-threshold signature sets rejected: 1-of-3 on inception, rotation,
   and cage write.
4. Edge-case rejections: duplicate signature index, duplicate key digest,
   threshold > sum(weights), delegated `dip` inception, wrong `seq_to`, reveal
   set not matching `next_digest`, signature by a revealed key over a
   mutated `new_next`.
5. Stolen-quorum demo: all three current raw keys sign a rotation attempt
   with attacker-chosen reveal material — rejected.
6. Tombstone check: re-inception at a `Closed`/`FrozenFatal` `trie_key`
   rejected by the absence proof.
7. O(1) evidence: rotation exec units measured with the AID owning 1 vs 100
   value-cage leaves — identical; and with registry populations 10 vs 1000 —
   growth only in MPF proof depth. Documented against PV3 limits, including
   max practical `KeySet` size (feeds Q2).

## Open questions

- **Q1 — KERI weighted-threshold mapping. RESOLVED (2026-07-07).** Verified
  against the ToIP KERI specification, including cryptographically
  reproducing the spec's worked next-key-digest examples. Results are
  normative in "KERI alignment": per-key digests + threshold confirmed; the
  digest preimage is the **qb64 qualified key** — this changed `key_digest`
  from `blake2b_256(raw)` to `blake2b_256(qb64(key))`; integer and
  single-clause fractional thresholds map exactly via reduce-then-lcm
  scaling; multi-clause, nested, and zero-weight forms plus
  reserve/custodial rotations are declared out of v1 scope. Residuals:
  (a) byte alignment of `n` entries requires F-prefix (Blake2b-256) KEL
  digests — the external gate already tracked as #42, now known to cover
  next-key digests as well as SAIDs; (b) the qb64-preimage convention was
  verified on E-prefix (Blake3) vectors and should be spot-checked for
  F-prefix codes in keripy/Signify when #41 lands.
- **Q2 — `max_keys` bound.** Needs the exec-unit measurement from acceptance
  item 7; proposal: freeze the bound in the validator (not just the SDK) so
  an over-long set cannot brick rotation against the budget.
- **Q3 — delegated-AID support — RESOLVED for V1.** V1 has no `delegator`
  field and rejects `dip` / `drt`. A future version must verify the immediate
  parent anchor and recursive trust chain; see
  `specs/68-keystate-shape/delegation-boundary-decision.md`.
- **Q4 — contention policy.** Whether registry griefing (A12) warrants
  batched identity ops or a per-op fee beyond the inception deposit —
  deferred until observed.
- **Q5 — version tags.** This spec assumes the never-deployed singleton
  layouts in `docs/architecture/identity-ops.md` are *updated in place* as
  `/v1` (docs re-vet #15) rather than minting `/v2` tags pre-deployment.
  Ratify.
- **Q6 — lifecycle ops threshold shape.** Close (current-set threshold) and
  emergency freeze (next-set partial reveal + threshold) follow directly from
  the satisfaction rule; confirm they land in #26 and that the freeze
  registry's `FreezeMarker.cur_pubkey_hash` field generalizes to
  `keyset_commit(cur_set)`.
