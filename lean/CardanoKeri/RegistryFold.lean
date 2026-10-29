import CardanoKeri.RegistryMetadata

/-! Imported batch and application metadata correspondence. -/
namespace CardanoKeri.Registry

/-- Registration keys in processing order, retaining their exact identity. -/
def registrationKeys (members : List Singular.FoldMember) : List Nat :=
  members.filterMap (fun m => match m with
    | .registration b => some b.request.key
    | .termination _ => none)

/-- The imported request sequence admits at most one registration of each key.
The proof follows actual sequential admission, including mixed batches. -/
theorem generic_registration_keys_unique (s : Singular.RegistryState)
    (batch : List Singular.Action) (t : Singular.Result)
    (hs : Singular.foldActions s batch = .ok t) :
    (batch.filterMap (fun a => if a.edge = .insertActive then some a.key else none)).Nodup := by
  induction batch generalizing s t with
  | nil => simp
  | cons action rest ih =>
    unfold Singular.foldActions at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i middle first
      split at hs
      · contradiction
      · rename_i last remaining
        have tail := ih middle.state last remaining
        by_cases edge : action.edge = .insertActive
        · simp only [List.filterMap_cons, edge, ↓reduceIte, List.nodup_cons]
          refine ⟨?_, tail⟩
          intro member
          obtain ⟨other, member, selected⟩ := List.mem_filterMap.mp member
          have otherEdge : other.edge = .insertActive := by
            split at selected
            · assumption
            · contradiction
          have same : other.key = action.key := by simpa [otherEdge] using selected
          obtain ⟨_, equal⟩ := Singular.step_eq_ok s action middle first
          have active : Singular.trieGet middle.state.trie other.key = .known .active := by
            rw [equal, (Singular.applyEdge_insertActive s action edge).1, same]
            simp
          exact generic_fold_registered_insert_impossible middle.state rest last other member
            otherEdge (Or.inl active) remaining
        · simpa [edge] using tail

