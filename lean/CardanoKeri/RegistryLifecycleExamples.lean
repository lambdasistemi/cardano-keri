import CardanoKeri.Registry
/-! Connected economic registration, retained parking and termination witnesses.
W1-W5 cover the connected lifecycle; N1 excludes phantom alias bindings. -/
namespace CardanoKeri.Registry.Examples
set_option maxRecDepth 10000
set_option maxHeartbeats 2000000
def p : Params := {
  D := 10, tip := 1, Mc := 4, Mr := 2,
  hD := by decide, hFund := by decide }
def cfg : Singular.Config := {
  root := Singular.rootOf [], minimumTip := 1,
  processTime := 5, retractTime := 5, applicationPolicy := 7, activePolicy := 8,
  registryId := 9, registrationCost := 2, bookingWidth := 1 }
def env : Env := {
  inception := fun _ => true,
  closeAuth := fun aid recipient => aid == 11 && recipient == 6,
  rotationFrom := fun aid k => aid == 11 && k == 1,
  duplicity := fun _ _ => true }
def parkedCarrier : Carrier := {
  aid := 11, token := 0,
  original := ⟨11, .active, 111, some 777⟩, k := 1, st := .parked, minAda := 4 }
def ParkingJourney (registered parked : Sys) : Prop :=
  ∃ (b : Singular.RegistrationBooking) (booked : Sys)
    (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction)
    (f0 f1 f2 : Flow),
    b.request.key = 11 ∧ b.request.destination = 111 ∧ b.request.datum = some 777 ∧
    b.request.reference = ⟨100, 0⟩ ∧ b.request.contents.lovelace = 17 ∧
    bookRegistration p (Sys.init cfg) b = .ok (f0, booked) ∧
    fold p env booked 0 cfg.applicationPolicy u tx = .ok (f1, registered) ∧
    park p env registered 11 6 = .ok (f2, parked)
def registrationTag : Singular.Approval :=
  { policy := cfg.applicationPolicy, edge := .insertActive, key := 11,
    owner := 42, destination := 111,
    assetName := Singular.applicationTagAssetName 11 42 111 0 }
def registrationRequest : Singular.RegistrationRequest :=
  let bare : Singular.RegistrationRequest := {
    reference := ⟨100, 0⟩, registryId := cfg.registryId, key := 11,
    refundAddress := 42, destination := 111, submittedAt := 1,
    registrationCost := 2, declaredTip := 1, carrierAda := 14, datum := some 777,
    contents := { lovelace := 17, applicationTags := [registrationTag], trieReadyTags := [] } }
  { bare with contents := { bare.contents with trieReadyTags := [bare.trieReadyTag cfg] } }
def registration : Singular.RegistrationBooking := {
  request := registrationRequest, interval := ⟨0, 1⟩,
  trieReadyTagsMinted := registrationRequest.contents.trieReadyTags,
  applicationTagsMinted := [registrationTag] }
def registrationBooked : Sys := { Sys.init cfg with registrations := [registration] }
def liveCarrier : Carrier := { parkedCarrier with k := 0, st := .live }
def registered : Sys := {
  Sys.init cfg with
  gen := 1,
  config := { cfg with root := Singular.rootOf [(11, .known .active)] },
  trie := [(11, .known .active)], carriers := [liveCarrier],
  bindings := [(11, 0)], nextToken := 1, treasury := 2 }
def parked : Sys := { registered with carriers := [parkedCarrier] }
def revived : Sys := { parked with carriers := [{ parkedCarrier with k := 2, st := .live }] }
def pending : Sys := { parked with carriers := [{ parkedCarrier with st := .terminationPending }] }
def registrationUnspent : Singular.EconomicUtxo :=
  [(registrationRequest.reference, Singular.registrationWitnessOutput registration),
   (⟨101, 0⟩, Singular.foldWitnessState cfg),
   (⟨101, 1⟩, Singular.foldWitnessOrdinary 1)]
