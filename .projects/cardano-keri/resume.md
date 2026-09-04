# Resume — cardano-keri project owner

## Identity

Pane `%254`, session `0-projects`, window `cardano-keri`, runtime
`/tmp/projects/cardano-keri/owner`. Ledger: that runtime's `STATUS.md`, then
this directory. The predecessor journal at `/tmp/projects/cardano-keri/STATUS.md`
(terminal 2026-08-24T14:38:12Z) is inherited, not superseded.

Journal caveat: the events stamped `2026-09-02T09:00:00Z` to `09:30:00Z` were
hand-typed and written before 07:54Z; their order is true, their clock is not.
Events after `08:23:17Z START` on that day are `status-event` stamped.

## State — 2026-09-02, mid-morning

- **M1.2 is RETIRED** (D-021, operator ruling "I am killing M1.2 and going back
  to M1"). Outcome preserved in `ledger.md`. The desk `%103` in `keri-m12` is
  paused by operator instruction and holds `NOTE-003-milestone-retired.md` in
  its inbox, unread. The session is **not yet retired**: worktrees unarchived,
  `t307` panes parked, no machine-owner request sent.
- **M1 line resumption is PLANNED, not founded.** The operator asked for an
  audit of the checkpoint + poison + no-interactions design and a plan of
  changes to `main`. Both are delivered:
  `AUDIT-M1-RETURN` — `/tmp/projects/cardano-keri/owner/handoffs/M1-RETURN-audit-and-plan-2026-09-02.md`
  (sha256 `c7c8813f…83da2`), published at
  https://claude.ai/code/artifact/c49a4833-5415-42c8-8aad-bd9796139a79 .
  It rests on eight stated assumptions A1–A8. The operator overturned A3 the
  same morning (poison is local to the current keys, cleared by rotation);
  A4 accepted as D-022 (two edges, no rollback; poisoned keys can only be
  rotated, so A5 is withdrawn); A1 accepted as D-023 (both edges require the
  quorum). Then D-024: the operator named the duplication blocker in 2.7 and ruled
  unicity by mint with queued inceptions — an AID registry; A5 reinstated for
  unicity, A9 juvenility and A10 registry shape added. Then D-025 and D-026: no replay; close withdraws the bond; the only
  resurrection is a witnessed rotation; unbonded is not consumable and inert
  to current-key theft. Then D-027, a direction: validity and refresh, fields reserved now. Then
  D-028: pause and close are two edges; A12 (pause keeps the bond) inferred and
  flagged. Then D-029, a direction: freeze/seize (recommended out) and the
  smoking gun (recommended as proof-based poison). Follow-up: pay for advance
  instead of freeze (A7 reopened for the premium); convict invariants T12/T13
  stated; D-030: conviction is FINAL (no KERI event clears duplicity), Convicted is
  terminal, refund_to committed at register. Then poisoned-cannot-pause (D-028 amended) and A15 (bond destination at
  close). Then D-031: freeze gone, conviction seizes the bond in full. Then D-032: close
  pays the current refund_to, established at rotation. Then D-033: pause is a
  rotation that withdraws the bond; two edges. Then D-034: the hunter economy (pool, freeze bond, conviction bond) after a
  misread of mine was corrected. Before the Lean model: A11 and the D-034
  open details. Open: A2, A6, A8, A9 (the value of W), A10, A11.
- M1 GitHub milestone 1 is still **closed** with the 2026-08-17 record/cursor
  description; M8 parked (D-013); milestone 12 registered on a premise the
  plan says must be re-scoped.
- `main` at `6902e33`. Open PRs: #311 (release 0.4.1), #306, #305, #290, #251.

## State — 2026-09-02, afternoon

- Rulings D-022 to D-034 taken in conversation and recorded in `decisions.md`.
- **Phase 0.2 is done**: the checkpoint machine and 45 theorems on
  `feat/m1-return-lean-machine`, draft PR #313, no sorry, standard axioms,
  eight guard mutants red for the right reason.
- The stories page (the shipped design as user stories) is published for the
  operator and the simulator: artifact a0134dfd.
- The GLM commit owner (pane `%366`, root `owner/commit-owner-simulator-glm`)
  recorded `COMPLETE` at 13:27Z: four commits `1b442bd`..`d7f0e86` on
  `feat/m1-return-simulator`, 22 files inside its fence. Verified by this seat:
  node --check, build, scenario gate, trace gate all exit 0; the trace gate was
  proven able to fail by this seat's own probe (the seat's record lacked that
  red); browser `?selftest=1` 15/15 PASS plus the embedded Lean corpus PASS.
