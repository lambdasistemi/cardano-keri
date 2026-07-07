# Trust Model

## On-chain guarantees

The identity registry script enforces the following properties within a single block:

**AID uniqueness.** A `trie_key` can be registered at most once. The MPF absence proof at inception is validated against the current identity root. No two valid inception transactions for the same `trie_key` can both succeed.

**Pre-rotation binding.** A rotation is valid only if `blake2b_256(reveal_key) == cur_state.next_digest`. The on-chain state binds the next rotation to the key committed at the previous step. This cannot be circumvented without a preimage of blake2b_256.

**Monotonic sequence.** `seq` increases by exactly one per rotation. The on-chain script checks `seq_to == cur_state.seq + 1`. There is no skip or rollback.

**Key possession at rotation.** The rotation message is signed with `reveal_key`. The on-chain script verifies the Ed25519 signature. Possession of the hash alone is insufficient.

**Value-write authorization against a key-state snapshot.** The cage script reads the identity root from the CIP-31 reference input and checks the key-state at `trie_key` at that snapshot. The authorization is valid for the specific block in which the value-write is included.

## What is NOT on-chain

**Full KEL history.** The on-chain state holds only the current key-state. The full sequence of inception and rotation events is not stored or verified on-chain. There is no CESR encoding, no event receipt chain.

**CESR self-cert verification.** The registry stores `cesr_aid` as controller-asserted metadata and never verifies it. The `blake2b_256` builtin *could* hash supplied inception-event bytes (which is why cardano-aid requires F-prefix, Blake2b-256 AIDs — Blake3 AIDs are not supported), but doing so would prove nothing: inception events are public, so anyone can supply bytes that hash to a victim's AID. Binding is off-chain — see [Binding verification protocol](../architecture/veridian-bridge.md#binding-verification-protocol).

**KERI duplicity detection.** Detecting that a controller published conflicting KERI events is off-chain work (watchers, witness receipts). Once detected, the evidence *can* be recorded on-chain as a permanent [duplicity freeze](../architecture/identity-ops.md#duplicity-freeze); the proposed [super watcher](super-watcher.md) adds economic enforcement. The chain itself never observes KERI.

**Instant revocation of data-plane authority.** Closing or freezing an identity revokes value-write authority at the next root update — cages require `status == Active` plus freeze-registry absence — but a compromised `cur_key` retains value-write capability during the [synchronization lag](#synchronization-lag) window until the [emergency freeze](../architecture/identity-ops.md#emergency-freeze) or rotation lands.

**Next-key compromise before rotation.** If `next_key` is stolen before rotation, the on-chain state provides no protection. The response is to rotate before the attacker does (a race condition outside the protocol).

## CESR AID: metadata for correlation

The `cesr_aid` field in KeyState is the decoded CESR AID, stored unverified and carried forward through rotations for off-chain correlation. The F-prefix (Blake2b-256) requirement exists so that *off-chain* verifiers recompute the derivation with the same hash Cardano scripts use elsewhere — see [Blake2b-256 Requirement](blake2b256-requirement.md).

Off-chain correlation works as follows: given a CESR AID (e.g., `FKYLUMm...`), decode the base64url prefix to 32 bytes, scan KeyState values across the trie looking for a matching `cesr_aid` field, then use the associated `trie_key` for Cardano interactions.

The authoritative resolution is always the KEL-derived `trie_key` recomputation — the `cesr_aid` field is a convenience index. Multiple registrants can assert the same `cesr_aid` (first-party squatting); the binding verification protocol in `veridian-bridge.md` is the authoritative check.

## On/off-chain boundary

| Property | On-chain | Off-chain (future) |
|---|---|---|
| trie_key is unique | Yes — absence proof at inception | — |
| trie_key derivation is correct | Yes — blake2b_256 verified on-chain | — |
| CESR AID is correctly derived (F-prefix AIDs) | No — asserted metadata only | KEL replay + trie_key recomputation (needs Veridian F-prefix issuance) |
| Key was not stolen | No | KEL replay + watchers |
| Current key is the legitimate one | Yes — pre-rotation chain | — |
| CESR AID matches trie_key holder | No — asserted metadata only | KERI KEL + metadata scan |
| AID is not compromised | No | KERI duplicity detection |
| Value-write was authorized | Yes — against a key-state snapshot | — |
| Identity has not been closed or frozen | Yes — leaf status is part of the proven KeyState; freeze registry checked alongside | — |
| KEL is complete and un-forked | No | Witness receipts |
| Settlement is final | No | Praos/Genesis finality depth |
| Cardano state mirrors Veridian | No | Synchronization lag (~20s) |

## Synchronization lag

After a KERI rotation in Veridian, the Cardano registry still shows the old key until the rotation transaction settles (approximately 20 seconds at typical Cardano block times). During this window:

- KERI witnesses see the new key
- Cardano cage scripts see the old key

Applications that need consistency across both registries must account for this lag. The Cardano state is a mirror of Veridian, not a source of truth for KERI identity — Veridian governs.

## Relationship to KERI

cardano-aid borrows the pre-rotation primitive from [KERI](https://github.com/WebOfTrust/ietf-keri) (Key Event Receipt Infrastructure). It does not implement KERI. Specifically, there are no:

- Witnesses or backer receipts
- CESR encoding of the KEL
- Duplicity-evidence gossip
- Watcher/judge roles

The on-chain layer is a minimal root of trust. For applications that require the full KERI trust model, an off-chain KEL infrastructure must be built on top of cardano-aid, treating the on-chain state as the canonical current key-state anchor. The Cardano state mirrors Veridian — Cardano does not control KERI identity, it provides an additional on-chain binding for it.
