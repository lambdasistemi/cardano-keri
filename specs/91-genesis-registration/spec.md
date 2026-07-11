# Feature Specification: Genesis & registration package — decision record

Issue: https://github.com/lambdasistemi/cardano-keri/issues/91
Parent epic: https://github.com/lambdasistemi/cardano-keri/issues/21
PR: https://github.com/lambdasistemi/cardano-keri/pull/95

This is a **design-decision ticket**, not implementation. The deliverable is a
decision-record amendment to the canonical design docs
(`specs/68-keystate-shape/identity-model.md` §7a/§7c and
`specs/68-keystate-shape/system-architecture.md` §6/§9) plus a mechanical
decision-acceptance check. No validator, Haskell, wire-schema, storage-layout,
CESR-parser, adjudicator, or #24 lifecycle code is written here.

## Background — why the earlier conclusion is obsolete

Prior PR #95 stated that genesis **cannot be cryptographic** (§7a, spike #88) and
**cannot even be adjudicated on-chain** (both a true and a forged inception are
receipted by their own declared witness sets — "symmetric circularity"), so the
package engineered only attribution/teeth/time around a one-shot *attested* event.
Two merged evidence gates make that premise obsolete:

- **#97 / PR #98** (merged) landed the complete **32-byte** checkpointed BLAKE3
  path. A single BLAKE3 chunk (inceptions **≤ 1024 bytes**) is verified across an
  **8-block Step + 8-block Finish** transaction chain. Full spend-context worst
  case: Step **70.11 % memory / 73.54 % CPU**, Finish 68.44 % / 72.64 %, against
  the 14 M / 10 G mainnet per-tx budget. Two honesty caveats travel with it:
  (a) the figure **excludes** ledger→script `Data` deserialization of the
  ~1024-byte redeemer, so it is a **lower bound**; (b) it is a **multi-tx** path
  whose intermediate chaining value must be authenticated — the spike explicitly
  says it does **not** implement that lifecycle (owned by #99/#24/#92).
- **#99 / PR #100** (merged) restored the cage/thread-token boundary: an oracle is
  **necessary but never sufficient** to manufacture AID authority or mutate
  another AID's leaf; owner auth is against **authenticated** state; keys are bound
  via `blake2b_256(owner_aid)`; a **real cardano-node Phase-2** proof settled a
  real `Modify`; batch bound **qualified** (mainnet ≈ N=2 at conservative declared
  budgets). #99 proves cage invariants; it does **not** integrate the #97
  checkpoint into genesis registration.

So `blake3(icp) == cesr_aid` is now an **on-chain-checkable predicate for the
single-chunk domain**, dissolving the "symmetric circularity" argument *there*.
The ticket re-aims on this evidence and **explicitly selects** a genesis model,
enumerating every remaining trust assumption honestly.

## Decision (selected): deliberately hybrid, two axes

### Axis 1 — the *byte binding* `blake3(icp) == cesr_aid`

- **Single-chunk inceptions (≤ 1024 B): cryptographic, on-chain.** Verified in
  Plutus via the #97 checkpointed Step+Finish chain. **Required integration
  invariant (not yet built):** the integrated genesis path MUST confine the
  intermediate chaining-value state in a #99-style cage/thread-token so no attacker
  can inject a forged mid-chunk value; #97's spike does not implement this and its
  measurements exclude it — the integration and its remeasurement are **#24/#92
  work**. Given that invariant holds, this axis **cryptographically prevents
  cross-AID impersonation** (nobody can present bytes hashing to a victim's AID)
  and is **on-chain-decidable and autonomous** — no trusted party.
- **Multi-chunk inceptions (> 1024 B): attested,** pending a native `blake3`
  builtin (multi-chunk tree hashing is out of #97 scope). The oracle attests
  `blake3(icp) == cesr_aid` off-chain; its fraud is **off-chain-recomputable**,
  **not** provable on-chain.

### Axis 2 — the *semantic projection* (stored key-state ⇄ CESR decode of bound bytes)

Even with the raw bytes bound (Axis 1, ≤1-chunk), hashing does **not** prove the
stored `(keys, kt, next_digest, witnesses, toad, native_sn)` is a faithful **CESR
decode** of those bytes — that needs an on-chain CESR field extractor, **out of
scope** here (no CESR parser authorized). Therefore the projection is **attested
at registration** and policed by challenge/freeze/adjudication (see Teeth). A
fully-trustless **on-chain CESR projection verifier** is named as a **deferred
future hardening**, not this ticket.

### Decision 1 (gating) — SELECTED: registration is oracle-GATED; the challenge is PERMISSIONLESS

Registration requires the registration-oracle's projection attestation (both
tiers) and, for >1-chunk, its byte-binding attestation — so **registration is
gated**. The ≤1-chunk byte-binding *computation* is on-chain and permissionlessly
verifiable, so **submission** of the Step/Finish byte-binding txs is permissionless,
but the leaf cannot **activate** without the oracle's projection attestation. In
contrast, **challenging** a registration is fully permissionless (anyone posts a
bonded challenge → freeze). Residual trust: **censorship** — the oracle can refuse
to attest; bounded by mechanicalness (a correct projection is off-chain-
reproducible, so refusal is *provable* censorship — reputational/contractual, not
epistemic) with a **deferred k-of-n SPO-watcher attestation** escape hatch (the
§11 bonded set); and a **single-attester liveness** dependence the escape hatch
mitigates.

### Decision 2 (registry) — SELECTED: MPFS-with-oracle

The oracle is still required for the semantic-projection attestation (all tiers)
and the >1-chunk byte-binding attestation, so the mandatory-attester argument that
retired the token model's self-cert mint **still holds for the projection**.
MPFS-with-oracle consolidates unicity (at-most-once absence proof), the projection
attestation, and batching in one write. The ≤1-chunk byte binding now
self-certifies on-chain — a **partial** revival of the token model's self-cert
story — but it does **not** remove the oracle (projection stays attested), so it
does not reverse this selection; it is recorded as an **input to #92's** advance-
path storage-shape choice (trie vs per-AID UTxO vs hybrid), which this ticket does
not decide.

### Teeth — bonds, windows, activation (state machine, not adjectives)

Numeric values are governance-set; **names, transitions, and Δ > 0 are decided
here**. Leaf states: `provisional → active`, with `frozen` reachable from either.

Named parameters:
- `bond_reg` — registrant bond, posted at registration.
- `bond_chal` — challenger bond, posted to open a challenge.
- `Δ_challenge` — challenge window; `provisional → active` after Δ if unchallenged
  (Δ > 0; suggested default 48h, governance-set — vLEI onboarding is slow, latency
  is cheap).
- `Δ_adjud` — adjudication timeout for a trusted-quorum verdict on a frozen leaf.
- `Δ_post` — finite post-activation challenge window.
- **Tier rule:** `bond_reg` scales with attestation surface —
  `bond_reg(≤1-chunk) < bond_reg(>1-chunk)` (>1-chunk attests *both* axes, weaker
  assurance), the exact ratio governance-set.

Transitions / invariants:
1. **Register:** post `bond_reg`; byte binding proven on-chain (≤1-chunk) or
   attested (>1-chunk); projection attested; leaf → `provisional`; `Δ_challenge`
   starts. `bond_reg` locked.
2. **Challenge (permissionless):** post `bond_chal`; leaf → `frozen`; `Δ_challenge`
   suspended; gated actions blocked.
3. **Adjudicate (trusted governance key / k-of-n quorum, off-chain-reproducible
   evidence):**
   - *upheld* (fraud confirmed): `bond_reg` slashed → bounty to challenger;
     `bond_chal` returned; leaf retracted (controller may re-register correctly).
   - *rejected* (false challenge): `bond_chal` **forfeited → registrant** (this is
     the anti-griefing lever that makes permissionless freeze safe); `bond_reg`
     retained; leaf → prior state (`provisional`/`active`), timer resumes.
   - *timeout* (`Δ_adjud` elapses with no verdict): **safe default = leaf stays
     `frozen`** (fail-safe, favors the possible victim); liveness escalation to the
     SPO-watcher quorum is the deferred path.
4. **Activate:** after `Δ_challenge` with no upheld challenge, `provisional →
   active`; gated actions (§2) require `active`. `bond_reg` is **retained** through
   `Δ_post` to fund post-activation challenges, then released.
5. **Post-activation fraud:** remains **challengeable during `Δ_post`** with
   `bond_reg` still available. After `Δ_post` the *bonded remedy* ends — an honest
   **finite assurance window**. Detectability is not finite: for ≤1-chunk the byte
   binding is cryptographic (cross-AID impersonation impossible), and any projection
   inconsistency stays **off-chain-reproducible forever** over the on-chain-bound
   bytes; only the *automated* remedy is time-boxed.

### Adjudication boundary (NOTE-004) — trusted, not trustless

The on-chain reaction is **permissionless bonded challenge → mechanical freeze**
(fail-safe, no adjudication). The **slash / unfreeze outcome is authorized by an
explicitly trusted governance key / k-of-n quorum**, using off-chain-reproducible
recomputation as evidence — **not** a trustless Plutus fraud proof, until an
on-chain CESR projection verifier exists. Same boundary for the >1-chunk attested
byte binding. The record must **not** call projection fraud or the >1-chunk
attested digest "objectively provable on-chain"; only the ≤1-chunk byte binding is.

### Signed registration package (OOBI-style, design shape only)

Controller-signed and oracle-co-signed evidence binds, at minimum (no wire schema
here — #68 freezes serialization):
- **domain/version** tag (protocol id + version — replay/domain separation);
- **`cesr_aid`** — the complete 32-byte AID digest (per #97 FR3; no truncation);
- the **inception commitment** — `input_commitment = blake2b_256(icp_bytes)` (the
  #97 datum field) binding the exact inception bytes the checkpoint chain verifies;
- the **projected key-state** `(keys₀, kt₀, next_digest₀, witnesses₀, toad₀,
  native_sn₀)` the registrant claims is the decode;
- a **nonce / consumed output reference** (anti-replay + unicity, mirroring #99's
  mint deriving its asset name from the consumed ref);
- the **tier** (≤1-chunk cryptographic vs >1-chunk attested).

Signatures: **controller** signs with `keys₀` (Ed25519, on-chain-verifiable
against `keys₀`) — proves control of the registered keys; **oracle/attester**
co-signs the same binding — attests the projection is a faithful CESR decode (both
tiers) and, for >1-chunk, `blake3(icp)==cesr_aid` off-chain.

**Witness role / genesis circularity:** the genesis seal's threshold receipts are
verified against the *claimed* `witnesses₀` — circular for truth, but proves the
claimed set exists, cooperates, and receipted this exact claim (one more artifact a
forger must fabricate). For ≤1-chunk the byte binding makes the claimed set the
**genuine** set (only genuine bytes hash to the AID), **breaking the circularity
for the binding**; the receipts corroborate, they are not the root of trust. For
>1-chunk the circularity persists (attested).

### Activation timing (summary)

- ≤1-chunk: byte binding proven on-chain at the Finish tx (immediate for the
  binding); leaf `provisional` for the projection until `Δ_challenge` → `active`.
- >1-chunk: fully attested on both axes → `provisional` + full `Δ_challenge` +
  larger `bond_reg`.

## Remaining trust assumptions (enumerated)

- **controller** — holds `keys₀`, presents inception bytes + signed statement.
- **witnesses** — honest threshold (unchanged KERI assumption) for advances; at
  ≤1-chunk genesis the byte binding does not rest on them; at >1-chunk it does not
  either (attested by oracle) — receipts are corroborating evidence.
- **oracle/attester** — attests projection (all tiers) + byte binding (>1-chunk);
  **necessary but not sufficient** (#99) — cannot forge authority; can **censor**
  by refusing to attest, and is a **liveness** dependency.
- **challenge / fraud proof** — ≤1-chunk byte binding is trustless on-chain;
  projection and >1-chunk byte binding are permissionless-challenge / mechanical-
  freeze but **trusted-adjudicated** slash/unfreeze.
- **gating / censorship** — registration gated (oracle attestation); censorship is
  *provable* (mechanicalness-bounded) with a deferred SPO-watcher escape.
- **slashing / bonds** — `bond_reg`/`bond_chal` teeth are **trusted-adjudicated**,
  not a trustless fraud proof, until the on-chain CESR projection verifier exists;
  false-challenge forfeiture deters freeze-griefing.
- **adjudicator liveness / collusion** — the trusted governance/quorum can stall
  (mitigated by the `Δ_adjud` fail-safe freeze) or collude to wrongly slash/unfreeze
  — an explicit, bounded, visible trust (bond a decentralized quorum to reduce it).
- **activation timing** — provisional→active after Δ; frozen while challenged.
- **objectively checkable on-chain** — ≤1-chunk byte binding: **yes**; semantic
  projection: **no**; >1-chunk byte binding: **no**.

## Merged evidence vs unimplemented integration (honesty separation)

- #97 measures the checkpoint core/handler **only**; it **excludes** the #99
  state/thread lifecycle and the ledger `Data` boundary — its ~70–74 % is a
  **lower bound**, not a genesis-path cost.
- #99 proves cage invariants and a real-node `Modify` boundary; its Modify **N ≈ 2**
  (mainnet, conservative declared budgets) is **not** a genesis-registration batch
  bound.
- The **integrated genesis path** (checkpoint Step/Finish + cage confinement +
  projection attestation + teeth) is **unbuilt and unmeasured**. Any statement that
  the intermediate value "is confined" is a **required #24/#92 integration
  invariant**, phrased as such — not an implemented fact. The integrated path
  **must be remeasured** before any budget claim.

## Clarifications

### 2026-07-11 — NOTE-003 (semantic-projection boundary)
The measured BLAKE3 fit does **not** make genesis fully trustless. #97 binds the
AID to the raw inception bytes; it does not prove the stored key-state is a faithful
CESR projection. Boundary named: **cryptographic byte binding + attested /
challengeable semantic projection**. Projection fraud is reproducible off-chain,
not decidable on-chain here.

### 2026-07-11 — NOTE-004 (adjudication / slashing boundary)
Off-chain-reproducible ≠ Plutus fraud proof. **Remedy (b):** permissionless
challenge/freeze on-chain; trusted governance/quorum authorizes slash/unfreeze; the
trustless on-chain CESR projection verifier is deferred. Same for the >1-chunk
attested tier. No "objectively provable on-chain" claim for projection / >1-chunk.

### 2026-07-11 — NOTE-005 (plan review)
(1) Decisions 1 & 2 explicitly selected above (oracle-gated registration /
permissionless challenge; MPFS-with-oracle) with residual censorship/liveness
trust. (2) Bonds/windows/activation promoted to a named state machine. (3) The
signed OOBI-style registration package pinned as a design shape. (4) Merged
evidence separated from the unbuilt, unmeasured integrated path.

## P1 user story

As a protocol designer ratifying the identity model, I read the amended
`identity-model.md` §7c and `system-architecture.md` §6/§9 and find an explicit,
evidence-backed hybrid genesis selection with decisions 1 & 2 resolved, a named
teeth state machine, the signed-package shape, every remaining trust assumption
named, honest separation of merged evidence from the unbuilt integration, and no
obsolete "BLAKE3 cannot fit" premise.

## Functional requirements

- **FR1.** §7c rewritten to the **hybrid** selection on both axes; §7a updated so it
  no longer asserts the obsolete "genesis is not cryptographic" as current
  (≤1-chunk byte binding is now on-chain; projection still attested).
- **FR2.** NOTE-003 projection boundary and NOTE-004 remedy (b) named; deferred
  on-chain CESR projection verifier named as the trustless future.
- **FR3.** Single scannable **trust-assumption enumeration** (the list above) in §7c.
- **FR4.** `system-architecture.md` §6 and §9 resolve **decision 1** (oracle-gated
  registration / permissionless challenge) and **decision 2** (MPFS-with-oracle)
  consistently with the shifted premise; §3 R-KEL note reflects byte binding; no
  decision left on the obsolete mandatory-attester-for-everything rationale.
- **FR5.** Explicit consequences for **#92** (2-tx checkpoint chain; cage-confined
  intermediate as a required invariant; provisional/active/frozen states; remeasure
  — #99 Modify N is not the genesis bound), **#68** (pin inception CESR
  serialization + #97 checkpoint datum/redeemer + projection fields with
  Haskell/Aiken golden parity; on-chain projection verification flagged deferred),
  and the **#24 re-cut** (base case = cryptographic byte-binding genesis +
  challengeable projection + cage integration; attested residual for >1-chunk) —
  **without absorbing** them.
- **FR6.** Honest capability language: no generic-KERI interop claim, no
  production-readiness claim; prototype framing preserved; #97/#99 links present.
- **FR7.** **Teeth state machine** (bonds `bond_reg`/`bond_chal`, windows
  `Δ_challenge`/`Δ_adjud`/`Δ_post`, tier rule, all transitions incl. false-challenge
  forfeiture and adjudication timeout) present in §7c.
- **FR8.** **Signed registration package** shape (bound fields + controller/oracle
  signatures + witness circularity) present in §7c.
- **FR9.** `accept.sh` mechanically asserts FR1–FR8: presence of decision markers,
  decisions 1 & 2, the teeth parameters/transitions, the signed-package fields, the
  trust enumeration, the #92/#68/#24 consequences, the evidence/integration
  separation, the #97/#99 links; **absence** of the obsolete conclusion and of any
  "objectively provable on-chain" claim adjacent to projection / >1-chunk binding.
  RED on `origin/main`, GREEN after the slice.

## Success criteria

- [ ] `./gate.sh` passes locally at HEAD before mark-ready.
- [ ] `accept.sh` demonstrably RED on the pre-decision tree, GREEN after the slice.
- [ ] One bisect-safe decision commit carrying `Tasks: T911, T912, T913, T914`.
- [ ] PR #95 body and issue #91 drop the obsolete premise and link #97/#98, #99/#100.
- [ ] Fresh GitHub CI green; PR-life `gate.sh` dropped before mark-ready.

## Out of scope (do not implement)

- Any validator, Haskell, wire-schema, or storage-layout code.
- An on-chain/off-chain **CESR parser / projection verifier** — deferred future only.
- The **adjudicator / governance-quorum mechanism** implementation — trust
  assumption only.
- #24 lifecycle, #92 storage model, #68 schema freeze — **consequences** documented,
  not solutions.
- Sibling ticket branches/worktrees; reverting merged #97/#99. #92 waits for #91.
