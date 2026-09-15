# Resume — M1 milestone owner

Status **ACTIVE**, lanes **PAUSED** by operator order of 2026-09-11 except where
named below. Desk `keri:1` `cardano-keri-ms1-identity-core`, pane `%1156`,
runtime `/tmp/ms-keri-1`. Home repo `lambdasistemi/cardano-keri`, GitHub
milestone 1, 84 open / 75 closed. Written 2026-09-14T12:00Z by the seat that
resurrected the desk after the previous `keri` session (desk `%459`) was
killed between 11:33Z and 11:43Z that day.

    launch: claude --dangerously-skip-permissions --model claude-fable-5-1
    cwd:    /code/cardano-keri

## What happened on 2026-09-14 before this seat existed

The previous desk, with the operator present, did three things and swept none
of them into the ledger:

1. **Released ticket-387** (`NOTE-012`, 11:01Z): rebase PR #390 onto
   `8021ff9`, rerun the gate, apply the two content tests, guard-merge. The
   lane rebased (4 commits, 0 conflicts), test 1 PASS (patch byte-identical to
   the audited `4c4890d`), gate v9 PASS on head `fbb851e` (27 min), pushed at
   11:32Z with `draft=true`. **It died before marking ready and merging.** PR
   #390 is MERGEABLE/CLEAN, 21 checks green. One mechanical step remains and
   it belongs to a ticket-387 seat, not to the desk.
2. **Released then withdrew the Lean lane** (`NOTE-010` 11:00Z, `NOTE-011`
   11:02Z): operator ruling that the Lean work is finished at the desk with
   the operator, and that its shape becomes *importing the Singular Lean as
   the registry authority*. The epic journaled `PAUSED`+`COMPLETE`; its child
   `ticket-408-repair-2` paused with no edits.
3. **Committed and pushed #408** at 11:14–11:20Z, four commits on
   `fix/408-registry-lifecycle` (`17008c4`, `0a2db18`, `8e911ea`, `27a7732`),
   PR #441 head `27a7732`, 21 checks green, BEHIND `main`. The obligation
   record claims: the six formerly-`sorry` claims proved with `CollectAxioms`
   showing no `sorryAx`; both libraries build with no `sorry` warnings; the
   trace driver repaired; five mutants all red at target. **Singular is not
   imported** — the record's row 7 (`Cage.lean` consolidation against
   Singular) is marked *undecided*, with Singular's Lean measured as building
   clean on the pinned 4.27 toolchain with no external dependencies.

These are the previous desk's claims, verified by nobody independent. Under
the constitution and `code-the-design`, #408 needs the frozen-and-falsified
actual-interface gate and an independent completeness/inversion inspection
before acceptance; none of that has run.

## 2026-09-15 update

Released by the operator for one task only; `ticket-singular-lean` (keri:2,
%1546) runs it. Answer its Q-files within the turn they arrive. Everything
else below is still owed.

## Outstanding at the desk, in order

- **Ask the operator two things** (asked in the first report of this seat):
  whether the Singular-import direction of `NOTE-011` still stands or the
  `Registry.lean` repair in PR #441 supersedes it; and which lanes, if any,
  are released from the 2026-09-11 pause.
- **Finish #390**: re-seat a ticket-387 owner (codex, in
  `/code/cardano-keri-issue-387`, root `/tmp/ms-keri-1/ticket-387`) with the
  single task *mark ready, guard-merge, delete branch, report MERGED*. The
  content-bound merge authorization of `NOTE-012` stands.
- **#408 acceptance path**: an independent Lean audit of PR #441 at `27a7732`
  (alternate family; `claude` barred), then rebase onto `main`. Not before
  the operator answers the direction question.
- Then the landing order the previous desk fixed: `#390 → #418 → #377`, the
  story-record correction parked on #390, the #318 record behind it, #319
  behind #318.
- **Record repair owed**: three `ticket-410` sub-lanes never journaled a
  terminal event (two empty journals). Bookkeeping only.
- The three operator escalations and five plan-lane rulings listed in the
  2026-09-11 sections remain open.

## Fences in force

`claude` is barred from every seat below milestone. Merge authorization is
this desk's to give and the owning lane's to execute (moved from the project
owner on 2026-09-11). No PR or issue comments, no reviewer pings. Operator
reporting is user stories in plain language, no internal epic codes.

## Read next

`ledger.md` from its last dated section upward, then `session.md`, then
`registry.md` — its `enforced: NONE` entries are each a scheduled incident.
