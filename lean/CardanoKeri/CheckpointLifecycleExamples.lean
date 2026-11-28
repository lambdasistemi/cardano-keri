import CardanoKeri.CheckpointCommitmentGoals
import CardanoKeri.AttestationFixtures
import CardanoKeri.CheckpointSystemHistory
import CardanoKeri.RegistryLifecycleExamples
import CardanoKeri.DuplicityExamples

/-! Connected Checkpoint origin, a local rotation, conviction and actual
termination completion. There is no owner exit. Fixture evidence models
verified cryptography only. -/
namespace CardanoKeri.Checkpoint.Examples

set_option maxRecDepth 10000
set_option maxHeartbeats 2000000

def p : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def env (aid : AID) : Env := {
  advanceReads := CardanoKeri.Attestation.Fixtures.advances (fun epoch sn next => aid == 11 && ((epoch == 0 && sn == 0 && next == 1) ||
    (epoch == 1 && sn == 1 && next == 2))),
  depositAuthorized := fun _ => false,
  quorum := fun _ => false,
  inceptionBytes := fun subject raw => if subject == aid && raw == 777 then some [1] else none,
  inceptionOpening := {
    prefixCode := fun subject => if subject == aid then some "D" else none
    decodeEvidence := fun bytes => if bytes == [1] then some ⟨Duplicity.writerFixture aid 0 .inception, []⟩ else none },
  rotationWriter := fun subject _ _ target => if subject == aid then
    some (Duplicity.writerFixture aid target .rotation) else none,
  keyReads := KeyReads.symbolic
  convictionReads := CardanoKeri.Attestation.Fixtures.convictionReads ⟨105 + (aid - 11), 0⟩,
  presentedSpend := fun e sn => some ⟨⟨105 + (aid - 11), 0⟩, CardanoKeri.CheckpointConviction.Fixtures.comparison aid e sn⟩,
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
  carrierRef := ⟨102, 1⟩, inception := .inception (Duplicity.writerFixture 11 0 .inception) [] }

def live : Live := ⟨0, 0, false, false, 1, 42, 5, false⟩
def rotatedLive : Live := ⟨1, 1, false, false, 1, 42, 4, false⟩
/-- The deployment these examples run in. -/
def deployment : Deployment := 21
def registered : Sys := (Sys.init deployment).installOrigin 11 (.present live) origin
def rotated : Sys := registered.set 11 (.present rotatedLive)
  (some (.rotation origin.inception (Duplicity.writerFixture 11 1 .rotation)))
/-- Cora's commitment: it names AID 11, this deployment, the key state after the
rotation and the evidence
the conviction shows there, naming payee 7, its opening transaction's
validity range ending at slot 4, eligible from slot 5, expiring at slot 20. -/
def commitment : Commitment := {
  aid := 11, deployment := deployment, keyState := rotatedLive.hash,
  evidence := (CardanoKeri.CheckpointConviction.Fixtures.comparison 11 1 1).rival,
  payee := 7, openedAt := 4, eligibleAfter := 5, expiresAt := 20, marker := 1 }
def committed : Sys :=
  { rotated with commitments := fun k => if k = commitment.marker then some commitment else rotated.commitments k }
def pending : Sys := (committed.set 11 (.terminationPending rotatedLive.hash) none ((env 11).convictionSpend 1 1)).retire commitment.marker

def registryPending : CardanoKeri.Registry.Sys := CardanoKeri.Registry.Examples.pending
def registryEntry : CardanoKeri.Registry.TerminationEntry := CardanoKeri.Registry.Examples.terminationEntry
def registryBooked : CardanoKeri.Registry.Sys := CardanoKeri.Registry.Examples.terminationBooked

