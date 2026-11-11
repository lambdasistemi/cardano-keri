# Where the design stands — record, cursor, and what we are actually selling

Written 2026-08-28, against DESIGN NOTE 001 (merged), DESIGN NOTE 002 (uncommitted), the four
accepted requirements in draft PR #306, and today's session decisions that are not yet in any file.
Where sources conflict, the conflict is named rather than resolved.

The product, stated once so the rest can be measured against it:

> a verdict you needn't trust, over evidence you can prove is all of it.

"We protect your identity" is false and was struck today. KERI protects the identity; pre-rotation
is the instrument and the controller is the defence. What this system adds is two things. To a
relying party: a verdict computed by the ledger under rules anyone can re-run, consumable inside
another validator with no oracle in the path. To a controller: *discovery* — one closed set they
can check completely, against KERI monitoring which is a search over an open set of witness pools
that can never be proven exhaustive.

The corollary is sharp and it is the spine of Part 3. Strip out completeness and the second clause
is false, which does not leave a missing feature — it leaves a *wrong verdict*.

---

## Part 1 — four stories

### Ingrid rotates into a fork, and the desk never notices (rung 2, working)

Ingrid Sørensen runs identity operations at Nordvest Fondsforvaltning, a Norwegian fund holding a
QVI-issued LE vLEI. The desk trades through an ECR role AID whose current signing key lives on an
order-signing service. At 02:40 that host is compromised. The thief has the current key and nothing
else: the next-key private half is on an HSM in Ingrid's custody, and only its digest is public.

At 03:10 the thief appends an `ixn` at sequence 12 of the role AID, anchoring an authorization for
an order the desk never placed. The append is permissionless and valid. Under R300-1 the MPF key is
derived from the event bytes, not chosen by the submitter, so the leaf lands at exactly
`(location(12, prior), SAID_thief)` and nowhere else.

At 04:00 Ingrid's watcher — a cron job reading the record — reports a leaf at sequence 12 she did
not author. She does not interact. She rotates. The HSM signs a `rot` at sequence 12 revealing the
pre-committed next public key and committing a fresh one. That event appends beside the thief's:
keyed by `location ‖ SAID`, the two coexist, non-overwriting (DN-001 §2).

The cursor now resolves this by content alone. Rotation supersedes interaction at the same sequence
because possession of the pre-committed next keys is strictly stronger evidence than a signature
with the current keys (DN-001 §3). No first-seen observation is consulted and none is needed: this
is the same answer `keripy` gives, from the same bytes, in any arrival order. `CursorV1` returns
`Resolved{tip = rot, Recovered}` with `ever_duplicitous` set (R300-3). Descendants of the thief's
`ixn` die with it.

Four hours later the lending protocol's order validator spends a Nordvest order. It reads the
cursor as a reference input, checks the detached witness set against the current weighted keys the
rotation installed, and finds the thief's outstanding order signed under keys that are no longer
authority. It fails. No oracle was consulted, no batcher was trusted, and nobody had to notify the
protocol that anything had happened. This is the case the design actually serves.

One gap bites even here. `ever_duplicitous` is permanent and, as R300-3 accepts it today, untyped.
The lending desk's policy engine sees a hard flag on an identity that in fact demonstrated exemplary
key hygiene in public. DN-002 §4b argues this should be typed by rung — *contested and resolved*
versus *unresolvably duplicitous* — but §4b is not in the accepted requirement. So until someone
lands the typing, every relying party has to write the forgiveness rule themselves, and most will
write it wrong or not at all.

### Tomás gets an abstention and freezes the register (rung 3, working as designed, and it hurts)

Tomás Ferreira is the transfer agent for a private placement issued as a register-as-cage security.
Transfers are gated on the holder AID's cursor.

A holder's current key leaks. The thief publishes an `ixn` at sequence 40 anchoring a transfer
authorization. The holder's operations team, not having read the operator rule, responds with their
own `ixn` at sequence 40 — a competing anchor, signed with the same current keys they still hold.

