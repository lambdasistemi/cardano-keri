import CardanoKeri.RegistryInvariant

/-! Internal proof decomposition of the complete application invariant.
These predicates add no transition guards or acceptance premises. -/
namespace CardanoKeri.Registry

/-- The application-owned fields of WellFormed, separated from the imported
trie and World facts for induction over the metadata installer. -/
structure Metadata (p : Params) (s : Sys) : Prop where
  bindingKeys : (s.bindings.map Prod.fst).Nodup
  bindingAliases : (s.bindings.map Prod.snd).Nodup
  allocated : ∀ aid tok, (aid, tok) ∈ s.bindings → tok < s.nextToken
  carrierKeys : (s.carriers.map (·.aid)).Nodup
  terminationKeys : (s.terminations.map (·.payload.aid)).Nodup
  carrierShape : ∀ c ∈ s.carriers,
    c.original.key = c.aid ∧ c.original.kind = .active ∧ c.minAda = p.Mc ∧
    bindingAt s c.aid = some c.token ∧
    ∀ e ∈ s.terminations, e.payload.aid ≠ c.aid
  registrationValues : ∀ b ∈ s.registrations, registrationShape p b
  terminationShape : ∀ e ∈ s.terminations,
    e.booking.request.key = e.payload.aid ∧
    e.booking.request.destination = e.payload.original.output ∧
    e.payload.original.key = e.payload.aid ∧ e.payload.original.kind = .active ∧
    e.booking.custodyInputs = [e.payload.original] ∧
    e.booking.request.carrierAda = p.Mr ∧ e.booking.request.declaredTip = p.tip ∧
    e.booking.request.contents.lovelace = p.Mr + p.tip ∧
    e.booking.request.singularTags = [s.config.singularTag e.payload.aid] ∧
    bindingAt s e.payload.aid = some e.payload.token

/-- Every whole invariant supplies its application metadata clauses. -/
theorem WellFormed.metadata {p : Params} {s : Sys} (hw : WellFormed p s) : Metadata p s := by
  refine ⟨hw.bindingKeys, hw.bindingAliases, hw.allocated, hw.carrierKeys,
    hw.terminationKeys, ?_, hw.registrationValues, ?_⟩
  · intro c member
    have facts := hw.carrierShape c member
    exact ⟨facts.1, facts.2.1, facts.2.2.1, facts.2.2.2.1, facts.2.2.2.2.2⟩
  · intro e member
    have facts := hw.terminationShape e member
    exact ⟨facts.1, facts.2.1, facts.2.2.1, facts.2.2.2.1, facts.2.2.2.2.1,
      facts.2.2.2.2.2.1, facts.2.2.2.2.2.2.1, facts.2.2.2.2.2.2.2.1,
      facts.2.2.2.2.2.2.2.2.1, facts.2.2.2.2.2.2.2.2.2.1⟩

/-- An absent lookup means no binding pair has that key. -/
theorem bindingAt_none_key {s : Sys} {aid : Nat} (absent : bindingAt s aid = none) :
    ∀ token, (aid, token) ∉ s.bindings := by
  unfold bindingAt at absent
  have missing : s.bindings.find? (fun e => e.1 == aid) = none := by
    cases found : s.bindings.find? (fun e => e.1 == aid) with
    | none => rfl
    | some pair => simp [found] at absent
  intro token member
  have no := List.find?_eq_none.mp missing (aid, token) member
  simp at no

