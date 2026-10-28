import CardanoKeri.RegistryGoals

/-! Application invariant preservation for the retained-output adapter. -/
namespace CardanoKeri.Registry

/-- An edit of local state or key sequence preserves the complete invariant
when it leaves each carrier's identity, original holding and budget unchanged. -/
theorem wellFormed_carrier_edit (p : Params) {s : Sys} (hw : WellFormed p s)
    (edit : Carrier → Carrier)
    (same : ∀ c, (edit c).aid = c.aid ∧ (edit c).token = c.token ∧
      (edit c).original = c.original ∧ (edit c).minAda = c.minAda) :
    WellFormed p { s with carriers := s.carriers.map edit } := by
  have originals := carrier_edit_world s edit (fun c => (same c).2.2.1)
  refine { hw with carrierKeys := ?_, carrierShape := ?_, worldReachable := ?_ }
  · simpa only [List.map_map, Function.comp_def, (same _).1] using hw.carrierKeys
  · intro c member
    obtain ⟨before, hbefore, equal⟩ := List.mem_map.mp member
    subst c
    simpa only [(same before).1, (same before).2.1, (same before).2.2.1,
      (same before).2.2.2] using hw.carrierShape before hbefore
  · rw [originals]; exact hw.worldReachable

/-- Admitted registration recovery only filters registrations. Every other
application invariant is preserved along with actual imported reachability. -/
theorem wellFormed_recover (p : Params) {s s' : Sys} (hw : WellFormed p s)
    {world : Singular.World} (hw' : Singular.WorldReachable world)
    (hs : recoverRegistrations s world = .ok s') : WellFormed p s' := by
  unfold recoverRegistrations at hs
  simp only [bind, Except.bind, pure, Except.pure] at hs
  split at hs
  · contradiction
  · rename_i projected
    cases hs
    refine { hw with requestRefs := ?_, registrationValues := ?_, worldReachable := ?_ }
    · exact hw.requestRefs.sublist
        ((List.Sublist.map _ List.filter_sublist).append_right _)
    · intro b member
      exact hw.registrationValues b (List.mem_filter.mp member).1
    · have equal : ({ s with registrations := s.registrations.filter (fun b =>
          world.pending.contains b) } : Sys).toWorld = world := by simpa using projected
      rw [equal]; exact hw'

/-- The actual generic history supplies uniqueness across both request stores. -/
theorem projected_request_refs {s : Sys} (hw : Singular.WorldReachable s.toWorld) :
    ((s.registrations.map (·.request.reference)) ++
      s.terminations.map (·.booking.request.reference)).Nodup := by
  simpa [Singular.worldRequestReferences, Sys.toWorld, List.map_map, Function.comp_def]
    using Singular.reachable_request_references s.toWorld hw

/-- Registration admission preserves the whole application invariant and
records the declared application carrier budget for the new request. -/
theorem wellFormed_bookRegistration (p : Params) {s s' : Sys} (hw : WellFormed p s)
    {b : Singular.RegistrationBooking} {f : Flow}
    (hs : bookRegistration p s b = .ok (f, s')) : WellFormed p s' := by
  obtain ⟨shape, booked, rfl, _⟩ := bookRegistration_sound p hs
  have world := Singular.WorldReachable.booking hw.worldReachable b booked
  refine { hw with
    requestRefs := projected_request_refs world,
    registrationValues := ?_, worldReachable := world }
  intro old member
  rcases List.mem_cons.mp member with rfl | old
  · exact shape
  · exact hw.registrationValues _ old

/-- Actual termination booking moves one convicted carrier into the complete
pending store while preserving all prior records, aliases and active leaves. -/
theorem wellFormed_bookTermination (p : Params) {s s' : Sys} (hw : WellFormed p s)
    {aid booker fee : Nat} {b : Singular.TerminationBooking} {f : Flow}
    (hs : bookTermination p s aid booker fee b = .ok (f, s')) : WellFormed p s' := by
  obtain ⟨c, world, lookup, _, key, destination, custody, mc, mr, tip, held,
    booked, successor, projected, _⟩ := (bookTermination_iff p s s' aid booker fee b f).mp hs
  have cMem : c ∈ s.carriers := List.mem_of_find?_eq_some lookup
  have cAid : c.aid = aid := by simpa using List.find?_some lookup
  have shape := hw.carrierShape c cMem
  have admitted : Singular.terminationBookingRefusal s.toWorld.registry b = none := by
    unfold Singular.bookTermination at booked
    split at booked
    · contradiction
    · assumption
  have tags := (Singular.terminationBooking_custody_shape admitted).1
  have reachable : Singular.WorldReachable s'.toWorld := by
    rw [projected]
    exact .termination hw.worldReachable b booked
  subst s'
  refine { hw with
    carrierKeys := ?_, terminationKeys := ?_, requestRefs := projected_request_refs reachable,
    carrierShape := ?_, terminationShape := ?_, worldReachable := reachable }
  · exact hw.carrierKeys.sublist (List.Sublist.map _ List.filter_sublist)
  · simp only [List.map_cons, List.nodup_cons]
    refine ⟨?_, hw.terminationKeys⟩
    intro member
    obtain ⟨e, old, equal⟩ := List.mem_map.mp member
    exact (shape.2.2.2.2.2 e old) (equal.trans cAid.symm)
  · intro other member
    obtain ⟨old, different⟩ := List.mem_filter.mp member
    have data := hw.carrierShape other old
    refine ⟨data.1, data.2.1, data.2.2.1, data.2.2.2.1, data.2.2.2.2.1, ?_⟩
    intro e member
    rcases List.mem_cons.mp member with rfl | oldTerm
    · have different' : other.aid ≠ aid := by simpa using different
      exact Ne.symm different'
    · exact data.2.2.2.2.2 e oldTerm
  · intro e member
    rcases List.mem_cons.mp member with rfl | old
    · exact ⟨key, destination, shape.1.trans cAid, shape.2.1,
        custody, mr, tip, held, by simpa [Sys.toWorld, key] using tags,
        by simpa [cAid] using shape.2.2.2.1,
        by simpa [cAid] using shape.2.2.2.2.1⟩
    · exact hw.terminationShape _ old

end CardanoKeri.Registry
