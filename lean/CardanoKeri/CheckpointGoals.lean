import CardanoKeri.Checkpoint

/-!
# The M1 return: theorems T1 … T16, second slice (D-036, D-037, D-038)

Statements for the independent statement audit of the second Lean slice;
proofs follow it. Every theorem of the first slice stays, amended where the
rulings changed the antecedent; the additions keep the number of the property
they strengthen. Numbering follows the plan's Phase 0 list; T11 and T13 do not
exist.

Every theorem below is a property of this model. Whether the model is the
right model is settled against the plan, the rulings and the stories, not
by `lake build`.
-/

namespace CardanoKeri.Checkpoint

/-- `omega` after unfolding the `Nat` abbreviations, which it does not see
through. -/
macro "omega'" : tactic =>
  `(tactic| ((try dsimp only [Slot, Seq, Epoch, Addr, Value, AID] at *); omega))

/-! ## Terminal and non-terminal states -/

/-- **T12a.** No step leaves `convicted`. -/
theorem T12_convicted_terminal (p : Params) (env : Env) {a : Action} {t : Slot} {e : Epoch} {n : Seq}
    {c : Slot} {f : Flow} {s' : State} (h : Step p env a t (.convicted e n c) f s') : False := by
  sorry

/-- A trace from `convicted` goes nowhere. -/
theorem trace_from_convicted (p : Params) (env : Env) {t : Slot} {e : Epoch} {n : Seq} {c : Slot}
    {es : List (Slot × Action)} {s' : State}
    (h : Trace p env t (.convicted e n c) es s') : s' = .convicted e n c := by
  sorry

/-- **T8d.** Registration is the only step from `absent`. -/
theorem T8_absent_only_registers (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State}
    (h : Step p env a t .absent f s') : ∃ refund pool0, a = .register refund pool0 := by
  sorry

/-- **T8e.** Reopen is the only step from `closed` (D-036): the tombstone is
not terminal, and nothing but a later witnessed rotation leaves it. -/
theorem T8_closed_only_reopens (p : Params) (env : Env) {a : Action} {t : Slot} {e : Epoch} {n : Seq}
    {f : Flow} {s' : State} (h : Step p env a t (.closed e n) f s') :
    ∃ sn' refund pool0, a = .reopen sn' refund pool0 ∧ n < sn' ∧ env.rotationTo e n sn' = true ∧
      f = { dregIn := p.D, bIn := p.B, poolIn := pool0 } ∧
      s' = .present ⟨sn', e + 1, false, t, refund, p.D, p.B, pool0⟩ := by
  sorry

/-- **T8f.** Conviction is the only terminal state: from every other state
some step is enabled under suitable evidence — registration from `absent`,
a top-up from `present`, a reopen from `closed`. -/
theorem T8_only_convicted_is_terminal (p : Params) (env : Env) (t : Slot) (s : State)
    (hnot : ∀ e n c, s ≠ .convicted e n c)
    (hreopen : ∀ e n, s = .closed e n → env.rotationTo e n (n + 1) = true) :
    ∃ a f s', Step p env a t s f s' := by
  sorry

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

/-- **T1d.** No step decreases the sequence a state records, across every
state that records one: a close records the closing rotation's sequence, a
reopen is strictly later than the tombstone (no stale resurrection, D-036),
a conviction records the tip. -/
theorem T1_sn_monotone_all (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') (n n' : Seq) (hn : s.sn? = some n) (hn' : s'.sn? = some n') : n ≤ n' := by
  sorry

/-- **T1e.** A reopen strictly increases the sequence over the tombstone. -/
theorem T1_reopen_strict (p : Params) (env : Env) {t : Slot} {e : Epoch} {n : Seq} {f : Flow}
    {sn' : Seq} {refund : Addr} {pool0 : Value} {l' : Live}
    (h : Step p env (.reopen sn' refund pool0) t (.closed e n) f (.present l')) : n < l'.sn := by
  sorry

/-- Along any trace, the sequence recorded never decreases between states
that record one — through closes and reopens included. -/
theorem trace_sn_monotone_all (p : Params) (env : Env) {t : Slot} {s s' : State}
    {es : List (Slot × Action)} (h : Trace p env t s es s') :
    ∀ n n', s.sn? = some n → s'.sn? = some n' → n ≤ n' := by
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

/-- **T2b.** A close opens the next epoch and records it in the tombstone;
a reopen opens the one after the tombstone's. -/
theorem T2_close_and_reopen_open_epochs (p : Params) (env : Env) {t : Slot} :
    (∀ {l : Live} {f : Flow} {e : Epoch} {n : Seq} {sn' : Seq} {r' : Option Addr},
      Step p env (.close sn' r') t (.present l) f (.closed e n) → e = l.epoch + 1 ∧ n = sn') ∧
    (∀ {e : Epoch} {n : Seq} {f : Flow} {l' : Live} {sn' : Seq} {refund : Addr} {pool0 : Value},
      Step p env (.reopen sn' refund pool0) t (.closed e n) f (.present l') → l'.epoch = e + 1 ∧ l'.sn = sn') := by
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

/-- The poison bit along a trace from a present state is the fold of the
actions over the starting bit — through a close and a reopen included, the
reopen opening a clean epoch. -/
theorem trace_poison_fold (p : Params) (env : Env) {t : Slot} {s s' : State}
    {es : List (Slot × Action)} (h : Trace p env t s es s') :
    ∀ l0 l, s = .present l0 → s' = .present l → l.poisoned = poisonAfter l0.poisoned es := by
  sorry

/-- **T3d.** Along any trace from `absent`, the checkpoint is poisoned
exactly when the last epoch-relevant action was a poison. -/
theorem T3_epoch_local (p : Params) (env : Env) {t : Slot} {es : List (Slot × Action)} {l : Live}
    (h : Trace p env t .absent es (.present l)) :
    l.poisoned = poisonSinceLastRotation es := by
  sorry

/-! ## T4 — poisoned keys can only be rotated -/

/-- **T4a.** From a poisoned state the current quorum can do nothing, and no
proof can freeze it. (A close is a rotation by the next keys, D-036.) -/
theorem T4_poisoned_blocks_quorum_and_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l : Live} {f : Flow} {s' : State}
    (h : Step p env a t (.present l) f s') (hp : l.poisoned = true) :
    a.actor ≠ .currentQuorum ∧ (∀ sn' payee, a ≠ .freeze sn' payee) := by
  sorry

/-- **T4b.** From a poisoned state, nothing but the next keys yields a
consumable state. -/
theorem T4_poisoned_nonrotation_inert (p : Params) (env : Env) {a : Action} {t t' : Slot}
    {l : Live} {f : Flow} {s' : State}
    (h : Step p env a t (.present l) f s') (hp : l.poisoned = true) (hn : a.actor ≠ .nextKeys) :
    ¬ consumableState p t' s' := by
  sorry

/-- **T4c.** The current keys' only Cardano power is the poison: whatever
the current quorum signs, the step is a poison (D-036 dissolved the close). -/
theorem T4_current_quorum_only_poisons (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State}
    {f : Flow} (h : Step p env a t s f s') (hq : a.actor = .currentQuorum) : a = .poison := by
  sorry

/-! ## T5 — totality: every ruled transition is enabled when its evidence is -/

/-- **T5a.** Given a valid witnessed rotation and the new keys' signature on
the bond option and the optional new refund address — one message carrying
both (D-038) — every bond option is enabled at every address choice,
whatever the pool holds (payment is never a gate, T14). `keep` with no new
address needs no signature. -/
theorem T5_every_bond_option (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq)
    (payee : Addr) (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hd : l.dreg ≤ p.D) (hb : l.b ≤ p.B) :
    ∀ (op : BondOp) (r' : Option Addr), env.intentOk (l.epoch + 1) op.intent r' = true →
      ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' op payee r') t (.present l) f (.present l') := by
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

/-- **T5e.** Given a later witnessed rotation and the new keys' signature on
the close intent, the close is enabled from every present state — poisoned
or not (D-036). -/
theorem T5_close_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (r' : Option Addr)
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hauth : env.intentOk (l.epoch + 1) .close r' = true) :
    ∃ f, Step p env (.close sn' r') t (.present l) f (.closed (l.epoch + 1) sn') := by
  sorry

/-- **T5f.** Given a witnessed rotation later than the tombstone, the reopen
is enabled from every closed state (D-036). -/
theorem T5_reopen_enabled (p : Params) (env : Env) (t : Slot) (e : Epoch) (n : Seq) (sn' : Seq)
    (refund : Addr) (pool0 : Value) (hev : env.rotationTo e n sn' = true) (hsn : n < sn') :
    ∃ f l', Step p env (.reopen sn' refund pool0) t (.closed e n) f (.present l') := by
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

/-- **T6c.** The conviction bond re-enters a present state only by a
depositing rotation, and then to full. -/
theorem T6_dreg_increases_only_by_deposit (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hlt : l.dreg < l'.dreg) :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧ l'.dreg = p.D ∧ l'.b = p.B ∧
    f.dregIn = p.D - l.dreg ∧ f.bIn = p.B - l.b ∧ l'.bornAt = t := by
  sorry

/-- **T6d.** `refundTo` changes only under a rotation that names the new
address, and the message the new keys signed is that rotation's own option
with that address (D-032, D-038): no unrelated intent authorizes the move. -/
theorem T6_refund_change_requires_new_keys (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.refundTo ≠ l.refundTo) :
    ∃ sn' op payee, a = .rotate sn' op payee (some l'.refundTo) ∧
      env.intentAuthorized l'.epoch op.intent (some l'.refundTo) = true := by
  sorry

/-- **T6e.** Poison and top-up move no bond; only rotations and freezes do. -/
theorem T6_bonds_move_only_by_rotation_or_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.dreg ≠ l.dreg ∨ l'.b ≠ l.b) :
    a.actor = .nextKeys ∨ (∃ sn' payee, a = .freeze sn' payee) := by
  sorry

/-- **T6f.** Every intent other than the empty one is authorized by the keys
of the epoch the rotation opens (D-038): a withdrawal, a deposit, a close,
and a keep with a new address each carry the new keys' signature on that
intent and that address. A relayer with public data alone can land a keep
and nothing else. -/
theorem T6_intent_requires_new_keys (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State} :
    (∀ {sn' payee r'}, Step p env (.rotate sn' .withdraw payee r') t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) .withdraw r' = true) ∧
    (∀ {sn' payee r'}, Step p env (.rotate sn' .deposit payee r') t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) .deposit r' = true) ∧
    (∀ {sn' r'}, Step p env (.close sn' r') t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) .close r' = true) ∧
    (∀ {sn' payee r}, Step p env (.rotate sn' .keep payee (some r)) t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) .keep (some r) = true) := by
  sorry

/-- **T6g.** Without the new keys' signature nothing but a keep with the
address unchanged lands: if the keys of epoch `e + 1` authorized no intent
at all, every rotation from epoch `e` is a keep with `refund' = none`, and no
close happens. -/
theorem T6_relayer_cannot_park_age_or_close (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live}
    {f : Flow} {s' : State} (h : Step p env a t (.present l) f s')
    (hno : ∀ i r, env.intentAuthorized (l.epoch + 1) i r = false) (hact : a.actor = .nextKeys) :
    ∃ sn' payee, a = .rotate sn' .keep payee none := by
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

