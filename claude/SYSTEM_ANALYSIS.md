# Full-System Analysis — Real KERI ⇄ cardano-keri ⇄ MPFS Value Cages

**Scope:** the *composed* system, not the on-chain crypto in isolation. Inputs:
`docs/index.md`, `docs/architecture/*`, `docs/design/*`, `docs/vetting/index.md`,
`docs/aid-ops.md`, and the prior crypto vetting in `discussion.md` /
`claude/ANALYSIS.md` / `codex/ANALYSIS.md`.

**What the prior round settled (and I take as given here):** the on-chain identity
layer (self-cert + pre-rotation + monotonic `seq` on a single trie) is sound; the
value-write layer needs the signer-model decision (Option B preferred) plus
canonical encoding, domain separation, and the operational bundle. This document
does **not** re-litigate those. It attacks the seam the prior round deliberately
left out of scope: the relationship between the **on-chain registry** and a **real
off-chain KERI deployment**, and what the MPFS data-plane actually inherits from
that relationship.

---

## Executive summary

**The single most important finding is a framing correction, and everything else
follows from it.** The brief describes a *bridge*: "a KERI AID controller maintains
a full off-chain KEL … on each KERI rotation the controller ALSO submits a Cardano
transaction updating their key-state." **The documented system is not that bridge.**
`docs/design/trust-model.md` is explicit and honest: *"cardano-keri borrows the
pre-rotation primitive from KERI. It does not implement KERI."* What is specified is
a **self-contained, KERI-inspired pre-rotation registry** whose AID is
`blake2b_256(cbor({cur_key, next_digest}))`. A real KERI AID is a **Blake3-256 SAID
over a multi-field CESR/JSON inception event**. These are different functions of
different inputs producing different bytes. **The on-chain AID and the controller's
real KERI AID are not the same value and have no cryptographic link.** So before
we can ask "what keeps the two key-states synchronized," we have to notice there is
no shared identifier to synchronize *to*. The "synchronization invariant" the brief
worries about is, as specified, an invariant **between two systems that share no
endpoint**.

This reframes all seven dimensions:

1. **Synchronization invariant** — Nothing enforces it; nothing *can*, on-chain.
   But the deeper problem is there is no binding between the two AIDs to even make
   the invariant statable. The chain is its own root of authority for the on-chain
   key-state; it never sees the KEL. Detection is possible only for a relying party
   who reads *both* worlds *and* who has been handed an off-chain attestation
   linking the two AIDs — i.e., nobody the protocol guarantees exists.

2. **Two-world problem** — Real and consequential. The MPFS data-plane is governed
   **exclusively** by the on-chain snapshot. Its security ceiling is the on-chain
   registry's *freshness*, not the KEL's authority. A key the KERI world has
   rotated away from (e.g. a vLEI-revoked entity) keeps full MPFS write authority
   until — and only if — the controller performs an on-chain rotation, which the
   griefing and revocation gaps from the prior round can block or fail to honour.

3. **Cardano as a KERI witness** — Possible only in a redefined sense. The ledger
   cannot produce a CESR `rct` witness receipt (it has no witness signing key and
   cannot parse/verify a CESR event on-chain). What it *can* provide is something a
   witness pool only approximates: a **global total order with enforced
   single-history** at the anchored AID. That is a strictly different — and in one
   axis stronger — trust primitive than a threshold of witness signatures, at the
   cost of ~20 s latency and probabilistic (hours-deep) finality.

4. **Delegation** — Absent, and it is the **highest-value missing feature for the
   MPFS use case**, because hierarchical org control of leaves (parent authorizes /
   rotates / revokes child) is exactly what real deployments (vLEI: GLEIF → QVI →
   Legal Entity) are built on. Addable, but it needs a new cooperative-anchoring
   operation, not a field tweak.

5. **Multi-sig threshold** — Single-key is **insufficient** for any organizational
   leaf owner. KERI key-state is natively a *list with a threshold* (`k`/`kt`,
   `n`/`nt`). For a DAO, single-key is a single point of failure that doesn't match
   governance. Option B maps threshold onto Cardano's native `atLeast` multisig
   cleanly; this is the most tractable of the KERI-parity gaps.

