# Plan — #91 genesis & registration decision record

## Nature of the work

Design-decision ticket. No build/test toolchain runs; the "tech stack" is
Markdown design docs plus a POSIX-shell acceptance check. The gate is doc hygiene
+ the mechanical decision-acceptance check (`gate.sh`, already added).

Because the deliverable is a **decision-acceptance change**, it is driven RED→GREEN
by a visible driver+navigator pair (per the ticket brief), not written by the
orchestrator. The orchestrator owns only the ticket-local spec/plan/tasks, gate.sh,
and PR/issue metadata.

## Owned-file set (whole ticket)

Orchestrator-owned (this and adjacent commits):

- `specs/91-genesis-registration/spec.md`
- `specs/91-genesis-registration/plan.md`
- `specs/91-genesis-registration/tasks.md`
- `gate.sh` (add / extend / drop)
- PR #95 body, issue #91 metadata (via `gh`, not files)

Slice-owned (driver+navigator, Slice 1):

- `specs/68-keystate-shape/identity-model.md`  (§ intro, §7a, §7c, §8 cascade, §10 open-threads 3)
- `specs/68-keystate-shape/system-architecture.md`  (§6, §9 decisions 1 & 2, §3 R-KEL note)
- `specs/91-genesis-registration/accept.sh`  (the RED-first acceptance check)

Forbidden for every actor in this ticket: anything under `onchain/`, `offchain/`,
`spikes/`, `cabal.project`, any `*.ak`/`*.hs`, any dependency manifest or hash, and
any other `specs/*/` directory (siblings). No CESR parser, no adjudicator code.

## Slice breakdown

One coherent decision → **one bisect-safe slice**. The two design docs and the
acceptance check move together because the decision must be internally consistent
across both docs at every commit (the gate's `accept.sh` asserts both).

### Slice 1 — the genesis/registration decision record (driver+navigator)

- **RED.** Author `specs/91-genesis-registration/accept.sh` asserting the FR1–FR6
  content markers (see tasks). Demonstrate it **fails** against the current
  (pre-decision) `identity-model.md` / `system-architecture.md`, and log the RED
  in `WIP.md`.
- **GREEN.** Amend `identity-model.md` (§ intro line, §7a, new §7c, §8 cascade,
  §10 open-thread 3) and `system-architecture.md` (§3 R-KEL note, §6, §9 decisions
  1 & 2) to the full hybrid decision: both axes; NOTE-003/NOTE-004 boundaries;
  **decision 1** (oracle-gated registration / permissionless challenge) and
  **decision 2** (MPFS-with-oracle); the **teeth state machine** (bonds, windows,
  tier rule, false-challenge forfeiture, adjudication timeout); the **signed
  registration package** shape; the **evidence/integration separation** (cage
  confinement as a required #24/#92 invariant, #99 Modify N not a genesis bound);
  the trust enumeration; the #92/#68/#24 consequences. `accept.sh` and `./gate.sh`
  pass. All decision shapes are pre-specified in `spec.md`; the driver must not
  re-open them or invent new ones.
- **One commit.** Subject `docs(identity-model): select hybrid genesis — crypto
  byte binding + attested/challengeable projection (§7c)`; body carries
  `Tasks: T91-S1`.

The decision content the driver must land is fully specified in `spec.md`
(Decision + Clarifications) and enumerated in `tasks.md`; the driver adapts wording
to the surrounding doc voice but must not re-open the decision or reintroduce the
obsolete premise.

## Orchestrator-owned finalization (post-slice)

- Extend/verify `gate.sh` already invokes `accept.sh` (it does, tolerant-then-strict).
- Update PR #95 body + issue #91 to drop the obsolete premise and link #97/#99.
- Finalization audit → drop `gate.sh` (`chore: drop gate.sh (ready for review)`).
- `gh pr ready 95`. Do **not** merge — the epic owner performs guarded merge.

## Visible execution team (pre-slice repair)

Before dispatching Slice 1, repair the two bottom panes (driver `%1291`, navigator
`%1293`) which currently point at the deleted #99 worktree: clear/respawn both into
`/code/cardano-keri-issue-91` retaining canonical slots (Opus 4.8 high driver;
GPT-5.6-sol high navigator), load `tmux-orchestrator` + `pair-programming` in their
briefs, verify the quadrant. No extra agents.

## Risks / notes

- The decision re-introduces a **trusted adjudicator** for projection challenges
  (NOTE-004 remedy b). That is an explicit, named trust assumption — surfaced in
  STATUS early so the epic owner can redirect to remedy (c) (no automated slashing)
  before mark-ready if preferred.
- `accept.sh` must forbid the phrase "objectively provable on-chain" (and close
  variants) adjacent to projection / >1-chunk binding, per NOTE-004.
