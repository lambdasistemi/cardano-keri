# M1 — Identity core. Milestone ledger

Owner seat `ms-keri-1`, desk `keri:7` `cardano-keri-ms1-identity-core`, pane
`%459`, runtime `/tmp/ms-keri-1`. Home repo `lambdasistemi/cardano-keri`,
GitHub milestone 1 (open; 59 open / 56 closed). Swept 2026-09-04.

## The outcome test

From the milestone description, and audited against — never against the
burn-down. **Done means, on preprod:** an identity registered once through the
registry; rotations landed by hunters for a premium; a freeze when the pool is
short; poison by the current quorum, cleared by rotation; close by the next
keys and reopen by a later rotation; conviction on a duplicity proof, terminal;
a consumer contract reading the checkpoint with the fail-closed verdict; ckeri
and a hunter daemon doing all of it; the fifteen stories replayed on preprod as
the acceptance suite; docs written from the stories; release 0.5.0.

Two repositories, one milestone: the registry is upstream work in
`cardano-mpfs-onchain`/`-offchain` that M1 implies.

## Adoption ruling — the TERMINAL record is superseded, not discarded

`.milestones/1/resume/ms.md` carried **TERMINAL NO-GO 2026-08-18** until this
sweep. The registry carried **ACTIVE**. That was never two competing rulings:
it was one live ruling and one stale snapshot.

The evidence, all of it re-read in the source by this seat:

- The project owner — this seat's parent — reopened M1 on **2026-09-03** on the
  operator's instruction, executed surface C on GitHub (milestone 1 reopened
  and retitled, epics #318–#330 filed, tickets #332–#357), and closed
  milestones 11 and 12. `.projects/cardano-keri/resume.md`, states of
  2026-09-03 14:30Z and 15:50Z.
- Work has since **merged under the reopened M1**: PRs #313, #315, #317 into
  `main`; slice 3 as #360 → `main@9b2e6b8` on 2026-09-04.
- The TERMINAL snapshot was written 2026-08-18 and never rewritten. Nothing in
  it post-dates the reopening.

**Ruled: adopt ACTIVE.** A stale ledger is not a competing authority. The
TERMINAL record's *conclusions* are superseded; its *measurements and caveats*
are not, and are carried below.

## What survives from the TERMINAL record

The NO-GO was not an opinion about ambition — it was a measurement, and the
measurement still binds the new plan.

- **The size result stands.** `checkpoint.checkpoint` compiled to **25,934
  bytes** before parameter application: **158.3 %** of the 16,384 transaction
  limit, 160.8 % of the 16,133 reference-program ceiling. Three more validators
  sat at 80–92 % before parameters. This is an architectural constraint, not a
  defect a build repairs. Plan v2 answers it with K1 (slim main) and **#336,
  the size table of the surviving scripts after the deletion** — that ticket is
  the discharge of this constraint and nothing else discharges it. Registered
  as contract `script-size-ceiling`, `enforced: NONE`.
- **The G0 INV-BIND repair survives** and is proven. Gate `7037228`,
  frozen before any build and never re-versioned across four sessions:
  RED 16/16 against the unfixed decoder, GREEN 16/16 against the repaired
  one; mutation 496/496 rejected by both decoders; ABI 4/4 with
  `caller_locator_fields=0`; `cross_decoder_divergence=FALSE`; registration
  vectors complete at exactly two, neither on the money path. It is issue
  #291 and epic K2 #320. See the single-copy risk below.
- **The G1 budget numbers may guide the redesign.** Registration breaches
  memory at **24 keys** (20 last accepted, 6.60 % headroom) and **memory
  binds before CPU**. The real ceiling is **~7 keys**, enforced one
  transaction earlier than claimed — an 8-key inception is 1,049 bytes
  against a 1024-byte SAID bound, refused at the *premint* validator.
  **Proof depth is not the cost driver**: depth 5 at vLEI scale costs
  4.6 % of memory; the structural maximum of 64 levels reaches only ~27 %.
  Coupling measured 15,155,350 mem across two transactions. Epic K3 #321 /
  ticket #338 re-measure on the slimmed tree.
- **The asymmetry a later reader will get wrong**: good evidence about a
  component does not make an oversized component fit. G0-green and G1-measured
  do not rescue an oversized architecture; only K1+#336 can.

### Caveats that must never be dropped when the G0/G1 evidence is retold

Carried verbatim in force from the superseded record:

