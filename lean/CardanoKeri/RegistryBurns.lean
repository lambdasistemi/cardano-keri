import CardanoKeri.RegistryTermination

/-! Exact singular-token burn and absence of replacement outputs. -/
namespace CardanoKeri.Registry

/-- No admitted imported step addresses a terminal key. -/
theorem generic_step_avoids_terminal (s : Singular.RegistryState) (a : Singular.Action)
    (t : Singular.Result) (aid : Nat)
    (terminal : Singular.trieGet s.trie aid = .known .terminal)
    (hs : Singular.step s a = .ok t) : a.key ≠ aid := by
  intro equal
  obtain ⟨admitted, _⟩ := Singular.step_eq_ok s a t hs
  obtain ⟨_, _, _, _, branch⟩ := (Singular.refusal_none_iff s a).mp admitted
  rcases branch with ⟨_, leaf⟩ | ⟨_, leaf, _⟩ <;>
    rw [equal, terminal] at leaf <;> contradiction

/-- No member of an admitted batch can address an initially terminal key. -/
theorem generic_fold_avoids_terminal (s : Singular.RegistryState)
    (batch : List Singular.Action) (t : Singular.Result) (aid : Nat)
    (terminal : Singular.trieGet s.trie aid = .known .terminal)
    (hs : Singular.foldActions s batch = .ok t) : ∀ a ∈ batch, a.key ≠ aid := by
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
        intro a member
        rcases List.mem_cons.mp member with rfl | later
        · exact generic_step_avoids_terminal s a middle aid terminal first
        · exact ih middle.state last
            (Singular.step_preserves_terminal s action middle aid terminal first) remaining a later

/-- Termination keys in actual processing order. -/
def terminationKeys (members : List Singular.FoldMember) : List Nat :=
  members.filterMap (fun m => match m with
    | .registration _ => none
    | .termination b => some b.request.key)

/-- An admitted imported batch terminates each key at most once. -/
theorem generic_termination_keys_unique (s : Singular.RegistryState)
    (batch : List Singular.Action) (t : Singular.Result)
    (hs : Singular.foldActions s batch = .ok t) :
    (batch.filterMap (fun a => if a.edge = .updateTerminal then some a.key else none)).Nodup := by
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
        by_cases edge : action.edge = .updateTerminal
        · simp only [List.filterMap_cons, edge, ↓reduceIte, List.nodup_cons]
          refine ⟨?_, tail⟩
          intro member
          obtain ⟨other, member, selected⟩ := List.mem_filterMap.mp member
          have otherEdge : other.edge = .updateTerminal := by
            split at selected
            · assumption
            · contradiction
          have same : other.key = action.key := by simpa [otherEdge] using selected
          exact generic_fold_avoids_terminal middle.state rest last action.key
            (generic_step_terminal s action middle first edge) remaining other member same
        · simpa [edge] using tail

/-- Actual adapter folds therefore select distinct termination keys. -/
theorem fold_termination_keys_unique (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s')) :
    (terminationKeys (Singular.foldMembers s.toWorld tx)).Nodup := by
  obtain ⟨_, result, batch, _, _⟩ := Singular.foldAccepted_checks (fold_sound p env hs).2.2.2.1
  have unique := generic_termination_keys_unique _ _ result (Singular.foldBatch_inv _ _ _ batch).2
  have projection : (fun m =>
      if (Singular.foldLegacyRequest s.config m).edge = .updateTerminal
      then some (Singular.foldLegacyRequest s.config m).key else none) =
      (fun m => match m with
        | .registration _ => none
        | .termination b => some b.request.key) := by
    funext m
    cases m <;> rfl
  simpa only [List.filterMap_map, Function.comp_def, Sys.toWorld, projection, terminationKeys] using unique

/-- The abstract public tag preserves the key's identity. -/
theorem singularTag_key_iff (cfg : Singular.Config) (a b : Nat) :
    cfg.singularTag a = cfg.singularTag b ↔ a = b := by
  constructor
  · intro equal
    exact congrArg (fun tag : Singular.SingularTag => tag.token.name) equal
  · intro equal; rw [equal]

set_option maxRecDepth 4096 in
/-- Accepted routing checks the complete support of the exact mint vector. -/
theorem routing_mint_checked {world : Singular.World} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} {result : Singular.Result}
    (checked : Singular.foldRoutingRefusal world u tx result = none) :
    Singular.foldSameQuantities tx.singularMint
      (Singular.foldMint world.registry.config (Singular.foldMembers world tx)) = true := by
  unfold Singular.foldRoutingRefusal at checked
  simp only [bind, pure, Option.bind] at checked
  repeat (split at checked <;> try contradiction)
  all_goals simp_all [← Option.eq_none_iff_forall_ne_some]

