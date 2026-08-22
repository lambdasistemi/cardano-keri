# Resume — M1.2 milestone owner (SUCCESSION SNAPSHOT)

**Status: PARKED FOR SUCCESSION, 2026-08-18T18:42Z.** Incumbent pane `%6695`; appointed successor
pane `%6656`; operator ruling `08f50ecd…e72a5` via NOTE-018. **Supervision transfers; child work is
retained.** Nothing was killed, reset, moved or torn down.

## Successor: your exact next action

1. Read this snapshot and both lane journals (`/tmp/ms-keri-11/b-decoder/STATUS.md`,
   `/tmp/ms-keri-11/s2-witness/STATUS.md`) plus their resume fragments beside this file.
2. Relocate into session `keri-m12` and append `START` to `/tmp/ms-keri-11/STATUS.md`.
3. Arm supervision and append `SUPERVISION-ARMED` to the same file. Only then does the incumbent
   stop its bridge beat `b080xpvsi` and go write-idle.

Do **not** restart either lane. Both are parked on rulings, not stalled.

## Identity

Runtime `/tmp/ms-keri-11`; home repo `/code/cardano-keri`; ledger branch `milestones`, depth 1,
fresh root per write. Parent: cardano-keri project owner `%6429`.
Launch: `claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high`.
Load chain: `orchestrator-contract` → `milestone-orchestrator` → `context-compiler` →
`worker-protocol` → `tmux-orchestrator` → `invariants` → `verification`.

## Live lanes — RETAINED, do not disturb

**Surface B — `b-decoder`**, ticket owner pane `%6715`, Grok repair owner pane `%6720`,
worktree `/code/cardano-keri-ms11-b-decoder`, branch `ms11/b-decoder-land`,
runtime `/tmp/ms-keri-11/b-decoder`.
Candidate `f31c467ba9c9579864ab51c2dd36b931047ab1ac`, tree
`54f17e58bbf61fbc7d2b269f15d40e6f325ae56b`, **static-ready**. Frozen gate
`7037228b898d5f93ad4ef365ac1cdfe0780f1bf6229f0f325cb2cf25171ac5b1` **unchanged**. Builds **0/1**
unspent, **no auditor launched, nothing pushed**. Parked on Q-002 → project **Q-007**.
F1 coverage claimed (icp `{k,n,b}`, dip `{k,n,b}`, rot `{k,n,br,ba}`, drt `{k,n,br,ba}`) and
**unaudited**.

**S2 — `s2-witness`**, ticket owner pane `%6716`, commit owner pane `%6718`,
worktree `/code/cardano-keri-ms11-s2-witness`, branch `ms11/s2-witness-mode`,
runtime `/tmp/ms-keri-11/s2-witness`.
Provisional `9049f37929b2017666eb8fbb5a17f361d4fe8395`, tree
`879368df34272d1b34b961c9f84d2aeae3228538`. Submission **uncharged**, auditor **not dispatched**,
builds **0/3**. Parked on the **mechanized** boundary: frozen gate `s2w-v2`
(`4361d4bdede3772478defdea7543c097e1f6322fd3590294f227185b67efe5af`) whose contract RED is
`exit 42: surface-B-oracle-unavailable`. **Do not bypass or pre-fill that oracle.**

S2 resumes only when all four hold: Surface B auditor-clean and gate-green accepted SHA; landed on
`main`; that exact ancestry incorporated; gates and every byte-dependent baseline rerun on it.

## Open decisions — inherited, unanswered, and NOT to be invented

- **`Q-007`** (blocking Surface B) — extend the A-006 proof fence by exactly
  `onchain/lib/cardano_keri/checkpoint/registration_tests.ak`. Its `mis_dup_k_rejects` row pins
  `R4…DuplicateKey` while the authorized in-fence vector records `E4CurKeysMismatch`, and the local
  `parity` helper requires `recorded == pinned` — so the row is **statically false** and the gate's
  `just ci` leg reaches it. Without the extension the single authorized build is spent on a known
  wrong-reason failure. Recommendation filed: grant as an **extension of A-006**, not a new
  campaign, so the submission-2 count and no-third-attempt rule are unaffected.
- **`Q-003`** — commission or decline the control-observability consolidation.
- **`Q-005`** — whether the enforcing sibling guard belongs in the shared `ledger-sweep.sh`.
- **Surface C** — exact-payload acceptance, submission 2 `dbcd520e…`, dry run `bcdf6350…`,
  **nothing applied**.

## Standing rules the successor must carry

- **Two-token interlock:** acquire `/tmp/ms-keri-11/BUILD-TOKEN` then `/tmp/machine/BUILD-TOKEN`,
  write the six-field `holder` marker, release **host first then programme** via a trap that removes
  its own marker first. Attribution is reporting only; **only the machine owner may reclaim**.
