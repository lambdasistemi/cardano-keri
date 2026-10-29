import CardanoKeri

/-! Exact expected types for the retained-output revision. Unused proof binder
names have an underscore prefix; premises and conclusions are unchanged. -/
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.trace_from_convicted : ∀ (p : Params) (env : Env) {t : Slot} {es : List (Slot × Action)} {s' : State} (_h : Trace p env t .convicted es s'), s' = .convicted)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_absent_only_registers : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State} (_h : Step p env a t .absent f s'), ∃ refund pool0, a = .register refund pool0)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T1_sn_monotone : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')), l.sn ≤ l'.sn)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T1_rotate_strict : ∀ (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow} {sn' : Seq} {op : BondOp} {payee : Addr} {r' : Option Addr} (_h : Step p env (.rotate sn' op payee r') t (.present l) f (.present l')), l.sn < l'.sn)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T1_sn_monotone_all : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s') (n n' : Seq) (_hn : s.sn? = some n) (_hn' : s'.sn? = some n'), n ≤ n')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T1_reopen_strict : ∀ (p : Params) (env : Env) {t : Slot} {h : Hash} {f : Flow} {sn' : Seq} {refund : Addr} {pool0 : Value} {l' : Live} (_hs : Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l')), h.sn < l'.sn)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T1_close_rotation_cannot_revive : ∀ (p : Params) (env : Env) {t t' : Slot} {l : Live} {f f' : Flow} {sn' : Seq} {payee : Addr} {r' : Option Addr} {h : Hash} {refund : Addr} {pool0 : Value} {s' : State} (_hc : Step p env (.close sn' payee r') t (.present l) f (.parked h)), ¬ Step p env (.reopen sn' refund pool0) t' (.parked h) f' s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.trace_sn_monotone_all : ∀ (p : Params) (env : Env) {t : Slot} {s s' : State} {es : List (Slot × Action)} (_h : Trace p env t s es s'), ∀ n n', s.sn? = some n → s'.sn? = some n' → n ≤ n')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T1_trace_sn_monotone : ∀ (p : Params) (env : Env) {t : Slot} {l l' : Live} {es : List (Slot × Action)} (_h : Trace p env t (.present l) es (.present l')), l.sn ≤ l'.sn)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T2_epoch_only_by_rotation : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hne : l'.epoch ≠ l.epoch), a.actor = .nextKeys ∧ l'.epoch = l.epoch + 1)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T2_close_and_reopen_open_epochs : ∀ (p : Params) (env : Env) {t : Slot}, (∀ {l : Live} {f : Flow} {h : Hash} {sn' : Seq} {payee : Addr} {r' : Option Addr}, Step p env (.close sn' payee r') t (.present l) f (.parked h) → h.epoch = l.epoch + 1 ∧ h.sn = sn') ∧ (∀ {h : Hash} {f : Flow} {l' : Live} {sn' : Seq} {refund : Addr} {pool0 : Value}, Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l') → l'.epoch = h.epoch + 1 ∧ l'.sn = sn'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T3_rotation_clears : ∀ (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow} {sn' : Seq} {op : BondOp} {payee : Addr} {r' : Option Addr} (_h : Step p env (.rotate sn' op payee r') t (.present l) f (.present l')), l'.poisoned = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T3_only_rotation_clears : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hp : l.poisoned = true) (_hc : l'.poisoned = false), a.actor = .nextKeys)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T3_only_poison_sets : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hset : l.poisoned = false) (_hset' : l'.poisoned = true), a = .poison ∧ l' = { l with poisoned := true } ∧ f = {})
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.trace_poison_fold : ∀ (p : Params) (env : Env) {t : Slot} {s s' : State} {es : List (Slot × Action)} (_h : Trace p env t s es s'), ∀ l0 l, s = .present l0 → s' = .present l → l.poisoned = poisonAfter l0.poisoned es)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T3_epoch_local : ∀ (p : Params) (env : Env) {t : Slot} {es : List (Slot × Action)} {l : Live} (_h : Trace p env t .absent es (.present l)), l.poisoned = poisonSinceLastRotation es)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T4_poisoned_blocks_quorum_and_freeze : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} {s' : State} (_h : Step p env a t (.present l) f s') (_hp : l.poisoned = true), a.actor ≠ .currentQuorum ∧ (∀ sn' payee, a ≠ .freeze sn' payee))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T4_poisoned_nonrotation_inert : ∀ (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow} {s' : State} (_h : Step p env a t (.present l) f s') (_hp : l.poisoned = true) (_hn : a.actor ≠ .nextKeys), ¬ consumableState p t' s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T4_current_quorum_only_poisons : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s') (_hq : a.actor = .currentQuorum), a = .poison)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T4_current_key_thief_cannot_park : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} {s' : State} (_hthief : ∀ sn', env.rotationTo l.epoch l.sn sn' = false) (_h : Step p env a t (.present l) f s'), a.actor ≠ .nextKeys ∧ (∀ sn' payee, a ≠ .freeze sn' payee) ∧ (∀ h', s' ≠ .parked h'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_every_bond_option : ∀ (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr) (_hev : env.rotationTo l.epoch l.sn sn' = true) (_hsn : l.sn < sn'), ∀ (op : BondOp) (r' : Option Addr), env.intentOk (l.epoch + 1) op.intent r' = true → ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' op payee r') t (.present l) f (.present l'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_keep_is_rotated : ∀ (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State} {sn' : Seq} {payee : Addr} {r' : Option Addr} (_hk : Step p env (.rotate sn' .keep payee r') t (.present l) f s'), f = { hunter := p.premium l payee } ∧ s' = .present (l.rotated p sn' r'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_deposit_on_full_is_keep : ∀ (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State} {sn' : Seq} {payee : Addr} {r' : Option Addr} (_hfull : l.frozen = false) (_hd : Step p env (.rotate sn' .deposit payee r') t (.present l) f s'), f = { hunter := p.premium l payee } ∧ f.bIn = 0 ∧ f.dregIn = 0 ∧ f.poolIn = 0 ∧ s' = .present (l.rotated p sn' r') ∧ ∃ l', s' = .present l' ∧ l'.bornAt = l.bornAt ∧ l'.frozen = false ∧ l'.sn = sn' ∧ l'.epoch = l.epoch + 1 ∧ l'.poisoned = false ∧ l'.refundTo = r'.getD l.refundTo ∧ ((p.P ≤ l.pool ∧ f.hunter = some { addr := payee, pool := p.P } ∧ l'.pool + p.P = l.pool) ∨ (l.pool < p.P ∧ f.hunter = none ∧ l'.pool = l.pool)))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_poison_enabled : ∀ (p : Params) (env : Env) (t : Slot) (l : Live) (_hq : env.quorum l.epoch = true) (_hclean : l.poisoned = false), ∃ l', Step p env .poison t (.present l) {} (.present l'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_freeze_enabled : ∀ (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr) (_hev : env.rotationTo l.epoch l.sn sn' = true) (_hsn : l.sn < sn') (_hpool : l.pool < p.P) (_hb : l.frozen = false) (_hclean : l.poisoned = false), ∃ (f : Flow) (l' : Live), Step p env (.freeze sn' payee) t (.present l) f (.present l'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_close_enabled : ∀ (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr) (r' : Option Addr) (_hev : env.rotationTo l.epoch l.sn sn' = true) (_hsn : l.sn < sn') (_hauth : env.intentOk (l.epoch + 1) (.close payee) r' = true), ∃ f, Step p env (.close sn' payee r') t (.present l) f (.parked ⟨l.epoch + 1, sn'⟩))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_reopen_enabled : ∀ (p : Params) (env : Env) (t : Slot) (h : Hash) (sn' : Seq) (refund : Addr) (pool0 : Value) (_hev : env.rotationTo h.epoch h.sn sn' = true) (_hsn : h.sn < sn'), ∃ f l', Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T5_keep_needs_no_intent : ∀ (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr) (_hev : env.rotationTo l.epoch l.sn sn' = true) (_hsn : l.sn < sn'), ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' .keep payee none) t (.present l) f (.present l'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_dreg_never_moves_between_present_states : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')), f.dregIn = 0 ∧ Payment?.dreg f.refund = 0 ∧ Payment?.dreg f.hunter = 0 ∧ Payment?.dreg f.convictor = 0)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_dreg_enters_only_at_birth : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s') (_hin : f.dregIn ≠ 0), ((∃ refund pool0, a = .register refund pool0 ∧ s = .absent) ∨ (∃ sn' refund pool0 hs, a = .reopen sn' refund pool0 ∧ s = .parked hs)) ∧ f.dregIn = p.D ∧ f.bIn = p.B ∧ ∃ l', s' = .present l' ∧ l'.frozen = false ∧ l'.bornAt = t)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_refund_change_requires_new_keys : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hne : l'.refundTo ≠ l.refundTo), ∃ sn' op payee, a = .rotate sn' op payee (some l'.refundTo) ∧ env.intentAuthorized l'.epoch op.intent (some l'.refundTo) = true)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_frozen_flips_only_by_rotation_or_freeze : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hne : l'.frozen ≠ l.frozen), a.actor = .nextKeys ∨ (∃ sn' payee, a = .freeze sn' payee))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_intent_requires_new_keys : ∀ (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}, (∀ {sn' payee r'}, Step p env (.rotate sn' .deposit payee r') t (.present l) f s' → env.intentAuthorized (l.epoch + 1) .deposit r' = true) ∧ (∀ {sn' payee r'}, Step p env (.close sn' payee r') t (.present l) f s' → env.intentAuthorized (l.epoch + 1) (.close payee) r' = true) ∧ (∀ {sn' payee r}, Step p env (.rotate sn' .keep payee (some r)) t (.present l) f s' → env.intentAuthorized (l.epoch + 1) .keep (some r) = true))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T6_relayer_cannot_park_age_or_close : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} {s' : State} (_h : Step p env a t (.present l) f s') (_hno : ∀ i r, env.intentAuthorized (l.epoch + 1) i r = false) (_hact : a.actor = .nextKeys), ∃ sn' payee, a = .rotate sn' .keep payee none)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_leaf_agrees_with_state : ∀ (p : Params) (env : Env) {s : Sys} (_h : SysReach p env s) (aid : AID), s.leaves aid = (s.states aid).leaf)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_present_implies_registered : ∀ (p : Params) (env : Env) {s : Sys} (_h : SysReach p env s) (aid : AID) (_hne : s.states aid ≠ .absent), s.leaves aid ≠ .absent)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T8_reopen_actor_is_proof : ∀ (sn' : Seq) (refund : Addr) (pool0 : Value), (Action.reopen sn' refund pool0).actor = .proof ∧ (Action.freeze sn' refund).actor = .proof ∧ (Action.convict refund).actor = .proof)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T9_juvenility_is_consumer_only : ∀ (p : Params) (env : Env) (W' : Nat) {a : Action} {t : Slot} {s s' : State} {f : Flow}, Step p env a t s f s' ↔ Step { p with W := W' } env a t s f s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T10_inert_without_next_keys : ∀ (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow} {s' : State} (_h : Step p env a t (.present l) f s') (_hfrozen : l.frozen = true) (_hnot : a.actor ≠ .nextKeys), ¬ consumableState p t' s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T10_only_deposit_restores : ∀ (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow} {s' : State} (_h : Step p env a t (.present l) f s') (_hfrozen : l.frozen = true) (_hc : consumableState p t' s'), (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧ ∃ l', s' = .present l' ∧ l'.frozen = false ∧ l'.bornAt = l.bornAt ∧ f.bIn = p.B)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T10_current_quorum_never_restores : ∀ (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow} {s' : State} (_h : Step p env a t (.present l) f s') (_hq : a.actor = .currentQuorum), ¬ consumableState p t' s')
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T10_reopen_is_juvenile : ∀ (p : Params) (env : Env) {t t' : Slot} {h : Hash} {f : Flow} {sn' : Seq} {refund : Addr} {pool0 : Value} {l' : Live} (_hs : Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l')), f.dregIn = p.D ∧ f.bIn = p.B ∧ l'.frozen = false ∧ l'.bornAt = t ∧ (t' < t + p.W → ¬ consumableState p t' (.present l')))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T10_bonds_are_observable : ∀ (p : Params) (l : Live) (h : Hash), (State.present l).dregHeld p ≠ (State.parked h).dregHeld p ∧ (State.present l).dregHeld p ≠ State.convicted.dregHeld p ∧ (l.frozen = true → (State.present l).bHeld p ≠ p.B))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T14_pool_decreases_only_by_premium : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hlt : l'.pool < l.pool), a.actor = .nextKeys ∧ l'.pool + p.P = l.pool ∧ Payment?.pool f.hunter = p.P)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T14_pool_increases_only_by_topup : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hlt : l.pool < l'.pool), ∃ x, a = .topUp x ∧ f = { poolIn := x } ∧ l' = { l with pool := l.pool + x })
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T15_b_leaves_only_by_freeze : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hheld : l.frozen = false) (_hgone : l'.frozen = true), ∃ sn' payee, a = .freeze sn' payee ∧ env.rotationTo l.epoch l.sn sn' = true ∧ l.pool < p.P ∧ l' = { l with frozen := true } ∧ f = { hunter := some { addr := payee, b := p.B } })
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T15_b_returns_only_by_deposit : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow} (_h : Step p env a t (.present l) f (.present l')) (_hgone : l.frozen = true) (_hback : l'.frozen = false), (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧ f.bIn = p.B)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T15_freeze_makes_inert : ∀ (p : Params) (env : Env) {t t' : Slot} {l l' : Live} {f : Flow} {sn' : Seq} {payee : Addr} (_h : Step p env (.freeze sn' payee) t (.present l) f (.present l')), ¬ consumableState p t' (.present l'))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.T16_payments_are_named : ∀ (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} (_h : Step p env a t s f s'), (∀ q, f.hunter = some q → (q.dreg = 0 ∧ q.b = 0 ∧ q.pool = p.P) ∨ (q.dreg = 0 ∧ q.b = p.B ∧ q.pool = 0)) ∧ (∀ q, f.convictor = some q → q.b = 0 ∧ q.pool = 0 ∧ q.dreg = s.dregHeld p))
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.register_iff : ∀ {p : Params} {env : Env} (now : Slot) (refund : Addr) (pool0 : Value), Step p env (.register refund pool0) now .absent { dregIn := p.D, bIn := p.B, poolIn := pool0 } (.present ⟨0, 0, false, false, now, refund, pool0⟩) ↔ True)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.rotateKeepPaid_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr), Step p env (.rotate sn' .keep payee refund') now (.present l) { hunter := some { addr := payee, pool := p.P } } (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, refundTo := refund'.getD l.refundTo, pool := l.pool - p.P }) ↔ env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ env.intentOk (l.epoch + 1) .keep refund' = true ∧ p.P ≤ l.pool)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.rotateKeepUnpaid_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr), Step p env (.rotate sn' .keep payee refund') now (.present l) {} (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, refundTo := refund'.getD l.refundTo }) ↔ env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ env.intentOk (l.epoch + 1) .keep refund' = true ∧ l.pool < p.P)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.rotateDepositPaid_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr), Step p env (.rotate sn' .deposit payee refund') now (.present l) { bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } } (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false, refundTo := refund'.getD l.refundTo, pool := l.pool - p.P }) ↔ env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ env.intentOk (l.epoch + 1) .deposit refund' = true ∧ p.P ≤ l.pool)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.rotateDepositUnpaid_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq) (payee : Addr) (refund' : Option Addr), Step p env (.rotate sn' .deposit payee refund') now (.present l) { bIn := p.B - l.bHeld p } (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false, frozen := false, refundTo := refund'.getD l.refundTo }) ↔ env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ env.intentOk (l.epoch + 1) .deposit refund' = true ∧ l.pool < p.P)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.poison_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot), Step p env .poison now (.present l) {} (.present { l with poisoned := true }) ↔ env.quorum l.epoch = true ∧ l.poisoned = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.freeze_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq) (payee : Addr), Step p env (.freeze sn' payee) now (.present l) { hunter := some { addr := payee, b := p.B } } (.present { l with frozen := true }) ↔ env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ l.pool < p.P ∧ l.frozen = false ∧ l.poisoned = false)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Checkpoint
#check (@CardanoKeri.Checkpoint.Step.topUp_iff : ∀ {p : Params} {env : Env} (l : Live) (now : Slot) (x : Value), Step p env (.topUp x) now (.present l) { poolIn := x } (.present { l with pool := l.pool + x }) ↔ True)
end CardanoKeri.Checkpoint
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_some_mem : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {r : α} (_h : lookup rs id = some r), (id, r) ∈ rs)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_none_of_not_mem : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} (_h : ∀ x, x ∈ rs → x.1 ≠ id), lookup rs id = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.not_mem_of_lookup_none : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} (_h : lookup rs id = none), ∀ x, x ∈ rs → x.1 ≠ id)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.key_not_mem_of_lookup_none : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} (_h : lookup rs id = none), id ∉ rs.map (·.1))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_some_of_mem : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {r : α} (_hn : (rs.map (·.1)).Nodup) (_h : (id, r) ∈ rs), lookup rs id = some r)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_cons_self : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {r : α}, lookup ((id, r) :: rs) id = some r)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_cons_ne : ∀ {α : Type} {rs : List (Nat × α)} {id i : Nat} {r : α} (_h : i ≠ id), lookup ((i, r) :: rs) id = lookup rs id)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.mem_remove : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {x : Nat × α} (_h : x ∈ remove rs id), x ∈ rs)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.fst_ne_of_mem_remove : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {x : Nat × α} (_h : x ∈ remove rs id), x.1 ≠ id)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.mem_remove_of_mem : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {x : Nat × α} (_h : x ∈ rs) (_hne : x.1 ≠ id), x ∈ remove rs id)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.nodup_map_remove : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} (_h : (rs.map (·.1)).Nodup), ((remove rs id).map (·.1)).Nodup)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_remove_self : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat}, lookup (remove rs id) id = none)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.lookup_remove_ne : ∀ {α : Type} {rs : List (Nat × α)} {id id' : Nat} (_h : id ≠ id'), lookup (remove rs id') id = lookup rs id)
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.key_not_mem_map_fst_remove_self : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat}, id ∉ (remove rs id).map (·.1))
end CardanoKeri.Registry
namespace CardanoKeri.Registry
#check (@CardanoKeri.Registry.eq_of_mem_of_fst_eq : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} {r : α} {x : Nat × α} (_hn : (rs.map (·.1)).Nodup) (_hl : lookup rs id = some r) (_hx : x ∈ rs) (_hid : x.1 = id), x = (id, r))
end CardanoKeri.Registry
namespace CardanoKeri.Registry.Agreement
#check (@CardanoKeri.Registry.Agreement.remove_absent : ∀ {α : Type} {rs : List (Nat × α)} {id : Nat} (_h : id ∉ rs.map (·.1)), remove rs id = rs)
end CardanoKeri.Registry.Agreement
namespace CardanoKeri.Samaritan
#check (@CardanoKeri.Samaritan.reap_conserves : ∀ (r : Reap), (reap r).intoRequest + (reap r).premium = r.Mc)
end CardanoKeri.Samaritan
