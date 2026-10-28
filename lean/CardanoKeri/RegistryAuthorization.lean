import CardanoKeri.RegistryBurns

/-! Reachable pending custody retains an actual prior application conviction. -/
namespace CardanoKeri.Registry

/-- Provenance at the coarse Registry evidence boundary. It records actual
execution at the retained key and does not identify that premise with the
Checkpoint concrete duplicity predicate. -/
def ConvictionOrigin (p : Params) (env : Env) (cfg : Singular.Config)
    (aid token key : Nat) (original : Singular.Holding) : Prop :=
  ∃ before after : Sys, ∃ c : Carrier,
    Reach p env cfg before ∧ carrierAt before aid = some c ∧
    c.token = token ∧ c.k = key ∧ c.original = original ∧
    (c.st = .live ∨ c.st = .parked) ∧ env.duplicity aid c.k = true ∧
    convictCkpt env before aid = .ok ({}, after)

/-- Both prebooking convicted carriers and complete booked records carry the
same historical authorization fact. This is an inductive proof property. -/
def AuthorizationHistory (p : Params) (env : Env) (cfg : Singular.Config) (s : Sys) : Prop :=
  (∀ c ∈ s.carriers, c.st = .terminationPending →
    ConvictionOrigin p env cfg c.aid c.token c.k c.original) ∧
  (∀ e ∈ s.terminations,
    ConvictionOrigin p env cfg e.payload.aid e.payload.token e.payload.keyState e.payload.original)

/-- Key uniqueness makes a present carrier's lookup return that exact carrier. -/
theorem carrier_lookup_of_mem (p : Params) {s : Sys} (hw : WellFormed p s)
    (c : Carrier) (member : c ∈ s.carriers) : carrierAt s c.aid = some c := by
  have selected := Singular.distinct_key_filter (fun c : Carrier => c.aid) hw.carrierKeys member
  unfold carrierAt
  rw [← List.head?_filter]
  have predicate : (fun old : Carrier => old.aid == c.aid) =
      (fun old => decide (old.aid = c.aid)) := by funext old; apply Bool.eq_iff_iff.mpr; simp
  rw [predicate, selected]; rfl

/-- Installing metadata never invents a pending carrier: registrations start
live, and terminations leave the existing carrier list untouched. -/
theorem installMember_pending_old (p : Params) (before acc after : Sys)
    (member : Singular.FoldMember) (hs : installMember p before acc member = .ok after)
    (c : Carrier) (present : c ∈ after.carriers) (pending : c.st = .terminationPending) :
    c ∈ acc.carriers := by
  cases member with
  | termination b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · split at hs
      · contradiction
      · cases hs; exact present
    · contradiction
  | registration b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · cases hs
      rcases List.mem_cons.mp present with equal | old
      · subst c; contradiction
      · exact old

/-- A pending carrier after the full installer is the exact old carrier. -/
theorem installMembers_pending_old (p : Params) (before acc after : Sys)
    (members : List Singular.FoldMember)
    (hs : members.foldlM (installMember p before) acc = .ok after)
    (c : Carrier) (present : c ∈ after.carriers) (pending : c.st = .terminationPending) :
    c ∈ acc.carriers := by
  induction members generalizing acc with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at hs
    subst after; exact present
  | cons member rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at hs
    split at hs
    · contradiction
    · rename_i middle first
      exact installMember_pending_old p before acc middle member first c (ih middle hs) pending

