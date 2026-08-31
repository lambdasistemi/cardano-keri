# Independent feasibility and adversarial evaluation — KERI delegated AIDs on Cardano

Evaluator: Opus 5, high effort, independent lane.
Date: 2026-08-14.
Repository under evaluation: `/code/cardano-keri` at sealed commit
`ae99e35e6aee577ccfc61a62f8a72f6067c1154b` (working tree clean, verified).
Sealed scope: `COMMON-SCOPE.md`, SHA-256
`4acbb08ccfd1968b04f31606d2c40a7faa4975ea178a225283574a35e987d3c2` (verified).
Blind to the Grok lane and to prior vLEI campaign conclusions. No production
repository edits; all builds and captures were performed on a copy under the
session scratchpad.

---

## 0. Executive verdict

**Delegated-AID support is buildable on Cardano, but not as an extension of the
current design: it requires a new datum, three new on-chain facts, and one
correction to a boundary that is presently believed closed and is not.**

Five conclusions carry the report.

1. **The settled baseline "V1 registration rejects `dip`, V1 advance rejects
   `drt`" is false, and this is now witnessed end to end, not merely argued.**
   The only event-type gate on either path is a three-byte slice at a
   *prover-supplied* offset (`registration.ak:313`, `advance.ak:115`;
   `enforcement.ak:81` shares the construction). I found this independently by
   code reading and measured the grind cost at **1,216 random draws / 9 ms**;
   the coordinator then supplied two executable witnesses, **both of which I
   verified independently and completely** (§3.3): a genuine 351-byte keripy
   `dip` whose canonical `t` is `dip` at offset 30 but which carries `icp` at
   offset 237 inside its own next-key digest, and its genuine 352-byte
   sequence-1 `drt` carrying `rot` at offset 59 inside its own SAID. I
   re-derived both SAIDs with `b3sum`, re-verified both Ed25519 controller
   signatures with an implementation independent of keripy, confirmed every
   E2–E9 / AE2–AE10 offset lands on genuine content, and confirmed the
   pre-rotation commitment binds (`blake3(qb64(drt current key))` equals the
   `dip`'s next digest exactly). **A complete delegated identity — inception and
   rotation — therefore projects onto the deployed V1 checkpoint as an
   independent identity, with no delegator approval anywhere in the picture.**
   KERI cooperative delegation silently degrades to single-party control, which
   is exactly the outcome `specs/68-keystate-shape/delegation-boundary-decision.md`
   calls invalid. This is a **high-severity prerequisite: every probability band
   in §12 is conditioned on it being fixed first**, and it must be fixed before
   either independent *or* delegated registration is trusted. Note the fix is
   narrower than it first appears — both witnesses are genuine keripy events
   with correct version-string sizes, so a size check does not catch them; only
   a **canonical, fixed-offset event-type and schema binding** does (§3.3).

2. **Direct recursive verification in one transaction is not feasible; the
   materialized-fact architecture is not merely cheaper, it is the only one that
   terminates.** The recursion is not "walk the parent chain once": validating a
   delegated AID's *current* key state requires every establishment event of
   every ancestor to be individually anchored and individually verified, and
   each ancestor anchor is verifiable only against that ancestor's key state *at
   that time*. Materialization converts unbounded recursion into an inductive
   invariant with **zero on-chain recursion**: level *n* exists only because
   level *n−1* already exists as a checkpoint. Cycles are structurally
   impossible (a `dip`'s AID is a digest over its own `di`, so a cycle demands a
   hash fixed point). Depth is unbounded but costs the *consumer* one reference
   input per hop, and the consumer sets its own bound.

3. **One measured fact blocks the GLEIF root today, and it has nothing to do
   with delegation.** The real production GLEIF Root inception event is
   **1,181 bytes** (measured from the live witness). The deployed hash-proof
   policy admits a single BLAKE3 chunk, **≤ 1,024 bytes**. The root cannot be
   registered at all. The real GLEIF External Delegated AID (GEDA) inception is
   **1,017 bytes** — inside the ceiling by **7 bytes**. I independently
   reproduced both AIDs from their live bytes with the deployed
   SAID-dummying rule (`b3sum`, §7.1), so this is not an inference. Rooting a
   Cardano trust chain at the real GLEIF Root therefore requires multi-chunk
   BLAKE3 (unimplemented; spike #97 checkpoints a *single* chunk only), or an
   explicitly declared pinned-root trust boundary.

4. **The anchoring-event class decides the transaction shape, and production
   uses the hard one.** When the parent's anchoring event is an *establishment*
   event, the delegation certificate can be minted as a side effect of the
   parent's own advance at near-zero marginal cost. When it is an *interaction*
   event — which is what the production GEDA uses for **all 26** of its anchors
   — there is no checkpoint transition to ride, and the ixn is verifiable
   on-chain only while the parent's current key state is still the one that
   signed it. **If the GEDA ever rotates, every QVI delegation not already
   materialized becomes permanently unprovable on-chain** under the current
   datum. The general remedy is a 32-byte establishment-history commitment in
   the datum (§8.4), which also serves historical ACDC verification.

5. **Honest transaction counts and cost.** A delegated registration under the
   recommended architecture is **3 transactions** (hash proof → certificate →
   register), a delegated rotation is **3 transactions** (SAID proof →
   certificate → advance) versus 1 for an ordinary rotation, and bootstrapping
   the real GLEIF chain to one QVI is **10–12 transactions**, of which the root
   leg is currently blocked. Fee estimate per delegated registration at live
   mainnet parameters (epoch 649): **≈ 3.0–3.6 ADA**, plus whatever registration
   bond the deployment sets (preprod uses 1,000 ADA). Execution-unit headroom is
   the binding risk, not fees, and the repository's own headroom gate is
   computed against a **stale memory budget** — it uses 14,000,000 where live
   mainnet is **16,500,000** (measured, §10.1).

**Overall feasibility:** delegated-AID support is a real, tractable, but
genuinely *new* protocol version — not a field addition. My probability bands
(§12) are: synthetic one-level demo **0.85–0.95**; real one-level GEDA
registration under a declared pinned root **0.6–0.8**; recursively validated
real GLEIF-Root→GEDA→QVI ancestry **0.25–0.45**; production-ready
mainnet-grade support **0.10–0.25** within the horizon of a single milestone.
The bands are wide because three of the load-bearing quantities are unmeasured
(§11), and I decline to collapse them into one number.

---

## 1. What I did, and what that licenses

| Activity | Status of resulting claims |
| --- | --- |
| Read the sealed repository (specs 68, 106, 114, 114-permissionless, 115, 116, 219, 254; `registration.ak`, `advance.ak`, `enforcement.ak`, `datum.ak`, `threshold.ak`, `observer.ak`, `checkpoint_register.ak`, `checkpoint_observer.ak`, the committed MEASUREMENTS files, the preprod manifest) | Facts about the code as sealed |
| Retrieved the current ToIP KERI specification (v1.1, DOI 10.5281/zenodo.18887102) in full and read the delegation, seal, config-trait, validation and superseding-recovery sections verbatim | Normative rules |
| Retrieved `keripy` `src/keri/core/eventing.py` at `main` (`7da1e64`, 2026-08-11) and read `validateDelegation` / `fetchDelegatingEvent` in full | Implementation behaviour |
| Retrieved the **live production GLEIF KEL** from a production witness OOBI (33,541 bytes, root + GEDA), parsed every event and attachment | Measured production facts |
| Independently recomputed both production AIDs with `b3sum` under the deployed SAID-dummying rule | Reproduced measurements |
| Built the sealed `onchain/` tree with the pinned Aiken 1.1.23 in a scratchpad copy and read compiled program sizes | Measured script sizes |
| Queried live mainnet protocol parameters (Koios, epoch 649) | Measured chain parameters |
| Ran a grinding experiment against the deployed event-type gate | Measured attack cost |
| Audited both coordinator-supplied collision witnesses from their published bytes alone — re-derived SAIDs with `b3sum`, re-verified both Ed25519 signatures outside keripy, checked every offset, re-derived the pre-rotation commitment, and hand-traced the deployed predicate to a verdict | Independently reproduced |
| Calibrated a KERI JSON size model against three independent real events | Model validated to the byte |

Everything below is labelled `MEASURED`, `REPRODUCED`, `BOUND`, `ESTIMATE`,
`INFERENCE`, or `UNKNOWN`. Where the sources do not settle a question, I say so
rather than choosing.

---

## 2. Normative acceptance predicate — delegated inception (Q1)

Sources: ToIP KERI specification v1.1, §Delegated Inception, §Cooperative
Delegation, §Seals, §Validation, §Configuration Traits; keripy
`Kever.validateDelegation`.

For a delegated inception event `D` claiming AID `X` with delegator `P`, a
**validator that is not the controller, witness, or delegator** MUST establish
all of the following before accepting `D` into its copy of `X`'s KEL. The spec
states the composite requirement directly: *"a non-controller, non-witness,
non-delegator validator MUST first verify the event's controller signatures,
witness signatures (if witnessed), and delegator anchoring seal (if delegated)
before it can accept that event into its copy of that event's KEL."*

**N1 — structure.** `t == "dip"`; the top-level field set and order is exactly
`[v, t, d, i, s, kt, k, nt, n, bt, b, c, a, di]`; `s == "0"`; `di` is present
and is a qualified AID. (Measured on live production data: this is precisely the
field set of the GEDA `dip`. The spec's v2 examples use the same field list.)

**N2 — self-addressing identity.** `X == d == i`, and `X` is the qualified
BLAKE3-256 digest of `D` with the `d` and `i` value spans replaced by the
dummy filler. Spec: *"The AID for a Delegatee AID (delegated identifier prefix)
MUST be a fully qualified digest of its inception event, which includes a
reference to the Delegator's AID."* This is the first half of the two-way
binding, and it is what makes the parent immutable per AID: `di` cannot be
changed without changing `X`.

**N3 — controller quorum.** Controller-indexed signatures over the exact
serialized bytes of `D` satisfy `kt` over `k`. Spec: *"A set of
controller-indexed signatures on an interaction or inception event (delegated or
not) MUST at least satisfy the current signing threshold."*

**N4 — witness quorum.** If `b` is non-empty, witness-indexed signatures over
the same bytes satisfy `bt` against `b`.

**N5 — delegator anchoring seal.** There exists an event `E` in `P`'s KEL whose
seal list `a` contains an event seal `{i: X, s: "0", d: SAID(D)}`. For a `dip`,
`SAID(D) == X`, so the seal degenerates to `{i: X, s: "0", d: X}` — **measured
verbatim in production**, both in the root's rot at sn 1 and in
`GLEIF-IT/gar`'s `anchor.json`. This is the second half of the two-way binding.
The spec is explicit that the combination is what creates it: *"The combination
of the appearance of this seal in Ean's KEL for an establishment event in the
KEL of a delegated AID that designates Ean's AID as the Delegator in that KEL's
Inception event provides a cryptographically verifiable two-way binding."*

**N6 — the anchoring event must itself be valid in `P`'s KEL.** `E` may be an
`ixn` or a `rot`. Its validity requires `P`'s key state *at `E`'s location*:
controller quorum against the key set established by `P`'s latest establishment
event at or before `E`, plus `P`'s witness quorum in force there.

**N7 — the anchor must be current, not merely historical.** keripy resolves the
seal through `self.db.kels.getLast(keys=delpre, on=ssn)` with the comment *"last
means not disputed or superseded"*. An anchoring event that has since been
superseded does not approve anything.

**N8 — the delegator must permit delegation.** If `P`'s inception carries the
`DND` (Do-Not-Delegate) configuration trait, the delegation is invalid. Spec:
*"A Validator MUST invalidate, i.e., drop any delegated events whose Delegator
has this configuration trait."* keripy enforces it: `if dkever.doNotDelegate:
raise ValidationError`.

**N9 — recursion and termination.** If `P` is itself delegated, N1–N8 apply to
every establishment event of `P` with respect to `P`'s own delegator, and so on.
The recursion terminates at an **undelegated** root AID, which the spec requires
to exist: *"the root KEL of the delegation which by definition MUST be
non-delegated."* KERI does not name that root; it is the *validator's*
configuration. Any Cardano design must therefore take the trust root as an
explicit parameter, not derive it.

### 2.1 What `di` alone does not prove — confirmed

The sealed baseline's claim is correct and, if anything, understated. `di` names
the immediate parent and nothing else. It does not prove the parent's anchoring
event exists, does not identify which parent event anchors, does not prove the
parent's key state, does not prove the parent permits delegation, and does not
prove recursively valid ancestry. A datum field holding `di` and nothing else is
an unauthenticated assertion by whoever built the datum.

---

## 3. Normative acceptance predicate — delegated rotation (Q2)

**Does every `drt` require a fresh delegator approval? Yes — unconditionally.**

Spec: *"A delegation operation directly seals an establishment event for a
delegated AID. Either an inception or rotation."* And: *"Control authority for
the delegated identifier, therefore, requires verification of a given delegated
establishment event, which in turn requires verification of the delegating
identifier's establishment event."* keripy routes both ilks through the same
gate: `delpre` is non-`None` exactly when `ilk in (dip, drt)`, and
`validateDelegation` then demands a matching seal.

For `drt` event `R` of `X` at sequence `n`:

**R1 — structure.** `t == "drt"`; field order per spec
`[v, t, d, i, s, p, kt, k, nt, n, bt, br, ba, c, a]`. **Measured discrepancy:**
production keripy 1.3.5 (KERI protocol v1, `KERI10JSON`) emits `rot`/`drt`
*without* the `c` field — 14 fields, `[v,t,d,i,s,p,kt,k,nt,n,bt,br,ba,a]`. I
verified this on the committed `reg_drt` fixture (352 bytes, no `c`), on the
`adv_wit_2key` real `rot`, and on both live production root rotations. The
current specification document describes KERI protocol **2.0**
(`KERICAACAAJSON` version strings); production GLEIF and every fixture in this
repository are protocol **1.0**. Anything slice-based that is written against
one will mis-locate fields in the other.

**R2 — no `di` on a `drt`.** Spec: *"the Delegated Rotation event does not have
a Delgator AID, di field. It uses the Delegator AID provided by the associated
Delegated Inception event's Delegator AID, di field."* Confirmed on the
committed `reg_drt` fixture. **Consequence for Cardano:** the parent identity of
a rotation is not carried by the rotating event. It must come from state that
was itself established when the `dip` was admitted. A validator that only ever
sees a `drt` cannot know who must approve it. This is the single strongest
argument that `di` must live in the checkpoint datum rather than be re-derived
per transaction.

**R3 — dual controller threshold.** Signatures satisfy both `R`'s own `kt` over
`k` and the prior establishment event's next-key digests and `nt`. Spec: *"A set
of controller-indexed signatures on a rotation event (delegated or not) MUST at
least satisfy both the current signing threshold and the prior next rotation
threshold."* This is exactly the repository's ratified eq6a/eq6b, already
implemented for the non-delegated case.

**R4 — witness quorum on the effective set.** The repository's ratified
incoming-set rule (`new_set = (old − br) ∪ ba`, receipts drawn from `new_set`,
count `≥ new_toad`) matches the spec's "effective witness list as established by
the latest establishment event". No change is needed for the delegated case.

**R5 — fresh delegator seal.** `{i: X, s: hex(n), d: SAID(R)}` in a
currently-accepted event of `P`'s KEL. **Here `SAID(R) ≠ X`**, unlike the `dip`
case. This is materially harder on-chain: it forces a BLAKE3 SAID computation
over the `drt` bytes to bind the sealed digest to the presented bytes. The
advance path today deliberately performs *no* BLAKE3 over the event
(`specs/115-advance/spec.md`, ratified QC) — delegated rotation reintroduces it.

**R6 — superseding rules if a competing `drt` exists at `n`.** §4.2.

### 3.1 The exact two-way binding, stated once

```
child → parent :  dip.di == P                    (immutable: X = blake3(dip incl. di))
parent → child :  ∃ E ∈ KEL(P), currently accepted, with
                  seal ∈ E.a  such that  seal.i == X
                                   and  seal.s == hex(sn of the delegated event)
                                   and  seal.d == SAID(that exact delegated event)
inheritance    :  a drt carries no di; it inherits P from the dip of X
```

Both halves are required, both are checkable, and neither implies the other.
**Verified end-to-end on live production data** (§7.4): the GEDA `dip` carries
`di` = the root AID; the root's `rot` at sn 1 carries the seal
`{i: EINmHd5g…, s: "0", d: EINmHd5g…}`; and the CESR attachment on the GEDA
`dip` carries the source-seal couple `(sn = 1, said = ECphNWm1_jZOupeKh6C7Tl…)`,
which is byte-identical to the root rot@1's own `d`.

### 3.2 The recursion predicate, written out

```
valid(X, e) ⟺  structure(e) ∧ selfAddressing(e if inceptive)
             ∧ ctrlQuorum(e, keystate(X, prev-est(e)))
             ∧ witQuorum(e, keystate(X, effective-set(e)))
             ∧ ( ¬delegated(X) ∨
                 ∃E ∈ acceptedKEL(P): sealOf(E) ∋ (X, sn(e), said(e))
                                    ∧ ¬DND(P)
                                    ∧ valid(P, E) )
where keystate(X, ·) is itself the fold of valid(X, ·) over X's establishment
events, and P = di(dip of X).
```

The two nested folds are the cost. Validating one delegated event demands the
whole ancestor KEL, and each ancestor establishment event demands *its* parent's
whole KEL up to the corresponding anchor. On real data (§7) that is 3 root
events + 27 GEDA events + a QVI KEL of at least 37 events to answer one question
about one QVI — and it grows with every future event of every ancestor. No
single Cardano transaction verifies that. §8 shows the only shape that does.

### 3.3 Critical finding — the deployed `dip`/`drt` boundary does not hold

**Claim under test (sealed baseline):** *"V1 registration accepts only `icp`;
`dip` is rejected"* and *"a delegated AID fails closed at the V1 registration
boundary."*

**Result: false against a grinding adversary. `CONFIRMED` three ways — by code
reading, by a measured grinding experiment, and by two executable witnesses that
I audited from their bytes alone (§3.3.1). Reached independently in this lane
and by the coordinator.**

Evidence chain, all at the sealed commit:

- `onchain/lib/cardano_keri/checkpoint/registration.ak:313` —
  `if !slice_matches(e.event_bytes, e.off_t, "icp")`. `off_t` is a field of
  `RegistrationEvidence`, supplied by the prover. `slice_matches` is bounds-
  checked but position-agnostic.
- `registration.ak:381` — `validate_inception_datum(Icp, d)` is invoked with the
  literal `Icp`, never with a value derived from the event. The
  `DelegatedInceptionRejected` constructor is therefore **unreachable on the
  wired path**; the three-byte slice is the entire gate.
- `onchain/lib/cardano_keri/checkpoint/observer.ak:66-102`
  (`validate_registration`, the deployed withdrawal-observer entry point) adds
  no event-type check.
- `onchain/validators/hash_proof.ak` (H1/H2) checks only length ≤ 1024, span
  disjointness/containment, and `blake3(dummied) == cesr_aid`. **A `dip`
  satisfies H2 exactly as an `icp` does**, because a `dip` is equally
  self-addressing with `d == i == AID` — reproduced on live production bytes in
  §7.1.
- E2/E3 pass unchanged for a `dip`: `i` is the AID; `s` is `"0"`.
- R7 controller quorum passes: the controller holds the keys.
- R7 witness quorum passes trivially if the delegated AID incepts with `b: []`,
  `bt: "0"` — a free choice of the AID's own controller.

The only thing standing between a real `dip` and a V1 checkpoint is the presence
of the ASCII substring `icp` somewhere inside the event bytes at a location the
prover can point at. Base64url alphabet is `A–Z a–z 0–9 - _`; the qb64 spellings
of keys, next-key digests, witnesses, the AID and `di` are all base64url; a
44-character field offers ~42 candidate windows; there are 18 such fields in a
GEDA-shaped `dip`.

**Measured grind cost:** searching random 32-byte values for a `D`-coded qb64
verkey containing `icp` succeeded at **try 1,216 in 9 ms** (Node.js,
`crypto.randomBytes`, this machine). The expected value is ≈ 6.2 × 10³ draws.
The attacker also controls the next-key digests and can vary any field to grind
the AID itself.

### 3.3.1 Executable witnesses — audited independently

The coordinator supplied two witnesses generated in the repository's pinned
keripy 1.3.5 fixture environment. **I did not take them at face value.** I
re-derived every cryptographic claim from the published bytes alone, using
`b3sum 1.8.3` and Node.js Ed25519 — implementations independent of keripy and
of the repository — and I traced the deployed predicate against them by hand.

Witness 1 — `OFF-T-COLLISION-WITNESS.md`, SHA-256
`f9ccd1e02a52d9c6062d507f02f9347434e45d633deba47cf9347e634de0a933` (verified).
Witness 2 — `OFF-T-COLLISION-DIP-DRT-WITNESS.md`, SHA-256
`f80fb1110da836bc2c756a7e063b64b8871681a0c652fdbc5fa53ec45489088c` (verified).

| Audited claim | Witness 1 (`dip`, 351 B) | Witness 2 (`drt`, 352 B) | Verdict |
| --- | --- | --- | --- |
| Byte length matches | 351 | 352 | ✔ |
| `raw_sha256` matches the published JSON | `36efe0ac…76c8f` | `e5dab2bf…e447` | ✔ |
| Version-string declared size equals actual length | 0x00015f = 351 | 0x000160 = 352 | ✔ **both are genuine, well-formed events** |
| Canonical `t` at offset 30 | `"dip"` | `"drt"` | ✔ |
| Collision slice at the supplied `off_t` | offset 237 → `"icp"` | offset 59 → `"rot"` | ✔ |
| Collision site | inside the genuine next-key digest | inside the event's **own SAID `d`** | ✔ |
| Every state offset lands on genuine content (`off_i`, `off_s`, `off_kt`, `off_k`, `off_nt`, `off_n`, `off_bt`) | all 7 verified | all 7 verified | ✔ |
| Controller Ed25519 signature over the exact bytes | verifies | verifies | ✔ (re-verified outside keripy) |
| SAID recomputes from the SAID-dummied bytes under the deployed rule | `EMmE-VQro3ZGkkx2nHqdzfLkN8JhSQmMU6zHSppRTUGL` | n/a (advance checks no SAID) | ✔ |
| Pre-rotation commitment binds the pair | — | `blake3(qb64("DF-MVNF7Lz_…"))` = `EIOyUoVz0YWjQYDicp_f6h6Xk1dWuI30DfuWmjNotom2` = the `dip`'s next digest | ✔ |
| Field set is the exact keripy v1 shape | `v,t,d,i,s,kt,k,nt,n,bt,b,c,a,di` | `v,t,d,i,s,p,kt,k,nt,n,bt,br,ba,a` | ✔ |

**End-to-end predicate trace against witness 1**, performed by me against the
sealed code and not reported by the witness:

`hash_proof` H1 (351 ≤ 1024) ✔ → H2(a) both 44-char spans at `d`/`i` equal
`qb64_aid(cesr_aid)` ✔ → H2(b) `blake3(splice_dummies(bytes)) == cesr_aid` ✔
(re-derived) → H3/H4 mint/burn shape ✔.
`registration_predicate`: `d_reg` floor ✔ → `d.seq == 0` ✔ → E1 at `off_t=237`
✔ → E2–E9 all ✔ (witnesses empty, `toad = 0`, so E8/E9 are trivially satisfied)
→ `validate_inception_datum(Icp, d)` ✔ (the literal `Icp` cannot reject) →
R7 controller quorum `evaluate(Unweighted(1), 1, [0])` ✔ → R7 witness quorum
(`toad == 0`, receipt list empty) ✔ → R8 deposit ✔.
**Verdict: `RegistrationValid`.**

**And the same for witness 2 on the advance path:** AE1 at `off_t=59` ✔,
AE2–AE10 ✔ on genuine offsets, dual-threshold eq6a/eq6b ✔ (the pre-rotation
digest binds, verified above), witness gate vacuous at `toad = 0`, and the
ratified "no SAID proof on the advance path" decision means `d` and `p` are
**deliberately never inspected** — which is precisely where witness 2 hides its
collision.

Three amplifications the witnesses make visible that my analysis alone did not:

1. **On the advance path the grind is free.** The attacker does not need to
   grind a *key*; the collision sits in the event's own SAID, a digest over
   content they choose, and the SAID is the one field the advance validator
   explicitly ignores. Every candidate next-key commitment is a fresh SAID draw.
2. **Nothing rejects the extra `di` field.** E1–E9 examine the fields they name
   and no others; the datum has no place for `di`, so it is neither represented
   nor refused. The coordinator's phrasing here is exactly right.
3. **The chain, not just the event, is constructible.** Witness 2 continues
   witness 1 with the key it actually pre-committed. So this is not "a malformed
   event slips in once"; it is a complete delegated identity whose entire
   Cardano lifecycle proceeds with the delegator cut out.

**Severity.** High, and it gates this whole report. It is a live defect in code
published as reference scripts on preprod (`docs/user/m1-preprod-deployment.md`),
it invalidates a stated epic invariant, and it silently converts a two-party
security property into a one-party one.

**Reality check (important for severity calibration):** I scanned the *live*
production GLEIF root `icp`, both root `rot`s and the GEDA `dip` for stray
`icp`/`rot`/`dip`/`drt` substrings. **None was found** outside the genuine `t`
field. So this is not an attack on existing GLEIF AIDs; it is an attack
available to anyone who *creates* a delegated AID and wants it to appear
independent on Cardano, and it is available for free.

**Impact.**

- The identity plane silently admits AIDs whose establishment authority is held
  by a third party. Every consumer that reads "this AID has a V1 checkpoint,
  therefore it is independent" is wrong.
- Worse on the advance path: `advance.ak:115` gates `"rot"` the same way. A
  `drt` that the delegator **never approved** can advance the checkpoint,
  because the advance predicate checks only the child's dual threshold and
  witness receipts. KERI rejects that event; Cardano accepts it. The distinctive
  security property of cooperative delegation — *"Both sets of keys must be
  compromised simultaneously"* — is destroyed on-chain for such an AID.
- The enforcement path (`enforcement.ak:81`) uses the same construction, so
  mislabelled events can enter conviction evidence; this bears on the #106
  framing-resistance requirement.
- The divergence is invisible to the existing enforcement axes: an unapproved
  `drt` projected on-chain is not a KEL fork and is not "Cardano behind".

**Recommended fix — canonical, fixed-offset type and schema binding.** In KERI
v1 JSON the type value always begins at byte offset **30**: `{"v":"` (6) +
`KERI10JSON` (10) + six size hex digits (6) + `_"` (2) + `,"t":"` (6). I
confirmed offset 30 on all four live production events, on both witnesses, and
on the repository's own honest fixtures (`checkpoint_measurements.ak:294,317`
already use `off_t: 30`). The remediation, in priority order:

1. **Necessary and sufficient for this class:** check the type at the **fixed**
   offset 30 — ideally as a single 33-byte comparison of
   `{"v":"KERI10JSON` ‖ six lowercase hex ‖ `_","t":"icp"` — and delete `off_t`
   from the evidence type entirely. A field the prover cannot aim cannot be
   aimed.
2. **Canonical schema binding**, as the coordinator requires: bind the event's
   field set and order to the ilk's normative schema, so that an `icp` carrying
   a `di`, or any hand-assembled field permutation, is refused rather than
   ignored. Without this, a hand-crafted "`icp` with a `di`" is still admissible
   — the SAID would compute over it, so the hash proof passes, and Cardano would
   hold a checkpoint for an AID that no KERI validator recognizes.
3. **Hardening, but not a fix for this class:** require the version-string
   declared size to equal `len(event_bytes)`. Both witnesses are genuine events
   with correct size fields, so **this check does not catch them.** It closes a
   different family (truncation and trailing-extension), which nothing checks
   today.

Two attractive-looking fixes that do **not** work, and why:

- *Widen the literal to `"t":"icp"` (9 bytes).* Base64url cannot contain quotes,
  so this looks conclusive — but keripy admits arbitrary field maps in the `a`
  anchor list, so quoted JSON syntax is reachable inside attacker-chosen
  content. Pinning the offset is what closes it.
- *Reject any event containing `"di"`.* Sound-looking defence in depth, same
  flaw: `a` can carry it. Useful as a belt, useless as braces.

**Remediation contract** (adopting the coordinator's requirement, and matching
this repository's own verification discipline): before either independent or
delegated registration is trusted again, the fix needs (a) an **adversarial
fixture family** built from these two witnesses plus fresh ground events for
`icp`/`rot`/`dip`/`drt` and the hand-crafted `icp`-with-`di` case; (b) **Haskell
and Aiken parity** on bytes *and* verdicts, per the standing A-001 condition;
and (c) a **live-boundary test** — a real transaction against a real node that
is shown to be rejected — because a pure-predicate green has repeatedly failed
to imply a chain-level green in this codebase (`specs/219-permissionless-advance/spec.md`,
the frozen-blueprint incident). Each control must be demonstrated able to fail.

**Standing:** this is a defect in shipped, preprod-deployed code. It is the
single most consequential thing this evaluation found, it was reached
independently by two lanes, and it is orthogonal to whether delegation support
is ever built.

---

## 4. Recovery, superseding, abandonment, withdrawal, forks, historical validity (Q3)

### 4.1 Historical versus current validity — the two rules that pull apart

The spec makes a strong statement in favour of durable approvals:

> *"the presence of the delegated event's SAID … in the Delegator's KEL is
> equivalent cryptographically to a signed endorsement by the Delegator of the
> delegated event itself but with the added advantage that **the validity of
> that delegation persists in spite of changes to the key state of the
> Delegator**."*

and, of seals generally: *"This also enables the validity of the commitment to
persist in spite of later changes to the key state."*

This is the normative licence for materialization: a delegation approval, once
anchored, is **not** invalidated by the parent later rotating. `CONFIRMED`.

But keripy resolves the seal through `db.kels.getLast(keys=delpre, on=ssn)`,
whose own comment says *"last means not disputed or superseded"*, and the
superseding rules (§4.2) explicitly re-evaluate a delegated rotation against
*which* delegating event currently occupies the parent's sequence slot.
`CONFIRMED` by implementation reading.

**The reconciliation** — and I state it as my own analysis, `INFERENCE`, because
neither source states it in these words — is that two different things are
being said:

- a *key-state change* in the parent (an ordinary rotation) never invalidates an
  existing anchor; and
- a *superseding event* in the parent that displaces the anchoring event from
  its sequence slot does invalidate it, because the anchoring event is no longer
  in the accepted trunk.

For a Cardano design this is the whole ballgame: a materialized delegation fact
is durable against the common case (parent rotation) and fragile against the
rare case (parent superseding recovery). That asymmetry is what makes
materialization + a challenge path the right shape, and it is why a materialized
fact must never be treated as unconditionally final.

### 4.2 Superseding recovery — the exact rules

Verbatim from the specification (§Superseding Rules for Recovery at a given
location):

- **A0.** Any rotation may supersede an interaction at the same `sn`, where that
  interaction is not before any other rotation.
- **A1.** A non-delegated rotation may **not** supersede another rotation.
- **A2.** An interaction may not supersede any event.
- **B.** A delegated rotation may supersede **the latest-seen delegated
  rotation** at the same `sn` if:
  - **B1.** its delegating event is later in the delegator's KEL; or
  - **B2.** the delegating event is the same event, and the superseding seal
    appears **later in that event's seal list**; or
  - **B3.** the delegating events share an `sn`, the superseding one is a
    rotation and the superseded one an interaction.
- **C/C1.** Otherwise recurse up the delegation chain applying A and B to the
  delegating events of the delegating events, until satisfied or the
  (necessarily undelegated) root KEL is reached; if unsatisfied there, discard.

Three consequences that any on-chain design must confront:

1. **B2 makes seal *list index* semantically load-bearing.** Two seals in one
   parent event are ordered, and the order decides which delegated rotation
   wins. Any Cardano evidence format must therefore carry the seal's index and
   the validator must be able to compare indices — a slice-offset scheme that
   merely proves "a matching seal exists somewhere in `a`" is insufficient for
   the recovery case.
2. **C is genuinely recursive across KELs**, and keripy implements it as an
   unbounded `while (True)` climb (`validateDelegation`, `fetchDelegatingEvent`).
   No on-chain validator can run that climb. It must be decomposed into
   per-level facts, or the recovery case must be declared out of scope with the
   consequence stated.
3. **Only the latest-seen delegated rotation is superseding-eligible.** The spec
   is candid about the residual: *"recovery can not happen for any compromise of
   pre-rotated keys, only the latest-seen"*, and an attacker who gets a second
   approved rotation in makes recovery impossible.

### 4.3 Abandonment

Normative and precise: *"When the Next, `n` field value in a Rotation or
Delegated Rotation Event is an empty list, then the associated AID MUST be
deemed abandoned, and no more key events MUST be allowed in its KEL."* An
inception with `n: []` means non-transferable.

**The sealed repository cannot represent this.**
`onchain/lib/cardano_keri/checkpoint/threshold.ak:93` returns
`Invalid(EmptyKeys)` for an empty key list, and `datum_well_formed` applies it to
both the current and the next pair. So an abandonment rotation can never be
projected: the checkpoint sticks at the pre-abandonment state while KERI
considers the identity dead. Whether the freeze ("Cardano behind") path can be
driven by an abandonment rotation is `UNKNOWN` to me — I did not trace the
freeze predicate's acceptance of an `n: []` event, and I flag it rather than
guess. This is a pre-existing V1 gap that a delegated version inherits and
should fix, because at the issuer tier an abandoned QVI AID is exactly the state
consumers most need to see.

### 4.4 Parent withdrawal or veto — the sources do not provide one

I searched the specification for a delegator-side revocation primitive. There is
none. A parent cannot un-anchor a seal; append-only KELs make that impossible.
The parent's levers are:

- refuse to approve future delegated rotations (freezes the child's key state
  but does not remove its signing ability);
- participate in a superseding recovery, which requires a competing delegated
  rotation the child must be able to sign — i.e. requires the *honest* child to
  still hold uncompromised pre-rotated keys;
- act outside the KEL layer entirely: in vLEI, revoke the QVI ACDC credential in
  the TEL.

`CONFIRMED` as an absence. **The practical consequence for Cardano is large and
frequently mis-stated: "GLEIF can revoke a QVI" is a credential/TEL fact, not a
KEL fact. A delegated-AID checkpoint protocol delivers no revocation
capability.** Anyone selling delegation support as "GLEIF can turn a QVI off
on-chain" is selling the wrong layer.

### 4.5 Forks and conflicting histories

The existing enforcement design already covers the two axes it names (fork →
convict → tombstone; Cardano behind → freeze). Delegation adds a third,
currently unaddressed axis:

**Axis D — approval withdrawn by supersession.** The materialized delegation
fact was true when observed and is false now, because the parent's anchoring
event has been superseded. This is not a fork of the child's KEL and not lag;
neither existing predicate fires. It needs its own challenge path with a bond
and a bounty, structurally parallel to `Freeze`/`Convict`.

### 4.6 What the sources do not settle

| Question | Status |
| --- | --- |
| Whether a delegation approval survives the parent's *abandonment* | `UNKNOWN` — no rule found |
| Whether an anchor in a parent event that is later superseded by A0 (rot over ixn) invalidates already-accepted delegated events, or only pending ones | `UNKNOWN` — B3 implies re-evaluation, but no rule states retroactive rejection of an accepted delegated inception |
| Whether the `DID` (Delegate-Is-Delegator) trait changes a validator's acceptance rules or only its authorization semantics | `UNKNOWN` — the spec defines it as a signal, with no MUST |
| Ordering: whether the anchoring seal may precede the delegated event in wall-clock or KEL time | `UNKNOWN` — no temporal rule; keripy escrows and retries in both directions |
| Depth limit | **None normatively.** `DND` is all-or-nothing at one level; the spec's own text notes a delegatee *"could delegate other AIDs via interaction events that do not require the approval of its delegate[or]"* — depth grows without upstream consent |

---

## 5. Four things called "delegation" (Q4)

| | KERI cooperative AID delegation | KERI group / multisig AID | ACDC authority chaining | Cardano stake delegation |
| --- | --- | --- | --- | --- |
| What is delegated | establishment (key-rotation) authority over a child AID | nothing — it is *joint* control of one AID | issuance/role authority carried by credentials | block-production rights of a stake credential |
| Carrier | `dip`.`di` + seal in the parent KEL | `kt`/`nt` weighted thresholds over multiple keys in one KEL | ACDC `e` edges pinned by schema SAID, `I2I` operator, TEL status | a delegation certificate in a Cardano transaction |
| Revocable | **no** (§4.4) | n/a | yes, via TEL revocation | yes, by re-delegating |
| Recursive validity | yes, up to an undelegated root | no | yes, along the edge chain (bounded: 4 hops OOR, 3 hops ECR-direct) | no |
| In the repository | rejected at V1 (nominally — §3.3) | **supported**: weighted fractional thresholds are implemented and mandated | M2 plane | M4 adapter |

**The commonest confusion, stated plainly.** In vLEI, *authority* to act as a QVI
comes from the **QVI ACDC credential** issued by GLEIF plus its TEL status — not
from KERI delegation. KERI delegation of the QVI's AID is about **key
management and recovery**: it makes the QVI's key state verifiable back to the
GLEIF root and gives GLEIF a role in the QVI's recovery. Both facts are needed
by a verifier, but they answer different questions and live in different planes.
The repository's `acdc-zoo.md` gets this right (Fact 1: no vLEI schema contains
any KERI delegation field), and my independent reading of the production data
agrees: the GEDA's KEL carries *both* delegation seals and TEL/credential
anchors in the same `a` lists (§7.5), which is exactly why the two planes are so
easily conflated.

---

## 6. Real GLEIF topology, measured (Q5)

Source: live production witness OOBI
`http://65.21.253.212:5623/oobi/EINmHd5g7iV-UldkkkKyBIH052bIyxZNBn9pq-zNrYoS/controller`,
retrieved 2026-08-14, 33,541 bytes, HTTP 200. The stream contains the GEDA's own
KEL **and** its delegator's KEL, with CESR attachments.

### 6.1 The chain

```
GLEIF Root AID   EDP1vHcw_wc4M__Fj53-cJaBnZZASd-aMTaSyWEQ-PC2   (undelegated icp)
   │  rot@1 seals {i: GEDA, s:"0", d: GEDA}
   ▼
GLEIF External   EINmHd5g7iV-UldkkkKyBIH052bIyxZNBn9pq-zNrYoS   (dip, di = root)
Delegated AID
   │  ixn@1..ixn@0x1a — 26 interaction events, 28 seals
   ▼
14 distinct delegated AIDs (QVI tier)     + TEL/credential anchors
```

`MEASURED`. The root's `rot` at sn 2 seals a second `dip`
(`EFcrtYzHx11TElxDmEDx355zm7nJhbmdcIluw7UMbUIL`) — consistent with the GIDA
(GLEIF Internal Delegated AID), though I did not retrieve that KEL, so the
identification is `INFERENCE`.

**Depth from root to QVI = 2.** I found no evidence of a third delegation level
in production, and no source requires one. `MEASURED` for the two levels
observed; `UNKNOWN` whether any QVI delegates further.

### 6.2 Measured event sizes and shapes

| Event | Size (bytes) | `k` | `n` | `b` | `kt`/`nt` | `bt` | Note |
| --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| Root `icp` @0 | **1,181** | 7 | 7 | 5 | 7 × `1/3` | 4 | **exceeds the 1,024-byte chunk ceiling by 157 bytes** |
| Root `rot` @1 | **895** | 3 | 7 | – | 3 × `1/3` | 4 | anchors the GEDA `dip` |
| Root `rot` @2 | **895** | 3 | 7 | – | 3 × `1/3` | 4 | anchors a second `dip` |
| GEDA `dip` @0 | **1,017** | 5 | 5 | 5 | 5 × `1/2` | 4 | fits with **7 bytes** to spare |
| GEDA `ixn` @1–@0x1a | **314–315** | – | – | – | – | – | 26 events, one seal each |

All `MEASURED` from the live stream. Attachments (not counted above): the GEDA
`dip` carries **5 controller signatures** (`-AAF`), **5 witness receipts**
(`-BAF`), a **source-seal couple** `(sn=1, said=root rot@1)` (`-GAB`), and a
first-seen timestamp of **2022-11-30T18:57:00**. Attachment block sizes measured
between event boundaries: root `icp` 780 B, root `rot@1` 788 B, GEDA `dip`
1,028 B, GEDA `ixn` 692 B.

### 6.3 A calibrated size model, for shapes I could not retrieve

I built a byte-exact JSON size model and validated it against three independent
real events: `dip(k=1,n=1,b=0,int)` → **351 = 351 measured**;
`ixn(1 seal)` → **314 = 314 measured**; and the root `rot@1` (`k=3,n=7`, one
seal, minus the 7 bytes of `,"c":[]` that keripy v1 omits from rotations) →
**895 = 895 measured**. Model-derived figures below are `ESTIMATE`, but the model
is exact on every shape I could check.

| Shape | Bytes | Chunk status |
| --- | ---: | --- |
| QVI single-sig `dip` (`GLEIF-IT/gar` `qvi-incept-single-sig.json`: k=1,n=1,b=1) | 397 | fits |
| QVI group `dip` (`vlei-qvi` `aid-incept.json`: k=2,n=2, weighted, b=5) | 699 | fits |
| GEDA-shape `drt` (k=5,n=5, no witness delta) | 784 | fits |
| GEDA-shape `drt` with one witness cut + one add | 876 | fits |
| Root-shape `drt` (k=7,n=7, no delta) | 996 | fits, 28 bytes margin |
| Root-shape `drt` with one cut + one add | 1,088 | **over ceiling** |
| Root-shape `dip` (k=7,n=7,b=5) | 1,229 | **over ceiling** |

`MEASURED` sizes for GLEIF's actual `dip` events sit at 1,017 and 1,181 bytes.
The 1,024-byte boundary runs directly through the production population.

---

## 7. Direct measurement records

### 7.1 Reproduced AID derivations

Using `b3sum 1.8.3` on the live bytes, replacing the 44-character `d` and `i`
spans with `#` filler exactly as the deployed `hash_proof.ak` H2(b) rule
prescribes:

| AID | Bytes hashed | Computed | Expected | Match |
| --- | ---: | --- | --- | --- |
| GLEIF Root | 1,181 | `EDP1vHcw_wc4M__Fj53-cJaBnZZASd-aMTaSyWEQ-PC2` | same | ✔ |
| GLEIF External (GEDA) | 1,017 | `EINmHd5g7iV-UldkkkKyBIH052bIyxZNBn9pq-zNrYoS` | same | ✔ |

`REPRODUCED`. Two independent consequences: (a) the deployed SAID rule is
correct against real production data, which was previously demonstrated only
against generated fixtures; (b) **a `dip` satisfies the hash-proof policy
exactly as an `icp` does** — the basis of §3.3.

### 7.2 Compiled program sizes at the sealed commit

`aiken build -t silent`, pinned Aiken 1.1.23 from nixpkgs
`753cc8a3a87467296ddd1fa93f0cc3e81120ee46`, scratchpad copy of `onchain/`.
Unapplied programs:

| Program | Bytes | % of the 16,384 cap |
| --- | ---: | ---: |
| `checkpoint.checkpoint` (legacy monolith, not deployed) | 25,934 | 158.3% |
| `checkpoint_observer.observer_advance` | **14,871** | **90.8%** |
| `checkpoint_observer.observer_enforcement` | 14,549 | 88.8% |
| `checkpoint_register.checkpoint_register` | 13,033 | 79.5% |
| `checkpoint_observer.observer_migration` | 8,834 | 53.9% |
| `hash_proof.hash_proof` | 8,732 | 53.3% |
| `endpoint_board.endpoint_board` | 6,540 | 39.9% |
| `checkpoint_observer.observer_lifecycle` | 6,471 | 39.5% |
| `bounty_commitment.bounty_commitment` | 4,698 | 28.7% |
| `checkpoint_observer.observer_entitlement` | 3,577 | 21.8% |

`MEASURED`. Parameter application adds bytes on top (five 28-byte policy hashes
plus integers for `checkpoint_register`, ≈ 200 bytes). **`observer_advance` has
roughly 1.2 KB of headroom against the repository's own 16,133-byte deployable
creation budget.** No delegated-rotation logic can be added to it. The
withdrawal-observer architecture is the good news here: a new
`observer_delegation` script is the natural and available slot, and it costs
nothing in the existing programs.

### 7.3 Grinding experiment

Node.js, `crypto.randomBytes(32)`, qb64 `D`-code spelling
(`'D' + base64url(0x00‖key).slice(1)`), searching for the substring `icp`:
**found at draw 1,216, elapsed 9 ms**, result
`DA0m3eDG-dc8V9aTuTLpKWxu17vPg9plEicpKkhuwea1`. `MEASURED`.

### 7.4 Two-way binding verified on production data

- GEDA `dip`.`di` = `EDP1vHcw_wc4M__Fj53-cJaBnZZASd-aMTaSyWEQ-PC2` (root). ✔
- Root `rot@1`.`a[0]` = `{"i":"EINmHd5g…","s":"0","d":"EINmHd5g…"}`. ✔
- GEDA `dip` CESR attachment `-GAB` source-seal couple = sn 1, said
  `ECphNWm1_jZOupeKh6C7TlBi81BlERqbnMpyqpnS4CJY` = root `rot@1`.`d`. ✔

`MEASURED`.

### 7.5 A real-world anomaly worth designing for

The GEDA's 28 seals split as 14 `dip`-shaped (`s == "0"`, `d == i`) and 14 of
other shapes. Two of the others are, verbatim:

```
GEDA ixn @7 : {"i":"ED88Jn6CnWpNbSYz6vp9DOSpJH2_Di5MSwWTf1l34JJm","s":"24","d":"EBD3Oyid3m2mRO7e_7JeoLzQe_GZE8WEbne2IMz3prwf"}
GEDA ixn @8 : {"i":"ED88Jn6CnWpNbSYz6vp9DOSpJH2_Di5MSwWTf1l34JJm","s":"18","d":"EBD3Oyid3m2mRO7e_7JeoLzQe_GZE8WEbne2IMz3prwf"}
```

The same digest sealed at two different sequence numbers for the same subject.
At most one can satisfy a two-way binding, since a given event has exactly one
`sn`. `MEASURED`; the interpretation (an operator mis-anchor at sn `0x24`
corrected by a re-anchor at `0x18`, or vice versa) is `INFERENCE`.

Design consequences, all real:

1. Parents publish inert or wrong seals. A validator must fail on the *seal*,
   never on the chain.
2. **You cannot assume the first anchor is the operative one.** An on-chain
   design that materializes "the delegation of X" from the earliest matching
   parent event will materialize the wrong one here.
3. The `a` list is heterogeneous — delegation approvals sit beside TEL and
   credential anchors — and is not self-describing. Evidence must name the seal
   by index and check all three components.

---

## 8. Architecture comparison (Q6)

### 8.1 Architecture A — direct recursive verification

One transaction presents the child event, the parent anchoring event, the
grandparent anchoring event, … up to a configured root, and the validator checks
the whole ladder.

| Dimension | Assessment |
| --- | --- |
| Trust root | explicit script parameter; clean |
| Historical KEL commitments | must be re-presented in full every time |
| Replay | each proof is self-contained; no state to replay against |
| Forks | undetectable — the transaction sees only what the prover shows; a superseded anchor looks identical to a live one |
| Cycles | impossible by hash construction |
| Depth bound | must be hard-coded; recursion is not expressible in Aiken without an explicit bound |
| Witness evidence | every ancestor event needs its own quorum re-verified per transaction |
| Popular-parent contention | none (no shared UTxO) |
| Proof authenticity | high — nothing is trusted from state |
| **Feasibility** | **rejected** |

The killer is §3.2: verifying an ancestor's anchoring event requires the
ancestor's key state *at that point*, which requires the ancestor's establishment
chain from its own inception, which requires *its* parent's anchors. For the real
GLEIF chain the ladder is 3 + 27 + ≥37 events with quorum signatures on each. At
the measured cost of a single 7-key registration (4.91 M memory for one event
with ~7 signature verifications) the ladder exceeds a 16.5 M-unit transaction
budget by roughly an order of magnitude. `ESTIMATE`, but not a close call.

A "prune the ladder" variant — trust the parent's on-chain checkpoint for the
key state and present only the parent's anchoring event — is not Architecture A
any more; it is Architecture B without the durable fact, and it re-verifies the
same anchor on every subsequent question while remaining unable to verify any
anchor older than the parent's current establishment epoch.

### 8.2 Architecture B — materialized delegation-certificate UTxOs (recommended)

A permissionlessly mintable, single-purpose token records one immutable fact:

```
DelegationCertificateV1 {
  parent_aid       : ByteArray  -- 32
  child_aid        : ByteArray  -- 32
  child_sn         : Int        -- the delegated event's own sn
  child_said       : ByteArray  -- 32; == child_aid iff child_sn == 0
  parent_event_sn  : Int        -- where the seal was found
  parent_seal_index: Int        -- required by superseding rule B2
  observed_seq     : Int        -- parent checkpoint seq at observation
  observed_slot    : Int
}
```

Token name = `blake2b_256(parent ‖ child ‖ sn ‖ said)`, policy = the certificate
script's own hash, so **the fact is authentic by construction: only the script
can mint it**, and a consumer authenticates it by policy id, never by address or
datum shape alone.

Minting requires, in one transaction:

- **reference input:** the parent's checkpoint UTxO (its current key state,
  witness set, `toad`, and lifecycle role);
- **evidence:** the parent's anchoring event bytes, the offsets of the seal's
  `i`/`s`/`d` spans and its list index, the parent's controller signatures over
  those bytes, and the parent's witness receipts over those bytes;
- **evidence:** the child's event bytes plus its hash-proof token (for `sn == 0`
  the proof already equals the child AID; for `sn > 0` a SAID proof over the
  `drt` bytes is required);
- **checks:** seal triple equals `(child_aid, hex(child_sn), child_said)`; the
  anchoring event's `i` slice equals the parent AID; parent quorum satisfied
  against the *referenced checkpoint's* `cur_keys`/`cur_threshold`; parent
  receipts satisfied against its `witnesses`/`toad`; the parent's `DND` bit is
  clear; the parent's checkpoint is ACTIVE.

Registration and advance for the child then consume or reference the matching
certificate, and the child's datum carries `di = parent_aid`.

| Dimension | Assessment |
| --- | --- |
| Trust root | the walk terminates when a checkpoint's `di` is `None`, which by construction means it was registered from an `icp`; the consumer supplies the root AID it demands |
| Historical KEL commitments | **the weak point** — the certificate asserts a fact about a parent state that will pass; see §8.4 |
| Replay | the token name binds `(parent, child, sn, said)`; a certificate cannot be re-pointed. Duplicate certificates for the same tuple are equivalent facts and harmless |
| Forks / stale facts | needs a new challenge path (Axis D, §4.5): bonded, permissionless, with a superseding proof |
| Cycles | impossible |
| Depth bound | unbounded on-chain; the *consumer* pays one reference input per hop and sets its own maximum. Fail-closed at the bound |
| Witness evidence | verified once, at materialization |
| **Popular-parent contention** | **solved**: the parent checkpoint is a *reference* input, so unboundedly many children can materialize in the same block. Residual: a transaction referencing a UTxO that another transaction spends earlier in the same block fails phase 1, so certificate minting races only against the parent's own advance/freeze/close |
| Proof authenticity | policy id is the authenticator; the datum alone proves nothing |
| **Feasibility** | **recommended** |

**Why it terminates where A does not.** Level *n*'s certificate can only be
minted if level *n−1*'s checkpoint exists, which required *its* certificate. The
recursion is discharged by induction over on-chain history, not by recursion
inside a script. Answering "is X descended from root R" costs the consumer
`depth` reference inputs and **zero signature verifications** — measured
comparable: the existing `Claim` context costs 654,656 memory units (4.7% of the
14 M budget the repo assumes), so a depth-3 ancestry walk is well under 2 M
units. That is the decisive asymmetry.

### 8.3 The anchoring-event class changes the transaction shape

`INFERENCE` from measured data, and I consider it the most actionable design
finding after §3.3.

- **Establishment anchor (`rot`).** The parent's advance transaction already
  verifies exactly the signatures and receipts the certificate needs. The
  certificate can be minted **in the same transaction as the parent's advance**,
  at the marginal cost of a slice comparison and a mint. Real case: the GEDA
  `dip` is anchored by the root's `rot@1`, so bootstrapping the root's KEL
  0→1→2 naturally captures it *if the certificate is minted at step 1*.
- **Interaction anchor (`ixn`).** No checkpoint transition exists — interaction
  events never touch the checkpoint. A standalone observation transaction is
  needed, and it is verifiable only while the parent's current key state is
  still the one that signed the `ixn`. **Production uses this path
  exclusively**: all 26 GEDA anchors are `ixn`.

**The sharp statement:** under the current datum, an `ixn`-anchored delegation
must be materialized *before* the parent's next checkpointed rotation, or it
becomes permanently unprovable on-chain. The GEDA has never rotated in 27
events, so today every QVI delegation is still capturable. The day the GEDA
rotates, every uncaptured one is lost.

### 8.4 Architecture B′ — B plus a 32-byte establishment-history commitment

The general fix for §8.3 and, independently, for historical ACDC verification:
add one field to the checkpoint datum,

```
est_history : ByteArray   -- blake2b_256(prev_est_history ‖ canonical(prior key state))
```

updated on every advance. Any party can then later prove "at establishment epoch
*e* the key state was *S*" by presenting the preimage chain, at O(number of
rotations) cost, permissionlessly and without a time limit. It converts the
checkpoint from a *current-state* oracle into a *history* oracle. Cost: 32 bytes
of datum, one blake2b per advance (negligible against the measured 7.6 M-unit
advance), and a new evidence type. I recommend it be evaluated in the same
version as delegation because it removes the only genuine liveness requirement
in Architecture B, and because #31 (historical ACDC verification) needs the same
primitive.

