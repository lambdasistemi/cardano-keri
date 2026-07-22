import CardanoKeri.Lifecycle
import CardanoKeri.Invariants

/-!
# M1 theorem goals (ticket #124) — statements ratified, all proved

Numbering follows the worker brief; goal 10 is dropped, goals 4/6/16 are
restated machine-level per the scope correction (2026-07-21), and goal 17
is added per the epic-owner rulings. Side-condition choices beyond the
brief's literal wording were flagged as Q-L01..Q-L03 and RATIFIED by
A-L01-03 (2026-07-21); the README mapping table carries them per goal.
Phase 2 (operator-authorized) proved every statement verbatim — no `sorry`,
no custom axioms; the shared machinery lives in `CardanoKeri/Invariants.lean`.
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
  obtain ⟨s, led⟩ := cfg
  cases s with
  | absent => simp [MachState.seq?] at hseq
  | reaping k' reaper d o =>
    have hk : k' = k := by simpa [MachState.seq?] using hseq
    subst hk
    intro t
    exact ⟨[⟨t, .advance⟩], _, ⟨t, .advance⟩,
      .cons (Nat.le_refl t) (Step.advanceReaping hbehind) (.nil _ _),
      Nat.le_succ 1, rfl, rfl, rfl⟩
  | active k' =>
    have hk : k' = k := by simpa [MachState.seq?] using hseq
    subst hk
    intro t
    exact ⟨[⟨t, .advance⟩], _, ⟨t, .advance⟩,
      .cons (Nat.le_refl t) (Step.advanceActive hbehind) (.nil _ _),
      Nat.le_succ 1, rfl, rfl, rfl⟩
  | frozen k' =>
    have hk : k' = k := by simpa [MachState.seq?] using hseq
    subst hk
    intro t
    exact ⟨[⟨t, .advance⟩], _, ⟨t, .advance⟩,
      .cons (Nat.le_refl t) (Step.advanceFrozen hbehind) (.nil _ _),
      Nat.le_succ 1, rfl, rfl, rfl⟩
  | closing k' r d =>
    have hk : k' = k := by simpa [MachState.seq?] using hseq
    subst hk
    intro t
    exact ⟨[⟨t, .advance⟩], _, ⟨t, .advance⟩,
      .cons (Nat.le_refl t) (Step.advanceClosing hbehind) (.nil _ _),
      Nat.le_succ 1, rfl, rfl, rfl⟩
  | armed k' hunter d =>
    have hk : k' = k := by simpa [MachState.seq?] using hseq
    subst hk
    intro t
    rcases Nat.lt_or_ge t d with hlt | hge
    · exact ⟨[⟨t, .advance⟩], _, ⟨t, .advance⟩,
        .cons (Nat.le_refl t) (Step.advanceArmed hbehind hlt) (.nil _ _),
        Nat.le_succ 1, rfl, rfl, rfl⟩
    · exact ⟨[⟨t, .claim⟩, ⟨t, .advance⟩], _, ⟨t, .advance⟩,
        .cons (Nat.le_refl t) (Step.claim hge)
          (.cons (Nat.le_refl t) (Step.advanceFrozen hbehind) (.nil _ _)),
        Nat.le_refl 2, rfl, rfl, rfl⟩

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
  obtain ⟨s, led⟩ := cfg
  intro t
  cases s with
  | absent => exact absurd hlive (by simp [MachState.live])
  | reaping k reaper d o =>
    exact ⟨⟨max t d, .reapExecute⟩, _, Nat.le_max_left t d,
      Step.reapExecute (Nat.le_max_right t d)⟩
  | active k =>
    exact ⟨⟨t, .closeIntent 0⟩, _, Nat.le_refl t, Step.closeIntent 0 (hcap k)⟩
  | armed k hunter d =>
    exact ⟨⟨max t d, .claim⟩, _, Nat.le_max_left t d,
      Step.claim (Nat.le_max_right t d)⟩
  | frozen k =>
    exact ⟨⟨t, .advance⟩, _, Nat.le_refl t,
      Step.advanceFrozen (Reachable.frozen_behind hreach rfl)⟩
  | closing k r d =>
    exact ⟨⟨max t d, .finalizeClose⟩, _, Nat.le_max_left t d,
      Step.finalizeClose (Nat.le_max_right t d)⟩

