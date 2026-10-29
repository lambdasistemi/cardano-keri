import CardanoKeri.Checkpoint
import CardanoKeri.RegistryLifecycleExamples
import CardanoKeri.DuplicityExamples

/-! Connected Checkpoint origin, retained output, local revival and actual
termination completion. Fixture evidence models verified cryptography only. -/
namespace CardanoKeri.Checkpoint.Examples

set_option maxRecDepth 10000
set_option maxHeartbeats 2000000

def p : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def env : Env := {
  rotationTo := fun epoch sn next => (epoch == 0 && sn == 0 && next == 1) ||
    (epoch == 1 && sn == 1 && next == 2),
  intentAuthorized := fun epoch intent refund => epoch == 1 && intent == .close 6 && refund == none,
  quorum := fun _ => false,
  convictionContext := fun epoch sn => some (Duplicity.fixture epoch sn).1,
  convictionRival := fun epoch sn => some (Duplicity.fixture epoch sn).2 }

def registrationReceipt : CardanoKeri.Registry.FoldReceipt CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg := {
  before := CardanoKeri.Registry.Examples.registrationBooked, after := CardanoKeri.Registry.Examples.registered,
  unspent := CardanoKeri.Registry.Examples.registrationUnspent, transaction := CardanoKeri.Registry.Examples.registrationTransaction,
  flow := { locked := [(11, 10)] }, reachable := CardanoKeri.Registry.Examples.registration_booked_reachable,
  executed := CardanoKeri.Registry.Examples.registration_folded }

def origin : Origin := {
  parameters := CardanoKeri.Registry.Examples.p, environment := CardanoKeri.Registry.Examples.env, configuration := CardanoKeri.Registry.Examples.cfg,
  registered := CardanoKeri.Registry.Examples.registered, token := 0, registrationRef := ⟨100, 0⟩,
  carrierRef := ⟨102, 1⟩ }

def live : Live := ⟨0, 0, false, false, 2, 42, 5⟩
def retained : Hash := ⟨1, 1⟩
def returned : Live := ⟨2, 2, false, false, 4, 42, 5⟩
def registered : Sys := Sys.init.installOrigin 11 (.present live) origin
def parked : Sys := registered.set 11 (.parked retained)
def revived : Sys := parked.set 11 (.present returned)
def pending : Sys := revived.set 11 (.terminationPending returned.hash)

def registryPending : CardanoKeri.Registry.Sys := {
  CardanoKeri.Registry.Examples.revived with carriers := [{ CardanoKeri.Registry.Examples.parkedCarrier with k := 2, st := .terminationPending }] }
def registryEntry : CardanoKeri.Registry.TerminationEntry := {
  CardanoKeri.Registry.Examples.terminationEntry with payload := { CardanoKeri.Registry.Examples.terminationEntry.payload with keyState := 2 } }
def registryBooked : CardanoKeri.Registry.Sys := {
  registryPending with carriers := [], terminations := [registryEntry] }

def association : PendingAssociation := {
  origin := origin, keyState := returned.hash, reference := ⟨200, 0⟩,
  entry := registryEntry, booked := registryBooked }
def booked : Sys := pending.associate 11 association
def completed : Sys := booked.finish 11

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

DeliveredOrigin registrationReceipt CardanoKeri.Registry.Examples.registration 11 origin
-/
theorem delivered_origin : DeliveredOrigin registrationReceipt CardanoKeri.Registry.Examples.registration 11 origin := by
  refine ⟨?_, rfl, rfl, rfl, rfl, rfl, rfl, rfl, ?_⟩
  · simp [registrationReceipt, Singular.foldMembers, Singular.foldMemberAt,
      CardanoKeri.Registry.Examples.registrationTransaction, CardanoKeri.Registry.Examples.registrationBooked, CardanoKeri.Registry.Sys.toWorld,
      CardanoKeri.Registry.Examples.registration, CardanoKeri.Registry.Examples.registrationRequest, Singular.foldWitnessInput]
  · exact ⟨1, CardanoKeri.Registry.Examples.carrierOutput, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env Sys.init registered
-/
theorem registered_step : SysStep p env Sys.init registered := by
  apply SysStep.register
  exact ⟨11, 2, 42, 5, { dregIn := 3, bIn := 2, poolIn := 5 }, .present live,
    CardanoKeri.Registry.Examples.p, CardanoKeri.Registry.Examples.env, CardanoKeri.Registry.Examples.cfg, registrationReceipt, CardanoKeri.Registry.Examples.registration, origin,
    rfl, rfl, Step.register 2 42 5, delivered_origin, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env registered parked