6. **KEL anchoring vs key-state anchoring** — Anchoring a KEL-root commitment (B)
   adds **falsifiability**: it lets a KEL-replaying verifier *detect* divergence at
   each anchored checkpoint and attribute it. It does **not** close the
   synchronization gap — nothing on-chain forces the controller to anchor every
   event, and the MPFS-only relying party (who never replays) gains nothing from
   it. (B) upgrades "trust the snapshot" to "trust the snapshot, detectable at
   anchors if someone replays." That is a real improvement and still not
   enforcement.

7. **Practical KERI adoption (vLEI)** — A vLEI controller **cannot anchor their
   actual AID** with this system. Blake3-256 SAIDs are not recomputable on-chain
   (PlutusV3 has no Blake3); the inception event is multi-field CESR/JSON, not a
   2-field CBOR record; keys and next-keys are *lists with thresholds*; the AID is
   delegated; events are witnessed and hash-chained by prior-event digest (`p`).
   Every one of those is a hard mismatch. The best achievable is a *separate*
   cardano-keri AID plus an off-chain attestation binding it to the vLEI AID — at
   which point the chain is not anchoring KERI, it is a parallel identity claiming
   linkage, and the linkage trust lives entirely off-chain.

### System-level findings

| # | Finding | Severity | Dimension |
|---|---|---|---|
| S1 | On-chain AID ≠ KERI AID; no enforced binding between the two identifiers | **Critical (design)** | 1, 7 |
| S2 | Synchronization invariant has no on-chain enforcement and, as specified, no shared endpoint to enforce | **Critical (design)** | 1 |
| S3 | MPFS data-plane authority is ceilinged by on-chain *freshness*, not KEL authority; honours KERI-stale/revoked keys | **High** | 2 |
| S4 | No delegation → no hierarchical org control of MPFS leaves | **High** | 4 |
| S5 | Single-key key-state → no threshold ownership; SPOF for org/DAO leaves | **High** | 5 |
| S6 | No KEL-event anchoring → divergence is undetectable even by a replaying verifier | **High** | 1, 6 |
| S7 | Cannot represent or verify real-KERI (Blake3/CESR/multi-field) AIDs on-chain | **High** | 7 |
| S8 | "Cardano as witness" conflates *anchoring* with *witness receipt*; no CESR receipt, no on-chain event verification | **Medium** | 3 |
| S9 | Revocation in the KERI world does not propagate to the data-plane | **Medium** | 2, 4 |
| S10 | Finality/latency mismatch: KERI receipts sub-second; Cardano anchor ~20 s + hours-deep settlement for high value | **Medium** | 3 |

The crypto-layer findings from the prior round (V1–V10) are inputs to several of
these — notably the recovery-rotation griefing (V3) and the tombstone-is-not-
revocation gap (V5), which become *system* failures here because they are the exact
mechanisms by which the on-chain world fails to track the off-chain world.

---

## 1. The synchronization invariant

**Claim under test:** the security of the composed system depends on the on-chain
key-state matching the KEL's current key-state.

**What enforces it on-chain: nothing — and nothing can.** The registry script's
inputs are: a redeemer, an MPF proof against its own root, and (for rotation) an
Ed25519 signature by `reveal_key`. It never receives the KEL, cannot parse CESR,
cannot verify witness receipts, and cannot run the KEL's digest function (Blake3).
The on-chain registry is therefore a **second, independent key-state machine**, not
a mirror of the first. It advances when, and only when, someone submits an on-chain
inception/rotation; it has its own `next_digest` pre-commitment, its own `seq`, and
its own notion of "current key." Two independent state machines with no shared
transition function do not stay equal by construction; they stay equal only if an
honest controller drives both in lockstep.

**There is not even a shared identifier.** As specified, the on-chain
`AID = blake2b_256(cbor({cur_key, next_digest}))` is a different value from the
controller's KERI AID (§7). So the invariant "on-chain key-state for AID *X* equals
KEL key-state for AID *X*" cannot be written down: the *X* on each side is a
different byte string. The invariant the brief names presupposes a binding the docs
never establish.

**Three independent ways the (intended) invariant breaks:**

- **Asymmetric rotation.** Controller rotates off-chain (KERI witnesses accept it)
  but does not — or cannot — rotate on-chain. The on-chain `cur_digest` now names a
  key the KERI world has retired. The reverse is equally possible.
