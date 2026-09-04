# cardano-keri project decisions

## D-001 — M1 terminal feasibility ruling (2026-08-18)

**Decision:** do not ship the current monolithic checkpoint design. The
25,934-byte compiled checkpoint exceeds both relevant ceilings before
parameter application. This is an architectural constraint, not another cold
slot's implementation defect.

**Preserved asymmetry:** G0's repair remains proven; G1's measurements remain
useful with caveats; neither rescues the monolith.

## D-002 — found M1.2 / GitHub milestone 11 (2026-08-18)

**Decision:** found `M1.2 — the decomposed record+cursor family` as ACTIVE, the
successor to terminal M1. The installed GitHub milestone 11 description is the
operator's mandate. M1 remains custodial-terminal.

## D-003 — staged execution (2026-08-18)

**Decision:** start with S0 and S1 only. S0 is the first technical verdict and
fails fast on per-script skeleton size above 80%. S1 applies the four-slot
harness lesson before subject work. S2 deep behavior and S3 preprod are
withheld; S3 requires a second written release naming the writes.

## D-004 — project capacity priority (2026-08-18)

**Decision:** new conflicting cardano-keri capacity goes first to M1.2 S0/S1
under the operator's direction to build the redesign now. This does not infer a
release for parked M8 and does not reopen M1.

## D-005 — claims and graduation boundary (2026-08-18)

**Decision:** experiment-claims policy stays in force. Mainnet, production,
announcement, external commitments, delegation/credentials, and product
graduation remain outside the current milestone release. The external pilot
and independent watcher remain the product gate outside M1.2.

## D-006 — resume the M1 product line under M1.2 (2026-08-18)

**Decision:** apply the operator directive immediately at the product layer.
The M1.2 desk triages every one of the 15 open M1 issues as ADOPT, REWRITE, or
CLOSE, non-realizing and without another lane, while S0/S1 audits continue.
M1 itself remains custodial-terminal; “resume M1 line” means successor work
under M1.2, not reopening the dead architecture.

**Mutation fence:** proposed issue text exists locally now. Issue edits,
re-homing, comments, and closures require an exact 15-row manifest accepted by
the project owner and must match it exactly.

## D-007 — co-residency risk is a measured S2 question, not an M1-shaped NO-GO (2026-08-18)

**Decision:** the established M1 reference-input path is a strong prior, not
proof of the new family. Do not relay the 25,617 B / 158.79% structural sum as
a feasibility failure by resemblance to M1's monolithic 158.3%. S2 first
proves witness mode, reads and cites the pinned reference-script size/cost
parameters, tests the inline branch, and only then decides whether the
append/cursor authentication coupling should change.

Answer: `/tmp/ms-keri-11/answers/A-002-co-residency-risk-ruling.md`.

## D-008 — prepared self-executing S2 and decoder release (2026-08-18)

**Decision:** accept machine conditional release sha256
`c6a88a475b2bbecbe6f5d03e2604a132283d52c6f5073077a75b62f7209e2f10`
as PREPARED / INACTIVE. A (S2) and B (decoder repair to main) activate only
after the milestone owner accepts independently audited S0 and S1 artifacts
and the project owner independently verifies them and records
`M12-S2-ACTIVATED`. Each later merge remains milestone-accepted,
auditor-clean, and green-CI fenced. C is exact-manifest bookkeeping, never a
blanket issue mutation grant.

## D-009 — accept the residual M1 triage and retarget cutover (2026-08-18)

**Decision:** accept the complete triage artifact
`6097aa95ece3ec777a3038a958f1473f9c0e1d1f46b0948ea9b445ffbfd7c58f`
at the product-ruling level: ADOPT 7 (`#162 #166 #171 #226 #227 #275 #291`),
REWRITE 8 (`#156 #163 #183 #184 #185 #186 #274 #279`), CLOSE 0. Retain
`#184` and `#185` as inherited release-quality contracts. The retired hunter
economy stays deleted; duplicity detection and consumer refusal survive.