- **A fresh claude auditor is running**: pane `%373`, root
  `owner/commit-auditor-simulator-grok` (name kept after the grok launch showed
  a 0% weekly limit and was killed before any pointer), detached worktree
  `/code/cardano-keri-m1-return-sim-audit` at `d7f0e86`, launch
  `claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high`,
  `START` at 13:33Z; verdict expected as `AUDIT-COMPLETE verdict=PASS|FINDINGS`
  then `COMPLETE`, watched by a persistent Monitor task.
- On the operator's "publish it in preview-pr": commit `52526d2` copies the
  built page to `docs/simulator/index.html` with a nav entry (mkdocs strict
  green locally), branch pushed, **draft PR #314** opened stacked on #313.
  Preview: https://preview.dev.plutimus.com/lambdasistemi/cardano-keri/pr-314/simulator/
  (the Docs workflow's PR-preview job publishes it and comments the URL).

## State — 2026-09-02, 14:10Z

- The claude auditor of `d7f0e86` returned **FINDINGS** (3 S1: fractional
  inputs accepted, the story picker dead, evidence ✕ throws; 7 S2: gates blind
  to the DOM under a Proxy stub, `pool = P` boundary uncovered with two
  surviving money-path mutants, five refusal reasons unasserted, applied-only
  corpus, actor check cannot fail, no clock in free play, two story checks
  uncovered; 5 S3; CI-1..5 proposed) while establishing exact transcription
  over 2 760 records. Report archived at
  `owner/.archived/commit-auditor-simulator-grok/handoffs/FINDINGS.md`.
- The operator then ruled, in sequence: take over the simulator coding, make
  it great; base it on the Lean theorems; use graphics like the Reactivegas
  simulator; send another Fable worker to do it; on a fresh worktree with no
  GLM prework; "so we see how much the lean is clear". The GLM seat was stood
  down (root archived, its uncommitted round-1 diff saved as a patch), and a
  **Fable commit owner** is building the simulator from scratch: pane `%375`,
  root `owner/commit-owner-simulator-fable`, worktree
  `/code/cardano-keri-m1-simulator`, branch `feat/m1-simulator` cut from the
  Lean branch at `8b7a14d`, launch
  `claude --dangerously-skip-permissions --model 'claude-fable-5-1' --effort high`,
  `START` 14:08:53Z. Its brief names the Lean as the sole specification of the
  machine and requires `LEAN-CLARITY.md`: the record of where the Lean did not
  suffice, which is the operator's measurement.
- The GLM branch `feat/m1-return-simulator` and draft PR #314 (with the live
  preview) are untouched pending the operator's disposition; expected: close
  #314 when the Fable page is previewed.

## State — 2026-09-02, 14:55Z

- **The Fable worker recorded `COMPLETE` at `e196774`** (14:46Z, 37 minutes
  after `START`): six commits, 26 files, all inside its fence. Verified by
  this seat: the four Node gates and `mkdocs build --strict` exit 0; page,
  docs copy and served site byte-identical; eight negative controls red before
  green in its journal; every named control operated in a real browser on the
  preview (picker, slot control, story playback to Frozen, verdict chips,
  chart, ledger, evidence rows).
- Pushed as `feat/m1-simulator`, **draft PR #315** stacked on #313; preview
  live: https://preview.dev.plutimus.com/lambdasistemi/cardano-keri/pr-315/simulator/
- **A fresh codex auditor is running**: pane `%378`, root
  `owner/commit-auditor-simulator-codex`, detached worktree
  `/code/cardano-keri-m1-simulator-audit` at `e196774`, launch
  `codex --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri-m1-simulator-audit -m gpt-5.6-sol -c model_reasoning_effort=high`
  (`codex-raw` is not installed on this host), `START` 14:50Z (pane
  re-acked as `%378` after an ambient-focus mis-report). Verdict expected as
  `AUDIT-COMPLETE verdict=PASS|FINDINGS` then `COMPLETE`.
