# Lean model of the M1 checkpoint lifecycle — goals only (#124)

A standalone Lake project (Lean 4, `v4.27.0`, **zero dependencies** — Lean
core only) that models the M1 checkpoint lifecycle as **the on-chain
validator's transition system** and states the M1 invariants as theorem
goals. Every theorem body is `sorry` by design: the deliverable of #124 is
*well-defined goals*, not proofs.

- `CardanoKeri/Lifecycle.lean` — states, actions, guards, value ledger,
  traces (definitions only).
- `CardanoKeri/Goals.lean` — the theorem statements (all `sorry`).

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

The build must pass with exactly 17 `declaration uses 'sorry'` warnings
(16 goals; goal 13 has a per-transition form plus a whole-trace corollary).
No `axiom` declarations anywhere: `#print axioms` on every goal reports only
`sorryAx` (and `propext`, Lean core).

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
`min + D + B`; Frozen `min + D`; Tombstone `min`); the `Ledger` tracks
cumulative pay-ins (`deposits`: register, thaw re-post) and an append-only
payout log (`outflows`), each payout tagged `bounty` (B to a hunter),
`forfeiture` (to a convictor) or `refund` (finalized close). Conservation
(`Config.balanced`): carried + paid-out = paid-in. Third-party pay-ins
(thaw re-posts) are donations — the machine records no creditor.

## Invariant ↔ theorem map

Side-conditions were flagged as Q-L01..Q-L03 and ratified by the epic-owner
rulings A-L01-03 (2026-07-21); "—" means the goal is stated with no
hypothesis beyond the brief's wording.

| # | Theorem | Claim | Side-conditions (ratified) | Source |
|---|---------|-------|----------------------------|--------|
| 1 | `advance_totality` | From every reachable live state behind the tip, an advance landing at `k+1` is admissible within ≤ 2 transitions at any slot (Armed past deadline routes claim → thaw). | — | design, anti-griefing invariant 1; epic #24 Technical contract |
| 2 | `no_absorbing_busy_state` | No reachable live state has an empty admissible-action set. | `∀ k, canClose k` — the machine-level residue of "for the honest side"; without it the quiet tip state (goal 12) admits nothing (Q-L03) | design, anti-griefing invariant 1 ("no absorbing busy state") |
| 3 | `adversarial_advance_is_progress` | Any admissible advance, by any submitter, moves the checkpoint to exactly `k+1` along the real KEL. | — | design, anti-griefing invariant 2; verification note ("zero discretion") |
| 4 | `bounded_churn` (restated `bounded_interference`) | Consecutive advances enclose ≤ 2 non-advance transitions: arm once per behind-state, claim once per armed-state. | `¬ fork ∧ ∀ k, ¬ canClose k` — the permissionless fragment, exactly the moves the validator grants everyone; capability-holder churn is goal 17's territory (Q-L02) | design, anti-griefing invariant 2; scope correction |
| 5 | `armed_exclusive_window` | From Armed before the deadline, only advance and convict are admissible — the window is the replayer's. | — | design, anti-griefing invariant 2 ("arm-once-then-exclusive-window") |
| 6 | `bond_transfer_only_via_elapsed_window` (restated `honest_lag_never_pays`) | Every bounty payout arises from a claim whose arming happened ≥ `Wf` earlier with no intervening advance. | `¬ fork`, and scoped to `.bounty`-kind outflows — the prose "B leaves only via the elapsed window" is fork-free-fragment language: convict legitimately routes `B` (to the armed hunter), finalizeClose legitimately refunds it (Q-L01) | design, Change B; scope correction |
| 7 | `abandonment_pays_exactly_B` | Claim pays exactly `B` to the hunter recorded at arm time (not the claimer) and freezes at the same position. | — | design, Change B; verification obligation 3 |
| 8 | `frozen_implies_true_silence` | Reaching Frozen requires an arming and a claim ≥ `Wf` slots later with no advance in between — a genuinely unanswered window. | — | design, Change B ("claim requires genuine Wf-long absence") |
| 9 | `close_lie_always_voidable` | A behind Closing state admits both voids — challengeClose and the direct advance-void — at every slot while it is Closing. | — | design, close amendment; verification ruling 6 |
| 10 | — DROPPED — | Challenger fairness is off-chain; the on-chain guarantee is goal 9. | | scope correction |
| 11 | `close_at_tip_unchallengeable` | At the tip no challenge guard is satisfiable (neither void), and finalizeClose is admissible at every slot past the deadline. | — | design, close amendment ("honest tip close just waits Wc") |
| 12 | `current_state_is_quiet` | At the tip, Active: every admissible spend is a closeIntent — no permissionless spender. | `¬ fork` — with fork evidence convict is legitimately admissible everywhere, per goal 14 (Q-L01) | design, anti-griefing corollary ("steady-state UTxOs are quiet") |
| 13 | `value_conservation` (+ `_trace`) | Every transition preserves carried + paid-out = paid-in; corollary: every reachable configuration is balanced. | — | brief §Model (value ledger); verification obligation 3 |
| 14 | `convict_dominance` | With fork evidence, convict is admissible from every live state at every slot. | — | design ("convict dominates every state") |
| 15 | `tombstone_terminal_but_no_aid_bar` | Tombstone admits no transitions; a fresh register on another instance of the same AID is admissible regardless. | — | design preamble (conviction = penalty + record, no mint-once) |
| 16 | `replay_convergence` (restated) | ∃ a valid trace from empty instance to Active-at-tip of length exactly `f(N) = N` (N = KEL event count): register + N−1 advances. | — | design, Change A; scope correction (existential only) |
| 17 | `close_cycle_requires_elapsed_window` | Every finalizeClose is immediately preceded by its own closeIntent, a full `Wc` earlier: even capability-holder self-churn cannot be fast churn — each cycle sits a whole unchallenged window, interruptible by one advance/challenge throughout. | — | A-L01-03 ruling on Q-L02 part 2 |

Goals 2 and 12 are the two faces of one fact: **at the tip, only the
controller can act; behind the tip, anyone can help.**

## Questions and rulings

The statement-precision questions Q-L01..Q-L03 (filed under
`/tmp/keri-24/t124/questions/`) were all RATIFIED by the epic-owner rulings
A-L01-03 (2026-07-21): the side-conditions above are the ratified readings,
and goal 17 was added by the ruling on Q-L02 part 2 (capability-holder
close-cycle churn gets its own named machine property; the economics of why
nobody self-churns stays in the docs).
