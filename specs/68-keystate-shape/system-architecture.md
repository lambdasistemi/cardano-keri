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
*state-mirror* roots on-chain per checkpoint.
Identity **R-KEL is excluded from this closure Merkle-mirror family** — it is the on-chain
cryptographic *checkpoint* (§3), advanced by witnessed anchoring seals, not a watcher-anchored
mirror. On-chain
**validators** then verify user actions against (a) native on-chain state and (b) the
anchored mirror roots — predominantly in **Blake2b**, with one checkpointed BLAKE3
exception: the ≤1-chunk AID **byte binding** `blake3(icp) == cesr_aid` is now verified
on-chain via the #97 Step/Finish chain (#91 §7c). Multi-chunk/tree hashing and the wider
credential-SAID plane stay outside that proof.

## 1. Strategic frame

- **The wall (now partial):** Plutus has `blake2b_256`, no native `blake3`. The vLEI
  ecosystem (AIDs *and* ACDC SAIDs) is Blake3, rooted at GLEIF. The #97 checkpointed
  Step/Finish path **does** recompute the complete 32-byte BLAKE3 predicate on-chain **for
  the single-chunk domain** (≤1024-byte AID inceptions), which is what makes the ≤1-chunk
  genesis byte binding cryptographic (§7c). Beyond that the wall stands: you cannot yet
  recompute a **multi-chunk / tree** Blake3 SAID on-chain, and you cannot re-hash GLEIF's
  tree — so the credential-SAID plane and >1-chunk inceptions stay watcher/oracle-attested.
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
| **Registration oracle** | CF | accepts AID registrations (+ declared credential chain); provides liveness; in the MPFS model, batches writes and attests the **semantic projection** at registration (all tiers) plus the **byte binding** only for >1-chunk inceptions — the ≤1-chunk byte binding is verified on-chain (#97), not oracle-attested (§7c) | liveness; registration **is** oracle-gated (#91 §7c decision 1), so **censorship is a live risk** (F7), mitigated only by the deferred k-of-n SPO-watcher escape |
| **Proof builders** (watchers) | many operators | watch the KERI witnesses of everything in the **closure**; build the mirror trees for the **credential / external-state plane** (R-TEL/R-ACDC/R-MAP) — identity **R-KEL is an on-chain cryptographic checkpoint, not a watcher-attested mirror** (§3), so here builders only watch/serve/submit identity advance material; serve inclusion-proof APIs; sign per-checkpoint roots | falsifiable + **bonded/slashable** (F8) |
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
| **R-MAP** | Blake3 ↔ Blake2b for AIDs and credential SAIDs | present only while Plutus lacks a blake3 builtin. **AID note is tier-scoped** (#91 §7c): the ≤1-chunk AID **byte binding** is on-chain (#97), so only the **>1-chunk residual AID mapping** stays oracle-attested; the credential-SAID mapping stays watcher/oracle-attested at every size. The AID slice can be absorbed by the registration oracle. |
| **R-TEL** | credential SAID → issued/revoked status | **the hot root** — see §7 |
| **R-ACDC** | credential existence / SAID | **likely folds into R-TEL** (`SAID → issued\|revoked` carries both) |

**Identity R-KEL — on-chain cryptographic checkpoint, set apart from the mirror family.**
Identity **R-KEL is set apart from the Proof-builder-anchored / watcher-consensus mirror family**;
it is an on-chain cryptographic *checkpoint*, never a watcher-attested mirror. Its relation to the
native registry is direct: the native **R-ID** registry seeds the genesis key-state and **R-KEL is
the advance-layer checkpoint over R-ID's** validator-checked rotations (R-ID holds the registered
AID → genesis key-state; R-KEL carries it forward per §4). Advance is by witnessed anchoring seals
carrying blake2b commitments. Genesis is the §7c **hybrid** (#91): the **byte binding**
`blake3(icp) == cesr_aid` is cryptographic on-chain for ≤1-chunk inceptions (#97), attested for
>1-chunk; the **semantic projection** is attested / challengeable at every tier (see
[identity-model.md](identity-model.md) §7a/§7c). This is a *classification*, not a physical-storage
choice — the advance-path storage shape is **#92's** to decide, not selected here.

## 4. The closure

The **minimal set of KERI identities + credentials the watchers must track in order to
verify everyone who registered** — nothing more, nothing less. The two planes differ:
identity KELs are watched to **assemble/serve/submit validator-checked R-KEL checkpoint advances**,
while credential/external state is **mirrored** into R-TEL/R-ACDC/R-MAP. R-KEL is not a
watcher mirror.

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
closure identities  = {Alice, LE, QVI, GLEIF}     → watch their KELs to submit R-KEL checkpoint advances
closure credentials = {OOR, OOR-AUTH, LE, QVI}    → mirror their status (R-TEL)
```

Properties: **closed** (a chain missing a hop is unverifiable), **minimal** (only what a
registrant depends on; unrelated vLEI identities never enter), **derived not chosen** (a
pure function of R-ID, so CF can't curate it). The closure is exactly the **key-domain over
settled R-ID** — of the credential/external mirror roots (R-TEL/R-ACDC/R-MAP) and of the
identity R-KEL checkpoint advances alike.

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
- **Credential/external mirror roots** `R-TEL_N` (and R-ACDC/R-MAP) = "state of `closure_N`
  as of **freshness cutoff `T_N`**" (a slot). A watcher disagreeing with an anchored
  **mirror** root is **provably wrong or provably lagging** — falsifiable against the pinned
  inputs (bonded watcher-consensus).
- **Identity `R-KEL`** is the **on-chain checkpoint over settled R-ID** — a validator-checked
  advance, not a watcher-computed mirror. Watchers serve/submit its checkpoint material, so
  its residual concern is **freshness/submission** of that material, not watcher-root
  integrity.

> **Invariant:** the coordinator only ever anchors a *deterministic function of settled
> inputs* (`R-ID@N`, `T_N`). It never decides; it commits what anyone can independently
> recompute. Disagreement collapses to "one watcher is faulty" → a slashing/challenge
> matter, not a coordinator decision.

Trust layering, end to end: native app state (trustless) → closure pinned to settled R-ID
(deterministic) → state mirror over pinned inputs (falsifiable, bonded watcher-consensus)
→ CF anchors, never adjudicates.

## 6. Identity registry: MPFS-with-oracle vs token-per-AID  (DECIDED #91 — MPFS-with-oracle)

**Decision note (2026-07-11, #91): MPFS-with-oracle.** The oracle is still required for
the semantic-projection attestation (all tiers) and the >1-chunk byte-binding
attestation, so the mandatory-attester argument that retired the token model's self-cert
mint **still holds for the projection** — even though the ≤1-chunk **byte binding** now
self-certifies on-chain (#97). MPFS-with-oracle consolidates unicity, the projection
attestation, and batching in one write; the partial ≤1-chunk self-cert is recorded as an
**input to #92's** storage-shape choice, not a reversal. See
[identity-model.md](identity-model.md) §7c (decision 2). The two models remain below for
the record.

The current design is a **single MPFS UTxO** (contention-flagged by vetting). Two models:

- **Token-per-AID** (mint from a known policy): parallel (no shared-UTxO bottleneck),
  proof-simple (reference the AID UTxO directly, datum carries key-state — no MPF proof),
  more permissionless (self-cert mint, no oracle). Loses **global "registered at most
  once"**. The old "self-cert (Ed25519 mint check) ⇒ only the key-holder can mint their
  AID, so no squatting" claim is **retired** (#91 §7c / NOTE-006): the mint signature is
  only against the **claimed** keys — **attribution, not genesis truth** — so without the
  projection verifier it does not prove those keys are encoded in the genuine inception;
  the residual loss is also a single canonical entry for freeze/revocation/burn targeting.
- **MPFS-with-oracle:** the oracle consolidates **three** things in one write —
  **unicity** (on-chain absence proof), the **semantic-projection attestation** (all
  tiers) plus the **byte-binding attestation for >1-chunk** — while the ≤1-chunk byte
  binding is on-chain (#97), so the token model would still need the watcher/oracle for
  the projection — and **batching** (many registrations per MPFS update, amortizing the
  single-UTxO contention that was the token model's main win). Cost: **censorable
  registration** (F7).

Since CF is already the trusted coordinator, the marginal centralization of the oracle is
small. The mandatory-attester premise has **shifted** (#91): the oracle is no longer
required to attest the *whole* AID binding — the ≤1-chunk **byte binding** is
on-chain-verifiable (#97) — but it **is** still required for the **semantic projection**
(all tiers) and the >1-chunk byte binding, which is why MPFS-with-oracle is retained.
Boundary: the oracle absorbs the *AID projection* attestation — credential SAID mappings
still come from the watcher. For ≤1-chunk the byte binding is on-chain (not merely
oracle-asserted); the semantic projection stays oracle-*asserted* and challengeable (§7c).

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

- The four cases only disagreed on whether the credential-mirror roots **R-MAP/R-ACDC** (and
  R-TEL) are needed — and the disagreement traced to one assumption: **Blake2b vs Blake3
  credentials.** In a CF-Blake2b world they collapse to native; in the Blake3 world (the
  forecast) they're **anchored mirrors**. So the methodology *proved* the proof-builder layer
  exists ⇔ Blake3/third-party. Identity **R-KEL** is orthogonal to that axis: the on-chain
  checkpoint over settled R-ID, advanced/anchored by witnessed seals and not a watcher
  mirror — its need does not follow from Blake3/third-party credentials.
- **R-TEL is the universal hot root** (every case gates on it).
- **R-POOL** (SPO) and **R-REG** (securities variant b) are new **native** registers
  (matching vetting F13's "missing core components").
- **Admission cache** pays the expensive verify once; receiver-admission (security tokens)
  is a *cached fact*, not a signature.

## 9. Decisions and open questions

1. **Registration gating — DECIDED (#91): oracle-gated registration, permissionless challenge.**
   Activation requires the oracle's projection attestation (both tiers)
   and, for >1-chunk, its byte-binding attestation — so registration is **oracle-gated** —
   while opening a bonded challenge → freeze is fully **permissionless**. The ≤1-chunk
   byte-binding computation is on-chain, so *submission* of the Step/Finish txs is
   permissionless, but the leaf cannot activate without the projection attestation.
   Residual: censorship + single-attester liveness, with a deferred k-of-n SPO-watcher
   escape (see [identity-model.md](identity-model.md) §7c, decision 1 / NOTE-006).
2. **Identity registry — DECIDED (#91): MPFS-with-oracle** (§6 decision note, §7c decision
   2); the ≤1-chunk byte-binding self-cert is an input to #92, not a reversal.
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
- **Censorable registration (F7)** — registration **is** oracle-gated (#91 §7c decision
  1), so this is a live residual, mitigated only by the deferred k-of-n SPO-watcher escape.
- **CF-parallel interop caveat** — Blake2b creds are spec-compliant but ecosystem-novel.
- The maximal "trustless on-chain verification of the real Blake3 ecosystem" is **bonded-
  bridge until Plutus gains blake3**, not pure-trustless. State it plainly.

---

## 11. Economics & the watcher layer

Added 2026-07-09. Supersedes the earlier "verify data-possession on-chain in every
action" exploration — that was a layering mistake; possession-for-service is a **market**,
not a consensus, concern.

### 11.1 The layering principle (correctness vs service)

- **Correctness is on-chain and watcher-agnostic.** A validator checks a proof against the
  anchored root; a valid proof is valid *regardless of who computed it*. The on-chain layer
  never needs to know a watcher exists to establish correctness.
- **Service is an off-chain market.** Who serves a proof, whether they hold the data,
  promptness, availability — a market concern. A watcher that lacks the data simply can't
  serve a valid proof, the holder goes elsewhere, it earns nothing. **The customer is the
  challenge**; no on-chain possession check is needed for correctness.

The complexity walls we hit earlier (mandatory per-action signatures, liveness coupling,
self-signer tiers) were the symptom of putting the market in the consensus layer. Don't.

### 11.2 Cost structure → who pays (fixed vs marginal)

Two costs, two payers:

- **Watching = fixed / infrastructure cost** (ingest witnesses, maintain the closure's
  credential/external mirror trees — R-TEL/R-ACDC/R-MAP — and serve/submit identity
  checkpoint material). Scales with closure size, not usage. → covered by the **issuer** (who
  benefits from mere *availability* of its credentials on Cardano). Issuer payment *gates
  whether its subtree is watched at all*, which is the lever behind "increase certificate
  production" — no free-riding, because no payment ⇒ no watching ⇒ its holders can't produce
  proofs.
- **Serving proofs = marginal cost** (fresh inclusion proof against the current root, on
  demand). Scales with usage. → covered by **holder micropayments**.

Proofs are **public, recomputable, competitive** data, so you can't charge per-proof
atomically. Charge for the **service** (fresh proof, current checkpoint, on demand, without
running your own watcher) via **prepaid accounts / payment channels** — excludability is
per-*relationship*, not per-proof. Competition floors the price at marginal cost, which is
fine because the fixed cost is already issuer-covered.

### 11.3 What stays on-chain: the trust layer only

- the anchored roots + **root-consensus** (agreement that `R_N` reflects real KERI state),
- **slashing for a provably-wrong anchored root**,
- validators checking proofs against the root — **plain, watcher-agnostic**.

Everything about serving and paying is off-chain.

### 11.4 Paid watchers are SPOs (on-chain reward-qualification)

The **one** place on-chain possession-checking earns its keep is gating **who draws the
on-chain reward pool** — decoupled from user actions, periodic and batched. And the paid set
is **stake-pool operators**:

SPOs already are everything a bonded watcher needs — **bonded** (stake = skin-in-the-game),
**high-availability** (24/7 block infra), **on-chain identity** (the stake-pool registry, no
new watcher registry to bootstrap), **VRF-native** (leader-election keys reused directly),
and **sybil-resistant + decentralized** (inherit Cardano's operator-set properties). Reward
is an **additional SPO revenue stream**. And because paid watchers = SPOs, **root-consensus
rides on the SPO set** — the same operators that produce Cardano blocks anchor the
KERI-mirror roots (the credential/external mirror plane — R-TEL/R-ACDC/R-MAP) and
serve/submit identity checkpoint material, so the mirror inherits Cardano's decentralization.

**VRF-batched challenge/response:**
1. Coordinator posts **one** challenge tx carrying a VRF seed.
2. Each SPO-watcher derives *its own* challenged key from `(its VRF, the seed, its stake)`.
3. Each responds with a tx that **spends the challenge and makes the validator check its
   proof on-chain** — passing is the on-chain witness that it holds the data.
4. Passing SPOs draw the issuer pool (by stake / performance).

One challenge, N independent unpredictable responses; efficient for the coordinator,
un-precomputable for the watcher.

**Anti-collusion (critical):** the per-watcher key must derive from a seed the **coordinator
cannot grind** — the SPO's *own* VRF over a **public unpredictable beacon** (recent block
hash / on-chain randomness). Then neither coordinator nor SPO picks the challenge; it's
forced. This keeps the coordinator **mechanical** (posts a seed, reads verifiable responses,
never chooses) — consistent with §5. The residual risk collapses to "did it use the honest
beacon," itself publicly checkable.

### 11.5 Reconciliation with §2/§5

- User actions never carry a watcher signature — they carry a plain proof against `R_N`.
- The possession challenge is a **separate periodic protocol** between coordinator and
  SPO-watchers, off the user's critical path.
- Non-SPOs may still serve proofs off-chain for direct micropayments (proofs are
  watcher-agnostic); "SPO-only" gates the **on-chain pool**, not the **market**.

### 11.6 Open knobs

- **VRF/beacon source** — must be un-grindable by the coordinator; pin it (it's what kills
  collusion).
- **Sampling cadence** — one round proves one key; over rounds the VRF covers the keyspace,
  so an SPO must hold its whole (shard of the) tree to keep passing. Set cadence for the
  statistical guarantee wanted.
- **Failure semantics** — consensus stake can't be slashed by this protocol, so a failed
  challenge most naturally = **forfeit that round's reward**, not a slash; teeth beyond that
  need a separate watcher-bond.
- **Stake-weighting** — challenge frequency / reward share by stake is natural but tilts
  toward big pools; decide if desired.
- **Cold availability** — usage + on-demand rebuild covers hot data; a thin cold-probe only
  if a use case needs a dormant credential instantly serveable (§7 open question).
- **Micropayment mechanism** — prepaid accounts vs payment channels for holder→watcher.
