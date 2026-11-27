# tmux session `cardano-keri-M1` — how to reopen it (state 2026-11-25 20:35 UTC, PAUSED)

Runtime root of the milestone: `/home/paolino/.orch-runtime/cardano-keri/m1` (called `$R` below). Each team has a
folder there with `brief.md`, `STATUS.md` (journal), `inbox/`, `questions/`, `answers/`, `handoffs/resume.md` and
`.pane`. Staffing and exact launchers: `$R/rulings/staffing-2026-11-24.md`. Every launcher is prefixed with
`env TMPDIR=/code/.lanes-tmp/keri-m1/<seat>`.

## Desk (window 1, pane %240)
Claude Fable 5.2. Reopen: `claude --dangerously-skip-permissions --model claude-fable-5-2`, then `/milestone-orchestrator`.
Read `$R/handoffs/decisions-while-away.md` (the tail first) and the last 60 lines of `$R/STATUS.md`. The desk watches
its children with the harness Monitor over `wait-channels $R 590`, re-armed every thirty minutes.

## Ticket owners (Codex gpt-6.2-astra, effort medium)
Launcher: `codex --remote unix:// --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri -m gpt-6.2-astra -c model_reasoning_effort=medium`
Resume paste for each: "Read <root>/brief.md, <root>/handoffs/resume.md, the last sixty lines of <root>/STATUS.md and
the unread files in <root>/inbox and <root>/answers; continue." Deliver every file with `send-pointer`: these seats
do not reliably wait on their channels.
- `register-351` (pane %526, root `$R/register-351`): ticket #546 (commands through Koios), then #559 builders, #558.
- `commitment-534` (pane %527, root `$R/commitment-534`): validators of #559 on `feat/559-validator-booking`, #534.
- `follower-353` (pane %534, root `$R/follower-353`): remaining slices of #353; #555 from 10 December.
Each owner launches its own writer (Claude Sonnet 5.5 high) and auditor (Codex gpt-6.2-sol high) per slice.

## Lean writer (Codex gpt-6.2-astra, effort high, no auditor)
- `lean-569` (pane %570, root `$R/lean-569`, worktree `/code/cardano-keri-569-lean-model-binds`, branch
  `feat/569-lean-model-binds`): ticket #569. Launcher as above with `-C <worktree>` and `model_reasoning_effort=high`.
  A seat that fills its context stops with `COMPLETE capacity-limit` and a resume record; start a fresh one on the
  same root with a start note like `$R/lean-569/inbox/START-20261124-successor.md`.

## Tracker clean-up seat (pane %432, Codex gpt-6.2-astra, root `$R/tracker-cleanup`)
Interactive, for the operator; woken by `send-pointer`.

## Sparring seats while the operator is away
`$R/handoffs/decision-audit.sh <NNN> <slug> <question> <answer> <context> not-delivered` (next 057) audits a desk
answer; `$R/handoffs/decision-answer.sh <NNN> <slug> <question> <context>` (next 013) prepares an analysis for the
operator. Each seat is retired when its verdict is consumed.

## Not this desk's
The Singular desk: session `singular-M1`, pane %510, runtime `/home/paolino/.orch-runtime/singular/m1`.
