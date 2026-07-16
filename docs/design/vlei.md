# vLEI Bridge: Legal Entity Identity on Cardano

## What is vLEI?

The [verifiable Legal Entity Identifier (vLEI)](https://www.gleif.org/en/organizational-identity/introducing-the-verifiable-lei-vlei) is [GLEIF's](https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei) extension of the traditional [Legal Entity Identifier (LEI)](https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei) into the world of cryptographic, self-certifying credentials. Where a classic LEI is a 20-character code assigned by a Local Operating Unit (LOU), a vLEI is a chain of [ACDC (Authentic Chained Data Containers)](https://github.com/WebOfTrust/ietf-acdc) credentials anchored to [KERI](https://github.com/WebOfTrust/ietf-keri) AIDs. Each credential in the chain is cryptographically signed and verifiable without consulting any central registry.

### The credential chain

GLEIF defines a strict credential-authority chain:

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

Every credential in the chain is an ACDC. ACDCs are chained: the Legal Entity
credential references the QVI credential, which terminates at the configured
GLEIF/QVI trust root. A verifier checks the issuance against the issuer's
**historical** KERI key state and checks TEL non-revocation at every credential
hop. Later issuer key rotation does not invalidate an issuance that was validly
anchored at that historical state.

### Credential authority is not KERI AID delegation

Two recursive relationships coexist but are not interchangeable:

- **ACDC authority chaining** is the GLEIF → QVI → LE → OOR/ECR credential
  graph above. It proves accreditation, legal-entity identity, and role
  authority.
- **KERI cooperative delegation** (`dip` / `drt`, with immediate parent `di`)
  lets a parent AID retain establishment authority over a child AID. Production
  QVI group AIDs are normally delegated from the GLEIF External AID, but LE and
  role-holder AIDs do not have to be delegated for their vLEI credentials to
  work.

The first Cardano checkpoint version (`CheckpointDatumV1`) accepts a
non-delegated inception (`icp`) only; it **rejects** a delegated inception
(`dip`) and delegated rotation (`drt`), and carries **no passive `di` /
`delegator` field**. A verifier that starts at the GLEIF Root must
eventually prove the recursive QVI delegation chain; a V1 verifier may instead
pin a QVI or GLEIF External AID as its disclosed trust root. The four current
dApp use cases require the ACDC relationship, not KERI-delegated acting AIDs.

### Why it matters: regulatory obligations

Three regulatory frameworks are converging on machine-verifiable legal entity identity:

**[MiFID II](https://eur-lex.europa.eu/eli/dir/2014/65/oj)** (Markets in Financial Instruments Directive) requires LEI codes on all financial transactions. vLEI extends this: instead of a human-readable code, the entity identity travels as a cryptographically signed credential in every transaction. Automated compliance becomes possible end-to-end.

**Basel III** (Bank for International Settlements counterparty risk framework) requires robust entity identification for counterparty exposure calculations. vLEI provides a non-repudiable, rotation-tracked proof of entity identity that survives mergers, re-incorporations, and key rotations.

**[eIDAS 2.0](https://digital-strategy.ec.europa.eu/en/policies/eudi-regulation)** (EU Digital Identity regulation, Regulation (EU) 2024/1183) mandates that EU member states provide digital identity wallets by end-2026. vLEI credentials issued to legal entities qualify as organizational identity credentials under the eIDAS 2.0 framework, bridging corporate and citizen identity.

!!! warning "Identity evidence, not compliance"
    These frameworks establish that machine-verifiable *entity
    identification* is what regulators run on. vLEI — and anything built on
    it here — provides cryptographic evidence of legal-entity identity, role,
    and authority. It does not by itself satisfy AML, sanctions screening,
    transaction reporting, suitability, or market-abuse obligations, and
    none of these frameworks mandates gating. Any stronger regulatory claim
    in these docs requires an article-level citation first — see
    [The Regulated DeFi Gate — honest limits](defi-gate.md#what-the-gate-is-not).

---

## How cardano-keri is the bridge layer

A GLEIF vLEI Legal Entity credential is anchored to a KERI AID managed by the entity's authorized controllers. cardano-keri gives that KERI AID a Cardano presence through its **sovereign per-AID checkpoint** — a quantity-one checkpoint token whose asset name is derived from the AID — creating a bilateral binding:

```
GLEIF vLEI chain (off-chain KERI)
  └─ Legal Entity AID  (the stable identity handle)
       └─ aid_asset_name = deriveAidAssetName(cesr_aid)
            └─ quantity-one per-AID checkpoint UTxO (checkpoint_policy_id, aid_asset_name)
                 └─ CheckpointDatumV1 { cur_keys, cur_threshold, next_keys, next_threshold, seq }
                      └─ value cages (MPFS)
```

The binding needs no digest-agility mandate: the contract is E-native, so the checkpoint datum stores the standard Blake3 KEL `n` entries and the Cardano on-chain commitment equals the KERI KEL commitment byte-for-byte from day one, for unmodified production identities.

Once registered, the legal entity's **qualified KERI AID — and the checkpoint asset name derived from it — is the stable handle** across all subsequent key rotations. A Cardano smart contract that authorizes the entity resolves the AID's quantity-one checkpoint UTxO generically by `(checkpoint_policy_id, aid_asset_name)` as a CIP-31 reference input and reads the **current weighted keys/threshold** from its `CheckpointDatumV1`. It keeps working after the entity rotates its signing keys: the checkpoint token name never changes, while the checkpoint it locates advances to the new key-state.

The bridge does not replace or duplicate the GLEIF infrastructure. GLEIF remains the root of trust for credential issuance. cardano-keri adds Cardano-specific guarantees on top: exact slot ordering, structural duplicity prevention, and smart contract composability.

---

## Four concrete use cases

### 1. Compliance-gated contracts

A DeFi protocol or securities issuance platform can gate entry to a value cage by checking the entity's **AID** against a registry of vLEI-verified entities. The cage resolves the entity's current authority from its **quantity-one per-AID checkpoint** via a CIP-31 reference input keyed by `(checkpoint_policy_id, aid_asset_name)`; the credential-admission allowlist is a separate historical cache, never the current-authority lookup. The vLEI credential chain verification and admission are off-chain steps; once an entity's **AID** is admitted, the cage enforces its current checkpoint key-state on-chain without further oracle calls. Any entity whose KERI AID has been verified off-chain by the platform and admitted to the cage's authorization set can interact.

**What Cardano adds:** the gate check is atomic with the transaction. There is no race between the allowlist update and the transaction inclusion. The cage either sees the authorized key-state or it does not.

This use case has a dedicated primer — [The Regulated DeFi Gate](defi-gate.md) — covering the incumbent allowlist pattern, the full gate flow (on-chain admission rather than the off-chain admission described above), cardano-keri's bounded role, and the honest limits of gating.

### 2. Non-censorable key history

An entity's complete Cardano key history — inception, every rotation, freeze events — is immutably recorded on-chain in slot order. No operator, including GLEIF or the QVI, can alter or suppress this record. A regulator or auditor can verify the entity's key custody chain from inception to the present without asking the entity or any intermediary.

This complements the KERI KEL: the on-chain record is a globally ordered, spend-linearized **projection of current authority** that a super watcher **relays and evidences** — not a second, independently sovereign identity history. Identity is KERI-sovereign (one witnessed KEL); the checkpoint cannot fork, it can only lag, so the super watcher relays valid anchoring transitions and submits duplicity / correspondence proofs rather than policing divergence between two rival records (see [Super Watcher](super-watcher.md)).

### 3. Governance eligibility

On-chain governance protocols (CIP-1694-style or bespoke) can require vLEI-verified legal entity identity as a precondition for voting or proposal submission. The entity's **qualified AID** serves as its governance handle. Voting weight or eligibility thresholds can be encoded in cage leaves authorized by the keys meeting the AID's **current checkpoint threshold**.

Entities can rotate their signing keys (for security) without losing their governance position — the **AID (and its checkpoint asset name) is stable**, while the checkpoint it locates advances to the new keys. A freeze event triggers automatic suspension of the entity's governance rights until the rotation settles, without requiring a governance council vote.

### 4. ACDC notarization on-chain

ACDC credentials (OOR, ECR) are issued by the QVI off-chain. Their content can be anchored to the Cardano chain by writing a credential hash into an MPFS value cage authorized by the Legal Entity's **AID checkpoint** (its current weighted keys/threshold). This creates a timestamped, tamper-evident on-chain anchor:

```
ACDC credential hash  →  cage leaf
  ↑ signed by keys meeting the AID's current checkpoint threshold
  ↑ slot-ordered in ledger
  ↑ immutable — cage leaf cannot be deleted without a further authorized write
```

A verifier checks: (a) the ACDC self-cert via KERI KEL replay; (b) the on-chain leaf exists and was written under the issuer AID's current checkpoint authority; (c) the checkpoint asset resolves to the issuer's KERI AID (`aid_asset_name = deriveAidAssetName(cesr_aid)`). All three checks are offline or cheap on-chain lookups. No GLEIF API call is needed at verification time.

---

!!! note "Identity requirement"
    cardano-keri is **E-native**: standard Blake3 (E-prefix) KERI AIDs — the
    Veridian and vLEI production default — register as-is. No re-issuance, no
    Cardano-specific AID flavor.

## Gap table

Status is milestone-based — see the [Roadmap](../roadmap.md). Nothing below is
shipped runtime infrastructure yet (see the
[implementation status](../index.md#implementation-status)); "designed" means
the cryptographic path exists and the work is scheduled.

| Capability | Status |
|---|---|
| Seq-0 binding verifiable from KEL | Native: the datum stores the KEL `n` digests byte-for-byte; genesis `blake3(icp) == cesr_aid` is verified trustlessly by the hash-proof minter for events up to one blake3 chunk (1024 B — covers the full V1 target population; only GLEIF-Root-scale 6+-key boards exceed it) |
| Full on-chain AID self-cert | E-native: hash-proof minter at genesis (spike #88 lane-packed core, ≤1024 B single-tx); rotations pay one single-block blake3 per revealing key (measured 3.6% cpu / 4.5% mem); plain authorizations verify raw keys — zero hashing |
| Value-write authorization | Dual-root cage landed on devnet; lifecycle completes in M1 |
| Super watcher (cross-plane relayer / evidence submitter) | Divergence-burn retired for identity (no fork possible under the checkpoint — identity-model §1/§11); live duties: relay witnessed anchoring, submit duplicity / correspondence proofs (a defined duty, drilled via #90 — identity-model §7b), request/trigger freeze, police R-TEL; permissionless, bounty-compatible; M5 |
| Cardano-only vLEI resolution | Unblocked by the E-native pivot: existing GLEIF/QVI credentials and AIDs are consumed as-is; large-event genesis (6+-key boards) waits for the chunk-token extension or a native `blake3` builtin CIP |

---

[GLEIF vLEI page]: https://www.gleif.org/en/organizational-identity/introducing-the-verifiable-lei-vlei
[GLEIF LEI page]: https://www.gleif.org/en/about-lei/introducing-the-legal-entity-identifier-lei
[KERI IETF draft]: https://github.com/WebOfTrust/ietf-keri
[ACDC IETF draft]: https://github.com/WebOfTrust/ietf-acdc
[eIDAS 2.0]: https://digital-strategy.ec.europa.eu/en/policies/eudi-regulation
