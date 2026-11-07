import CardanoKeri.RegistryCustody

/-! The registration request lifecycle. Until its deadline a booked
registration is spent only by a fold that delivers its committed checkpoint.
After it, anyone may return it, paying its refund address everything but its
declared tip, which the spender may keep. A pending termination is not a
request of this kind: only the registry's terminating fold consumes it. -/
namespace CardanoKeri.Registry

/-- A unique reference finds its own booking. -/
theorem registration_find_unique {pool : List Singular.RegistrationBooking}
    (unique : (pool.map (·.request.reference)).Nodup) {b : Singular.RegistrationBooking}
    (member : b ∈ pool) :
    pool.find? (fun x => x.request.reference == b.request.reference) = some b := by
  induction pool with
  | nil => simp at member
  | cons x rest ih =>
    simp only [List.map_cons, List.nodup_cons] at unique
    rcases List.mem_cons.mp member with rfl | later
    · simp
    · have different : x.request.reference ≠ b.request.reference := by
        intro same
        exact unique.1 (same ▸ List.mem_map.mpr ⟨b, later, rfl⟩)
      simp [different, ih unique.2 later]

/-- A well-formed system books each registration reference once. -/
theorem registration_refs_unique {p : Params} {s : Sys} (hw : WellFormed p s) :
    (s.registrations.map (·.request.reference)).Nodup :=
  (List.nodup_append.mp hw.requestRefs).1

/-- An accepted economic fold checks every member's window. -/
theorem foldPrerequisite_window {world : Singular.World} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} (h : Singular.foldPrerequisite world u tx = none) :
    ∃ interval, tx.transaction.validity = some interval ∧
      ∀ member ∈ Singular.foldMembers world tx,
        Singular.foldMemberRefusal world.registry.config interval member = none := by
  unfold Singular.foldPrerequisite at h
  simp only [bind, pure, Option.bind] at h
  repeat (split at h <;> try contradiction)
  all_goals simp_all [← Option.eq_none_iff_forall_ne_some, List.findSome?_eq_none_iff]

/-- A fold spending a booked registration's output selects that registration. -/
theorem consumed_registration_selected {p : Params} {s : Sys} (hw : WellFormed p s)
    {tx : Singular.EconomicTransaction} {b : Singular.RegistrationBooking}
    (hb : b ∈ s.registrations)
    (consumed : Singular.inputsContainReference tx.transaction.inputs b.request.reference = true) :
    Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx := by
  obtain ⟨input, member, ref⟩ := List.any_eq_true.mp consumed
  have ref : input.ref = some b.request.reference := of_decide_eq_true ref
  have found : Singular.foldMemberAt s.toWorld b.request.reference = some (.registration b) := by
    have lookup := registration_find_unique (registration_refs_unique hw) hb
    simp [Singular.foldMemberAt, Sys.toWorld, lookup]
  unfold Singular.foldMembers
  exact List.mem_filterMap.mpr ⟨input, member, by simp [ref, found]⟩