/-- An accepted adapter fold selects distinct registration keys. -/
theorem fold_registration_keys_unique (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s')) :
    (registrationKeys (Singular.foldMembers s.toWorld tx)).Nodup := by
  obtain ⟨_, result, batch, _, _⟩ := Singular.foldAccepted_checks (fold_sound p env hs).2.2.2.1
  have unique := generic_registration_keys_unique _ _ result (Singular.foldBatch_inv _ _ _ batch).2
  have projection : (fun m =>
      if (Singular.foldLegacyRequest s.config m).edge = .insertActive
      then some (Singular.foldLegacyRequest s.config m).key else none) =
      (fun m => match m with
        | .registration b => some b.request.key
        | .termination _ => none) := by
    funext m
    cases m <;> rfl
  simpa only [List.filterMap_map, Function.comp_def, Sys.toWorld, projection, registrationKeys] using unique

/-- A selected registration is fresh with respect to every existing alias
binding; the full invariant's domain clause binds aliases to registry leaves. -/
theorem fold_registration_binding_fresh (p : Params) (env : Env) {s s' : Sys}
    (hw : WellFormed p s) {gen plugin : Nat} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s'))
    (b : Singular.RegistrationBooking)
    (selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx) :
    bindingAt s b.request.key = none := by
  cases binding : bindingAt s b.request.key with
  | none => rfl
  | some token =>
    have known := (hw.bindingDomain b.request.key).mp ⟨token, binding⟩
    have refused := registered_registration_refused p env s gen plugin u tx b selected known
    simp [hs, Except.toOption] at refused

/-- An imported step adds exactly its registration key to the registered
leaf domain. Termination preserves that domain. -/
theorem generic_step_domain (s : Singular.RegistryState) (a : Singular.Action)
    (t : Singular.Result) (aid : Nat) (hs : Singular.step s a = .ok t) :
    (Singular.trieGet t.state.trie aid = .known .active ∨
      Singular.trieGet t.state.trie aid = .known .terminal) ↔
    (Singular.trieGet s.trie aid = .known .active ∨
      Singular.trieGet s.trie aid = .known .terminal) ∨
    (a.edge = .insertActive ∧ a.key = aid) := by
  obtain ⟨admitted, equal⟩ := Singular.step_eq_ok s a t hs
  rw [equal]
  obtain ⟨_, _, _, _, branch⟩ := (Singular.refusal_none_iff s a).mp admitted
  rcases branch with ⟨edge, unknown⟩ | ⟨edge, active, _⟩
  · rw [(Singular.applyEdge_insertActive s a edge).1]
    by_cases same : aid = a.key
    · simp [same, unknown, edge]
    · rw [Singular.trieGet_set_of_ne _ _ _ _ same]
      simp [edge, Ne.symm same]
  · rw [(Singular.applyEdge_updateTerminal s a edge).1]
    by_cases same : aid = a.key
    · simp [same, active, edge]
    · rw [Singular.trieGet_set_of_ne _ _ _ _ same]
      simp [edge]

/-- The imported batch adds precisely its selected registration keys to the
old domain, regardless of the interleaving of terminations. -/
theorem generic_fold_domain (s : Singular.RegistryState) (batch : List Singular.Action)
    (t : Singular.Result) (aid : Nat) (hs : Singular.foldActions s batch = .ok t) :
    (Singular.trieGet t.state.trie aid = .known .active ∨
      Singular.trieGet t.state.trie aid = .known .terminal) ↔
    (Singular.trieGet s.trie aid = .known .active ∨
      Singular.trieGet s.trie aid = .known .terminal) ∨
    ∃ a ∈ batch, a.edge = .insertActive ∧ a.key = aid := by
  induction batch generalizing s t with
  | nil =>
    simp only [Singular.foldActions, Except.ok.injEq] at hs
    subst t
    simp [Singular.emptyResult]
  | cons action rest ih =>
    unfold Singular.foldActions at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i middle first
      split at hs
      · contradiction
      · rename_i last remaining
        cases hs
        change (Singular.trieGet last.state.trie aid = .known .active ∨
          Singular.trieGet last.state.trie aid = .known .terminal) ↔ _
        rw [ih middle.state last remaining, generic_step_domain s action middle aid first]
        simp only [List.mem_cons]
        grind

/-- Installing metadata changes the alias domain exactly when a registration
is installed. This is a consequence of the actual installer, not a guard. -/
theorem installMember_domain (p : Params) (before acc after : Sys)
    (member : Singular.FoldMember) (hs : installMember p before acc member = .ok after)
    (aid : Nat) :
    (∃ token, bindingAt after aid = some token) ↔
      (∃ token, bindingAt acc aid = some token) ∨ aid ∈ registrationKeys [member] := by
  cases member with
  | termination b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · split at hs
      · contradiction
      · cases hs; simp [registrationKeys]
    · contradiction
  | registration b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · cases hs
      by_cases same : b.request.key = aid
      · simp [bindingAt, registrationKeys, same]
      · simp [bindingAt, registrationKeys, same, Ne.symm same]

/-- The complete actual installer adds exactly the selected registration
keys to the alias domain, preserving old terminal aliases. -/
theorem installMembers_domain (p : Params) (before acc after : Sys)
    (members : List Singular.FoldMember)
    (hs : members.foldlM (installMember p before) acc = .ok after) (aid : Nat) :
    (∃ token, bindingAt after aid = some token) ↔
      (∃ token, bindingAt acc aid = some token) ∨ aid ∈ registrationKeys members := by
  induction members generalizing acc with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at hs
    subst after
    simp [registrationKeys]
  | cons member rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at hs
    split at hs
    · contradiction
    · rename_i middle first
      rw [ih middle hs, installMember_domain p before acc middle member first aid]
      have keys : registrationKeys (member :: rest) = registrationKeys [member] ++ registrationKeys rest := by
        cases member <;> simp [registrationKeys]
      rw [keys, List.mem_append]
      exact or_assoc

/-- One successful installer preserves application metadata when its newly
registered key has no prior alias. A termination leaves metadata unchanged. -/
theorem installMember_metadata (p : Params) (before acc after : Sys)
    (member : Singular.FoldMember) (hm : Metadata p acc)
    (hs : installMember p before acc member = .ok after)
    (fresh : ∀ b, member = .registration b → bindingAt acc b.request.key = none) :
    Metadata p after := by
  cases member with
  | termination b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · split at hs
      · contradiction
      · cases hs; exact hm
    · contradiction
  | registration b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · cases hs
      exact hm.add_carrier _ (fresh b rfl) ⟨rfl, rfl, rfl, rfl⟩

/-- Distinct fresh registration keys make the complete actual metadata
installation preserve every old alias, budget and pending-record clause. -/
theorem installMembers_metadata (p : Params) (before acc after : Sys)
    (members : List Singular.FoldMember) (hm : Metadata p acc)
    (hs : members.foldlM (installMember p before) acc = .ok after)
    (unique : (registrationKeys members).Nodup)
    (fresh : ∀ b, .registration b ∈ members → bindingAt acc b.request.key = none) :
    Metadata p after := by
  induction members generalizing acc with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at hs
    subst after
    exact hm
  | cons member rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at hs
    split at hs
    · contradiction
    · rename_i middle first
      have keys : registrationKeys (member :: rest) = registrationKeys [member] ++ registrationKeys rest := by
        cases member <;> simp [registrationKeys]
      rw [keys] at unique
      have parts := List.nodup_append.mp unique
      have metadata := installMember_metadata p before acc middle member hm first (by
        intro b equal
        apply fresh b
        rw [equal]
        exact List.mem_cons_self)
      apply ih middle metadata hs parts.2.1
      intro b selected
      have oldFresh := fresh b (List.mem_cons_of_mem member selected)
      cases found : bindingAt middle b.request.key with
      | none => rfl
      | some token =>
        have domain := (installMember_domain p before acc middle member first b.request.key).mp ⟨token, found⟩
        rcases domain with ⟨oldToken, old⟩ | newKey
        · rw [oldFresh] at old; contradiction
        · have tailKey : b.request.key ∈ registrationKeys rest :=
            List.mem_filterMap.mpr ⟨.registration b, selected, rfl⟩
          exact False.elim (parts.2.2 _ newKey _ tailKey rfl)

/-- An actual reconstructed fold retains exactly the metadata accumulator
produced by its actual member list. -/
theorem foldResult_installer (p : Params) {s s' : Sys} {tx : Singular.EconomicTransaction}
    {world : Singular.World} {f : Flow} (hs : foldResult p s tx world = .ok (f, s')) :
    ∃ acc, (Singular.foldMembers s.toWorld tx).foldlM (installMember p s) s = .ok acc ∧
      s'.carriers = acc.carriers ∧ s'.bindings = acc.bindings ∧ s'.nextToken = acc.nextToken := by
  unfold foldResult at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · rename_i acc installed
    split at hs
    · contradiction
    · cases hs
      exact ⟨acc, installed, rfl, rfl, rfl⟩

/-- Metadata installation leaves the source configuration and both request
stores unchanged; pool consumption belongs to final reconstruction. -/
theorem installMember_frame (p : Params) (before acc after : Sys)
    (member : Singular.FoldMember) (hs : installMember p before acc member = .ok after) :
    after.config = acc.config ∧ after.registrations = acc.registrations ∧
      after.terminations = acc.terminations := by
  cases member with
  | termination b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · split at hs
      · contradiction
      · cases hs; exact ⟨rfl, rfl, rfl⟩
    · contradiction
  | registration b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · cases hs; exact ⟨rfl, rfl, rfl⟩

/-- The entire installer preserves its source configuration and both pools. -/
theorem installMembers_frame (p : Params) (before acc after : Sys)
    (members : List Singular.FoldMember)
    (hs : members.foldlM (installMember p before) acc = .ok after) :
    after.config = acc.config ∧ after.registrations = acc.registrations ∧
      after.terminations = acc.terminations := by
  induction members generalizing acc with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at hs
    subst after; exact ⟨rfl, rfl, rfl⟩
  | cons member rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at hs
    split at hs
    · contradiction
    · rename_i middle first
      have head := installMember_frame p before acc middle member first
      have tail := ih middle hs
      exact ⟨tail.1.trans head.1, tail.2.1.trans head.2.1, tail.2.2.trans head.2.2⟩

/-- Replacing one trie entry preserves uniqueness of its stored keys. -/
theorem trieSet_keys_unique (trie : Singular.Trie) (key : Nat) (leaf : Singular.Leaf)
    (unique : (trie.map Prod.fst).Nodup) :
    ((Singular.trieSet trie key leaf).map Prod.fst).Nodup := by
  simp only [Singular.trieSet, List.map_cons, List.nodup_cons]
  refine ⟨?_, unique.sublist (List.Sublist.map _ List.filter_sublist)⟩
  intro member
  obtain ⟨pair, member, equal⟩ := List.mem_map.mp member
  have different := (List.mem_filter.mp member).2
  simp [equal] at different

/-- An admitted imported step preserves trie-key uniqueness. -/
theorem generic_step_trie_keys (s : Singular.RegistryState) (a : Singular.Action)
    (t : Singular.Result) (unique : (s.trie.map Prod.fst).Nodup)
    (hs : Singular.step s a = .ok t) : (t.state.trie.map Prod.fst).Nodup := by
  obtain ⟨admitted, equal⟩ := Singular.step_eq_ok s a t hs
  rw [equal]
  obtain ⟨_, _, _, _, branch⟩ := (Singular.refusal_none_iff s a).mp admitted
  rcases branch with ⟨edge, _⟩ | ⟨edge, _, _⟩
  · rw [(Singular.applyEdge_insertActive s a edge).1]
    exact trieSet_keys_unique _ _ _ unique
  · rw [(Singular.applyEdge_updateTerminal s a edge).1]
    exact trieSet_keys_unique _ _ _ unique

/-- Trie-key uniqueness persists through the imported sequential batch. -/
theorem generic_fold_trie_keys (s : Singular.RegistryState) (batch : List Singular.Action)
    (t : Singular.Result) (unique : (s.trie.map Prod.fst).Nodup)
    (hs : Singular.foldActions s batch = .ok t) : (t.state.trie.map Prod.fst).Nodup := by
  induction batch generalizing s t with
  | nil =>
    simp only [Singular.foldActions, Except.ok.injEq] at hs
    subst t; exact unique
  | cons action rest ih =>
    unfold Singular.foldActions at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · rename_i middle first
      split at hs
      · contradiction
      · rename_i last remaining
        cases hs
        exact ih middle.state last (generic_step_trie_keys s action middle unique first) remaining

/-- Registration-key membership is preserved by the public request projection. -/
theorem legacy_registration_mem (cfg : Singular.Config) (members : List Singular.FoldMember)
    (aid : Nat) :
    (∃ a ∈ members.map (Singular.foldLegacyRequest cfg),
      a.edge = .insertActive ∧ a.key = aid) ↔ aid ∈ registrationKeys members := by
  constructor
  · rintro ⟨a, member, edge, key⟩
    obtain ⟨m, selected, equal⟩ := List.mem_map.mp member
    subst a
    cases m with
    | registration b => exact List.mem_filterMap.mpr ⟨.registration b, selected, by simpa using key⟩
    | termination b => contradiction
  · intro member
    obtain ⟨m, selected, key⟩ := List.mem_filterMap.mp member
    cases m with
    | registration b =>
      exact ⟨Singular.foldLegacyRequest cfg (.registration b), List.mem_map.mpr ⟨_, selected, rfl⟩,
        rfl, by simpa using key⟩
    | termination b => contradiction

/-- A successful fold preserves the full alias/registered-leaf domain in both
directions, including aliases of permanently retired keys. -/
theorem fold_binding_domain (p : Params) (env : Env) {s s' : Sys} (hw : WellFormed p s)
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s')) (aid : Nat) :
    (∃ token, bindingAt s' aid = some token) ↔
      (Singular.trieGet s'.trie aid = .known .active ∨
        Singular.trieGet s'.trie aid = .known .terminal) := by
  obtain ⟨_, _, _, world, _, reconstructed⟩ := (fold_iff p env s s' gen plugin u tx f).mp hs
  obtain ⟨acc, installed, _, bindings, _⟩ := foldResult_installer p reconstructed
  have aliases := installMembers_domain p s s acc _ installed aid
  obtain ⟨result, batch, effect⟩ := Singular.economic_fold_registry_correspondence
    (fold_sound p env hs).2.2.2.1
  have trie : s'.trie = result.state.trie := congrArg Singular.RegistryState.trie effect
  have domain := generic_fold_domain _ _ result aid (Singular.foldBatch_inv _ _ _ batch).2
  have converted := domain.trans (or_congr Iff.rfl
    (legacy_registration_mem s.toWorld.registry.config (Singular.foldMembers s.toWorld tx) aid))
  change (Singular.trieGet result.state.trie aid = .known .active ∨
    Singular.trieGet result.state.trie aid = .known .terminal) ↔
      (Singular.trieGet s.trie aid = .known .active ∨
        Singular.trieGet s.trie aid = .known .terminal) ∨
      aid ∈ registrationKeys (Singular.foldMembers s.toWorld tx) at converted
  rw [← trie, ← hw.bindingDomain aid] at converted
  apply Iff.trans ?_ converted.symm
  simpa only [bindingAt, bindings] using aliases

/-- An accepted imported fold and its exact application reconstruction
preserve every field of the full invariant, for arbitrary well-formed input. -/
theorem wellFormed_fold (p : Params) (env : Env) {s s' : Sys} (hw : WellFormed p s)
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s')) : WellFormed p s' := by
  have sound := fold_sound p env hs
  obtain ⟨_, _, _, world, _, reconstructed⟩ := (fold_iff p env s s' gen plugin u tx f).mp hs
  obtain ⟨acc, installed, carriers, bindings, next⟩ := foldResult_installer p reconstructed
  have frames := installMembers_frame p s s acc _ installed
  have metadata := installMembers_metadata p s s acc _ hw.metadata installed
    (fold_registration_keys_unique p env hs) (fold_registration_binding_fresh p env hw hs)
  have config : s'.config = { s.config with root := s'.config.root } :=
    Singular.foldAccepted_config sound.2.2.2.1
  have afterMetadata : Metadata p s' := metadata.transport carriers bindings next
    (by rw [frames.2.1, sound.2.2.2.2.2.1]; exact List.filter_sublist)
    (by rw [frames.2.2, sound.2.2.2.2.2.2]; exact List.filter_sublist)
    (by rw [frames.1]; exact config)
  obtain ⟨result, batch, effect⟩ := Singular.economic_fold_registry_correspondence sound.2.2.2.1
  have trie : s'.trie = result.state.trie := congrArg Singular.RegistryState.trie effect
  apply afterMetadata.wellFormed (.fold hw.worldReachable u tx sound.2.2.2.1)
  · rw [trie]
    exact generic_fold_trie_keys _ _ result hw.trieKeys (Singular.foldBatch_inv _ _ _ batch).2
  · exact fold_binding_domain p env hw hs

end CardanoKeri.Registry