-/
theorem parked_step : SysStep p env registered parked := by
  apply SysStep.local
  refine ⟨11, .close 1 6 none, 3,
    { refund := some { addr := 42, dreg := 3, b := 2, pool := 4 },
      hunter := some { addr := 6, pool := 1 } }, .parked retained,
    ?_, ?_, ?_, rfl⟩
  · intro refund pool equal; cases equal
  · exact Step.closePaid 3 1 6 none (by decide) (by decide) (by decide) (by decide)
  · rintro ⟨sn, refund, pool, equal⟩; cases equal

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env parked revived
-/
theorem revived_step : SysStep p env parked revived := by
  apply SysStep.local
  refine ⟨11, .reopen 2 42 5, 4, { dregIn := 3, bIn := 2, poolIn := 5 },
    .present returned, ?_, ?_, ?_, rfl⟩
  · intro refund pool equal; cases equal
  · exact Step.reopen 4 2 42 5 (by decide) (by decide)
  · intro _; rfl

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env revived pending
-/
theorem pending_step : SysStep p env revived pending := by
  apply SysStep.local
  refine ⟨11, .convict 7, 5,
    { refund := some { addr := 42, b := 2, pool := 5 },
      convictor := some { addr := 7, dreg := 3 } },
    .terminationPending returned.hash, ?_, ?_, ?_, rfl⟩
  · intro refund pool equal; cases equal
  · exact Step.convict 5 7 (by decide)
  · rintro ⟨sn, refund, pool, equal⟩; cases equal


/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.convictCkpt CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.revived 11 = .ok ({}, registryPending)
-/
theorem registry_convicted :
    CardanoKeri.Registry.convictCkpt CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.revived 11 = .ok ({}, registryPending) := by rfl

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.bookTermination CardanoKeri.Registry.Examples.p registryPending 11 7 1 CardanoKeri.Registry.Examples.termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, registryBooked)
-/
theorem registry_booked :
    CardanoKeri.Registry.bookTermination CardanoKeri.Registry.Examples.p registryPending 11 7 1 CardanoKeri.Registry.Examples.termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, registryBooked) := by
  simp [registryPending, registryBooked, registryEntry, CardanoKeri.Registry.Examples.revived, CardanoKeri.Registry.bookTermination, CardanoKeri.Registry.carrierAt, CardanoKeri.Registry.Examples.parked, CardanoKeri.Registry.Examples.registered, CardanoKeri.Registry.Examples.liveCarrier, CardanoKeri.Registry.Examples.parkedCarrier,
    CardanoKeri.Registry.Examples.termination, CardanoKeri.Registry.Examples.terminationRequest, CardanoKeri.Registry.Examples.terminationEntry, CardanoKeri.Registry.Examples.p, CardanoKeri.Registry.Examples.cfg,
    Singular.bookTermination, Singular.terminationBookingRefusal, Singular.terminationContentsShape,
    Singular.terminationDeclaredLovelace, Singular.terminationCustody, CardanoKeri.Registry.Sys.toWorld, CardanoKeri.Registry.Sys.init,
    Singular.TerminationRequest.trieReadyTag, Singular.TerminationRequest.operation,
    Singular.Config.singularTag, Singular.Config.trieReadyTag,
    CardanoKeri.Registry.instBEqCkState, Singular.trieGet, bind, Except.bind, pure, Except.pure]
  rfl

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env registryBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy
      CardanoKeri.Registry.Examples.terminationUnspent CardanoKeri.Registry.Examples.terminationTransaction = .ok ({}, CardanoKeri.Registry.Examples.retired)
