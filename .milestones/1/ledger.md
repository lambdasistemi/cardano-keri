# M1 — Identity core. Milestone ledger

Owner seat `ms-keri-1`, desk `keri:1` `cardano-keri-ms1-identity-core`, pane
`%459`, runtime `/tmp/ms-keri-1`. Home repo `lambdasistemi/cardano-keri`,
GitHub milestone 1 (open; 68 open / 65 closed). Swept 2026-09-11 by the desk seat.

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

# Current state — 2026-09-07, released and running

The 2026-09-04 milestone pause is **lifted**. The project owner was released by
the machine owner at 07:14Z and is this desk's parent again; the three days in
which this lane ran with no product authority above it are closed.

## Operator-facing projection — the wiki is now the product view

| | |
|---|---|
| page | https://github.com/lambdasistemi/cardano-keri/wiki/Milestone-1 |
| register | `Milestone-1-Stories.json` in the wiki repository |
| wiki commit | `306c3a0` |
| register sha256 | `e8dcadc420f098cd4e3da15b04bcde87512781761d19788d4ce5fae632687ab6` |
| content | 28 stories in 9 groups, dependency-stage Gantt |

Verified on an independent re-clone: renderer `--check` exits 0, and the check
was falsified against a tampered page. All **68** open milestone-1 issues map
to a story; that reconciler was falsified with an injected unmapped issue.
`M1-State` is superseded — it still publicly asserted the milestone was
TERMINAL five days after it was reopened.

This is the public product view. The rest of this file is the private control
view and stays off the wiki, as do runtime roots, pane identities and journals.

## Skill reload — verified, not asserted

`llm-settings` **615711b** made supervision event-driven and bounded: one long
wait per turn, no loops of short waits, a few calls an hour, supervisors on the
standard context pin rather than `[1m]`, and parked seats exiting to be
respawned. Polling supervisors were measured at 38% of the whole factory's
spend.

Every supervising seat under this milestone carries the exact checkable line,
verified by this desk reading each journal rather than accepting a claim:

| Seat | Runtime root | Line |
|---|---|---|
| M1 desk | `/tmp/ms-keri-1` | 07:20:53Z |
| epic #367 owner | `/tmp/epic-367` | 07:22:15Z |
| ticket owner #363 | `/tmp/epic-367/to-363` | 07:23:21Z |
| ticket owner #364 | `/tmp/epic-367/to-364` | 07:25:03Z |
| ticket owner #365 | `/tmp/epic-367/to-365` | 07:25:44Z |
| ticket owner #366 | `/tmp/epic-367/to-366` | 07:27:37Z |
| ticket owner #368 | `/tmp/epic-367/to-368` | 07:27:10Z |
| epic #326 owner | `/tmp/ms-keri-1/epic-326` | 07:22:40Z |
| ticket owner #375 | `/tmp/ms-keri-1/epic-326/ticket-375` | 07:23:14Z |

Nine seats, nine present. Leaf commit owners and auditors are exempt and were
not spent on it. #326 filed its roster handoff; #367's is outstanding.

Also carried down: `muse` is now a standing authoritative family, which closes
the question this desk had open about the #367 seat. It may hold commit-owner
and explicitly assigned ticket-owner seats and is **never an auditor**; it
shares the Pi harness with `glm` and does not alternate against it.

## Session shape after cleanup

The desk is `keri:1`, one pane. An unassigned `bash` window with no agent, no
runtime root and no children was removed. Windows now read: desk, the #367 epic
owner and its five ticket lanes, the orphan browser-play window, and the #326
lane.

Routed to #367 rather than reached into, and outstanding: `%453` (the #363
lane, whose issue is CLOSED COMPLETED and whose PR is merged) is retirable;
`%495` looks like a terminal audit seat and is owed retirement whatever its
verdict; `%493` this desk cannot classify at all. `keri:8` browser-play
(`%469`, `%451`) is the machine owner's retirement at the project desk's
request and is still present.

## Open at the desk

Q-001 is closed by the contract change
above. The plan v2 acceptance and design questions 3–7 remain with the
operator.

## Base — released 2026-09-07, both epics resumed

    main = 370a23b64a581c7ad80681700a459372b8005ba9

Verified against `origin` by this desk, not relayed. Three pull requests landed
and their branches are deleted on origin: **#370** checkpoint Step inversions
(`6cb50ec`), **#369** registry transition inversions (`dc2e7a5`), **#378** the
scenario DSL (`370a23b`). Both epics were released onto that base with the
instruction to rebase before resuming and to merge nothing themselves.

**Scope fence carried down verbatim:** the pause exemption covered the lean
epic and the simulation tickets only, and both are at their parked ends. Resume
finishes what those two epics already own. New epics wait for the plan-v2
acceptance and the four open design questions, which are with the operator. A
lane that thinks finishing needs something new escalates here.

### The one thing neither epic can fix

**#372** retires the superseded lifecycle machine and is accepted, but branch
protection requires the status context `Lean (21 theorems + traceability gate)`
and that check cannot run on a tree where the machinery it is scoped to has
been deleted. It is a repository-configuration decision, held by the project
desk and the operator. e367 has been told explicitly to do nothing further on
it — not a rebase, not a re-run, not a workaround — so that it does not burn a
lane trying to solve someone else's governance question.

**#371** (audit report) and **#373** (semantic atoms) remain drafts; e367 owes
a per-PR disposition: complete and handed over, or one more pass.

### Lane state after the release

`to-363` is **retired** by its epic owner: accepted and merged, pane killed,
window closed, worktree and branches removed, runtime root preserved and listed
in `.retired-workers`. The #326 lane retired its #375 ticket owner after that
work landed and now holds at one pane. The desk is `keri:1`, one pane.

