# Lean model of the M1 checkpoint lifecycle — goals only (#124)

A standalone Lake project (Lean 4, `v4.27.0`, **zero dependencies** — Lean
core only) that models the M1 checkpoint lifecycle as **the on-chain
validator's transition system** and proves the M1 invariants. Phase 1 of
#124 delivered the statements (all `sorry`); phase 2 (operator-authorized)
delivered the proofs; ticket #127 (the burn axiom) extended the model and
goals — **all 21 goals are proved**, no `sorry` anywhere.

- `CardanoKeri/Lifecycle.lean` — states, actions, guards, value ledger,
  traces (definitions only).
- `CardanoKeri/Invariants.lean` — shared invariant lemmas (the QuickCheck
  property seed inventory for the #114/#115/#116 reworks).
- `CardanoKeri/Goals.lean` — the 21 theorems, statements exactly as
  ratified, fully proved.

## The burn axiom (#127)

**"Everything not spendable — even by reference — is burnt."** A UTxO must be
spendable by some future transition or read on-chain by some consumer; a state
failing both must not exist. Applied here:

- **Convict burns.** The `tombstone` state/role is DELETED; convict from every
  live state goes straight to `.absent`, releasing the FULL carried escrow as
  outflows (`D`→convictor; `B`→armed hunter if from ARMED else convictor; the
  freed min-ADA→convictor). The conviction record lives in the convict
  transaction, in history — not in an eternal UTxO.
- **Reap = the third challenge window.** A new `reaping` state (with `W_reap`,
  the third deployment parameter) reclaims the escrow of a truly-abandoned
  FROZEN (or stale-and-behind CLOSING — see Q-B01) checkpoint: anyone posts a
  reap-intent (`deadline = now + W_reap`); any single permissionless advance
  voids it (topping the successor escrow back to `min + D + B`, generalising
  thaw); an untouched full window lets the reaper burn the UTxO and take the
  remainder. Every exit now burns: close (voluntary), reap (abandonment),
  convict (punitive). The ledger's permanent footprint is exactly the live
  identities.

Role tags (the on-chain datum's role byte; abstracted away in the model, which
carries the role in the state constructor): ACTIVE bare, FROZEN `0x00`, ARMED
`0x02`, CLOSING `0x03`, REAPING = the freed `0x01` (ex-tombstone) or a fresh
`0x04` — reserved, the spec picks at implementation.

Sources: epic #24 Technical contract; the "Permissionless bridging +
incentivised freeze" design note (LOCKED 2026-07-21); the epic-owner
verification note (2026-07-21); the #124 scope correction (2026-07-21).

## Build

```
cd lean
lake build          # with elan: picks up lean-toolchain (v4.27.0)
# without elan:
nix shell nixpkgs#lean4 -c lake build
```

The build passes with **zero `sorry`** (21 goals; goal 13 has a
per-transition form plus a whole-trace corollary, goal 17 was added by ruling,
and goals 18–21 are the burn-axiom additions). No `axiom` declarations
anywhere: `#print axioms` on every goal reports at most `propext` and
`Quot.sound` (both Lean core).

## Lemma inventory (QuickCheck property seeds)

`Invariants.lean` names the machine facts the proofs run on; each is a
candidate property-based test for the reworks:

- `Step.preserves_balanced` / `TraceFrom.preserves_balanced` — conservation
  per transition and along any trace.
- `TraceFrom.last_step` / `TraceFrom.step_at` — every final-state fact is
  witnessed by its producing transition; any indexed transition splits the
  trace.
- `reachable_behind` (+ `Reachable.armed_behind`, `Reachable.frozen_behind`,
  `Reachable.reaping_behind`) — reachable Armed/Frozen/Reaping states are
  genuinely behind, so response, thaw, and reap-void advances are always
  enabled.
- `reap_escrow_topUp` — the reaping escrow plus its thaw top-up recompose to
  `min + D + B` for either origin (the generalised-thaw invariant).
- `Step.advance_target` — every advance lands Active (at exactly `k+1`).
- `fragment_no_four_stalls` — the permissionless fragment stalls out after
  arm → claim → reap-intent: four consecutive non-advance, non-reap-execute
  transitions are impossible (goal 4's engine, the RATIFIED constant-3 bound).
- `active_advance_chain` — the replay ladder: `n` advances whenever the KEL
  extends that far (goal 16's witness).
- `outflowTotal_append`, `initConfig_balanced`, `getElem?_some_lt`,
  `getElem?_isSome_of_lt` — bookkeeping.

Proof-shape facts worth vectoring: a claim is always index-adjacent to the
arm/challenge that set its deadline, and a finalizeClose is always
index-adjacent to its closeIntent (nothing can sit between without leaving
the state).

## Scope: the validator, nothing else

Per the scope correction (2026-07-21) the model is exactly what the
on-chain code admits or rejects. There are **no actors, no honesty labels,
no fairness assumptions, no economics** — those live in docs/blog, never
here. Consequences:

- Original goal 10 (`close_lie_never_finalizes_under_liveness`) is
  **dropped**: challenger fairness is off-chain. The on-chain guarantee is
  goal 9.
- Goals 4, 6, 16 are restated machine-level (see the table).
- The one place actor-hood survives is the closeIntent guard, modeled as
  the abstract capability `Env.canClose k` — "a valid signature by the
  seq-`k` datum keys is presented", i.e. the signature check the validator
  performs, nothing about who holds the keys.

## The KEL-abstraction boundary

The validator never sees "the KEL". Per action it verifies signatures and
witness receipts over `event_bytes` binding the submitted event to the
datum's committed key-state (the #106/#114/#115 machinery). The model
collapses that entire verification stack into three environment predicates:

- `Env.kel.hasEvent s` — "a validly-signed, witnessed event at sequence `s`
  can be presented". `behind k := hasEvent (k+1)`; the well-formedness field
  of `Kel` (the i-th event carries seq i) is the projection-determinism
  precondition: the only admissible advance target is the real event `k+1`.
- `Env.fork` — "verifiable fork evidence is presentable" (convict guard).
- `Env.canClose k` — "a seq-`k` datum-key signature is presentable"
  (closeIntent guard).

Everything below these predicates — CESR parsing, signature verification,
receipt thresholds, hash chaining — is out of model. The theorems therefore
say: *given sound event verification, the transition system has these
properties.* They say nothing about the soundness of the verification
itself.

Two further modeling choices at the same boundary:

- **The environment is fixed per trace** (the KEL does not grow mid-trace).
  Each theorem quantifies over one `Env`. Growth only ever adds behind-ness
  (the tip moves away), so armed/frozen states are behind whenever they are
  reachable; this is what makes Frozen always thawable (goals 1, 2).
- **A transition's single `slot` abstracts the transaction's validity
  range** (attacker-pessimal deadline semantics, verification obligation 2):
  `deadline = slot + W`; responses require `slot < deadline`, claims and
  finalizations `deadline ≤ slot`. Traces are non-strictly slot-monotone.

## Value accounting

`carried` is the value-ledger rule (Active/Armed/Closing hold
`min + D + B`; Frozen `min + D`; Reaping `reapEscrow origin` = `min + D`
from FROZEN or `min + D + B` from CLOSING; Absent `0` — everything burnt or
paid out); the `Ledger` tracks cumulative pay-ins (`deposits`: register, thaw
re-post, reap-void top-up) and an append-only payout log (`outflows`), each
payout tagged `bounty` (B to a hunter), `forfeiture` (to a convictor),
`refund` (finalized close) or `reap` (the reaper's burn). Conservation
(`Config.balanced`): carried + paid-out = paid-in. Third-party pay-ins (thaw
and reap-void re-posts) are donations — the machine records no creditor.

## Invariant ↔ theorem map

Side-conditions were flagged as Q-L01..Q-L03 and ratified by the epic-owner
rulings A-L01-03 (2026-07-21); "—" means the goal is stated with no
hypothesis beyond the brief's wording.

| # | Theorem | Claim | Side-conditions (ratified) | Source |
|---|---------|-------|----------------------------|--------|
| 1 | `advance_totality` | From every reachable live state behind the tip, an advance landing at `k+1` is admissible within ≤ 2 transitions at any slot (Armed past deadline routes claim → thaw). | — | design, anti-griefing invariant 1; epic #24 Technical contract |
| 2 | `no_absorbing_busy_state` | No reachable live state has an empty admissible-action set. | `∀ k, canClose k` — the machine-level residue of "for the honest side"; without it the quiet tip state (goal 12) admits nothing (Q-L03) | design, anti-griefing invariant 1 ("no absorbing busy state") |
| 3 | `adversarial_advance_is_progress` | Any admissible advance, by any submitter, moves the checkpoint to exactly `k+1` along the real KEL. | — | design, anti-griefing invariant 2; verification note ("zero discretion") |
| 4 | `bounded_churn` (restated `bounded_interference`) | Consecutive advances enclose ≤ 3 non-advance transitions (`j ≤ i+4`): arm, claim, and now reap-intent, once each. | `¬ fork ∧ ∀ k, ¬ canClose k` (the permissionless fragment) **plus `hnoreap`** — no reap-execute between the two advances; a reap-execute burns the identity and re-registration restarts the count, so it is excluded like capability-holder churn (Q-L02, Q-B02). **RATIFIED constant 2 → 3.** | design, anti-griefing invariant 2; burn axiom (#127) |
| 5 | `armed_exclusive_window` | From Armed before the deadline, only advance and convict are admissible — the window is the replayer's. | — | design, anti-griefing invariant 2 ("arm-once-then-exclusive-window") |
| 6 | `bond_transfer_only_via_elapsed_window` (restated `honest_lag_never_pays`) | Every bounty payout arises from a claim whose arming happened ≥ `Wf` earlier with no intervening advance. | `¬ fork`, and scoped to `.bounty`-kind outflows — the prose "B leaves only via the elapsed window" is fork-free-fragment language: convict legitimately routes `B` (to the armed hunter), finalizeClose legitimately refunds it (Q-L01) | design, Change B; scope correction |
| 7 | `abandonment_pays_exactly_B` | Claim pays exactly `B` to the hunter recorded at arm time (not the claimer) and freezes at the same position. | — | design, Change B; verification obligation 3 |
| 8 | `frozen_implies_true_silence` | Reaching Frozen requires an arming and a claim ≥ `Wf` slots later with no advance in between — a genuinely unanswered window. | — | design, Change B ("claim requires genuine Wf-long absence") |
| 9 | `close_lie_always_voidable` | A behind Closing state admits both voids — challengeClose and the direct advance-void — at every slot while it is Closing. | — | design, close amendment; verification ruling 6 |
| 10 | — DROPPED — | Challenger fairness is off-chain; the on-chain guarantee is goal 9. | | scope correction |
| 11 | `close_at_tip_unchallengeable` | At the tip no challenge guard is satisfiable (neither void), and finalizeClose is admissible at every slot past the deadline. | — | design, close amendment ("honest tip close just waits Wc") |
| 12 | `current_state_is_quiet` | At the tip, Active: every admissible spend is a closeIntent — no permissionless spender. | `¬ fork` — with fork evidence convict is legitimately admissible everywhere, per goal 14 (Q-L01) | design, anti-griefing corollary ("steady-state UTxOs are quiet") |
| 13 | `value_conservation` (+ `_trace`) | Every transition preserves carried + paid-out = paid-in; corollary: every reachable configuration is balanced. | — | brief §Model (value ledger); verification obligation 3 |
| 14 | `convict_dominance` | With fork evidence, convict is admissible from every live state at every slot, and the target is now `.absent` (burn). | — | design ("convict dominates every state"); burn axiom (#127) |
| 15 | `convict_burns_and_no_aid_bar` (replaces `tombstone_terminal_but_no_aid_bar`) | Convict from any live state burns straight to `.absent`, releasing the full carried escrow as outflows; a fresh register on an absent instance of the same AID stays admissible (record = the transaction, not a UTxO). | — | burn axiom (#127); design preamble (conviction = penalty + record, no mint-once) |
| 16 | `replay_convergence` (restated) | ∃ a valid trace from empty instance to Active-at-tip of length exactly `f(N) = N` (N = KEL event count): register + N−1 advances. | — | design, Change A; scope correction (existential only) |
| 17 | `close_cycle_requires_elapsed_window` | Every finalizeClose is immediately preceded by its own closeIntent, a full `Wc` earlier: even capability-holder self-churn cannot be fast churn — each cycle sits a whole unchallenged window, interruptible by one advance/challenge throughout. | — | A-L01-03 ruling on Q-L02 part 2 |
| 18 | `dead_end_freedom` | From every reachable live state, at every slot, there is an admissible path ending in `.absent` (burnt) or `.active _` (revived) — no reachable dead end. | — (capability-free and fork-free; strictly weaker hypotheses than goal 2, because reap makes the FROZEN/REAPING exits capability-free) | burn axiom (#127) — the axiom's theorem |
| 19 | `reap_voidable` | A reachable REAPING admits the advance-void at every slot (reachable ⇒ behind). | — | burn axiom (#127); Q-B01 (behind guard on stale-CLOSING reap keeps this true) |
| 20 | `reap_requires_untouched_window` | A reapExecute is immediately preceded by its own reapIntent, a full `Wr` earlier — the reaping sat untouched through the window. | — | burn axiom (#127); the goal-17 pattern for the third window |
| 21 | `frozen_reap_requires_two_windows` | A FROZEN-origin reapExecute implies an earlier arm→claim pair a full `Wf` apart with no intervening advance — two consecutive unanswered public windows preceded the burn. | frozen-origin witness (`hfrozenOrigin`) — the reaping was entered from Frozen | burn axiom (#127); composes `frozen_implies_true_silence` |

Goals 2 and 12 are the two faces of one fact: **at the tip, only the
controller can act; behind the tip, anyone can help.** Goal 18
(`dead_end_freedom`) is the burn axiom made a theorem: **nothing that is only
a memory keeps a UTxO — every live state can move, or be reclaimed and burnt.**

## Questions and rulings

The statement-precision questions Q-L01..Q-L03 (filed under
`/tmp/keri-24/t124/questions/`) were all RATIFIED by the epic-owner rulings
A-L01-03 (2026-07-21): the side-conditions above are the ratified readings,
and goal 17 was added by the ruling on Q-L02 part 2 (capability-holder
close-cycle churn gets its own named machine property; the economics of why
nobody self-churns stays in the docs).

The burn-axiom formalization (#127) raised two design points, filed under
`/tmp/keri-24/t127/questions/` for epic-owner review (the model already
encodes the defensible reading of each):
- **Q-B01** — `reapIntentClosing` carries a `behind` guard in addition to
  staleness. Without it a stale *tip* CLOSING would be reap-eligible, which
  both falsifies `reap_voidable` and lets a griefer divert an honest closer's
  refund; the guard keeps every reachable REAPING behind and closes the theft
  vector. (Tip stale CLOSINGs are still cleaned up by permissionless
  `finalizeClose`.)
- **Q-B02** — `bounded_churn` carries a `hnoreap` side-condition (no
  reap-execute between the two advances). A reap-execute burns the identity to
  `absent`, and permissionless re-registration reopens the churn cycle; it is
  excluded exactly as capability-holder self-churn is (Q-L02), so the RATIFIED
  `j ≤ i + 4` holds for an ongoing, un-reaped replay.
