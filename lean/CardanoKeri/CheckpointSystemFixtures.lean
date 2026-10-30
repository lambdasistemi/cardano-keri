import CardanoKeri.CheckpointSystemWire

/-! Connected certificate journeys. Transaction assemblers propose complete
observations; the certificate interpreter executes the actual model events.
The Checkpoint and Registry key representations remain separate abstractions. -/
namespace CardanoKeri.Checkpoint.SystemFixtures
open Lean (Json toJson)
open SystemWire TraceWire

def p : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def evidence : EnvTable := {
  rotationTo := [(0, 0, 1), (1, 1, 2)]
  intentAuthorized := []
  quorum := []
  duplicityAt := [(0, 0), (1, 1), (2, 2)] }
def registryEnvironment : Registry.TraceWire.EnvTable := {
  inception := [11, 12, 13]
  duplicity := [(11, 0), (11, 1), (11, 2), (12, 0)] }
def context : RegistryContext := ⟨Registry.Scenarios.p, registryEnvironment, Registry.Scenarios.cfg⟩

def applyRegistry (s : Registry.Sys) (a : Registry.Action) : Except String Registry.Sys := do
  let (_, next) ← Registry.stepFn Registry.Scenarios.p registryEnvironment.toEnv a s
  pure next

def registrationCommand (ctx : RegistryContext := context) : Except String Command := do
  let initial := Registry.Sys.init ctx.configuration
  let b := Registry.Scenarios.registration initial 11 100
  let before ← Registry.replay ctx.parameters ctx.environment.toEnv initial [.bookRegistration b]
  let (u, tx) ← Registry.Scenarios.foldTransaction before [⟨100, 0⟩] 2 1 1
  pure (.register 11 2 42 5 ctx ⟨[.bookRegistration b], u, tx⟩ b 1)

def rotatedCommand : Command := .local 11 3 (.rotate 1 .keep 7 none)
def rotatedAgainCommand : Command := .local 11 4 (.rotate 2 .keep 7 none)
def convictedCommand : Command := .local 11 5 (.convict 7)
def registryLocalHistory : List Registry.Action := [.convictCkpt 11]

def advance (machine : Machine) (command : Command) : Except String Machine := do
  let (next, _, _) ← execute machine p evidence.toEnv command
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
  let registered ← advance Machine.init registration
  let rotated ← advance registered rotatedCommand
  let rotatedAgain ← advance rotated rotatedAgainCommand
  let pending ← advance rotatedAgain convictedCommand
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

def trace (name : String) (commands : List (String × Command)) : Json :=
  let (cells, final) := commands.foldl (fun (cells, current) (name, command) =>
    let (result, next) := cell name p evidence current command
    (cells ++ [result], next)) ([], Machine.init)
  Json.mkObj [("name", toJson name), ("initial", stateJson Machine.init),
    ("cells", toJson cells), ("final", stateJson final)]

def traces : Except String (List Json) := do
  let f ← fixture
  let journey := [("register", f.registration), ("rotate", rotatedCommand),
    ("rotate-again", rotatedAgainCommand), ("convict", convictedCommand), ("book", f.booking)]
  let restricted ← registrationCommand { context with environment.duplicity := [] }
  pure [
    trace "retained-associated-completion" (journey ++ [
      ("pending-refuses-local-rotation", .local 11 6 (.rotate 3 .keep 7 none)), ("complete", f.completion),
      ("repeat-completion-refused", f.completion), ("retired-registration-refused", f.registration)]),
    trace "same-context-other-request" (journey ++ [
      ("other-valid-fold-cannot-complete-this-request", f.otherCompletion),
      ("mixed-fold-completes-own-request", f.mixedCompletion)]),
    trace "stored-origin-environment" [
      ("register-without-registry-duplicity", restricted), ("rotate", rotatedCommand),
      ("rotate-again", rotatedAgainCommand), ("checkpoint-concrete-conviction", convictedCommand),
      ("booking-history-cannot-replace-stored-environment", f.booking)],
    trace "system-premises" [
      ("bare-registration-is-not-a-system-registration", .local 11 2 (.register 42 5)),
      ("completion-needs-association", f.completion), ("register", f.registration),
      ("duplicate-origin-refused", f.registration), ("book-live-refused", f.booking),
      ("rotate", rotatedCommand), ("rotate-again", rotatedAgainCommand),
      ("book-rotated-live-refused", f.booking),
      ("convict", convictedCommand), ("book", f.booking),
      ("rebook-refused", f.booking), ("complete", f.completion)] ]

end CardanoKeri.Checkpoint.SystemFixtures
