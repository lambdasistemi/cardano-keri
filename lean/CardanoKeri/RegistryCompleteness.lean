import CardanoKeri.RegistryAuthorization

/-! Completeness of reconstruction after actual imported economic admission. -/
namespace CardanoKeri.Registry

/-- The exact pending record is found by its reference in a well-formed pool. -/
theorem pending_lookup_of_mem (p : Params) {s : Sys} (hw : WellFormed p s)
    (e : TerminationEntry) (member : e ∈ s.terminations) :
    pendingAt s e.booking.request.reference = some e := by
  have unique := (List.nodup_append.mp hw.requestRefs).2.1
  have selected := Singular.distinct_key_filter
    (fun e : TerminationEntry => e.booking.request.reference) unique member
  unfold pendingAt
  rw [← List.head?_filter]
  have predicate : (fun old : TerminationEntry => old.booking.request.reference == e.booking.request.reference) =
      (fun old => decide (old.booking.request.reference = e.booking.request.reference)) := by
    funext old; apply Bool.eq_iff_iff.mpr; simp
  rw [predicate, selected]; rfl

/-- Every actual imported member has its complete application metadata. -/
def MemberAvailable (s : Sys) : Singular.FoldMember → Prop
  | .registration b => b ∈ s.registrations
  | .termination b => ∃ e, pendingAt s b.request.reference = some e ∧ e.booking = b

/-- Given the complete parameters and hypotheses:

(p : Params) {s : Sys} (hw : WellFormed p s)
    (tx : Singular.EconomicTransaction) (member : Singular.FoldMember)
    (selected : member ∈ Singular.foldMembers s.toWorld tx)

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

MemberAvailable s member
-/
theorem actual_members_available (p : Params) {s : Sys} (hw : WellFormed p s)
    (tx : Singular.EconomicTransaction) (member : Singular.FoldMember)
    (selected : member ∈ Singular.foldMembers s.toWorld tx) : MemberAvailable s member := by
  cases member with
  | registration b => exact (Singular.foldMembers_registration selected).1
  | termination b =>
    obtain ⟨e, old, equal⟩ := List.mem_map.mp (Singular.foldMembers_termination selected).1
    subst b
    exact ⟨e, pending_lookup_of_mem p hw e old, rfl⟩

/-- Complete member metadata makes the actual installer succeed at every
accumulator; this does not assume successful final reconstruction. -/
theorem installMember_exists (p : Params) (before acc : Sys) (member : Singular.FoldMember)
    (available : MemberAvailable before member) :
    ∃ after, installMember p before acc member = .ok after := by
  cases member with
  | registration b =>
    simp [installMember, MemberAvailable] at available ⊢
    simp [available, pure, Except.pure]
  | termination b =>
    obtain ⟨e, found, equal⟩ := available
    exact ⟨acc, by simp [installMember, found, equal, bind, Except.bind, pure, Except.pure]⟩

/-- The proof removes all original pending custody from a structural held
list. This is an observation used in correspondence, not an extra transition. -/
def outsidePending (s : Sys) (holding : Singular.Holding) : Bool :=
  !(holding.kind == .active && s.toWorld.terminations.any (fun b => b.request.key == holding.key))

