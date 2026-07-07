# Case D — Institutional Contracts

Bilateral or few-party on-chain contracts — escrow, DvP settlement, repo,
consortium disbursement — with counterparty identity enforced by the
validator, not an oracle.

## 1. Actors & credential level

Two to five legal entities per contract, each holding a vLEI chain
(GLEIF → QVI → LE, per [vLEI Bridge](../vlei.md)). The distinguishing feature
of this case: **the LE credential alone is not enough**. A contract is binding
only if executed by someone *authorized to bind the entity* — so the signing
credential is the **OOR** (Official Organizational Role: CEO, CFO, treasurer),
issued by the QVI on behalf of the LE, or an **ECR** scoped to the specific
engagement.

This makes delegation-of-authority the *central* design question, not a parity
footnote. Two distinct delegation concepts must not be conflated:

- **Credential-level delegation (ACDC)**: the LE issues/receives OOR/ECR
  credentials naming officers. Verifying "the signer is the CFO" is one more
  hop in the ACDC chain (four hops: GLEIF → QVI → LE → OOR), which exceeds the
  epic's 3-hop bound — the verifier's hop budget is a case-driven parameter,
  not a constant.
- **KERI-level delegation (`dip`/`drt`)**: the officer's *AID itself* is
  delegated from the LE's AID, with cooperative anchoring. This binds key
  custody, not role authority.

The chain can enforce the first today (it is ACDC verification, Layer 3); the
second is the deferred KERI-parity work. For contracts, credential-level
delegation is sufficient and is the natural v1: role authority is what
contract law cares about.

## 2. Gated action & enforcement point

The enforcement point is the **contract UTxO's spend validator** at each state
transition of a bilateral/multiparty state machine: escrow release, DvP
settlement legs, repo open/roll/close, syndicated-position transfers. Each
transition names which party (or quorum) must act; the validator checks that
the acting signature verifies against the *current* key-state of the expected
counterparty's `trie_key` (via the L1 registry CIP-31 reference input) and,
where role-bound, that an unrevoked OOR links signer to entity (L2 TEL
proofs).

**Formation** is off-chain but uses the same rails: entities exchange
`trie_key`s, replay each other's KELs, verify each other's credential chains
against the on-chain registries (the binding-verification protocol of
[Veridian Bridge](../../architecture/veridian-bridge.md)), then co-sign the
instantiation transaction that locks funds under the template parameterized
with both identities. No trusted introducer is needed — the registries are the
mutual due-diligence substrate.

## 3. Design sketch

On top of L1–L4:

- **Contract template library** (Aiken): escrow, 2-party DvP, n-party
  disbursement. Each template is parameterized at instantiation with the
  counterparties' identity references and a transition table (who may fire
  which transition, with what quorum).
- **Identity fixing mode per template** — the key design axis:
    - *Fixed at formation*: bake counterparty `trie_key`s into the datum.
      Stable (rotation-proof, since `trie_key` never changes), but blind to
      post-formation revocation unless paired with per-transition status
      checks.
    - *Live per transition*: re-verify AID `Active` + OOR non-revocation at
      every spend. The honest default for institutional risk: each transition
      is a fresh attestation.
    - Recommended: fixed `trie_key` + live status/role check — identity cannot
      drift, standing is re-proven.
- **Ceremony tooling**: institutional contract UX is a *ceremony
  orchestrator* that gathers OOR-backed witnesses from each entity's signers
  and assembles the transition transaction — witness collection across
  organizations, encrypted key vaults, wizard-driven build→sign→submit with
  resumable client state. This operational shape already exists in practice in
  multi-organization treasury ceremonies on Cardano mainnet and should be
  reused, not reinvented.

## 4. Pressure on the open decisions

- **Admission vs per-tx**: the one case where **full per-transaction
  verification is affordable** — 2–5 parties, transitions measured in
  days/weeks, ex-units irrelevant at that frequency. No admission cache
  needed; the contract UTxO *is* the admission. This weakens "hybrid
  everywhere" into "hybrid where throughput demands it" — the verifier library
  must expose both modes.
- **KeyState parity**: thresholds are essential (corporate keys are k-of-n).
  Supports list-shaped KeyState now. KERI-level delegation stays deferred; OOR
  covers the authority question at the credential level.
- **Revocation freshness**: the sharp scenario is *OOR revoked mid-contract*
  (officer departs). With live per-transition checks the next transition
  simply requires a fresh OOR holder — the contract must therefore define a
  **re-designation transition** (entity swaps its authorized signer) or funds
  freeze. Templates need this transition as a first-class state, not an
  afterthought.
- **Throughput**: lowest of the four cases; the single-UTxO registry ceiling
  is irrelevant here.
- **Privacy**: institutions *want* attributability of counterparties but not
  of terms. Keep terms as a hash in the datum (the full agreement stays
  bilateral, off-chain — consistent with the ACDC-notarization pattern in
  [vLEI Bridge](../vlei.md) use case 4); amounts/assets are unavoidably public
  on Cardano L1, which is itself a screening criterion for which contract
  types fit.

## 5. Demand side

Buyers: funds and banks doing bilateral settlement/collateral operations;
corporate treasuries; consortium disbursement operations. A **proto-customer
already exists in the project's orbit**: the Amaru treasury — PRAGMA member
organizations co-signing mainnet disbursements — is precisely a multi-entity
institutional ceremony whose signers could be OOR-verified rather than "known
key hashes in a registry file." **Smallest pilot**: re-implement one existing
multi-sig ceremony (one treasury disbursement flow) with vLEI-verified signers
— no new counterparties to recruit, real mainnet value, and it exercises L1–L3
plus one template.

## 6. Case-specific risks & limitations

- **Legal enforceability gap**: an on-chain identity proof shows *who* signed,
  not that a legally valid contract was formed (offer/acceptance, capacity,
  governing law). The template is evidence infrastructure, not a contract-law
  substitute — the regulation-vs-implementation line must be stated as in
  [The Regulated DeFi Gate](../defi-gate.md).
- **OOR freshness**: role credentials churn faster than entity credentials;
  without the re-designation transition, every personnel change threatens
  liveness of locked funds.
- **Four-hop chains** (OOR-signed transitions) exceed the current 3-hop
  verifier bound — direct scope pressure on the chain-verifier design.
- **Venue acceptance**: institutions may not accept public mainnet for
  material positions (terms leakage, MEV-adjacent ordering, settlement
  finality); a sidechain/permissioned-ledger deployment story may be a
  prerequisite for anything beyond the treasury-shaped pilot.
