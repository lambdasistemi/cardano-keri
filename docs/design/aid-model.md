# AID Cryptographic Model

!!! warning "`trie_key` / current-cage-auth here is the superseded Candidate-B lineage (#92)"
    Per `specs/92-checkpoint-contention/DECISION.md`, the `trie_key` / `KeyState` /
    current-cage-auth and `cesr_aid`-squatting-resolution material in this document is the
    **superseded Candidate-B lineage**. Live **current authority and discovery** are the
    **per-AID, AID-derived, quantity-one checkpoint token** — asset id
    `(checkpoint_policy_id, aid_asset_name)`, the sovereign per-AID checkpoint UTxO. The
    **genesis binding, front-run defense, and pre-rotation analysis below remain valid** and
    are unchanged.

## Two identifiers, two roles

Every registered identity has two identifiers that are always distinct:

| Identifier | Derivation | Where used | Verified on-chain? |
|---|---|---|---|
| `trie_key` | `blake2b_256(cbor({cur_pubkey, next_digest}))` | MPF trie key, cage auth | Yes |
| [CESR](https://github.com/WebOfTrust/ietf-cesr) AID | `blake3_256(cesr_inception_event)` (E prefix — the production KERI default) | KERI witnesses, Veridian | Genesis binding via the hash-proof minter (≤1024 B events); stored in the checkpoint datum |

The CESR AID is stored as the `cesr_aid` field inside the `KeyState` value at the `trie_key`. Off-chain tools correlate KERI identities to their on-chain state by scanning the trie metadata.

!!! warning "cesr_aid is an untrusted one-to-many index"
    `cesr_aid → trie_key` is **not** a lookup function. Multiple registrants can assert the same `cesr_aid` (first-party squatting). KERI's duplicity and watcher machinery does not fire on these — they are unrelated controllers, not conflicting events for the same controller. The only authoritative resolution is KEL-derived `trie_key` recomputation (see [Binding verification](../architecture/veridian-bridge.md#binding-verification-protocol)).

## trie_key derivation

```
trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))
```

This is the MPF key for the on-chain registry. It is derived from the same inception material as the CESR AID and uses [`blake2b_256`](https://www.rfc-editor.org/rfc/rfc7693) — a Cardano-native Plutus builtin.

**Stability:** The `trie_key` is derived from inception material only (`cur_pubkey` and `next_digest` from the very first event). It never changes across rotations. A cage holding a reference to a `trie_key` always refers to the same identity, regardless of how many times the key has rotated.

## KeyState

```
KeyState {
  cur_pubkey  : ByteArray[32]   -- current Ed25519 public key (raw bytes)
  next_digest : ByteArray[32]   -- blake2b_256(next pubkey), committed not yet revealed
  seq         : Int             -- monotonic rotation counter, starts at 0
  cesr_aid    : ByteArray[32]   -- decoded CESR AID, stored as metadata only
  deposit     : Lovelace        -- ADA locked at inception; immutable; returned on close
}
```

The trie leaf wraps `KeyState` with a lifecycle status:
`IdentityLeaf { key_state, status }` where status is `Active`, `FrozenFatal`
(duplicity tombstone), or `Closed` (exit tombstone) — see
[Identity Operations](../architecture/identity-ops.md).

!!! note "Scope change: list-shaped KeyState"
    The business-case analyses require `KeyState` to be list-shaped and
    threshold-capable from v1 (organizational AIDs are k-of-n multisig; a
    single key is the 1-of-1 degenerate case). V1 accepts independent AIDs only
    and has no passive `delegator` field; cooperative delegation is a versioned
    proof extension. The singleton shape above is the illustration. See the
    [factored core](business-cases/index.md#the-factored-core-required-by-every-case).

**Encoding note:** `cesr_aid` is typed as `ByteArray[32]` — the raw digest bytes after stripping the CESR derivation code. cardano-keri is E-native: the derivation code is always `E` (Blake3-256, the production KERI default) and is not stored separately.

`cur_pubkey` is the raw public key, stored on-chain. This differs from earlier designs that stored only a hash. Storing the raw key enables the on-chain script to verify `trie_key` derivation and Ed25519 signatures without requiring the caller to re-supply the key in the redeemer.

`next_digest` is opaque until rotation: the on-chain state commits to the hash of the next key before that key is ever used or revealed. This is the pre-rotation property.

`cesr_aid` is controller-asserted metadata. The script stores it but does not verify it against anything. Its sole purpose is to allow off-chain tools to find candidate `trie_key`s without scanning the full KERI KEL. Treat it as a hint, never as authoritative.

## Front-run-proof property

!!! danger "Why the CESR AID cannot be the trie key"
    If `trie_key = cesr_aid`, an adversary watching the mempool can copy the AID bytes from an in-flight inception transaction and submit their own inception transaction for the same AID with a different public key. Because the AID contains no key material, the on-chain script cannot distinguish the two registrations — whoever gets included first wins.

    With `trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))`, the adversary must supply the same `cur_pubkey` to derive the same `trie_key`. But possessing `cur_pubkey` alone is not enough to pass the Ed25519 self-auth check at inception — they also need the private key. The same private key that the legitimate registrant holds. Front-running collapses to key theft.

## Inception security: two attacks, different fixes

**Attack A — front-run metadata poisoning.** An adversary copies the victim's in-flight inception material (`cur_pubkey`, `next_digest`, `trie_key`) and submits first, substituting an attacker-chosen `cesr_aid`. Result: the victim's identity is registered under the wrong CESR prefix. **Fix:** include `cesr_aid` in `inc_msg` (the signed domain-separated message). The attacker cannot forge a signature over the victim's `cesr_aid` without the private key.

**Attack B — first-party squatting.** An adversary uses their own keys, produces a valid inception, and asserts a `cesr_aid` they do not control (a well-known KERI prefix). Signing `inc_msg` does nothing here — they are honestly signing their own inception with false metadata. Nor would on-chain derivation checking help: KERI inception events are public, so a squatter can always supply the victim's real event bytes and pass a `blake2b_256(event) == cesr_aid` check; binding the event to the *registrant* would require parsing CESR on-chain, which is out of scope by design. The authoritative defense is the off-chain KEL-derived resolution protocol — the bridge's authoritative identity is the `trie_key` recomputed from the real KEL, not the `cesr_aid` index.

cardano-keri is E-native: standard Blake3-256 (E-prefix) AIDs are supported as-is; genesis hash binding is verified by the hash-proof minter for events up to one blake3 chunk.

## Seq-0 binding gap

!!! warning "Superseded by the E-native contract (2026-07-16)"
    The digest-agility mandate below is dissolved: the checkpoint contract is
    now **E-native** — the datum's `next_keys` are the standard Blake3 KEL `n`
    entries byte-for-byte, so the seq-0 correspondence holds for unmodified
    production identities with no bridge mandate. The analysis is kept for the
    historical Candidate-B lineage only.

!!! danger "Pre-rotation identity is unverifiable without the digest agility mandate"
    At seq 0, the `next_pubkey` is secret (by design — it has not been revealed in a rotation yet). An off-chain verifier holding only the KEL has access to `cur_pubkey` (from the KEL's `k` field) but cannot reproduce `next_digest` without knowing `next_pubkey`.

    The bridge mandates Blake2b-256 digest agility so that the KERI `n` field and the Cardano `next_digest` are byte-for-byte equal. If this mandate is violated, the two commitments are incomparable from public data at seq 0, and a verifier cannot reconstruct `trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))` from the public KEL.

**Consequence:** a freshly-incepted, never-rotated identity is in a limbo state where the bridge binding is unverifiable for its entire pre-rotation lifetime. This is exactly when onboarding and authorization mistakes are most likely.

**Fix — digest agility alignment:** the Veridian bridge MUST mandate that KERI inception events use `blake2b_256` digest agility over the **same canonical next-key encoding** that Cardano hashes. Specifically:

```
KERI inception event: n = "ABCD..."  (base64url of blake2b_256(canonical_next_pubkey_bytes))
Cardano registry:     next_digest = blake2b_256(canonical_next_pubkey_bytes)
```

With this alignment, the KEL's `n` field (decoded from Base64) equals Cardano's `next_digest` byte-for-byte. The verifier can recompute `trie_key` from public KEL data at seq 0, making the binding immediately verifiable after inception.

This requirement must be enforced by the Veridian bridge SDK (it generates the KERI inception event). The on-chain script cannot verify it — it only sees `next_digest` as an opaque commitment. If the SDK violates the mandate, the binding is silently unverifiable until first rotation.

## Pre-rotation property

The pre-rotation property is: **a thief who obtains `cur_pubkey` (and its private key) cannot advance `seq`**.

To rotate, the attacker must produce `reveal_key` such that `blake2b_256(reveal_key) == next_digest`. This is a preimage problem on blake2b_256, assumed computationally infeasible.

The legitimate holder commits to `next_key` at inception (or at each rotation) and keeps `next_key` in cold storage. The rotation redeemer reveals it. Theft of `cur_key` alone is insufficient for rotation.

**What pre-rotation does NOT protect:**

- If `next_key` is compromised before it is used for rotation, the attacker can rotate and take over the identity. The owner's defense is to rotate first (race condition).
- If both `cur_key` and `next_key` are compromised simultaneously, the identity is lost with no on-chain recovery mechanism.
- After rotation reveals `next_key`, the window between submission and inclusion exposes `next_key` to mempool observers. Cardano's short slot time mitigates this but does not eliminate it.

## Continuous binding re-verification

!!! warning "Superseded framing (2026-07-09)"
    The two-machines premise below is retired by
    `specs/68-keystate-shape/identity-model.md` (PR #87): the Cardano key-state is an
    **on-chain checkpoint of the one witnessed KEL**, advanced only by witness-receipted
    anchoring seals. For a witnessed AID, a controller-only Cardano branch is rejected; the
    guarantee assumes an honest witness threshold and does not cover `toad = 0`. What
    *remains* to verify continuously is
    the **seal↔native key-state correspondence** (§7a, open thread 4): witnesses receipt
    events, not truth, so a controller can self-equivocate about her own keys across the
    two views. The per-rotation invariant below survives as that correspondence check
    (falsifiable, watcher-performable) — no longer as the only thing holding the bridge
    together. Note also the leaf is now keyed by `cesr_aid`, not the frozen `trie_key`
    preimage (the derivation below is the superseded #24-original shape). Extending this to
    #92 (`specs/92-checkpoint-contention/DECISION.md`): the `trie_key`-as-current-cage-auth
    framing (including the "cage auth" role in the two-identifier table above) is superseded
    — an AID's current authority is now its **own sovereign, per-AID, quantity-one
    uniquely-tokenized checkpoint UTxO** `(checkpoint_policy_id, aid_asset_name)` read as a
    CIP-31 reference input, discovered by a generic `(policy_id, asset_name)` asset lookup.
    The genesis-binding / front-run-defense material below is unaffected and stands.

**The bridge is two independently advancing pre-rotation state machines that share inception material.** On-chain, each registry (the Cardano key-state chain; the KERI KEL) is internally sound, but nothing on-chain forces Cardano rotations to track KERI rotations. The binding is established once at inception and must be re-proven off-chain at every rotation.

After seq 0, the Cardano chain and the KERI KEL can diverge while `cesr_aid` (carried forward unchanged) keeps asserting they represent the same identity. A verifier that stops watching accepts the divergence silently. A verifier that re-checks at each rotation can detect and reject a forked chain.

**Per-rotation invariant that verifiers must check:**

```
KEL.rotation[seq].cur_pubkey == Cardano.KeyState[seq].cur_pubkey
KEL.rotation[seq].next_digest_bytes == Cardano.KeyState[seq].next_digest
blake2b_256(cbor({cur_pubkey, next_digest})) == inception_trie_key   [unchanged]
KeyState[trie_key].cesr_aid == decoded(KEL.prefix)
```

This check is not a one-time event; it must be re-run at each rotation to confirm the two chains remain synchronized.

## CBOR determinism

All hashed and signed objects — inception material, `inc_msg`, `rot_msg`, `close_msg`, `freeze_msg`, `auth_msg` — must be encoded in canonical CBOR ([RFC 7049](https://www.rfc-editor.org/rfc/rfc7049) §3.9 / [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) §4.2). Specifically:

- Integer encoding must use the shortest form.
- Map keys must be sorted in canonical order (length-lexicographic).
- No indefinite-length encodings.
- No duplicate keys.

Non-canonical CBOR opens second-preimage attacks on the hash-then-sign construction.

## Domain separation

Every hashed or signed value must carry a unique domain tag to prevent cross-protocol signature reuse and type confusion.

| Object | Domain tag |
|---|---|
| Inception message | `"cardano-keri/inception/v1"` |
| Rotation message | `"cardano-keri/rotation/v1"` |
| Close message | `"cardano-keri/close/v1"` |
| Freeze message | `"cardano-keri/freeze/v1"` |
| Value-write auth (Option A) | `"cardano-keri/value-write/v1"` |
| MPF leaf node | `"mpf/leaf/v1"` (distinct from branch and empty) |
| MPF branch node | `"mpf/branch/v1"` |
| MPF empty node | `"mpf/empty/v1"` |

MPF node domain separation is foundational. Without distinct tags for leaf, branch, and empty nodes, a structural second-preimage attack is possible: a crafted trie with different structure but the same root hash. This breaks the collision resistance that absence and inclusion proofs rely on.
