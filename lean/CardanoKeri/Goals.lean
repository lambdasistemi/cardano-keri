import CardanoKeri.Lifecycle

/-!
# M1 theorem goals — STATEMENTS ONLY (ticket #124)

Every body is `sorry` by design: the deliverable is well-defined goals.
Numbering follows the worker brief; goal 10 is dropped, goals 4/6/16 are
restated machine-level per the scope correction (2026-07-21), and goal 17
is added per the epic-owner rulings. Side-condition choices beyond the
brief's literal wording were flagged as Q-L01..Q-L03 and RATIFIED by
A-L01-03 (2026-07-21); the README mapping table carries them per goal.
-/

namespace CardanoKeri

/-- **Goal 1 — advance_totality.** From every reachable live state that is
behind the tip, an advance landing at `k+1` is admissible within ≤ 2
transitions, starting at any slot (Armed past its deadline routes via
claim → thaw; nothing blocks it). -/
theorem advance_totality (p : Params) (env : Env) (cfg : Config) (k : Seq)
    (hreach : Reachable p env cfg) (hlive : cfg.state.live)
    (hseq : cfg.state.seq? = some k) (hbehind : env.kel.behind k) :
    ∀ t : Slot, ∃ (txs : List Tx) (cfg' : Config) (last : Tx),
      TraceFrom p env t cfg txs cfg' ∧
      txs.length ≤ 2 ∧
      txs.getLast? = some last ∧
      last.act = .advance ∧
      cfg'.state = .active (k + 1) := by
  sorry

/-- **Goal 2 — no_absorbing_busy_state.** No reachable live state has an
empty admissible-action set: at every slot some transition (possibly later)
is admissible. Hypothesis `hcap`: the close capability is presentable — the
machine-level residue of "for the honest side"; without it the quiet
at-tip Active state (goal 12) admits nothing (Q-L03). -/
theorem no_absorbing_busy_state (p : Params) (env : Env)
    (hcap : ∀ k : Seq, env.canClose k)
    (cfg : Config) (hreach : Reachable p env cfg) (hlive : cfg.state.live) :
    ∀ t : Slot, ∃ (tx : Tx) (cfg' : Config),
      t ≤ tx.slot ∧ Step p env cfg tx cfg' := by
  sorry

/-- **Goal 3 — adversarial_advance_is_progress.** ANY admissible advance —
the model has no actor distinction, so this covers every submitter — moves
the checkpoint to exactly `k+1` along the real KEL. -/
theorem adversarial_advance_is_progress (p : Params) (env : Env)
    (cfg : Config) (tx : Tx) (cfg' : Config)
    (hstep : Step p env cfg tx cfg') (hadv : tx.act = .advance) :
    ∃ k : Seq, cfg.state.seq? = some k ∧
      cfg'.state = .active (k + 1) ∧
      env.kel.hasEvent (k + 1) := by
  sorry

/-- **Goal 4 — bounded_churn** (restated machine-level from
`bounded_interference`). In the permissionless fragment of the machine — no
fork evidence, no close capability, i.e. exactly the moves the validator
grants to everyone — any two consecutive advances enclose at most 2
non-advance transitions (`j ≤ i + 3`): an arm (once per behind-state) and a
claim (once per armed-state). The constant 2 matches the design's
expectation. With the close capability the machine admits unbounded
self-churn via closeIntent → finalizeClose → register cycles — see Q-L02. -/
theorem bounded_churn (p : Params) (env : Env)
    (hfork : ¬ env.fork) (hcap : ∀ k : Seq, ¬ env.canClose k)
    (txs : List Tx) (cfg : Config)
    (htrace : TraceFrom p env 0 initConfig txs cfg)
    (i j : Nat) (txi txj : Tx)
    (hi : txs[i]? = some txi) (hj : txs[j]? = some txj) (hij : i < j)
    (hadvi : txi.act = .advance) (hadvj : txj.act = .advance)
    (hbetween : ∀ (m : Nat) (txm : Tx),
      i < m → m < j → txs[m]? = some txm → txm.act ≠ .advance) :
    j ≤ i + 3 := by
  sorry

/-- **Goal 5 — armed_exclusive_window.** From Armed strictly before the
deadline, the ONLY admissible transitions are advance and convict: the
window belongs to the replayer. -/
theorem armed_exclusive_window (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (hunter : Addr) (d : Slot)
    (tx : Tx) (cfg' : Config)
    (hstep : Step p env ⟨.armed k hunter d, led⟩ tx cfg')
    (hwin : tx.slot < d) :
    tx.act = .advance ∨ ∃ c : Addr, tx.act = .convict c := by
  sorry

/-- **Goal 6 — bond_transfer_only_via_elapsed_window** (restated
machine-level from `honest_lag_never_pays`; merges the goal-8 window
structure). Absent fork evidence (Q-L01), every bounty payout in a trace is
produced by a claim whose arming (arm or challengeClose, which recorded the
payee) happened a full `Wf` earlier with no advance in between: `B` leaves
as a bounty only through a genuinely elapsed, unanswered window. -/
theorem bond_transfer_only_via_elapsed_window (p : Params) (env : Env)
    (hfork : ¬ env.fork)
    (txs : List Tx) (cfg : Config)
    (htrace : TraceFrom p env 0 initConfig txs cfg)
    (tr : Transfer) (hmem : tr ∈ cfg.ledger.outflows)
    (hkind : tr.kind = .bounty) :
    ∃ (i j : Nat) (txi txj : Tx),
      txs[i]? = some txi ∧ txs[j]? = some txj ∧ i < j ∧
      (txi.act = .arm tr.dest ∨ txi.act = .challengeClose tr.dest) ∧
      txj.act = .claim ∧
      txi.slot + p.Wf ≤ txj.slot ∧
      tr.amount = p.B ∧
      (∀ (m : Nat) (txm : Tx),
        i < m → m < j → txs[m]? = some txm → txm.act ≠ .advance) := by
  sorry

/-- **Goal 7 — abandonment_pays_exactly_B.** A claim from Armed pays exactly
`B`, to exactly the hunter recorded at arm time (the claimer chooses
nothing), and moves the state to Frozen at the same position. -/
theorem abandonment_pays_exactly_B (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (hunter : Addr) (d : Slot)
    (tx : Tx) (cfg' : Config)
    (hstep : Step p env ⟨.armed k hunter d, led⟩ tx cfg')
    (hclaim : tx.act = .claim) :
    cfg'.state = .frozen k ∧
    cfg'.ledger.outflows = led.outflows ++ [⟨hunter, p.B, .bounty⟩] ∧
    cfg'.ledger.deposits = led.deposits := by
  sorry

/-- **Goal 8 — frozen_implies_true_silence.** Reaching Frozen requires a
trace segment ≥ `Wf` slots long containing no advance: an arming (arm or
challengeClose) at slot `s` and a claim at slot ≥ `s + Wf` with no advance
between them. -/
theorem frozen_implies_true_silence (p : Params) (env : Env)
    (txs : List Tx) (cfg : Config)
    (htrace : TraceFrom p env 0 initConfig txs cfg)
    (k : Seq) (hfrozen : cfg.state = .frozen k) :
    ∃ (i j : Nat) (txi txj : Tx) (h : Addr),
      txs[i]? = some txi ∧ txs[j]? = some txj ∧ i < j ∧
      (txi.act = .arm h ∨ txi.act = .challengeClose h) ∧
      txj.act = .claim ∧
      txi.slot + p.Wf ≤ txj.slot ∧
      (∀ (m : Nat) (txm : Tx),
        i < m → m < j → txs[m]? = some txm → txm.act ≠ .advance) := by
  sorry

/-- **Goal 9 — close_lie_always_voidable.** If a Closing state is behind the
tip, then at EVERY slot before finalization (i.e. while the state is
Closing) both voids are admissible: challengeClose by any challenger, and
the direct advance-void. -/
theorem close_lie_always_voidable (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (r : Addr) (d : Slot)
    (hbehind : env.kel.behind k) :
    ∀ t : Slot,
      (∀ c : Addr, ∃ cfg' : Config,
        Step p env ⟨.closing k r d, led⟩ ⟨t, .challengeClose c⟩ cfg') ∧
      (∃ cfg' : Config,
        Step p env ⟨.closing k r d, led⟩ ⟨t, .advance⟩ cfg') := by
  sorry

-- Goal 10 (`close_lie_never_finalizes_under_liveness`) is DROPPED: challenger
-- fairness is an off-chain assumption (scope correction, 2026-07-21). The
-- on-chain guarantee is goal 9.

/-- **Goal 11 — close_at_tip_unchallengeable.** For a Closing state at the
tip, no challenge guard is satisfiable — neither challengeClose nor the
advance-void, at any slot — and finalizeClose is admissible at every slot
past the deadline (honest close liveness). -/
theorem close_at_tip_unchallengeable (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (r : Addr) (d : Slot)
    (htip : ¬ env.kel.behind k) :
    (∀ (t : Slot) (c : Addr) (cfg' : Config),
      ¬ Step p env ⟨.closing k r d, led⟩ ⟨t, .challengeClose c⟩ cfg') ∧
    (∀ (t : Slot) (cfg' : Config),
      ¬ Step p env ⟨.closing k r d, led⟩ ⟨t, .advance⟩ cfg') ∧
    (∀ t : Slot, d ≤ t → ∃ cfg' : Config,
      Step p env ⟨.closing k r d, led⟩ ⟨t, .finalizeClose⟩ cfg') := by
  sorry

/-- **Goal 12 — current_state_is_quiet.** At the tip, Active, and absent
fork evidence (Q-L01), every admissible spend is a closeIntent — the one
capability-gated action. A current checkpoint has no permissionless
spender. -/
theorem current_state_is_quiet (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (tx : Tx) (cfg' : Config)
    (htip : ¬ env.kel.behind k) (hfork : ¬ env.fork)
    (hstep : Step p env ⟨.active k, led⟩ tx cfg') :
    ∃ r : Addr, tx.act = .closeIntent r := by
  sorry

/-- **Goal 13 — value_conservation** (per-transition form). Every transition
preserves the balance: value carried on the UTxO plus cumulative payouts
equals cumulative pay-ins. -/
theorem value_conservation (p : Params) (env : Env)
    (cfg : Config) (tx : Tx) (cfg' : Config)
    (hstep : Step p env cfg tx cfg') (hbal : cfg.balanced p) :
    cfg'.balanced p := by
  sorry

/-- **Goal 13 (corollary) — value_conservation_trace.** Whole-trace form:
every reachable configuration is balanced. -/
theorem value_conservation_trace (p : Params) (env : Env)
    (cfg : Config) (hreach : Reachable p env cfg) :
    cfg.balanced p := by
  sorry

/-- **Goal 14 — convict_dominance.** With fork evidence, convict is
admissible from every live state, at every slot, by any convictor. -/
theorem convict_dominance (p : Params) (env : Env) (hfork : env.fork)
    (cfg : Config) (hlive : cfg.state.live) (t : Slot) (c : Addr) :
    ∃ cfg' : Config, Step p env cfg ⟨t, .convict c⟩ cfg' := by
  sorry

/-- **Goal 15 — tombstone_terminal_but_no_aid_bar.** A tombstone admits no
transitions; AND a fresh register on a different instance of the SAME AID is
admissible regardless of the tombstone (conviction is penalty + record, not
an AID bar). -/
theorem tombstone_terminal_but_no_aid_bar (p : Params) (env : Env) :
    (∀ (k : Seq) (led : Ledger) (tx : Tx) (cfg' : Config),
      ¬ Step p env ⟨.tombstone k, led⟩ tx cfg') ∧
    (∀ (sys : Sys) (i j : InstanceId) (k : Seq) (ledi ledj : Ledger) (t : Slot),
      i ≠ j →
      sys i = ⟨.tombstone k, ledi⟩ →
      sys j = ⟨.absent, ledj⟩ →
      env.kel.hasEvent 0 →
      ∃ sys' : Sys, SysStep p env sys j ⟨t, .register⟩ sys') := by
  sorry

/-- **Goal 16 — replay_convergence** (restated machine-level: existential
reachability only, no adversarial-interleaving quantifier). From the empty
instance there EXISTS a valid trace reaching Active-at-tip in exactly
`f(N) = N` transitions, where `N` is the KEL event count (one register plus
`N - 1` advances). -/
theorem replay_convergence (p : Params) (env : Env)
    (hicp : env.kel.hasEvent 0) :
    ∃ (txs : List Tx) (cfg : Config),
      TraceFrom p env 0 initConfig txs cfg ∧
      cfg.state = .active env.kel.tip ∧
      txs.length = env.kel.events.length := by
  sorry

/-- **Goal 17 — close_cycle_requires_elapsed_window** (added per A-L01-03,
ratifying Q-L02 part 2). Even capability-holder self-churn cannot be fast
churn: every finalizeClose is immediately preceded in the machine's trace by
its own closeIntent — the state sat Closing, untouched, through a full
unchallenged `Wc` window (`intent slot + Wc ≤ finalize slot`), interruptible
by a single advance/challenge the entire time. Why nobody rationally
self-churns (fees, re-escrow, self-harm) is docs material, not model. -/
theorem close_cycle_requires_elapsed_window (p : Params) (env : Env)
    (txs : List Tx) (cfg : Config)
    (htrace : TraceFrom p env 0 initConfig txs cfg)
    (j : Nat) (txj : Tx)
    (hj : txs[j]? = some txj) (hfin : txj.act = .finalizeClose) :
    ∃ (i : Nat) (txi : Tx) (r : Addr),
      i + 1 = j ∧
      txs[i]? = some txi ∧
      txi.act = .closeIntent r ∧
      txi.slot + p.Wc ≤ txj.slot := by
  sorry

end CardanoKeri
