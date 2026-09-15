# Session map — M1, tmux session `keri`

Rewritten 2026-09-14T12:00Z by the resurrecting desk. The previous `keri`
session died that morning with every lane in it; this map records what exists
now and the exact launch line that brings each parked lane back. **Only the
desk is live.** Every other block is a parked lane whose process is dead and
whose runtime root, worktree and resume fragment are intact.

Every seat below milestone is drawn from `codex`, `grok`, `muse`, `glm`.
`claude` is barred from all of them by operator ruling; `muse` and `glm` never
audit; `glm` is commit-owner only; `grok` is pinned to `grok-4.6`. `codex-raw`
is an interactive alias and does not exist in a pane command; launch `codex`.
Verify every launcher with `command -v` in a non-interactive shell first.

---

## keri:1 — `cardano-keri-ms1-identity-core` — THE DESK (singleton, LIVE)

    cwd:      /code/cardano-mpfs-onchain (launched there; scope is cardano-keri)
    root:     /tmp/ms-keri-1
    pane:     %1156
    launch:   claude --dangerously-skip-permissions --model claude-fable-5-1
    resume:   paste resume/ms.md

---

## keri:2 — `cardano-keri-ms1-t-unknown-singular-lean` — ticket-singular-lean, PAUSED 2026-09-15T17:23Z

    ticket owner:  pane %1546, codex gpt-6-astra high, cwd /code/cardano-keri
                   launch: codex --dangerously-bypass-approvals-and-sandbox \
                             -C /code/cardano-keri -m gpt-6-astra \
                             -c model_reasoning_effort=high
    root:          /tmp/ms-keri-1/ticket-singular-lean
    START:         2026-09-15T11:12:35Z
    holds:         #408 DONE (main@0e638fa). Slice 1 = #446 / PR #447, candidate
                   0bf9bcd green locally, audit not launched; glm %1582 and
                   grok %1584 write-idle in the same window. Slice 2 (muse)
                   waits for the operator dormant ruling
    resume:        paste brief.md, then its STATUS tail

---

## ticket-387 — `cardano-keri-ms1-t387-name-truncation` — RELEASED, seat dead

PR #390 rebased, gate v9 green on `fbb851e`, pushed draft. Remaining: mark
ready, guard-merge, delete branch, report `MERGED pr=390 merge=<sha>`.

    ticket owner:  codex, cwd /code/cardano-keri-issue-387
                   launch: codex --dangerously-bypass-approvals-and-sandbox \
                             -C /code/cardano-keri-issue-387 \
                             -c model_reasoning_effort=high
    root:          /tmp/ms-keri-1/ticket-387   (journal ends 11:32:45Z PUSHED)
    authority:     NOTE-012 (content-bound merge authorization)
    resume:        the lane's STATUS tail plus NOTE-012; .orch/resume.md there
                   is stale (says BLOCKED on Q-001)

---

## epic-lean-invariants — `cardano-keri-e-lean-invariants-plan` — PAUSED, desk-owned

Stood down by `NOTE-011`; the desk owns the Lean work directly. #408 is at
PR #441 head `27a7732` (four commits of 2026-09-14), claims complete, unaudited.

    epic owner:  codex high, cwd /code/cardano-keri   (dead; relaunch only on
                 an explicit release; pin model and effort explicitly — its
                 last identity could not be self-reported)
    root:        /tmp/ms-keri-1/epic-lean-invariants   (LIVING-STATE.md there
                 is the epic-owned living state; predates the four commits)
    worktree:    /code/cardano-keri-issue-408  fix/408-registry-lifecycle

---

## epic-318 — `cardano-keri-e318-t332-the-record` — PAUSED

    epic owner:  codex high, cwd /code/cardano-keri
                 launch: codex --dangerously-bypass-approvals-and-sandbox \
                           -C /code/cardano-keri -c model_reasoning_effort=high
    root:        /tmp/ms-keri-1/epic-318
    holds:       #318 (#332 PR #420 draft; #333) then #319 (PR #423 draft,
                 deletion held under the constitution); #418 PR #419 draft
    wake:        explicit desk release naming it

## epic-326 — `cardano-keri-e326-t377-n1-n11` — PAUSED

    epic owner:  muse --approve, cwd /code/cardano-keri
    root:        /tmp/ms-keri-1/epic-326 ; ticket-377 PR #428 draft,
                 candidate f779345 local-unpushed preserved
    wake:        explicit desk release naming 326

## ticket-382 — `cardano-keri-ms1-t382-devnet-race` — PAUSED

    ticket owner: codex high, cwd /code/cardano-keri-issue-382 (PR #385 draft,
                  head 21e9473); root /tmp/ms-keri-1/ticket-382; resume file
                  named in its last PAUSED line (sha256 f3196ab1…)
    wake:         explicit desk release naming it

## ticket-279 — preprod inventory — PAUSED

    root /tmp/ms-keri-1/ticket-279; PR #425 draft, head 0847e87, gate green,
    GREEN commit deliberately not made. Wake: explicit release naming ticket279.

---

## Retired, evidence preserved (`/tmp/ms-keri-1/.retired-workers`)

ticket-355, epic-367, ticket-383 (accepted, PR #386), ticket-400 (partial,
PR #402; issue open for SDK/deployment gaps).

## Host facts that die with the host

Runtime roots under `/tmp/ms-keri-1/`; worktrees `/code/cardano-keri-<issue>-<slug>`.
