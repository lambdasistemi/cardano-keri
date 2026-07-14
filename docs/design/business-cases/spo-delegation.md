# Case B — Identified SPO Delegation

"Only delegate to legally identified pools" — an institution's stake may only
ever back operators with a valid Legal Entity vLEI.

!!! warning "Current-actor resolution is the sovereign per-AID checkpoint (#92)"
    Per `specs/92-checkpoint-contention/DECISION.md`, wherever this case resolves the SPO Legal
    Entity's **current authority** — "`PoolBinding.trie_key` Active in the L1 AID registry"
    (§2), the mermaid "trie_key Active?" step, and the LE `cur_key` owner-signature on
    pool-side registration — the live surface is that LE AID's **own sovereign, per-AID,
    quantity-one uniquely-tokenized checkpoint UTxO**: asset id `(checkpoint_policy_id,
    aid_asset_name)`, current weighted keys/threshold in the inline `CheckpointDatum`, read as
    a **CIP-31 reference input** and discovered by a **generic exact-asset `(policy_id,
    asset_name)` lookup** (candidate outref for liveness only, re-validated against the
    ledger). "Active" is enforced as its **live UTxO in the accepted mint/spend lineage** (not
    a closed/tombstoned one) **and** the AID **absent from the separate, shared,
    attacker-contendable R-FRZ freeze registry** — not a status field in the datum. A
    `delta = 0` rotation (`seq + 1`) **consumes** the checkpoint UTxO, so an owner signature
    made under the prior sequence is **stale** and must be **re-signed** by the current
    weighted keys over the fully bound message + current sequence, never merely re-pointed at
    the fresh checkpoint. **Preserved as written**: the separate **identified-pools registry**
    (`pool_id → PoolBinding`, its own key space and cold-key-rotation lifecycle), the
    **GLEIF → QVI → LE** hierarchy, and L2 TEL non-revocation — the pool-binding and
    credential planes, which gate *eligibility* but never select the LE's current checkpoint
    identity.

## 1. Actors & credential level

- **The SPO** is a legal entity holding a
  [vLEI Legal Entity credential](../vlei.md) (QVI-issued). Its identity anchor
  is its **pool cold key**: the binding object is
  `{pool_id, cold_vkey, aid, trie_key}` where `pool_id = blake2b_224(cold_vkey)`
  — the same hash the ledger uses in delegation and registration certificates
  (Aiken stdlib: `StakePoolId = Hash<Blake2b_224, VerificationKey>`) — carrying
  the LE's **stable qualified `aid`** (from which the sovereign checkpoint asset
  id is derived) alongside `cold_vkey` and the historical **`trie_key`**
  (admission-cache key only). Binding
  to `pool_id` rather than to a wallet key matters: it survives relay changes,
  reward-address changes, and pledge moves; it dies only with cold-key
  rotation (a pool re-registration event, which is the correct time to
  re-attest).