Two interactions at one location. No content rule separates them; both signatures are valid, both
chains to the same prior, both are producible by either party. The cursor returns
`Abstained(FirstSeenUnavailable, 40, [said_a, said_b])` with the candidate SAIDs canonically sorted
(R300-3). Tomás's transfer validator has no `accepted_states` entry for `Abstained`, so it refuses
both transfers and the position is stuck until the issuer intervenes out of band.

Be clear about the comparison, because this is not a win. Plain KERI *resolves* this case. The
holder's witnesses receipted one branch first and first-seen-suppressed the other; a verifier
querying the witness pool gets one linear KEL and transfers proceed. Our chain declines, on purpose,
because first-seen is a witness-local observation that is not in the events, not in any proof, and
not in our tree, and resolving by settlement slot would make the chain a different oracle (DN-001
§6). We trade liveness for not lying.

KERI's resolution here is *arbitrary with respect to honesty*: it canonizes whoever reached the pool
first, which in a current-key theft is usually the thief, since the victim does not yet know. But
the holder's business does not care about that epistemology at 11:15 on a settlement day. It cares
that the register is frozen.

The operator rule that falls out is worth putting in front of every controller: *when in doubt,
rotate, never interact.* A controller who always rotates can never manufacture this case themselves.

### Marek serves a branch, and the validator believes him (the occupancy gap)

Marek Dudek operates an indexer. Ingrid's watcher and the lending protocol's off-chain assembler
both read from him.

Take the first story again and change one thing: Marek is dishonest, or merely lagging. When the
lending protocol assembles the transaction that reads Nordvest's cursor, it must be *handed* the
leaves the on-chain derivation will fold over, with MPF proofs. Marek hands over the thief's `ixn`
and omits Ingrid's `rot` — or in the second story, hands over one `ixn` and omits its sibling. Every
proof he supplies is individually valid against the root, and the validator folds them into a
cursor.

There is no on-chain instrument that catches this. The Aiken MPF library hashes its keys —
`including` and `excluding` both call `blake2b_256(key)` — so `location ‖ SAID` entries have no trie
locality, sub-trie enumeration is impossible, and there is no way to walk "everything under location
12". MPF commits no cardinality either, so no root can bound *how many*. A consumer can ask "is key
K present?" and that is all; to ask it, they must already know the SAID, which is exactly what an
omitting server does not tell them.

`occupancy_root` was supposed to be this instrument. It is not one. It is a running hash
`blake2b_256(old ‖ said)` (DN-001 line 53), and it is written and never read: the only consumer in
the entire repository is a 32-byte length check at `onchain/validators/s0_lineage.ak:26`.

So the second story's outcome silently becomes the first's, and the first's becomes clean. The
validator returns `Resolved(Clean)` on an identity that is in fact abstaining. This is not a missing
feature; it is a *wrong verdict*, produced with full cryptographic ceremony.

Note the shape. #291 was "which bytes does the validator read". R300-1 is "which slot does the event
occupy". This is the same defect at a third altitude: **which branch is the validator shown**. It
appears in none of R300-1..R300-4 and in none of the four mandates.

### Kestrel's fork sits for eleven hours (S-1 and S-4)

Kestrel Pool is a vLEI-identified SPO. An institutional delegator's stake credential script only
publishes delegation certificates to pools whose LE cursor is clean.

At 21:00 a stranger — running a bot for the standing bounty — appends a conflicting event on
Kestrel's operating AID. Good: the record is now complete and public, which is the whole service.
Kestrel's own watcher, a container on the same box as the pool relay, died at 19:00 with an OOM and
nobody was paged. The fork sits, visible to anyone who looks, until 08:00 the next morning.

Two structural limits, neither fixable. Publication is not notification (S-4): the chain made the
fork public and could not make Kestrel know; something off-chain must watch, and when it stops the
guarantee stops with it — the record stayed complete and *nobody read it*. And promptness cannot be
paid for (S-1): the bot that published at 21:00 was paid exactly what a bot publishing at 08:00
would have been paid, because there is no reference clock for "when could you have published this",
and inventing one would be inventing first-seen.

The delegator was fine: its validator read the cursor at 21:05 and declined. The relying-party
guarantee held throughout. It is the *controller-facing alarm* — the thing DN-002 §1 says the escrow
buys — that has no timeliness dimension at all.