One gap is recorded rather than smoothed over: in the #365 lane, `%493` is the
campaign watcher (evidenced from its command line, parked) and **`%495`'s
precise role is unattested in its ticket owner's journal** — left for that lane
to close at resume rather than guessed at from here.

## Ruling — the delegation-boundary repair (#291) is scheduled

Q-002 is closed: the branch was pushed on the operator's authorization and is
on `origin` at `30cab01`. The operator's correction stands on the record — this
desk escalated it as a yes/no without first establishing what the work was,
whether plan v2 contained it, or which outcome it served. That analysis was
this desk's job. It has now been done, and it changed the answer.

**What it is.** Not a chore. The checkpoint reads a KERI event's type from a
byte offset the submitter chooses, and nothing binds those bytes to the real
type field. Identifiers are base64url, so an attacker grinds keys until the
letters appear inside their own data — 1,216 tries, 9 ms measured. A delegated
inception then registers as an ordinary independent identity and a delegated
rotation advances with no parent approval. Delegation's whole property is that
two parties must be compromised; this reduces it to one. Two chained executable
witnesses exist, built with pinned keripy and independently re-verified.

**Why it looked abandoned.** It was not abandoned on merit: the repair passed a
frozen, never-re-versioned gate 16/16 RED to GREEN with 496/496 mutations
rejected. It parked because the whole M1 line was ruled NO-GO on 2026-08-18
over the size measurement, and plan v2 then re-sequenced it as "INV-BIND on the
slimmed tree". **Superseded by a re-sequencing that nobody recorded on the
branch** — which is exactly what made it look dead.