/-- Adding a fresh carrier with the next alias preserves the application
metadata, including every old carrier, pending record and allocated alias. -/
theorem Metadata.add_carrier {p : Params} {s : Sys} (hm : Metadata p s)
    (c : Carrier) (fresh : bindingAt s c.aid = none)
    (shape : c.original.key = c.aid ∧ c.original.kind = .active ∧
      c.minAda = p.Mc ∧ c.token = s.nextToken) :
    Metadata p { s with
      carriers := c :: s.carriers, bindings := (c.aid, c.token) :: s.bindings,
      nextToken := s.nextToken + 1 } := by
  have noCarrier : ∀ old ∈ s.carriers, old.aid ≠ c.aid := by
    intro old member equal
    have binding := (hm.carrierShape old member).2.2.2.1
    rw [equal, fresh] at binding
    contradiction
  have noTermination : ∀ e ∈ s.terminations, e.payload.aid ≠ c.aid := by
    intro e member equal
    have binding := (hm.terminationShape e member).2.2.2.2.2.2.2.2.2
    rw [equal, fresh] at binding
    contradiction
  have oldBinding (aid : Nat) (different : aid ≠ c.aid) :
      bindingAt { s with
        carriers := c :: s.carriers, bindings := (c.aid, c.token) :: s.bindings,
        nextToken := s.nextToken + 1 } aid = bindingAt s aid := by
    simp [bindingAt, Ne.symm different]
  constructor
  · simp only [List.map_cons, List.nodup_cons]
    refine ⟨?_, hm.bindingKeys⟩
    intro selected
    obtain ⟨pair, member, equal⟩ := List.mem_map.mp selected
    exact bindingAt_none_key fresh pair.2 (by simpa [← equal] using member)
  · simp only [List.map_cons, List.nodup_cons]
    refine ⟨?_, hm.bindingAliases⟩
    intro member
    obtain ⟨pair, member, equal⟩ := List.mem_map.mp member
    have allocated := hm.allocated pair.1 pair.2 member
    have next := shape.2.2.2
    omega
  · intro aid token member
    rcases List.mem_cons.mp member with equal | old
    · cases equal
      change c.token < s.nextToken + 1
      have next := shape.2.2.2
      omega
    · exact Nat.lt_trans (hm.allocated aid token old) (Nat.lt_succ_self _)
  · simp only [List.map_cons, List.nodup_cons]
    refine ⟨?_, hm.carrierKeys⟩
    intro member
    obtain ⟨old, member, equal⟩ := List.mem_map.mp member
    exact noCarrier old member equal
  · exact hm.terminationKeys
  · intro old member
    rcases List.mem_cons.mp member with rfl | member
    · exact ⟨shape.1, shape.2.1, shape.2.2.1, by simp [bindingAt], noTermination⟩
    · have facts := hm.carrierShape old member
      exact ⟨facts.1, facts.2.1, facts.2.2.1,
        by rw [oldBinding old.aid (noCarrier old member)]; exact facts.2.2.2.1,
        facts.2.2.2.2⟩
  · exact hm.registrationValues
  · intro e member
    have facts := hm.terminationShape e member
    refine ⟨facts.1, facts.2.1, facts.2.2.1, facts.2.2.2.1, facts.2.2.2.2.1,
      facts.2.2.2.2.2.1, facts.2.2.2.2.2.2.1, facts.2.2.2.2.2.2.2.1,
      facts.2.2.2.2.2.2.2.2.1, ?_⟩
    rw [oldBinding e.payload.aid (noTermination e member)]
    exact facts.2.2.2.2.2.2.2.2.2

