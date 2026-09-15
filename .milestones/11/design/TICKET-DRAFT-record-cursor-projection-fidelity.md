# TICKET DRAFT — ready to file, not filed

**Proposed title:** `docs+spec: land the projection-fidelity design record, and the four requirements it creates`
**Proposed milestone:** 11 (M1.2)
**Authored by:** parked incumbent M1.2 owner `%6695`, at operator request, 2026-08-19.
**Status: NOT FILED.** Issue creation is an authenticated GitHub mutation and no grant covers it.

---

## Why this exists

An hour of design discussion with the operator produced conclusions that change what S2 has to
build. Right now they live in `/tmp`, which dies with the host. This ticket lands them in the
repository and turns the four that are actionable into stated requirements.

The short version of what came out of it: **the thing we are building is a Cardano-validated KERI
watcher.** Other KERI watchers are *reported* — you trust that the service computed its conclusion
honestly. This one is *validated*: no state transition exists unless the ledger enforced the rule
that produced it.

That framing is not decoration. It decides what the system may and may not conclude, and three of
the four requirements below fall directly out of it.

## What to land

The design record at `design/DESIGN-NOTE-001-record-cursor-projection-fidelity.md`
(sha256 `80feb30fc26b6939e907eed44b38937ebfb7058bdfc7ae5e85a959ce32c15ac2`), as a repository
document. Every claim in it is tagged **[settled in discussion]** or **[OPEN]**; nothing in it is a
ruling, and the OPEN items must stay open when it lands.

## The four requirements it creates

**1. The Merkle-tree key must be derived from the event bytes, not supplied by the submitter.**
Today's skeleton does `mpf.insert(trie, proof.key, ...)` where `proof.key` comes from the redeemer —
so the submitter chooses which slot its event occupies. That is issue #291's defect one level up:
not *which bytes do I read* but *which slot do I occupy*. Under bytes-only admission, location must
be computed from the parsed sequence and prior digest, and the SAID from content, with the proof
used only to prove absence at that derived key.

**2. The leaf must carry a key-state snapshot, not just the SAID.**
It needs current keys, the **next-key digests**, the witness set and thresholds. Without the
next-key digests you cannot check whether a claimed successor was authorised; without the witness
set you cannot grade receipts. As it stands the cursor is **not computable** from the tree at all
without re-reading every event off-chain.

**3. The cursor must be derived over the whole record, never the tip.**
A tip-derived cursor lets an attacker out-run a controller's defensive event indefinitely, forcing
endless re-poisoning. History-derived, the fact of a conflict is permanent and one defensive event
is enough.

**4. A cursor-vs-`keripy` parity oracle with TWO obligations.**
This is the highest-value item and the reason the others are safe to state.

- agreement with `keripy` on every rule derivable from event content;
- **proven abstention** wherever `keripy` resolves by *first-seen* — which is a witness-local
  observation, not present in our data and not to be fabricated.

The second obligation is the one that will catch us. A cursor that quietly resolved conflicts by
Cardano settlement slot would pass a naive parity test, because it would agree everywhere *except*
the contested cases — exactly where the test must look. So abstention must be its own assertion,
with a **resolve-by-slot mutant demonstrated to make it fail**.

## Technical contract

- Admission stays **bytes-only**. The validator must not consult derived state to admit an append;
  pruning a superseded branch at admission would make the chain an adjudicator and is forbidden.
- The record is a **watcher evidence set**, not a KEL. A KEL is first-seen-filtered and holds one
  branch; the record holds every validly-signed claim, keyed by `location + SAID`. Both entries at a
  contested sequence survive; nothing is overwritten and there are no tombstones.
- **No version number** may be introduced to distinguish competing events at one sequence. A counter
  would have to be assigned, and assignment is the chain originating identity state. The SAID is
  self-derived and needs no authority.
- Resolution rules split in two, and the split is the compliance boundary:
  - *content-derivable* — superseding, next-key commitment validity, prior-digest chaining,
    thresholds — must match `keripy` exactly;
  - *observation-dependent* — first-seen between otherwise-equal events — the cursor **abstains**,
    and `duplicity-detected` means precisely *"unresolvable without witness-local evidence we will
    not fabricate."*
- The Cardano settlement slot **may be stored as evidence** and **must never be used to resolve**.
  Recording a fact and ruling on it are different acts.
- Duplicity is reported as **two facts** — *ever-duplicitous* (permanent) and *current tip state*
  (possibly `forked-recovered`) — so consumer policy chooses, rather than the chain deciding
  terminality for everyone.
- One hypothesis to test rather than implement: *deepest demonstrated key generation wins* is
  stronger than the textbook *rotation supersedes interaction at the same sequence*. Feed the oracle
  cases where they could diverge — conflicts at different sequences, multiple rotations, a rotation
  appearing several sequences after the fork — and require agreement or expose the gap.

## Out of scope

No implementation. This lands a document and states requirements. Building any of them is S2 work
under its own authorisation, and the OPEN questions in the design record stay open.

## Related

- **#291** — requirement 1 is the same defect class one level up.
- **#163** — duplicity semantics, the self-poison path, the grade-policy tension.
- **#171** — the store is a watcher evidence set, not a KEL; this changes what "current state" means.
- **#274** — the technical contract above extends *"Cardano projects the KEL; the chain never
  originates identity state"* into resolution semantics.