1. Witness frontier **not reached** — 24 is a maximum measured, not a bound.
2. Historical-recovery terminal **blocked**.
3. Respelling **1 of 4**; cause traced to fixture provenance, not a validator
   defect.
4. Depth beyond 5 is **extrapolated from a measured slope**, not generated.
5. Coupling is an **upper-bound composition** across two transactions — not a
   same-AID trace, and not a headroom claim.
6. **Script byte lengths under 16,384 do not prove any transaction fits.**

## Epics and tickets

| Unit | Issue | Stage | Lane |
|---|---|---|---|
| K0 the record | #318 | open; #332 #333 children | not seated |
| K1 slim main | #319 | open; #334 #335 **#336** | not seated |
| K2 INV-BIND + parity oracle | #320 | open; #337 #338 | not seated; `feat/291-inv-bind` exists |
| K3 receipts budget spike | #321 | open | not seated |
| K4 datum V2, owner edges | #322 | open; #339–#343 | not seated |
| K5 hunter edges | #323 | open; #344–#347 | not seated |
| K6 registry integration | #324 | open; #348–#350 | not seated |
| K7 off-chain | #325 | open; #351–#353 | not seated |
| K8 stories as acceptance | #326 | open; #354 | not seated |
| K9 docs | #327 | open; #355 | **#355 partial at `c6692c0` on `docs/355-m1-return`, seat not dispatched** |
| K10 preprod cutover, 0.5.0 | #328 | open; #356 #357 | not seated |
| U1 MPFS permissionless batching | #329 | upstream tracking (mpfs-onchain #98) | operator's lane |
| U2 MPFS gating plugin | #330 | upstream tracking (mpfs-onchain #99) | operator's lane |
| U3 registry model | #316 | merged as PR #317 | done |
| **E367 Lean FULL close-out** | **#367** | **LIVE** | epic seat `%449`, `keri:1`, `/tmp/epic-367` |

### Epic #367 — the only lane in flight

Children, all off `main@9b2e6b8`, no PRs and no branches pushed yet:

| Child | Issue | Ticket owner | Window | Worktree | State |
|---|---|---|---|---|---|
| C1 Checkpoint inversions | #363 | `%453` codex medium | keri:3 | `/code/cardano-keri-363` | PLANNING, intake |
| C2 Registry inversions | #364 | `%454` codex medium | keri:4 | `/code/cardano-keri-364` | START only |
| C3 Semantic atoms + mutants | #365 | `%455` codex | keri:5 | `/code/cardano-keri-365` | parked on C1+C2 |
| C4 Lifecycle + report | #366 | `%456` codex | keri:6 | `/code/cardano-keri-366` | parked on C3 |
| C5 Hash-bound audit report | #368 | `%460` codex medium | keri:8 | `/code/cardano-keri-368` | START, serial tail |

**#367 and all five children are now on GitHub milestone 1** — asked of the
epic owner as NOTE-001 at 17:01Z, acked, and independently verified by this
desk (milestone-1 open count 59 -> 65). They were unregistered at founding and
invisible to a milestone-1 query.

## Priority

1. **#367**, the only seated lane — it closes out the Lean the whole plan rests
   on. Runs to completion before a second lane opens.
2. **#355 docs** (K9) — a partial rewrite exists at `c6692c0` and rots.
   Project owner's queued next action; codex family named.
3. **#362 denominators** — a gate that counts problems calls an empty run
   green, across all five gates. Cross-cutting; every other lane's evidence is
   worth less until it lands.
4. **#336 the size table** (inside K1) — the discharge of the only measured
   reason M1 was ever ruled NO-GO. It outranks the rest of K1's ordering.
5. #358 after the registry's cut; #361 opportunistically.

No inversion has been made implicitly. Item 4 is raised above its position in
K1's own list because of the TERMINAL measurement, and that is the reason.

## Parked, and what would unblock each

- **Plan v2 acceptance** — published on the design page §3, pending the
  operator. Unblocks: the operator's word. Question 4 (validity) goes first.
- **Design questions 3–7** — parameters, validity, poison encoding, receipts at
  GLEIF scale, the checks outside the Lean. Operator-owned, one at a time.
- **Where the MPFS modification lives** — a keri-specific cage in cardano-keri
  vs a permissionless mode upstream. Operator's lane.
- **M8 (Blaster)** — PARKED, revisit condition D-013: first M1-line slice
  merged, or 2026-09-30. The first condition is **met** (#313/#315/#317/#360
  merged). Owned by the project seat, not this one.