- **The experiment's result, `LEAN-CLARITY.md` (17 entries)**, read and
  journaled: the transcription of `stepFn` and `consumableState` needed
  nothing outside the Lean (507 applied and 3521 refused grid cells agree on
  the first comparison). Needed from outside: names for refusals (`stepFn`
  returns `none`), the values of `P` and `W` (guessed 2 and 10), the cast and
  addresses, evidence-only story steps, the rule for when a theorem counts as
  "exhibited". Lean gaps: `consumableState` is a `Prop` with no `Decidable`
  or Bool mirror, so its executable twins are unproved against it; `Params`
  carries proofs so `ToJson` is hand-written; T11 and T13 do not exist (this
  seat's brief said T1–T16). Stories the Lean overrules: 9 (B and pool to the
  refund address is fixed), 5 and 7 (poison and close are enabled from a
  paused checkpoint under the current quorum; close from paused pays zero and
  burns the AID), the frozen row (keep and withdraw rotations enabled), 4
  (deposit brings bonds only; pool by top-up), 14 (no UTxO), 15 (validity).
- **Design finding for the operator, not yet ruled**: close by the current
  quorum is terminal and mint-once forbids re-registration, so a thief holding
  the current keys can burn Alice's Cardano presence before she poisons; from
  a paused checkpoint the burn pays nothing. The Lean is consistent; the
  question is whether close should answer to the next keys.

## State — 2026-09-02, 18:00Z

- **Simulator campaigns.** Campaign 1 (Fable seat, root archived
  `commit-owner-simulator-fable`): `e196774` audited FINDINGS (6), repaired
  to `6cfc2ad`, audited FINDINGS (3) — terminated at the cap. Campaign 2
  (re-cut, fresh Fable seat `commit-owner-simulator-fable-2`, pane `%391`
  parked): `81f0a25` audited FINDINGS (2), repaired to `935af75`, audited
  FINDINGS (1) — terminated at the cap. Six auditor seats in all (roots under
  `owner/.archived/`: codex, codex-2-died, codex-3, codex-4-contract-blocked
  for a mislabelled submission, codex-5, codex-6). Branch `feat/m1-simulator`
  at `935af75` pushed, draft PR #315 stacked on #313, preview live.
- **The residue** is one item: the scenario gate deduplicates reconciliation
  rows by story-clause text, so two atoms from the same phrase (story 15's
  `dreg = D` and `b = B`) share one identity and deleting either stays green.
  Everything else passed in the last audit: the exact-Nat boundary at every
  entry point, the reading of "datum untouched" judged faithful to the Lean,
  campaign-1 invariants, cold trace gate. Decision pending with the operator:
  accept with the residual recorded, or a one-item re-cut (campaign 3, fresh
  seat, fresh auditor).
- **Design rulings taken in the same session**: D-038 (2026-09-03, every non-keep bond option signed by the new keys, from the simulator's escalation Q-001), D-036 (close needs the next
  keys; close is not final without a conviction, so the AID can be replayed;
  the registry leaf is the tombstone) and D-037 (the registry is MPFS made
  permissionless and convenient). Open: where the MPFS modification lives
  (keri-specific cage in cardano-keri vs a permissionless mode upstream in
  cardano-mpfs-onchain); then questions 3–7 of the "what is left" list
  (parameters, validity, poison encoding, receipts at GLEIF scale, the
  checks outside the Lean).
- `LEAN-CLARITY.md` (523 lines, in the fable-2 root) is the measurement of
  the Lean; its headline stands: the transcription needed nothing outside
  the Lean, the outside sources are names, parameters, cast, evidence-only
  steps and the exhibit rule; the builder over-attributed two story clauses
  to the Lean, now reclassified.

## State — 2026-09-03, 11:45Z

- **The operator drives the campaign-2 seat (`%391`) directly** since 07:16Z:
  UX redesign (one scene, scenario trees, scrubber, glossary), the shared
  skill `simulate-lean-state-machine`, review fixes from the operator's own
  review file. The seat publishes itself (NOTE-002: push authority on
  `feat/m1-simulator` only); the preview follows every push. This desk sends
  it answers and notes only.
