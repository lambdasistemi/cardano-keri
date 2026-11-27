import CardanoKeri.CheckpointSystemEvidence
import CardanoKeri.RegistryAuthorization
import CardanoKeri.ConcreteConvictionGoals

namespace CardanoKeri.Checkpoint

/-- The successive states of an actual system execution, newest transition
first. The initial state fixes the deployment and every edge is a SysStep. -/
inductive SystemHistory (p : Params) (env : SystemEnv) (deployment : Deployment) :
    List (Sys × Sys) → Sys → Prop where
  | init : SystemHistory p env deployment [] (Sys.init deployment)
  | step {edges before after} : SystemHistory p env deployment edges before →
      SysStep p env before after → SystemHistory p env deployment ((before, after) :: edges) after

/-- Given a reachable system, when its past is retained, then it has a
history from initialization containing precisely accepted system steps. -/
theorem reachable_has_system_history {p : Params} {env : SystemEnv} {s : Sys}
    (reachable : SysReach p env s) : ∃ deployment edges, SystemHistory p env deployment edges s := by
  induction reachable with
  | init d => exact ⟨d, [], .init⟩
  | step _ next ih =>
    obtain ⟨d, edges, previous⟩ := ih
    exact ⟨d, _, .step previous next⟩

/-- A conviction of this identifier and key state inside one system edge.
The observer consumes the live input of this identifier, the local step enters
pending at its key state, and the system consumes its open commitment. -/
def ConvictionEdge (p : Params) (env : SystemEnv) (aid : AID) (key : KeyState)
    (before after : Sys) : Prop :=
  ∃ live now payee commitment flow,
    before.states aid = .present live ∧ live.hash = key ∧
    Step p (env aid) (.convict payee commitment) now (.present live) flow (.terminationPending key) ∧
    (before.revealOpen aid (.convict payee commitment) ∧ before.comparisonMatchesWriter (env aid) aid = true) ∧
    after = (before.set aid (.terminationPending key) none ((env aid).convictionSpend key.epoch key.sn)).retireRevealed (.convict payee commitment)

private theorem pending_step_origin {p : Params} {env : SystemEnv} {before after : Sys}
    {aid : AID} {key : KeyState} (step : SysStep p env before after)
    (pending : after.states aid = .terminationPending key) :
    (before.states aid = .terminationPending key ∧ after.convictions aid = before.convictions aid) ∨ ConvictionEdge p env aid key before after := by
  cases step with
  | register event =>
    obtain ⟨subject, now, refund, pool, flow, st, rp, re, cfg, receipt, booking, origin,
      _, _, registered, _, _, rfl⟩ := event
    by_cases same : aid = subject
    · subst subject
      have target : st = .terminationPending key := by simpa [Sys.installOrigin, Sys.set] using pending
      subst st
      obtain ⟨_, _, _, _, impossible, _⟩ := pending_only_by_conviction _ _ registered
      contradiction
    · exact Or.inl ⟨by simpa [Sys.installOrigin, Sys.set, same] using pending, by simp [Sys.installOrigin, Sys.set, same]⟩
  | «local» event =>
    obtain ⟨subject, action, now, flow, st, _, executed, opened, rfl⟩ := event
    by_cases same : aid = subject
    · subst subject
      have target : st = .terminationPending key := by simpa [Sys.set] using pending
      subst st
      obtain ⟨l, payee, c, wasLive, rfl, _, _, atKey⟩ := pending_only_by_conviction _ _ executed
      rw [wasLive] at executed
      exact Or.inr ⟨l, now, payee, c, flow, wasLive, atKey, executed, ⟨opened.1, by
        simpa [Sys.localWriter] using opened.2⟩, by simp [State.producingSpend]⟩
    · exact Or.inl ⟨by simpa [Sys.set, same] using pending, by simp [Sys.set, same]⟩
  | book event =>
    obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := event
    exact Or.inl ⟨pending, rfl⟩
  | complete event =>
    obtain ⟨subject, association, receipt, matching, rfl⟩ := event
    by_cases same : aid = subject
    · subst subject
      simp [Sys.finish, Sys.set] at pending
    · exact Or.inl ⟨by simpa [Sys.finish, Sys.set, same] using pending, by simp [Sys.finish, Sys.set, same]⟩
  | openCommitment event =>
    obtain ⟨c, _, _, rfl⟩ := event
    exact Or.inl ⟨pending, rfl⟩
  | reveal event =>
    obtain ⟨c, now, _, _, _, rfl⟩ := event
    exact Or.inl ⟨pending, rfl⟩
  | sweep event =>
    obtain ⟨c, now, _, _, rfl⟩ := event
    exact Or.inl ⟨pending, rfl⟩

