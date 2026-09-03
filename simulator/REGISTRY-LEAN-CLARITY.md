# The registry machine — clarity record

Every point where `lean/CardanoKeri/Registry.lean` did not decide and the
simulator had to, with the source of the decision — with one caveat first:
this was a single-seat slice (the same seat wrote the Lean and the
simulator; the other family, Codex, audited after the proofs), so the record
measures nothing about what the Lean carries to a fresh reader; it records
the decisions and the disagreements only; every place a story, a doc
comment and a definition disagreed; every audit finding that was not folded
into the Lean, with what it waits for. The Lean is the law; this file is the
list of what the law left open. Dates are 2026 unless said.

## Decisions the simulator took (D)

| id | point | decision | source |
|---|---|---|---|
| D-R1 | `stepFn` returns `none` without naming the failed conjunct | one refusal name per `if` conjunct and per refusing `match` arm, in the Lean's textual order; the table `LEAN_GUARDS` in the core binds each name to its decision sites and the scenario gate checks the binding both ways | the simulate-lean-state-machine skill; the guard texts are the Lean's own |
| D-R2 | one Lean pattern, two names | `stepFn .pause` and `.resume` match `some ⟨tok, k, .live⟩` / `some ⟨tok, k, .parked _⟩` against `_ => none`; the core reports `no-checkpoint` when the lookup is empty and `not-live` / `not-parked` otherwise, because its lookup comes first. Declared in `LEAN_SHARED_SITES` | transcription order |
| D-R3 | what a step "exhibits" | a lamp lights when the property's antecedent held non-vacuously on that step; pinned per scenario step in `exhibits`; a boundary refusal (`invalid-*`) exhibits nothing | skill rule |
| D-R4 | executable properties are grouped | 15 lamps over 47 named theorems (`THEOREMS[].lean`); the helper and invariant theorems of `RegistryGoals.lean`, the 12 of `Cage.lean` and the 6 of `Samaritan.lean` have no executable twin — the gate says "every executable property exhibited", and every lamp has a fabricated violation it must red on (R10 by the phases-overlap mutant) | audit finding 11, 2026-09-03 |
| D-R5 | the bound on Nat | exact to 2^53 − 1 for inputs *and* results: `nextReq + 1`, `nextToken + 1`, `gen + 1`, `k + 1`, `submittedAt + process (+ retract)`, `parked + W`, `bond + tip`, `n × tip` refuse `invalid-nat/<field>` past the bound (`NatOverflow`, caught by `step`) | audit finding 10 |
| D-R6 | a property about a batch element | reads the accumulator the element saw (`batchView`), never the pre-state; the Lean twin is `R14_convict_in_batch_needs_proof` (any accumulator) and `R14_convict_at_position` (any position of an applied batch) | audit finding 9 |
| D-R7 | the values, the cast, the addresses | D 1000, tip 2, Mc 4, Mr 1, process 10, retract 10, W 5, far 10⁹, plugin 7; Alice 1, Bob 2, Hal 3, Mallory 4, Cora 5, Sam 6; AIDs 11–13 | the stories |
| D-R8 | a story's refused attempts and what-ifs | branches (`forks`) from a trunk state, folded by the driver as `f<id>.<i>` cells; a fork may bring its own evidence table (another world) | skill rule; audit finding 13 (two narratives claimed cases no step played) |
| D-R10 | what a payment clause proves | a payment row names the full assignment `field := expression` inside the arm's result and the matched step must pay through that field; the *amount* is not read off the prose — the exact flow every position owes is what R11 checks on every applied step, and a verdict row names the theorem the step instantiated (`by`) | audit 2, finding 4 |
| D-R11 | T7 in free play | every page record carries the evidence table and looks its step up in the embedded corpus (stories, traces, the grid); the ledger's T7 row says "agrees", "disagrees" or "no Lean cell for this step — parity not shown"; a story step always has its cell | audit 2, findings 2 and 3 |
| D-R12 | sessions | the core owns immutable sessions (`newSession`, `attempt`, `addEvidence`, `removeEvidence`, `setSlot`, `heldSoFar`, the `session` slice); the page keeps a tree of them and plays a path's edges forward or in reverse (`goTo`) — the checkpoint page's shape, adopted on 2026-09-03 evening at the operator's request ("I want this exact style") | audit 2, note 11; closed |
| D-R13 | the page's shape | the checkpoint page's template (`simulate-lean-state-machine/assets`): its stylesheet verbatim as the page's first `<style>` (the template's `check` reports no drift for `page.css`), its panels in its order (the play and its tree, the play bar, where we are, the glossary, the narration; what can happen next by stakeholder with the refusals written out; the scene; the lamps; the drawers), its generic functions ported as they are; the registry's own panels (the evidence table by AID, the registry in numbers) live in the template's drawers, so the skeleton and the id list drift there by design — the registry is a second instance, not the reference | the operator, 2026-09-03 evening: "I want this exact style" |
| D-R14 | the game hooks of the template (skill update of 2026-09-03 evening) | ▶ stops on the punchline — the last accepted move of the trunk, or the story's own `punchline` — and shows the hit as a toast; "what fails after ›" walks the coda; the tree marks the punchline ★; the HUD clones the where-strip when it scrolls out; the glossary draws the leaf's states as rooms (no leaf, active, dormant with a door back, convicted sealed); story mode lights the next actor's card and the one move, folds the others; refusals grouped by reason; inventory and moves labelled; lamps shown in the run carry ★ with a discovered-of counter; one challenge, "Register Alice's AID as yours", won against the same `stepFn` and read off R1, R1d, R6 | the skill's page reference, "the page is a game" |
| D-R15 | the deployment's phase lengths | the stories play `process` = 10 slots for legibility; on a chain where a block is about twenty slots, phase 1 must span many blocks — it is the number of leaders a censor has to be to keep a request out (ruling 11 and the starvation remark) — and the design note says so; the machine is indifferent to the value | the operator, 2026-09-03 evening |
| D-R9 | who may fold, reap, register | nobody signs: `stepFn` has no submitter, the page's cast are stakeholders and `actor` on a step is a label the gate checks against `actionActor`, never an authorization | Registry.lean (`Actor` is derived) |

