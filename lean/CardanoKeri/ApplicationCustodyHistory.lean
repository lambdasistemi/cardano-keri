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
      (created : tx.creates out) (datum : Carries i token aid out state)
      (ordinary : ∀ refund pool, action ≠ .register refund pool)
      (executed : Step p (env aid) action now (before.states aid) flow state)
      (openMarker : before.revealOpen aid action)
      (writer : (before.localWriter (env aid) aid action).isSome = true)
      (updated : after = (before.set aid state (before.localWriter (env aid) aid action).join).retireRevealed action) :
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

/-- Given a carrier history, when the current holding is read from its ledger
world, then that very output remains unspent and carries one active token. -/
theorem carrier_unspent {p env i token aid edges s w out}
    (path : CarrierHistory p env i token aid edges s w out) :
    out ∈ w.unspent ∧ quantity out token = 1 := by
  induction path with
  | register _ _ _ _ _ tx _ created datum =>
    exact ⟨tx.ledger.nextUnspent ▸ List.mem_append_right _ (List.mem_of_getElem? created.1), datum.1⟩
  | spend _ tx _ created datum _ _ _ _ _ _ =>
    exact ⟨tx.ledger.nextUnspent ▸ List.mem_append_right _ (List.mem_of_getElem? created.1), datum.1⟩
  | retain _ tx survives _ _ ih =>
    rw [tx.ledger.nextUnspent]
    exact ⟨List.mem_append_left _ (List.mem_filter.mpr ⟨ih.1, by simpa using survives⟩), ih.2⟩

/-- Given a carrier history, when its current output decodes as pending, then
this exact output was created by a conviction edge of this identifier at
the decoded key state. -/
theorem pending_output_producer {p env i token aid edges s w out key}
    (path : CarrierHistory p env i token aid edges s w out)
    (pending : checkpointDatum i out = some ⟨aid, .terminationPending key⟩) :
    ∃ before after, (before, after, out) ∈ edges ∧ ConvictionEdge p env aid key before after := by
  induction path with
  | register _ _ _ _ _ _ _ _ datum =>
    rw [datum.2] at pending
    simp [State.datumFacts] at pending
  | @spend edges before after w w' old out action now flow state _ _ _ _ datum _ executed opened _ updated _ =>
    subst after
    rw [datum.2] at pending
    have target : state = .terminationPending key := by cases state <;> simp_all [State.datumFacts]
    subst state
    obtain ⟨live, payee, c, wasLive, rfl, _, _, atKey⟩ := pending_only_by_conviction _ _ executed
    rw [wasLive] at executed
    exact ⟨_, _, List.mem_cons_self, live, now, payee, c, flow, wasLive, atKey, executed, opened, rfl⟩
  | retain _ _ _ _ _ ih => exact ih pending

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
  obtain ⟨cfg, input, request, _, named, _, _, pending, _⟩ :=
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
  exact ⟨index, key, before, after, booked, named, pendingDatum, member, edge⟩

end Custody
end CardanoKeri.Application
