# BRAINSTORM — 2026-08-28 design session

**Status: CAPTURED EVIDENCE, NOT A RULING.** A dump of the day's reasoning, kept
because the path matters more than the conclusions and three positions reversed
inside it. Successor to DESIGN NOTE 001 (merged) and DESIGN NOTE 002 (captured
2026-08-28). Conclusions reached in session are marked **[settled in
discussion]**; everything else is **[OPEN]**. Nothing here is decided.

Participants: the project owner and the M1.2 milestone desk. Three research
agents on the occupancy question; their findings are folded in where they bear.

---

## 1. Witness validation comes out — and then half of it goes back in

**Opening question:** can we say witness validations are out of the design?

Three things travel under that name and they were separated:

- **(a)** verifying receipt signatures on chain, which produces `grade`
- **(b)** storing the effective witness set and `bt` threshold in the leaf
- **(c)** `grade` as a cursor output field

**(b) stays.** The effective witness set is derived from the events themselves
(cuts then adds), so it is parsing already being done. It is also what makes the
witness-set-swap fork visible — the entire subject of the countermeasures
dossier. Dropping it would blind the design to that attack class to save
nothing. It later turned out to be load-bearing three separate ways: swap
detection, bounding receipt admission, and completeness proofs.
**[settled in discussion]**

**(a) and (c) come out, and the reason is semantic rather than cost.**
DN-002 §7: the kill switch can be **out-graded**. The victim's defensive event
is bare *by construction* — witnesses first-seen-suppress the second event at a
sequence, which is their job — while the thief's branch may be fully witnessed,
because the witness set is named in the accepted rotation, which may be the
thief's. A grade-weighting consumer therefore discounts exactly the evidence
trying to save the victim. Put beside §3 — grade is controller-dependent, so a
witness-free identity carries a constant-zero grade forever — the picture is an
expensive on-chain computation, advisory by ruling, unavailable to the
identities that most need the chain, and pointing the wrong way in the one
scenario the system exists for. §4b had already replaced its main consumer by
making the default policy rung-typed. **[settled in discussion]**

**Cost was deliberately not used as an argument.** The measured advance rows
bundle receipt-quorum verification with message reconstruction, controller
signature admission and AE1-AE10 binding, and all three cells carry ≥45% memory
headroom — but every row uses only *two* receipts, and there is no clean
measurement of receipt verification alone or of its scaling toward a real GLEIF
pool. The case rests on §7 and §3, not on a number nobody can show.

### The reversal

The desk argued receipts should be stored unverified, on the grounds that
verification implies a decision and both branches are bad: reject the event and
admission is no longer bytes-only; accept anyway and you paid for a verdict you
do not act on.

**There is a third branch. You reject the receipt, not the event.** That is not
adjudication — it is the same class as refusing a malformed event. The chain is
not ruling on which branch is honest; it is declining to store a signature that
is not a signature. **[settled in discussion]**

Once receipts are their own append path, the rest dissolves. Timing: the event
lands bare and immediately, receipts arrive whenever they arrive, the poison
path is unconditioned. Cost shape: one check per receipt at its own append,
amortised, rather than `toad` checks bundled into every advance — the opposite
of the profile feared. Griefing: verification bounds the set more tightly than a
membership test, since a forged signature from a genuinely designated witness is
also rejected.

### And the real reason to keep them

Not grading. **KEL completeness, so indexers can become KEL servers.**

DN-002 §6 claims witnesses lose their availability role because the KEL is
served by Cardano. That claim is load-bearing on receipt storage: without
receipts, Cardano serves events stripped of their attestations, which is not a
KEL any KERI tool accepts, so anyone needing verifiable history returns to the
witness pool and §6 collapses. Store them and §6 stands on something built
rather than assumed. **[settled in discussion]**

Formulation adopted: **the chain records what witnesses said, verifies that they
said it, and never counts it.** Verification for authenticity, not for verdict.

