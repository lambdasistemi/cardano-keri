import CardanoKeri.CheckpointGoals

/-! The amounts a checkpoint output holds: the deposit, the freeze bond and the
premium pool. The datum carries none of them (`State.datumFacts`); they are held
in the output's value. -/
namespace CardanoKeri.Checkpoint

/-- The deposit, freeze bond and pool a checkpoint in state `s` holds. -/
def State.heldAmounts (p : Params) (s : State) : Value :=
  s.dregHeld p + s.bHeld p + s.poolHeld

/-- The facts a checkpoint datum carries about a state. The premium pool is an
amount held in the output's value, not a datum fact, so it is set to zero; the
value clause of `ConsumerIdentity.realizesState` reads the amounts from the value. -/
def State.datumFacts : State → State
  | .present l => .present { l with pool := 0 }
  | s => s

/-- What one payment carries, all three components together. -/
def Payment?.total (q : Option Payment) : Value :=
  Payment?.dreg q + Payment?.b q + Payment?.pool q

/-- What a step takes into the checkpoint output. -/
def Flow.takenIn (f : Flow) : Value := f.dregIn + f.bIn + f.poolIn

/-- What a step pays out of the checkpoint output, to the refund address, the
hunter and the convictor. -/
def Flow.paidOut (f : Flow) : Value :=
  Payment?.total f.refund + Payment?.total f.hunter + Payment?.total f.convictor

/-- Given any parameters and a live checkpoint.
When its held amounts are computed.
Then it holds the deposit, the freeze bond unless frozen, and its pool. -/
theorem present_held_amounts (p : Params) (l : Live) :
    (State.present l).heldAmounts p = p.D + (if l.frozen then 0 else p.B) + l.pool := rfl

/-- Given any parameters and key state.
When the held amounts of a pending termination, an absent and a convicted
checkpoint are computed.
Then all three hold none of the deposit, the freeze bond or the pool. -/
theorem no_amounts_without_live_checkpoint (p : Params) (h : Hash) :
    (State.terminationPending h).heldAmounts p = 0 ∧
    State.absent.heldAmounts p = 0 ∧ State.convicted.heldAmounts p = 0 := ⟨rfl, rfl, rfl⟩

/-- Given every successful step over arbitrary parameters, environment, action,
time and states.
When the held amounts before and after and the step's flow are compared.
Then what the input holds plus what the step takes in equals what the output
holds plus what the step pays out. -/
theorem held_amounts_conserved (p : Params) (env : Env) {a : Action} {t : Slot}
    {s s' : State} {f : Flow} (h : Step p env a t s f s') :
    s.heldAmounts p + f.takenIn = s'.heldAmounts p + f.paidOut := by
  obtain ⟨hd, hb, hp⟩ := T6_component_conservation p env h
  simp only [State.heldAmounts, Flow.takenIn, Flow.paidOut, Payment?.total]
  omega'

/-- Given a live checkpoint convicted to its pending termination.
When the step's payments are compared with what the live checkpoint held.
Then the convictor receives exactly the deposit, the refund address exactly the
freeze bond held and the pool, and the pending output keeps none of them. -/
theorem conviction_pays_out_every_amount (p : Params) (env : Env) {t : Slot} {l : Live}
    {payee : Addr} {f : Flow} {s' : State} (h : Step p env (.convict payee) t (.present l) f s') :
    Payment?.total f.convictor = p.D ∧
    Payment?.total f.refund = l.bHeld p + l.pool ∧
    Payment?.total f.hunter = 0 ∧
    s'.heldAmounts p = 0 ∧
    f.paidOut = (State.present l).heldAmounts p := by
  cases h
  simp [Payment?.total, Payment?.dreg, Payment?.b, Payment?.pool, State.heldAmounts,
    State.dregHeld, State.bHeld, State.poolHeld, Flow.paidOut]
  omega'

/-! The lovelace a checkpoint output holds. Its minimum ADA is the registry's
carrier minimum `Mc`, separate from the deposit: the registration carrier
delivers it and the termination booking consumes it (`Registry.bookTermination`
requires `minAda = Mc`). -/

/-- The lovelace a checkpoint output in state `s` holds: the registry's minimum
ADA while the output exists, plus the deposit, the freeze bond and the pool. -/
def State.heldValue (p : Params) (rp : CardanoKeri.Registry.Params) (s : State) : Value :=
  (if s.hasOutput then rp.Mc else 0) + s.heldAmounts p

/-- The amount below which a holding with these datum facts cannot hold the
deposit and freeze bond its state says it holds. -/
def State.valueFloor (p : Params) (rp : CardanoKeri.Registry.Params) : State → Value
  | .present l => rp.Mc + p.D + l.bHeld p
  | .terminationPending _ => rp.Mc
  | .absent | .convicted => 0

/-- The state a holding's datum facts and its lovelace determine: a live
checkpoint's pool is what the value holds above its floor; a pending
termination holds exactly the minimum ADA. -/
def State.withValue (p : Params) (rp : CardanoKeri.Registry.Params) (s : State)
    (lovelace : Value) : Option State :=
  match s with
  | .present l =>
      if s.valueFloor p rp ≤ lovelace then
        some (.present { l with pool := lovelace - s.valueFloor p rp })
      else none
  | .terminationPending _ => if lovelace = rp.Mc then some s else none
  | .absent | .convicted => none

