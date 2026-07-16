# Blake2b-256 AID Requirement

!!! warning "Retired — superseded by the E-native contract (2026-07-16)"
    cardano-keri is now **E-native**: standard Blake3 (`E`-prefix) AIDs are
    supported as-is, with in-script blake3 (spike #88 lane-packed core) on the
    rare genesis/rotation paths and raw-key verification on the authorization
    hot path. This document is kept as the archived rationale for the earlier
    F-prefix decision and as the cost record that motivated it.

cardano-keri **required** Blake2b-256 (CESR `F` prefix) AID derivation; Blake3 AIDs were not supported.

## Why Blake2b-256

`blake2b_256` is a native Plutus builtin. With F-prefix AIDs, the full derivation chain is on-chain verifiable today, with no Plutus changes:

```
cesr_aid    = blake2b_256(inception_event)    — Cardano builtin
next_digest = blake2b_256(next_pubkey)        — Cardano builtin
trie_key    = blake2b_256(cbor({cur_pubkey, next_digest}))  — Cardano builtin
```

All three steps use the same builtin. An on-chain script can verify the full chain. This was demonstrated with a working CLI: https://github.com/lambdasistemi/cardano-keri-verify.

## CESR F prefix

CESR (Composable Event Streaming Representation) encodes the hash algorithm alongside the value as a derivation code prefix. The `F` prefix denotes Blake2b-256 (RFC 7693). The qualified base64url value is 44 characters.

Example:

```
raw bytes (32):  f4a778e87cb3d6e9c9ab6e6b59a2b0e1e7c8d2f1a3b5c7d9e0f1a2b3c4d5e6f7
F-prefix qb64:   F9Kd46Hy026-mm5rm5orzh7x4tLxowtc2exeD7Gim3M
```

The KERI inception event's `n` (next-key digest) field carries this CESR-qualified value. Cardano stores only the raw 32 bytes after decoding.

## The Veridian fix

Veridian's `prefixer.ts` does not yet implement the `F` prefix. The fix is approximately 40 lines. Fix branch: https://github.com/lambdasistemi/signify-ts/tree/feat/blake2b-256-prefix-derivation.

Until this merges upstream, the cardano-keri SDK bridge must apply the patch when generating KERI inception events.

## Existing Blake3 AIDs

Veridian users with existing Blake3 (`E` prefix) AIDs cannot use cardano-keri with those identities. They must create a new identity using F-prefix derivation.

Blake3 as a Plutus builtin is not planned and not needed. cardano-keri is fully functional with Blake2b-256.
