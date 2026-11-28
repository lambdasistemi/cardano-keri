import CardanoKeri.RegistryCompleteness
import CardanoKeri.RegistryRequestLifecycle

/-! Where the registry reads the inception evidence of a key.

A registration is booked only for a key that has its inception evidence
(`bookRegistration`). No other step reads it: a fold delivers the checkpoint
of a request that was booked, and a return pays a booked request back. So in a
reachable registry every booked request, and every checkpoint a fold
delivered, belongs to a key whose inception was shown when it was booked. -/
namespace CardanoKeri.Registry

/-- **A booking for a key without inception evidence is refused.**
Given any registry state and a registration booking whose key has no
inception evidence.
When it is booked.
Then the booking is refused: the request never enters the registry, so there
is nothing to fold or to return. -/
theorem booking_refuses_missing_inception (p : Params) (env : Env) (s : Sys)
    (b : Singular.RegistrationBooking) (missing : env.inception s.config.applicationPolicy b = false) :
    (bookRegistration p env s b).toOption = none := by
  cases success : bookRegistration p env s b with
  | error message => rfl
  | ok result =>
    obtain ⟨f, s'⟩ := result
    have evidence := (bookRegistration_sound p success).2.2.2.2
    rw [missing] at evidence
    contradiction

/-- The carriers a fold installs: each is an earlier carrier or the checkpoint
of a registration that was booked before the fold. -/
theorem installMembers_carriers (p : Params) (before acc after : Sys)
    (members : List Singular.FoldMember)
    (hs : members.foldlM (installMember p before) acc = .ok after) :
    ∀ c ∈ after.carriers, c ∈ acc.carriers ∨
      ∃ b ∈ before.registrations, c.aid = b.request.key := by
  induction members generalizing acc with
  | nil =>
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at hs
    subst after
    exact fun c mem => Or.inl mem
  | cons member rest ih =>
    simp only [List.foldlM_cons, bind, Except.bind] at hs
    split at hs
    · contradiction
    · rename_i middle installed
      intro c mem
      rcases ih middle hs c mem with old | booked
      · cases member with
        | termination b =>
          unfold installMember at installed
          simp only [bind, Except.bind, pure, Except.pure] at installed
          split at installed
          · split at installed
            · contradiction
            · cases installed; exact Or.inl old
          · contradiction
        | registration b =>
          unfold installMember at installed
          simp only [bind, Except.bind, pure, Except.pure] at installed
          split at installed
          · contradiction
          · rename_i available
            cases installed
            rcases List.mem_cons.mp old with rfl | earlier
            · exact Or.inr ⟨b, by simpa using available, rfl⟩
            · exact Or.inl earlier
      · exact Or.inr booked

