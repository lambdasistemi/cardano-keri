import CardanoKeri.Checkpoint

/-!
# The M1 return: theorems T1 … T16, third slice (D-039, D-040)

Statements audited independently (two rounds, 2026-09-03/04: the close names its
payee, and the two keep-shaped statements are stated from their own
hypothesis), then proved. Every theorem of the second slice stays, restated where D-040
changed the state or the flow; three are retired with their content carried
by a named successor (`T6_dreg_increases_only_by_deposit` →
`T6_dreg_enters_only_at_birth`, `T10_withdraw_is_observable` →
`T10_bonds_are_observable`, `T16_withdraw_destination` → `T16_close_destination`
and `T16_parked_hash_is_the_closed_checkpoints`); the additions keep the
number of the property they strengthen. Numbering follows the plan's Phase 0
list; T11 and T13 do not exist.

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
theorem T12_convicted_terminal (p : Params) (env : Env) {a : Action} {t : Slot}
    {f : Flow} {s' : State} (h : Step p env a t .convicted f s') : False := by
  cases h

/-- A trace from `convicted` goes nowhere. -/
theorem trace_from_convicted (p : Params) (env : Env) {t : Slot}
    {es : List (Slot × Action)} {s' : State}
    (h : Trace p env t .convicted es s') : s' = .convicted := by
  cases h with
  | nil => rfl
  | cons _ hs _ => exact (T12_convicted_terminal p env hs).elim

/-- **T8d.** Registration is the only step from `absent`. -/
theorem T8_absent_only_registers (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State}
    (h : Step p env a t .absent f s') : ∃ refund pool0, a = .register refund pool0 := by
  cases h with
  | register => exact ⟨_, _, rfl⟩

/-- **T8e.** From `parked` there are exactly two steps (D-040, D-030): the
revival — a witnessed rotation strictly later than the parked key state,
fresh bonds, a first pool, born now, at the next epoch — and a conviction by
a proof against the parked key state, which moves nothing. -/
theorem T8_parked_only_revives_or_convicts (p : Params) (env : Env) {a : Action} {t : Slot} {h : Hash}
    {f : Flow} {s' : State} (hs : Step p env a t (.parked h) f s') :
    (∃ sn' refund pool0, a = .reopen sn' refund pool0 ∧ h.sn < sn' ∧ env.rotationTo h.epoch h.sn sn' = true ∧
      f = { dregIn := p.D, bIn := p.B, poolIn := pool0 } ∧
      s' = .present ⟨sn', h.epoch + 1, false, false, t, refund, pool0⟩) ∨
    (∃ payee, a = .convict payee ∧ env.duplicityAt h.epoch h.sn = true ∧ f = {} ∧ s' = .convicted) := by
  cases hs with
  | reopen => exact Or.inl ⟨_, _, _, rfl, ‹_›, ‹_›, rfl, rfl⟩
  | convictParked => exact Or.inr ⟨_, rfl, ‹_›, rfl, rfl⟩

/-- **T8l.** The only way back from `parked` is the revival: whatever step
reaches a present state from a parked one is a reopen (D-040: "the only way
back is a witnessed rotation from exactly that key state"). -/
theorem T8_parked_returns_only_by_revival (p : Params) (env : Env) {a : Action} {t : Slot} {h : Hash}
    {f : Flow} {l' : Live} (hs : Step p env a t (.parked h) f (.present l')) :
    ∃ sn' refund pool0, a = .reopen sn' refund pool0 ∧ env.rotationTo h.epoch h.sn sn' = true ∧ h.sn < sn' := by
  cases hs with
  | reopen => exact ⟨_, _, _, rfl, ‹_›, ‹_›⟩

/-- **T8f.** Conviction is the only terminal state: from every other state
some step is enabled under suitable evidence — registration from `absent`,
a top-up from `present`, a revival from `parked`. -/
theorem T8_only_convicted_is_terminal (p : Params) (env : Env) (t : Slot) (s : State)
    (hnot : s ≠ .convicted)
    (hrevive : ∀ h, s = .parked h → env.rotationTo h.epoch h.sn (h.sn + 1) = true) :
    ∃ a f s', Step p env a t s f s' := by
  cases s with
  | absent => exact ⟨.register 0 0, _, _, Step.register t 0 0⟩
  | present l => exact ⟨.topUp 0, _, _, Step.topUp t 0⟩
  | convicted => exact absurd rfl hnot
  | parked h => exact ⟨.reopen (h.sn + 1) 0 0, _, _, Step.reopen t (h.sn + 1) 0 0 (hrevive h rfl) (Nat.lt_succ_self h.sn)⟩

/-! ## T1 — the checkpoint cannot roll back -/

/-- **T1a.** No step between present states decreases the sequence. -/
theorem T1_sn_monotone (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) : l.sn ≤ l'.sn := by
  cases h <;> first | exact Nat.le_of_lt ‹l.sn < _› | exact Nat.le_refl _

/-- **T1b.** Every rotation strictly increases the sequence. -/
theorem T1_rotate_strict (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {op : BondOp} {payee : Addr} {r' : Option Addr}
    (h : Step p env (.rotate sn' op payee r') t (.present l) f (.present l')) : l.sn < l'.sn := by
  cases h <;> exact ‹l.sn < _›

/-- **T1d.** No step decreases the sequence a state records, across every
state that records one: a close parks the closing rotation's sequence, a
revival is strictly later than the parked one (no stale resurrection,
D-036, D-040). A conviction records no sequence. -/
theorem T1_sn_monotone_all (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') (n n' : Seq) (hn : s.sn? = some n) (hn' : s'.sn? = some n') : n ≤ n' := by
  cases h <;> simp_all [State.sn?] <;> omega'

/-- **T1e.** A revival strictly increases the sequence over the parked key
state. -/
theorem T1_reopen_strict (p : Params) (env : Env) {t : Slot} {h : Hash} {f : Flow}
    {sn' : Seq} {refund : Addr} {pool0 : Value} {l' : Live}
    (hs : Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l')) : h.sn < l'.sn := by
  cases hs with
  | reopen => assumption

/-- **T1f.** No stale resurrection across park and revival: the rotation a
close presented parks its own sequence, so presenting that same rotation
again cannot revive — a revival needs a rotation later than the close's. A
relayer replaying the public close cannot bring the identity back. -/
theorem T1_close_rotation_cannot_revive (p : Params) (env : Env) {t t' : Slot} {l : Live} {f f' : Flow}
    {sn' : Seq} {payee : Addr} {r' : Option Addr} {h : Hash} {refund : Addr} {pool0 : Value} {s' : State}
    (hc : Step p env (.close sn' payee r') t (.present l) f (.parked h)) :
    ¬ Step p env (.reopen sn' refund pool0) t' (.parked h) f' s' := by
  intro hr
  cases hc <;> cases hr with
  | reopen =>
    rename_i hev' hsn'
    simp at hsn'

/-- Along any trace, the sequence recorded never decreases between states
that record one — through closes and revivals included. -/
theorem trace_sn_monotone_all (p : Params) (env : Env) {t : Slot} {s s' : State}
    {es : List (Slot × Action)} (h : Trace p env t s es s') :
    ∀ n n', s.sn? = some n → s'.sn? = some n' → n ≤ n' := by
  induction h with
  | nil t s => intro n n' h1 h2; rw [h1] at h2; cases h2; exact Nat.le_refl _
  | @cons t₁ t₂ s₁ s₂ s₃ a f rest hle hs htail ih =>
    intro n n' h1 h2
    cases hm : s₂.sn? with
    | some m => exact Nat.le_trans (T1_sn_monotone_all p env hs n m h1 hm) (ih m n' hm h2)
    | none =>
      have hconv : s₂ = .convicted := by cases hs <;> simp_all [State.sn?]
      subst hconv
      have := trace_from_convicted p env htail
      subst this
      simp [State.sn?] at h2

/-- **T1c.** Along any trace between present states the sequence never
decreases. -/
theorem T1_trace_sn_monotone (p : Params) (env : Env) {t : Slot} {l l' : Live}
    {es : List (Slot × Action)} (h : Trace p env t (.present l) es (.present l')) : l.sn ≤ l'.sn := by
  exact trace_sn_monotone_all p env h l.sn l'.sn rfl rfl

/-! ## T2 — keys change only by rotation -/

/-- **T2.** The epoch changes only under a rotation, and then by one. -/
theorem T2_epoch_only_by_rotation (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.epoch ≠ l.epoch) :
    a.actor = .nextKeys ∧ l'.epoch = l.epoch + 1 := by
  cases h <;> simp_all [Action.actor]

/-- **T2b.** A close opens the next epoch and parks it with the closing
sequence; a revival opens the one after the parked epoch at the revival's
sequence. -/
theorem T2_close_and_reopen_open_epochs (p : Params) (env : Env) {t : Slot} :
    (∀ {l : Live} {f : Flow} {h : Hash} {sn' : Seq} {payee : Addr} {r' : Option Addr},
      Step p env (.close sn' payee r') t (.present l) f (.parked h) → h.epoch = l.epoch + 1 ∧ h.sn = sn') ∧
    (∀ {h : Hash} {f : Flow} {l' : Live} {sn' : Seq} {refund : Addr} {pool0 : Value},
      Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l') → l'.epoch = h.epoch + 1 ∧ l'.sn = sn') := by
  constructor
  · intro l f h sn' payee r' hs
    cases hs with
    | closePaid => exact ⟨rfl, rfl⟩
    | closeUnpaid => exact ⟨rfl, rfl⟩
  · intro h f l' sn' refund pool0 hs
    cases hs with
    | reopen => exact ⟨rfl, rfl⟩

/-! ## T3 — poison is epoch-local -/

/-- **T3a.** A rotation always yields an unpoisoned state. -/
theorem T3_rotation_clears (p : Params) (env : Env) {t : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {op : BondOp} {payee : Addr} {r' : Option Addr}
    (h : Step p env (.rotate sn' op payee r') t (.present l) f (.present l')) : l'.poisoned = false := by
  cases h <;> rfl

/-- **T3b.** Only a rotation clears the poison. -/
theorem T3_only_rotation_clears (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l'))
    (hp : l.poisoned = true) (hc : l'.poisoned = false) : a.actor = .nextKeys := by
  cases h <;> simp_all [Action.actor]

/-- **T3c.** Only the poison sets it, from a clean state, and it changes
nothing else. -/
theorem T3_only_poison_sets (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l'))
    (hset : l.poisoned = false) (hset' : l'.poisoned = true) :
    a = .poison ∧ l' = { l with poisoned := true } ∧ f = {} := by
  cases h <;> simp_all

/-- The poison bit along a trace from a present state is the fold of the
actions over the starting bit — through a close and a revival included, the
revival opening a clean epoch. -/
theorem trace_poison_fold (p : Params) (env : Env) {t : Slot} {s s' : State}
    {es : List (Slot × Action)} (h : Trace p env t s es s') :
    ∀ l0 l, s = .present l0 → s' = .present l → l.poisoned = poisonAfter l0.poisoned es := by
  have gen : ∀ b : Bool, (∀ l0, s = .present l0 → b = l0.poisoned) →
      ∀ l, s' = .present l → l.poisoned = poisonAfter b es := by
    induction h with
    | nil t s => intro b hb l h2; subst h2; exact (hb l rfl).symm
    | cons hle hs htail ih =>
      intro b hb l h2
      cases hs with
      | register => exact ih false (fun l0 h0 => by cases h0; rfl) l h2
      | rotateKeepPaid => exact ih false (fun l0 h0 => by cases h0; rfl) l h2
      | rotateKeepUnpaid => exact ih false (fun l0 h0 => by cases h0; rfl) l h2
      | rotateDepositPaid => exact ih false (fun l0 h0 => by cases h0; rfl) l h2
      | rotateDepositUnpaid => exact ih false (fun l0 h0 => by cases h0; rfl) l h2
      | poison => exact ih true (fun l0 h0 => by cases h0; rfl) l h2
      | freeze => exact ih b (fun l0 h0 => by cases h0; exact (hb _ rfl).trans rfl) l h2
      | topUp => exact ih b (fun l0 h0 => by cases h0; exact (hb _ rfl).trans rfl) l h2
      | convict =>
        have := trace_from_convicted p env htail
        subst this
        cases h2
      | convictParked =>
        have := trace_from_convicted p env htail
        subst this
        cases h2
      | closePaid => exact ih b (fun l0 h0 => by cases h0) l h2
      | closeUnpaid => exact ih b (fun l0 h0 => by cases h0) l h2
      | reopen => exact ih false (fun l0 h0 => by cases h0; rfl) l h2
  intro l0 l h1 h2
  exact gen l0.poisoned (fun l0' h' => by subst h1; cases h'; rfl) l h2

/-- **T3d.** Along any trace from `absent`, the checkpoint is poisoned
exactly when the last epoch-relevant action was a poison. -/
theorem T3_epoch_local (p : Params) (env : Env) {t : Slot} {es : List (Slot × Action)} {l : Live}
    (h : Trace p env t .absent es (.present l)) :
    l.poisoned = poisonSinceLastRotation es := by
  cases h with
  | cons hle hs htail =>
    cases hs with
    | register =>
      have := trace_poison_fold p env htail _ l rfl rfl
      simpa [poisonSinceLastRotation, poisonAfter] using this

/-! ## T4 — poisoned keys can only be rotated; a thief of the current keys can neither park nor revive -/

/-- **T4a.** From a poisoned state the current quorum can do nothing, and no
proof can freeze it. (A close is a rotation by the next keys, D-036.) -/
theorem T4_poisoned_blocks_quorum_and_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l : Live} {f : Flow} {s' : State}
    (h : Step p env a t (.present l) f s') (hp : l.poisoned = true) :
    a.actor ≠ .currentQuorum ∧ (∀ sn' payee, a ≠ .freeze sn' payee) := by
  cases h <;> simp_all [Action.actor]

/-- **T4b.** From a poisoned state, nothing but the next keys yields a
consumable state. -/
theorem T4_poisoned_nonrotation_inert (p : Params) (env : Env) {a : Action} {t t' : Slot}
    {l : Live} {f : Flow} {s' : State}
    (h : Step p env a t (.present l) f s') (hp : l.poisoned = true) (hn : a.actor ≠ .nextKeys) :
    ¬ consumableState p t' s' := by
  cases h <;> simp_all [Action.actor, consumableState]

/-- **T4c.** The current keys' only Cardano power is the poison: whatever
the current quorum signs, the step is a poison (D-036 dissolved the close). -/
theorem T4_current_quorum_only_poisons (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State}
    {f : Flow} (h : Step p env a t s f s') (hq : a.actor = .currentQuorum) : a = .poison := by
  cases h <;> simp_all [Action.actor]

/-- **T4d.** A thief of the current keys cannot park (D-036, D-040): when
the next keys of the checkpoint's key state never signed a rotation, no
step from that checkpoint is by the next keys, none freezes it, and none
parks it — whatever the current keys sign. What is left is the poison, a
top-up and a conviction. -/
theorem T4_current_key_thief_cannot_park (p : Params) (env : Env) {a : Action} {t : Slot}
    {l : Live} {f : Flow} {s' : State}
    (hthief : ∀ sn', env.rotationTo l.epoch l.sn sn' = false)
    (h : Step p env a t (.present l) f s') :
    a.actor ≠ .nextKeys ∧ (∀ sn' payee, a ≠ .freeze sn' payee) ∧ (∀ h', s' ≠ .parked h') := by
  cases h <;> simp_all [Action.actor]

/-- **T4e.** A thief of the current keys cannot revive (D-040): when the
next keys of the parked key state never signed a rotation, the only step
from `parked` is a conviction — the identity stays parked whatever the
current keys sign, and never reaches a present state. -/
theorem T4_current_key_thief_cannot_revive (p : Params) (env : Env) {a : Action} {t : Slot}
    {h : Hash} {f : Flow} {s' : State}
    (hthief : ∀ sn', env.rotationTo h.epoch h.sn sn' = false)
    (hs : Step p env a t (.parked h) f s') :
    (∃ payee, a = .convict payee) ∧ s' = .convicted ∧ ∀ l', s' ≠ .present l' := by
  cases hs with
  | reopen => simp_all
  | convictParked => exact ⟨⟨_, rfl⟩, rfl, fun _ h => by cases h⟩

/-! ## T5 — totality: every ruled transition is enabled when its evidence is -/

/-- **T5a.** Given a valid witnessed rotation and the new keys' signature on
the bond option and the optional new refund address — one message carrying
both (D-038) — both bond options are enabled at every address choice,
whatever the pool holds (payment is never a gate, T14) and whether or not
the checkpoint is frozen. `keep` with no new address needs no signature. -/
theorem T5_every_bond_option (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq)
    (payee : Addr) (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn') :
    ∀ (op : BondOp) (r' : Option Addr), env.intentOk (l.epoch + 1) op.intent r' = true →
      ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' op payee r') t (.present l) f (.present l') := by
  intro op r' hauth
  cases op with
  | keep =>
    by_cases hpay : p.P ≤ l.pool
    · exact ⟨_, _, Step.rotateKeepPaid t sn' payee r' hev hsn hauth hpay⟩
    · exact ⟨_, _, Step.rotateKeepUnpaid t sn' payee r' hev hsn hauth (Nat.lt_of_not_le hpay)⟩
  | deposit =>
    by_cases hpay : p.P ≤ l.pool
    · exact ⟨_, _, Step.rotateDepositPaid t sn' payee r' hev hsn hauth hpay⟩
    · exact ⟨_, _, Step.rotateDepositUnpaid t sn' payee r' hev hsn hauth (Nat.lt_of_not_le hpay)⟩

/-- **T5j.** A keep is exactly the rotated datum with the premium: the flow
is the premium to the payee and nothing else, the state is `Live.rotated`
— which ties the helper the next two statements use to the constructors'
field-by-field conclusions. -/
theorem T5_keep_is_rotated (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}
    {sn' : Seq} {payee : Addr} {r' : Option Addr}
    (hk : Step p env (.rotate sn' .keep payee r') t (.present l) f s') :
    f = { hunter := p.premium l payee } ∧ s' = .present (l.rotated p sn' r') := by
  cases hk with
  | rotateKeepPaid _ _ _ _ hev hsn hauth hpay =>
    simp [Params.premium, Live.rotated, hpay]
  | rotateKeepUnpaid _ _ _ _ hev hsn hauth hnopay =>
    simp [Params.premium, Live.rotated, Nat.not_le.mpr hnopay]

/-- **T5h.** D-040: a deposit is a no-op on full bonds. Every licensed
deposit from an unfrozen checkpoint is keep-shaped — from the deposit step
alone, whatever else the keys did or did not sign: it brings nothing, pays
the premium as a keep would, leaves the rotated datum with the freeze bit
clear, and resets nothing (`bornAt` unchanged). -/
theorem T5_deposit_on_full_is_keep (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow}
    {s' : State} {sn' : Seq} {payee : Addr} {r' : Option Addr}
    (hfull : l.frozen = false)
    (hd : Step p env (.rotate sn' .deposit payee r') t (.present l) f s') :
    f = { hunter := p.premium l payee } ∧ f.bIn = 0 ∧ f.dregIn = 0 ∧ f.poolIn = 0 ∧
    s' = .present (l.rotated p sn' r') ∧
    ∃ l', s' = .present l' ∧ l'.bornAt = l.bornAt ∧ l'.frozen = false ∧ l'.sn = sn' ∧
      l'.epoch = l.epoch + 1 ∧ l'.poisoned = false ∧ l'.refundTo = r'.getD l.refundTo ∧
      ((p.P ≤ l.pool ∧ f.hunter = some { addr := payee, pool := p.P } ∧ l'.pool + p.P = l.pool) ∨
       (l.pool < p.P ∧ f.hunter = none ∧ l'.pool = l.pool)) := by
  cases hd with
  | rotateDepositPaid _ _ _ _ hev hsn hauth hpay =>
    refine ⟨?_, ?_, rfl, rfl, ?_, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, Or.inl ⟨hpay, ?_, ?_⟩⟩
    · simp [Params.premium, Live.bHeld, hfull, hpay]
    · simp [Live.bHeld, hfull]
    · simp [Live.rotated, hfull, hpay]
    · simp [Live.bHeld, hfull]
    · simp; omega'
  | rotateDepositUnpaid _ _ _ _ hev hsn hauth hnopay =>
    refine ⟨?_, ?_, rfl, rfl, ?_, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, Or.inr ⟨hnopay, ?_, rfl⟩⟩
    · simp [Params.premium, Live.bHeld, hfull, Nat.not_le.mpr hnopay]
    · simp [Live.bHeld, hfull]
    · simp [Live.rotated, hfull, Nat.not_le.mpr hnopay]
    · simp [Live.bHeld, hfull]

/-- **T5b.** Given the quorum, an unpoisoned state can be poisoned. -/
theorem T5_poison_enabled (p : Params) (env : Env) (t : Slot) (l : Live)
    (hq : env.quorum l.epoch = true) (hclean : l.poisoned = false) :
    ∃ l', Step p env .poison t (.present l) {} (.present l') := by
  exact ⟨_, Step.poison t hq hclean⟩

/-- **T5c.** Given a later witnessed rotation, a short pool, the freeze bond
held and no poison, the freeze is enabled. -/
theorem T5_freeze_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr)
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hpool : l.pool < p.P) (hb : l.frozen = false) (hclean : l.poisoned = false) :
    ∃ (f : Flow) (l' : Live), Step p env (.freeze sn' payee) t (.present l) f (.present l') := by
  exact ⟨_, _, Step.freeze t sn' payee hev hsn hpool hb hclean⟩

/-- **T5d.** Given a duplicity proof, conviction is enabled from every
present state, poisoned or frozen included. -/
theorem T5_convict_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (payee : Addr)
    (hdup : env.duplicityAt l.epoch l.sn = true) :
    ∃ f, Step p env (.convict payee) t (.present l) f .convicted := by
  exact ⟨_, Step.convict t payee hdup⟩

/-- **T5i.** Given a duplicity proof against the parked key state, conviction
is enabled from every parked state, and moves nothing (D-030; the registry's
story 13). -/
theorem T5_convict_parked_enabled (p : Params) (env : Env) (t : Slot) (h : Hash) (payee : Addr)
    (hdup : env.duplicityAt h.epoch h.sn = true) :
    Step p env (.convict payee) t (.parked h) {} .convicted := by
  exact Step.convictParked t payee hdup

/-- **T5e.** Given a later witnessed rotation and the new keys' signature on
the close intent naming the payee, the close is enabled from every present
state — poisoned, frozen or not, whatever the pool holds (D-036, D-039,
D-040) — and parks the key state the rotation reached. -/
theorem T5_close_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr)
    (r' : Option Addr)
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn')
    (hauth : env.intentOk (l.epoch + 1) (.close payee) r' = true) :
    ∃ f, Step p env (.close sn' payee r') t (.present l) f (.parked ⟨l.epoch + 1, sn'⟩) := by
  by_cases hpay : p.P ≤ l.pool
  · exact ⟨_, Step.closePaid t sn' payee r' hev hsn hauth hpay⟩
  · exact ⟨_, Step.closeUnpaid t sn' payee r' hev hsn hauth (Nat.lt_of_not_le hpay)⟩

/-- **T5f.** Given a witnessed rotation later than the parked key state, the
revival is enabled from every parked state (D-036, D-040). -/
theorem T5_reopen_enabled (p : Params) (env : Env) (t : Slot) (h : Hash) (sn' : Seq)
    (refund : Addr) (pool0 : Value) (hev : env.rotationTo h.epoch h.sn sn' = true) (hsn : h.sn < sn') :
    ∃ f l', Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l') := by
  exact ⟨_, _, Step.reopen t sn' refund pool0 hev hsn⟩

/-- **T5g.** D-038's empty message: a keep that names no new address needs no
signature at all — given the witnessed rotation it is enabled under every
environment, whatever the new keys did or did not sign. -/
theorem T5_keep_needs_no_intent (p : Params) (env : Env) (t : Slot) (l : Live) (sn' : Seq) (payee : Addr)
    (hev : env.rotationTo l.epoch l.sn sn' = true) (hsn : l.sn < sn') :
    ∃ (f : Flow) (l' : Live), Step p env (.rotate sn' .keep payee none) t (.present l) f (.present l') := by
  by_cases hpay : p.P ≤ l.pool
  · exact ⟨_, _, Step.rotateKeepPaid t sn' payee none hev hsn rfl hpay⟩
  · exact ⟨_, _, Step.rotateKeepUnpaid t sn' payee none hev hsn rfl (Nat.lt_of_not_le hpay)⟩

/-! ## T6 — value: three components that never mix -/

/-- **T6a.** Component-wise conservation: for each of the conviction bond,
the freeze bond and the pool, held plus in equals held after plus out. -/
theorem T6_component_conservation (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    s.dregHeld p + f.dregIn = s'.dregHeld p + Payment?.dreg f.refund + Payment?.dreg f.hunter + Payment?.dreg f.convictor ∧
    s.bHeld p + f.bIn = s'.bHeld p + Payment?.b f.refund + Payment?.b f.hunter + Payment?.b f.convictor ∧
    s.poolHeld + f.poolIn = s'.poolHeld + Payment?.pool f.refund + Payment?.pool f.hunter + Payment?.pool f.convictor := by
  cases h <;> simp_all [State.dregHeld, State.bHeld, State.poolHeld, Live.bHeld, Payment?.dreg, Payment?.b, Payment?.pool] <;> (try (split <;> simp_all)) <;> omega'

/-- **T6b.** The conviction bond is never a fee source: no hunter payment
ever carries it, and it leaves a present state only whole — to the refund
address at the close, after which nothing is held, or to the convictor. -/
theorem T6_dreg_never_a_fee (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    Payment?.dreg f.hunter = 0 ∧
    (Payment?.dreg f.refund ≠ 0 → Payment?.dreg f.refund = p.D ∧ s.dregHeld p = p.D ∧ s'.dregHeld p = 0) ∧
    (Payment?.dreg f.convictor ≠ 0 → Payment?.dreg f.convictor = p.D ∧ s.dregHeld p = p.D ∧ s' = .convicted) := by
  cases h <;> simp_all [State.dregHeld, Payment?.dreg]

/-- **T6h.** No unbonded on-chain state (D-040): between present states the
conviction bond neither enters nor leaves — a present checkpoint holds it
in full before and after every step that keeps the UTxO. -/
theorem T6_dreg_never_moves_between_present_states (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow} (h : Step p env a t (.present l) f (.present l')) :
    f.dregIn = 0 ∧ Payment?.dreg f.refund = 0 ∧ Payment?.dreg f.hunter = 0 ∧ Payment?.dreg f.convictor = 0 := by
  cases h <;> simp_all [Payment?.dreg]

/-- **T6c.** The conviction bond enters only at a birth: a registration or a
revival, and then in full, together with the freeze bond. -/
theorem T6_dreg_enters_only_at_birth (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') (hin : f.dregIn ≠ 0) :
    ((∃ refund pool0, a = .register refund pool0 ∧ s = .absent) ∨
     (∃ sn' refund pool0 hs, a = .reopen sn' refund pool0 ∧ s = .parked hs)) ∧
    f.dregIn = p.D ∧ f.bIn = p.B ∧ ∃ l', s' = .present l' ∧ l'.frozen = false ∧ l'.bornAt = t := by
  cases h <;> first
    | exact ⟨Or.inl ⟨_, _, rfl, rfl⟩, rfl, rfl, _, rfl, rfl, rfl⟩
    | exact ⟨Or.inr ⟨_, _, _, _, rfl, rfl⟩, rfl, rfl, _, rfl, rfl, rfl⟩
    | exact (hin rfl).elim

/-- **T6d.** `refundTo` changes only under a rotation that names the new
address, and the message the new keys signed is that rotation's own option
with that address (D-032, D-038): no unrelated intent authorizes the move. -/
theorem T6_refund_change_requires_new_keys (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.refundTo ≠ l.refundTo) :
    ∃ sn' op payee, a = .rotate sn' op payee (some l'.refundTo) ∧
      env.intentAuthorized l'.epoch op.intent (some l'.refundTo) = true := by
  cases h with
  | rotateKeepPaid _ sn' payee refund' hev hsn hauth hpay =>
    cases refund' with
    | none => exact absurd rfl hne
    | some r => exact ⟨_, _, _, rfl, by simpa [Env.intentOk, BondOp.intent] using hauth⟩
  | rotateKeepUnpaid _ sn' payee refund' hev hsn hauth hnopay =>
    cases refund' with
    | none => exact absurd rfl hne
    | some r => exact ⟨_, _, _, rfl, by simpa [Env.intentOk, BondOp.intent] using hauth⟩
  | rotateDepositPaid _ sn' payee refund' hev hsn hauth hpay =>
    cases refund' with
    | none => exact absurd rfl hne
    | some r => exact ⟨_, _, _, rfl, by simpa [Env.intentOk, BondOp.intent] using hauth⟩
  | rotateDepositUnpaid _ sn' payee refund' hev hsn hauth hnopay =>
    cases refund' with
    | none => exact absurd rfl hne
    | some r => exact ⟨_, _, _, rfl, by simpa [Env.intentOk, BondOp.intent] using hauth⟩
  | poison => exact absurd rfl hne
  | freeze => exact absurd rfl hne
  | topUp => exact absurd rfl hne

/-- **T6e.** The freeze bond moves between present states only by a rotation
(the deposit) or a freeze; poison and top-up move no bond. -/
theorem T6_frozen_flips_only_by_rotation_or_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow}
    (h : Step p env a t (.present l) f (.present l')) (hne : l'.frozen ≠ l.frozen) :
    a.actor = .nextKeys ∨ (∃ sn' payee, a = .freeze sn' payee) := by
  cases h <;> simp_all [Action.actor]

/-- **T6f.** Every intent other than the empty one is authorized by the keys
of the epoch the rotation opens (D-038): a deposit, a close, and a keep with
a new address each carry the new keys' signature on that intent and that
address. A relayer with public data alone can land a keep and nothing else. -/
theorem T6_intent_requires_new_keys (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State} :
    (∀ {sn' payee r'}, Step p env (.rotate sn' .deposit payee r') t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) .deposit r' = true) ∧
    (∀ {sn' payee r'}, Step p env (.close sn' payee r') t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) (.close payee) r' = true) ∧
    (∀ {sn' payee r}, Step p env (.rotate sn' .keep payee (some r)) t (.present l) f s' →
      env.intentAuthorized (l.epoch + 1) .keep (some r) = true) := by
  refine ⟨?_, ?_, ?_⟩
  · intro sn' payee r' h
    cases h with
    | rotateDepositPaid _ _ _ _ hev hsn hauth hpay => cases r' <;> simpa [Env.intentOk] using hauth
    | rotateDepositUnpaid _ _ _ _ hev hsn hauth hnopay => cases r' <;> simpa [Env.intentOk] using hauth
  · intro sn' payee r' h
    cases h with
    | closePaid _ _ _ _ hev hsn hauth hpay => cases r' <;> simpa [Env.intentOk] using hauth
    | closeUnpaid _ _ _ _ hev hsn hauth hnopay => cases r' <;> simpa [Env.intentOk] using hauth
  · intro sn' payee r h
    cases h with
    | rotateKeepPaid _ _ _ _ hev hsn hauth hpay => simpa [Env.intentOk] using hauth
    | rotateKeepUnpaid _ _ _ _ hev hsn hauth hnopay => simpa [Env.intentOk] using hauth

/-- **T6g.** Without the new keys' signature nothing but a keep with the
address unchanged lands: if the keys of epoch `e + 1` authorized no intent
at all, every rotation from epoch `e` is a keep with `refund' = none`, and no
close happens — a relayer cannot park, unfreeze or move the address. -/
theorem T6_relayer_cannot_park_age_or_close (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live}
    {f : Flow} {s' : State} (h : Step p env a t (.present l) f s')
    (hno : ∀ i r, env.intentAuthorized (l.epoch + 1) i r = false) (hact : a.actor = .nextKeys) :
    ∃ sn' payee, a = .rotate sn' .keep payee none := by
  cases h with
  | rotateKeepPaid _ sn' payee r' hev hsn hauth hpay =>
    cases r' with
    | none => exact ⟨_, _, rfl⟩
    | some r => simp_all [Env.intentOk]
  | rotateKeepUnpaid _ sn' payee r' hev hsn hauth hnopay =>
    cases r' with
    | none => exact ⟨_, _, rfl⟩
    | some r => simp_all [Env.intentOk]
  | rotateDepositPaid _ sn' payee r' hev hsn hauth hpay =>
    cases r' <;> simp_all [Env.intentOk]
  | rotateDepositUnpaid _ sn' payee r' hev hsn hauth hnopay =>
    cases r' <;> simp_all [Env.intentOk]
  | poison => simp [Action.actor] at hact
  | freeze => simp [Action.actor] at hact
  | topUp => simp [Action.actor] at hact
  | convict => simp [Action.actor] at hact
  | closePaid _ sn' payee r' hev hsn hauth hpay =>
    cases r' <;> simp_all [Env.intentOk]
  | closeUnpaid _ sn' payee r' hev hsn hauth hnopay =>
    cases r' <;> simp_all [Env.intentOk]

/-! ## T7 — the state is the fold of the accepted actions -/

/-- **T7a.** The relation and the functional step agree exactly. -/
theorem T7_step_iff_stepFn (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow} :
    Step p env a t s f s' ↔ stepFn p env a t s = some (f, s') := by
  constructor
  · intro h
    cases h <;> simp_all [stepFn, BondOp.intent]
  · intro h
    cases a with
    | register refund pool0 =>
      cases s with
      | absent =>
        simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact Step.register _ _ _
      | present l => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | rotate sn' op payee refund' =>
      cases s with
      | present l =>
        cases op with
        | keep =>
          simp only [stepFn, BondOp.intent] at h
          split at h
          · rename_i hc
            obtain ⟨hev, hsn, hauth⟩ := hc
            split at h
            · rename_i hpay
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact Step.rotateKeepPaid _ _ _ _ hev hsn hauth hpay
            · rename_i hnopay
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact Step.rotateKeepUnpaid _ _ _ _ hev hsn hauth (Nat.lt_of_not_le hnopay)
          · simp at h
        | deposit =>
          simp only [stepFn, BondOp.intent] at h
          split at h
          · rename_i hc
            obtain ⟨hev, hsn, hauth⟩ := hc
            split at h
            · rename_i hpay
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact Step.rotateDepositPaid _ _ _ _ hev hsn hauth hpay
            · rename_i hnopay
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact Step.rotateDepositUnpaid _ _ _ _ hev hsn hauth (Nat.lt_of_not_le hnopay)
          · simp at h
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | poison =>
      cases s with
      | present l =>
        simp only [stepFn] at h
        split at h
        · rename_i hc
          obtain ⟨hq, hclean⟩ := hc
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact Step.poison _ hq hclean
        · simp at h
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | freeze sn' payee =>
      cases s with
      | present l =>
        simp only [stepFn] at h
        split at h
        · rename_i hc
          obtain ⟨hev, hsn, hpool, hb, hclean⟩ := hc
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact Step.freeze _ _ _ hev hsn hpool hb hclean
        · simp at h
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | topUp x =>
      cases s with
      | present l =>
        simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact Step.topUp _ _
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | convict payee =>
      cases s with
      | present l =>
        simp only [stepFn] at h
        split at h
        · rename_i hdup
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact Step.convict _ _ hdup
        · simp at h
      | parked hs =>
        simp only [stepFn] at h
        split at h
        · rename_i hdup
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact Step.convictParked _ _ hdup
        · simp at h
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
    | close sn' payee refund' =>
      cases s with
      | present l =>
        simp only [stepFn] at h
        split at h
        · rename_i hc
          obtain ⟨hev, hsn, hauth⟩ := hc
          split at h
          · rename_i hpay
            simp only [Option.some.injEq, Prod.mk.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact Step.closePaid _ _ _ _ hev hsn hauth hpay
          · rename_i hnopay
            simp only [Option.some.injEq, Prod.mk.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact Step.closeUnpaid _ _ _ _ hev hsn hauth (Nat.lt_of_not_le hnopay)
        · simp at h
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | reopen sn' refund pool0 =>
      cases s with
      | parked hs =>
        simp only [stepFn] at h
        split at h
        · rename_i hc
          obtain ⟨hev, hsn⟩ := hc
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact Step.reopen _ _ _ _ hev hsn
        · simp at h
      | absent => simp [stepFn] at h
      | present l => simp [stepFn] at h
      | convicted => simp [stepFn] at h

/-- **T7b.** A trace is exactly a successful replay. -/
theorem T7_trace_iff_replay (p : Params) (env : Env) {t : Slot} {s s' : State} {es : List (Slot × Action)} :
    Trace p env t s es s' ↔ replay p env t s es = some s' := by
  constructor
  · intro h
    induction h with
    | nil => rfl
    | cons hle hs htail ih =>
      simp only [replay, hle, if_true]
      rw [(T7_step_iff_stepFn p env).1 hs]
      exact ih
  · intro h
    induction es generalizing t s with
    | nil =>
      simp only [replay, Option.some.injEq] at h
      subst h
      exact Trace.nil _ _
    | cons e rest ih =>
      obtain ⟨t', a⟩ := e
      simp only [replay] at h
      split at h
      · rename_i hle
        split at h
        · rename_i f s₁ hstep
          exact Trace.cons hle ((T7_step_iff_stepFn p env).2 hstep) (ih h)
        · simp at h
      · simp at h

/-! ## T8 — one incarnation per AID: the registry leaf over its three states (D-036, D-037, D-040) -/

/-- **T8a.** In every reachable system every leaf agrees with its state:
the leaf is exactly the identity-level projection of the UTxO's state. -/
theorem T8_leaf_agrees_with_state (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    s.leaves aid = (s.states aid).leaf := by
  induction h with
  | init => rfl
  | step _ hs ih => cases hs <;> simp only [Sys.set] <;> split <;> simp_all

/-- **T8b.** The partition of D-037, stated as such: a step leaves every
leaf as it was exactly when its action is a rotate, a poison, a freeze or a
top-up (`Action.touchesLeaf = false`); a register, a reopen, a close and a
conviction change the leaf. -/
theorem T8_edges_leave_the_leaf (p : Params) (env : Env) {s : Sys} {aid : AID} {a : Action} {now : Slot}
    {f : Flow} {st' : State} (hs : SysReach p env s) (hstep : Step p env a now (s.states aid) f st') :
    (s.set aid st').leaves = s.leaves ↔ a.touchesLeaf = false := by
  have hag := T8_leaf_agrees_with_state p env hs aid
  generalize hst : s.states aid = st at hstep hag
  constructor
  · intro heq
    have h1 := congrFun heq aid
    simp only [Sys.set] at h1
    rw [hag] at h1
    cases hstep <;> simp_all [State.leaf, Action.touchesLeaf]
  · intro hf
    funext a
    simp only [Sys.set]
    split
    · rename_i h; subst h; rw [hag]; cases hstep <;> simp_all [State.leaf, Action.touchesLeaf]
    · rfl

/-- **T8c.** In every reachable system, an AID with a state other than
`absent` has a leaf: active, parked or convicted — the token was minted once
by a registration under an absence proof and the leaf never returns to
absent. -/
theorem T8_present_implies_registered (p : Params) (env : Env) {s : Sys} (h : SysReach p env s)
    (aid : AID) (hne : s.states aid ≠ .absent) : s.leaves aid ≠ .absent := by
  have hag := T8_leaf_agrees_with_state p env h aid
  rw [hag]
  generalize hst : s.states aid = st at hne
  cases st <;> simp_all [State.leaf]

/-- **T8g.** The three leaf states, read back (D-040): a parked leaf holds
exactly the hash the state holds and nothing else exists; an active leaf
means the UTxO exists; a convicted leaf means the state is convicted. -/
theorem T8_leaf_states (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (∀ hs, s.leaves aid = .parked hs → s.states aid = .parked hs) ∧
    (s.leaves aid = .active → ∃ l, s.states aid = .present l) ∧
    (s.leaves aid = .convicted → s.states aid = .convicted) := by
  have hag := T8_leaf_agrees_with_state p env h aid
  rw [hag]
  cases hst : s.states aid <;> simp [State.leaf]

/-- **T8m.** One UTxO (D-040): in every reachable system an AID has a
checkpoint UTxO exactly when its leaf is active — a parked or convicted
identity has none. -/
theorem T8_utxo_iff_active (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (∃ l, s.states aid = .present l) ↔ s.leaves aid = .active := by
  have hag := T8_leaf_agrees_with_state p env h aid
  rw [hag]
  cases hst : s.states aid <;> simp [State.leaf]

/-- **T8h.** The leaf never returns to absent, and a convicted leaf is
terminal: no system step changes it. -/
theorem T8_leaf_never_absent_again (p : Params) (env : Env) {s s' : Sys} (hs : SysReach p env s)
    (h : SysStep p env s s') (aid : AID) :
    (s.leaves aid ≠ .absent → s'.leaves aid ≠ .absent) ∧
    (s.leaves aid = .convicted → s'.leaves aid = .convicted) := by
  have hag := T8_leaf_agrees_with_state p env hs aid
  have key : ∀ (aid₀ : AID) (a : Action) (now : Slot) (f : Flow) (st' : State),
      Step p env a now (s.states aid₀) f st' →
      (s.leaves aid ≠ .absent → (s.set aid₀ st').leaves aid ≠ .absent) ∧
      (s.leaves aid = .convicted → (s.set aid₀ st').leaves aid = .convicted) := by
    intro aid₀ a now f st' hstep
    by_cases heq : aid = aid₀
    · subst heq
      generalize hst : s.states aid = st at hstep hag
      cases hstep <;> simp_all [Sys.set, State.leaf]
    · simp [Sys.set, heq]
  cases h with
  | register _ hstep => exact key _ _ _ _ _ hstep
  | reopen _ hstep => exact key _ _ _ _ _ hstep
  | other _ _ hstep => exact key _ _ _ _ _ hstep

/-- **T8i.** Mint-once: a registration lands only on an absent leaf, a
revival only on a parked one; an active or convicted AID is never registered
or revived. -/
theorem T8_mint_once (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (∀ refund pool0 now f st', Step p env (.register refund pool0) now (s.states aid) f st' →
      s.leaves aid = .absent) ∧
    (∀ sn' refund pool0 now f st', Step p env (.reopen sn' refund pool0) now (s.states aid) f st' →
      ∃ hs, s.leaves aid = .parked hs) := by
  have hag := T8_leaf_agrees_with_state p env h aid
  refine ⟨fun refund pool0 now f st' hstep => ?_, fun sn' refund pool0 now f st' hstep => ?_⟩
  · generalize hst : s.states aid = st at hstep hag
    cases hstep
    simpa [State.leaf] using hag
  · generalize hst : s.states aid = st at hstep hag
    cases hstep
    exact ⟨_, by simpa [State.leaf] using hag⟩

/-- **T8j.** A reopen is proof-bearing: its actor is the evidence class, the
same as a freeze and a conviction — never `anyone` (D-036, D-037). -/
theorem T8_reopen_actor_is_proof (sn' : Seq) (refund : Addr) (pool0 : Value) :
    (Action.reopen sn' refund pool0).actor = .proof ∧ (Action.freeze sn' refund).actor = .proof ∧
    (Action.convict refund).actor = .proof := by
  exact ⟨rfl, rfl, rfl⟩

/-- **T8k.** The system step is exactly the partition its constructors name:
every system step is one `Step` on one AID whose leaf follows; a
registration only under an absent leaf, a revival only under a parked leaf
(the hash the step reads), and every other action neither. -/
theorem T8_sysstep_partition (p : Params) (env : Env) {s s' : Sys} (h : SysStep p env s s') :
    ∃ aid a now f st', s' = s.set aid st' ∧ Step p env a now (s.states aid) f st' ∧
      ((∃ refund pool0, a = .register refund pool0) → s.leaves aid = .absent) ∧
      ((∃ sn' refund pool0, a = .reopen sn' refund pool0) → ∃ hs, s.leaves aid = .parked hs) := by
  cases h with
  | register habs hstep =>
    exact ⟨_, _, _, _, _, ⟨rfl, ⟨hstep, ⟨fun _ => habs, (fun h => by obtain ⟨_, _, _, hc⟩ := h; cases hc)⟩⟩⟩⟩
  | reopen hparked hstep =>
    exact ⟨_, _, _, _, _, ⟨rfl, ⟨hstep, ⟨(fun h => by obtain ⟨_, _, hc⟩ := h; cases hc), fun _ => ⟨_, hparked⟩⟩⟩⟩⟩
  | other hnotreg hnotreopen hstep =>
    exact ⟨_, _, _, _, _, ⟨rfl, ⟨hstep, ⟨(fun h => by obtain ⟨r, q, hc⟩ := h; exact absurd hc (hnotreg r q)),
      (fun h => by obtain ⟨x, r, q, hc⟩ := h; exact absurd hc (hnotreopen x r q))⟩⟩⟩⟩

/-! ## T9 — juvenility is consumer policy -/

/-- **T9.0.** The consumer's program is the consumer's predicate: the
decidable mirror `consumableStateB` decides exactly `consumableState`, so
what the trace driver and the simulator run is what the theorems below
speak about. -/
theorem consumableStateB_iff (p : Params) (now : Slot) (s : State) :
    consumableStateB p now s = true ↔ consumableState p now s := by
  cases s <;> simp [consumableStateB, consumableState, and_assoc]

/-- **T9.** No transition depends on `W`: the registry's grace window is not
this machine's, and this machine has none. -/
theorem T9_juvenility_is_consumer_only (p : Params) (env : Env) (W' : Nat) {a : Action} {t : Slot}
    {s s' : State} {f : Flow} :
    Step p env a t s f s' ↔ Step { p with W := W' } env a t s f s' := by
  constructor <;> intro h <;> cases h <;> first
    | exact Step.register _ _ _
    | exact Step.rotateKeepPaid _ _ _ _ ‹_› ‹_› ‹_› ‹_›
    | exact Step.rotateKeepUnpaid _ _ _ _ ‹_› ‹_› ‹_› ‹_›
    | exact Step.rotateDepositPaid _ _ _ _ ‹_› ‹_› ‹_› ‹_›
    | exact Step.rotateDepositUnpaid _ _ _ _ ‹_› ‹_› ‹_› ‹_›
    | exact Step.poison _ ‹_› ‹_›
    | exact Step.freeze _ _ _ ‹_› ‹_› ‹_› ‹_› ‹_›
    | exact Step.topUp _ _
    | exact Step.convict _ _ ‹_›
    | exact Step.convictParked _ _ ‹_›
    | exact Step.closePaid _ _ _ _ ‹_› ‹_› ‹_› ‹_›
    | exact Step.closeUnpaid _ _ _ _ ‹_› ‹_› ‹_› ‹_›
    | exact Step.reopen _ _ _ _ ‹_› ‹_›

/-! ## T10 — a frozen checkpoint is inert to everyone but the next keys; a parked one holds nothing -/

/-- **T10a.** If the freeze bond is missing, no step by anyone but the next
keys yields a consumable state. -/
theorem T10_inert_without_next_keys (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p env a t (.present l) f s')
    (hfrozen : l.frozen = true) (hnot : a.actor ≠ .nextKeys) :
    ¬ consumableState p t' s' := by
  cases h <;> simp_all [Action.actor, consumableState]

/-- **T10b.** Only a depositing rotation restores consumability to a frozen
checkpoint, and it does not restart juvenility (D-040: the deposit is the
unfreeze, not a bonding). -/
theorem T10_only_deposit_restores (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live} {f : Flow}
    {s' : State} (h : Step p env a t (.present l) f s')
    (hfrozen : l.frozen = true) (hc : consumableState p t' s') :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧
    ∃ l', s' = .present l' ∧ l'.frozen = false ∧ l'.bornAt = l.bornAt ∧ f.bIn = p.B := by
  cases h <;> first
    | exact ⟨⟨_, _, _, rfl⟩, _, rfl, rfl, rfl, by simp [Live.bHeld, hfrozen]⟩
    | (exfalso; simp_all [consumableState])

/-- **T10c.** The current quorum never produces a consumable state: its only
move is the poison. -/
theorem T10_current_quorum_never_restores (p : Params) (env : Env) {a : Action} {t t' : Slot} {l : Live}
    {f : Flow} {s' : State} (h : Step p env a t (.present l) f s') (hq : a.actor = .currentQuorum) :
    ¬ consumableState p t' s' := by
  cases h <;> simp_all [Action.actor, consumableState]

/-- **T10d.** A revival brings both bonds in full and restarts juvenility:
the revived checkpoint is unconsumable for `W` slots. -/
theorem T10_reopen_is_juvenile (p : Params) (env : Env) {t t' : Slot} {h : Hash} {f : Flow}
    {sn' : Seq} {refund : Addr} {pool0 : Value} {l' : Live}
    (hs : Step p env (.reopen sn' refund pool0) t (.parked h) f (.present l')) :
    f.dregIn = p.D ∧ f.bIn = p.B ∧ l'.frozen = false ∧ l'.bornAt = t ∧
    (t' < t + p.W → ¬ consumableState p t' (.present l')) := by
  cases hs with
  | reopen =>
    refine ⟨rfl, rfl, rfl, rfl, fun hlt hc => ?_⟩
    simp only [consumableState] at hc
    omega'

/-- **T10e.** Both bonds are positive, so the bond states are observable in
value: a present checkpoint holds the conviction bond and a parked or
convicted identity holds none of it, so the two differ in value; a frozen
checkpoint holds less than the full freeze bond. -/
theorem T10_bonds_are_observable (p : Params) (l : Live) (h : Hash) :
    (State.present l).dregHeld p ≠ (State.parked h).dregHeld p ∧
    (State.present l).dregHeld p ≠ State.convicted.dregHeld p ∧
    (l.frozen = true → (State.present l).bHeld p ≠ p.B) := by
  have hD := p.hD
  have hB := p.hB
  refine ⟨?_, ?_, fun hf => ?_⟩
  · simp [State.dregHeld]; omega'
  · simp [State.dregHeld]; omega'
  · simp [State.bHeld, Live.bHeld, hf]; omega'

/-- **T10f.** A parked identity holds nothing (D-040: no UTxO): every
component of a parked or convicted state is zero. -/
theorem T10_parked_holds_nothing (p : Params) (h : Hash) :
    (State.parked h).dregHeld p = 0 ∧ (State.parked h).bHeld p = 0 ∧ (State.parked h).poolHeld = 0 ∧
    State.convicted.dregHeld p = 0 ∧ State.convicted.bHeld p = 0 ∧ State.convicted.poolHeld = 0 := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

/-! ## T12 — conviction needs a proof and is exact -/

/-- **T12b.** Only a conviction reaches `convicted` from a present state;
the flow is exactly the conviction bond to the convictor and the rest to
the refund address; the proof is against the checkpoint's own key state. -/
theorem T12_convict_exact (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow}
    (h : Step p env a t (.present l) f .convicted) :
    (∃ payee, a = .convict payee ∧
      f = { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
            convictor := some { addr := payee, dreg := p.D } }) ∧
    env.duplicityAt l.epoch l.sn = true := by
  cases h with
  | convict => exact ⟨⟨_, rfl, rfl⟩, ‹_›⟩

/-- **T12c.** Only a conviction reaches `convicted` from a parked state; the
proof is against the parked key state and nothing moves. -/
theorem T12_convict_parked_exact (p : Params) (env : Env) {a : Action} {t : Slot} {hs : Hash} {f : Flow}
    (h : Step p env a t (.parked hs) f .convicted) :
    (∃ payee, a = .convict payee) ∧ f = {} ∧ env.duplicityAt hs.epoch hs.sn = true := by
  cases h with
  | convictParked => exact ⟨⟨_, rfl⟩, rfl, ‹_›⟩

/-! ## T14, T15 — the pool and the freeze bond -/

/-- **T14a.** The pool decreases between present states only by the premium
under a paid rotation. -/
theorem T14_pool_decreases_only_by_premium (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l'.pool < l.pool) :
    a.actor = .nextKeys ∧ l'.pool + p.P = l.pool ∧ Payment?.pool f.hunter = p.P := by
  cases h <;> simp_all [Action.actor, Payment?.pool] <;> omega'

/-- **T14b.** The pool increases between present states only by a top-up. -/
theorem T14_pool_increases_only_by_topup (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l')) (hlt : l.pool < l'.pool) :
    ∃ x, a = .topUp x ∧ f = { poolIn := x } ∧ l' = { l with pool := l.pool + x } := by
  cases h <;> first
    | exact ⟨_, rfl, rfl, rfl⟩
    | (exfalso; omega')

/-- **T15a.** The freeze bond leaves a present state for a present state
only by a freeze — proof of a later rotation, pool short, exactly `B` to the
hunter, datum otherwise untouched. -/
theorem T15_b_leaves_only_by_freeze (p : Params) (env : Env) {a : Action} {t : Slot}
    {l l' : Live} {f : Flow} (h : Step p env a t (.present l) f (.present l'))
    (hheld : l.frozen = false) (hgone : l'.frozen = true) :
    ∃ sn' payee, a = .freeze sn' payee ∧ env.rotationTo l.epoch l.sn sn' = true ∧ l.pool < p.P ∧
      l' = { l with frozen := true } ∧ f = { hunter := some { addr := payee, b := p.B } } := by
  cases h <;> first
    | exact ⟨_, _, rfl, ‹_›, ‹_›, rfl, rfl⟩
    | simp_all

/-- **T15b.** The freeze bond returns only by a depositing rotation, and then
in full. -/
theorem T15_b_returns_only_by_deposit (p : Params) (env : Env) {a : Action} {t : Slot} {l l' : Live}
    {f : Flow} (h : Step p env a t (.present l) f (.present l'))
    (hgone : l.frozen = true) (hback : l'.frozen = false) :
    (∃ sn' payee r', a = .rotate sn' .deposit payee r') ∧ f.bIn = p.B := by
  cases h <;> first
    | exact ⟨⟨_, _, _, rfl⟩, by simp [Live.bHeld, hgone]⟩
    | simp_all

/-- **T15c.** A freeze makes the checkpoint unconsumable — the bond is
positive, so "missing" is observable. -/
theorem T15_freeze_makes_inert (p : Params) (env : Env) {t t' : Slot} {l l' : Live} {f : Flow}
    {sn' : Seq} {payee : Addr} (h : Step p env (.freeze sn' payee) t (.present l) f (.present l')) :
    ¬ consumableState p t' (.present l') := by
  cases h with
  | freeze =>
    intro ⟨hf, _, _⟩
    simp at hf

/-! ## T16 — the closer chooses when, never where; the parked hash is the closed checkpoint's -/

/-- **T16a.** A close is a witnessed rotation by the next keys, poisoned or
frozen or not: it pays the premium to the signed payee when the pool covers
it and everything else the UTxO holds to the refund address it results in
— the one in the datum, or the one the new keys authorized in the same
message as the close and the payee — parks the epoch it opened with its
sequence, and needs the rotation and the signed intent (D-036, D-038,
D-039, D-040). -/
theorem T16_close_destination (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow}
    {h : Hash} (hs : Step p env a t (.present l) f (.parked h)) :
    ∃ sn' payee r', a = .close sn' payee r' ∧
      f = { refund := some { addr := r'.getD l.refundTo, dreg := p.D, b := l.bHeld p,
                             pool := (l.rotated p sn' r').pool },
            hunter := p.premium l payee } ∧
      ((p.P ≤ l.pool ∧ f.hunter = some { addr := payee, pool := p.P } ∧ Payment?.pool f.refund + p.P = l.pool) ∨
       (l.pool < p.P ∧ f.hunter = none ∧ Payment?.pool f.refund = l.pool)) ∧
      h = ⟨l.epoch + 1, sn'⟩ ∧ l.sn < sn' ∧ env.rotationTo l.epoch l.sn sn' = true ∧
      env.intentOk (l.epoch + 1) (.close payee) r' = true := by
  cases hs with
  | closePaid _ _ _ _ hev hsn hauth hpay =>
    refine ⟨_, _, _, rfl, ?_, Or.inl ⟨hpay, rfl, ?_⟩, rfl, ‹_›, ‹_›, ‹_›⟩
    · simp [Params.premium, Live.rotated, hpay]
    · simp [Payment?.pool]; omega'
  | closeUnpaid _ _ _ _ hev hsn hauth hnopay =>
    refine ⟨_, _, _, rfl, ?_, Or.inr ⟨hnopay, rfl, rfl⟩, rfl, ‹_›, ‹_›, ‹_›⟩
    simp [Params.premium, Live.rotated, Nat.not_le.mpr hnopay]

/-- **T16d.** No close without the rotation: the current quorum cannot
close, and a close never lands on a state the presented rotation does not
advance. -/
theorem T16_close_needs_rotation (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}
    {sn' : Seq} {payee : Addr} {r' : Option Addr} (h : Step p env (.close sn' payee r') t (.present l) f s') :
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ (Action.close sn' payee r').actor = .nextKeys := by
  cases h <;> exact ⟨‹_›, ‹_›, rfl⟩

/-- **T16e.** The parked hash is the closed checkpoint's (D-040), from the
close alone: the leaf holds the hash of the checkpoint the closing rotation
reached — the rotated datum, the same a keep with that rotation would have
put on chain (`T5_keep_is_rotated`) — and the parked state holds nothing of
what the close paid out. -/
theorem T16_parked_hash_is_the_closed_checkpoints (p : Params) (env : Env) {t : Slot} {l : Live}
    {f : Flow} {sn' : Seq} {payee : Addr} {r' : Option Addr} {h : Hash}
    (hc : Step p env (.close sn' payee r') t (.present l) f (.parked h)) :
    h = (l.rotated p sn' r').hash ∧ h = ⟨l.epoch + 1, sn'⟩ ∧
    Payment?.dreg f.refund = (State.present l).dregHeld p ∧
    Payment?.b f.refund = (State.present l).bHeld p ∧
    Payment?.pool f.refund + Payment?.pool f.hunter = (State.present l).poolHeld ∧
    (State.parked h).dregHeld p = 0 ∧ (State.parked h).bHeld p = 0 ∧ (State.parked h).poolHeld = 0 := by
  cases hc with
  | closePaid _ _ _ _ hev hsn hauth hpay =>
    refine ⟨rfl, rfl, rfl, rfl, ?_, rfl, rfl, rfl⟩
    simp [Payment?.pool, State.poolHeld]; omega'
  | closeUnpaid _ _ _ _ hev hsn hauth hnopay =>
    exact ⟨rfl, rfl, rfl, rfl, by simp [Payment?.pool, State.poolHeld], rfl, rfl, rfl⟩

/-- **T16f.** The copied reap is refused (D-039; the registry's Q-R6): when
the new keys signed exactly one close message — one payee, one address —
every close that lands from that checkpoint names that payee and that
address. A block producer copying the reap with itself as payee presents a
message the keys never signed. -/
theorem T16_copied_reap_refused (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}
    {sn' : Seq} {payee payee₀ : Addr} {r' r₀ : Option Addr}
    (hone : ∀ q r, env.intentAuthorized (l.epoch + 1) (.close q) r = true → q = payee₀ ∧ r = r₀)
    (h : Step p env (.close sn' payee r') t (.present l) f s') :
    payee = payee₀ ∧ r' = r₀ ∧ (∀ q, f.hunter = some q → q.addr = payee₀) := by
  cases h with
  | closePaid _ _ _ _ hev hsn hauth hpay =>
    have hm : env.intentAuthorized (l.epoch + 1) (.close payee) r' = true := by
      cases r' <;> simpa [Env.intentOk] using hauth
    obtain ⟨h1, h2⟩ := hone payee r' hm
    exact ⟨h1, h2, fun q hq => by cases hq; exact h1⟩
  | closeUnpaid _ _ _ _ hev hsn hauth hnopay =>
    have hm : env.intentAuthorized (l.epoch + 1) (.close payee) r' = true := by
      cases r' <;> simpa [Env.intentOk] using hauth
    obtain ⟨h1, h2⟩ := hone payee r' hm
    exact ⟨h1, h2, fun q hq => by cases hq⟩

/-- **T16c.** No step pays a hunter anything but the premium or the freeze
bond, and no step pays a convictor anything but the conviction bond. -/
theorem T16_payments_are_named (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    (∀ q, f.hunter = some q → (q.dreg = 0 ∧ q.b = 0 ∧ q.pool = p.P) ∨ (q.dreg = 0 ∧ q.b = p.B ∧ q.pool = 0)) ∧
    (∀ q, f.convictor = some q → q.b = 0 ∧ q.pool = 0 ∧ q.dreg = s.dregHeld p) := by
  cases h <;> simp_all [State.dregHeld]

end CardanoKeri.Checkpoint
