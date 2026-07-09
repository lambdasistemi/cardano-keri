# cardano-keri — system architecture (design dump)

Status: **discussion-phase capture** (2026-07-09). This is the working architecture
we converged on while grounding #68 and the Blake3 question. Many items are marked
**OPEN**. It should graduate into `docs/design/` once ratified.

---

## 0. One-paragraph shape

Entities that want a Cardano-verifiable identity **register their KERI AID** on-chain.
The set of KERI identities and credentials the system must track is the **closure** of
those registrations up to GLEIF — a pure, derived set, not a curated one. **Proof
builders** watch the KERI witnesses of everything in the closure and maintain
**Merkle-mirror trees** of that off-chain *state* (the **closure itself is computed, not
stored** — see §5); **Cardano Foundation**, as **coordinator**, anchors the agreed
*state-mirror* roots on-chain per checkpoint. On-chain
**validators** then verify user actions against (a) native on-chain state and (b) the
anchored mirror roots — all in **Blake2b**, never Blake3.

## 1. Strategic frame

- **The wall:** Plutus has `blake2b_256`, no `blake3`. The vLEI ecosystem (AIDs *and*
  ACDC SAIDs) is Blake3, rooted at GLEIF. You cannot recompute a Blake3 SAID on-chain,
  and you cannot re-hash GLEIF's tree.
- **Two tiers:** (1) CF-as-QVI issues **Blake2b** credentials — self-sufficient, no
  Plutus change, but "CF-parallel," not the existing ecosystem. (2) Verify the **real
  Blake3** vLEI ecosystem — needs the watcher bridge.
- **Operator forecast (adopted as working assumption):** target users already hold
  vLEI from *other* QVIs in Blake3; re-issuance is a big ask ⇒ the **watcher bridge is
  the spine**, CF-Blake2b a sidecar.
- **Blake2/Blake3 does NOT fork the system.** KERI state lives off-chain in witnesses,
  so the watch→build→anchor layer exists regardless. Blake3 only requires one extra
  root (**R-MAP**). A future Plutus `blake3` builtin simply **deletes R-MAP** and lets
  validators recompute — zero redesign. This is the sunset property.

## 2. Roles

| Role | Who | Does | Trust |
|---|---|---|---|
| **Registration oracle** | CF | accepts AID registrations (+ declared credential chain); provides liveness; in the MPFS model, batches writes and attests the AID Blake-mapping at registration | liveness; **censorship is the risk** (F7) if gated |
| **Proof builders** (watchers) | many operators | watch the KERI witnesses of everything in the **closure**; build the mirror trees (R-KEL/R-TEL/R-ACDC/R-MAP); serve inclusion-proof APIs; sign per-checkpoint roots | falsifiable + **bonded/slashable** (F8) |
| **Coordinator** | CF | anchors the agreed mirror roots on-chain, per checkpoint | **mechanical, never a judge** (see §5) |

The watcher is a **hash/state oracle, not a verifier** — the ACDC verification *logic*
stays on-chain in Plutus; the watcher only supplies the Blake3 digests and mirrored
state Plutus can't compute. Its only forgeable lever is a false `content↔SAID` mapping,
which is publicly recomputable and slashable.

## 3. Root families

**On-chain-native** (authoritative chain state; validators read/write directly; trustless):

| Root | Contents |
|---|---|
| **R-ID** | identity registry: registered AID → key-state (the closure seeds) |
| **R-VAL** | value cages, incl. the **admission-cache** leaves `trie_key → {credential_saids, role, admitted_at, not_after}` |
| **R-FRZ** | freeze registry (emergency revocation markers) |
| **R-POOL** | identified-pools registry (SPO case): `pool_id → {cold_vkey, trie_key}` |
| **R-REG** | securities register (security-tokens variant b): `trie_key → position` |

**Proof-builder-anchored** (mirror external KERI/Blake3 state; keyed over the closure;
CF-anchored; watcher-consensus; falsifiable):

