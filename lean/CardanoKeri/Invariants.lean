import CardanoKeri.Lifecycle

/-!
# Shared invariant lemmas

Workhorse lemmas extracted from the phase-2 goal proofs (ticket #124).
They are the seed inventory for the QuickCheck properties of the #114/#115/
#116 reworks: each names one machine fact a property-based test can vector.
-/

namespace CardanoKeri

/-- An index that resolves in a list is in bounds. -/
theorem getElem?_some_lt {α : Type} {l : List α} {i : Nat} {a : α}
    (h : l[i]? = some a) : i < l.length := by
  cases Nat.lt_or_ge i l.length with
  | inl hlt => exact hlt
  | inr hge =>
    rw [List.getElem?_eq_none hge] at h
    simp at h

/-- Payout totals add across appends. -/
theorem outflowTotal_append (xs ys : List Transfer) :
    outflowTotal (xs ++ ys) = outflowTotal xs + outflowTotal ys := by
  induction xs with
  | nil => simp [outflowTotal]
  | cons x xs ih => simp [outflowTotal, ih, Nat.add_assoc]

/-- The empty instance is balanced. -/
theorem initConfig_balanced (p : Params) : initConfig.balanced p := rfl

/-- **Per-transition conservation** (goal 13's engine): every admissible
step preserves carried + paid-out = paid-in. -/
theorem Step.preserves_balanced {p : Params} {env : Env}
    {cfg : Config} {tx : Tx} {cfg' : Config}
    (hstep : Step p env cfg tx cfg') (hbal : cfg.balanced p) :
    cfg'.balanced p := by
  cases hstep <;>
    simp_all [Config.balanced, carried, outflowTotal_append, outflowTotal,
      Nat.add_comm, Nat.add_left_comm] <;>
    (rw [← hbal]; simp [Nat.add_comm, Nat.add_left_comm])

/-- Balance is preserved along any trace. -/
theorem TraceFrom.preserves_balanced {p : Params} {env : Env} {t : Slot}
    {c0 c : Config} {txs : List Tx}
    (h : TraceFrom p env t c0 txs c) (h0 : c0.balanced p) : c.balanced p := by
  induction h with
  | nil _ _ => exact h0
  | @cons t cfg cfg' cfg'' tx txs hmono hstep hrest ih =>
    exact ih (hstep.preserves_balanced h0)

/-- Decompose a nonempty trace at its final transition: every fact about the
final state is witnessed by the last step's constructor. -/
theorem TraceFrom.last_step {p : Params} {env : Env} {t : Slot}
    {c0 c : Config} {txs : List Tx}
    (h : TraceFrom p env t c0 txs c) :
    (txs = [] ∧ c0 = c) ∨
    ∃ (pre : List Tx) (lst : Tx) (cmid : Config),
      txs = pre ++ [lst] ∧
      TraceFrom p env t c0 pre cmid ∧
      Step p env cmid lst c := by
  induction h with
  | nil t cfg => exact Or.inl ⟨rfl, rfl⟩
  | @cons t cfg cfg' cfg'' tx txs hmono hstep hrest ih =>
    rcases ih with ⟨hnil, heq⟩ | ⟨pre, lst, cmid, heq, htr, hst⟩
    · subst hnil
      subst heq
      exact Or.inr ⟨[], tx, cfg, rfl, .nil _ _, hstep⟩
    · subst heq
      exact Or.inr ⟨tx :: pre, lst, cmid, rfl, .cons hmono hstep htr, hst⟩

/-- Decompose a trace at index `j`: prefix trace, the step at `j`, suffix
trace. -/
theorem TraceFrom.step_at {p : Params} {env : Env} {t : Slot}
    {c0 c : Config} {txs : List Tx}
    (h : TraceFrom p env t c0 txs c) (j : Nat) (txj : Tx)
    (hj : txs[j]? = some txj) :
    ∃ (c1 c2 : Config),
      TraceFrom p env t c0 (txs.take j) c1 ∧
      Step p env c1 txj c2 ∧
      TraceFrom p env txj.slot c2 (txs.drop (j + 1)) c := by
  induction h generalizing j with
  | nil _ _ => simp at hj
  | @cons t cfg cfg' cfg'' tx txs hmono hstep hrest ih =>
    cases j with
    | zero =>
      simp at hj
      subst hj
      exact ⟨cfg, cfg', .nil _ _, hstep, hrest⟩
    | succ j' =>
      simp only [List.getElem?_cons_succ] at hj
      obtain ⟨c1, c2, h1, h2, h3⟩ := ih j' hj
      exact ⟨c1, c2, .cons hmono hstep h1, h2, h3⟩

/-- Resolve an in-bounds index to its element. -/
theorem getElem?_isSome_of_lt {α : Type} {l : List α} {i : Nat}
    (h : i < l.length) : ∃ a, l[i]? = some a := by
  cases hx : l[i]? with
  | some a => exact ⟨a, rfl⟩
  | none =>
    rw [List.getElem?_eq_none_iff] at hx
    exact absurd h (Nat.not_lt.mpr hx)

/-- Every advance lands in an Active state. -/
theorem Step.advance_target {p : Params} {env : Env}
    {cfg : Config} {tx : Tx} {cfg' : Config}
    (h : Step p env cfg tx cfg') (hadv : tx.act = .advance) :
    ∃ (k : Seq) (led : Ledger), cfg' = ⟨.active k, led⟩ := by
  cases h <;> simp_all

/-- Reachable Armed and Frozen states are genuinely behind: arming (and the
challenge that re-arms) proves a later event, claim preserves the position,
and the KEL is fixed per trace. -/
theorem reachable_behind {p : Params} {env : Env} :
    ∀ (n : Nat) (txs : List Tx) (cfg : Config), txs.length ≤ n →
      TraceFrom p env 0 initConfig txs cfg →
      (∀ (k : Seq) (hunter : Addr) (d : Slot),
        cfg.state = .armed k hunter d → env.kel.behind k) ∧
      (∀ k : Seq, cfg.state = .frozen k → env.kel.behind k) := by
  intro n
  induction n with
  | zero =>
    intro txs cfg hlen htr
    have htxs : txs = [] := List.eq_nil_of_length_eq_zero (Nat.le_zero.mp hlen)
    subst htxs
    cases htr
    exact ⟨fun k hunter d h => by simp [initConfig] at h,
           fun k h => by simp [initConfig] at h⟩
  | succ n ih =>
    intro txs cfg hlen htr
    rcases htr.last_step with ⟨hnil, heq⟩ | ⟨pre, lst, cmid, heq, hpre, hst⟩
    · rw [← heq]
      exact ⟨fun k hunter d h => by simp [initConfig] at h,
             fun k h => by simp [initConfig] at h⟩
    · subst heq
      have hlenpre : pre.length ≤ n := by
        simp only [List.length_append, List.length_cons, List.length_nil] at hlen
        omega
      constructor
      · intro k hunter d h
        cases hst <;> simp at h
        case arm led2 k2 t2 hunter2 hbehind2 =>
          obtain ⟨hk, -, -⟩ := h
          subst hk
          exact hbehind2
        case challengeClose led2 k2 r2 d2 t2 ch2 hbehind2 =>
          obtain ⟨hk, -, -⟩ := h
          subst hk
          exact hbehind2
      · intro k h
        cases hst <;> simp at h
        case claim led2 k2 hunter2 d2 t2 hdl =>
          subst h
          exact (ih pre _ hlenpre hpre).1 _ hunter2 d2 rfl

/-- A reachable Armed state is behind (the arm guard proved a later event). -/
theorem Reachable.armed_behind {p : Params} {env : Env} {cfg : Config}
    (h : Reachable p env cfg) {k : Seq} {hunter : Addr} {d : Slot}
    (hs : cfg.state = .armed k hunter d) : env.kel.behind k := by
  obtain ⟨txs, htr⟩ := h
  exact (reachable_behind txs.length txs cfg (Nat.le_refl _) htr).1 k hunter d hs

/-- A reachable Frozen state is behind: the thaw advance is always enabled. -/
theorem Reachable.frozen_behind {p : Params} {env : Env} {cfg : Config}
    (h : Reachable p env cfg) {k : Seq}
    (hs : cfg.state = .frozen k) : env.kel.behind k := by
  obtain ⟨txs, htr⟩ := h
  exact (reachable_behind txs.length txs cfg (Nat.le_refl _) htr).2 k hs

/-- In the permissionless fragment (no fork evidence, no close capability)
an Active state admits at most two consecutive non-advance transitions —
arm, then claim — and Frozen then admits only advance. Three in a row is
impossible. -/
theorem fragment_no_three_stalls {p : Params} {env : Env}
    (hcap : ∀ s : Seq, ¬ env.canClose s) (hfork : ¬ env.fork)
    {k : Seq} {led : Ledger} {t : Slot} {txs : List Tx} {c : Config}
    (htr : TraceFrom p env t ⟨.active k, led⟩ txs c)
    {a b cc : Tx}
    (h0 : txs[0]? = some a) (h1 : txs[1]? = some b) (h2 : txs[2]? = some cc)
    (na : a.act ≠ .advance) (nb : b.act ≠ .advance) (nc : cc.act ≠ .advance) :
    False := by
  cases htr with
  | nil => simp at h0
  | @cons _ _ cfg1 _ tx1 rest1 hmono1 hstep1 hrest1 =>
    simp at h0 h1 h2
    subst h0
    cases hstep1 with
    | @advanceActive _ _ _ hnext => exact na rfl
    | @closeIntent _ _ _ refund hcapk => exact hcap _ hcapk
    | @convictActive _ _ _ cv hf => exact hfork hf
    | @arm _ _ _ hunter hbehind =>
      cases hrest1 with
      | nil => simp at h1
      | @cons _ _ cfg2 _ tx2 rest2 hmono2 hstep2 hrest2 =>
        simp at h1 h2
        subst h1
        cases hstep2 with
        | @advanceArmed _ _ _ _ _ hnext hwin => exact nb rfl
        | @convictArmed _ _ _ _ _ cv hf => exact hfork hf
        | @claim _ _ _ _ _ hdl =>
          cases hrest2 with
          | nil => simp at h2
          | @cons _ _ cfg3 _ tx3 rest3 hmono3 hstep3 hrest3 =>
            simp at h2
            subst h2
            cases hstep3 with
            | @advanceFrozen _ _ _ hnext => exact nc rfl
            | @convictFrozen _ _ _ cv hf => exact hfork hf

/-- From Active k, a chain of `n` plain advances is admissible whenever the
KEL extends that far (all at one slot). -/
theorem active_advance_chain (p : Params) (env : Env) :
    ∀ (n : Nat) (k : Seq) (led : Ledger) (t : Slot),
      k + n < env.kel.events.length →
      ∃ txs : List Tx,
        TraceFrom p env t ⟨.active k, led⟩ txs ⟨.active (k + n), led⟩ ∧
        txs.length = n := by
  intro n
  induction n with
  | zero =>
    intro k led t _
    exact ⟨[], .nil _ _, rfl⟩
  | succ n ih =>
    intro k led t hlt
    have harr : k + 1 + n = k + (n + 1) := by
      rw [Nat.add_assoc, Nat.add_comm 1 n]
    have hnext : env.kel.hasEvent (k + 1) :=
      Nat.lt_of_le_of_lt
        (Nat.le_trans (Nat.le_add_right (k + 1) n) (Nat.le_of_eq harr)) hlt
    obtain ⟨txs, htr, hlen⟩ := ih (k + 1) led t (by rw [harr]; exact hlt)
    refine ⟨⟨t, .advance⟩ :: txs, ?_, by simp [hlen]⟩
    have htr' : TraceFrom p env t ⟨.active (k + 1), led⟩ txs
        ⟨.active (k + (n + 1)), led⟩ := by
      rw [← harr]
      exact htr
    exact .cons (Nat.le_refl t) (Step.advanceActive hnext) htr'

end CardanoKeri