def association : PendingAssociation := {
  origin := origin, keyState := rotatedLive.hash, reference := ⟨200, 0⟩,
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

SysStep p env (Sys.init deployment) registered
-/
theorem registered_step : SysStep p env (Sys.init deployment) registered := by
  apply SysStep.register
  exact ⟨11, 1, 42, 5, { dregIn := 3, bIn := 2, poolIn := 5 }, .present live,
    CardanoKeri.Registry.Examples.p, CardanoKeri.Registry.Examples.env, CardanoKeri.Registry.Examples.cfg, registrationReceipt, CardanoKeri.Registry.Examples.registration, origin,
    rfl, rfl, Step.register 1 42 5 (by decide), delivered_origin, ⟨by decide, by decide⟩, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env registered rotated
-/
theorem rotated_step : SysStep p env registered rotated := by
  apply SysStep.local
  refine ⟨11, .rotate 1 .keep 6, 3, { hunter := some { addr := 6, pool := 1 } },
    .present rotatedLive, ?_, ?_, ?_, rfl⟩
  · intro refund pool equal; cases equal
  · exact Step.rotateKeepPaid 3 1 6 (by decide) (by decide) (by decide)
  · exact ⟨rfl, by decide⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env rotated committed
-/
theorem committed_step : SysStep p env rotated committed := by
  apply SysStep.openCommitment
  exact ⟨commitment, rfl, by decide, rfl⟩

/-- Given the registered and rotated checkpoint, when its payee convicts at
slot five, the checked transition consumes the open marker and produces pending. -/
private theorem conviction_at_five : (ClosingEvent.convict 11 7 5).Occurs p env committed pending commitment := by
  refine ⟨
    { refund := some { addr := 42, b := 2, pool := 4 },
      convictor := some { addr := 7, dreg := 3 } },
    .terminationPending rotatedLive.hash, ?_, ?_, ?_, rfl⟩
  · intro refund pool equal; cases equal
  · exact Step.convict 5 7 commitment (by decide) (by decide)
  · exact ⟨by unfold Sys.revealOpen; decide, rfl⟩

-- The same two states admit both commands. The headline timing result for
-- the reveal must still use slot 10, even when the caller also has the sweep.
example : commitment.eligibleAfter ≤ 10 ∧ 10 ≤ commitment.expiresAt := by
  have reachable : SysReach p env committed :=
    .step (.step (.step (.init deployment) registered_step) rotated_step) committed_step
  have reveal : (ClosingEvent.reveal 10).Occurs p env committed (committed.retire 1) commitment :=
    ⟨rfl, by decide, by decide, rfl⟩
  have sweep : (ClosingEvent.sweep 21).Occurs p env committed (committed.retire 1) commitment :=
    ⟨rfl, by decide, rfl⟩
  have applyReveal := commitment_closes_in_or_after_window p env reachable
    (m := 1) (c := commitment) (event := .reveal 10) rfl (s' := committed.retire 1)
  fail_if_success exact (applyReveal sweep).2.2
  have sweepBound : commitment.expiresAt < 21 :=
    (commitment_closes_in_or_after_window p env reachable (m := 1) (c := commitment)
      (event := .sweep 21) rfl sweep).2.2
  fail_if_success exact sweepBound
  exact (applyReveal reveal).2.2

-- The headline itself rules out a conviction at slot 4 for this reachable
-- opening, even though the same successor can be produced at slot 5.
example : ¬ (ClosingEvent.convict 11 7 4).Occurs p env committed pending commitment := by
  intro early
  have reachable : SysReach p env committed :=
    .step (.step (.step (.init deployment) registered_step) rotated_step) committed_step
  have window := (commitment_closes_in_or_after_window p env reachable (m := 1)
    (c := commitment) (event := .convict 11 7 4) rfl early).2.2
  exact (by decide : ¬ commitment.eligibleAfter ≤ 4) window.1

-- A conviction supplied at slot 5 entitles the supplied payee at slot 5.
example : commitment.entitles (env 11) rotatedLive 7 5 ∧ commitment.openedAt < 5 := by
  have reachable : SysReach p env committed :=
    .step (.step (.step (.init deployment) registered_step) rotated_step) committed_step
  exact (sys_conviction_after_opening_slot p env reachable (aid := 11) (payee := 7)
    (now := 5) (l := rotatedLive) rfl conviction_at_five).2

-- The former time-only conclusion holds for every commitment, without a step.
example (c : Commitment) : ∃ now : Slot,
    (c.eligibleAfter ≤ now ∧ now ≤ c.expiresAt) ∨ c.expiresAt < now :=
  ⟨c.expiresAt + 1, Or.inr (Nat.lt_succ_self _)⟩

-- With no opening in the initial system, none of the three closing events occurs.
example (c : Commitment) (event : ClosingEvent) :
    ¬ event.Occurs p env (Sys.init deployment) (Sys.init deployment) c := by
  intro actual
  have held : (Sys.init deployment).commitments c.marker = some c := by
    cases event with
    | convict aid payee now =>
      obtain ⟨_, _, _, _, checks, _⟩ := actual
      exact ((Sys.revealOpen_iff _ _ _).mp checks.1 c rfl).1
    | reveal => exact actual.1
    | sweep => exact actual.1
  cases held

-- Slot 21 satisfies the old conclusion for this exact commitment. The actual
-- conviction at slot five cannot instead be certified with the expired slot.
example : commitment.expiresAt < 21 ∧
    ¬ (ClosingEvent.convict 11 7 21).Occurs p env committed pending commitment := by
  refine ⟨by decide, fun actual => ?_⟩
  exact (by decide : ¬ 21 ≤ commitment.expiresAt) (ClosingEvent.timing actual).2

-- The old after-opening conclusion also holds with no closing transaction:
-- slot six entitles the payee, while keeping the marker open precludes a conviction.
example : committed.commitments commitment.marker = some commitment ∧
    commitment.entitles (env 11) rotatedLive 7 6 ∧ commitment.openedAt < 6 ∧
    ¬ (ClosingEvent.convict 11 7 6).Occurs p env committed committed commitment := by
  refine ⟨rfl, by decide, by decide, ?_⟩
  intro actual
  obtain ⟨_, _, _, _, _, target⟩ := actual
  have marker := congrArg (fun s : Sys => s.commitments commitment.marker) target
  have held : committed.commitments commitment.marker = some commitment := rfl
  simp [Sys.retireRevealed, Action.revealed, Sys.retire, held] at marker

example : (ClosingEvent.reveal 20).Occurs p env committed (committed.retire 1) commitment :=
  ⟨rfl, by decide, by decide, rfl⟩
example : (ClosingEvent.sweep 21).Occurs p env committed (committed.retire 1) commitment :=
  ⟨rfl, by decide, rfl⟩
example : ¬ (ClosingEvent.sweep 20).Occurs p env committed (committed.retire 1) commitment :=
  fun actual => (by decide : ¬ commitment.expiresAt < 20) (ClosingEvent.timing actual)

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env committed pending
-/
theorem pending_step : SysStep p env committed pending :=
  ClosingEvent.system_step (event := .convict 11 7 5) conviction_at_five


/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.convictCkpt CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.registered 11 = .ok ({}, registryPending)
-/
theorem registry_convicted :
    CardanoKeri.Registry.convictCkpt CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.registered 11 = .ok ({}, registryPending) := by rfl

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.bookTermination CardanoKeri.Registry.Examples.p registryPending 11 7 1 CardanoKeri.Registry.Examples.termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, registryBooked)
-/
theorem registry_booked :
    CardanoKeri.Registry.bookTermination CardanoKeri.Registry.Examples.p registryPending 11 7 1 CardanoKeri.Registry.Examples.termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, registryBooked) :=
  CardanoKeri.Registry.Examples.termination_booked

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p registryBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy
      CardanoKeri.Registry.Examples.terminationUnspent CardanoKeri.Registry.Examples.terminationTransaction = .ok ({}, CardanoKeri.Registry.Examples.retired)