/-- Every actual carrier is outside the pending pool; every pending holding
is inside it. Hence erasing projected pending custody recovers exact originals. -/
theorem projected_carriers_exact (p : Params) {s : Sys} (hw : WellFormed p s) :
    (Singular.foldProjectedRegistry s.toWorld).held.filter (outsidePending s) =
      s.carriers.map (·.original) := by
  have carriers : (s.carriers.map (·.original)).filter (outsidePending s) = s.carriers.map (·.original) := by
    apply List.filter_eq_self.mpr
    intro holding member
    obtain ⟨c, old, equal⟩ := List.mem_map.mp member
    subst holding
    have shape := hw.carrierShape c old
    have absent : s.toWorld.terminations.any (fun b => b.request.key == c.original.key) = false := by
      apply List.any_eq_false.mpr
      intro b member
      obtain ⟨e, pendingMem, equal⟩ := List.mem_map.mp member
      subst b
      have different := shape.2.2.2.2.2 e pendingMem
      simpa [shape.1, (hw.terminationShape e pendingMem).1] using different
    simp [outsidePending, absent]
  have pending : (s.toWorld.terminations.flatMap (·.custodyInputs)).filter (outsidePending s) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro holding member
    obtain ⟨b, member, custody⟩ := List.mem_flatMap.mp member
    obtain ⟨e, old, equal⟩ := List.mem_map.mp member
    subst b
    have shape := hw.terminationShape e old
    rw [shape.2.2.2.2.1] at custody
    have equal : holding = e.payload.original := by simpa using custody
    subst holding
    have present : s.toWorld.terminations.any
        (fun b => b.request.key == e.payload.original.key) = true := by
      apply List.any_eq_true.mpr
      exact ⟨e.booking, List.mem_map.mpr ⟨e, old, rfl⟩, by simp [shape.1, shape.2.2.1]⟩
    simp [outsidePending, shape.2.2.2.1, present]
  change ((s.carriers.map (·.original)) ++ s.toWorld.terminations.flatMap (·.custodyInputs)).filter
    (outsidePending s) = s.carriers.map (·.original)
  rw [List.filter_append, carriers, pending, List.append_nil]