---

## Part 2 — where the design stands

**Settled.** The chain holds an evidence set, not a KEL: every validly-signed event, all branches,
append-only, deliberately unfiltered so duplicity is a shape in the data and not a verdict anyone
issues (DN-001 §6, DN-002 §0.1). The chain never rules: it matches `keripy` exactly on
content-derivable rules and abstains wherever KERI would need first-seen (DN-001 §6, DN-002 §0.2).
The settlement slot is stored as evidence and is never a tie-breaker. The cursor is derived over the
whole record, never the tip. Keys are `location ‖ SAID` so rivals coexist. "When in doubt, rotate,
never interact."

**Accepted but unmerged.** R300-1 (event-derived MPF key), R300-2 (`EventLeafV1` and
`KeyStateSnapshotV1`), R300-3 (whole-record `CursorV1` with the two facts), R300-4 (pinned `keripy`
parity with proven abstention and a resolve-by-slot mutant that must go RED). Audited, accepted,
sitting in draft PR #306. None is implemented; #300 authorizes no implementation. Each is an ordered
independently-gated future slice.

**Decided today, not yet written anywhere.** On-chain witness validation *for verdict purposes* is
out: the chain computes no `grade` and no on-chain outcome depends on witness receipts. Two reasons.
DN-002 §7 — the kill switch can be out-graded, because the victim's defensive event is bare *by
construction* (witnesses first-seen-suppress the second event at a sequence, which is their job)
while the thief's branch may be fully witnessed, so a grade-weighting consumer discounts exactly the
evidence trying to save the victim. DN-002 §3 — grade is controller-dependent, so an identity that
publishes to Cardano instead of running witnesses has a constant-zero grade and could never benefit.

Receipts are nonetheless still collected and verified, as a *separate append path*. Receipts trail
their events; the victim's poison event is bare by construction, so receipt verification must never
gate event admission. Verifying a receipt at its own append is legitimate — you reject the
*receipt*, not the event, which is not adjudication. The purpose is KEL completeness, so indexers
can become KEL servers: DN-002 §6's claim that witnesses lose their availability role is only true
if Cardano serves a complete, independently verifiable artifact. The formulation agreed:
**the chain records what witnesses said, verifies that they said it, and never counts it.**

**Known broken, and not in scope anywhere.** The occupancy instrument, per the third story. Absent
from R300-1..R300-4 and from all four mandates.

**Still open.** DN-001 carries six substantive `[OPEN]` markers (lines 14, 39, 59, 95, 106, 127):
the object's name; the exact leaf schema; the derived-key decision, which A-019 §2 now binds for V1
but whose provenance beyond the A-019 minimum is decision debt; the grade-policy tension on the kill
switch; the consumer treatment of ever-duplicitous versus recovered; and whether a successor stamp
requires the predecessor to be `closed`. PR #306's spec header says "its 4 `[OPEN]` tags" — a
bookkeeping discrepancy, since the note has six. Nothing here settles any of them.

**DN-002's ledger.** Fixable: F-1 premium gated on `FullyWitnessed`, which by construction cannot
pay the append most worth paying for; F-2 the premium has no payee, which is the #271 exposure
returning and is absent from the S2 scope list — the highest-risk item in the note; F-3 paying the
second arrival rewards withholding, fixed by paying the pair rather than the second; F-4 leaf
insufficiency, which is simultaneously a correctness item and the indexer's entire economics; F-5
submitter-chosen slot, which R300-1 addresses. Structural: S-1 promptness unpayable; S-2 indexer
service unprovable; S-3 victim and thief indistinguishable; S-4 publication is not notification.

**Unresolved external tension.** A reviewer from the Cardano Foundation read two design gists on
2026-08-27. He likes the record/policies design as a better match for KERI verification, but holds
that on-chain adjudication "only really works if there is some form of first-seen and liveness which
can mirror KERI, so we can discriminate between dead attacks and duplicity properly." He also doubts
the "pen" construction — a deterministic daemon holding a KERI witness key whose receipting policy
is a pure function of chain state, making first-seen equal settlement order — on a dilemma: either
the pen keys can be stolen and used off-chain on KERI, or we enforce indexing Cardano and break
interop. Two things to note. The pen is not in the repository at all; it exists only in a personal
gist. And DN-002 §6 answers the same question in the *opposite* direction — witnesses evaporate —
without citing the pen or the reviewer. This is an open tension, not a settled matter.

