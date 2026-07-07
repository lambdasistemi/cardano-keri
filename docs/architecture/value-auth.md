# Value Authorization

A value-write operation mutates a leaf in a value cage MPFS trie. Every leaf
mutation requires **two authorizations**: the leaf owner's Ed25519
authorization against the identity registry key-state, and the cage oracle's
co-signature (necessary-not-sufficient — the oracle provides liveness and
cannot forge; see [Architecture Overview](overview.md#residual-oracle-trust-value-plane-only)).

The cage script resolves the authorizing identity by `trie_key` — the stable
identity handle derived at inception (see [AID Model](../design/aid-model.md)).

## Registry reference

The cage takes the identity registry UTxO (and the freeze registry UTxO) as
**CIP-31 reference inputs** (non-spending). The registry datum carries a
sliding window of valid roots. The cage accepts an inclusion proof valid
against any root in the window, tolerating registry write latency.

## Signer resolution

The cage resolves `cur_pubkey` by:

1. Verifying an MPFS inclusion proof `trie_key → leaf` against a root in the registry datum window
2. Checking `leaf.status == Active` — closed and frozen identities are rejected
3. Checking no active `FreezeMarker` for `trie_key` (absence proof against the freeze root; a marker is active while `marker.seq == key_state.seq` — see [Identity Operations — Emergency freeze](identity-ops.md#emergency-freeze))
4. Reading `leaf.key_state.cur_pubkey`

The CESR AID plays no role in on-chain authorization.

## Option A — Detached signature

The transaction redeemer carries the raw public key and a detached
[Ed25519](https://www.rfc-editor.org/rfc/rfc8032) signature over a
fully-bound authorization message. The AID owner need not sign the Cardano
transaction itself — the authorization travels as data.

**On-chain checks:**

1. Signer resolution above (Active + no freeze marker)
2. `vk == leaf.key_state.cur_pubkey`
3. `Ed25519.verify(vk, auth_msg, sig)`

**Authorization message:**

```
auth_msg = cbor({
  domain                     : "cardano-aid/value-write/v1",
  network_id                 : NetworkId,
  value_cage_policy_id       : PolicyId,
  value_cage_thread_token    : AssetName,
  trie_key                   : ByteArray[32],
  key_seq                    : Int,
  identity_root              : ByteArray,
  value_input_root           : ByteArray,
  value_output_root          : ByteArray,
  op_hash                    : ByteArray,
  counter                    : Int,
  valid_from                 : POSIXTime,
  valid_until                : POSIXTime
})
```

The message binds to the specific cage, the `trie_key`, the key sequence,
both MPFS roots, the operation, and a counter with validity window for replay
protection.

```mermaid
flowchart TD
    A["Redeemer: {trie_key, vk, sig, inclusion_proof, freeze_proof, auth_msg}"] --> B
    B["inclusion_proof valid for trie_key at some root in window?"]
    B -->|yes| C["leaf.status == Active and no active FreezeMarker?"]
    B -->|no| FAIL1["Fail: bad inclusion proof"]
    C -->|yes| D["vk == leaf.key_state.cur_pubkey?"]
    C -->|no| FAIL2["Fail: identity closed/frozen"]
    D -->|yes| E["Ed25519.verify(vk, auth_msg, sig)?"]
    D -->|no| FAIL3["Fail: key mismatch"]
    E -->|yes| F["Oracle co-signature + MPFS update valid?"]
    E -->|no| FAIL4["Fail: bad signature"]
    F -->|yes| OK["Value-write authorized"]
    F -->|no| FAIL5["Fail: oracle/trie op"]

    style OK fill:#1e3a2f,stroke:#4a9040,color:#e0e0e0
    style FAIL1 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL2 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL3 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL4 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL5 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
```

## Option B — Native signer

The AID owner signs the value-write transaction as a native Cardano
`extra_signatory`. The cage verifies `blake2b_224(cur_pubkey)` is a
transaction signatory.

**On-chain checks:**

1. Signer resolution above (Active + no freeze marker)
2. `blake2b_224(leaf.key_state.cur_pubkey) ∈ tx.extra_signatories`
3. Oracle co-signature + MPFS update valid

No app-level signature required. The ledger enforces that the named key
signed the transaction.

```mermaid
flowchart TD
    A["tx.extra_signatories + inclusion_proof + freeze_proof"] --> B
    B["inclusion_proof valid for trie_key at some root in window?"]
    B -->|yes| C["leaf.status == Active and no active FreezeMarker?"]
    B -->|no| FAIL1["Fail: bad inclusion proof"]
    C -->|yes| D["blake2b_224(cur_pubkey) ∈ extra_signatories?"]
    C -->|no| FAIL2["Fail: identity closed/frozen"]
    D -->|yes| E["Oracle co-signature + MPFS update valid?"]
    D -->|no| FAIL3["Fail: AID key not a signer"]
    E -->|yes| OK["Value-write authorized"]
    E -->|no| FAIL4["Fail: oracle/trie op"]

    style OK fill:#1e3a2f,stroke:#4a9040,color:#e0e0e0
    style FAIL1 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL2 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL3 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style FAIL4 fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
```

**Replay protection:** Cardano's UTxO model guarantees uniqueness — each
value-write spends and recreates the cage UTxO. No counter or validity
interval needed.

## Choosing the mode

The two options are not a preference ranking — each is **structurally
required** in different flows. The verifier library must expose both.

| Situation | Mode | Why |
|---|---|---|
| The AID owner signs the executing transaction (self-submitted cage writes, contract state transitions, delegation certificates) | **Option B** | Cheapest: no app-level signature, replay protection free from UTxO uniqueness |
| A third party signs the executing transaction (batcher-executed DEX orders, ceremony assemblers, any order/intent consumed later) | **Option A — the only option** | The owner's key is *not* among the transaction signatories; the authorization must travel inside the data, fully bound and validity-bounded |
| The AID key must stay isolated from any Cardano payment key (hardware custody constraints) | **Option A** | The key never signs a Cardano transaction |

!!! warning "Option B cannot cover the flagship use case"
    On batcher-model DEXes the trader never signs the executing transaction,
    so a required-signer check has nothing to find. Detached-signature
    authorization is part of the use-case-invariant core — see
    [Business Cases — factored core](../design/business-cases/index.md#the-factored-core-required-by-every-case)
    and the [Regulated DeFi case](../design/business-cases/regulated-defi.md).
    Where the actor does sign the transaction, Option B remains the cheaper
    path.

When Option A is used, the `auth_msg` counter and validity bounds are
required.

## Window root selection

The cage redeemer includes the specific root from the window used for the
inclusion proof. The cage script verifies that root is present in
`registry_datum.roots`. This makes the proof deterministic and auditable.

If the registry advances the root (new inception, rotation, close, or freeze)
between proof construction and tx inclusion, the old root may drop out of the
window. The proof must be recomputed against a root still in the window.
Window depth 10 gives strong liveness at typical registry write rates.