def carrierOutput : Singular.EconomicOutput := {
  Singular.foldWitnessOrdinary 14 with
  output := { (Singular.foldWitnessOrdinary 14).output with
    address := some 111, datum := .inline, datumValue := some 777 },
  singularTags := [cfg.singularTag 11] }
def registrationTransaction : Singular.EconomicTransaction :=
  let outputs := [Singular.foldWitnessState registered.config,
    carrierOutput, Singular.foldWitnessOrdinary 1]
  { identity := 102, outputs := outputs,
    transaction := {
      inputs := [Singular.foldWitnessInput ⟨100, 0⟩,
        Singular.foldWitnessInput ⟨101, 0⟩, Singular.foldWitnessInput ⟨101, 1⟩],
      outputs := outputs.map (·.output), mint := [], signers := [], refunds := [],
      validity := some ⟨2, 3⟩, fee := 1, donation := 2 },
    trieReadyMint := registrationRequest.contents.trieReadyTags.map (fun tag => (tag, -1)),
    applicationMint := [(⟨registrationTag.policy, registrationTag.assetName⟩, -1)],
    singularMint := [(cfg.singularTag 11, 1)] }
def terminationRequest : Singular.TerminationRequest :=
  let bare : Singular.TerminationRequest := {
    reference := ⟨200, 0⟩, registryId := cfg.registryId, key := 11, destination := 111,
    declaredTip := 1, carrierAda := 2, singularTags := [cfg.singularTag 11],
    contents := { lovelace := 3, trieReadyTags := [], applicationTags := [] } }
  { bare with contents := { bare.contents with trieReadyTags := [bare.trieReadyTag cfg] } }
def termination : Singular.TerminationBooking := {
  request := terminationRequest, custodyInputs := [parkedCarrier.original],
  trieReadyTagsMinted := terminationRequest.contents.trieReadyTags }
def terminationEntry : TerminationEntry := {
  booking := termination, payload := {
    aid := 11, token := 0, keyState := 1, original := parkedCarrier.original,
    booker := 7, bookingFee := 1 } }
def terminationBooked : Sys := {
  pending with carriers := [], terminations := [terminationEntry] }
def terminationUnspent : Singular.EconomicUtxo :=
  Singular.terminationWitnessUnspent terminationBooked.toWorld 1
def terminationTransaction : Singular.EconomicTransaction :=
  Singular.terminationWitnessTransaction terminationBooked.toWorld termination 20 1 1
def retired : Sys := {
  terminationBooked with
  gen := 2,
  config := { cfg with root := Singular.rootOf [(11, .known .terminal)] },
  trie := [(11, .known .terminal)], terminations := [], treasury := 4 }
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

bookRegistration p (Sys.init cfg) registration =
      .ok ({ deposited := 17 }, registrationBooked)
-/
theorem registration_booked :
    bookRegistration p (Sys.init cfg) registration =
      .ok ({ deposited := 17 }, registrationBooked) := by
  simp [bookRegistration, registrationShape, Singular.book,
    Singular.registrationBookingRefusal, Singular.registrationContentsShape,
    Singular.registrationApplicationTagValid, Singular.registrationDeclaredLovelace,
    registration, registrationRequest, registrationTag, cfg, p, Sys.init, Sys.toWorld,
    registrationBooked, Singular.Interval.valid, Singular.Interval.width,
    Singular.RegistrationRequest.trieReadyTag, Singular.RegistrationRequest.operation,
    bind, Except.bind, pure, Except.pure]
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

fold p env registrationBooked 0 cfg.applicationPolicy registrationUnspent registrationTransaction =
      .ok ({ locked := [(11, 10)] }, registered)
