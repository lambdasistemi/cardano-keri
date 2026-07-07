# Business Cases — Comparison and Factored Core

!!! tip "Unfamiliar with the finance vocabulary?"
    These pages assume Cardano literacy but **no** financial or institutional
    background. Every market, legal, and compliance concept they use —
    securities, registers, custody, KYC/AML, escrow, repo, batchers, MEV — is
    explained from zero in the [Finance Primer](../../finance-primer.md), and
    each page links there on first use. The identity-side concepts (AID, KEL,
    ACDC, vLEI) are covered by the [KERI Primer](../../keri-primer.md).

The [epic](https://github.com/lambdasistemi/cardano-keri/issues/21) names four
use cases for ACDC verification on-chain. This section analyzes each as a
concrete design — actors, enforcement point, components on top of the four
layers, and the pressure each puts on the open architectural decisions — then
factors out what is common. The headline result: **most of the open decisions
are use-case-invariant**; the business pick only selects a last-mile adapter.

| Case | Enforcement point | Verification mode | Cheapest pilot |
|---|---|---|---|
| [Regulated DeFi](regulated-defi.md) | order/pool spend validator (batcher model, withdraw-zero) | admission cache **mandatory** | tokenized instrument + venue on preprod |
| [Identified SPO delegation](spo-delegation.md) | delegator's script stake credential, `publish` handler | full per-certificate **affordable** | one QVI-credentialed SPO + one institutional delegator |
| [KYC security tokens](security-tokens.md) | CIP-113 substandard, or register-as-cage | admission cache **mandatory** (receiver check) | private placement on register-as-cage |
| [Institutional contracts](institutional-contracts.md) | contract state-machine spend validators | full per-transition **affordable** | one treasury disbursement ceremony, vLEI-verified signers |

## The factored core: required by every case

1. **List-shaped, threshold-capable KeyState.** Unanimous: every case has
   organizational actors whose AIDs are k-of-n weighted multisig. Because
   `trie_key` is derived from inception material, the schema shape is frozen
   into the identity key — it must be list-shaped from v1 (a single key is the
   1-of-1 degenerate case), with a `delegator` field reserved. Scope change to
   [#24](https://github.com/lambdasistemi/cardano-keri/issues/24).
2. **Hop bound 4, parameterized.** Three of four cases gate on the *role*
   credential (trader ECR, officer OOR, transfer-agent OOR), not the Legal
   Entity credential — LE root AIDs are board-custody multisig and never sign
   operations. The epic's linear picture (GLEIF → QVI → LE → Individual)
   undercounts the real chain: per the
   [vLEI schemas](https://github.com/WebOfTrust/vLEI/tree/main/schema/acdc),
   OOR credentials are issued by the QVI and chain to the LE credential
   through an LE-signed OOR-AUTH credential — **four ACDCs**; ECRs may also be
   issued by the LE directly — three. Hence a bound of 4, parameterized. Scope
   change to [#31](https://github.com/lambdasistemi/cardano-keri/issues/31).
3. **Layer-3 verifier with both modes.** The cases split exactly 2/2: DeFi and
   security tokens *require* the admission cache (batch size limits; receiver
   checks); SPO delegation and institutional contracts *afford* full
   per-transaction verification. Ship the full verifier plus a reusable
   **admission-cage component**
   (`trie_key → {credential_saids, role_level, admitted_at, not_after}`).
4. **Detached-signature authorization (Option A).** Forced by the DeFi batcher
   model (the entity never signs the executing transaction) and generalizing
   to ceremonies and cage writes: a domain-separated, nonce- and
   validity-bounded signature envelope verified against the L1 registry.
   Required-signer checking (Option B) remains an optimization where the actor
   does sign the transaction.
5. **All-TELs cascade checks with a stated freshness floor.** Non-revocation
   must be proven at every level of the chain (a revoked QVI must invalidate
   downstream access). Cascade semantics are to be cited from the GLEIF
   ecosystem governance framework, not invented. Freshness is minutes-grade
   (TEL root cadence + settlement) — never sanctions-screening-grade.
6. **A scoped-override policy knob per cage.** Security tokens legally require
   freeze/seize; contracts require signer re-designation; venues require
   admission expiry. One spec concept covers all: *forging is impossible
   everywhere; scoped, issuer-AID-signed intervention powers are per-cage
   policy — explicit, on-chain, auditable.* This must be reconciled with the
   epic's "oracle cannot forge" headline in so many words.
7. **The KERI-wallet ↔ Cardano signing bridge (Layer 4).** Every case's actors
   keep keys in KERI wallets, not CIP-30 wallets. Producing
   order/transition-bound detached signatures programmatically is on the
   critical path of every design and is currently nobody's deliverable.

## What still depends on the business pick

Only the last-mile adapter and its case-local unsolved problems:

- **Regulated DeFi**: order gate + admission cage; the batcher as an
  unregulated compliance actor; attributed order-flow privacy.
- **SPO delegation**: delegator stake script + identified-pools registry;
  delegation stickiness after revocation.
- **Security tokens**: CIP-113 substandard and/or register-as-cage; position
  privacy; retail out of scope.
- **Institutional contracts**: template library + ceremony tooling; OOR churn
  and the re-designation transition.

## Pilot ladder by cost

SPO delegation and institutional contracts are the cheapest end-to-end pilots
and use counterparties already in the project's network (the Amaru/Veridian
channel; the Amaru treasury ceremony). The security-token private placement is
next. The DeFi gate is the most component-heavy, and its real buyer — the RWA
issuer — converges with the security-token case anyway.

!!! note "Provenance"
    These four analyses were produced independently against the same template
    (actors, enforcement point, design sketch, decision pressure, demand,
    risks) and then factored. Where they contradict earlier documents — e.g.
    the batcher-model correction to [The Regulated DeFi Gate](../defi-gate.md)
    — the case study is the more recent analysis. Issue links on this page
    (#21, #24, #31) point to the project's internal tracker and are not
    publicly readable; the decisions themselves are stated inline.