### Contradictions in the current material

- **R300-2/R300-3 versus today's witness decision.** R300-2 normatively requires the
  validator-derived effective witness set with `bt` threshold and states "grade derives from
  verified receipt identities against the snapshot's witness set and threshold"; R300-3 puts
  `evidence_grade` in `CursorV1`. Today's decision says the chain computes no grade. Accepted
  requirement and today's ruling disagree; #306 needs an amendment or the ruling needs a carve-out.
- **R300-3 versus DN-002 §4b.** R300-3 accepts DN-001's untyped permanent `ever_duplicitous`.
  DN-002 §4b argues that flag conflates rung-2 supersession with rungs 3 and 4 and must be typed.
  The accepted requirement encodes the shape §4b rejects.
- **`docs/keri-primer.md` versus everything.** The primer's "Where Cardano fits" table still claims
  "Duplicity **prevention** (UTxO spent once, structurally impossible)" and "Cardano becomes an
  additional witness." Both are now false. The chain prevents nothing, records both branches, and is
  explicitly not a witness. This is user-facing and states exactly the claim Part 3 retracts.
- **DN-002 §5 S-1's "race" framing versus the rung correction.** S-1 says the victim's recovery
  window is a race. At rung 2 there is no race in the content sense: supersession resolves the same
  way regardless of arrival order. Promptness governs *exposure duration* — how long consumers act
  on the thief's branch before the rotation lands — not the outcome. S-1 remains true; its
  motivation needs restating.
- **`docs/design/trust-model.md` and `super-watcher.md`** were last touched 2026-07-28 and describe
  the superseded monolithic design. Background only.

---

## Part 3 — what is weaker than plain KERI

This is the section the design must not soften. Each item says whether it is fixable or structural,
and where structural, what the design must therefore stop claiming.

**Witnesses prevent; we only record.** In KERI a thief holding only current keys cannot get a fork
receipted: the witness has already receipted the sequence and refuses, so the fork is stillborn and
the controller's KEL never carries a mark. Our chain accepts both branches and prevents nothing. The
fork exists, permanently, in a public artifact. **Structural** — it is the direct cost of holding an
evidence set rather than a filtered log, and it cannot be removed without becoming a witness.
DN-002 §6 argues §4b's rung typing neutralizes the reputational half of this, and that argument is
sound *for a controller whose consumers read Cardano*. It does not touch the operational half: in
KERI the attack leaves no artifact to explain, and here it leaves one forever.
**Stop claiming:** "Cardano prevents duplicity" and "Cardano is an additional witness". Both are
still in `docs/keri-primer.md`.

**We abstain where KERI resolves.** Rung 3 is the second story. A KERI verifier gets a linear KEL
and proceeds; we return `Abstained` and the consumer stalls. **Structural** — first-seen is a
witness-local observation, is in no event and no proof, and resolving by settlement slot would be a
different oracle giving a different answer whenever the attacker reaches witnesses first and the
victim reaches the chain first. R300-4 makes the abstention a proven obligation with a
resolve-by-slot mutant, which is the right response: make the limit falsifiable rather than quiet.
**Stop claiming:** availability of a decision. What we offer at rung 3 is a *refusal to guess*,
which is a different product from an answer, and consumers must plan for it as a state their
business logic reaches.

**No promptness, no clock.** S-1. A finder who publishes a fork in sixty seconds is paid what a
finder who waits a week is paid, because there is no reference clock for "when could you have
published this" and building one means building first-seen. A KERI witness receipt is immediate and
free. **Structural.** **Stop claiming:** anything about detection *speed*. The claim is completeness
of the place to look, never latency to the look.

