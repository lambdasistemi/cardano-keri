import CardanoKeri.ApplicationGoals
import CardanoKeri.CheckpointSystemHistory

namespace CardanoKeri.Application
open SingularApplicationHeld
open Singular (TokenId)
namespace Custody
open Checkpoint

/-- The transaction submitted to the ledger has an identity and an ordered
output list. The ledger assigns the reference of each created output. The
candidate-world relation also checks input availability, freshness, consumption
and the complete resulting UTxO set. -/
structure Transaction (before after : CandidateWorld) where
  identity : Nat
  observation : Observation
  fee : Nat
  ledger : LedgerObservationCorrespondence before after observation.assets
    observation.inputs observation.outputs fee observation.donation

def Transaction.creates {before after : CandidateWorld} (t : Transaction before after)
    (out : ObservedOutput) : Prop :=
  t.observation.outputs[out.reference.index]? = some out ∧ out.reference.tx = t.identity

/-- The observer reads the output of the selected identifier with its unique
active asset and the facts written into its checkpoint datum. Its address is
checked by the spend and the mint. The premium pool is held in the value. -/
def Carries (i : Interpretation) (token : TokenId) (aid : AID) (out : ObservedOutput)
    (state : State) : Prop :=
  quantity out token = 1 ∧ checkpointDatum i out = some ⟨aid, state.datumFacts⟩