/-- **Goal 3 — adversarial_advance_is_progress.** ANY admissible advance —
the model has no actor distinction, so this covers every submitter — moves
the checkpoint to exactly `k+1` along the real KEL. -/
theorem adversarial_advance_is_progress (p : Params) (env : Env)
    (cfg : Config) (tx : Tx) (cfg' : Config)
    (hstep : Step p env cfg tx cfg') (hadv : tx.act = .advance) :
    ∃ k : Seq, cfg.state.seq? = some k ∧
      cfg'.state = .active (k + 1) ∧
      env.kel.hasEvent (k + 1) := by
  cases hstep <;> simp_all [MachState.seq?, Kel.behind]

/-- **Goal 4 — bounded_churn** (restated machine-level from
`bounded_interference`; **RATIFIED change under the burn axiom: the constant
rises 2 → 3**, `j ≤ i + 4`). In the permissionless fragment of the machine —
no fork evidence, no close capability, i.e. exactly the moves the validator
grants to everyone — any two consecutive advances that do NOT enclose a
reap-execute (`hnoreap`) enclose at most 3 non-advance transitions: an arm
(once per behind-state), a claim (once per armed-state), and now a reap-intent
(once per frozen-state). The reap-intent is the one new stall the burn axiom
adds; a reap-execute burns the identity to Absent and re-registration starts a
fresh count, so it (like closeIntent → finalizeClose → register self-churn,
Q-L02) is excluded — see Q-B02. -/
theorem bounded_churn (p : Params) (env : Env)
    (hfork : ¬ env.fork) (hcap : ∀ k : Seq, ¬ env.canClose k)
    (txs : List Tx) (cfg : Config)
    (htrace : TraceFrom p env 0 initConfig txs cfg)
    (i j : Nat) (txi txj : Tx)
    (hi : txs[i]? = some txi) (hj : txs[j]? = some txj) (hij : i < j)
    (hadvi : txi.act = .advance) (hadvj : txj.act = .advance)
    (hbetween : ∀ (m : Nat) (txm : Tx),
      i < m → m < j → txs[m]? = some txm → txm.act ≠ .advance)
    (hnoreap : ∀ (m : Nat) (txm : Tx),
      i < m → m < j → txs[m]? = some txm → txm.act ≠ .reapExecute) :
    j ≤ i + 4 := by
  refine Nat.le_of_not_lt fun hcon => ?_
  have hjlen : j < txs.length := getElem?_some_lt hj
  obtain ⟨c1, c2, hpre, hsti, hsuf⟩ := htrace.step_at i txi hi
  obtain ⟨k2, led2, hc2⟩ := hsti.advance_target hadvi
  subst hc2
  obtain ⟨a, ha⟩ := getElem?_isSome_of_lt (l := txs) (i := i + 1) (by omega)
  obtain ⟨b, hb⟩ := getElem?_isSome_of_lt (l := txs) (i := i + 2) (by omega)
  obtain ⟨cc, hcc⟩ := getElem?_isSome_of_lt (l := txs) (i := i + 3) (by omega)
  obtain ⟨dd, hdd⟩ := getElem?_isSome_of_lt (l := txs) (i := i + 4) (by omega)
  exact fragment_no_four_stalls hcap hfork hsuf
    (by rw [List.getElem?_drop]; exact ha)
    (by rw [List.getElem?_drop]; exact hb)
    (by rw [List.getElem?_drop]; exact hcc)
    (by rw [List.getElem?_drop]; exact hdd)
    (hbetween (i + 1) a (by omega) (by omega) ha)
    (hbetween (i + 2) b (by omega) (by omega) hb)
    (hbetween (i + 3) cc (by omega) (by omega) hcc)
    (hbetween (i + 4) dd (by omega) (by omega) hdd)
    (hnoreap (i + 4) dd (by omega) (by omega) hdd)

/-- **Goal 5 — armed_exclusive_window.** From Armed strictly before the
deadline, the ONLY admissible transitions are advance and convict: the
window belongs to the replayer. -/
theorem armed_exclusive_window (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (hunter : Addr) (d : Slot)
    (tx : Tx) (cfg' : Config)
    (hstep : Step p env ⟨.armed k hunter d, led⟩ tx cfg')
    (hwin : tx.slot < d) :
    tx.act = .advance ∨ ∃ c : Addr, tx.act = .convict c := by
  cases hstep <;> simp_all <;> (rename_i hd; exact absurd hwin (Nat.not_lt.mpr hd))

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
  suffices H : ∀ (n : Nat) (txs : List Tx) (cfg : Config), txs.length ≤ n →
      TraceFrom p env 0 initConfig txs cfg →
      ∀ tr : Transfer, tr ∈ cfg.ledger.outflows → tr.kind = .bounty →
      ∃ (i j : Nat) (txi txj : Tx),
        txs[i]? = some txi ∧ txs[j]? = some txj ∧ i < j ∧
        (txi.act = .arm tr.dest ∨ txi.act = .challengeClose tr.dest) ∧
        txj.act = .claim ∧
        txi.slot + p.Wf ≤ txj.slot ∧
        tr.amount = p.B ∧
        (∀ (m : Nat) (txm : Tx),
          i < m → m < j → txs[m]? = some txm → txm.act ≠ .advance) by
    exact H txs.length txs cfg (Nat.le_refl _) htrace tr hmem hkind
  intro n
  induction n with
  | zero =>
    intro txs cfg hlen htr tr hmem hkind
    have htxs : txs = [] := List.eq_nil_of_length_eq_zero (Nat.le_zero.mp hlen)
    subst htxs
    cases htr
    simp [initConfig] at hmem
  | succ n ih =>
    intro txs cfg hlen htr tr hmem hkind
    rcases htr.last_step with ⟨hnil, heq⟩ | ⟨pre, lst, cmid, heq, hpre, hst⟩
    · subst hnil
      rw [← heq] at hmem
      simp [initConfig] at hmem
    · subst heq
      have hlenpre : pre.length ≤ n := by
        simp only [List.length_append, List.length_cons, List.length_nil] at hlen
        omega
      have lift : (∃ (i j : Nat) (txi txj : Tx),
            pre[i]? = some txi ∧ pre[j]? = some txj ∧ i < j ∧
            (txi.act = .arm tr.dest ∨ txi.act = .challengeClose tr.dest) ∧
            txj.act = .claim ∧ txi.slot + p.Wf ≤ txj.slot ∧ tr.amount = p.B ∧
            (∀ (m : Nat) (txm : Tx),
              i < m → m < j → pre[m]? = some txm → txm.act ≠ .advance)) →
          ∃ (i j : Nat) (txi txj : Tx),
            (pre ++ [lst])[i]? = some txi ∧ (pre ++ [lst])[j]? = some txj ∧ i < j ∧
            (txi.act = .arm tr.dest ∨ txi.act = .challengeClose tr.dest) ∧
            txj.act = .claim ∧ txi.slot + p.Wf ≤ txj.slot ∧ tr.amount = p.B ∧
            (∀ (m : Nat) (txm : Tx),
              i < m → m < j → (pre ++ [lst])[m]? = some txm → txm.act ≠ .advance) := by
        rintro ⟨i, j, txi, txj, hi, hj, hij, hact, hcl, hwin, hamt, hbet⟩
        have hjlen : j < pre.length := getElem?_some_lt hj
        refine ⟨i, j, txi, txj, ?_, ?_, hij, hact, hcl, hwin, hamt, ?_⟩
        · rw [List.getElem?_append_left (Nat.lt_trans hij hjlen)]
          exact hi
        · rw [List.getElem?_append_left hjlen]
          exact hj
        · intro m txm h1 h2 hm
          rw [List.getElem?_append_left (Nat.lt_trans h2 hjlen)] at hm
          exact hbet m txm h1 h2 hm
      cases hst with
      | @register led t hicp =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @advanceActive led k t hnext =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @advanceArmed led k hunter d t hnext hwin =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @advanceFrozen led k t hnext =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @advanceClosing led k r d t hnext =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @arm led k t hunter hbehind =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @closeIntent led k t refund hcap =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @challengeClose led k r d t ch hbehind =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @finalizeClose led k r d t hdeadline =>
        rcases List.mem_append.mp hmem with hold | hnew
        · exact lift (ih pre _ hlenpre hpre tr hold hkind)
        · have htr' : tr = ⟨r, p.minAda + p.D + p.B, .refund⟩ := by simpa using hnew
          subst htr'
          simp at hkind
      | @convictActive led k t c hforkev =>
        exact absurd hforkev hfork
      | @convictArmed led k hunter d t c hforkev =>
        exact absurd hforkev hfork
      | @convictFrozen led k t c hforkev =>
        exact absurd hforkev hfork
      | @convictClosing led k r d t c hforkev =>
        exact absurd hforkev hfork
      | @convictReaping led k reaper d o t c hforkev =>
        exact absurd hforkev hfork
      | @reapIntentFrozen led k t reaper =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @reapIntentClosing led k r d t reaper hstale hbehind =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @advanceReaping led k reaper d o t hnext =>
        exact lift (ih pre _ hlenpre hpre tr hmem hkind)
      | @reapExecute led k reaper d o t hdeadline =>
        rcases List.mem_append.mp hmem with hold | hnew
        · exact lift (ih pre _ hlenpre hpre tr hold hkind)
        · have htr' : tr = ⟨reaper, reapEscrow p o, .reap⟩ := by simpa using hnew
          subst htr'
          simp at hkind
      | @claim led k' hunter d t3 hdeadline =>
        rcases List.mem_append.mp hmem with hold | hnew
        · exact lift (ih pre _ hlenpre hpre tr hold hkind)
        · have htr' : tr = ⟨hunter, p.B, .bounty⟩ := by simpa using hnew
          subst htr'
          rcases hpre.last_step with ⟨hnil2, heq2⟩ | ⟨pre2, lst2, cmid2, heq2, hpre2, hst2⟩
          · exact absurd (congrArg Config.state heq2) (by simp [initConfig])
          · have hL : (pre2 ++ [lst2]).length = pre2.length + 1 := by simp
            subst heq2
            cases hst2 with
            | @arm led2 k2 t2 hunter2 hbehind2 =>
              refine ⟨pre2.length, pre2.length + 1, ⟨t2, .arm hunter⟩, ⟨t3, .claim⟩,
                ?_, ?_, Nat.lt_succ_self _, Or.inl rfl, rfl, hdeadline, rfl, ?_⟩
              · rw [List.getElem?_append_left (by rw [hL]; exact Nat.lt_succ_self _)]
                exact List.getElem?_concat_length
              · rw [← hL]
                exact List.getElem?_concat_length
              · intro m txm h1 h2 _
                omega
            | @challengeClose led2 k2 r2 d2 t2 ch hbehind2 =>
              refine ⟨pre2.length, pre2.length + 1, ⟨t2, .challengeClose hunter⟩, ⟨t3, .claim⟩,
                ?_, ?_, Nat.lt_succ_self _, Or.inr rfl, rfl, hdeadline, rfl, ?_⟩
              · rw [List.getElem?_append_left (by rw [hL]; exact Nat.lt_succ_self _)]
                exact List.getElem?_concat_length
              · rw [← hL]
                exact List.getElem?_concat_length
              · intro m txm h1 h2 _
                omega

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
  cases hstep <;> simp_all

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
  rcases htrace.last_step with ⟨hnil, heq⟩ | ⟨pre, lst, cmid, heq, hpre, hst⟩
  · rw [← heq] at hfrozen
    simp [initConfig] at hfrozen
  · subst heq
    cases hst <;> try (simp at hfrozen)
    case claim led k' hunter d t3 hdeadline =>
      subst hfrozen
      rcases hpre.last_step with ⟨hnil2, heq2⟩ | ⟨pre2, lst2, cmid2, heq2, hpre2, hst2⟩
      · exact absurd (congrArg Config.state heq2) (by simp [initConfig])
      · have hL : (pre2 ++ [lst2]).length = pre2.length + 1 := by simp
        subst heq2
        cases hst2 with
        | @arm led2 k2 t2 hunter2 hbehind2 =>
          refine ⟨pre2.length, pre2.length + 1, ⟨t2, .arm hunter⟩, ⟨t3, .claim⟩,
            hunter, ?_, ?_, Nat.lt_succ_self _, Or.inl rfl, rfl, hdeadline, ?_⟩
          · rw [List.getElem?_append_left (by rw [hL]; exact Nat.lt_succ_self _)]
            exact List.getElem?_concat_length
          · rw [← hL]
            exact List.getElem?_concat_length
          · intro m txm h1 h2 _
            omega
        | @challengeClose led2 k2 r2 d2 t2 ch hbehind2 =>
          refine ⟨pre2.length, pre2.length + 1, ⟨t2, .challengeClose hunter⟩, ⟨t3, .claim⟩,
            hunter, ?_, ?_, Nat.lt_succ_self _, Or.inr rfl, rfl, hdeadline, ?_⟩
          · rw [List.getElem?_append_left (by rw [hL]; exact Nat.lt_succ_self _)]
            exact List.getElem?_concat_length
          · rw [← hL]
            exact List.getElem?_concat_length
          · intro m txm h1 h2 _
            omega

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
  intro t
  exact ⟨fun c => ⟨_, Step.challengeClose c hbehind⟩, ⟨_, Step.advanceClosing hbehind⟩⟩

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
  refine ⟨fun t c cfg' hstep => ?_, fun t cfg' hstep => ?_,
    fun t ht => ⟨_, Step.finalizeClose ht⟩⟩
  · cases hstep <;> simp_all [Kel.behind]
  · cases hstep <;> simp_all [Kel.behind]

/-- **Goal 12 — current_state_is_quiet.** At the tip, Active, and absent
fork evidence (Q-L01), every admissible spend is a closeIntent — the one
capability-gated action. A current checkpoint has no permissionless
spender. -/
theorem current_state_is_quiet (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (tx : Tx) (cfg' : Config)
    (htip : ¬ env.kel.behind k) (hfork : ¬ env.fork)
    (hstep : Step p env ⟨.active k, led⟩ tx cfg') :
    ∃ r : Addr, tx.act = .closeIntent r := by
  cases hstep <;> simp_all [Kel.behind]

/-- **Goal 13 — value_conservation** (per-transition form). Every transition
preserves the balance: value carried on the UTxO plus cumulative payouts
equals cumulative pay-ins. -/
theorem value_conservation (p : Params) (env : Env)
    (cfg : Config) (tx : Tx) (cfg' : Config)
    (hstep : Step p env cfg tx cfg') (hbal : cfg.balanced p) :
    cfg'.balanced p := by
  exact hstep.preserves_balanced hbal

/-- **Goal 13 (corollary) — value_conservation_trace.** Whole-trace form:
every reachable configuration is balanced. -/
theorem value_conservation_trace (p : Params) (env : Env)
    (cfg : Config) (hreach : Reachable p env cfg) :
    cfg.balanced p := by
  obtain ⟨txs, htr⟩ := hreach
  exact htr.preserves_balanced (initConfig_balanced p)

/-- **Goal 14 — convict_dominance.** With fork evidence, convict is
admissible from every live state, at every slot, by any convictor — and the
burn axiom now makes the target `.absent` (no tombstone residue). -/
theorem convict_dominance (p : Params) (env : Env) (hfork : env.fork)
    (cfg : Config) (hlive : cfg.state.live) (t : Slot) (c : Addr) :
    ∃ cfg' : Config, Step p env cfg ⟨t, .convict c⟩ cfg' ∧ cfg'.state = .absent := by
  obtain ⟨s, led⟩ := cfg
  cases s with
  | absent => exact absurd hlive (by simp [MachState.live])
  | active k => exact ⟨_, Step.convictActive c hfork, rfl⟩
  | armed k h d => exact ⟨_, Step.convictArmed c hfork, rfl⟩
  | frozen k => exact ⟨_, Step.convictFrozen c hfork, rfl⟩
  | closing k r d => exact ⟨_, Step.convictClosing c hfork, rfl⟩
  | reaping k reaper d o => exact ⟨_, Step.convictReaping c hfork, rfl⟩

/-- **Goal 15 — convict_burns_and_no_aid_bar** (the burn axiom; replaces the
tombstone theorem). Convict from ANY live state, at any slot, burns straight
to `.absent`, releasing the FULL carried escrow as outflows (nothing is left
behind); AND a fresh register on an absent instance of the SAME AID is
admissible regardless (conviction is penalty + record, never an AID bar — the
record lives in the convict transaction, in history). -/
theorem convict_burns_and_no_aid_bar (p : Params) (env : Env) (hfork : env.fork) :
    (∀ (cfg : Config), cfg.state.live → ∀ (t : Slot) (c : Addr),
      ∃ cfg' : Config, Step p env cfg ⟨t, .convict c⟩ cfg' ∧
        cfg'.state = .absent ∧
        outflowTotal cfg'.ledger.outflows
          = outflowTotal cfg.ledger.outflows + carried p cfg.state) ∧
    (∀ (sys : Sys) (j : InstanceId) (ledj : Ledger) (t : Slot),
      sys j = ⟨.absent, ledj⟩ →
      env.kel.hasEvent 0 →
      ∃ sys' : Sys, SysStep p env sys j ⟨t, .register⟩ sys') := by
  refine ⟨?_, ?_⟩
  · rintro ⟨s, led⟩ hlive t c
    cases s with
    | absent => exact absurd hlive (by simp [MachState.live])
    | active k =>
      exact ⟨_, Step.convictActive c hfork, rfl, by
        simp only [outflowTotal_append, outflowTotal, carried, Value]; omega⟩
    | armed k h d =>
      exact ⟨_, Step.convictArmed c hfork, rfl, by
        simp only [outflowTotal_append, outflowTotal, carried, Value]; omega⟩
    | frozen k =>
      exact ⟨_, Step.convictFrozen c hfork, rfl, by
        simp only [outflowTotal_append, outflowTotal, carried, Value]; omega⟩
    | closing k r d =>
      exact ⟨_, Step.convictClosing c hfork, rfl, by
        simp only [outflowTotal_append, outflowTotal, carried, Value]; omega⟩
    | reaping k reaper d o =>
      exact ⟨_, Step.convictReaping c hfork, rfl, by
        simp only [outflowTotal_append, outflowTotal, carried, Value]; omega⟩
  · intro sys j ledj t hsj hicp
    have hstep : Step p env (sys j) ⟨t, .register⟩
        ⟨.active 0, { ledj with deposits := ledj.deposits + (p.minAda + p.D + p.B) }⟩ := by
      rw [hsj]
      exact Step.register hicp
    exact ⟨_, SysStep.step hstep⟩

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
  obtain ⟨txs, htr, hlen⟩ :=
    active_advance_chain p env (env.kel.events.length - 1) 0
      ⟨0 + (p.minAda + p.D + p.B), []⟩ 0
      (by rw [Nat.zero_add]; exact Nat.sub_lt hicp Nat.zero_lt_one)
  rw [Nat.zero_add (env.kel.events.length - 1)] at htr
  refine ⟨⟨0, .register⟩ :: txs, _,
    .cons (Nat.le_refl 0) (Step.register hicp) htr, rfl, ?_⟩
  rw [List.length_cons, hlen]
  exact Nat.sub_add_cancel hicp

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
  have hjlen : j < txs.length := getElem?_some_lt hj
  obtain ⟨c1, c2, hpre, hst, hsuf⟩ := htrace.step_at j txj hj
  cases hst <;> try (simp at hfin)
  case finalizeClose led k r d t hdeadline =>
    rcases hpre.last_step with ⟨hnil2, heq2⟩ | ⟨pre2, lst2, cmid2, heq2, hpre2, hst2⟩
    · exact absurd (congrArg Config.state heq2) (by simp [initConfig])
    · have hlen : (txs.take j).length = j := by
        rw [List.length_take]
        exact Nat.min_eq_left (Nat.le_of_lt hjlen)
      have hj1 : pre2.length + 1 = j := by
        rw [← hlen, heq2]
        simp
      cases hst2 with
      | @closeIntent led2 k2 t2 refund hcap =>
        refine ⟨pre2.length, ⟨t2, .closeIntent r⟩, r, hj1, ?_, rfl, hdeadline⟩
        rw [← List.getElem?_take_of_lt (by omega : pre2.length < j), heq2]
        exact List.getElem?_concat_length

/-- **Goal 18 — dead_end_freedom** (the burn axiom's theorem). From EVERY
reachable live state, at every slot, there exists an admissible transition
path ending in `.absent` (burnt) or in `.active _` (revived). No reachable
configuration is a dead end — nothing that is only a memory keeps a UTxO.
Sibling of `no_absorbing_busy_state`, but reap makes the FROZEN/REAPING exits
capability-free, so this needs NO capability or fork hypothesis at all
(strictly weaker than goal 2): Active is already a target (empty path); Frozen,
Armed and Reaping reach Active via the always-enabled advance (reachable ⇒
behind); Closing and Reaping reach Absent via the permissionless
finalize/reap-execute past their deadlines. -/
theorem dead_end_freedom (p : Params) (env : Env) (cfg : Config)
    (hreach : Reachable p env cfg) (hlive : cfg.state.live) :
    ∀ t : Slot, ∃ (txs : List Tx) (cfg' : Config),
      TraceFrom p env t cfg txs cfg' ∧
      (cfg'.state = .absent ∨ ∃ k : Seq, cfg'.state = .active k) := by
  obtain ⟨s, led⟩ := cfg
  intro t
  cases s with
  | absent => exact absurd hlive (by simp [MachState.live])
  | active k => exact ⟨[], _, .nil _ _, Or.inr ⟨k, rfl⟩⟩
  | frozen k =>
    have hb : env.kel.behind k := Reachable.frozen_behind hreach rfl
    exact ⟨[⟨t, .advance⟩], _,
      .cons (Nat.le_refl t) (Step.advanceFrozen hb) (.nil _ _), Or.inr ⟨k + 1, rfl⟩⟩
  | closing k r d =>
    exact ⟨[⟨max t d, .finalizeClose⟩], _,
      .cons (Nat.le_max_left t d) (Step.finalizeClose (Nat.le_max_right t d)) (.nil _ _),
      Or.inl rfl⟩
  | reaping k reaper d o =>
    exact ⟨[⟨max t d, .reapExecute⟩], _,
      .cons (Nat.le_max_left t d) (Step.reapExecute (Nat.le_max_right t d)) (.nil _ _),
      Or.inl rfl⟩
  | armed k hunter d =>
    have hb : env.kel.behind k := Reachable.armed_behind hreach rfl
    rcases Nat.lt_or_ge t d with hlt | hge
    · exact ⟨[⟨t, .advance⟩], _,
        .cons (Nat.le_refl t) (Step.advanceArmed hb hlt) (.nil _ _), Or.inr ⟨k + 1, rfl⟩⟩
    · exact ⟨[⟨t, .claim⟩, ⟨t, .advance⟩], _,
        .cons (Nat.le_refl t) (Step.claim hge)
          (.cons (Nat.le_refl t) (Step.advanceFrozen hb) (.nil _ _)),
        Or.inr ⟨k + 1, rfl⟩⟩

/-- **Goal 19 — reap_voidable.** A reachable REAPING admits the direct
advance-void at every slot (`reachable ⇒ behind`, extending the
`reachable_behind` lemmas to the reaping state). Stated stronger than "before
the deadline": like the close void it is admissible throughout, so past the
deadline it merely races the reap-execute and the ledger picks. -/
theorem reap_voidable (p : Params) (env : Env)
    (led : Ledger) (k : Seq) (reaper : Addr) (d : Slot) (o : ReapOrigin)
    (hreach : Reachable p env ⟨.reaping k reaper d o, led⟩) :
    ∀ t : Slot, ∃ cfg' : Config,
      Step p env ⟨.reaping k reaper d o, led⟩ ⟨t, .advance⟩ cfg' := by
  have hb : env.kel.behind k := Reachable.reaping_behind hreach rfl
  intro t
  exact ⟨_, Step.advanceReaping hb⟩

/-- **Goal 20 — reap_requires_untouched_window.** A reapExecute at slot `s` is
immediately preceded (`i + 1 = j`) by its own reapIntent, posted at slot
`≤ s − Wr`: the reaping sat untouched through a full `Wr` window. The
`close_cycle_requires_elapsed_window` pattern, for the third window. -/
theorem reap_requires_untouched_window (p : Params) (env : Env)
    (txs : List Tx) (cfg : Config)
    (htrace : TraceFrom p env 0 initConfig txs cfg)
    (j : Nat) (txj : Tx)
    (hj : txs[j]? = some txj) (hexec : txj.act = .reapExecute) :
    ∃ (i : Nat) (txi : Tx) (reaper : Addr),
      i + 1 = j ∧
      txs[i]? = some txi ∧
      txi.act = .reapIntent reaper ∧
      txi.slot + p.Wr ≤ txj.slot := by
  have hjlen : j < txs.length := getElem?_some_lt hj
  obtain ⟨c1, c2, hpre, hst, hsuf⟩ := htrace.step_at j txj hj
  cases hst <;> try (simp at hexec)
  case reapExecute led k reaper d o t hdeadline =>
    rcases hpre.last_step with ⟨hnil2, heq2⟩ | ⟨pre2, lst2, cmid2, heq2, hpre2, hst2⟩
    · exact absurd (congrArg Config.state heq2) (by simp [initConfig])
    · have hlen : (txs.take j).length = j := by
        rw [List.length_take]
        exact Nat.min_eq_left (Nat.le_of_lt hjlen)
      have hj1 : pre2.length + 1 = j := by
        rw [← hlen, heq2]
        simp
      cases hst2 with
      | @reapIntentFrozen _ _ t2 _ =>
        refine ⟨pre2.length, ⟨t2, .reapIntent reaper⟩, reaper, hj1, ?_, rfl, hdeadline⟩
        rw [← List.getElem?_take_of_lt (by omega : pre2.length < j), heq2]
        exact List.getElem?_concat_length
      | @reapIntentClosing _ _ _ _ t2 _ hstale2 hbehind2 =>
        refine ⟨pre2.length, ⟨t2, .reapIntent reaper⟩, reaper, hj1, ?_, rfl, hdeadline⟩
        rw [← List.getElem?_take_of_lt (by omega : pre2.length < j), heq2]
        exact List.getElem?_concat_length

/-- **Goal 21 — frozen_reap_requires_two_windows.** Any trace reaching a
FROZEN-origin REAPING (`.fromFrozen`) contains an earlier arm→claim pair a full
`Wf` apart with no intervening advance: TWO consecutive unanswered public
windows precede a FROZEN-origin reap (`Wf` then `Wr`). A reapExecute can only
fire from such a reachable reaping, so this covers the "FROZEN-origin
reapExecute implies two windows" claim a fortiori. Composes
`frozen_implies_true_silence` (the freeze window) with the reap-intent that
opened the second. -/
theorem frozen_reap_requires_two_windows (p : Params) (env : Env)
    (txs : List Tx) (k : Seq) (reaper : Addr) (d : Slot) (ledr : Ledger)
    (hreaching :
      TraceFrom p env 0 initConfig txs ⟨.reaping k reaper d .fromFrozen, ledr⟩) :
    ∃ (a b : Nat) (txa txb : Tx) (h : Addr),
      txs[a]? = some txa ∧ txs[b]? = some txb ∧ a < b ∧
      (txa.act = .arm h ∨ txa.act = .challengeClose h) ∧
      txb.act = .claim ∧
      txa.slot + p.Wf ≤ txb.slot ∧
      (∀ (m : Nat) (txm : Tx),
        a < m → m < b → txs[m]? = some txm → txm.act ≠ .advance) := by
  rcases hreaching.last_step with ⟨hnil, heq⟩ | ⟨pre, lst, cmid, heq, hpre, hst⟩
  · exact absurd (congrArg Config.state heq) (by simp [initConfig])
  · cases hst with
    | @reapIntentFrozen _ _ t2 _ =>
      have lift : ∀ (m : Nat), m < pre.length → txs[m]? = pre[m]? := by
        intro m hm
        rw [heq, List.getElem?_append_left hm]
      obtain ⟨a, b, txa, txb, h, ha, hb, hab, hact, hcl, hwin, hbet⟩ :=
        frozen_implies_true_silence p env pre ⟨.frozen k, ledr⟩ hpre k rfl
      refine ⟨a, b, txa, txb, h, ?_, ?_, hab, hact, hcl, hwin, ?_⟩
      · rw [lift a (getElem?_some_lt ha)]; exact ha
      · rw [lift b (getElem?_some_lt hb)]; exact hb
      · intro m txm hm1 hm2 hmem
        have hmpre : m < pre.length := Nat.lt_trans hm2 (getElem?_some_lt hb)
        rw [lift m hmpre] at hmem
        exact hbet m txm hm1 hm2 hmem

end CardanoKeri
