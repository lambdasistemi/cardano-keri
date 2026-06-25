# vLEI Bridge: Legal Entity Identity on Cardano

## What is vLEI?

The [verifiable Legal Entity Identifier (vLEI)](https://www.gleif.org/en/organizational-identity/introducing-the-verifiable-lei-vlei) is [GLEIF's](https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei) extension of the traditional [Legal Entity Identifier (LEI)](https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei) into the world of cryptographic, self-certifying credentials. Where a classic LEI is a 20-character code assigned by a Local Operating Unit (LOU), a vLEI is a chain of [ACDC (Authentic Chained Data Containers)](https://github.com/WebOfTrust/ietf-acdc) credentials anchored to [KERI](https://github.com/WebOfTrust/ietf-keri) AIDs. Each credential in the chain is cryptographically signed and verifiable without consulting any central registry.

### The credential chain

GLEIF defines a strict four-level delegation hierarchy:

```
GLEIF Root AID
  └─ Qualified vLEI Issuer (QVI)
       └─ Legal Entity (LE)
            ├─ Official Organizational Role (OOR)
            └─ Engagement Context Role (ECR)
```

| Level | Issued by | Covers |
|---|---|---|
| GLEIF Root | GLEIF | Trust anchor — self-signed by GLEIF's AID |
| QVI | GLEIF | Qualified vLEI Issuers — accredited organizations |
| Legal Entity | QVI | Any legal entity holding an LEI |
| OOR | QVI on behalf of LE | Named officers: CEO, CFO, board member |
| ECR | LE (or QVI) | Role-in-context credentials for specific engagements |

Every credential in the chain is an ACDC. ACDCs are chained: the Legal Entity credential references the QVI credential, which references the GLEIF Root. A verifier walks the chain and checks each KERI KEL to confirm that the issuing AID has not been rotated away, revoked, or forked.

### Why it matters: regulatory obligations

Three regulatory frameworks are converging on machine-verifiable legal entity identity:

**[MiFID II](https://www.esma.europa.eu/regulation/trading/mifid-ii-and-mifir)** (Markets in Financial Instruments Directive) requires LEI codes on all financial transactions. vLEI extends this: instead of a human-readable code, the entity identity travels as a cryptographically signed credential in every transaction. Automated compliance becomes possible end-to-end.

**Basel III** (Bank for International Settlements counterparty risk framework) requires robust entity identification for counterparty exposure calculations. vLEI provides a non-repudiable, rotation-tracked proof of entity identity that survives mergers, re-incorporations, and key rotations.

**[eIDAS 2.0](https://digital-strategy.ec.europa.eu/en/policies/eudi-regulation)** (EU Digital Identity regulation, Regulation (EU) 2024/1183) mandates that EU member states provide digital identity wallets by end-2026. vLEI credentials issued to legal entities qualify as organizational identity credentials under the eIDAS 2.0 framework, bridging corporate and citizen identity.

---

## How cardano-aid is the bridge layer

A GLEIF vLEI Legal Entity credential is anchored to a KERI AID managed by the entity's authorized controllers. cardano-aid maps that KERI AID to a Cardano registry entry, creating a bilateral binding:

```
GLEIF vLEI chain (off-chain KERI)
  └─ Legal Entity AID
       └─ cesr_aid ←→ trie_key (Cardano registry)
                             └─ KeyState { cur_pubkey, next_digest, seq }
                                  └─ value cages (MPFS)
```

The binding is established at inception by the bridge's [digest agility mandate](../architecture/veridian-bridge.md#digest-agility-requirement): the KERI inception event's `n` field uses `blake2b_256` rather than the default Blake3, so the Cardano on-chain commitment and the KERI KEL commitment are byte-for-byte equal from day one.

Once registered, the legal entity's Cardano `trie_key` is stable across all subsequent key rotations. A Cardano smart contract that authorizes the entity at `trie_key` continues to work after the entity rotates its signing key — it reads the live `KeyState` from the registry reference input and sees the current `cur_pubkey`.

The bridge does not replace or duplicate the GLEIF infrastructure. GLEIF remains the root of trust for credential issuance. cardano-aid adds Cardano-specific guarantees on top: exact slot ordering, structural duplicity prevention, and smart contract composability.

---

## Four concrete use cases

### 1. Compliance-gated contracts

A DeFi protocol or securities issuance platform can gate entry to a value cage by checking the entity's `trie_key` against a registry of vLEI-verified entities. The cage script reads the identity registry via a CIP-31 reference input; no runtime oracle after admission is needed. The vLEI credential chain verification and cage admission are off-chain steps; once a `trie_key` is admitted, the cage enforces it on-chain without further oracle calls. Any entity whose KERI AID has been verified off-chain by the platform and whose `trie_key` has been admitted to the cage's authorization set can interact.

**What Cardano adds:** the gate check is atomic with the transaction. There is no race between the allowlist update and the transaction inclusion. The cage either sees the authorized key-state or it does not.

### 2. Non-censorable key history

An entity's complete Cardano key history — inception, every rotation, freeze events — is immutably recorded on-chain in slot order. No operator, including GLEIF or the QVI, can alter or suppress this record. A regulator or auditor can verify the entity's key custody chain from inception to the present without asking the entity or any intermediary.

This complements the KERI KEL: the on-chain record provides a second, independently ordered record that a super watcher can use to detect divergence (see [Super Watcher](super-watcher.md)).

### 3. Governance eligibility

On-chain governance protocols (CIP-1694-style or bespoke) can require vLEI-verified legal entity identity as a precondition for voting or proposal submission. The entity's `trie_key` serves as its governance handle. Voting weight or eligibility thresholds can be encoded in cage leaves authorized by the entity's signing key.

Entities can rotate their signing keys (for security) without losing their governance position — the `trie_key` is stable. A freeze event triggers automatic suspension of the entity's governance rights until the rotation settles, without requiring a governance council vote.

### 4. ACDC notarization on-chain

ACDC credentials (OOR, ECR) are issued by the QVI off-chain. Their content can be anchored to the Cardano chain by writing a credential hash into an MPFS value cage authorized by the Legal Entity's `trie_key`. This creates a timestamped, tamper-evident on-chain anchor:

```
ACDC credential hash  →  cage leaf
  ↑ signed by cur_pubkey (trie_key verified)
  ↑ slot-ordered in ledger
  ↑ immutable — cage leaf cannot be deleted without a further authorized write
```

A verifier checks: (a) the ACDC self-cert via KERI KEL replay; (b) the on-chain leaf exists and was written by the correct `trie_key`; (c) the `trie_key` is the one that maps to the issuer's KERI AID. All three checks are offline or cheap on-chain lookups. No GLEIF API call is needed at verification time.

---

## Gap table: what works now vs what needs Blake3

| Capability | Status | Blocker |
|---|---|---|
| Legal entity AID → Cardano registry binding | Available now | — |
| Seq-0 KEL binding verifiable offline | Available now | Digest agility mandate in SDK |
| Rotation tracked on-chain | Available now | — |
| Emergency freeze (next-key) | Available now | — |
| Compliance-gated cage writes | Available now | — |
| ACDC hash anchoring in cage | Available now | — |
| On-chain self-cert of CESR AID | Needs Blake3 or ZK proof | No Plutus Blake3 builtin |
| Squatting attack (Attack B) eliminated | Needs Blake3 or ZK proof | No Plutus Blake3 builtin |
| Super watcher burn fully trustless | Needs Blake3 or ZK proof | No Plutus Blake3 builtin |
| Cardano-only vLEI resolution (no KERI network) | Needs Blake3 | No Plutus Blake3 builtin |

The first five rows cover the core vLEI bridge use cases. They work today. The remaining rows are the reason to push for a Blake3 Plutus builtin CIP.

---

## The policy argument: vLEI strengthens the case for a Blake3 CIP

The [Blake3 requirement](blake3-requirement.md) page makes the cryptographic argument for adding Blake3 as a Plutus builtin. The vLEI use case adds a regulatory-weight policy argument.

KERI uses Blake3 as its default digest algorithm. Every KERI AID — including the AIDs that anchor GLEIF vLEI credentials — is derived as `blake3(inception_event)`. Without a Blake3 Plutus builtin:

- Cardano cannot verify on-chain that a `cesr_aid` value is the correct KERI identifier for a key.
- Applications requiring vLEI-grade assurance (MiFID II, Basel III, eIDAS 2.0 conformance) must rely on off-chain KERI infrastructure for the identity proof and use Cardano only for ordering and anchoring.
- A Blake3 CIP would allow Cardano to serve as a fully self-contained vLEI resolution layer: present the KERI inception event, verify the CESR AID derivation on-chain, proceed with the authorized cage operation. No KERI network dependency at verification time.

The growing adoption of vLEI for regulated financial and legal workflows — mandated by MiFID II and eIDAS 2.0 — represents a concrete, measurable target community for Cardano identity infrastructure. A CIP proposing Blake3 as a Plutus builtin can cite this demand directly.

---

[GLEIF vLEI page]: https://www.gleif.org/en/organizational-identity/introducing-the-verifiable-lei-vlei
[GLEIF LEI page]: https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei
[KERI IETF draft]: https://github.com/WebOfTrust/ietf-keri
[ACDC IETF draft]: https://github.com/WebOfTrust/ietf-acdc
[eIDAS 2.0]: https://digital-strategy.ec.europa.eu/en/policies/eudi-regulation
