# cardano-keri project session map

Swept 2026-09-02.

## Project owner

```text
session       0-projects
window        cardano-keri
pane          %254
role          project-orchestrator
family        claude (Fable 5.1 since the 2026-09-02 restart)
cwd           /code/cardano-keri
runtime       /tmp/projects/cardano-keri/owner
brief         /tmp/projects/cardano-keri/owner/brief.md
brief sha256  78a7a18f82a717511f740e71323c1d53f3f5d486a36fe589bae70e4e570117a1
ledger        /tmp/projects/cardano-keri/owner/STATUS.md
handoffs      /tmp/projects/cardano-keri/owner/handoffs/  (AUDIT-M1-RETURN lives here)
resume        this branch's .projects/cardano-keri/resume.md
```

Predecessor seats, all dead: `%6429` then `%32` (session `projects`, runtime
`/tmp/projects/cardano-keri` top level, journal terminal 2026-08-24), and the
2026-08-31 to 2026-09-02 context of `%254` itself, lost at a Claude Code
restart on 2026-09-02 after it recorded `MILESTONE-RETIRED 11`. The pane
survived; the conversation did not. The journal is complete across the gap.

## M1.2 / GitHub milestone 11 — RETIRED, session pending retirement

```text
session       keri-m12
window        m12-desk
pane          %103
role          milestone-orchestrator (retired)
family        claude
runtime       /tmp/keri/m12   (durable record; keep; archive after COMPLETE)
state         PAUSED by operator 2026-09-01 end of day; NOTE-003 retirement
              note in inbox, unread; no wake source armed
head          0cfc9c28 on docs/300-projection-fidelity-requirements, clean
```

Lane window `t307-mpf-proof` carries `%104` (codex-raw, idle), `%132` (grok,
parked), `%124` (pi/glm, parked). Ticket #307 is merged; the panes are
leftovers. Retire the session through the machine owner after the desk records
`COMPLETE` on NOTE-003 or the operator waives it.

## M1 — resumption planned; two lanes without a desk

```text
lean          feat/m1-return-lean-machine at 8b7a14d, PR #313 draft, worktree
              /code/cardano-keri-m1-return-lean
simulator     campaign-2 Fable commit owner, pane %391 in 0-projects:2 (below the
              project owner), parked after submission 2 (935af75); worktree
              /code/cardano-keri-m1-simulator on feat/m1-simulator,
              root /tmp/projects/cardano-keri/owner/commit-owner-simulator-fable-2,
              launch `claude --dangerously-skip-permissions --model 'claude-fable-5-1' --effort high`
auditors      none live; six roots archived under owner/.archived (codex, codex-2-died,
              codex-3, codex-4-contract-blocked, codex-5, codex-6); the audit worktree
              /code/cardano-keri-m1-simulator-audit4 (detached 935af75) is retirable
other         %388 (claude, /code/cardano-wallet) sits in this window's right column,
              placed by another actor on 2026-09-02; not this desk's child
retired       GLM commit owner %366 (root archived, uncommitted diff saved) and
              claude auditor %373 (root archived) — 2026-09-02 14:06Z; the GLM
              worktree /code/cardano-keri-m1-return-sim (feat/m1-return-simulator@52526d2)
              and /code/cardano-keri-m1-return-sim-audit (detached d7f0e86) still exist
```

### previously

To be founded after the operator rules on the plan's A1–A8. Runtime root to be
created fresh (not `/tmp/ms-keri-1`, which is the custodial-terminal record and
stays untouched).

## M8 — parked

No desk, no session. Runtime `/tmp/ms-keri-8` preserved. Release requires a
session restoration first.

## Worktrees worth knowing

- `/code/cardano-keri-291` on `feat/291-inv-bind` at `30cab01` — the proven
  INV-BIND repair, **unpushed**.
- `/code/cardano-keri-162-relayer` — relayer spec and tests only.
- `/tmp/keri-sweep{,2,3,4}` — ledger sweep worktrees on `sweep-2026083*`,
  `sweep-20260901`, `sweep-20260902`; all clean; removable once pushed.
- Some twenty M1.2 lane worktrees (`/code/cardano-keri-ms11-*`,
  `-220-*`, `-289-*`, `-307-*`) — the M1.2 desk's and epic lanes' to archive;
  not this seat's.

2026-09-03: the operator drives the campaign-2 seat %391 directly (UX redesign,
scenario trees, a shared skill simulate-lean-state-machine drafted in
llm-settings); the seat publishes its own versions under NOTE-002 (push
authority on feat/m1-simulator only); this desk issues it no instructions
except answers and passive notes on request.

2026-09-03 14:30Z: PR #317 (the operator's registry, stacked on feat/m1-simulator)
and PR #315 are ready for review; the seat's branch received a parent docs
commit (a87365f), the seat told to pull --rebase before its next push.

2026-09-03 16:40Z: session keri-m12 killed (orch %102, M1.2 desk %103, t307 seats
%104/%132/%124), runtime archived at /tmp/keri/.archived/m12. This desk (%254)
pauses for the night; no child panes live. Worktrees of this desk's work all
removed; the operator's /code/cardano-keri-issue-316 (feat/registry-simulator,
merged) remains theirs. Tomorrow's M1 desk lives in a new session the operator
names.