/-- Given any parameters and a live checkpoint.
When the lovelace its output holds is computed.
Then it is the minimum ADA, the deposit, the freeze bond unless frozen, and the pool. -/
theorem present_held_value (p : Params) (rp : CardanoKeri.Registry.Params) (l : Live) :
    (State.present l).heldValue p rp = rp.Mc + p.D + (if l.frozen then 0 else p.B) + l.pool := by
  simp only [State.heldValue, State.hasOutput, if_true, present_held_amounts]
  omega'

/-- Given any parameters and key state.
When the lovelace of a pending termination output is computed.
Then it is exactly the registry's minimum ADA, the amount the termination booking
requires of the pending carrier; absent and convicted checkpoints have no output
and hold nothing. -/
theorem pending_holds_minimum_ada (p : Params) (rp : CardanoKeri.Registry.Params) (h : Hash) :
    (State.terminationPending h).heldValue p rp = rp.Mc ∧
    State.absent.heldValue p rp = 0 ∧ State.convicted.heldValue p rp = 0 := by
  simp [State.heldValue, State.hasOutput, State.heldAmounts, State.dregHeld, State.bHeld,
    State.poolHeld]

/-- Given a registration step with any refund address and initial pool.
When the lovelace of the registered output is computed.
Then it is the minimum ADA plus everything the step takes in: the deposit, the
freeze bond and the initial pool. -/
theorem registration_holds_carrier (p : Params) (rp : CardanoKeri.Registry.Params) (env : Env)
    {t : Slot} {refund : Addr} {pool0 : Value} {s : State} {f : Flow} {s' : State}
    (h : Step p env (.register refund pool0) t s f s') :
    s'.heldValue p rp = rp.Mc + p.D + p.B + pool0 ∧ s'.heldValue p rp = rp.Mc + f.takenIn := by
  cases h
  simp [State.heldValue, State.hasOutput, State.heldAmounts, State.dregHeld, State.bHeld,
    State.poolHeld, Live.bHeld, Flow.takenIn]
  omega'

/-- Given every successful step from a state that has an output (every step
except registration) over arbitrary parameters, environment, action and time.
When the lovelace before and after and the step's flow are compared.
Then what the input holds plus what the step takes in equals what the output
holds plus what the step pays out; the minimum ADA stays in the output. -/
theorem held_value_conserved (p : Params) (rp : CardanoKeri.Registry.Params) (env : Env)
    {a : Action} {t : Slot} {s s' : State} {f : Flow} (h : Step p env a t s f s')
    (output : s.hasOutput = true) :
    s.heldValue p rp + f.takenIn = s'.heldValue p rp + f.paidOut := by
  have amounts := held_amounts_conserved p env h
  have kept : s'.hasOutput = true := by cases h <;> simp_all [State.hasOutput]
  simp only [State.heldValue, output, kept, if_true]
  omega'

/-- Given any parameters and a state with an output.
When its datum facts are paired with the lovelace it holds.
Then they determine the state again, pool included. -/
theorem withValue_heldValue (p : Params) (rp : CardanoKeri.Registry.Params) (s : State)
    (output : s.hasOutput = true) :
    s.datumFacts.withValue p rp (s.heldValue p rp) = some s := by
  cases s with
  | absent | convicted => simp [State.hasOutput] at output
  | terminationPending h => simp [State.datumFacts, State.withValue, State.heldValue, State.hasOutput,
      State.heldAmounts, State.dregHeld, State.bHeld, State.poolHeld]
  | present l =>
    have floor : (State.present l).heldValue p rp = (State.present { l with pool := 0 }).valueFloor p rp + l.pool := by
      simp only [State.heldValue, State.hasOutput, if_true, State.heldAmounts, State.dregHeld,
        State.bHeld, State.poolHeld, State.valueFloor, Live.bHeld]
      omega'
    simp only [State.datumFacts, State.withValue, floor]
    simp

/-- Given any parameters, a state with an output and any lovelace.
When the state's datum facts are read together with that lovelace.
Then they give back exactly that state if and only if the lovelace is what the
state holds: the reading the vectors execute is the value clause. -/
theorem withValue_iff (p : Params) (rp : CardanoKeri.Registry.Params) (s : State)
    (output : s.hasOutput = true) (v : Value) :
    s.datumFacts.withValue p rp v = some s ↔ v = s.heldValue p rp := by
  constructor
  · intro h
    cases s with
    | absent | convicted => simp [State.hasOutput] at output
    | terminationPending k =>
      simp only [State.datumFacts, State.withValue] at h
      split at h
      · rename_i hv; simp [hv, State.heldValue, State.hasOutput, State.heldAmounts,
          State.dregHeld, State.bHeld, State.poolHeld]
      · simp at h
    | present l =>
      simp only [State.datumFacts, State.withValue] at h
      split at h
      · rename_i hv
        simp only [Option.some.injEq, State.present.injEq] at h
        have pool : v - (State.present { l with pool := 0 }).valueFloor p rp = l.pool := by
          rw [← h]
        simp only [State.valueFloor, Live.bHeld] at hv pool
        simp only [State.heldValue, State.hasOutput, if_true, State.heldAmounts, State.dregHeld,
          State.bHeld, State.poolHeld, Live.bHeld]
        omega'
      · simp at h
  · rintro rfl; exact withValue_heldValue p rp s output

end CardanoKeri.Checkpoint