/-! ## T8 — one incarnation per AID: the registry leaf (D-036, D-037) -/

/-- **T8a.** In every reachable system every leaf agrees with its state:
the leaf is exactly the identity-level projection of the UTxO's state. -/
theorem T8_leaf_agrees_with_state (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    s.leaves aid = (s.states aid).leaf := by
  sorry

/-- **T8b.** The partition of D-037, stated as such: a step leaves every
leaf as it was exactly when its action is a rotate, a poison, a freeze or a
top-up (`Action.touchesLeaf = false`); a register, a reopen, a close and a
conviction change the leaf. -/
theorem T8_edges_leave_the_leaf (p : Params) (env : Env) {s : Sys} {aid : AID} {a : Action} {now : Slot}
    {f : Flow} {st' : State} (hs : SysReach p env s) (hstep : Step p env a now (s.states aid) f st') :
    (s.set aid st').leaves = s.leaves ↔ a.touchesLeaf = false := by
  sorry

/-- **T8c.** In every reachable system, an AID with a state other than
`absent` has a leaf: live, closed or convicted — the token was minted once
by a registration under an absence proof and the leaf never returns to
absent. -/
theorem T8_present_implies_registered (p : Params) (env : Env) {s : Sys} (h : SysReach p env s)
    (aid : AID) (hne : s.states aid ≠ .absent) : s.leaves aid ≠ .absent := by
  sorry

/-- **T8g.** A closed leaf records exactly the tombstone the state holds, and
a live leaf means the UTxO exists: closed-implies-registered, with its
content. -/
theorem T8_closed_leaf_is_the_tombstone (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (∀ e n, s.leaves aid = .closed e n → s.states aid = .closed e n) ∧
    (s.leaves aid = .live → ∃ l, s.states aid = .present l) ∧
    (s.leaves aid = .convicted → ∃ e n c, s.states aid = .convicted e n c) := by
  sorry

/-- **T8h.** The leaf never returns to absent, and a convicted leaf is
terminal: no system step changes it. -/
theorem T8_leaf_never_absent_again (p : Params) (env : Env) {s s' : Sys} (hs : SysReach p env s)
    (h : SysStep p env s s') (aid : AID) :
    (s.leaves aid ≠ .absent → s'.leaves aid ≠ .absent) ∧
    (s.leaves aid = .convicted → s'.leaves aid = .convicted) := by
  sorry

/-- **T8i.** Mint-once: a registration lands only on an absent leaf, a reopen
only on a closed one; a live or convicted AID is never registered or
reopened. -/
theorem T8_mint_once (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (∀ refund pool0 now f st', Step p env (.register refund pool0) now (s.states aid) f st' →
      s.leaves aid = .absent) ∧
    (∀ sn' refund pool0 now f st', Step p env (.reopen sn' refund pool0) now (s.states aid) f st' →
      ∃ e n, s.leaves aid = .closed e n) := by
  sorry

/-! ## T9 — juvenility is consumer policy -/

/-- **T9.0.** The consumer's program is the consumer's predicate: the
decidable mirror `consumableStateB` decides exactly `consumableState`, so
what the trace driver and the simulator run is what the theorems below
speak about. -/
theorem consumableStateB_iff (p : Params) (now : Slot) (s : State) :
    consumableStateB p now s = true ↔ consumableState p now s := by
  sorry

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

/-- **T10b.** Only a depositing rotation restores consumability from a
present state, and it restarts juvenility. -/
theorem T10_only_deposit_restores (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p env a t (.present l) f s')
    (hmissing : l.dreg ≠ p.D ∨ l.b ≠ p.B) (hc : consumableState p t' s') :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧
    ∃ l', s' = .present l' ∧ l'.dreg = p.D ∧ l'.b = p.B ∧ l'.bornAt = t := by
  sorry

/-- **T10c.** The current quorum never produces a consumable state: its only
move is the poison. -/
theorem T10_current_quorum_never_restores (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live}
    {f : Flow} {s' : State} (h : Step p env a t (.present l) f s') (hq : a.actor = .currentQuorum) :
    ¬ consumableState p t' s' := by
  sorry

/-- **T10d.** A reopen brings both bonds back to full and restarts
juvenility: the reopened checkpoint is unconsumable for `W` slots. -/
theorem T10_reopen_is_juvenile (p : Params) (env : Env) {t t' : Slot} {e : Epoch} {n : Seq} {f : Flow}
    {sn' : Seq} {refund : Addr} {pool0 : Value} {l' : Live}
    (h : Step p env (.reopen sn' refund pool0) t (.closed e n) f (.present l')) :
    l'.dreg = p.D ∧ l'.b = p.B ∧ l'.bornAt = t ∧ (t' < t + p.W → ¬ consumableState p t' (.present l')) := by
  sorry

/-! ## T12 — conviction needs a proof and is exact -/

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

/-- **T14a.** The pool decreases between present states only by the premium
under a paid rotation, or to zero under a withdrawing rotation. -/
theorem T14_pool_decreases_only_by_premium (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l'.pool < l.pool) :
    a.actor = .nextKeys ∧
    ((l'.pool + p.P = l.pool ∧ Payment?.pool f.hunter = p.P) ∨ (l'.pool = 0 ∧ f.refund ≠ none)) := by
  sorry

/-- **T14b.** The pool increases between present states only by a top-up. -/
theorem T14_pool_increases_only_by_topup (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l.pool < l'.pool) :
    ∃ x, a = .topUp x ∧ f = { poolIn := x } ∧ l' = { l with pool := l.pool + x } := by
  sorry

/-- **T15a.** The freeze bond leaves a present state for a present state
only by a freeze — proof of a later rotation, pool short, exactly `B` to the
hunter, datum otherwise untouched — or by a withdrawing rotation. -/
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

/-- **T16a.** A close is a witnessed rotation by the next keys, poisoned or
not: it pays everything to the refund address it results in — the one in
the datum, or the one the new keys authorized in the same message as the
close — records the epoch it opened and its sequence, and needs the
rotation and the signed intent (D-036, D-038). -/
theorem T16_close_destination (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow}
    {e : Epoch} {n : Seq} (h : Step p env a t (.present l) f (.closed e n)) :
    ∃ sn' r', a = .close sn' r' ∧
      f = { refund := some { addr := r'.getD l.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } } ∧
      e = l.epoch + 1 ∧ n = sn' ∧ l.sn < sn' ∧ env.rotationTo l.epoch l.sn sn' = true ∧
      env.intentOk (l.epoch + 1) .close r' = true := by
  sorry

/-- **T16d.** No close without the rotation: the current quorum cannot
close, and a close never lands on a state the presented rotation does not
advance. -/
theorem T16_close_needs_rotation (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}
    {sn' : Seq} {r' : Option Addr} (h : Step p env (.close sn' r') t (.present l) f s') :
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ (Action.close sn' r').actor = .nextKeys := by
  sorry

/-- **T16b.** A withdrawing rotation pays everything to the refund address
it results in — the one in the datum, or the one the new keys authorized. -/
theorem T16_withdraw_destination (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {payee : Addr} {r' : Option Addr}
    (h : Step p env (.rotate sn' .withdraw payee r') t (.present l) f (.present l')) :
    f = { refund := some { addr := l'.refundTo, dreg := l.dreg, b := l.b, pool := l.pool } } ∧
    l'.refundTo = r'.getD l.refundTo := by
  sorry

/-- **T16c.** No step pays a hunter anything but the premium or the freeze
bond, and no step pays a convictor anything but the conviction bond. -/
theorem T16_payments_are_named (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    (∀ q, f.hunter = some q → (q.dreg = 0 ∧ q.b = 0 ∧ q.pool = p.P) ∨ (q.dreg = 0 ∧ q.b = p.B ∧ q.pool = 0)) ∧
    (∀ q, f.convictor = some q → q.b = 0 ∧ q.pool = 0 ∧ q.dreg = s.dregHeld) := by
  sorry

end CardanoKeri.Checkpoint