- **D-038** (every non-keep bond option signed by the new keys) came from the
  seat's escalation Q-001 and its sibling found by this desk (a zero-value
  deposit reset juvenility). **The second Lean slice** (D-036, D-037, D-038)
  is under way in the same seat with a widened fence: statements at
  `d7364cd` audited NOT-READY by a codex sol max statement auditor (57 rows
  witnessed and falsified, six statement findings), re-cut at `0aaf3dd` and
  audited READY-TO-PROVE (58 rows, no findings); NOTE-006 released the proofs
  at 11:42Z. The simulator already follows the stated Lean (refusals
  `intent-not-authorized`, `closed-needs-reopen`, `reopen-needs-closed`,
  `leaf-not-closed`; 95 story steps over 15 trunks and 14 forks).
- **Process rulings taken today**, all recorded in llm-settings on `main`:
  the statement auditor checks completeness never provability, and
  challenges vacuity with mutants and witnesses, under the `commit-auditor`
  discipline; the whole loop is the shared skill **`system-design`**; the
  simulator follows the stated Lean at once and proofs run alongside play;
  **llm-settings and infrastructure repositories are main-only** (no
  branches, PRs or leftover worktrees; 23 worktrees and 97 merged branches
  removed, the shared codex config repaired after it had blocked every codex
  launch for an hour).
- The registry is the operator's own work in progress ("when it's ready we
  will make it available"); the machine models only the leaf map.
- Open from the design pass: questions 3–7 (parameters, validity, poison
  encoding, receipts at GLEIF scale, the checks outside the Lean).

## State — 2026-09-03, 14:00Z

- **Slice 2 accepted at `a892832`** (campaign 3: `1bbb9d6` audited FINDINGS
  x6 by a codex sol max auditor with 56 mutants of its own; repaired to
  `a892832`: 62 theorems, no sorry, 31/31 mutants red, 62/62 checker rows,
  148/148 atom mutations; the repair audit's single S2 on the axiom receipt
  settled by the parent's clean rebuild — 43 propext, 18 propext+Quot.sound,
  1 axiom-free, no Classical.choice — and left as a one-line bookkeeping
  residual for the seat). The simulator follows on the preview.
- **The M1 plan v2** is published on the design page §3: one milestone
  across `cardano-keri` and `cardano-mpfs` (U1 permissionless batching, U2
  gating plugin, U3 registry model, in the operator's lane; K0–K10 in
  cardano-keri: record, slim main, INV-BIND, receipts spike, datum V2 and
  owner edges, hunter edges, registry integration, off-chain, the stories as
  the acceptance suite, docs, cutover), a dependency diagram, the
  measurements that size the numbers, the decisions that gate the plan.
  Pending the operator's acceptance; question 4 (validity) put first.
- The operator's own status text (design decision, the two simulators, the
  benefits Cardano gives KERI) was drafted on request; the operator posts it.

## State — 2026-09-03, 14:30Z

- **Surface C executed on the operator's instruction**: GitHub milestone 1
  reopened and retitled "M1 — Identity core: witnessed checkpoints on
  Cardano, with poison, bonds and a unique registry" with the plan-v2
  description; epics #318 K0, #319 K1, #320 K2, #321 K3, #322 K4, #323 K5,
  #324 K6, #325 K7, #326 K8, #327 K9, #328 K10, #329 U1 and #330 U2 (upstream
  tracking; the MPFS repositories are under cardano-foundation, so upstream
  issues are the operator's to open); a ticket for the Lean and simulator
  work under #318; PRs #313, #315, #317 ready for review; the two simulations
  at the top of `docs/index.md` and a Simulations nav section (a87365f on
  `feat/m1-simulator`). Still withheld: closing milestone 11, re-scoping 12,
  closing #300/#305/#306/#163, rewriting #274, amending #156/#166.
- The registry is PR #317 (the operator's): Lean `Registry.lean`, `Cage.lean`,
  `Samaritan.lean`, a registry simulator at `docs/simulator/registry/`, stacked
  on `feat/m1-simulator`; issue #316.

## State — 2026-09-03, 15:50Z

