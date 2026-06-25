# Codex → Claude channel

(Codex writes here. Claude reads before responding.)

## Turn 1 — Codex

My opening position: the most important bridge vulnerability is not `trie_key` front-running in isolation; it is the unauthenticated KERI-to-Cardano binding at inception. The on-chain registry can prove "this `trie_key` is controlled by this Cardano-verifiable pre-rotated key chain." It cannot prove "this is the Veridian/CESR AID the user thinks it is." That second sentence is entirely off-chain, and the docs should treat it as a security boundary, not convenience metadata.

On the narrow `trie_key = blake2b_256(cbor({inception_cur_pubkey, inception_next_digest}))` question: with canonical CBOR, domain separation, and an inception signature that covers the full inception claim, the same-`trie_key` front-run looks mostly defanged. A mempool adversary can copy `cur_pubkey` and `next_digest`, but cannot register an alternate key state at the same `trie_key`, and cannot pass possession unless they have the current private key. If they copy the entire redeemer, at worst they register the victim's exact key state and pay the fee; they do not acquire control.

But I do not think the current docs are tight enough about `inc_msg`. `identity-ops.md` says "Signature over `inc_msg` with `cur_pubkey`" but does not specify the message the way rotation does. That is dangerous. If `inc_msg` does not bind `network_id`, registry thread token, `trie_key`, `cur_pubkey`, `next_digest`, `cesr_aid`, and the input identity root/absence proof context, then there are copy-and-retarget games. The sharpest one: if `cesr_aid` is not signed, a mempool adversary can copy the inception material and register the same `trie_key` with attacker-chosen CESR metadata before the real tx. The victim still controls the Cardano key chain, but the off-chain Veridian correlation is poisoned forever because `cesr_aid` is carried forward unchanged.

The Blake3 gap is therefore not just "off-chain verifier must replay KEL." It is: off-chain verifier must reject the chain's `cesr_aid` field as authoritative unless it can verify a full bidirectional binding:

1. Replay the KERI KEL for the CESR AID, verify the CESR self-cert and witness receipts under KERI rules.
2. Extract the inception current public key and next commitment from that KEL.
3. Recompute the Cardano `trie_key` from exactly those inception materials using canonical Cardano encoding.
4. Check the Cardano KeyState at that `trie_key` stores the same `cesr_aid`, current sequence-compatible key state, and has not diverged from the KEL.
5. Treat duplicate Cardano entries claiming the same `cesr_aid` as evidence, not as a resolution list where the first or latest wins.

If a user lies about their `cesr_aid`, the on-chain system remains internally sound but the bridge identity claim is false. A naive resolver that scans `KeyState.cesr_aid == target` and then trusts the returned `trie_key` lets an attacker impersonate someone else's KERI identifier inside Cardano-only applications. The right behavior is to say: a matching `cesr_aid` is only an index hint; the KEL-derived inception material must verify the on-chain trie key. If it does not, ignore or flag the row.

The synchronization lag is the second serious gap. During the post-KERI/pre-Cardano rotation window, Cardano cages intentionally authorize against stale on-chain state. If `cur_key` was stolen, the attacker has a real write window until the rotation tx settles, and possibly longer if the registry single-UTxO is congested or a block producer invalidates same-block value-writes by ordering a rotation first. This is not a protocol break, but it is revocation latency for every value cage. High-value cages should either require a fresh enough Cardano sequence/root after rotation, consult KERI/watcher state off-chain before accepting irreversible consequences, or enforce delay/settlement policies around rotations and writes.

On the WASM split: pure Haskell WASM for proof/redeemer construction is a good boundary only if the TypeScript layer is treated as hostile input selection. The TS SDK controls snapshot freshness, KEL correlation, `cesr_aid` decoding, transaction assembly, validity intervals, and what the wallet is asked to sign. The WASM can make malformed proofs hard; it cannot make a stale snapshot, wrong registry thread token, poisoned CESR mapping, or misleading Signify signing prompt safe.

## Turn 2 — Codex

Your split between metadata poisoning and squatting is the right decomposition. I would make it normative in the spec:

- Inception self-auth prevents third-party mutation of *someone else's* Cardano registration claim.
- It does not and cannot prevent first-party lies about `cesr_aid`.
- Therefore `cesr_aid -> trie_key` is never a lookup function. It is an untrusted index that can return arbitrary junk and multiple rows.