| Root | Contents | Notes |
|---|---|---|
| **R-MAP** | Blake3 ↔ Blake2b for AIDs and credential SAIDs | present only while Plutus lacks blake3; AID slice can be absorbed by the registration oracle |
| **R-KEL** | AID → current KERI key-state (KEL checkpoint) | the *external* key-state; distinct from R-ID's Cardano-native key-state |
| **R-TEL** | credential SAID → issued/revoked status | **the hot root** — see §7 |
| **R-ACDC** | credential existence / SAID | **likely folds into R-TEL** (`SAID → issued\|revoked` carries both) |

## 4. The closure

The **minimal set of KERI identities + credentials the watchers must mirror in order to
verify everyone who registered** — nothing more, nothing less.

- **Nodes:** AIDs (identities) and ACDCs (credentials).
- **Seeds:** the AIDs registered on-chain (R-ID entries).
- **Rule:** from any node, follow its credential chain one hop toward the issuer and add
  what you reach; repeat to a fixpoint. **GLEIF is the fixed terminal.**

```
closure = registered AIDs ∪ { every AID + credential reachable by walking
                              credential chains from a registrant up to GLEIF }
```

Example — Alice (individual, OOR credential) registers:
```
Alice-AID → OOR → OOR-AUTH(+LE-AID) → LE-cred(+QVI-AID) → QVI-cred(+GLEIF-AID)
closure identities  = {Alice, LE, QVI, GLEIF}     → watch their KELs   (R-KEL)
closure credentials = {OOR, OOR-AUTH, LE, QVI}    → watch their status (R-TEL)
```