/-- Given an execution from system initialization, when an identifier is
pending at a particular key state, then an edge of that very execution
convicted the same identifier's live checkpoint at that exact key state. -/
theorem pending_spend_in_system_history {p : Params} {env : SystemEnv}
    {d : Deployment} {edges : List (Sys × Sys)} {s : Sys} {aid : AID} {key : KeyState}
    (history : SystemHistory p env d edges s) (pending : s.states aid = .terminationPending key) :
    ∃ before after, (before, after) ∈ edges ∧ ConvictionEdge p env aid key before after ∧
      s.convictions aid = (env aid).convictionSpend key.epoch key.sn := by
  induction history with
  | init => cases pending
  | step previous step ih =>
    rcases pending_step_origin step pending with inherited | produced
    · obtain ⟨before, after, mem, edge, same⟩ := ih inherited.1
      exact ⟨before, after, List.mem_cons_of_mem _ mem, edge, inherited.2.trans same⟩
    · refine ⟨_, _, List.mem_cons_self, produced, ?_⟩
      obtain ⟨_, _, _, _, _, _, _, _, _, rfl⟩ := produced
      simp [Sys.set]


/-- Given a pending state on a system path, a conviction in that path produced it. -/
theorem pending_conviction_in_system_history {p env d edges s aid key}
    (history : SystemHistory p env d edges s) (pending : s.states aid = .terminationPending key) :
    ∃ before after, (before, after) ∈ edges ∧ ConvictionEdge p env aid key before after := by
  obtain ⟨before, after, member, edge, _⟩ := pending_spend_in_system_history history pending
  exact ⟨before, after, member, edge⟩

private theorem history_snapshots {p env d edges s} (history : SystemHistory p env d edges s) :
    OriginsReachable s ∧ PendingReachable s := by
  induction history with
  | init => exact ⟨(CertifiedSys.init _).origins, (CertifiedSys.init _).pending⟩
  | step _ step ih => exact sysstep_snapshot_reachability p env ih.1 ih.2 step

/-- Given the actual system path to a booking, when the economic entry is
associated, its origin and the producing checkpoint edge read the same
indexed output and the same full comparison, including the rival evidence. -/
theorem booking_uses_producing_spend {p env d edges s next aid association}
    (history : SystemHistory p env d edges s) (book : BookingEvent s next)
    (empty : s.pending aid = none) (installed : next.pending aid = some association) :
    s.states aid = .terminationPending association.keyState ∧
    ∃ observed before after,
      (before, after) ∈ edges ∧ ConvictionEdge p env aid association.keyState before after ∧
      (env aid).convictionSpend association.keyState.epoch association.keyState.sn = some observed ∧
      association.origin.environment.conviction aid = some observed ∧
      association.entry.payload.spend = ⟨observed.output, aid, association.keyState⟩ ∧
      Registry.ConvictionOrigin association.origin.parameters association.origin.environment
        association.origin.configuration aid association.entry.payload.token
        (some association.entry.payload.spend) association.entry.payload.original := by
  obtain ⟨subject, key, origin, prior, booked, booker, fee, b, flow, entry,
    pending, stored, _, extension, placement, lookup, _, identifier, ⟨_, receipt, shared⟩, rfl⟩ := book
  have same : aid = subject := by
    by_cases h : aid = subject
    · exact h
    · simp [Sys.associate, h, empty] at installed
  cases same
  simp [Sys.associate] at installed
  subst association
  obtain ⟨before, after, member, edge, read⟩ := pending_spend_in_system_history history pending
  refine ⟨pending, ?_⟩
  unfold bookingSharesConviction at shared
  cases found : s.convictions aid with
  | none => simp [found] at shared
  | some observed =>
    simp only [found, decide_eq_true_eq] at shared
    refine ⟨observed, before, after, member, edge,
      read.symm.trans found, shared.2, ?_, ?_⟩
    · simpa [shared.1] using receipt
    · have priorReach := extension.reachable ((history_snapshots history).1 aid origin stored)
      have bookedReach := Registry.Reach.next priorReach (action := .bookTermination aid booker fee b) placement
      have authorized := (Registry.reachable_authorization _ _ _ bookedReach).2 entry (List.mem_of_find?_eq_some lookup)
      simpa [identifier] using authorized