/-- With no registration at this key and genuine termination tags, its
expected mint quantity is minus the number of selected terminations. -/
theorem foldMint_termination_quantity (cfg : Singular.Config)
    (members : List Singular.FoldMember) (aid : Nat)
    (noRegistration : ∀ b, .registration b ∈ members → b.request.key ≠ aid)
    (tags : ∀ b, .termination b ∈ members → b.request.singularTags = [cfg.singularTag b.request.key]) :
    (((Singular.foldMint cfg members).filter (fun pair =>
      decide (pair.1 = cfg.singularTag aid))).map Prod.snd).sum =
        -((terminationKeys members).count aid : Int) := by
  induction members with
  | nil => simp [Singular.foldMint, terminationKeys]
  | cons member rest ih =>
    have tail := ih (fun b selected => noRegistration b (List.mem_cons_of_mem member selected))
      (fun b selected => tags b (List.mem_cons_of_mem member selected))
    cases member with
    | registration b =>
      have different := noRegistration b List.mem_cons_self
      have tagDifferent : cfg.singularTag b.request.key ≠ cfg.singularTag aid := by
        intro same; exact different ((singularTag_key_iff cfg _ _).mp same)
      simpa [Singular.foldMint, terminationKeys, tagDifferent] using tail
    | termination b =>
      have tag := tags b List.mem_cons_self
      by_cases same : b.request.key = aid
      · simp [Singular.foldMint, terminationKeys, tag, same] at tail ⊢
        omega
      · have tagDifferent : cfg.singularTag b.request.key ≠ cfg.singularTag aid := by
          intro equal; exact same ((singularTag_key_iff cfg _ _).mp equal)
        simpa [Singular.foldMint, terminationKeys, tag, tagDifferent, same] using tail

/-- Without a registration at this key, no carrier output for its exact tag
is created by the imported routing contract. -/
theorem foldCarrierTags_absent (cfg : Singular.Config) (members : List Singular.FoldMember)
    (aid : Nat) (noRegistration : ∀ b, .registration b ∈ members → b.request.key ≠ aid) :
    cfg.singularTag aid ∉ Singular.foldCarrierTags cfg members := by
  intro member
  obtain ⟨m, selected, tag⟩ := List.mem_filterMap.mp member
  cases m with
  | registration b =>
    have same : cfg.singularTag b.request.key = cfg.singularTag aid := by simpa using tag
    exact noRegistration b selected ((singularTag_key_iff cfg _ _).mp same)
  | termination b => contradiction

