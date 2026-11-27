# Current state — 2026-11-27, 15:55 UTC — RUNNING

The desk is pane %240 of tmux session `cardano-keri-M1` (Claude). Runtime root (this machine only):
`/home/paolino/.orch-runtime/cardano-keri/m1`; its journal is `STATUS.md`, and every operator decision is in
`handoffs/decisions-while-away.md`. The desk's watch is a Monitor re-armed every thirty minutes (the command is in
the journal; it also runs `handoffs/owner-nudge.sh`). Main is `9692e70c`.

## The first presentation is Wednesday 9 December 2026

The operator, 27 November: the 2 December presentation is gone; the first is the 9th; its demo is "at least" the
prepared one on a rebuilt registry whose registration reads the signed event through the structural decoder (#291,
epic #320) and admits the key-derived identifier (#590). Targets: on-chain part on main Thursday 3 December,
off-chain part Friday 4 December, the rehearsal packet accepted by the desk Monday 7 December, a possible preprod
run Tuesday 8 December on the operator's word. Nothing has been signed or submitted on preprod.

The prepared demo is kept: branch `demo/2026-12-02` (= `9692e70c`: registration and fold through Koios with
Singular's replay; one output funds and is collateral, through Singular's library; PR 588). Its accepted packet
(build identity, local rehearsal of 14 transactions, cast, transaction list, runbook) is in the runtime under
`follower-353/handoffs/trial-2026-12-02/demo-9692e70c/`. Trial terms: deposit 50, freeze bond 5, premium 2,
registration cost 1, minimum tip 0.5, booking width 100 s, processing 180 s; ceiling 400 test ADA (the list shows
324, and 390 with a second run). The folder's vault holds one output of 10,000 test ADA.

## Seats (each journals in `<runtime>/<seat>/STATUS.md`; panes in `<seat>/.pane`)

| seat | staffing | work now |
|---|---|---|
| commitment-534 | owner Codex gpt-6.2-astra medium; writer Claude Sonnet 5.5; auditor Codex gpt-6.2-sol | first: the structural decoder on main's registration and advance readers, then #590 on main, then the consumer-vector conversion to schema 2; behind it #576 (attestations minted at use; slices R1 to I1 accepted, branch `feat/576-checkpoint-attestations`, **52 commits not pushed**), #591, #597 |
| register-351 | same shape | first: the off-chain counterpart for the 9 December registry (Haskell decoder, `ckeri` builders without caller-supplied positions, #590 through the command); behind it #573 (conviction; branch `feat/573-conviction-validators`, **13 commits not pushed**) |
| follower-353 | same shape | the rehearsal packet for 9 December; holds the keripy comparison #589 (226 rows; bugs #590, #591, #595, #596, #597, #598) |
| lean-569 | Codex gpt-6.2-astra high, no auditor | the prefix model as a standalone draft on main; a conformance table of model rules against validators; no new model work that is not a repair. Drafts: 574, 577, 581, 582, 592, 593, 594 |
| lean-neon | agy gemini-4-neon-high, fenced, evaluation only, never merged | idle; three tasks done and audited |
| lean-eval-audit | Claude Opus 5.5 high, fenced | idle; three blind audit reports in its runtime `handoffs/` |

## Decisions of 26 and 27 November (the operator's words are in the runtime decisions file)

- ckeri reuses Singular's code as a library and does not reimplement it.
- cardano-tx-tools pull request 137's branch is brought up to date with its main and pinned; not merged there.
- Deployment refuses a premium below the minimum output; the builder never makes up the difference.
- A rotation's link to its previous event is not checked on chain and no proof of the link chain is imposed; this
  is stated as an open limit that may be a vulnerability (draft 593); a zero-knowledge proof is named as out of
  reach.
- A Gemini 4 Neon seat is evaluated on Lean tasks beside the Astra seat, graded by an independent blind auditor.
- No lane is to sit parked.

## Waiting for the operator

1. Whether signed negative test events against the project's own validators are authorized: two team owners
   decline to build them and several test-first repairs wait.
2. Whether the Neon seat repairs its later audit findings or the evaluation stops.
3. Whether the Astra seat's repair of draft 594 gets a confirming audit.

## What exists only on this machine

The runtime root above (journals, decisions, the demo packet, the audit reports); the unpushed commits named in the
table; the preprod wallets' keys under `~/.secrets/` (paths only are ever used). The two fast disks are mirrored;
no backup job to another disk was found on 27 November.

---

# Earlier state (kept for the record)

# Current state — 2026-11-25, 20:35 UTC — PAUSED by the operator

The milestone is paused ("let's pause", at the desk). Order: runtime `handoffs/pause-order-20261125T2026Z.md`.
Every seat journaled `PAUSED` at a clean point; nothing was killed; the desk's Monitor is stopped. **To resume:** on
the operator's word, re-arm the desk's Monitor (the command is in the runtime `STATUS.md` history; it also runs
`handoffs/owner-nudge.sh`) and wake each of register-351 (%526), commitment-534 (%527), follower-353 (%534) and the
Lean seat (pane in runtime `lean-569/.pane`) with a pointer to a resume note. Main is `9b9646a4`.

**Waiting for the operator:** how a rotation puts its event's digest on chain: every rotation in two transactions (a
hash proof minted first, then the rotation that burns it), or one transaction when it fits (up to about four keys)
and two when it does not. Storing the declared digest is excluded by the admission rule. Figures: runtime
`commitment-534/handoffs/576/digest-shapes.md`; guarantees: `lean-569/handoffs/576/digest-shapes-guarantees.md`. The
checkpoint datum's wire form is held on this. Not urgent: a published command to burn attestations. Parked by the
operator until the on-chain code is done: validator evidence for the refusal at a never-rotated checkpoint; the
reader's history route; the closing-slot theorem; the underfunded-holding question; the configuration-file key for
the time setting.

**Decided 24 and 25 November (operator):** inception proven at the booking (#559); a conviction needs a rival valid
under its own rules (#573); no program through a reward withdrawal, every KERI evidence check an attestation minted
at use and read in the mint field (#576); the chain admits exactly the events keripy accepts; an event is identified
by the digest of its signed bytes and a conviction compares digests; every deploy transaction carries a validity
end; an unobserved transaction is reported unconfirmed; a defect found in review is fixed without asking; on-chain
code first.

**Where each piece stands**

| Piece | Lean | Validators | Commands |
|---|---|---|---|
| Booking proves the inception (#559) | draft 564 | implementation reviewed at `8fdfcf6c` (local, zero open findings); acceptance needs settled bookings | builders in progress on that head (register-351); the installed command's first local run failed at its control booking, repair in progress |
| Model binds what validators check (#569) | draft 574 | — | — |
| Conviction rule (#573) | drafts 577 and 582 | not started | — |
| Attestations (#576) | drafts 581 and 582 | booking done with #559; rotation, freeze and deposit: split into an event-verification policy and a transition policy adopted (measured: 9 keys or 33 witnesses fit, against 10 and 36 on main); datum wire form held | deploy and register follow |
| Design pages against the model (#580) | — | — | inventory of 2,573 units done (453 claims disagree); corrections being regrouped by claim family; no edit yet |

Measured limits: a rotation event over 1,024 bytes is refused by the on-chain hash (about nine keys), which already
limits registration on main. Bugs filed: #579 (the consumer page's browser check fails on main and no gate runs
it), #580. Merged on 25 November: pull request 578. The December registry needs #559, #573 and #576 on main: the
trial of 2 December cannot hold and the demo of 9 December is at risk.

Working rules: writers Claude Sonnet 5.5 high, auditors Codex gpt-6.2-sol high, ticket owners Codex gpt-6.2-astra
medium, Lean one Codex gpt-6.2-astra high writer with each checkpoint checked by the desk and a fresh Astra seat
(`handoffs/decision-audit.sh`, next 057) in one complete pass over a closed list of points. Codex owners let their
pairs wait unnoticed five times in two days (100, 50, 55, 94 and 230 minutes): the owner watch exists for that.

## State recorded on 2026-11-25, 13:35 UTC and before


Main is `9b9646a4`. The operator is present. The record of every decision is the runtime file
`handoffs/decisions-while-away.md`.

**Decided by the operator on 24 and 25 November**
- The inception is proven at the booking by the application mint (#559; constitution 2.1.0, principles XII and XIII).
- A conviction requires a rival rotation valid under its own rules against the previous event's commitments, which
  the checkpoint carries one step (ruling of 2026-09-11 confirmed; ticket #573 under #347 and #438), with a
  comparison of the model's rotation rule against keripy.
- **No program runs through a reward withdrawal. Every KERI evidence check is an attestation minted in the
  transaction that uses it and required in the mint field** (ticket #576). Attest at use by default; mint earlier
  only when a check does not fit beside its use or a fact must pass from one role's transaction to another's (the
  hash proof; the approval from booking to fold). Demonstrated on the local chain: runtime
  `commitment-534/handoffs/attestation-at-use-spike.md`. Deployment publishes the attestation policies first and
  registers no stake credential; every script hash of a release changes; a registry is created only when all the
  policies it is parameterized by are final.
- Every transaction of `ckeri registry deploy` carries a validity end as Singular's do; an unobserved transaction
  is reported "unconfirmed", never "unpaid".
- **A defect found in review is fixed without asking the operator.** The operator is asked only about meaning or
  design, a proposed waiver, a stall, or something outside a mandate.
- On-chain code first. Parked until it is done: evidence that the validator refuses a conviction at a never-rotated
  checkpoint; the reader's history route; the closing-slot theorem (Lean Q-006); whether an underfunded live
  holding is "active"; the configuration-file key for Singular's time setting.

**The on-chain work**

| Piece | Lean | Validators | Commands |
|---|---|---|---|
| Booking proves the inception (#559) | draft 564 | in progress (commitment-534), interface v3, attestation at use | started (register-351, #559-B) |
| Model binds what validators check (#569) | draft 574, on 564 | — | — |
| Conviction rule (#573) | draft 577, on 574 | not started | — |
| Attestations for every check (#576) | draft 581, on 577 | booking only, as part of #559 | deploy and register follow |

The four Lean drafts form one stack and merge only when the validators follow. The December registry is created
only when #559, #573 and #576 are all on main: the trial of 2 December cannot hold and the demo of 9 December is
at risk; not yet sized.

**Merged since the last sweep:** pull request 578 (the registry commands deploy, register and return through a Koios
endpoint, #546). **Filed:** #576; bugs #579 (the consumer page's browser check fails on main and no gate runs it)
and #580 (design pages contradict the model).

| Team (ticket owner Codex gpt-6.2-astra medium) | Pane | Work |
|---|---|---|
| register-351 | %526 | builders of #559 against interface v3, then the fold wrapper #558 |
| commitment-534 | %527 | validators of #559 (booking) on `feat/559-validator-booking` |
| follower-353 | %534 | ticket #580: every design and architecture page against the model, one pull request on main |
| lean-569 (Lean writer, Codex gpt-6.2-astra high) | see runtime `lean-569/.pane` | waiting; four drafts pushed |
| tracker clean-up | %432 | interactive, idle |

Working rules that changed: a child never pastes into the desk's pane (it journals `REVIEW-REQUESTED` or `BLOCKED`
with a file); the desk's Monitor also runs `handoffs/owner-nudge.sh`, which wakes a Codex owner whose child waits
on it; each Lean checkpoint is checked by the desk and then by a fresh Codex Astra seat in one complete pass
(`handoffs/decision-audit.sh`, next 050), with a closed list of points.


## State recorded on 2026-11-24, 22:25 UTC and before


Main is `c7deac30`. No team is working, so the desk's watch is not armed; the operator's next message restarts it.
The record of every decision of the day is the runtime file `handoffs/decisions-while-away.md`.

**Waiting for the operator, in order:**
1. **The pattern for every KERI evidence check.** The operator ruled that Singular is parameterized with policies and
   that cardano-keri should not use reward-withdrawal scripts, then reopened the choice on cost. A demonstration on
   the local chain (runtime `commitment-534/handoffs/attestation-at-use-spike.md`) settled two rotations whose
   evidence check is an attestation minted in the same transaction and required in the mint field, the second
   burning the first's token; slightly cheaper than today's observer run by a zero-value withdrawal; no stake
   credential needed; the rotation policy fits the 16,133-byte ceiling with about 140 bytes to spare. The inventory
   of the four withdrawal scripts and their costs is `commitment-534/handoffs/withdrawal-scripts-inventory.md`.
   Asked and not yet answered: adopt the attestation minted at use everywhere? The validators' team and the Lean
   seat are paused on this.
2. **One repair pass for the registration team** (its Q-044): a partial provider answer accepted as the chain tip;
   a multi-line provider reason displacing the transaction identifier from the refusal line.
3. Parked by the operator until the on-chain code is done ("I want the onchain code done before we work on those"):
   evidence that the validator refuses a conviction at a never-rotated checkpoint; the reader's history route; the
   closing-slot theorem (Lean Q-006); whether an underfunded live holding is "active"; the configuration-file key
   for Singular's time setting.

**Decided today (operator):** the inception is proven at the booking by the application mint (#559, constitution
2.1.0 principles XII and XIII, merged); every transaction of `ckeri registry deploy` carries a validity end as
Singular's do; an unobserved publication is reported "unconfirmed", never "unpaid"; a conviction requires a rival
valid under its own rules against the previous event's commitments (ruling of 2026-09-11 confirmed; ticket #573
under #347 and #438), with a comparison of the model's rotation rule against keripy; on-chain code first.

**On-chain order once the pattern is chosen:** the booking's validators for #559 in that pattern; #573, Lean first;
rotation, freeze and deposit if converted; then the rest of the milestone's on-chain tickets. The December registry
is created only when every on-chain change is on main: the trial of 2 December and the demo of 9 December will
move; not yet sized.

**Merged today:** pull requests 554, 560, 565, 566, 567, 568, 570, 571, 561, 572, 575.
**Open:** 564 (Lean of #559, contains main `5d03dfef`, draft), 574 (Lean of #569 on 564, draft; does not close the
ticket), 485 (release, held).
**Filed today:** #553, #555, #556, #557, #558, #559, #562, #563, #569, #573; in Singular #819, #820.

| Team (ticket owner Codex gpt-6.2-astra medium) | Pane | State |
|---|---|---|
| register-351 | %526 | Stopped for the operator (Q-044); candidate `14ec42a0` of the combined deploy repair passed its gates |
| commitment-534 | %527 | Paused at `aba9be3d` on #559's validators (observer-based booking claim withdrawn); inventory and spike delivered |
| follower-353 | %534 | Idle; two pieces of the status slice merged (572, 575); the rest waits on parked decisions |
| lean-569 (Lean writer, Codex gpt-6.2-astra high) | %551 | #569 pushed as draft 574; waits for a start note on #573 |
| tracker clean-up | %432 | Interactive, idle |

Staffing (`rulings/staffing-2026-11-24.md`): writers Claude Sonnet 5.5 high per slice, auditors Codex gpt-6.2-sol
high, Lean one Codex gpt-6.2-astra high writer with no auditor. Codex owners do not stay on their channels: every
delivery goes with `send-pointer`, and `handoffs/owner-nudge.sh` (run inside the desk's Monitor) wakes an owner whose
child waits on it. While the operator was away the desk had each of its answers audited by a fresh Astra seat
(`handoffs/decision-audit.sh`, next 036); that seat changed nine of eleven answers on substance.


## State recorded earlier on 2026-11-24


Main is `5d03dfef`. The operator is away until about 17:30 UTC; while away, every answer the desk gives a team is
audited by a fresh Codex gpt-6.2-astra high seat before delivery, and a question that is the operator's gets a
provisional analysis from such a seat. The full record of the day's decisions, and the list waiting for the operator,
is the runtime file `handoffs/decisions-while-away.md`.

**The day's main finding.** The new design proved an identifier's inception at the fold, where the earlier deployed
validators and ticket #348 prove it at the booking (the application mint). The operator ruled: the application mint
carries the burden of proof; the folder is a role of the Singular registry and knows nothing of the application;
roles meet only on the chain; no layer-two mechanics; stay consistent with Singular. These are constitution 2.1.0
(principles XII and XIII, pull request 561, merged). The correction is ticket #559: its Lean is draft pull request
564 (`ad9566f2`), and the validators (team commitment-534) and the builders and fold wrapper (#558, team
register-351) land with it as one stack. Main has moved since; merging it into the Lean branch conflicts in
generated files and is being assigned.

**Merged today:** pull requests 554, 560, 565, 566, 567, 568, 570, 571 (the Lean reader model of #353), 561.
**Open:** 564 (draft, base of the #559 stack), 485 (release, held).
**Filed today:** #553, #555, #556, #557, #558, #559, #562, #563, #569; in Singular #819 and #820.

**Staffing, changed by the operator today** (runtime `rulings/staffing-2026-11-24.md`): ticket owners Codex
gpt-6.2-astra medium; writers Claude Sonnet 5.5 high, fresh per slice; auditors Codex gpt-6.2-sol high; Lean one
Codex gpt-6.2-astra high writer with no auditor, the desk comparing the statements with the ticket before any push.
Codex owners do not reliably wait on their channels: every delivery to them goes with a direct pointer.

| Team | Work | State |
|---|---|---|
| register-351 | #546 Koios commands slice; then #559 builders, #558 fold wrapper, the trial | Stopped for the operator: a third block (deploy's output line on an ASCII terminal), and `ckeri registry deploy` cannot create a registry through Koios because its first transaction has no validity end |
| commitment-534 | validators of #559; a test of a conviction at a never-rotated checkpoint; rest of #534 | Reviews proceed on existing commits; waits for main merged into the Lean branch |
| lean-569 | #569: the model binds what the validators check | Second seat after a clean handover at `67cd2cf8`; two obligations open with the operator |
| follower-353 | remaining slices of #353 (history, status, endpoint, connected run); #555 from 10 December | First slice authorized; the value question held for the operator |
| tracker clean-up | ticket text for the operator | Interactive, idle |

**Waiting for the operator, most important first:** the deploy publication's validity end (analysis: do as
Singular, a finite window); one more repair pass for deploy's output line; whether a rival accepted in a conviction
must satisfy its own rotation rules (analysis ready); the test at a never-rotated checkpoint when reported; whether
a live holding whose lovelace cannot cover its datum's amounts is "active"; how `ckeri` reads Singular's time
setting from a configuration file; whether the desk moves to a Codex seat; the three later demos; Singular's desk.

**Dates:** preprod trial Wednesday 2 December (approved, ceiling 400 test ADA, nothing signed; the December registry
is created only after every on-chain change is on main; moves if the #559 stack is late); demo 9 December; hosted
reader 16 December (maximum lag 120 slots); the earlier design is removed from 10 December (#555).


## State recorded earlier on 2026-11-24 and before (superseded where the section above says otherwise)


- State at 2026-11-24 07:55 UTC; main is e847279d (pull requests 554 and 560 merged today). THE DAY'S MAIN FINDING: the registration design (#348) and the earlier deployed validators prove the inception when the controller books, at the application mint; the Lean and the new validators on main prove it in the fold, so a folder has to carry the controller's evidence. Operator rules of 2026-11-24, now a draft constitution amendment (pull request 561, version 2.1.0, green, HELD for the operator's word on its text): the application mint carries the burden of proof; the folder is a role of Singular and completely ignorant of the application; the fold is a Singular command and ckeri wraps it with an application adapter; no communication between roles aside from the chain; no layer-two mechanics; stay consistent with Singular. CORRECTION IN PROGRESS, ticket #559: its Lean is approved on three reviews and pushed as draft pull request 564 (head 82823ee2, branch feat/559-lean-inception-at-booking; writer lean-559 pane %511 parked, auditor lean-559-audit pane %512); one hosted check stays red by design until the validators follow, so the Lean, the validators and the builders land as one stack: validators by the #534 team (ticket owner commitment-534, pane %507) after its slice 1, builders (#559-B) and the fold wrapper (#558) by the registration team (register-351, pane %435). The December registry is created only after that stack is on main; the 2 December trial moves if it is late (team dates: 26, 27, 28 November, no slack against 29 November). ALSO RUNNING: the reader-model Lean pair (#353, writer lean-353 pane %499, auditor pane %500): statements and proofs approved, pre-push review in repair; register-351's two pairs (the wallet vault #553, fully approved, before its push; the Koios work, with a half-day refactor that moves the registry commands to their own component). An independent audit of the model against the design finished with eleven findings (owner runtime, model-audit/handoffs/report.md). Tickets filed today: #553, #555, #556, #557, #558, #559, #562, #563; in Singular: #819 (earlier) and #820. The Singular milestone 1 desk was relaunched on the operator's instruction (session singular-M1, pane %510). WAITING FOR THE OPERATOR, in order: pull request 561; what a fold still contains after the correction (the configuration record by reference, the treasury donation, the redeemer); two checks the corrected model proposes at the booking (an unrecordable refund, an inadequate premium); a second pair for the validators; one more statement-only pass for a sentence of the Koios handoff (register-351 Q-034); the audit's four questions (model-audit/questions/Q-003 to Q-006); the hosted reader's lag ceiling; the later demo tickets' content; who runs #555. All decisions of the day are in the owner's runtime, handoffs/decisions-while-away.md.
- SUPERSEDED by the first bullet. State at 2026-11-24 04:30 UTC, operator present since about 02:10 UTC and deciding one question at a time; main is 2e229ae8. FOUR TEAMS RUN in tmux session cardano-keri-M1: (1) the Lean pair on the reader model, a slice of #353 (writer lean-353 pane %499, auditor lean-353-audit pane %500; statements review blocked twice, second repair under way); (2) the registration team register-351 (pane %435) with two pairs: the settlement slice of #546 and the wallet ticket #553, with sizing notes owed for the fold rework; (3) the reader team follower-353 (pane %431), parked after pushing pull request 554 (the pages stop advertising the retired address of the earlier hosted service), which waits for its hosted checks and the owner's merge; (4) a new team on the code of #534, ticket owner commitment-534 (pane %507, Opus 5.5 high, with a Sonnet 5.5 high writer and a Codex gpt-6.2-sol high auditor), window cardano-keri-ms1-t534-commitment-code, worktree /code/cardano-keri-534-commitment-code. The tracker clean-up seat (pane %432) is parked after rewriting #452, #351, #356, extending #455 and moving #453 to #467 to every second Wednesday from 6 January 2027. OPERATOR DECISIONS OF 2026-11-24: reader model: a booked termination is pending termination; only the complete registry history from creation establishes never registered and terminal; the Lean states the replay; the reader answers when one source suffices. Koios: read-only calls with the token at ~/.secrets/koios (never read by a seat); settlement waits for the transaction's first output as public Singular does; Singular's transport is kept (bug lambdasistemi/singular#819); the provider is not a Lockness provider (https://github.com/lambdasistemi/lockness) and the documentation and release of ckeri and Singular say so; the token forwarded on a redirect is to be reported publicly once reproduced. Consistency with Singular ("we have to stay consistent with singular and capitalize the efforts on that CLI"): ckeri adopts Singular's wallet vault (#553, no key or transfer command in ckeri); ckeri registry fold rebuilds the registry state from public history and takes no supplied file; time near a deadline is decided exactly as Singular does (the clock check goes); the command names stay. Preprod trial of 2 December through Koios: scope approved with a ceiling of 400 test ADA, a seat signs with keys passed by path, one folder vault made with singular wallet create, terms deposit 50, freeze bond 5, premium 2, registration cost 1, minimum tip 0.5 test ADA, booking width 100 s, processing time 180 s; nothing is signed before submission through Koios is on main and the owner has checked the team's transaction list. Demo of 9 December (#452): registration as the trial; the ledger-level duplicate refusal and the terminal-key refusal moved to #455. The earlier hosted service is retired; the earlier design's commands are to be removed after 9 December (#555, not assigned). No meeting on 23 December. #534 code starts now; a slice that changes on-chain bytes merges by Sunday 29 November or waits until the December registry is no longer needed. Register #435 gained entry 16 (the byte-level correspondence covers data the ledger admits). The registration team builds ckeri status through the provider after submission. A note for the Singular desk (redirect fix, the provider statement, a plain transfer command, the confirmation window) sits in the inbox of Singular's desks; the operator dispatches it. STILL OPEN WITH THE OPERATOR: whether the fold rework must be in place for the trial (after the team's sizing); how the folder's vault is funded if Singular has no transfer command by then; the lag ceiling of the hosted reader for 16 December; the content of the later demo tickets where it no longer matches (local store instead of Koios; the cutover demos #457 to #459); four leads not filed; who runs #555. Everything is listed in the owner's runtime, handoffs/decisions-while-away.md.
- RUNNING since 2026-11-24 02:21 UTC, on the operator's word "Start the reader lean": a Lean pair on the reader's status model, a slice of #353 (what a reader answers about one identifier at one chain point: active, pending termination, terminal, never registered or unavailable). Writer lean-353 (Claude Fable 5.2 high, pane %499) and persistent auditor lean-353-audit (Codex gpt-6.2-astra high on the shared server, pane %500), window cardano-keri-ms1-t353-lean-reader in session cardano-keri-M1; worktree /code/cardano-keri-353-lean-reader, branch feat/353-lean-reader-model from main 2e229ae8; runtime roots lean-353 and lean-353-audit under the owner's runtime, each with its brief. Reviews at statements, proofs and before the push; push only on the owner's exact-commit grant; then a draft pull request, Part of #353. Two points inside it are the operator's and not settled: what a reader answers once a termination is booked (the asset sits with the termination request until the fold), and what evidence establishes "never registered"; the statements review cannot be requested before both. The model takes no freshness number. To resume a dead seat: relaunch with the launcher of the staffing line (Claude: env TMPDIR=/code/.lanes-tmp/keri-m1/lean-353 claude --dangerously-skip-permissions --model claude-fable-5-2 --effort high, in the worktree; Codex: env TMPDIR=/code/.lanes-tmp/keri-m1/lean-353-audit codex --remote unix:// --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri -m gpt-6.2-astra -c model_reasoning_effort=high) and point it at its brief and journal.
- State at 2026-11-23 19:10 UTC, operator back since 08:00 UTC. Main is 2e229ae8 (2026-11-24 00:10 UTC); pull request 552 (`ckeri registry return` and the short deposit refused at the node, Part of #351) merged too, so the four registry commands of the new design are on main over the node backend. Merged today: pull request 545 (`ckeri registry register` and `ckeri registry fold`, Part of #351), 547 (the public reader's identity read, Part of #353), 548 (first provider slice of #546), 551 (first Koios slice of #546: Singular's public provider library as a dependency, the Koios reads on recorded answers). Open pull requests: only the held release 485. Filed today: #546 (the command line through a ledger provider, Koios supported), bugs #549 and #550 (two hosted checks that fail for outside reasons; #544 is the third).
- SUPERSEDED by the first bullet (both teams were woken on 2026-11-24). Earlier text: The registration team (ticket owner register-351, pane %435) on #546: P0, P1 (pull request 548) and P2a (pull request 551) are merged; one offline part of P2b (the submission handoff with the resend rule) is built on the local branch feat/546-koios-handoff, unpushed, every line approved except the handoff line, which waits for the operator (public Singular's transport follows redirects; reported as https://github.com/lambdasistemi/singular/issues/819); the rest of P2b (the live transport, the command line's provider choice, submission), P4 (one preprod run through Koios); its slices S4 (refusals, `registry return`; parked with a handoff at local commit 1493bb60) and S5 (pages) of #351 come after P2. PARKED: the reader team (follower-353, pane %431): its remaining slices of #353 wait on the Lean reader model. IDLE: the tracker clean-up seat (pane %432) with two unread inbox notes, waiting for the operator.
- Operator decisions of 2026-11-23, in order. (1) The fold's final report: the node client is not linked to the command's thread for register and fold; a dead connection is the failed result of a node call; no worker thread, no waiver. (2) The stated bound after a connection ends is the true one (the node client's one-second release timeout on the path where a query has acquired) and that path is tested live. (3) The project fixes no freshness number: the limit depends on the network and belongs to the deployment and the client; the reader service takes it as a required setting with no default, and it governs every route of registry mode ("up-to-date chain following is a requirement"); the version 1 service keeps its fixed 60. (4) No new line on the model's consumer design page for now. (5) The hosted reader for the new design is the content of the 16 December demo. (6) The public reader is not for our command line: the command line reads and writes through a ledger-provider interface, Koios supported; the local node is a separate unsupported backend that implements the same interface. (7) Interface: the commands keep their own runtime record; the Koios instance is built on public Singular's Koios client (public main 8280da7b). (8) The 2 December trial runs through the Koios provider, no fallback to the node socket; it moves if the instance is late. (9) On Koios a submission that got no answer may be resent as the identical signed bytes; never a new transaction.
- Withdrawn by those decisions: the provisional answers that fixed 60 slots for the new reader, that made Koios answer "unsupported" for the new design, and the `ckeri status` paths through the hosted reader and the local store for the new design.
- SUPERSEDED by the first bullet. Earlier list of open items: read-only calls to public preprod Koios from the development machine without a credential, to record fixtures and measure Koios's delay (holds P2b and the trial); what the commands trust of the provider (register-351 question Q-024); the token file for the trial; the two points inside the reader model (the booked termination; the evidence for never registered); preprod scope and spend and a second key for the fold; whether the team meets on 23 December; the rewording of #452, #351, #356; the old-design service at ckeri.dev.plutimus.com, which does not answer (restore or retire, and the pages that advertise it).
- Everything decided and everything pending is listed for the operator in the desk runtime, `handoffs/decisions-while-away.md`.


## State recorded on 2026-11-22 and earlier (superseded where the section above says otherwise)

- State at 2026-11-23 04:35 UTC, operator away until about 07:30 UTC. NOTHING IS RUNNING: both teams parked on purpose with written questions for the operator (the registration team at 04:31 on the fold command's final report, file handoffs/reporting-question.md in its runtime, after twelve reviews and an audit that said to hold it; the reader team at 00:10). Their panes (%435, %431) are idle; each is woken by an inbox note with a pointer once the operator decides. The owner's watch is not armed. Start from handoffs/decisions-while-away.md in the owner's runtime. Main is c0a622c1 (pull request 542, the follower's declaration page, merged at 01:06; bug #544 filed for the hosted Dev shell job failing intermittently in cabal's package-list update). The #353 team parked itself at 00:10 with a resume record: its slices 1 and 2 are merged, its status-read slice is approved and held unpushed until the model-side declaration exists. The registration team is on its third slice (`ckeri registry register` and `fold`): every line approved except the fold command's stop report under a node-client failure, eleven rounds so far, each owner answer corrected by a fresh audit; a re-cut of the slice was proposed by the owner and blocked by an audit (it would publish a fold whose outcome can be lost). Earlier state follows. Main was 4f585511 at 00:10. Merged since 2026-11-22: pull requests 537 and 541 (first and second slice of #353: the consumer rule in the Haskell library; the follower and the indexer read the registry design beside the old reader mode, with the indexer tests now in the hosted checks), 539 (the release identity type shared by reader and deployment), 540 and 543 (first and second slice of the registration work under #351: the registration builders in the deployment library; `ckeri registry deploy`, which never uses an output carrying a reference script or data as seed, funding or collateral), and 538 (the Lean for #534, with register #435 entries 13 to 15 and the new #534 body published by the owner). Open: pull request 542 (docs: what the follower observes and when a read is unavailable), fully green, being rebased, merged next. Running: the #353 team on the status read of a live identity (built, reviewed by its auditor, held from publication until the model-side declaration exists) and the registration team on `ckeri registry register` and `fold`. No Lean seat is running: an audit found that starting the reader model, or any Lean work, without the operator is not the owner's to decide. Every answer given to a team while the operator is away was obtained from, or audited by, a fresh Codex gpt-6.2-astra seat (twelve audits of the owner's own decisions, nine answers to waiting questions); the list for the operator, with what waits for them, is handoffs/decisions-while-away.md in the owner's runtime. Nothing was signed, funded or submitted on preprod; the provisional terms for the demo registry are a deposit of 50 test ADA, booking width 100 s, processing time 180 s, and the preprod wallet holds about 1,067 test ADA.
- Operator decisions of 2026-11-22 on planning. (1) No migration is planned or supported, on preprod or on mainnet: a deployment is always fresh. The Lean has no migration; the code and about 70 doc pages still carry one, and the tickets #279, #328, #356, #458 and #512 are built on it and await rewriting or closing. (2) Demos are played on Wednesdays at the team meeting. Plan as last stated by the operator: the registration story (#452) is played on preprod on Wednesday 2026-12-09, with a trial deployment and one registration on preprod aimed at Wednesday 2026-12-02; the local-chain run is the rehearsal before it. The owner read this as lifting the 28 October hold for deploying the new design on preprod (fresh registry); the release (#357) and pull request 485 stay held. (3) A second team started the same day on the installed registration command and the deployment: ticket owner register-351 (pane %435, Claude Opus 5.5 high, worktree /code/cardano-keri-351-register, branch feat/351-register-registry), with a Sonnet 5.5 commit owner and a Codex gpt-6.2-sol auditor; it makes no preprod transaction before the owner answers its question on wallet and key. The release identity type is defined once, by the #353 team, and consumed by this one. Still to be answered by the operator: what the Wednesday 2026-12-16 demo shows now; whether the team meets on 2026-12-23 for the rotation demo (#453); the #353 question on the reader's status rule (four parts). Tickets #452, #351 and #356 are not yet reworded. A clean-up seat (Codex gpt-6.2-astra, pane %432, runtime tracker-cleanup) works with the operator on the open tickets.

- Desk: pane %240 in tmux session cardano-keri-M1, window 1, on Claude Fable 5.2.
- Staffing, decided by the operator on 2026-11-22 for this milestone only: on Aiken tickets the persistent auditor runs on Codex gpt-6.2-sol at high effort (launcher `codex --dangerously-bypass-approvals-and-sandbox -C <worktree> -m gpt-6.2-sol -c model_reasoning_effort=high`, checked on client 0.169.0); the ticket owner stays on Claude Opus 5.5 high and the commit owner on Claude Sonnet 5.5. Lean tickets have a writer on Claude Fable 5.2 at high effort and, new, a persistent auditor on Codex gpt-6.2-astra at high effort (`codex --dangerously-bypass-approvals-and-sandbox -C /code/cardano-keri -m gpt-6.2-astra -c model_reasoning_effort=high`). The Lean auditor never talks to the writer and gives a verdict through the desk at three points: after the theorem statements, after the proofs, and before the push.
- Decided by the operator on 2026-11-22, on its own: the commitment's deployment field is bound (bug #508), as the Lean writer had been told. Also decided on its own the same day: #353 starts now, in parallel with the Lean for #534; the code slice of #534 goes to the same team once the Lean is approved. Nothing awaits the operator.
- Main is 863727ab. #353 (follower, indexer and query endpoint on the version 2 datum and the registry leaf) is running since 2026-11-22 on the operator's decision (first launched by the desk on a misreading, parked, then started by the operator): ticket owner follower-353 (pane %431, Claude Opus 5.5 high), worktree /code/cardano-keri-353-follower, branch feat/353-follower-v2; it launches a commit owner on Claude Sonnet 5.5 and a persistent auditor on Codex gpt-6.2-sol. It works on a local test chain only, in slices it proposes first, and does not index bounty commitments because their shape is changing under #534.
- #534 (Lean: a conviction pays only the payee of a commitment opened beforehand) is running with a new Lean pair launched 2026-11-22: writer lean-534-b (pane %429) in the worktree /code/cardano-keri-534-lean-commitment on branch feat/534-lean-conviction-commitment (local head e985574b, five signed commits rebased on 863727ab, unpushed; the remote branch holds 7ce18f9b; no pull request) and auditor lean-534-audit (pane %430, own detached worktree /code/cardano-keri-534-lean-audit). The earlier writer (lean-534, Opus 5.5) was retired the same day with a hand-over record and an unbuilt patch under its runtime handoffs. The operator answered both open decisions on 2026-11-22: (1) a commitment names the identifier and the key state it accuses (epoch and sequence number) in place of the checkpoint output, so a top-up, a freeze or a poison leaves it valid and only a rotation voids it; (2) the commitment's deployment field is bound to the deployment that settles the conviction, which closes bug #508 on the code side. The minimum age of a commitment stays at one: the operator ruled a longer age out because it delays every honest conviction. Two limits remain and go into #435 once the writer supplies the text: a rotation voids an open commitment, and a block producer that makes two blocks in a row can take the deposit.
- Order for #534: the writer rebases onto 863727ab, then Lean, vectors, simulators and the design page, and lists every Aiken and Haskell place the new commitment shape reaches. The desk reviews before any push. An Aiken slice (commitment format, entitlement check, deployment equality) follows on the same branch with the Aiken team.
- Unchanged from 2026-11-16: #435 entry 12 (the rotation premium and the freeze bond go to whoever lands the transaction, accepted as a known limit); #334 closed; #343 closed (PR 535); bug #536 open; the milestone wiki is not republished; held #356, #328, #357 and release PR 485.

# Current state — 2026-11-16

- Desk: pane %240 in tmux session cardano-keri-M1, window 1. The desk model was switched to Claude Fable 5.2 by the operator on 2026-11-16; the staffing of the teams is unchanged (Lean tickets: one Claude Opus 5.5 high writer; Aiken tickets: ticket owner Opus 5.5 high, commit owner Sonnet 5.5 high, persistent auditor Opus 5.5 high).
- Main is 863727ab. #343 is closed: its last item, the consumer example reading checkpoints left by genuine registration, freeze and conviction journeys on a local test chain, merged as PR 535 on 2026-11-16. The team consumer-journey-343 (ticket owner pane %426) is closing its seats.
- Operator decision 2026-11-16 (#435 entry 12): the premium of a rotation and the freeze bond go to whoever lands the transaction; a block producer can substitute itself. This is accepted as a known limit of the design, with no Lean or code change. The deployed premium and freeze bond, to be chosen before #356, account for the captured share.
- #334 is closed as completed: the claim, burn and reap steps it wanted deleted were already gone, and the bounty commitment and the entitlement check are kept because conviction relies on them.
- #534 (Lean: a conviction pays only the payee of a commitment opened beforehand) is running with one Lean writer (pane %425, runtime lean-534). Its candidate 7ce18f9b is pushed to the branch feat/534-lean-conviction-commitment, with no pull request. It is parked on two operator decisions: (1) a top-up, rotation or freeze spends the checkpoint output a commitment names and so voids the commitment, which lets a block producer take the deposit for the price of one premium; record it as a limit, or make the commitment name the key state instead of the output (desk recommendation); (2) bug #508, whether the commitment's checkpoint-policy field is bound (recommended) or not. The branch needs a rebase onto 863727ab before a pull request.
- Bug #536 filed: check-version-remnant-sweep fails on main and runs in no hosted job, so the full local run cannot pass.
- A paper on checkpoint monitoring (two fixed monitors, a reward per update) was compared with this design in an artifact for the operator; its reward formula assumes exactly two monitors and does not price the premium here.
- Open in the milestone after this: #353 (follower and indexer on the version 2 datum), #351 (owner commands), #352 (hunter daemon), #347, #340 and #344 (to be reconciled against what landed under #339 and #345), the debt tickets #508, #511 to #516, #521, #524, #536. Held: #356, #328, #357 and release PR 485.
- The milestone wiki still shows an older story projection and is not republished.

The sections below are earlier snapshots and remain valid where not superseded above.

# Current state — 2026-10-31

- Desk: Claude Opus 5.5 in pane %240 (Codex seats retired by operator ruling of 2026-10-30).
- #437 retained parking merged as PR 486 (ff78b1c).
- #439 exact consumer identity: PR 487 merged as 9d23a8c; #435 entry 4 updated; issue closed.
- #477 Aiken consumer of the published Singular package: PR 488 merged 2026-10-30 as 2a92c4b; issue closed.
- #343 consumer check in Aiken: PR 491 merged 2026-10-30 as 4554970 (predicate mirrors the Lean clause for clause, 47 predicate tests, 8 validator tests, 7 node-evaluated local-chain cases, 11 caught mutants; labelled test encoding and seeded holding). Issue stays open: next slice binds the #489 bytes and reproduces the vector table; genuine registration journey is #324. Team: ticket owner Opus 5.5, commit owner Sonnet 5.5, auditor Opus 5.5.
- #489 concrete consumer identity bytes in Lean (AID key = qualified CESR text bytes; layout = public Singular preimage module; BLAKE2b-256 in Lean; 8-row checked vector table): PR 490 merged 2026-10-30 as 2c10e45; #435 entry 4 updated; issue closed. Binding the Aiken predicate to these bytes is the next slice of #343.
- Paused 2026-10-30 21:15 UTC and resumed by the operator 2026-10-31 05:55 UTC. #495 (on-chain owner-exit removal, consumer Parked state removed too) merged as PR 496 (9f796bb); #343 item 1 ticked.
- 2026-10-31: #497 (ckeri close and reopen removed from offchain/, plus the Koios classifier that read conviction burns as closes) merged as PR 499 (922e46c). #498 (V2 checkpoint datum and concrete consumer decoder in Lean) merged as PR 500 (68d333d); #435 entry 4, #339 and #343 updated. Operator decisions: the Lean declares V2 first; the AID is carried as qualified CESR text; poisoned, frozen, born-at, refund and termination are datum facts while pool and bond amounts come from the output value (a separate value obligation, #339). Desk ruling: realizesState compares the datum facts only. The #343 Aiken decoder for the V2 datum merged as PR 501 (8391716); #343 keeps only the registration journey (#324). #502 (checkpoint output value in Lean) merged as PR 503 (0eab1e1). Operator decisions 2026-10-31: minimum ADA is separate and equals the registry Mc; the registration carrier is Mc + D + B + pool0 with pool0 chosen per registration; desk rulings under them: registry D = D + B, locked = carrierAda - Mc. Running: lane datum-v2-onchain (Aiken team, ticket owner Opus 5.5 pane %309) makes the checkpoint validator write V2 with the exact held value (#339), one PR per slice: slice 1 (V2 codec, value and generated vectors) merged as PR 504 (771a83d); slice 2 register + value + born_at + refund_to running. Operator decisions 2026-11-01: convict follows the Lean now (pending output holding Mc, no burn); premium P now with an output-index payee in the Advance redeemer; born_at is the upper validity bound. Desk took the recommended readings where the operator had no preference: two-step freeze removed (one-step freeze is #345). Operator ruling 2026-11-02: the freeze race is accepted (no privilege to rotate; a sponsor keeps the pool at or above P to protect B), the Lean one-step freeze stands. Paused 2026-11-02 by the operator while this was decided; #339 lane datum-v2-onchain PAUSED with nothing in flight; resumed 2026-11-02 under A-001. Operator decision 2026-11-02: the refund address belongs to whoever pays the registration, unsigned, fixed for life (#505 merged as PR 506, 7ba8517; #435 entry 9; eight dependent issues annotated). #339 slice 2 (two-step freeze and V1 migration-in removed) merged as PR 507 (ee2851e); slice 3, the switch to V2, merged as PR 509 (a152ee5) with the Lean pending-datum commit first. Operator decision 2026-11-04: the pending-termination datum carries no key material (aid, sn, epoch; at most 72 bytes), so every live checkpoint stays convictable with the fixed Mc (2 ADA covers it up to 5,780 lovelace per byte). Slice 4 (older combined checkpoint.ak and the V1 constructor deleted) merged as PR 510 (37af9b7). #339 closed as completed 2026-11-04; its ownerless limits filed as #511-#516. Running: lane freeze-345 (Aiken team, ticket owner Opus 5.5 pane %326), the one-step freeze and the deposit rotation as the Lean states them; the deposit intent bytes must come back as a question. Operator decisions 2026-11-04: the deposit intent binds the exact spent output, names the amount that moves (B or 0), a zero deposit is accepted, and the bytes are declared in the Lean first: #517 merged as PR 518 (7a3b95c). #345 delivered and closed: one-step freeze PR 519 (5692aad), deposit rotation PR 520 (cda64ca). Bug #521 filed (backend-check flake check red in the sandbox). Running (operator choice 2026-11-05): lane topup-346 (Aiken team, ticket owner Opus 5.5 pane %332), top-up. Operator decisions 2026-11-05: a premise-free top-up is a contention-griefing vector, so registration requires the initial pool to be at least P, and a top-up is allowed at most once between two rotations, for at least P (flag topped_up in the V2 Live datum, cleared by rotation). #346 and #522 delivered as PR 523 (c5c82a8). 2026-11-05 to 06: all org CI runners were down (github-runner 2.336.0 deprecated by GitHub); escalated to the machine owner, fixed by infrastructure a12dd24 (2.338.0). Bug #524 (narrate.py) filed. Next (operator 2026-11-06): the registry fold (#348, #350), after its model prerequisite #468. #468 decisions: only the fold spends a request in its window; after the deadline anyone returns everything but the tip to the request refund address; the window is a deployment parameter from the booking upper bound. #468 merged as PR 525 (7da669b); #435 entry 10. Running: lane registry-348 (Aiken team, ticket owner Opus 5.5 pane %340), registration approval and the Singular-backed fold on a local chain; #350 follows. Operator decisions 2026-11-08: the KERI Lean first imports Singular public models/singular-application-held and states the KERI application against it (#526 merged as PR 527, 5ba2bfa; #435 entry 11). #348 slice 1 (configuration record, Singular registry pin, state(A) on chain) merged as PR 528 (a3d02d0). Operator decision 2026-11-10: the delivered checkpoint lives at its own validator (checkpoint_register); the configuration record names it; desk: the consumer checks that credential. #348 slice 2 (booking, request spend, fold, return, consumer checks the checkpoint credential) with the #529 Lean (holding address, exact initial state, closed mint) merged as PR 530 (4bc2995). Desk: one request per fold (declared limit); the application validator keeps the Singular template by hash (size). #348 slice 3 merged as PR 531 (1b6d075): checkpoint_register recognises the registry active token, its Register mint and MigrateOut retired (operator 2026-11-10: retire migration), builders and the devnet journey book, fold by another party, return. #348 slice 4 (a second registration of a registered AID cannot be folded: builder refusal and ledger race; identities page) merged as PR 532 (0556f3c); #348 closed as completed 2026-11-11. #350 Lean (termination booking: anyone books after a conviction, one approval, booker keeps Mc - Mr - tip, treasury gets the request less the tip at the terminating fold; terminal key refused) on branch feat/350-lean-termination (6ae107d). #350 delivered as PR 533 (9596a8d): a convicted checkpoint is released only into a termination booking (anyone), the terminating fold (anyone) makes the key terminal and pays the treasury the request less the tip; re-registration of a terminal key cannot be folded. #324 epic now has #348 and #350 delivered; the fold donates the registration costs to the ledger treasury; a foreign registry is refused on chain. Desk: the approval commits deposit = carrierAda exactly; singular/registry pinned at d69ab005 in onchain. Bug #508 (a bounty reservation checkpoint policy is checked by no program) filed by an investigator; #334 and #319 would delete that machinery, refund_to is full address bytes bound by the signed intent, token names stay over the raw digest; desk rulings: V1 migration-in removed, MigrateOut kept. Then #324, #325, #354 on a local test chain.
- 2026-10-30 morning goal met: #439, #477, #489 and #343 merged in part (PRs 487, 488, 490, 491, 492). #343 parked open: datum layout in Lean, registration journey #324.
- #493 merged as PR 494 (1a73568): the Lean, simulators, corpora and docs have no owner exit. Open economic item: an honest owner cannot recover deposit, freeze bond or pool except through conviction or premiums. 26 affected issues rescoped 2026-10-30; #229 closed not planned; #227 retargeted to signing for rotation and poison intents; #343 rescoped (remove Aiken parked state, datum decoder binding, registration journey).
- Operator ruling 2026-10-30: no owner exit; a checkpoint is alive until convicted (parking economics unsettled: deposit holder while parked, sponsor tracking; parking returns only with an economic model settling both). #342, #349, #358 closed as not planned; #435 entry 2 records it. #493 (one Opus 5.5 writer, window cardano-keri-ms1-lean-no-owner-exit) removes park, revive and owner close from the Lean first; Aiken and off-chain follow-ups and issue rescoping come from its affected-issues list.
- Order now: #493 Lean; then the Aiken and off-chain follow-ups it names; then #324, #325, #354 on a local test chain.
- Held: #356 preprod deployment, #328 cutover, #357 release, and release PR 485.

The sections below are the 28 October intake record and remain valid where not superseded above.

# Identity core milestone — current delivery snapshot

Updated 28 October 2026. As an identity controller, register once, maintain a witnessed checkpoint, park and revive with the retained token and last key state, and have proven duplicity permanently retire the identity. As a relying application, use the exact checkpoint asset and canonical registry to authorize a real downstream transaction within its validity interval.

Current delivery is limited to a local test chain. Preprod deployment, cutover and release remain held. The code is not for mainnet. This snapshot replaces the September execution order; historical evidence remains in the linked issues and pull requests.

## Current evidence

Main is a4c103726c41c5f3d2ab4788bec92ff28efbb0aa. The concrete duplicity model and qualified theorem identity repair landed in [PR #483](https://github.com/lambdasistemi/cardano-keri/pull/483), closing #438 and #387. This establishes the bounded model and simulator results described there, not Aiken/Haskell or connected ledger correspondence. No open pull request was reported at intake.

## Delivery order

1. Bind the KERI Lean model to the exact public Singular main revision delivering the new contract. Align retained parking (#437) and the consumer's exact token, registry and validity end (#439). Public upstream delivery: [registration](https://github.com/lambdasistemi/singular/issues/742), [termination](https://github.com/lambdasistemi/singular/issues/743).
2. Deliver the reproducible pinned Aiken consumer check (#477). Its technical compatibility evidence does not accept application behavior.
3. Implement the consumer mirror (#343), park (#342) and revive (#349) against the accepted model.
4. Integrate the application (#324), packaged commands (#325) and connected local story replay (#354). Request custody, reclaim and refunds still depend on #468; these obligations are not waived by this order.
5. Hold preprod deployment (#356), cutover (#328) and release (#357). Other independent work is not dispatched by this snapshot.

## Contract evidence

The conviction row in registry.md now names the enforcing model declarations and finite controls from PR #483. Production enforcement remains open. Remaining legacy registry rows retain their original evidence limits; none gains acceptance from this sweep. Retained parking, exact consumer identity, request custody and connected implementation correspondence remain open requirements.

## Recovery and reporting

The current session and authorized writer arrangement are in session.md. The complete prior snapshot is preserved locally under /home/paolino/.orch-runtime/cardano-keri/m1/handoffs/prior-milestone-snapshot, bound to revision 62d696da14e882c3389ab37c6d072828ffb7eb0d; unresolved historical decisions remain subject to their current issues and accepted rulings. No implementation worker is active at this intake. The milestone owner reviews statements before push and grants merge only after exact-head checks and acceptance review.

The [milestone wiki](https://github.com/lambdasistemi/cardano-keri/wiki/Milestone-1) still contains an older story projection. Its last observed remote revision is c027adaa79187af27759f223926626b82ffcde55. Full story reconciliation and publication are pending; this snapshot does not claim the wiki is current.

## Issue inventory

This is a state census, not an acceptance claim. Closed requirements retain the limits stated in their issue and PR records. Every open issue remains an obligation unless explicitly superseded; state alone does not settle dispatch or acceptance.

| Issue | State | Title |
| --- | --- | --- |
| [#15](https://github.com/lambdasistemi/cardano-keri/issues/15) | closed | docs: re-vet the canonical permissionless model |
| [#24](https://github.com/lambdasistemi/cardano-keri/issues/24) | closed | epic: the V1 validator — an identity's on-chain life, from registration to retirement |
| [#26](https://github.com/lambdasistemi/cardano-keri/issues/26) | closed | feat: migrate legacy entries and restrict shutdown so owners cannot lose their data |
| [#43](https://github.com/lambdasistemi/cardano-keri/issues/43) | closed | docs: roadmap page — milestone layout and overall plan |
| [#44](https://github.com/lambdasistemi/cardano-keri/issues/44) | closed | demo(identity): watch it work end to end — one identity, one key rotation, two attacks that fail |
| [#49](https://github.com/lambdasistemi/cardano-keri/issues/49) | closed | docs: fix status claims in vlei.md gap table; super-watcher and runway notes in roadmap |
| [#68](https://github.com/lambdasistemi/cardano-keri/issues/68) | closed | design(identity): freeze weighted CheckpointDatumV1 and CBOR boundary |
| [#69](https://github.com/lambdasistemi/cardano-keri/issues/69) | closed | fix(super-watcher): burning an identity's record must leave a permanent tombstone, not erase it |
| [#70](https://github.com/lambdasistemi/cardano-keri/issues/70) | closed | fix(identity): the emergency freeze exposes the identity's reserve key without rotating to it |
| [#71](https://github.com/lambdasistemi/cardano-keri/issues/71) | closed | spec(identity): fully specify the emergency-freeze transaction and sign the key it reveals |
| [#72](https://github.com/lambdasistemi/cardano-keri/issues/72) | closed | fix(identity): a single freeze signature can be replayed to keep an identity frozen forever |
| [#75](https://github.com/lambdasistemi/cardano-keri/issues/75) | closed | design(super-watcher): the misbehaviour bond is advertised as a guarantee it cannot yet deliver |
| [#76](https://github.com/lambdasistemi/cardano-keri/issues/76) | closed | fix(identity): duplicity detection misses real forks and can destroy an innocent identity |
| [#77](https://github.com/lambdasistemi/cardano-keri/issues/77) | closed | fix(identity): rotation redeemer must bind rot_msg to new_next/trie_key/seq_to |
| [#78](https://github.com/lambdasistemi/cardano-keri/issues/78) | closed | design(deposit): the docs disagree about how the security deposit works — pick one model |
| [#79](https://github.com/lambdasistemi/cardano-keri/issues/79) | closed | spec(identity): identity_root single-value vs sliding-window; inception staleness; typing |
| [#81](https://github.com/lambdasistemi/cardano-keri/issues/81) | closed | spec(identity): remove passive delegator field from CheckpointDatumV1 |
| [#84](https://github.com/lambdasistemi/cardano-keri/issues/84) | closed | docs: bring the hash-requirement document up to date with credentials, the CF trust anchor, and the watcher oracle |
| [#106](https://github.com/lambdasistemi/cardano-keri/issues/106) | closed | feat(identity): freeze and fully receipted irreconcilable-fork conviction |
| [#109](https://github.com/lambdasistemi/cardano-keri/issues/109) | closed | chore(88): measure the real cost of blake3 hashing inside full transactions |
| [#135](https://github.com/lambdasistemi/cardano-keri/issues/135) | open | test(e2e): consolidate checkpoint PV11 scenarios into one devnet boot |
| [#156](https://github.com/lambdasistemi/cardano-keri/issues/156) | closed | epic: producer applications — every role behind a CLI (milestone M1) |
| [#157](https://github.com/lambdasistemi/cardano-keri/issues/157) | closed | M1 story: preprod witness pool with a published OOBI list |
| [#158](https://github.com/lambdasistemi/cardano-keri/issues/158) | closed | M1 story: deploy V1 to preprod with a verifiable release manifest |
| [#159](https://github.com/lambdasistemi/cardano-keri/issues/159) | closed | M1 story: a stranger registers their kli identity (incl. 2-of-5) |
| [#160](https://github.com/lambdasistemi/cardano-keri/issues/160) | closed | M1 story: a kli rotation lands on the preprod checkpoint |
| [#161](https://github.com/lambdasistemi/cardano-keri/issues/161) | closed | M1 story: close and reclaim the escrow |
| [#162](https://github.com/lambdasistemi/cardano-keri/issues/162) | open | M1 story: relayer — rotations land with nobody relaying by hand |
| [#163](https://github.com/lambdasistemi/cardano-keri/issues/163) | closed | M1 story: hunter I — freeze, response, claim, thaw on preprod |
| [#164](https://github.com/lambdasistemi/cardano-keri/issues/164) | closed | M1 story: hunter II — witnessed conviction on preprod |
| [#165](https://github.com/lambdasistemi/cardano-keri/issues/165) | closed | M1 story: the endpoint board — a current, on-chain OOBI registry for witnesses |
| [#166](https://github.com/lambdasistemi/cardano-keri/issues/166) | open | M1 story: the stranger run — full lifecycle by docs alone |
| [#168](https://github.com/lambdasistemi/cardano-keri/issues/168) | closed | chore: declare the preprod witness stack in /code/infrastructure (IaC) |
| [#171](https://github.com/lambdasistemi/cardano-keri/issues/171) | closed | epic: the indexer — chain-follower state for every watcher (milestone M1) |
| [#175](https://github.com/lambdasistemi/cardano-keri/issues/175) | closed | M1 story: the follower library — indexed checkpoint state with exact rollback |
| [#176](https://github.com/lambdasistemi/cardano-keri/issues/176) | closed | M1 story: the query endpoint — the follower hosted, answers without a node |
| [#177](https://github.com/lambdasistemi/cardano-keri/issues/177) | closed | M1 story: one interface, three backends — ckeri reads local, hosted, or third-party |
| [#181](https://github.com/lambdasistemi/cardano-keri/issues/181) | closed | M1 story: no cardano-cli in the transaction path — build, sign and submit in-process |
| [#183](https://github.com/lambdasistemi/cardano-keri/issues/183) | open | chore: replace CheckpointTxBuilder's bespoke assembly — import and instantiate the tx-build abstraction |
| [#184](https://github.com/lambdasistemi/cardano-keri/issues/184) | open | chore: audit the settled M1 tree and derive the release-quality remediation map |
| [#185](https://github.com/lambdasistemi/cardano-keri/issues/185) | open | chore: independently prove M1 release quality from a fresh checkout |
| [#186](https://github.com/lambdasistemi/cardano-keri/issues/186) | closed | epic: M1 release hardening — enforce whole-repository quality before release |
| [#196](https://github.com/lambdasistemi/cardano-keri/issues/196) | closed | chore: release pipeline — publish runnable artifacts from cardano-keri (day 0) |
| [#219](https://github.com/lambdasistemi/cardano-keri/issues/219) | closed | onchain: finish the permissionless migration on the advance path (M1, blocks #162/#163/#164/#166) |
| [#220](https://github.com/lambdasistemi/cardano-keri/issues/220) | open | M1 story: hear a rotation — resolve witnesses from the board, fetch and verify the KEL (ckeri verify) |
| [#226](https://github.com/lambdasistemi/cardano-keri/issues/226) | open | M1: register needs two plain UTxOs and says so nowhere — the first-run wall |
| [#227](https://github.com/lambdasistemi/cardano-keri/issues/227) | open | release: ship signing support for next-key checkpoint parking |
| [#228](https://github.com/lambdasistemi/cardano-keri/issues/228) | closed | M1: status crashes without --board-manifest, whose default path only exists in a checkout |
| [#229](https://github.com/lambdasistemi/cardano-keri/issues/229) | open | close routes the entire fee-UTxO remainder to --change-address |
| [#231](https://github.com/lambdasistemi/cardano-keri/issues/231) | open | errors surface as raw GHC IOException traces; the actionable line is buried |
| [#232](https://github.com/lambdasistemi/cardano-keri/issues/232) | closed | M1: collateral exposure is unbounded — a failed script seizes the entire second-largest UTxO |
| [#235](https://github.com/lambdasistemi/cardano-keri/issues/235) | closed | M1: E2E (withDevnet)'s Plutus blueprint is a stale fixed-output derivation, silently decoupled from onchain/ source since 8edfa8b |
| [#237](https://github.com/lambdasistemi/cardano-keri/issues/237) | open | list aborts entirely when one AID has duplicate live checkpoints |
| [#238](https://github.com/lambdasistemi/cardano-keri/issues/238) | open | payer omits UTxO values, and its as_of_slot answers the wrong question |
| [#239](https://github.com/lambdasistemi/cardano-keri/issues/239) | open | ckeri: report parked and terminal identities consistently across read commands |
| [#240](https://github.com/lambdasistemi/cardano-keri/issues/240) | closed | M1: remove Koios from the write path — local tier only |
| [#241](https://github.com/lambdasistemi/cardano-keri/issues/241) | closed | M1: close and board-close still need Koios — the historical-read half of #240 |
| [#253](https://github.com/lambdasistemi/cardano-keri/issues/253) | closed | onchain: OOBI board registration binds no nonce — bind owner + sequence to the witness signature |
| [#254](https://github.com/lambdasistemi/cardano-keri/issues/254) | closed | onchain: support checkpoint validator version migration — do not repeat MPFS's stuck-at-v0 trap |
| [#257](https://github.com/lambdasistemi/cardano-keri/issues/257) | closed | M1: refactor the chain-query layer — free query algebra, providers as interpreters, atomic snapshots |
| [#259](https://github.com/lambdasistemi/cardano-keri/issues/259) | closed | M1: the gate silently rewrites flake.lock — a declared input is unlocked, and nothing checks it |
| [#262](https://github.com/lambdasistemi/cardano-keri/issues/262) | closed | Route every write-path read through the ChainQuery algebra (INV-240-LOCALTIER, split from #240) |
| [#263](https://github.com/lambdasistemi/cardano-keri/issues/263) | closed | The deployed endpoint-board validator cannot be rebuilt from this repository (frozen policy id has no preimage) |
| [#265](https://github.com/lambdasistemi/cardano-keri/issues/265) | closed | Replace #262 public-surface text heuristics with GHC export information |
| [#266](https://github.com/lambdasistemi/cardano-keri/issues/266) | closed | Derive the public-surface guard from GHC export information instead of hand-rolled source scanning (split from #262) |
| [#271](https://github.com/lambdasistemi/cardano-keri/issues/271) | closed | onchain: enforcement bounty payees are unauthenticated — a mempool observer steals the hunter and convictor rewards |
| [#272](https://github.com/lambdasistemi/cardano-keri/issues/272) | closed | constitution + docs: state the KERI projection law, and fix the doc rows that made an audit invent a requirement |
| [#274](https://github.com/lambdasistemi/cardano-keri/issues/274) | closed | epic: the on-chain block — projection law, validator migration, board binding, bounty authentication |
| [#275](https://github.com/lambdasistemi/cardano-keri/issues/275) | open | chore: scrub internal-process leaks from PR descriptions across the repository |
| [#279](https://github.com/lambdasistemi/cardano-keri/issues/279) | open | onchain: inventory preprod v0 checkpoints before the cutover — an ARMED or FROZEN checkpoint blocks it entirely |
| [#291](https://github.com/lambdasistemi/cardano-keri/issues/291) | open | fix: the checkpoint lets the submitter choose which event type it is reading |
| [#318](https://github.com/lambdasistemi/cardano-keri/issues/318) | open | epic K0: the record — design note 003, the Lean merged, the clarity record folded in |
| [#319](https://github.com/lambdasistemi/cardano-keri/issues/319) | open | epic K1: slim main — delete the enforcement economy and the M1.2 skeleton, measure what is left |
| [#320](https://github.com/lambdasistemi/cardano-keri/issues/320) | open | epic K2: INV-BIND on the slimmed tree, and the advance-versus-keripy parity oracle |
| [#321](https://github.com/lambdasistemi/cardano-keri/issues/321) | open | epic K3: receipts budget spike — measure verification cost before the hunter's edges |
| [#322](https://github.com/lambdasistemi/cardano-keri/issues/322) | open | epic: datum V2, rotation, poison and retained-output parking |
| [#323](https://github.com/lambdasistemi/cardano-keri/issues/323) | open | epic K5: the hunter's edges — paid advance, freeze, top-up, conviction |
| [#324](https://github.com/lambdasistemi/cardano-keri/issues/324) | open | epic: KERI application integration with the Singular registry backend |
| [#325](https://github.com/lambdasistemi/cardano-keri/issues/325) | open | epic K7: off-chain — every role behind a ckeri command, and the hunter daemon |
| [#326](https://github.com/lambdasistemi/cardano-keri/issues/326) | open | epic K8: the fifteen stories as the acceptance suite |
| [#327](https://github.com/lambdasistemi/cardano-keri/issues/327) | open | epic K9: docs from the stories, the simulations in every page |
| [#328](https://github.com/lambdasistemi/cardano-keri/issues/328) | open | epic: K10 — preprod cutover and identity-core release |
| [#329](https://github.com/lambdasistemi/cardano-keri/issues/329) | closed | epic U1 (upstream tracking): MPFS permissionless batching |
| [#330](https://github.com/lambdasistemi/cardano-keri/issues/330) | closed | epic U2 (upstream tracking): MPFS gating plugin for the keri registry |
| [#331](https://github.com/lambdasistemi/cardano-keri/issues/331) | closed | Lean checkpoint machine (two slices, 62 theorems) and the checkpoint simulator |
| [#332](https://github.com/lambdasistemi/cardano-keri/issues/332) | open | docs: DESIGN NOTE 003 — the checkpoint, its poison, its bonds and the registry, from the design page |
| [#333](https://github.com/lambdasistemi/cardano-keri/issues/333) | open | lean: fold the simulator's clarity record into the Lean doc comments |
| [#334](https://github.com/lambdasistemi/cardano-keri/issues/334) | open | onchain+offchain: delete the enforcement economy, lifting convict_predicate first |
| [#335](https://github.com/lambdasistemi/cardano-keri/issues/335) | open | onchain: delete the M1.2 skeleton, keep the MPF dependency and the proof-check recipe |
| [#336](https://github.com/lambdasistemi/cardano-keri/issues/336) | open | onchain: the size table of the surviving scripts after the deletion |
| [#337](https://github.com/lambdasistemi/cardano-keri/issues/337) | open | onchain: the advance-versus-keripy parity oracle, with a mutant that flips the witness set |
| [#338](https://github.com/lambdasistemi/cardano-keri/issues/338) | open | onchain: measure advance verification cost by witness count and signer count |
| [#339](https://github.com/lambdasistemi/cardano-keri/issues/339) | open | onchain: datum V2 and registration with the three value components |
| [#340](https://github.com/lambdasistemi/cardano-keri/issues/340) | open | onchain: rotate with bond options and the signed intent |
| [#341](https://github.com/lambdasistemi/cardano-keri/issues/341) | open | onchain: poison — the current quorum declares the epoch untrustworthy |
| [#342](https://github.com/lambdasistemi/cardano-keri/issues/342) | open | onchain: park the checkpoint with its token and last key state |
| [#343](https://github.com/lambdasistemi/cardano-keri/issues/343) | open | onchain: the consumer predicate in Aiken, checked against the Lean's decidable mirror |
| [#344](https://github.com/lambdasistemi/cardano-keri/issues/344) | open | onchain: advance paid from the pool, unpaid when the pool is short |
| [#345](https://github.com/lambdasistemi/cardano-keri/issues/345) | open | onchain: freeze — take the freeze bond when the pool is short |
| [#346](https://github.com/lambdasistemi/cardano-keri/issues/346) | open | onchain: top-up — anyone adds to the pool |
| [#347](https://github.com/lambdasistemi/cardano-keri/issues/347) | open | onchain: convict on a duplicity proof — seize the bond, end the identity |
| [#348](https://github.com/lambdasistemi/cardano-keri/issues/348) | open | onchain: KERI registration approval and Singular-backed checkpoint creation |
| [#349](https://github.com/lambdasistemi/cardano-keri/issues/349) | open | onchain: revive a parked KERI output while the Singular leaf stays active |
| [#350](https://github.com/lambdasistemi/cardano-keri/issues/350) | open | onchain: permanent Singular retirement on KERI conviction |
| [#351](https://github.com/lambdasistemi/cardano-keri/issues/351) | open | ckeri: the owner's commands — register-request, advance with a bond option, poison, close, reopen, top-up |
| [#352](https://github.com/lambdasistemi/cardano-keri/issues/352) | open | ckeri: the hunter daemon — watch the KEL, advance or freeze, convict on proof |
| [#353](https://github.com/lambdasistemi/cardano-keri/issues/353) | open | follower, indexer and query endpoint on datum V2 and the registry leaf |
| [#354](https://github.com/lambdasistemi/cardano-keri/issues/354) | open | e2e: replay the simulator's story trees as transaction sequences on a devnet |
| [#355](https://github.com/lambdasistemi/cardano-keri/issues/355) | closed | docs: the user guide rewritten from the stories, with the simulation on every page |
| [#356](https://github.com/lambdasistemi/cardano-keri/issues/356) | open | preprod: deploy the family and the registry store, reissue the manifests, migrate the operator's identities |
| [#357](https://github.com/lambdasistemi/cardano-keri/issues/357) | open | release: publish the accepted identity-core artifact after version reconciliation |
| [#358](https://github.com/lambdasistemi/cardano-keri/issues/358) | open | lean: bind retained-output parking to next-key and payee authorization |
| [#359](https://github.com/lambdasistemi/cardano-keri/issues/359) | closed | lean: checkpoint machine slice 3 — active / parked(hash) / convicted; leaving is the reap, no withdraw, no unbonded checkpoint (D-040) |
| [#361](https://github.com/lambdasistemi/cardano-keri/issues/361) | open | registry simulator: story trunks end on the state the reader wanted; mechanical refusals become forks |
| [#362](https://github.com/lambdasistemi/cardano-keri/issues/362) | open | gates: assert the denominator — an empty run must be RED, not GREEN |
| [#363](https://github.com/lambdasistemi/cardano-keri/issues/363) | closed | Checkpoint inversions: one public inversion per Step ctor, 100% gate |
| [#364](https://github.com/lambdasistemi/cardano-keri/issues/364) | closed | Registry inversions (+ Step-relation decision) |
| [#365](https://github.com/lambdasistemi/cardano-keri/issues/365) | closed | Historical semantic-atom coverage and non-vacuity witnesses |
| [#366](https://github.com/lambdasistemi/cardano-keri/issues/366) | closed | Lifecycle disposition + hash-bound audit report |
| [#367](https://github.com/lambdasistemi/cardano-keri/issues/367) | closed | Lean FULL close-out: inversions, semantic atoms, and missing mutant surfaces |
| [#368](https://github.com/lambdasistemi/cardano-keri/issues/368) | closed | Hash-bound Lean audit report (serial tail) |
| [#374](https://github.com/lambdasistemi/cardano-keri/issues/374) | closed | Factor simulator session-tree into headless backend modules with CLI |
| [#375](https://github.com/lambdasistemi/cardano-keri/issues/375) | closed | Author simulator scenarios in a terse DSL compiling to the current JSON |
| [#376](https://github.com/lambdasistemi/cardano-keri/issues/376) | open | Devnet runner reads the scenario DSL |
| [#377](https://github.com/lambdasistemi/cardano-keri/issues/377) | open | Promote free-played stories N1–N11 to the acceptance suite |
| [#381](https://github.com/lambdasistemi/cardano-keri/issues/381) | open | epic: Singular backend readiness for Cardano KERI M1 |
| [#382](https://github.com/lambdasistemi/cardano-keri/issues/382) | open | test(e2e): the withDevnet smoke races the validity interval and blocks unrelated branches |
| [#383](https://github.com/lambdasistemi/cardano-keri/issues/383) | closed | Semantic-atom campaign re-cut: gate executability + fresh audit (F-365-001) |
| [#387](https://github.com/lambdasistemi/cardano-keri/issues/387) | closed | two tools truncate qualified Lean names, and both check by count instead of identity |
| [#400](https://github.com/lambdasistemi/cardano-keri/issues/400) | open | the interface we offer, with ckeri as its first consumer |
| [#404](https://github.com/lambdasistemi/cardano-keri/issues/404) | open | Design shared GLEIF KEL/TEL sponsorship without issuer participation in Cardano |
| [#405](https://github.com/lambdasistemi/cardano-keri/issues/405) | open | Pre-fund checkpoint unfreezing with a sponsor-funded locked reserve |
| [#406](https://github.com/lambdasistemi/cardano-keri/issues/406) | open | Protect sponsor funds from issuer-driven rewards and closure |
| [#408](https://github.com/lambdasistemi/cardano-keri/issues/408) | closed | registry: remove pause, the on-chain parked state and grace window after ruling 12 |
| [#409](https://github.com/lambdasistemi/cardano-keri/issues/409) | open | Bring the identity watcher and funding invariants into executable Lean |
| [#410](https://github.com/lambdasistemi/cardano-keri/issues/410) | open | Record Lean invariant coverage and baseline attack traces |
| [#411](https://github.com/lambdasistemi/cardano-keri/issues/411) | open | Ordinary KEL evidence and watcher |
| [#412](https://github.com/lambdasistemi/cardano-keri/issues/412) | open | Challenge alternatives |
| [#413](https://github.com/lambdasistemi/cardano-keri/issues/413) | open | Sponsor ownership and loss |
| [#414](https://github.com/lambdasistemi/cardano-keri/issues/414) | open | Prepaid recovery and shared operation |
| [#415](https://github.com/lambdasistemi/cardano-keri/issues/415) | open | Identity-core composition and review |
| [#416](https://github.com/lambdasistemi/cardano-keri/issues/416) | open | Keep authenticated ordinary KEL key-state history in the checkpoint |
| [#418](https://github.com/lambdasistemi/cardano-keri/issues/418) | open | docs: explain retained tokens, parking revival and freeze in checkpoint stories |
| [#422](https://github.com/lambdasistemi/cardano-keri/issues/422) | open | release: the release pipeline has been red since 7 September — a stale release PR blocks every new one |
| [#424](https://github.com/lambdasistemi/cardano-keri/issues/424) | open | gates: the three simulator gates are wired into nothing — CI never runs them |
| [#426](https://github.com/lambdasistemi/cardano-keri/issues/426) | closed | docs: the registry's upstream is singular, not cardano-mpfs-onchain |
| [#429](https://github.com/lambdasistemi/cardano-keri/issues/429) | closed | docs: link the KERI specification from every story page, at the pinned version |
| [#431](https://github.com/lambdasistemi/cardano-keri/issues/431) | closed | docs: three corrections the onboarding readers surfaced (first-seen, terminal conviction, six programs) |
| [#433](https://github.com/lambdasistemi/cardano-keri/issues/433) | closed | docs: the project's words, define or rename; retire "the M1 return" as a name |
| [#434](https://github.com/lambdasistemi/cardano-keri/issues/434) | closed | constitution: Lean is the behavioral authority, model-first rulings, retroactive |
| [#435](https://github.com/lambdasistemi/cardano-keri/issues/435) | open | Lean correspondence register: where the repository already diverges from its model, as user stories awaiting rulings |
| [#437](https://github.com/lambdasistemi/cardano-keri/issues/437) | open | lean: dormancy in the KERI application — a parked identity keeps its output, the registry leaf stays active |
| [#438](https://github.com/lambdasistemi/cardano-keri/issues/438) | closed | lean: make the duplicity predicate concrete, conformant to KERI 1.1 |
| [#439](https://github.com/lambdasistemi/cardano-keri/issues/439) | open | lean: the consumer predicate gains the exact token, the canonical registry and the validity end |
| [#446](https://github.com/lambdasistemi/cardano-keri/issues/446) | closed | lean: bind to Singular's Lean as a pinned dependency (final re-cut) |
| [#449](https://github.com/lambdasistemi/cardano-keri/issues/449) | open | preprod demos: verify manifests and board state through the indexer |
| [#450](https://github.com/lambdasistemi/cardano-keri/issues/450) | open | plan: reconcile v1/v2 demo milestones with the 0.5.0 release tickets |
| [#451](https://github.com/lambdasistemi/cardano-keri/issues/451) | open | 2026-10-23 — Cardano KERI Singular-backend mapping review (target) |
| [#452](https://github.com/lambdasistemi/cardano-keri/issues/452) | open | 2026-12-07 — Registry-backed identity registration (target) — [Cardano KERI v1.0.0 planned] |
| [#453](https://github.com/lambdasistemi/cardano-keri/issues/453) | open | 2026-12-22 — Identity register and advance (target) — [Cardano KERI v1.0.0 planned] |
| [#454](https://github.com/lambdasistemi/cardano-keri/issues/454) | open | 2027-01-06 — Hunter advance and short-pool branch (target) — [Cardano KERI v1.0.0 planned] |
| [#455](https://github.com/lambdasistemi/cardano-keri/issues/455) | open | 2027-01-21 — Application park/revive and permanent conviction (target) |
| [#456](https://github.com/lambdasistemi/cardano-keri/issues/456) | open | 2027-02-05 — Identity role commands (target) — [Cardano KERI v1.0.0 planned] |
| [#457](https://github.com/lambdasistemi/cardano-keri/issues/457) | open | 2027-02-20 — Identity story suite on preprod (target) — [Cardano KERI v1.0.0 planned] |
| [#458](https://github.com/lambdasistemi/cardano-keri/issues/458) | open | 2027-03-07 — Preprod cutover rehearsal (target) — [Cardano KERI v1.0.0 planned] |
| [#459](https://github.com/lambdasistemi/cardano-keri/issues/459) | open | 2027-03-22 — Identity preprod release journey (target) — [Cardano KERI v1.0.0 planned] |
| [#468](https://github.com/lambdasistemi/cardano-keri/issues/468) | open | lean: KERI owns request processing, reclaim and refunds on the redesigned Singular registry |
| [#477](https://github.com/lambdasistemi/cardano-keri/issues/477) | open | build: pin a reproducible Aiken consumer to the redesigned Singular package |
| [#478](https://github.com/lambdasistemi/cardano-keri/issues/478) | closed | lean: pin a compatible Singular main revision after the Lean 4.27 repair |
| [#480](https://github.com/lambdasistemi/cardano-keri/issues/480) | closed | Reconcile conviction payouts with Singular's ruled termination economics |
| [#482](https://github.com/lambdasistemi/cardano-keri/issues/482) | closed | Lean dependency check: the pinned Singular checkout's hash changes between fetches (fetchgit leaveDotGit) |