private theorem pending_association_source {p env s next aid association}
    (step : SysStep p env s next) (found : next.pending aid = some association) :
    s.pending aid = some association ∨ (BookingEvent s next ∧ s.pending aid = none) := by
  cases step with
  | register event =>
    obtain ⟨subject, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := event
    by_cases same : aid = subject
    · simp [Sys.installOrigin, same] at found
    · exact .inl (by simpa [Sys.installOrigin, same] using found)
  | «local» event => exact .inl (by rwa [(local_event_preserves_associations _ _ event).2] at found)
  | book event =>
    have h := event
    obtain ⟨subject, _, _, _, _, _, _, _, _, _, _, _, empty, _, _, _, _, _, _, rfl⟩ := h
    by_cases same : aid = subject
    · exact .inr ⟨event, same ▸ empty⟩
    · exact .inl (by simpa [Sys.associate, same] using found)
  | complete event =>
    obtain ⟨subject, _, _, _, rfl⟩ := event
    by_cases same : aid = subject
    · simp [Sys.finish, same] at found
    · exact .inl (by simpa [Sys.finish, same] using found)
  | openCommitment e => obtain ⟨_, _, _, rfl⟩ := e; exact .inl found
  | reveal e => obtain ⟨_, _, _, _, _, rfl⟩ := e; exact .inl found
  | sweep e => obtain ⟨_, _, _, _, rfl⟩ := e; exact .inl found

private theorem associated_spend_in_history {p env d edges s aid association}
    (history : SystemHistory p env d edges s) (stored : s.pending aid = some association) :
    ∃ observed before after, (before, after) ∈ edges ∧
      ConvictionEdge p env aid association.keyState before after ∧
      (env aid).convictionSpend association.keyState.epoch association.keyState.sn = some observed ∧
      association.origin.environment.conviction aid = some observed ∧
      association.entry.payload.spend = ⟨observed.output, aid, association.keyState⟩ := by
  induction history with
  | init => cases stored
  | step past step ih =>
    rcases pending_association_source step stored with prior | ⟨book, empty⟩
    · obtain ⟨observed, before, after, member, rest⟩ := ih prior
      exact ⟨observed, before, after, List.mem_cons_of_mem _ member, rest⟩
    · obtain ⟨_, observed, before, after, member, edge, localRead, economic, payload, _⟩ :=
        booking_uses_producing_spend past book empty stored
      exact ⟨observed, before, after, List.mem_cons_of_mem _ member, edge, localRead, economic, payload⟩