### 8.5 What is *not* an option

Requiring the parent to sign anything Cardano-shaped. GLEIF, GARs and QVIs
publish KELs and TELs; they do not sign Cardano domain messages, and asking them
to is not a protocol design, it is a business-development plan. Every design
here reads only what the parent already publishes. This also rules out
"parent co-signs the child's registration transaction" and "parent maintains an
on-chain allowlist", both of which are otherwise attractive.

---

## 9. Threat model

| # | Threat | Vector | Mitigation | Residual |
| --- | --- | --- | --- | --- |
| T1 | **Delegated AID projected as independent** | prover-chosen `off_t` + ground `icp` substring — **witnessed and audited** (§3.3.1) | fixed-offset type binding + canonical schema binding | none once fixed; **live today** |
| T2 | **Unapproved `drt` advances the checkpoint** | same, on `advance.ak`; collision sits in the deliberately-unchecked SAID — **witnessed and audited** | same, plus require a certificate for every advance of a `di`-bearing checkpoint | none once fixed; **live today** |
| T2b | Hand-crafted `icp` carrying a `di` | no field-set binding; SAID computes over any byte string | canonical schema binding (fix item 2) | phantom AIDs with no valid KEL; **live today** |
| T3 | Certificate minted from a seal the parent later supersedes | KERI superseding recovery (§4.2) | bonded challenge path (Axis D) + `parent_seal_index` recorded | detection is off-chain and permissionless; latency is the bond window |
| T4 | Certificate minted from an inert/mis-typed seal | real production behaviour (§7.5) | full triple check `(i, s, d)`; index recorded | a wrong-but-matching seal is impossible: `d` is a digest |
| T5 | Wrong-parent substitution | attacker claims a different `di` | impossible: `di` is inside the hashed inception, `X = blake3(dip)` | none |
| T6 | Cycle / infinite ancestry | A delegates B delegates A | impossible: requires a hash fixed point | none |
| T7 | Depth DoS on consumers | attacker builds a 1,000-deep chain | consumer-side depth bound, fail-closed | consumers must set one; a naive consumer stalls |
| T8 | Contention on a popular parent | 14 QVIs materializing at once | parent read as a *reference* input | only against the parent's own spend in the same block |
| T9 | Replay of certificate evidence | resubmit old evidence | token name binds the tuple; duplicates are equivalent | duplicate tokens exist; consumers must not count them |
| T10 | Stale fact consumed as fresh | dApp reads an old certificate | `observed_slot`/`observed_seq` in the datum; consumer policy | policy is the consumer's; the protocol cannot force freshness |
| T11 | Datum forgery at a look-alike address | attacker creates a UTxO with a plausible datum | authenticate by **policy id**, never by address or datum shape | consumer error remains possible; document loudly |
| T12 | Parent frozen / tombstoned after materialization | enforcement fires on the parent | require parent ACTIVE at materialization; consumer re-checks the parent's live role during the ancestry walk | a certificate outlives the parent's role change; the walk, not the certificate, must decide |
| T13 | Abandoned ancestor invisible | `n: []` cannot be projected (§4.3) | fix `threshold.well_formed` to admit the abandonment shape as terminal | **live gap today** |
| T14 | Protocol-version drift (KERI v1 → v2) | field sets and version strings differ (§3, R1) | version-string check makes drift a hard failure rather than a mis-parse | a v2 migration is a new validator version, full stop |

