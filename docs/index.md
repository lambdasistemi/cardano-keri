# cardano-aid

Self-certifying identities on Cardano, bridged to the Veridian / [KERI](https://github.com/WebOfTrust/ietf-keri) ecosystem.

**New here? Start with the [KERI primer](keri-primer.md)** — it explains what KERI is, how pre-rotation works, what Veridian is, and what Cardano adds.

---

## Implementation status

- **Shipped substrate:** MPFS plugin support. This is the concrete extension
  point for domain-specific value-cage authorization.
- **cardano-aid status:** research/design and prototypes for an MPFS identity
  plugin. The identity registry, freeze registry, super watcher, and
  Veridian/KERI bridge are not shipped runtime infrastructure in this repo.
- **Design target:** on-chain-verifiable key-state operations using
  `blake2b_256`, Ed25519, MPF proofs, and MPFS cage/plugin composition.

---

## The one idea

In the proposed identity plugin, inception commits to two things: the key you
use now, and the *hash* of the key you will use next. That commitment lives
on-chain. When you rotate, you reveal the pre-committed next key. A thief who
steals your current key cannot rotate your identity — they do not know the
pre-committed next key.

## Real-world use case: vLEI

cardano-aid explores an MPFS plugin bridge for [GLEIF vLEI](design/vlei.md) —
the cryptographic extension of the Legal Entity Identifier used for MiFID II,
Basel III, and eIDAS 2.0 compliance. In the design, a legal entity's KERI AID
(the root of its vLEI credential chain) maps to a stable Cardano `trie_key`,
enabling compliance-gated contracts, non-censorable key history, governance
eligibility, and on-chain ACDC notarization. See [vLEI Bridge](design/vlei.md)
for the full use-case analysis.

## Node-level attribution: the Amaru question

Where does cardano-aid sit relative to the proposed Veridian × Amaru node-level attribution work, what is still missing for full ACDC support (schema + revocation/TEL anchoring), and does anything actually need to live *inside* the node? See [Amaru Integration Analysis](architecture/amaru-integration.md).

That analysis also records the MPFS-side contention pattern: snapshot the cage
UTxO datum/value root for a value-write, then rebuild from a newer snapshot if
another write advances the cage before submission.

---

## Key derivation: trie_key vs CESR AID

Two separate identifiers exist for the same identity. They serve different roles.

```mermaid
flowchart LR
    A["cur_pubkey<br/>(Ed25519, 32 bytes)"] --> C["cbor({cur_pubkey, next_digest})"]
    B["next_digest<br/>blake2b_256(next_pubkey)"] --> C
    C --> D["blake2b_256"]
    D --> E["trie_key<br/>(Cardano on-chain key, 32 bytes)"]
    style E fill:#1e3a5f,stroke:#4a90d9,color:#e0e0e0

    A2["cesr_inception_event"] --> F["blake2b_256"]
    F --> G["CESR AID<br/>(KERI identifier, F-prefix, 32 bytes)"]
    style G fill:#3a2f1e,stroke:#d9a04a,color:#e0e0e0

    G -->|"stored as metadata<br/>in KeyState"| E
```

The **trie_key** is the [MPF](https://github.com/aiken-lang/merkle-patricia-forestry)
key used by the proposed on-chain registry — Cardano-verifiable,
front-run-proof, stable across rotations.

The **[CESR](https://github.com/WebOfTrust/ietf-cesr) AID** is the KERI-native identifier used by Veridian and KERI witnesses. cardano-aid requires F-prefix (Blake2b-256) AIDs, which Cardano can verify on-chain via the `blake2b_256` builtin. See [Blake2b-256 AID Requirement](design/blake2b256-requirement.md).

## System components

```mermaid
flowchart TD
    subgraph Chain
        IR["Identity Registry UTxO<br/>thread_token + identity_root<br/>MPF trie: trie_key → KeyState"]
        FR["Freeze Registry UTxO<br/>freeze_token + freeze_root<br/>emergency revocation"]
        VC0["Value Cage UTxO<br/>tx_in A + value_root A<br/>(pre-state)"]
        VC1["Value Cage UTxO<br/>tx_in B + value_root B<br/>(current after contention)"]
    end

    subgraph "MPFS Plugin / Sidecar Snapshot Cache"
        SnapA["Snapshot A<br/>tx_in A + value_root A"]
        SnapB["Snapshot B<br/>tx_in B + value_root B"]
        Build["Build value-write<br/>proof + unsigned tx"]
        Retry["Stale snapshot<br/>discard + rebuild"]
    end

    VC0 -->|"snapshot live cage pre-state"| SnapA
    SnapA --> Build
    Owner["AID Owner<br/>(cur_pubkey)"] -->|"authorizes"| ITX["Identity / freeze tx"]
    ITX -->|"rotation/inception<br/>(spends)"| IR
    ITX -->|"freeze<br/>(next_key authorized)"| FR
    Owner -->|"signs built tx"| VTX["Value-write tx"]
    Build -->|"built against snapshot"| VTX
    VTX -->|"tries to spend tx_in A"| VC0
    VC0 -->|"another write wins first<br/>spends A, recreates B"| VC1
    VTX -->|"tx_in A already spent"| Retry
    Retry -->|"read newer live cage"| SnapB
    VC1 -->|"snapshot current pre-state"| SnapB
    SnapB -->|"rebuild against B"| Build
    IR -->|"CIP-31 reference input"| VTX
    FR -->|"CIP-31 reference input"| VTX

    style IR fill:#1e3a5f,stroke:#4a90d9,color:#e0e0e0
    style FR fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style VC0 fill:#1e3a2f,stroke:#4a9040,color:#e0e0e0
    style VC1 fill:#1e3a2f,stroke:#4a9040,color:#e0e0e0
    style SnapA fill:#3a2f1e,stroke:#d9a04a,color:#e0e0e0
    style SnapB fill:#3a2f1e,stroke:#d9a04a,color:#e0e0e0
    style Retry fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
```