-/
theorem registry_folded :
    CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p registryBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy
      CardanoKeri.Registry.Examples.terminationUnspent CardanoKeri.Registry.Examples.terminationTransaction = .ok ({}, CardanoKeri.Registry.Examples.retired) :=
  CardanoKeri.Registry.Examples.termination_folded

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.History CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.registered registryPending
-/
theorem origin_history : CardanoKeri.Registry.History CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.registered registryPending :=
  CardanoKeri.Registry.History.step (CardanoKeri.Registry.History.refl CardanoKeri.Registry.Examples.registered)
    (action := .convictCkpt 11) registry_convicted

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

CardanoKeri.Registry.Reach CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg registryPending
-/
theorem registry_pending_reachable : CardanoKeri.Registry.Reach CardanoKeri.Registry.Examples.p CardanoKeri.Registry.Examples.env CardanoKeri.Registry.Examples.cfg registryPending :=
  CardanoKeri.Registry.Reach.next CardanoKeri.Registry.Examples.registered_reachable
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

/-- The observed booking associates the request with the prior checkpoint spend. -/
theorem booked_event : BookingEvent pending booked := by
  exact ⟨11, rotatedLive.hash, origin, registryPending, registryBooked, 7, 1,
    CardanoKeri.Registry.Examples.termination, { premium := some (7, 1), intoRequest := 3, bookingFee := 1 },
    registryEntry, rfl, rfl, rfl, origin_history, registry_booked, rfl, rfl, rfl, ⟨rfl, rfl, by decide⟩, rfl⟩

