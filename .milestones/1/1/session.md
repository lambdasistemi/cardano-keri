# tmux session `keri` — resurrection manual

Snapshot reconciled **2026-08-07T11:35Z** (post-#181 housekeeping: keri:2 renamed cardano-keri-e274-t272-constitution — e171 holds the SEATS, epic #274 owns the TICKET, #181 campaign seats retired; e156 in keri:3 as e156-t257-query-layer + parked t220 window; per-window authority lives in resume/ fragments, which are CURRENT for both epics). Previous reconciliation 2026-08-05T14:10Z, at the desk succession
(`%5237` → `%5511`). Every pane below was measured with
`tmux list-panes -a` at 13:58Z and re-checked at 14:05Z, not copied forward.
Window INDICES shift when windows close; bind to window NAMES and pane IDs.

**Standing hazard:** a pane's live argv and its effective model can disagree —
models get switched at runtime, and `~/.claude/settings.json` pins
`claude-fable-5[1m]` as the default for BARE `claude` launches. Never respawn a
seat from observed argv; use the pinned lines below, which state intent.

## window `cardano-keri-ms1-identity-core` (milestone desk, singleton)

- Pane `%5511` (pid 3487682), role `milestone-orchestrator`, **claude-fable-5**
  (context cleared and reseated by the operator 2026-08-06T~12:20Z; previously
  Opus 5 xhigh — same pane, no succession). Succeeded `%5237` by operator order
  2026-08-05T14:00Z; there is exactly one desk.
- Respawn line (states intent, not argv):

  ```sh
  claude --dangerously-skip-permissions --model claude-fable-5
  ```

- Runtime `/tmp/ms-keri-1/`; `STATUS.md` is the desk journal.
- Resume: bare `/milestone-orchestrator` cold start — registry
  `/code/llm-settings/shared/milestones.md` → this repo's `milestones` branch
  → `.milestones/1/resume/ms.md`.
- Watchers — exactly one, re-arm on takeover, never duplicate:
  - `desk-decision-watch.sh` pid **3522854**, 120s, decision-only zero-model,
    `notify_target=%5511`; log `desk-decision-watch.log`. It self-exits when
    its target pane dies, so a successor kills it by exact PID and re-arms
    after editing `notify_target`.
  - No lane-watch and no worker monitor armed at succession.
  - **AT OMNIA PAUSA 2026-08-05T15:57Z: watcher STOPPED by exact PID, beat
    STOPPED, no monitors.** A resurrector re-arms exactly one of each on
    RELEASE from the machine owner, never before. Exempt machine-wide and not
    the desk's to touch: `machine-night-watch`, `machine-usage-notify`.
  - Pane `%5290` (e156 epic owner) was found squeezed to 19 columns, which broke
    pointer delivery; the desk resized it to 120 to deliver the pause order and
    left it usable. Layout ownership still belongs to that window.
  - AT OMNIA PAUSA 15:57Z: watcher STOPPED by exact PID, beat STOPPED. A
    resurrector re-arms exactly one of each on RELEASE, never before.
  - Pane `%5290` (e156 epic owner) was found squeezed to 19 columns, which
    broke pointer delivery; the desk resized it to 120 to deliver the pause
    order and left it usable. Layout ownership is still that window's.
- **Second pane `%5510`** (bash, `~`) exists in this window at succession —
  unattributed, believed the operator's own shell. The singleton rule wants
  one pane; the desk does not close a pane it did not open. Ask the operator.

## window `cardano-keri-e171-indexer` (epic #171 + #181, MERGED 14:03Z)

- Epic owner `%5189` (pid 2248626), Claude, effective Opus 5 [1m]. ALIVE.
  Its own fragment is authoritative for everything inside:
  `/code/cardano-keri-e171-indexer/.orch/window-brief.md`.
- Runtime `/tmp/ms-keri-1/e171/`. It merged keri:2 and keri:4 into ONE quadrant
  at 14:03Z after two ticket owners died unseen in the split layout: `%5189`
  top-left, ticket owner `%5513` below, Codex commit owner `%5493` right column.
  keri:4 no longer exists.
- Desk supervises ONLY `%5189`; #181 and everything under it is the epic's.

## the #181 lane (inside the merged window above)

- Slice-2C Codex commit owner `%5493` (pid 2503683), the slice-2C Codex commit
  owner: `codex-raw --dangerously-bypass-approvals-and-sandbox -C
  /code/cardano-keri-181-txpath -c model_reasoning_effort=xhigh`. Live,
  mid-repair of submission-1 audit findings.
- Ticket owner RESEATED as RUN 3: pane `%5513`, `claude --dangerously-skip-permissions --model sonnet`, cwd `/code/cardano-keri-181-txpath`, STARTed 14:04Z, appending to the EXISTING root; brief `BRIEF-RESEAT-RUN3-2026-08-05.md`. It inherits gate v11 `fcdd46f2`, candidate `efb2d30b`, the 13:42Z FINDINGS verdict, and the load-bearing fact that the one repair for submission 1 is SPENT — what `%5493` hands up next is SUBMISSION 2 and needs a NEW fresh auditor.
- The predecessor ticket-owner pane `%5445` was GONE (verified: `tmux display-message
  -t %5445` fails; no claude process holds a `/code/cardano-keri-181-txpath`
  cwd). Auditor `%5505` is also gone, which is contract-correct — it reports
  and exits. Reseating the ticket owner is e171's job, as **run 3** into the
  EXISTING root `/tmp/ms-keri-1/e171/cardano-keri-181/` (run 2's
  `BRIEF-RESEAT-2026-08-05.md` is the precedent). Never restart the ticket.
- Worktree `/code/cardano-keri-181-txpath`, branch `feat/181-no-cardano-cli`,
  PR #221. Authority: e171's fragment + that root's `STATUS.md`.

## window `cardano-keri-e156-t257-query-layer (was t220-hear-rotation; t220 parked in its own window)` (epic #156, PARKED)

- Epic owner `%5290` (pid 2809526), Claude opus-5 high. Parked, not dead —
  its pane reads "wait for the desk to unpark at #240".
- Also present: `%5313` (Claude, `/code/cardano-keri-220-verify`). `%5312` and
  `%5302` (the parked ticket-220 Codex owner) VANISHED between 13:58Z and 14:10Z,
  in the same sweep of pane closures as `%5237` and `%5445` — believed operator
  housekeeping, not measured. Low cost: #220 is out of M1 and its state is
  durable (`RESUME.md`, signed unpushed WIP `74def116`). Runtime `/tmp/ms-keri-1/e156/`;
  durable epic map `e156/epic-map.md`; canonical handoff
  `e156/ticket-220/RESUME.md`.
- Parked by desk SERIALIZATION, not by any pause. Unparks for **#240**.
  #220 itself is OUT of M1 (first post-M1 item).
- FRAGMENT DEBT: `.orch/window-brief.md` predates this lane's resurrection;
  the owner owes a republish at its next boundary. Resume meanwhile from
  STATUS + epic-map + `answers/A-005-*`.

## parked / archived — do not recreate

- `cardano-keri-ms1-t219-advance-symmetry`: window CLOSED 2026-08-04 after a
  clean park; #219 is DONE (PR #222 merged). Root `/tmp/ms-keri-1/t219/` is the
  durable record. Phase 2 plumbing + the preprod cutover get a FRESH seat when
  their turn comes — do not resurrect the old pane.
- Release-hardening #186: lane-less until every other required M1 outcome is
  merged; bootstrap evidence `.archived/bootstrap-release-hardening/`.
- #196: DONE (v0.2.0); root `.archived/t196-v020-accepted/`. No window.
- #168, merge-policy lanes: complete, archived.
- `.archived/desk-scratch-2026-08-03/`: strays from the pre-reset desk context.
- Eight older e171 worktrees remain retirement debt at epic close.