## Live risks

- **`feat/291-inv-bind` at `30cab01` is single-copy on this host's disk.** Not
  on `origin`, flagged as such on 2026-08-18, still true 21 days later. It
  carries the proven INV-BIND decoder repair. A branch push is the whole fix.
  Queued as the project owner's action 4, conditional on the operator; raised
  here because the condition has been met since 2026-09-03 and the branch is
  still unpushed.
- **The epic-367 seat runs an unauthorized family.** `%449` is
  `muse-spark-1.3-contributor` on the Pi/opencode-go harness, cwd
  `/code/cardano-wallet`. The standing authoritative set is `claude`, `codex`,
  `grok`, `glm`; the `muse` Pi launcher was added to llm-settings today
  (`22f2674`, 16:28Z) with no authorizing ruling in any rule or skill. Its
  children are correctly seated codex ticket owners. Put to the operator; this
  desk has not disturbed the seat.
- **The epic seat's pane bookkeeping is unreliable** — its
  `.orch/window-brief.md` names `%450` as the idle pane (live: `%451`) and its
  STATUS names this desk as `%458` (live: `%459`). Resurrection from that
  fragment would seat the wrong panes.

## Cleared since the superseded record

- Wedged **pid 948866**, alive since 2026-08-14: gone. Pane `%6501`: gone.
- **No-authenticated-GitHub-mutation**: lifted — the project seat executed
  surface C on 2026-09-03. Read access verified by this seat.
- **The ledger is no longer unpublished single-copy** — this sweep is the
  first publication of the M1 chapter since 2026-08-18.

### One G0 result that was never attained, and why it does not matter

The G0 **terminal marker** was never reached — a harness defect, not a subject
defect: formatter-version drift over 84 blank lines, the valve fired at four
distinct harness failures in four slots. Buying it adds no information about
the subject. Its root cause is live and uncommissioned: the gate's vector
checks are regenerate-and-diff against committed files, brittle to any drift.
The fix is to pin/normalize formatter output **and** compare generated vectors
semantically. Unowned; it is the kind of thing #362 is adjacent to.

Also on the record from that programme: **no GitHub, push, merge, preprod,
live-system or production mutation occurred at any point in it.**

## Open questions at the desk

**The milestone is PAUSED as of 2026-09-04T22:12Z — see the pause section at
the end of this file. Neither question below was resolved before the pause.**

| Q | Subject | State |
|---|---|---|
| Q-001 | The epic #367 seat runs `muse-spark-1.3-contributor`, a family no ruling authorizes for an orchestrator seat | with the operator; seat not disturbed |
| Q-002 | `feat/291-inv-bind` at `30cab01` absent from origin 21 days after being flagged single-copy | with the operator; recommend a branch-only push today |

Both are in `/tmp/ms-keri-1/questions/` with options and a recommendation.
Neither blocks epic #367.

## Epic #326 — K8, the fifteen stories as the acceptance suite

Seated 2026-09-04 on an operator directive
(`/tmp/operator-to-ms1-326-window.md`). Second live lane; does not overlap
#367.

    window:  keri:10  cardano-keri-e326-t-unknown-stories-acceptance
    pane:    %481
    runtime: /tmp/ms-keri-1/epic-326
    base:    main@9b2e6b8
    START:   2026-09-04T17:59:06Z, identity as required

Children: **#375** (scenario DSL, owns the shared grammar), **#374** (headless
backend modules + CLI), **#376** (devnet runner, consumes #375's grammar),
plus pre-existing #354 and #135.

**Ordering set by this desk: #375 first**, then #374 and #376 against it. #375
is the only child that *defines* an interface the others compile against;
building the consumers first designs the grammar twice. #374 and #376 are
parallel-safe once the grammar is stable — disjoint trees. The epic owner may
revise with a recorded reason.

**Dependency flagged in the brief, not papered over:** #326's technical
contract depends on K7 (#325, off-chain), which is **not seated**. #375 and
#374 are simulator-side and unaffected; **#376's devnet replay is not**. The
epic owner is instructed to raise it here rather than let a child promise a
devnet green K7 has not made possible.

**#374, #375 and #376 carried no GitHub milestone at dispatch** (verified by
this desk). Registering them is the epic owner's own bookkeeping, asked in the
brief.

## Family rulings in force