**Publication is not notification.** S-4. The chain makes a fork public; it cannot make the victim
know. Something off-chain must watch, and when it dies the guarantee dies with it, as Kestrel's
container did. It is also complete over the *record*, not over reality: a fork nobody appended is
invisible. **Structural**, and it is why the notification guarantee and the append bounty are one
mechanism rather than two — which in turn is why F-2 (the premium with no payee) is load-bearing
for the security goal and not merely an economics defect. **Stop claiming:** "the controller is
notified". The claim is "there is exactly one place a fork can be recorded, and it is cheap to read
completely".

**Victim and thief are indistinguishable.** S-3, DN-001 §5. Where both hold identical key material,
any signature-based claim is producible by both, and heirship is decided out of band with the chain
projecting that decision rather than originating it. Note this is *not* worse than KERI — KERI has
the same problem — but it is worse than what an on-chain registry naively suggests it can do, and
it bounds the succession design permanently. **Structural.** **Stop claiming:** that the chain can
adjudicate succession. `close` leaving memory without verdict is the correct shape.

**Latency and cost against a free instant receipt.** A KERI event is receipted in the round-trip to
a witness, at zero marginal cost. Our append waits for settlement and pays a fee, and the cursor a
relying party reads is at best one settlement behind reality. **Structural** for the ordering
component, and merely a parameter for the fee. **Stop claiming** parity with witness latency; the
honest positioning is that we are a *slower, complete* record, not a faster witness.

**Every guarantee is conditional on the consumer reading Cardano.** DN-002 §6's conclusion —
"there is no function witnesses perform that the chain does not" — carries the qualifier "for a
controller whose consumers read Cardano". Outside that population the chain does nothing at all: a
verifier querying only the witness pool sees the first-seen-filtered branch and never learns the
fork exists. **Structural**, and it is what the Cardano Foundation reviewer is pointing at with the
interop half of his pen dilemma. **Stop claiming:** any unqualified security property. Every one of
them is scoped to consumers who read the record.

**The record is an evidence set, so it cannot serve a KEL.** This is the item most likely to be
underestimated. A KERI verifier expects one branch, first-seen filtered. We hold all of them, and we
have deliberately refused the only mechanism that would let us pick. So an indexer built on the
record can serve *evidence* and it can serve a *cursor*, but it cannot serve a canonical KEL without
either replicating first-seen or fabricating it. **Structural.** This directly limits DN-002 §6:
witnesses lose their availability role only for consumers willing to take an evidence set plus a
cursor in place of a KEL, and standard KERI tooling is not that consumer today.

**And the one that is fixable, and is the most dangerous.** The occupancy gap. Right now the
submitter chooses which branch the validator is shown, and nothing on chain contradicts them. That
turns the second clause of the product statement — "over evidence you can prove is all of it" —
from true to false, and a false completeness clause does not degrade the verdict, it inverts it: the
consumer gets `Resolved(Clean)` where the truth is `Abstained`, with a valid proof attached.
**Fixable**, and until it is fixed the product statement must not be used, because on the current
skeleton it is a claim we cannot support. Nothing in R300-1..R300-4 fixes it.

---

## Part 4 — what is genuinely stronger

Three things survive scrutiny.

**One closed set instead of an open search.** KERI duplicity monitoring is a search over witness
pools that can never be proven exhaustive; you can always be told about one more pool. The record is
a lookup on one place. This is completeness, not cost (DN-002 §1), and it is the only durable
advantage — which is why the occupancy gap is not a detail.

**A verdict with no oracle in the path.** The cursor is computed by the ledger under rules anyone
can re-run, and consumed inside another validator as a reference input. Nordvest's lending desk did
not trust Marek, did not trust a batcher, and did not trust us. Under R300-4 the derivation is
pinned to a specific `keripy` commit and container digest with arrival-order permutation invariance
proven, so "we project KERI" is a falsifiable claim rather than an assertion.

**A censorship-resistant publication path for the kill switch.** When pre-rotation is gone, a
deliberate conflicting event is the only remaining instrument, and it needs only the current keys —
the material still held. KERI already concludes *duplicitous → untrusted*; what the chain adds is
that the poison event cannot be first-seen-suppressed into never reaching a watcher. Note the limit
in the same breath: with grade off the verdict path the poison can no longer be out-graded on chain,
but a consumer applying their own grade weighting off-chain can still discount it, and DN-001 §3's
`[OPEN]` on that tension stands.