- **Pre-commitment drift.** The on-chain `next_digest` and the KEL's `n` list are
  chosen independently. A controller who picks different next keys on each side has
  two genuinely different futures committed; after one rotation the two key-states
  are unrelated, not merely stale.
- **Griefing-induced lag.** Per `operational.md`, the single identity UTxO admits
  one rotation per block, and (in the dual-compromise case) an attacker can occupy
  every block. The on-chain world can be *prevented* from tracking an off-chain
  recovery rotation precisely when tracking it matters most.

**Who detects a break?** Only a relying party who (a) reads the on-chain snapshot,
(b) replays the KEL, **and** (c) possesses an off-chain attestation binding the two
AIDs so that "the same identity" is even well-defined across the two reads. The
MPFS-only relying party reads only (a) and cannot detect it. The KERI-only relying
party reads only (b) and cannot detect it. The protocol guarantees the existence of
none of these three inputs for any party. **Detection is possible; it is nobody's
guaranteed job.**

> **Verdict:** the invariant is unenforced, and worse, unstatable as written. The
> first constructive move is not "enforce it" (impossible on-chain) but "make it
> *statable and falsifiable*" — bind the two AIDs (§7) and anchor KEL events (§6).
> Enforcement of *liveness* (every event anchored) remains impossible on-chain and
> must be pushed to watchers + incentives.

---

## 2. The two-world problem

**Setup:** RP-MPFS checks the on-chain snapshot (CIP-31 reference input) to
authorize a leaf write. RP-KERI replays the KEL and verifies witness receipts. They
can disagree about who controls AID *X*.

**When divergence occurs:** any time the on-chain and off-chain key-states are not
equal — i.e., all of §1's break modes — plus one the brief understates:

- **Revocation that doesn't propagate.** In KERI, a controller can *abandon* an AID
  (a rotation to a null/zero next-key set, or simply ceasing to witness) and, in
  vLEI, a credential/AID can be revoked by the issuer. None of this touches the
  on-chain `cur_digest`. Per `identity-ops.md` / `operational.md`, even an on-chain
  *tombstone* (`new_next = 0x00…00`) stops future rotation but **leaves
  `cur_digest` live for value-writes**. So a KERI-revoked or KERI-abandoned key
  retains full MPFS authority.

**Consequences, asymmetrically:**

- **For RP-MPFS (the consequential one):** the data-plane honours the *on-chain*
  key, full stop. If that key is stale-or-revoked in the KERI world, RP-MPFS
  authorizes a write by a key the *real* identity authority has retired. Because
  the MPFS use case is the entire point of the system, this is the load-bearing
  failure: **MPFS security is capped by on-chain freshness, not by KERI authority.**
  The expensive off-chain KERI machinery (witnesses, watchers, duplicity detection,
  legal-grade vLEI revocation) does not protect MPFS leaves at all unless its
  conclusions are *pushed onto the chain* by a successful on-chain rotation/revoke —
  exactly the step that has no liveness guarantee.

- **For RP-KERI:** the failure is "rejects something MPFS accepted," which surfaces
  as an audit/repudiation problem: a leaf write that the chain treats as authorized
  but that the KEL says was made by a non-controlling key. RP-KERI's view is the
  one that matches real-world/legal trust, so this is the view under which the MPFS
  write is "fraudulent" even though it was on-chain-valid.

**The compounding factor:** the divergence is *silent* to each party in isolation
(§1), and the party that suffers (RP-MPFS, and downstream, the real identity owner)
is precisely the party with the least ability to detect it, since RP-MPFS by design
reads only the chain.

> **Verdict:** this is the most practically dangerous dimension. The mitigation is
> not symmetric reconciliation; it is (a) propagate KERI revocation to a real
> on-chain `revoked` flag that **cage scripts must check** (closes S9 and the
> tombstone gap), and (b) make the on-chain rotation the *authoritative* control
> point for the data-plane and accept that the data-plane therefore inherits the
> on-chain liveness/griefing risk — then harden *that* (require the identity UTxO be
> spendable only by a valid reveal-key rotation; settlement depth; anti-griefing).

---

## 3. Cardano as a KERI witness

**The question:** could the Cardano ledger be one of the *N* witnesses for a KERI
AID? What is the receipt format? What are the constraints?

