# Spec: identity key-state UTxO + permissionless pre-rotation (list-shaped KeyState)

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
`trie_key` is derived from inception material and can never be retrofitted,
the KeyState must be **list-shaped and threshold-capable from v1**, with a
reserved `delegator` field. A single key is the 1-of-1 degenerate case.

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
  key_digest : ByteArray   -- blake2b_256(raw Ed25519 pubkey), 32 bytes
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
   per-key digests plus a threshold — never raw next keys. If the Cardano
   commitment is a digest over `{threshold, per-key digests}`, an off-chain
   verifier can recompute it from public KEL data at seq 0. A digest over raw
   keys would be unverifiable until first rotation.
3. **Partial reveal at rotation.** Only the members that actually sign reveal
   their raw keys; the rest stay digest-committed (see Rotation).

Satisfaction rule (used by every operation):

> A set of signatures satisfies a `KeySet` iff each signature verifies under
> a raw key whose `blake2b_256` equals a distinct `key_digest` in the set,
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
  delegator   : Option<ByteArray>  -- RESERVED: must be None in v1 (Q3)
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
- `delegator` — reserved for KERI delegated AIDs (vLEI pattern). It sits
  inside the `trie_key` preimage so that, when delegation is specified,
  delegated identities occupy a distinct key space by construction. In v1 it
  MUST be `None`: inception with `Some(_)` is rejected, and no v1 code path
  interprets it. Squatting on future semantics is thereby impossible (attack
  A7).
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
  next_digest : ByteArray[32],
  delegator   : Option<ByteArray>    -- None in v1, inside the preimage
}))
```

Derived from inception material only; never changes across rotations
(stability property of `docs/design/aid-model.md`). The 1-of-1 singleton is
not special-cased: it is a `KeySet` with one key of weight 1 and threshold 1.

This supersedes the illustrative singleton derivation
`blake2b_256(cbor({cur_pubkey, next_digest}))` in `docs/design/aid-model.md`
in three ways: a domain tag is added, the key material is committed via
`cur_commit`, and `delegator` enters the preimage. The docs re-vet (#15) must
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

Redeemer: `{ cur_set, next_digest, cesr_aid, delegator, absence_proof,
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
  delegator            : Option<ByteArray>,
  identity_root        : ByteArray[32]
})
```

On-chain checks:

1. `cur_set` well-formed (rules above); `delegator == None` (v1).
2. `trie_key` recomputed by the script from `keyset_commit(cur_set)`,
   `next_digest`, `delegator` — never taken from the redeemer.
3. Absence proof: `trie_key` not in the trie — any leaf, including `Closed`
   and `FrozenFatal` tombstones, blocks (re-)registration.
4. Signatures satisfy `cur_set` over `inc_msg` (satisfaction rule): each
   `(index, raw_key, sig)` has `blake2b_256(raw_key) == keys[index].key_digest`,
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
   `(index, raw_key, sig)`, `blake2b_256(raw_key) ==
   reveal_set_digests.keys[index].key_digest`, indices strictly increasing,
   Ed25519 verifies, weights sum `>= reveal_set_digests.threshold`. The
   threshold met is the one **pre-committed in the previous event** — the
   owner rotates under the policy they promised, and the signature binds the
   `new_next` the owner actually chose (the preimage check alone is not
   authorization: `docs/architecture/identity-ops.md`, rotation danger note).
5. `mpf.update` of the leaf: `cur_set = reveal_set_digests`,
   `next_digest = new_next`, `seq = seq_to`; `cesr_aid`, `deposit`,
   `delegator` unchanged; new root pushed onto the window.

Pre-rotation preserved: theft of every raw current key (a full quorum) yields
neither the preimage of `next_digest` nor signatures under the next set.

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
- **A7 — delegator squatting.** Inception with `delegator != None` is
  rejected in v1; the field is inside the `trie_key` preimage, so future
  delegated identities cannot collide with v1 identities.
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
   threshold > sum(weights), `delegator = Some(_)`, wrong `seq_to`, reveal
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

- **Q1 — KERI weighted-threshold mapping.** KERI expresses signing thresholds
  (`kt`/`nt`) including *fractional weighted* forms; this spec uses integer
  weights with an integer threshold. The bundled doc corpus has no KERI
  sources, so the exact KEL field semantics (per-key next digests, next
  threshold encoding) are stated here from design intent, **unverified
  against the KERI spec**. Before freezing v1: verify against
  https://trustoverip.github.io/tswg-keri-specification/ and decide the
  integer-weight mapping (e.g. common-denominator scaling) so the seq-0
  recomputability claim holds byte-for-byte.
- **Q2 — `max_keys` bound.** Needs the exec-unit measurement from acceptance
  item 7; proposal: freeze the bound in the validator (not just the SDK) so
  an over-long set cannot brick rotation against the budget.
- **Q3 — `delegator` content type.** Reserved as `Option<ByteArray>`; whether
  it will hold a delegator `trie_key` (32 bytes) or richer material affects
  nothing in v1 (must be `None`) but should be recorded when delegation is
  specified.
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