**Cutover ruling:** `#279` targets the M1.2 record+cursor family. Its
inventory-first obligation survives, but this decision starts no preprod read
or write and does not release S3/G2.

**Mutation fence:** classification acceptance is not exact-payload acceptance.
Surface C remains inactive until one deterministic 15-entry artifact contains
the complete final title/body/milestone/state/comment payload for every issue,
is checked against fresh live concurrency bases, and is accepted by the
project owner. Prose such as “body as above” is not executable authority.

## D-010 — milestone register corrected to match the ruled state (2026-08-31)

**Decision:** the shared milestone register disagreed with the project ledger
and with the host, and the register is what is wrong. It listed M1 and M8 as
ACTIVE and omitted milestone 11 entirely — it simply never received D-001 (M1
NO-GO / terminal) and D-002 (M1.2 founded as GitHub milestone 11). Corrected in
`/code/llm-settings/shared/milestones.md` to: M1 `TERMINAL 2026-08-18`, M8
`PARKED 2026-08-23`, M1.2 / milestone 11 `ACTIVE` with desk `m12-desk`, session
`keri-m12`, runtime `/tmp/keri/m12`.

**This founds, retires and releases nothing.** The absent `keri` and
`keri-ms8-blaster` sessions are consistent with the true state: a terminal
milestone correctly has no desk, and M8's desk was lost in a restoration while
its work and runtime survive. M8 holds a *finished* campaign and is therefore
not a retirement candidate; releasing it requires technical restoration of a
session first, which no ruling here requests.

**Supersedes:** nothing. It corrects a register, not a decision.

## Standing question at sweep time

**Q-001 `resolved-adjective-amendment`** — open, with the operator. Whether the
2026-08-30 `Resolved{tip, Clean|Recovered}` statement is a decision or thinking
aloud. Its content: the construct carries zero bits beyond `ever_duplicitous`
(inside `Resolved` the two are equivalent by construction), so it is a verdict
the chain must not issue; keep the monotone fact as the completeness TRIGGER,
drop the adjective. It amends MANDATE-R3. The occupancy/enumeration ruling
amends MANDATE-R1 **and** R3. Both are held together deliberately so R3 is not
amended in two halves with the second re-opening the first.

## D-011 — occupancy resolved by optional path hashing (2026-08-31)

**Decision:** M1.2 owes record-completeness — a consumer must be able to demand
every entry at one location and verify none were withheld. Required by DN-001:53,
DN-002 §3/§4b and MANDATE-R1/R3; `enforced: NONE` repo-wide; absent from all four
requirements accepted 2026-08-27. Scope grows deliberately: deferring re-opens R1
and R2, because it changes the key and leaf design, and a data-structure change
cannot be deferred cheaply.

**Design direction — supersedes the 2026-08-28 converged candidate.** Do NOT
build the outer MPF keyed by location with `count ++ commitment`, and no ECMH or
inner-MPF bucket. Those worked around two MPF properties (hashed keys destroy
locality; the root commits no cardinality). Instead, **make the key hashing
optional, additively, in a local branch**: keep `has`/`insert`/`delete`/`update`
hashing exactly as today so every existing caller — including
`cardano-foundation/cardano-mpfs-onchain` — is untouched, and add `*_at` variants
taking a caller-supplied 32-byte path. **`do_including` and `do_excluding` are
not entered**; those are the proof-walking internals where both v2.0.1 and
v2.1.0 correctness bugs lived. With a structured path (sequence, then prior,
then SAID) the sub-trie at a location prefix **is** the bucket.

**Mandate amendments under A-019.** R1: the key becomes a structured path, and
the no-submitter-chosen-key property is what makes it safe, so it must not
weaken. R3: `ResolutionV1` drops the adjective — `Resolved{tip}`, because
`Clean|Recovered` is the chain grading an identity and is true exactly when the
record already shows a fork; and `ever_duplicitous` is re-specified as a
*maintained index over tree shape*, gated to equal the walk with a mutant proven
able to fail.

