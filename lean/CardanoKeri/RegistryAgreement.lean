import CardanoKeri.RegistryCompleteness

/-!
# Executable registry actions and their relation

The relation retains every action's actual execution result. Local
conviction retains the carrier; only an accepted imported termination fold
retires the registry key. Whole pending custody and refusal laws live in
RegistryCustody and RegistryReach.
-/

namespace CardanoKeri.Registry.Agreement

/-- Given a list without an identifier, when removing that identifier, then
all entries and their order remain unchanged. -/
theorem remove_absent {α : Type} {rs : List (Nat × α)} {id : Nat}
    (h : id ∉ rs.map (·.1)) : remove rs id = rs := by
  induction rs with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨j, r'⟩ := x
    have hj : j ≠ id := fun e => h (List.mem_map.2 ⟨(j, r'), List.mem_cons.2 (Or.inl rfl), e⟩)
    simp only [remove, if_neg hj]
    rw [ih (fun hm => h (List.mem_cons.2 (Or.inr hm)))]


/-- Each constructor records the full successful result of its action. -/
inductive Step (p : Params) (env : Env) : Action → Sys → Flow → Sys → Prop where
  | bookRegistration {s s' f b} : bookRegistration p s b = .ok (f, s') →
      Step p env (.bookRegistration b) s f s'
  | convict {s s' f aid} : convictCkpt env s aid = .ok (f, s') →
      Step p env (.convictCkpt aid) s f s'
  | bookTermination {s s' f aid booker fee b} :
      bookTermination p s aid booker fee b = .ok (f, s') →
      Step p env (.bookTermination aid booker fee b) s f s'
  | fold {s s' f gen plugin u tx} : fold p env s gen plugin u tx = .ok (f, s') →
      Step p env (.fold gen plugin u tx) s f s'
  | retract {s s' f u tx} : genericRetraction s u tx = .ok (f, s') →
      Step p env (.genericRetraction u tx) s f s'
  | reject {s s' f u tx} : genericRejection s u tx = .ok (f, s') →
      Step p env (.genericRejection u tx) s f s'

/-- Given any action, state, and complete result, when executing the action,
then success is equivalent to its relational constructor with that result.
This relation introduces no alternate interpreter or acceptance premise. -/
theorem step_iff (p : Params) (env : Env) (a : Action) (s s' : Sys) (f : Flow) :
    stepFn p env a s = .ok (f, s') ↔ Step p env a s f s' := by
  constructor
  · intro h
    cases a with
    | bookRegistration b => exact .bookRegistration h
    | convictCkpt aid => exact .convict h
    | bookTermination aid booker fee b => exact .bookTermination h
    | fold gen plugin u tx => exact .fold h
    | genericRetraction u tx => exact .retract h
    | genericRejection u tx => exact .reject h
  · intro h
    cases h <;> assumption

end CardanoKeri.Registry.Agreement