---

## 10. Costs, transaction counts and actor stories (Q7, Q8, Q10)

### 10.1 Chain parameters and a budget correction

Live mainnet, epoch 649 (Koios, `MEASURED` 2026-08-14):

| Parameter | Value |
| --- | ---: |
| `maxTxSize` | 16,384 |
| `maxTxExMem` | **16,500,000** |
| `maxTxExSteps` | 10,000,000,000 |
| `priceMem` | 0.0577 lovelace/unit |
| `priceStep` | 0.0000721 lovelace/unit |
| `minFeeA` / `minFeeB` | 44 / 155,381 |
| `minFeeRefScriptCostPerByte` | 15 |

**Correction to the repository's own gate.** Every committed MEASUREMENTS file
computes headroom against a memory budget of **14,000,000**
(`specs/114-permissionless-registration/MEASUREMENTS.md`,
`specs/115-advance/MEASUREMENTS.md`). Live mainnet is 16,500,000 — **17.9%
larger**. The existing numbers are therefore conservative, not wrong, but the
"25% headroom" gate is being enforced against a stale denominator, and any
delegation feasibility argument that inherits the 14 M figure understates what
fits. `MEASURED`.

**A second correction, in the other direction.** Reference scripts are now
charged per byte. A transaction using `checkpoint_register` (13.0 KB) plus
`observer_advance` (14.9 KB) references ~28.1 KB, crossing the first 25,600-byte
tier: ≈ 384,000 + 44,478 ≈ **0.43 ADA of reference-script fee per advance
transaction**, before anything else. That is a larger recurring cost than the
execution units.