/-- Imported acceptance cannot register any key already held in a pending
termination, even when other requests precede that registration. -/
theorem imported_registration_not_pending (p : Params) {s : Sys} (hw : WellFormed p s)
    {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {world : Singular.World}
    (accepted : Singular.foldAccepted s.toWorld u tx = .ok world)
    (b : Singular.RegistrationBooking)
    (selected : .registration b ∈ Singular.foldMembers s.toWorld tx) :
    s.toWorld.terminations.any (fun old => old.request.key == b.request.key) = false := by
  obtain ⟨_, result, batch, _, _⟩ := Singular.foldAccepted_checks accepted
  apply List.any_eq_false.mpr
  intro old member
  obtain ⟨e, pendingMem, equal⟩ := List.mem_map.mp member
  subst old
  have shape := hw.terminationShape e pendingMem
  have different : e.booking.request.key ≠ b.request.key := by
    intro same
    have active : Singular.trieGet s.trie b.request.key = .known .active := by
      rw [← same, shape.1]
      exact shape.2.2.2.2.2.2.2.2.2.2
    exact generic_fold_registered_insert_impossible _ _ result
      (Singular.foldLegacyRequest s.config (.registration b))
      (List.mem_map.mpr ⟨.registration b, selected, rfl⟩) rfl (Or.inl active)
      (Singular.foldBatch_inv _ _ _ batch).2
  simpa using different

/-- One imported step and the actual metadata installer agree on the exact
holding list after original pending custody is projected out. -/
theorem installMember_held (p : Params) (before acc after : Sys)
    (registry : Singular.RegistryState) (result : Singular.Result) (member : Singular.FoldMember)
    (available : MemberAvailable before member)
    (fresh : ∀ b, member = .registration b →
      before.toWorld.terminations.any (fun old => old.request.key == b.request.key) = false)
    (relation : registry.held.filter (outsidePending before) = acc.carriers.map (·.original))
    (installed : installMember p before acc member = .ok after)
    (executed : Singular.step registry (Singular.foldLegacyRequest before.config member) = .ok result) :
    result.state.held.filter (outsidePending before) = after.carriers.map (·.original) := by
  obtain ⟨_, effect⟩ := Singular.step_eq_ok _ _ _ executed
  cases member with
  | registration b =>
    unfold installMember at installed
    simp only [bind, Except.bind, pure, Except.pure] at installed
    split at installed
    · contradiction
    · cases installed
      rw [effect, (Singular.applyEdge_insertActive _ _ rfl).2.2.1]
      have kept : outsidePending before {
          key := b.request.key, kind := .active, output := b.request.destination, datum := b.request.datum } = true := by
        simp [outsidePending, fresh b rfl]
      change (List.filter (outsidePending before)
        ({ key := b.request.key, kind := .active, output := b.request.destination, datum := b.request.datum } :: registry.held)) = _
      rw [List.filter_cons_of_pos kept, relation]
      rfl
  | termination b =>
    obtain ⟨e, lookup, equal⟩ := available
    have member : b ∈ before.toWorld.terminations :=
      List.mem_map.mpr ⟨e, (pending_lookup_mem before b.request.reference e lookup).1, equal⟩
    have present : before.toWorld.terminations.any (fun old => old.request.key == b.request.key) = true :=
      List.any_eq_true.mpr ⟨b, member, by simp⟩
    have afterEqual : after = acc := by
      simpa [installMember, lookup, equal, bind, Except.bind, pure, Except.pure] using installed.symm
    subst after
    rw [effect, (Singular.applyEdge_updateTerminal _ _ rfl).2.2.1, ← relation]
    rw [List.filter_filter]
    apply List.filter_congr
    intro holding _
    by_cases key : holding.key = b.request.key <;> by_cases kind : holding.kind = .active <;>
      simp [Singular.foldLegacyRequest, outsidePending, key, kind, present]

/-- Actual imported steps reconstruct an accumulator with the exact filtered
holding list. Metadata availability and registration freshness are consequences
of the supplied input history and imported admission, not new adapter guards. -/
theorem installMembers_held (p : Params) (before acc : Sys)
    (registry : Singular.RegistryState) (result : Singular.Result) (members : List Singular.FoldMember)
    (available : ∀ member ∈ members, MemberAvailable before member)
    (fresh : ∀ b, .registration b ∈ members →
      before.toWorld.terminations.any (fun old => old.request.key == b.request.key) = false)
    (relation : registry.held.filter (outsidePending before) = acc.carriers.map (·.original))
    (executed : Singular.foldActions registry (members.map (Singular.foldLegacyRequest before.config)) = .ok result) :
    ∃ after, members.foldlM (installMember p before) acc = .ok after ∧
      result.state.held.filter (outsidePending before) = after.carriers.map (·.original) := by
  induction members generalizing registry acc result with
  | nil =>
    simp only [List.map_nil, Singular.foldActions, Except.ok.injEq] at executed
    subst result
    exact ⟨acc, rfl, relation⟩
  | cons member rest ih =>
    simp only [List.map_cons, Singular.foldActions, bind, Except.bind, pure, Except.pure] at executed
    split at executed
    · contradiction
    · rename_i middle first
      split at executed
      · contradiction
      · rename_i last remaining
        cases executed
        obtain ⟨next, installed⟩ := installMember_exists p before acc member (available member List.mem_cons_self)
        have nextRelation := installMember_held p before acc next registry middle member
          (available member List.mem_cons_self)
          (by intro b equal; apply fresh b; rw [equal]; exact List.mem_cons_self)
          relation installed first
        obtain ⟨after, tail, related⟩ := ih next middle.state last
          (fun m hm => available m (List.mem_cons_of_mem member hm))
          (fun b hb => fresh b (List.mem_cons_of_mem member hb)) nextRelation remaining
        exact ⟨after, by simp [List.foldlM_cons, installed, tail, bind, Except.bind], related⟩

/-- Restoring genuine pending custody gives the imported registry its exact
active-supply law, derived from actual World reachability. -/
theorem projected_active_supply (p : Params) {s : Sys} (hw : WellFormed p s) :
    Singular.RegistryActiveSupply (Singular.foldProjectedRegistry s.toWorld) := by
  intro key
  have shape := Singular.reachable_pending_custody_shape s.toWorld hw.worldReachable
  have counts := Singular.pending_custody_counts s.toWorld.registry.config s.toWorld.terminations shape key
  have projected : Singular.kindCount (Singular.foldProjectedRegistry s.toWorld) .active key =
      Singular.worldSingularSupply s.toWorld key := by
    simp only [Singular.kindCount, Singular.foldProjectedRegistry, List.filter_append,
      List.length_append, Singular.worldSingularSupply, Singular.carriedSingularCount]
    rw [counts.1, counts.2]
  rw [projected]
  have sync := Singular.Statements.world_supply_sync s.toWorld hw.worldReachable key
  change Singular.worldSingularSupply s.toWorld key =
    if Singular.trieGet s.trie key = .known .active then 1 else 0
  by_cases active : Singular.trieGet s.trie key = .known .active
  · rw [if_pos active]; exact sync.1.mpr active
  · rw [if_neg active]; exact sync.2.1.mpr active

/-- The final generic custody projection is equivalent to removing all old
pending custody: selected keys have already been consumed by the actual batch,
while unselected pending records are removed only from this projection. -/
theorem fold_effect_erase_all (p : Params) {s : Sys} (hw : WellFormed p s)
    (tx : Singular.EconomicTransaction) (result : Singular.Result)
    (accepted : Singular.foldBatch (Singular.foldProjectedRegistry s.toWorld)
      ((Singular.foldMembers s.toWorld tx).map (Singular.foldLegacyRequest s.config)) = .ok result) :
    (Singular.foldRegistryEffect s.toWorld tx result).held =
      result.state.held.filter (outsidePending s) := by
  have supply := Singular.foldActions_active_supply (projected_active_supply p hw)
    (Singular.foldBatch_inv _ _ _ accepted).2
  have consumedAbsent : ∀ e ∈ s.terminations,
      Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference = true →
      ∀ holding ∈ result.state.held, holding.key ≠ e.booking.request.key := by
    intro e old consumed holding member equal
    have selected := consumed_pending_member p hw (pending_lookup_of_mem p hw e old) consumed
    have terminal := generic_fold_selected_terminal _ _ result
      (Singular.foldLegacyRequest s.config (.termination e.booking))
      (List.mem_map.mpr ⟨.termination e.booking, selected, rfl⟩) rfl
      (Singular.foldBatch_inv _ _ _ accepted).2
    change Singular.trieGet result.state.trie e.booking.request.key = .known .terminal at terminal
    have zero := supply e.booking.request.key
    rw [terminal] at zero
    change Singular.kindCount result.state .active e.booking.request.key = 0 at zero
    have positive : 0 < Singular.kindCount result.state .active e.booking.request.key := by
      apply List.length_pos_iff_exists_mem.mpr
      exact ⟨holding, List.mem_filter.mpr ⟨member, by cases holding.kind; simp [equal]⟩⟩
    omega
  have same (holding : Singular.Holding) (member : holding ∈ result.state.held) :
      (Singular.foldRemainingTerminations s.toWorld tx).any (fun b => b.request.key == holding.key) =
      s.toWorld.terminations.any (fun b => b.request.key == holding.key) := by
    apply Bool.eq_iff_iff.mpr
    constructor
    · intro kept
      obtain ⟨b, selected, key⟩ := List.any_eq_true.mp kept
      exact List.any_eq_true.mpr ⟨b, (List.mem_filter.mp selected).1, key⟩
    · intro old
      obtain ⟨b, selected, key⟩ := List.any_eq_true.mp old
      obtain ⟨e, pendingMem, equal⟩ := List.mem_map.mp selected
      subst b
      have keyEqual : e.booking.request.key = holding.key := by simpa using key
      have notConsumed : Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference = false := by
        cases consumed : Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference with
        | false => rfl
        | true => exact False.elim (consumedAbsent e pendingMem consumed holding member keyEqual.symm)
      exact List.any_eq_true.mpr ⟨e.booking, List.mem_filter.mpr
        ⟨List.mem_map.mpr ⟨e, pendingMem, rfl⟩, by simp [notConsumed]⟩, key⟩
  unfold Singular.foldRegistryEffect
  apply List.filter_congr
  intro holding member
  rw [same holding member]
  rfl
/-- Given the actual full before Sys and actual successful adapter fold; when
reading its result; then the actual imported fold accepted exactly its full
projected successor and the exact two pools are filtered by consumed refs.
Conversely a reachable Sys, preserved KERI registration authorization and
actual upstream acceptance must reconstruct successfully: a metadata guard
cannot hide missing adapter behavior. The two custody theorems preserve the
entire unselected record and retire/burn/remove only the exact selected one,
including alias and tag identity observations. These types are universal over
mixed batches, not just terminal-only lists. Positive witness: registration
of a fresh AID plus termination of AID11, with AID12 still pending. Negative
controls isolate wrong root, config/plugin, generation, request/ref, donation,
carrier, mint, and unselected tail independently. Compile/setup failures do
not count as semantic kills. -/
theorem fold_complete (p : Params) (env : Env) (cfg : Singular.Config)
    {s : Sys} (hr : Reach p env cfg s)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) (world : Singular.World)
    (auth : registrationsAuthorized env (Singular.foldMembers s.toWorld tx) = true)
    (accepted : Singular.foldAccepted s.toWorld u tx = .ok world) :
    ∃ f s', fold p env s s.gen s.config.applicationPolicy u tx = .ok (f, s') ∧
      s'.toWorld = world := by
  have hw := reachable_wellFormed p env cfg hr
  obtain ⟨_, result, batch, _, effect⟩ := Singular.foldAccepted_checks accepted
  obtain ⟨acc, installed, held⟩ := installMembers_held p s s
    (Singular.foldProjectedRegistry s.toWorld) result (Singular.foldMembers s.toWorld tx)
    (actual_members_available p hw tx) (imported_registration_not_pending p hw accepted)
    (projected_carriers_exact p hw) (Singular.foldBatch_inv _ _ _ batch).2
  have worldHeld : world.registry.held = acc.carriers.map (·.original) := by
    rw [effect]
    change (Singular.foldRegistryEffect s.toWorld tx result).held = _
    rw [fold_effect_erase_all p hw tx result batch]
    exact held
  have pools := Singular.foldAccepted_pending accepted
  have terminations : (s.terminations.filter (fun e =>
      !Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference)).map (·.booking) =
      world.terminations := by
    rw [pools.2]
    simp [Singular.foldRemainingTerminations, Sys.toWorld, List.filter_map, Function.comp_def]
  let after : Sys := { acc with
    gen := s.gen + 1, config := world.registry.config, trie := world.registry.trie, treasury := world.treasury,
    registrations := s.registrations.filter (fun b =>
      !Singular.inputsContainReference tx.transaction.inputs b.request.reference),
    terminations := s.terminations.filter (fun e =>
      !Singular.inputsContainReference tx.transaction.inputs e.booking.request.reference) }
  let flow : Flow := { locked := (Singular.foldMembers s.toWorld tx).filterMap (fun m => match m with
    | .registration b => some (b.request.key, b.request.carrierAda - p.Mc)
    | .termination _ => none) }
  have projected : after.toWorld = world := by
    have registry : ({
        config := world.registry.config, trie := world.registry.trie,
        held := acc.carriers.map (·.original) } : Singular.RegistryState) = world.registry := by
      rw [← worldHeld]
    change ({ registry := _, pending := _, terminations := _, treasury := world.treasury } : Singular.World) = world
    dsimp only [after]
    change ({
        registry := _
        pending := s.toWorld.pending.filter (fun b =>
          !Singular.inputsContainReference tx.transaction.inputs b.request.reference)
        terminations := _
        treasury := world.treasury } : Singular.World) = world
    rw [registry, ← pools.1, terminations]
  have reconstructed : foldResult p s tx world = .ok (flow, after) := by
    simp only [foldResult, installed, bind, Except.bind, pure, Except.pure]
    change (if after.toWorld ≠ world then Except.error "keri-fold-reconstruction-mismatch"
      else Except.ok (flow, after)) = Except.ok (flow, after)
    rw [if_neg (by simp [projected])]
  exact ⟨flow, after, (fold_iff p env s after s.gen s.config.applicationPolicy u tx flow).mpr
    ⟨rfl, rfl, auth, world, accepted, reconstructed⟩, projected⟩

end CardanoKeri.Registry