**What a KERI witness actually does.** A witness is a designated AID (listed in the
controller's `b` field, with threshold-of-accountable-duplicity `bt`/toad). On
receiving a key event, it (1) verifies the event against the key-state it holds,
(2) checks it has not already receipted a *different* event at that sequence number
(duplicity), and (3) returns a **receipt**: its own signature over the event's SAID
(a `rct` message / witness receipt couplet). Controllers gather ≥ toad receipts to
make an event "fully witnessed"; watchers compare receipts across witnesses to
surface duplicity.

**Why the ledger cannot be a witness in the literal sense.** Two hard blockers:

- **No witness signing key.** "Cardano" is not a principal with an Ed25519 key that
  can sign a SAID. A receipt is *a specific witness AID's signature*; there is no
  such key for the chain itself.
- **No on-chain event verification.** A witness must *verify the event* before
  receipting (steps 1–2). The registry script cannot parse CESR/JSON, cannot run
  Blake3 to recompute the SAID, and cannot evaluate weighted thresholds over a key
  list as KERI defines them. So the script cannot perform the validation a witness
  is responsible for.

**What the ledger *can* be — and it is arguably stronger on one axis.** Anchor the
event seal `{i: aid, s: seq, d: event_said}` into the registry via a rotation/
interaction transaction. Because the single identity UTxO holds exactly one
key-state per AID and rotation requires `seq_to == seq + 1` against the *consumed*
root, **the chain physically cannot anchor two conflicting events at the same
sequence number** — the second spend fails. That is the anti-duplicity guarantee a
witness pool only achieves *probabilistically* (if ≥ toad honest witnesses never
sign a fork). So Cardano offers **global total order + enforced single-history**,
which dominates a witness threshold for non-duplicity, while offering **nothing** on
the axes a witness is fast at.

**Two concrete "receipt" realizations, neither standard:**

1. **Ledger-backed witness service.** A bridge holds a real witness AID key,
   watches the chain, and — once the anchoring tx reaches a chosen confirmation
   depth — emits a *standard* CESR `rct` over the event SAID. KERI verifiers consume
   it unmodified. Trust shifts to the bridge's key, but the bridge's honesty is
   "follows the chain," and any duplicity it commits is chain-detectable. This is
   the pragmatic path: real receipts, Cardano as the bridge's source of truth.
2. **Custom "ledger receipt" type.** A new CESR receipt whose verification is "tx
   anchoring this seal is in the Cardano chain at depth ≥ N." This needs a Cardano
   light client *in every KERI verifier* and a non-standard receipt codec. Most
   faithful to "Cardano *is* the witness," least deployable today.

**Practical constraints (the brief's numbers, sharpened):**

- **Latency.** Witness receipts are sub-second; a Cardano anchor is one block
  (~20 s average at `f = 0.05`, 1 s slots) *before any confirmation depth*.
- **Finality.** The brief's "~5 blocks" (~100 s) is fine for low-value ordering but
  optimistic for identity. Praos common-prefix security is parameterized by
  `k = 2160` blocks (~12 h); practical high-value settlement is tens of blocks
  (minutes), deep settlement is hours. A witness gives "accountable now"; the chain
  gives "irreversible later." For a *legal-identity* anchor you want the latter and
  must budget the wait.
- **Cost & liveness.** Every receipted event is an on-chain tx contending for the
  single identity UTxO (one per block — `operational.md`). A witness pool has no
  such global bottleneck. So Cardano scales poorly as a *per-event* witness and
  well as a *checkpoint* witness (receipt every K-th event, or only establishment
  events).

> **Verdict:** don't sell Cardano as a drop-in Nth witness. Sell it as a
> **checkpointing super-witness** that provides ordering/non-duplicity/public
> auditability that ordinary witnesses can't, accessed either via a ledger-backed
> witness service (deployable now) or a custom ledger-receipt extension (faithful,
> not yet deployable). Combine with fast conventional witnesses for liveness.

---

## 4. Delegation

**How KERI delegation works.** A delegated AID is incepted with a delegated
inception event (`dip`) carrying `di` = delegator AID; delegated rotation is `drt`.
Delegation is *cooperative and mutually anchored*: the delegate's `dip`/`drt` SAID
must be sealed (anchored) in the **delegator's** KEL (via the delegator's `ixn`/
rotation `a` seals). Neither side can move the delegation unilaterally — the
delegate commits to the delegator (`di`), and the delegator ratifies by anchoring
the delegate's event digest. This is the backbone of vLEI: GLEIF's external
delegated AID (GEDA) delegates QVIs, QVIs sit above Legal Entity AIDs.

**Importance for MPFS: high — arguably the feature that makes the system
organizationally usable.** The natural MPFS ownership model is hierarchical: an org
root AID owns a region of the cage's keyspace and authorizes child AIDs to write
specific leaves, with the power to *rotate or revoke a child* if the child's key is
lost or the employee leaves. Single, flat, self-incepted AIDs (today's design)
force every leaf owner to be an independent root of trust with no recovery path and
no organizational override — which is wrong for exactly the institutional users
(vLEI-style) this is pitched at. Without delegation, "a DAO owning MPFS leaves"
degenerates to "a shared single key," which is both §5's SPOF and an audit
nightmare.

**What it takes to add it (sketch):**

- **State.** Add `delegator : Option<AID>` to `KeyState` (or a parallel delegation
  record in the trie).
- **A cooperative-anchoring operation.** A delegated inception/rotation tx must be
  accompanied by evidence that the delegator's current key-state has anchored the
  delegate event's digest. Two implementable shapes:
  - *Same-tx co-authorization:* the delegated op and a delegator *anchor op* are in
    one transaction; the delegator's `cur_digest` must be a required signer
    (Option B) and the tx commits the delegate event digest in a seal the registry
    records.
  - *Prior-seal proof:* the delegator performs an interaction-style anchor op first
    (recording `{delegate_aid, seq, event_digest}` in the identity trie or a
    side-trie), and the delegated op presents an MPF inclusion proof of that seal.
- **A new "interaction/anchor" operation.** KERI's `ixn` has no analogue here; you
  need one for the delegator to ratify without rotating. This doubles as the
  KEL-anchoring primitive in §6.
- **Revocation of delegation** must reuse §2's data-plane revocation: revoking a
  child must stop the child's value-writes, not merely freeze its rotation.

> **Verdict:** delegation is not a nice-to-have for the MPFS use case; it is the
> difference between a toy and an org-grade registry. It is addable but it is *new
> machinery* (state field + cooperative anchoring + an interaction op), and the
> interaction op is shared infrastructure with §6, so design them together.

---

## 5. Multi-sig threshold

**KERI is natively threshold.** Key-state is a *list* `k` with a (possibly
weighted) threshold `kt`, and pre-rotation commits to a *list* `n` with threshold
`nt`. `kt`/`nt` can be fractional weighted (`["1/2","1/2","1/2"]`, meaning any two
of three). cardano-keri's `KeyState` is strictly single: one `cur_digest`, one
`next_digest`. It cannot express `2-of-3` current or `3-of-5` next.

**Is single-key sufficient for a DAO owning MPFS leaves? No.** Single-key means:
one compromised or lost key = total loss of the leaf region; no separation of duty;
no governance quorum; no per-signer accountability. For any organization — and
emphatically for a DAO, whose entire premise is distributed control — single-key
defeats the purpose. The prior round's recovery-rotation griefing (V3) is also
worse single-key: one key is one point an attacker must occupy.

**What it takes — and why Option B makes it easy.** This is the *most tractable* of
the KERI-parity gaps because Cardano has native threshold multisig:

- **State.** `cur_keys : [KeyDigest]`, `cur_threshold : Threshold`,
  `next_keys : [KeyDigest]`, `next_threshold : Threshold` (support weighted, not
  just `m-of-n`, to match KERI).
- **Authorization, Option B:** check that a satisfying weighted subset of
  `cur_keys` appears in `tx.extra_signatories`. This is *exactly* Cardano's native
  `atLeast n [pkh…]` script semantics — the ledger already enforces multi-required-
  signers, so the on-chain check is a subset/weight test, no extra Ed25519 verifies.
- **Authorization, Option A:** carry a list of `(vk, sig)` and count satisfied
  weights; costs one Ed25519 verify per provided signature (bounded by the list
  length, so keep `k` small or cap it).
- **Pre-rotation with thresholds:** rotation reveals the participating next keys
  and the script checks each `blake2b_256(reveal_key_i) == next_keys[j]` and that
  the revealed set satisfies `next_threshold`. Commit the *new* `next_keys`/
  `next_threshold` simultaneously.

**One subtlety:** weighted thresholds must be encoded canonically and domain-
separated like everything else (prior round), and the threshold itself must be part
of the rotation-signed message so it can't be downgraded (e.g. an attacker rotating
`2-of-3` down to `1-of-3`). Bind `cur_threshold`/`next_threshold` into `rot_msg`.

> **Verdict:** single-key is insufficient for the stated organizational/DAO use
> case; threshold is necessary, not optional. Option B + Cardano-native `atLeast`
> makes it the cheapest KERI-parity upgrade to ship. Guard against threshold-
> downgrade by binding thresholds into the signed rotation message.

---

## 6. KEL anchoring vs key-state anchoring

**(A) key-state only (today):** the datum/trie holds `{cur_digest, next_digest,
seq}` — a *snapshot*. It commits to *a* current key-state but not to the *history*
that produced it. Many different KELs (different intermediate keys, different
interaction events, even a forked history that reconverges) can yield the same
current snapshot. The on-chain state cannot tell you *which* KEL it corresponds to —
it doesn't even reference a KEL event.

**(B) anchor a KEL-root commitment:** additionally store, per AID, a commitment to
the KEL up to event N — concretely the SAID of event N (which in KERI hash-chains
all priors via `p`), or a running accumulator. Each on-chain rotation/anchor records
the event digest it corresponds to.

**What (B) adds:**

- **Falsifiability / attributable divergence.** A KEL-replaying verifier can now
  compute each event's SAID and check it against the on-chain anchor. If the KEL
  they were handed disagrees with the chain at event N, they *detect* it and can
  *attribute* it (the chain says SAID *x*, my KEL says SAID *y* at seq N → someone
  forked). Under (A) there is nothing to compare against — the snapshot has no event
  identity.
- **Anti-duplicity teeth for the bridge.** Combined with §3's single-history
  property, anchoring event digests means the chain enforces *one* KEL prefix per
  AID. Two conflicting event-N's cannot both be anchored. This is the strongest
  duplicity guarantee in the system.
- **A real link to KERI.** Anchoring the *KERI* event SAID (not a cardano-keri-native
  digest) is also the natural place to bind the on-chain AID to the KERI AID (§7,
  §1): record the KERI AID/prefix at inception, anchor KERI event SAIDs thereafter.

**What (B) does *not* do — the honest limits:**

- **It does not enforce the invariant.** Nothing on-chain compels the controller to
  anchor *every* event, or to anchor the *latest* one. The chain stores what it is
  given; a controller who stops anchoring simply freezes the on-chain view while the
  KEL advances. (B) gives *detectable* staleness, not *prevented* staleness.
- **It does nothing for the MPFS-only relying party.** RP-MPFS never replays the
  KEL; it reads the snapshot. A KEL-root commitment in the datum is, to RP-MPFS,
  opaque bytes it does not check. So (B) improves the auditor's world (§1's
  cross-checker) and the bridge's anti-duplicity, but does not raise RP-MPFS's
  security ceiling (§2) at all. RP-MPFS is still capped by on-chain *freshness*.