-/
theorem registry_folded :
    CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env registryBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy
      CardanoKeri.Registry.Examples.terminationUnspent CardanoKeri.Registry.Examples.terminationTransaction = .ok ({}, CardanoKeri.Registry.Examples.retired) := by
  simp +decide [registryPending, registryBooked, registryEntry, CardanoKeri.Registry.Examples.revived,
    Singular.foldMemberRefusal,
    Singular.foldPrerequisite,
    Singular.foldEffect,
    Singular.foldAccepted,
    Singular.foldMemberAt,
    Singular.foldMembers,
    Singular.foldLegacyRequest,
    Singular.foldProjectedRegistry,
    Singular.foldRemainingTerminations,
    Singular.foldRegistryEffect,
    Singular.foldBareValue,
    Singular.foldStateShape,
    Singular.foldCarrierRefusal,
    Singular.foldRoutingRefusal,
    Singular.economicLookup,
    Singular.economicSpent,
    Singular.observesRegistration,
    Singular.observesTermination,
    Singular.observesWorld,
    Singular.economicObservationRefusal,
    Singular.exactBurns,
    Singular.requestTagsBurned,
    Singular.inputsContainReference,
    Singular.inputPresenceRefusal,
    Singular.delta,
    Singular.assetDelta,
    Singular.refusal,
    Singular.emptyResult,
    Singular.combineResults,
    Singular.applyEdge,
    Singular.step,
    Singular.foldActions,
    Singular.batchConsumesCreated,
    Singular.batchConsumesCreated.go,
    Singular.foldBatch,
    CardanoKeri.Registry.Examples.terminationBooked,
    CardanoKeri.Registry.Examples.terminationEntry,
    CardanoKeri.Registry.Examples.termination,
    CardanoKeri.Registry.Examples.terminationRequest,
    CardanoKeri.Registry.Examples.terminationTransaction,
    CardanoKeri.Registry.Examples.terminationUnspent,
    CardanoKeri.Registry.Examples.retired,
    CardanoKeri.Registry.Examples.pending,
    CardanoKeri.Registry.Examples.parked,
    CardanoKeri.Registry.pendingAt,
    Singular.terminationWitnessTransaction,
    Singular.terminationWitnessUnspent,
    Singular.terminationWitnessInputs,
    Singular.terminationWitnessFresh,
    Singular.worldRequestReferences,
    Singular.terminationWitnessResult,
    Singular.terminationWitnessOutput,
    CardanoKeri.Registry.Examples.registered,
    CardanoKeri.Registry.Examples.liveCarrier,
    CardanoKeri.Registry.Examples.parkedCarrier,
    CardanoKeri.Registry.Examples.cfg,
    CardanoKeri.Registry.Examples.p,
    CardanoKeri.Registry.Sys.init,
    CardanoKeri.Registry.Sys.toWorld,
    CardanoKeri.Registry.fold,
    CardanoKeri.Registry.foldResult,
    CardanoKeri.Registry.installMember,
    Singular.foldWitnessInput,
    Singular.foldWitnessState,
    Singular.foldWitnessOrdinary,
    Singular.registrationWitnessOutput,
    Singular.Config.stateToken,
    Singular.Config.singularTag,
    Singular.trieGet,
    Singular.trieSet,
    BEq.beq,
    bind,
    Except.bind,
    pure,
    Except.pure]

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.History CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.registered registryPending
-/
theorem origin_history : CardanoKeri.Registry.History CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.registered registryPending :=
  CardanoKeri.Registry.History.step
    (CardanoKeri.Registry.History.step
      (CardanoKeri.Registry.History.step (CardanoKeri.Registry.History.refl CardanoKeri.Registry.Examples.registered)
        (action := .park 11 6) CardanoKeri.Registry.Examples.parking_success)
      (action := .revive 11) CardanoKeri.Registry.Examples.revival_success)
    (action := .convictCkpt 11) registry_convicted

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.Reach CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg registryPending
-/
theorem registry_pending_reachable : CardanoKeri.Registry.Reach CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg registryPending :=
  CardanoKeri.Registry.Reach.next
    (CardanoKeri.Registry.Reach.next CardanoKeri.Registry.Examples.parked_reachable (action := .revive 11) CardanoKeri.Registry.Examples.revival_success)
    (action := .convictCkpt 11) registry_convicted

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.Reach CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg registryBooked
-/
theorem registry_booked_reachable : CardanoKeri.Registry.Reach CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg registryBooked :=
  CardanoKeri.Registry.Reach.next registry_pending_reachable
    (action := .bookTermination 11 7 1 CardanoKeri.Registry.Examples.termination) registry_booked

def completionReceipt : CardanoKeri.Registry.FoldReceipt CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg := {
  before := registryBooked, after := CardanoKeri.Registry.Examples.retired,
  unspent := CardanoKeri.Registry.Examples.terminationUnspent, transaction := CardanoKeri.Registry.Examples.terminationTransaction,
  flow := {}, reachable := registry_booked_reachable, executed := registry_folded }

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env pending booked
-/
theorem booked_step : SysStep p env pending booked := by
  apply SysStep.book
  exact ⟨11, returned.hash, origin, registryPending, registryBooked, 7, 1,
    CardanoKeri.Registry.Examples.termination, { premium := some (7, 1), intoRequest := 3, bookingFee := 1 },
    registryEntry, rfl, rfl, rfl, origin_history, registry_booked, rfl, rfl, rfl, rfl, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