## Questions escalated (Q), rulings pending

| id | fact in the Lean | what it means | proposed | status |
|---|---|---|---|---|
| Q-R1 | `Checkpoint.lean:305–312` (base branch, PR 315): `.close` takes a present checkpoint to `.gone` under quorum; `Registry.lean` has no edge for it | the constraint: ruling 4, "the permissionless version can't be closed", reached the registry and not the checkpoint machine. The attack: after a registration the owner closes, and the registry keeps an active leaf with neither checkpoint nor go-request — `Inv.activeCkpt` does not hold of the pair, and the AID can never be revived or convicted | a ruling on the checkpoint machine's exits (the base branch's slice) | audit blocker 1; open |
| Q-R2 | `Inv` bound an active leaf to *some* checkpoint, not to the checkpoint carrying *that* token | an `Inv`-satisfying state could have leaf `active 0` and checkpoint token 1 | `activeCkpt` strengthened to name the token — see "Token binding" below | audit major 2; **closed** |
| Q-R3 | `stepFn .retract` checks the request id and the phase; no signer | the constraint: the machine has no signer on any edge (ruling 1: permissionless), and `validators/request.ak:91` on cardano-mpfs-onchain main requires the owner among the signatories for a retract. The attack: in phase 2 a stranger retracts another's request; the refund reaches the recorded owner, so the owner loses the registration attempt and the fee, not the bond | a ruling: is the retract the one signed edge of the registry cage, as the Aiken has it, or is it permissionless like every other edge | audit major 3; open (story 5 marks it an omission) |
| Q-R4 | `rejectable` holds when `now < submittedAt`; a go-request dated `far` is therefore rejectable by the cage; safety is the plugin veto `r.op.userPostable = true` in `rejectOne` | on cardano-mpfs-onchain main (`state.ak:113–121`) `Rejected` has no plugin veto: a go-request would be rejectable and its key state lost; the model depends on #102 | keep; the design note now says so | audit major 4 |
| Q-R6 | `reapable`: `env.quorum aid = true` lets the owner reap inside the grace window; the reaper address is a free field of `.reap` | the constraint: ruling 11 — the owner reaps her own checkpoint, and the block producer copies any transaction it sees. The attack: the producer copies her early reap with itself as the reaper; the quorum evidence is bound to the AID, not the payee, so the copy is admitted inside the window that was meant to protect her; it takes the premium now and the go-request's min-ADA at the fold — her exposure is `Mc` (story 11, branch "the block producer copies Alice's early reap") | a ruling: does the owner's quorum message name the reaper (`env.quorum aid reaper`), as D-038 made the rotation's keys name the refund address | open; the Lean is unchanged until ruled |
| Q-R5 | `Sys` has `plugin` but no owner / stake-script field | R5 proves the plugin pinned, not the owner pin #100 asks for; `types.ak:197–201` on main lets the owner change | add the fields when #100 lands upstream; until then the design note lists it | audit major 7 |

