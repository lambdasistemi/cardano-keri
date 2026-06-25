# Operational Constraints

## Contention model

The identity registry is a single UTxO per company. All oracle writes (inception, rotation, delete, freeze) spend and recreate it. This means at most one registry operation can land per block per registry.

**Why this is acceptable:**

- Only the oracle writes. There is no contention between independent users — a company's write rate is bounded by its employee onboarding and rotation cadence, not by adversarial flooding.
- The sliding window of roots in the registry datum absorbs oracle write latency for value-write consumers. A value-write built against `root_t-3` remains valid while that root is still in the window.
- Rotations are infrequent in practice. Key rotation in KERI is a deliberate act; the oracle mirrors these, not a continuous stream.

For very large deployments (thousands of concurrent rotations per day), the oracle can batch multiple updates into a single transaction using the MPFS `Modify` pattern.

## Sliding window depth

The window depth `k` is a registry deployment parameter. It trades liveness against datum size:

- Deeper window → value-writes survive more oracle writes between proof construction and tx inclusion
- Shallower window → smaller datum, cheaper reference input reads

Each root slot is 32 bytes. A window of depth 10 adds 320 bytes to the datum — negligible. Recommended default: **10**.

Since oracle writes are infrequent (inceptions and observed KERI rotations only), even a shallow window provides strong liveness guarantees in practice.

## Oracle operational requirements

The oracle must:

1. **Watch the KERI witness network** for each registered user's KEL — to detect rotation events and submit on-chain mirrors, and to detect duplicity events for freeze.
2. **Submit rotations promptly** — a stale on-chain key-state means value-write consumers see the wrong `cur_pubkey`. The oracle's latency is the liveness bound for key rotation.
3. **Maintain the oracle key securely** — the oracle key authorizes all trie writes. Compromise of the oracle key allows the attacker to delete or freeze any identity in the registry (but not forge key material, which requires user private keys).

The oracle does not need to be online for value-writes — those only reference the registry, not modify it.

## Name reassignment prohibition

The registry validator explicitly forbids updating the `trie_key` for an existing `name`. A leaf, once inserted, can only be rotated (KeyState updated, name unchanged), deleted, or frozen.

This means a name is permanently bound to the `trie_key` derived from the user's inception material for as long as the leaf exists. The company cannot silently redirect a name to a different identity.

If a name must be reassigned (e.g. a legal name change), the old leaf must be deleted and a new leaf inserted with the new `trie_key`. This requires the new identity to have been registered (the user must provide a new KEL and self-auth signature) and the old identity to be explicitly removed.

## Freeze model

Freeze is a one-way, permanent trie update. The `FrozenFatal` status embeds the duplicity proof directly in the leaf. Anyone can verify the proof by:

1. Reading the leaf from the trie (via inclusion proof against any window root)
2. Checking both Ed25519 signatures against the embedded `cur_pubkey`
3. Confirming `event_1 != event_2` and `seq` matches

The oracle cannot freeze without a valid proof. An oracle that holds a provably valid `DuplicityProof` and refuses to submit it has verifiably failed its operational duty — the proof is public and any auditor can see it.

## Deposit model

There is no ADA inception deposit in this design. The oracle controls membership; permissionless flooding is not possible. The oracle's operational costs (transaction fees) are borne by the company.

## Settlement depth

Applications that rely on the finality of a key-state or a spent value-write authorization must choose a settlement depth consistent with Cardano's Praos/Genesis finality guarantees. The registry does not specify this — it is a cage-level policy.

For high-value identity operations (legal identity binding), waiting for deep settlement is appropriate. The oracle's rotation latency should be factored into the settlement window.

## CESR AID metadata

`cesr_aid` is stored in `KeyState` as controller-asserted metadata. The registry script does not verify it against anything on-chain. Its purpose is to allow off-chain tools to correlate KERI identities to their on-chain state.

Treat `cesr_aid` as a hint, never as authoritative. The authoritative on-chain identity is the `name` in the trie and the `trie_key` derived from inception material.