- **Sibling guard:** `/tmp/ms-keri-11/tools/preserve-siblings-guard.sh` **must** exit 0 before any
  `milestones` push. It aborts; the old inline check only printed, and that cost M1's terminal
  record once. Refresh every non-`.milestones/11/` path from the fetched base before staging.
- **Evidence correction `EVIDENCE-CORRECTION-001`** (`d2f19779…`) is mandatory reading before citing
  M1's G0 decoder evidence. Never restate the `496/496` or `parity 0 mismatches` claims unqualified.
- Accept nothing by relay. Verify the exact final tree yourself, and **positive-control any diff
  check before believing a clean result**.

## Bridge

Incumbent beat `b080xpvsi` stays alive as a continuity bridge until the successor appends both
`START` and `SUPERVISION-ARMED`. The incumbent then stops it, appends
`BEAT-STOPPED-FOR-SUCCESSION`, and remains write-idle.

## Current (2026-08-19T06:10Z) — supersedes the flow above

Surface B is TERMINAL: A-017's one v8 full-ladder rehearsal (cluster 8/11)
failed 8/26 legs; Option 3 automatic. Escalation
`/tmp/projects/cardano-keri/inbox/NOTE-M12-cluster8-terminal-s2-without-b.md`
awaits the project owner's S2-without-B disposition — that answer is the next
desk event. Ticket owner %6740 (@4664) held write-idle until it lands;
rehearsal seat %6741 closing via machine owner. Candidate `7c78e5f2` and all
eight gate generations are immutable evidence. DESIGN-NOTE-001 +
HANDOFF-001 (design/) accepted; three registry contracts added enforced=NONE.
On resume: check the project inbox answer first, then b-recut6/questions,
then the monitors (bzpawvhgf lanes, b6ax5mt63 ledgers).

## Current (2026-08-19T09:00Z) — A-018 execution

A-018 (answers/A-018-…, sha aa296be7…) governs. Steps: (1) %6716 terminalize
handoff [pointed]; (2) machine builds fresh Opus TO (window …tS2-no-b, runtime
/tmp/ms-keri-11/s2-no-b) + docs lane (…t-docs-design-record) [asked]; (3) TO
authors+freezes s2w-no-b-v1, desk verifies before product write; (4) issue #300
DONE, docs lane lands DN-001 bytes at docs/design/record-cursor-projection-
fidelity.md; (5) witness slice → then four requirement slices, each gated+
audited. S2 COMPLETE only when slice+4 accepted (or ruled deferral). On resume:
check answers/, machine seat reports, s2-no-b/ and s2-witness/ STATUS.

## Current (2026-08-19T12:45Z)

Witness slice audited+accepted; PR-302 open RED (real defect, repair round
running under A-005 option-b: Codex owner commit-owner-2, gate v1.2 delta to
verify at desk, audit post-reset Aug 21 09:00Z, merge VOID till audit-2 PASS).
Q-018 pending with project (OPEN semantics for requirement slices). On resume:
s2-no-b/STATUS + questions first, then answers/A-019*, then machine reports.

## OMNIA PAUSA 2026-08-19T15:26Z
All parked. Resume path: machine RELEASE → desk resume note to %6752 → audit-2(6a8d6ef6) → merge PR-302 → R1..R4 per A-019. Store bar 62.00 GiB one-lane. Nothing in flight; no tokens; no ambiguity.

## Current (2026-08-20T09:10Z)

PR-302 green-unmerged at 228a0cdd; packet 93111c32 sealed for old-head shadow.
At reset (08:00Z + natural reading): TO runs pilot-shadow (old head) then
formal audit-2 (8c546e16..228a0cdd) with two DIFFERENT fresh Opus seats (TO
builds its own children); formal PASS ⇒ guard-merge ⇒ R1 (Codex). All rulings:
A-019..A-022 in answers/.

## Current (2026-08-21T10:25Z)

READY-BUT-HOST-BLOCKED. On the machine's capacity release for the recut:
place fresh Opus TO (recut-prep/BRIEF-witness-recut-ticket-owner.md, fill
seat ids), lane runs gate-first (desk verifies vs
FALSIFICATION-PLAN-nonrealizing.md bar), then Codex owner → candidate →
fresh Opus audit → merge → R1 recreation → R2..R4 serial per A-026. All
seeds/duties in recut-prep/COMPOSITION-witness-recut.md.

## PAUSED by operator 2026-08-21T15:1xZ
No workers live (terminal lanes read-only; no recut seats placed). Resume: operator word → check machine release state → seat ask → recut per recut-prep/.

## Current (2026-08-21T15:5xZ) — watcher-first

On machine capacity release: place S0-reland TO (watcher-prep/BRIEF-s0-reland.md)
→ merge → place R1 TO (BRIEF-R1-v2-watcher-base.md, fill base SHA) →
R2..R4 (mandates/ + A-027 hardening) → watcher demo per
WATCHER-DEMO-acceptance.md. Witness recut package = M1.3 handoff, untouched.
