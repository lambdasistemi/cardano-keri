import CardanoKeri.Checkpoint
import Lean.Elab.Command

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

/-- Given Every action, slot, flow and successor and an alleged local Step out of completed convicted state.
When Invert that alleged Step.
Then False: no local action leaves completed retirement. A connected actual system fold must exhibit this source state; a newly unreachable local Trace endpoint cannot be used as a nonvacuous lifecycle witness. -/
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

/-- Given pending custody, no local action completes it. -/
theorem pending_step_impossible (p : Params) (env : Env) (h : Hash)
    {a : Action} {t : Slot} {f : Flow} {s' : State}
    (hs : Step p env a t (.terminationPending h) f s') : False := by
  cases hs

/-- Pending has no local trace exit; only the associated system fold completes. -/
theorem trace_from_pending (p : Params) (env : Env) {h : Hash} {t : Slot}
    {es : List (Slot × Action)} {s' : State}
    (hs : Trace p env t (.terminationPending h) es s') : s' = .terminationPending h := by
  cases hs with
  | nil => rfl
  | cons _ step _ => exact (pending_step_impossible p env h step).elim

/-- Given the complete parameters and hypotheses:

(p : Params) (env : Env) (h : Hash)
    (a : Action) (now : Slot)

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

stepFn p env a now (.terminationPending h) = none
-/
theorem pending_has_no_local_exit (p : Params) (env : Env) (h : Hash)
    (a : Action) (now : Slot) :
    stepFn p env a now (.terminationPending h) = none := by cases a <;> rfl

/-- Given the complete parameters and hypotheses:

(p : Params) (now : Slot) (h : Hash)

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

¬ consumableState p now (.terminationPending h) ∧
    consumableStateB p now (.terminationPending h) = false
-/
theorem pending_consumer_refused (p : Params) (now : Slot) (h : Hash) :
    ¬ consumableState p now (.terminationPending h) ∧
    consumableStateB p now (.terminationPending h) = false := by exact ⟨id, rfl⟩

/-- Given the complete parameters and hypotheses:

(p : Params) (h : Hash)

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

(State.terminationPending h).hasOutput = true ∧
    (State.terminationPending h).representativeHeld = 1 ∧
    (State.terminationPending h).leaf = .active ∧
    (State.terminationPending h).sn? = some h.sn ∧
    (State.terminationPending h).dregHeld p = 0 ∧
    (State.terminationPending h).bHeld p = 0 ∧
    (State.terminationPending h).poolHeld = 0
-/
theorem pending_custody_observations (p : Params) (h : Hash) :
    (State.terminationPending h).hasOutput = true ∧
    (State.terminationPending h).representativeHeld = 1 ∧
    (State.terminationPending h).leaf = .active ∧
    (State.terminationPending h).sn? = some h.sn ∧
    (State.terminationPending h).dregHeld p = 0 ∧
    (State.terminationPending h).bHeld p = 0 ∧
    (State.terminationPending h).poolHeld = 0 := by exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- **T8d.** Registration is the only step from `absent`. -/
theorem T8_absent_only_registers (p : Params) (env : Env) {a : Action} {t : Slot} {f : Flow} {s' : State}
    (h : Step p env a t .absent f s') : ∃ refund pool0, a = .register refund pool0 := by
  cases h with
  | register => exact ⟨_, _, rfl⟩

/-- Given Arbitrary Params, Env, action, slot, exact parked hash, flow and successor, with actual Step success.
When Classify the accepted action from the retained parked state.
Then Either the exact later witnessed rotation, strict sequence condition, all fresh D/B/pool, exact new live datum and revival action hold, or the action is conviction with concrete duplicity at that retained hash, empty component flow and pending at the same hash. There are no other local actions. -/
theorem T8_parked_only_revives_or_convicts (p : Params) (env : Env) {a : Action} {t : Slot} {h : Hash}
    {f : Flow} {s' : State} (hs : Step p env a t (.parked h) f s') :
    (∃ sn' refund pool0, a = .reopen sn' refund pool0 ∧ h.sn < sn' ∧ env.rotationTo h.epoch h.sn sn' = true ∧
      f = { dregIn := p.D, bIn := p.B, poolIn := pool0 } ∧
      s' = .present ⟨sn', h.epoch + 1, false, false, t, refund, pool0⟩) ∨
    (∃ payee, a = .convict payee ∧ env.duplicityAt h.epoch h.sn = true ∧ f = {} ∧ s' = .terminationPending h) := by
  cases hs with
  | reopen => exact Or.inl ⟨_, _, _, rfl, ‹_›, ‹_›, rfl, rfl⟩
  | convictParked => exact Or.inr ⟨_, rfl, ‹_›, rfl, rfl⟩

/-- Given Every Step from parked h to a present live datum, arbitrary inputs.
When Invert return to present.
Then There exist sn′/refund/pool0 with action reopen, exact retained-state rotation evidence true, and h.sn < sn′. -/
theorem T8_parked_returns_only_by_revival (p : Params) (env : Env) {a : Action} {t : Slot} {h : Hash}
    {f : Flow} {l' : Live} (hs : Step p env a t (.parked h) f (.present l')) :
    ∃ sn' refund pool0, a = .reopen sn' refund pool0 ∧ env.rotationTo h.epoch h.sn sn' = true ∧ h.sn < sn' := by
  cases hs with
  | reopen => exact ⟨_, _, _, rfl, ‹_›, ‹_›⟩

/-- Given Arbitrary parameters, environment, slot and state; state is neither convicted nor any terminationPending; every applicable parked next-sequence rotation premise holds.
When Ask for a local Checkpoint Step.
Then There exists an action, flow and successor as before. Pending has no local exit. Completion is a separate actual imported-fold system event with reachable origin, exact pending membership and an accepted supplied transaction. -/
theorem local_progress_unless_pending_or_retired (p : Params) (env : Env) (t : Slot) (s : State)
    (hnot : s ≠ .convicted)
    (hnotPending : ∀ h, s ≠ .terminationPending h)
    (hrevive : ∀ h, s = .parked h → env.rotationTo h.epoch h.sn (h.sn + 1) = true) :
    ∃ a f s', Step p env a t s f s' := by
  cases s with
  | absent => exact ⟨.register 0 0, _, _, Step.register t 0 0⟩
  | present l => exact ⟨.topUp 0, _, _, Step.topUp t 0⟩
  | convicted => exact absurd rfl hnot
  | terminationPending h => exact absurd rfl (hnotPending h)
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
  cases h <;> simp_all [State.sn?, Live.hash] <;> omega'

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
        have := trace_from_pending p env htail
        subst this
        cases h2
      | convictParked =>
        have := trace_from_pending p env htail
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

/-- Given Every parked hash, action, time, result and successful Step, with all rotations from that exact hash false.
When Classify a successful action available to the current-key thief.
Then The action must be conviction, its exact successor is pending at the original hash, and no live successor exists. Completion of retirement is a separate associated system event. -/
theorem T4_current_key_thief_cannot_revive (p : Params) (env : Env) {a : Action} {t : Slot}
    {h : Hash} {f : Flow} {s' : State}
    (hthief : ∀ sn', env.rotationTo h.epoch h.sn sn' = false)
    (hs : Step p env a t (.parked h) f s') :
    (∃ payee, a = .convict payee) ∧ s' = .terminationPending h ∧ ∀ l', s' ≠ .present l' := by
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
    · simp []
    · simp; omega'
  | rotateDepositUnpaid _ _ _ _ hev hsn hauth hnopay =>
    refine ⟨?_, ?_, rfl, rfl, ?_, _, rfl, rfl, rfl, rfl, rfl, rfl, rfl, Or.inr ⟨hnopay, ?_, rfl⟩⟩
    · simp [Params.premium, Live.bHeld, hfull, Nat.not_le.mpr hnopay]
    · simp [Live.bHeld, hfull]
    · simp [Live.rotated, hfull, Nat.not_le.mpr hnopay]
    · simp []

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

/-- Given Every parameter, slot, source state and payee in the exact type; the enabled statements additionally assume concrete duplicity at that source state.
When Execute the local conviction transition, or compare it to its complete guard in the iff statements.
Then The exact existing component flow and concrete duplicity guard remain; the target is pending at the source hash. Both iff directions remain obligations. Enabled clauses are local applicability only, not a claim that an arbitrary economic request can be booked. -/
theorem T5_convict_enabled (p : Params) (env : Env) (t : Slot) (l : Live) (payee : Addr)
    (hdup : env.duplicityAt l.epoch l.sn = true) :
    ∃ f, Step p env (.convict payee) t (.present l) f (.terminationPending l.hash) := by
  exact ⟨_, Step.convict t payee hdup⟩

/-- Given Every parameter, slot, source state and payee in the exact type; the enabled statements additionally assume concrete duplicity at that source state.
When Execute the local conviction transition, or compare it to its complete guard in the iff statements.
Then The exact existing component flow and concrete duplicity guard remain; the target is pending at the source hash. Both iff directions remain obligations. Enabled clauses are local applicability only, not a claim that an arbitrary economic request can be booked. -/
theorem T5_convict_parked_enabled (p : Params) (env : Env) (t : Slot) (h : Hash) (payee : Addr)
    (hdup : env.duplicityAt h.epoch h.sn = true) :
    Step p env (.convict payee) t (.parked h) {} (.terminationPending h) := by
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

/-- Given Every successful Step over arbitrary states, actions, time, environment and Params.
When Observe before/after holdings and addressed flow.
Then Each of D, B and pool satisfies its own full incoming = retained + refund + hunter + convictor equality. No component is used as an undeclared min-ADA or fee source. -/
theorem T6_component_conservation (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    s.dregHeld p + f.dregIn = s'.dregHeld p + Payment?.dreg f.refund + Payment?.dreg f.hunter + Payment?.dreg f.convictor ∧
    s.bHeld p + f.bIn = s'.bHeld p + Payment?.b f.refund + Payment?.b f.hunter + Payment?.b f.convictor ∧
    s.poolHeld + f.poolIn = s'.poolHeld + Payment?.pool f.refund + Payment?.pool f.hunter + Payment?.pool f.convictor := by
  cases h <;> simp_all [State.dregHeld, State.bHeld, State.poolHeld, Live.bHeld, Payment?.dreg, Payment?.b, Payment?.pool] <;> (try (split <;> simp_all)) <;> omega'

/-- Given Every parameter/environment/action/time/state/flow and an actual local Step.
When Inspect D payments to hunter, refund and convictor.
Then Hunter receives zero D; every nonzero refund is exactly D from a D-holding source to a zero-D successor; every nonzero convictor payment is exactly D from a D-holding live source, and the target is pending at that same source hash. All original amount/source/non-fee clauses remain. -/
theorem T6_dreg_never_a_fee (p : Params) (env : Env) {a : Action} {t : Slot} {s s' : State} {f : Flow}
    (h : Step p env a t s f s') :
    Payment?.dreg f.hunter = 0 ∧
    (Payment?.dreg f.refund ≠ 0 → Payment?.dreg f.refund = p.D ∧ s.dregHeld p = p.D ∧ s'.dregHeld p = 0) ∧
    (Payment?.dreg f.convictor ≠ 0 → Payment?.dreg f.convictor = p.D ∧ s.dregHeld p = p.D ∧ ∃ l, s = .present l ∧ s' = .terminationPending l.hash) := by
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

/-- Given All p/env/actions/times/states/flows/successors without additional reachability assumptions.
When Compare Step with executable stepFn.
Then Step holds iff stepFn returns precisely some(flow,successor), in both directions. -/
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
      | terminationPending hs => simp [stepFn] at h
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
      | terminationPending hs => simp [stepFn] at h
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
      | terminationPending hs => simp [stepFn] at h
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
      | terminationPending hs => simp [stepFn] at h
      | parked hs => simp [stepFn] at h
    | topUp x =>
      cases s with
      | present l =>
        simp only [stepFn, Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact Step.topUp _ _
      | absent => simp [stepFn] at h
      | convicted => simp [stepFn] at h
      | terminationPending hs => simp [stepFn] at h
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
      | terminationPending hs => simp [stepFn] at h
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
      | terminationPending hs => simp [stepFn] at h
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
      | terminationPending hs => simp [stepFn] at h

/-- Given All p/env/start-time/states and timestamped action lists.
When Compare Trace with replay.
Then Trace holds iff replay returns precisely the stated final state; timestamp and refusal semantics unchanged. -/
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
  | step _ hs ih =>
    cases hs with
    | register event =>
      obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, _, _, rfl⟩ := event
      simp only [Sys.installOrigin, Sys.set]
      split <;> simp_all
    | «local» event =>
      obtain ⟨x, a, now, f, st, _, _, _, rfl⟩ := event
      simp only [Sys.set]
      split <;> simp_all
    | book event =>
      obtain ⟨x, h, origin, before, booked, booker, fee, b, f, entry,
        _, _, _, _, _, _, _, _, _, rfl⟩ := event
      exact ih
    | complete event =>
      obtain ⟨x, assoc, receipt, _, rfl⟩ := event
      simp only [Sys.finish, Sys.set]
      split <;> simp_all

/-- Given Arbitrary reachable Checkpoint Sys and a successful local Step on the chosen AID with every typed parameter.
When Apply Sys.set to that local result.
Then The entire leaf function is unchanged iff Action.touchesLeaf is false. Only local registration has touchesLeaf=true; close, reopen and conviction-to-pending are false. Completed retirement is a separate associated system event, not a local Action. -/
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

/-- Given All p/env/reachable system s and AID; no assumption of live eligibility.
When Observe the key and application state.
Then Active iff present, parked or terminationPending, in both directions; retired implies completed conviction. The pending payload retains the recorded key state; its system association retains the whole booked request. -/
theorem T8_leaf_states (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (s.leaves aid = .active ↔
      (∃ l, s.states aid = .present l) ∨ (∃ hs, s.states aid = .parked hs) ∨
      (∃ pending, s.states aid = .terminationPending pending)) ∧
    (s.leaves aid = .retired → s.states aid = .convicted) := by
  have hag := T8_leaf_agrees_with_state p env h aid
  rw [hag]
  cases hst : s.states aid <;> simp [State.leaf]

/-- Given All p/env/s/aid with SysReach p env s.
When Observe State.hasOutput and the leaf.
Then Output existence iff active key, including present, parked and terminationPending. The pending output retains the representative; completed conviction has neither output nor active key. -/
theorem T8_utxo_iff_active (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (s.states aid).hasOutput = true ↔ s.leaves aid = .active := by
  have hag := T8_leaf_agrees_with_state p env h aid
  rw [hag]
  cases hst : s.states aid <;> simp [State.leaf, State.hasOutput]

/-- Given Arbitrary reachable Checkpoint Sys, actual system step and AID.
When Observe that AID after the step.
Then A nonabsent leaf never becomes absent, and a retired leaf remains retired. Registration-origin and booking-association events preserve the same lifecycle clauses. -/
theorem T8_leaf_never_absent_again (p : Params) (env : Env) {s s' : Sys} (hs : SysReach p env s)
    (h : SysStep p env s s') (aid : AID) :
    (s.leaves aid ≠ .absent → s'.leaves aid ≠ .absent) ∧
    (s.leaves aid = .retired → s'.leaves aid = .retired) := by
  have hag := T8_leaf_agrees_with_state p env hs aid
  have key : ∀ (aid₀ : AID) (a : Action) (now : Slot) (f : Flow) (st' : State),
      Step p env a now (s.states aid₀) f st' →
      (s.leaves aid ≠ .absent → (s.set aid₀ st').leaves aid ≠ .absent) ∧
      (s.leaves aid = .retired → (s.set aid₀ st').leaves aid = .retired) := by
    intro aid₀ a now f st' hstep
    by_cases heq : aid = aid₀
    · subst heq
      generalize hst : s.states aid = st at hstep hag
      cases hstep <;> simp_all [Sys.set, State.leaf]
    · simp [Sys.set, heq]
  cases h with
  | register event =>
    obtain ⟨x, now, refund, pool, f, st, rp, re, cfg, receipt, b, origin, _, _, step, _, rfl⟩ := event
    exact key _ _ _ _ _ step
  | «local» event =>
    obtain ⟨x, a, now, f, st, _, step, _, rfl⟩ := event
    exact key _ _ _ _ _ step
  | book event =>
    obtain ⟨x, h, origin, before, booked, booker, fee, b, f, entry,
      _, _, _, _, _, _, _, _, _, rfl⟩ := event
    exact ⟨id, id⟩
  | complete event =>
    obtain ⟨x, assoc, receipt, _, rfl⟩ := event
    by_cases equal : aid = x
    · simp [Sys.finish, Sys.set, equal, State.leaf]
    · simp [Sys.finish, Sys.set, equal]

/-- Given All p/env/reachable s/aid, and all action data, times, flows and successors in each quantified clause.
When A registration succeeds, or a reopening succeeds.
Then Registration requires the previously absent key; reopening requires an extant parked state and active key. Both universally quantified implications remain. Same-token identity is separately checked in Registry. -/
theorem T8_mint_once (p : Params) (env : Env) {s : Sys} (h : SysReach p env s) (aid : AID) :
    (∀ refund pool0 now f st', Step p env (.register refund pool0) now (s.states aid) f st' →
      s.leaves aid = .absent) ∧
    (∀ sn' refund pool0 now f st', Step p env (.reopen sn' refund pool0) now (s.states aid) f st' →
      (∃ hs, s.states aid = .parked hs) ∧ s.leaves aid = .active) := by
  have hag := T8_leaf_agrees_with_state p env h aid
  refine ⟨fun refund pool0 now f st' hstep => ?_, fun sn' refund pool0 now f st' hstep => ?_⟩
  · generalize hst : s.states aid = st at hstep hag
    cases hstep
    simpa [State.leaf] using hag
  · generalize hst : s.states aid = st at hstep hag
    cases hstep
    exact ⟨⟨_, rfl⟩, by simpa [State.leaf] using hag⟩

/-- **T8j.** A reopen is proof-bearing: its actor is the evidence class, the
same as a freeze and a conviction — never `anyone` (D-036, D-037). -/
theorem T8_reopen_actor_is_proof (sn' : Seq) (refund : Addr) (pool0 : Value) :
    (Action.reopen sn' refund pool0).actor = .proof ∧ (Action.freeze sn' refund).actor = .proof ∧
    (Action.convict refund).actor = .proof := by
  exact ⟨rfl, rfl, rfl⟩

/-- Given Arbitrary Checkpoint parameters and environment, before/after abstract Sys and actual SysStep.
When Classify the system transition.
Then Exactly the fully defined RegistrationEvent, LocalEvent, BookingEvent or CompletionEvent holds. Local lifecycle clauses remain complete; registration binds the actual origin, booking fixes its pending association, and completion checks the stored context, history, hash, full entry, reference and alias. Full mixed Registry effects are separate from this focused Checkpoint observation. -/
theorem T8_sysstep_partition (p : Params) (env : Env) {s s' : Sys}
    (h : SysStep p env s s') :
    RegistrationEvent p env s s' ∨ LocalEvent p env s s' ∨
      BookingEvent s s' ∨ CompletionEvent s s' := by
  cases h with
  | register event => exact Or.inl event
  | «local» event => exact Or.inr (Or.inl event)
  | book event => exact Or.inr (Or.inr (Or.inl event))
  | complete event => exact Or.inr (Or.inr (Or.inr event))

/-! ## T9 — juvenility is consumer policy -/

/-- Given All Params, slots and State values.
When Evaluate the Boolean and proposition.
Then Boolean is true iff the full proposition holds, both directions; explicit parked branches remain false. -/
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

/-! ## T10 — a frozen checkpoint is inert to everyone but the next keys; a parked one holds no bonds or pool -/

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

/-- Given Every Params p and key state h; no transition or reachability hypothesis.
When Compute dregHeld, bHeld and poolHeld for parked h and convicted.
Then All six quantities are zero. This excludes neither the representative token nor retained min-ADA; no conclusion about either was in the old theorem. -/
theorem parked_and_convicted_hold_no_bonds_or_pool (p : Params) (h : Hash) :
    (State.parked h).dregHeld p = 0 ∧ (State.parked h).bHeld p = 0 ∧ (State.parked h).poolHeld = 0 ∧
    State.convicted.dregHeld p = 0 ∧ State.convicted.bHeld p = 0 ∧ State.convicted.poolHeld = 0 := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

/-! ## T12 — conviction needs a proof and is exact -/

/-- Given All arguments and the exact successful local Checkpoint conviction premise in the statement, against the actual source live or parked key state.
When Invert that local conviction into explicit terminationPending at the unchanged source key state.
Then For T12 inversions the pending target is arbitrary and must equal the actual source hash; a wrong pending-key successor is excluded by this owning equality. Every original action, addressed D/B/pool payment, concrete-context, event-validity, same-sequence and distinct-event clause in the full conclusion is preserved verbatim. The representative and generic key remain active at the combined booking boundary; no local burn or retirement is asserted. -/
theorem T12_convict_exact (p : Params) (env : Env) {a : Action} {t : Slot} {l : Live} {f : Flow} {pendingKey : Hash}
    (h : Step p env a t (.present l) f (.terminationPending pendingKey)) :
    pendingKey = l.hash ∧
    (∃ payee, a = .convict payee ∧
      f = { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
            convictor := some { addr := payee, dreg := p.D } }) ∧
    env.duplicityAt l.epoch l.sn = true := by
  cases h with
  | convict => exact ⟨rfl, ⟨_, rfl, rfl⟩, ‹_›⟩

/-- Given All arguments and the exact successful local Checkpoint conviction premise in the statement, against the actual source live or parked key state.
When Invert that local conviction into explicit terminationPending at the unchanged source key state.
Then For T12 inversions the pending target is arbitrary and must equal the actual source hash; a wrong pending-key successor is excluded by this owning equality. Every original action, addressed D/B/pool payment, concrete-context, event-validity, same-sequence and distinct-event clause in the full conclusion is preserved verbatim. The representative and generic key remain active at the combined booking boundary; no local burn or retirement is asserted. -/
theorem T12_convict_parked_exact (p : Params) (env : Env) {a : Action} {t : Slot} {hs : Hash} {f : Flow} {pendingKey : Hash}
    (h : Step p env a t (.parked hs) f (.terminationPending pendingKey)) :
    pendingKey = hs ∧
    (∃ payee, a = .convict payee) ∧ f = {} ∧ env.duplicityAt hs.epoch hs.sn = true := by
  cases h with
  | convictParked => exact ⟨rfl, ⟨_, rfl⟩, rfl, ‹_›⟩

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

/-- Given Any successful present-to-parked step, for all parameters, environment, live input, slot, flow and parked key state.
When Invert the successful close.
Then There exist sequence/payee/optional refund with exact close action; exact addressed refund and premium fields; the full paid-or-unpaid disjunction with its pool equality; exact reached epoch/sequence; strict sequence, valid rotation and signed close intent. -/
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

/-- Given Every successful close from a live input, arbitrary action data and result.
When Inspect the successful close.
Then Rotation evidence from the exact live epoch/sequence is true, its sequence strictly increases, and its actor is nextKeys. -/
theorem T16_close_needs_rotation (p : Params) (env : Env) {t : Slot} {l : Live} {f : Flow} {s' : State}
    {sn' : Seq} {payee : Addr} {r' : Option Addr} (h : Step p env (.close sn' payee r') t (.present l) f s') :
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ (Action.close sn' payee r').actor = .nextKeys := by
  cases h <;> exact ⟨‹_›, ‹_›, rfl⟩

/-- Given All p/env/t/l/f/sn′/payee/refund′/h and a successful close to parked h.
When Observe the retained key and three component payouts.
Then h equals both the rotated live hash and (epoch+1,sn′); the refund returns exactly held D and B; refund pool plus hunter pool equals input pool; parked D/B/pool each equal zero. Retention of Mc/token is an additional observation, not a removed clause. -/
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

/-- Given All close inputs and a premise that every authorized close message at the next epoch has exactly payee0 and refund0; a close step succeeds.
When Inspect its action and any hunter payment.
Then The action payee equals payee0, refund option equals refund0, and every hunter payment goes to payee0. -/
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

namespace CardanoKeri.Checkpoint

/-- Inversion for `register`: no guards. -/
theorem Step.register_iff {p : Params} {env : Env} (now : Slot) (refund : Addr) (pool0 : Value) :
    Step p env (.register refund pool0) now .absent
      { dregIn := p.D, bIn := p.B, poolIn := pool0 }
      (.present ⟨0, 0, false, false, now, refund, pool0⟩) ↔ True := by
  constructor
  · intro _; trivial
  · intro _; exact Step.register now refund pool0

/-- Inversion for `rotateKeepPaid`. -/
theorem Step.rotateKeepPaid_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr) :
    Step p env (.rotate sn' .keep payee refund') now (.present l)
      { hunter := some { addr := payee, pool := p.P } }
      (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                         refundTo := refund'.getD l.refundTo, pool := l.pool - p.P }) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
    env.intentOk (l.epoch + 1) .keep refund' = true ∧ p.P ≤ l.pool := by
  constructor
  · intro h
    cases h with
    | rotateKeepPaid _ _ _ _ hev hsn hauth hpay => exact ⟨hev, hsn, hauth, hpay⟩
  · rintro ⟨hev, hsn, hauth, hpay⟩
    exact Step.rotateKeepPaid now sn' payee refund' hev hsn hauth hpay

/-- Inversion for `rotateKeepUnpaid`. -/
theorem Step.rotateKeepUnpaid_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr) :
    Step p env (.rotate sn' .keep payee refund') now (.present l) {}
      (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                         refundTo := refund'.getD l.refundTo }) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
    env.intentOk (l.epoch + 1) .keep refund' = true ∧ l.pool < p.P := by
  constructor
  · intro h
    cases h with
    | rotateKeepUnpaid _ _ _ _ hev hsn hauth hnopay => exact ⟨hev, hsn, hauth, hnopay⟩
  · rintro ⟨hev, hsn, hauth, hnopay⟩
    exact Step.rotateKeepUnpaid now sn' payee refund' hev hsn hauth hnopay

/-- Inversion for `rotateDepositPaid`. -/
theorem Step.rotateDepositPaid_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr) :
    Step p env (.rotate sn' .deposit payee refund') now (.present l)
      { bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } }
      (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                         frozen := false, refundTo := refund'.getD l.refundTo,
                         pool := l.pool - p.P }) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
    env.intentOk (l.epoch + 1) .deposit refund' = true ∧ p.P ≤ l.pool := by
  constructor
  · intro h
    cases h with
    | rotateDepositPaid _ _ _ _ hev hsn hauth hpay => exact ⟨hev, hsn, hauth, hpay⟩
  · rintro ⟨hev, hsn, hauth, hpay⟩
    exact Step.rotateDepositPaid now sn' payee refund' hev hsn hauth hpay

/-- Inversion for `rotateDepositUnpaid`. -/
theorem Step.rotateDepositUnpaid_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr) :
    Step p env (.rotate sn' .deposit payee refund') now (.present l)
      { bIn := p.B - l.bHeld p }
      (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                         frozen := false, refundTo := refund'.getD l.refundTo }) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
    env.intentOk (l.epoch + 1) .deposit refund' = true ∧ l.pool < p.P := by
  constructor
  · intro h
    cases h with
    | rotateDepositUnpaid _ _ _ _ hev hsn hauth hnopay => exact ⟨hev, hsn, hauth, hnopay⟩
  · rintro ⟨hev, hsn, hauth, hnopay⟩
    exact Step.rotateDepositUnpaid now sn' payee refund' hev hsn hauth hnopay

/-- Inversion for `poison`. -/
theorem Step.poison_iff {p : Params} {env : Env} (l : Live) (now : Slot) :
    Step p env .poison now (.present l) {} (.present { l with poisoned := true }) ↔
    env.quorum l.epoch = true ∧ l.poisoned = false := by
  constructor
  · intro h
    cases h with
    | poison _ hq hclean => exact ⟨hq, hclean⟩
  · rintro ⟨hq, hclean⟩
    exact Step.poison now hq hclean

/-- Inversion for `freeze`. -/
theorem Step.freeze_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq) (payee : Addr) :
    Step p env (.freeze sn' payee) now (.present l)
      { hunter := some { addr := payee, b := p.B } }
      (.present { l with frozen := true }) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ l.pool < p.P ∧
    l.frozen = false ∧ l.poisoned = false := by
  constructor
  · intro h
    cases h with
    | freeze _ _ _ hev hsn hpool hb hclean => exact ⟨hev, hsn, hpool, hb, hclean⟩
  · rintro ⟨hev, hsn, hpool, hb, hclean⟩
    exact Step.freeze now sn' payee hev hsn hpool hb hclean

/-- Inversion for `topUp`: no guards. -/
theorem Step.topUp_iff {p : Params} {env : Env} (l : Live) (now : Slot) (x : Value) :
    Step p env (.topUp x) now (.present l) { poolIn := x }
      (.present { l with pool := l.pool + x }) ↔ True := by
  constructor
  · intro _; trivial
  · intro _; exact Step.topUp now x

/-- Given Every parameter, slot, source state and payee in the exact type; the enabled statements additionally assume concrete duplicity at that source state.
When Execute the local conviction transition, or compare it to its complete guard in the iff statements.
Then The exact existing component flow and concrete duplicity guard remain; the target is pending at the source hash. Both iff directions remain obligations. Enabled clauses are local applicability only, not a claim that an arbitrary economic request can be booked. -/
theorem Step.convict_iff {p : Params} {env : Env} (l : Live) (now : Slot) (payee : Addr) :
    Step p env (.convict payee) now (.present l)
      { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
        convictor := some { addr := payee, dreg := p.D } } (.terminationPending l.hash) ↔
    env.duplicityAt l.epoch l.sn = true := by
  constructor
  · intro h
    cases h with
    | convict _ _ hdup => exact hdup
  · intro hdup
    exact Step.convict now payee hdup

/-- Given Every parameter, slot, source state and payee in the exact type; the enabled statements additionally assume concrete duplicity at that source state.
When Execute the local conviction transition, or compare it to its complete guard in the iff statements.
Then The exact existing component flow and concrete duplicity guard remain; the target is pending at the source hash. Both iff directions remain obligations. Enabled clauses are local applicability only, not a claim that an arbitrary economic request can be booked. -/
theorem Step.convictParked_iff {p : Params} {env : Env} (h : Hash) (now : Slot) (payee : Addr) :
    Step p env (.convict payee) now (.parked h) {} (.terminationPending h) ↔
    env.duplicityAt h.epoch h.sn = true := by
  constructor
  · intro hStep
    cases hStep with
    | convictParked _ _ hdup => exact hdup
  · intro hdup
    exact Step.convictParked now payee hdup

/-- Given All typed parameters in the exact statement below. The left-hand flow and successor are fully fixed, not existential approximations.
When Compare the precisely addressed Step against its evidence and arithmetic guards.
Then Both implication directions and every fixed state/flow field remain exactly as in the copied full type. Parked now denotes a retained output; local active-key and token assertions are added separately. -/
theorem Step.closePaid_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr) :
    Step p env (.close sn' payee refund') now (.present l)
      { refund := some { addr := refund'.getD l.refundTo, dreg := p.D,
                         b := l.bHeld p, pool := l.pool - p.P },
        hunter := some { addr := payee, pool := p.P } }
      (.parked ⟨l.epoch + 1, sn'⟩) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
    env.intentOk (l.epoch + 1) (.close payee) refund' = true ∧ p.P ≤ l.pool := by
  constructor
  · intro h
    have hc := T16_close_destination p env h
    obtain ⟨sn0, pay0, r0, ha, _, hdisj, _, hlt, hev0, hauth0⟩ := hc
    cases ha
    cases hdisj with
    | inl hpaid =>
      obtain ⟨hpay, _, _⟩ := hpaid
      exact ⟨hev0, hlt, hauth0, hpay⟩
    | inr hunpaid =>
      obtain ⟨_, hnone, _⟩ := hunpaid
      cases hnone
  · rintro ⟨hev, hsn, hauth, hpay⟩
    exact Step.closePaid now sn' payee refund' hev hsn hauth hpay

/-- Given All typed parameters in the exact statement below. The left-hand flow and successor are fully fixed, not existential approximations.
When Compare the precisely addressed Step against its evidence and arithmetic guards.
Then Both implication directions and every fixed state/flow field remain exactly as in the copied full type. Parked now denotes a retained output; local active-key and token assertions are added separately. -/
theorem Step.closeUnpaid_iff {p : Params} {env : Env} (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr) :
    Step p env (.close sn' payee refund') now (.present l)
      { refund := some { addr := refund'.getD l.refundTo, dreg := p.D,
                         b := l.bHeld p, pool := l.pool } }
      (.parked ⟨l.epoch + 1, sn'⟩) ↔
    env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
    env.intentOk (l.epoch + 1) (.close payee) refund' = true ∧ l.pool < p.P := by
  constructor
  · intro h
    have hc := T16_close_destination p env h
    obtain ⟨sn0, pay0, r0, ha, _, hdisj, _, hlt, hev0, hauth0⟩ := hc
    cases ha
    cases hdisj with
    | inl hpaid =>
      obtain ⟨_, hsome, _⟩ := hpaid
      cases hsome
    | inr hunpaid =>
      obtain ⟨hnopay, _, _⟩ := hunpaid
      exact ⟨hev0, hlt, hauth0, hnopay⟩
  · rintro ⟨hev, hsn, hauth, hnopay⟩
    exact Step.closeUnpaid now sn' payee refund' hev hsn hauth hnopay

/-- Given All typed parameters in the exact statement below. The left-hand flow and successor are fully fixed, not existential approximations.
When Compare the precisely addressed Step against its evidence and arithmetic guards.
Then Both implication directions and every fixed state/flow field remain exactly as in the copied full type. Parked now denotes a retained output; local active-key and token assertions are added separately. -/
theorem Step.reopen_iff {p : Params} {env : Env} (h : Hash) (now : Slot) (sn' : Seq)
    (refund : Addr) (pool0 : Value) :
    Step p env (.reopen sn' refund pool0) now (.parked h)
      { dregIn := p.D, bIn := p.B, poolIn := pool0 }
      (.present ⟨sn', h.epoch + 1, false, false, now, refund, pool0⟩) ↔
    env.rotationTo h.epoch h.sn sn' = true ∧ h.sn < sn' := by
  constructor
  · intro hStep
    cases hStep with
    | reopen _ _ _ _ hev hsn => exact ⟨hev, hsn⟩
  · rintro ⟨hev, hsn⟩
    exact Step.reopen now sn' refund pool0 hev hsn

end CardanoKeri.Checkpoint

open Lean Elab Command
open CardanoKeri.Checkpoint

/- Coverage (S363-1 RED): denominator from the compiled `Step` inductive;
   one public `Step.<ctor>_iff` per constructor. Exact-type `#check`s below
   validate binding, premises, and effects; they fail with the missing
   inversions until T363-003 lands. -/
run_cmd do
  let env ← getEnv
  let some (.inductInfo info) := env.find? ``CardanoKeri.Checkpoint.Step
    | throwError "checkpoint-inversions: compiled Step inductive missing"
  if info.ctors.isEmpty then
    throwError "checkpoint-inversions: empty Step constructor denominator"
  let mut numerator := 0
  for ctor in info.ctors do
    match ctor with
    | .str pre short =>
      let inv := Name.str pre (short ++ "_iff")
      match env.find? inv with
      | some (.thmInfo _) =>
          numerator := numerator + 1
          logInfo m!"checkpoint-inversion-row constructor={ctor} inversion={inv}"
      | some _ => throwError m!"checkpoint-inversions: expected theorem is not a theorem: {inv}"
      | none => throwError m!"checkpoint-inversions: missing public inversion {inv} for {ctor}"
    | _ => throwError m!"checkpoint-inversions: constructor has no string component: {ctor}"
  if numerator != info.ctors.length then
    throwError m!"checkpoint-inversions: numerator={numerator} denominator={info.ctors.length}"
  logInfo m!"checkpoint-inversions: coverage={numerator}/{info.ctors.length}"

section CheckpointInversionExactTypes

variable (p : Params) (env : Env)

#check (Step.register_iff : ∀ (now : Slot) (refund : Addr) (pool0 : Value),
  Step p env (.register refund pool0) now .absent
    { dregIn := p.D, bIn := p.B, poolIn := pool0 }
    (.present ⟨0, 0, false, false, now, refund, pool0⟩) ↔ True)

#check (Step.rotateKeepPaid_iff : ∀ (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr),
  Step p env (.rotate sn' .keep payee refund') now (.present l)
    { hunter := some { addr := payee, pool := p.P } }
    (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                       refundTo := refund'.getD l.refundTo, pool := l.pool - p.P }) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
  env.intentOk (l.epoch + 1) .keep refund' = true ∧ p.P ≤ l.pool)

#check (Step.rotateKeepUnpaid_iff : ∀ (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr),
  Step p env (.rotate sn' .keep payee refund') now (.present l) {}
    (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                       refundTo := refund'.getD l.refundTo }) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
  env.intentOk (l.epoch + 1) .keep refund' = true ∧ l.pool < p.P)

#check (Step.rotateDepositPaid_iff : ∀ (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr),
  Step p env (.rotate sn' .deposit payee refund') now (.present l)
    { bIn := p.B - l.bHeld p, hunter := some { addr := payee, pool := p.P } }
    (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                       frozen := false, refundTo := refund'.getD l.refundTo,
                       pool := l.pool - p.P }) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
  env.intentOk (l.epoch + 1) .deposit refund' = true ∧ p.P ≤ l.pool)

#check (Step.rotateDepositUnpaid_iff : ∀ (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr),
  Step p env (.rotate sn' .deposit payee refund') now (.present l)
    { bIn := p.B - l.bHeld p }
    (.present { l with sn := sn', epoch := l.epoch + 1, poisoned := false,
                       frozen := false, refundTo := refund'.getD l.refundTo }) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
  env.intentOk (l.epoch + 1) .deposit refund' = true ∧ l.pool < p.P)

#check (Step.poison_iff : ∀ (l : Live) (now : Slot),
  Step p env .poison now (.present l) {} (.present { l with poisoned := true }) ↔
  env.quorum l.epoch = true ∧ l.poisoned = false)

#check (Step.freeze_iff : ∀ (l : Live) (now : Slot) (sn' : Seq) (payee : Addr),
  Step p env (.freeze sn' payee) now (.present l)
    { hunter := some { addr := payee, b := p.B } }
    (.present { l with frozen := true }) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ l.pool < p.P ∧
  l.frozen = false ∧ l.poisoned = false)

#check (Step.topUp_iff : ∀ (l : Live) (now : Slot) (x : Value),
  Step p env (.topUp x) now (.present l) { poolIn := x }
    (.present { l with pool := l.pool + x }) ↔ True)

#check (Step.convict_iff : ∀ (l : Live) (now : Slot) (payee : Addr),
  Step p env (.convict payee) now (.present l)
    { refund := some { addr := l.refundTo, b := l.bHeld p, pool := l.pool },
      convictor := some { addr := payee, dreg := p.D } } (.terminationPending l.hash) ↔
  env.duplicityAt l.epoch l.sn = true)

#check (Step.convictParked_iff : ∀ (h : Hash) (now : Slot) (payee : Addr),
  Step p env (.convict payee) now (.parked h) {} (.terminationPending h) ↔
  env.duplicityAt h.epoch h.sn = true)

#check (Step.closePaid_iff : ∀ (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr),
  Step p env (.close sn' payee refund') now (.present l)
    { refund := some { addr := refund'.getD l.refundTo, dreg := p.D,
                       b := l.bHeld p, pool := l.pool - p.P },
      hunter := some { addr := payee, pool := p.P } }
    (.parked ⟨l.epoch + 1, sn'⟩) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
  env.intentOk (l.epoch + 1) (.close payee) refund' = true ∧ p.P ≤ l.pool)

#check (Step.closeUnpaid_iff : ∀ (l : Live) (now : Slot) (sn' : Seq)
    (payee : Addr) (refund' : Option Addr),
  Step p env (.close sn' payee refund') now (.present l)
    { refund := some { addr := refund'.getD l.refundTo, dreg := p.D,
                       b := l.bHeld p, pool := l.pool } }
    (.parked ⟨l.epoch + 1, sn'⟩) ↔
  env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧
  env.intentOk (l.epoch + 1) (.close payee) refund' = true ∧ l.pool < p.P)

#check (Step.reopen_iff : ∀ (h : Hash) (now : Slot) (sn' : Seq)
    (refund : Addr) (pool0 : Value),
  Step p env (.reopen sn' refund pool0) now (.parked h)
    { dregIn := p.D, bIn := p.B, poolIn := pool0 }
    (.present ⟨sn', h.epoch + 1, false, false, now, refund, pool0⟩) ↔
  env.rotationTo h.epoch h.sn sn' = true ∧ h.sn < sn')

end CheckpointInversionExactTypes