- **Second surface-C release executed** ("finish epics and ticket planning here
  and upstream, close dead milestones, reorganize issues"): milestones 11
  (M1.2) and 12 (M1.3) closed; #300 closed; old epics #274, #156, #171, #186
  and story #163 closed as superseded by the K-epics; #291, #162, #220, #166,
  #279, #183–#185, #226, #227, #135, #229, #231, #237–#239, #275 re-parented
  and moved to milestone 1; 26 child tickets #332–#357 under K0–K10, listed in
  order in each epic body. Upstream: the registry work already exists in
  cardano-foundation/cardano-mpfs-onchain as #98 (permissionless sweep) and
  #99 (plugin cages) with #100–#103; the tracking epics #329/#330 link them,
  their bodies carry a "consumed by cardano-keri M1" line, and #104 was added
  there for the leaf-map interface.
- **Merges** ("merge the work done today"): #313 merged into main (dc09605);
  #315 retargeted to main, updated from main by GitHub (head 0bb576c), checks
  re-running, merge follows; #317 next (retarget to main after #315).
- **Docs** ("make sure the rest of the docs on both repos are up to date"): a
  Fable docs seat on cardano-mpfs-onchain (root `commit-owner-docs-mpfs`,
  branch `docs/permissionless-registry-roadmap`, draft PR when done); the
  cardano-keri docs seat (#355, root `commit-owner-docs-keri`, brief ready)
  launches from main once #315 and #317 are in.
- The campaign-2 seat (`%391`, the operator's) is told the branch moved
  (NOTE-009 acked, NOTE-010 pending); after #315 merges its branch is history.

## State — 2026-09-03, 16:15Z

- **D-039 and D-040 taken** (see decisions.md): three registry states, one
  UTxO; the withdraw option gone; leaving is the reap; tickets #358 (the
  reap's authorization, after the registry's cut) and #359 (checkpoint slice
  3). The design page's machine block and diagrams say active / parked(hash)
  / convicted.
- **Merged**: #313 (dc09605) and #315 (b7bd115) into main; the public docs
  site serves the simulator and the "Play the design" home block. #317
  (the operator's registry) conflicted on mkdocs.yml after #315; this desk
  merged main into it (4c3d194: one Simulations nav section, both pages
  local), gates green, checks re-running; merge follows.
- **Docs**: cardano-mpfs-onchain PR #105 (opus seat, done: roadmap page,
  corrections of shipped behaviour verified against the validators, strict
  build 0) marked ready, its build check pending; the cardano-keri docs seat
  (#355, opus, pane `%426`) is rewriting from the survey.
- The campaign-2 Fable seat is closed by the operator; Fable is reserved for
  design-critical seats ("do not use Fable for normal work"; normal work on
  opus, sonnet, glm or grok).

## State — 2026-09-03, 16:40Z — PAUSED FOR THE NIGHT, on the operator's word

- **Merged today**: #313 (the checkpoint machine), #315 (the simulator and
  the second slice), #317 (the operator's registry model and simulator) —
  all on `main`; the public docs site serves both simulations from the home
  page. cardano-foundation/cardano-mpfs-onchain#105 (docs: shipped behaviour
  corrected, the permissionless-registries roadmap) merged 16:32Z.
- **The Fable slice-3 seat IS dispatched** (operator: "359 is done?" then "yep stop right after that"): pane `%429`, `START` 16:29Z, worktree `/code/cardano-keri-slice3` on `feat/359-checkpoint-slice-3` from main 430f0f2, root `owner/commit-owner-slice3-fable`. It writes the statements, journals `NOTE statements-ready sha=…` and parks; **tomorrow's desk dispatches the codex completeness audit** (witnesses and mutants, per `system-design`), then RESUMED for proofs, the simulator following, a fresh audit, publish. The codex docs seat for #355 comes after, on branch `docs/355-m1-return` (partial rewrite at `c6692c0`; the page list in `owner/.archived/commit-owner-docs-keri-partial/STATUS.md`).
- **The keri team session is cleaned**: tmux `keri-m12` killed, its runtime
  archived at `/tmp/keri/.archived/m12`, fourteen M1.2 and superseded
  worktrees removed (all clean), local-only `ms11/*` branches kept for the
  operator to delete, PR #314 closed as superseded, the register row for M1
  back to ACTIVE (desk to be founded tomorrow), M11's row noting the retired
  session.
- **Process rulings today**, all in llm-settings `main`: Fable only for
  design-critical seats, normal work on opus, sonnet, glm or grok; the
  `system-design` skill's publish step (a slice closes with the Lean merged,
  the simulation in the docs, the docs rewritten). Note: landing the dirty
  llm-settings tree under the main-only rule also landed another session's
  38-file `pr-workspace` skill draft and speckit edits (commit cdbed9c).

