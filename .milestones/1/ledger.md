# M1 — Identity core, witnessed checkpoints on Cardano

Home: `lambdasistemi/cardano-keri`, GitHub milestone 1. **2026-08-14 is a MARKER,
not a gate** — operator ruling 2026-08-06T09:04Z: *time is not the constraint,
demonstrable value is*; M1 releases when the work can be consumed. This inverts
the 08-03 "clean AND on time / all resources devoted" posture and is recorded as
an inversion, not drift.
Desk: tmux session `keri`, window `cardano-keri-ms1-identity-core`, pane `%5511`
(pid 3487682, **claude-fable-5** — context cleared and reseated by the operator
2026-08-06T~12:20Z; previously Opus 5 xhigh; same pane, no succession).
Runtime: `/tmp/ms-keri-1`. Snapshot reconciled 2026-08-06T12:45Z (post-reseat
sweep; children measured by pane, PR measured by gh).

## Outcome test

STRATEGIC CONTEXT 2026-08-04 (source: confidential partner brief held LOCALLY —
partner names never travel to this public ledger): product vision re-anchors to
"public trust anchor" (reference implementation + neutral checkpoint layer +
operator trust economy). Milestones stay as scoped; M1 gains an external
audience; permissionless-advance is load-bearing for the vision.

OPERATOR RULING 2026-08-01: **M1 is a full release of usable executables,
packaged** — satisfied only from a published release. A stranger installs
packaged `ckeri`, and with standard `kli` + published docs alone completes the
full preprod identity lifecycle (register incl. 2-of-5 multisig, witnessed
rotate, freeze/respond/claim/thaw, close + escrow reclaim), every step with a
reproducible transcript and settled txids. #166 owns the audit.

OPERATOR RULING 2026-08-06T09:00Z — **second, closing half of the test: M1 does
not close without a downstream Cardano transaction CONSUMING an identity
checkpoint** (validator resolves it as a reference input, revalidates the five
rules, enforces its own authorization against current key state). Sized by the
operator to the smallest sufficient example: **"mint a CID signed by a KEL"**
(subscription policy + subscription_home validator, 9 negative controls; ask at
`/tmp/ms-keri-1/asks/ASK-t-consumer-example-ipfs-attestation.md`). Belongs in
the M1 demo. Maintaining an identity is not the same as using one.

