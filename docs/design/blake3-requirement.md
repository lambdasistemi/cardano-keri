# Blake3 Plutus Builtin Requirement

## Two distinct gaps

The Blake3 requirement is often stated as a single gap, but there are actually two separate issues with different severities and different fix paths.

| Gap | What it blocks | Fix |
|---|---|---|
| CESR AID self-cert verification | On-chain proof that `cesr_aid = blake3(inception_event)` | Blake3 Plutus builtin or ZK proof |
| Next-key commitment chain | Seq-0 binding verifiable from KEL alone | Blake2b-256 digest agility in KERI (available now) |

## Gap 1: CESR AID self-cert

**For new F-prefix (Blake2b-256) AIDs, this gap is resolved.** If Veridian generates AIDs using Blake2b-256 digest agility (CESR `F` prefix), the full derivation chain is:

```
cesr_aid = blake2b_256(inception_event)   — Cardano has this builtin
next_digest = blake2b_256(next_pubkey)    — same
trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))  — same
```

All three steps use `blake2b_256`, a native Plutus builtin. The on-chain script can verify the full chain today, with no Plutus changes. This was demonstrated with a working CLI: https://github.com/lambdasistemi/cardano-keri-verify. The Veridian fix is a ~40-line change to `prefixer.ts` (branch: https://github.com/lambdasistemi/signify-ts/tree/feat/blake2b-256-prefix-derivation).

**For existing Blake3 (`E` prefix) AIDs**, the original gap remains:

KERI AIDs are derived as `blake3(inception_event)`. Cardano's Plutus VM has no [Blake3](https://github.com/BLAKE3-team/BLAKE3) builtin, so a script cannot verify that a presented `cesr_aid` is the correct derivation.

**Consequence for Blake3 AIDs:** the `cesr_aid` field in the Cardano registry is controller-asserted metadata. The squatting attack (Attack B) is irreducible without Blake3 — anyone can assert any CESR AID. Off-chain KEL replay is the only authoritative resolution.

**Fix for Blake3 AIDs:** Blake3 as a Plutus builtin (hard fork) or a ZK proof via BLS12-381. See below.

## Gap 2: Next-key commitment (soft, fixable now)