- **It cannot verify the KEL.** The chain still can't run Blake3 or parse CESR, so
  "anchor the KEL root" means "store a digest the controller supplied," verified
  off-chain. The verification is real but it is the *verifier's*, not the *script's*.

> **Verdict:** ship (B) — it is the precondition for §1 being even *statable* and
> for §7's AID binding — but do not oversell it. (B) converts an untestable trust
> assumption into a *testable* one for parties who replay. It closes the
> *detectability* half of the synchronization gap and leaves the *enforcement*
> (liveness: "did they anchor the latest event?") to watchers and incentives, where
> it irreducibly lives.

---

## 7. Practical KERI adoption (vLEI / GLEIF)

**Do real KERI networks use the AID format, key derivation, and event encoding
cardano-keri assumes? No, on every axis.** Taking GLEIF's vLEI ecosystem
(keripy/KERIA witnesses, ACDC credentials) as the reference:

| Property | Real KERI / vLEI | cardano-keri assumes | Breaks? |
|---|---|---|---|
| Digest for SAID/AID | **Blake3-256** default (CESR code `E`) | Blake2b-256 | **Hard** — PlutusV3 has no Blake3; the AID is unrecomputable on-chain |
| Identifier value | SAID over the **full `icp` event** | `blake2b_256(cbor({cur_key, next_digest}))` | **Hard** — different function, different bytes |
| Event encoding | **CESR/JSON** (`KERI10JSON…`), `v`-string framed | 2-field canonical CBOR | **Hard** — not parseable on-chain, different preimage |
| Current keys | **list `k` + threshold `kt`** (weighted) | single `cur_digest` | **Hard** — can't represent (§5) |
| Pre-rotation | **list `n` + threshold `nt`** | single `next_digest` | **Hard** — can't represent (§5) |
| History | hash-chained by **`p`** (prior-event digest) + `ixn` events | `seq` int, no prior-event link, no `ixn` | **Hard** — no KEL identity (§6) |
| Delegation | **`di` + cooperative anchoring** (vLEI core) | none | **Hard** — (§4) |
| Witnessing | **`b`/`bt` toad, receipts** | none / ledger anchor | **Soft** — different primitive (§3) |
| Signatures | Ed25519 (also secp256k1) | Ed25519 | **OK** — the one clean match |

