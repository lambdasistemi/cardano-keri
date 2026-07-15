# Business Cases — Comparison and Factored Core

!!! tip "Unfamiliar with the finance vocabulary?"
    These pages assume Cardano literacy but **no** financial or institutional
    background. Every market, legal, and compliance concept they use —
    securities, registers, custody, KYC/AML, escrow, repo, batchers, MEV — is
    explained from zero in the [Finance Primer](../../finance-primer.md), and
    each page links there on first use. The identity-side concepts (AID, KEL,
    ACDC, vLEI) are covered by the [KERI Primer](../../keri-primer.md).

!!! warning "Current-actor authority across these cases is the sovereign per-AID checkpoint (#92)"
    Per `specs/92-checkpoint-contention/DECISION.md`, wherever these analyses resolve **who
    may act now** — "verified against the L1 registry", "`trie_key` Active?", "`cur_pubkey`
    from L1" — the live authority is an AID's **own sovereign, per-AID, quantity-one
    uniquely-tokenized checkpoint UTxO**: asset id `(checkpoint_policy_id, aid_asset_name)`,
    current weighted keys/threshold in the inline `CheckpointDatum`, read as a **CIP-31
    reference input** and discovered by a **generic exact-asset `(policy_id, asset_name)`
    lookup** (candidate outref for liveness only, re-validated against the ledger). A
    `delta = 0` rotation (`seq + 1`) **consumes** that checkpoint UTxO, so any pending
    authorization is **stale** and MUST be **discarded and re-signed** by the AID's **current
    weighted keys** over the fully bound action + current sequence — a simple re-reference to
    the fresh checkpoint is **not** sufficient (the exact shortcut #92 rejected). Value-bearing
    protocols carry the explicit **Execute / Refresh-Re-sign / Cancel-Reclaim / Expire-Cleanup**
    lifecycle. Two planes stay
    **distinct**: this current-actor authority is **not** the **historical credential/admission
    plane** — the **admission cache** (`trie_key → AdmissionLeaf {aid, credential_saids…}`,
    carrying the verified stable qualified `aid` from which the sovereign checkpoint asset is
    derived; `trie_key` stays a historical-only key), the
    **GLEIF → QVI → LE** hierarchy, and all-TELs cascade revocation are preserved as written;
    KEL/ACDC admission may still gate protocol *eligibility*, but it never selects the current
    checkpoint identity. Lifecycle/close is the checkpoint's **mint/spend lineage** and freeze
    is the **separate shared R-FRZ** registry — neither is a datum field. The **factored-core
    "list-shaped, threshold-capable KeyState" (item 1) remains the current weighted key state**;
    only its **physical store** moves from a shared MPF identity registry to the per-AID
    checkpoint (the mechanical re-cut is downstream #24/#23).

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
   organizational actors whose AIDs are k-of-n weighted multisig. The
   list-shaped, weighted key state is **carried in each AID's per-AID
   `CheckpointDatum`** — the current weighted keys/threshold that the sovereign
   checkpoint advances (#92) — a single key being the 1-of-1 degenerate case.
   V1 accepts independent AIDs only and carries no passive `delegator` / `di`
   field: cooperative KERI delegation needs parent-anchor proofs and is a
   separately versioned extension. The admission `trie_key` is only a
   **stable historical-cache key** into the credential/admission plane; it is
   **never** the current-authority schema or lookup, which is the sovereign
   per-AID checkpoint (asset id `(checkpoint_policy_id, aid_asset_name)`,
   generic exact-asset lookup). Scope change to
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
   (`trie_key → {aid, credential_saids, role_level, admitted_at, not_after}` —
   the leaf carries the verified stable qualified `aid`, bound at admission, so
   the sovereign checkpoint asset `(checkpoint_policy_id, aid_asset_name)` is
   derived from it; historical `trie_key` alone cannot select the current
   checkpoint).
4. **Detached witness-set authorization (Option A).** Forced by the DeFi batcher
   model (the entity never signs the executing transaction) and generalizing
   to ceremonies and cage writes: a domain-separated, nonce- and
   validity-bounded **detached witness-set envelope** — a set of signatures
   **meeting the acting AID's current weighted threshold** — verified against
   that AID's **sovereign per-AID checkpoint** (current weighted keys/threshold
   in the inline `CheckpointDatum`, read as a CIP-31 reference input; #92), not
   against a shared L1 registry root. A `delta = 0` rotation **consumes** that
   checkpoint UTxO, so a pending envelope is **stale** and cannot merely be
   re-pointed at the fresh checkpoint: it MUST be **re-signed** as a fresh
   witness set meeting the current weighted threshold over the fully bound
   action + current sequence. Value-bearing flows therefore carry the explicit
   **Execute / Refresh-Re-sign / Cancel-Reclaim / Expire-Cleanup** lifecycle.
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
   order/transition-bound **detached witness sets** (each member's signature,
   together meeting the acting AID's current weighted threshold) programmatically
   is on the critical path of every design and is currently nobody's deliverable.

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
