# DESIGN NOTE 001 — record/cursor data model and projection fidelity

**Source:** operator design session with the (parked) M1.2 milestone owner, 2026-08-19.
**Status: CAPTURED EVIDENCE, NOT A RULING.** Nothing here is decided. It is written by a desk with
no product authority, for the successor owner `%6656` and the project owner `%6429` to accept,
amend or discard. Where the session reached a conclusion it is marked **[settled in discussion]**;
where it did not, **[OPEN]**.

---

## 1. Naming

`checkpoint` implies one current state. The new object deliberately holds **many competing branches
at once**, so the name should not suggest a single tip. `record` is provisional. **[OPEN]**

## 2. What the Merkle tree actually holds

The root commits to an **authenticated key→value map**, one entry per event.

**Key = location + SAID.** [settled in discussion]

- `location` = position in the identity's history: sequence number plus prior-event linkage.
- `SAID` = the event's own content hash.

Why both: keying by location alone loses competing events at the same sequence (destroying the
evidence of equivocation); keying by SAID alone loses ordering. Together they let two validly-signed
events at seq N coexist, addressable and non-overwriting. **That is what makes the record
append-only *and* multi-branch, and it is why duplicity is a shape in the data rather than a verdict
someone issues.**

**There is no version number, and there must not be one.** A counter would have to be *assigned*,
and assignment is the chain originating identity state. The SAID is self-derived from content and
needs no authority. [settled in discussion]

**Value = the validator-computed post-event key-state snapshot.** It must carry at minimum:
current keys; the **next-key digests**; the witness set and thresholds.

Without the next-key digests you cannot check whether a claimed successor was authorized. Without
the witness set you cannot grade receipts or reason about attestation. **[OPEN: exact schema.]**

### Gap against the current skeleton — material

The S0 skeleton (`m12/record.ak`, self-described as "not production schemas") does:

```aiken
mpf.insert(trie, proof.key, parsed.said, proof.proof)
```

- the value is **only the SAID**, so the cursor is **not computable** from the tree without
  re-reading every event's bytes off-chain;
- `location` is declared in `HistoricalProof` and **never used**;
- `prior_snapshot_digest` is declared and never used;
- `occupancy_root` is a running hash `blake2b_256(old ++ said)`, not an occupancy map;
- **the key comes from the redeemer**, i.e. the submitter chooses where its event lands.

That last point is the #291 defect one level up: not *which bytes do I read* but *which slot do I
occupy*. Under bytes-only admission the key must be **derived from the event bytes** — location from
the parsed sequence and prior digest, SAID from content — with the MPF proof used only to prove
absence at that derived key. **[OPEN, and S2 must decide it explicitly.]**

## 3. Security model, as worked through

- **Pre-rotation blocks forward theft.** An attacker holding rotated-out keys cannot extend past the
  rotation; the `n` commitment names the successor keys.
- **Revealing next keys reveals PUBLIC keys.** It permits verification, not production — rotation
  requires signing with the private halves. An attacker who learns revealed keys still cannot rotate.
- **The fork window is the rotation event itself**, where old current keys are legitimately
  authorized. Cryptography cannot separate the two claims; that is why KERI has witnesses.
- **Rotation supersedes interaction at the same sequence**, because a rotation proves possession of
  pre-committed keys — strictly stronger evidence than signing with current keys. Descendants of the
  superseded event die with it. Cursor: `forked-recovered`.
- **Interaction vs interaction is symmetric.** No rule separates them → `duplicity-detected`.
  Painful corollary: **the victim's honest event is what makes the fork visible.** Before it, the
  thief's branch is cryptographically indistinguishable from the controller's.

**Operator rule that falls out, worth putting in user docs:** *when in doubt, rotate — never
interact.* Rotation supersedes; interaction contests. A controller who always rotates can never
create the unresolvable case themselves. [settled in discussion]

### Self-duplicity as a kill switch

If the next keys are unavailable, rotation is closed and the only remaining instrument is a
**deliberate conflicting event** — poisoning the identity so careful consumers refuse it. It needs
only current keys, which is the material still held when pre-rotation has failed.

This is **not a new primitive**: KERI already concludes *duplicitous → untrusted*. What the chain
adds is a **censorship-resistant publication path**, since witnesses first-seen-suppress the
conflicting event and it may never reach a watcher. Same semantics, deliverable.

It is free because grading never gates and no on-chain flow is economic — nothing to bribe, nothing
at stake in pulling it.

**Tension to decide:** if the attacker's branch is fully-witnessed and the poison is `bare`, a
grade-weighting consumer may discount it. **The kill switch's strength is a function of the grade
policy consumers adopt.** **[OPEN]**

## 4. Terminality of duplicity — reframed

Do not model it as one flag. Report **two facts**:

- *has this identity ever been duplicitous* — permanent and unerasable, since the record is
  append-only with no tombstones;
- *current tip state* — possibly `forked-recovered` after a later legitimate rotation.

`accepted_states` then lets each consumer choose. A high-assurance consumer refuses ever-duplicitous;
a pragmatic one accepts an identity that has since demonstrated pre-rotation control. **[OPEN, but
the reframe removes the false binary.]**