/-- What every reachable registry keeps: each booked request and each carrier
belongs to a key with inception evidence. -/
theorem inception_invariant (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys}
    (hr : Reach p env cfg s) :
    (∀ b ∈ s.registrations, env.inception cfg.applicationPolicy b = true) ∧
    (∀ c ∈ s.carriers, ∃ b : Singular.RegistrationBooking, b.request.key = c.aid ∧ env.inception cfg.applicationPolicy b = true) := by
  induction hr with
  | init => simp [Sys.init]
  | @next s s' action flow past step ih =>
    obtain ⟨requests, carriers⟩ := ih
    cases action with
    | bookRegistration b =>
      obtain ⟨_, _, rfl, _, evidence⟩ := bookRegistration_sound p step
      refine ⟨?_, carriers⟩
      intro b' mem
      rcases List.mem_cons.mp mem with rfl | old
      · have fixed := congrArg Singular.Config.applicationPolicy (reachable_config p env cfg past)
        simpa only [show s.config.applicationPolicy = cfg.applicationPolicy from fixed] using evidence
      · exact requests b' old
    | convictCkpt aid =>
      obtain ⟨_, _, _, _, _, rfl⟩ := (convictCkpt_iff env s s' aid flow).mp step
      refine ⟨requests, ?_⟩
      intro c mem
      obtain ⟨old, held, rfl⟩ := List.mem_map.mp mem
      have := carriers old held
      split <;> simpa using this
    | bookTermination aid booker fee booking =>
      obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, rfl, _, _⟩ :=
        (bookTermination_iff p s s' aid booker fee booking flow).mp step
      exact ⟨requests, fun c mem => carriers c (List.mem_filter.mp mem).1⟩
    | fold gen plugin u tx =>
      have step : fold p s gen plugin u tx = .ok (flow, s') := step
      obtain ⟨_, _, world, _, reconstructed⟩ := (fold_iff p s s' gen plugin u tx flow).mp step
      obtain ⟨acc, installed, same, _, _⟩ := foldResult_installer p reconstructed
      have remaining := (fold_sound p step).2.2.2.2.1
      refine ⟨?_, ?_⟩
      · intro b mem
        rw [remaining] at mem
        exact requests b (List.mem_filter.mp mem).1
      · intro c mem
        rw [same] at mem
        rcases installMembers_carriers p s s acc _ installed c mem with old | ⟨b, booked, key⟩
        · exact carriers c old
        · exact ⟨b, key.symm, requests b booked⟩
    | returnRequests u tx =>
      have step : returnRequests s u tx = .ok (flow, s') := step
      have kept := return_registrations s s' step
      have frame := (return_sound s s' u tx flow step).2.2.2.1
      refine ⟨?_, ?_⟩
      · intro b mem
        rw [kept] at mem
        exact requests b (List.mem_filter.mp mem).1
      · intro c mem
        rw [frame] at mem
        exact carriers c mem

/-- **Every booked request of a reachable registry has its inception evidence.**
Given a registry reached from its creation by accepted steps, and a
registration request booked in it and not yet folded or returned.
When the request's key is read.
Then the key has its inception evidence: it was shown when the request was
booked, and nothing books a request without it. -/
theorem booked_request_has_inception (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys}
    (hr : Reach p env cfg s) {b : Singular.RegistrationBooking} (booked : b ∈ s.registrations) :
    env.inception cfg.applicationPolicy b = true :=
  (inception_invariant p env cfg hr).1 b booked

/-- **Every checkpoint of a reachable registry belongs to a key with inception
evidence.**
Given a registry reached from its creation by accepted steps, and the carrier
of an identifier in it, live or pending termination.
When the identifier is read.
Then it has its inception evidence, although the fold that delivered the
checkpoint read none. -/
theorem registered_key_has_inception (p : Params) (env : Env) (cfg : Singular.Config) {s : Sys}
    (hr : Reach p env cfg s) {aid : Nat} {c : Carrier} (registered : carrierAt s aid = some c) :
    ∃ b : Singular.RegistrationBooking, b.request.key = aid ∧ env.inception cfg.applicationPolicy b = true := by
  have mem := List.mem_of_find?_eq_some registered
  have key : c.aid = aid := by simpa using List.find?_some registered
  rw [← key]
  exact (inception_invariant p env cfg hr).2 c mem

/-- **Every registration a fold takes has its inception evidence.**
Given a reachable registry and an accepted fold of it.
When the registrations among the fold's members are read.
Then each one's key has its inception evidence. On main the fold checked this
itself (`fold_sound` carried the clause); it now follows from the booking,
and the fold reads no evidence. -/
theorem folded_registration_has_inception (p : Params) (env : Env) (cfg : Singular.Config)
    {s s' : Sys} (hr : Reach p env cfg s) {gen plugin : Nat} {u : Singular.EconomicUtxo}
    {tx : Singular.EconomicTransaction} {f : Flow}
    (_folded : fold p s gen plugin u tx = .ok (f, s')) {b : Singular.RegistrationBooking}
    (selected : Singular.FoldMember.registration b ∈ Singular.foldMembers s.toWorld tx) :
    env.inception cfg.applicationPolicy b = true :=
  booked_request_has_inception p env cfg hr
    (actual_members_available p (reachable_wellFormed p env cfg hr) tx _ selected)

/-- **Only a booking reads the inception evidence.**
Given two environments with the same duplicity evidence and any inception
evidence each, and any step that is not a registration booking: a fold, a
return, a conviction, a termination booking.
When the step is taken under each environment.
Then the two results are the same: a fold of a booked request, and a return,
succeed or are refused whatever inception evidence exists. -/
theorem only_booking_reads_inception (p : Params) (env env' : Env)
    (sameDuplicity : env.pendingSpend = env'.pendingSpend) (action : Action) (s : Sys)
    (notBooking : ∀ b, action ≠ .bookRegistration b) :
    stepFn p env action s = stepFn p env' action s := by
  cases action with
  | bookRegistration b => exact absurd rfl (notBooking b)
  | convictCkpt aid => simp [stepFn, convictCkpt, Carrier.convicted, sameDuplicity]
  | bookTermination aid booker fee booking => rfl
  | fold gen plugin u tx => rfl
  | returnRequests u tx => rfl

end CardanoKeri.Registry