CUTOVER PRECONDITION 2026-08-13 (#279, desk-filed from e274 RQ-254-10): the
cutover proceeds only from a live preprod inventory showing every deployed
checkpoint in a state the immutable v0 script can EXIT. An ARMED or FROZEN
checkpoint has no authorized exit and cannot be added one — a single such
checkpoint blocks the entire cutover. Re-run immediately before cutover; a
checkpoint can enter ARMED at any time.

NEW M1-EXIT CONDITION 2026-08-13 (operator ruling, via the census disclosure
question): **no money-path census finding is still open when preprod is
announced.** Public issues are permanent and indexed and the announcement
follows M1, so the control sits at M1's EXIT rather than at the census's
entry — costing nothing today, slowing no census, and landing where the risk
actually starts.

M1-CLOSE GATE 2026-08-05 (operator via M8 desk): M8 formal verification blocks
close when ready; ships as a hash-bound evidence bundle ON the ckeri release
line (decision b).

OPERATOR SCOPE RULING 2026-08-03: permissionless-advance is M1 scope (#219) —
done, merged.

First hands-on evidence 2026-08-03 (operator via Qwen agent, release AppImage,
funded preprod lifecycle): PASSES end-to-end; five findings, all UX/onboarding
(F-series below).

## The milestone artifact

| | |
|---|---|
| artifact | `ckeri` (production). Epic #171's `ckeri-follower` fork RETIRED into production `ckeri` at PR #216's merge, with no-loss/no-leak proofs |
| release line | **v0.4.0 LIVE 2026-08-04T08:52Z — first TESTED release** (honest input-addressed E2E gate; 3 assets verified). Erratum live on v0.1.0–v0.3.0 |
| pipeline | #196 done; deliberate residual instrument debt #205, #218 (post-M1, waivers in registry) |
| graduates into | the product `ckeri` release line at milestone close |

## v0.3.0 findings priority (operator: verticality first)

1. **F1** register two-UTxO wall — M1, e156
2. **F2-close** signing helpers not in release assets — M1, e156 (F2-advance dissolved under #219)
3. **F4** board-manifest checkout-path default — executed in e171/#177 board-route PR2
4. **F3** close change-routing ergonomics — post-0.3.0 unless trivial
5. **F5** raw GHC traces — hardening pool (#184)

## Current state

| unit | state | owner / resurrection source |
|---|---|---|
| validator epic #24 | CLOSED | GitHub |
| #219 advance symmetry | DONE — PR #222 merged 2026-08-04 (be3d8860). Phase 2 (offchain plumbing) + preprod cutover remain DESK-GATED, post-#181/#240 | `/tmp/ms-keri-1/t219/` (archive) |
| indexer epic #171 | ACTIVE. #177 CLOSED. OWED to desk: ckeri-query redeploy ask; stale Q-003/8/9 to mark superseded; fresh `.orch/window-brief.md` fragment (current one is 08-03) | `/tmp/ms-keri-1/e171/`; keri:2 `%5189` |
| no cardano-cli tx path #181 | **DONE — PR #221 MERGED 2026-08-07T04:05:31Z** at head dd6b220f (merge commit 11a45d5c), operator-merged, guards verified in the same atomic call (21/21, zero pending, MERGEABLE); issue CLOSED. Slice-4 audit Finding 1 — packaged runner shipped cardanoCli on its internal PATH — repaired under a one-repair fence extension, control proven at CLOSURE level (reintroduction goes RED). ~17h GitHub-side pull_request event-delivery outage diagnosed, survived and proven recovered in-lane. Product claim stands: full preprod write journey on a machine with NO cardano-cli installed | e171 post-merge cleanup owed (8 worktrees at epic close; #253/#254 consumer stories keep the epic open) |
| PAYER RULING 2026-08-06T12:35Z, then DISSOLVED ~14:52 | Fixture = key-derived preprod address `addr_test1vzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehgnv4mdx` (documented address dropped — key never located). Faucet hit a real captcha, NOT worked around; e171 then re-derived the requirement: the 4,028M floor was a SUM, true PEAK lock-up is ~1,015-1,020M lovelace (advance spends the locked input forward, close REFUNDS escrow, manifest is verified not republished) vs 3,993M balance — ~4x margin. NO FUNDING NEEDED; fixture stands; dotted-path doc defect fixed inside slice 4 | relay `/tmp/ms-keri-1/e171/inbox/A-payer-funding-ruled-2026-08-06.md` |
| producer epic #156 | ACTIVE — #257 seated 06:22Z (Codex T.O. + chain), running pre-reset under the operator direct order, machine informed on the record. Q-017 filed and answered (flake-lock contract). #240 queues behind #257. #220 stays OUT of M1. Owes fresh window-brief fragment (08-03) | `/tmp/ms-keri-1/e156/`; keri:3 `%5290` + `%5514` + `%5519` |
| #253 + #254 + checkpoint-consumer example | **PLACEMENT RULED (operator 2026-08-06T12:35Z): ONE NEW ONCHAIN EPIC** bundling #253 board-OOBI nonce, #254 validator version migration, and the consumer example — all touch the validator family and ride the cutover. NOT dispatched: needs machine scope (claude 9 points left; realistically post-weekly-roll). Consumer halves of #253/#254 remain e171 stories | ask file in `/tmp/ms-keri-1/asks/` |
| relayer #162 → hunters #163/#164 → stranger #166 | queued on the dam; #166 audits from a published release | e156 |
| release-hardening #186 (#184→remediation→#185) | PARKED lane-less; pre-arbitration on record: #184 may start on a named near-final candidate with delta re-audit at freeze; #185 binds to the exact frozen tree | GitHub |
| tx assembly #183 / tx-tools#135 | FILED, undispatched; never concurrent with #181 | registry |
| #196 / #168 / #218 / #205 / M1bis / PR #187 | done / done / post-M1 waiver / post-M1 waiver / parked / #179 debt | GitHub, `.archived/` |

## Priority and capacity

0. **PARKED — OMNIA PAUSA 2026-08-14T14:59:45Z** (machine-wide, operator order;
   pause not teardown; park accepted by the machine with every claim
   independently verified). e274 PARKED 15:05:00 clean boundary; e156 PARKED
   15:07:21 with #162 SOURCE-READY-static-unverified at HEAD 466337b4,
   panes/worktree/runtime preserved. Desk watcher killed by exact PID, zero
   after. Store 59.01 GiB, 11.29 above min-free.
   **EPIC #274 COMPLETE IN SOURCE, NONE DEPLOYED** — #272 constitution, #253
   board binding (fb4e58a0), #271 bounty commitment (7a6661b7), #254 migration
   (ae99e35e). **CLOSED IN MAIN, OPEN ON PREPROD.** The cutover stays gated on
   #279 live inventory (an ARMED or FROZEN v0 checkpoint has no authorized
   exit and blocks it entirely), T254-405 consumer-side acceptance needing a
   SECOND SEATED PARTY, and checkpoint-side wiring existing in main only.
   In flight at the stop: #280 (e274), #162 (e156). Carried: floor checks name
   /nix/store never a worktree; a possible machine event is stop-and-report
   never retry; git+https not github:; families claude/codex/grok, agy
   REVOKED, one grok seat per ticket; grok-4.6 pilot THREE TRIALS UNSPENT and
   ineligible for cutover/#279/deployed-validator acceptance; scrutiny tiers
   fixed at spec time and never raised in place. Released only by the machine
   owner, scoped and in writing.

0. **OMNIA PAUSA 2026-08-07T15:28Z — ALL M1 LANES PARKED AND CONFIRMED** (e171
   15:28:25Z, e156 15:51:14Z with child evidence, desk last). Machine-owner
   release only. #257: three commits LOCAL-ONLY (PR #258 head 31b84ff has none
   of the work); submission-2 FINDINGS report 7fb5d470 unprocessed = first act
   on release.
1. **Serial chain to close:** #181 DONE (merged 2026-08-07) → **#257 IN FLIGHT in e156 (query algebra; architecture consolidated in body; #241 re-verify = slice 0) → #259 (flake-lock enforcement, T.O.-ruled SEPARATE) → #240 (consumes the layer)** →
   onchain epic (#253 + #254 + consumer example) → preprod CUTOVER (moves every
   identity; desk-gated) → #162 → #163/#164 → #166 → #186, plus #219 phase-2
   plumbing. M8 evidence bundle gates close when ready.
2. **CAPACITY VOID (ratification 2026-08-07): weekly ROLLED — claude 1% at 08:09Z, +50% promo through Aug 19; nothing rationed. Pause superseded in full; keri released (e171, e156 for #257 then #240); ms8/wallet/csk/trenitalia stay parked.**
   SEAT DISPUTE RESOLVED 14:52: e171 escalated (live-journey asymmetry — an
   exhausted commit owner mid-preprod-journey is irreversible, an exhausted
   auditor is a recoverable delay), machine CONCEDED in full and withdrew its
   flip as a forbidden mid-slice reseat. Slice 4 keeps Claude T.O. %5513 ->
   Codex commit owner %5493 -> ONE fresh Claude auditor. Codex-T.O. flip
   applies FROM #240 ONWARD. Position at ruling: claude 94% (6 left), codex
   25%. TIMING LEVER PRE-RULED: if claude exhausts before the audit, the
   candidate FREEZES and the audit WAITS for the weekly roll — no
   substitution.
3. Time is NOT the constraint (operator 09:04Z). Ceremony never thins for speed.
4. Merge protocol: desk authorizes against a NAMED head SHA green at that SHA,
   undrafted; the LANE runs guard-merge; **desk reports the head SHA to the
   machine at merge time** (machine's explicit ask, 12:24Z).

## Cross-epic contracts steering work

See `registry.md` — including today's two mutations:
`registration-deposit-vs-live-pparams` NONE→ENFORCED 2026-08-06 (mutant-proven,
residual named, feeds #255) and `identity-authorization-model` registered NONE,
deliberately unscheduled (enforcing check arrives WITH the consumer-example
epic; MPFS/cage ruled overkill for M1 — scaling answer goes in the blog).
Standing: #219 offchain fenced till #181; preprod redeploy = desk cutover;
#181/#183 never concurrent; #220 read-path only; pairs model-diverse always;
merge-commit method; desk authorizes merges, owning lane runs guard-merge; M1
never moves the compiled-UPLC proof target silently (ms8/blaster — announce at
acceptance + cutover).

## Resurrection and drift

- Desk `%5511` pid 3487682, claude-fable-5, fresh context 2026-08-06 (operator
  reseat at the pane; same standard-of-evidence caveat as the 08-05 succession —
  the operator was present and typing at the desk). Exactly ONE decision-watch:
  pid 549747 → `%5511`, started 06:22:22Z, verified single.
- e171 relay ack pending at sweep time (pane processing, verified by capture);
  the watcher relays e171 STATUS to the desk pane.
- BOTH epic fragments STALE (08-03): chase e171 and e156 for fresh
  `.orch/window-brief.md` at next contact; do not ghost-write.
- `%5510` (bash, desk window) remains unattributed — operator's, do not close.
- send-pointer exit 124 ⇒ verify STATUS/pane yourself (false-negatived twice
  today; both deliveries were in fact processing).
- Operator housekeeping flag (their funds): sweep 4991.80 tADA off the
  throwaway change address BEFORE deleting docker volume
  `ckeri-qwen-demo-20260803`.
- Eight older e171 worktrees remain retirement debt at epic close.
- M1 blog: ONE consolidated post ships with the milestone; arc settled 09:25Z
  (manage → register → bond-against-yourself → use it); four source drafts
  inventoried on the state page; closing section truthful only after the chain
  through cutover lands.

## Date-talk outcome (was: Thursday inputs)

The 2026-08-06 date talk RESOLVED into the 09:04Z ruling above: value over
time; 08-14 stays as a marker. The shipped-list and remaining-chain inputs that
were assembled for it are superseded by *Current state* and *Priority*.
