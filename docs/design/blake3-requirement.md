# Blake3 Plutus Builtin Requirement

## Two distinct gaps

The Blake3 requirement is often stated as a single gap, but there are actually two separate issues with different severities and different fix paths.

| Gap | What it blocks | Fix |
|---|---|---|
| CESR AID self-cert verification | On-chain proof that `cesr_aid = blake3(inception_event)` | Blake3 Plutus builtin or ZK proof |
| Next-key commitment chain | Seq-0 binding verifiable from KEL alone | Blake2b-256 digest agility in KERI (available now) |

## Gap 1: CESR AID self-cert (hard, needs Blake3)

KERI AIDs are derived as `blake3(inception_event)`. This is what makes the CESR AID self-certifying — the identifier encodes the hash of the event that created it. Cardano's Plutus VM has no Blake3 builtin, so a script cannot verify that a presented `cesr_aid` is the correct derivation.

**Consequence:** the `cesr_aid` field in the Cardano registry is controller-asserted metadata. The squatting attack (Attack B) is irreducible without Blake3 — anyone can assert any CESR AID. Off-chain KEL replay is the only authoritative resolution.

**Fix:** Blake3 as a Plutus builtin (hard fork) or a ZK proof via BLS12-381. See below.

## Gap 2: Next-key commitment (soft, fixable now)

KERI uses **digest agility** — the hash algorithm used for the next-key commitment is encoded alongside the value in CESR. Blake3-256 is the current default (CESR prefix `E`) but the protocol explicitly supports other algorithms including Blake2b-256 (prefix `F`), SHA3-256 (`G`), and others.

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

CIP-0381 (BLS12-381 Plutus builtins) landed in PlutusV3 with Conway. BLS12-381 enables Groth16 and PLONK verifiers on-chain.

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

## Current design position

| Capability | Status |
|---|---|
| Seq-0 binding verifiable from KEL | Available now — Blake2b-256 digest agility mandate in SDK |
| Next-key commitment chain Cardano-verifiable | Available now — same |
| CESR AID self-cert on-chain | Needs Blake3 builtin or ZK proof |
| Squatting attack (Attack B) eliminated | Needs Blake3 builtin or ZK proof |
| Super watcher burn fully trustless | Needs Blake3 builtin or ZK proof |

The design is upgrade-compatible: if Blake3 lands as a Plutus builtin, the inception script can start verifying `cesr_aid` on-chain. Existing registry entries remain valid — the `cesr_aid` field is already stored.