-/
theorem registration_folded :
    fold p env registrationBooked 0 cfg.applicationPolicy registrationUnspent registrationTransaction =
      .ok ({ locked := [(11, 10)] }, registered) := by
  simp +decide [
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
    Singular.applicationTagIdentity,
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
    registrationBooked,
    registration,
    registrationRequest,
    registrationTag,
    registrationTransaction,
    registrationUnspent,
    registered,
    liveCarrier,
    parkedCarrier,
    carrierOutput,
    cfg,
    p,
    Sys.init,
    Sys.toWorld,
    fold,
    foldResult,
    installMember,
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

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

park p env registered 11 6 = .ok ({ bondReturn := some (6, 10) }, parked)
-/
theorem parking_success :
    park p env registered 11 6 = .ok ({ bondReturn := some (6, 10) }, parked) := by rfl
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

revive p env parked 11 = .ok ({ deposited := 10, locked := [(11, 10)] }, revived)
-/
theorem revival_success :
    revive p env parked 11 = .ok ({ deposited := 10, locked := [(11, 10)] }, revived) := by rfl
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

convictCkpt env parked 11 = .ok ({}, pending)
-/
theorem conviction_success :
    convictCkpt env parked 11 = .ok ({}, pending) := by rfl
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

bookTermination p pending 11 7 1 termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, terminationBooked)
-/
theorem termination_booked :
    bookTermination p pending 11 7 1 termination =
      .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, terminationBooked) := by
  simp [bookTermination, carrierAt, pending, parked, registered, liveCarrier, parkedCarrier,
    termination, terminationRequest, terminationEntry, terminationBooked, p, cfg,
    Singular.bookTermination, Singular.terminationBookingRefusal, Singular.terminationContentsShape,
    Singular.terminationDeclaredLovelace, Singular.terminationCustody, Sys.toWorld, Sys.init,
    Singular.TerminationRequest.trieReadyTag, Singular.TerminationRequest.operation,
    Singular.Config.singularTag, Singular.Config.trieReadyTag,
    instBEqCkState, Singular.trieGet, bind, Except.bind, pure, Except.pure]
  rfl
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

fold p env terminationBooked 1 cfg.applicationPolicy terminationUnspent terminationTransaction =
      .ok ({}, retired)
