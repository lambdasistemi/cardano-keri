# Resume — M1 milestone owner

Status **ACTIVE**. Desk `keri:1` `cardano-keri-ms1-identity-core`, pane `%459`,
runtime `/tmp/ms-keri-1`. Home repo `lambdasistemi/cardano-keri`, GitHub
milestone 1, 68 open / 65 closed. Written 2026-09-11T14:08Z.

    launch: claude --dangerously-skip-permissions --model 'claude-opus-5[1m]'
    cwd:    /code/cardano-keri

## Where the milestone stands

M1 is the base of a layered roadmap that is now explicit above it — M2 the
verification and authorization core (Layer 3), M3 the KERI-wallet ↔ Cardano
signing bridge (Layer 4), then M4 pilots, M5 case adapters, M6 live witnesses,
M7 delegated AIDs, and M1bis the GLEIF-scale proofs. **M1's own contents did
not change.** The eleven-epic arc #318–#328 stands as filed, and nothing
downstream of it is reachable until the identity core lands.

The pause is over. The operator's release, 2026-09-11: *"so clean up the
window and proceed with M1 work, upstream registry is progressing."*

## What this desk did on the 11th, and why

The finding was a priority inversion: the head of the arc was unstaffed while
four lanes worked on tooling and on the arc's tail. #319 is what nine other
epics wait behind, and it had no owner. Corrected in one sweep —

1. released the three lanes holding unlanded branches to land them, because
   each is one PR from terminal and each is a future conflict against #319's
   deletion;
2. opened `keri:6` on #318 → #319, one lane owning both in sequence;
3. opened `keri:7` on the Lean invariants plan, which the previous sweep had
   recorded as owed the moment the pause lifted;
4. retired ticket-383 (accepted) and ticket-400 (partial), evidence preserved.

## The live finding, and it is the important one

Within four minutes of starting, `keri:6` parked on a real divergence and was
right to. Ruling 12 / D-039 / D-040 removes pause, the parked state and the
grace window. The checkpoint machine adopted it through #359 on 2026-09-04.
**The registry machine never did**, and the registry-side slice was never
filed — #316 is CLOSED, and #358 is blocked on an artifact with no number.

Ruled in `epic-318/answers/A-001`: #318 is **not** held behind the repair. The
record is first in the order precisely so the code is brought to it, and
holding it would put the whole milestone behind an unfiled Lean change.
Instead #318's acceptance now reads: the note, the Lean and the simulator name
the same rulings, **and** every place the shipped model does not yet implement
a named ruling is recorded in the note as an open defect carrying its issue
number. The lane is authorized to file exactly that one issue and then return
to its fence.

The repair sequences as: new registry-slice-3 issue → #358 → #324. It is off
#318's critical path and **this desk owes it an implementer** — that is the
first outstanding action for whoever holds this seat next.

## Outstanding at the desk

- **Find an owner for the registry slice-3 repair** once `keri:6` reports its
  issue number. Upstream of #358 and #324; a Lean model change, so not the
  #324 integration lane's natural work.
- **Accept or reject #318**, then hand #319 to the same lane. Nine epics are
  behind that handover.
- **Route the three merges** as PRs #379, #385 and #390 come ready. Merge
  authorization is the project owner's, not this desk's — the lanes report
  `REVIEW-REQUESTED` and this desk routes. That fence exists because this desk
  merged #373 three minutes after an auditor wrote that merge was withheld.
- **`keri:5`** is an unowned idle Fable seat in the main checkout with a
  hand-typed `/model` in it. Flagged to the operator rather than killed.
- **Three escalations still with the operator**, from the #400 interface work:
  whether operations sign or hand back unsigned; whose job fetching KEL and TEL
  segments is; whether *freeze* survives the design churn.
- **Five rulings the operator owes the plan lane**: the cool-down value (a
  signing ceremony, not a block time); where `D_reg` goes on conviction; the
  cool-down at registration; the freeze during the cool-down; the datum's extra
  step.
- **#400 stays OPEN** for concrete SDK and deployment gaps despite PR #402
  having merged and the catalogue being live.

## Fences in force

`claude` is barred from every seat below milestone. Merge authorization is the
project owner's. No PR or issue comments, no reviewer pings — outward prose
waits for the operator. Operator-facing reporting is user stories in plain
language: no internal epic codes such as `K0`/`K4`, and no index-style reports.

## Read next

`ledger.md` from its last dated section upward, then `session.md` for the
seven windows and their exact launch lines, then `registry.md` — six of its
entries are `enforced: NONE` and each one is a scheduled incident.