/-- Actual transitions preserve prior authorization or supply their own
successful conviction as its source; no fold receipt manufactures evidence. -/
theorem authorization_step (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} (hr : Reach p env cfg s) (history : AuthorizationHistory p env cfg s)
    {action : Action} {f : Flow} (hs : stepFn p env action s = .ok (f, s')) :
    AuthorizationHistory p env cfg s' := by
  have hw := reachable_wellFormed p env cfg hr
  cases action with
  | bookRegistration b =>
    obtain ⟨_, _, rfl, _⟩ := bookRegistration_sound p hs
    exact history
  | park aid recipient =>
    obtain ⟨source, _, _, _, _, rfl⟩ := (park_iff p env s s' aid recipient f).mp hs
    refine ⟨?_, history.2⟩
    intro c member pending
    obtain ⟨old, oldMem, equal⟩ := List.mem_map.mp member
    subst c
    split at pending
    · contradiction
    · rename_i notSelected
      simpa only [if_neg notSelected] using history.1 old oldMem pending
  | revive aid =>
    obtain ⟨source, _, _, _, _, rfl⟩ := (revive_iff p env s s' aid f).mp hs
    refine ⟨?_, history.2⟩
    intro c member pending
    obtain ⟨old, oldMem, equal⟩ := List.mem_map.mp member
    subst c
    split at pending
    · contradiction
    · rename_i notSelected
      simpa only [if_neg notSelected] using history.1 old oldMem pending
  | convictCkpt aid =>
    obtain ⟨source, lookup, state, evidence, flow, successor⟩ := (convictCkpt_iff env s s' aid f).mp hs
    have actual : convictCkpt env s aid = .ok ({}, s') := by simpa [stepFn, flow] using hs
    subst s'
    refine ⟨?_, history.2⟩
    intro c member pending
    obtain ⟨old, oldMem, equal⟩ := List.mem_map.mp member
    subst c
    split at pending
    · rename_i selected
      simp only [if_pos selected]
      have key : old.aid = aid := by simpa using selected
      have oldLookup := carrier_lookup_of_mem p hw old oldMem
      rw [key, lookup] at oldLookup
      have same : source = old := Option.some.inj oldLookup
      subst source
      refine ⟨s, { s with carriers := s.carriers.map (fun carrier =>
        if carrier.aid == aid then { carrier with st := .terminationPending } else carrier) },
        old, hr, ?_, rfl, rfl, rfl, state, ?_, ?_⟩
      · simpa [key] using lookup
      · simpa [key] using evidence
      · simpa [key] using actual
    · rename_i notSelected
      simpa only [if_neg notSelected] using history.1 old oldMem pending
  | bookTermination aid booker fee b =>
    obtain ⟨c, world, lookup, pending, _, _, _, _, _, _, _, _, rfl, _, _⟩ :=
      (bookTermination_iff p s s' aid booker fee b f).mp hs
    refine ⟨?_, ?_⟩
    · intro old member state
      exact history.1 old (List.mem_filter.mp member).1 state
    · intro e member
      rcases List.mem_cons.mp member with rfl | old
      · have key : c.aid = aid := by simpa using List.find?_some lookup
        simpa [key] using history.1 c (List.mem_of_find?_eq_some lookup) pending
      · exact history.2 e old
  | fold gen plugin u tx =>
    obtain ⟨_, _, _, world, _, reconstructed⟩ := (fold_iff p env s s' gen plugin u tx f).mp hs
    obtain ⟨acc, installed, carriers, _, _⟩ := foldResult_installer p reconstructed
    refine ⟨?_, ?_⟩
    · intro c member pending
      rw [carriers] at member
      exact history.1 c (installMembers_pending_old p s s acc _ installed c member pending) pending
    · intro e member
      rw [(fold_sound p env hs).2.2.2.2.2.2] at member
      exact history.2 e (List.mem_filter.mp member).1
  | genericRetraction u tx =>
    have facts := generic_retraction_sound s s' u tx f hs
    exact ⟨fun c member pending => history.1 c (facts.2.1 ▸ member) pending,
      fun e member => history.2 e (facts.2.2.1 ▸ member)⟩
  | genericRejection u tx =>
    have facts := generic_rejection_sound s s' u tx f hs
    exact ⟨fun c member pending => history.1 c (facts.2.1 ▸ member) pending,
      fun e member => history.2 e (facts.2.2.1 ▸ member)⟩

/-- Every actual reachable state retains authorization in both custody stages. -/
theorem reachable_authorization (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (hr : Reach p env cfg s) : AuthorizationHistory p env cfg s := by
  induction hr with
  | init => simp [AuthorizationHistory, Sys.init]
  | next before executed ih => exact authorization_step p env cfg before ih executed

/-- Given the exact inputs and actual success, plus actual Reach history where
stated; when booking the convicted carrier or inspecting a reachable pending
record; then the iff includes every application field constraint, actual
imported admission and complete successor, premium, request and external fee
observation. Each reachable booked payload has a real prior reachable KERI
conviction at its retained key, using the existing opaque premise. This is
not a proof that the opaque predicate equals concrete Checkpoint duplicity.
All earlier pending records survive wholly; actual supply remains one and
custody moves exactly once. Required refusals: parked/live without prior
conviction, invalid coarse proof, wrong holding/key/token, duplicate reference
in either store, second booking of the same carrier, and a tail-drop mutant
that otherwise still admits both bookings. Full concrete Checkpoint evidence
controls are exercised separately from the whole-record preservation claim. -/
theorem pending_has_keri_authorization
    (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys}
    (hr : Reach p env cfg s) (e : TerminationEntry) (he : e ∈ s.terminations) :
    ∃ before after : Sys, ∃ c : Carrier,
      Reach p env cfg before ∧ carrierAt before e.payload.aid = some c ∧
      c.token = e.payload.token ∧ c.k = e.payload.keyState ∧
      c.original = e.payload.original ∧ (c.st = .live ∨ c.st = .parked) ∧
      env.duplicity e.payload.aid c.k = true ∧
      convictCkpt env before e.payload.aid = .ok ({}, after) := by
  exact (reachable_authorization p env cfg hr).2 e he

end CardanoKeri.Registry