KERI uses **digest agility** — the hash algorithm used for the next-key commitment is encoded alongside the value in CESR. Blake3-256 is the current default (CESR prefix `E`) but the protocol explicitly supports other algorithms including [Blake2b-256](https://www.rfc-editor.org/rfc/rfc7693) (prefix `F`), SHA3-256 (`G`), and others.

Cardano already has `blake2b_256` as a native Plutus builtin. If the bridge mandates **Blake2b-256 digest agility** in KERI inception events, then:

```
KERI inception event: n = "F..." (base64url of blake2b_256(next_pubkey_bytes))
Cardano registry:     next_digest = blake2b_256(next_pubkey_bytes)
```

The KEL `n` field decoded equals Cardano's `next_digest` byte-for-byte. A verifier can recompute `trie_key` from the public KEL at seq 0 — the seq-0 binding gap closes completely, with no Plutus changes required.

**This is a SDK mandate, not a protocol change.** The Veridian bridge SDK generates the KERI inception event. It simply uses `F` prefix (Blake2b-256) instead of `E` prefix (Blake3) for the `n` field. KERI witnesses accept both — digest agility is a first-class KERI feature.

**What changes in the docs:**

The [Digest agility requirement](../architecture/veridian-bridge.md#digest-agility-requirement) is already correct in direction — it mandates blake2b_256 for the next-key commitment. That requirement is achievable today, with no dependency on any Plutus change.

## What Blake3 would unlock

With a Blake3 Plutus builtin, Gap 1 closes:

- On-chain verification: `blake3(canonical_cbor(inception_event)) == cesr_aid`
- `cesr_aid → trie_key` becomes a genuine on-chain lookup, not an untrusted index
- The CESR AID could serve as the trie key directly, eliminating the `trie_key` indirection
- Cardano-only applications can resolve KERI identity without touching the KERI network
- The super watcher burn transaction becomes fully trustless (KERI event bytes verifiable on-chain)

## Path to resolution

### Option 1 — Plutus Blake3 builtin (hard fork)

A CIP proposing a Blake3 Plutus builtin resolves Gap 1 completely. Blake3 is:
- Fast and parallelizable
- Already used by the KERI ecosystem as the default digest agility primitive
- A natural fit alongside the existing `blake2b_256` and `sha2_256` builtins

The on-chain verifier cost would be negligible. No trust assumptions. The clean long-term solution.

**Status:** no CIP exists for this as of 2026. The argument is straightforward: KERI interoperability requires Blake3 for full on-chain AID verification; the KERI ecosystem is a growing target for Cardano identity infrastructure.

### Option 2 — ZK proof (interim, available now)

[CIP-0381](https://cips.cardano.org/cip/CIP-0381) (BLS12-381 Plutus builtins) landed in PlutusV3 with Conway. BLS12-381 enables Groth16 and PLONK verifiers on-chain.

**The circuit:** prove `blake3(preimage) == cesr_aid` in zero knowledge. The Plutus script verifies the proof using BLS12-381 pairings.

**Tradeoffs:**

| | ZK proof (now) | Blake3 builtin (hard fork) |
|---|---|---|
| Availability | Now (Conway / PlutusV3) | Requires CIP + hard fork |
| On-chain verifier cost | ~100M execution units (estimate) | Negligible |
| Proof generation | Seconds on user device | N/A |
| Circuit complexity | High — Blake3 is bitwise-heavy | N/A |
| Trust assumption | None (PLONK) or trusted setup (Groth16) | None |

Blake3's bitwise operations make it a large circuit. PLONK avoids a trusted setup but the proof generation time and circuit size are non-trivial. Reasonable as an interim path if shipping before a Blake3 hard fork is a priority.

## What's buildable today

New Veridian identities created with F-prefix (Blake2b-256) derivation are fully Cardano-verifiable with no Plutus changes:

- `cesr_aid = blake2b_256(inception_event)` — verified by Cardano's builtin
- `next_digest = blake2b_256(next_pubkey)` — verified by Cardano's builtin
- `trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))` — verified by Cardano's builtin

The only blocker is that Veridian's `prefixer.ts` does not yet implement the `F` prefix (~40 lines). Fix branch: https://github.com/lambdasistemi/signify-ts/tree/feat/blake2b-256-prefix-derivation. The full chain was verified by CLI: https://github.com/lambdasistemi/cardano-keri-verify.

Existing Blake3 AID holders retain the squatting caveat until Blake3 lands in Plutus. The vLEI chain (GLEIF → QVI → LE) also requires GLEIF and QVIs to adopt F prefix for end-to-end on-chain verification.

## Current design position

| Capability | Status |
|---|---|
| Full on-chain verification for F-prefix (Blake2b-256) AIDs | **Available now** — no Plutus changes, just Veridian fix |
| Seq-0 binding verifiable from KEL | Available now — Blake2b-256 digest agility |
| Next-key commitment Cardano-verifiable | Available now |
| Full on-chain verification for existing Blake3 AIDs | Needs Blake3 builtin or ZK proof |
| Squatting attack eliminated for Blake3 AIDs | Needs Blake3 builtin or ZK proof |
| Super watcher burn fully trustless | Needs Blake3 builtin or ZK proof |
| vLEI chain fully on-chain (GLEIF→QVI→LE) | Needs GLEIF/QVI adoption of F prefix + Veridian fix |

The design is upgrade-compatible: if Blake3 lands as a Plutus builtin, the inception script can start verifying `cesr_aid` on-chain for existing Blake3 AIDs. Existing registry entries remain valid — the `cesr_aid` field is already stored.
