# Session map — M1, tmux session `keri`

Swept 2026-09-04 from the live pane table (`tmux list-panes -a`), not from any
agent's self-report. Where a lane's own fragment disagreed with the live table,
the live table is recorded and the disagreement is named.

A stranger with tmux and git rebuilds the session from this file alone.

---

## keri:7 — `cardano-keri-ms1-identity-core` — THE DESK (singleton)

Milestone owner. One pane, always. Never grows panes; never touches the epic or
ticket windows below.

    pane:     %459
    cwd:      /code/cardano-keri            (main worktree, read-only in practice)
    runtime:  /tmp/ms-keri-1
    ledger:   this directory, on the `milestones` orphan branch
    launch:   claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high
    resume:   paste a pointer to .milestones/1/resume/ms.md

Note: the epic seat's STATUS records this desk as `%458`. It is `%459`.

---

## keri:1 — `cardano-keri-e367-t-unknown-lean-audit` — epic #367 owner

Epic owner for "Lean FULL close-out". Two panes.

    pane:     %449   (the seat)
    pane:     %451   (idle bash; the seat's own fragment calls this %450)
    cwd:      /code/cardano-wallet (detached)     <-- WRONG REPO for this lane
    runtime:  /tmp/epic-367
    fragment: /code/cardano-keri/.orch/window-brief.md
    launch:   muse-spark-1.3-contributor on the Pi/opencode-go harness
              (`pi/muse` in llm-settings, added 2026-09-04 as 22f2674)

    !! UNRESOLVED: `muse` is not in the standing authoritative set
       (claude, codex, grok, glm) and no rule or skill authorizes it for an
       orchestrator seat. Put to the operator 2026-09-04; the seat has not
       been disturbed and its children are correctly seated. If the operator
       declines the family, reseat this window as:
         claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high
       in cwd /code/cardano-keri, and re-point it at /tmp/epic-367.

---

## The #367 child lanes — ticket owners, one window each

All five are `codex` ticket owners in their own worktrees, all cut from
`main@9b2e6b8`, none pushed and none with a PR as of this sweep. Launch shape
for every one of them:

    codex --dangerously-bypass-approvals-and-sandbox -C <worktree> \
      -m gpt-5.6-sol -c model_reasoning_effort=medium

(`codex-raw` is not installed on this host; the project seat recorded the same
substitution on 2026-09-02.)

| Window | Name | Pane | Issue | Worktree | Branch | Runtime |
|---|---|---|---|---|---|---|
| keri:3 | `cardano-keri-e367-t363-checkpoint-inv` | %453 | #363 | `/code/cardano-keri-363` | `issue-363-checkpoint-inversions` | `/tmp/epic-367/to-363` |
| keri:4 | `cardano-keri-e367-t364-registry-inv` | %454 | #364 | `/code/cardano-keri-364` | `issue-364-registry-inversions` | `/tmp/epic-367/to-364` |
| keri:5 | `cardano-keri-e367-t365-atoms-mutants` | %455 | #365 | `/code/cardano-keri-365` | `issue-365-semantic-atoms` | `/tmp/epic-367/to-365` |
| keri:6 | `cardano-keri-e367-t366-lifecycle-report` | %456 | #366 | `/code/cardano-keri-366` | `issue-366-lifecycle-report` | `/tmp/epic-367/to-366` |
| keri:8 | `cardano-keri-e367-t368-audit-report` | %460 | #368 | `/code/cardano-keri-368` | `issue-368-audit-report` | `/tmp/epic-367/to-368` |

Resume each by pointing it at `<runtime>/brief.md` and requiring `START`.
Ordering: #363 and #364 are parallel-safe on disjoint boundaries; #365 waits on
both; #366 waits on #365; #368 is the serial tail.

**These are the epic owner's children, not the desk's.** The desk never
prompts, answers, or recovers them — if one is stuck, the symptom the desk acts
on is the epic owner failing to report or resolve it.

---

## keri:10 — `cardano-keri-e326-t-unknown-stories-acceptance` — epic #326 owner

Epic owner for K8, the fifteen stories as the acceptance suite. One pane at
seating; it builds its own lane below itself.

    pane:     %481
    cwd:      /code/cardano-keri
    runtime:  /tmp/ms-keri-1/epic-326
    launch:   muse --approve
              (/code/llm-settings/pi/muse -> pi --provider opencode-go
               --model muse-spark-1.3-contributor --thinking xhigh --approve)
    resume:   paste a pointer to /tmp/ms-keri-1/epic-326/brief.md and require
              START mode=EPIC-OWNER epic=326
    family:   muse, by explicit operator ruling 2026-09-04, THIS SEAT ONLY.
              Not precedent for keri:1 (Q-001) or any seat it dispatches.

---

## keri:2 — `bash` — unassigned

    pane: %452, cwd /code/cardano-keri. No role, no runtime. Setup residue.

---

## Not in this session

- The **project owner** for cardano-keri lives in session `0-projects`, window
  `cardano-keri`, pane `%254`, runtime `/tmp/projects/cardano-keri/owner`.
  It is this desk's parent. Its ledger is `.projects/cardano-keri/` on this
  same `milestones` branch.
- M1.2's session `keri-m12` was killed 2026-09-03; runtime archived at
  `/tmp/keri/.archived/m12`.
- M8 (Blaster) has no live session; runtime `/tmp/ms-keri-8` preserved.

## Host facts that die with the host

Every `/tmp` path above is lost on reboot. This file, on the remote, is the
only thing that is not. Worktrees under `/code/` survive a reboot; the 30+
worktrees listed by `git worktree list` in `/code/cardano-keri` include many
from retired lines and are not all M1's.
