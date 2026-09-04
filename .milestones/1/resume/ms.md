# Resume brief — M1 milestone owner

**State: ACTIVE.** You are resuming a live milestone with one seated epic lane.
This file replaces the TERMINAL NO-GO handover of 2026-08-18; read
`ledger.md` for why, and for the six caveats from that record which are still
in force.

## You are

Milestone owner, worker `ms-keri-1`, milestone 1 of
`lambdasistemi/cardano-keri`. Desk: tmux `keri:7`,
`cardano-keri-ms1-identity-core`, **one pane, always**. Runtime
`/tmp/ms-keri-1`. Parent: the cardano-keri project owner in session
`0-projects`, window `cardano-keri`, pane `%254`.

Skill chain: `orchestrator-contract`, `milestone-orchestrator`,
`tmux-orchestrator`, `worker-protocol`, `verification`, `invariants`.

## Read in this order

1. `ledger.md` — the outcome test, the adoption ruling, the state table, the
   priority order with its reasons, the parked decisions, the live risks.
2. `registry.md` — eight contracts, six of them `enforced: NONE`.
3. `session.md` — every window, pane, worktree, runtime and launch line.
4. `.projects/cardano-keri/resume.md` on this branch — your parent's record.
   Its last entry is 2026-09-04 13:45Z and it does **not** know about epic
   #367, which was seated after it.

## What is in flight

Two lanes. **Epic #326** (K8, stories as the acceptance suite), seat `%481`
in `keri:10`, runtime `/tmp/ms-keri-1/epic-326`, family **`muse` by explicit
operator ruling of 2026-09-04 for that seat only** — not precedent for any
other seat, and expressly not for the #367 seat in Q-001. Children #375 (first:
it owns the shared grammar), then #374 and #376.

And **epic #367**, Lean FULL close-out, seat `%449` in `keri:1`,
runtime `/tmp/epic-367`, five codex ticket owners in `keri:3`–`keri:6` and
`keri:8`. Base `main@9b2e6b8`. No branches pushed, no PRs.

Supervise it through `/tmp/epic-367/STATUS.md` and the epic's own artifacts —
**read the artifacts every period, not the events**. Its children are its own;
never address them.

## The three things waiting on the operator

1. **The epic seat's family.** `%449` runs `muse-spark-1.3-contributor` on the
   Pi harness — not in the standing authoritative set, no authorizing ruling
   anywhere in llm-settings. Reseat line is in `session.md`.
2. **`feat/291-inv-bind` at `30cab01` is single-copy on this host's disk**,
   21 days after it was first flagged. One branch push fixes it. It is the
   project owner's queued action 4.
3. **Plan v2 acceptance**, and design questions 3–7 one at a time, question 4
   (validity) first.

## Exact next action

Answer whichever of the three the operator settles; otherwise supervise #367
to completion before opening a second lane. The queue after #367 is: #355 docs
(codex, partial at `c6692c0` on `docs/355-m1-return`), then #362 denominators,
then #336 the size table, then #358 after the registry's cut, #361
opportunistically.

## Discipline that cost something to learn

- Every STATUS line goes through
  `/code/llm-settings/shared/skills/worker-protocol/scripts/status-event`.
  A predecessor's hand-typed timestamps landed an hour in the future.
- Verify a mutation applied before trusting its result.
- Do not put your own bookkeeping to the operator as a question.
- Capture an exit code before piping it; `| head` returns 141 and hides the
  verdict.
- The registry file `/code/llm-settings/shared/milestones.md` has been
  corrupted twice by scripted edits. Gate every edit of it on a post-edit
  check that you have watched fail. One is in this seat's STATUS.
- Fable is reserved for design-critical seats; normal work goes to opus,
  sonnet, glm or grok.

## Boundaries inherited from the project seat

Withheld: merge of #306, closure of #300, S3 and any preprod read or write,
surface-C issue mutations, mainnet, production rollout, announcement, external
commitment, delegation/credentials, product claims. The experiment-claims
policy governs every external word. No agent touches
`aiken-lang/merkle-patricia-forestry`.

**Hard constraint, non-negotiable:** `meetings/veridian-amaru/` must never
enter the public repo, in history or in tree. Backup at
`/home/paolino/cardano-keri-meetings-private/`. Issue/PR numbers #1–#52 and
milestones M1–M5 were recreated preserving numbers exactly; that numbering is
load-bearing.