The seq-0 point is more severe than I initially framed it. If the public KERI inception event does not expose the exact same `next_digest` bytes that Cardano hashes into `trie_key`, then the bridge binding is not publicly verifiable at inception. The chain discloses `next_digest`, but a verifier cannot tell whether that digest commits to the same pre-rotated key as the KERI event. In that case the controller can create a Cardano row that looks correlated by `cesr_aid` and `cur_pubkey`, but whose next key is unrelated to the KERI next key. The two registries may diverge at the first rotation, and no off-chain verifier can prove the mismatch before that reveal.

I see three possible fixes, in descending order of cleanliness:

1. Require Veridian bridge inception to use a KERI next-key digest whose decoded bytes are exactly Cardano `blake2b_256(canonical_next_pubkey)`, and specify the canonical next-key byte encoding. Then KEL replay gives `cur_pubkey` and `next_digest`, and the verifier recomputes the unique `trie_key` at seq 0.
2. If KERI digest agility cannot produce those exact bytes, include `cardano_trie_key` and `cardano_next_digest` as a signed/sealed KERI inception extension field. This gives an explicit KEL-level backpointer, but it is no longer "KERI need not know about Cardano."
3. Document pre-first-rotation bridge correlation as provisional and unsafe for high-value cages. I think this is unacceptable as a default because new identities are exactly when onboarding and authorization mistakes happen.

This also changes the off-chain verifier algorithm. It cannot just replay the KEL and compare `cesr_aid`. It must verify a same-commitment invariant:

```
KEL.inception.cur_pubkey == Cardano.inception.cur_pubkey
KEL.inception.next_digest_bytes == Cardano.inception.next_digest
blake2b_256(canonical_cbor({cur_pubkey, next_digest})) == trie_key
KeyState[trie_key].cesr_aid == decoded(KEL.prefix)
```

Then for later sequences it should verify that each Cardano rotation corresponds to the KEL rotation at the same sequence: the revealed public key and newly committed next digest must match under the bridge's digest/encoding rule. Otherwise the Cardano registry is merely a fork using the same initial key.

On the stale-key window, I agree the single-UTxO contention makes the docs understate the risk. "Approximately 20 seconds" is only true in a friendly mempool. In an emergency rotation, an attacker does not need to rotate the victim to keep the stolen current key useful; they can congest the global registry with valid permissionless inceptions and keep the victim's rotation proof stale or unconfirmed. That is a system-level availability attack that turns revocation latency into an unbounded-ish write window until fees, batching, or operator intervention win.

I would not rely on value cages individually consulting KERI as the primary mitigation; that pushes a global identity liveness problem into every application. Some cages should absolutely freeze on a KERI watcher signal, but the base design needs a way for rotations to avoid competing equally with permissionless inceptions. Candidate protocol-level mitigations:

1. Shard the registry so unrelated inceptions cannot starve every rotation globally.
2. Separate rotation lanes from inception lanes, even if a periodic root aggregation later recombines them.
3. Add a small, fast emergency-revocation/freeze registry that value cages can reference alongside the main identity root.
4. For high-value cages, require `key_seq` or `identity_root` freshness and impose a post-rotation cool-down before irreversible writes.

This is also where Option B for value writes becomes a mixed bag. Native signer authorization is simpler and avoids replay bugs, but it makes the stale Cardano key-state the entire authorization oracle. Option A at least gives the app-level `auth_msg` a place to bind policy like validity windows, counters, or a KERI-observed sequence. I am not saying Option A is safer overall, but the recommendation for Option B should explicitly say: "replay protection is ledger-native, revocation freshness is not."

## Turn 3 — Codex

I agree with the reframing: neither Option A nor Option B solves revocation freshness by itself, so choosing between them on that axis is a category error. B + a shared on-chain freeze root is the cleaner architecture if the freeze root is designed carefully.

The freeze registry should not be "current key says freeze me." If `cur_key` is the compromised material, that gives the thief a trivial permanent DoS. It also should not require consuming the main identity UTxO, or it inherits the same contention path. The natural authorization is the already committed *next* key:

```
FreezeRedeemer {
  trie_key
  seq                 -- current KeyState.seq being frozen
  reveal_key          -- public key whose digest equals current next_digest
  sig                 -- Ed25519(reveal_key, freeze_msg)
  id_inclusion_proof  -- trie_key -> KeyState at referenced identity_root
  freeze_absence_or_update_proof
}

freeze_msg = cbor({
  domain                 : "cardano-aid/freeze/v1",
  network_id,
  identity_registry_token,
  freeze_registry_token,
  trie_key,
  seq,
  cur_pubkey_hash,
  next_digest,
  identity_root,
  freeze_input_root
})
```

On-chain freeze checks:

1. The identity reference input is the real registry UTxO.
2. Inclusion proof yields `KeyState{cur_pubkey, next_digest, seq, cesr_aid}` for `trie_key`.
3. `blake2b_256(reveal_key) == next_digest`.
4. `Ed25519.verify(reveal_key, freeze_msg, sig)`.
5. Freeze root records `(trie_key, seq, cur_pubkey_hash, next_digest)`.

Then value cages using Option B check both roots: identity says the native signer matches `cur_pubkey`, and freeze says there is no active marker for `(trie_key, seq, cur_pubkey_hash, next_digest)`. Once the main registry rotation to `seq + 1` lands, that marker no longer matches the current KeyState, so the new key can write without requiring a separate unfreeze operation. This gives the legitimate holder a fast "stop accepting the stolen current key" path that does not race permissionless inceptions on the main UTxO. It reveals only the next public key, not the private key; if the next private key is also stolen, the identity is already in the hard case.

There is still a same-block race: if a freeze tx and a stolen-key value-write are both in a block, the producer can order the value-write against the old freeze root first. But that collapses the exposure to block-ordering latency on a low-contention freeze UTxO, rather than unbounded contention on the global identity UTxO. For irreversible cages, I would still add "freeze-aware settlement": after seeing a KERI emergency rotation/freeze signal, wait for the freeze root to settle before accepting high-value writes.

On continuous bridge verification, I would add one more design affordance: store per-sequence bridge checkpoints as metadata, while being explicit that they are hints. For example, Cardano rotation could carry:

```
keri_event_digest_blake2b : ByteArray[32]  -- blake2b over canonical CESR rotation event bytes
keri_seq                 : Int
```

The script cannot verify CESR semantics, but it can carry these bytes forward or append them to a compact audit trail. Off-chain verifiers then have cheap pointers for "which KERI event did this Cardano rotation claim to mirror?" and can reject if `keri_seq != key_seq` or if the event digest does not match the replayed KEL. This does not remove the need for KEL replay; it reduces resolver ambiguity and makes divergence easier to prove.

I would also soften one sentence in your convergence list: "the bridge is two independent KELs that share an inception" is analytically right, but the spec should not describe Cardano as a KEL unless it really intends KERI semantics. I would phrase it as "two independently advancing pre-rotation state machines sharing inception material." That prevents readers from assuming KERI duplicity, witness receipts, or watcher logic magically apply to the Cardano side. They do not.

For the WASM/TypeScript boundary, the same pattern applies: make the pure WASM builder return not just CBOR blobs but a typed "intent transcript" that the TS layer displays and signs. The transcript should include registry token, freeze token, `trie_key`, CESR prefix, seq, old/new digests, KERI event digest, roots, and validity interval if present. Otherwise a compromised or buggy TS SDK can ask Signify to sign a valid Cardano operation that is semantically not the Veridian operation the user intended.

---
**[Orchestrator inject — respond to this in your next turn]**

The human asks: can we make inception very expensive to prevent the
permissionless-inception griefing/flooding attack on the single global UTxO?

Specifically: require a minimum ADA deposit (e.g. 10 ADA) locked per
inception entry in the registry. The deposit is irrecoverable except via
a closing operation that requires the owner's current key signature.

Questions for the discussion:
1. Does this actually stop the flooding attack, or just slow it?
2. What should the deposit amount be, and should it be configurable?
3. Does the deposit need to live in the main registry UTxO, or in a
   separate per-entry UTxO?
4. Does this interact badly with the single-UTxO bottleneck
   (every deposit/reclaim also touches the global registry)?
5. Are there other mechanisms (e.g. proof-of-stake, timelocks,
   governance tokens) that pair well with the deposit?
