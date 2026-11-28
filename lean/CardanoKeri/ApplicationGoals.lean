import CardanoKeri.Application
import CardanoKeri.ConsumerIdentity
import CardanoKeri.CheckpointDatumGoals
import CardanoKeri.Samaritan
import SingularApplicationHeld.HistoryClaims

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
whole validity interval ends by the deadline and which delivers what the
approval commits (the committed address, a datum of the committed hash,
exactly the deposit, the one new active token); or a return names it whose
whole validity interval starts at the deadline or later, and the refund
address is paid at least the request's lovelace less the tip. No clause reads
the inception evidence: the booking did (`booking_inversion`). -/
theorem registration_spend_is_fold_or_return (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {input : ObservedOutput} {data : RegistrationData} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (hd : decoded i.decode input = some (.registration data)) :
    ∃ c, configurationOf i release data.registry o = some c ∧
      parametersValid c.parameters = true ∧
      approvalBurned i release data o = true ∧
      ((∃ index holding, Action.foldRegistration input.reference index ∈ o.actions ∧
          o.outputs[index]? = some holding ∧ foldWindow data o.interval = true ∧
          delivered i data holding o = true) ∨
       (Action.returnRegistration input.reference ∈ o.actions ∧
          returnWindow data o.interval = true ∧
          input.lovelace - c.parameters.minimumTip ≤ paidTo o.outputs data.refundAddress)) := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨⟨⟨covered, actions⟩, money⟩, _⟩, _⟩ := ok
  have cover := List.all_eq_true.mp covered input mem
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, atApplication, not_true_eq_false, false_or,
    List.any_eq_true, decide_eq_true_eq] at cover
  obtain ⟨a, amem, ain⟩ := cover
  have aok := List.all_eq_true.mp actions a amem
  obtain ⟨raw, hraw⟩ := decoded_application hd
  cases a with
  | createConfiguration => simp [Action.input?] at ain
  | bookRegistration => simp [Action.input?] at ain
  | bookTermination => simp [Action.input?] at ain
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
        obtain ⟨⟨⟨valid, _⟩, burned⟩, window, holding⟩ := aok
        split at holding
        · rename_i h hh
          exact ⟨p, hp, valid, burned, Or.inl ⟨index, h, amem, hh, window, holding⟩⟩
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
Then a fold names it and delivers what its approval commits, with the
registry's configuration record read by reference; no return can. -/
theorem before_deadline_only_fold (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {input : ObservedOutput} {data : RegistrationData} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (hd : decoded i.decode input = some (.registration data))
    (early : o.interval.lower < data.processDeadline) :
    ∃ c index holding, configurationOf i release data.registry o = some c ∧
      Action.foldRegistration input.reference index ∈ o.actions ∧
      o.outputs[index]? = some holding ∧ delivered i data holding o = true := by
  obtain ⟨c, hc, _, _, spend⟩ :=
    registration_spend_is_fold_or_return i env rp cp release o ok mem atApplication hd
  rcases spend with ⟨index, holding, amem, hh, _, hdel⟩ | ⟨_, window, _⟩
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
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {input : ObservedOutput} {data : RegistrationData} {c : Configuration}
    (named : namedInput o input.reference = some input)
    (hd : decoded i.decode input = some (.registration data))
    (hc : configurationOf i release data.registry o = some c)
    (returned : Action.returnRegistration input.reference ∈ o.actions) :
    data.processDeadline ≤ o.interval.lower ∧
      input.lovelace - c.parameters.minimumTip ≤ paidTo o.outputs data.refundAddress := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨⟨⟨_, actions⟩, money⟩, _⟩, _⟩ := ok
  have aok := List.all_eq_true.mp actions _ returned
  simp only [action, named, hd, spendRegistration, hc, Bool.and_eq_true] at aok
  simp only [returnWindow, Bool.and_eq_true, decide_eq_true_eq] at aok
  refine ⟨aok.2.2, ?_⟩
  simp only [moneyRouted, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at money
  have entry : (data.refundAddress, input.lovelace - c.parameters.minimumTip) ∈ requiredRefunds i release o :=
    List.mem_filterMap.mpr ⟨.returnRegistration input.reference, returned,
      by simp [spentRequest_of named hd hc]⟩
  exact Nat.le_trans (le_address_sum entry) (money.1 _ entry)

/-- **A termination request is spent only by its terminating fold.**
Given an accepted transaction and one of its inputs at the application address
that does not decode as a registration request (a termination request carries
no datum).
When that input is spent.
Then a terminating fold names it, reads the registry's configuration record by
reference, burns its termination approval and its active token, and the
registry's state policy runs. It has no deadline: no clause reads the clock. -/
theorem termination_only_by_fold (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {input : ObservedOutput} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (notRequest : ∀ data, decoded i.decode input ≠ some (.registration data)) :
    ∃ registry key, Action.foldTermination input.reference registry key ∈ o.actions ∧
      (configurationOf i release registry o).isSome = true ∧
      SingularApplicationHeld.Assets.mintQty o.assets
        (terminationApproval i.hash i.code release registry key) = -1 ∧
      SingularApplicationHeld.Assets.mintQty o.assets (activeAsset i.hash i.code registry key) = -1 ∧
      o.assets.invoked.contains registry.policy = true := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨⟨⟨covered, actions⟩, _⟩, _⟩, _⟩ := ok
  have cover := List.all_eq_true.mp covered input mem
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, atApplication, not_true_eq_false, false_or,
    List.any_eq_true, decide_eq_true_eq] at cover
  obtain ⟨a, amem, ain⟩ := cover
  have aok := List.all_eq_true.mp actions a amem
  cases a with
  | createConfiguration => simp [Action.input?] at ain
  | bookRegistration => simp [Action.input?] at ain
  | bookTermination => simp [Action.input?] at ain
  | foldTermination ref registry key =>
    simp only [Action.input?, Option.some.injEq] at ain
    subst ain
    simp only [action] at aok
    split at aok
    · rename_i x named
      have := namedInput_unique named mem rfl
      subst this
      simp only [spendTermination, Bool.and_eq_true, beq_iff_eq] at aok
      exact ⟨registry, key, amem, aok.1.1.1.1, aok.1.1.2, aok.1.2, aok.2⟩
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
When it folds registration requests and termination requests.
Then its `treasury_donation` is at least the sum of the registration costs of
the registration requests it folds and of the lovelace less the minimum tip of
the termination requests it folds. -/
theorem treasury_covers_registration_costs (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) :
    requiredTreasury i release o ≤ o.donation := by
  simp only [accepted, moneyRouted, Bool.and_eq_true, decide_eq_true_eq] at ok
  exact ok.1.1.2.2

/-- **Each folded request's registration cost is in the donation.**
Given an accepted transaction with a fold of a request whose configuration
record gives registration cost `c`.
When the transaction is accepted.
Then its treasury donation is at least `c`. -/
theorem folded_cost_in_donation (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {ref : OutRef} {index : Nat} {input : ObservedOutput} {data : RegistrationData}
    {p : ApplicationParameters}
    (folded : Action.foldRegistration ref index ∈ o.actions)
    (hs : spentRequest i release o ref = some (input, data, p)) :
    p.registrationCost ≤ o.donation := by
  have total := treasury_covers_registration_costs i env rp cp release o ok
  have member : p.registrationCost ∈ o.actions.filterMap (Action.treasuryDue i release o) :=
    List.mem_filterMap.mpr ⟨.foldRegistration ref index, folded, by simp [Action.treasuryDue, hs]⟩
  exact Nat.le_trans (le_sum_of_mem' member) total

/-- **A terminating fold donates the request less the tip.**
Given an accepted transaction with a terminating fold of a termination request
whose registry's configuration record gives minimum tip `tip`.
When the transaction is accepted.
Then its treasury donation is at least the request's lovelace less `tip`: the
folder keeps at most the tip (the economic termination donation). -/
theorem termination_fold_donates (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {ref : OutRef} {registry : TokenId} {key : Key} {input : ObservedOutput} {c : Configuration}
    (folded : Action.foldTermination ref registry key ∈ o.actions)
    (named : namedInput o ref = some input)
    (hc : configurationOf i release registry o = some c) :
    input.lovelace - c.parameters.minimumTip ≤ o.donation := by
  have total := treasury_covers_registration_costs i env rp cp release o ok
  have member : input.lovelace - c.parameters.minimumTip ∈
      o.actions.filterMap (Action.treasuryDue i release o) :=
    List.mem_filterMap.mpr ⟨.foldTermination ref registry key, folded,
      by simp [Action.treasuryDue, terminationDonation, named, hc]⟩
  exact Nat.le_trans (le_sum_of_mem' member) total

/-! ## The application's mint -/

/-- A token that is no entry's key has quantity zero. -/
theorem qty_eq_zero {l : List (TokenId × Int)} {asset : TokenId} (absent : asset ∉ l.map (·.1)) :
    ((l.filter fun entry => entry.1 == asset).map (·.2)).sum = 0 := by
  have empty : l.filter (fun entry => entry.1 == asset) = [] := by
    rw [List.filter_eq_nil_iff]
    intro e he h
    exact absent (List.mem_map.mpr ⟨e, he, by simpa using h⟩)
  simp [empty]

theorem sum_nonpos {l : List Int} (h : ∀ x ∈ l, x ≤ 0) : l.sum ≤ 0 := by
  induction l with
  | nil => simp
  | cons x t ih =>
    simp only [List.sum_cons]
    have hx := h x (by simp)
    have ht := ih (fun y hy => h y (by simp [hy]))
    omega

/-- **The application mints exactly what its actions justify.**
Given a transaction the KERI application accepts.
When its mint under the application policy is read.
Then every token under that policy is minted in exactly the quantity the
actions justify: one configuration token per created record, one registration
approval per distinct booked output, one approval burned per fold or return,
one termination approval burned per terminating fold, and nothing else. -/
theorem accepted_mint_is_justified (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {asset : TokenId}
    (policy : asset.policy = release.applicationPolicy) :
    SingularApplicationHeld.Assets.mintQty o.assets asset = justifiedQty i release o asset := by
  simp only [accepted, Bool.and_eq_true] at ok
  have closed := ok.1.2
  unfold mintClosed at closed
  by_cases m : asset ∈ o.assets.mint.map (·.1) ++ (justifiedMint i release o).map (·.1)
  · have each := List.all_eq_true.mp closed asset (List.mem_filter.mpr ⟨m, by simp [policy]⟩)
    simpa using each
  · simp only [List.mem_append, not_or] at m
    unfold justifiedQty SingularApplicationHeld.Assets.mintQty
    rw [qty_eq_zero m.1, qty_eq_zero m.2]

/-- **Each booked output is booked once.**
Given a transaction the KERI application accepts.
When its bookings are listed.
Then no output is booked twice. -/
theorem accepted_books_once (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) : (bookedOutputs o).Nodup := by
  simp only [accepted, Bool.and_eq_true] at ok
  simpa [bookedOnce] using ok.2

/-- Every action but a booking or a configuration creation justifies only burns. -/
theorem justifies_burns_only {i : Interpretation} {release : PublishedRelease} {o : Observation}
    {a : Action} (notBooking : a.booking? = none)
    (notConfiguration : ∀ registry seed index, a ≠ .createConfiguration registry seed index)
    {entry : TokenId × Int} (mem : entry ∈ a.justifies i release o) : entry.2 ≤ 0 := by
  cases a with
  | createConfiguration registry seed index => exact absurd rfl (notConfiguration registry seed index)
  | bookRegistration => simp [Action.booking?] at notBooking
  | foldTermination => simp [Action.justifies] at mem; simp [mem]
  | bookTermination => simp [Action.booking?] at notBooking
  | foldRegistration ref _ | returnRegistration ref =>
    simp only [Action.justifies] at mem
    split at mem
    · split at mem
      · simp at mem; simp [mem]
      · simp at mem
    · simp at mem

/-- **No approval without a booking.**
Given a transaction with no booking and no configuration creation (no action at
all, or only folds, returns and terminating folds), minting a positive quantity
of a token under the application policy, such as a registration approval of a
payload of the minter's choosing.
When the KERI application judges it.
Then it is refused: an approval exists only through a booking. -/
theorem mint_without_booking_refused (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (noBooking : ∀ a ∈ o.actions, a.booking? = none)
    (noConfiguration : ∀ registry seed index, Action.createConfiguration registry seed index ∉ o.actions)
    {asset : TokenId} (policy : asset.policy = release.applicationPolicy)
    (minted : 0 < SingularApplicationHeld.Assets.mintQty o.assets asset) :
    accepted i env rp cp release o = false := by
  cases h : accepted i env rp cp release o
  · rfl
  · have closed := accepted_mint_is_justified i env rp cp release o h policy
    have burns : justifiedQty i release o asset ≤ 0 := by
      unfold justifiedQty justifiedMint
      apply sum_nonpos
      intro x hx
      simp only [List.mem_map, List.mem_filter, List.mem_flatMap] at hx
      obtain ⟨entry, ⟨⟨a, amem, emem⟩, _⟩, rfl⟩ := hx
      exact justifies_burns_only (noBooking a amem)
        (fun registry seed index heq => noConfiguration registry seed index (heq ▸ amem)) emem
    omega

/-- **A booked output is booked once.**
Given a transaction whose actions book the same output twice.
When the KERI application judges it.
Then it is refused. -/
theorem duplicate_booking_refused (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {index : Nat}
    (twice : 2 ≤ (bookedOutputs o).count index) :
    accepted i env rp cp release o = false := by
  cases h : accepted i env rp cp release o
  · rfl
  · have once := List.nodup_iff_count.mp (accepted_books_once i env rp cp release o h) index
    omega

/-! ## The initial checkpoint state -/

/-- **The initial state is the checkpoint model's registration.**
Given registry and checkpoint parameters, a refund address, a registration
request and any checkpoint environment.
When the request's initial state is computed.
Then it is the state `s` exactly when the deposit leaves a pool above the
minimum ADA, the deposit and the freeze bond, and the checkpoint model's
registration step with that refund address and that pool, at the request's
booking bound, writes `s` from the absent checkpoint. -/
theorem initialState_is_registration (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (cenv : CardanoKeri.Checkpoint.Env)
    (refund : CardanoKeri.Checkpoint.Addr) (data : RegistrationData)
    (s : CardanoKeri.Checkpoint.State) :
    initialState rp cp refund data = some s ↔
      ∃ pool f, initialPool rp cp data = some pool ∧
        CardanoKeri.Checkpoint.Step cp cenv (.register refund pool) data.bookedAt .absent f s := by
  unfold initialState
  constructor
  · intro h
    split at h
    · rename_i pool hp
      split at h
      · rename_i hP
        cases h
        exact ⟨pool, _, hp, CardanoKeri.Checkpoint.Step.register _ _ _ hP⟩
      · contradiction
    · contradiction
  · rintro ⟨pool, f, hp, step⟩
    cases step with
    | register _ _ _ hpool => simp [hp, hpool]

/-- The floor arithmetic of an initial pool, over plain naturals. -/
theorem initial_pool_arithmetic {floor premium deposit : Nat} (covered : floor ≤ deposit)
    (pays : premium ≤ deposit - floor) :
    floor + premium ≤ deposit ∧ floor + (deposit - floor) = deposit := by
  omega

/-- **What the initial state holds.**
Given a request whose initial state for refund address `refund` is `s`.
When its datum facts and held value are read.
Then its facts are live at sequence number and epoch 0, neither poisoned,
frozen nor topped up, born at the booking bound and refunding to `refund`; the
deposit covers the minimum ADA, the deposit, the freeze bond and one premium;
and the checkpoint holds exactly the deposit. -/
theorem initialState_facts {rp : CardanoKeri.Registry.Params} {cp : CardanoKeri.Checkpoint.Params}
    {refund : CardanoKeri.Checkpoint.Addr} {data : RegistrationData}
    {s : CardanoKeri.Checkpoint.State} (h : initialState rp cp refund data = some s) :
    s.datumFacts = .present ⟨0, 0, false, false, data.bookedAt, refund, 0, false⟩ ∧
      rp.Mc + cp.D + cp.B + cp.P ≤ data.deposit ∧ s.heldValue cp rp = data.deposit := by
  unfold initialState at h
  cases hp : initialPool rp cp data with
  | none => simp [hp] at h
  | some pool =>
    simp only [hp] at h
    by_cases hP : cp.P ≤ pool
    · simp only [hP, if_true, Option.some.injEq] at h
      subst h
      unfold initialPool at hp
      by_cases floor : rp.Mc + cp.D + cp.B ≤ data.deposit
      · simp only [floor, if_true, Option.some.injEq] at hp
        subst hp
        have arithmetic := initial_pool_arithmetic floor hP
        refine ⟨rfl, arithmetic.1, ?_⟩
        rw [CardanoKeri.Checkpoint.present_held_value]
        simp only [Bool.false_eq_true, if_false]
        exact arithmetic.2
      · simp [floor] at hp
    · simp [hP] at h

/-- A raw datum that is the initial state decodes as the initial state of the
request's key, for the refund address the request names. -/
theorem initialStateDatum_inversion {i : Interpretation} {rp : CardanoKeri.Registry.Params}
    {cp : CardanoKeri.Checkpoint.Params} {data : RegistrationData} {raw : Nat}
    (h : initialStateDatum i rp cp data raw = true) :
    ∃ d refund s, i.decodeCheckpoint raw = some d ∧
      i.refundTo data.refundAddress = some refund ∧ initialState rp cp refund data = some s ∧
      i.keyOf d.aid = data.key ∧ d.state = s.datumFacts := by
  unfold initialStateDatum at h
  split at h
  · rename_i refund hr
    split at h
    · rename_i d s hd hs
      simp only [Bool.and_eq_true, beq_iff_eq] at h
      exact ⟨d, refund, s, hd, hr, hs, h.1, h.2⟩
    · contradiction
  · contradiction

/-- A holding that writes the initial state decodes as the initial state of
the request's key, for the refund address the request names. -/
theorem writesInitialState_inversion {i : Interpretation} {rp : CardanoKeri.Registry.Params}
    {cp : CardanoKeri.Checkpoint.Params} {data : RegistrationData} {holding : ObservedOutput}
    (h : writesInitialState i rp cp data holding = true) :
    ∃ raw d refund s, holding.datum = .application raw ∧ i.decodeCheckpoint raw = some d ∧
      i.refundTo data.refundAddress = some refund ∧ initialState rp cp refund data = some s ∧
      i.keyOf d.aid = data.key ∧ d.state = s.datumFacts := by
  unfold writesInitialState at h
  split at h
  · rename_i raw held
    obtain ⟨d, refund, s, rest⟩ := initialStateDatum_inversion h
    exact ⟨raw, d, refund, s, held, rest⟩
  · contradiction

/-- **What a datum that is the initial state says.**
Given a raw datum that is the initial state of a registration request, and any
checkpoint environment.
When it is decoded.
Then it is a checkpoint datum of the AID whose key the request names; the
request's refund address has a checkpoint refund address `refund`; and the
checkpoint model's registration step with `refund` and the pool the deposit
leaves above the minimum ADA, the deposit and the freeze bond, at the request's
booking bound, writes from the absent checkpoint a state whose facts are the
datum's and whose held value is the deposit: live at sequence number and epoch
0, neither poisoned, frozen nor topped up, born at the booking bound, with a
pool of at least one premium. -/
theorem initialStateDatum_is_registration {i : Interpretation} {rp : CardanoKeri.Registry.Params}
    {cp : CardanoKeri.Checkpoint.Params} (cenv : CardanoKeri.Checkpoint.Env)
    {data : RegistrationData} {raw : Nat} (h : initialStateDatum i rp cp data raw = true) :
    ∃ d refund pool f s, i.decodeCheckpoint raw = some d ∧ i.keyOf d.aid = data.key ∧
      i.refundTo data.refundAddress = some refund ∧
      CardanoKeri.Checkpoint.Step cp cenv (.register refund pool) data.bookedAt .absent f s ∧
      d.state = s.datumFacts ∧ data.deposit = s.heldValue cp rp ∧
      d.state = .present ⟨0, 0, false, false, data.bookedAt, refund, 0, false⟩ ∧
      pool = data.deposit - (rp.Mc + cp.D + cp.B) ∧ cp.P ≤ pool := by
  obtain ⟨d, refund, s, hd, hr, hs, key, facts⟩ := initialStateDatum_inversion h
  obtain ⟨pool, f, hp, step⟩ := (initialState_is_registration rp cp cenv refund data s).mp hs
  obtain ⟨written, floor, value⟩ := initialState_facts hs
  have pool_eq : pool = data.deposit - (rp.Mc + cp.D + cp.B) := by
    unfold initialPool at hp
    split at hp
    · cases hp; rfl
    · contradiction
  refine ⟨d, refund, pool, f, s, hd, key, hr, step, facts, value.symm, facts.trans written,
    pool_eq, ?_⟩
  have arithmetic : rp.Mc + cp.D + cp.B + cp.P ≤ data.deposit := floor
  rw [pool_eq]
  exact Nat.le_sub_of_add_le (by rw [Nat.add_comm]; exact arithmetic)

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

/-- **A booking validates everything KERI validates about a registration.**
Given an accepted booking of a request output.
When it is booked.
Then the request decodes to a registration of a `state(A_keri)` registry,
whose configuration record is read by reference; the holding address is the
checkpoint validator's credential the record names, which is not the
application credential; the deposit is at least the registry's minimum ADA
plus its deposit; the output holds exactly the deposit, the registration cost
and the minimum tip; the deadline is the booking's upper bound plus the
processing time; one approval of the payload is minted; the request's key has
its inception evidence; and the initial datum the request carries is exactly
the initial state of the request's key. -/
theorem booking_inversion (i : Interpretation) (env : Env) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (release : PublishedRelease) (o : Observation)
    {output : ObservedOutput}
    (ok : bookRegistration i env rp cp release o output = true) :
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
        (registrationAsset i.hash i.code release data) = 1 ∧
      env.inception data.key = true ∧
      initialStateDatum i rp cp data data.initialDatum = true := by
  unfold bookRegistration at ok
  split at ok
  · rename_i data hd
    split at ok
    · rename_i c hc
      simp only [Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, decide_eq_true_eq,
        bookingClock] at ok
      obtain ⟨⟨⟨⟨⟨⟨⟨⟨⟨_, policy⟩, address⟩, distinct⟩, floor⟩, exact⟩,
        ⟨⟨⟨⟨_, booked⟩, _⟩, deadline⟩, _⟩⟩, evidence⟩, initial⟩, minted⟩ := ok
      exact ⟨data, c, hd, hc, policy, address, distinct, floor, exact, booked, deadline, minted,
        evidence, initial⟩
    · contradiction
  · contradiction

/-- **A booking for a key without inception evidence is refused.**
Given a request output decoding to a registration whose key has no inception
evidence.
When it is booked.
Then the booking is refused: no approval is minted for it, so there is no
request to fold. -/
theorem booking_refuses_missing_inception (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (missing : env.inception data.key = false) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · obtain ⟨d, _, hd', _, _, _, _, _, _, _, _, _, evidence, _⟩ :=
      booking_inversion i env rp cp release o h
    rw [hd] at hd'
    cases hd'
    rw [missing] at evidence
    contradiction

/-- **A booking names only a registry of `state(A_keri)`.**
Given a request output decoding to a registration that names a registry whose
state policy is not the release's state policy `state(A_keri)`.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_foreign_registry (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (foreign : data.registry.policy ≠ release.statePolicy) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · obtain ⟨d, _, hd', _, policy, _⟩ := booking_inversion i env rp cp release o h
    rw [hd] at hd'
    cases hd'
    exact absurd policy foreign

/-- **A booking that commits the application address as the holding is refused.**
Given a registration whose committed holding address is the application
credential.
When it is booked.
Then the booking is refused: a checkpoint is never delivered where the
application's own records live. -/
theorem booking_refuses_application_holding (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    {output : ObservedOutput} {data : RegistrationData}
    (hd : decoded i.decode output = some (.registration data))
    (atApplication : data.holdingAddress = release.applicationCredential) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · obtain ⟨d, _, hd', _, _, address, distinct, _⟩ := booking_inversion i env rp cp release o h
    rw [hd] at hd'
    cases hd'
    exact absurd (address.symm.trans atApplication) distinct

/-- **A booking that commits another holding address than the checkpoint
validator's is refused.**
Given a registration whose configuration record names checkpoint credential
`c.checkpointCredential`, and whose committed holding address differs from it.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_other_holding (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} {c : Configuration}
    (hd : decoded i.decode output = some (.registration data))
    (hc : configurationOf i release data.registry o = some c)
    (other : data.holdingAddress ≠ c.checkpointCredential) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · obtain ⟨d, q, hd', hq, _, address, _⟩ := booking_inversion i env rp cp release o h
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
theorem booking_refuses_short_deposit (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (short : data.deposit < rp.Mc + rp.D) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · obtain ⟨d, _, hd', _, _, _, _, floor, _⟩ := booking_inversion i env rp cp release o h
    rw [hd] at hd'
    cases hd'
    omega

/-- **A booking holding anything but the exact contents is refused.**
Given a registration whose request output does not hold exactly its deposit,
its registry's registration cost and minimum tip.
When it is booked.
Then the booking is refused. -/
theorem booking_refuses_inexact_contents (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} {c : Configuration}
    (hd : decoded i.decode output = some (.registration data))
    (hc : configurationOf i release data.registry o = some c)
    (inexact : output.lovelace ≠ requestLovelace c.parameters data) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · obtain ⟨d, q, hd', hq, _, _, _, _, exact, _⟩ := booking_inversion i env rp cp release o h
    rw [hd] at hd'
    cases hd'
    rw [hc] at hq
    cases hq
    exact absurd exact inexact

/-! ## The initial datum a booking commits -/

/-- The initial datum of a booked request is the initial state of its key. -/
theorem booking_initial_state {i : Interpretation} {env : Env} {rp : CardanoKeri.Registry.Params}
    {cp : CardanoKeri.Checkpoint.Params} {release : PublishedRelease} {o : Observation}
    {output : ObservedOutput} {data : RegistrationData}
    (ok : bookRegistration i env rp cp release o output = true)
    (hd : decoded i.decode output = some (.registration data)) :
    initialStateDatum i rp cp data data.initialDatum = true := by
  obtain ⟨d, _, hd', _, _, _, _, _, _, _, _, _, _, initial⟩ :=
    booking_inversion i env rp cp release o ok
  rw [hd] at hd'
  cases hd'
  exact initial

/-- **A booking committing a checkpoint in any other state is refused.**
Given a registration request whose refund address has the checkpoint refund
address `refund`, and whose initial datum decodes as a checkpoint datum whose
state is not live at sequence number and epoch 0, neither poisoned, frozen nor
topped up, born at the request's booking bound and refunding to `refund`:
another sequence number, epoch, poison, freeze or top-up flag, birth slot or
refund address, or a pending termination.
When it is booked.
Then the booking is refused. On main the fold refused it
(`fold_refuses_other_state`); the datum is now validated once, before the
approval exists. -/
theorem booking_refuses_other_state (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData}
    {d : CardanoKeri.ConsumerIdentity.DecodedDatum} {refund : CardanoKeri.Checkpoint.Addr}
    (hd : decoded i.decode output = some (.registration data))
    (hdec : i.decodeCheckpoint data.initialDatum = some d)
    (hr : i.refundTo data.refundAddress = some refund)
    (other : d.state ≠ .present ⟨0, 0, false, false, data.bookedAt, refund, 0, false⟩) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · have initial := booking_initial_state h hd
    obtain ⟨d', refund', s, hd', hr', hs, _, facts⟩ := initialStateDatum_inversion initial
    have written := facts.trans (initialState_facts hs).1
    rw [hdec] at hd'
    cases hd'
    rw [hr] at hr'
    cases hr'
    exact absurd written other

/-- **A booking committing the checkpoint of another AID is refused.**
Given a registration request whose initial datum decodes as a checkpoint datum
of an AID whose key is not the key the request names.
When it is booked.
Then the booking is refused. On main the fold refused it
(`fold_refuses_other_aid`). -/
theorem booking_refuses_other_aid (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} {d : CardanoKeri.ConsumerIdentity.DecodedDatum}
    (hd : decoded i.decode output = some (.registration data))
    (hdec : i.decodeCheckpoint data.initialDatum = some d) (other : i.keyOf d.aid ≠ data.key) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · have initial := booking_initial_state h hd
    obtain ⟨d', _, _, hd', _, _, key, _⟩ := initialStateDatum_inversion initial
    rw [hdec] at hd'
    cases hd'
    exact absurd key other

/-- **A booking whose deposit cannot pay one premium is refused.**
Given a registration request whose deposit is below the minimum ADA, the
checkpoint deposit, the freeze bond and one premium.
When it is booked.
Then the booking is refused: no initial state has a pool below one premium.
On main such a request was booked and its fold refused
(`fold_refuses_pool_below_premium`), so it waited for its deadline to be
returned. -/
theorem booking_refuses_pool_below_premium (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (short : data.deposit < rp.Mc + cp.D + cp.B + cp.P) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · have initial := booking_initial_state h hd
    obtain ⟨_, _, _, _, _, hs, _⟩ := initialStateDatum_inversion initial
    have := (initialState_facts hs).2.1
    omega

/-- **A booking for a refund address no checkpoint can record is refused.**
Given a registration request whose refund address has no checkpoint refund
address.
When it is booked.
Then the booking is refused. On main the fold refused it
(`fold_refuses_unrecorded_refund`). -/
theorem booking_refuses_unrecorded_refund (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) {output : ObservedOutput}
    {data : RegistrationData} (hd : decoded i.decode output = some (.registration data))
    (unrecorded : i.refundTo data.refundAddress = none) :
    bookRegistration i env rp cp release o output = false := by
  cases h : bookRegistration i env rp cp release o output
  · rfl
  · have initial := booking_initial_state h hd
    obtain ⟨_, _, _, _, hr, _⟩ := initialStateDatum_inversion initial
    rw [unrecorded] at hr
    cases hr

/-- **A booked request commits exactly the initial checkpoint state.**
Given an accepted booking of a request, and any checkpoint environment.
When the request's initial datum is read.
Then it is a checkpoint datum of the AID whose key the request names, for the
checkpoint refund address `refund` of the request's refund address; and the
checkpoint model's registration step with `refund` and the pool the deposit
leaves above the minimum ADA, the deposit and the freeze bond, at the request's
booking bound, writes from the absent checkpoint a state whose facts are the
datum's and whose held value is the committed deposit: live at sequence number
and epoch 0, neither poisoned, frozen nor topped up, born at the booking
bound, with a pool of at least one premium. -/
theorem booked_initial_state {i : Interpretation} {env : Env}
    {rp : CardanoKeri.Registry.Params} {cp : CardanoKeri.Checkpoint.Params}
    (cenv : CardanoKeri.Checkpoint.Env) {release : PublishedRelease} {booking : Observation}
    {request : ObservedOutput} {data : RegistrationData}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data)) :
    ∃ d refund pool f s, i.decodeCheckpoint data.initialDatum = some d ∧
      i.keyOf d.aid = data.key ∧
      i.refundTo data.refundAddress = some refund ∧
      CardanoKeri.Checkpoint.Step cp cenv (.register refund pool) data.bookedAt .absent f s ∧
      d.state = s.datumFacts ∧ data.deposit = s.heldValue cp rp ∧
      d.state = .present ⟨0, 0, false, false, data.bookedAt, refund, 0, false⟩ ∧
      pool = data.deposit - (rp.Mc + cp.D + cp.B) ∧ cp.P ≤ pool :=
  initialStateDatum_is_registration cenv (booking_initial_state booked hb)


/-! ## The fold's holding -/

/-- **A fold delivering any other lovelace than the deposit is refused.**
Given a booked registration and a fold naming a holding whose lovelace differs
from the committed deposit, by one lovelace more or less.
When the request is spent by that fold.
Then the spend is refused. -/
theorem fold_refuses_inexact_holding (i : Interpretation) (release : PublishedRelease)
    (o : Observation) {ref : OutRef} {index : Nat} {input holding : ObservedOutput}
    {data : RegistrationData} (hh : o.outputs[index]? = some holding)
    (inexact : holding.lovelace ≠ data.deposit) :
    spendRegistration i release o (.foldRegistration ref index) input data = false := by
  unfold spendRegistration
  split
  · rfl
  · simp [hh, delivered, inexact]

/-- **A fold delivering another datum than the committed one is refused.**
Given a fold naming a holding whose datum is not the initial datum the request
commits: no application datum, or another one.
When the request is spent by that fold.
Then the spend is refused: a fold delivers the datum the approval binds, which
the request carries. -/
theorem fold_refuses_other_datum (i : Interpretation) (release : PublishedRelease)
    (o : Observation) {ref : OutRef} {index : Nat} {input holding : ObservedOutput}
    {data : RegistrationData} (hh : o.outputs[index]? = some holding)
    (other : holding.datum ≠ .application data.initialDatum) :
    spendRegistration i release o (.foldRegistration ref index) input data = false := by
  unfold spendRegistration
  split
  · rfl
  · simp [hh, delivered, other]

/-- **A fold delivering to another address than the committed one is refused.**
Given a fold naming a holding that is not at the holding address the request
commits.
When the request is spent by that fold.
Then the spend is refused. -/
theorem fold_refuses_other_address (i : Interpretation) (release : PublishedRelease)
    (o : Observation) {ref : OutRef} {index : Nat} {input holding : ObservedOutput}
    {data : RegistrationData} (hh : o.outputs[index]? = some holding)
    (other : holding.credential ≠ data.holdingAddress) :
    spendRegistration i release o (.foldRegistration ref index) input data = false := by
  unfold spendRegistration
  split
  · rfl
  · simp [hh, delivered, other]


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

/-- A delivered holding sits at the committed holding address. -/
theorem delivered_credential {i : Interpretation} {data : RegistrationData}
    {holding : ObservedOutput} {o : Observation} (h : delivered i data holding o = true) :
    holding.credential = data.holdingAddress := by
  simp only [delivered, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1.1.1.1

/-- A fold spend that is not refused delivers a holding. -/
theorem fold_spend_delivers {i : Interpretation} {release : PublishedRelease} {o : Observation}
    {ref : OutRef} {index : Nat} {input : ObservedOutput} {data : RegistrationData}
    (h : spendRegistration i release o (.foldRegistration ref index) input data = true) :
    ∃ holding, o.outputs[index]? = some holding ∧ delivered i data holding o = true := by
  unfold spendRegistration at h
  split at h
  · contradiction
  · simp only [Bool.and_eq_true] at h
    obtain ⟨_, _, holding⟩ := h
    split at holding
    · rename_i x hx
      exact ⟨x, hx, holding⟩
    · contradiction

/-- **Every fold delivers what its request's approval commits.**
Given a transaction the KERI application accepts.
When it folds a registration request, naming the output it delivers.
Then the named request is spent exactly once and decodes as a registration,
and the delivered holding is at the committed address, carries a datum of the
committed hash, and holds exactly the committed deposit and the one new
active token of the key. -/
theorem fold_delivers_committed (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {ref : OutRef} {index : Nat}
    (folded : Action.foldRegistration ref index ∈ o.actions) :
    ∃ input data holding, namedInput o ref = some input ∧
      decoded i.decode input = some (.registration data) ∧
      o.outputs[index]? = some holding ∧ delivered i data holding o = true := by
  simp only [accepted, Bool.and_eq_true] at ok
  have aok := List.all_eq_true.mp ok.1.1.1.2 _ folded
  simp only [action] at aok
  split at aok
  · rename_i input named
    split at aok
    · rename_i data hd
      obtain ⟨holding, hh, hdel⟩ := fold_spend_delivers aok
      exact ⟨input, data, holding, named, hd, hh, hdel⟩
    · contradiction
  · contradiction

/-- **Every fold delivers its checkpoint to the checkpoint validator.**
Given a request booked by an accepted booking, and a transaction the KERI
application accepts that folds a request of the same registration data, naming
the output it delivers.
When the delivered holding is inspected.
Then it sits at the holding address the request committed, which is the
checkpoint validator's credential named by the configuration record the
booking read, and is not the application's. On main the fold compared the
holding with the record it read itself; the address is now validated once, at
the booking, and the fold delivers to the committed address. -/
theorem fold_delivers_to_checkpoint_validator (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) {booking o : Observation} {request input : ObservedOutput}
    {data : RegistrationData}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (ok : accepted i env rp cp release o = true) {ref : OutRef} {index : Nat}
    (folded : Action.foldRegistration ref index ∈ o.actions)
    (named : namedInput o ref = some input)
    (hd : decoded i.decode input = some (.registration data)) :
    ∃ c holding, configurationOf i release data.registry booking = some c ∧
      o.outputs[index]? = some holding ∧ delivered i data holding o = true ∧
      holding.credential = c.checkpointCredential ∧
      holding.credential = data.holdingAddress ∧
      holding.credential ≠ release.applicationCredential := by
  obtain ⟨input', data', holding, named', hd', hh, hdel⟩ :=
    fold_delivers_committed i env rp cp release o ok folded
  rw [named] at named'
  cases named'
  rw [hd] at hd'
  cases hd'
  obtain ⟨d, c, hb', hc, _, address, distinct, _⟩ := booking_inversion i env rp cp release booking booked
  rw [hb] at hb'
  cases hb'
  have cred := delivered_credential hdel
  exact ⟨c, holding, hc, hh, hdel, cred.trans address, cred, by rw [cred, address]; exact distinct⟩

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
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {input : ObservedOutput} {raw : Nat} (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (held : input.datum = .application raw)
    (notRequest : ∀ data, i.decode raw ≠ some (.registration data)) : False := by
  have notDecoded : ∀ data, decoded i.decode input ≠ some (.registration data) := by
    intro data h
    exact notRequest data (by simpa [decoded, held] using h)
  obtain ⟨registry, key, amem, _⟩ :=
    termination_only_by_fold i env rp cp release o ok mem atApplication notDecoded
  simp only [accepted, Bool.and_eq_true] at ok
  have aok := List.all_eq_true.mp ok.1.1.1.2 _ amem
  simp only [action] at aok
  split at aok
  · rename_i x named
    have := namedInput_unique named mem rfl
    subst this
    simp [spendTermination, terminationShape, appGuard, held, application_beq_empty,
      none_beq_flip] at aok
  · contradiction

/-! ## The checkpoint a fold delivers -/

/-- A delivered holding carries the initial datum its request commits. -/
theorem delivered_holds_committed {i : Interpretation} {data : RegistrationData}
    {holding : ObservedOutput} {o : Observation} (h : delivered i data holding o = true) :
    holding.datum = .application data.initialDatum := by
  simp only [delivered, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  exact h.1.1.1.2

/-- **A delivered holding is exactly the initial checkpoint state.**
Given a request booked by an accepted booking, a holding delivered for it by a
fold, and any checkpoint environment.
When the holding's datum and lovelace are read.
Then its datum is the request's initial datum, a checkpoint datum of the AID
whose key the request names; the request's refund address has a checkpoint
refund address `refund`; and the checkpoint model's registration step with
`refund` and the pool the deposit leaves above the minimum ADA, the deposit
and the freeze bond, at the request's booking bound, writes from the absent
checkpoint a state whose facts are the datum's and whose held value is the
holding's lovelace: live at sequence number and epoch 0, neither poisoned,
frozen nor topped up, born at the booking bound, with a pool of at least one
premium. On main the fold checked the datum itself; the booking now does, and
the fold delivers the committed datum. -/
theorem delivered_initial_state {i : Interpretation} {env : Env}
    {rp : CardanoKeri.Registry.Params} {cp : CardanoKeri.Checkpoint.Params}
    (cenv : CardanoKeri.Checkpoint.Env) {release : PublishedRelease} {booking fold : Observation}
    {request holding : ObservedOutput} {data : RegistrationData}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (h : delivered i data holding fold = true) :
    ∃ d refund pool f s, holding.datum = .application data.initialDatum ∧
      i.decodeCheckpoint data.initialDatum = some d ∧ i.keyOf d.aid = data.key ∧
      i.refundTo data.refundAddress = some refund ∧
      CardanoKeri.Checkpoint.Step cp cenv (.register refund pool) data.bookedAt .absent f s ∧
      d.state = s.datumFacts ∧ holding.lovelace = s.heldValue cp rp ∧
      d.state = .present ⟨0, 0, false, false, data.bookedAt, refund, 0, false⟩ ∧
      pool = data.deposit - (rp.Mc + cp.D + cp.B) ∧ cp.P ≤ pool := by
  have held := delivered_holds_committed h
  obtain ⟨d, refund, pool, f, s, hd, key, hr, step, facts, value, written, pool_eq, premium⟩ :=
    booked_initial_state cenv booked hb
  simp only [delivered, Bool.and_eq_true, beq_iff_eq] at h
  exact ⟨d, refund, pool, f, s, held, hd, key, hr, step, facts, h.1.1.2.trans value, written,
    pool_eq, premium⟩

/-- **A delivered holding writes the initial state.**
Given a request booked by an accepted booking and a holding delivered for it.
When the holding is tested for the initial state of the request's key.
Then it writes it. -/
theorem delivered_writes_initial_state {i : Interpretation} {env : Env}
    {rp : CardanoKeri.Registry.Params} {cp : CardanoKeri.Checkpoint.Params}
    {release : PublishedRelease} {booking fold : Observation}
    {request holding : ObservedOutput} {data : RegistrationData}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (h : delivered i data holding fold = true) :
    writesInitialState i rp cp data holding = true := by
  have held := delivered_holds_committed h
  have initial := booking_initial_state booked hb
  simp [writesInitialState, held, initial]

/-- **A fold delivers exactly the initial checkpoint state.**
Given a request booked by an accepted booking, any checkpoint environment, and
a transaction the KERI application accepts that folds a request of the same
registration data, naming the output it delivers.
When the delivered holding is read.
Then it is exactly the state the checkpoint model's registration step writes
for the request: its datum is the request's initial datum, a checkpoint datum
of the AID whose key the request names, live at sequence number and epoch 0,
neither poisoned, frozen nor topped up, born at the request's booking bound
and refunding to the refund address the request names; its lovelace is that
state's held value, whose pool is the deposit less the minimum ADA, the
deposit and the freeze bond and covers at least one premium. -/
theorem fold_delivers_initial_state (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (cenv : CardanoKeri.Checkpoint.Env) (release : PublishedRelease) {booking o : Observation}
    {request input : ObservedOutput} {data : RegistrationData}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (ok : accepted i env rp cp release o = true) {ref : OutRef} {index : Nat}
    (folded : Action.foldRegistration ref index ∈ o.actions)
    (named : namedInput o ref = some input)
    (hd : decoded i.decode input = some (.registration data)) :
    ∃ holding d refund pool f s, o.outputs[index]? = some holding ∧
      holding.datum = .application data.initialDatum ∧
      i.decodeCheckpoint data.initialDatum = some d ∧ i.keyOf d.aid = data.key ∧
      i.refundTo data.refundAddress = some refund ∧
      CardanoKeri.Checkpoint.Step cp cenv (.register refund pool) data.bookedAt .absent f s ∧
      d.state = s.datumFacts ∧ holding.lovelace = s.heldValue cp rp ∧
      d.state = .present ⟨0, 0, false, false, data.bookedAt, refund, 0, false⟩ ∧
      pool = data.deposit - (rp.Mc + cp.D + cp.B) ∧ cp.P ≤ pool := by
  obtain ⟨input', data', holding, named', hd', hh, hdel⟩ :=
    fold_delivers_committed i env rp cp release o ok folded
  rw [named] at named'
  cases named'
  rw [hd] at hd'
  cases hd'
  obtain ⟨d, refund, pool, f, s, rest⟩ := delivered_initial_state cenv booked hb hdel
  exact ⟨holding, d, refund, pool, f, s, hh, rest⟩

/-! ## A genuine checkpoint -/

/-- **A delivered checkpoint is genuine.**
Given a request booked by an accepted booking that read the configuration
record `c`, and a fold delivering a holding for it.
When the holding is inspected.
Then it is genuine: at the checkpoint validator's credential `c` names, not
the application's; holding the one active token of the key under a registry of
`state(A_keri)`; carrying the committed initial datum; holding exactly the
committed deposit. -/
theorem delivered_is_genuine (i : Interpretation) (env : Env) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) {booking fold : Observation} {request holding : ObservedOutput}
    {data : RegistrationData} {c : Configuration}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (hc : configurationOf i release data.registry booking = some c)
    (hdel : delivered i data holding fold = true) :
    genuine i release c data holding := by
  obtain ⟨d, c', hd', hc', policy, address, distinct, _⟩ :=
    booking_inversion i env rp cp release booking booked
  rw [hb] at hd'
  cases hd'
  rw [hc] at hc'
  cases hc'
  simp only [delivered, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hdel
  obtain ⟨⟨⟨⟨atAddress, datum⟩, lovelace⟩, quantity⟩, _⟩ := hdel
  refine ⟨atAddress.trans address, ?_, policy, quantity, datum, lovelace⟩
  rw [atAddress, address]
  exact distinct

/-- **Until its deadline a booked request is spent only by delivering a
genuine checkpoint.**
Given a request booked by an accepted booking, and an accepted transaction
spending it at the application address whose validity interval starts before
the request's deadline.
When the request is spent.
Then a fold names it and delivers a genuine checkpoint, at the checkpoint
validator named by the configuration record the booking read. -/
theorem before_deadline_delivers_genuine (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) {booking o : Observation}
    {request input : ObservedOutput} {data : RegistrationData}
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (ok : accepted i env rp cp release o = true) (mem : input ∈ o.inputs)
    (atApplication : input.credential = release.applicationCredential)
    (hd : decoded i.decode input = some (.registration data))
    (early : o.interval.lower < data.processDeadline) :
    ∃ c index holding, configurationOf i release data.registry booking = some c ∧
      Action.foldRegistration input.reference index ∈ o.actions ∧
      o.outputs[index]? = some holding ∧ genuine i release c data holding := by
  obtain ⟨_, index, holding, _, amem, hh, hdel⟩ :=
    before_deadline_only_fold i env rp cp release o ok mem atApplication hd early
  obtain ⟨d, c, hd', hc, _⟩ := booking_inversion i env rp cp release booking booked
  rw [hb] at hd'
  cases hd'
  exact ⟨c, index, holding, hc, amem, hh,
    delivered_is_genuine i env rp cp release booked hb hc hdel⟩

/-- **A genuine checkpoint carries the version 2 datum its request committed.**
Given a genuine checkpoint whose request committed the raw version 2
checkpoint datum `d`.
When the holding's datum is read.
Then it is that raw datum. On main the request's field was read as the hash of
the datum and this needed a datum hash with no collision; the field is the
datum itself, as in the upstream model. -/
theorem genuine_holds_committed_datum {i : Interpretation} {release : PublishedRelease}
    {c : Configuration} {data : RegistrationData} {holding : ObservedOutput}
    (g : genuine i release c data holding) {d : CheckpointDatum.Data}
    (committed : data.initialDatum = CheckpointDatum.raw d) :
    holding.datum = .application (CheckpointDatum.raw d) := by
  obtain ⟨_, _, _, _, datum, _⟩ := g
  rw [datum, committed]

/-- **A genuine checkpoint satisfies the consumer's holding clauses.**
Given a genuine checkpoint whose request committed the raw version 2 datum
written for the consumer's AID and a state with an output; a consumer context
naming the checkpoint credential of the configuration record, the registry the
request named and the request's key for its AID, whose active token of that
registry and key is the application's; and an authenticated environment.
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
    (active : activeAsset i.hash i.code data.registry data.key =
      activeAsset CheckpointDatum.interpretation.hash CheckpointDatum.interpretation.code
        data.registry data.key)
    (registry : data.registry =
      CardanoKeri.ConsumerIdentity.registryAsset CheckpointDatum.interpretation cc)
    (key : data.key = CheckpointDatum.interpretation.keyOf cc.aid)
    {s : CardanoKeri.Checkpoint.State} {k : CheckpointDatum.KeyMaterial} {d : CheckpointDatum.Data}
    (written : CheckpointDatum.datum cc.aid k s = some d) (bytewise : k.Bytewise)
    (committed : data.initialDatum = CheckpointDatum.raw d) :
    CardanoKeri.ConsumerIdentity.consumableHolding CheckpointDatum.interpretation cc e p now
        holding ↔ CardanoKeri.Checkpoint.consumableState p now s := by
  have held := genuine_holds_committed_datum g committed
  obtain ⟨atCheckpoint, _, _, quantity, _, _⟩ := g
  rw [active, registry, key] at quantity
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


/-! ## Booking a termination -/

/-- The input an action names is an input of the transaction. -/
theorem namedInput_mem {o : Observation} {ref : OutRef} {x : ObservedOutput}
    (named : namedInput o ref = some x) : x ∈ o.inputs := by
  unfold namedInput at named
  split at named
  · exact List.mem_of_find?_eq_some named
  · contradiction

/-- A token compares equal to itself. -/
theorem token_beq_self (a : TokenId) : (a == a) = true := by
  cases a; simp [BEq.beq, instBEqTokenId.beq]

/-- An output holding exactly one unit of one asset holds one unit of it. -/
theorem exactAssets_single {output : ObservedOutput} {asset : TokenId}
    (h : exactAssets output [(asset, 1)] = true) : quantity output asset = 1 := by
  unfold exactAssets at h
  have each := List.all_eq_true.mp h asset (by simp)
  simpa [token_beq_self] using each

/-- A list of integers with a positive sum has a positive member. -/
theorem exists_pos_of_sum_pos {l : List Int} (h : 0 < l.sum) : ∃ x ∈ l, 0 < x := by
  apply Classical.byContradiction
  intro none
  have : l.sum ≤ 0 := sum_nonpos fun x hx =>
    Int.not_lt.mp fun positive => none ⟨x, hx, positive⟩
  omega

/-- **The pending output a booking spends is a conviction's.**
Given an output the termination booking accepts as the convicted pending
output of `key` under a configuration record.
When its fields are read.
Then it sits at the checkpoint validator's credential the record names, holds
exactly the registry's minimum ADA and one active token of the key, and
carries the pending-termination datum of an AID whose key is `key`. -/
theorem convictedPending_inversion {i : Interpretation} {rp : CardanoKeri.Registry.Params}
    {c : Configuration} {registry : TokenId} {key : Key} {input : ObservedOutput}
    (h : convictedPending i rp c registry key input = true) :
    input.credential = c.checkpointCredential ∧ input.lovelace = rp.Mc ∧
      quantity input (activeAsset i.hash i.code registry key) = 1 ∧
      ∃ d k, checkpointDatum i input = some d ∧ i.keyOf d.aid = key ∧
        d.state = .terminationPending k := by
  unfold convictedPending readPendingSpend at h
  split at h <;> try contradiction
  rename_i aid position datum
  split at h <;> try contradiction
  rename_i accepted
  simp only [Bool.and_eq_true, beq_iff_eq] at accepted
  obtain ⟨⟨⟨credential, lovelace⟩, assets⟩, sameKey⟩ := accepted
  exact ⟨credential, lovelace, exactAssets_single assets, _, position, datum, sameKey, rfl⟩

/-- **A termination booking spends a convicted pending output and places the
request the terminating fold consumes.**
Given a transaction the KERI application accepts, with a termination booking
of `key` under `registry` naming an input and an output.
When the booking is read.
Then the registry's configuration record is read by reference and its state
policy is `state(A_keri)`; the input, spent once, is the convicted pending
output of the key at the checkpoint validator's credential (exactly the
minimum ADA and the active token, a pending-termination datum of an AID whose
key is `key`); the output is the termination request the terminating fold
accepts (`terminationShape`: the application address, an empty datum, exactly
the active token and the termination approval) holding exactly `Mr` plus the
minimum tip; exactly one termination approval of the registry and key is
minted. -/
theorem termination_booking_inversion (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true)
    {ref : OutRef} {index : Nat} {registry : TokenId} {key : Key}
    (booked : Action.bookTermination ref index registry key ∈ o.actions) :
    ∃ c input output, configurationOf i release registry o = some c ∧
      namedInput o ref = some input ∧ o.outputs[index]? = some output ∧
      registry.policy = release.statePolicy ∧
      convictedPending i rp c registry key input = true ∧
      terminationShape .none i.hash i.code release output registry key = true ∧
      output.lovelace = terminationLovelace rp c.parameters ∧
      SingularApplicationHeld.Assets.mintQty o.assets
        (terminationApproval i.hash i.code release registry key) = 1 := by
  simp only [accepted, Bool.and_eq_true] at ok
  obtain ⟨⟨⟨⟨_, actions⟩, _⟩, _⟩, _⟩ := ok
  have aok := List.all_eq_true.mp actions _ booked
  simp only [action] at aok
  split at aok
  · rename_i input output named hout
    unfold bookTermination at aok
    split at aok
    · rename_i c hc
      simp only [Bool.and_eq_true, beq_iff_eq] at aok
      obtain ⟨⟨⟨⟨policy, pending⟩, shape⟩, lovelace⟩, minted⟩ := aok
      exact ⟨c, input, output, hc, named, hout, policy, pending, shape, lovelace, minted⟩
    · contradiction
  · contradiction

/-- **No termination approval without a termination booking of that key.**
Given a transaction the KERI application accepts that mints a positive
quantity of the termination approval of `key` under `registry`, and that no
other preimage hashes to that approval's name.
When the application's mint is read.
Then a termination booking of exactly that registry and key is among its
actions. -/
theorem termination_approval_requires_booking (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {registry : TokenId} {key : Key}
    (unique : ∀ p, i.hash (i.code p) = i.hash (i.code (.terminationApproval registry key)) →
      p = .terminationApproval registry key)
    (minted : 0 < SingularApplicationHeld.Assets.mintQty o.assets
      (terminationApproval i.hash i.code release registry key)) :
    ∃ ref index, Action.bookTermination ref index registry key ∈ o.actions := by
  have justified := accepted_mint_is_justified i env rp cp release o ok
    (asset := terminationApproval i.hash i.code release registry key) rfl
  rw [justified] at minted
  unfold justifiedQty justifiedMint at minted
  obtain ⟨x, hx, positive⟩ := exists_pos_of_sum_pos minted
  simp only [List.mem_map, List.mem_filter, List.mem_flatMap] at hx
  obtain ⟨entry, ⟨⟨a, amem, emem⟩, same⟩, rfl⟩ := hx
  have same := SingularApplicationHeld.Proofs.token_eq _ _ same
  cases a with
  | createConfiguration r seed index =>
    simp only [Action.justifies, List.mem_singleton] at emem
    subst emem
    simp only [configurationAsset, terminationApproval, TokenId.mk.injEq] at same
    exact absurd (unique _ same.2) (by simp)
  | bookRegistration index =>
    simp only [Action.justifies] at emem
    split at emem
    · split at emem
      · simp only [List.mem_singleton] at emem
        subst emem
        simp only [registrationAsset, registrationApproval, terminationApproval,
          TokenId.mk.injEq] at same
        exact absurd (unique _ same.2) (by simp)
      · simp at emem
    · simp at emem
  | bookTermination ref index r k =>
    simp only [Action.justifies, List.mem_singleton] at emem
    subst emem
    simp only [terminationApproval, TokenId.mk.injEq] at same
    have pre := unique _ same.2
    simp only [Preimage.terminationApproval.injEq] at pre
    obtain ⟨rfl, rfl⟩ := pre
    exact ⟨ref, index, amem⟩
  | foldTermination =>
    simp only [Action.justifies, List.mem_singleton] at emem
    subst emem; simp at positive
  | foldRegistration ref _ | returnRegistration ref =>
    simp only [Action.justifies] at emem
    split at emem
    · split at emem
      · simp only [List.mem_singleton] at emem
        subst emem; simp at positive
      · simp at emem
    · simp at emem

/-- **No termination approval without a convicted pending output of that key.**
Given a transaction the KERI application accepts that mints a positive
quantity of the termination approval of `key` under `registry`, and that no
other preimage hashes to that approval's name.
When the application's mint is read.
Then exactly one is minted, and the transaction spends, once, an output at the
checkpoint validator's credential the registry's configuration record names
that holds exactly the minimum ADA and the key's one active token and carries
the pending-termination datum of an AID whose key is `key`; it places the
termination request of the key holding exactly `Mr` plus the minimum tip. -/
theorem termination_approval_requires_pending (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {registry : TokenId} {key : Key}
    (unique : ∀ p, i.hash (i.code p) = i.hash (i.code (.terminationApproval registry key)) →
      p = .terminationApproval registry key)
    (minted : 0 < SingularApplicationHeld.Assets.mintQty o.assets
      (terminationApproval i.hash i.code release registry key)) :
    SingularApplicationHeld.Assets.mintQty o.assets
        (terminationApproval i.hash i.code release registry key) = 1 ∧
      ∃ c input output d k, configurationOf i release registry o = some c ∧
        input ∈ o.inputs ∧ input.credential = c.checkpointCredential ∧ input.lovelace = rp.Mc ∧
        quantity input (activeAsset i.hash i.code registry key) = 1 ∧
        checkpointDatum i input = some d ∧ i.keyOf d.aid = key ∧
        d.state = .terminationPending k ∧
        output ∈ o.outputs ∧ terminationShape .none i.hash i.code release output registry key = true ∧
        output.lovelace = terminationLovelace rp c.parameters := by
  obtain ⟨ref, index, booked⟩ :=
    termination_approval_requires_booking i env rp cp release o ok unique minted
  obtain ⟨c, input, output, hc, named, hout, _, pending, shape, lovelace, one⟩ :=
    termination_booking_inversion i env rp cp release o ok booked
  obtain ⟨credential, minimum, active, d, k, hd, sameKey, state⟩ := convictedPending_inversion pending
  exact ⟨one, c, input, output, d, k, hc, namedInput_mem named, credential, minimum, active, hd,
    sameKey, state, List.mem_of_getElem? hout, shape, lovelace⟩

/-- **No termination approval without a conviction of that key.**
Given a transaction the KERI application accepts that mints a positive
quantity of the termination approval of `key` under `registry`, that no other
preimage hashes to that approval's name, and that every checkpoint output at
the checkpoint validator's credential carries a state the checkpoint model
reaches from an absent checkpoint (the checkpoint validator realizes the
checkpoint model).
When the application's mint is read.
Then the transaction spends the pending output of an AID whose key is `key`,
and that AID's checkpoint was convicted: its trace has a conviction step of the
live checkpoint at the pending key state, with duplicity evidence at that key
state and a commitment entitling its payee at that step's slot. -/
theorem termination_approval_requires_conviction (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (cenv : CardanoKeri.Checkpoint.Env) (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {registry : TokenId} {key : Key}
    (unique : ∀ p, i.hash (i.code p) = i.hash (i.code (.terminationApproval registry key)) →
      p = .terminationApproval registry key)
    (realized : ∀ c input d, configurationOf i release registry o = some c → input ∈ o.inputs →
      input.credential = c.checkpointCredential → checkpointDatum i input = some d →
      CardanoKeri.Checkpoint.Reachable cp cenv d.state)
    (minted : 0 < SingularApplicationHeld.Assets.mintQty o.assets
      (terminationApproval i.hash i.code release registry key)) :
    ∃ input d k, input ∈ o.inputs ∧ checkpointDatum i input = some d ∧ i.keyOf d.aid = key ∧
      d.state = .terminationPending k ∧
      ∃ (t : CardanoKeri.Checkpoint.Slot) (es : List (CardanoKeri.Checkpoint.Slot × CardanoKeri.Checkpoint.Action))
        (t' : CardanoKeri.Checkpoint.Slot) (payee : CardanoKeri.Checkpoint.Addr)
        (c : CardanoKeri.Checkpoint.Commitment) (l : CardanoKeri.Checkpoint.Live),
        CardanoKeri.Checkpoint.Trace cp cenv t .absent es (.terminationPending k) ∧
        (t', CardanoKeri.Checkpoint.Action.convict payee c) ∈ es ∧
        cenv.acceptsRival l.epoch l.sn = true ∧ c.entitles cenv l payee t' ∧ l.hash = k := by
  obtain ⟨_, c, input, _, d, k, hc, mem, credential, _, _, hd, sameKey, state, _⟩ :=
    termination_approval_requires_pending i env rp cp release o ok unique minted
  have reach := realized c input d hc mem credential hd
  rw [state] at reach
  exact ⟨input, d, k, mem, hd, sameKey, state,
    CardanoKeri.Checkpoint.reachable_pending_convicted cp cenv reach⟩

/-- **The checkpoint validator releases a pending output only into a booking.**
Given a transaction the KERI application accepts, in which the checkpoint
validator releases a pending output of `registry` (`pendingReleased`), and that
no other preimage hashes to the name of the termination approval of the key of
that output's AID.
When the transaction is read.
Then a termination booking of the registry and of that key is among its
actions, spending a convicted pending output of the key and placing its
termination request. -/
theorem pending_released_only_into_booking (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {registry : TokenId} {input : ObservedOutput}
    {d : CardanoKeri.ConsumerIdentity.DecodedDatum} (hd : checkpointDatum i input = some d)
    (released : pendingReleased i release registry input o = true)
    (unique : ∀ p, i.hash (i.code p) = i.hash (i.code (.terminationApproval registry (i.keyOf d.aid))) →
      p = .terminationApproval registry (i.keyOf d.aid)) :
    ∃ ref index c pending output, Action.bookTermination ref index registry (i.keyOf d.aid) ∈ o.actions ∧
      configurationOf i release registry o = some c ∧ namedInput o ref = some pending ∧
      convictedPending i rp c registry (i.keyOf d.aid) pending = true ∧
      o.outputs[index]? = some output ∧
      terminationShape .none i.hash i.code release output registry (i.keyOf d.aid) = true := by
  unfold pendingReleased at released
  rw [hd] at released
  simp only [Bool.and_eq_true, beq_iff_eq] at released
  obtain ⟨ref, index, booked⟩ := termination_approval_requires_booking i env rp cp release o ok unique
    (by rw [released.2]; decide)
  obtain ⟨c, pending, output, hc, named, hout, _, convicted, shape, _, _⟩ :=
    termination_booking_inversion i env rp cp release o ok booked
  exact ⟨ref, index, c, pending, output, booked, hc, named, convicted, hout, shape⟩

/-! ## The money of a termination -/

/-- **The booking splits the minimum ADA as the economic booking does.**
Given the registry's economic parameters, whose tip is the configuration
record's minimum tip, and any external booking fee.
When a termination booking spends the pending output's minimum ADA `Mc` and
places a request of `terminationLovelace`.
Then the request holds what the economic booking puts into the request
(`Samaritan.reap`), and what the booker keeps, `Mc` less the request, is the
economic premium `Mc - Mr - tip`. -/
theorem termination_booking_matches_reap (rp : CardanoKeri.Registry.Params)
    (p : ApplicationParameters) (tip : rp.tip = p.minimumTip) (fee : Nat) :
    terminationLovelace rp p = (CardanoKeri.Samaritan.reap ⟨rp.Mc, rp.Mr, rp.tip, fee, rp.hFund⟩).intoRequest ∧
      rp.Mc - terminationLovelace rp p =
        (CardanoKeri.Samaritan.reap ⟨rp.Mc, rp.Mr, rp.tip, fee, rp.hFund⟩).premium := by
  refine ⟨?_, ?_⟩ <;> simp only [terminationLovelace, CardanoKeri.Samaritan.reap] <;> omega

/-- **The terminating fold donates what the economic fold donates.**
Given an economic termination booking whose request holds a booked request's
lovelace and declares the configuration record's minimum tip.
When the terminating fold's donation is computed.
Then it is the economic termination donation (`FoldMember.donation`), which is
the termination carrier `Mr`. -/
theorem termination_donation_matches_economic (rp : CardanoKeri.Registry.Params)
    (p : ApplicationParameters) (b : Singular.TerminationBooking)
    (contents : b.request.contents.lovelace = terminationLovelace rp p)
    (tip : b.request.declaredTip = p.minimumTip) :
    terminationLovelace rp p - p.minimumTip = (Singular.FoldMember.termination b).donation ∧
      terminationLovelace rp p - p.minimumTip = rp.Mr := by
  refine ⟨by simp [Singular.FoldMember.donation, contents, tip], ?_⟩
  unfold terminationLovelace
  omega

/-! ## The terminal key -/

/-- **The KERI terminating fold makes the key terminal.**
Given a transaction the KERI application accepts with a terminating fold of
`key` under the registry `world`, which is also an accepted step of the
public registry's history (`HistoryTransaction`) from a reachable world, with
the history's encoding and collision-freedom premises for the key's active role.
When the registry's leaf of the key is read after the fold.
Then the registry's fold has a termination change of the key and leaves the
key's leaf terminal. -/
theorem termination_fold_retires_key (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) (commit : TrieCommit)
    (before after : CandidateWorld) (fo : FoldObservation) (world : PublicRegistry) {ref : OutRef}
    {key : Key} (folded : Action.foldTermination ref world.identity key ∈ o.actions)
    (history : HistoryTransaction i.hash i.code commit release before after o.assets (some fo))
    (premises : HistoryPremises i.hash i.code commit release before world key)
    (encoding : FiniteEncoding i.code (after.domain ++ [.active world.identity key]))
    (collision : FiniteCollisionFree i.hash i.code (after.domain ++ [.active world.identity key])) :
    world.identity = fo.before.identity ∧ (∃ reference, Change.terminate reference key ∈ fo.changes) ∧
      trieGet fo.after.trie key = .known .terminal := by
  have aok := (by
    simp only [accepted, Bool.and_eq_true] at ok
    exact List.all_eq_true.mp ok.1.1.1.2 _ folded : action i env rp cp release o _ = true)
  simp only [action] at aok
  split at aok
  · simp only [spendTermination, Bool.and_eq_true, beq_iff_eq] at aok
    have burn : SingularApplicationHeld.Assets.mintQty o.assets
        (activeAsset i.hash i.code world.identity key) < 0 := by rw [aok.1.2]; decide
    obtain ⟨o', same, identity, change, terminal⟩ :=
      HistoryStatements.burn_only_terminating_fold i.hash i.code commit release before after o.assets
        (some fo) world key ⟨history, premises, encoding, collision, burn⟩
    cases same
    exact ⟨identity, change, terminal⟩
  · contradiction

/-- **A terminal key stays terminal.**
Given a reachable public registry history in which `key` is terminal in
`world`, and the next transaction of the history, whatever it is (a fold, the
genesis of another registry, or a transaction that does not touch the
registries), with the history's encoding and collision-freedom premises for
the key's active role.
When the registries after it are read.
Then every registry with `world`'s identity still has the key terminal, and
the transaction mints no active token of the key. -/
theorem terminal_key_permanent (h : Hash) (c : Codec) (t : TrieCommit)
    (release : PublishedRelease) (before after : CandidateWorld)
    (view : SingularApplicationHeld.Assets.TxView) (folded : Option FoldObservation)
    (world : PublicRegistry) (key : Key)
    (transaction : HistoryTransaction h c t release before after view folded)
    (premises : HistoryPremises h c t release before world key)
    (encoding : FiniteEncoding c (after.domain ++ [.active world.identity key]))
    (collision : FiniteCollisionFree h c (after.domain ++ [.active world.identity key]))
    (terminal : trieGet world.trie key = .known .terminal) :
    (∀ successor ∈ after.registries, successor.identity = world.identity →
      trieGet successor.trie key = .known .terminal) ∧
    SingularApplicationHeld.Assets.mintQty view (activeAsset h c world.identity key) ≤ 0 := by
  have reachable := premises.1
  have member := premises.2.1
  rcases transaction with ⟨_, transaction⟩
  cases folded with
  | some fo =>
    rcases transaction with ⟨rfl, foldPremises⟩
    obtain ⟨noMint, kept⟩ := HistoryStatements.no_remint_after_terminal h c t release before after fo
      world key ⟨foldPremises, premises, encoding, collision, terminal⟩
    exact ⟨kept, noMint⟩
  | none =>
    have own : world.identity.policy = release.statePolicy := by
      rw [(HistoryProofs.registry_identity h c t release before reachable world member).1]; rfl
    rcases transaction with created | neutral
    · obtain ⟨seed, inputs, outputs, registry, fee, donation, _, accepted, identity, _, _, _, _,
        fresh, registries, domainEq⟩ := created
      refine ⟨?_, ?_⟩
      · intro successor mem same
        rw [registries] at mem
        rcases List.mem_append.mp mem with old | new
        · rw [HistoryProofs.registry_unique h c t release before reachable successor old world member same]
          exact terminal
        · simp only [List.mem_singleton] at new
          subst new
          exact absurd (List.mem_map.mpr ⟨world, member, same.symm⟩) fresh
      · have zero := HistoryProofs.genesis_active_zero h c t release seed view outputs
          (after.domain ++ [.active world.identity key]) world.identity key
          (by simp [domainEq]) (by simp) encoding collision own accepted
        omega
    · obtain ⟨inputs, outputs, fee, donation, _, noMint, _, registries, _⟩ := neutral
      refine ⟨?_, ?_⟩
      · intro successor mem same
        rw [registries] at mem
        rw [HistoryProofs.registry_unique h c t release before reachable successor mem world member same]
        exact terminal
      · have zero := Proofs.delta_at view release.statePolicy [] noMint
          (activeAsset h c world.identity key) own
        simp only [List.filter_nil, List.map_nil, List.sum_nil] at zero
        omega

/-- **No booking of a terminal key.**
Given a reachable public registry history in which `key` is terminal in
`world`, with the history's encoding and collision-freedom premises for the
key's active role, and a transaction whose inputs are unspent outputs of that
history.
When the KERI application judges a termination booking of the key.
Then it is refused: no unspent output holds the key's active token, which the
booking's pending output must hold. -/
theorem termination_booking_refused_for_terminal_key (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) (commit : TrieCommit)
    (history : CandidateWorld) (world : PublicRegistry) (key : Key)
    (premises : HistoryPremises i.hash i.code commit release history world key)
    (terminal : trieGet world.trie key = .known .terminal)
    (present : ∀ input ∈ o.inputs, input ∈ history.unspent)
    {ref : OutRef} {index : Nat} (booked : Action.bookTermination ref index world.identity key ∈ o.actions) :
    accepted i env rp cp release o = false := by
  cases ok : accepted i env rp cp release o
  · rfl
  · obtain ⟨_, input, _, _, named, _, _, pending, _⟩ :=
      termination_booking_inversion i env rp cp release o ok booked
    have held := (convictedPending_inversion pending).2.2.1
    have supply := HistoryStatements.supply_in_step i.hash i.code commit release history world key premises
    unfold SupplyAt at supply
    rw [terminal] at supply
    simp at supply
    have counted : quantity input (activeAsset i.hash i.code world.identity key) ≤
        liveActiveCount i.hash i.code world.identity key history.unspent := by
      unfold liveActiveCount
      exact le_sum_of_mem' (List.mem_map.mpr ⟨input, present _ (namedInput_mem named), rfl⟩)
    omega

/-- **No re-registration of a terminal key.**
Given a reachable public registry history in which `key` is terminal in
`world`, an accepted registry fold that is the next step of that history, with
the history's encoding and collision-freedom premises for the key's active
role, and a transaction the KERI application judges with the same mint.
When the KERI application judges a fold of a registration request of the key
under that registry.
Then it is refused: the fold must mint the key's active token, and the
registry mints none for a terminal key (`no_remint_after_terminal`); the
registry's insertion requires an unknown key. -/
theorem registration_fold_refused_for_terminal_key (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation) (commit : TrieCommit)
    (before after : CandidateWorld) (fo : FoldObservation) (world : PublicRegistry) (key : Key)
    (step : HistoryFoldPremises i.hash i.code commit release before after fo)
    (premises : HistoryPremises i.hash i.code commit release before world key)
    (encoding : FiniteEncoding i.code (after.domain ++ [.active world.identity key]))
    (collision : FiniteCollisionFree i.hash i.code (after.domain ++ [.active world.identity key]))
    (terminal : trieGet world.trie key = .known .terminal)
    (sameMint : fo.assets = o.assets)
    {ref : OutRef} {index : Nat} {input : ObservedOutput} {data : RegistrationData}
    (folded : Action.foldRegistration ref index ∈ o.actions)
    (named : namedInput o ref = some input)
    (hd : decoded i.decode input = some (.registration data))
    (registry : data.registry = world.identity) (sameKey : data.key = key) :
    accepted i env rp cp release o = false := by
  cases ok : accepted i env rp cp release o
  · rfl
  · have aok := (by
      simp only [accepted, Bool.and_eq_true] at ok
      exact List.all_eq_true.mp ok.1.1.1.2 _ folded : action i env rp cp release o _ = true)
    simp only [action, named, hd, spendRegistration] at aok
    have noMint := (HistoryStatements.no_remint_after_terminal i.hash i.code commit release before
      after fo world key ⟨step, premises, encoding, collision, terminal⟩).1
    rw [sameMint] at noMint
    split at aok
    · contradiction
    · simp only [Bool.and_eq_true] at aok
      have holding := aok.2.2
      split at holding
      · simp only [delivered, Bool.and_eq_true, beq_iff_eq] at holding
        have one := holding.2
        rw [registry, sameKey] at one
        omega
      · contradiction

/-! ## The inception evidence -/

/-- **An accepted transaction books only keys with inception evidence.**
Given a transaction the KERI application accepts, one of whose actions books
the registration held by an output.
When that output's registration data is read.
Then its key has its inception evidence. -/
theorem accepted_booking_has_inception (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {index : Nat} {output : ObservedOutput}
    {data : RegistrationData} (booked : Action.bookRegistration index ∈ o.actions)
    (ho : o.outputs[index]? = some output)
    (hd : decoded i.decode output = some (.registration data)) :
    env.inception data.key = true := by
  simp only [accepted, Bool.and_eq_true] at ok
  have aok := List.all_eq_true.mp ok.1.1.1.2 _ booked
  simp only [action, ho] at aok
  obtain ⟨d, _, hd', _, _, _, _, _, _, _, _, _, evidence, _⟩ :=
    booking_inversion i env rp cp release o aok
  rw [hd] at hd'
  cases hd'
  exact evidence

/-- **No registration approval without inception evidence.**
Given a transaction the KERI application accepts that mints a positive
quantity of the registration approval of a payload (registry, key, holding
address, initial-datum hash, deposit), and that no other preimage hashes to
that approval's name.
When the application's mint is read.
Then one of its actions books an output whose registration data has exactly
that payload, and the key has its inception evidence: an approval exists only
for a key whose inception was shown when it was booked. -/
theorem registration_approval_requires_inception (i : Interpretation) (env : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (ok : accepted i env rp cp release o = true) {data : RegistrationData}
    (unique : ∀ p, i.hash (i.code p) = i.hash (i.code (.registrationApproval data.registry
        data.key data.holdingAddress data.initialDatum data.deposit)) →
      p = .registrationApproval data.registry data.key data.holdingAddress data.initialDatum
        data.deposit)
    (minted : 0 < SingularApplicationHeld.Assets.mintQty o.assets
      (registrationAsset i.hash i.code release data)) :
    ∃ index output booked, Action.bookRegistration index ∈ o.actions ∧
      o.outputs[index]? = some output ∧
      decoded i.decode output = some (.registration booked) ∧
      booked.registry = data.registry ∧ booked.key = data.key ∧
      booked.holdingAddress = data.holdingAddress ∧ booked.initialDatum = data.initialDatum ∧
      booked.deposit = data.deposit ∧ env.inception data.key = true := by
  have justified := accepted_mint_is_justified i env rp cp release o ok
    (asset := registrationAsset i.hash i.code release data) rfl
  rw [justified] at minted
  unfold justifiedQty justifiedMint at minted
  obtain ⟨x, hx, positive⟩ := exists_pos_of_sum_pos minted
  simp only [List.mem_map, List.mem_filter, List.mem_flatMap] at hx
  obtain ⟨entry, ⟨⟨a, amem, emem⟩, same⟩, rfl⟩ := hx
  have same := SingularApplicationHeld.Proofs.token_eq _ _ same
  cases a with
  | createConfiguration r seed index =>
    simp only [Action.justifies, List.mem_singleton] at emem
    subst emem
    simp only [configurationAsset, registrationAsset, registrationApproval,
      TokenId.mk.injEq] at same
    exact absurd (unique _ same.2) (by simp)
  | bookRegistration index =>
    simp only [Action.justifies] at emem
    split at emem
    · rename_i output ho
      split at emem
      · rename_i booked hd
        simp only [List.mem_singleton] at emem
        subst emem
        simp only [registrationAsset, registrationApproval, TokenId.mk.injEq] at same
        have pre := unique _ same.2
        simp only [Preimage.registrationApproval.injEq] at pre
        obtain ⟨registry, key, address, datum, deposit⟩ := pre
        have evidence := accepted_booking_has_inception i env rp cp release o ok amem ho hd
        exact ⟨index, output, booked, amem, ho, hd, registry, key, address, datum, deposit,
          key ▸ evidence⟩
      · simp at emem
    · simp at emem
  | bookTermination ref index r k =>
    simp only [Action.justifies, List.mem_singleton] at emem
    subst emem
    simp only [terminationApproval, registrationAsset, registrationApproval,
      TokenId.mk.injEq] at same
    exact absurd (unique _ same.2) (by simp)
  | foldTermination =>
    simp only [Action.justifies, List.mem_singleton] at emem
    subst emem; simp at positive
  | foldRegistration ref _ | returnRegistration ref =>
    simp only [Action.justifies] at emem
    split at emem
    · split at emem
      · simp only [List.mem_singleton] at emem
        subst emem; simp at positive
      · simp at emem
    · simp at emem

/-- **Only a booking reads the inception evidence.**
Given two environments, and a transaction none of whose actions books a
registration: folds, returns, terminating folds, termination bookings,
configuration creations.
When the KERI application judges it under each environment.
Then the two verdicts are the same: a fold or a return of a booked request is
accepted or refused whatever inception evidence exists. -/
theorem only_booking_reads_inception (i : Interpretation) (env env' : Env)
    (rp : CardanoKeri.Registry.Params) (cp : CardanoKeri.Checkpoint.Params)
    (release : PublishedRelease) (o : Observation)
    (noBooking : ∀ index, Action.bookRegistration index ∉ o.actions) :
    accepted i env rp cp release o = accepted i env' rp cp release o := by
  have each : ∀ a ∈ o.actions,
      action i env rp cp release o a = action i env' rp cp release o a := by
    intro a amem
    cases a with
    | bookRegistration index => exact absurd amem (noBooking index)
    | _ => rfl
  have same : o.actions.all (action i env rp cp release o) =
      o.actions.all (action i env' rp cp release o) := by
    rw [Bool.eq_iff_iff]
    simp only [List.all_eq_true]
    constructor <;> intro h a amem
    · rw [← each a amem]; exact h a amem
    · rw [each a amem]; exact h a amem
  simp only [accepted, same]

/-! ## What a folder needs -/

/-- An accepted booking's request has the registration shape. -/
theorem booking_shape {i : Interpretation} {env : Env} {rp : CardanoKeri.Registry.Params}
    {cp : CardanoKeri.Checkpoint.Params} {release : PublishedRelease} {o : Observation}
    {output : ObservedOutput} {data : RegistrationData}
    (ok : bookRegistration i env rp cp release o output = true)
    (hd : decoded i.decode output = some (.registration data)) :
    registrationShape .none i.hash i.code release output data = true := by
  unfold bookRegistration at ok
  rw [hd] at ok
  simp only at ok
  split at ok
  · simp only [Bool.and_eq_true] at ok
    exact ok.1.1.1.1.1.1.1.1.1
  · contradiction

/-- **A spend that does not read the registry's configuration record is refused.**
Given a transaction that does not read by reference the configuration record
of the registry a request names.
When the request is spent, by a fold or by a return.
Then the spend is refused. This is one of the two things a KERI fold asks of a
folder beyond the request itself; the other is the treasury donation
(`treasury_covers_registration_costs`). -/
theorem fold_refuses_unread_record (i : Interpretation) (release : PublishedRelease)
    (o : Observation) (a : Action) (input : ObservedOutput) {data : RegistrationData}
    (unread : configurationOf i release data.registry o = none) :
    spendRegistration i release o a input data = false := by
  simp [spendRegistration, unread]

/-! ## The fold the Singular client builds -/

/-- Tokens of different policies are different tokens. -/
theorem token_beq_of_policy_ne {a b : TokenId} (h : a.policy ≠ b.policy) : (a == b) = false := by
  cases hab : (a == b)
  · rfl
  · exact absurd (congrArg TokenId.policy (SingularApplicationHeld.Proofs.token_eq _ _ hab)) h

/-- A validity interval in the upstream processing phase is inside KERI's fold window. -/
theorem processing_is_fold_window {data : RegistrationData} {interval : Interval}
    (h : classifyPhase data interval = .processing) : foldWindow data interval = true := by
  unfold classifyPhase at h
  simp only [foldWindow, Bool.and_eq_true, decide_eq_true_eq]
  split at h
  · contradiction
  · rename_i nonempty
    split at h
    · rename_i upper
      exact ⟨by simpa using nonempty, upper⟩
    · split at h
      · contradiction
      · split at h <;> contradiction

/-- A transaction that folds one registration request, delivering its committed
holding at output 1 and reading the registry's configuration record, is
accepted by KERI's application. The shape is the one the upstream client
builds for one request (`public_fold_accepted`). -/
theorem single_fold_accepted {i : Interpretation} {env : Env} {rp : CardanoKeri.Registry.Params}
    {cp : CardanoKeri.Checkpoint.Params} {release : PublishedRelease} {o : Observation}
    {state request ordinary record holding : ObservedOutput} {data : RegistrationData}
    {c : Configuration}
    (inputs : o.inputs = [state, request, ordinary])
    (spent : o.assets.spent = [state.reference, request.reference, ordinary.reference])
    (mint : o.assets.mint = [(activeAsset i.hash i.code data.registry data.key, 1),
      (registrationAsset i.hash i.code release data, -1)])
    (actions : o.actions = [.foldRegistration request.reference 1])
    (placed : o.outputs[1]? = some holding)
    (atAddress : holding.credential = data.holdingAddress)
    (datum : holding.datum = .application data.initialDatum)
    (lovelace : holding.lovelace = data.deposit)
    (token : holding.assets = [(activeAsset i.hash i.code data.registry data.key, 1)])
    (referenced : o.referenceInputs = [record.reference]) (records : o.referenceOutputs = [record])
    (distinct : [state.reference, request.reference, ordinary.reference].Nodup)
    (stateElsewhere : state.credential ≠ release.applicationCredential)
    (ordinaryElsewhere : ordinary.credential ≠ release.applicationCredential)
    (policies : release.applicationPolicy ≠ data.registry.policy)
    (hd : decoded i.decode request = some (.registration data))
    (shape : registrationShape .none i.hash i.code release request data = true)
    (window : foldWindow data o.interval = true)
    (recordShape : configurationShape i release data.registry record = true)
    (recordDatum : configurationDatum i record = some c)
    (valid : parametersValid c.parameters = true)
    (donated : c.parameters.registrationCost ≤ o.donation) :
    accepted i env rp cp release o = true ∧ delivered i data holding o = true := by
  have refs : state.reference ≠ request.reference ∧ ordinary.reference ≠ request.reference := by
    simp only [List.nodup_cons, List.mem_cons, not_or, List.not_mem_nil,
      not_false_eq_true, List.nodup_nil, and_true] at distinct
    exact ⟨distinct.1.1, fun h => distinct.2 h.symm⟩
  have named : namedInput o request.reference = some request := by
    simp [namedInput, spent, inputs, refs.1, refs.2]
  have differ : (activeAsset i.hash i.code data.registry data.key ==
      registrationAsset i.hash i.code release data) = false :=
    token_beq_of_policy_ne (fun h => policies h.symm)
  have differ' : (registrationAsset i.hash i.code release data ==
      activeAsset i.hash i.code data.registry data.key) = false :=
    token_beq_of_policy_ne policies
  have hc : configurationOf i release data.registry o = some c := by
    simp [configurationOf, records, referenced, recordShape, recordDatum]
  have burned : approvalBurned i release data o = true := by
    simp [approvalBurned, SingularApplicationHeld.Assets.mintQty, mint, differ]
  have minted : SingularApplicationHeld.Assets.mintQty o.assets
      (activeAsset i.hash i.code data.registry data.key) = 1 := by
    simp [SingularApplicationHeld.Assets.mintQty, mint, differ']
  have hdel : delivered i data holding o = true := by
    simp [delivered, atAddress, datum, lovelace, quantity, token, minted]
  have spend : spendRegistration i release o (.foldRegistration request.reference 1) request data =
      true := by
    simp [spendRegistration, hc, valid, shape, burned, window, placed, hdel]
  refine ⟨?_, hdel⟩
  simp only [accepted, Bool.and_eq_true]
  refine ⟨⟨⟨⟨?_, ?_⟩, ?_⟩, ?_⟩, ?_⟩
  · simp [inputsCovered, inputs, actions, Action.input?, stateElsewhere, ordinaryElsewhere]
  · simp [actions, action, named, hd, spend]
  · simp [moneyRouted, requiredRefunds, requiredTreasury, Action.treasuryDue, actions,
      spentRequest_of named hd hc, donated]
  · have activePolicy : ((activeAsset i.hash i.code data.registry data.key).policy ==
        release.applicationPolicy) = false := by
      simp only [activeAsset, beq_eq_false_iff_ne, ne_eq]
      exact fun h => policies h.symm
    have approvalPolicy : ((registrationAsset i.hash i.code release data).policy ==
        release.applicationPolicy) = true := by
      simp [registrationAsset, registrationApproval]
    simp [mintClosed, justifiedQty, justifiedMint, actions, Action.justifies, named, hd, mint,
      List.filter, activePolicy, approvalPolicy, SingularApplicationHeld.Assets.mintQty, differ]
  · simp [bookedOnce, bookedOutputs, actions, Action.booking?]
/-- **KERI's application accepts the fold the Singular client builds.**
Given a request booked by an accepted booking; the public registry and an
ordinary funding input under the upstream client's own premises for a fold of
that one request (`PublicFoldPremises`: the registry's state is genuine, the
key is not yet registered, the references are distinct, the validity interval
is in the request's processing phase); the application and the state policy
distinct and the registry's state not at the application address; and what
KERI's adapter adds: the registry's configuration record with valid
parameters, read by reference, and a treasury donation of at least its
registration cost.
When the upstream client builds the fold from the registry and the request
(`SingularApplicationHeld.buildFold`) and the adapter adds those to it
(`adapted`).
Then KERI's application accepts the transaction, and the holding the client
placed at output 1 is the approved one: at the committed address, carrying the
request's initial datum, holding exactly the deposit and the one new active
token, and it writes the initial checkpoint state of the request's key. The
folder supplies no inception evidence, no datum and no file: every field of
the holding is the request's data. -/
theorem public_fold_accepted (i : Interpretation) (env : Env) (rp : CardanoKeri.Registry.Params)
    (cp : CardanoKeri.Checkpoint.Params) (release : PublishedRelease) (commit : TrieCommit)
    {booking : Observation} {request record : ObservedOutput} {data : RegistrationData}
    {c : Configuration} (registry : PublicRegistry) (funding : FoldFunding) (donation : Nat)
    (booked : bookRegistration i env rp cp release booking request = true)
    (hb : decoded i.decode request = some (.registration data))
    (premises : PublicFoldPremises i.hash i.code commit i.decode release registry
      [.registration request data] funding)
    (policies : release.applicationPolicy ≠ release.statePolicy)
    (stateElsewhere : registry.state.credential ≠ release.applicationCredential)
    (recordShape : configurationShape i release data.registry record = true)
    (recordDatum : configurationDatum i record = some c)
    (valid : parametersValid c.parameters = true)
    (donated : c.parameters.registrationCost ≤ donation) :
    accepted i env rp cp release (adapted
      (buildFold i.hash i.code commit release registry [.registration request data] funding)
      record donation) = true ∧
    ∃ holding, (adapted
        (buildFold i.hash i.code commit release registry [.registration request data] funding)
        record donation).outputs[1]? = some holding ∧
      holding.credential = data.holdingAddress ∧
      holding.datum = .application data.initialDatum ∧
      holding.lovelace = data.deposit ∧
      quantity holding (activeAsset i.hash i.code data.registry data.key) = 1 ∧
      writesInitialState i rp cp data holding = true := by
  obtain ⟨_, _, _, _, identity, _, _, _, ordinaryElsewhere, _, distinct, _, each⟩ := premises
  obtain ⟨sameRegistry, _, _, phase⟩ := each _ (List.mem_singleton.mpr rfl)
  have sameRegistry : data.registry = registry.identity := sameRegistry
  obtain ⟨d, _, hd', _, statePolicy, _⟩ := booking_inversion i env rp cp release booking booked
  rw [hb] at hd'
  cases hd'
  have accepted_and_delivered := single_fold_accepted (i := i) (env := env) (rp := rp) (cp := cp)
    (release := release) (c := c) (record := record) (data := data)
    (o := adapted (buildFold i.hash i.code commit release registry [.registration request data]
      funding) record donation)
    (state := registry.state) (request := request) (ordinary := funding.ordinaryInput)
    (holding := ⟨⟨funding.transactionId, 1⟩, data.holdingAddress, data.deposit,
      .application data.initialDatum, [(activeAsset i.hash i.code data.registry data.key, 1)]⟩)
    rfl rfl (by rw [sameRegistry]; rfl) rfl rfl rfl rfl rfl rfl rfl rfl
    (by simpa using distinct) stateElsewhere ordinaryElsewhere
    (by rw [statePolicy]; exact policies) hb (booking_shape booked hb)
    (processing_is_fold_window phase) recordShape recordDatum valid donated
  refine ⟨accepted_and_delivered.1, _, rfl, rfl, rfl, rfl, ?_,
    delivered_writes_initial_state booked hb accepted_and_delivered.2⟩
  simp [quantity]