/-- The executed fold consumed the stored request and recorded the terminal
leaf. Its pending receipt identifies the full observation at a checkpoint
conviction in this system prefix. -/
def RecordedConviction (p : Params) (env : SystemEnv) (edges : List (Sys × Sys))
    (aid : AID) (association : PendingAssociation)
    (receipt : Registry.FoldReceipt association.origin.parameters association.origin.environment
      association.origin.configuration) : Prop :=
    Registry.pendingAt receipt.before association.reference = some association.entry ∧
    Singular.inputsContainReference receipt.transaction.transaction.inputs association.reference = true ∧
    Registry.pendingAt receipt.after association.reference = none ∧
    Singular.trieGet receipt.after.trie aid = .known .terminal ∧
    ∃ observed source target, (source, target) ∈ edges ∧
      ConvictionEdge p env aid association.keyState source target ∧
      (env aid).convictionSpend association.keyState.epoch association.keyState.sn = some observed ∧
      association.origin.environment.conviction aid = some observed ∧
      association.entry.payload.spend = ⟨observed.output, aid, association.keyState⟩ ∧
      CheckpointConviction.accepts (env aid).verifyRival observed.comparison.tip observed.comparison.rival = true

/-- Given a system history and its matching executed retirement fold, when the
registry consumes this identifier's request, the exact entry at the spent
reference names the output, position and rival of a conviction in the same
history. The fold removes the request and records the terminal leaf. -/
theorem terminal_fold_traces_to_conviction {p env d edges s aid} {association : PendingAssociation}
    (history : SystemHistory p env d edges s)
    (receipt : Registry.FoldReceipt association.origin.parameters association.origin.environment
      association.origin.configuration) (matching : ReceiptMatches s aid association receipt) :
    RecordedConviction p env edges aid association receipt := by
  obtain ⟨stored, _, _, _, _, exactEntry, completes⟩ := matching
  obtain ⟨_, removed, _, retired, _, _⟩ := Registry.completion_receipt_effects _ _ _ _ _ _ _ completes
  obtain ⟨_, _, _, _, consumed⟩ := completes
  obtain ⟨observed, source, target, member, edge, read, economic, payload⟩ :=
    associated_spend_in_history history stored
  refine ⟨exactEntry, consumed, removed, retired, observed, source, target, member, edge, read, economic, payload, ?_⟩
  obtain ⟨live, _, _, _, _, _, position, executed, _⟩ := edge
  obtain ⟨comparison, selected, _, _, accepted⟩ := conviction_has_spent_tip_comparison _ _ executed
  have raw : (env aid).comparison live.epoch live.sn = some observed.comparison := by
    change ((env aid).convictionSpend live.hash.epoch live.hash.sn).map _ = _
    rw [position, read]
    rfl
  rw [raw] at selected
  cases selected
  exact accepted

/-- Given a system path and any next step that newly records conviction for
an identifier, that very step completed an executed fold for the identifier.
The consumed registry entry identifies its earlier accepted checkpoint spend. -/
theorem newly_retired_leaf_has_recorded_fold {p env d edges s next aid}
    (history : SystemHistory p env d edges s) (step : SysStep p env s next)
    (wasLive : s.leaves aid ≠ .retired) (retired : next.leaves aid = .retired) :
    ∃ (association : PendingAssociation)
      (receipt : Registry.FoldReceipt association.origin.parameters association.origin.environment
        association.origin.configuration),
      ReceiptMatches s aid association receipt ∧ next = s.finish aid ∧
      RecordedConviction p env edges aid association receipt := by
  have reach : SysReach p env s := by
    clear step wasLive retired
    induction history with
    | init => exact .init _
    | step _ event ih => exact .step ih event
  have prior : s.states aid ≠ .convicted := by
    intro convicted
    exact wasLive ((T8_leaf_agrees_with_state p env reach aid).trans (by rw [convicted]; rfl))
  have terminal := (T8_leaf_states p env (.step reach step) aid).2 retired
  have localTarget {action time start flow state subject}
      (executed : Step p (env subject) action time start flow state) : state ≠ .convicted := by
    cases executed <;> simp
  have outside {subject st} :
      (if aid = subject then st else s.states aid) = .convicted → st ≠ .convicted → False := by
    by_cases same : aid = subject <;> simp [same, prior]
  cases step with
  | register event =>
    obtain ⟨subject, _, _, _, _, st, _, _, _, _, _, _, _, _, executed, _, _, rfl⟩ := event
    exact False.elim (outside (subject := subject) (st := st) terminal (localTarget executed))
  | «local» event =>
    obtain ⟨subject, _, _, _, st, _, executed, _, rfl⟩ := event
    rw [Sys.retireRevealed_states] at terminal
    exact False.elim (outside (subject := subject) (st := st) terminal (localTarget executed))
  | book event =>
    rw [(booking_event_preserves_checkpoint _ _ event).1] at terminal
    exact False.elim (prior terminal)
  | complete event =>
    obtain ⟨subject, association, receipt, matching, rfl⟩ := event
    by_cases same : aid = subject
    · cases same
      exact ⟨association, receipt, matching, rfl, terminal_fold_traces_to_conviction history receipt matching⟩
    · exact False.elim (prior (by simpa [Sys.finish, Sys.set, same] using terminal))
  | openCommitment e => obtain ⟨_, _, _, rfl⟩ := e; exact False.elim (prior terminal)
  | reveal e => obtain ⟨_, _, _, _, _, rfl⟩ := e; exact False.elim (prior terminal)
  | sweep e => obtain ⟨_, _, _, _, rfl⟩ := e; exact False.elim (prior terminal)

