import CardanoKeri.CheckpointCompletionGoals

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
    before.revealOpen aid (.convict payee commitment) ∧
    after = (before.set aid (.terminationPending key)).retireRevealed (.convict payee commitment)

private theorem pending_step_origin {p : Params} {env : SystemEnv} {before after : Sys}
    {aid : AID} {key : KeyState} (step : SysStep p env before after)
    (pending : after.states aid = .terminationPending key) :
    before.states aid = .terminationPending key ∨ ConvictionEdge p env aid key before after := by
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
    · exact Or.inl (by simpa [Sys.installOrigin, Sys.set, same] using pending)
  | «local» event =>
    obtain ⟨subject, action, now, flow, st, _, executed, opened, rfl⟩ := event
    by_cases same : aid = subject
    · subst subject
      have target : st = .terminationPending key := by simpa [Sys.set] using pending
      subst st
      obtain ⟨l, payee, c, wasLive, rfl, _, _, atKey⟩ := pending_only_by_conviction _ _ executed
      rw [wasLive] at executed
      exact Or.inr ⟨l, now, payee, c, flow, wasLive, atKey, executed, opened.1, rfl⟩
    · exact Or.inl (by simpa [Sys.set, same] using pending)
  | book event =>
    rw [(booking_event_preserves_checkpoint _ _ event).1] at pending
    exact Or.inl pending
  | complete event =>
    obtain ⟨subject, association, receipt, matching, rfl⟩ := event
    by_cases same : aid = subject
    · subst subject
      simp [Sys.finish, Sys.set] at pending
    · exact Or.inl (by simpa [Sys.finish, Sys.set, same] using pending)
  | openCommitment event =>
    obtain ⟨c, _, _, rfl⟩ := event
    exact Or.inl pending
  | reveal event =>
    obtain ⟨c, now, _, _, _, rfl⟩ := event
    exact Or.inl pending
  | sweep event =>
    obtain ⟨c, now, _, _, rfl⟩ := event
    exact Or.inl pending

/-- Given an execution from system initialization, when an identifier is
pending at a particular key state, then an edge of that very execution
convicted the same identifier's live checkpoint at that exact key state. -/
theorem pending_conviction_in_system_history {p : Params} {env : SystemEnv}
    {d : Deployment} {edges : List (Sys × Sys)} {s : Sys} {aid : AID} {key : KeyState}
    (history : SystemHistory p env d edges s) (pending : s.states aid = .terminationPending key) :
    ∃ before after, (before, after) ∈ edges ∧ ConvictionEdge p env aid key before after := by
  induction history with
  | init => cases pending
  | step previous step ih =>
    rcases pending_step_origin step pending with inherited | produced
    · obtain ⟨before, after, mem, edge⟩ := ih inherited
      exact ⟨before, after, List.mem_cons_of_mem _ mem, edge⟩
    · exact ⟨_, _, List.mem_cons_self, produced⟩

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

end CardanoKeri.Checkpoint
