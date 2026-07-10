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
lane-packed second pass the same day extended the fit to the whole single-chunk domain
(17.1% cpu / 22.4% mem at 300 bytes, 54.3% cpu / 71.7% mem at 1024); the full
registration context remains unmeasured. Genesis therefore stays on the
attested-registration track pending that proof. Correspondence (open thread 4)
**drilled via #90** (§7b — required, fraud-proof policed). Remaining pre-ratification
thread: **3 (registration & genesis package, #91)**; contention (thread 8) is #92.

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

**This is exactly #24** (reveal pre-committed next key, check `hash(revealed)==next_digest`,
threshold sig, advance seq). #24 is therefore revived as the **integrity backbone**, not a
retired idea: the state only advances through validator-checked rotations, so no party can
inject fake keys — there is nothing to trust.

One caveat travels with the revival: original #24 derived `trie_key` from inception
material, so its **base case was self-certifying** in blake2b. Here the leaf key is an
external **Blake3** AID — the induction *step* is unchanged, but the base case (genesis)
is no longer self-certifying on-chain. See §7a.

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

**Genesis is not cryptographic.** The checkpoint is an induction with a **trusted base
case**. The binding `cesr_aid` (a Blake3-derived prefix) ↔ initial keys ↔ **initial
witness set** cannot be verified in blake2b, and the receipt check is **circular at
inception** — the witness set Cardano would verify receipts against is exactly what the
genesis leaf asserts. Whoever writes the genesis leaf can bind someone else's AID to
attacker keys and an attacker "witness set", and every later advance is then flawlessly
"cryptographic" on top of a forged base. Genesis therefore stays at **registration
grade: oracle-asserted, publicly falsifiable** (`system-architecture.md` §6) — the same
trust class as R-MAP, moved to registration time, not escaped. Two mitigating facts:
the trust is **one-shot** (one event per identity lifetime, vs every-read in the
watcher-mirror), and a forged binding is **objectively provable** off-chain (recompute
the Blake3 prefix) — the ideal shape for bond + challenge-window mechanics. A possible
full closure — one-shot **in-script blake3** at genesis via the Plutus V3 bitwise
builtins — is spike #88 (open thread 3). Its lane-packed core is now viable across the
whole single-chunk domain (inputs up to 1024 bytes); a full registration-context
measurement is the remaining test before changing the trust model.

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
| On-chain checkpoint via **blake2b seal** (this doc) | **cryptographic from genesis** — advances rest on the controller's witnesses; the genesis binding itself is registration-attested, falsifiable (§7a) |
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
Cardano. Consequence on success: **freeze the leaf** (safe default; whether a deposit
slash rides on top is a knob for the registration package, #91). The controller can
recover by advancing the checkpoint with a corrective seal.

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

## 8. Cascade — what changes elsewhere

- **#24** — *revived* as the incremental checkpoint (§3), now driven by witnessed seals.
- **#68** — the *frozen trie_key preimage* concern largely **dissolves**: Cardano mirrors
  the KERI key-state (shape is KERI's `k/kt/n/nt`), it doesn't derive a frozen preimage. The
  **weighted-threshold verification** (F18 rational-weight arithmetic) still stands — it's
  the sig check, not a frozen shape.
- **#10 (super-watcher)** — divergence-burn is **not needed** for identity forks (one
  machine). Its identity-plane role is now (§7b): submit **correspondence fraud proofs**
  (permissionless, bounty-compatible — the old divergence-proof mechanics transfer, with
  the receipts-over-raw-bytes simplification), plus freshness/liveness of anchoring.
- **`system-architecture.md`** — R-KEL *for identity* is the on-chain checkpoint
  (cryptographic from a registration-attested genesis — §7a), not a watcher-attested
  mirror. R-TEL (credential status) remains watcher-mirrored — see the open thread below.

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
3. **Genesis binding (§7a)** — the trusted base case.
   - **Spike #88 — in-script blake3 at genesis — reopened 2026-07-10.** The lane-packed,
     vector-validated core costs 17.1% cpu / 22.4% mem at 300-byte inceptions and 54.3%
     cpu / 71.7% mem at the full 1024-byte chunk — the whole single-chunk domain fits.
     Measure the complete single-transaction registration path before changing the
     attested base case. A native `blake3` builtin remains the sunset path for
     multi-chunk inputs; no CIP exists yet.
   - **The live track: attested registration** — exact flow, who attests
     `cesr_aid ↔ (keys, witnesses)@inception`, bond + challenge window before the leaf is
     usable + freeze fast-path; whether controller-signed evidence (OOBI-style) tightens it.
4. **Seal ↔ native key-state correspondence — drilled 2026-07-09 (#90), resolution in
   §7b**: correspondence is **required** and **policed via on-chain divergence fraud
   proofs** (native event bytes + threshold receipts vs the stored witness set — no
   Blake3 needed); freeze on proof, slash knob deferred to the registration package
   (#91); witness-swap residual degrades to the watcher-attested path. New seal-payload
   requirement: bind `native_sn`. Residual knobs: slash-vs-freeze-only (#91), and the
   delegated-AID "operating keys" question when delegation enters the model.
5. **Credential-side integrity (R-TEL)** — identity advances are now cryptographic via
   seals; are credential issuance/revocation events analogously anchorable (issuer seals),
   or do they stay watcher-mirrored (trusted)? Note the action-level guarantee is the
   **min over both planes** (§2 still carries admission + non-revocation).
6. **Freshness window sizing** — submission-liveness incentive + freeze fast-path vs the
   stolen-key window; per-use-case floor.
7. **SDK requirement** — the controller's KERI wallet/bridge must emit the seal per
   rotation (#42 family; no SAID patching — the seal is a plain native event); who submits
   the Cardano advance tx (controller vs relayer/watcher).
8. **Who pays / contention** — per-`cesr_aid` checkpoint UTxO (ordered, no global
   contention) vs an MPFS checkpoint trie (aggregate root, batched writes).