private def WritersAuthenticated (s : Sys) : Prop :=
  ∀ aid history, s.writers aid = some history → history.authenticated aid = true

private theorem initial_writer_authenticated {env : Env} {aid datum history}
    (installed : env.initialHistory aid datum = some history) : history.authenticated aid = true := by
  unfold Env.initialHistory at installed
  split at installed <;> try contradiction
  split at installed <;> try contradiction
  dsimp only at installed
  split at installed <;> simp_all

private theorem rotation_writer_authenticated {s : Sys} {env : Env} {aid sn history}
    (prior : WritersAuthenticated s) (accepted : s.rotationHistory env aid sn = some history) :
    history.authenticated aid = true := by
  unfold Sys.rotationHistory at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> simp_all
  subst history
  simp_all [EventHistory.authenticated, WritersAuthenticated]

private theorem local_writer_authenticated {s : Sys} {env : Env} {aid action history}
    (prior : WritersAuthenticated s) (stored : (s.localWriter env aid action).join = some history) :
    history.authenticated aid = true := by
  cases action <;> simp [Sys.localWriter] at stored
  case convict => split at stored <;> contradiction
  case rotate sn op payee =>
    cases found : s.rotationHistory env aid sn <;> simp [found] at stored
    subst history
    exact rotation_writer_authenticated prior found
  case freeze sn payee =>
    cases found : s.rotationHistory env aid sn <;> simp [found] at stored

private theorem set_writers_authenticated {s : Sys} {aid st writer}
    (prior : WritersAuthenticated s)
    (valid : ∀ h : EventHistory, writer = some h → h.authenticated aid = true) :
    WritersAuthenticated (s.set aid st writer) := by
  intro a h stored
  by_cases same : a = aid
  · subst a
    cases writer <;> simp_all [Sys.set, WritersAuthenticated]
  · exact prior a h (by simpa [Sys.set, same] using stored)

/-- Given a system reachable from its deployment, when the stored writer of
an identifier is read, then every event back to its registration authenticates
under that identifier and the predecessor installed by the preceding event. -/
theorem reachable_writer_authenticated {p : Params} {env : SystemEnv} {s : Sys}
    (reachable : SysReach p env s) {aid history} (stored : s.writers aid = some history) :
    history.authenticated aid = true := by
  suffices all : WritersAuthenticated s from all aid history stored
  clear stored history aid
  induction reachable with
  | init => intro a h absent; cases absent
  | step _ step prior =>
    cases step with
    | register registration =>
      obtain ⟨a, now, refund, pool, flow, st, rp, re, cfg, receipt, b, origin,
        _, _, _, _, facts, rfl⟩ := registration
      apply set_writers_authenticated (st := st) prior
      intro h installed
      cases installed
      exact initial_writer_authenticated facts.2
    | «local» transition =>
      obtain ⟨a, action, now, flow, st, _, _, _, rfl⟩ := transition
      have valid := set_writers_authenticated (aid := a) (st := st) prior
        (fun _ stored => local_writer_authenticated (action := action) (env := env a) prior stored)
      unfold Sys.retireRevealed
      cases action.revealed <;> exact valid
    | book booking =>
      obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := booking
      exact prior
    | complete completion =>
      obtain ⟨_, _, _, _, rfl⟩ := completion
      exact set_writers_authenticated (st := .convicted) prior (by simp)
    | openCommitment event => obtain ⟨_, _, _, rfl⟩ := event; exact prior
    | reveal event => obtain ⟨_, _, _, _, _, rfl⟩ := event; exact prior
    | sweep event => obtain ⟨_, _, _, _, rfl⟩ := event; exact prior

