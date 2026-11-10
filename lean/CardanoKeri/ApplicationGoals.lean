import CardanoKeri.Application
import CardanoKeri.ConsumerIdentity
import CardanoKeri.CheckpointDatumGoals

/-! The guarantees of KERI's application on the application-held model.
Each theorem states its Given/When/Then contract in its comment. -/
namespace CardanoKeri.Application
open Singular SingularApplicationHeld

/-! ## Supporting facts -/

theorem filter_one_eq {α : Type} {p : α → Bool} {l : List α} {x y : α}
    (one : (l.filter p).length = 1) (hx : x ∈ l) (px : p x = true) (hy : y ∈ l)
    (py : p y = true) : x = y := by
  obtain ⟨z, hz⟩ := List.length_eq_one_iff.mp one
  have mx : x ∈ l.filter p := List.mem_filter.mpr ⟨hx, px⟩
  have my : y ∈ l.filter p := List.mem_filter.mpr ⟨hy, py⟩
  rw [hz] at mx my
  simp only [List.mem_singleton] at mx my
  rw [mx, my]

/-- The input an action names is the only input with that reference. -/
theorem namedInput_unique {o : Observation} {ref : OutRef} {x input : ObservedOutput}
    (named : namedInput o ref = some x) (mem : input ∈ o.inputs) (hr : input.reference = ref) :
    x = input := by
  unfold namedInput at named
  split at named
  · rename_i guard
    simp only [Bool.and_eq_true, beq_iff_eq] at guard
    have px := List.find?_some named
    exact filter_one_eq guard.2 (List.mem_of_find?_eq_some named) px mem
      (by simp [hr])
  · contradiction

theorem le_sum_of_mem' {l : List Nat} {a : Nat} (h : a ∈ l) : a ≤ l.sum := by
  induction l with
  | nil => simp at h
  | cons b t ih =>
    simp only [List.sum_cons]
    rcases List.mem_cons.mp h with rfl | ht
    · omega
    · have := ih ht
      omega

theorem le_address_sum {l : List (Nat × Nat)} {x : Nat × Nat} (hx : x ∈ l) :
    x.2 ≤ ((l.filter fun other => other.1 == x.1).map (·.2)).sum :=
  le_sum_of_mem' (List.mem_map_of_mem (List.mem_filter.mpr ⟨hx, by simp⟩))

theorem application_beq_empty (raw : Nat) :
    (OutputDatum.application raw == OutputDatum.empty) = false := rfl

theorem none_beq_flip (g : AppGuard) : (AppMutation.none == AppMutation.flip g) = false := rfl

/-- An output that decodes carries an application datum. -/
theorem decoded_application {decode : DecodeApplication} {output : ObservedOutput}
    {d : ApplicationDatum} (h : decoded decode output = some d) :
    ∃ raw, output.datum = .application raw := by
  unfold decoded at h
  split at h
  · exact ⟨_, by assumption⟩
  · contradiction

theorem spentRequest_of {i : Interpretation} {release : PublishedRelease} {o : Observation}
    {ref : OutRef} {input : ObservedOutput} {data : RegistrationData} {c : Configuration}
    (named : namedInput o ref = some input) (hd : decoded i.decode input = some (.registration data))
    (hc : configurationOf i release data.registry o = some c) :
    spentRequest i release o ref = some (input, data, c.parameters) := by
  simp [spentRequest, named, hd, hc]

/-! ## Every spend of a request -/

