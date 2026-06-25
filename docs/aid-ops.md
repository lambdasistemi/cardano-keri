# AID Operations — Cryptographic Specification

This document describes the three on-chain AID operations and their
cryptographic bindings. It is the primary input for correctness vetting.

## Primitives available on-chain (Aiken / PlutusV3)

| Primitive | Function | Cost |
|---|---|---|
| [Ed25519](https://www.rfc-editor.org/rfc/rfc8032) signature verify | `verify_ed25519_signature(vk, msg, sig)` | ~1700 mem / ~900 cpu units |
| [Blake2b-256](https://www.rfc-editor.org/rfc/rfc7693) hash | `blake2b_256(bytes)` | ~1 mem unit per byte |
| Equality | `==` on ByteArray | cheap |

NOT available on-chain (unbounded / missing): SHA-3, secp256k1 schnorr (available but not used here), CESR parsing, list recursion over unbounded KEL.

## Core types

```
AID        : ByteArray[32]   -- self-certifying identifier
PubKey     : ByteArray[32]   -- Ed25519 public key
KeyDigest  : ByteArray[32]   -- blake2b_256(PubKey)
Seq        : Int              -- monotonic rotation counter (starts at 0)

KeyState {
  cur_digest  : KeyDigest    -- blake2b_256(current pubkey)
  next_digest : KeyDigest    -- blake2b_256(NEXT pubkey, pre-committed)
  seq         : Seq
}

InceptionEvent {
  cur_key     : PubKey       -- initial public key
  next_digest : KeyDigest    -- pre-committed hash of next key
}
```

## AID self-certification

```
AID = blake2b_256( cbor(InceptionEvent{ cur_key, next_digest }) )
```

The AID value IS the hash of the inception event. Anyone can verify the
binding offline without trusting any authority.

## Operation 1 — Inception

**Purpose:** Register a new AID and its initial key-state.

**Redeemer input:**
```
IncRedeemer {
  inception : InceptionEvent { cur_key, next_digest }
}
```

**On-chain checks (script):**
1. `blake2b_256( cbor(inception) ) == aid_from_datum` — self-cert binding
2. MPF absence proof: `aid` not yet in the identity trie (no double-registration)
3. Resulting key-state: `KeyState{ cur_digest = blake2b_256(cur_key), next_digest, seq = 0 }`

**No signature required**: the AID value itself is the proof of pre-image knowledge.

**Security claim**: An adversary who does not know `cur_key` cannot produce
a valid `InceptionEvent` whose hash matches a chosen AID. Pre-image
resistance of blake2b_256.

## Operation 2 — Rotation

**Purpose:** Rotate to the pre-committed next key.

**Redeemer input:**
```
RotRedeemer {
  reveal_key  : PubKey       -- the key whose digest was committed as next_digest
  new_next    : KeyDigest    -- digest of the key AFTER this rotation
  sig         : Signature    -- Ed25519(reveal_key, rot_msg)
}
```

**rot_msg (the signed message):**
```
rot_msg = cbor({ aid, seq: current_seq + 1, new_next })
```

**On-chain checks (script):**
1. `blake2b_256(reveal_key) == current_state.next_digest` — pre-rotation binding
2. `verify_ed25519_signature(reveal_key, rot_msg, sig)` — key possession
3. MPF inclusion proof: current `KeyState` is in the identity trie at `aid`
4. MPF update: replace `KeyState` with `KeyState{ cur_digest = blake2b_256(reveal_key), next_digest = new_next, seq = seq + 1 }`

**Security claim**: An adversary who stole `cur_key` cannot rotate forward
because `reveal_key` (the next key) was never revealed and its digest was
committed at inception. Stealing `cur_key` only lets the adversary transact
with the *current* key-state; it cannot advance the sequence.

## Operation 3 — Value-write (MPFS cage op)

**Purpose:** Authorize an MPFS operation (insert/delete/update a leaf) using
the AID key-state as authorization.

This is NOT an identity-registry operation. It happens in the MPFS value cage
script, which reads the identity UTxO as a CIP-31 reference input.

**Redeemer input (MPFS cage redeemer, augmented):**
```
AuthRedeemer {
  aid        : AID
  op         : MpfsOp         -- Insert | Delete | Update
  sig        : Signature      -- Ed25519(cur_key, auth_msg)
  id_proof   : MpfInclusionProof  -- proves aid→keyState in identity trie
}
```

**auth_msg:**
```
auth_msg = cbor({ aid, op, identity_root })
```
where `identity_root` is the MPF root of the identity UTxO (taken from the
reference input datum).

**On-chain checks (MPFS value cage script):**
1. Reference input has identity UTxO thread token (fixed policyId + assetName)
2. MPF inclusion proof: `id_proof` proves `aid → keyState` against `identity_root`
3. `blake2b_256(vk_from_tx_signatories) == keyState.cur_digest` — resolve signer
4. `verify_ed25519_signature(vk_from_tx_signatories, auth_msg, sig)` — key possession
5. `auth_msg` binds to current `identity_root` — anti-replay binding

**Security claim**: The `identity_root` in `auth_msg` ties the authorization
to the exact key-state snapshot used. A replayed signature from a previous
rotation cannot be re-used because `identity_root` would have changed.

## Questions for cryptographic vetting

1. **Inception replay**: Can an adversary register the same AID twice (before
   the first registration is confirmed on-chain, e.g. front-running)?

2. **Rotation replay**: Is `rot_msg = cbor({ aid, seq: seq+1, new_next })` a
   sufficient anti-replay binding? What if `new_next` collides?

3. **Value-write replay**: Does binding `auth_msg` to `identity_root` fully
   prevent replaying a signature across rotations? What if an MPF root
   collides or is predictable?

4. **Rotation after key compromise**: If `cur_key` is stolen, the attacker
   can sign with it but cannot advance the sequence. Can the attacker do
   anything else harmful (e.g. spam value-write ops, block legitimate
   rotation)?

5. **Inception event malleability**: Is `cbor(InceptionEvent)` deterministic
   across CBOR encoders? Should canonical CBOR be mandated?

6. **next_digest grinding**: Can an adversary grind `new_next` in a rotation
   redeemer to claim a useful AID as the "next" AID? (Is the AID namespace
   polluted by this?)

7. **Missing: inception self-auth**: Inception requires no signature. Is
   absence proof + hash pre-image sufficient, or should the registrant also
   sign the inception event to prove liveness?

8. **On-chain vs off-chain boundary**: What properties are guaranteed purely
   by on-chain checks, and what requires off-chain KEL replay? Is the
   boundary drawn correctly for the MPFS use case?
