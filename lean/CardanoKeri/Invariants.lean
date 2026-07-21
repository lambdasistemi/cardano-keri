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

end CardanoKeri