**Caveat that must be stated wherever this is published:** we cannot serve *a
KEL*. A KEL is first-seen-filtered and holds one branch; the record deliberately
holds every validly-signed claim. What an indexer serves is the evidence set —
byte-identical to a witness's KEL for an uncontested identity, which is nearly
all identities nearly all the time, and for a contested one it serves both
branches and the consumer applies policy. More honest than a KEL server, but it
must be said plainly rather than discovered by an integrator. **[settled in
discussion]**

**Left open:** who pays for receipt landing. DN-002 §6's second-order finding
bites hardest here — the controller's own witnesses receive every event first by
construction, so under a flat premium they harvest the routine stream and become
paid dependents of the controller, which is the relationship that makes
reporting that controller's fork unattractive. Receipt appends are the purest
form of that stream. The candidate lever (designated payee for empty slots, open
for occupied ones) appears to apply, but it was marked a trade, not an answer.
**[OPEN]**

---

## 2. Occupancy — the instrument three requirements already assume

**Trigger:** if consumers read the record through indexers, we must trust the
indexer not to omit. How do we cryptographically commit the collected receipts
so completeness is provable?

### What the research established

**The Aiken MPF hashes its keys.** Both `including` and `excluding` walk
`blake2b_256(key)`. So `location ‖ SAID` entries land at uniformly random,
unrelated trie positions, and the textbook answer — prove the sub-trie at prefix
L, since a Patricia sub-trie *is* exhaustively every key with that prefix — is
not merely unsupported here, it is meaningless.

**MPF commits no cardinality.** A node hash is `prefix ‖ merkle_root(children)`.
The off-chain `Branch.serialise()` carries a `size`; `computeHash` deliberately
excludes it. A root can never bound "how many".

**`occupancy_root` is written and never read.** The only consumer anywhere is a
32-byte length check at `onchain/validators/s0_lineage.ak:26`. No test asserts
its value; `grep` over `offchain/` returns nothing. `HistoricalProof.location`
is the same — declared, never read. Replacing both is unconstrained by any
consumer.

**Budget reality: size binds, execution does not.** `s0_append` is 8,471 B, 52.5%
of the 16,133 B reference ceiling, with roughly 4,436 B before it trips
REDESIGN. Co-residency `append + cursor + staging` is already 25,617 B =
158.78%, headroom **−9,484 B**. No m12 script has any measured execution number
at all. This argues for a commitment that is a handful of builtin applications
over a bespoke trie.

### The design that survives

Outer MPF keyed by **location only**; value is `count ‖ commitment` over that
location's entries. Completeness by reconstruction rather than by boundary or
absence proofs: one membership proof binds `location → (count, commitment)`, the
indexer hands over the entries, the consumer recomputes and compares. Order
independent at both levels. Uses only the currently pinned public API.

Bucket commitment is the open choice: **ECMH** (sum of `hash_to_group` in
BLS12-381 G1 — O(1) per insert, roughly 56–109M CPU, constant regardless of how
many rivals) or an **inner MPF** keyed by SAID. **[OPEN: which]**

**Rejected: a plain digest over the canonically sorted entry list.** Cheapest to
write; updating it on chain requires the whole list in the redeemer, so a
key-holding attacker appends rivals until every future transaction at that
location is unbuildable — a permanent per-location lock, arriving in precisely
the compromise scenario the system exists for. The two research agents disagreed
here and this one is right. **[settled in discussion]**

### The reframe that matters more than the mechanism

This was being called anti-censorship. It is sharper than that: it is
**submitter-selected evidence**, and it is the same defect a third time.

- #291 — the submitter chose *which bytes the validator read*.
- R300-1 / DN-001 — the submitter chose *which slot its event occupied*;
  DN-001's own words, "#291's defect one level up".
- occupancy — the submitter chooses *which branch the validator is shown*.

