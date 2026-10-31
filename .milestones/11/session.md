# Session record — cardano-keri M1.2 (milestone 11)

Session `keri-m12`. A stranger with tmux and git rebuilds the milestone from this file.
Every launch line below is EXACT and copy-pasteable, quotes included: the recorded line is
what a successor pastes, so an approximation here becomes the next seat's real launch.

---

## Window 1 — `cardano-keri-ms11-decomposed-record-cursor` (singleton; owner pane `%6656` after succession — window consolidation pending incumbent retirement)

Why it exists: the milestone owner's desk — the project owner's only content control
surface for M1.2. One pane, deliberately: the desk has no code, no pairs, no slices, and
empty seats would invite work that must never happen here.

```sh
# cwd: /code/cardano-keri   (the desk owns NO product-code worktree)
claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high
```

- role skill chain: `orchestrator-contract` → `milestone-orchestrator` → `context-compiler`
  → `worker-protocol` → `tmux-orchestrator` → `invariants` → `verification`
- runtime root: `/tmp/ms-keri-11`
- worker id: `cardano-keri-ms11-owner-succ-20260818` (successor, family claude, model claude-fable-5, long-lived operator conversation pane — resume = talk to it; it re-arms per its own wakeup loop)
- parent: cardano-keri project owner, pane `%6429`, runtime `/tmp/projects/cardano-keri`
- resume paste: `.milestones/11/resume/ms.md`
- lane beat: Monitor task `bmibxhszr`, persistent, running
  `BEAT_ROOT=/tmp/ms-keri-11 BEAT_STALE=900 BEAT_NEVER=600 BEAT_INTERVAL=30 /tmp/ms-keri-11/beat/lane-beat.sh`
  (re-arm this on any resurrection; a desk without it is unsupervised)

---

## Window 2 — `cardano-keri-ms11-tB-decoder-mainline` (window `@4653`, pane `%6715`)

Why it exists: owns **Surface B** — landing the accepted, proven decoder repair (`7f49dd8b`,
`d57e4354`) on current `main`, preserving frozen gate `7037228…` and stating `30cab019`'s
disposition explicitly. First product-code mutation this milestone has been permitted.

```sh
# launched with -C /code/cardano-keri; the lane created its OWN worktree
codex-raw --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri -c model_reasoning_effort=high
```

- runtime root `/tmp/ms-keri-11/b-decoder` · worktree `/code/cardano-keri-ms11-b-decoder`,
  branch `ms11/b-decoder-land`, base `77e392d`
- internal chain: T.O. `codex` → commit owner `grok-4.6` (one seat) → final auditor
  `claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high`
- push/PR/merge permitted **for this repair only**, fenced on milestone acceptance +
  auditor-clean + green CI; exact current-`main` delta and final SHA reported with the push

## Window 3 — `cardano-keri-ms11-tS2-witness-mode` (window `@4654`, pane `%6716`)

Why it exists: owns **Surface A slice 1** — proving the family's TxB witness pattern while
**testing the inline branch rather than inferring it away**, citing `maxRefScriptSizePerTx` and the
reference-script fee tiers under the pin, and placing 25,617 B / 26,448 B against both including
the 25,600 B vicinity. Builds the offchain TxB construction, which does not exist today.

```sh
codex-raw --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri -c model_reasoning_effort=high
```

- runtime root `/tmp/ms-keri-11/s2-witness` · worktree `/code/cardano-keri-ms11-s2-witness`,
  branch `ms11/s2-witness-mode`, base `77e392d`
- same internal chain and fences
- **candidate boundary:** no final candidate until Surface B's SHA is on `main`, incorporated, and
  gates rerun on that ancestry

## Shared machinery

- **Build tokens — TWO, host-wide interlock binding from 2026-08-18.** Acquire the programme
  token `/tmp/ms-keri-11/BUILD-TOKEN` first by atomic `mkdir`, THEN the host token
  `/tmp/machine/BUILD-TOKEN` by atomic `mkdir`. If the host token cannot be taken, do not
  realize: unwind only your own acquisition, wait, retry. Release in the REVERSE order — host token first, then programme token — via a
  cleanup trap, including on failure. One host-wide holder means one cold realization across ALL
  projects on this machine. Holder writes lane id, the `df -B1 --output=avail /nix/store`
  reading taken immediately before its realizing command, and start time. Released on
  completion. Two authoring lanes are allowed; ONE realization at a time is the hard bound.
- **Floors v2:** stop AT 50.00 GiB; never start below 50.00 + 3.10 × N GiB (N=1 → 53.10).
- **Pinned toolchain:** `aiken v1.1.23`, binary sha256 `c248f991…360e689`, at
  `/nix/store/zk3s76mjwcb5fz099d6dq02c684bg8wn-aiken-1.1.23/bin/aiken` — verified present
  2026-08-18, so S0 may need no cold realization at all.
- **Known toolchain trap:** nixpkgs `aiken` prints NO compiler diagnostics without a TTY and
  simply exits 1. Wrap builds in `script -qec '<cmd>' /dev/null` or the lane will burn a slot
  staring at a silent failure.
- **Ledger branch:** `milestones`, depth 1, fresh root each write, force-with-lease bound to
  the base actually fetched. Preserve `.projects/cardano-keri/` and every sibling milestone
  tree byte-for-byte. NOTE: the bundled `ledger-sweep.sh` now parents and fast-forwards
  instead, which cannot hold depth 1 — do the fresh root explicitly.

---

## SUCCESSION — 2026-08-18T18:42Z

Incumbent milestone owner pane `%6695` **PARKED FOR SUCCESSION**; appointed successor pane `%6656`
(operator ruling `08f50ecd…e72a5`). **Supervision transfers; child work is retained.**

Session `keri-m12` at park time — all panes alive, none to be killed, reset or moved:

```
@4646  cardano-keri-ms11-decomposed-record-cursor   %6695  milestone desk (incumbent, parking)
@4653  cardano-keri-ms11-tB-decoder-mainline        %6715  Surface B ticket owner   (codex)
                                                     %6720  Grok 4.6 repair owner
@4654  cardano-keri-ms11-tS2-witness-mode           %6716  S2 ticket owner          (codex)
                                                     %6718  Grok 4.6 commit owner
```

Successor sequence: read `.milestones/11/resume/ms.md` and both lane journals → relocate into
`keri-m12` → append `START` to `/tmp/ms-keri-11/STATUS.md` → arm supervision → append
`SUPERVISION-ARMED`. Only then does the incumbent stop bridge beat `b080xpvsi`.

## Succession addendum (2026-08-18T19:35Z)

Owner is now pane `%6656` (window `cardano-keri-ms11-owner-succ`, index 4, to take
the singleton slot when the machine retires incumbent `%6695`). The successor is a
long-lived Claude (Fable) session that is ALSO the operator's conversation desk;
it is not relaunched from a command line — resurrection of this seat means the
operator reopening that conversation, or seating a fresh
`claude --dangerously-skip-permissions --model 'claude-opus-5[1m]' --effort high`
with this snapshot per the standard cold start. START and SUPERVISION-ARMED are
lines 141-143 of /tmp/ms-keri-11/STATUS.md; lane supervision monitor brgxxk88u.
