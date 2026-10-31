import CardanoKeri.ConsumerGoals

/-! The value clause at the consumer and at registration: a holding's datum facts
and its lovelace determine the checkpoint state, a holding short of the deposit or
freeze bond its datum says are held realizes no state, and a registration carrier
short of the minimum ADA, the deposit and the freeze bond is refused. -/
namespace CardanoKeri.ConsumerIdentity
open CardanoKeri.Checkpoint

/-- Given any parameters and state.
When the value floor of its datum facts is computed.
Then it is the floor of the state itself: the floor reads no pool. -/
theorem valueFloor_datumFacts (p : Params) (rp : CardanoKeri.Registry.Params) (s : State) :
    s.datumFacts.valueFloor p rp = s.valueFloor p rp := by
  cases s <;> simp [State.datumFacts, State.valueFloor, Live.bHeld]

/-- Given any parameters and a state with an output.
When its held lovelace is compared with its value floor.
Then the floor is never above what the state holds. -/
theorem valueFloor_le_heldValue (p : Params) (rp : CardanoKeri.Registry.Params) (s : State) :
    s.valueFloor p rp ≤ s.heldValue p rp := by
  cases s <;> simp [State.valueFloor, State.heldValue, State.hasOutput, State.heldAmounts,
    State.dregHeld, State.bHeld, State.poolHeld] <;> omega'

/-- Given any interpretation, context and parameters, and one holding that realizes
two states.
When the two states are compared.
Then they are the same state, pool included: the datum's facts and the holding's
lovelace determine the full state. -/
theorem realizes_determines_state (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) {s s' : State} {o : AH.ObservedOutput}
    (h : realizesState i c p rp s o) (h' : realizesState i c p rp s' o) : s = s' := by
  obtain ⟨_, _, datum, value⟩ := h
  obtain ⟨_, _, datum', value'⟩ := h'
  have facts : s.datumFacts = s'.datumFacts := by
    have := datum.symm.trans datum'
    simpa using this
  have held : s.heldValue p rp = s'.heldValue p rp := value.symm.trans value'
  have output : ∀ x : State, x.datumFacts.hasOutput = x.hasOutput := by
    intro x; cases x <;> rfl
  by_cases hs : s.hasOutput = true
  · have hs' : s'.hasOutput = true := by rw [← output s', ← facts, output s]; exact hs
    have back := withValue_heldValue p rp s hs
    rw [facts, held, withValue_heldValue p rp s' hs'] at back
    exact (Option.some.inj back).symm
  · have keep : ∀ x : State, x.hasOutput = false → x.datumFacts = x := by
      intro x hx; cases x <;> simp_all [State.hasOutput, State.datumFacts]
    have hs' : s'.hasOutput = false := by
      rw [← output s', ← facts, output s]; simpa using hs
    rw [← keep s (by simpa using hs), ← keep s' hs', facts]

/-- Given any interpretation, context and parameters, and a holding whose lovelace
is below the floor of a state: the minimum ADA plus the deposit plus the freeze
bond a live state's datum says is held, or the minimum ADA of a pending one.
When it is checked against that state.
Then it does not realize it, whatever its pool: a holding missing part of a bond
is refused. -/
theorem short_holding_refused (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (s : State) (o : AH.ObservedOutput)
    (short : o.lovelace < s.valueFloor p rp) : ¬ realizesState i c p rp s o := by
  rintro ⟨_, _, _, value⟩
  have := valueFloor_le_heldValue p rp s
  omega'

/-- Given a live unfrozen checkpoint and a holding one lovelace short of what it
holds with an empty pool.
When the holding is checked against every live state with the same datum facts.
Then none is realized: the freeze bond, or the deposit, is short by one. -/
theorem missing_bond_lovelace_refused (i : Interpretation) (c : Context) (p : Params)
    (rp : CardanoKeri.Registry.Params) (l : Live) (o : AH.ObservedOutput)
    (unfrozen : l.frozen = false) (short : o.lovelace + 1 = rp.Mc + p.D + p.B) (pool : Value) :
    ¬ realizesState i c p rp (.present { l with pool := pool }) o := by
  apply short_holding_refused
  simp [State.valueFloor, Live.bHeld, unfrozen]
  omega'

/-- Given any registry parameters and a registration booking whose declared carrier
is one lovelace short of the minimum ADA plus the deposit and freeze bond.
When the registry books it.
Then the booking is refused for its value. -/
theorem short_carrier_registration_refused (rp : CardanoKeri.Registry.Params)
    (s : CardanoKeri.Registry.Sys) (b : Singular.RegistrationBooking)
    (short : b.request.carrierAda + 1 = rp.Mc + rp.D) :
    CardanoKeri.Registry.bookRegistration rp s b = .error "keri-registration-value-mismatch" := by
  have refused : ¬ CardanoKeri.Registry.registrationShape rp b := by
    rintro ⟨carrier, _⟩; omega
  simp [CardanoKeri.Registry.bookRegistration, refused, bind, Except.bind]

/-- Given a successful joint registration.
When its parameters, declared carrier, registered checkpoint and holding are compared.
Then the registry's deposit is the checkpoint's deposit plus freeze bond; the carrier
is the minimum ADA plus the deposit, the freeze bond and the chosen initial pool; and
the delivered holding holds exactly that. -/
theorem registerJoint_value (i : Interpretation) (c : Context)
    (abstractRegistry : Singular.TokenId → Nat) (commit : SingularApplicationHeld.TrieCommit)
    (q : RegistrationInput) (r : Registered)
    (accepted : registerJoint i c abstractRegistry commit q = .ok r) :
    q.registryParams.D = q.checkpointParams.D + q.checkpointParams.B ∧
    q.booking.request.carrierAda =
      q.registryParams.Mc + q.checkpointParams.D + q.checkpointParams.B + q.pool ∧
    r.holding.lovelace = q.booking.request.carrierAda := by
  have sound := registerJoint_sound i c abstractRegistry commit q r accepted
  have agreement := sound.2.2.2.2.2.1
  have registration := sound.2.2.2.2.1
  simp only [registrationAgreementB, Bool.and_eq_true, and_assoc] at agreement
  rcases agreement with ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, relation, carrier, _, holding, _⟩
  have step := registration_holds_carrier q.checkpointParams q.registryParams q.checkpointEnv
    ((T7_step_iff_stepFn _ _).mpr registration)
  refine ⟨by simpa using relation, ?_, by simpa using holding⟩
  rw [beq_iff_eq.mp carrier, step.1]

end CardanoKeri.ConsumerIdentity