/-- A consumed pending request burns exactly one of its own singular tag and
creates no output carrying that tag, even in an accepted mixed fold. -/
theorem booked_fold_token_effects (p : Params) (env : Env) {s s' : Sys}
    (hw : WellFormed p s) {gen plugin : Nat} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s'))
    {ref : Singular.OutRef} {e : TerminationEntry} (hp : pendingAt s ref = some e)
    (consumed : Singular.inputsContainReference tx.transaction.inputs ref = true) :
    ((tx.singularMint.filter (fun pair =>
      decide (pair.1 = s.config.singularTag e.payload.aid))).map Prod.snd).sum = -1 ∧
    (tx.outputs.flatMap (·.singularTags)).count (s.config.singularTag e.payload.aid) = 0 := by
  have shape := hw.terminationShape e (pending_lookup_mem s ref e hp).1
  have selected := consumed_pending_member p hw hp consumed
  have noRegistration : ∀ b, .registration b ∈ Singular.foldMembers s.toWorld tx →
      b.request.key ≠ e.payload.aid := by
    intro b member same
    have fresh := fold_registration_binding_fresh p env hw hs b member
    rw [same, shape.2.2.2.2.2.2.2.2.2.1] at fresh
    contradiction
  have tags : ∀ b, .termination b ∈ Singular.foldMembers s.toWorld tx →
      b.request.singularTags = [s.config.singularTag b.request.key] := by
    intro b member
    exact (Singular.reachable_pending_custody_shape s.toWorld hw.worldReachable b
      (Singular.foldMembers_termination member).1).1
  have keyMember : e.payload.aid ∈ terminationKeys (Singular.foldMembers s.toWorld tx) :=
    List.mem_filterMap.mpr ⟨.termination e.booking, selected, by simp [shape.1]⟩
  have count : (terminationKeys (Singular.foldMembers s.toWorld tx)).count e.payload.aid = 1 := by
    rw [(fold_termination_keys_unique p env hs).count]
    simp [keyMember]
  have expected := foldMint_termination_quantity s.config (Singular.foldMembers s.toWorld tx)
    e.payload.aid noRegistration tags
  have expectedOne : (((Singular.foldMint s.config (Singular.foldMembers s.toWorld tx)).filter
      (fun pair => decide (pair.1 = s.config.singularTag e.payload.aid))).map Prod.snd).sum = -1 := by
    simpa [count] using expected
  obtain ⟨_, result, _, routing, _⟩ := Singular.foldAccepted_checks (fold_sound p env hs).2.2.2.1
  constructor
  · have pairMember : (s.config.singularTag e.payload.aid, (-1 : Int)) ∈
        Singular.foldMint s.config (Singular.foldMembers s.toWorld tx) := by
      apply List.mem_flatMap.mpr
      exact ⟨.termination e.booking, selected, by simp [tags e.booking selected, shape.1]⟩
    have checked := routing_mint_checked routing
    unfold Singular.foldSameQuantities at checked
    have quantity := List.all_eq_true.mp checked (s.config.singularTag e.payload.aid)
      (List.mem_append.mpr (Or.inr (List.mem_map.mpr ⟨_, pairMember, rfl⟩)))
    have same : ((tx.singularMint.filter (fun pair =>
        decide (pair.1 = s.config.singularTag e.payload.aid))).map Prod.snd).sum =
        (((Singular.foldMint s.config (Singular.foldMembers s.toWorld tx)).filter
        (fun pair => decide (pair.1 = s.config.singularTag e.payload.aid))).map Prod.snd).sum := by
      simpa only [decide_eq_true_eq] using quantity
    exact same.trans expectedOne
  · rw [(Singular.foldRouting_partitions routing).2.2.1.count_eq]
    exact List.count_eq_zero_of_not_mem (foldCarrierTags_absent s.config _ e.payload.aid noRegistration)

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
theorem fold_consumes_exact (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} (hr : Reach p env cfg s) {gen plugin : Nat}
    {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction} {f : Flow}
    (hs : fold p env s gen plugin u tx = .ok (f, s'))
    {ref : Singular.OutRef} {e : TerminationEntry}
    (hp : pendingAt s ref = some e)
    (hc : Singular.inputsContainReference tx.transaction.inputs ref = true) :
    pendingAt s' ref = none ∧ carrierAt s' e.payload.aid = none ∧
    Singular.trieGet s'.trie e.payload.aid = .known .terminal ∧
    Singular.worldSingularSupply s'.toWorld e.payload.aid = 0 ∧
    bindingAt s' e.payload.aid = some e.payload.token ∧
    ((tx.singularMint.filter (fun pair =>
      decide (pair.1 = s.config.singularTag e.payload.aid))).map Prod.snd).sum = -1 ∧
    (tx.outputs.flatMap (·.singularTags)).count (s.config.singularTag e.payload.aid) = 0 := by
  have before := reachable_wellFormed p env cfg hr
  have after := wellFormed_fold p env before hs
  have shape := before.terminationShape e (pending_lookup_mem s ref e hp).1
  have selected := consumed_pending_member p before hp hc
  obtain ⟨result, batch, effect⟩ := Singular.economic_fold_registry_correspondence
    (fold_sound p env hs).2.2.2.1
  have trie : s'.trie = result.state.trie := congrArg Singular.RegistryState.trie effect
  have terminal : Singular.trieGet s'.trie e.payload.aid = .known .terminal := by
    rw [trie]
    have final := generic_fold_selected_terminal _ _ result
      (Singular.foldLegacyRequest s.config (.termination e.booking))
      (List.mem_map.mpr ⟨.termination e.booking, selected, rfl⟩) rfl
      (Singular.foldBatch_inv _ _ _ batch).2
    simpa only [Singular.foldLegacyRequest, shape.1] using final
  have noCarrier := (terminal_no_custody p after e.payload.aid terminal).1
  have supply : Singular.worldSingularSupply s'.toWorld e.payload.aid = 0 :=
    (Singular.Statements.world_supply_sync s'.toWorld after.worldReachable e.payload.aid).2.1.mpr
      (by simp [Sys.toWorld, terminal])
  have alias := fold_old_binding p env before hs e.payload.aid e.payload.token
    shape.2.2.2.2.2.2.2.2.2.1
  exact ⟨fold_pending_consumed p env hs ref hc, noCarrier, terminal, supply, alias,
    booked_fold_token_effects p env before hs hp hc⟩

/-- Given an actual reachable/executed FoldReceipt and exact Completes relation;
when using it for a Checkpoint focused completion; then actual imported
acceptance, exact removal/retirement/supply/alias effects hold. If its tx did
not consume the reference, that receipt cannot complete it. Wrong AID or alias
must fail the full lookup binding; unrelated receipt and wrong pending-key
controls are distinct. Full transactions remain authoritative over all their
members; this receipt cannot stand for an unexecuted proposed fold. -/
theorem completion_receipt_effects (p : Params) (env : Env) (cfg : Singular.Config)
    (r : FoldReceipt p env cfg) (ref : Singular.OutRef) (aid token : Nat)
    (hc : Completes r ref aid token) :
    Singular.foldAccepted r.before.toWorld r.unspent r.transaction = .ok r.after.toWorld ∧
    pendingAt r.after ref = none ∧ carrierAt r.after aid = none ∧
    Singular.trieGet r.after.trie aid = .known .terminal ∧
    Singular.worldSingularSupply r.after.toWorld aid = 0 ∧
    bindingAt r.after aid = some token := by
  obtain ⟨e, pending, aidEqual, tokenEqual, consumed⟩ := hc
  have effects := fold_consumes_exact p env cfg r.reachable r.executed pending consumed
  refine ⟨(fold_sound p env r.executed).2.2.2.1, effects.1, ?_, ?_, ?_, ?_⟩
  · simpa [aidEqual] using effects.2.1
  · simpa [aidEqual] using effects.2.2.1
  · simpa [aidEqual] using effects.2.2.2.1
  · simpa [aidEqual, tokenEqual] using effects.2.2.2.2.1

end CardanoKeri.Registry
