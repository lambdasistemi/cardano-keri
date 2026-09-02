import CardanoKeri.Checkpoint

/-!
# The M1 return: theorem statements T1 … T16

Statements first, proofs after an independent audit of the statements
(operator process, 2026-09-02). Every `sorry` here is a deliberate
placeholder; the audit reads the statements against the design in
`AUDIT-M1-RETURN` Phase 0 and D-022 … D-034, looking for statements that are
narrower than their names, vacuous arms, and missing invariants. Proofs are
filled only after that audit.

Naming follows the plan: T1 … T15 as listed under Phase 0, plus T16 for the
close destination (D-032).
-/

namespace CardanoKeri.Checkpoint

/-! ## T1 — the checkpoint cannot roll back -/

/-- **T1a.** No step between present states decreases the sequence. -/
theorem T1_sn_monotone (p : Params) {a : Actor} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p a t (.present l) f (.present l')) : l.sn ≤ l'.sn := by
  sorry

/-- **T1b.** A rotation strictly increases the sequence; every step by the
next keys is a rotation. -/
theorem T1_rotate_strict (p : Params) {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p .nextKeys t (.present l) f (.present l')) : l.sn < l'.sn := by
  sorry

/-! ## T2 — keys change only by rotation -/

/-- **T2.** The epoch changes only under the next keys; poison, freeze and
top-up leave it alone. -/
theorem T2_epoch_only_by_rotation (p : Params) {a : Actor} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p a t (.present l) f (.present l')) (hne : l'.epoch ≠ l.epoch) :
    a = .nextKeys ∧ l'.epoch = l.epoch + 1 := by
  sorry

/-! ## T3 — poison is epoch-local -/

/-- **T3a.** A rotation always yields an unpoisoned state. -/
theorem T3_rotation_clears (p : Params) {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p .nextKeys t (.present l) f (.present l')) : l'.poisoned = false := by
  sorry

/-- **T3b.** The only step that sets the poison is the current quorum's
poison, and it is enabled only when the state is clean. -/
theorem T3_only_poison_sets (p : Params) {a : Actor} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p a t (.present l) f (.present l'))
    (hset : l.poisoned = false) (hset' : l'.poisoned = true) :
    a = .currentQuorum ∧ l' = { l with poisoned := true } := by
  sorry

/-! ## T4 — poisoned keys can only be rotated -/

/-- **T4.** From a poisoned state the current quorum can do nothing (no
close, no second poison), and no proof can freeze it; what remains is the
next keys' rotation, anyone's top-up, and a conviction. -/
theorem T4_poisoned_only_rotates (p : Params) {a : Actor} {t : Slot} {l : Live} {f : Flow} {s' : State}
    (h : Step p a t (.present l) f s') (hp : l.poisoned = true) :
    a ≠ .currentQuorum ∧ (a = .proof → s' = .convicted l.epoch l.sn) := by
  sorry

/-! ## T5 — totality: no present state is absorbing -/

/-- **T5a.** From every present state the next keys can rotate, whatever the
pool holds (this is also T14: payment is never a gate). -/
theorem T5_rotation_always_enabled (p : Params) (t : Slot) (l : Live) :
    ∃ (f : Flow) (l' : Live), Step p .nextKeys t (.present l) f (.present l') := by
  sorry

/-- **T5b.** From every unpoisoned present state the current quorum can poison. -/
theorem T5_poison_enabled (p : Params) (t : Slot) (l : Live) (hclean : l.poisoned = false) :
    ∃ l', Step p .currentQuorum t (.present l) {} (.present l') := by
  sorry

/-! ## T6 — value conservation and the bond rules -/

/-- **T6a.** Every step conserves value: what the state held plus what came
in equals what the state holds plus what went out. -/
theorem T6_conservation (p : Params) {a : Actor} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p a t s f s') :
    s.value + f.deposited = s'.value + f.toRefund + f.toHunter + f.toConvictor := by
  sorry

/-- **T6b.** The conviction bond is never a fee source: it leaves a present
state only whole, and only to the refund address (withdraw, close) or to the
convictor (convict); nothing else changes it. -/
theorem T6_dreg_never_a_fee (p : Params) {a : Actor} {t : Slot} {l : Live} {f : Flow} {s' : State}
    (h : Step p a t (.present l) f s') (hD : l.dreg = p.D) :
    (∃ l', s' = .present l' ∧ l'.dreg = p.D) ∨
    (a = .nextKeys ∧ f.toRefund = l.dreg + l.b + l.pool) ∨
    (a = .currentQuorum ∧ s' = .gone ∧ f.toRefund = l.dreg + l.b + l.pool) ∨
    (a = .proof ∧ s' = .convicted l.epoch l.sn ∧ f.toConvictor = l.dreg) := by
  sorry

/-- **T6c.** `refundTo` changes only under the next keys. -/
theorem T6_refund_only_by_rotation (p : Params) {a : Actor} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p a t (.present l) f (.present l')) (hne : l'.refundTo ≠ l.refundTo) :
    a = .nextKeys := by
  sorry

/-- **T6d.** Poison and top-up move no bond: `dreg` and `b` are untouched by
anything but the next keys and a freeze. -/
theorem T6_bonds_move_only_by_rotation_or_freeze (p : Params) {a : Actor} {t : Slot}
    {l l' : Live} {f : Flow}
    (h : Step p a t (.present l) f (.present l')) (hne : l'.dreg ≠ l.dreg ∨ l'.b ≠ l.b) :
    a = .nextKeys ∨ (a = .proof ∧ l'.dreg = l.dreg ∧ l'.b = 0) := by
  sorry

/-! ## T8 — one incarnation per AID, ever -/

/-- **T8a.** The registry only grows. -/
theorem T8_registry_monotone (p : Params) {s s' : Sys} (h : SysStep p s s') :
    ∀ aid, aid ∈ s.registered → aid ∈ s'.registered := by
  sorry

/-- **T8b.** A registered AID can never take the registration step again. -/
theorem T8_register_once (p : Params) {s s' : Sys} (hreach : SysReach p s)
    (aid : AID) (hin : aid ∈ s.registered)
    (h : SysStep p s s') : s'.registered.length = s.registered.length ∨ aid ∈ s.registered := by
  sorry

/-- **T8c.** In every reachable system, an AID with a state other than
`absent` is in the registry. -/
theorem T8_present_implies_registered (p : Params) {s : Sys} (hreach : SysReach p s)
    (aid : AID) (hne : s.states aid ≠ .absent) : aid ∈ s.registered := by
  sorry

/-- **T8d.** Gone is terminal. -/
theorem T8_gone_terminal (p : Params) {a : Actor} {t : Slot} {f : Flow} {s' : State}
    (h : Step p a t .gone f s') : False := by
  sorry

/-! ## T10 — an unbonded or frozen checkpoint is inert to the current keys -/

/-- **T10.** If either bond is missing, no step by anyone but the next keys
yields a consumable state. Only a depositing rotation restores
consumability. -/
theorem T10_inert_without_next_keys (p : Params) {a : Actor} {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p a t (.present l) f s')
    (hmissing : l.dreg ≠ p.D ∨ l.b ≠ p.B) (hnot : a ≠ .nextKeys) :
    ¬ consumable p t' s' := by
  sorry

/-- **T10'.** The current quorum can never make a state consumable: from a
consumable state its only moves are poison (unconsumable) and close (gone). -/
theorem T10_current_quorum_never_restores (p : Params) {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p .currentQuorum t (.present l) f s') : ¬ consumable p t' s' := by
  sorry

/-! ## T12 — conviction is terminal and needs a proof -/

/-- **T12a.** No step leaves `convicted`. -/
theorem T12_convicted_terminal (p : Params) {a : Actor} {t : Slot} {e : Epoch} {n : Seq}
    {f : Flow} {s' : State} (h : Step p a t (.convicted e n) f s') : False := by
  sorry

/-- **T12b.** Only a proof reaches `convicted`, and it seizes exactly the
conviction bond to the convictor. -/
theorem T12_convict_needs_proof (p : Params) {a : Actor} {t : Slot} {l : Live} {f : Flow}
    {e : Epoch} {n : Seq} (h : Step p a t (.present l) f (.convicted e n)) :
    a = .proof ∧ f.toConvictor = l.dreg ∧ f.toHunter = 0 := by
  sorry

/-! ## T14, T15 — the pool and the freeze bond -/

/-- **T14.** The pool decreases only by the premium under a rotation, or to
zero under a withdrawing rotation; it never gates anything (T5a). -/
theorem T14_pool_decreases_only_by_premium (p : Params) {a : Actor} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p a t (.present l) f (.present l')) (hlt : l'.pool < l.pool) :
    a = .nextKeys ∧ (l'.pool + p.P = l.pool ∧ f.toHunter = p.P ∨ l'.pool = 0) := by
  sorry

/-- **T15a.** The freeze bond leaves a present state only by a freeze — a
proof, while the pool is short of the premium, taking exactly `B` — or by a
withdrawing rotation. -/
theorem T15_b_leaves_only_by_freeze_or_withdraw (p : Params) {a : Actor} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p a t (.present l) f (.present l')) (hlt : l'.b < l.b) :
    (a = .proof ∧ l.pool < p.P ∧ l'.b = 0 ∧ f.toHunter = p.B ∧ l'.sn = l.sn ∧ l'.epoch = l.epoch) ∨
    (a = .nextKeys ∧ l'.b = 0 ∧ l'.dreg = 0 ∧ l'.pool = 0) := by
  sorry

/-- **T15b.** The freeze bond returns only by a rotation, and then to full. -/
theorem T15_b_returns_only_by_rotation (p : Params) {a : Actor} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p a t (.present l) f (.present l')) (hgt : l.b < l'.b) :
    a = .nextKeys ∧ l'.b = p.B ∧ l'.dreg = p.D := by
  sorry

/-- **T15c.** A freeze leaves the keys where they are: the old keys stay. -/
theorem T15_freeze_keeps_datum (p : Params) {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p .proof t (.present l) f (.present l')) :
    l'.sn = l.sn ∧ l'.epoch = l.epoch ∧ l'.poisoned = l.poisoned ∧
    l'.refundTo = l.refundTo ∧ l'.dreg = l.dreg ∧ l'.pool = l.pool := by
  sorry

/-! ## T16 — the closer chooses when, never where -/

/-- **T16.** Close and withdraw pay everything to the refund address recorded
in the datum; no step pays a bond anywhere else except the conviction bond
to a convictor and the premium or freeze bond to a hunter. -/
theorem T16_close_pays_refund (p : Params) {t : Slot} {l : Live} {f : Flow}
    (h : Step p .currentQuorum t (.present l) f .gone) :
    f.toRefund = l.dreg + l.b + l.pool ∧ f.toHunter = 0 ∧ f.toConvictor = 0 ∧ l.poisoned = false := by
  sorry

end CardanoKeri.Checkpoint