**What breaks if a vLEI controller tries to anchor their AID here:**

1. **The AID won't match.** Their real AID is a Blake3-256 SAID over a JSON `icp`
   event. cardano-keri would compute a *different* 32-byte value from a 2-field CBOR
   record. The on-chain inception self-cert check (`AID == blake2b_256(cbor(…))`)
   *cannot be made to equal* the vLEI AID. PlutusV3 has no Blake3 builtin, so the
   script cannot even recompute the real SAID to check it. The controller is forced
   to register a **new, unrelated identifier**.
2. **The key-state won't fit.** A vLEI GEDA/QVI is multisig and delegated; the
   single-`cur_digest`/single-`next_digest` slot cannot hold a `2-of-3` set or a
   delegator.
3. **The history won't anchor.** vLEI relies on the full KEL (with `ixn` anchors for
   credential issuance/revocation seals). cardano-keri has no event-digest anchor and
   no interaction event, so credential-anchoring seals (the thing vLEI actually uses
   the KEL for) have nowhere to go.
4. **Witnessing semantics don't carry over.** vLEI events are only accountable when
   fully witnessed (toad). The on-chain anchor is not a receipt and carries no toad
   semantics; a vLEI verifier will not accept a Cardano anchor as witnessing.

**The only coherent integration** is therefore *not* "anchor the vLEI AID" but
"register a **distinct** cardano-keri AID and publish an **off-chain attestation**
(naturally an ACDC issued by the vLEI AID) binding `cardano_aid ↔ vLEI_aid`." That
attestation, verified off-chain, is what lets a cross-checking RP say "these two
identifiers are the same controller." Consequences:

- The binding's trust is **entirely off-chain** (the ACDC and its KEL anchoring),
  so RP-MPFS — who reads only the chain — never sees it. This is §1/§2 again: the
  data-plane is governed by the cardano-keri key-state, and the vLEI authority only
  reaches it through the controller's discipline in keeping the two in step.
- If you instead want the *on-chain* side to reference the vLEI AID, store the vLEI
  prefix in the inception datum and anchor vLEI event SAIDs (§6) — but the chain
  still can't *verify* them (no Blake3), so it's a controller-asserted link, not a
  script-checked one.

> **Verdict:** cardano-keri is **KERI-*inspired*, not KERI-*interoperable***, and the
> docs say so. For real vLEI adoption the honest story is: (a) it cannot host the
> real AID; (b) integration is via a separate AID + an off-chain (ACDC) binding;
> (c) closing the gap to true interop would require Blake3 on-chain (a Plutus
> builtin that doesn't exist), CESR/JSON-shaped events, multi-key thresholds (§5),
> delegation (§4), and event-digest anchoring (§6). Items (§4)(§5)(§6) are
> tractable; **Blake3-on-chain is the one true blocker** for verifying genuine KERI
> SAIDs, and absent it the AID binding is always a controller assertion, never a
> script-enforced equality.

---

## Prioritized gaps & recommendations

Ordered by **blast radius on the MPFS data-plane**, which is the system's reason to
exist. "Bridge-honest" means: stop describing this as a KERI anchor and describe it
as what it is.

### P0 — Decide what the system *is*, and bind the identifiers accordingly
1. **State the architecture honestly (S1, S2, S7).** Either (a) "a self-contained
   pre-rotation registry, KERI-*inspired*" — then drop the bridge framing entirely
   and the synchronization invariant is a non-goal; or (b) "a KERI anchor" — then
   you owe an *enforced or at least falsifiable* binding between the on-chain AID
   and the KERI AID. You cannot claim (b)'s security from (a)'s mechanism. The docs
   currently lean (a) in `trust-model.md` but the brief/system pitch assumes (b).
2. **If (b): bind the on-chain AID to the KERI AID (S1, S7).** Record the KERI
   prefix at inception and anchor KERI event SAIDs (P1·#5). Accept that on-chain it
   is a *controller assertion* (no Blake3), made *falsifiable* by anchoring +
   off-chain replay.

### P1 — Stop the data-plane from honouring stale/revoked authority
3. **Real revocation that gates value-writes (S3, S9, prior V5).** Add
   `revoked : Bool` to `KeyState`; a revoke op authorized by `cur_key`; and require
   **every cage script to check it** before authorizing. Tombstone ≠ revocation.
   This is the single highest-value change for §2 and the one that lets KERI-world
   revocation actually reach MPFS leaves.
4. **Make the on-chain rotation the authoritative data-plane control point, then
   harden it (S3, prior V3).** Require the identity UTxO be spendable *only* by a
   valid reveal-key rotation (so a stolen `cur_key` can't even grief it), and
   specify a settlement depth at which a key-state is final for value-write
   purposes. The data-plane inherits on-chain liveness; fund that fact.

### P2 — KERI-parity features the org use case requires
5. **KEL-event anchoring (S6, §6).** Add an interaction/anchor operation that records
   `{aid, seq, event_said}`. Precondition for falsifiable sync (§1), for the AID
   binding (P0·#2), and shared infrastructure with delegation.
6. **Delegation (S4, §4).** `delegator : Option<AID>` + cooperative anchoring built
   on #5. Without it there is no hierarchical org control and "DAO owns leaves" is
   just a shared key.
7. **Threshold multi-sig (S5, §5).** `cur_keys`/`cur_threshold`,
   `next_keys`/`next_threshold` (weighted), authorized via Option B's native
   `atLeast`. Bind thresholds into `rot_msg` to block downgrade. Cheapest parity win.

### P3 — Position the Cardano-as-witness story correctly
8. **Don't claim drop-in witness; claim checkpointing super-witness (S8, S10).**
   Ship the ledger-backed witness *service* (real CESR receipts after N
   confirmations) for deployability; reserve the custom ledger-receipt type as the
   faithful-but-future path. Document the latency (~20 s + confirmations) and the
   one-op-per-block bottleneck; recommend receipting establishment/checkpoint events
   only, paired with fast conventional witnesses for liveness.

### Cross-cutting (carried from the prior round, still binding here)
9. The signer-model decision (Option B), canonical CBOR, domain separation
   (including **MPF node** separation), the verified one-shot identity NFT + inline
   datum, and MPF-proof anchoring to the consumed root are all *upstream* of every
   system-level claim above. None of P0–P3 is sound if the anchor itself can be
   forged or its snapshot mis-encoded. They remain the foundation; this analysis
   builds the bridge on top of them.

---

### One-paragraph bottom line

The documented system is a sound, self-contained, single-key pre-rotation registry
with a clean on-chain root of trust — and it is **not the KERI bridge the brief
describes**. The on-chain AID is a different value from a real KERI AID; nothing
on-chain can see, verify, or stay synchronized with an off-chain KEL; and the MPFS
data-plane — the whole point — is therefore secured by the *freshness of the
on-chain snapshot*, not by KERI's witnessed, revocable, threshold, delegated
authority. The fixes that matter most are not cryptographic refinements but
**architectural honesty plus three concrete additions**: data-plane revocation so
KERI revocation can reach the leaves, KEL-event anchoring so divergence becomes
detectable, and delegation + threshold so organizations (the actual customers) can
own leaves at all. Cardano's genuine, under-claimed strength in this composition is
not "being a witness" but providing **global single-history ordering** that a
witness pool only approximates — sell that, and stop selling AID-format interop the
primitives cannot deliver.
