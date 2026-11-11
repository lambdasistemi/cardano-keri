# HANDOFF — design evidence from an operator session, for the sitting M1.2 owner

From: parked incumbent M1.2 owner `%6695`. To: sitting M1.2 milestone owner `%6656`.
2026-08-19.

**This is a handoff artifact, not an instruction.** I hold no product authority. You own what
happens to this, including discarding it. I am passing it because the operator asked me to, and
because it came out of a session I was in and you were not.

## The artifact

`/tmp/ms-keri-11/design/DESIGN-NOTE-001-record-cursor-projection-fidelity.md`
sha256 `80feb30fc26b6939e907eed44b38937ebfb7058bdfc7ae5e85a959ce32c15ac2`, 220 lines.

Every point is tagged **[settled in discussion]** or **[OPEN]**. Nothing in it is decided. It names
three candidate registry contracts for **you** to accept or reject — I did not register them.

## Why it may change the plan

Four things in it bear on work you are currently supervising:

1. **The S0 skeleton takes its MPF key from the redeemer.** The submitter chooses which slot its
   event occupies. That is #291's defect one level up — not *which bytes do I read* but *which slot
   do I occupy*. Under bytes-only admission the key must be **derived from the event bytes**. This
   is S2 scope and it is not currently written down as a requirement anywhere.

2. **The leaf stores only the SAID**, so the cursor is **not computable** from the tree without
   re-reading every event off-chain. The snapshot must carry next-key digests, witness set and
   thresholds. Also S2 scope, also unwritten.

3. **The cursor must be derived over the whole record, not the tip.** A tip-derived cursor lets an
   attacker out-run a controller's defensive event indefinitely. Hard requirement, cheap to state
   now, expensive to retrofit.

4. **The projection-fidelity problem, which is the substantive one.** Our record is a *superset* of
   a first-seen-filtered KEL, so it is a **watcher evidence set**, not a KEL. First-seen is
   witness-local and **not derivable from our data**. The chain's settlement slot is a *different*
   ordering oracle — resolving by it would make the chain a competing authority and break
   *"Cardano projects the KEL; the chain never originates identity state."* So the cursor must
   **abstain** where KERI needs first-seen, and `duplicity-detected` means exactly *"unresolvable
   without witness-local evidence we will not fabricate."*

## The one item I would put in front of you first

A **cursor-vs-`keripy` parity oracle with two obligations**: agreement on content-derivable rules,
**and proven abstention** where `keripy` requires first-seen — with a *resolve-by-slot mutant
demonstrated to make it fail*.

A naive parity test passes a cursor that quietly resolves by slot, because it agrees everywhere
except the contested cases, which is exactly where the test must look. Without that second
obligation, "we project KERI" is unfalsifiable — and this milestone has already paid for one
unfalsifiable claim, in the inherited G0 decoder evidence.

## Where it lands, so you need not re-derive the mapping

- Backlog rows **#163** (duplicity semantics, self-poison path, grade-policy tension), **#171**
  (the store is a watcher evidence set, not a KEL), **#274** (§6 extends the projection law into
  resolution semantics). All three sit behind the **inactive** Surface C payload — nothing can be
  edited until the project owner accepts an exact manifest.
- **S2 scope**: key derivation, leaf schema, whole-record cursor derivation, parity-and-abstention
  oracle.
- **Registry candidates**: *cursor fidelity*, *first-seen non-replication*, *leaf sufficiency* —
  each currently `enforced: NONE`, and the third is violated by today's skeleton.

I did not touch the ledger, the registry, the state page or any issue. Those are yours.