/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the local Checkpoint or associated system relation named by this theorem.
Then the complete conclusion is:

SysStep p env pending booked
-/
theorem booked_step : SysStep p env pending booked := .book booked_event

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
          (SysReach.step (SysReach.step (SysReach.init deployment) registered_step) rotated_step)
            committed_step)
        pending_step) booked_step) completed_step


-- A second actual history at the same context/AID/alias, with a different request.
def otherTermination : CardanoKeri.Registry.TerminationBooking := {
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
  have read : Registry.Examples.env.pendingSpend 11 = some otherTermination.spend := by decide
  simp [Registry.Carrier.convicted, Registry.Carrier.st, read, otherTermination, otherEntry, otherBooked, registryPending, registryEntry, CardanoKeri.Registry.Examples.pending, CardanoKeri.Registry.bookTermination, CardanoKeri.Registry.carrierAt, CardanoKeri.Registry.Examples.registered, CardanoKeri.Registry.Examples.liveCarrier,
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

CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p otherBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy otherUnspent otherTransaction =
      .ok ({}, CardanoKeri.Registry.Examples.retired)
-/
theorem other_folded :
    CardanoKeri.Registry.fold CardanoKeri.Registry.Examples.p otherBooked 1 CardanoKeri.Registry.Examples.cfg.applicationPolicy otherUnspent otherTransaction =
      .ok ({}, CardanoKeri.Registry.Examples.retired) := by
  simp +decide [otherTermination, otherEntry, otherBooked, otherUnspent, otherTransaction, registryPending, registryEntry,
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
  change some rotatedLive.hash = some (⟨2, 3⟩ : Hash) at key
  cases key

/-- Given the same successful conviction source, replay under an environment with
no conviction authorization actually refuses at the canonical function. -/
theorem stored_context_conviction_refused :
    CardanoKeri.Registry.convictCkpt { CardanoKeri.Registry.Examples.env with presentedConviction := fun _ => none } CardanoKeri.Registry.Examples.registered 11 =
      .error "keri-conviction-refused" := by rfl


/-- Given the reachable rotated checkpoint and its open commitment, when the
convictor supplies the same observed rival with no separate two-event history
lookup, then the local spend enters pending at the rotated position. -/
theorem rotated_spend_uses_one_rival :
    let localEnv := { env 11 with convictionContext := fun _ _ => none, convictionRival := fun _ _ => none }
    stepFn p localEnv (.convict 7 commitment) 5 (.present rotatedLive) =
      some ({ refund := some { addr := 42, b := 2, pool := 4 }, convictor := some { addr := 7, dreg := 3 } },
        .terminationPending rotatedLive.hash) := by decide

-- Keep the original commitment and two-event reader while changing the
-- output selected in the conviction transaction.
/-- The pending output selects its producing spend. A production recorded only
at 105#1 fails the read for 105#0 with the same spent-tip comparison. -/
theorem conviction_mint_bound_to_output :
    let exactClaim : Registry.Conviction :=
      ⟨⟨105, 0⟩, CheckpointConviction.Fixtures.comparison 11 1 1⟩
    let other := {exactClaim with output.index := 1}
    let atUse := fun (claim : Registry.Conviction) =>
      ({env 11 with convictionReads := CardanoKeri.Attestation.Fixtures.convictionReads claim.output} : Env)
    (atUse exactClaim).acceptsRival 1 1 = true ∧
      (atUse other).acceptsRival 1 1 = false := by decide

example : stepFn p { env 11 with convictionReads := { (env 11).convictionReads with producingSpend := fun _ => none } } (.convict 7 commitment) 5
    (.present rotatedLive) = none := by decide

namespace NestedWriter

private def threshold : Duplicity.Threshold := .weighted [[.group ⟨1, 1⟩ [⟨1, 1⟩]]]

private def writer (aid sn : Nat) : Duplicity.SignedEvent :=
  let content := { (Duplicity.writerFixture aid sn .rotation).event with
    eventDigest := s!"nested-writer/{aid}/{sn}", threshold := threshold, nextThreshold := threshold }
  Duplicity.signed content [aid] []

private def sibling := Duplicity.signed { (writer 11 1).event with extension := [1], eventDigest := "lifecycle-sibling" } [11] []
private def history := EventHistory.rotation origin.inception (writer 11 1)
private def comparison : CheckpointConviction.Comparison :=
  ⟨history.datum.tip KeyEncoding.symbolic 1, sibling⟩

private def environment (aid : Nat) : Env :=
  { env aid with
    rotationWriter := fun subject _ _ sn => some (writer subject sn)
    presentedSpend := fun _ _ => some ⟨⟨105, 0⟩, comparison⟩ }

private def state := registered.set 11 (.present rotatedLive) (some history)

private theorem reachable : SysReach p environment state := by
  have reg : SysStep p environment (Sys.init deployment) registered := by
    apply SysStep.register
    exact ⟨11, 1, 42, 5, { dregIn := 3, bIn := 2, poolIn := 5 }, .present live,
      Registry.Examples.p, Registry.Examples.env, Registry.Examples.cfg, registrationReceipt,
      Registry.Examples.registration, origin, rfl, rfl, Step.register 1 42 5 (by decide),
      delivered_origin, ⟨by decide, by decide⟩, rfl⟩
  refine .step (.step (.init deployment) reg) (.local ?_)
  refine ⟨11, .rotate 1 .keep 6, 3, { hunter := some { addr := 6, pool := 1 } },
    .present rotatedLive, ?_, ?_, ?_, rfl⟩
  · intro refund pool equal
    cases equal
  · exact Step.rotateKeepPaid 3 1 6 (by decide) (by decide) (by decide)
  · exact ⟨rfl, by decide⟩

/-- Registration and advance reach a writer with nested signing and next
thresholds. Its seal-only sibling binds to that live input and passes both
comparison gates in the environment of the same execution. -/
theorem reachable_nested_writer_accepts_sibling :
    SysReach p environment state ∧ state.writers 11 = some history ∧
    comparison.tip.keys.curThreshold = threshold ∧ comparison.tip.keys.nextThreshold = threshold ∧
    Duplicity.duplicityAt 1 1 ⟨1, origin.inception.predecessor, writer 11 1⟩ sibling = true ∧
    state.comparisonMatchesWriter (environment 11) 11 = true ∧
    (environment 11).acceptsRival 1 1 = true := by
  have gates := presented_conflict_passes_system_comparison (aid := 11) (live := rotatedLive)
    (previous := origin.inception) (writer := writer 11 1) (rival := sibling)
    reachable rfl rfl (by decide) rfl (by decide) KeyEncoding.symbolic ⟨105, 0⟩ rfl rfl
  exact ⟨reachable, rfl, rfl, rfl, by decide, gates⟩

end NestedWriter
end CardanoKeri.Checkpoint.Examples