## D-012 — the upstream push is the operator's, gated on proof (2026-08-31)

**Decision:** the feature proposal to `aiken-lang/merkle-patricia-forestry` is
raised by the operator, in their words, only after five obligations are met:
depth analysis; the collision number for the 32-byte packing; **the withholding
attack failing with its mutant proven able to fail**; locality holding by
construction; and the size effect measured against the committed S0 baseline
(family 25,716 B against a 16,133 B reference ceiling, headroom −9,583 B). A
negative result on the last one is a real result and is wanted.

## D-013 — M8 parked with a named revisit (2026-08-31)

**Decision:** M8 stays PARKED, is not retired, and carries a revisit condition
rather than sitting in limbo — whichever comes first of M1.2's first requirement
slice merging, or 2026-09-30.

Not resumed now: M1.2 owns capacity under D-004 and was unblocked today by
D-011; two milestones competing for one operator is how both stall. Not retired:
#289's campaign is accepted and unspent (6/6, candidate `c4249307`), and
retiring would discard proven work. Parking became tolerable rather than
negligent on 2026-08-31 when that candidate was finally pushed to the remote
(`4544da2 → c424930`) and stopped existing only on one disk.

## CONSTRAINT — the MPF author is the operator's boss (2026-08-31)

**No agent under this project touches `aiken-lang/merkle-patricia-forestry`** —
no issue, PR, comment or review, at any point, including after the proof gate
passes. Every credential on this host posts as the operator, and this is a
colleague they report to. Stricter than the general outward-prose rule, not an
instance of it.

"Fork" is internal vocabulary only. Outward, this is a local branch testing a
feature proposal — *"let callers supply their own path"* — not a divergence.
Staying additive keeps the project inside upstream's maintenance, which
2026-08-31's #308 (two `excluding()` fixes found upstream, not here) priced
exactly.

## D-014 — V1 must admit interactions as evidence only (2026-09-01)

**Decision:** the record must accept `ixn` events as evidence, with no
state-advancing role.

**What was wrong.** The victim's signalling move — publish a plain conflicting
event so the fork is visible *without* rotation keys — is not projectable in V1.
`event_decoder.ak:354` accepts exactly `icp`, `dip`, `rot`, `drt` and returns
`ErrUnsupportedType` otherwise; `EventVariant` has four inhabitants and no
interaction; the carrier type is `DecodedEstablishmentEvent`. A closed sum, not
a setting.

**Why it is a product hole, not a missing feature.** When both parties hold
identical key material neither can prove legitimacy, so the victim's only
remaining power is *denial* — making the identity unusable to the thief. KERI's
first-seen removes even that, since witnesses refuse to receipt the victim's
conflicting event. The record is supposed to **restore** it, and restores
nothing if the victim's cheapest signal is inadmissible while the expensive
alternative needs exactly the pre-committed keys the victim may not have.

An interaction changes no keys, so evidence-only admission needs no key-state
snapshot and no advance-path semantics — consistent with the settled framing
that the record is a watcher's evidence set, not a KEL. Lands on R2. The size
cost belongs to the desk, reported jointly with D-016.

## D-015 — the R1 re-cut block extends to consumer demand (2026-09-01)

**Decision:** R1 does not re-cut until the leaf schema is settled against
consumer demand as well as occupancy. Raised by the M1.2 desk against this
owner's own release, and accepted.

It is the occupancy argument one level up and stronger: it also changes the
leaf; it is in **no mandate at all**; and a downstream validator cannot
re-derive the cursor because it has no budget to walk the trie. Re-cutting on
occupancy alone risked a third cut.

