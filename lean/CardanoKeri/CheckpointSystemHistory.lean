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

end CardanoKeri.Checkpoint