ReceiptMatches booked 11 association completionReceipt
-/
theorem receipt_matches : ReceiptMatches booked 11 association completionReceipt := by
  exact ⟨rfl, rfl, rfl, CardanoKeri.Registry.History.refl registryBooked, rfl, rfl,
    registryEntry, rfl, rfl, rfl, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env booked completed
-/
theorem completed_step : SysStep p env booked completed :=
  SysStep.complete ⟨11, association, completionReceipt, receipt_matches, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysReach p env completed ∧ completed.states 11 = .convicted ∧
      completed.leaves 11 = .retired ∧ completed.pending 11 = none ∧
      completed.origins 11 = some origin
-/
theorem connected_completion :
    SysReach p env completed ∧ completed.states 11 = .convicted ∧
      completed.leaves 11 = .retired ∧ completed.pending 11 = none ∧
      completed.origins 11 = some origin := by
  refine ⟨?_, rfl, rfl, rfl, rfl⟩
  exact SysReach.step
    (SysReach.step
      (SysReach.step
        (SysReach.step
          (SysReach.step
            (SysReach.step SysReach.init registered_step) parked_step)
          revived_step) pending_step) booked_step) completed_step


-- A second actual history at the same context/AID/alias, with a different request.
def otherTermination : Singular.TerminationBooking := {
  CardanoKeri.Registry.Examples.termination with request := { CardanoKeri.Registry.Examples.termination.request with reference := ⟨201, 0⟩ } }
def otherEntry : CardanoKeri.Registry.TerminationEntry := { registryEntry with booking := otherTermination }
def otherBooked : CardanoKeri.Registry.Sys := { registryPending with carriers := [], terminations := [otherEntry] }
def otherUnspent : Singular.EconomicUtxo := Singular.terminationWitnessUnspent otherBooked.toWorld 1
def otherTransaction : Singular.EconomicTransaction :=
  Singular.terminationWitnessTransaction otherBooked.toWorld otherTermination 20 1 1

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.bookTermination CardanoKeri.Registry.Examples.p registryPending 11 7 1 otherTermination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, otherBooked)
-/
theorem other_booked :
    CardanoKeri.Registry.bookTermination CardanoKeri.Registry.Examples.p registryPending 11 7 1 otherTermination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, otherBooked) := by
  simp [otherTermination, otherEntry, otherBooked, registryPending, registryEntry, CardanoKeri.Registry.Examples.revived, CardanoKeri.Registry.bookTermination, CardanoKeri.Registry.carrierAt, CardanoKeri.Registry.Examples.parked, CardanoKeri.Registry.Examples.registered, CardanoKeri.Registry.Examples.liveCarrier, CardanoKeri.Registry.Examples.parkedCarrier,
    CardanoKeri.Registry.Examples.termination, CardanoKeri.Registry.Examples.terminationRequest, CardanoKeri.Registry.Examples.terminationEntry, CardanoKeri.Registry.Examples.p, CardanoKeri.Registry.Examples.cfg,
    Singular.bookTermination, Singular.terminationBookingRefusal, Singular.terminationContentsShape,
    Singular.terminationDeclaredLovelace, Singular.terminationCustody, CardanoKeri.Registry.Sys.toWorld, CardanoKeri.Registry.Sys.init,
    Singular.TerminationRequest.trieReadyTag, Singular.TerminationRequest.operation,
    Singular.Config.singularTag, Singular.Config.trieReadyTag,
    CardanoKeri.Registry.instBEqCkState, Singular.trieGet, bind, Except.bind, pure, Except.pure]
  rfl

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env otherBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy otherUnspent otherTransaction =
      .ok ({}, CardanoKeri.Registry.Examples.retired)