**The structural evidence.** All four accepted #300 requirements face inward —
event-derived key, event leaf plus snapshot, whole-record cursor, keripy parity.
R300-2 justifies its schema by "the cursor must become computable from the tree
alone", i.e. from our own append recursion. Meanwhile the milestone description
names a consumer predicate library and a reference cursor-consumer
(AUTHORIZING before a conflict, REFUSED after) **as part of the family**, and it
has no requirement, no mandate, no lane, and no place in the S2 gate list.

## D-016 — materialisation is a standing architectural constraint (2026-09-01)

**Decision:** every fact a consumer predicate needs must be materialised in the
cursor datum itself — self-contained, fixed-size, readable without a proof —
because a CIP-31 reference input is all a consumer gets and it has no budget to
walk the trie. A cursor whose meaning can only be recovered by replaying the
record is, to a consumer, not a cursor.

Binds the R300-2 leaf schema and the R3 cursor output. It is why consumer demand
cannot be deferred: it decides what the leaf *contains*. Materialisation and
D-014 push the same size wall and are costed together, not separately.

## D-017 — no-submitter-key-choice becomes an enforced gate duty (2026-09-01)

**Decision:** amend MANDATE-R1 under A-019 so that "the submitter cannot choose
the key" is a **named gate duty carrying a mutant proven able to fail**, not a
design intention.

The whole O1 depth argument — and therefore the case for the structured path and
anything eventually put to the library's author — is contingent on that one
property. If R1 ever weakens to admit submitter-influenced key placement, the
structured path loses its balance guarantee and upstream's hash becomes
load-bearing again, silently, because nothing today would notice. An invariant
whose violation no check can detect is not enforced, and this project has been
bitten by that exact shape more than once.

## Open premise — Q-002, the consumer

Which applications consume a projected KERI identity, and what must their
predicates read? Not inventable by this seat: fixing the leaf schema against a
fictional consumer is the same defect the desk caught in inward-facing form, and
this role must not infer users or commitments from repository contents. Put to
the operator with a concrete proposal — adopt the reference cursor-consumer
already named in the milestone description as the minimum demand that fixes the
leaf. As of 2026-09-01 the operator is settling it directly with the M1.2 desk.

## D-018 — measure before any lifecycle call (2026-09-01)

**Decision:** no re-found, continue or retire ruling on M1.2 until the one
number every route depended on existed: the combined size of evidence-only
`ixn` admission, a materialised consumer cursor and provable completeness,
against the 16,133 B reference ceiling. Superseded the same evening by the
measurement itself (D-019) and the next morning by D-021.

## D-019 — the co-residency coupling is not an invariant (2026-09-01)

**Decision:** no lifecycle assessment may cite the 25,716 B co-residency sum
without stating the witness mode it assumes and whether the pair-token
coupling that forces co-residency is still present. Measured from the pinned
genesis: reference scripts are fee-priced (`minFeeRefScriptCostPerByte` 44),
not counted against `maxTxSize`; the family in reference mode costs about
1.13 ADA per transaction, not minus 9,332 bytes. The "foundering" number was
one D-007 had forbidden reading that way. Still true under the return: a
single script over 16,384 B is undeployable in both modes (its deployment
transaction carries it), which is why D-001 stands for the monolith.

## D-020 — hold the upstream proposal indefinitely (2026-09-02)

**Decision:** the additive path-hashing proposal to
`aiken-lang/merkle-patricia-forestry` is held, not merely gated: if the tree
goes, the proposal is unnecessary. Under D-021 it is permanently moot. The
constraint that no agent touches that repository stands.

## D-021 — M1.2 retired, the M1 line resumed (2026-09-02)

**Decision:** operator ruling, "I am killing M1.2 and going back to M1",
accepted and executed. DN002 §6 reached the same place from analysis: with the
tree gone, what remains is a UTxO per AID, and M1.2 converged back on the
checkpoint with the poison added and the duplicity machinery removed.

Three bounds on what "back to M1" means. M1 is a deployed artifact (five
preprod reference scripts), not a design; D-001 stands for the monolith and
the reference-mode measurement does not rescue it; what killed the monolith is
the enforcement machinery DN002 drops.