### 10.2 Measured execution units (repository, at or near the sealed commit)

| Context | Memory | CPU | Source |
| --- | ---: | ---: | --- |
| Register, 2-key unwitnessed | 1,468,223 | 649,280,426 | `114-permissionless/MEASUREMENTS.md` |
| Register, witnessed 2-of-2 / 2-of-3 | 2,104,834 | 1,001,220,049 | ibid. |
| Register, 7-key GLEIF-shaped | 4,914,284 | 2,121,024,410 | ibid. |
| Advance `adv_wit_2key` | 4,226,861 | 2,046,910,284 | `115-advance/MEASUREMENTS.md` |
| Advance `adv_wit_7key` | 7,612,741 | 3,438,427,877 | ibid. |
| Advance `adv_keep` | 3,824,714 | 1,886,941,692 | ibid. |
| Claim (cheapest full context) | 654,656 | 213,846,973 | `114-permissionless/MEASUREMENTS.md` |
| BLAKE3 in-script, 300 B | 3,141,028 | 1,709,986,879 | `spikes/88-blake3-plutus/REPORT.md` |
| BLAKE3 in-script, 1,024 B | 10,035,212 | 5,429,574,328 | ibid. |
| BLAKE3 checkpointed Step (½ chunk) | 9,815,601 | 7,354,116,811 | `spikes/97-blake3-multitx/REPORT.md` |
| BLAKE3 checkpointed Finish (½ chunk) | 9,581,091 | 7,263,792,055 | ibid. |

