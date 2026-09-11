# Session map — M1, tmux session `keri`

Rewritten 2026-09-11 by the desk seat, from the live session rather than from
fragments: the previous map still described epic #367 (closed on the 7th) and
window numbers that no longer exist.

A stranger with tmux and git rebuilds this session from the blocks below. Each
launch line is exact and copy-pasteable. **`codex-raw` is an interactive shell
alias and does not exist in a non-interactive shell — the binary is `codex`,
and a pane launched with `codex-raw` dies instantly and takes its window with
it.** That cost one dispatch today.

Every seat below milestone is drawn from `codex`, `grok`, `muse`, `glm`.
`claude` is barred from all of them by operator ruling; `muse` and `glm` never
audit; `glm` is commit-owner only; `grok` is pinned to `grok-4.6`.

---

## keri:1 — `cardano-keri-ms1-identity-core` — THE DESK (singleton)

The milestone owner. One window, one pane, no quadrant: this seat has no code,
no pairs and no slices, and empty seats would invite work that must not happen
here.

    cwd:      /code/cardano-keri
    root:     /tmp/ms-keri-1
    pane:     %459
    launch:   claude --dangerously-skip-permissions --model 'claude-opus-5[1m]'
    resume:   paste resume/ms.md

The `[1m]` pin is deliberate here and **nowhere below** — supervising seats
launch at the standard pin so compaction bounds their cost.

---

## keri:2 — `cardano-keri-e326-t377-n1-n11` — epic #326, acceptance suite

Epic #326 is the fifteen stories as the acceptance suite. It sits **last** in
the M1 order and depends on off-chain work that does not exist yet, so this
lane finishes the harness it already holds and starts nothing new.

    epic owner:    pane %481, muse   (harness=pi provider=opencode-go
                   model=muse-spark-1.3-contributor effort=xhigh)
                   cwd /code/cardano-keri
                   launch: muse --approve
    ticket owner:  pane %746, codex gpt-6-astra medium
                   cwd /code/cardano-keri-377-stories
                   launch: codex --dangerously-bypass-approvals-and-sandbox \
                             -C /code/cardano-keri-377-stories \
                             -c model_reasoning_effort=medium
    roots:         /tmp/ms-keri-1/epic-326 , .../epic-326/ticket-377
    in flight:     PR #379 (draft) — headless simulator backend, issue #374
    resume:        resume/e326.md
    owed:          a current fragment for ticket-377

---

## keri:3 — `cardano-keri-ms1-t382-devnet-race` — ticket #382, standalone

The devnet validity-interval race. Critical-path infrastructure: every
end-to-end epic downstream boots a devnet through this path. Three failures
were observed submitted 1, 14 and 15 slots after `invalidHereafter`.

    ticket owner:  pane %708, codex gpt-5.6-sol high, cwd /code/cardano-keri
    auditor:       pane %784, grok-4.6 high
    commit owner:  pane %742, muse, cwd /code/cardano-keri-issue-382
    root:          /tmp/ms-keri-1/ticket-382
    worktree:      /code/cardano-keri-issue-382 (fix/382-withdevnet-validity-race)
    in flight:     PR #385 (draft)
    contract:      A-008 governs this lane's audit — the auditor's fresh route
                   is the five semantic rows only; the integration receipt is
                   retained evidence, labelled retained; two hash-bound
                   controls (read-only checkout, network disabled) must be RED
                   then GREEN before any auditor is commissioned; one launch
                   attempt remains (4/5).
    owed:          a resume fragment

---

## keri:4 — `cardano-keri-ms1-t387-name-truncation` — ticket #387, standalone