/-- Given the authenticated writer installed in a reachable system and a
consistent reading of the tip and rival, when the spent-tip comparison
accepts, then KERI duplicity for these two events holds exactly when the
rival is valid against that writer's actual predecessor. -/
theorem accepted_rotated_tip_iff_rival_valid {p env s aid previous writer}
    (reachable : SysReach p env s) (stored : s.writers aid = some (.rotation previous writer))
    (reads : ComparisonReads) (rival : CheckpointConviction.Rival)
    (encode : Duplicity.Content → ForwardFields)
    (fields : reads.FieldsAgree (.rotation previous writer) rival encode)
    (accepted : CheckpointConviction.accepts reads.verify (reads.tipOf (.rotation previous writer)) rival = true) :
    let tip := reads.tipOf (.rotation previous writer)
    let signed := reads.rivalOf tip rival
    Duplicity.duplicityAt tip.epoch tip.sn ⟨previous.epoch + 1, previous.predecessor, writer⟩ signed = true ↔
      Duplicity.rotationValid previous.predecessor signed = true := by
  let history := EventHistory.rotation previous writer
  let tip := reads.tipOf history
  let signed := reads.rivalOf tip rival
  obtain ⟨_, _, sameSn, _, _, _, conflict⟩ := CheckpointConviction.accepted_rival _ _ _ accepted
  have same : writer.event.sn = signed.event.sn := fields.writerPosition.symm.trans (sameSn.trans fields.rivalPosition.symm)
  have different : writer.event ≠ signed.event := by
    intro equality
    exact conflict (fields.writerFields.trans ((congrArg encode equality).trans fields.rivalFields.symm))
  change Duplicity.duplicityAt tip.epoch tip.sn _ signed = true ↔ _
  rw [show tip.epoch = previous.epoch + 1 from fields.epoch, show tip.sn = writer.event.sn from fields.writerPosition]
  exact rotated_duplicity_iff_rival_valid (reachable_writer_authenticated reachable stored) same different

private def WriterAt (writer : Option EventHistory) (position : KeyState) : Prop :=
  ∃ history, writer = some history ∧ history.epoch = position.epoch ∧
    history.writer.event.sn = position.sn

private def LiveWriters (s : Sys) : Prop :=
  ∀ aid live, s.states aid = .present live → WriterAt (s.writers aid) live.hash

/-- Given matching writers at all live identifiers, when one state is updated with its matching writer, then all live identifiers still have matching writers. -/
private theorem set_live_writers {s : Sys} {aid state writer} (old : LiveWriters s)
    (here : ∀ live, state = .present live →
      WriterAt (writer.orElse (fun _ => s.writers aid)) live.hash) :
    LiveWriters (s.set aid state writer) := by
  intro other live found
  by_cases same : other = aid
  · subst other
    simpa [Sys.set] using here live (by simpa [Sys.set] using found)
  · simpa [Sys.set, same] using old other live (by simpa [Sys.set, same] using found)

