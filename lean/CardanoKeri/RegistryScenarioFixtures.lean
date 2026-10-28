import CardanoKeri.Registry
import Singular.Lemmas.RetractionWitness

/-! Transaction fixtures for executable registry journeys.
These assemble model transactions; the imported judgments decide acceptance.
Every successful journey step carries its actual reachability derivation.
No fixture represents a wallet transaction or production implementation. -/
namespace CardanoKeri.Registry.Scenarios

def p : Params := {
  D := 10, tip := 1, Mc := 4, Mr := 2,
  hD := by decide, hFund := by decide }
def cfg : Singular.Config := {
  root := Singular.rootOf [], minimumTip := 1,
  processTime := 5, retractTime := 5, applicationPolicy := 7, activePolicy := 8,
  registryId := 9, registrationCost := 2, bookingWidth := 1 }
def env : Env := {
  inception := fun _ => true
  rotationFrom := fun _ k => k == 1
  duplicity := fun _ _ => true
  closeAuth := fun _ recipient => recipient == 6 }

structure Reached where
  state : Sys
  proof : Reach p env cfg state

def start : Reached := ⟨Sys.init cfg, .init⟩

def execute (before : Reached) (action : Action) : Except String (Flow × Reached) :=
  match h : stepFn p env action before.state with
  | .error reason => .error reason
  | .ok (flow, after) => .ok (flow, ⟨after, .next before.proof h⟩)

def registration (s : Sys) (aid reference : Nat) : Singular.RegistrationBooking :=
  let tag : Singular.Approval := {
    policy := s.config.applicationPolicy, edge := .insertActive, key := aid,
    owner := 42, destination := aid + 100,
    assetName := Singular.applicationTagAssetName aid 42 (aid + 100) 0 }
  let bare : Singular.RegistrationRequest := {
    reference := ⟨reference, 0⟩, registryId := s.config.registryId, key := aid,
    refundAddress := 42, destination := aid + 100, submittedAt := 1,
    registrationCost := s.config.registrationCost, declaredTip := p.tip,
    carrierAda := p.Mc + p.D, datum := some (aid + 700),
    contents := {
      lovelace := p.Mc + p.D + p.tip + s.config.registrationCost,
      applicationTags := [tag], trieReadyTags := [] } }
  let request := { bare with contents.trieReadyTags := [bare.trieReadyTag s.config] }
  { request, interval := ⟨0, 1⟩,
    trieReadyTagsMinted := request.contents.trieReadyTags,
    applicationTagsMinted := [tag] }

def termination (s : Sys) (aid reference : Nat) : Except String Singular.TerminationBooking := do
  let some carrier := carrierAt s aid | throw "fixture-carrier-missing"
  let bare : Singular.TerminationRequest := {
    reference := ⟨reference, 0⟩, registryId := s.config.registryId, key := aid,
    destination := carrier.original.output, declaredTip := p.tip,
    carrierAda := p.Mr, singularTags := [s.config.singularTag aid],
    contents := { lovelace := p.Mr + p.tip, trieReadyTags := [], applicationTags := [] } }
  let request := { bare with contents.trieReadyTags := [bare.trieReadyTag s.config] }
  pure {
    request, custodyInputs := [carrier.original],
    trieReadyTagsMinted := request.contents.trieReadyTags }

/-- Build a finite mixed batch with explicit ordinary funding and fee.
The structural result supplies the proposed root; actual economic execution
still checks observation, routing, tags, timing, authorization and balances. -/
def foldTransaction (s : Sys) (references : List Singular.OutRef)
    (time funding fee : Nat) : Except String (Singular.EconomicUtxo × Singular.EconomicTransaction) := do
  let world := s.toWorld
  let fresh := Singular.terminationWitnessFresh world
  let members ← references.mapM fun ref => match Singular.foldMemberAt world ref with
    | some member => Except.ok member
    | none => Except.error "fixture-request-missing"
  let result ← Singular.foldBatch (Singular.foldProjectedRegistry world)
    (members.map (Singular.foldLegacyRequest s.config))
  let carrierOutputs := members.filterMap fun member => match member with
    | .termination _ => none
    | .registration b => some {
        Singular.foldWitnessOrdinary b.request.carrierAda with
        output := { (Singular.foldWitnessOrdinary b.request.carrierAda).output with
          address := some b.request.destination, datum := Singular.datumFormOf b.request.datum,
          datumValue := b.request.datum }
        singularTags := [s.config.singularTag b.request.key] }
  let obligations := Singular.foldObligations members
  let outputs := [Singular.foldWitnessState result.state.config] ++ carrierOutputs ++
    [Singular.foldWitnessOrdinary (funding + obligations.tips - fee)]
  let ready := members.flatMap fun member => match member with
    | .registration b => b.request.contents.trieReadyTags
    | .termination b => b.request.contents.trieReadyTags
  let application := members.flatMap fun member => match member with
    | .registration b => b.request.contents.applicationTags
    | .termination _ => []
  let transaction : Singular.EconomicTransaction := {
    identity := fresh + 1, outputs,
    transaction := {
      inputs := (references ++ [Singular.OutRef.mk fresh 0, Singular.OutRef.mk fresh 1]).map Singular.foldWitnessInput,
      outputs := outputs.map (·.output), mint := [], signers := [], refunds := [],
      validity := some ⟨time, time + 1⟩, fee, donation := obligations.donation }
    trieReadyMint := ready.map (fun tag => (tag, -1)),
    applicationMint := application.map (fun tag => (Singular.applicationTagIdentity tag, -1)),
    singularMint := Singular.foldMint s.config members }
  pure (Singular.terminationWitnessUnspent world funding, transaction)

end CardanoKeri.Registry.Scenarios
