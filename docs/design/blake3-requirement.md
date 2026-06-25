# Blake3 Plutus Builtin Requirement

## The gap

Cardano's Plutus VM does not include a Blake3 hash builtin. KERI AIDs are self-certifying identifiers derived as `blake3(cesr_inception_event)`. Without Blake3 on-chain, a Plutus script cannot verify that a presented `cesr_aid` value is the correct KERI self-certifying identifier for the presented key material.

**Consequence:** the `cesr_aid` field in the Cardano identity registry is controller-asserted metadata. Any party can register any `cesr_aid` value. The on-chain registry cannot be a proper KERI oracle — it is a Cardano-native pre-rotation key registry with off-chain KERI correlation.

## What Blake3 would unlock

With a Blake3 Plutus builtin, the inception script could verify:

```
blake3(canonical_cbor(inception_event)) == presented_cesr_aid
```

This would:
- Make `cesr_aid → trie_key` a genuine on-chain lookup (no squatting possible)
- Allow using the CESR AID directly as the trie key, eliminating the `trie_key` indirection
- Enable Cardano-only applications to resolve KERI identity without touching the KERI network
- Turn the registry into a proper on-chain KERI oracle

## Path to resolution

### Option 1 — Plutus Blake3 builtin (hard fork)

A CIP proposing a Blake3 Plutus builtin would resolve the gap completely. Blake3 is:
- Fast and parallelizable
- Already used by KERI ecosystem (KERI's default digest agility primitive)
- A natural fit alongside the existing blake2b_256 and sha2_256 builtins

The on-chain verifier cost would be negligible (same order as blake2b_256). No trust assumptions. No circuit complexity. This is the clean solution.

**Status:** no CIP exists for this as of 2026. Worth filing. The argument is straightforward: KERI interoperability requires Blake3; the KERI ecosystem is a large and growing target for Cardano identity infrastructure.

### Option 2 — ZK proof (interim, available now)

CIP-0381 (BLS12-381 Plutus builtins) landed in PlutusV3 with Conway. BLS12-381 enables Groth16 and PLONK verifiers on-chain without additional hard forks.

**The circuit:** prove `blake3(preimage) == cesr_aid` in zero knowledge. The Plutus script verifies the proof using BLS12-381 pairings — it never executes Blake3 itself.

**Tradeoffs:**

| | ZK proof (available now) | Blake3 builtin (needs hard fork) |
|---|---|---|
| Availability | Now (Conway / PlutusV3) | Requires CIP + hard fork |
| On-chain verifier cost | ~100M execution units (estimate) | Negligible |
| Proof generation | Seconds on user device | N/A |
| Circuit complexity | High — Blake3 is bitwise-heavy, poor ZK fit | N/A |
| Trust assumption | None (PLONK) or trusted setup (Groth16) | None |
| UX impact | Proof generation adds latency at inception | Transparent |

Blake3's bitwise operations (XOR, rotation, addition) make it a large circuit in any ZK system. A PLONK-based approach avoids a trusted setup but the proof generation time and circuit size are non-trivial. Groth16 is faster to prove but requires a trusted setup ceremony per circuit.

**Verdict:** the ZK route is technically feasible today but adds significant complexity for what is ultimately a hash function verification. It is a reasonable interim path if shipping before a Blake3 hard fork is a priority. The clean long-term solution is the builtin.

## Current design position

The `cardano-aid` registry is designed to work correctly without Blake3, with a documented limitation:

- Applications where both parties are Veridian users (they already have each other's KEL) are not affected — the KEL replay resolves the binding without on-chain Blake3.
- Applications that need to resolve KERI identity purely from Cardano state (no KERI network access) cannot be built securely until Blake3 lands or a ZK verifier is deployed.

The design is upgrade-compatible: if Blake3 lands as a Plutus builtin, the inception script can be updated to verify `cesr_aid` on-chain. Existing registry entries remain valid — the `cesr_aid` field is already stored; the script would simply start verifying it on new inceptions.
