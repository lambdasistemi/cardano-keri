# cardano-keri

Self-certifying identities on Cardano, bridged to the Veridian / [KERI](https://github.com/WebOfTrust/ietf-keri) ecosystem.

**New here? Start with the [KERI primer](keri-primer.md)** — it explains what KERI is, how pre-rotation works, what Veridian is, and what Cardano adds. Then the **[ACDC primer](acdc-primer.md)** covers the credential layer — how vLEI credentials chain, how revocation works, and how Cardano verifies a chain on-chain. For the financial and institutional concepts behind the use cases (securities, KYC/AML, custody, escrow, batchers…), see the **[Finance primer](finance-primer.md)**.

---

## Implementation status

- **Shipped substrate:** MPFS plugin support. This is the concrete extension
  point for domain-specific value-cage authorization.
- **cardano-keri status:** research/design and prototypes for an MPFS identity
  plugin. The identity registry, freeze registry, super watcher, and
  Veridian/KERI bridge are not shipped runtime infrastructure in this repo.
- **Security gates:** issue #99 hardened the value-cage validator's token and
  AID-ownership invariants — a unique thread token confined to its state output,
  a pinned migration predecessor, and an oracle that is necessary but not
  sufficient for AID authority. This is **one** completed security gate among the
  verification, hardening, bridge, and runtime work still required; it does not
  make the cage production- or mainnet-ready, and closing it does not lift the
  prototype label.
- **Design target:** on-chain-verifiable key-state operations using
  `blake2b_256`, Ed25519, MPF proofs, and MPFS cage/plugin composition.
- **Delivery plan:** see the [Roadmap](roadmap.md) — five milestones building
  the use-case-invariant core first (identity, verification, signing bridge),
  each closed by a vertical E2E demo, with the business-case adapters last.

---

## The one idea

In the proposed identity plugin, inception commits to two things: the key you
use now, and the *hash* of the key you will use next. That commitment lives
on-chain. When you rotate, you reveal the pre-committed next key. A thief who
steals your current key cannot rotate your identity — they do not know the
pre-committed next key.

## Real-world use case: vLEI

cardano-keri explores an MPFS plugin bridge for [GLEIF vLEI](design/vlei.md) —
the cryptographic extension of the Legal Entity Identifier, the entity ID
that MiFID II, Basel III, and eIDAS 2.0 already rely on for identification.
(Identity evidence, not compliance: nothing here satisfies AML, sanctions
screening, or reporting obligations by itself.) In the design, a legal
entity's KERI AID
(the root of its vLEI credential chain) maps to a stable Cardano `trie_key`,
enabling compliance-gated contracts, non-censorable key history, governance
eligibility, and on-chain ACDC notarization. See [vLEI Bridge](design/vlei.md)
for the full use-case analysis.

## Node-level attribution: the Amaru question

Where does cardano-keri sit relative to the proposed Veridian × Amaru node-level attribution work, what is still missing for full ACDC support (schema + revocation/TEL anchoring), and does anything actually need to live *inside* the node? See [Amaru Integration Analysis](architecture/amaru-integration.md).

That analysis also records the MPFS-side contention pattern: snapshot the cage
UTxO datum/value root for a value-write, then rebuild from a newer snapshot if
another write advances the cage before submission.

---

## Key derivation: the AID keys the checkpoint

One identifier keys the on-chain identity: the **CESR AID**. The former separate
`trie_key = blake2b_256(cbor({cur_pubkey, next_digest}))` derivation is superseded — the
identity leaf is keyed by `cesr_aid` and holds a KERI-shaped checkpoint, advanced only by
witness-receipted anchoring seals (`specs/68-keystate-shape/identity-model.md`, PR #87).

Its **physical current-authority store** is the **sovereign per-AID checkpoint UTxO** —
each AID's own `(checkpoint_policy_id, aid_asset_name)` UTxO (inline `CheckpointDatum`,
`delta = 0` rotation), discovered by a **generic `(policy_id, asset_name)` multi-asset
lookup**, **not** a shared `identity_root` registry with a sliding-root window (the
rejected Candidate B); see `specs/92-checkpoint-contention/DECISION.md`. The
`trie_key → KeyState` / `identity_root` framing in the **System components** mermaid below
is that superseded shared-registry shape; the mechanical re-cut is downstream #24, and the
**freeze registry** stays a shared, attacker-contendable UTxO (not sovereign).

**Indexer / discovery trust boundary.** The generic `(policy_id, asset_name)` index lookup
supplies **only a candidate outref / location for liveness — never identity or
current-authority truth**. The **consuming transaction validates** the returned UTxO against
the ledger: the exact **quantity-one policy + asset**; an **accepted checkpoint script /
version / lineage**; a **well-formed inline datum with the expected AID / sequence binding
and the current weighted key state**; and the **applicable active / freeze rules**
(validation rules, **not** datum fields). A **stale or false outref fails ledger validation**
(it no longer exists, or no longer matches) → refresh / retry; it can never yield forged
authority. An **indexer outage only blocks transaction construction (liveness)** — it never
grants false authority.

```mermaid
flowchart LR
    ICP["cesr_inception_event"] --> H["blake3<br/>(E-native, the production KERI default)"]
    H --> AID["cesr_aid<br/>(KERI identifier, 32 bytes)"]
    style AID fill:#3a2f1e,stroke:#d9a04a,color:#e0e0e0
    AID -->|"asset name"| CK["Checkpoint<br/>raw keys+weights · kt · next_keys/nt (blake3)<br/>witnesses · toad · seq"]
    style CK fill:#1e3a5f,stroke:#4a90d9,color:#e0e0e0
    SEAL["witnessed anchoring seal<br/>(canonical payload commitments)"] -->|"advance tx:<br/>seal + threshold receipts"| CK
```

The **[CESR](https://github.com/WebOfTrust/ietf-cesr) AID** is the KERI-native identifier
used by Veridian and KERI witnesses. Native **Blake3** AIDs are served as-is — the checkpoint stores the standard
KEL `n` digests byte-for-byte, so no digest-agility patch and no
Cardano-specific AID flavor exist. The genesis binding
`cesr_aid == blake3(icp_bytes)` is verified trustlessly by the hash-proof
minter for inception events up to one blake3 chunk (1024 B — every observed
production shape below GLEIF-Root scale); every later advance is cryptographic
via the dual-threshold reveal. The historical F-prefix option is retired — see
[Blake2b-256 AID Requirement](design/blake2b256-requirement.md) for the
archived rationale.

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