/-- An observation of the life of one active token. Its registration starts at
the exact public fold output. A checkpoint spend names the previous output
and installs its indexed successor. An intervening system step keeps that
output only if the corresponding ledger transaction leaves it unspent.
The edge list retains the particular system transition that produced each
output for this token. -/
inductive CarrierHistory (p : Checkpoint.Params) (env : SystemEnv) (i : Interpretation)
    (token : TokenId) (aid : AID) :
    List (Sys × Sys × ObservedOutput) → Sys → CandidateWorld → ObservedOutput → Prop where
  | register {before after w w' origin live} {out : ObservedOutput} (past : SysReach p env before)
      (event : RegistrationEvent p env before after)
      (fresh : before.origins aid = none) (installed : after.origins aid = some origin)
      (state : after.states aid = .present live) (tx : Transaction w w')
      (ref : out.reference = origin.carrierRef) (created : tx.creates out)
      (datum : Carries i token aid out (.present live)) :
      CarrierHistory p env i token aid [(before, after, out)] after w' out
  | spend {edges before after w w' old out action now flow state}
      (past : CarrierHistory p env i token aid edges before w old)
      (tx : Transaction w w') (input : namedInput tx.observation old.reference = some old)
      (created : tx.creates out ∧ ∀ key, state = .terminationPending key →
        ((env aid).convictionSpend key.epoch key.sn).map Registry.Conviction.output = some out.reference)
      (datum : Carries i token aid out state)
      (ordinary : ∀ refund pool, action ≠ .register refund pool)
      (executed : Step p (env aid) action now (before.states aid) flow state)
      (openMarker : before.revealOpen aid action)
      (writer : (before.localWriter (env aid) aid action).isSome = true)
      (updated : after = (before.set aid state (before.localWriter (env aid) aid action).join (state.producingSpend (env aid))).retireRevealed action) :
      CarrierHistory p env i token aid ((before, after, out) :: edges) after w' out
  | retain {edges before after w w' out} (past : CarrierHistory p env i token aid edges before w out)
      (tx : Transaction w w') (unspent : out.reference ∉ tx.observation.assets.spent)
      (event : SysStep p env before after) (frame : after.states aid = before.states aid) :
      CarrierHistory p env i token aid edges after w' out

/-- Given an observed carrier history, when its current system is read, then
it is reachable by actual system transitions from the deployment. -/
theorem carrier_reachable {p env i token aid edges s w out}
    (path : CarrierHistory p env i token aid edges s w out) : SysReach p env s := by
  induction path with
  | register past event => exact .step past (.register event)
  | spend _ _ _ _ _ ordinary executed opened writer updated ih =>
    subst updated
    exact .step ih (.local ⟨_, _, _, _, _, ordinary, executed, ⟨opened, writer⟩, rfl⟩)
  | retain _ _ _ event _ ih => exact .step ih event

/-- Given an observed carrier path, when a producer is selected from its
edge list, then the producer's source system is reachable. -/
theorem carrier_edge_source_reachable {p env i token aid edges s w out before after produced}
    (path : CarrierHistory p env i token aid edges s w out)
    (member : (before, after, produced) ∈ edges) : SysReach p env before := by
  induction path with
  | register reachable _ _ _ _ _ _ _ _ =>
    simp only [List.mem_singleton] at member
    cases member
    exact reachable
  | spend past _ _ _ _ _ _ _ _ _ ih =>
    rcases List.mem_cons.mp member with eq | earlier
    · cases eq
      exact carrier_reachable past
    · exact ih earlier
  | retain _ _ _ _ _ ih => exact ih member

/-- Given a carrier history, when the current holding is read from its ledger
world, then that very output remains unspent and carries one active token. -/
theorem carrier_unspent {p env i token aid edges s w out}
    (path : CarrierHistory p env i token aid edges s w out) :
    out ∈ w.unspent ∧ quantity out token = 1 := by
  induction path with
  | register _ _ _ _ _ tx _ created datum =>
    exact ⟨tx.ledger.nextUnspent ▸ List.mem_append_right _ (List.mem_of_getElem? created.1), datum.1⟩
  | spend _ tx _ created datum _ _ _ _ _ _ =>
    exact ⟨tx.ledger.nextUnspent ▸ List.mem_append_right _ (List.mem_of_getElem? created.1.1), datum.1⟩
  | retain _ tx survives _ _ ih =>
    rw [tx.ledger.nextUnspent]
    exact ⟨List.mem_append_left _ (List.mem_filter.mpr ⟨ih.1, by simpa using survives⟩), ih.2⟩

/-- Given a carrier history, when its current output decodes as pending, then
this exact output was created by a conviction edge of this identifier at
the decoded key state. -/
theorem pending_output_observation {p env i token aid edges s w out key}
    (path : CarrierHistory p env i token aid edges s w out)
    (pending : checkpointDatum i out = some ⟨aid, .terminationPending key⟩) :
    ∃ before after, (before, after, out) ∈ edges ∧ ConvictionEdge p env aid key before after ∧
      ((env aid).convictionSpend key.epoch key.sn).map Registry.Conviction.output = some out.reference := by
  induction path with
  | register _ _ _ _ _ _ _ _ datum =>
    rw [datum.2] at pending
    simp [State.datumFacts] at pending
  | @spend edges before after w w' old out action now flow state _ _ _ created datum _ executed opened writer updated _ =>
    subst after
    rw [datum.2] at pending
    have target : state = .terminationPending key := by cases state <;> simp_all [State.datumFacts]
    subst state
    obtain ⟨live, payee, c, wasLive, rfl, _, _, atKey⟩ := pending_only_by_conviction _ _ executed
    rw [wasLive] at executed
    exact ⟨_, _, List.mem_cons_self, ⟨live, now, payee, c, flow, wasLive, atKey, executed,
      ⟨opened, by simpa [Sys.localWriter] using writer⟩, by simp [State.producingSpend]⟩, created.2 _ rfl⟩
  | retain _ _ _ _ _ ih => exact ih pending

/-- Given the decoded pending output of a carrier history, its exact producer is a conviction. -/
theorem pending_output_producer {p env i token aid edges s w out key}
    (path : CarrierHistory p env i token aid edges s w out)
    (pending : checkpointDatum i out = some ⟨aid, .terminationPending key⟩) :
    ∃ before after, (before, after, out) ∈ edges ∧ ConvictionEdge p env aid key before after := by
  obtain ⟨before, after, member, edge, _⟩ := pending_output_observation path pending
  exact ⟨before, after, member, edge⟩

private theorem carrier_datum {p env i token aid edges s w out}
    (path : CarrierHistory p env i token aid edges s w out) :
    checkpointDatum i out = some ⟨aid, (s.states aid).datumFacts⟩ := by
  induction path with
  | register _ _ _ _ state _ _ _ datum => rw [state]; exact datum.2
  | spend _ _ _ _ datum _ _ _ _ updated _ =>
    rw [updated, Sys.retireRevealed_states]
    simpa [Sys.set] using datum.2
  | retain _ _ _ _ frame ih => rwa [frame]

/-- Given a pending carrier and its new booking association, when the record
is read, the economic conviction used the exact observation of the checkpoint
edge that created this output. The receipt names the same outpoint and position. -/
theorem booked_carrier_shares_observation {p env i token aid edges s next w out association}
    (path : CarrierHistory p env i token aid edges s w out)
    (book : BookingEvent s next) (empty : s.pending aid = none)
    (installed : next.pending aid = some association) :
    ∃ observed before after, (before, after, out) ∈ edges ∧
      ConvictionEdge p env aid association.keyState before after ∧
      (env aid).convictionSpend association.keyState.epoch association.keyState.sn = some observed ∧
      association.origin.environment.conviction aid = some observed ∧ observed.output = out.reference ∧
      association.entry.payload.spend = ⟨out.reference, aid, association.keyState⟩ ∧
      Registry.ConvictionOrigin association.origin.parameters association.origin.environment
        association.origin.configuration aid association.entry.payload.token
        (some association.entry.payload.spend) association.entry.payload.original := by
  obtain ⟨_, _, history⟩ := reachable_has_system_history (carrier_reachable path)
  obtain ⟨pending, observed, _, _, _, _, read, economic, receipt, authorized⟩ :=
    booking_uses_producing_spend history book empty installed
  have datum := carrier_datum path
  rw [pending] at datum
  obtain ⟨before, after, member, edge, reference⟩ := pending_output_observation path datum
  simp [read] at reference
  exact ⟨observed, before, after, member, edge, read, economic, reference, by rwa [reference] at receipt, authorized⟩

private theorem carrier_identifier {p env i token aid edges s w out}
    (path : CarrierHistory p env i token aid edges s w out) :
    ∃ st, checkpointDatum i out = some ⟨aid, st⟩ := by
  induction path with
  | register _ _ _ _ _ _ _ _ datum => exact ⟨_, datum.2⟩
  | spend _ _ _ _ datum _ _ _ _ _ _ => exact ⟨_, datum.2⟩
  | retain _ _ _ _ _ ih => exact ih

private theorem sole_holder {outputs : List ObservedOutput} {token : TokenId} {x y : ObservedOutput}
    (one : (outputs.map (fun o => quantity o token)).sum ≤ 1)
    (mx : x ∈ outputs) (my : y ∈ outputs) (qx : quantity x token = 1)
    (qy : quantity y token = 1) : x = y := by
  induction outputs with
  | nil => cases mx
  | cons a rest ih =>
    simp only [List.mem_cons] at mx my
    simp only [List.map_cons, List.sum_cons] at one
    rcases mx with rfl | mx <;> rcases my with rfl | my
    · rfl
    · have bound := le_sum_of_mem' (List.mem_map_of_mem (f := fun o => quantity o token) my)
      exfalso
      dsimp only at bound
      rw [qx] at one
      rw [qy] at bound
      omega
    · have bound := le_sum_of_mem' (List.mem_map_of_mem (f := fun o => quantity o token) mx)
      exfalso
      dsimp only at bound
      rw [qy] at one
      rw [qx] at bound
      omega
    · exact ih (by omega) mx my

/-- Given a reachable registry and an observed carrier history, when an admitted
booking names an input and request index, then the mint reads the precise
reference, AID and native position of the output produced by the conviction
in that history. The result applies to the particular booking action selected. -/
theorem booking_spends_conviction_output
    {p env} {i : Interpretation} {aid edges s world next carrier}
    (registry : PublicRegistry) (release : PublishedRelease) (commit : TrieCommit)
    (history : HistoryPremises i.hash i.code commit release world registry (i.keyOf aid))
    (path : CarrierHistory p env i (activeAsset i.hash i.code registry.identity (i.keyOf aid))
      aid edges s world carrier)
    (tx : Transaction world next) (aenv : Application.Env) (rp : Registry.Params)
    (ok : accepted i aenv rp p release tx.observation = true)
    {ref : Singular.OutRef} {index : Nat}
    (booked : Application.Action.bookTermination ref index registry.identity (i.keyOf aid) ∈
      tx.observation.actions) :
    ∃ cfg key before after, ref = carrier.reference ∧
      configurationOf i release registry.identity tx.observation = some cfg ∧
      namedInput tx.observation ref = some carrier ∧
      readPendingSpend i rp cfg registry.identity (i.keyOf aid) carrier =
        some ⟨ref, aid, key⟩ ∧
      checkpointDatum i carrier = some ⟨aid, .terminationPending key⟩ ∧
      (before, after, carrier) ∈ edges ∧ ConvictionEdge p env aid key before after := by
  obtain ⟨cfg, input, request, configured, named, _, _, pending, _⟩ :=
    termination_booking_inversion i aenv rp p release _ ok booked
  obtain ⟨_, _, holds, d, key, decoded, _, state⟩ := convictedPending_inversion pending
  obtain ⟨unspent, token⟩ := carrier_unspent path
  have same := sole_holder (HistoryStatements.one_live_token _ _ _ _ _ _ _ history)
    (tx.ledger.inputsPresent _ (namedInput_mem named)) unspent holds token
  subst input
  have reference : carrier.reference = ref := by
    unfold namedInput at named
    split at named
    · simpa using List.find?_some named
    · contradiction
  subst ref
  obtain ⟨st, observed⟩ := carrier_identifier path
  rw [observed] at decoded
  cases decoded
  have pendingDatum : checkpointDatum i carrier = some ⟨aid, .terminationPending key⟩ := by
    change st = .terminationPending key at state
    rwa [← state]
  obtain ⟨before, after, member, edge⟩ := pending_output_producer path pendingDatum
  have read := pending
  unfold convictedPending readPendingSpend at read
  rw [pendingDatum] at read
  refine ⟨cfg, key, before, after, rfl, configured, named, ?_, pendingDatum, member, edge⟩
  unfold readPendingSpend
  rw [pendingDatum]
  split at read <;> simp_all

/-- Given a reachable public registry and an observed checkpoint history of
its active token, when a ledger transaction accepted by the application mints
the key's termination approval, then its booking spends the exact output
created in that history by the conviction of this identifier and key state.
The ledger supplies the UTxO transition and the public encoding premises give
the active-token supply bound. The mint checks the named pending input. -/
theorem approval_spends_conviction_output
    {p env} {i : Interpretation} {aid edges s world next carrier}
    (registry : PublicRegistry) (release : PublishedRelease) (commit : TrieCommit)
    (history : HistoryPremises i.hash i.code commit release world registry (i.keyOf aid))
    (path : CarrierHistory p env i (activeAsset i.hash i.code registry.identity (i.keyOf aid))
      aid edges s world carrier)
    (tx : Transaction world next) (aenv : Application.Env) (rp : Registry.Params)
    (ok : accepted i aenv rp p release tx.observation = true)
    (unique : ∀ preimage, i.hash (i.code preimage) =
      i.hash (i.code (.terminationApproval registry.identity (i.keyOf aid))) →
      preimage = .terminationApproval registry.identity (i.keyOf aid))
    (minted : 0 < SingularApplicationHeld.Assets.mintQty tx.observation.assets
      (terminationApproval i.hash i.code release registry.identity (i.keyOf aid))) :
    ∃ index key before after,
      Application.Action.bookTermination carrier.reference index registry.identity (i.keyOf aid) ∈ tx.observation.actions ∧
      namedInput tx.observation carrier.reference = some carrier ∧
      checkpointDatum i carrier = some ⟨aid, .terminationPending key⟩ ∧
      (before, after, carrier) ∈ edges ∧ ConvictionEdge p env aid key before after := by
  obtain ⟨ref, index, booked⟩ := termination_approval_requires_booking i aenv rp p release _ ok unique minted
  obtain ⟨_, key, before, after, rfl, _, named, _, datum, member, edge⟩ :=
    booking_spends_conviction_output registry release commit history path tx aenv rp ok booked
  exact ⟨index, key, before, after, booked, named, datum, member, edge⟩

/-- The application's projection of one economic booking. The registry names
the created request by its transaction and output index. The booker's action
names the spent input. Both are read in this transaction, along with the
lovelace and checkpoint credential recorded by the economic booking. The public
fold still consumes its usual request. -/
def Transaction.bookingSpend {world next : CandidateWorld} (tx : Transaction world next)
    (i : Interpretation) (release : PublishedRelease) (rp : Registry.Params)
    (registry : Singular.TokenId) (b : Singular.TerminationBooking) (ref : Singular.OutRef) :
    Option PendingSpend := do
  let request := b.request
  let output ← tx.observation.outputs[request.reference.index]?
  let input ← namedInput tx.observation ref
  let cfg ← configurationOf i release registry tx.observation
  let key := i.keyOf request.key
  if request.reference.tx = tx.identity ∧ output.reference = request.reference ∧
      Application.Action.bookTermination ref request.reference.index registry key ∈ tx.observation.actions ∧
      output.lovelace = request.contents.lovelace ∧ input.credential = request.destination then
    readPendingSpend i rp cfg registry key input
  else none

/-- Project a booking observed at the application mint into the economic
transition. The request and its named pending input belong to this one
transaction. The public folder only needs the embedded Singular booking. -/
def Transaction.economicBooking {world next : CandidateWorld} (tx : Transaction world next)
    (i : Interpretation) (release : PublishedRelease) (rp : Registry.Params)
    (registry : Singular.TokenId) (b : Singular.TerminationBooking) (ref : Singular.OutRef) :
    Option Registry.TerminationBooking := do
  let spent ← tx.bookingSpend i release rp registry b ref
  if spent.aid = b.request.key then
    some { toTerminationBooking := b, pendingReference := spent.reference, position := spent.position }
  else none

/-- Given an accepted mint, a public registry history and its observed carrier,
when the economic booking's indexed request and the mint's named input produce
a receipt, then the receipt names this exact input, identifier and native key
state. The conviction produced it, and the mint transaction created the
request at the economic booking's reference. -/
theorem booking_receipt_provenance {p env} {i : Interpretation} {edges s world next carrier}
    (registry : PublicRegistry) (release : PublishedRelease) (commit : TrieCommit)
    (b : Singular.TerminationBooking) {ref receipt}
    (history : HistoryPremises i.hash i.code commit release world registry (i.keyOf b.request.key))
    (path : CarrierHistory p env i (activeAsset i.hash i.code registry.identity (i.keyOf b.request.key))
      b.request.key edges s world carrier)
    (tx : Transaction world next) (aenv : Application.Env) (rp : Registry.Params)
    (ok : accepted i aenv rp p release tx.observation = true)
    (read : tx.bookingSpend i release rp registry.identity b ref = some receipt) :
    ∃ request before after,
      tx.creates request ∧ request.reference = b.request.reference ∧
      namedInput tx.observation receipt.reference = some carrier ∧
      receipt.reference = carrier.reference ∧ receipt.aid = b.request.key ∧
      checkpointDatum i carrier = some ⟨receipt.aid, .terminationPending receipt.position⟩ ∧
      (before, after, carrier) ∈ edges ∧
      ConvictionEdge p env receipt.aid receipt.position before after ∧
      ∃ writer, before.writers receipt.aid = some writer ∧ writer.authenticated receipt.aid = true ∧
        writer.epoch = receipt.position.epoch ∧ writer.writer.event.sn = receipt.position.sn := by
  unfold Transaction.bookingSpend at read
  simp only [bind, Option.bind] at read
  split at read <;> try contradiction
  rename_i request selected
  dsimp only at read
  split at read <;> try contradiction
  rename_i spent named
  dsimp only at read
  split at read <;> try contradiction
  rename_i cfg configured
  dsimp only at read
  split at read <;> try contradiction
  rename_i fields
  obtain ⟨txId, outputRef, action, _, _⟩ := fields
  obtain ⟨cfg', key, before, after, sameRef, config, input, decoded, datum, member, edge⟩ :=
    booking_spends_conviction_output registry release commit history path tx aenv rp ok action
  rw [named] at input
  rw [configured] at config
  cases input
  cases config
  rw [decoded] at read
  cases read
  exact ⟨request, before, after, ⟨by rwa [outputRef], by rwa [outputRef]⟩, outputRef,
    named, sameRef, rfl, datum, member, edge,
    conviction_spends_authenticated_writer (carrier_edge_source_reachable path member) edge⟩

/-- Given a public carrier history, when an accepted mint supplies the
economic booking and that booking succeeds, then the stored payload names
the exact output produced by conviction, its identifier and native position.
The mint reads the pending datum and the folder sees the original request. -/
theorem economic_entry_traces_to_conviction {p env} {i : Interpretation} {edges s world next carrier}
    (registry : PublicRegistry) (release : PublishedRelease) (commit : TrieCommit)
    (b : Singular.TerminationBooking) {ref localBooking before booked booker fee flow}
    (history : HistoryPremises i.hash i.code commit release world registry (i.keyOf b.request.key))
    (path : CarrierHistory p env i (activeAsset i.hash i.code registry.identity (i.keyOf b.request.key))
      b.request.key edges s world carrier)
    (tx : Transaction world next) (aenv : Application.Env) (rp : Registry.Params)
    (ok : accepted i aenv rp p release tx.observation = true)
    (read : tx.economicBooking i release rp registry.identity b ref = some localBooking)
    (placed : Registry.bookTermination rp before b.request.key booker fee localBooking = .ok (flow, booked)) :
    ∃ entry source target, Registry.pendingAt booked b.request.reference = some entry ∧
      entry.booking = b ∧ entry.payload.spend.reference = carrier.reference ∧
      entry.payload.spend.aid = b.request.key ∧
      checkpointDatum i carrier = some ⟨entry.payload.spend.aid, .terminationPending entry.payload.spend.position⟩ ∧
      (source, target, carrier) ∈ edges ∧
      ConvictionEdge p env entry.payload.spend.aid entry.payload.spend.position source target := by
  unfold Transaction.economicBooking at read
  cases found : tx.bookingSpend i release rp registry.identity b ref with
  | none => simp [found] at read
  | some spent =>
    by_cases key : spent.aid = b.request.key
    · simp [found, key] at read
      subst localBooking
      obtain ⟨entry, lookup, generic, payload, _⟩ := Registry.booking_stores_spend placed
      obtain ⟨_, source, target, _, _, _, reference, _, datum, member, edge, _⟩ :=
        booking_receipt_provenance registry release commit b history path tx aenv rp ok found
      have same : entry.payload.spend = spent := by
        rw [payload]
        cases spent
        simp_all [Registry.TerminationBooking.spend]
      exact ⟨entry, source, target, lookup, generic, same ▸ reference, same ▸ key,
        same ▸ datum, member, same ▸ edge⟩
    · simp [found, key] at read

end Custody
end CardanoKeri.Application
