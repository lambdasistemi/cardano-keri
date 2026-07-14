# Identity model — KERI-sovereign, on-chain checkpoint, witnessed anchoring event

Status: **design decision, drillable.** Captured 2026-07-09. This reshapes #24, #68,
and #10, and refines `system-architecture.md` (identity key-state is now an on-chain
checkpoint, not a watcher-attested mirror). Open threads to drill are listed at the end.

Amended 2026-07-09 after adversarial validation: two limits of the "cryptographic"
claim stated explicitly (§7a — genesis binding, seal↔native correspondence); receipt
mechanics corrected against keripy (receipts sign **raw event bytes**, so the blake2b-SAID
requirement is **dropped** — §5); witness-set rotation elevated to a ratification blocker
and then **drilled to resolution the same day** (§6a — the two-seal handoff). Spike #88
reopened the genesis in-script-blake3 performance question on 2026-07-10, and the
lane-packed second pass the same day extended the fit to the whole single-chunk
domain. Genesis was then **decided 2026-07-11 (#91)** on that evidence: two merged
gates — **#97/#98** (the 32-byte checkpointed BLAKE3 path — a single ≤1024-byte chunk
verified across an 8-block Step + 8-block Finish chain) and **#99/#100** (the
cage/thread-token boundary) — make `blake3(icp) == cesr_aid` an on-chain-checkable
predicate for the single-chunk domain. Genesis is therefore now a **deliberately
hybrid** selection (§7c): cryptographic byte binding for ≤1-chunk inceptions, attested
for >1-chunk, with the semantic projection attested and challengeable at every tier.
Correspondence (open thread 4) **drilled via #90** (§7b — required, fraud-proof
policed). All pre-ratification threads are now drilled: the genesis/registration
package (thread 3, #91) is resolved in §7c; contention (thread 8) is **resolved by #92** —
the sovereign per-AID checkpoint (§10).

---

## 1. The decision: identities are KERI-sovereign

There must be **no chance of forking an identity.** So an identity lives in the
**KERI / vLEI domain** — the witnessed KEL is the single source of truth — and Cardano
**anchors** it, never runs a second, independently-rotating copy. One state machine.
This retires the "two independent state machines" tension (and the divergence-burn that
policed it).

Precision: "one state machine" holds at the **event-log** level — the seal chain lives
inside the one witnessed KEL. Whether the seal chain's *claimed key-state* matches the
native Blake3 key-state in that same KEL is a separate, weaker guarantee — see §7a.

## 2. How Alice consumes her identity in a transaction (bring-your-own-proof)

Alice does **not** hold or spend an identity UTxO. Per gated action she carries a
self-contained proof:

- `cesr_aid` — her KERI AID (the opaque identity handle),
- `key_state` — her current keys revealed `[(pubkey, weight)...]`, threshold,
- an **inclusion proof** that `cesr_aid → commit(key_state)` is in the anchored
  checkpoint at `R_N`,
- **weighted k-of-n detached signatures** (Option A / #39) over the action,
- admission + non-revocation proofs,

and references, read-only (CIP-31), the **anchor UTxO** (`R_N`) and the admission-cache
UTxO. The validator checks: inclusion vs `R_N`, revealed keys match the commitment,
threshold signatures verify, admission + non-revocation, freshness. Because everything is
a **reference input**, identity use is inherently parallel — no identity-UTxO contention.

## 3. Why the key-state is an *incremental checkpoint*, not a KEL replay

A KEL is **unbounded** — no validator can replay it from inception. So identity is a
**checkpoint advanced one event at a time**: `state@seq N` + `rotation N+1` → validator
checks the single event against the current state → `state@seq N+1`. **O(1) per event**,
bounded. And only **establishment (rotation) events** change keys — interaction events
don't — so the on-chain cadence is *one tx per rotation* (rare), not per KERI event.
That per-rotation advance now has a **decided physical home**: each AID's **own** sovereign
per-AID checkpoint UTxO (#92, 2026-07-14 — §10 thread 8).

**This is exactly #24** (reveal pre-committed next key, check `hash(revealed)==next_digest`,
threshold sig, advance seq). #24 is therefore revived as the **integrity backbone**, not a
retired idea: the state only advances through validator-checked rotations, so no party can
inject fake keys — there is **no additional watcher/oracle trust to add for post-genesis
advances** (the genesis projection stays attester-trusted per §7a/§7c).

One caveat travels with the revival: original #24 derived `trie_key` from inception
material, so its **base case was self-certifying** in blake2b. Here the leaf key is an
external **Blake3** AID, so the base case is now the **hybrid** genesis of §7a/§7c: the
induction *step* is unchanged; the genesis **byte binding** `blake3(icp) == cesr_aid`
**self-certifies on-chain for ≤1-chunk inceptions** (#97) and is attested for >1-chunk,
while the **semantic projection** is attested / challengeable at every tier.

## 4. The special anchoring event that drives the checkpoint

For a **Blake3** (real vLEI) controller, Cardano cannot verify the native rotation event
(no `blake3` builtin). Resolution: the controller emits a **special anchoring seal** into
her own KEL — a **witnessed** interaction/anchor event (a plain native event, **Blake3
SAID like any other** — see §5 for why no blake2b SAID is needed) whose seal data carries
a **blake2b** commitment to the new key-state (reveal pre-committed next keys, commit the
new `next_digest` in blake2b), signed by the (new) keys.

- **KERI-sovereign** — the seal is in the one witnessed KEL; no separate machine, no fork.
- **Cardano-cryptographic without a builtin** — Cardano verifies the seal's **blake2b
  payload commitments** and its **Ed25519 witness receipts** (§5), never the Blake3
  rotation. The invent-key-material hazard (§7) closes *for every advance after genesis*
  (§7a).
- **Ecosystem-compatible** — the native AID/KEL stays Blake3; the controller merely *adds*
  a seal whose *payload digests* are blake2b. The event itself needs **no digest-agility
  patch anywhere** (§5) — far lighter than mandating blake2b agility on the whole `n`
  field, and lighter than this doc's first draft assumed.
- **KERI-idiomatic** — seals/anchors are native KERI; this is the "normative KERI
  checkpoint / event anchor" the original two-agent analysis (`system-discussion.md`)
  already recommended, re-derived from the integrity angle.

The controller must **emit** the seal per rotation — an SDK requirement in the same family
as the F-prefix work (#42). Cost: one seal + one Cardano advance tx per (rare) rotation.

## 5. Signature vs. witness — and why no-fork demands *witness*

What does Cardano check on the seal?

- **Signature-only** — that the controller's keys signed it. Proves *authorization*, but
  she can sign a **different** seal for the KERI world → Cardano and KERI **fork**. Trust
  bottoms out at *the controller not equivocating*.
- **Witness-receipted** — that the seal carries **threshold witness receipts**. KERI
  witnesses refuse to receipt two conflicting events at one sequence (duplicity
  protection), so the seal Cardano sees **must** be the one KERI sees → **no fork**. Trust
  bottoms out at *the controller's own witness set (honest threshold)* — exactly KERI's own
  assumption, no new trusted party.

**The no-fork decision (§1) forces witness-receipted.** Signature-only re-opens the fork.

Cost of witness-receipting: Cardano must (a) track the **witness set + toad** as part of
the checkpoint (they change through the two-seal handoff — §6a), and (b) verify
threshold Ed25519 receipts over the seal.

**Corrected against keripy (2026-07-09).** Witness receipts sign the **raw serialized
event bytes**, not the SAID — `Kevery.processReceipt` / `valSigsWigsDel` verify
`verfer.verify(sig, serder.raw)`. So Cardano checks
`Ed25519.verify(witness_pk, seal_bytes, receipt_sig)` **directly over the seal bytes it
already holds — no SAID recomputation at all**. Consequences:

- the seal keeps its **native Blake3 SAID**; the former "blake2b-SAID'd seal" requirement
  and its digest-agility open thread **dissolve**;
- the real on-chain cost moves to **parsing** the seal's serialization to extract the AID,
  `s`, and the payload commitments — so the seal's serialization kind + field layout must
  be **pinned** (open thread 2).

## 6. The checkpoint state (what the leaf holds)

The advancing checkpoint per `cesr_aid` holds more than keys:

```
Checkpoint {
  keys        : [(pubkey, weight)...]   -- current establishment keys (KERI k)
  threshold   : kt                       -- weighted k-of-n (KERI kt; fractional clauses — F18)
  next_digest : blake2b(next key config) -- pre-rotation commitment (blake2b)
  witnesses   : [witness_pubkey...]      -- current witness set (KERI b)
  toad        : Int                      -- witness threshold (KERI bt; NOT nt — nt is the
                                         --   next-KEY threshold, don't reuse the name)
  seq         : Int
}
```

**Physical storage (decided — #92, 2026-07-14).** This advancing checkpoint per `cesr_aid`
lives in its **own** sovereign, per-AID, quantity-one uniquely-tokenized checkpoint UTxO
(Candidate A — §10 thread 8): the state above is that UTxO's inline datum, and unrelated
AIDs cannot consume or serialize it. This is a *physical-storage* selection only; it does
not alter the R-KEL classification (§7c / `system-architecture.md`).

Both the signing keys **and** the witness set advance through witness-receipted seals.
Which set receipts a witness-set change was the sharp question — verified keripy behavior
cuts both ways:

- KERI counts a rotation's receipts against the **new** set and new toad
  (`Kever.update` → `self.rotate(serder)` → `valSigsWigsDel(wits=new)`), and a
  post-rotation seal is receipted by the **then-current (new)** set.
- So a naive "receipted by the *old* threshold" rule **deadlocks** — cut witnesses have no
  duty to receipt anything after removal — while accepting the new set's receipts lets the
  checking set be **swapped inside the very event being checked**, voiding the duplicity
  argument behind no-fork (§5).

The resolution is the two-seal handoff, drilled in §6a.

### 6a. Witness-set rotation: the two-seal handoff

**Rule: every checking set endorses its successor.** The chain of witness custody must be
unbroken from genesis — Cardano never checks receipts against a set that was not itself
endorsed by the previously checked set. The mechanism exploits timing: a witness change is
announced *while the outgoing set is still in office*.

1. **Seal W (handoff pre-announcement).** Before the native rotation, the controller emits
   an interaction event whose seal data carries a blake2b commitment to the incoming
   configuration `(W', toad')`. Signed by the current keys; receipted by the **outgoing**
   set — natively and willingly, because at this sequence number they *are* the current
   witnesses (no post-removal duty is ever invoked, which is what killed the naive
   old-set rule).
2. **Native rotation** follows in the KEL (Blake3, receipted per KERI by the new set —
   Cardano never reads it).
3. **Seal K (the §4 advance seal).** Post-rotation: reveals the pre-committed new keys,
   commits the next digest, signed by the new keys, receipted by the **incoming** set
   `W'`.

**One Cardano tx can carry both seals**: the validator checks Seal W against the *stored*
`(witnesses, toad)`, then Seal K against the just-endorsed `(W', toad')`, and advances the
checkpoint once. No "pending" state needs to persist on-chain, and a pure key rotation
(witness set unchanged) needs only Seal K, exactly as in §4–5.

**Why no-fork survives.** The checking set can no longer be swapped inside the checked
event: introducing a disjoint set requires the outgoing threshold to receipt the handoff,
and two conflicting handoffs at one sequence number are duplicity against the *same*
outgoing set — the very protection §5 already relies on. Induction restored: every
checking set is endorsed by its predecessor, back to genesis (whose own binding is §7a's
stated limit).

**Cost: stricter than native KERI.** KERI lets key authority alone rotate witnesses; this
rule adds outgoing-set consent for the *Cardano-facing* handoff. The consequence is a
liveness dependence: an outgoing set that withholds receipts (dead or hostile beyond the
toad margin) can hold the checkpoint's witness evolution hostage — it cannot forge, only
freeze. Note this scenario already breaks the model's *existing* trust assumption (§5:
honest threshold of the controller's own witnesses), and it degrades plain KERI liveness
for that AID too (the same witnesses gate native receipting).

**Liveness fallback (explicit, time-locked degradation).** If the outgoing threshold is
unreachable, allow a **signature-only witness reset**: a seal signed by the current keys
without outgoing receipts, which activates only after a challenge window Δ; during Δ, any
conflicting outgoing-receipted seal wins, and watchers can raise the alarm. Trust during
the fallback degrades exactly to "the controller's keys + time + public observability" —
bounded, visible, and only reachable when the model's base assumption has already failed.

**Out of scope here:** KERI superseding/delegated recovery (no delegated AIDs in this
model yet); divergence between the announced `W'` and the native rotation's actual set is
the §7a correspondence limit (open thread 4), unchanged.

## 7. What this settles: the integrity hazard

The sharpest residual risk was **forged key material**: a colluding watcher/SPO quorum
anchoring fake keys for `cesr_aid` (impersonation), which in the watcher-mirror model is
neither preventable nor punishable on-chain (both need Blake3). The on-chain checkpoint
**closes it for every advance after genesis**: the key-state advances only through
**validator-verified, witness-receipted** seals, so third parties cannot inject keys —
integrity of *advances* is **cryptographic**, resting on the controller's own witnesses,
not on watcher honesty. The two places where "cryptographic" does **not** reach are stated
next.

### 7a. Two stated limits

**Genesis byte binding — now cryptographic for single-chunk inceptions (#97).** The
checkpoint is an induction; the base case is the byte binding `blake3(icp) ==
cesr_aid`. #97/#98 landed the 32-byte checkpointed BLAKE3 path, so for a
**single-chunk** inception (≤ 1024 B) this predicate is **verified on-chain** in
Plutus and no longer rests on a trusted assertion. For **multi-chunk** (> 1024 B)
inceptions the byte binding stays **attested** (oracle-recomputable off-chain, not
provable on-chain) pending a native `blake3` builtin. What hashing does **not** settle
is the **semantic projection**: that the stored `(keys, kt, next_digest, witnesses,
toad, native_sn)` is a faithful CESR decode of the bound bytes is **attested and
challengeable**, not on-chain-decidable here (no CESR parser authorized). So genesis is
no longer a flat trusted base case — it is the **deliberately hybrid** selection
detailed in §7c, where the full decision, teeth, signed package, and remaining trust
assumptions live. The receipt check is still **circular at inception** — the witness
set Cardano would verify receipts against is exactly what the genesis leaf asserts — so
overall genesis authority remains attester-trusted at that projection boundary (§7c).

**Witnesses receipt events, not truth.** Receipts attest ordering and duplicity-freedom;
nobody validates that a seal's *claimed* key-state matches the native Blake3 `k`/`n`
fields in the same KEL. The seal chain is internally enforced (blake2b pre-rotation), but
its correspondence to the native key-state is not witnessed-into-truth: a controller
can maintain two divergent key-state threads in one witnessed KEL with zero duplicity —
**self-equivocation, not third-party forgery**. *Drilled (#90):* this is **policed via
on-chain divergence fraud proofs** — objective wherever the stored witness threshold
receipted the divergent native event, watcher-attested for the witness-swap residual.
See §7b.

Corollary that refines "Blake2/Blake3 doesn't fork the system": it doesn't change the
*shape*, but it **does** change the *integrity model*:

| Path | Identity integrity |
|---|---|
| On-chain checkpoint via **blake2b seal** (this doc) | **cryptographic from genesis for advances** — they rest on the controller's witnesses; the genesis **byte binding** is cryptographic on-chain for ≤1-chunk (#97), attested for >1-chunk; the semantic **projection** is attested / challengeable (§7c) |
| Watcher-**mirror** of native Blake3, no seal | **honest-majority-trusted** — the invent-hazard, on every read |
| Native Blake3 + a future Plutus `blake3` builtin | cryptographic (verify the KEL directly; genesis self-certifies via the AID prefix) |

### 7b. Correspondence policy: police, via on-chain fraud proofs (drilled — #90)

**Decision: correspondence is required** — the seal's claimed key-state must equal the
native establishment key-state at the bound sequence number. Divergence is not an
"operating keys" feature; the regulated business cases gate actions on *the credentialed
identity's* keys, and a silent split between "who KERI says acts" and "who Cardano lets
act" breaks exactly the attribution the product sells. (Institutions that genuinely need
distinct signing infrastructure have KERI's own idiomatic answer — **delegated AIDs** —
out of scope until delegation enters the model.)

**The upgrade that makes policing cheap:** the §5 raw-bytes fact applies to *native*
events too. A native rotation is bytes; its `k` field is parseable; its witness receipts
are Ed25519 signatures **over those bytes**. So Cardano can verify a **divergence fraud
proof** with no Blake3 anywhere:

```
FraudProof {
  native_event   : ByteArray        -- the establishment event at the seal-bound sn
  receipts       : [(idx, sig)...]  -- threshold witness receipts over native_event
}
-- validator: parse sn and k from native_event;
--   sn == checkpoint.native_sn,
--   threshold receipts verify against checkpoint.witnesses/toad,
--   parsed k ≠ checkpoint.keys  →  divergence proven
```

The proof is **objective and witness-attributable**: the controller's own stored witness
threshold receipted an establishment event whose keys contradict what her seal told
Cardano. Consequence on success: **freeze the leaf** (safe default). Whether a deposit
slash rides on top is **decided by the §7c teeth** (#91): an upheld-fraud verdict slashes
`bond_reg` → bounty; only the numeric bond/window values remain governance-set. The
controller can recover by advancing the checkpoint with a corrective seal.

**Requirement on the seal (new):** the seal payload must bind the **native sequence
number** (`native_sn`) of the establishment event it mirrors — otherwise the
correspondence claim is not precise enough to be falsifiable on-chain. (It may also carry
the native event's SAID as opaque bytes for off-chain audit; Cardano never verifies it.)

**Stated residual — the witness-swap escape.** A single native rotation that *both*
diverges the keys *and* replaces the witness set beyond the stored toad is receipted only
by the new set (keripy counts receipts against the post-rotation set, §6), so the fraud
proof cannot verify its receipts against the stored set. That divergence remains
**off-chain falsifiable** (anyone replaying the KEL sees it) but not on-chain-provable —
it degrades to the watcher-attested freeze path, the same trust grade as genesis (§7a).
Under the model's base assumption (honest threshold of the *stored* set) the escape
requires the controller to burn her entire witness relationship in one event — loud,
attributable, and exactly what the §6a handoff refuses to endorse on the Cardano side.

**Role assignment:** submitting fraud proofs is the super-watcher's identity-plane job
(#10) — permissionless, bounty-compatible, and the divergence-proof/burn mechanics
already designed there transfer with the receipts-over-raw-bytes simplification.

This upgrades §7a's second limit from "rests on controller honesty" to **"fraud-proof
policed — objective wherever the stored witness threshold receipted the divergent event;
watcher-attested for the witness-swap residual."**

### 7c. Genesis & registration: the deliberately hybrid decision (#91)

**Decision (2026-07-11, #91): a deliberately hybrid genesis on two axes.** Two merged
evidence gates re-aim the earlier conclusion — **#97/#98** made `blake3(icp) ==
cesr_aid` an on-chain-checkable predicate for the single-chunk domain, and **#99/#100**
restored the cage/thread-token boundary — so the selection is a **hybrid**: cryptographic
byte binding for ≤1-chunk inceptions (attested for >1-chunk) plus an **attested,
challengeable** semantic projection at every tier.

#### Axis 1 — the byte binding `blake3(icp) == cesr_aid`

For **single-chunk** inceptions (≤ 1024 B) the byte binding is **cryptographic, on-chain** — verified via the #97 checkpointed Step+Finish chain — so the ≤1-chunk byte binding is **objectively provable on-chain** and autonomous for the binding itself.
For **multi-chunk** (> 1024 B) inceptions the byte binding is **attested** — oracle-recomputable off-chain, not on-chain-decidable — pending a native `blake3` builtin (multi-chunk tree hashing is out of #97 scope).
The ≤1-chunk byte binding cryptographically **prevents inception-byte substitution** under a given AID (nobody can present *other* bytes that hash to the AID); it does not by itself prevent **impersonation** — the separately-stored projection `(keys₀, …)` that confers authority is never compared to the bytes on-chain, so a corrupt attester can co-sign attacker `keys₀`/`witnesses₀` beside the victim's genuine raw bytes.
**Overall genesis authority therefore remains attester-trusted at the projection boundary** until the deferred on-chain projection verifier exists.

#### Axis 2 — the semantic projection

Even with the raw bytes bound, hashing does **not** prove the stored `(keys, kt, next_digest, witnesses, toad, native_sn)` is a faithful CESR decode; the **semantic projection** is therefore **attested at registration** and policed by **challenge / freeze / adjudication** (**NOTE-003** boundary: cryptographic byte binding ≠ semantic projection).
A fully-trustless **on-chain CESR projection verifier** is named as a **deferred** future hardening — not authorized here — and closing it is what would make the projection on-chain-decidable.

#### Decision 1 (gating) — SELECTED: registration is oracle-gated; the challenge is permissionless

**Decision 1 (SELECTED):** registration is **oracle-gated** — the projection attestation (both tiers) and, for >1-chunk, the byte-binding attestation are required to activate a leaf — while **challenging** a registration is fully **permissionless** (anyone posts a bonded challenge → freeze).
The ≤1-chunk byte-binding *computation* is on-chain and permissionlessly verifiable, so **submission** of the Step/Finish txs is permissionless, but the leaf cannot **activate** without the oracle's projection attestation. Residual trust: **censorship** — the oracle can refuse to attest — and a single-attester **liveness** dependence; a **deferred k-of-n SPO-watcher** escape hatch mitigates both.

#### Decision 2 (registry) — SELECTED: MPFS-with-oracle

**Decision 2 (SELECTED): MPFS-with-oracle.** The oracle is still required for the semantic-projection attestation (all tiers) and the >1-chunk byte-binding attestation, so the mandatory-attester argument **still holds for the projection**; MPFS-with-oracle consolidates unicity (at-most-once absence proof), the projection attestation, and batching in one write. The ≤1-chunk byte binding now self-certifies on-chain — a *partial* revival of the token model's self-cert story — but it does **not** remove the oracle, so it is recorded as an **input to #92's** storage-shape choice, not a reversal.

#### NOTE-004 — adjudication boundary (trusted, not trustless)

The on-chain reaction is a **permissionless bonded challenge → mechanical freeze** (fail-safe, no adjudication); the **slash / unfreeze** outcome is authorized by an explicitly **trusted governance key / k-of-n quorum** using off-chain-reproducible recomputation as evidence — **not** a trustless Plutus fraud proof, until an on-chain CESR projection verifier exists (**NOTE-004**).
The record keeps projection fraud and the >1-chunk attested digest as **off-chain-reproducible, not on-chain-decidable**; only the ≤1-chunk byte binding is trustless on-chain.

#### Teeth — bonds, windows, activation (state machine, not adjectives)

Leaf states: `provisional → active`, with `frozen` reachable from either. Numeric values are governance-set; **names, transitions, and `Δ > 0` are decided here.**

- `bond_reg` — registrant bond, posted at registration.
- `bond_chal` — challenger bond, posted to open a challenge.
- `Δ_challenge` — challenge window; `provisional → active` after it if unchallenged (`Δ_challenge > 0`; suggested default 48h, governance-set — vLEI onboarding is slow, latency is cheap).
- `Δ_adjud` — adjudication timeout for a trusted-quorum verdict on a frozen leaf.
- `Δ_post` — finite post-activation challenge window.
- **Tier rule:** `bond_reg` scales with attestation surface — `bond_reg(≤1-chunk) < bond_reg(>1-chunk)` (the >1-chunk tier attests *both* axes, weaker assurance; the exact ratio governance-set).

Transitions / invariants:

1. **Register:** post `bond_reg`; byte binding proven on-chain (≤1-chunk) or attested (>1-chunk); projection attested; leaf → `provisional`; `Δ_challenge` starts (`bond_reg` locked).
2. **Challenge (permissionless):** anyone posts `bond_chal`; leaf → `frozen`; `Δ_challenge` suspended; gated actions (§2) blocked.
3. **Adjudicate** (trusted governance key / k-of-n quorum, off-chain-reproducible evidence):
   - *upheld* (fraud confirmed): `bond_reg` **slashed → bounty** to the challenger; `bond_chal` returned; leaf **retracted** (controller may re-register correctly).
   - *rejected* (false challenge): `bond_chal` **forfeited → registrant** — this **mitigates** freeze-griefing but does **not** make it safe (a capitalised griefer can still force repeated freezes); `bond_reg` retained; leaf → its prior state (`provisional`/`active`), timer resumes.
   - *timeout* (`Δ_adjud` elapses with no verdict): **both bonds stay escrowed and the leaf stays frozen** (fail-safe, favouring the possible victim); liveness escalation to the SPO-watcher quorum is the deferred path.
4. **Activate:** after `Δ_challenge` with no upheld challenge, `provisional → active`; gated actions (§2) require `active`; `bond_reg` is **retained** through `Δ_post`, then released.
5. **Post-activation fraud:** challengeable during `Δ_post` with `bond_reg` still available; after `Δ_post` the *bonded remedy* ends — an honest **finite assurance window** (detectability is not finite: any projection inconsistency stays off-chain-reproducible over the on-chain-bound bytes; only the *automated* remedy is time-boxed).

#### Signed registration package (OOBI-style, design shape only)

Controller-signed and oracle-co-signed evidence binds, at minimum (no wire schema here — #68 freezes serialization):

- a **domain/version** tag (protocol id + version — replay / domain separation);
- **`cesr_aid`** — the complete **32-byte** AID digest (per #97 FR3; no truncation);
- the **inception commitment** `input_commitment = blake2b_256(icp_bytes)` (the #97 datum field) binding the exact inception bytes the checkpoint chain verifies;
- the **projected key-state** `(keys₀, kt₀, next_digest₀, witnesses₀, toad₀, native_sn₀)` the registrant claims is the CESR decode;
- a **nonce / consumed-output reference** (anti-replay + unicity, mirroring #99's mint deriving its asset name from the consumed ref);
- the **tier** (≤1-chunk cryptographic vs >1-chunk attested).

Signatures: the **controller** signs with the **claimed** `keys₀` (Ed25519) — proving possession of the claimed keys (**attribution**), not that they are the keys embedded in the genuine inception bytes; the **oracle / attester** co-signs the same binding — attesting the projection is a faithful CESR decode (both tiers) and, for >1-chunk, `blake3(icp)==cesr_aid` off-chain.

**Witness circularity.** The genesis seal's threshold receipts are verified against the *claimed* `witnesses₀` — circular for truth, but proving the claimed set exists and receipted this exact claim; the ≤1-chunk byte binding narrows the surface but does not make the separately-stored authority genuine, so receipts stay corroborating at every tier and the oracle's projection attestation is the genesis trust bridge.

#### Merged evidence vs unbuilt integration (honesty separation)

#97 measures the checkpoint core/handler **only** — it **excludes** the #99 state/thread lifecycle and the ledger `Data` boundary, so its ~70–74 % is a **lower bound**, not a genesis-path cost. #99 proves cage invariants and a real-node `Modify` boundary, but the #99 **Modify N ≈ 2** is **not** the genesis-registration batch bound.
#99's "necessary but not sufficient" is scoped to **post-genesis mutation** against authenticated prior owner state, **not** genesis projection admission — a colluding registration oracle can still admit a false genesis projection.
The **integrated genesis path** (checkpoint Step/Finish + cage confinement + projection attestation + teeth) is **unbuilt and unmeasured**: it **MUST confine** the intermediate chaining-value state in a #99-style cage/thread-token — a **required #24/#92 integration invariant**, phrased as such, not an implemented fact — and it **MUST be remeasured** before any budget claim.

#### Consequences (documented, not absorbed)

- **#92** — the **2-tx Step/Finish checkpoint chain**; the cage-confined intermediate as a **required #24/#92 integration invariant**; the `provisional`/`active`/`frozen` states; **remeasure** (the #99 Modify N is **not** the genesis bound); the trie-vs-per-AID-UTxO storage shape is **now decided (sovereign per-AID)** — #92 selected the sovereign, per-AID, uniquely-tokenized checkpoint UTxO (Candidate A; §10 thread 8).
- **#68** — **#68** must pin the inception **CESR serialization**, the #97 checkpoint **datum/redeemer**, and the **projection fields**, with **Haskell/Aiken golden parity**; on-chain projection verification is flagged **deferred**.
- **#24** — **#24 is re-cut**: base case = cryptographic byte-binding genesis + challengeable projection + cage integration; the attested residual for >1-chunk travels with it.

#### Remaining trust assumptions (enumerated)

- **controller** — holds `keys₀`, presents inception bytes + signed statement.
- **witnesses** — honest threshold (unchanged KERI assumption) for advances; at genesis the byte binding does not rest on them — receipts are corroborating evidence.
- **overall genesis authority** — **attester-trusted at the projection boundary**: a colluding registration oracle can admit a **false genesis projection** (attacker `keys₀`/`witnesses₀` beside genuine bytes); closed only by the deferred on-chain projection verifier.
- **oracle / attester** — attests projection (all tiers) + byte binding (>1-chunk); can **censor** by refusing to attest; a **liveness** dependency.
- **challenge / fraud-proof** — ≤1-chunk byte binding is trustless on-chain; projection and >1-chunk byte binding are permissionless-challenge / mechanical-freeze but **trusted-adjudicated** slash/unfreeze.
- **gating / censorship** — registration is gated; refusal is **detectable / attributable only** with an auditable **signed receipt / SLA**, otherwise indistinguishable from an **availability failure**; deferred SPO-watcher escape.
- **slashing / bonds** — `bond_reg`/`bond_chal` teeth are trusted-adjudicated; false-challenge forfeiture **mitigates (does not eliminate)** freeze-griefing.
- **adjudicator liveness / collusion** — the trusted quorum can stall (on timeout **both bonds stay escrowed and the leaf stays frozen** → **indefinite frozen-state griefing under quorum failure**) or collude to wrongly slash/unfreeze — a bounded, visible trust.
- **activation timing** — `provisional → active` after Δ; frozen while challenged.
- **objectively checkable on-chain** — ≤1-chunk byte binding: **yes**; semantic projection: **no**; >1-chunk byte binding: **no**.

#### Honest capability framing

This stays prototype design — it does not claim production maturity, nor interoperability with the wider (non-blake2b) KERI ecosystem; the merged evidence is #97/#98 and #99/#100, and the unbuilt, unmeasured integrated path is #24/#92.

## 8. Cascade — what changes elsewhere

- **#24** — *revived* as the incremental checkpoint (§3), now driven by witnessed seals;
  its **base case is re-cut** by §7c to the hybrid genesis (cryptographic byte binding for
  ≤1-chunk + challengeable projection + the required cage integration; attested residual
  for >1-chunk), replacing the old flat trusted base case.
- **#68** — the *frozen trie_key preimage* concern largely **dissolves**: Cardano mirrors
  the KERI key-state (shape is KERI's `k/kt/n/nt`), it doesn't derive a frozen preimage. The
  **weighted-threshold verification** (F18 rational-weight arithmetic) still stands — it's
  the sig check, not a frozen shape. §7c adds a freeze target: pin the inception CESR
  serialization, the #97 checkpoint datum/redeemer, and the projection fields with
  Haskell/Aiken golden parity; an on-chain projection verifier stays **deferred**.
- **#10 (super-watcher)** — divergence-burn is **not needed** for identity forks (one
  machine). Its identity-plane role is now (§7b): submit **correspondence fraud proofs**
  (permissionless, bounty-compatible — the old divergence-proof mechanics transfer, with
  the receipts-over-raw-bytes simplification), plus freshness/liveness of anchoring.
- **`system-architecture.md`** — R-KEL *for identity* is the on-chain checkpoint
  (advances cryptographic; genesis is the §7c hybrid — byte binding cryptographic on-chain
  for ≤1-chunk (#97), attested for >1-chunk, projection attested/challengeable), not a
  watcher-attested mirror. R-TEL (credential status) remains watcher-mirrored — see below.

## 9. Freshness ≠ integrity

The checkpoint guarantees the on-chain state is **correct**, but not necessarily **current**:
there's a window between a KERI rotation and someone submitting the advancing tx. That's a
**staleness/liveness** knob (submission incentive + the freeze fast-path), separate from the
integrity the checkpoint provides.

## 10. Open threads to drill

1. **Witness-set rotation — drilled 2026-07-09, resolution in §6a** (two-seal handoff:
   pre-announcement receipted by the outgoing set while still in office, activation
   receipted by the incoming set; both seals in one advance tx). No longer a blocker.
   Residual knobs: **Δ sizing** for the time-locked signature-only fallback (relates to
   thread 6's freshness windows), whether Seal W and Seal K must be KEL-adjacent or may
   be separated by interaction events, and the delegated/superseding-recovery case when
   delegated AIDs enter the model.
2. **Pin the seal's serialization** — receipts sign raw bytes (§5), so Plutus parses the
   seal to extract AID / `s` / commitments: fix one serialization kind + field layout so
   parsing is cheap and unambiguous. (Replaces the former "blake2b-SAID digest agility"
   thread, **dissolved** — the seal keeps its native Blake3 SAID.)
3. **Genesis binding — RESOLVED 2026-07-11 (#91), decision in §7c.** No longer the flat
   trusted base case: the selection is a **deliberately hybrid** genesis — cryptographic
   byte binding on-chain for ≤1-chunk inceptions (#97/#98), attested for >1-chunk, with an
   attested / challengeable semantic projection at every tier; registration oracle-gated,
   challenge permissionless (decision 1); MPFS-with-oracle (decision 2); teeth, signed
   package, and the full trust enumeration in §7c. Residual work is downstream: the
   integrated genesis path (checkpoint + cage + projection + teeth) is unbuilt/unmeasured
   (#24/#92), and a trustless on-chain CESR projection verifier is a **deferred** future.
   A native `blake3` builtin remains the sunset path for multi-chunk inputs; no CIP yet.
4. **Seal ↔ native key-state correspondence — drilled 2026-07-09 (#90), resolution in
   §7b**: correspondence is **required** and **policed via on-chain divergence fraud
   proofs** (native event bytes + threshold receipts vs the stored witness set — no
   Blake3 needed); freeze on proof, with the **slash decided by the §7c teeth** (#91:
   upheld fraud slashes `bond_reg` → bounty); witness-swap residual degrades to the
   watcher-attested path. New seal-payload requirement: bind `native_sn`. Residual work is
   only downstream: the numeric bond/window values (governance-set) and the delegated-AID
   "operating keys" question when delegation enters the model.
5. **Credential-side integrity (R-TEL)** — identity advances are now cryptographic via
   seals; are credential issuance/revocation events analogously anchorable (issuer seals),
   or do they stay watcher-mirrored (trusted)? Note the action-level guarantee is the
   **min over both planes** (§2 still carries admission + non-revocation).
6. **Freshness window sizing** — submission-liveness incentive + freeze fast-path vs the
   stolen-key window; per-use-case floor.
7. **SDK requirement** — the controller's KERI wallet/bridge must emit the seal per
   rotation (#42 family; no SAID patching — the seal is a plain native event); who submits
   the Cardano advance tx (controller vs relayer/watcher).
8. **Who pays / contention — thread 8 is RESOLVED 2026-07-14 (#92).** The physical R-KEL
   checkpoint storage is now **decided**:
   the sovereign, per-AID, quantity-one uniquely-tokenized checkpoint UTxO (Candidate A).
   Each `cesr_aid` advances its current-authority state through its **own** checkpoint UTxO,
   so unrelated issuers and attacker-created AIDs cannot consume, serialize, or delay it —
   sovereignty and unrelated-AID isolation are the load-bearing selection criteria. The
   rejected shapes are kept for the record: a single/global/shared checkpoint-root UTxO (B)
   serializes unrelated identities on one contended UTxO; a grindable public lane
   `lane = f(cesr_aid)` (C) lets hostile AIDs target a victim's lane, making sovereignty
   depend on shard machinery. The selection is **not** conditional on A winning a
   throughput/capital/cost contest; Candidate-A cost / tx-size / min-ada / batch-fan-in
   measurements plus the live-boundary smoke remain a **downstream implementation gate**,
   not the reason A was chosen. See `specs/92-checkpoint-contention/{spec.md,DECISION.md}`
   (NOTE-021) and §7c.