/-- Filtering pending pools and updating only the root, trie, treasury and
generation preserves all remaining application metadata. -/
theorem Metadata.transport {p : Params} {s s' : Sys} (hm : Metadata p s)
    (carriers : s'.carriers = s.carriers) (bindings : s'.bindings = s.bindings)
    (next : s'.nextToken = s.nextToken) (regs : s'.registrations.Sublist s.registrations)
    (terms : s'.terminations.Sublist s.terminations)
    (config : s'.config = { s.config with root := s'.config.root }) : Metadata p s' := by
  have binding (aid : Nat) : bindingAt s' aid = bindingAt s aid := by simp [bindingAt, bindings]
  refine ⟨by simpa [bindings] using hm.bindingKeys,
    by simpa [bindings] using hm.bindingAliases, ?_,
    by simpa [carriers] using hm.carrierKeys,
    hm.terminationKeys.sublist (List.Sublist.map _ terms), ?_, ?_, ?_⟩
  · intro aid token member
    rw [bindings] at member
    rw [next]
    exact hm.allocated aid token member
  · intro c member
    rw [carriers] at member
    have facts := hm.carrierShape c member
    exact ⟨facts.1, facts.2.1, facts.2.2.1, by rw [binding]; exact facts.2.2.2.1,
      fun e old => facts.2.2.2.2 e (terms.subset old)⟩
  · intro b member
    exact hm.registrationValues b (regs.subset member)
  · intro e member
    have facts := hm.terminationShape e (terms.subset member)
    refine ⟨facts.1, facts.2.1, facts.2.2.1, facts.2.2.2.1, facts.2.2.2.2.1,
      facts.2.2.2.2.2.1, facts.2.2.2.2.2.2.1, facts.2.2.2.2.2.2.2.1, ?_, ?_⟩
    · rw [config]
      exact facts.2.2.2.2.2.2.2.2.1
    · rw [binding]; exact facts.2.2.2.2.2.2.2.2.2

/-- A well-shaped actual carrier contributes positive generic supply, so its
leaf is active in every reachable projected World. -/
theorem Metadata.carrier_active {p : Params} {s : Sys} (hm : Metadata p s)
    (world : Singular.WorldReachable s.toWorld) (c : Carrier) (member : c ∈ s.carriers) :
    Singular.trieGet s.trie c.aid = .known .active := by
  have shape := hm.carrierShape c member
  have positive : 0 < Singular.kindCount s.toWorld.registry .active c.aid := by
    apply List.length_pos_iff_exists_mem.mpr
    refine ⟨c.original, List.mem_filter.mpr ⟨List.mem_map.mpr ⟨c, member, rfl⟩, ?_⟩⟩
    simp [shape.1, shape.2.1]
  by_cases active : Singular.trieGet s.trie c.aid = .known .active
  · exact active
  · have zero := (Singular.Statements.world_supply_sync s.toWorld world c.aid).2.1.mpr active
    unfold Singular.worldSingularSupply at zero
    omega

/-- The complete invariant follows once metadata, actual generic history,
trie uniqueness and the exact alias/leaf domain have all been established. -/
theorem Metadata.wellFormed {p : Params} {s : Sys} (hm : Metadata p s)
    (world : Singular.WorldReachable s.toWorld) (trie : (s.trie.map Prod.fst).Nodup)
    (domain : ∀ aid, (∃ token, bindingAt s aid = some token) ↔
      (Singular.trieGet s.trie aid = .known .active ∨
        Singular.trieGet s.trie aid = .known .terminal)) : WellFormed p s := by
  refine ⟨trie, domain, hm.bindingKeys, hm.bindingAliases, hm.allocated,
    hm.carrierKeys, hm.terminationKeys, projected_request_refs world, ?_,
    hm.registrationValues, ?_, world⟩
  · intro c member
    have facts := hm.carrierShape c member
    exact ⟨facts.1, facts.2.1, facts.2.2.1, facts.2.2.2.1,
      hm.carrier_active world c member, facts.2.2.2.2⟩
  · intro e member
    have facts := hm.terminationShape e member
    have active := (Singular.Statements.termination_request_carries_genuine_token
      s.toWorld world e.booking (List.mem_map.mpr ⟨e, member, rfl⟩)).2.2.1
    refine ⟨facts.1, facts.2.1, facts.2.2.1, facts.2.2.2.1, facts.2.2.2.2.1,
      facts.2.2.2.2.2.1, facts.2.2.2.2.2.2.1, facts.2.2.2.2.2.2.2.1,
      facts.2.2.2.2.2.2.2.2.1, facts.2.2.2.2.2.2.2.2.2, ?_⟩
    simpa [facts.1] using active

end CardanoKeri.Registry