Two tools truncate qualified Lean names and both compare by count instead of
identity. `CheckpointGoals.lean` declares thirteen dotted theorems and the
scenario gate's `/^theorem\s+([A-Za-z0-9_']+)/` captures `Step` thirteen times.
The mainline gate stays red until this lands, so every Lean and simulator
change downstream is blocked behind it.

    ticket owner:  pane %791, codex gpt-5.6-sol high, cwd /code/cardano-keri
    auditor:       pane %811, grok-4.6 high
    root:          /tmp/ms-keri-1/ticket-387
    in flight:     PR #390 (draft), branch fix/387-qualified-lean-names
    ruling:        the proof-only identity class is derived, not listed; and
                   the truncation **masked a real coverage gap** — thirteen
                   inversion theorems have no simulator coverage at all.
    owed:          a resume fragment

---

## keri:5 — `claude` — NOT THIS DESK'S

A Claude/Fable seat idle at a prompt in `/code/cardano-keri`, the main
checkout, with no worker root, no brief and a `/model` command typed into it by
hand. Left alive on the 2026-09-11 cleanup sweep and flagged to the operator:
an unowned expensive idle seat is exactly what a cleanup kills, and an
operator's own pane is exactly what it must not.

---

## keri:6 — `cardano-keri-e318-t332-the-record` — epic #318, then #319

**The head of the M1 arc, and the most important lane in the milestone.** #319
depends on #318, and #320, #321, #322, #323, #324, #325, #326, #327 and #328
all depend on #319. Nothing downstream moves while this lane is idle.

    epic owner:  pane %923, codex high, cwd /code/cardano-keri
                 launch: codex --dangerously-bypass-approvals-and-sandbox \
                           -C /code/cardano-keri -c model_reasoning_effort=high
    root:        /tmp/ms-keri-1/epic-318
    START:       2026-09-11T14:02:03Z
    holds:       #318 (children #332 design note 003, #333 clarity record into
                 the Lean doc comments) and then #319 (children #334 delete the
                 enforcement economy, #335 delete the M1.2 skeleton, #336 the
                 size table of the survivors)
    acceptance:  #318 — the note, the Lean and the simulator name the same
                 rulings; that is an identity check across three artifacts, not
                 three separately plausible documents.
                 #319 — `just ci`, `mkdocs --strict` and lychee green, plus the
                 published size table.
    sequencing:  #319 is held until this desk accepts #318 and hands it over.

---

## keri:7 — `cardano-keri-e-lean-invariants-plan` — the plan epic

Owns `docs/design/lean-invariants-plan.md` (PR #407, `main@5a35284`), which had
no epic. Files one, then drives it.

    epic owner:  pane %924, codex high, cwd /code/cardano-keri
                 launch: codex --dangerously-bypass-approvals-and-sandbox \
                           -C /code/cardano-keri -c model_reasoning_effort=high
    root:        /tmp/ms-keri-1/epic-lean-invariants
    START:       2026-09-11T14:04:05Z
    task one:    file the M1 epic and one child per **M1** slice — six of the
                 plan's nine. TEL/credential composition, delegated extension
                 and per-lane completeness review are M2 and M7 and stay there.
    task two:    split #391 — ordinary KEL history to M1, credential consumers
                 staying M2, delegated supersession to M7.
    owns:        registry entry `conviction-matches-keri-duplicity`,
                 `enforced: NONE` — the tip-only conviction escape.
    blocked on:  the Coverage-and-baseline slice starts with #318, so no ticket
                 owner for it before this desk accepts #318. Filing is not
                 blocked and started immediately.

---

## Retired, evidence preserved

Both recorded in `/tmp/ms-keri-1/.retired-workers`.

- **ticket-383** — accepted. PR #386 merged, issue #383 closed, window killed
  on the 2026-09-11 sweep. Worktree `/code/cardano-keri-383` preserved clean.
- **ticket-400** — partial. PR #402 merged `96854b7`; the offered-interface
  catalogue is live at `https://lambdasistemi.github.io/cardano-keri/offered-api/`,
  32 operations, all 24 source downloads hash-matching the merged commit.
  Issue #400 stays OPEN for the concrete SDK and deployment gaps.
- **epic #367** — closed 2026-09-07; its lane and its `resume/e367.md` are gone.

---

## Host facts that die with the host

Runtime roots live under `/tmp/ms-keri-1/<worker-id>/` and do not survive a
reboot; worktrees live at `/code/cardano-keri-<issue>-<slug>`. This ledger is
the only thing that must not die, which is why it lives on the `milestones`
orphan branch of the home repo and nowhere else.