**Hard requirement either way:** the cursor must be derived over the **whole record**, not the tip.
A tip-derived cursor lets an attacker out-run a poison event and forces endless re-poisoning.
[settled in discussion]

## 5. Succession — linkage, never authority

Victim and thief hold **identical cryptographic material**, so any signature-based successor claim is
producible by both. Signing with the *next* keys would settle it, and those are exactly what is
missing.

The chain can therefore prove: a `predecessor_id` pointer; the registration slot (when the claim was
made); the predecessor's **observed state at stamping time** (presence proof); and a **juvenility
window** in which a contest can surface. It cannot prove heirship.

Heirship is decided **out of band** — for vLEI, the QVI re-issues to the legal entity — and the chain
projects that decision rather than originating it. `close` leaving *memory without verdict* is the
correct shape.

**[OPEN]** Does a successor stamp require the predecessor to be in `closed` state? If not, the thief
stamps too and contested succession is normal. If so, poison-then-close becomes a prerequisite of
succession — a much stronger sequencing rule.

## 6. Projection fidelity — the central risk

The invariant is a **fold with fidelity**, in two parts:

1. **Determinism** — the cursor is a pure function of the evidence set; same events in, same state
   out, independent of arrival order or who replays it.
2. **Fidelity** — for any evidence set `E`, `cursor(E)` equals what a correct KERI watcher would
   conclude from that same `E`.

### The divergence, exactly

- A **KEL is first-seen-filtered**: witnesses accept the first event at a sequence and reject
  conflicts, so a served KEL is one linear branch and duplicity is not in it.
- **Our record is unfiltered**: it holds every validly-signed claim.

Our record is therefore a **superset** of the KEL.

### The resolving move [settled in discussion]

**The record is not a KEL. It is a watcher's evidence set** — an existing KERI role, since duplicity
detection already requires collecting across witness sets. We make the watcher's evidence public,
permanent and cheap. That keeps us inside the projection law instead of competing with it.

### First-seen cannot be replicated, and must not be faked

First-seen is a **witness-local observation**. It is not in the events, not in any proof, and not in
our tree. We record that two events are children of the same parent at the same location; we record
no arrival relation between them.

The chain does have an ordering — settlement slot — which is mechanically *better* evidence
(globally ordered, publicly verifiable, non-repudiable). **But it is a different oracle.** Resolving
by slot would make the chain the authority and would diverge from KERI whenever the attacker reaches
witnesses first and the victim reaches the chain first.

**Therefore scope the invariant** [settled in discussion]:

- **content-derivable rules** — superseding, next-key commitment validity, prior-digest chaining,
  thresholds — must match `keripy` **exactly**;
- **observation-dependent rules** — first-seen between otherwise-equal events — the cursor
  **abstains**.

`duplicity-detected` thereby acquires a precise meaning: *"KERI would need witness-local observation
to resolve this, and we will not fabricate it."* A declared limit of the projection, not a failure.

**Store the settlement slot in the leaf as evidence, never as verdict.** Consumers may weigh it; the
chain must never use it to pick. Recording a fact and ruling on it are different acts.

**Receipts are the closest honest proxy.** A witness receipting *both* branches is itself detectably
duplicitous, so receipt distribution across the designated witness set is real evidence about which
branch witnesses accepted — carried as strength-of-evidence via `grade`, which informs and never
gates.

## 7. The check this implies — concrete, and the highest-value item here

Build a **cursor-vs-`keripy` parity oracle**, and give it **two** obligations:

1. agreement with `keripy` on content-derivable rules;
2. **abstention** wherever `keripy` requires first-seen.

Obligation 2 is the one that will actually catch us. A cursor that quietly resolved by settlement
slot would pass a naive parity test — it would agree everywhere *except* the contested cases, which
is exactly where the test must look. So the abstention must be its own assertion, with a
**resolve-by-slot mutant proven to make it fail**.

This is the same shape as the cross-decoder parity that caught the real `Err(_) -> []` divergence in
#291, lifted from *decoding agreement* to *resolution agreement*. Without it, "we project KERI" is an
unfalsifiable claim.

## 8. Where this lands

**Affected backlog rows** (payload submission 2 is authored but unapplied; Surface C inactive):

- **#163** duplicity detection — the abstention semantics, the self-poison path, the grade-policy
  tension, and the AUTHORIZING-before / REFUSED-after demonstration;
- **#171** indexer — the store is a **watcher evidence set**, not a KEL; this changes what it means
  to serve "current state";
- **#274** projection law — §6 is a direct extension of *"Cardano projects the KEL; the chain never
  originates identity state"* into resolution semantics.

**Affected S2 scope:** key derivation (§2), leaf schema sufficiency (§2), whole-record cursor
derivation (§4), and the parity-and-abstention oracle (§7).

**Candidate registry contracts** for the milestone owner to accept or reject:

- *cursor fidelity* — `cursor(E)` matches `keripy` on derivable rules; **enforced: NONE** until the
  oracle in §7 exists;
- *first-seen non-replication* — the cursor never resolves by settlement slot; **enforced: NONE**,
  and it needs the resolve-by-slot mutant to be enforceable at all;
- *leaf sufficiency* — the snapshot must make the cursor computable without off-chain re-reads;
  **enforced: NONE**, and today's skeleton violates it.