/-- Given an admitted inception read, when the initial history is installed, then it has epoch and native sequence zero. -/
private theorem inception_position {env : Env} {aid datum history}
    (found : env.initialHistory aid datum = some history) : WriterAt (some history) ⟨0, 0⟩ := by
  unfold Env.initialHistory at found
  split at found <;> try contradiction
  split at found <;> try contradiction
  dsimp only at found
  split at found <;> try contradiction
  rename_i valid
  cases found
  refine ⟨_, rfl, rfl, ?_⟩
  simp only [EventHistory.authenticated, inceptionWrites, Bool.and_eq_true, beq_iff_eq] at valid
  exact valid.1.1.1.1.1.1.1.2

/-- Given the live source, when its authenticated rotation history is found, then the writer advances one epoch and records the proposed native sequence. -/
private theorem rotation_position {s : Sys} {env aid sn history live}
    (present : s.states aid = .present live) (found : s.rotationHistory env aid sn = some history) :
    WriterAt (some history) ⟨live.epoch + 1, sn⟩ := by
  unfold Sys.rotationHistory at found
  rw [present] at found
  cases prev : s.writers aid <;> simp only [prev] at found <;> try contradiction
  split at found <;> try contradiction
  split at found <;> try contradiction
  rename_i valid
  cases found
  simp only [Bool.and_eq_true, beq_iff_eq] at valid
  exact ⟨_, rfl, congrArg (· + 1) valid.1.1.1, valid.1.2⟩

/-- Given matching live writers, when an ordinary local step produces a live output, then its selected writer has that output’s native position. -/
private theorem local_position {p env s aid action now flow state} (old : LiveWriters s)
    (ordinary : ∀ refund pool, action ≠ .register refund pool)
    (executed : Step p env action now (s.states aid) flow state)
    (writer : (s.localWriter env aid action).isSome = true) :
    ∀ live, state = .present live →
      WriterAt ((s.localWriter env aid action).join.orElse (fun _ => s.writers aid)) live.hash := by
  generalize src : s.states aid = st at executed
  cases executed <;> intro live target
  case register => exact False.elim (ordinary _ _ rfl)
  case convict => cases target
  all_goals cases target
  case poison | topUp =>
    have kept := old aid _ src
    exact kept
  case freeze =>
    simp only [Sys.localWriter] at *
    generalize found : s.rotationHistory env aid _ = result at writer ⊢
    have kept := old aid _ src
    cases result <;> exact kept
  all_goals
    simp only [Sys.localWriter] at *
    generalize found : s.rotationHistory env aid _ = result at writer ⊢
    cases result with
    | none => simp at writer
    | some h => have atPosition := rotation_position src found; exact atPosition

/-- Given a complete execution from deployment, when its live outputs are read, then each has a stored writer for its position. -/
private theorem reachable_live_writers {p env s} (reach : SysReach p env s) : LiveWriters s := by
  induction reach with
  | init => intro aid live absent; cases absent
  | @step before _ _ step old =>
    cases step with
    | register event =>
      obtain ⟨aid, now, refund, pool, flow, st, rp, re, cfg, receipt, b, origin,
        _, _, executed, _, facts, rfl⟩ := event
      apply set_live_writers old
      intro live target
      generalize src : before.states aid = prior at executed
      cases executed
      cases target
      exact inception_position facts.2
    | «local» event =>
      obtain ⟨aid, action, now, flow, st, ordinary, executed, checked, rfl⟩ := event
      have valid := set_live_writers old (local_position old ordinary executed checked.2)
      unfold Sys.retireRevealed
      cases action.revealed <;> exact valid
    | book event =>
      obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := event
      exact old
    | complete event =>
      obtain ⟨_, _, _, _, rfl⟩ := event
      apply set_live_writers old
      intro _ impossible
      cases impossible
    | openCommitment event => obtain ⟨_, _, _, rfl⟩ := event; exact old
    | reveal event => obtain ⟨_, _, _, _, _, rfl⟩ := event; exact old
    | sweep event => obtain ⟨_, _, _, _, rfl⟩ := event; exact old

