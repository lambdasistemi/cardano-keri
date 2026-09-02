import CardanoKeri.Checkpoint

/-!
# The M1 return: theorem statements, second cut

Statements after the independent audit of 2026-09-02
(`handoffs/lean-audit/FINDINGS-codex-statement-audit.md`). Every `sorry` is
a deliberate placeholder for the proof phase. Numbering follows the plan's
Phase 0 list; the audit's additions keep the number of the property they
strengthen.

Every theorem below is a property of this model. Whether the model is the
right model is settled against the plan, the rulings and the stories, not
by `lake build`.
-/

namespace CardanoKeri.Checkpoint

/-! ## T1 — the checkpoint cannot roll back -/

/-- **T1a.** No step between present states decreases the sequence. -/
theorem T1_sn_monotone (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) : l.sn ≤ l'.sn := by
  sorry

/-- **T1b.** Every rotation strictly increases the sequence. -/
theorem T1_rotate_strict (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {op : BondOp} {payee : Addr} {r' : Option Addr}
    (h : Step p env (.rotate sn' op payee r') t (.present l) f (.present l')) : l.sn < l'.sn := by
  sorry

/-- **T1c.** Along any trace between present states the sequence never
decreases. -/
theorem T1_trace_sn_monotone (p : Params) (env : Env) {t : Slot} {l l' : Live}
    {es : List (Slot × Action)} (h : Trace p env t (.present l) es (.present l')) : l.sn ≤ l'.sn := by
  sorry

/-! ## T2 — keys change only by rotation -/

/-- **T2.** The epoch changes only under a rotation, and then by one. -/
theorem T2_epoch_only_by_rotation (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.epoch ≠ l.epoch) :
    a.actor = .nextKeys ∧ l'.epoch = l.epoch + 1 := by
  sorry

/-! ## T3 — poison is epoch-local -/

/-- **T3a.** A rotation always yields an unpoisoned state. -/
theorem T3_rotation_clears (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {op : BondOp} {payee : Addr} {r' : Option Addr}
    (h : Step p env (.rotate sn' op payee r') t (.present l) f (.present l')) : l'.poisoned = false := by
  sorry

/-- **T3b.** Only a rotation clears the poison. -/
theorem T3_only_rotation_clears (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l'))
    (hp : l.poisoned = true) (hc : l'.poisoned = false) : a.actor = .nextKeys := by
  sorry

/-- **T3c.** Only the poison sets it, from a clean state, and it changes
nothing else. -/
theorem T3_only_poison_sets (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l'))
    (hset : l.poisoned = false) (hset' : l'.poisoned = true) :
    a = .poison ∧ l' = { l with poisoned := true } ∧ f = {} := by
  sorry

/-- **T3d.** Along any trace from `absent`, the checkpoint is poisoned
exactly when the last epoch-relevant action was a poison. -/
theorem T3_epoch_local (p : Params) (env : Env) {t : Slot} {es : List (Slot × Action)} {l : Live}
    (h : Trace p env t .absent es (.present l)) :
    l.poisoned = poisonSinceLastRotation es := by
  sorry

/-! ## T4 — poisoned keys can only be rotated -/

/-- **T4a.** From a poisoned state the current quorum can do nothing, and no
proof can freeze it. -/
theorem T4_poisoned_blocks_quorum_and_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l : Live} {f : Flow} {s' : State}
    (h : Step p env a t (.present l) f s') (hp : l.poisoned = true) :
    a.actor ≠ .currentQuorum ∧ (∀ sn' payee, a ≠ .freeze sn' payee) := by
  sorry

/-- **T4b.** From a poisoned state, nothing but a rotation yields a
consumable state. -/
theorem T4_poisoned_nonrotation_inert (p : Params) (env : Env) {a : Action} {t t' : Slot}
    {l : Live} {f : Flow} {s' : State}
    (h : Step p env a t (.present l) f s') (hp : l.poisoned = true) (hn : a.actor ≠ .nextKeys) :
    ¬ consumableState p t' s' := by
  sorry

/-! ## T5 — totality: every ruled transition is enabled when its evidence is -/

/-- **T5a.** Given a valid witnessed rotation, every bond option is
enabled — whatever the pool holds (payment is never a gate, T14). -/
theorem T5_every_bond_option (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq)
    (payee : Addr) (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hd : l.dreg ≤ p.D) (hb : l.b ≤ p.B) :
    ∀ op : BondOp, ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' op payee none) t (.present l) f (.present l') := by
  sorry

/-- **T5b.** Given the quorum, an unpoisoned state can be poisoned. -/
theorem T5_poison_enabled (p : Params) (env : Env) (t : Slot) (l : Live)
    (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
    ∃ l', Step p env .poison t (.present l) {} (.present l') := by
  sorry

/-- **T5c.** Given a later witnessed rotation, a short pool, a full freeze
bond and no poison, the freeze is enabled. -/
theorem T5_freeze_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr)
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hpool : l.pool < p.P) (hb : l.b = p.B) (hclean : l.poisoned = false) :
    ∃ (f : Flow) (l' : Live), Step p env (.freeze sn' payee) t (.present l) f (.present l') := by
  sorry

/-- **T5d.** Given a duplicity proof, conviction is enabled from every
present state, poisoned or paused included. -/
theorem T5_convict_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (payee : Addr)
    (hdup : env.duplicityAt l.epoch l.sn = true) :
    ∃ f, Step p env (.convict payee) t (.present l) f (.convicted l.epoch l.sn t) := by
  sorry

/-- **T5e.** Given the quorum, an unpoisoned state can be closed. -/
theorem T5_close_enabled (p : Params) (env : Env) (t : Slot) (l : Live)
    (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
    ∃ f, Step p env .close t (.present l) f .gone := by
  sorry

/-! ## T6 — value: three components that never mix -/

/-- **T6a.** Component-wise conservation: for each of the conviction bond,
the freeze bond and the pool, held plus in equals held after plus out. -/
theorem T6_component_conservation (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    s.dregHeld + f.dregIn = s'.dregHeld + Payment?.dreg f.refund + Payment?.dreg f.hunter + Payment?.dreg f.convictor ∧
    s.bHeld + f.bIn = s'.bHeld + Payment?.b f.refund + Payment?.b f.hunter + Payment?.b f.convictor ∧
    s.poolHeld + f.poolIn = s'.poolHeld + Payment?.pool f.refund + Payment?.pool f.hunter + Payment?.pool f.convictor := by
  sorry

/-- **T6b.** The conviction bond is never a fee source: no hunter payment
ever carries it, and it leaves a present state only whole, to the refund
address (withdraw, close) or to the convictor. -/
theorem T6_dreg_never_a_fee (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    Payment?.dreg f.hunter = 0 ∧
    (Payment?.dreg f.refund ≠ 0 → Payment?.dreg f.refund = s.dregHeld ∧ s'.dregHeld = 0) ∧
    (Payment?.dreg f.convictor ≠ 0 → Payment?.dreg f.convictor = s.dregHeld ∧ ∃ e n c, s' = .convicted e n c) := by
  sorry

/-- **T6c.** The conviction bond re-enters only by registration or a
depositing rotation, and then to full. -/
theorem T6_dreg_increases_only_by_deposit (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hlt : l.dreg < l'.dreg) :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧ l'.dreg = p.D ∧ l'.b = p.B ∧
    f.dregIn = p.D - l.dreg ∧ f.bIn = p.B - l.b ∧ l'.bornAt = t := by
  sorry

/-- **T6d.** `refundTo` changes only under a rotation whose new keys
authorized the new address (D-032). -/
theorem T6_refund_change_requires_new_keys (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.refundTo ≠ l.refundTo) :
    a.actor = .nextKeys ∧ env.refundAuthorized l'.epoch l'.refundTo = true := by
  sorry

/-- **T6e.** Poison and top-up move no bond; only rotations and freezes do. -/
theorem T6_bonds_move_only_by_rotation_or_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.dreg ≠ l.dreg ∨ l'.b ≠ l.b) :
    a.actor = .nextKeys ∨ (∃ sn' payee, a = .freeze sn' payee) := by
  sorry

/-! ## T7 — the state is the fold of the accepted actions -/

/-- **T7a.** The relation and the functional step agree exactly. -/
theorem T7_step_iff_stepFn (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} :
    Step p env a t s f s' ↔ stepFn p env a t s = some (f, s') := by
  sorry

/-- **T7b.** A trace is exactly a successful replay. -/
theorem T7_trace_iff_replay (p : Params) (env : Env) {t : Slot} {s s' : State} {es : List (Slot × Action)} :
    Trace p env t s es s' ↔ replay p env t s es = some s' := by
  sorry

/-! ## T8 — one incarnation per AID, ever -/

/-- **T8a.** In every reachable system the registry has no duplicates:
registration inserts under an absence proof and nothing else touches it. -/
theorem T8_registry_nodup (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) :
    s.registered.Nodup := by
  sorry

/-- **T8b.** The registry only grows. -/
theorem T8_registry_monotone (p : Params) (env : Env) {s s' : Sys} (h : SysStep p env s s') :
    ∀ aid, aid ∈ s.registered → aid ∈ s'.registered := by
  sorry

/-- **T8c.** In every reachable system, an AID with a state other than
`absent` is in the registry. -/
theorem T8_present_implies_registered (p : Params) (env : Env) {s : Sys} (h : SysReach p env s)
    (aid : AID) (hne : s.states aid ≠ .absent) : aid ∈ s.registered := by
  sorry

/-- **T8d.** Registration is the only step from `absent`, and none from `gone`. -/
theorem T8_absent_only_registers (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State}
    (h : Step p env a t .absent f s') : ∃ refund pool0, a = .register refund pool0 := by
  sorry

theorem T8_gone_terminal (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State}
    (h : Step p env a t .gone f s') : False := by
  sorry

/-! ## T9 — juvenility is consumer policy -/

/-- **T9.** No transition depends on `W`. -/
theorem T9_juvenility_is_consumer_only (p : Params) (env : Env) (W' : Nat) {a : Action} {t : Slot}
    {s s' : State} {f : Flow} :
    Step p env a t s f s' ↔ Step { p with W := W' } env a t s f s' := by
  sorry

/-! ## T10 — an unbonded or frozen checkpoint is inert to everyone but the next keys -/

/-- **T10a.** If either bond is missing, no step by anyone but the next keys
yields a consumable state. -/
theorem T10_inert_without_next_keys (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p env a t (.present l) f s')
    (hmissing : l.dreg ≠ p.D ∨ l.b ≠ p.B) (hnot : a.actor ≠ .nextKeys) :
    ¬ consumableState p t' s' := by
  sorry

/-- **T10b.** Only a depositing rotation restores consumability, and it
restarts juvenility. -/
theorem T10_only_deposit_restores (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p env a t (.present l) f s')
    (hmissing : l.dreg ≠ p.D ∨ l.b ≠ p.B) (hc : consumableState p t' s') :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧
    ∃ l', s' = .present l' ∧ l'.dreg = p.D ∧ l'.b = p.B ∧ l'.bornAt = t := by
  sorry

/-- **T10c.** The current quorum never produces a consumable state: its only
moves are poison and close. -/
theorem T10_current_quorum_never_restores (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live}
    {f : Flow} {s' : State} (h : Step p env a t (.present l) f s') (hq : a.actor = .currentQuorum) :
    ¬ consumableState p t' s' := by
  sorry

/-! ## T12 — conviction is terminal, needs a proof, and is exact -/

/-- **T12a.** No step leaves `convicted`. -/
theorem T12_convicted_terminal (p : Params) (env : Env) {a : Action} {t : Slot} {e : Epoch} {n : Seq}
    {c : Slot} {f : Flow} {s' : State} (h : Step p env a t (.convicted e n c) f s') : False := by
  sorry

/-- **T12b.** Only a conviction reaches `convicted`; the tombstone records
the tip's epoch and sequence and the slot of the conviction; the flow is
exactly the conviction bond to the convictor and the rest to the refund
address. -/
theorem T12_convict_exact (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow}
    {e : Epoch} {n : Seq} {c : Slot} (h : Step p env a t (.present l) f (.convicted e n c)) :
    (∃ payee, a = .convict payee ∧
      f = { refund := some { addr := l.refundTo, b := l.b, pool := l.pool },
            convictor := some { addr := payee, dreg := l.dreg } }) ∧
    e = l.epoch ∧ n = l.sn ∧ c = t ∧ env.duplicityAt l.epoch l.sn = true := by
  sorry

/-! ## T14, T15 — the pool and the freeze bond -/

/-- **T14a.** The pool decreases only by the premium under a paid rotation,
or to zero under a withdrawing rotation. -/
theorem T14_pool_decreases_only_by_premium (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l'.pool < l.pool) :
    a.actor = .nextKeys ∧
    ((l'.pool + p.P = l.pool ∧ Payment?.pool f.hunter = p.P) ∨ (l'.pool = 0 ∧ f.refund ≠ none)) := by
  sorry

/-- **T14b.** The pool increases only by a top-up. -/
theorem T14_pool_increases_only_by_topup (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l.pool < l'.pool) :
    ∃ x, a = .topUp x ∧ f = { poolIn := x } ∧ l' = { l with pool := l.pool + x } := by
  sorry

/-- **T15a.** The freeze bond leaves a present state only by a freeze —
proof of a later rotation, pool short, exactly `B` to the hunter, datum
otherwise untouched — or by a withdrawing rotation. -/
theorem T15_b_leaves_only_by_freeze_or_withdraw (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l'.b < l.b) :
    (∃ sn' payee, a = .freeze sn' payee ∧ env.rotationTo l.epoch l.sn sn' = true ∧ l.pool < p.P ∧
      l' = { l with b := 0 } ∧ f = { hunter := some { addr := payee, b := p.B } }) ∨
    (∃ sn' payee r', a = .rotate sn' .withdraw payee r' ∧ l'.b = 0 ∧ l'.dreg = 0 ∧ l'.pool = 0) := by
  sorry

/-- **T15b.** The freeze bond returns only by a depositing rotation, and then
to full. -/
theorem T15_b_returns_only_by_deposit (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hgt : l.b < l'.b) :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧ l'.b = p.B ∧ l'.dreg = p.D := by
  sorry

/-- **T15c.** A freeze makes the checkpoint unconsumable — the bond is
positive, so "missing" is observable. -/
theorem T15_freeze_makes_inert (p : Params) (env : Env) {t t' : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {payee : Addr} (h : Step p env (.freeze sn' payee) t (.present l) f (.present l')) :
    ¬ consumableState p t' (.present l') := by
  sorry

/-! ## T16 — the closer chooses when, never where -/

/-- **T16a.** Close pays everything to the refund address recorded in the
datum, and only from an unpoisoned state under the quorum. -/
theorem T16_close_destination (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow}
    (h : Step p env a t (.present l) f .gone) :
    a = .close ∧ f = { refund := some { addr := l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } } ∧
    l.poisoned = false ∧ env.quorum l.epoch = true := by
  sorry

/-- **T16b.** A withdrawing rotation pays everything to the refund address
it results in — the one in the datum, or the one the new keys authorized. -/
theorem T16_withdraw_destination (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {payee : Addr} {r' : Option Addr}
    (h : Step p env (.rotate sn' .withdraw payee r') t (.present l) f (.present l')) :
    f = { refund := some { addr := l'.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } } ∧
    l'.refundTo = r'.getD l.refundTo := by
  sorry

/-- **T16c.** No step pays the refund address anything but the withdrawal,
the close, or the conviction's residue; no step pays a hunter anything but
the premium or the freeze bond. -/
theorem T16_payments_are_named (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    (∀ q, f.hunter = some q → (q.dreg = 0 ∧ q.b = 0 ∧ q.pool = p.P) ∨ (q.dreg = 0 ∧ q.b = p.B ∧ q.pool = 0)) ∧
    (∀ q, f.convictor = some q → q.b = 0 ∧ q.pool = 0 ∧ q.dreg = s.dregHeld) := by
  sorry

end CardanoKeri.Checkpoint