-/
theorem termination_folded :
    fold p env terminationBooked 1 cfg.applicationPolicy terminationUnspent terminationTransaction =
      .ok ({}, retired) := by
  simp +decide [
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
    terminationBooked,
    terminationEntry,
    termination,
    terminationRequest,
    terminationTransaction,
    terminationUnspent,
    retired,
    pending,
    parked,
    pendingAt,
    Singular.terminationWitnessTransaction,
    Singular.terminationWitnessUnspent,
    Singular.terminationWitnessInputs,
    Singular.terminationWitnessFresh,
    Singular.worldRequestReferences,
    Singular.terminationWitnessResult,
    Singular.terminationWitnessOutput,
    registered,
    liveCarrier,
    parkedCarrier,
    cfg,
    p,
    Sys.init,
    Sys.toWorld,
    fold,
    foldResult,
    installMember,
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

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

ParkingJourney registered parked
-/
theorem parking_journey : ParkingJourney registered parked := by
  exact ⟨registration, registrationBooked, registrationUnspent, registrationTransaction,
    { deposited := 17 }, { locked := [(11, 10)] }, { bondReturn := some (6, 10) },
    rfl, rfl, rfl, rfl, rfl, registration_booked, registration_folded, parking_success⟩
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

Reach p env cfg registrationBooked
-/
theorem registration_booked_reachable : Reach p env cfg registrationBooked :=
  Reach.next Reach.init (action := .bookRegistration registration) registration_booked
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

Reach p env cfg registered
-/
theorem registered_reachable : Reach p env cfg registered :=
  Reach.next registration_booked_reachable
    (action := .fold 0 cfg.applicationPolicy registrationUnspent registrationTransaction) registration_folded
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

Reach p env cfg parked
-/
theorem parked_reachable : Reach p env cfg parked :=
  Reach.next registered_reachable (action := .park 11 6) parking_success
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

Reach p env cfg pending
-/
theorem pending_reachable : Reach p env cfg pending :=
  Reach.next parked_reachable (action := .convictCkpt 11) conviction_success
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

Reach p env cfg terminationBooked
-/
theorem termination_booked_reachable : Reach p env cfg terminationBooked :=
  Reach.next pending_reachable (action := .bookTermination 11 7 1 termination) termination_booked
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

Reach p env cfg retired
-/
theorem retired_reachable : Reach p env cfg retired :=
  Reach.next termination_booked_reachable
    (action := .fold 1 cfg.applicationPolicy terminationUnspent terminationTransaction) termination_folded
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

∃ registered parked, ParkingJourney registered parked ∧
      Reach p env cfg registered ∧ Reach p env cfg parked ∧
      carrierAt parked 11 = some parkedCarrier ∧ minAdaAt parked 11 = 4 ∧
      Singular.trieGet parked.trie 11 = .known .active ∧
      parked.toWorld = registered.toWorld ∧
      parked.terminations = [] ∧
      park p env registered 11 6 = .ok ({ bondReturn := some (6, 10) }, parked)
-/
theorem W1_connected_parking :
    ∃ registered parked, ParkingJourney registered parked ∧
      Reach p env cfg registered ∧ Reach p env cfg parked ∧
      carrierAt parked 11 = some parkedCarrier ∧ minAdaAt parked 11 = 4 ∧
      Singular.trieGet parked.trie 11 = .known .active ∧
      parked.toWorld = registered.toWorld ∧
      parked.terminations = [] ∧
      park p env registered 11 6 = .ok ({ bondReturn := some (6, 10) }, parked) := by
  refine ⟨registered, parked, parking_journey, registered_reachable, parked_reachable, ?_⟩
  exact ⟨rfl, rfl, rfl, rfl, rfl, parking_success⟩
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

∃ registered parked revived, ParkingJourney registered parked ∧
      revive p env parked 11 = .ok ({ deposited := 10, locked := [(11, 10)] }, revived) ∧
      carrierAt revived 11 = some { parkedCarrier with k := 2, st := .live } ∧
      minAdaAt revived 11 = 4 ∧ revived.toWorld = parked.toWorld ∧
      revived.bindings = parked.bindings ∧ revived.nextToken = parked.nextToken
-/
theorem W2_connected_revival :
    ∃ registered parked revived, ParkingJourney registered parked ∧
      revive p env parked 11 = .ok ({ deposited := 10, locked := [(11, 10)] }, revived) ∧
      carrierAt revived 11 = some { parkedCarrier with k := 2, st := .live } ∧
      minAdaAt revived 11 = 4 ∧ revived.toWorld = parked.toWorld ∧
      revived.bindings = parked.bindings ∧ revived.nextToken = parked.nextToken := by
  refine ⟨registered, parked, revived, parking_journey, revival_success, ?_⟩
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

∃ registered parked, ParkingJourney registered parked ∧
      revive p { env with rotationFrom := fun _ _ => false } parked 11 =
        .error "keri-revival-refused" ∧
      carrierAt parked 11 = some parkedCarrier ∧ minAdaAt parked 11 = 4 ∧
      Singular.trieGet parked.trie 11 = .known .active
-/
theorem W3_refused_revival_keeps_output :
    ∃ registered parked, ParkingJourney registered parked ∧
      revive p { env with rotationFrom := fun _ _ => false } parked 11 =
        .error "keri-revival-refused" ∧
      carrierAt parked 11 = some parkedCarrier ∧ minAdaAt parked 11 = 4 ∧
      Singular.trieGet parked.trie 11 = .known .active := by
  refine ⟨registered, parked, parking_journey, ?_⟩
  exact ⟨rfl, rfl, rfl, rfl⟩
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

∃ registered parked, ParkingJourney registered parked ∧
      park p env registered 11 7 = .error "keri-close-refused" ∧
      park p { env with closeAuth := fun _ _ => false } registered 11 6 =
        .error "keri-close-refused"
-/
theorem W4_wrong_recipient_and_missing_premise :
    ∃ registered parked, ParkingJourney registered parked ∧
      park p env registered 11 7 = .error "keri-close-refused" ∧
      park p { env with closeAuth := fun _ _ => false } registered 11 6 =
        .error "keri-close-refused" := by
  refine ⟨registered, parked, parking_journey, ?_⟩
  exact ⟨rfl, rfl⟩
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

∃ registered parked pending booked retired,
      ∃ (b : Singular.TerminationBooking) (u : Singular.EconomicUtxo)
        (tx : Singular.EconomicTransaction) (f : Flow),
      ParkingJourney registered parked ∧
      convictCkpt env parked 11 = .ok ({}, pending) ∧
      carrierAt pending 11 = some { parkedCarrier with st := .terminationPending } ∧
      Singular.trieGet pending.trie 11 = .known .active ∧
      b.request.reference = ⟨200, 0⟩ ∧
      bookTermination p pending 11 7 1 b =
        .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, booked) ∧
      Singular.worldSingularSupply booked.toWorld 11 = 1 ∧
      fold p env booked booked.gen cfg.applicationPolicy u tx = .ok (f, retired) ∧
      Singular.trieGet retired.trie 11 = .known .terminal ∧
      Singular.worldSingularSupply retired.toWorld 11 = 0 ∧
      tx.transaction.donation = 2 ∧ Singular.foldCarrierLovelace tx.outputs = 0 ∧
      pendingAt retired ⟨200, 0⟩ = none
