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

Slice-owned (driver+navigator):

- `specs/68-keystate-shape/identity-model.md`  (**whole file**: intro, §3, §7a, §7b,
  §7c, §8 cascade, §10 open-threads — whole-document consistency, not only the new
  section)
- `specs/68-keystate-shape/system-architecture.md`  (**whole file**: §0, §1, §2, §3,
  §6, §9 — the selection must not leave any section asserting the obsolete premise)
- `specs/91-genesis-registration/accept.sh`  (the RED-first acceptance check)

Forbidden for every actor in this ticket: anything under `onchain/`, `offchain/`,
`spikes/`, `cabal.project`, any `*.ak`/`*.hs`, any dependency manifest or hash, and
any other `specs/*/` directory (siblings). No CESR parser, no adjudicator code.

## Slice breakdown

One coherent decision → **one bisect-safe slice**. The two design docs and the
acceptance check move together because the decision must be internally consistent
across both docs at every commit (the gate's `accept.sh` asserts both).

### Slice 1 — the genesis/registration decision record (driver+navigator)

- **RED.** Author `specs/91-genesis-registration/accept.sh` asserting the FR1–FR9
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
  `Tasks: T911, T912, T913, T914`.

The decision content the driver must land is fully specified in `spec.md`
(Decision + Clarifications) and enumerated in `tasks.md`; the driver adapts wording
to the surrounding doc voice but must not re-open the decision or reintroduce the
obsolete premise.

**What actually executed in Slice 1 (recorded):** three RED-review rounds
(Q-001 coverage → Q-002 guard-regex correctness → spot-checked non-invertible) and
**three GREEN review passes with two blocking objections** (initial GREEN → Q-003
block; pass 2 → Q-004 block; pass 3 → approval/commit). The navigator's
whole-document review (Q-003, Q-004) found
stale premises **outside** the new §7c that contradicted the selection; reconciling
them was an **in-scope whole-file consistency fix** (identity-model §3/§7b + the
intro/§8/§10; system-architecture §0/§1/§2 + the §9 heading), not scope expansion —
the owned files are the whole documents. Slice committed at `8babc57` with
`accept.sh` grown to 66 assertions + a positive/negative spot-check.

### Slice 2 — NOTE-008 canonical-doc consistency correction (driver+navigator)

Epic-owner final audit (NOTE-008) found residual decision-consistency contradictions
in the same two owned files. Re-opened as a bisect-safe correction slice, RED→GREEN,
fresh navigator approval + `NAVIGATOR-VERIFIED`:

- `system-architecture.md`: §0 exclude identity R-KEL from the closure Merkle-mirror
  framing; §3 reclassify/separate the R-KEL on-chain checkpoint from the
  "Proof-builder-anchored" (watcher-consensus/falsifiable) family and clarify its
  relation to R-ID **without** selecting #92 storage; scope the R-MAP AID note to the
  current tiers (≤1-chunk on-chain / >1-chunk residual oracle mapping).
- `identity-model.md`: §3 qualify "there is nothing to trust" → no **additional**
  watcher/oracle trust for **post-genesis advances**; genesis projection stays
  attester-trusted (§7a/§7c).
- Strengthen `accept.sh` to lock these (no unqualified "nothing to trust"; R-KEL not
  under the watcher-mirror family; R-MAP AID note tier-scoped).

These are decision-consistency corrections, **not** a #92 storage-layout decision or
scope expansion.

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
