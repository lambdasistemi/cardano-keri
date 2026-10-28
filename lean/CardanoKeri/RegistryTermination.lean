import CardanoKeri.RegistryCustody

/-! Exact selected-request retirement through actual imported folds. -/
namespace CardanoKeri.Registry

/-- An admitted imported termination ends at the terminal leaf. -/
theorem generic_step_terminal (s : Singular.RegistryState) (a : Singular.Action)
    (t : Singular.Result) (hs : Singular.step s a = .ok t)
    (edge : a.edge = .updateTerminal) :
    Singular.trieGet t.state.trie a.key = .known .terminal := by
  obtain ⟨_, equal⟩ := Singular.step_eq_ok s a t hs
  rw [equal, (Singular.applyEdge_updateTerminal s a edge).1]
  simp

/-- Every selected imported termination leaves its key permanently terminal
through the rest of that same admitted batch. -/
theorem generic_fold_selected_terminal (s : Singular.RegistryState)
    (batch : List Singular.Action) (t : Singular.Result) (request : Singular.Action)
    (selected : request ∈ batch) (edge : request.edge = .updateTerminal)
    (hs : Singular.foldActions s batch = .ok t) :
    Singular.trieGet t.state.trie request.key = .known .terminal := by
  induction batch generalizing s t with
  | nil => simp at selected
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
        rcases List.mem_cons.mp selected with equal | later
        · subst action
          exact Singular.foldActions_preserves_terminal middle.state rest last request.key
            (generic_step_terminal s request middle first edge) remaining
        · exact ih middle.state last later remaining

/-- Consumption of a reachable pending reference selects its actual complete
termination booking in the imported member list. -/
theorem consumed_pending_member (p : Params) {s : Sys} (hw : WellFormed p s)
    {tx : Singular.EconomicTransaction} {ref : Singular.OutRef} {e : TerminationEntry}
    (hp : pendingAt s ref = some e)
    (consumed : Singular.inputsContainReference tx.transaction.inputs ref = true) :
    Singular.FoldMember.termination e.booking ∈ Singular.foldMembers s.toWorld tx := by
  have old := pending_lookup_mem s ref e hp
  have lookup := Singular.foldMemberAt_pending_termination s.toWorld hw.worldReachable e.booking
    (List.mem_map.mpr ⟨e, old.1, rfl⟩)
  rw [old.2] at lookup
  obtain ⟨input, member, same⟩ := List.any_eq_true.mp consumed
  have reference : input.ref = some ref := by simpa using same
  apply List.mem_filterMap.mpr
  exact ⟨input, member, by simp [reference, lookup]⟩

/-- A consumed reference cannot survive the exact pending-store filter. -/
theorem fold_pending_consumed (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s')) (ref : Singular.OutRef)
    (consumed : Singular.inputsContainReference tx.transaction.inputs ref = true) :
    pendingAt s' ref = none := by
  unfold pendingAt
  rw [(fold_sound p env hs).2.2.2.2.2.2]
  apply List.find?_eq_none.mpr
  intro e member
  have kept := (List.mem_filter.mp member).2
  have different : e.booking.request.reference ≠ ref := by
    intro equal
    simp [equal, consumed] at kept
  simpa using different

/-- An installer step cannot alter a binding at a key it does not register. -/
theorem installMember_binding_other (p : Params) (before acc after : Sys)
    (member : Singular.FoldMember) (hs : installMember p before acc member = .ok after)
    (aid : Nat) (other : ∀ b, member = .registration b → b.request.key ≠ aid) :
    bindingAt after aid = bindingAt acc aid := by
  cases member with
  | termination b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · split at hs
      · contradiction
      · cases hs; rfl
    · contradiction
  | registration b =>
    unfold installMember at hs
    simp only [bind, Except.bind, pure, Except.pure] at hs
    split at hs
    · contradiction
    · cases hs
      simp [bindingAt, other b rfl]

/-- The whole installer preserves the exact old token alias at every key not
registered by this batch. -/
theorem installMembers_binding_other (p : Params) (before acc after : Sys)
    (members : List Singular.FoldMember)
    (hs : members.foldlM (installMember p before) acc = .ok after) (aid : Nat)
    (other : ∀ b, .registration b ∈ members → b.request.key ≠ aid) :
    bindingAt after aid = bindingAt acc aid := by
  induction members generalizing acc with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at hs
    subst after; rfl
  | cons member rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at hs
    split at hs
    · contradiction
    · rename_i middle first
      rw [ih middle hs (fun b selected => other b (List.mem_cons_of_mem member selected))]
      apply installMember_binding_other p before acc middle member first aid
      intro b equal
      apply other b
      rw [equal]; exact List.mem_cons_self

/-- A successful fold preserves every existing alias exactly, including the
alias of a key whose token this fold permanently retires. -/
theorem fold_old_binding (p : Params) (env : Env) {s s' : Sys} (hw : WellFormed p s)
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s'))
    (aid token : Nat) (old : bindingAt s aid = some token) : bindingAt s' aid = some token := by
  obtain ⟨_, _, _, world, _, reconstructed⟩ := (fold_iff p env s s' gen plugin u tx f).mp hs
  obtain ⟨acc, installed, _, bindings, _⟩ := foldResult_installer p reconstructed
  have same := installMembers_binding_other p s s acc _ installed aid (by
    intro b selected equal
    have fresh := fold_registration_binding_fresh p env hw hs b selected
    rw [equal, old] at fresh
    contradiction)
  have after : bindingAt s' aid = bindingAt acc aid := by simp [bindingAt, bindings]
  exact after.trans (same.trans old)

end CardanoKeri.Registry
