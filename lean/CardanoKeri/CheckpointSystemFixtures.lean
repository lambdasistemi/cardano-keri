import CardanoKeri.CheckpointSystemWire

/-! Connected certificate journeys. Transaction assemblers propose complete
observations; the certificate interpreter executes the actual model events.
The Checkpoint and Registry key representations remain separate abstractions. -/
namespace CardanoKeri.Checkpoint.SystemFixtures
open Lean (Json toJson)
open SystemWire TraceWire

def p : Params := { D := 8, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def evidence : EnvTable := {
  rotationTo := [(0, 0, 1), (1, 1, 2)]
  depositAuthorized := []
  quorum := []
  duplicityAt := [(0, 0), (1, 1), (2, 2)]
  writers := WriterTable.fixture 11 711 [(0, 0, 1), (1, 1, 2)] }
def byIdentifier : EvidenceTable := [(11, evidence)]

def registryEnvironment : Registry.TraceWire.EnvTable := {
  bookings := CardanoKeri.Attestation.Fixtures.bookingTransactions [⟨100, 0, 711, 19⟩, ⟨101, 0, 712, 14⟩]
  convictionTransactions := ([11, 12] : List Nat).map (fun aid =>
    ⟨⟨105 + (aid - 11), 0⟩, CardanoKeri.Attestation.Fixtures.convictionSpend ⟨103 + (aid - 11), 0⟩⟩)
  convictions := [CardanoKeri.Registry.Scenarios.convictionFixture 11 2 2, CardanoKeri.Registry.Scenarios.convictionFixture 12 1 1] }
def context : RegistryContext := ⟨Registry.Scenarios.p, registryEnvironment, Registry.Scenarios.cfg⟩
/-- The deployment the journeys run in. -/
def deployment : Deployment := 21

def applyRegistry (s : Registry.Sys) (a : Registry.Action) : Except String Registry.Sys := do
  let (_, next) ← Registry.stepFn Registry.Scenarios.p registryEnvironment.toEnv a s
  pure next

def registrationCommand (ctx : RegistryContext := context) : Except String Command := do
  let initial := Registry.Sys.init ctx.configuration
  let b := Registry.Scenarios.registration initial 11 100 5
  let before ← Registry.replay ctx.parameters ctx.environment.toEnv initial [.bookRegistration b]
  let (u, tx) ← Registry.Scenarios.foldTransaction before [⟨100, 0⟩] 2 1 1
  pure (.register 11 1 42 5 ctx ⟨[.bookRegistration b], u, tx⟩ b 1)

def rotatedCommand : Command := .local 11 3 (.rotate 1 .keep 7)
def rotatedAgainCommand : Command := .local 11 4 (.rotate 2 .keep 7)
/-- The live output of AID 11 after the two rotations of the journey. -/
def rotatedAgainLive : Live := ⟨2, 2, false, false, 1, 42, 3, false⟩
/-- The convictor's commitment: it names AID 11, this deployment, the key state of
that output and the evidence at it,
naming payee 7: opened by a transaction whose validity range ends at slot 4,
eligible from slot 5, expiring at slot 20. -/
def commitment : Commitment := {
  aid := 11, deployment := deployment, keyState := rotatedAgainLive.hash,
  evidence := (CardanoKeri.CheckpointConviction.Fixtures.comparison 11 2 2).rival,
  payee := 7, openedAt := 4, eligibleAfter := 5, expiresAt := 20, marker := 1 }
/-- Another deployment, holding a checkpoint for the same AID. -/
def otherDeployment : Deployment := 22
/-- The same commitment made for the other deployment, under its own marker. -/
def foreignCommitment : Commitment := { commitment with deployment := otherDeployment, marker := 2 }
/-- A commitment opened one rotation earlier, while the checkpoint carries key state
(1, 1): its opening transaction's validity range ends at slot 3. -/
def earlierCommitment : Commitment := { commitment with
  keyState := ⟨1, 1⟩, evidence := (CardanoKeri.CheckpointConviction.Fixtures.comparison 11 1 1).rival,
  openedAt := 3, eligibleAfter := 4, marker := 2 }
def openCommand : Command := .openCommitment commitment
def convictedCommand : Command := .local 11 5 (.convict 7 commitment)
def registryLocalHistory : List Registry.Action := [.convictCkpt 11]

def advance (machine : Machine) (command : Command) : Except String Machine := do
  let (next, _, _) ← execute machine p (evidenceFor byIdentifier) command
  pure next

def bookingCommand (registered : Registry.Sys) : Except String Command := do
  let before ← Registry.replay Registry.Scenarios.p registryEnvironment.toEnv registered registryLocalHistory
  let booking ← Registry.Scenarios.termination before 11 200
  pure (.book 11 7 1 registryLocalHistory booking)

def completionCommand (booked : Registry.Sys) (history : List Registry.Action := [])
    (refs : List Singular.OutRef := [⟨200, 0⟩]) : Except String Command := do
  let before ← Registry.replay Registry.Scenarios.p registryEnvironment.toEnv booked history
  let (u, tx) ← Registry.Scenarios.foldTransaction before refs 2 1 1
  pure (.complete 11 ⟨history, u, tx⟩)

structure Fixture where
  registration : Command
  registered : Machine
  pending : Machine
  booking : Command
  booked : Machine
  completion : Command
  otherHistory : List Registry.Action
  otherCompletion : Command
  mixedCompletion : Command

def fixture : Except String Fixture := do
  let registration ← registrationCommand
  let registered ← advance (Machine.init deployment) registration
  let rotated ← advance registered rotatedCommand
  let rotatedAgain ← advance rotated rotatedAgainCommand
  unless decide (rotatedAgain.certified.state.states 11 = .present rotatedAgainLive) do
    throw "fixture-rotated-output-differs"
  let committed ← advance rotatedAgain openCommand
  let pending ← advance committed convictedCommand
  let some origin := registered.certified.state.origins 11 | throw "fixture-origin-missing"
  let booking ← bookingCommand origin.registered
  let booked ← advance pending booking
  let some association := booked.certified.state.pending 11 | throw "fixture-association-missing"
  let completion ← completionCommand association.booked
  let b := Registry.Scenarios.registration association.booked 12 101
  let otherRegistered ← applyRegistry association.booked (.bookRegistration b)
  let (u, tx) ← Registry.Scenarios.foldTransaction otherRegistered [⟨101, 0⟩] 2 1 1
  let foldAction : Registry.Action := .fold otherRegistered.gen Registry.Scenarios.cfg.applicationPolicy u tx
  let otherLive ← applyRegistry otherRegistered foldAction
  let otherPending ← applyRegistry otherLive (.convictCkpt 12)
  let otherBooking ← Registry.Scenarios.termination otherPending 12 201
  let otherHistory := [.bookRegistration b, foldAction, .convictCkpt 12, .bookTermination 12 7 1 otherBooking]
  let otherCompletion ← completionCommand association.booked otherHistory [⟨201, 0⟩]
  let mixedCompletion ← completionCommand association.booked otherHistory [⟨200, 0⟩, ⟨201, 0⟩]
  pure {
    registration, registered, pending, booking, booked, completion,
    otherHistory, otherCompletion, mixedCompletion }

def trace (name : String) (commands : List (String × Command)) (d : Deployment := deployment) (table : EvidenceTable := byIdentifier) : Json :=
  let (cells, final) := commands.foldl (fun (cells, current) (name, command) =>
    let (result, next) := cell name p table current command
    (cells ++ [result], next)) ([], (Machine.init d))
  Json.mkObj [("name", toJson name), ("deployment", toJson d), ("initial", stateJson (Machine.init d)),
    ("cells", toJson cells), ("final", stateJson final)]

/-- Two identifiers in a single fold of the same registry. The certificates point
to different holdings of that transaction. Both are at epoch and sequence zero. -/
def authorizationTrace : Except String Json := do
  let context := {context with environment.bookings := CardanoKeri.Attestation.Fixtures.bookingTransactions [⟨100, 0, 711, 19⟩, ⟨101, 0, 712, 19⟩]}
  let initial := Registry.Sys.init context.configuration
  let first := Registry.Scenarios.registration initial 11 100 5
  let second := Registry.Scenarios.registration initial 12 101 5
  let history := [Registry.Action.bookRegistration first, .bookRegistration second]
  let booked ← Registry.replay context.parameters context.environment.toEnv initial history
  let (u, tx) ← Registry.Scenarios.foldTransaction booked
    [first.request.reference, second.request.reference] 2 1 1
  let register := fun (b : Singular.RegistrationBooking) => do
    let some index := tx.outputs.findIdx? (fun o =>
      o.singularTags == [booked.config.singularTag b.request.key]) | throw "missing registered holding"
    pure (Command.register b.request.key 1 42 5 context ⟨history, u, tx⟩ b index)
  let a ← register first
  let b ← register second
  -- Both candidate events for 12 are available. Only its first target has
  -- a rotation authorization, so the foreign row is the sole changed guard.
  let table : EvidenceTable := [
    (11, ⟨[(0,0,1), (0,0,2)], [1], [0], [], WriterTable.fixture 11 711 [(0,0,1), (0,0,2)]⟩),
    (12, ⟨[(0,0,1)], [], [], [], WriterTable.fixture 12 712 [(0,0,1), (0,0,2)]⟩)]
  pure (trace "identity-bound-authorizations" [
    ("register-first", a), ("register-second", b),
    ("foreign-rotation-refused", .local 12 3 (.rotate 2 .keep 7)),
    ("foreign-poison-refused", .local 12 3 .poison),
    ("foreign-deposit-refused-with-own-rotation", .local 12 3 (.rotate 1 .deposit 7)),
    ("own-poison", .local 11 3 .poison),
    ("own-deposit", .local 11 4 (.rotate 1 .deposit 7)),
    ("own-keep", .local 12 4 (.rotate 1 .keep 7))] (table := table))

def traces : Except String (List Json) := do
  let f ← fixture
  let journey := [("register", f.registration), ("rotate", rotatedCommand),
    ("rotate-again", rotatedAgainCommand), ("open-commitment", openCommand),
    ("convict", convictedCommand), ("book", f.booking)]
  let restricted ← registrationCommand { context with environment.convictions := [] }
  let row := Registry.Scenarios.convictionFixture 11 2 2
  let different := {row.comparison.rival.event with nextKeys := [888]}
  let otherRival := {row with comparison.rival := Duplicity.signed different [11] []}
  let rivalOrigin ← registrationCommand {context with environment.convictions := [otherRival]}
  let otherOutput := {row with output.index := row.output.index + 1}
  let outputOrigin ← registrationCommand {context with environment.convictions := [otherOutput]}
  let .book subject booker fee history booking := f.booking | throw "termination booking required"
  let otherBooking := Command.book subject booker fee history {booking with pendingReference := otherOutput.output}
  let sharedPrefix := [("rotate", rotatedCommand), ("rotate-again", rotatedAgainCommand),
    ("open-commitment", openCommand), ("convict", convictedCommand)]
  let .register aid now refund pool ctx cert b index := f.registration | throw "registration fixture required"
  let registration := fun t r v => Command.register aid t r v ctx cert b index
  let authorizations ← authorizationTrace
  pure [
    trace "retained-associated-completion" (journey ++ [
      ("pending-refuses-local-rotation", .local 11 6 (.rotate 3 .keep 7)), ("complete", f.completion),
      ("repeat-completion-refused", f.completion), ("retired-registration-refused", f.registration)]),
    trace "booking-compares-the-earlier-rival" ([("register", rivalOrigin)] ++ sharedPrefix ++
      [("different-economic-rival-refused", f.booking)]),
    trace "booking-compares-the-producing-outpoint" ([("register", outputOrigin)] ++ sharedPrefix ++
      [("different-economic-output-refused", otherBooking)]),
    trace "same-context-other-request" (journey ++ [
      ("other-valid-fold-cannot-complete-this-request", f.otherCompletion),
      ("mixed-fold-completes-own-request", f.mixedCompletion)]),
    trace "stored-origin-environment" [
      ("register-without-registry-duplicity", restricted), ("rotate", rotatedCommand),
      ("rotate-again", rotatedAgainCommand), ("open-commitment", openCommand),
      ("checkpoint-concrete-conviction", convictedCommand),
      ("booking-history-cannot-replace-stored-environment", f.booking)],
    trace "system-premises" [
      ("bare-registration-is-not-a-system-registration", .local 11 2 (.register 42 5)),
      ("completion-needs-association", f.completion), ("register", f.registration),
      ("duplicate-origin-refused", f.registration), ("book-live-refused", f.booking),
      ("rotate", rotatedCommand), ("rotate-again", rotatedAgainCommand),
      ("book-rotated-live-refused", f.booking),
      ("convict-without-open-commitment-refused", convictedCommand),
      ("open-commitment", openCommand), ("reopen-same-marker-refused", openCommand),
      ("convict", convictedCommand), ("reveal-after-conviction-refused", .reveal 1 6),
      ("book", f.booking),
      ("rebook-refused", f.booking), ("complete", f.completion)],
    trace "commitment-follows-the-key-state" [
      ("register", f.registration), ("rotate", rotatedCommand),
      ("open-commitment-before-the-rotation", .openCommitment earlierCommitment),
      ("rotate-again", rotatedAgainCommand),
      ("convict-with-the-earlier-commitment-refused", .local 11 5 (.convict 7 earlierCommitment)),
      ("open-commitment", openCommand), ("top-up", .local 11 5 (.topUp 1)),
      ("convict-after-the-top-up", convictedCommand)],
    trace "another-deployment" (d := otherDeployment) [
      ("register", f.registration), ("rotate", rotatedCommand), ("rotate-again", rotatedAgainCommand),
      ("open-commitment", openCommand),
      ("convict-with-the-other-deployment-commitment-refused", convictedCommand),
      ("open-commitment-for-this-deployment", .openCommitment foreignCommitment),
      ("convict", .local 11 5 (.convict 7 foreignCommitment))],
    trace "registered-booking-facts" [
      ("different-birth-refused", registration (now+1) refund pool),
      ("different-refund-refused", registration now (refund+1) pool),
      ("different-pool-refused", registration now refund (pool+1)),
      ("booked-facts-accepted", f.registration)],
    authorizations ]

end CardanoKeri.Checkpoint.SystemFixtures