-/
theorem other_folded :
    CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env otherBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy otherUnspent otherTransaction =
      .ok ({}, CardanoKeri.Registry.Examples.retired) := by
  simp +decide [otherTermination, otherEntry, otherBooked, otherUnspent, otherTransaction, registryPending, registryEntry, CardanoKeri.Registry.Examples.revived,
    Singular.foldMemberRefusal,
    Singular.foldPrerequisite,
    Singular.foldEffect,
    Singular.foldAccepted,
    Singular.foldMemberAt,
    Singular.foldMembers,
    Singular.foldLegacyRequest,
    Singular.foldProjectedRegistry,
    Singular.foldRemainingTerminations,
    Singular.foldRegistryEffect,
    Singular.foldBareValue,
    Singular.foldStateShape,
    Singular.foldCarrierRefusal,
    Singular.foldRoutingRefusal,
    Singular.economicLookup,
    Singular.economicSpent,
    Singular.observesRegistration,
    Singular.observesTermination,
    Singular.observesWorld,
    Singular.economicObservationRefusal,
    Singular.exactBurns,
    Singular.requestTagsBurned,
    Singular.inputsContainReference,
    Singular.inputPresenceRefusal,
    Singular.delta,
    Singular.assetDelta,
    Singular.refusal,
    Singular.emptyResult,
    Singular.combineResults,
    Singular.applyEdge,
    Singular.step,
    Singular.foldActions,
    Singular.batchConsumesCreated,
    Singular.batchConsumesCreated.go,
    Singular.foldBatch,
    CardanoKeri.Registry.Examples.terminationBooked,
    CardanoKeri.Registry.Examples.terminationEntry,
    CardanoKeri.Registry.Examples.termination,
    CardanoKeri.Registry.Examples.terminationRequest,
    CardanoKeri.Registry.Examples.retired,
    CardanoKeri.Registry.Examples.pending,
    CardanoKeri.Registry.Examples.parked,
    CardanoKeri.Registry.pendingAt,
    Singular.terminationWitnessTransaction,
    Singular.terminationWitnessUnspent,
    Singular.terminationWitnessInputs,
    Singular.terminationWitnessFresh,
    Singular.worldRequestReferences,
    Singular.terminationWitnessResult,
    Singular.terminationWitnessOutput,
    CardanoKeri.Registry.Examples.registered,
    CardanoKeri.Registry.Examples.liveCarrier,
    CardanoKeri.Registry.Examples.parkedCarrier,
    CardanoKeri.Registry.Examples.cfg,
    CardanoKeri.Registry.Examples.p,
    CardanoKeri.Registry.Sys.init,
    CardanoKeri.Registry.Sys.toWorld,
    CardanoKeri.Registry.fold,
    CardanoKeri.Registry.foldResult,
    CardanoKeri.Registry.installMember,
    Singular.foldWitnessInput,
    Singular.foldWitnessState,
    Singular.foldWitnessOrdinary,
    Singular.registrationWitnessOutput,
    Singular.Config.stateToken,
    Singular.Config.singularTag,
    Singular.trieGet,
    Singular.trieSet,
    BEq.beq,
    bind,
    Except.bind,
    pure,
    Except.pure]

def otherReceipt : CardanoKeri.Registry.FoldReceipt CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg := {
  before := otherBooked, after := CardanoKeri.Registry.Examples.retired, unspent := otherUnspent,
  transaction := otherTransaction, flow := {},
  reachable := CardanoKeri.Registry.Reach.next registry_pending_reachable
    (action := .bookTermination 11 7 1 otherTermination) other_booked,
  executed := other_folded }

/-- Given an actual successful termination receipt at the same context, AID and
alias but reference201, when offered to the stored reference200 association,
then the association refuses; the correct receipt has receipt_matches. -/
theorem other_request_receipt_refused : ¬ ReceiptMatches booked 11 association otherReceipt := by
  intro h
  have missing := h.2.2.2.2.2.1
  change none = some association.entry at missing
  cases missing

/-- Given the genuine receipt and pending checkpoint, changing the recorded
pending key cannot satisfy the stored association check. -/
theorem changed_pending_key_refused :
    ¬ ReceiptMatches booked 11 { association with keyState := ⟨2, 3⟩ } completionReceipt := by
  intro h
  have same := h.1
  have key := congrArg (fun x => x.map PendingAssociation.keyState) same
  change some returned.hash = some (⟨2, 3⟩ : Hash) at key
  cases key

/-- Given the same successful revival source, replay under an environment with
no conviction authorization actually refuses at the canonical function. -/
theorem stored_context_conviction_refused :
    CardanoKeri.Registry.convictCkpt { CardanoKeri.Registry.Examples.env with duplicity := fun _ _ => false } CardanoKeri.Registry.Examples.revived 11 =
      .error "keri-conviction-refused" := by rfl

end CardanoKeri.Checkpoint.Examples