One shape at three altitudes: who decides what the validator looks at. The first
two are fixed by deriving from content; the third needs a structure that answers
a question about a set rather than a key. **[settled in discussion]**

### The consequence

**R300-3 may not be implementable as accepted.** Its mandate requires derivation
"over the COMPLETE authenticated event-and-attestation record — never the latest
leaf, never a submitter-selected branch". There is no mechanism today by which a
validator can demonstrate it derived over the complete record; it can only
verify the proofs it was handed. So R300-3 is a requirement whose enforcement has
no instrument, and the missing instrument is the fifth defect DN-001 listed and
#300 did not carry. The same dependency runs through DN-002 §4b's ungraded
whole-record derivation and through §1's product claim, "a lookup on a closed
one" — which is the pitch, and is untrue without it.

**[OPEN]** whether occupancy becomes the fifth requirement on #300 (cheap now,
the PR is draft and unmerged) or a separate ticket R300-3 declares a dependency
on. The desk leans to the first.

---

## 3. The rung correction

The desk told a motivating story in which the attacker published a **rotation**.
The project owner rejected it: a rotation requires the pre-rotated next keys, so
an attacker who can rotate holds the pre-rotation secret and the victim has
nothing left to fight with. That is rung 4, and nothing rescues it.

Restated correctly:

| rung | attacker holds | solvable? | what completeness buys |
|---|---|---|---|
| 2 — `rot` over `ixn` | current keys only | **yes, by content rule** | the alarm that triggers the rescue, and the proof the rescue happened |
| 3 — `ixn` vs `ixn` | current keys, symmetric | no — abstain | that the conflict is seen at all, so abstention is reachable |
| 4 — `rot` vs `rot` | the pre-rotation secret | no — identity gone | that everyone can be told, permanently |

**Rung 2 is the product.** The thief holds current keys only, cannot rotate, and
publishes an interaction. The victim still holds pre-rotation, rotates
defensively, and KERI's superseding rule resolves it by content — no first-seen,
no witness opinion, no abstention.

Completeness earns its place twice in that story. The victim must **find out**:
the rescue only happens if she learns the thief's `ixn` is at her next sequence,
and she cannot name its SAID because it derives from bytes she has never seen,
so the only query that finds it is "what is at this location". And the relying
party must **see the rescue**: the thief builds the transaction and picks the
proof, supplying a clean membership proof of his own interaction, while the
victim's superseding rotation sits in the same trie under the same root with no
way to demand it. The victim wins by the content rules and the design throws the
win away at the point of use.

**Rule adopted:** the case to argue from is rung 2. A story told at rung 4
describes a funeral, not a defence. **[settled in discussion]**

**[OPEN]** whether rung 2 — current-key theft with pre-rotation intact — is a
large enough case to carry the milestone. It is the case KERI itself is proudest
of handling; our claim is only that we make the rescue findable and showable.

---

## 4. What the product actually is

"We protect your identity" was said by the desk and struck. **KERI protects the
identity.** Pre-rotation is the instrument and the controller is the defence;
the rescue at rung 2 is entirely theirs.

What this system gives:

- **To a relying party, a verdict they need not trust anyone for.** Every other
  KERI watcher answers by *reporting* — you trust the service computed honestly
  over evidence it chose to look at. This one is computed by the ledger under
  rules anyone can re-run, and readable inside another validator with no oracle
  in the path.
- **To a controller, discovery.** Not protection. The controller already holds
  the cure; what they lack is knowing they are sick. A closed set checkable
  completely, against KERI monitoring which is a search over an open set of
  witness pools that can never be proven exhaustive.

One line: **a verdict you needn't trust, over evidence you can prove is all of
it.** **[settled in discussion]**

Corollary, and it is why occupancy is not a hardening extra: strip completeness
and the second clause is false, which makes the cursor **a wrong verdict rather
than a missing feature**. Second corollary: if a relying party will not read the
chain, we have given them nothing. Every guarantee is conditional on the
consumer looking at Cardano.