- **The delegator** is the buyer: an institution
  ([fund, treasury](../../finance-primer.md#fund-desk-treasury), exchange
  under compliance constraints) that must demonstrate its stake only ever
  backs identified operators.
- **The verifier** is the delegator's own *stake credential script* — not the
  pool, not an oracle. cardano-keri supplies the registries and the verifier
  library it imports.

!!! info "What is an 'institution under compliance constraints'?"
    A [fund, desk, or treasury](../../finance-primer.md#fund-desk-treasury)
    manages money under written rules — set by a board, by client mandate, or
    by regulation — and must be able to show an auditor that every action
    followed those rules. "Compliant staking yield" simply means earning
    staking rewards *without stepping outside those rules*: e.g. a treasury
    policy saying company funds may only back service providers whose legal
    identity is [verified](../../finance-primer.md#kyc-know-your-customer).
    An exchange is "under compliance constraints" because it is itself a
    regulated business with
    [AML duties](../../finance-primer.md#aml-and-sanctions-screening) — it
    cannot route customer assets to anonymous operators. Today such policies
    live in documents and are checked by hand after the fact; this design
    turns one into a rule the chain itself enforces at the moment of
    delegation.

## 2. Gated action & enforcement point

Verified against the Aiken validator and certificate documentation:

- A stake credential can be a Plutus script. Publishing a delegation
  certificate for a script credential invokes the script's **`publish`
  handler**, whose target is the full `Certificate` value.
- The handler **sees**:
  `DelegateCredential { credential, delegate: DelegateBlockProduction { stake_pool } }`
  — i.e. the exact target `pool_id` — plus the whole transaction, so the
  distinct CIP-31 reference inputs are visible: the **identified-pools
  registry** (pool binding), the bound LE's **sovereign per-AID checkpoint**
  (current authority), and the **L2 TELs** (credential non-revocation) — plus an
  **admission cache** where a venue uses one (this case does not; see §4). Same for
  `DelegateVote`/`DelegateBoth` (DRep analog) and
  `RegisterAndDelegateCredential`.
- The handler **cannot see**: the *current* delegation of the credential
  (certificates carry no prior state), epoch boundaries, or anything after the
  certificate lands. Enforcement exists only at certificate-publication time.

So the design is: **the institution's stake credential is a script that
witnesses a delegation certificate only if the redeemer proves `stake_pool` is
bound to an Active, unrevoked vLEI entity.** The script checks: membership
proof of `pool_id → PoolBinding` in the identified-pools registry, and — since
the binding carries the LE's **stable qualified AID** — resolves the bound LE
AID's **current authority live in its sovereign per-AID checkpoint** — asset id
`(checkpoint_policy_id, aid_asset_name)` derived from that qualified AID, read
as a CIP-31 reference input, its live UTxO in the accepted mint/spend lineage
and the AID absent from the shared R-FRZ freeze registry (#92) — and TEL
non-revocation (L2), all against reference inputs.

**Pool-side registration** is mutual attestation: the SPO submits
`PoolBinding { pool_id, cold_vkey, aid, trie_key }` — carrying the LE's
**stable qualified AID** `aid` (from which the checkpoint asset id
`(checkpoint_policy_id, aid_asset_name)` is derived) alongside the historical
`trie_key` (admission-cache key only; it cannot by itself select the current
checkpoint) — with (a) an Ed25519 signature by `cold_vkey` over a
domain-separated `{pool_id, cold_vkey, aid, trie_key, network_id}` message,
verified on-chain (`blake2b_224(cold_vkey) == pool_id` — blake2b_224 is a
PlutusV3 builtin), and (b) the LE AID's **witness set meeting its current
weighted threshold** — read from its sovereign per-AID checkpoint — over the
**same full payload** (`{pool_id, cold_vkey, aid, trie_key, network_id}`) plus
the current sequence (not a single `cur_key` signature). Both signatures bind
the identical full payload — including **both** `aid` and `trie_key` **and**
`network_id` — so neither party can bind the other unilaterally, no field can be
swapped after attestation, and the binding cannot be replayed onto another
network.

The two flows side by side — binding happens once per cold key; the gate fires
at every delegation certificate:

```mermaid
flowchart TB
    subgraph bind["Pool-side binding — once per cold key"]
        COLD["SPO cold-key signature over<br/>{pool_id, cold_vkey, aid, trie_key, network_id}"]
        LESIG["SPO's Legal Entity AID witness set (current weighted threshold)<br/>over {pool_id, cold_vkey, aid, trie_key, network_id} + current sequence"]
    end
    IPR["Identified-pools registry<br/>pool_id → PoolBinding {pool_id, cold_vkey, aid, trie_key}"]
    COLD --> IPR
    LESIG --> IPR

    subgraph deleg["Delegation — every certificate"]
        INST["Institution publishes<br/>delegation certificate → pool_id"]
        PUB["Script stake credential<br/>publish handler"]
        INST --> PUB
    end
    PUB -->|"pool_id bound?<br/>(membership proof)"| IPR
    PUB -->|"LE current authority live<br/>in its own checkpoint? (#92)"| CHK["LE AID sovereign checkpoint<br/>(per-AID, reference input)"]
    PUB -->|"LE credential unrevoked?"| L2["L2 issuer TELs<br/>(reference input)"]

    style IPR fill:#1e3a5f,stroke:#4a90d9,color:#e0e0e0
    style PUB fill:#1e3a2f,stroke:#4a9040,color:#e0e0e0
```

## 3. Design sketch

New components on top of L1–L4:

- **Identified-pools registry**: an MPF cage `pool_id → PoolBinding`,
  owner-signed leaves (the LE owns its binding), oracle co-signed. Not leaves
  inside the AID registry — different key space, different lifecycle (cold-key
  rotation ≠ AID rotation).
- **Delegator stake script** (`publish` + `withdraw` handlers), parameterized
  by the registries it trusts and the owner's authorization rule (institution
  multisig).
- **Delegation-state UTxO (optional but load-bearing)**: because the script is
  stateless, an "evict on revocation" path needs a companion UTxO recording
  the current `pool_id`. With it, a permissionless keeper can publish a
  re-delegation to a fallback identified pool by proving the *recorded* pool's
  credential is now revoked. Without it, revocation response is purely an
  off-chain operational duty of the institution.
- **DRep analog** falls out for free: the same handler pattern on
  `DelegateVote` against an identified-DReps registry.

!!! warning "Honest limit — delegation is sticky"
    The ledger re-invokes no script at epoch boundaries. If the pool's vLEI is
    revoked *after* delegation, stake keeps flowing to it until someone
    publishes a new certificate. In everyday terms: a delegation certificate
    is like a standing order at a bank — it keeps acting until you replace it,
    and nobody re-checks it each period. The gate guarantees "was identified
    at delegation time," and only with the keeper/eviction extension
    "re-delegated promptly after revocation." It can never guarantee "never
    staked to a revoked pool."

## 4. Pressure on the open decisions

- **Admission vs per-tx**: delegation certificates are *rare* (per
  institution: a few per year). Full per-certificate verification is
  affordable — this case exerts **no pressure toward the admission cache**;
  it is the natural home for full per-transaction verification.
- **KeyState parity**: SPO legal entities and institutional delegators are
  both organizations — **thresholds needed on both sides** (LE AID multisig;
  the institution's owner-rule is native script/multisig). Reinforces
  list-shaped KeyState.
- **Revocation freshness**: strong at the gate, **structurally weak after it**
  (stickiness). Cascade depth matters at certificate time (revoked QVI ⇒ pool
  not delegatable).
- **Throughput**: negligible. Current-AID rotation has **no shared registry
  ceiling** — the SPO LE rotates on its **own** sovereign per-AID checkpoint
  UTxO (#92). The shared **identified-pools registry**, the **admission** plane,
  and any **R-FRZ** freeze UTxO **retain their own serialization** as separate
  contended objects, but at this case's certificate frequency (a few per year)
  it is immaterial, not absent.
- **Privacy**: pool identity is *meant* to be public (differentiation); the
  delegator's identity need not be on-chain at all — only its policy is.
  Mildest privacy profile of the four cases.

## 5. Demand side

Buyers: (i) institutions that want compliant staking yield — the
certificate-time guarantee maps directly to an auditable policy; (ii) SPOs
buying differentiation ("legally identified pool") to attract that stake;
(iii) the Veridian/Amaru channel: identified SPOs are the same population
pitched as **KERI witness hosts** (witnesses are the always-on servers that
receipt KERI key events — see the [KERI primer](../../keri-primer.md)) — one
vLEI onboarding sells both ("witness hosting under a verifiable legal
identity"), and Amaru bundling is the distribution vector. **Smallest pilot**:
one [QVI](../vlei.md)-credentialed SPO + one institutional delegator + the
pools registry on preprod; no DeFi protocol needed, no per-trade throughput,
exercises L1+L2+L3 end-to-end.

!!! info "Why 'auditable policy' is the selling point"
    Today, "we only stake with reputable operators" is a sentence in a policy
    document, checked by hand after the fact. With the stake script, the
    policy is enforced by the chain at the moment of delegation, and every
    past delegation carries on-chain proof that the check ran. An auditor can
    verify years of policy compliance from public data, without trusting
    anyone's spreadsheet — that verifiability, not the yield itself, is what
    the institution is buying.

## 6. Case-specific risks & limitations

- **Gates the delegator, not the pool**: an unidentified world continues
  delegating to anyone; value exists only if identified stake is commercially
  meaningful to SPOs.
- **Address migration**: the institution must move funds to base addresses
  with the script stake credential — operational cost, custody-integration
  friction.

    !!! info "Custody-integration friction, in plain terms"
        Institutions usually do not hold keys themselves — a
        [custodian](../../finance-primer.md#custody) does, under contract and
        regulation. Moving funds to addresses whose staking rights are
        controlled by a script means the custodian's systems must know how to
        build and sign transactions for that script. If the custodian does not
        support it, the institution cannot adopt the design at all — a
        sales-and-integration hurdle, not a cryptographic one.
- **Rewards custody**: rewards accrue to the script's reward account; the
  `withdraw` handler must gate withdrawals (owner multisig) — more scope, and
  a bug here strands rewards.
- **Cold-key rotation** invalidates the binding; needs a re-attestation flow
  tied to pool re-registration.
- **Stickiness** (above) is the headline caveat for any compliance claim
  stronger than certificate-time.