**Supersedes:** D-011, D-014, D-015, D-016, D-017 (all dead with the tree).
**Closes:** Q-002 and Q-003 as overtaken.

## Superseded on 2026-09-02, for the record

- **D-014** (`ixn` as evidence): withdrawn. DN002 §4 — poison is not an event.
- **D-011** (`ever_duplicitous` as a maintained index; occupancy by optional
  path hashing; the MPF fork direction): withdrawn. DN002 §3 (contested
  watermark) and §6 (the tree is not needed).
- **D-015, D-016, D-017**: dead with R1, the leaf and the structured path.

## PROPOSED — the M1 return plan (2026-09-02, not a decision)

`AUDIT-M1-RETURN` (`owner/handoffs/M1-RETURN-audit-and-plan-2026-09-02.md`,
sha256 `c7c8813f1b704aecfb62c62ed3afa0face419541dfae3073fbadafc502183da2`;
https://claude.ai/code/artifact/c49a4833-5415-42c8-8aad-bd9796139a79 ).
Audit verdicts: the checkpoint dissolves completeness and the oracle (holds);
witness gating is already M1's rule but DN002's "parent's witness set" differs
from the shipped tally over the new set, settled only by a keripy parity oracle;
the poison breaks unless it is evaluated at `cur_threshold`; **A3 (monotone
watermark) was withdrawn the same day on operator correction** — next keys are
control by KERI's rule, the poison is local to the current keys and cannot
taint the next keys, so the bit clears on any witnessed rotation and history is
the indexer's; the close marker (A5) is demoted to a Phase 3 decision covering
only the lost-next-keys corner; **A4 accepted as D-022 the same morning**: the
checkpoint cannot roll back, and the live state machine has exactly two
edges, rotate (moves the keys, clears the poison) and poison (sets the bit,
leaves the keys), with register and close as boundaries — the shape the Lean
model of Phase 0 must take; **amended the same hour: poisoned keys can only be
rotated** — from the poisoned state neither close nor a second poison is
enabled, which closes the current-key-thief-closes exposure for every poisoned
epoch and withdraws A5 (no marker needed); **D-023: both edges require the
quorum**, A1 accepted. A poisoned identity whose next keys are lost is frozen
forever, deposit included, a stated limit; **D-024, the blocker the operator
named in 2.7 — verified on main: no on-chain uniqueness for an AID checkpoint
exists (trust-model.md:183-189; CLI-only refusal), so a stale-key holder can
mint a second incarnation at their epoch — ruling: AIDs have to be minted to
prove unicity, inceptions must be queued**: an AID registry (one UTxO, one MPF
root, absence proof on Register, spent by nothing else), the token never
burned (close parks, reopen by the parked quorum), juvenility over `born_at`
for the first-registration residual. A5 reinstated for unicity; A9, A10 new;
**D-025 (operator, same morning): no replay** — the checkpoint UTxO is permanent,
close withdraws the bond (quorum, not while poisoned) and leaves the state in
place, bonding is permissionless (anyone deposits D_reg, born_at reset), an
unbonded checkpoint is not consumable; bonded is a value-level fact, edges are
independent of it; a stale bond is captured by whoever holds the current keys
once the checkpoint is advanced, so a stale-key re-bond costs the attacker D_reg;
**D-026 (operator, same morning) supersedes the permissionless bond**: a parked,
unpoisoned checkpoint whose current keys are later stolen would be an entry
point if anyone could re-bond it, so the ONLY resurrection is a witnessed
rotation carrying the bond back; no bond transition exists; a parked checkpoint
is inert to current-key theft; the bond is the freshness signal. Residual stated:
leaked later-epoch keys plus the controller's own public rotation can resurrect
at that epoch, bounded by juvenility and bond capture, inherent to
permissionless advance; **D-027 (operator direction, not ruled)**: liveness is a
Cardano-side fact — transitions carry a validity and the controller renews it
by re-signing with the current keys (no next-key reveal); stress-tested as a
second declaration next to poison that RENEWS and never REVIVES (an expired
checkpoint is inert to the current keys, like an unbonded one, and returns only
by rotation), covering abandonment not lag; reserve alive_at and valid_until in
datum V2 now; A11 opened on whether refresh ships in this return; **D-028
(operator, same morning)**: what D-025/D-026 described is the PAUSE edge (state
stays, allowed poisoned or not, no unpause, resurrection only by witnessed
rotation); the real CLOSE edge redeems the bond and removes the AID, only
unpoisoned, terminal (token burned, registry row stays); stress-test inference
A12: pause never touches the bond, else a current-key thief takes D_reg on a
poisoned identity — the bond enters with register and leaves only by close; **D-029 (operator
direction, not ruled)**: freeze for KERI-observed liveness failure, seize, and
witness duplicity as the smoking gun; verified in source that the deployed
freeze predicate consumes the identical evidence advance does (and tallies
against the old witness set) and that the deployed convict predicate is exactly
rot-vs-rot at the tip with receipts at toad, verifiable without history;
stress-test recorded: freeze is dominated by advance and seize pays for the
harmful move (the 2026-08-17 class invariant), so A13 recommends both out; the
smoking gun is recommended as a PROOF-BASED POISON with a permanent
convicted_at mark and no bond flow (A14), proven duplicity being a KERI verdict
unlike an epoch-local declaration; cutting the receipting witnesses on exit is
open; follow-up the same hour: freeze is replaced by PAYING FOR ADVANCE (the
2026-08-17 maintenance premium, A7 reopened for this return or the next) and the
convict invariants are stated exactly (T12: convicted_at and liars written only
by a verified proof, never cleared; T13 if clearable: the exit rotation's witness
set is disjoint from liars); FINAL versus CLEARABLE is the operator's call - final
is KERI's verdict but makes conviction terminal again under the registry;
**D-030 (operator, same day): CONVICTION IS FINAL** — asked what event clears
proven duplicity inside KERI, the answer is none, so by the projection law the
chain may not invent a recovery; Convicted is a terminal state (token retained
as tombstone, no edges), the declared poison stays clearable by rotation, the
conviction does not; the bond is not locked: refund_to is committed at register
and anyone may refund D_reg there from Convicted; reverses the July
not-terminality rule for proven establishment-level duplicity because Cardano
mirrors KERI and KERI is terminal here; **D-028 amended (operator, same day):
poisoned cannot pause** — pause is enabled only when unpoisoned and unpaused, so
from a poisoned state the only edge is rotate, exactly D-022; A12 (pause keeps
the bond) becomes an economic choice; A15 opened: where the bond goes at close,
the committed refund_to or the closer's choice; **D-031 (operator, same day):
freeze is gone (A13 ruled) and conviction is a FULL SEIZE** — the convicting
transaction pays D_reg to a payee it names, no refund path; reverses the
2026-08-17 class invariant for proven establishment-level duplicity only, on
D-030's ground; stress-test: only a next-key holder with >= toad colluding
witnesses can stage it, and the victim of such a thief loses D_reg as well as
the identity, bounded by the D_reg parameter; **D-032 (operator, same day): close
pays the CURRENT refund_to, established at rotation** (A15 ruled) — set by the
registrant, re-established only by a rotation whose new address is authorized
by the NEW current keys (a relayer on public data cannot move it), never by
poison, pause or close; a current-key thief who closes sends the bond to the
controller; the key-compromise.md close exposure is closed; cost is one optional
threshold verification on the advance path, to be measured; **D-033 (operator,
same day): pause is a ROTATION that withdraws the bond** (A12 ruled) — no pause
edge, no paused flag, unbonded is the value; resurrection is a rotation that
deposits it; both need the next keys; the rotation itself authorizes every bond
option, so it covers both poisoned states automatically; the machine is back to
two edges, rotate and poison, plus the convict proof and the boundaries;
**D-034 (operator design, same day): the HUNTER ECONOMY** — the owner rotates on
KERI only; a hunter (own watcher seeded from the endpoint board) lands the
rotation for P from the advance pool if the pool covers it, else passes the same
rotation with receipts and takes the FREEZE BOND B, freezing the AID on the old
keys; the owner must then rotate on Cardano with B replenished and top up the
pool; three value components never mixed — D_reg the conviction bond (never a
fee source), B, the pool; frozen is B missing, a value-level fact; a draft that
paid maintenance from D_reg was withdrawn on the operator's correction ("the
bond is for the conviction"); open: P global or per AID, freeze from poisoned,
B and pool at conviction; the DN002 §7 accumulator is unnecessary in a no-ixn
chain; the datum change lands on a script 3 B under its ceiling and must be
measured first. Eight assumptions A1–A8 are the operator's to overturn. This
becomes D-022 only when they rule.

**D-035 (operator, 2026-09-02 ~14:00Z): THE SIMULATOR IS REBUILT FROM THE LEAN
BY A FRESH FABLE WORKER, AS A MEASUREMENT OF THE LEAN** — after the GLM
candidate's audit (FINDINGS), the operator ruled the simulator be taken over
and made great, based on the Lean theorems, with graphics in the manner of the
Reactivegas simulator, by another Fable worker on a fresh worktree with no GLM
prework, "so we see how much the lean is clear". Consequence: the worker's
brief names `Checkpoint.lean`, `CheckpointGoals.lean` and
`CHECKPOINT-MUTANTS.md` as the sole specification of the machine and the
stories as vocabulary; the worker records every point where the Lean did not
let it decide in `LEAN-CLARITY.md`. That file is the experiment's result and
feeds the Lean's doc comments and the design note before Phase 1. The page
checks T1–T16 as executable properties on every step (a theorem ledger) and
the gates check them over every replay and over a Lean-emitted boundary grid
that includes refusals.

**D-036 (operator, 2026-09-02 ~16:00Z): CLOSE NEEDS THE NEXT KEYS; CLOSE IS
NOT FINAL WITHOUT A CONVICTION** — "obviously we have to protect the owner and
so close is only possible signing with the next keys; on the other hand close
is not final if there is no conviction so the ID can be replayed". Made precise
in conversation: close is a witnessed rotation that withdraws everything and
burns the UTxO, so the unpoisoned guard on close dissolves (D-022); the
registry leaf is the tombstone — a map from AID to status (absent / live /
closed(epoch, sn) / convicted), the checkpoint UTxO being only the live part;
reopen is a registration presenting a witnessed rotation later than the
closed sequence with fresh bonds and juvenility; conviction is the only
terminal leaf. Supersedes the close half of D-028 and the terminality of Gone
in D-025. Reason: a current-key thief could otherwise burn the owner's Cardano
presence before she poisons. To be folded into the Lean before Phase 1.

**D-037 (operator, same day, ~16:10Z): THE REGISTRY IS MPFS MADE PERMISSIONLESS
AND CONVENIENT** — "serialization is a problem, we could use MPFS for the
registry" then "we should modify MPFS to be permissionless and convenient".
MPFS (cardano-mpfs-onchain) facts checked: oracle-only Modify, permissionless
requests with time-gated phases, integrity on chain, honest processing
off-chain. Permissionless: no owner signature on Modify, no End/transfer,
objective rejection only, tips to whoever applies, cage proofs re-proved.
Convenient: a request carries the inception and the bonds and the checkpoint
mints at application inside the applier's transaction (keri policy composed
with the cage); reopen is a request with a presence proof and a later
witnessed rotation; close and convict are leaf-update requests. Open:
placement (keri-specific cage in cardano-keri vs permissionless mode upstream).