-/
theorem W5_connected_termination :
    ∃ registered parked pending booked retired,
      ∃ (b : Singular.TerminationBooking) (u : Singular.EconomicUtxo)
        (tx : Singular.EconomicTransaction) (f : Flow),
      ParkingJourney registered parked ∧
      convictCkpt env parked 11 = .ok ({}, pending) ∧
      carrierAt pending 11 = some { parkedCarrier with st := .terminationPending } ∧
      Singular.trieGet pending.trie 11 = .known .active ∧
      b.request.reference = ⟨200, 0⟩ ∧
      bookTermination p pending 11 7 1 b =
        .ok ({ premium := some (7, 1), intoRequest := 3, bookingFee := 1 }, booked) ∧
      Singular.worldSingularSupply booked.toWorld 11 = 1 ∧
      fold p env booked booked.gen cfg.applicationPolicy u tx = .ok (f, retired) ∧
      Singular.trieGet retired.trie 11 = .known .terminal ∧
      Singular.worldSingularSupply retired.toWorld 11 = 0 ∧
      tx.transaction.donation = 2 ∧ Singular.foldCarrierLovelace tx.outputs = 0 ∧
      pendingAt retired ⟨200, 0⟩ = none := by
  refine ⟨registered, parked, pending, terminationBooked, retired, termination,
    terminationUnspent, terminationTransaction, {}, parking_journey, conviction_success, ?_⟩
  exact ⟨by decide, by decide, rfl, termination_booked, by decide,
    termination_folded, by decide, by decide, by decide, by decide, by decide⟩
/-- Given the complete parameters and hypotheses:

No additional local parameters; use the definitions in this module.

When observe the Registry transition, projection or custody relation named by this theorem.
Then the complete conclusion is:

¬ WellFormed p { Sys.init cfg with bindings := [(11, 0)], nextToken := 1 }
-/
theorem phantom_binding_not_wellFormed :
    ¬ WellFormed p { Sys.init cfg with bindings := [(11, 0)], nextToken := 1 } := by
  intro h
  have leaf := (h.bindingDomain 11).mp ⟨0, rfl⟩
  simp [Sys.init, Singular.trieGet] at leaf
end CardanoKeri.Registry.Examples
