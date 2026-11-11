# M1 plan v3 — trunk-based, a release per ticket

Drafted 2026-09-14 at the desk for the operator's ruling. Supersedes the
fourteen-epic layout of `docs/roadmap.md` once approved; the outcome does not
change.

## The outcome, unchanged

On preprod: an identity registered once through the registry; rotations landed
by hunters for a premium; a freeze when the pool is short; poison by the
current quorum, cleared by rotation; close by the next keys and reopen by a
later rotation; conviction on a duplicity proof, terminal; a consumer contract
reading the checkpoint with the fail-closed verdict; `ckeri` and a hunter
daemon doing all of it; the fifteen stories replayed on preprod; release 0.5.0.

## Rules

1. **One branch.** Every ticket is one PR against `main`, merged on green by
   its own lane. No epic lanes, no quadrants, no long-lived branches. The
   epics #318–#328 stop being lanes and become the order below.
2. **Every merge releases.** The release planner already runs on push to
   `main`; it opens a release PR that today waits for a hand merge. Ticket A1
   makes that PR auto-merge, so `merge → release PR → tag → GitHub release`
   needs nobody. A ticket is not done until its release exists.
3. **A ticket ships something a user can run.** For the story tickets that
   means, in one diff: the validator edge, the `ckeri` command, the story
   replayed on a devnet, and the docs page for that story. Acceptance is one
   paragraph, frozen at filing; widening it is a new ticket.
4. **Lean first, in the same PR or the one before it.** Any behaviour change
   lands its Lean change first (constitution 2.0.0). A story whose Lean is
   not settled is not started; the design ticket that settles it comes
   immediately before it in the order.
5. **Assurance does not gate.** Mutation censuses, inventories, gate wiring
   and audits of the settled tree move to a milestone "M1 assurance" and are
   planned after the product runs.
6. **Capacity.** One product lane, sequential, plus at most one independent
   lane for pipeline, docs or tooling. `claude` stays barred below the desk;
   ticket owners are `codex`, commit owners `glm` or `grok`, auditors `grok`
   or `codex`.

## The order

### A — unblock the pipeline and land what is already in hand

| # | ticket | what ships | state |
|---|---|---|---|
| A1 | #422 | release pipeline green: close stale #311, cut 0.4.1 from today's `main`, release PR auto-merges from now on | not started |
| A2 | #387 / PR 390 | the Lean-name gate repair; unmasks thirteen theorems with no simulator coverage | gate green, rebased, one step from merge |
| A3 | #408 / PR 441 | registry Lean carries ruling 12, six theorems proved, driver repaired | pushed today, unaudited; needs an independent Lean audit then rebase |
| A4 | #332 / PR 420 | design note 003, the record | draft |
| A5 | #418 / PR 419 | checkpoint story clarity | draft |
| A6 | #377 / PR 428 | stories N1–N11 promoted in the simulator | draft, candidate unpushed |
| A7 | #382 / PR 385 | devnet smoke no longer races the validity interval; every devnet story below boots through it | draft |
| A8 | #279 / PR 425 | preprod checkpoint inventory before cutover | gate green, GREEN commit withheld |

Each of A2–A8 is one merge and one release. A3 first needs its audit.

### B — slim `main` (#319 as three PRs)

| # | ticket | what ships |
|---|---|---|
| B1 | #334 | the enforcement economy deleted, `convict_predicate` lifted first; `ckeri` still registers, advances, closes on the current checkpoint |
| B2 | #335 | the M1.2 skeleton deleted, MPF dependency and proof-check recipe kept |
| B3 | #336 | the size table of the survivors published; this is the discharge of the 158 % size finding and nothing else discharges it |

### C — the proven security fix

| # | ticket | what ships |
|---|---|---|
| C1 | #291 (was #320) | INV-BIND on the slimmed tree: the submitter can no longer choose which event type the checkpoint reads |

### D — the stories, one ticket each, vertical

Each row is one new ticket that replaces the layered ones named in its last
column. Each ships validator + `ckeri` + devnet replay + docs page, and
releases.

| # | story | what a user can do after the release | Lean prerequisite | replaces |
|---|---|---|---|---|
| D1 | 1, 12 | register once through the registry with datum V2; a stale re-registration is refused | Singular consolidation of `Cage.lean` (#408 row 7, undecided) | #339 #348 #351(part) |
| D2 | 2, 14 | a hunter lands a rotation and is paid from the pool; two hunters race, one wins | — | #344 #351(advance) #352(part) |
| D3 | 3, 4 | freeze when the pool is short; the owner unfreezes | — | #345 |
| D4 | 13 | anyone tops up the pool | — | #346 |
| D5 | 5, 10 | close by the next keys, also under attack; the registry leaf records it | #358 (reap authorization, signed intent) | #342 #350(close) |
| D6 | 7 | poison by the current quorum, cleared by rotation | — | #341 |
| D7 | 8 | move the refund address: bond options and the signed intent | — | #340 |
| D8 | 6 | reopen through the registry with a later witnessed rotation | #437 (dormancy) | #349 |
| D9 | 9 | convict on a duplicity proof, terminal | #438 (concrete duplicity predicate) | #347 #350(convict) |
| D10 | 11 | a consumer contract reads the checkpoint with the fail-closed verdict | #439 | #343 |
| D11 | 15 | forget; follower, indexer and query endpoint on V2 | — | #353 |
| D12 | all | the fifteen story trees replayed end to end on a devnet as one suite | — | #354 #326 |

### E — preprod and 0.5.0

| # | ticket | what ships |
|---|---|---|
| E1 | #356 | the family and the registry store deployed on preprod, manifests reissued, the operator's identities migrated |
| E2 | #357 | `ckeri` 0.5.0 whose release notes are the fifteen stories; the stories replayed on preprod is the acceptance |

Docs (#327 / #355) are not a phase: every D ticket carries its page.

## What leaves M1

**To "M1 assurance"** (gates nothing, planned after E2): #337 parity oracle,
#338 and #321 budget spike, #410 Lean inventory, #362, #424, #184, #185,
#135, #275, #183, #409 and its design children #411–#416 except those named
as prerequisites above, #435.

**Out of M1** (later layers of the roadmap): #404, #405, #406 GLEIF
sponsorship; #162 relayer; #220 hear a rotation; #166 stranger run (its
substance is E2's acceptance).

**Superseded, to close:** epics #318–#328 once this plan is the roadmap;
#329, #330 in favour of #381, which stays as the upstream index with no lane;
#226, #227, #229, #238 (datum V2 removes the surface they describe).

**Small fixes to the shipped `ckeri`, land early as independent-lane tickets,
each releasing:** #231 error surfacing, #237 list with duplicate checkpoints,
#239 checkpoint on a closed AID.

## Decisions needed

1. Release mechanics: auto-merge the planner's release PR (recommended, one
   ticket) or replace the planner with tag-on-merge.
2. Re-cut #339–#353 into the twelve story tickets D1–D12, filing new and
   closing the layered ones.
3. Singular as registry authority: a Lean ticket importing Singular's Lean
   as the cage before D1, or consolidate later and let D1 build on the
   current `Cage.lean`.
4. The assurance list, the out-of-M1 list, and the four superseded bug
   tickets.
5. Capacity: one product lane plus one independent lane.
