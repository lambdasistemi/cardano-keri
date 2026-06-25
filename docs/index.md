# cardano-aid

Self-certifying identities on Cardano, bridged to the Veridian / [KERI](https://datatracker.ietf.org/doc/draft-ssmith-keri/) ecosystem.

**New here? Start with the [KERI primer](keri-primer.md)** — it explains what KERI is, how pre-rotation works, what Veridian is, and what Cardano adds.

---

## The one idea

At inception, you commit to two things: the key you use now, and the *hash* of the key you will use next. That commitment lives on-chain. When you rotate, you reveal the pre-committed next key. A thief who steals your current key cannot rotate your identity — they do not know the pre-committed next key.

## Real-world use case: vLEI

cardano-aid is the bridge layer for [GLEIF vLEI](design/vlei.md) — the cryptographic extension of the Legal Entity Identifier used for MiFID II, Basel III, and eIDAS 2.0 compliance. A legal entity's KERI AID (the root of its vLEI credential chain) maps to a stable Cardano `trie_key`, enabling compliance-gated contracts, non-censorable key history, governance eligibility, and on-chain ACDC notarization. See [vLEI Bridge](design/vlei.md) for the full use-case analysis.

---

## Key derivation: trie_key vs CESR AID

Two separate identifiers exist for the same identity. They serve different roles.

```mermaid
flowchart LR
    A["cur_pubkey\n(Ed25519, 32 bytes)"] --> C["cbor({cur_pubkey, next_digest})"]
    B["next_digest\nblake2b_256(next_pubkey)"] --> C
    C --> D["blake2b_256"]
    D --> E["trie_key\n(Cardano on-chain key, 32 bytes)"]
    style E fill:#1e3a5f,stroke:#4a90d9,color:#e0e0e0

    A2["cesr_inception_event"] --> F["blake3"]
    F --> G["CESR AID\n(KERI identifier, 32 bytes)"]
    style G fill:#3a2f1e,stroke:#d9a04a,color:#e0e0e0

    G -->|"stored as metadata\nin KeyState"| E
```

The **trie_key** is the [MPF](https://github.com/aiken-lang/merkle-patricia-forestry) key used in the on-chain registry — Cardano-verifiable, front-run-proof, stable across rotations.

The **[CESR](https://datatracker.ietf.org/doc/draft-ssmith-cesr/) AID** is the KERI-native identifier used by Veridian and KERI witnesses. Cardano cannot verify it today (no [Blake3](https://github.com/BLAKE3-team/BLAKE3) builtin). It is stored as metadata for off-chain KERI correlation. See [Blake3 requirement](design/blake3-requirement.md).

## System components

```mermaid
flowchart TD
    subgraph Chain
        IR["Identity Registry UTxO\nthread_token + identity_root\nMPF trie: trie_key → KeyState"]
        FR["Freeze Registry UTxO\nfreeze_token + freeze_root\nemergency revocation"]
        VC["Value Cage UTxO\ncage_thread_token + value_root\nMPF trie of domain data"]
    end

    Owner["AID Owner\n(cur_pubkey)"] -->|"signs tx"| TX["Transaction"]
    TX -->|"rotation/inception\n(spends)"| IR
    TX -->|"value-write\n(spends)"| VC
    TX -->|"freeze\n(next_key authorized)"| FR
    IR -->|"CIP-31 reference input"| VC
    FR -->|"CIP-31 reference input"| VC

    style IR fill:#1e3a5f,stroke:#4a90d9,color:#e0e0e0
    style FR fill:#3a1e1e,stroke:#d94a4a,color:#e0e0e0
    style VC fill:#1e3a2f,stroke:#4a9040,color:#e0e0e0
```