/-- Given a fold that selects a booked registration; when the fold is
accepted; then its whole validity interval starts no earlier than the booking
and ends by the request's deadline. -/
theorem fold_ends_by_deadline (p : Params) (env : Env) {s s' : Sys}
    {gen plugin : Nat} {u : Singular.EconomicUtxo} {tx : Singular.EconomicTransaction}
    {f : Flow} (hs : fold p env s gen plugin u tx = .ok (f, s'))
    {b : Singular.RegistrationBooking}
    (selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx) :
    ∃ interval, tx.transaction.validity = some interval ∧
      b.request.submittedAt ≤ interval.lower ∧ interval.upper ≤ deadline s.config b.request := by
  have accepted := (fold_sound p env hs).2.2.2.1
  obtain ⟨interval, validity, members⟩ :=
    foldPrerequisite_window (Singular.foldAccepted_checks accepted).1
  have refusal := members _ selected
  simp only [Singular.foldMemberRefusal, Singular.inPhase1] at refusal
  refine ⟨interval, validity, ?_, ?_⟩
  · apply Classical.byContradiction
    intro early
    simp [Nat.lt_of_not_le early] at refusal
  · apply Classical.byContradiction
    intro late
    have : ¬ interval.upper ≤ b.request.submittedAt + s.toWorld.registry.config.processTime :=
      late
    simp [this] at refusal

/-- Given an accepted return naming a booked registration's reference; when
reading its validity interval; then the interval starts no earlier than that
request's deadline. -/
theorem return_starts_at_deadline (p : Params) {s s' : Sys} (hw : WellFormed p s)
    {u : Singular.EconomicUtxo} {tx : Singular.Rejection} {f : Flow}
    (hs : returnRequests s u tx = .ok (f, s')) {b : Singular.RegistrationBooking}
    (hb : b ∈ s.registrations) {member : Singular.OutRef × Singular.RejectReason}
    (named : member ∈ tx.members) (ref : member.1 = b.request.reference) :
    ∃ interval, tx.transaction.transaction.validity = some interval ∧
      deadline s.config b.request ≤ interval.lower := by
  obtain ⟨⟨interval, validity, _, ready⟩, _⟩ := return_sound s s' u tx f hs
  refine ⟨interval, validity, ?_⟩
  have checked := List.all_eq_true.mp ready member named
  have lookup : returnedRegistration s member = some b := by
    unfold returnedRegistration
    rw [ref]
    exact registration_find_unique (registration_refs_unique hw) hb
  simpa [returnMemberReady, lookup] using checked

/-- A return removes exactly the registrations its members name. -/
theorem return_registrations (s s' : Sys) {u : Singular.EconomicUtxo}
    {tx : Singular.Rejection} {f : Flow} (hs : returnRequests s u tx = .ok (f, s')) :
    s'.registrations = s.registrations.filter (fun b =>
      !(tx.members.any fun m => m.1 == b.request.reference)) := by
  have facts := return_sound s s' u tx f hs
  have effect := Singular.rejectionAccepted_effect facts.2.2.1
  have pending := congrArg Singular.World.pending effect
  simpa [Sys.toWorld, Singular.rejectionEffect] using pending

/-- Given a reachable-shape system, a booked registration and any accepted
step whose successor no longer holds it; when classifying the step; then it
is either a fold whose validity interval ends by the request's deadline, or a
return whose validity interval starts at or after it. No other action, and no
signature of the requester, spends a booked registration. -/
theorem consumed_registration_spends (p : Params) (env : Env) {s s' : Sys}
    (hw : WellFormed p s) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) {b : Singular.RegistrationBooking}
    (hb : b ∈ s.registrations) (gone : b ∉ s'.registrations) :
    (∃ gen plugin u tx interval, action = .fold gen plugin u tx ∧
      tx.transaction.validity = some interval ∧
      interval.upper ≤ deadline s.config b.request) ∨
    (∃ u tx interval, action = .returnRequests u tx ∧
      tx.transaction.transaction.validity = some interval ∧
      deadline s.config b.request ≤ interval.lower) := by
  cases action with
  | bookRegistration booking =>
    obtain ⟨_, _, registrations, _⟩ := bookRegistration_sound p hs
    exact False.elim (gone (registrations ▸ List.mem_cons_of_mem _ hb))
  | convictCkpt aid =>
    obtain ⟨c, _, _, _, _, rfl⟩ := (convictCkpt_iff env s s' aid f).mp hs
    exact False.elim (gone hb)
  | bookTermination aid booker fee booking =>
    obtain ⟨c, world, _, _, _, _, _, _, _, _, _, _, rfl, _, _⟩ :=
      (bookTermination_iff p s s' aid booker fee booking f).mp hs
    exact False.elim (gone hb)
  | fold gen plugin u tx =>
    have registrations := (fold_sound p env hs).2.2.2.2.2.1
    have consumed : Singular.inputsContainReference tx.transaction.inputs
        b.request.reference = true := by
      apply Classical.byContradiction
      intro kept
      exact gone (registrations ▸ List.mem_filter.mpr ⟨hb, by simpa using kept⟩)
    obtain ⟨interval, validity, _, upper⟩ :=
      fold_ends_by_deadline p env hs (consumed_registration_selected hw hb consumed)
    exact Or.inl ⟨gen, plugin, u, tx, interval, rfl, validity, upper⟩
  | returnRequests u tx =>
    change returnRequests s u tx = .ok (f, s') at hs
    have registrations := return_registrations s s' hs
    have named : (tx.members.any fun m => m.1 == b.request.reference) = true := by
      cases kept : (tx.members.any fun m => m.1 == b.request.reference)
      · exact False.elim (gone (registrations ▸ List.mem_filter.mpr ⟨hb, by simp [kept]⟩))
      · rfl
    obtain ⟨member, mem, ref⟩ := List.any_eq_true.mp named
    obtain ⟨interval, validity, ready⟩ :=
      return_starts_at_deadline p hw hs hb mem (by simpa using ref)
    exact Or.inr ⟨u, tx, interval, rfl, validity, ready⟩

/-- Given a booked registration and a step that spends it but is not a fold;
when reading the step; then it is a return that cannot be valid before the
request's deadline. Until the deadline nobody, the requester included, can
cancel, reclaim or clean up the request. -/
theorem window_spend_is_fold (p : Params) (env : Env) {s s' : Sys}
    (hw : WellFormed p s) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) {b : Singular.RegistrationBooking}
    (hb : b ∈ s.registrations) (gone : b ∉ s'.registrations)
    (notFold : ∀ gen plugin u tx, action ≠ .fold gen plugin u tx) :
    ∃ u tx interval, action = .returnRequests u tx ∧
      tx.transaction.transaction.validity = some interval ∧
      deadline s.config b.request ≤ interval.lower := by
  rcases consumed_registration_spends p env hw hs hb gone with
    ⟨gen, plugin, u, tx, _, rfl, _⟩ | spent
  · exact False.elim (notFold gen plugin u tx rfl)
  · exact spent

/-- A member of a list of naturals is at most its sum. -/
theorem le_sum_of_mem {l : List Nat} {x : Nat} (member : x ∈ l) : x ≤ l.sum := by
  induction l with
  | nil => simp at member
  | cons y rest ih =>
    rcases List.mem_cons.mp member with rfl | later
    · simp
    · simp only [List.sum_cons]
      exact Nat.le_trans (ih later) (Nat.le_add_left _ _)

/-- Given an accepted return naming a booked registration; when reading the
outputs at the request's refund address; then they hold at least the
request's contents less its declared tip, so the refund cannot be redirected or
reduced; the spender may keep the tip. -/
theorem return_pays_refund_address (p : Params) {s s' : Sys} (hw : WellFormed p s)
    {u : Singular.EconomicUtxo} {tx : Singular.Rejection} {f : Flow}
    (hs : returnRequests s u tx = .ok (f, s')) {b : Singular.RegistrationBooking}
    (hb : b ∈ s.registrations) {member : Singular.OutRef × Singular.RejectReason}
    (named : member ∈ tx.members) (ref : member.1 = b.request.reference) :
    b.request.contents.lovelace - b.request.declaredTip ≤
      Singular.refundPaid tx.transaction b.request.refundAddress := by
  have floor := return_refund_floor s s' u tx f hs b.request.refundAddress
  have returned : b.request ∈ Singular.rejectedRequests s.toWorld tx.members := by
    unfold Singular.rejectedRequests
    apply List.mem_filterMap.mpr
    refine ⟨member, named, ?_⟩
    rw [ref]
    have lookup := registration_find_unique (registration_refs_unique hw) hb
    simp [Sys.toWorld, lookup]
  have owed : b.request.contents.lovelace - b.request.declaredTip ≤
      Singular.refundOwed (Singular.rejectedRequests s.toWorld tx.members) false
        b.request.refundAddress := by
    unfold Singular.refundOwed
    apply le_sum_of_mem
    exact List.mem_map.mpr ⟨b.request, List.mem_filter.mpr ⟨returned, by simp⟩,
      by simp [Singular.refundAmount]⟩
  exact Nat.le_trans owed floor

/-- Given a booked registration whose key is already active or terminal (a
duplicate); when any accepted step spends it; then that step is a return valid
only from the request's deadline. A duplicate cannot be folded, so it waits for
the deadline and is then recoverable by anyone at its refund address. -/
theorem duplicate_returned_after_deadline (p : Params) (env : Env) {s s' : Sys}
    (hw : WellFormed p s) {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) {b : Singular.RegistrationBooking}
    (hb : b ∈ s.registrations) (gone : b ∉ s'.registrations)
    (known : Singular.trieGet s.trie b.request.key = .known .active ∨
      Singular.trieGet s.trie b.request.key = .known .terminal) :
    ∃ u tx interval, action = .returnRequests u tx ∧
      tx.transaction.transaction.validity = some interval ∧
      deadline s.config b.request ≤ interval.lower := by
  apply window_spend_is_fold p env hw hs hb gone
  intro gen plugin u tx same
  subst same
  have folded : fold p env s gen plugin u tx = .ok (f, s') := hs
  have registrations := (fold_sound p env folded).2.2.2.2.2.1
  have consumed : Singular.inputsContainReference tx.transaction.inputs
      b.request.reference = true := by
    apply Classical.byContradiction
    intro kept
    exact gone (registrations ▸ List.mem_filter.mpr ⟨hb, by simpa using kept⟩)
  have refused := registered_registration_refused p env s gen plugin u tx b
    (consumed_registration_selected hw hb consumed) known
  simp [folded, Except.toOption] at refused

/-- Given a pending termination; when any accepted step
consumes its reference; then that step is a fold. The pending-termination
output is not a registration request: neither the deadline nor the return
applies to it. -/
theorem termination_custody_only_fold (p : Params) (env : Env)
    {s s' : Sys} {action : Action} {f : Flow}
    (hs : stepFn p env action s = .ok (f, s')) (ref : Singular.OutRef)
    (e : TerminationEntry) (hp : pendingAt s ref = some e)
    (gone : pendingAt s' ref ≠ some e) : ConsumesPending ref action := by
  apply Classical.byContradiction
  intro kept
  exact gone (pending_record_frame p env hs ref e hp kept)

end CardanoKeri.Registry