Properties: **closed** (a chain missing a hop is unverifiable), **minimal** (only what a
registrant depends on; unrelated vLEI identities never enter), **derived not chosen** (a
pure function of R-ID, so CF can't curate it). The closure is exactly the **key-domain of
the mirror roots**.

**Minimum registration payload** (so the closure is computable without fetching): the
registrant's AID + its credential-chain path `[(credential_SAID, issuer_AID), …]`
terminating at the pinned GLEIF root. (Witness/OOBI pointers ride along to *watch* each
target, but aren't needed to *compute the set*.) OPEN: full-path declaration vs inductive
(direct-parent-must-already-exist).

## 5. Determinism & the bounded-coordinator trust model

If watchers compute the closure over the **live** tip they disagree at the margin (A saw
a registration B hasn't), their roots differ, and CF would have to **arbitrate** — making
it a *judge* and breaking bounded trust. Fix: **pin every computation to settled inputs.**

- `closure_N = closure(R-ID @ settled root_N)` — the closure over registrations **as of a
  settled R-ID checkpoint**. Every watcher computes the *same* set. Late registrations
  roll into N+1. (No separate "closure structure" is stored/anchored — the commitment you
  need is the R-ID root you already have on chain.)
- State roots are `R-TEL_N`, `R-KEL_N` = "state of `closure_N` as of **freshness cutoff
  `T_N`**" (a slot / KEL-checkpoint). A watcher disagreeing with the anchored root is
  **provably wrong or provably lagging** — falsifiable against the pinned inputs.

> **Invariant:** the coordinator only ever anchors a *deterministic function of settled
> inputs* (`R-ID@N`, `T_N`). It never decides; it commits what anyone can independently
> recompute. Disagreement collapses to "one watcher is faulty" → a slashing/challenge
> matter, not a coordinator decision.

Trust layering, end to end: native app state (trustless) → closure pinned to settled R-ID
(deterministic) → state mirror over pinned inputs (falsifiable, bonded watcher-consensus)
→ CF anchors, never adjudicates.

## 6. Identity registry: MPFS-with-oracle vs token-per-AID  (OPEN — leaning MPFS-oracle)

The current design is a **single MPFS UTxO** (contention-flagged by vetting). Two models:

- **Token-per-AID** (mint from a known policy): parallel (no shared-UTxO bottleneck),
  proof-simple (reference the AID UTxO directly, datum carries key-state — no MPF proof),
  more permissionless (self-cert mint, no oracle). Loses **global "registered at most
  once"** — though self-cert (Ed25519 mint check) means only the key-holder can mint their
  AID, so no squatting; the residual loss is a single canonical entry for
  freeze/revocation/burn targeting.
- **MPFS-with-oracle:** the oracle consolidates **three** things in one write —
  **unicity** (on-chain absence proof), the **AID Blake-mapping** (attested at
  registration; the token model would need the watcher for this), and **batching** (many
  registrations per MPFS update, amortizing the single-UTxO contention that was the
  token model's main win). Cost: **censorable registration** (F7).

Since CF is already the trusted coordinator, the marginal centralization of the oracle is
small; **lean MPFS-oracle unless permissionless/un-censorable registration is a hard
requirement.** Boundary: the oracle absorbs only the *AID* mapping — credential SAID
mappings still come from the watcher (issued over time by third parties). The blake3 side
of the AID mapping is oracle-*asserted* (falsifiable), same trust grade as the watcher.

## 7. Cold path vs hot path (the performance/trust concentration)

The expensive 4-hop chain verify (touching R-MAP, R-KEL, R-ACDC, V6) happens **once, at
admission**, and writes a native **admission-cache leaf** (R-VAL). The **cheap per-action
hot path** then consults only:

```
R-VAL (admission membership) + R-ID (key-state) + R-FRZ (freeze absence)  [all native]
  + R-TEL (non-revocation cascade)              [anchored under the forecast — §9 open #4]
```

(Here R-ACDC is treated as still distinct from R-TEL; if folded — §9 open #3 — the
admission list loses R-ACDC. R-TEL is "anchored" per the operator forecast, formally
open per §9 #4.)

⇒ **In the hot path the only proof-builder-anchored dependency is R-TEL.** The heavy
anchored roots are admission-time only. This concentrates the entire per-transaction
trust-and-freshness question on **R-TEL** — which is why its consensus/anchoring/freshness
design matters most and why every business case gated on it.

## 8. How this was derived (methodology + four-case result)

Methodology: **use case → which validator → which redeemer → what proofs it carries →
which Merkle root each proof comes from.** Applied to all four business cases:

- The four cases only disagreed on whether R-MAP/R-KEL/R-ACDC are needed — and the
  disagreement traced to one assumption: **Blake2b vs Blake3 credentials.** In a
  CF-Blake2b world they collapse to native; in the Blake3 world (the forecast) they're
  anchored. So the methodology *proved* the proof-builder layer exists ⇔ Blake3/third-party.
- **R-TEL is the universal hot root** (every case gates on it).
- **R-POOL** (SPO) and **R-REG** (securities variant b) are new **native** registers
  (matching vetting F13's "missing core components").
- **Admission cache** pays the expensive verify once; receiver-admission (security tokens)
  is a *cached fact*, not a signature.

## 9. Open decisions

1. Registration: **permissionless vs CF-gated** (the last trust knob).
2. Identity registry: **MPFS-oracle vs token** (leaning MPFS-oracle).
3. **R-ACDC folds into R-TEL?** (likely yes).
4. **R-TEL native vs anchored** — pivots on issuer origin; forecast ⇒ anchored.
5. Closure declaration: **full-path vs inductive**.
6. Proof-builder **consensus mechanism** (threshold-sig quorum, challenge window) + the
   **freshness-cutoff cadence** `T_N`.
7. #68 keystate shape → **Lean** (weighted-threshold pre-rotation invariant) before freeze.

## 10. Honest residual risks

- CF actually obtaining **GLEIF QVI accreditation** (a business/governance step).
- **Bond soundness (F8)** — the slashing/challenge machinery that keeps proof builders
  honest is the one real cryptographic-design task underneath.
- **Censorable registration (F7)** if the oracle is gated.
- **CF-parallel interop caveat** — Blake2b creds are spec-compliant but ecosystem-novel.
- The maximal "trustless on-chain verification of the real Blake3 ecosystem" is **bonded-
  bridge until Plutus gains blake3**, not pure-trustless. State it plainly.
