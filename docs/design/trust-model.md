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

**CESR self-cert verification.** Cardano cannot verify the [CESR](https://datatracker.ietf.org/doc/draft-ssmith-cesr/) AID self-certifying property. The CESR AID (`blake3(cesr_inception_event)`) is stored in KeyState as controller-asserted metadata — the registrant supplies it at inception and the script stores it without checking the [Blake3](https://github.com/BLAKE3-team/BLAKE3) derivation (no Plutus Blake3 builtin exists). The CESR self-cert is an off-chain guarantee only.

**Duplicity detection.** If an attacker and the legitimate holder both submit rotation transactions in the same block (or in competing forks), the chain will accept one and discard the other. There is no gossip or watcher network to detect and flag this.

**Revocation of data-plane authority after key compromise.** A tombstoned AID stops future rotations but does not revoke value-write authority for the current key. A compromised current key retains value-write capability until a revocation flag is added to KeyState and cage scripts are updated to check it.

**Next-key compromise before rotation.** If `next_key` is stolen before rotation, the on-chain state provides no protection. The response is to rotate before the attacker does (a race condition outside the protocol).

## CESR AID: controller-asserted metadata

The `cesr_aid` field in KeyState is asserted by the registrant at inception time. The on-chain script:

- Stores it in KeyState without verification
- Carries it forward unchanged through rotations
- Does not use it for any authorization check

Off-chain correlation works as follows: given a CESR AID (e.g., `EKYLUMm...`), decode the base64url prefix to 32 bytes, scan KeyState values across the trie looking for a matching `cesr_aid` field, then use the associated `trie_key` for Cardano interactions.

This is a one-way, non-authoritative mapping. A registrant could assert any `cesr_aid` value. The KERI KEL is the authoritative source for KERI identity — the on-chain `cesr_aid` is a convenience pointer.

## On/off-chain boundary

| Property | On-chain | Off-chain (future) |
|---|---|---|
| trie_key is unique | Yes — absence proof at inception | — |
| trie_key derivation is correct | Yes — blake2b_256 verified on-chain | — |
| CESR AID is correctly derived | No — Blake3 not available | KERI KEL replay |
| Key was not stolen | No | KEL replay + watchers |
| Current key is the legitimate one | Yes — pre-rotation chain | — |
| CESR AID matches trie_key holder | No — asserted metadata only | KERI KEL + metadata scan |
| AID is not compromised | No | KERI duplicity detection |
| Value-write was authorized | Yes — against a key-state snapshot | — |
| Identity has not been tombstoned | Yes — seq and next_digest checks | — |
| KEL is complete and un-forked | No | Witness receipts |
| Settlement is final | No | Praos/Genesis finality depth |
| Cardano state mirrors Veridian | No | Synchronization lag (~20s) |

## Synchronization lag

After a KERI rotation in Veridian, the Cardano registry still shows the old key until the rotation transaction settles (approximately 20 seconds at typical Cardano block times). During this window:

- KERI witnesses see the new key
- Cardano cage scripts see the old key

Applications that need consistency across both registries must account for this lag. The Cardano state is a mirror of Veridian, not a source of truth for KERI identity — Veridian governs.

## Relationship to KERI

cardano-aid borrows the pre-rotation primitive from [KERI](https://datatracker.ietf.org/doc/draft-ssmith-keri/) (Key Event Receipt Infrastructure). It does not implement KERI. Specifically, there are no:

- Witnesses or backer receipts
- CESR encoding of the KEL
- Duplicity-evidence gossip
- Watcher/judge roles

The on-chain layer is a minimal root of trust. For applications that require the full KERI trust model, an off-chain KEL infrastructure must be built on top of cardano-aid, treating the on-chain state as the canonical current key-state anchor. The Cardano state mirrors Veridian — Cardano does not control KERI identity, it provides an additional on-chain binding for it.
