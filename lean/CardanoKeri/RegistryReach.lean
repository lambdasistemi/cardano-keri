import CardanoKeri.RegistryFold

/-! Whole application invariants along the actual transition history. -/
namespace CardanoKeri.Registry

/-- Given the whole WellFormed predicate, including the explicit bindingDomain
clause, when an arbitrary adapter step succeeds, then the
entire invariant persists. Reachable initial/step history supplies this
predicate and the explicit domain iff; generic reachability alone does not
prove anything about alias bindings. The empty-world/phantom-alias
fixture must fail bindingDomain, while a genuine fresh registration succeeds.
No policy rejects legitimate registration merely to avoid that missing proof.

Given an actual pending lookup in a reachable system, a successful arbitrary
competing action, and absence of consumption of its exact reference; when
observing its successor; then the complete old record, token binding, active
leaf and supply remain. This covers local steps, booking in either store,
generic recovery and mixed fold. No obsolete now<far premise is imported.
These are the successors to Agreement's
custody and refusal obligations, not merely names for the old go-request. -/
theorem wellFormed_step (p : Params) (env : Env) {s s' : Sys}
    (hw : WellFormed p s) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) : WellFormed p s' := by
  cases action with
  | bookRegistration b => exact wellFormed_bookRegistration p hw hs
  | convictCkpt aid =>
    obtain ⟨c, _, _, _, _, rfl⟩ := (convictCkpt_iff env s s' aid f).mp hs
    apply wellFormed_carrier_edit p hw
    intro old
    split <;> exact ⟨rfl, rfl, rfl, rfl⟩
  | bookTermination aid booker fee b => exact wellFormed_bookTermination p hw hs
  | fold gen plugin u tx => exact wellFormed_fold p env hw hs
  | genericRetraction u tx =>
    change genericRetraction s u tx = .ok (f, s') at hs
    unfold genericRetraction at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i world executed
      split at hs
      · contradiction
      · rename_i after reconstructed
        cases hs
        exact wellFormed_recover p hw (.retraction hw.worldReachable u tx executed) reconstructed
  | genericRejection u tx =>
    change genericRejection s u tx = .ok (f, s') at hs
    unfold genericRejection at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i world executed
      split at hs
      · contradiction
      · rename_i after reconstructed
        cases hs
        exact wellFormed_recover p hw (.rejection hw.worldReachable u tx executed) reconstructed

/-- Given any Sys for projection, or a Reach derivation from actual init/stepFn
for the latter two; when observing the entire current system; then every
projected field is the actual stored field, the complete named WellFormed
predicate holds, and active means exactly one custody location in both
directions. Prebooking terminationPending carriers count as carriers. No
ignored extra holding, duplicate pending record or free parallel World is
allowed. Required trace contains two registrations and two convictions,
books one while leaving the other carrier pending, then books the second. -/
theorem reachable_wellFormed (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (h : Reach p env cfg s) : WellFormed p s := by
  induction h with
  | init => exact wellFormed_initial p cfg
  | next _ executed ih => exact wellFormed_step p env ih executed

/-- Given the whole WellFormed predicate, including the explicit bindingDomain
clause, when an arbitrary adapter step succeeds, then the
entire invariant persists. Reachable initial/step history supplies this
predicate and the explicit domain iff; generic reachability alone does not
prove anything about alias bindings. The empty-world/phantom-alias
fixture must fail bindingDomain, while a genuine fresh registration succeeds.
No policy rejects legitimate registration merely to avoid that missing proof.

Given an actual pending lookup in a reachable system, a successful arbitrary
competing action, and absence of consumption of its exact reference; when
observing its successor; then the complete old record, token binding, active
leaf and supply remain. This covers local steps, booking in either store,
generic recovery and mixed fold. No obsolete now<far premise is imported.
These are the successors to Agreement's
custody and refusal obligations, not merely names for the old go-request. -/
theorem reachable_binding_domain (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (hr : Reach p env cfg s) (aid : Nat) :
    (∃ token, bindingAt s aid = some token) ↔
      (Singular.trieGet s.trie aid = .known .active ∨
       Singular.trieGet s.trie aid = .known .terminal) := by
  exact (reachable_wellFormed p env cfg hr).bindingDomain aid

end CardanoKeri.Registry