**D-038 (operator, 2026-09-03 ~08:50Z): EVERY BOND OPTION OTHER THAN `keep` IS
AUTHORIZED BY THE NEW EPOCH'S KEYS** — from the simulator seat's escalation
Q-001: `Step.rotateWithdraw` needed only the witnessed rotation, so anyone
relaying a public rotation could park the owner; the sibling
`Step.rotateDeposit` on full bonds brought nothing and still reset `bornAt`,
a free juvenility reset. Ruling: "we want to protect those edges with the
signature from current keys", precised as the keys of the epoch the rotation
opens (the keys the rotation reveals, which sign the rotation and, under
D-032, the refund address), never the retired keys. Form: one optional
message signed at threshold carrying (bond option, refund address); absent
means keep and unchanged. Keeps the relay permissionless; covers close under
D-036. Amends D-033 (the plan's sentence "the rotation itself authorizes every
bond_op" was the origin). Rides the second Lean slice with D-036 and D-037.

**Process rulings (operator, 2026-09-03), recorded in llm-settings `main`:**
the statement auditor of a Lean slice checks completeness (every licensed
transition, every ruling's theorem, nothing dropped) and never provability
("if we think the theorem holds we prove it"), and challenges vacuity with a
reachable witness and a single-guard mutant per theorem, under the
`commit-auditor` discipline; the design loop (rulings → Lean statements →
completeness audit → proofs + mutants → simulator from the Lean alone as the
operator's review surface, `LEAN-CLARITY.md` as the measurement) is the shared
skill `system-design`; the simulator follows the stated Lean at once and the
proofs run alongside play; llm-settings and infrastructure repositories are
main-only (no branches, pull requests or leftover worktrees).

**D-039 (operator, 2026-09-03 ~16:00Z): THE OWNER'S REAP OF A LIVE CHECKPOINT
TAKES CLOSE'S AUTHORIZATION, AS A SEPARATE TICKET AFTER THE REGISTRY'S SLICE 3**
— the registry seat's slice 3 (its ruling 12: no pause, no parked UTxO state,
no grace window) authorizes the owner's reap of a live checkpoint with the
current quorum; this desk found that reap to be the checkpoint machine's close
(D-036), which answers to the next keys and the D-038 signed message naming
the payee, and that the same message resolves the registry's Q-R6 (the block
producer copying a reap with itself as payee). Operator: "you can add it after
the changes as a separate ticket" — #358.

**D-040 (operator, same day, ~16:05Z): THREE REGISTRY STATES, ONE UTxO** — "so
at the end there is only active (UTxO), parked (checkpoint hash), convicted
(probably nothing)", "this is reflected in the checkpoint state machine".
Active: the checkpoint UTxO (live, poisoned, frozen). Parked: no UTxO; the leaf
holds the hash of the last checkpoint; revival only by a witnessed rotation
from that key state with fresh bonds. Convicted: terminal, the leaf holds
nothing but the mark. Ruling 12 is global: the checkpoint machine loses the
withdraw option and the unbonded on-chain state; leaving is the reap (close);
deposit survives as the unfreeze. The plan's "closed(epoch, sn)" is renamed
parked(hash). Checkpoint slice 3: #359. Supersedes D-033's withdraw option.

**D-042 (operator, 2026-09-04 ~13:38Z): SLICE 3 ACCEPTED WITH THE DENOMINATOR
RESIDUAL** — the repair audit of `8820582` closed all three earlier findings
(the campaign table matches its run; all 74 checkers die when made
unconditional; the template assets are one identity with the page) but found
one defect in two runners: a gate that decides from a problem count treats an
empty run as green (`lean/mutants/run.sh` → `TOTAL 0/0`, exit 0; the scenario
gate's `--vacuity` and `--selftest` → "0 checker rows", exit 0). Operator:
"accept". PR #360 merged as `9b2e6b8`; the residual is #362 (assert the
denominator in all five gates, each with its own control) and the rule is in
the shared `lean-simulations` skill.