| Seat | Family | Authority |
|---|---|---|
| This desk (`%459`, `keri:7`) | `claude`, `claude-opus-5[1m]`, effort high | standing set |
| Epic **#326** (`%481`, `keri:10`) | **`muse`** — pi / opencode-go / `muse-spark-1.3-contributor` / xhigh | **explicit operator ruling, 2026-09-04, for this seat only** |
| Epic #367 (`%449`, `keri:1`) | `muse` | **UNRESOLVED — Q-001.** The #326 ruling is expressly *not* precedent for this seat; the operator directed that the two not be conflated. |
| #367 ticket owners, #326's future ticket owners | `codex` and the standing set | standing set + alternation |

The #326 authorization is a named exception to `orchestrator-contract`'s
standing set (`claude`, `codex`, `grok`, `glm`), of the same shape as `glm`'s:
a launcher that fixes provider, model and thinking, refuses overrides, and
fails closed when the model is absent from the catalog
(`/code/llm-settings/pi/muse`). It covers **one seat**. It does not extend to
the seats that epic dispatches, and the brief says so.

---

# MILESTONE PAUSED — 2026-09-04T22:12Z, operator order

**Everything below the desk is at rest. Nothing was killed.** Order:
`/tmp/ms-keri-1/pausa/2026-09-04T1805Z-milestone-pause.md`. Scope is M1 only —
this was not a host pause, and no claim is made about anything outside session
`keri`.

## How it was verified

`pause-verify.sh` over the ten M1 panes, two samples each, its own test suite
run and passing first: **0 ACTIVE, 0 gone, 8 PAUSED, 2 IDLE-UNDECLARED**. The
two undeclared (`%455`, `%495`) were read in full and are genuinely parked —
*"No commit, push, merge, cleanup, or teardown occurred"*, *"remaining
write-idle pending release"*. The detector lacks their phrasing; recorded
compliant, with the miss logged as a limit of the instrument.

Independent of any seat's claim: the two suspended background pgids are
`STAT=T`, and a CPU probe over 65 M1 processes (enumerated by resolved `/proc`
cwd) shows only eight accruing, all idle `codex`/`pi` TUI event loops at
0.03–0.17 %.

## What the pause caught that the pane detector could not see

Epic #367 journalled `background=none`. Its child `%455`'s pane said *"1
background terminal running"*. Routed to #367 — never to `%455` — and
corrected: an **ACTIVE audit-poll loop, pgid 3819941, 5-second cadence**, plus
the stopped campaign-028, pgid 3844859. Both now SIGSTOP-suspended and
resumable.

The lesson for the next pause: **the pane detector is blind to background
processes by construction.** A seat's own `background=` line is the only
instrument covering that class, and here it was wrong. Ask for it, then check
it against the pane.

## Work parked mid-flight — nothing merged

| Lane | State at pause |
|---|---|
| e367 `%449` | mid-acceptance. #363 accepted (PR #370 READY), #364 accepted (PR #369 READY), #366 accepted (PR #372 READY), #368 planning-parked (PR #371 draft), #365 mid-campaign-028 (PR #373 draft). Merges of #369/#370 were awaiting authorization and were never given. |
| e326 `%481` | mid-supervision. #375 ran to COMPLETE, **PR #378 READY, epic acceptance NOT done.** It had also planned child #377 and parked #374/#376. |

**No merge authorization was ever issued by this desk.** Every PR above is
unmerged and stays that way until the milestone resumes.

## Deliberately not paused, named rather than assumed

- `keri:2` `%452` — plain `bash`, no agent, nothing to pause.
- `keri:9` `cardano-keri-browser-play`, `%469` and `%451` — two `muse` panes
  working in `/code/cardano-keri`, **seated by no lane of this milestone**.
  Not claimed and not exempted; **ownership is the operator's to settle.**
- This desk `%459` — not exempt; it stops after this sweep.

## Classes this desk cannot measure

cron, `at`, systemd timers, and per-session Stop-hook goal loops are host-level
and outside this desk's instruments. **No claim is made about them.** If a
scheduled job or Stop-hook re-invokes a paused seat, this pause will not hold,
and only the machine owner can settle that.

## To resume

Both epic owners are parked with their subtrees, worktrees, branches and
runtime roots intact. Resumption is an order from this desk to `%449` and
`%481` only; each wakes its own children. The suspended pgids resume with
`kill -CONT 3819941` and `-CONT 3844859` — the epic owner's call, not the
desk's. Nothing needs rebuilding.
