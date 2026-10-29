import CardanoKeri.CheckpointGoals
import CardanoKeri.RegistryGoals

/-! Stored-origin and exact-request completion contracts. -/
namespace CardanoKeri.Checkpoint

/-- Given exact local/booking/completion events or a valid origin-indexed receipt;
when observing frame/association/retirement; then every indicated map equality,
fixed initial-config field, stored-key equality and clearing holds. A valid
same-context receipt whose before state lacks this stored request cannot
complete it. Foreign-context receipts cannot instantiate the indexed type;
that is a proof-interface exclusion, not a semantic refusal or mutation kill. -/
theorem local_event_preserves_associations (p : Params) (env : Env) {s s' : Sys}
    (h : LocalEvent p env s s') :
    s'.origins = s.origins ∧ s'.pending = s.pending := by
  obtain ⟨aid, action, now, flow, state, _, _, _, rfl⟩ := h
  exact ⟨rfl, rfl⟩

/-- Given exact local/booking/completion events or a valid origin-indexed receipt;
when observing frame/association/retirement; then every indicated map equality,
fixed initial-config field, stored-key equality and clearing holds. A valid
same-context receipt whose before state lacks this stored request cannot
complete it. Foreign-context receipts cannot instantiate the indexed type;
that is a proof-interface exclusion, not a semantic refusal or mutation kill. -/
theorem booking_event_preserves_checkpoint (s s' : Sys) (h : BookingEvent s s') :
    s'.states = s.states ∧ s'.leaves = s.leaves ∧ s'.origins = s.origins := by
  obtain ⟨aid, key, origin, before, booked, booker, fee, booking, flow, entry,
    _, _, _, _, _, _, _, _, _, rfl⟩ := h
  exact ⟨rfl, rfl, rfl⟩

/-- Given exact local/booking/completion events or a valid origin-indexed receipt;
when observing frame/association/retirement; then every indicated map equality,
fixed initial-config field, stored-key equality and clearing holds. A valid
same-context receipt whose before state lacks this stored request cannot
complete it. Foreign-context receipts cannot instantiate the indexed type;
that is a proof-interface exclusion, not a semantic refusal or mutation kill. -/
theorem indexed_receipt_preserves_origin_config
    (association : PendingAssociation)
    (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters
      association.origin.environment association.origin.configuration) :
    receipt.before.config = {
      association.origin.configuration with root := receipt.before.config.root } := by
  exact CardanoKeri.Registry.reachable_config _ _ _ receipt.reachable

/-- Given exact local/booking/completion events or a valid origin-indexed receipt;
when observing frame/association/retirement; then every indicated map equality,
fixed initial-config field, stored-key equality and clearing holds. A valid
same-context receipt whose before state lacks this stored request cannot
complete it. Foreign-context receipts cannot instantiate the indexed type;
that is a proof-interface exclusion, not a semantic refusal or mutation kill. -/
theorem receipt_missing_own_request_refused
    (s : Sys) (aid : AID) (association : PendingAssociation)
    (receipt : CardanoKeri.Registry.FoldReceipt association.origin.parameters
      association.origin.environment association.origin.configuration)
    (missing : CardanoKeri.Registry.pendingAt receipt.before association.reference = none) :
    ¬ ReceiptMatches s aid association receipt := by
  intro matching
  have present := matching.2.2.2.2.2.1
  rw [missing] at present
  contradiction

/-- Given exact local/booking/completion events or a valid origin-indexed receipt;
when observing frame/association/retirement; then every indicated map equality,
fixed initial-config field, stored-key equality and clearing holds. A valid
same-context receipt whose before state lacks this stored request cannot
complete it. Foreign-context receipts cannot instantiate the indexed type;
that is a proof-interface exclusion, not a semantic refusal or mutation kill. -/
theorem completion_uses_recorded_pending_key (s s' : Sys) (h : CompletionEvent s s') :
    ∃ aid association, s.pending aid = some association ∧
      s.origins aid = some association.origin ∧
      s.states aid = .terminationPending association.keyState ∧
      s'.states aid = .convicted ∧ s'.pending aid = none ∧
      s'.origins = s.origins := by
  obtain ⟨aid, association, receipt, matching, rfl⟩ := h
  exact ⟨aid, association, matching.1, matching.2.1, matching.2.2.1,
    by simp [Sys.finish, Sys.set], by simp [Sys.finish], rfl⟩

/-- Given any actual system step and an already stored origin, when observing that
AID afterward, the entire origin is unchanged, including fixed Registry
Params/Env/Config, exact registration snapshot, alias and output references.
Registration can install an origin only into an absent/unbound AID. Local,
booking and completion events preserve existing origins; completion clears
only the pending association. This binds all later history extensions to the
origin context rather than reselecting one at each event. -/
theorem sysstep_preserves_existing_origin (p : Params) (env : Env)
    {s s' : Sys} (hs : SysStep p env s s') (aid : AID) (origin : Origin)
    (ho : s.origins aid = some origin) : s'.origins aid = some origin := by
  cases hs with
  | register event =>
    obtain ⟨other, now, refund, pool, flow, state, rp, re, cfg, receipt, booking,
      origin', _, empty, _, _, rfl⟩ := event
    have different : aid ≠ other := by
      intro same
      subst other
      rw [empty] at ho
      contradiction
    simpa [Sys.installOrigin, Sys.set, different] using ho
  | «local» event => rw [(local_event_preserves_associations p env event).1]; exact ho
  | book event => rw [(booking_event_preserves_checkpoint _ _ event).2.2]; exact ho
  | complete event =>
    obtain ⟨other, association, receipt, _, rfl⟩ := event
    exact ho

end CardanoKeri.Checkpoint