/-- **Every spend of a registration request is a fold in its window or a full
return after it.**
Given a transaction the KERI application accepts, and one of its inputs at the
application address that decodes as a booked registration request.
When that input is spent.
Then the request's configuration record is read by reference with valid
parameters, the request's approval is burned, and either a fold names it whose
whole validity interval ends by the deadline, whose key has its inception
evidence and which delivers the committed holding (address, which is the
checkpoint validator's credential the record names, initial datum, exactly the
deposit, the one new active token); or a return names it whose whole validity
interval starts at the deadline or later, and the refund address is paid at
least the request's lovelace less the tip. -/
theorem registration_spend_is_fold_or_return (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true)
    {input : ObservedOutput} {data : RegistrationData} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (hd : decoded i.decode input = some (.registration data)) :
    ∃ c, configurationOf i release data.registry o = some c ∧
      parametersValid c.parameters = true ∧
      approvalBurned i release data o = true ∧
      ((∃ index holding, Action.foldRegistration input.reference index ∈ o.actions ∧
          o.outputs[index]? = some holding ∧ foldWindow data o.interval = true ∧
          env.inception data.key = true ∧ delivered i c data holding o = true) ∨
       (Action.returnRegistration input.reference ∈ o.actions ∧
          returnWindow data o.interval = true ∧
          input.lovelace - c.parameters.minimumTip ≤ paidTo o.outputs data.refundAddress)) := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨covered, actions⟩, money⟩ := ok
  have cover := List.all_eq_true.mp covered input mem
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, atApplication, not_true_eq_false, false_or,
    List.any_eq_true, decide_eq_true_eq] at cover
  obtain ⟨a, amem, ain⟩ := cover
  have aok := List.all_eq_true.mp actions a amem
  obtain ⟨raw, hraw⟩ := decoded_application hd
  cases a with
  | createConfiguration => simp [Action.input?] at ain
  | bookRegistration => simp [Action.input?] at ain
  | foldTermination ref registry key =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      simp [spendTermination, terminationShape, appGuard, hraw, application_beq_empty,
        none_beq_flip] at aok
    · contradiction
  | foldRegistration ref index =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      rw [hd] at aok
      simp only at aok
      unfold spendRegistration at aok
      split at aok
      · contradiction
      · rename_i p hp
        simp only [Bool.and_eq_true] at aok
        obtain ⟨⟨⟨valid, _⟩, burned⟩, ⟨window, inception⟩, holding⟩ := aok
        split at holding
        · rename_i h hh
          exact ⟨p, hp, valid, burned, Or.inl ⟨index, h, amem, hh, window, inception, holding⟩⟩
        · contradiction
    · contradiction
  | returnRegistration ref =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      rw [hd] at aok
      simp only at aok
      unfold spendRegistration at aok
      split at aok
      · contradiction
      · rename_i p hp
        simp only [Bool.and_eq_true] at aok
        obtain ⟨⟨⟨valid, _⟩, burned⟩, window⟩ := aok
        refine ⟨p, hp, valid, burned, Or.inr ⟨amem, window, ?_⟩⟩
        simp only [moneyRouted, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at money
        have entry : (data.refundAddress, x.lovelace - p.parameters.minimumTip) ∈ requiredRefunds i release o :=
          List.mem_filterMap.mpr ⟨.returnRegistration x.reference, amem,
            by simp [spentRequest_of named hd hp]⟩
        exact Nat.le_trans (le_address_sum entry) (money.1 _ entry)
    · contradiction

/-- **Until its deadline a request is spent only by a fold.**
Given an accepted transaction spending a booked registration request at the
application address, whose validity interval starts before the request's deadline.
When the request is spent.
Then a fold names it and delivers its committed holding, under the
configuration record read by reference; no return can. -/
theorem before_deadline_only_fold (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true)
    {input : ObservedOutput} {data : RegistrationData} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (hd : decoded i.decode input = some (.registration data))
    (early : o.interval.lower < data.processDeadline) :
    ∃ c index holding, configurationOf i release data.registry o = some c ∧
      Action.foldRegistration input.reference index ∈ o.actions ∧
      o.outputs[index]? = some holding ∧ delivered i c data holding o = true := by
  obtain ⟨c, hc, _, _, spend⟩ :=
    registration_spend_is_fold_or_return i env rp release o ok mem atApplication hd
  rcases spend with ⟨index, holding, amem, hh, _, _, hdel⟩ | ⟨_, window, _⟩
  · exact ⟨c, index, holding, hc, amem, hh, hdel⟩
  · simp only [returnWindow, Bool.and_eq_true, decide_eq_true_eq] at window
    omega

/-- **From its deadline a request is returned in full but the tip.**
Given an accepted transaction that returns a booked registration request.
When the request is spent by the return.
Then the transaction's whole validity interval starts at the deadline or
later, and the refund address is paid at least the request's lovelace less
the registry's minimum tip. -/
theorem return_pays_refund_address (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true)
    {input : ObservedOutput} {data : RegistrationData} {c : Configuration}
    (named : namedInput o input.reference = some input)
    (hd : decoded i.decode input = some (.registration data))
    (hc : configurationOf i release data.registry o = some c)
    (returned : Action.returnRegistration input.reference ∈ o.actions) :
    data.processDeadline ≤ o.interval.lower ∧
      input.lovelace - c.parameters.minimumTip ≤ paidTo o.outputs data.refundAddress := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨_, actions⟩, money⟩ := ok
  have aok := List.all_eq_true.mp actions _ returned
  simp only [action, named, hd, spendRegistration, hc, Bool.and_eq_true] at aok
  simp only [returnWindow, Bool.and_eq_true, decide_eq_true_eq] at aok
  refine ⟨aok.2.2, ?_⟩
  simp only [moneyRouted, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at money
  have entry : (data.refundAddress, input.lovelace - c.parameters.minimumTip) ∈ requiredRefunds i release o :=
    List.mem_filterMap.mpr ⟨.returnRegistration input.reference, returned,
      by simp [spentRequest_of named hd hc]⟩
  exact Nat.le_trans (le_address_sum entry) (money.1 _ entry)

/-- **A pending termination is spent only by its terminating fold.**
Given an accepted transaction and one of its inputs at the application address
that does not decode as a registration request (a pending termination output
carries no datum).
When that input is spent.
Then a terminating fold names it, burns its termination approval and its
active token, and the registry's state policy runs. -/
theorem termination_only_by_fold (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true)
    {input : ObservedOutput} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (notRequest : ∀ data, decoded i.decode input ≠ some (.registration data)) :
    ∃ registry key, Action.foldTermination input.reference registry key ∈ o.actions ∧
      SingularApplicationHeld.Assets.mintQty o.assets
        (terminationApproval i.hash i.code release registry key) = -1 ∧
      SingularApplicationHeld.Assets.mintQty o.assets (activeAsset i.hash i.code registry key) = -1 ∧
      o.assets.invoked.contains registry.policy = true := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨covered, actions⟩, _⟩ := ok
  have cover := List.all_eq_true.mp covered input mem
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, atApplication, not_true_eq_false, false_or,
    List.any_eq_true, decide_eq_true_eq] at cover
  obtain ⟨a, amem, ain⟩ := cover
  have aok := List.all_eq_true.mp actions a amem
  cases a with
  | createConfiguration => simp [Action.input?] at ain
  | bookRegistration => simp [Action.input?] at ain
  | foldTermination ref registry key =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      simp only [spendTermination, Bool.and_eq_true, beq_iff_eq] at aok
      exact ⟨registry, key, amem, aok.1.1.2, aok.1.2, aok.2⟩
    · contradiction
  | foldRegistration ref index =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      split at aok
      · rename_i data hd
        exact absurd hd (notRequest data)
      · contradiction
    · contradiction
  | returnRegistration ref =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      split at aok
      · rename_i data hd
        exact absurd hd (notRequest data)
      · contradiction
    · contradiction

/-! ## The treasury -/

/-- **A fold's treasury donation covers its registration costs.**
Given a transaction the KERI application accepts.
When it folds registration requests.
Then its `treasury_donation` is at least the sum of the registration costs of
the requests it folds. -/
theorem treasury_covers_registration_costs (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true) :
    requiredTreasury i release o ≤ o.donation := by
  simp only [accepted, moneyRouted, Bool.and_eq_true, decide_eq_true_eq] at ok
  exact ok.2.2

/-- **Each folded request's registration cost is in the donation.**
Given an accepted transaction with a fold of a request whose configuration
record gives registration cost `c`.
When the transaction is accepted.
Then its treasury donation is at least `c`. -/
theorem folded_cost_in_donation (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true)
    {ref : OutRef} {index : Nat} {input : ObservedOutput} {data : RegistrationData}
    {p : ApplicationParameters}
    (folded : Action.foldRegistration ref index ∈ o.actions)
    (hs : spentRequest i release o ref = some (input, data, p)) :
    p.registrationCost ≤ o.donation := by
  have total := treasury_covers_registration_costs i env rp release o ok
  have member : p.registrationCost ∈ (o.actions.filterMap fun a => match a with
      | .foldRegistration ref _ => (spentRequest i release o ref).map fun (_, _, p) => p.registrationCost
      | _ => none) :=
    List.mem_filterMap.mpr ⟨.foldRegistration ref index, folded, by simp [hs]⟩
  exact Nat.le_trans (le_sum_of_mem' member) total

/-! ## Booking -/


/-- **No configuration record for a foreign registry.**
Given a registry whose state policy is not `state(A_keri)`.
When its configuration record is created.
Then the creation is refused, so no booking can read one. -/
theorem configuration_refuses_foreign_registry (i : Interpretation) (release : PublishedRelease)
    {registry : TokenId} (seed : OutRef) (output : ObservedOutput) (o : Observation)
    (foreign : registry.policy ≠ release.statePolicy) :
    createConfiguration i release registry seed output o = false := by
  simp [createConfiguration, foreign]

/-- **A configuration record has no retraction window.**
Given a configuration record whose parameters have a positive `retractTime`.
When it is created.
Then the creation is refused. -/
theorem configuration_refuses_retraction (i : Interpretation) (release : PublishedRelease)
    {registry : TokenId} (seed : OutRef) {output : ObservedOutput} (o : Observation)
    {c : Configuration} (hc : configurationDatum i output = some c)
    (positive : c.parameters.retractTime ≠ 0) :
    createConfiguration i release registry seed output o = false := by
  simp [createConfiguration, hc, parametersValid, positive]

/-- **A booking commits the checkpoint validator and holds exactly the deposit,
the registration cost and the tip.**
Given an accepted booking of a request output.
When it is booked.
Then the request decodes to a registration of a `state(A_keri)` registry,
whose configuration record is read by reference; the holding address is the
checkpoint validator's credential the record names, which is not the
application credential; the deposit is at least the registry's minimum ADA
plus its deposit; the output holds exactly the deposit, the registration cost
and the minimum tip; the deadline is the booking's upper bound plus the
processing time; and one approval of the payload is minted. -/
theorem booking_inversion (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    (ok : bookRegistration i rp release o output = true) :
    ∃ data c, decoded i.decode output = some (.registration data) ∧
      configurationOf i release data.registry o = some c ∧
      data.registry.policy = release.statePolicy ∧
      data.holdingAddress = c.checkpointCredential ∧
      c.checkpointCredential ≠ release.applicationCredential ∧
      rp.Mc + rp.D ≤ data.deposit ∧
      output.lovelace = data.deposit + c.parameters.registrationCost + c.parameters.minimumTip ∧
      data.bookedAt = o.interval.upper ∧
      data.processDeadline = data.bookedAt + c.parameters.processTime ∧
      SingularApplicationHeld.Assets.mintQty o.assets
        (registrationAsset i.hash i.code release data) = 1 := by
  unfold bookRegistration at ok
  split at ok
  · rename_i data hd
    split at ok
    · rename_i c hc
      simp only [Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, decide_eq_true_eq,
        bookingClock] at ok
      obtain ⟨⟨⟨⟨⟨⟨⟨_, policy⟩, address⟩, distinct⟩, floor⟩, exact⟩,
        ⟨⟨⟨⟨_, booked⟩, _⟩, deadline⟩, _⟩⟩, minted⟩ := ok
      exact ⟨data, c, hd, hc, policy, address, distinct, floor, exact, booked, deadline, minted⟩
    · contradiction
  · contradiction

/-- **A booking names only a registry of `state(A_keri)`.**
Given a request output decoding to a registration that names a registry whose
state policy is not the release's state policy `state(A_keri)`.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_foreign_registry (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (foreign : data.registry.policy ≠ release.statePolicy) :
    bookRegistration i rp release o output = false := by
  cases h : bookRegistration i rp release o output
  · rfl
  · obtain ⟨d, _, hd', _, policy, _⟩ := booking_inversion i rp release o h
    rw [hd] at hd'
    cases hd'
    exact absurd policy foreign

/-- **A booking that commits the application address as the holding is refused.**
Given a registration whose committed holding address is the application
credential.
When it is booked.
Then the booking is refused: a checkpoint is never delivered where the
application's own records live. -/
theorem booking_refuses_application_holding (i : Interpretation)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    {output : ObservedOutput} {data : RegistrationData}
    (hd : decoded i.decode output = some (.registration data))
    (atApplication : data.holdingAddress = release.applicationCredential) :
    bookRegistration i rp release o output = false := by
  cases h : bookRegistration i rp release o output
  · rfl
  · obtain ⟨d, _, hd', _, _, address, distinct, _⟩ := booking_inversion i rp release o h
    rw [hd] at hd'
    cases hd'
    exact absurd (address.symm.trans atApplication) distinct

/-- **A booking that commits another holding address than the checkpoint
validator's is refused.**
Given a registration whose configuration record names checkpoint credential
`c.checkpointCredential`, and whose committed holding address differs from it.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_other_holding (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} {c : Configuration}
    (hd : decoded i.decode output = some (.registration data))
    (hc : configurationOf i release data.registry o = some c)
    (other : data.holdingAddress ≠ c.checkpointCredential) :
    bookRegistration i rp release o output = false := by
  cases h : bookRegistration i rp release o output
  · rfl
  · obtain ⟨d, q, hd', hq, _, address, _⟩ := booking_inversion i rp release o h
    rw [hd] at hd'
    cases hd'
    rw [hc] at hq
    cases hq
    exact absurd address other

/-- **A booking short of the carrier floor is refused.**
Given a registration whose committed deposit is below the registry's minimum
ADA plus its deposit.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_short_deposit (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (short : data.deposit < rp.Mc + rp.D) :
    bookRegistration i rp release o output = false := by
  cases h : bookRegistration i rp release o output
  · rfl
  · obtain ⟨d, _, hd', _, _, _, _, floor, _⟩ := booking_inversion i rp release o h
    rw [hd] at hd'
    cases hd'
    omega

/-- **A booking holding anything but the exact contents is refused.**
Given a registration whose request output does not hold exactly its deposit,
its registry's registration cost and minimum tip.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_inexact_contents (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} {c : Configuration}
    (hd : decoded i.decode output = some (.registration data))
    (hc : configurationOf i release data.registry o = some c)
    (inexact : output.lovelace ≠ requestLovelace c.parameters data) :
    bookRegistration i rp release o output = false := by
  cases h : bookRegistration i rp release o output
  · rfl
  · obtain ⟨d, q, hd', hq, _, _, _, _, exact, _⟩ := booking_inversion i rp release o h
    rw [hd] at hd'
    cases hd'
    rw [hc] at hq
    cases hq
    exact absurd exact inexact


/-! ## The fold's holding -/

/-- **A fold delivering any other lovelace than the deposit is refused.**
Given a booked registration and a fold naming a holding whose lovelace differs
from the committed deposit, by one lovelace more or less.
When the request is spent by that fold.
Then the spend is refused. -/
theorem fold_refuses_inexact_holding (i : Interpretation) (env : Env) (release : PublishedRelease)
    (o : Observation) {ref : OutRef} {index : Nat} {input holding : ObservedOutput}
    {data : RegistrationData} (hh : o.outputs[index]? = some holding)
    (inexact : holding.lovelace ≠ data.deposit) :
    spendRegistration i env release o (.foldRegistration ref index) input data = false := by
  unfold spendRegistration
  split
  · rfl
  · simp [hh, delivered, inexact]

/-- **The two windows are the upstream processing and cleanup phases.**
Given a request recorded with `reclaimEnd = processDeadline`, as a KERI booking
with `retractTime = 0` records it.
When its fold and return windows are compared with the upstream phase
classification.
Then the fold window is the processing phase and the return window is the
cleanup phase. -/
theorem windows_are_upstream_phases (data : RegistrationData) (interval : Interval)
    (noRetraction : data.reclaimEnd = data.processDeadline) :
    (foldWindow data interval = true ↔ classifyPhase data interval = .processing) ∧
    (returnWindow data interval = true ↔ classifyPhase data interval = .cleanup) := by
  unfold foldWindow returnWindow classifyPhase nonemptyInterval
  rw [noRetraction]
  constructor <;> by_cases h1 : interval.lower < interval.upper <;>
    by_cases h2 : interval.upper ≤ data.processDeadline <;>
    by_cases h3 : data.processDeadline ≤ interval.lower <;> simp [h1, h2, h3] <;> omega

/-- **A KERI booking records no retraction window.**
Given an accepted booking under configuration parameters with `retractTime = 0`.
When the request records its deadlines.
Then the reclaim end equals the deadline. -/
theorem booking_no_retraction {p : ApplicationParameters} {data : RegistrationData}
    {interval : Interval} (clock : bookingClock p data interval = true)
    (valid : parametersValid p = true) : data.reclaimEnd = data.processDeadline := by
  simp only [bookingClock, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at clock
  simp only [parametersValid, beq_iff_eq] at valid
  rw [clock.2, valid, Nat.add_zero]

/-! ## The approval -/

/-- The preimages two KERI approvals and their registries are drawn from. -/
def approvalDomain (i : Interpretation) (d₁ d₂ : Deployment) (aid₁ aid₂ : CardanoKeri.Checkpoint.AID)
    (a₁ a₂ h₁ h₂ dep₁ dep₂ : Nat) : List Preimage :=
  [.registrationApproval (d₁.registry i) (i.keyOf aid₁) a₁ h₁ dep₁,
   .registrationApproval (d₂.registry i) (i.keyOf aid₂) a₂ h₂ dep₂,
   .state d₁.seed, .state d₂.seed]

/-- **The approval binds the registry, the key, the holding and the deposit.**
Given the finite encoding and collision-freedom premises over the preimages
of two KERI approvals and their registries' state roles, and an injective AID
key encoding.
When the two approvals are the same token.
Then the two deployments have the same application policy, the same state
policy `state(A_keri)` and the same registry seed (so the same registry name),
and the two approvals name the same AID, holding address, initial datum hash
and deposit. -/
theorem approval_binds (i : Interpretation) (d₁ d₂ : Deployment)
    (aid₁ aid₂ : CardanoKeri.Checkpoint.AID) (a₁ a₂ h₁ h₂ dep₁ dep₂ : Nat)
    (encoding : FiniteEncoding i.code (approvalDomain i d₁ d₂ aid₁ aid₂ a₁ a₂ h₁ h₂ dep₁ dep₂))
    (collision : FiniteCollisionFree i.hash i.code
      (approvalDomain i d₁ d₂ aid₁ aid₂ a₁ a₂ h₁ h₂ dep₁ dep₂))
    (keys : ∀ x y, i.keyOf x = i.keyOf y → x = y)
    (same : approval i d₁ aid₁ a₁ h₁ dep₁ = approval i d₂ aid₂ a₂ h₂ dep₂) :
    d₁.release.applicationPolicy = d₂.release.applicationPolicy ∧
    d₁.release.statePolicy = d₂.release.statePolicy ∧ d₁.seed = d₂.seed ∧
    aid₁ = aid₂ ∧ a₁ = a₂ ∧ h₁ = h₂ ∧ dep₁ = dep₂ := by
  simp only [approval, registrationApproval, TokenId.mk.injEq] at same
  obtain ⟨policy, name⟩ := same
  have code := collision _ (by simp [approvalDomain]) _ (by simp [approvalDomain]) name
  have pre := encoding _ (by simp [approvalDomain]) _ (by simp [approvalDomain]) code
  simp only [Preimage.registrationApproval.injEq] at pre
  obtain ⟨registry, key, address, datum, deposit⟩ := pre
  simp only [Deployment.registry, stateAsset, TokenId.mk.injEq] at registry
  obtain ⟨statePolicy, stateName⟩ := registry
  have stateCode := collision _ (by simp [approvalDomain]) _ (by simp [approvalDomain]) stateName
  have seed := encoding _ (by simp [approvalDomain]) _ (by simp [approvalDomain]) stateCode
  simp only [Preimage.state.injEq] at seed
  exact ⟨policy, statePolicy, seed, keys _ _ key, address, datum, deposit⟩

/-- The deployment a consumer's relying context names. -/
def Deployment.ofContext (c : CardanoKeri.ConsumerIdentity.Context) : Deployment :=
  ⟨c.release, c.seed⟩

/-- **The network is outside the approval.**
Given two relying contexts with the same release and registry seed and any
two networks.
When the approval of the same AID, holding address, initial datum hash and
deposit is computed for each.
Then the two approvals are the same token: the network is bound by the chain
the transaction runs on, not by the approval (the declared boundary). -/
theorem approval_ignores_network (i : Interpretation)
    (c c' : CardanoKeri.ConsumerIdentity.Context) (release : c.release = c'.release)
    (seed : c.seed = c'.seed) (aid : CardanoKeri.Checkpoint.AID) (address datumHash deposit : Nat) :
    approval i (.ofContext c) aid address datumHash deposit =
      approval i (.ofContext c') aid address datumHash deposit := by
  simp [Deployment.ofContext, release, seed]

/-! ## Where the checkpoint lives -/

/-- A delivered holding sits at the committed holding address and at the
checkpoint validator's credential the configuration record names. -/
theorem delivered_credential {i : Interpretation} {c : Configuration} {data : RegistrationData}
    {holding : ObservedOutput} {o : Observation} (h : delivered i c data holding o = true) :
    holding.credential = data.holdingAddress ∧ holding.credential = c.checkpointCredential := by
  simp only [delivered, Bool.and_eq_true, beq_iff_eq] at h
  exact ⟨h.1.1.1.1.1, h.1.1.1.1.2⟩

/-- **Every fold delivers its checkpoint to the checkpoint validator.**
Given a transaction the KERI application accepts.
When it folds a registration request, naming the output it delivers.
Then the named request is spent exactly once and decodes as a registration
whose configuration record is read by reference, and the delivered holding
sits at the checkpoint validator's credential that record names, which is the
holding address the request committed. -/
theorem fold_delivers_to_checkpoint_validator (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true) {ref : OutRef} {index : Nat}
    (folded : Action.foldRegistration ref index ∈ o.actions) :
    ∃ input data c holding, namedInput o ref = some input ∧
      decoded i.decode input = some (.registration data) ∧
      configurationOf i release data.registry o = some c ∧
      o.outputs[index]? = some holding ∧ delivered i c data holding o = true ∧
      holding.credential = c.checkpointCredential ∧
      holding.credential = data.holdingAddress := by
  simp only [accepted, Bool.and_eq_true] at ok
  have aok := List.all_eq_true.mp ok.1.2 _ folded
  simp only [action] at aok
  split at aok
  · rename_i input named
    split at aok
    · rename_i data hd
      unfold spendRegistration at aok
      split at aok
      · contradiction
      · rename_i c hc
        simp only [Bool.and_eq_true] at aok
        obtain ⟨_, _, holding⟩ := aok
        split at holding
        · rename_i h hh
          have cred := delivered_credential holding
          exact ⟨input, data, c, h, named, hd, hc, hh, holding, cred.2, cred.1⟩
        · contradiction
    · contradiction
  · contradiction

/-- **No input at the application address is a checkpoint.**
Given a transaction the KERI application accepts, and one of its inputs at the
application address carrying an application datum that the request decoder
does not read as a registration request, as it does not read a checkpoint's
version 2 datum.
When the transaction is accepted.
Then there is no such input: the application spends at its address only
registration requests and datum-less pending terminations, never a
checkpoint. -/
theorem no_application_input_is_a_checkpoint (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp release o = true)
    {input : ObservedOutput} {raw : Nat} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (held : input.datum = .application raw)
    (notRequest : ∀ data, i.decode raw ≠ some (.registration data)) : False := by
  have notDecoded : ∀ data, decoded i.decode input ≠ some (.registration data) := by
    intro data h
    exact notRequest data (by simpa [decoded, held] using h)
  obtain ⟨registry, key, amem, _⟩ :=
    termination_only_by_fold i env rp release o ok mem atApplication notDecoded
  simp only [accepted, Bool.and_eq_true] at ok
  have aok := List.all_eq_true.mp ok.1.2 _ amem
  simp only [action] at aok
  split at aok
  · rename_i x named
    have := namedInput_unique named mem rfl
    subst this
    simp [spendTermination, terminationShape, appGuard, held, application_beq_empty,
      none_beq_flip] at aok
  · contradiction

/-! ## A genuine checkpoint -/

/-- **A delivered checkpoint is genuine.**
Given a request booked by an accepted booking, and a fold delivering a holding
for it under the registry's configuration record.
When the holding is inspected.
Then it is genuine: at the checkpoint validator's credential, not the
application's; holding the one active token of the key under a registry of
`state(A_keri)`; carrying the committed initial datum; holding exactly the
committed deposit. -/
theorem delivered_is_genuine (i : Interpretation) (rp : CardanoKeri.Registry.Params)
    (release : PublishedRelease) {booking fold : Observation} {request holding : ObservedOutput}
    {data : RegistrationData} {c : Configuration}
    (booked : bookRegistration i rp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (hdel : delivered i c data holding fold = true) :
    genuine i release c data holding := by
  obtain ⟨d, _, hd', _, policy, address, distinct, _⟩ :=
    booking_inversion i rp release booking booked
  rw [hb] at hd'
  cases hd'
  simp only [delivered, Bool.and_eq_true, beq_iff_eq] at hdel
  obtain ⟨⟨⟨⟨⟨atAddress, atCheckpoint⟩, datum⟩, lovelace⟩, quantity⟩, _⟩ := hdel
  refine ⟨atCheckpoint, ?_, policy, quantity, datum, lovelace⟩
  rw [atAddress, address]
  exact distinct

/-- **Until its deadline a booked request is spent only by delivering a
genuine checkpoint.**
Given a request booked by an accepted booking, and an accepted transaction
spending it at the application address whose validity interval starts before
the request's deadline.
When the request is spent.
Then a fold names it and delivers a genuine checkpoint, at the checkpoint
validator named by the registry's configuration record. -/
theorem before_deadline_delivers_genuine (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (release : PublishedRelease) {booking o : Observation}
    {request input : ObservedOutput} {data : RegistrationData}
    (booked : bookRegistration i rp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (ok : accepted i env rp release o = true) (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (hd : decoded i.decode input = some (.registration data))
    (early : o.interval.lower < data.processDeadline) :
    ∃ c index holding, configurationOf i release data.registry o = some c ∧
      Action.foldRegistration input.reference index ∈ o.actions ∧
      o.outputs[index]? = some holding ∧ genuine i release c data holding := by
  obtain ⟨c, index, holding, hc, amem, hh, hdel⟩ :=
    before_deadline_only_fold i env rp release o ok mem atApplication hd early
  exact ⟨c, index, holding, hc, amem, hh, delivered_is_genuine i rp release booked hb hdel⟩

/-- **A genuine checkpoint carries the version 2 datum its request committed.**
Given a genuine checkpoint whose request committed the hash of the raw version
2 checkpoint datum `d`, and a datum hash with no collision on `d`.
When the holding's datum is read.
Then it is that raw datum. -/
theorem genuine_holds_committed_datum {i : Interpretation} {release : PublishedRelease}
    {c : Configuration} {data : RegistrationData} {holding : ObservedOutput}
    (g : genuine i release c data holding) {d : CheckpointDatum.Data}
    (committed : data.initialDatum = i.datumHash (CheckpointDatum.raw d))
    (collision : ∀ x, i.datumHash x = i.datumHash (CheckpointDatum.raw d) →
      x = CheckpointDatum.raw d) :
    holding.datum = .application (CheckpointDatum.raw d) := by
  obtain ⟨_, _, _, _, datum, _⟩ := g
  unfold holdingDatumHash at datum
  split at datum
  · rename_i raw held
    simp only [Option.some.injEq] at datum
    rw [held, collision raw (datum.trans committed)]
  · contradiction

/-- **A genuine checkpoint satisfies the consumer's holding clauses.**
Given a genuine checkpoint whose request committed the hash of the raw version
2 datum written for the consumer's AID and a state with an output, with no
datum-hash collision on it; a consumer context naming the checkpoint
credential of the configuration record, the registry the request named and
the request's key for its AID, under the same hash and codec; and an
authenticated environment.
When the consumer checks the holding with the concrete decoder.
Then it accepts it exactly when the written state is consumable: the holding
passes the predicate's credential, token, datum and AID clauses. -/
theorem genuine_checkpoint_consumable_iff {i : Interpretation} {release : PublishedRelease}
    {c : Configuration} {data : RegistrationData} {holding : ObservedOutput}
    (g : genuine i release c data holding)
    (cc : CardanoKeri.ConsumerIdentity.Context) (e : CardanoKeri.ConsumerIdentity.Environment)
    (p : CardanoKeri.Checkpoint.Params) (now : CardanoKeri.Checkpoint.Slot)
    (context : CardanoKeri.ConsumerIdentity.authenticatedContext cc e)
    (credential : c.checkpointCredential = cc.checkpointCredential)
    (hash : i.hash = CheckpointDatum.interpretation.hash)
    (code : i.code = CheckpointDatum.interpretation.code)
    (registry : data.registry =
      CardanoKeri.ConsumerIdentity.registryAsset CheckpointDatum.interpretation cc)
    (key : data.key = CheckpointDatum.interpretation.keyOf cc.aid)
    {s : CardanoKeri.Checkpoint.State} {k : CheckpointDatum.KeyMaterial} {d : CheckpointDatum.Data}
    (written : CheckpointDatum.datum cc.aid k s = some d) (bytewise : k.Bytewise)
    (committed : data.initialDatum = i.datumHash (CheckpointDatum.raw d))
    (collision : ∀ x, i.datumHash x = i.datumHash (CheckpointDatum.raw d) →
      x = CheckpointDatum.raw d) :
    CardanoKeri.ConsumerIdentity.consumableHolding CheckpointDatum.interpretation cc e p now
        holding ↔ CardanoKeri.Checkpoint.consumableState p now s := by
  have held := genuine_holds_committed_datum g committed collision
  obtain ⟨atCheckpoint, _, _, quantity, _, _⟩ := g
  rw [hash, code, registry, key] at quantity
  exact CheckpointDatum.written_holding_iff cc e p now s k d holding context written bytewise
    (atCheckpoint.trans credential) quantity held

/-! ## Correspondence with the economic model -/

/-- **A KERI request holds what the economic request declares.**
Given an economic registration request whose registration cost is the
configuration record's, whose declared tip is the record's minimum tip and
whose carrier is the committed deposit.
When the two contents are compared.
Then the held-level request lovelace is the economic declared lovelace, and
the return's refund (the lovelace less the tip) is the economic registration
cost plus the carrier. -/
theorem request_matches_economic (p : ApplicationParameters) (data : RegistrationData)
    (r : Singular.RegistrationRequest) (cost : r.registrationCost = p.registrationCost)
    (tip : r.declaredTip = p.minimumTip) (carrier : r.carrierAda = data.deposit) :
    requestLovelace p data = Singular.registrationDeclaredLovelace r ∧
    requestLovelace p data - p.minimumTip = r.registrationCost + r.carrierAda := by
  simp only [requestLovelace, Singular.registrationDeclaredLovelace, cost, tip, carrier]
  omega

/-- **The KERI carrier floor is the economic one.**
Given an economic registration booking whose carrier is the committed deposit
and whose declared tip is the economic tip.
When the economic registration shape is read.
Then it holds exactly when the deposit is at least the registry's minimum ADA
plus its deposit. -/
theorem carrier_floor_matches_economic (rp : CardanoKeri.Registry.Params)
    (b : Singular.RegistrationBooking) (data : RegistrationData)
    (carrier : b.request.carrierAda = data.deposit) (tip : b.request.declaredTip = rp.tip) :
    CardanoKeri.Registry.registrationShape rp b ↔ rp.Mc + rp.D ≤ data.deposit := by
  simp [CardanoKeri.Registry.registrationShape, carrier, tip]

end CardanoKeri.Application