All `MEASURED` by the repository and reproducible via `just measure-checkpoint`
and the spike commands.

**A warning the repository's own numbers carry.** The measured `adv_wit_7key`
cell uses **2 witness receipts**. The real production shapes use **`toad = 4`
and 5 witnesses**, and a real GLEIF-scale rotation reveals up to 7 keys, each
requiring a BLAKE3 digest for the pre-rotation check. Extrapolating from the
measured pairs (≈ 0.32 M units per Ed25519 verification, derived from the
Register witnessed-versus-unwitnessed delta; ≈ 0.3–0.7 M units per single-block
BLAKE3, derived from the spike's intercept), a production-shaped advance plausibly
lands at **12–18 M memory units**, i.e. straddling the 16.5 M cap. `ESTIMATE`.
This is not a delegation problem — it is an existing one — but a delegated
advance sits on top of it. Spike S3 (§13) is the falsifier.

### 10.3 Honest transaction counts

Assumes Architecture B and a delegated child whose parent checkpoint already
exists and is ACTIVE.

| Journey | Txs | Who submits | Consumes | Creates |
| --- | ---: | --- | --- | --- |
| **Delegated registration (happy path)** | **3** | | | |
| ① hash proof over the `dip` | 1 | anyone with the public KEL | fee UTxO | proof token (bytes ↔ AID) |
| ② delegation certificate | 1 | anyone | proof token stays; parent checkpoint as **reference** input | certificate token + datum |
| ③ register | 1 | anyone | proof token (burned), certificate (referenced or consumed) | child checkpoint, ACTIVE, bond locked |
| **Ordinary (non-delegated) rotation** | 1 | anyone | child checkpoint | successor checkpoint |
| **Delegated rotation** | **3** | | | |
| ① SAID proof over the `drt` | 1 | anyone | fee UTxO | proof token (bytes ↔ `said`) |
| ② certificate for `(child, n, said)` | 1 | anyone | parent checkpoint referenced | certificate token |
| ③ advance | 1 | anyone | child checkpoint + proof + certificate | successor checkpoint |
| **Parent rotation** | 1 (+0) | anyone | parent checkpoint | successor; **if the rotation carries delegation seals, certificates may be minted in the same transaction** |
| **Parent interaction anchor observation** | 1 | anyone, urgently | parent checkpoint referenced | certificate token |
| **Superseding recovery of a child** | 3 + 1 | anyone; challenger | as delegated rotation, plus a challenge tx | successor + convicted stale certificate |
| **Approval-withdrawn challenge (Axis D)** | 1 | challenger, bonded | stale certificate | tombstoned certificate + bounty |
| **Failed / stale proof** | 1 | anyone | fee only | nothing; the transaction fails phase 2 and the submitter loses collateral |
| **Bootstrap GLEIF Root → GEDA → one QVI** | **10–12** | anyone | — | three checkpoints + two certificates |

Bootstrap detail (`ESTIMATE`, and the first leg is currently blocked):

```
Root:  multi-chunk BLAKE3 over 1,181 B      2–3 tx   ← UNIMPLEMENTED
       register (icp)                          1 tx
       advance 0→1  (+ mint GEDA certificate)  1 tx   ← certificate rides the advance
       advance 1→2                             1 tx
GEDA:  hash proof over 1,017 B                 1 tx
       register (dip, consumes certificate)    1 tx
QVI:   hash proof over ~700 B                  1 tx
       observe GEDA ixn anchor → certificate   1 tx   ← must precede any GEDA rotation
       register (dip, consumes certificate)    1 tx
                                            = 10–12 tx
```

### 10.4 Estimated cost per transaction

Fee model: `minFeeB + minFeeA·bytes + priceMem·mem + priceStep·steps +
refScriptFee`. `ESTIMATE` throughout; the ex-unit inputs are `MEASURED`.

| Transaction | Ex-units (mem / steps) | Ref scripts | Est. fee |
| --- | --- | ---: | ---: |
| Hash proof, 1,024 B | 10.04 M / 5.43 G | 8.7 KB | **≈ 1.32 ADA** |
| Register, 7-key | 4.91 M / 2.12 G | 19.7 KB | **≈ 0.98 ADA** |
| Advance, 7-key (measured shape) | 7.61 M / 3.44 G | 28.1 KB | **≈ 1.38 ADA** |
| Delegation certificate (parent event ≈ 900 B, 3 ctrl sigs + 4 receipts) | ≈ 3–5 M / 1.5–2.5 G | ≈ 20 KB | **≈ 0.9–1.2 ADA** |
| **Delegated registration, total** | | | **≈ 3.2–3.5 ADA** |
| **Delegated rotation, total** | | | **≈ 3.0–3.6 ADA** |
| **GLEIF bootstrap to one QVI** | | | **≈ 11–15 ADA** |

Excluded, because it is a deployment parameter and not a protocol cost: the
registration bond, set to 1,000,000,000 lovelace on the preprod release, plus
the 5,000,000-lovelace freeze bond. On mainnet these dominate everything above
and are a business decision, not an engineering one.

Transaction size is comfortable: the largest evidence payload (child `dip`
1,017 B + parent event 895 B + 10 signatures × 64 B + offsets) is ≈ 2.8 KB
against a 16,384-byte limit. `ESTIMATE`. **Execution units and script size, not
transaction size or fees, are the binding constraints.**

### 10.5 Actor-by-actor stories (Q10)

**Story 1 — a QVI is put on Cardano by a stranger.** A relayer with no
relationship to GLEIF fetches the public KELs, submits ① the hash proof over the
QVI's `dip`, ② the certificate transaction referencing the GEDA's live
checkpoint and presenting the GEDA `ixn` that seals the QVI's inception with its
4 witness receipts, ③ the registration, locking the bond from the relayer's own
funds. Three transactions, ≈ 3.3 ADA in fees plus the bond. **Nobody at GLEIF or
the QVI does anything, or needs to know.** *What goes wrong:* if the GEDA has
rotated since that `ixn`, step ② is unprovable and the journey stops — with the
history commitment of §8.4 it does not.

**Story 2 — the QVI rotates its keys.** The QVI signs a `drt` and GLEIF anchors
it in a new GEDA `ixn` — both purely KERI operations. Any relayer then submits
①' SAID proof over the `drt`, ②' certificate, ③' advance. Three transactions
where an independent AID needs one. *What goes wrong:* if the `drt` exceeds
1,024 bytes (root-shaped rotations with witness deltas do — §6.3), ①' is
unimplemented today.

**Story 3 — GLEIF rotates the GEDA.** One ordinary advance of the GEDA's
checkpoint. Every already-materialized certificate remains valid — the spec
guarantees the anchor survives key-state change. Every *un*materialized `ixn`
anchor is lost under the current datum. *This is the single operational risk
that a Cardano deployment must monitor.*

**Story 4 — a compromised QVI, recovered.** An attacker with the QVI's
pre-rotated keys gets a malicious `drt` approved and projected on-chain. The
honest QVI produces a competing `drt` at the same `sn`; GLEIF anchors it later
(rule B1); a challenger submits the superseding proof and convicts the stale
certificate, collecting the bond. The child's checkpoint must then be repaired —
**and this is the least-designed part of the whole proposal.** The existing
tombstone machinery convicts an AID; it has no notion of rewinding a checkpoint
to a superseded sequence point. `UNKNOWN` whether re-registration after
conviction (which the repository permits) is an adequate answer here.

**Story 5 — a dApp checks a counterparty.** The contract is configured with the
GLEIF Root AID and a maximum depth of 3. It takes the counterparty's checkpoint
as a reference input, reads `di`, takes the parent's checkpoint as a reference
input (address and asset name are *derived* from `di`, not supplied), repeats
until `di` is `None`, and compares that terminal AID with its configured root.
Zero signature verifications, ≈ 3 reference inputs, well under 2 M memory units.
*What goes wrong:* if it authenticates by address instead of policy id (T11), or
forgets to check each hop's lifecycle role (T12), it is not checking what it
thinks it is checking.

---

## 11. Measured versus inferred — the honest ledger

**Measured or reproduced by me, in this evaluation:**
production GLEIF root and GEDA event sizes, field sets, thresholds, witness sets
and `toad`; the complete GEDA seal inventory and the sn-mismatch anomaly; both
AID derivations under the deployed hashing rule; the CESR attachment structure
including the source-seal couple; compiled program sizes at the sealed commit;
live mainnet protocol parameters; the grinding work factor; the size model's
byte-exactness on three real shapes; the absence of an event-type constraint
beyond a movable three-byte slice; and every cryptographic claim in both
collision witnesses, re-derived from their published bytes with tooling
independent of keripy and of this repository.

**Measured by the repository and taken at face value:**
all execution-unit cells in §10.2 (they are reproducible and internally
consistent; I did not re-run `just measure-checkpoint`).

**Inferred, and labelled as such:**
that `EFcrtYzHx11…` is the GIDA; that the sn-24/sn-18 pair is an operator
mis-anchor and repair; that the "other" seals are TEL/credential anchors; the
production-shape advance cost band of 12–18 M units; the reconciliation of the
"persists in spite of key-state change" rule with keripy's `getLast` behaviour;
the certificate's execution cost.

**Unknown, and load-bearing:**

| # | Unknown | Why it matters |
| --- | --- | --- |
| U1 | Real QVI-tier KEL sizes, depth and `drt` shapes — the witness at hand serves only the root and GEDA, and QVI OOBIs returned 404 | Decides whether `drt` SAID proofs fit one chunk |
| U2 | Whether any production `drt` exceeds 1,024 bytes | Decides whether multi-chunk BLAKE3 is on the critical path or merely for the root |
| U3 | Production-shape advance execution cost (5 witnesses / `toad` 4 / 7 revealed keys) | Decides whether *any* GLEIF-scale advance fits, delegated or not |
| U4 | Certificate-transaction execution cost | Decides the 3-transaction count; could become 4 |
| U5 | Multi-chunk BLAKE3 cost and transaction count | Decides whether the real GLEIF root is reachable at all |
| U6 | Whether the freeze path accepts an abandonment rotation as lag evidence | Decides whether abandonment is representable at all |
| U7 | KERI v2 migration timeline for GLEIF | A v2 cutover invalidates every byte-offset predicate in the system |
| U8 | Whether GLEIF would ever supersede a delegating event in practice | Sets the real-world weight of the whole Axis-D challenge machinery |
| U9 | Whether `enforcement.ak:81`'s identical movable-`off_t` construction is exploitable into a *framing* attack (convicting an honest AID on mislabelled evidence) | Bears directly on the #106 framing-resistance requirement; the registration and advance cases are witnessed, this one is not |

---

## 12. Feasibility outcome and probability bands (Q9)

**Gating precondition.** Every band below is conditioned on the §3.3 defect
being remediated under the full contract (fixed-offset type binding, canonical
schema binding, adversarial fixtures, Haskell/Aiken parity, live-boundary test).
Unremediated, the correct band for *all four* finish lines is **0**, because a
delegation protocol layered on a boundary that does not distinguish `icp` from
`dip` verifies nothing: an attacker simply declines to use it.

Assumptions common to all four: the §3.3 defect is fixed first; delegation ships
as a new validator version with its own datum, using the existing #254
hash-identified migration; no new trusted role is introduced; the team's
demonstrated throughput on comparable slices (registration, advance, enforcement,
migration) continues.

| Finish line | Band | Binding constraint | What would move it |
| --- | --- | --- | --- |
| **1. Minimal synthetic demo** — one level, synthetic AIDs ≤ 1,024 B, certificate + delegated registration + delegated rotation, executable vectors both languages | **0.85–0.95** | none technical; only the datum/version decision and the certificate script's execution cost (U4) | S1 + S2 landing green |
| **2. Real one-level delegated registration** — the *actual* GEDA `dip` (1,017 B) registered against a **declared pinned root** trust boundary | **0.60–0.80** | the root's key state must come from somewhere; a pinned root is a stated trust boundary, not a proof. Needs `est_history` or same-transaction capture for the `rot@1` anchor | S2 + S4; a decision to accept a pinned root |
| **3. Recursively validated real GLEIF Root → GEDA → QVI ancestry** | **0.25–0.45** | multi-chunk BLAKE3 for the 1,181-byte root (U5, unimplemented), `ixn`-anchor liveness (§8.3), U1/U2 on the QVI tier, U3 on advance cost | S3 + S5 + retrieving a QVI KEL |
| **4. Production-ready mainnet support** | **0.10–0.25** | Axis-D challenge design and Story-4 recovery (least designed); U3 execution headroom; script-size budget with `observer_advance` already at 90.8%; KERI v2 drift (U7); mainnet bond economics | all spikes green plus a settled recovery semantics ruling |

These are subjective probabilities over a single-milestone horizon, conditioned
on the assumptions above. I decline to publish a single number: bands 3 and 4
are dominated by unknowns U1–U5, and two of those (U3, U5) could each on their
own force a redesign rather than a schedule slip. If S3 shows a production-shape
advance over 16.5 M units, band 4 drops below 0.10 until the signature-verification
work is itself moved into premint proof transactions — which is a larger change
than delegation.

---

## 13. Decisive falsifying spikes

Ordered by information gained per unit of effort. Each is designed to be able to
*fail*.

**S0 — ~~Falsify~~ *remediate* the `dip`/`drt` boundary (do this first).**
**Superseded as an open question: both event-level witnesses now exist and I
have audited them (§3.3.1).** What remains is not discovery but proof and
repair, at three levels, each shown able to fail:
(a) **transaction-envelope fixtures** — drive witness 1 through the full
`hash_proof` → `checkpoint_register` path and witness 2 through the
`observer_advance` path with constructed `ScriptContext`s, asserting
`RegistrationValid` / accept *before* the fix and rejection after;
(b) **Haskell/Aiken parity** on both verdicts;
(c) **live-boundary test** against a real node, since predicate-level green has
not implied chain-level green in this codebase.
Extend the same three levels to `enforcement.ak:81`, which shares the
construction and has not been witnessed — that one is still a genuine open
question, and it bears on the #106 framing-resistance requirement.

**S1 — Certificate script cost (1–2 days).** Implement the §8.2 mint check
against real production bytes (GEDA `dip` + root `rot@1`, and GEDA `ixn` +
a synthetic child) and measure. *Falsifies:* U4 and the 3-transaction count.
*Fails if* the certificate needs more than ~8 M memory units, which would force
a split and make delegated registration four transactions.

**S2 — Real GEDA registration against a pinned root (2–3 days).** Register the
actual production GEDA `dip` end-to-end on preprod with the root's key state
pinned as a script parameter. *Falsifies:* band 2. *Fails if* the 7-byte margin
under the chunk ceiling turns out to be consumed by anything, or if the pinned
root is judged an unacceptable trust boundary.

**S3 — Production-shape advance measurement (1 day, highest value per hour).**
Measure a `rot` with 7 revealed keys, 7 next digests, 5 witnesses and `toad = 4`
— the actual GLEIF Root shape — against the *correct* 16.5 M budget.
*Falsifies:* U3 and, with it, band 4. *Fails if* it exceeds 16.5 M, in which
case delegation is not the project's problem.

**S4 — `ixn`-anchor liveness (1 day).** Build the observation transaction for a
real GEDA `ixn` anchor and then demonstrate that the same evidence is rejected
once the referenced checkpoint has advanced past that establishment epoch.
*Falsifies:* §8.3. *Fails if* it can somehow still be verified — which would mean
I have missed a mechanism.

**S5 — Multi-chunk BLAKE3 (1–2 weeks).** Extend the #97 checkpointed core from a
single chunk to the BLAKE3 chunk tree, and hash the real 1,181-byte root `icp`.
*Falsifies:* U5 and band 3. *Fails if* the chunk-tree parent compression pushes
the per-transaction cost past budget or the transaction count past ~4.

**S6 — Retrieve a real QVI KEL (hours, if an OOBI can be obtained).**
*Falsifies:* U1 and U2. Requires a QVI OOBI; the GLEIF witness at
`65.21.253.212:5623` serves only the root and GEDA (404 on both delegatee AIDs
I tried).

**S7 — Superseding-recovery semantics (design spike, 2–3 days).** Write the
Axis-D challenge predicate and its Story-4 checkpoint-repair semantics, with
adversarial vectors, before any code. *Falsifies:* the assumption that the
existing conviction machinery generalizes. This is the spike most likely to
uncover work nobody has costed.

---

## 14. Recommendations

1. **Ship the §3.3 fix now**, on its own issue, decoupled from delegation:
   delete `off_t` from all three evidence types and bind the type at the fixed
   offset 30; add canonical field-set/order binding per ilk; add declared-size
   equality as hardening (`registration.ak`, `advance.ak`, `enforcement.ak`).
   Land it under the full remediation contract — adversarial fixtures built from
   witnesses W1/W2 plus the hand-crafted `icp`-with-`di` case, Haskell/Aiken
   parity on bytes and verdicts, and a live-boundary rejection test. The
   deployed preprod release carries the defect.
2. **Run S3 before any delegation design is ratified**, and treat S0 as repair
   work rather than investigation — the question it was going to answer has been
   answered (§3.3.1). S3 tells you whether the production shape fits at all.
3. **If delegation proceeds, choose Architecture B′** (§8.2 + §8.4): certificate
   UTxOs plus a 32-byte establishment-history commitment. Do not attempt direct
   recursive verification; do not add `di` to a datum without the certificate
   requirement that gives it meaning.
4. **Fix `threshold.well_formed` to represent abandonment** (`n: []`) as a
   terminal state. It is a small change with disproportionate consumer value at
   the issuer tier.
5. **Say what delegation does not buy.** It gives no revocation (§4.4). Publish
   that in the same document that announces it, or the feature will be
   mis-sold.
6. **Treat the KERI v1/v2 gap as a first-class scheduling risk** (U7). Every
   byte-offset predicate in this system is protocol-version-specific, and the
   normative specification has already moved to v2 while production has not.

---

## 15. Claim ledger

Primary sources, with stable identifiers.

**Normative**

| ID | Claim | Source |
| --- | --- | --- |
| K1 | Cooperative delegation = `di` in the delegated inception + event seal in the delegator's KEL; both parties MUST participate | KERI specification v1.1, §Cooperative Delegation. https://trustoverip.github.io/kswg-keri-specification/ — DOI https://doi.org/10.5281/zenodo.18887102 |
| K2 | The pair of bindings is the "two-way binding (two-way peg)" | ibid., §Delegated Inception Event Example |
| K3 | A delegated AID's prefix MUST be a digest of its inception event including the delegator reference | ibid., §Cooperative Delegation |
| K4 | A `drt` has no `di` and inherits it from the `dip` | ibid., §Delegated Rotation Event Message Body |
| K5 | Delegation operations seal an establishment event — inception **or rotation** | ibid., §Cooperative Delegation |
| K6 | A rotation (delegated or not) MUST satisfy both current and prior-next thresholds | ibid., §Signature Thresholds |
| K7 | A non-party validator MUST verify controller signatures, witness signatures and the delegator anchoring seal before accepting | ibid., §Validator role |
| K8 | Delegation validity persists in spite of changes to the delegator's key state | ibid., §Sealing |
| K9 | Superseding rules A0–A2, B1–B3, C/C1 | ibid., §Superseding Rules for Recovery at a given location, SN |
| K10 | `n: []` on a rotation ⇒ the AID MUST be deemed abandoned; no further events | ibid., §Next Key Digest field |
| K11 | `DND` config trait: a validator MUST drop delegated events whose delegator carries it; traits are inception-only | ibid., §Configuration Traits |
| K12 | The KERI specification document is at status v1.1 and describes protocol version 2.0 (`KERICAACAAJSON` version strings) | ibid., §Version String; header block |

**Implementation**

| ID | Claim | Source |
| --- | --- | --- |
| P1 | `validateDelegation` requires the delegator's KEL, rejects on `doNotDelegate`, resolves the anchor via `kels.getLast` ("not disputed or superseded"), and matches the seal on `(i, s, d)` | `WebOfTrust/keripy`, `src/keri/core/eventing.py`, `main` @ `7da1e64a1df971ab34d622e2f30c541e7c48305c` (2026-08-11), `Kever.validateDelegation` |
| P2 | Superseding `drt`-over-`drt` climbs the delegation chain in an unbounded loop via `fetchDelegatingEvent` | ibid. |
| P3 | keripy 1.3.5 (protocol v1) emits `rot`/`drt` **without** the `c` field | measured on `offchain/test/keri-fixtures/fixtures/registration.json` (`reg_drt`, 352 B), `advance.json`, and live production events |
| P4 | GLEIF operates on the `gleif/keri:1.1.44` image (protocol v1) | `GLEIF-IT/gar`, `README.md`, `main` |

**Production data** (all retrieved 2026-08-14)

| ID | Claim | Source |
| --- | --- | --- |
| G1 | GLEIF Root AID `EDP1vHcw_wc4M__Fj53-cJaBnZZASd-aMTaSyWEQ-PC2`, `icp` 1,181 B, 7 keys, 7 next, 5 witnesses, `toad` 4, `kt`/`nt` = 7 × `1/3` | witness OOBI `http://65.21.253.212:5623/oobi/EINmHd5g7iV-UldkkkKyBIH052bIyxZNBn9pq-zNrYoS/controller` |
| G2 | GEDA `EINmHd5g7iV-UldkkkKyBIH052bIyxZNBn9pq-zNrYoS`, `dip` 1,017 B, `di` = root, 5 keys, 5 next, 5 witnesses, `toad` 4, `kt`/`nt` = 5 × `1/2`, first-seen 2022-11-30 | ibid. |
| G3 | The root `rot@1` (895 B) seals `{i: GEDA, s:"0", d: GEDA}`; the GEDA `dip`'s CESR source-seal couple names sn 1 and that rotation's SAID | ibid. |
| G4 | The GEDA's KEL is `dip` + 26 `ixn`, carrying 28 seals: 14 `dip`-shaped delegations and 14 other anchors; **all delegation anchors are interaction events** | ibid. |
| G5 | Two GEDA seals name the same digest at different sequence numbers for the same subject | ibid., `ixn@7` and `ixn@8` |
| G6 | GEDA inception config: `delpre` = root, weighted `1/2` thresholds, 5 witnesses, `toad` 4 | `GLEIF-IT/gar`, `external/scripts/ext-aid-incept.json`, `main` |
| G7 | The delegation anchor file GLEIF operators use has the seal shape `{i, s, d}` | `GLEIF-IT/gar`, `external/scripts/anchor.json`, `main` |
| G8 | QVI single-sig inception config: `delpre` = GEDA, 1 witness, `toad` 1 | `GLEIF-IT/gar`, `external/config/qvi-incept-single-sig.json`, `main` |
| G9 | Live mainnet epoch 649: `maxTxExMem` 16,500,000; `maxTxSize` 16,384; `priceMem` 0.0577; `priceStep` 0.0000721; `minFeeRefScriptCostPerByte` 15 | Koios `/epoch_params`, `https://api.koios.rest/api/v1/epoch_params` |

**Repository at `ae99e35e6aee577ccfc61a62f8a72f6067c1154b`**

| ID | Claim | Source |
| --- | --- | --- |
| C1 | The only `dip` rejection on the wired registration path is a 3-byte slice at a prover-supplied offset; `validate_inception_datum` is called with a literal `Icp` | `onchain/lib/cardano_keri/checkpoint/registration.ak:313,381` |
| C2 | Same construction on the advance and enforcement paths | `onchain/lib/cardano_keri/checkpoint/advance.ak:115`; `onchain/lib/cardano_keri/checkpoint/enforcement.ak:81` |
| C3 | The deployed observer entry point adds no event-type check | `onchain/lib/cardano_keri/checkpoint/observer.ak:66-102` |
| C4 | Honest fixtures use `off_t: 30`, corroborating the fixed structural offset | `onchain/validators/checkpoint_measurements.ak:294,317` |
| C5 | Empty key lists are rejected for both current and next state, so abandonment cannot be projected | `onchain/lib/cardano_keri/checkpoint/threshold.ak:93`; `datum.ak:89-115` |
| C6 | Compiled sizes: `observer_advance` 14,871 B (90.8% of the 16,384-byte cap); `checkpoint_register` 13,033 B | built at the sealed commit, pinned Aiken 1.1.23 (nixpkgs `753cc8a3a87467296ddd1fa93f0cc3e81120ee46`), `aiken build -t silent` |
| C7 | Committed execution-unit measurements and their 14,000,000-unit memory denominator | `specs/114-permissionless-registration/MEASUREMENTS.md`; `specs/115-advance/MEASUREMENTS.md`; `specs/116-*/MEASUREMENTS.md` |
| C8 | In-script BLAKE3 costs 10,035,212 memory / 5,429,574,328 CPU at 1,024 B; the checkpointed split costs ~70% of a transaction per half-chunk and covers a **single** chunk only | `spikes/88-blake3-plutus/REPORT.md`; `spikes/97-blake3-multitx/REPORT.md` |
| C9 | Registration and advance are permissionless and authenticate KEL-own signatures over raw event bytes | `specs/219-permissionless-advance/spec.md`; `specs/114-permissionless-registration/` |
| C10 | A hash-identified validator family with migration entry/exit already exists, so a new delegated version has a landing path | `specs/254-validator-migration/spec.md` |
| C11 | M1 is live on preprod as five reference scripts with `d_reg` = 1,000,000,000 lovelace | `docs/user/m1-preprod-deployment.md`; `deploy/preprod/m1-manifest.json` |
| C12 | The delegation boundary was decided as an explicit versioned extension, with eight named completion requirements | `specs/68-keystate-shape/delegation-boundary-decision.md` |
| C13 | vLEI credential chaining is ACDC `e` edges; no vLEI schema contains a KERI delegation field | `specs/68-keystate-shape/acdc-zoo.md`; corroborated at `https://github.com/WebOfTrust/vLEI/tree/main/schema/acdc` |
| C14 | Committed real keripy `dip` (351 B) and `drt` (352 B) rejection fixtures, and a 1,271 B oversize inception | `offchain/test/keri-fixtures/fixtures/registration.json` |

**Collision witnesses (supplied by the coordinator; every claim independently
re-derived by me from the published bytes — §3.3.1)**

| ID | Claim | Source |
| --- | --- | --- |
| W1 | A genuine signed 351-byte keripy `dip`, canonical `t="dip"` at offset 30, `icp` at offset 237 inside its next-key digest, passes E1–E9, R4, R7, R8 and the hash-proof policy | `OFF-T-COLLISION-WITNESS.md`, SHA-256 `f9ccd1e02a52d9c6062d507f02f9347434e45d633deba47cf9347e634de0a933` (verified); SAID, signature and all offsets re-derived independently with `b3sum` + Node.js Ed25519 |
| W2 | Its genuine signed 352-byte sequence-1 `drt`, canonical `t="drt"` at offset 30, `rot` at offset 59 inside its own SAID, passes AE1–AE10 and the dual-threshold gate | `OFF-T-COLLISION-DIP-DRT-WITNESS.md`, SHA-256 `f80fb1110da836bc2c756a7e063b64b8871681a0c652fdbc5fa53ec45489088c` (verified); same independent re-derivation |
| W3 | The pair chains: `blake3(qb64("DF-MVNF7Lz_RtunA3OewtsGAmKbvnpuxSQo2zcG1rcpO"))` = `EIOyUoVz0YWjQYDicp_f6h6Xk1dWuI30DfuWmjNotom2`, the `dip`'s own next digest | computed by me, `b3sum 1.8.3` |
| W4 | Both witnesses carry correct version-string sizes (0x00015f = 351, 0x000160 = 352), so a declared-size check does **not** catch them | computed by me from the published JSON |

**Reproduction commands for my own measurements**

```console
# production KELs
curl -sS http://65.21.253.212:5623/oobi/EINmHd5g7iV-UldkkkKyBIH052bIyxZNBn9pq-zNrYoS/controller

# AID reproduction: dummy the 44-char d and i spans with '#', then
b3sum --no-names --raw <dummied>   # → 'E' + base64url(0x00 ‖ digest)[1:]

# script sizes
cd <copy-of>/onchain && nix shell github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken \
  -c aiken build -t silent && jq -r '.validators[] | [.title, ((.compiledCode|length)/2)] | @tsv' plutus.json

# chain parameters
curl -sS https://api.koios.rest/api/v1/epoch_params
```

---

*End of report. Every unknown is flagged; no uncertainty has been smoothed into
a single percentage.*