## Disagreements found between prose, doc comments and definitions

| where | said | the Lean | fixed |
|---|---|---|---|
| story 11 narrative | "the leaf is active(1) again" | Bob took token 1; the revive mints token 2 | narrative corrected; the branch "Mallory's revive carries no rotation from key state 1" plays the case the old text claimed |
| story 13 narrative | "a conviction request without the proof is refused" | no step played it | branches "the go-request and the conviction in one fold" and "the same fold without the proof" |
| `REGISTRY-STORIES.md` (phases), the page's inbox hint | "a go-request is … never rejectable" | `rejectable` holds for it; `rejectOne`'s plugin veto refuses | both now say the cage would reject it and the plugin refuses (the first fix reached story 14 only; audit 2 found the two remaining sites) |
| story 7 narrative | "the real fold then lands" | no fold lands; Alice retracts in phase 2 | narrative corrected |
| story 15 narrative | "in phase 1 for a hundred slots" | `inPhase1` holds at slots 0–109 for `submitted_at` 100 and `process` 10 | "until slot 110" |
| design note, samaritan | "nobody reaps" as a consequence of the tip bound | `samaritan_never_loses` counts the go-request's eventual refund; it is a conditional, eventual accounting, not a per-transaction guarantee | the note now states the condition |
| design note, cage | "`refundAll` as `validModify` does today" | `validModify` on main checks an aggregate refund range less fee and n·tip, ignores the action tail past the requests, and accepts an empty Modify | the note lists the three divergences (audit majors 5, 6) |

## The second audit (Codex, max, 2026-09-03 evening)

On the folded tree: 1 blocker, 5 majors, 3 minors, 2 notes. Folded: the
fork-drift control's message (the nested build's stdout and stderr are kept;
five more controls: a story file removed, a refusal never asserted, a verdict
retied within its group, a payment text truncated, a page record without the
evidence; the trace gate's schema/version control); the page record carries
the evidence (three lamps threw on every fold in free play and the smoke did
not look); T7 in free play (D-R11); verdict rows tied to the theorem the step
instantiated and payment rows to the full assignment (D-R10); R3 reds on an
applied re-registration of a convicted AID and the R11 fixture reaches its
wrong refund; strict validation at every entry (`replay` with an empty list,
every evidence table present, no stranger parameter, corpus results validated
and compared exactly); the boundary grid at slots 19, 20, 21 with the phase
ends, the grace end and the genesis generation triad at −1 / = / +1 (3000
cells); story 7 and 15 narratives; the "never rejectable" wording on the
page and in the stories; mobile overflow. Recorded: D-R12 (sessions); the
mutation record does not mutate `applyBatch_append` on its own (it is a
lemma, not a guard; M9 exercises it through `R14_convict_at_position`).

## Token binding (Q-R2), done

`Inv.activeCkpt` (and `AccInv.activeCkpt` on the fold's accumulator) now reads
`(∃ c, lookup s.ckpts aid = some c ∧ c.token = tok) ∨ goPending s aid`:
an active leaf's token is the token of its checkpoint. `inv_replace_ckpt`
takes `c'.token = c.token` (pause, resume and a checkpoint conviction keep the
token); registration and revival mint the leaf's token into the checkpoint by
construction. `R1_active_ckpt_or_go` states it; the executable R1 checks it
on every applied step and reds on a leaf whose checkpoint carries another
token. The audit's countermodel (leaf `active 0`, checkpoint token 1) no
longer satisfies `Inv`. Q-R2 is closed.

## What the gates do not establish

- Parity is with the corpus the driver emitted (6 traces, the boundary grid,
  15 stories with 13 forks): a transition outside those cells is checked
  only by the properties, not against Lean.
- The properties are projections of the theorems (D-R4); a green corpus does
  not prove a statement outside its checked projection.
- The clause table ties prose to declarations and steps; it cannot see what
  the prose leaves unsaid.