---

## 5. Unresolved from external review

A Cardano Foundation reviewer read two gists on 2026-08-27 and said the design
of the record and policies matches KERI verification better, but that on-chain
adjudication "only really works if there is some form of first-seen and liveness
which can mirror KERI, so we can discriminate between dead attacks and duplicity
properly". He doubts the **pen** — a deterministic daemon holding a KERI witness
key whose receipting policy is a pure function of chain state, making first-seen
equal settlement order by construction — on a dilemma: either the pen keys are
stolen and used off-chain on KERI, or Cardano is enforced as the index and
interop breaks.

Two things to record. The pen exists **only in a personal gist**, never in the
repository; it entered that draft at 2026-08-19T08:18:08Z, before issue #300 was
filed at 08:54 and before the record merged at 09:31, and survived every later
revision. And **DN-002 §6 answers the same question in the opposite direction —
witnesses evaporate — without citing it**, nine days later.

The dilemma lands on a limit the pen's own text concedes: "a pure off-chain KERI
verifier counts W's signatures without knowing the chain discipline". One
narrowing in the pen's favour: a stolen pen key does not let anyone advance a
KEL, since a receipt attests rather than authorises — the exposure is helping an
already-compromised controller's rival branch look witnessed to verifiers who do
not check the chain. **[OPEN — product ruling, not the desk's]**

---

## 6. Errors recorded against the desk today

- **The `[OPEN]` count is wrong and was propagated all day.** `grep -c
  '\[OPEN\]'` returns 4 because it matches only the bare token; the record
  carries six substantive open items plus a legend line, since lines 39, 59 and
  106 use `[OPEN: exact schema.]`, `[OPEN, and S2 must decide it explicitly.]`
  and `[OPEN, but …]`. A gate asserting "4 `[OPEN]` tags survive" would pass with
  `[OPEN: exact schema.]` deleted outright — it cannot fail in the way it claims.
  The figure is in A-001, the #300 gate, COMMON.md, issue #300's body, the pause
  acknowledgement and the state page.
- **Gist revisions were queried with 8-character SHAs**, GitHub answered 422, and
  the pipeline counted the error text as a zero match — nearly reporting that the
  pen appears nowhere in the history. The prior desk's standing rule earned again:
  never abbreviate a hash anyone may need to reproduce.
- **Escape sent after Enter into a codex pane cancels submission.** Two notes sat
  unsent while one was reported delivered.
- **The ledger sweep would have orphaned PR #306's authority citation.** Fixed by
  tagging `3653813e…` as `refs/tags/ms11/mandates/a-019` before sweeping, and
  verified to survive the force-push. Any future sweep must check that a cited
  commit is tagged before it pushes.

---

## 7. Carried out, needing a ruling

- **#306 encodes two decisions reversed today**: R300-2 and R300-3 normatively
  require a validator-derived witness set and place `evidence_grade` in
  `CursorV1`; and R300-3 encodes DN-001's untyped permanent `ever_duplicitous`,
  the shape DN-002 §4b argues must be typed by rung. Two independent reasons not
  to merge it as drafted, on top of the missing occupancy instrument.
- **`docs/keri-primer.md` is user-facing and now wrong** — it still says Cardano
  gives "duplicity prevention (UTxO spent once, structurally impossible)" and
  that "Cardano becomes an additional witness".
- **DN-002 S-1's rationale does not survive the rung-2 correction.** It motivates
  itself as a race, but supersession is order-independent; promptness governs
  exposure duration, not outcome. The limit stands, its stated reason does not.
- **F-2 remains the highest-risk item**: #271's commit-reveal entitlement is
  absent from the m12 escrow and from DN-001 §8's S2 scope list, so nothing
  downstream would notice.
- **No repository document explains witnessing.** Every design doc touching it
  was last written 2026-07-28, before the terminal ruling and the decomposition.