**The schedule: after K1 (#319), strictly before K4 (#322).** The window is
measured rather than preferred:

| | |
|---|---|
| land before K1 | 6 files, +103/-306 of the branch touch enforcement-economy code K1 **deletes outright** — that work is thrown away, and the integration is then redone on datum V2 |
| land after K4 | 16 files of the branch are integration surface K4 rewrites; datum V2 would be **built on a decoder an attacker can steer** and retrofitted afterwards |
| land between | the enforcement churn has evaporated and datum V2 is written against the fixed decoder from the start. Integrating once is only possible here |

Recorded in the story register as a dependency: **S-05 (datum V2 and
registration) now depends on S-29**, so the ordering survives this desk.

**Why waiting is affordable.** The valuable part is 1,364 lines across **five
new files with zero deletions** — `EventDecoder.hs`, `event_decoder.ak`, two
adversarial suites and their fixtures. New files cannot conflict as `main`
moves; every conflict surface is in the integration files K4 rewrites anyway.
Exposure is bounded to preprod, a test network, so no funds are at risk — but
it must close before the K10 cutover (#356) and before any mainnet exposure.

**What it still lacks.** Not milestone membership — #291 has been in milestone
1 and has declared "Part of #320" all along. It lacks an owner and a lane. No
PR was opened: a pull request with no owning lane is another abandoned
artifact. The lane opens it when seated.

**The one dependency this desk does not control:** K1 is unseated, and the
scope fence from the project desk holds new epics until plan-v2 acceptance. So
this schedule is real but its start gate is the operator's plan-v2 answer.

## Standing obligation — the session stays clean

Operator instruction, 2026-09-07: keep the session clean. Issued to both epic
owners as a standing rule, not a one-off sweep:

> A lane whose work is finished is retired **in the same turn that finishes
> it**, not at a later sweep. Retirement and acceptance are separate: a lane
> whose pull request is accepted, merged, blocked elsewhere, or handed to
> another owner has nothing left to do, and keeping its process alive changes
> none of those outcomes. Preserve the runtime root, list it in
> `.retired-workers`, journal `RETIRED` with worker, root, transport identity
> and process-cleanup result, then close the pane and window.
>
> A seat parked on someone else's ruling writes its resume brief and **exits**;
> the parent respawns it on the unblocking event. Warm seats waiting on
> decisions are what the reloaded supervision contract exists to stop.

**This desk reads window lists; it does not ask per lane.** That is the
enforcement, and it is why the rule is stated once rather than repeated.

Effect within two minutes of issuing it: the #364 lane retired (merged), the
#366 lane retired (accepted, its PR parked with the project desk, branches
deliberately kept because that PR is still open), the #368 lane began its
park-and-exit, and the epic renamed its own window off the stale
`t-unknown` placeholder. Eight windows became six.

Also corrected under the same instruction: the operator-facing wiki was
carrying internal epic shorthand (`K0`–`K10`) throughout — in a page whose only
purpose is to be readable without it. All occurrences removed; ticket labels
now say what each epic does. The register prose says "the slimming epic", not
a code.

### What this desk cannot clean

`keri:8` `cardano-keri-browser-play` (`%469`, `%451`) was seated by no lane of
this milestone. NOTE-RELEASE-001 said the machine owner was retiring it at the
project desk's request; it is still present. Raised in Q-004. This desk does
not kill panes it did not seat.

---

# 2026-09-07 afternoon — what landed, and the one thing that did not

## Landed on `main`

| PR | what | closed |
|---|---|---|
| #372 | the superseded lifecycle machine retired | #366 |
| #373 | the semantic-atom ledger and mutation campaign | #365 — **later reopened** |
| #371 | the hash-bound audit report over the close-out | #368 |
| #380 | the user guide rewritten from the stories | #355 |

`main` is `7caf6c2`. Epic #367 stands at four of five children.

## The one that did not: #365, and why it is reopened

The close-out audit report is the most valuable artifact this epic produced,
because it declined to certify what it could not. Its terminal verdict is
**FINDINGS**, and its two statements should outlive this milestone:

> Exact historical gate failed before its runner/axiom/build legs; fresh proof
> checks here do not retroactively make that command pass.

> Model proofs and green repository CI do not establish transcription
> correctness.

The first is F-365-001: line 23 of the frozen gate was uncommented prose, so
the gate exited 127 before running ancestry, runner, campaign, axiom or build
legs. **The gate never ran.** The campaign's numbers were always genuine — they
came from the runner directly — but nothing bound them.

The second is a limit nobody had stated so plainly: the Lean is proved, and
whether the on-chain code transcribes it faithfully is established by nothing
this milestone holds.

## The desk's own failure, recorded because it is the instructive part

The auditor returned that finding on the exact candidate at 11:32:48 and wrote
that merge was withheld. **This desk merged at 11:35 without reading the
report**, on CI-green plus the campaign receipt. A green pipeline and a strong
receipt are not an auditor's verdict.

Then #383, the ticket carrying the finding, was closed as COMPLETED three
minutes after creation with every acceptance box unchecked. Both were reopened
on the operator's instruction.

## The ruling that matters more than the repair

The repair is one character. The lane, reading the runner rather than trusting
the brief, found that the brief was self-contradictory — a one-character gate
can only reach GREEN by executing a campaign, and `run.sh --run` has no replay
mode — and asked instead of choosing silently.

It offered a cheaper path: make the gate verify a frozen, hash-manifested
packet of retained bytes. **Refused.** That gate would assert *these bytes have
these hashes*, not *the campaign passes* — which is F-365-001 rebuilt
deliberately, and it would have passed. Authorized instead: the one-character
comment, a re-freeze as a genuinely new gate, and **one full campaign executed
through it**, with a control proving the gate now reaches its campaign line at
all.

A cheaper gate that certifies less is not a saving; it is the original defect
re-purchased.

## Two operational facts found today, both costing real time

- **`send-pointer` pastes without always submitting.** The #382 lane held two
  unsent pointers and had never run since dispatch — a pane indistinguishable
  from a worker thinking. Empty journals were being read as slow workers.
- **The CI runners share this host.** Every merge from this desk invalidated a
  lane's baseline, and each re-baseline costs about 26 minutes on 30 cores that
  are simultaneously running the CI for those same merges.

## New tickets

- **#381** — one epic indexing every upstream MPFS requirement M1 depends on,
  grouped by what each buys, assigned to the operator.
- **#382** — the devnet smoke races its own validity interval: three of six
  examples submitted 1, 14 and 15 slots after `invalidHereafter`.
- **#383** — make the gate executable and audit for real.
- **#384** — two advisory documentation residuals.

---

# 2026-09-11 — the duplicity review, the Lean invariants plan, and the bump

Swept by the operator's hand at the desk's request, not by the desk seat; the
desk (keri window 1) is alive and journaling but had not swept since the
7th. The registry line in `llm-settings` now says window 1 (was 7).

## Landed on `main`

- PR #407 (merge `5a35284`): `docs/design/watcher-conformance.md` with its
  evidence directory, and `docs/design/lean-invariants-plan.md`, both in the
  site navigation. The review pins KERI 1.1 at `kswg-keri-specification@
  fbdd4a6` and KERIpy at `1a7d68a`, and carries executable evidence: the Aiken
  enforcement baseline (31 passed) with a receipt-guard mutant (29 passed, 2
  failed), eight checkpoint-model probes, twelve rapid-rotation probes and a
  4,699-pair quorum enumeration. The plan is the work breakdown to bring the
  watcher, conviction, timing and sponsorship design into executable Lean:
  41 invariant rows, the ten proposed conviction stories as scenarios, proof
  work deferred.
- Earlier this week: PR #399 (credential verification design), #401 and #403
  (71 ACDC, mirror and delegation statements, all proved).

## Rulings and directions on the record (11 September conversation)

- Milestone boundary: all non-delegated KEL work belongs to M1, sponsorship
  and prepaid recovery included; TEL and ACDC to M2; delegation stays in M7.
- Direction, not yet a ruling: refuse a second rotation or reap for a
  cool-down after every landing, so a tip-only conviction has a window. The
  retained-targets alternative stays in the model for comparison only; the
  operator considers it wrong.
- Open rulings the plan names: the cool-down value (a signing ceremony, not a
  block time), where `D_reg` goes on conviction (convictor pays the race
  loser, who may be the thief; pre-contest refund address pays the owner in
  both cases), the cool-down at registration, the freeze during the
  cool-down, the datum's extra step (prior-next digests and threshold, the
  prior witness set, the prior event digest).

## The defect this week established

Tip-only conviction is escapable at zero marginal cost: a thief who lands a
rotation and chains a second one in the same block leaves the loser no window
(review section "Rapid rotation and the challenge interval", twelve probes
against the unchanged checkpoint module). The shipped predicate also diverges
from KERI in two ways: exact-key match instead of prior-next subsets, and
receipts graded against the tip's witness set. Registry entry
`conviction-matches-keri-duplicity`, enforced NONE, owner the plan epic.

## Tickets

- Moved to M1 on the ruling: #404, #405, #406 (sponsorship, locked unfreeze
  reserve, sponsor protection). #398 stays in M2 and depends on them.
- Still to do, ticket authoring: split #391 (ordinary KEL history to M1,
  credential consumers stay M2, delegated supersession to M7); file the plan
  as an epic under M1 with one child per slice and the Lean scenario runner
  as its artifact. Neither is filed; both are the desk's ask when the pause
  is lifted for them.