/-- Given a reachable system, when an identifier has a live checkpoint, then
its stored writer exists, authenticates back to that identifier's inception,
and has exactly the epoch and native sequence of this live output. -/
theorem live_has_authenticated_writer {p env s aid live} (reach : SysReach p env s)
    (present : s.states aid = .present live) :
    ∃ history, s.writers aid = some history ∧ history.authenticated aid = true ∧
      history.epoch = live.epoch ∧ history.writer.event.sn = live.sn := by
  obtain ⟨history, stored, epoch, sn⟩ := reachable_live_writers reach aid live present
  exact ⟨history, stored, reachable_writer_authenticated reach stored, epoch, sn⟩

/-- Given a reachable system and the conviction edge for one key state,
when its live input is spent, then its stored writer authenticates under
the selected identifier and has the native position named by that edge. -/
theorem conviction_spends_authenticated_writer {p env before after aid key}
    (reach : SysReach p env before) (edge : ConvictionEdge p env aid key before after) :
    ∃ history, before.writers aid = some history ∧ history.authenticated aid = true ∧
      history.epoch = key.epoch ∧ history.writer.event.sn = key.sn := by
  obtain ⟨live, _, _, _, _, present, rfl, _⟩ := edge
  exact live_has_authenticated_writer reach present

/-- Given a conviction edge with a reachable source, when its comparison is
read, then the checkpoint's stored authenticated writer agrees with every
spent key field and the observer accepted the rival at that exact position. -/
theorem conviction_compares_authenticated_writer {p env before after aid key}
    (reach : SysReach p env before) (edge : ConvictionEdge p env aid key before after) :
    ∃ writer comparison, before.writers aid = some writer ∧ writer.authenticated aid = true ∧
      (env aid).comparison key.epoch key.sn = some comparison ∧
      (env aid).keyReads.matches aid writer comparison.tip = true ∧
      comparison.tip.epoch = key.epoch ∧ comparison.tip.sn = key.sn ∧
      CheckpointConviction.accepts (env aid).verifyRival comparison.tip comparison.rival = true := by
  obtain ⟨writer, stored, authenticated, _, _⟩ := conviction_spends_authenticated_writer reach edge
  obtain ⟨live, now, payee, c, flow, present, rfl, step, ⟨_, matched⟩, _⟩ := edge
  obtain ⟨comparison, selected, epoch, sn, accepted⟩ := conviction_has_spent_tip_comparison _ _ step
  exact ⟨writer, comparison, stored, authenticated, selected,
    by simpa [Sys.comparisonMatchesWriter, stored, present, selected] using matched, epoch, sn, accepted⟩

/-- Given a reachable conviction after rotation and consistent decoding of
the observed comparison, when KERI judges those two events, then duplicity
holds exactly when the rival passes the same predecessor's rotation rules. -/
theorem rotated_conviction_iff_rival_valid {p env before after aid key previous writer comparison}
    (reach : SysReach p env before) (edge : ConvictionEdge p env aid key before after)
    (stored : before.writers aid = some (.rotation previous writer))
    (selected : (env aid).comparison key.epoch key.sn = some comparison)
    (reads : ComparisonReads) (tip : reads.tipOf (.rotation previous writer) = comparison.tip)
    (encode : Duplicity.Content → ForwardFields)
    (fields : reads.FieldsAgree (.rotation previous writer) comparison.rival encode) :
    let rival := reads.rivalOf comparison.tip comparison.rival
    Duplicity.duplicityAt key.epoch key.sn ⟨previous.epoch + 1, previous.predecessor, writer⟩ rival = true ↔
      Duplicity.rotationValid previous.predecessor rival = true := by
  obtain ⟨_, observed, _, _, found, _, epoch, sn, accepted⟩ := conviction_compares_authenticated_writer reach edge
  rw [selected] at found
  cases found
  let actual := { reads with verify := (env aid).verifyRival }
  have judged := accepted_rotated_tip_iff_rival_valid reach stored actual comparison.rival encode
    ⟨fields.epoch, fields.writerPosition, fields.rivalPosition, fields.writerFields, fields.rivalFields⟩
    (by simpa [actual, tip] using accepted)
  simpa [actual, tip, epoch, sn] using judged

end CardanoKeri.Checkpoint
