# The registry machine — clarity record

Every point where `lean/CardanoKeri/Registry.lean` did not decide and the
simulator had to, with the source of the decision; every place a story, a doc
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
| D-R9 | who may fold, reap, register | nobody signs: `stepFn` has no submitter, the page's cast are stakeholders and `actor` on a step is a label the gate checks against `actionActor`, never an authorization | Registry.lean (`Actor` is derived) |

## Questions escalated (Q), rulings pending

| id | fact in the Lean | what it means | proposed | status |
|---|---|---|---|---|
| Q-R1 | `Checkpoint.lean:305–312` (base branch, PR 315): `.close` takes a present checkpoint to `.gone` under quorum; `Registry.lean` has no edge for it | after a registration, an owner who closes leaves an active leaf with neither checkpoint nor go-request: `Inv.activeCkpt` (`Registry.lean:459`) does not hold of the pair of machines | under the ruling "the permissionless version cannot be closed" (2026-09-03), `close` leaves the checkpoint machine and becomes park + reap; a checkpoint's only exits are reap and tombstone | audit blocker 1; the change is on the base branch, not in this PR |
| Q-R2 | `Inv` bound an active leaf to *some* checkpoint, not to the checkpoint carrying *that* token | an `Inv`-satisfying state could have leaf `active 0` and checkpoint token 1 | `activeCkpt` strengthened to name the token — see "Token binding" below | audit major 2; **closed** |
| Q-R3 | `stepFn .retract` checks the request id and the phase; no signer | anyone may retract another's request in phase 2; the refund still goes to the recorded owner, so it is a cancellation, not a theft; `validators/request.ak:91` on cardano-mpfs-onchain main requires the owner's signature | add a `signer` to `.retract` and the guard `signer = r.owner`, or keep the machine signer-free and record the omission (the stories mark it as an omission today) | audit major 3; a design ruling: the machine has no signer anywhere else |
| Q-R4 | `rejectable` holds when `now < submittedAt`; a go-request dated `far` is therefore rejectable by the cage; safety is the plugin veto `r.op.userPostable = true` in `rejectOne` | on cardano-mpfs-onchain main (`state.ak:113–121`) `Rejected` has no plugin veto: a go-request would be rejectable and its key state lost; the model depends on #102 | keep; the design note now says so | audit major 4 |
| Q-R5 | `Sys` has `plugin` but no owner / stake-script field | R5 proves the plugin pinned, not the owner pin #100 asks for; `types.ak:197–201` on main lets the owner change | add the fields when #100 lands upstream; until then the design note lists it | audit major 7 |

## Disagreements found between prose, doc comments and definitions

| where | said | the Lean | fixed |
|---|---|---|---|
| story 11 narrative | "the leaf is active(1) again" | Bob took token 1; the revive mints token 2 | narrative corrected; the branch "Mallory's revive carries no rotation from key state 1" plays the case the old text claimed |
| story 13 narrative | "a conviction request without the proof is refused" | no step played it | branches "the go-request and the conviction in one fold" and "the same fold without the proof" |
| `REGISTRY-STORIES.md` (phases) | "a go-request is … never rejectable" | `rejectable` holds for it; `rejectOne`'s plugin veto refuses | the words say "the plugin refuses to reject it" |
| design note, samaritan | "nobody reaps" as a consequence of the tip bound | `samaritan_never_loses` counts the go-request's eventual refund; it is a conditional, eventual accounting, not a per-transaction guarantee | the note now states the condition |
| design note, cage | "`refundAll` as `validModify` does today" | `validModify` on main checks an aggregate refund range less fee and n·tip, ignores the action tail past the requests, and accepts an empty Modify | the note lists the three divergences (audit majors 5, 6) |

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