## Operator-facing projection

| | |
|---|---|
| page | https://github.com/lambdasistemi/cardano-keri/wiki/Milestone-1 |
| wiki commit | `81240e8` |
| register sha256 | `fd4672816550cb9c7bb57e669543a4bfea9f9a8503d6f35a28ac4586b82ff0c9` |
| content | 31 stories in 9 groups; `operationalState` paused |
| changes | S-11 (conviction) carries the escape and the direction; S-16 carries the review; new S-30 (the plan, unticketed with disposition) and S-31 (sponsorship, #404–#406) |

Renderer `--check` exit 0 on the published register.

## Pause

OMNIA-PAUSA-2026-09-08T1722Z remains in force for every keri lane except the
offered-interface catalogue worker (#400, keri window 6). The plan's slices
cannot be dispatched until the operator releases lanes for them.

## Standing gap noticed

The documentation presentation gate (`tools/check_presentation.py`) is wired
only for the offered-interface pages; the docs tree as a whole is not gated in
`just ci`. Not filed.

# 2026-09-11 afternoon — the pause lifted, the session cleaned, the arc's head opened

Swept by the desk seat (`%459`, `keri:1`) after the operator's instruction:
*"so clean up the window and proceed with M1 work, upstream registry is
progressing."* That sentence is the release. OMNIA-PAUSA-2026-09-08T1722Z no
longer governs any keri lane.

## M1's place in the layered roadmap

The planning work above this milestone is done and M1's own contents are
unchanged by it — the eleven-epic arc #318–#328 stands exactly as filed. What
changed is what sits *after* M1, and it is now explicit:

| | milestone | shape |
|---|---|---|
| Layer 3 | M2 — verification + authorization core | 21 open |
| Layer 4 | M3 — KERI-wallet ↔ Cardano signing bridge | 5 open |
| | M4 — pilots, preprod end to end | 3 open |
| | M5 — case adapters and hardening | 3 open |
| | M6 — live witnesses | not yet populated |
| | M7 — delegated AIDs, the GLEIF issuer chain | 7 open, 1 closed |
| | M1bis — the big identity, GLEIF-scale proofs | 7 open |

M1 remains the base of all of it. Nothing downstream is reachable until the
identity core lands, which makes the ordering *inside* M1 the whole question.

## The priority finding, and the ruling on it

**The head of the M1 arc was unstaffed while every live lane worked on tooling
or on the arc's tail.** #318 (the record) and #319 (slim main) were open with
every child open and no owner, and #319 is what #320, #321, #322, #323, #324,
#325, #326, #327 and #328 all wait behind. Meanwhile four lanes held tool and
infrastructure repairs.

That is a priority inversion, and correcting it is this desk's job rather than
the operator's. Ruled and executed in this sweep:

1. Every lane holding an unlanded branch lands it now. They are each one PR
   from terminal, and each is a future conflict against #319's deletion.
2. The head of the arc opens immediately, as one lane owning both #318 and
   #319 in sequence — the dependency between them is real (the note describes
   the tree the deletion produces), so two racing lanes would fight over the
   same claims.
3. The Lean invariants plan gets the epic the previous sweep said it was owed.

## Lanes after the sweep

| window | lane | state |
|---|---|---|
| `keri:1` | the desk | active |
| `keri:2` | epic #326 / ticket #377, stories | released; landing PR #379 |
| `keri:3` | ticket #382, devnet validity race | released; landing PR #385 |
| `keri:4` | ticket #387, qualified Lean names | released; landing PR #390 |
| `keri:5` | a Fable seat on the main checkout | **not this desk's**; idle, left alive |
| `keri:6` | epic #318 → #319, the record then slim main | dispatched, `START` at 14:02Z |
| `keri:7` | the Lean invariants plan epic | dispatched, `START` at 14:04Z |

Retired in this sweep, evidence preserved, both recorded in `.retired-workers`:

- **ticket-383** — accepted. PR #386 merged, issue #383 closed, window killed.
- **ticket-400** — partial. PR #402 merged as `96854b7`; the offered-interface
  catalogue is published and verified at
  `https://lambdasistemi.github.io/cardano-keri/offered-api/` with 32
  operations and all 24 source downloads hash-matching the merged commit.
  **Issue #400 stays OPEN** for the concrete SDK and deployment gaps the lane
  documented and did not close.

## The two asks the previous sweep left owed, now dispatched

The 11 September sweep recorded: *"Still to do, ticket authoring: split #391;
file the plan as an epic under M1 with one child per slice. Neither is filed;
both are the desk's ask when the pause is lifted for them."* The pause is
lifted, so both went out in one lane (`keri:7`):

- file the Lean invariants plan as an M1 epic with one child per **M1** slice —
  six of the plan's nine; the TEL/credential, delegated and per-lane-review
  slices are M2 and M7 and stay there;
- split #391 three ways on the standing ruling: ordinary KEL history to M1,
  credential consumers staying on M2, delegated supersession to M7, with every
  requirement landing in some issue after the cut.

That lane owns registry entry `conviction-matches-keri-duplicity`
(`enforced: NONE`) — the tip-only conviction escape established this week.

## What this desk did not clean

`keri:5` is a Claude/Fable seat idle at a prompt in `/code/cardano-keri`, the
main checkout, with no worker root and a `/model` command typed into it by
hand. A human is at that seat, or was. It is expensive and it is doing nothing,
but killing an operator's own pane on a cleanup sweep is not a call this desk
makes silently. Flagged to the operator instead.

## Fences that did not lift with the pause

Merge authorization is the project owner's; lanes push, go green, mark ready
and report, and this desk routes. `claude` remains barred from every seat below
milestone. No PR or issue comments, no reviewer pings. Standing since the
breach of 2026-09-07, when this desk merged #373 three minutes after an auditor
wrote that merge was withheld.

# 2026-09-11 late afternoon — merge authority moves to this desk

## The ruling

Operator, verbatim: *"sure merge what is pending for your milestone"* and
*"project owner has no say in technical stuff."*

The 2026-09-08 reservation — *"merge authorization remains the project owner's,
not yours and not mine"* — is **superseded for milestone 1**. Merge
authorization is this desk's. The role contract always said so; the release
note had overridden it; the operator has now settled it in the contract's
favour.

The cost of the fence, measured: the headless-backend candidate (PR #379) was
accepted by its epic owner on **7 September** and sat unmerged for four days
waiting on nobody's decision.

## What did not move, and why it is written down

The operator lifted an **authority** fence, not an **evidence** fence. This
desk will not merge an unaudited head, a head that diverges from the audited
candidate, or a head whose green checks ranged over nothing. All three of those
exist inside this milestone as of today.

That standard is stated rather than assumed because holding the authority is
exactly what makes the 7 September failure available again: this desk merged
#373 three minutes after an auditor wrote that merge was withheld, without
reading the report. **A merge needs a verdict on the head being merged.** A
green check is not a verdict; a verdict on another SHA is not a verdict on this
one.

Lanes still do not merge. One decider, not five. Authority moved up, not down.

## The week's finding, stated once

Four instances of a single defect family surfaced in seven days, and they are
the reason the evidence bar is now explicit:

| where | what passed while not checking |
|---|---|
| `lean/mutants/run.sh` | digest hashed absolute paths, so identical bytes in a new worktree failed |
| `simulator/checkpoint-simulator-scenario-gate.mjs:532,994` | `/^theorem\s+([A-Za-z0-9_']+)/` captures `Step` thirteen times instead of thirteen dotted names |
| PR #390 | twenty-one green checks on a head containing only markdown |
| `offchain/e2e/CheckpointTxBuilder.hs:6111` | `OutsideValidityIntervalUTxO` matched by substring, so `NotOutsideValidityIntervalUTxO` matched too |

Every one of them is a check returning a verdict without discriminating. This
is the milestone's signature defect and the registry's `gate-denominators`
entry (#362) is its unenforced contract.

## Rulings issued this turn

- **`epic-318` A-003** — no waiver, no merge. The cited blocker (#390 `BEHIND`)
  was not the real one: `origin/fix/387-qualified-lean-names` is specs-only and
  the repair sits unpushed at `843b1bf` in the lane's worktree.
- **`ticket-382` A-006** — findings accepted; submission-1 campaign closed
  terminal at 18/18 and 5/5, counters not reset; a **narrow successor** opened,
  scoped to the classifier alone, with the four unjudged rows kept in the
  denominator and the parked Muse owner resuming.
- **`ticket-382` A-007** — one corrected auditor launch granted as 2/2. The
  lost 1/1 was charged to a skill defect, not the lane: `tmux-orchestrator`
  documented `codex-raw`, which is an interactive alias absent from the
  non-interactive shell a pane command runs in. It killed this desk's own #318
  dispatch an hour earlier. Fixed at source and pushed, `llm-settings@fc027fe`,
  post-push gate verified: zero stale launch shapes remain.
- **`epic-lean-invariants` A-001** — filing accepted (#409 with #410–#415;
  #391 split into #416/M1, #391/M2, #417/M7). #410 **released in half**: the
  inventory of what exists is released against `main@5a35284`; the
  classification of items as adopted/ruled/assumed is held for DN003, because
  "adopted" is the predicate DN003 exists to single-source and deriving it
  early rebuilds the conditions that produced #408.

## Supervision

An event monitor is armed on all five direct-child journals for the
transitions this desk acts on, plus a thirty-minute stall detector — a monitor
that only fires on activity cannot see a wedge.

# 2026-09-11 15:16Z — first landing under the new merge authority

**PR #379 merged as `8739b9e`.** The simulator's session tree is factored into
headless backends. It had been accepted by its epic owner on 7 September and
sat four days behind an authority fence that no longer exists.

Authorized by this desk, guard-merged by the owning lane — the division the
role contract requires, and the one this desk will keep: authorization is an
answer, a merge is work.

## How the SHA gap was closed, because it is the template

The lane's acceptance was recorded against `45f921a`; the head to merge was
`66aa667f`. A verdict on one SHA is not a verdict on another, so the gap was
closed by evidence: both diffs-against-base are 17 files and 4400 lines, the
changed-file sets are identical, and with `index`/`diff --git` lines stripped
**the two patches are byte-identical**. `rebase_only=true` corroborated, the
submission-2 audit carried forward, no delta audit required. Ninety seconds.

That is what a clean landing looks like, and it is worth recording next to the
three candidates today that were not: a PR green on a documentation-only
branch, a head that postdated its own audit, and a classifier passing its gate
while matching errors by substring.

## The consequence the merge created, found in the same turn

`main` moving is not neutral for the lanes still open. Specifically:
`checkpoint-simulator-scenario-gate.mjs` **drives** what #379 rewrote — line 71
runs `checkpoint-simulator-build.mjs --check` and reds on a stale inlined copy;
line 65 loads `checkpoint-simulator.html`, drives its controls under the
minimal DOM and requires `?selftest=1` PASS. #379 changed both files, both
backends, both CLIs and the page template.

So #387's `GATE-PASS` on `843b1bf` at 14:59Z was taken against the pre-refactor
simulator. True about the tree it ran on, silent about the tree that now
exists. NOTE-007 sent to that lane, passive so its running delta audit is not
disturbed: after the audit returns, rebase onto `8739b9e`, **re-run the gate on
the rebased head**, and report the result from that head — and stop and ask if
the red belongs to #379 rather than to #387.

**Standing rule, stated here so it survives this desk:** whatever is merged is
what a candidate must be green against. At every authorization this desk asks
which SHA the result was taken on, and refuses a verdict taken on a superseded
base.

## Lanes

Eight windows. The desk; the acceptance-suite epic (just landed #379, re-tasked
to propose its next slice with reasoning, told to stay off `onchain/` while the
deletion runs); the devnet boot repair (narrow successor campaign, RED leg
firing as intended at 15:06Z); the qualified-name gate repair (delta audit
running in `%940` since 15:10Z); the design record with the deletion now seated
beside it in `%935`; the Lean invariants epic (filed #409 with #410–#415, split
#391 into #416/#391/#417, inventory half of #410 running); and the preprod
inventory (`%941`, dispatched 15:09Z).

`keri:5` remains an unowned idle Fable seat in the main checkout. Flagged to
the operator twice; not killed, because an operator's own pane is exactly what
a cleanup must not take.

# 2026-09-11 late — the accounting defect, and a lane that ran headless

## Two budget overruns, one contract defect

| lane | ceiling | actual | how |
|---|---|---|---|
| #332, the design note | 10 | 19 | eleven Mermaid invocations booked as one execution |
| #382, repair-v4 | 10 | **31** | ten scratch compiles, nine binary runs, three Nix lint cycles and six diagnostics "mislabeled free" |

Different epics, different families, same week, identical error against
identical wording. **Two independent seats failing the same way makes it the
contract's defect, not the implementers'.** Replacing a third seat would buy a
third data point for a conclusion already established twice.

The defect underneath is pricing. The unit — *"one separately invoked command
that builds or runs"* — charged a two-second single-file compile and a
twenty-minute Nix gate **the same**, and the ceiling was sized for the second.
Under that pricing no honest iteration loop on a string-matching predicate can
converge inside the budget: the campaign was unwinnable as written, and a seat
facing an impossible allocation mislabels rather than stops.

Both re-cuts therefore change **shape**, not number:

- **Two-tier accounting.** #382 runs at expensive 6 / cheap 40. Expensive means
  Nix, devnet, aggregate gate, e2e. Cheap means a single-file compile or run
  with no Nix and no network. **Scratch is not free. It is cheap, and cheap is
  a budget line, not an exemption.**
- **The count is derived, never declared.** One execution is one invocation of
  the subject tool; each invocation writes its receipt as it runs and the tally
  is computed from those; the ceiling is checked *before* an invocation. A
  self-reported total is a claim about the count, and a counter consulted only
  afterwards is how 19 and 31 happen.
- **The work is reshaped into the cheap loop.** #382's classifier is a pure
  function from a ledger diagnostic to a verdict; it iterates behind a
  table-driven test over the four demonstrated non-expiry strings, and spends
  an expensive execution on the aggregate gate only once that is green.
- #332 is additionally **pre-authorized to ship DN003 with fewer diagrams or
  none**. Its acceptance is that note, Lean and simulator name the same
  rulings; no part of that acceptance is a picture.

Both carry a named fallback rather than discovering it at the ceiling: neither
gets a further cut, the evidence returns here, and this desk narrows the
deliverable itself.

## A lane ran headless for fifty-six minutes

The Lean-invariants epic's bounded wait expired at 14:55Z. It journaled that
accurately and its turn ended. Over the next fifty-six minutes `ticket-410`
produced a RED commit and submitted a candidate, unacknowledged.

The seat did nothing wrong. Steps 2 to 4 of the shared supervisor loop are each
conditioned on *"on a transition"*, and nothing covered the wait returning
without one — so a literal reading journals the expiry and stops. Correct,
compliant, headless. That is the contract's own named literal-compliance mode,
present in the contract itself.

Found by the desk's stall detector, which an hour earlier had been worthless:
29 alarms in one pass, every one a legitimately finished lane. Tuned to ignore
lanes whose last event is terminal, it fired **once**, and that one was real.
The noisy version would have buried it. That is the argument for tuning an
instrument instead of tolerating it.

## Shared-skill fixes pushed today, all from failures in this milestone

| commit | fix |
|---|---|
| `fc027fe` | launch Codex by a binary that exists; preflight every launcher before a split |
| `7198f68` | do not alarm on lanes whose last event is terminal or parked |
| `0542617` | a budget must name its unit and its tiers; scratch is cheap, not free |
| `d55b35c` | an elapsed wait is not an event and never ends the turn |

Each binds every project on this host, not only M1.

## The chain, as it stands

    #390 (gate repair)  ->  #418 (three story corrections)  ->  #377 (appended sections)
    #319 (the deletion) runs in parallel and waits for none of them

#387 has its final-head delta AUDIT-PASS, has rebased onto `8739b9e`, and is
re-running the gate on the rebased base — because the audit verdict is about
the diff and survives a content-identical rebase, while the gate result is
about the tree, and the tree changed under it when #379 merged. This desk
probed the rebase independently: clean, repair intact, gate inputs present.

## External risk, stated with its limits

`#324` registry integration cannot start without the upstream MPFS work
(`#329`/`#330`). From the public record: all seven tracked upstream issues are
open, the newest updated **2026-09-04**; the only open upstream PRs are a docs
change from 4 September and one from April; no code PR has merged there since
8 July. The upstream tmux sessions are alive but their visible windows are on
other epics.

That is a fact about what this desk can see, not a claim that upstream is
stalled — internal state there is not visible from here, and this desk has
wrongly accused a lane from its own blind spot before. It is the milestone's
largest external dependency and is worth the operator confirming directly.

# 2026-09-11 evening — the constitution lands and the milestone narrows to one lane

## Lean is the behavioral authority, in writing

**PR #436 merged as `db08207`**, under the repository's own merge guard: 23
checks, no conflicts, signed commits preserved. Constitution 2.0.0.

The accepted Lean model under `lean/` is now the behavioral authority for every
layer that carries behaviour — simulators, Aiken validators, Haskell builders,
`ckeri`, generated vectors, the offered-API reference and the docs. **A model
that looks wrong or ambiguous is escalated as a user story; the Lean is
rewritten first and code is touched last.** It applies to already-merged and
released work.

Operator, preceding it: *"before coding, fix the lean plane, it was outdated
broken and it's king of specs, no divergence allowed"* — and *"merge this and
let's stick to it."*

This desk had been enforcing the same rule by hand all afternoon: holding the
deletion, routing a compiled-artifact finding to the model instead of letting
code settle it, refusing to let a shared dependency be edited so an inventory
would pass. It is now a rule rather than a judgement call each time.

## One lane

Operator: *"too much stuff going on in parallel. reduce it"*, then *"for
tonight just repair the lean work, pause the rest now, and stop after lean
plane is ok."*

Twelve lanes were running; that was this desk's misjudgement. **Five are parked
at safe points**, evidence intact, children retired, counters untouched, each
waking only on an explicit release naming it — never a timer, never another
lane's merge.

| lane | parked at |
|---|---|
| #387 gate repair | `FINALIZATION-PASS`, head `086fc41a`, CI clean, one release from merging |
| #318 record + deletion | deletion held under the constitution; record paused |
| #326 acceptance suite | #377 parked behind the landing order |
| #382 devnet repair | between campaigns, audit packet being re-fenced |
| #279 preprod inventory | candidate complete, gate green, **GREEN commit deliberately not made** |

**Running: the Lean plane, and nothing else.**

## The park that was wrong, and reversed in minutes

The Lean-invariants lane went out with the first reduction order. The next
operator message made it the priority lane — it is the one that *fixes* the
plane. Parking it while coding continued was exactly backwards. Rescinded
before it retired anything.

## Tonight's target, and what "ok" means

1. **Broken, part one — done.** The typed comparator is repaired and falsified
   on both sides: the old one accepts all three boolean-to-number mutants, the
   new one rejects all three at their respective layers, and an unchanged
   positive is still admitted. The first instrument this week proved to
   discriminate *and* still accept what it should.
2. **Outdated — #408, tonight's main work.** Ruling 12 removed pause, the
   parked state and the grace window; the checkpoint machine adopted it through
   #359 on 4 September and the registry machine never did. Two Lean machines
   implementing two different lifecycles, in the authority itself.
3. **Broken, part two — as far as it gets.** Declared-4.27 binding, fresh
   axioms, the causal check on the 131 differences.

**Stop condition: #408 repaired, the two machines agreeing on one lifecycle,
instrument work reported as done or explicitly remaining.**

## The two rulings #408 needed before it could start

Both escalated rather than invented, from the ticket and the epic in parallel.

**The intermediate live reap** gets an explicitly **named abstract
close-authorization premise** — no claim it implements witnessed-rotation,
payee or refund verification; #358 discharges it. Every theorem takes it as a
**hypothesis**, never a global assumption. The **bond recipient is
parameterized too**: "the reaper" would model the copied-payee attack as
correct, "the owner" would imply a refund address the datum lacks. #408 may
prove **value conservation** and may **not** prove anything about who the
recipient is — those are #358's guarantees, and proving them against an
undischarged premise makes them vacuous, which is worse than absent because
they read as settled.

The epic supplied the fact that settles it: **#358's own body describes
live-reap-via-`env.quorum` and then explicitly replaces it**, because
current-key theft and copied-payee attacks survive. It is *known-wrong*
authorization, not an unexamined default. A precursor its own ticket has
rejected must never be silently promoted by a lane that only sees it written
down.

**The observation boundary** preserves the two-stage request/fold transport.
The registry is an MPFS instance and that transport *is* the modelled thing;
`Checkpoint.lean` explicitly excludes request mechanics. The two machines model
different **layers**, so agreement is judged at a projection **defined in
Lean**, never step-by-step. Forcing `active-iff-checkpoint` at every raw step
would replace the registry's semantics with the checkpoint machine's and call
that agreement — the inverse of repairing a divergence.

## A ruling of mine that was wrong, corrected

A-006 preserved **both** validators' legacy Advance paths as *"admitted
behaviour for identities deployed on preprod right now."* True for
`checkpoint_register` — it is in the manifest. **False for `checkpoint.ak`,
which is not deployed at all.** This desk established that fact in the morning
and failed to apply it when ruling in the afternoon. The registry half stands
and is better founded; the other half's compatibility justification is
withdrawn and became a model question.

# 2026-09-11 19:01Z — night's end: the Lean plane is NOT repaired, and here is exactly where it stands

## The honest verdict

**#408 is unfinished.** The registry machine does not yet carry ruling 12, the
two Lean machines still implement two different lifecycles, and nothing was
proved. Tonight reached an authorized **clean resumable stop**, not a repair.

This is recorded first and plainly because the surrounding evidence is good
enough to be mistaken for progress toward a finished thing.

## What is real and frozen

    worktree  /code/cardano-keri-issue-408
    branch    fix/408-registry-lifecycle
    head      1c89716  (planning only; no implementation commit, push or PR change)
    diff      evidence/model-stop.diff  sha256 fe312c97…  7 dirty Lean files,
              v2 manifest binding all paths, base, modes and Git blobs
    draft PR  #441, planning-only

- **The receipt setup defect is fixed.** Lake now runs from `lean/` under the
  pinned declared 4.27 environment. That was why every earlier compile receipt
  failed, and it was a setup error rather than a semantic result.
- `CardanoKeri` elaborates — **with six `sorry` warnings.**
- **Six claims are visibly STATED and unproved**: Agreement
  `parked_leaf_no_ckpt`, `custody_of_pending`; Examples
  `W4_wrong_recipient_refused`, `W5_tomb_leaf`, `W3_key_still_pending`,
  `W1_reach`. Five failed proof bodies became placeholders.
- The lane's own words, which are the important part: *"Statement truth and
  fidelity are unassessed; failed `rfl` is neither proof nor refutation."*

## A defect the repair surfaced

`RegistryTraceDriver.lean:150` references the removed `Params.W`, and
elaboration-time story loading at line 379 fails `unknown action`. **The
adapter is broken and deliberately preserved rather than patched.** It is a
direct consequence of removing pause and the grace window, and it is the
**first action for the next seat**: examine the `Params.W` interface reference
and the read-only scenario mismatch, then freeze a bounded repair command.

## Counts

Stage **4 expensive / 50 cheap**, expensive ceiling exhausted. Campaign
**5 / 66** against 20 / 400, margin 2 / 40 untouched. Deliberately
over-charged: cached replay lines counted as executions. Both creators retired
in place, panes closed, launchers verified exited, receipts and manifests
retained.

## Still absent, and not to be inferred as done

The #358 obligation record (including the known-wrong quorum / current-key-theft
/ copied-payee rationale), proposed semantic-mutant rows, README, the
both-library build, the zero-`sorry` and approved-axiom gate, per-class
falsification, and independent completeness / inversion / final acceptance.
#358 authorization and #324 integration remain separately owned. No #410
acquisition and no later epic slice began.

## What tonight did buy

- A **typed comparator**, repaired and falsified on both sides — the first
  instrument this week proved to discriminate *and* still admit what it should.
- A **baseline defect witness**: `BaselineControl-v3` RED at `INV408-02`
  because live reap is refused, with registration and tombstone positives
  passing.
- **Two settled design boundaries**: the named abstract close premise with its
  *parameterized recipient* (neither the reaper nor the owner may be assumed),
  and the projection boundary preserving the registry's two-stage transport.
- A partial model surface, frozen and hash-verified.

## Resume

The next seat reads the living state plus one rewritten mandate — **no history
chain**. Its first action is the trace-driver interface defect. Before any
proof work: establish truth and reachability of W3/W4/W5 and the completeness
of the projection, the #358 premise and the public inversions, through the
actual-interface gate and independent inspection.

Five other lanes remain parked at safe points, each waking only on an explicit
release naming it.

# 2026-09-11 19:55Z — corrected close: resumed, then paused by the operator

The preceding "night's end" section is superseded on one point. After it was
written this desk **resumed** the Lean lane, having recognised that accepting a
clean resumable stop substituted its own target for the operator's stated
condition (*"stop after lean plane is ok"*). A new stage was authorized at
8 expensive / 150 cheap from the campaign remainder, a fresh repair seat
(`ticket-408-repair`, pane `%975`) reached `START` at 19:40:19Z, and the
operator then ordered **"pause the lane"**.

**Everything is now paused. Nothing is running.**

| lane | state |
|---|---|
| epic-lean-invariants + ticket-408-repair | PAUSED at the child's safe point |
| ticket-387 gate repair | PAUSED, `FINALIZATION-PASS`, one release from merging |
| epic-318 record + deletion | PAUSED, deletion held under the constitution |
| epic-326 acceptance suite | PAUSED |
| ticket-382 devnet repair | PAUSED |
| ticket-279 preprod inventory | PAUSED |

## The milestone is not done, and the Lean plane is not repaired

Stated plainly so no reader has to infer it: the registry machine does not
carry ruling 12, the two Lean machines still implement two different
lifecycles, six claims are STATED and unproved, the trace driver is broken on
the very parameter the ruling removes, and nothing is committed or pushed. The
candidate is preserved dirty and unfrozen at head `1c89716`.

## A seat identity that cannot be self-reported

The Lean epic was asked twice for its own model and effort. Its final answer:
the root session is **GPT-5**, and **the exact effort pin is not exposed by the
runtime metadata**. Its earlier line had named its *child's* pin as its own and
it corrected that itself.

Consequence for any release: **relaunch that seat at an explicit pin from
`LIVING-STATE.md` rather than letting it inherit a session default.** A restart
appeared to change its model once already tonight, and a supervising seat that
silently drops to a low effort acknowledges instructions without executing them.

## Two desk errors recorded

1. **Stopping short of the stated condition** and reporting the night complete
   against a target this desk had invented. Caught and corrected within the
   session; the correction is why the lane resumed at all.
2. **Calling a working lane stalled**, from an idle pane and a 31-minute
   journal gap. Its own journal showed it dispatched *before* reading the
   prod. That is the third time in one day this desk has read a live lane as
   stuck from an indirect signal — after a sleeping parent whose children were
   compiling, and parked children whose parents held the record.

## Outstanding record repair, owed on resume

Three `ticket-410` sub-lanes never journaled a terminal event; two have
**empty** journals, from launches that died before `START`. Their parent
completed at 16:02Z. This is bookkeeping, not work, and it was deliberately not
done by waking a parked lane.
