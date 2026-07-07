# Case A — Regulated DeFi Gate

Gate protocol entry and actions on a valid Legal Entity vLEI. This deepens
[The Regulated DeFi Gate](../defi-gate.md) primer into a design analysis — and
corrects it on one load-bearing point (the batcher model, §2).

## 1. Actors & credential level

The gated party is a **Legal Entity** (fund, bank desk, corporate treasury),
but the acting party is almost never the entity's root AID. GLEIF's framework
puts LE AIDs under multi-sig group control (board-level custody); nobody signs
swap orders with a 2-of-3 board key. The realistic check target is therefore
the **third hop: an OOR/ECR credential** held by an individual trader or an
operations service, chained LE → trader. This makes the full chain
verification (GLEIF → QVI → LE → ECR) load-bearing — a gate that stops at the
LE credential either forces hot custody of a governance-grade key or silently
degrades to "whoever holds the entity key," which is the allowlist pattern
again. Integrators: the DeFi protocol (imports the verifier), the venue
operator (deploys the admission cage), QVIs (issue), the entity's compliance
office (holds credentials in a KERI wallet).

## 2. Gated action & enforcement point

"The entity signs the gated spend" is wrong for most Cardano DeFi. Major
DEXes use the **batcher model**: the user locks an order UTxO at an order
script; an off-chain batcher later spends orders against the pool UTxO in a
transaction **signed by the batcher, not the entity**. Two consequences:

- **Order placement cannot be the enforcement point.** Paying to a script
  address runs no validator; anyone can lock funds at the order script.
- **Required-signer checks (Option B) fail at execution time** — the entity's
  key is not among the transaction signatories of the batch. The gate must
  verify a **detached Ed25519 signature carried in the order datum**
  (Option A), signed by the trader's registered key over the order terms plus
  a nonce/validity window, checked against the L1 registry reference input
  when the batcher spends the order.

Enforcement points, concretely: (a) the **pool/order spend validator**
verifies the detached signature + admission proof per order; (b) for venues
with many scripts, factor the identity check into a **withdraw-zero staking
validator** (the CIP-112-documented pattern) so one script execution per
transaction covers all orders in a batch; (c) a **minting policy on
LP/position tokens** gates position creation, which catches deposits even when
order flow is composed through aggregators.

## 3. Design sketch

On top of L1–L4:

- **Admission cage per venue** (an MPFS instance):
  `trie_key → AdmissionLeaf { credential_saids: [qvi, le, ecr], role_level, admitted_at, not_after }`.
  The admission transaction carries the raw ACDCs + proofs; the L3 verifier
  runs the full chain on-chain; permissionless.
- **Per-action check** (in batch execution): MPF membership proof of
  `trie_key` in the admission cage (reference input) + AID `Active` +
  `cur_pubkey` from L1 (reference input) + detached signature verification +
  TEL non-revocation proofs (reference input) +
  `tx validity range ⊂ not_after`.
- **Expiry**: vLEI ecosystem governance handles lapse (annual LEI renewal) via
  **revocation**, not credential-internal expiry — so `not_after` is a venue
  policy knob (force re-admission every N days), while the authoritative kill
  switch is the TEL. Don't duplicate GLEIF semantics on-chain.
- **L4 addition this case forces**: a signing bridge. LE/ECR keys live in KERI
  wallets (Veridian), not CIP-30 Cardano wallets. The proof builder must
  produce the order-datum detached signature via the KERI wallet — a real
  UX/integration component, not a library detail.

## 4. Pressure on the open decisions

- **Admission-cached vs per-tx**: hybrid is **mandatory**, not preferred. A
  batch of 10 orders × 3 raw ACDCs (~1–2 KB each) cannot fit 16 KB transaction
  limits; full per-transaction verification is arithmetically out. Admission
  on-chain once; per-order checks are proofs + one signature.
- **KeyState parity**: **thresholds required at L1** (LE and QVI AIDs are
  multisig in practice — a singleton KeyState cannot checkpoint them, breaking
  the bridge claim for the anchor actors). **Delegation pressure is high**:
  the LE→ECR hop *is* delegation in spirit; if L1 cannot represent delegated
  AIDs, ECR holders must incept independent AIDs and the chain check carries
  the whole burden of linking them.
- **Cascade/freshness**: all-TELs per action (three MPF proofs — cheap).
  Freshness floor = TEL root-update cadence + settlement, i.e., minutes. Fine
  for "revoked entity loses access"; **not** sanctions-screening-grade, and
  the docs must say so.
- **Throughput**: gated *reads* scale (reference inputs are unlimited
  concurrent readers). Writes serialize per UTxO: one admission per block per
  venue, one rotation per block per L1 registry — acceptable here; order flow
  never writes the registries.
- **Privacy**: worst of the four cases. Real-time, LEI-attributed order flow
  enables front-running and copy-trading of named institutions; MiFID
  transparency regimes have deferral windows, the chain does not. Pseudonymous
  per-venue sub-AIDs would help traders and gut the audit story — a genuine
  open trade-off.

## 5. Demand side

The buyer is **not the DEX** (Aave Arc's lesson: venues build gates only when
a paying user demands one) — it is the **RWA/tokenized-fund issuer** whose
asset legally cannot trade unrestricted, and secondarily the institution
needing demonstrable counterparties. The institutional on-chain activity that
demonstrably exists is tokenized treasuries/money-market funds on other
chains, all using issuer-controlled allowlists; none on Cardano at scale — a
2026 Cardano RWA pipeline is a gap to research, not assert. Smallest real
pilot: **one tokenized instrument + one venue on preprod**, synthetic
GLEIF/QVI chain (dev-issued F-prefix credentials, since real F-prefix vLEIs do
not exist until Veridian ships the ask), demonstrating admission, gated batch
execution, and revocation propagation end-to-end.

## 6. Case-specific risks

- **The batcher becomes a compliance actor**: it selects and orders identified
  flow and can censor named entities — MEV against known institutions is
  qualitatively worse than against anonymous addresses. Is the batcher itself
  gated? Undesigned.
- **Composability breakage**: gated pools cannot be routed through ungated
  aggregators; liquidity fragments — the economic failure mode that killed the
  precedent.
- **Venue reclassification**: a venue enforcing per-counterparty identity
  starts resembling a regulated trading facility; the gate may *create*
  licensing questions for the protocol (regulation-vs-implementation flag:
  needs counsel-grade citation, not our inference).
- **KERI-wallet ↔ Cardano-wallet split** (§3): the signing bridge is on the
  critical path of every order; if Veridian cannot produce order-bound
  detached signatures programmatically, the UX collapses to custodial signing
  services.
