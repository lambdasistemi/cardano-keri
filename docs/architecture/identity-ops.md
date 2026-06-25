# Identity Operations

There are four operations on the identity registry: inception, rotation, delete, and freeze. All are submitted by the oracle (company). Value-write authorization is covered in [Value Authorization](value-auth.md).

## Inception

Registers a new identity. Requires off-chain coordination between the user and oracle; not permissionless.

**Off-chain handover:**

1. User provides the oracle with: desired `name`, KERI KEL, and a self-auth signature
2. Oracle verifies the KEL is valid, derives `trie_key` from the inception event:
   ```
   trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))
   ```
3. Oracle submits the inception transaction

**Self-auth message — signed by user off-chain, verified on-chain:**

```
inc_auth_msg = cbor({
  domain     : "cardano-aid/inception/v1",
  name       : ByteArray,
  trie_key   : ByteArray[32],
  oracle_pkh : ByteArray[28],
  network_id : NetworkId
})
```

Binding `name` in the signed message prevents the oracle from registering the user under a different name. Binding `oracle_pkh` scopes the authorization to this specific registry.

**On-chain checks:**
1. Oracle key in `tx.signatories`
2. Absence proof: `name` not yet in trie
3. `Ed25519.verify(cur_pubkey, inc_auth_msg, user_sig)` — user consented to this registration
4. New root pushed onto sliding window (oldest dropped if over depth)

**Resulting leaf:**
```
name → IdentityLeaf {
  key_state: KeyState {
    cur_pubkey  = cur_pubkey
    next_digest = next_digest
    seq         = 0
    cesr_aid    = cesr_aid    -- metadata only, not verified
  }
  status: Active
}
```

```mermaid
sequenceDiagram
    participant U as User (Veridian)
    participant O as Oracle (company)
    participant N as Cardano Node
    participant S as Registry Script

    U->>U: Generate cur_pubkey, next_pubkey
    U->>U: next_digest = blake2b_256(next_pubkey)
    U->>U: trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))
    U->>U: inc_auth_msg = cbor({domain, name, trie_key, oracle_pkh, network_id})
    U->>U: user_sig = Ed25519.sign(cur_key, inc_auth_msg)
    U->>O: name + KEL + user_sig
    O->>O: Verify KEL, derive trie_key
    O->>N: Submit inception tx (oracle signs)
    N->>S: Execute registry script
    S->>S: Check oracle key in signatories
    S->>S: Check absence proof for name
    S->>S: Check Ed25519.verify(cur_pubkey, inc_auth_msg, user_sig)
    S->>S: Insert leaf, push new root to window
    S-->>O: Identity registered
```

## Rotation

The oracle mirrors a KERI rotation event on-chain. Only the oracle can submit rotations; the user has no direct Cardano write access after inception.

**Trigger:** oracle's KERI watcher observes a rotation event in the user's KEL. The event reveals `next_key` (now public) and commits to a new `new_next_key`.

**On-chain checks:**
1. Oracle key in `tx.signatories`
2. Inclusion proof: `name → leaf` where `leaf.status == Active`
3. `blake2b_256(reveal_key) == leaf.key_state.next_digest` — reveal binds to commitment
4. `seq_to == leaf.key_state.seq + 1` — monotonic

**Resulting leaf:**
```
name → IdentityLeaf {
  key_state: KeyState {
    cur_pubkey  = reveal_key
    next_digest = new_next_digest
    seq         = cur_state.seq + 1
    cesr_aid    = cur_state.cesr_aid   -- unchanged
  }
  status: Active
}
```

The oracle cannot fabricate a rotation: without knowing the preimage of `next_digest`, the check `blake2b_256(reveal_key) == next_digest` cannot be satisfied.

## Delete

Removes the identity from the registry. Used for normal offboarding (employee leaves the company). No fraud proof required.

**On-chain checks:**
1. Oracle key in `tx.signatories`
2. Inclusion proof: `name → leaf`
3. `name` removed from trie, new root pushed to window

## Freeze

Records a permanent duplicity proof in the trie leaf. The oracle submits this when it observes the user publishing two conflicting KERI rotation events at the same `seq` — a protocol violation that cannot be retracted.

**DuplicityProof:**
```
DuplicityProof {
  event_1 : ByteArray    -- first conflicting rotation event bytes
  sig_1   : ByteArray    -- Ed25519 signature over event_1
  event_2 : ByteArray    -- second conflicting rotation event bytes
  sig_2   : ByteArray    -- Ed25519 signature over event_2
  seq     : Int          -- sequence number at which the fork occurred
}
```

**On-chain checks:**
1. Oracle key in `tx.signatories`
2. Inclusion proof: `name → leaf` where `leaf.status == Active`
3. `proof.seq == leaf.key_state.seq`
4. `Ed25519.verify(leaf.key_state.cur_pubkey, proof.event_1, proof.sig_1)`
5. `Ed25519.verify(leaf.key_state.cur_pubkey, proof.event_2, proof.sig_2)`
6. `proof.event_1 != proof.event_2`
7. Leaf updated to `FrozenFatal(proof)`, new root pushed to window

**Resulting leaf:**
```
name → IdentityLeaf {
  key_state: <unchanged>
  status: FrozenFatal { event_1, sig_1, event_2, sig_2, seq }
}
```

There is no unfreeze path for `FrozenFatal`. The duplicity proof is permanently embedded in the trie and publicly inspectable. Value cages that encounter a `FrozenFatal` leaf reject the authorization.

The oracle must hold the key (DDoS protection) but cannot freeze without a machine-verifiable proof. An oracle that refuses to freeze a provably malicious identity has verifiably misbehaved — the proof is public.

## AID lifecycle

```mermaid
stateDiagram-v2
    [*] --> Active: Inception<br/>(oracle submits, user self-auth)
    Active --> Active: Rotation<br/>(oracle mirrors KEL)
    Active --> Deleted: Delete<br/>(oracle offboards)
    Active --> FrozenFatal: Freeze<br/>(oracle + DuplicityProof)
    Deleted --> [*]

    note right of FrozenFatal
        Leaf remains in trie as
        permanent audit record.
        All value-write auth rejected.
        No unfreeze path.
    end note
```