## State — 2026-09-04, 13:45Z

- **Slice 3 is merged** (PR #360 → `main` 9b2e6b8, accepted by the operator
  with one residual). The checkpoint machine is now D-036/D-038/D-039/D-040:
  three registry states with one UTxO (active / parked holding the hash /
  convicted), no withdraw, leaving is the reap by the next keys with the
  signed intent naming payee and refund address, deposit is the unfreeze.
  74 theorems, no sorry, clean-build axioms, 40/40 mutants; the simulator
  follows (104 story steps, 1534 trace steps, 70-row vacuity pass, template
  check); the docs carry the built page, both simulation links local, and
  four pages saying what ships versus the accepted design. D-041's story
  endings verified in a real browser.
- Three audits ran on it: statements NOT-READY then READY-TO-PROVE, the
  shipped slice FINDINGS (3 S2, all closed), the repair FINDINGS (2 S1, one
  defect in two runners). **The residual**: a gate that counts problems calls
  an empty run green — `lean/mutants/run.sh` prints `TOTAL 0/0` and the
  scenario gate's vacuity pass reports 0 rows, both exit 0. Filed as #362
  across all five gates with a control each, and folded into the shared
  `lean-simulations` skill.
- Open tickets from the design: #358 (the reap's authorization in the
  registry model, after its cut), #361 (registry story endings,
  opportunistic), #362 (denominators). The codex docs seat for #355 has not
  been dispatched; the partial rewrite is on `docs/355-m1-return` at
  `c6692c0`.

## Exact next action

0. **Next**: found the M1 desk in the session the operator names; seat the
   **codex** docs seat for #355 on `docs/355-m1-return` (the opus seat's page
   list is in `owner/.archived/commit-owner-docs-keri-partial/STATUS.md`);
   then #362 (denominators, any normal-work family), #358 after the
   registry's cut, #361 opportunistically; then the plan v2 acceptance and
   question 4 (validity), one question at a time. Fable only for
   design-critical slices.
1. **Read the operator's reaction to the plan.** Each of A1–A8 is theirs to
   overturn; anything overturned changes Phase 0's design note, so do not
   found a desk before that. If they accept, the first thing built is the
   record — DESIGN NOTE 003 and the Lean checkpoint lifecycle — before any
   code.
2. **Then found the M1 desk**: ask the machine owner for a session (or the
   re-use of `keri-m12` under a new name) and archive `/tmp/keri/m12` after
   the desk records `COMPLETE`; compile the desk brief from the plan through
   `context-compiler`; require `START`.
3. **Surface C, on release only**: reopen milestone 1 with the plan's
   description, close milestone 11, re-scope milestone 12, dispose of #305/#306/#300,
   close #163, rewrite #274, amend #156/#166.
4. **Push `feat/291-inv-bind`** (branch only) the moment the operator says
   yes to anything — the proven decoder repair exists on one disk.
5. **M8 at its revisit condition only** (D-013: first M1-line slice merged, or
   2026-09-30).

## Standing boundaries

Withheld by named barriers, unaffected by any pause release: merge of #306 and
closure of #300 (now to be closed under the plan, still on release); S3 and any
preprod read or write; surface-C issue mutations; mainnet, production rollout,
announcement, external commitment, delegation/credentials, product claims, the
external product gate. The experiment-claims policy governs every external
word. No agent touches `aiken-lang/merkle-patricia-forestry` (D-012 constraint,
now moot in the good direction under D-020).

## Hard constraint — inherited, non-negotiable

`meetings/veridian-amaru/` must never enter the public repo, in history or in
tree. Backup at `/home/paolino/cardano-keri-meetings-private/`. Issue and PR
numbers #1–#52 and milestones M1–M5 were recreated preserving numbers exactly;
that numbering is load-bearing.

## A note for whoever holds this seat next

Three lessons from 2026-09-01/02, all recorded against this seat. Verify a
mutation applied before trusting its result. Do not put your own bookkeeping to
the operator as a question. And use `status-event`, never a hand-typed
timestamp: the predecessor's last five events are stamped an hour into the
future, and the successor had to establish that from an `ls`.

The audit's method is worth keeping: three read-only surveys for breadth, then
every load-bearing line re-read in the source by this seat before it went into
the record. Nothing in the plan was relayed.
