import CardanoKeri.RegistryTraceWire

/-! Semantic boundary corpus. Each row changes one complete input to the
actual stepFn. Successful neighbors are retained. Malformed transaction
observations are deliberate negative inputs, not reachable state claims. -/
open Lean CardanoKeri.Registry CardanoKeri.Registry.Scenarios CardanoKeri.Registry.TraceWire
namespace RegistryBoundary

def evidence : EnvTable := {
  inception := [11, 12, 13, 9007199254740993]
  rotationFrom := [(11, 1)]
  duplicity := [(11, 0), (11, 1), (12, 0)]
  closeAuth := [(11, 6)] }

def appendCell (s : Sys) (name : String) (action : Action) : Json := cell name p evidence s action

def syncOutputs (tx : Singular.EconomicTransaction) (f : Singular.EconomicOutput → Singular.EconomicOutput) : Singular.EconomicTransaction :=
  let outputs := tx.outputs.map f
  { tx with outputs := outputs, transaction.outputs := outputs.map (·.output) }

def bookingCells : List Json :=
  let s := Sys.init cfg
  let b := registration s 11 100
  [ ("registration-valid", b),
    ("registration-carrier", { b with request.carrierAda := 13 }),
    ("registration-tip", { b with request.declaredTip := 0 }),
    ("registration-cost", { b with request.registrationCost := 3 }),
    ("registration-value-low", { b with request.contents.lovelace := 16 }),
    ("registration-surplus", { b with request.contents.lovelace := 18 }),
    ("registration-wrong-registry", { b with request.registryId := 99 }),
    ("registration-application-policy", { b with
      request.contents.applicationTags := b.request.contents.applicationTags.map (fun tag => { tag with policy := 99 }) }),
    ("registration-application-name", { b with
      request.contents.applicationTags := b.request.contents.applicationTags.map (fun tag => { tag with assetName := 99 }) }),
    ("registration-application-missing", { b with request.contents.applicationTags := [] }),
    ("registration-tag-missing", { b with request.contents.trieReadyTags := [] }),
    ("registration-tag-mint", { b with trieReadyTagsMinted := [] }),
    ("registration-application-mint", { b with applicationTagsMinted := [] }),
    ("registration-empty-interval", { b with interval := ⟨1, 1⟩ }),
    ("registration-backdated", { b with request.submittedAt := 0 }),
    ("registration-too-wide", { b with interval := ⟨0, 2⟩, request.submittedAt := 2 }),
    ("registration-large-nat", registration s 9007199254740993 9007199254740995)
  ].map (fun (name, booking) => appendCell s name (.bookRegistration booking))

def foldCells (s : Sys) (refs : List Singular.OutRef) : Except String (List Json) := do
  let (u, tx) ← foldTransaction s refs 2 1 1
  let run := fun (name : String) (u : Singular.EconomicUtxo) (tx : Singular.EconomicTransaction) =>
    appendCell s name (.fold s.gen s.config.applicationPolicy u tx)
  let altered : List (String × Singular.EconomicTransaction) := [
    ("fold-valid", tx),
    ("fold-duplicate-input", { tx with transaction.inputs := tx.transaction.inputs ++ tx.transaction.inputs.take 1 }),
    ("fold-overlap", { tx with transaction.referenceInputs := tx.transaction.inputs.take 1 }),
    ("fold-missing-input", { tx with transaction.inputs := [Singular.foldWitnessInput ⟨9999, 0⟩] }),
    ("fold-empty", { tx with transaction.inputs := [] }),
    ("fold-state-missing", { tx with
      transaction.inputs := tx.transaction.inputs.filter
        (fun i => i.ref != some ⟨Singular.terminationWitnessFresh s.toWorld, 0⟩) }),
    ("fold-interval-missing", { tx with transaction.validity := none }),
    ("fold-interval-empty", { tx with transaction.validity := some ⟨2, 2⟩ }),
    ("fold-before-submission", { tx with transaction.validity := some ⟨0, 1⟩ }),
    ("fold-at-deadline", { tx with transaction.validity := some ⟨5, 6⟩ }),
    ("fold-past-deadline", { tx with transaction.validity := some ⟨5, 7⟩ }),
    ("fold-output-observation", { tx with transaction.outputs := [] }),
    ("fold-ready-burn", { tx with trieReadyMint := [] }),
    ("fold-application-burn", { tx with applicationMint := [] }),
    ("fold-singular-mint", { tx with singularMint := [] }),
    ("fold-state-mint", { tx with stateMint := [(s.config.stateToken, 1)] }),
    ("fold-foreign-asset", { tx with transaction.mint := [((.active, 11), 1)] }),
    ("fold-donation", { tx with transaction.donation := tx.transaction.donation + 1 }),
    ("fold-fee-funding", { tx with transaction.fee := 2 }),
    ("fold-unbalanced", syncOutputs tx (fun o => if Singular.foldOrdinary o then
      { o with output.lovelace := o.output.lovelace + 1, contents.lovelace := o.contents.lovelace + 1 } else o)),
    ("fold-state-token", syncOutputs tx (fun o => if o.output.stateTokens > 0 then
      { o with output.stateToken := some ⟨99, 0⟩ } else o)),
    ("fold-state-root", syncOutputs tx (fun o => if o.output.stateTokens > 0 then
      { o with output.config := o.output.config.map (fun c => { c with root := ByteArray.empty }) } else o)),
    ("fold-state-config", syncOutputs tx (fun o => if o.output.stateTokens > 0 then
      { o with output.config := o.output.config.map (fun c => { c with processTime := 99 }) } else o)),
    ("fold-state-value", syncOutputs tx (fun o => if o.output.stateTokens > 0 then
      { o with output.lovelace := 1, contents.lovelace := 1 } else o)),
    ("fold-carrier-value", syncOutputs tx (fun o => if !o.singularTags.isEmpty then
      { o with output.lovelace := 13, contents.lovelace := 13 } else o)),
    ("fold-carrier-destination", syncOutputs tx (fun o => if !o.singularTags.isEmpty then
      { o with output.address := some 999 } else o)),
    ("fold-carrier-datum", syncOutputs tx (fun o => if !o.singularTags.isEmpty then
      { o with output.datumValue := some 999 } else o)),
    ("fold-carrier-tag", syncOutputs tx (fun o => if !o.singularTags.isEmpty then
      { o with singularTags := [s.config.singularTag 999] } else o)) ]
  pure (altered.map (fun (name, tx) => run name u tx) ++ [
    run "fold-duplicate-utxo" (u ++ u.take 1) tx,
    run "fold-unrecognized-funding" (u.map fun (ref, o) => (ref,
      if ref == ⟨Singular.terminationWitnessFresh s.toWorld, 1⟩ then
        { o with singularTags := [cfg.singularTag 999] } else o)) tx,
    run "fold-stale-transaction-id" u { tx with identity := ((u.head?).map (fun entry => entry.1.tx)).getD 0 },
    run "fold-missing-request-observation" (u.filter (fun x => x.2.request.isNone)) tx,
    run "fold-wrong-request-observation" (u.map fun (ref, o) => (ref,
      if o.request.isSome then { o with contents.lovelace := 999 } else o)) tx,
    run "fold-wrong-input-state" (u.map fun (ref, o) => (ref,
      if o.output.stateTokens > 0 then { o with output.stateToken := some ⟨99, 0⟩ } else o)) tx,
    cell "fold-missing-inception" p {} s (.fold s.gen s.config.applicationPolicy u tx) ])

def terminationCells (s : Sys) : Except String (List Json) := do
  let b ← termination s 11 200
  let run := fun name b => appendCell s name (.bookTermination 11 7 1 b)
  pure ([ ("termination-valid", b),
    ("termination-carrier", { b with request.carrierAda := 3 }),
    ("termination-destination", { b with request.destination := 999 }),
    ("termination-original-datum", { b with custodyInputs := b.custodyInputs.map (fun h => { h with datum := none }) }),
    ("termination-value", { b with request.contents.lovelace := 4 }),
    ("termination-wrong-registry", { b with request.registryId := 999 }),
    ("termination-singular-tag", { b with request.singularTags := [s.config.singularTag 12] }),
    ("termination-ready-tag", { b with trieReadyTagsMinted := [] }),
    ("termination-refund", { b with request.refundAddress := some 7 }),
    ("termination-clock", { b with request.submittedAt := some 10 })
    ].map (fun (name, b) => run name b))

/-- Registration recovery neighbors keep an actually booked starting state.
Malformed observations are candidate transactions, never asserted histories. -/
def recoveryCells (s : Sys) (b : Singular.RegistrationBooking) : List Json := Id.run do
  let world := s.toWorld
  let fresh := Singular.terminationWitnessFresh world
  let u := Singular.terminationWitnessUnspent world 1
  let tx := Singular.retractionWitnessTransaction world b ⟨6, 7⟩ [42] 1 1
  let run := fun name u tx => appendCell s name (.genericRetraction u tx)
  let stateInput := Singular.foldWitnessInput ⟨fresh, 0⟩
  let variants : List (String × Singular.EconomicTransaction) := [
    ("retract-valid", tx),
    ("retract-interval-missing", { tx with transaction.validity := none }),
    ("retract-interval-empty", { tx with transaction.validity := some ⟨6, 6⟩ }),
    ("retract-ready-burn", { tx with trieReadyMint := [] }),
    ("retract-application-burn", { tx with applicationMint := [] }),
    ("retract-state-mint", { tx with stateMint := [(cfg.stateToken, 1)] }),
    ("retract-singular-mint", { tx with singularMint := [(cfg.singularTag 11, 1)] }),
    ("retract-foreign-mint", { tx with transaction.mint := [((.active, 11), 1)] }),
    ("retract-donation", { tx with transaction.donation := 1 }),
    ("retract-fee-short", { tx with transaction.fee := 2 }),
    ("retract-unbalanced", syncOutputs tx (fun o => { o with
      contents.lovelace := o.contents.lovelace + 1, output.lovelace := o.output.lovelace + 1 })),
    ("retract-short-refund", syncOutputs tx (fun o => { o with
      contents.lovelace := 16, output.lovelace := 16 })),
    ("retract-wrong-refund", syncOutputs tx (fun o => { o with output.address := some 99 })),
    ("retract-state-spent", { tx with transaction.inputs := stateInput :: tx.transaction.inputs }),
    ("retract-state-read", { tx with transaction.referenceInputs := [stateInput] }),
    ("retract-duplicate-input", { tx with transaction.inputs := tx.transaction.inputs ++ tx.transaction.inputs.take 1 }),
    ("retract-overlap", { tx with transaction.referenceInputs := tx.transaction.inputs.take 1 }),
    ("retract-no-request", { tx with transaction.inputs := tx.transaction.inputs.drop 1 }) ]
  let funding : List (String × (Singular.EconomicOutput → Singular.EconomicOutput)) := [
    ("retract-funding-ready", fun o => { o with contents.trieReadyTags := b.request.contents.trieReadyTags }),
    ("retract-funding-application", fun o => { o with contents.applicationTags := b.request.contents.applicationTags }),
    ("retract-funding-singular", fun o => { o with singularTags := [cfg.singularTag 11] }),
    ("retract-funding-role", fun o => { o with output.role := .request }),
    ("retract-funding-request", fun o => { o with request := some (.registration b.request) }),
    ("retract-funding-assets", fun o => { o with contents.otherAssets := [(⟨99, 11⟩, 1)] }) ]
  return variants.map (fun (name, tx) => run name u tx) ++ funding.map (fun (name, edit) =>
    run name (u.map fun (ref, o) => (ref, if ref == ⟨fresh, 1⟩ then edit o else o)) tx)

def rejectionCells (s : Sys) (b : Singular.RegistrationBooking) : List Json := Id.run do
  let fresh := Singular.terminationWitnessFresh s.toWorld
  let u := Singular.terminationWitnessUnspent s.toWorld 0
  let output := { Singular.foldWitnessOrdinary 16 with output.address := some 42 }
  let tx : Singular.EconomicTransaction := {
    identity := fresh + 1, outputs := [output]
    transaction := {
      inputs := [Singular.foldWitnessInput b.request.reference]
      referenceInputs := [Singular.foldWitnessInput ⟨fresh, 0⟩]
      outputs := [output.output], mint := [], signers := [], refunds := [], validity := some ⟨11, 12⟩ }
    trieReadyMint := b.request.contents.trieReadyTags.map (fun tag => (tag, -1))
    applicationMint := b.request.contents.applicationTags.map (fun tag => (Singular.applicationTagIdentity tag, -1)) }
  let r : Singular.Rejection := {
    transaction := tx, stateReference := ⟨fresh, 0⟩, members := [(b.request.reference, .expired)] }
  let run := fun name u r => appendCell s name (.genericRejection u r)
  let variants : List (String × Singular.Rejection) := [
    ("reject-valid", r),
    ("reject-no-state-read", { r with transaction.transaction.referenceInputs := [] }),
    ("reject-no-state-utxo", { r with
      stateReference := ⟨999, 0⟩,
      transaction.transaction.referenceInputs := [Singular.foldWitnessInput ⟨999, 0⟩] }),
    ("reject-spent-state-overlap", { r with
      transaction.transaction.inputs :=
        Singular.foldWitnessInput ⟨fresh, 0⟩ :: tx.transaction.inputs }),
    ("reject-spent-state", { r with
      transaction.transaction.referenceInputs := [],
      transaction.transaction.inputs := Singular.foldWitnessInput ⟨fresh, 0⟩ :: tx.transaction.inputs }),
    ("reject-duplicate-input", { r with transaction.transaction.inputs := tx.transaction.inputs ++ tx.transaction.inputs }),
    ("reject-input-overlap", { r with
      transaction.transaction.referenceInputs :=
        tx.transaction.inputs ++ tx.transaction.referenceInputs }),
    ("reject-interval-missing", { r with transaction.transaction.validity := none }),
    ("reject-interval-empty", { r with transaction.transaction.validity := some ⟨11, 11⟩ }),
    ("reject-empty", { r with members := [] }),
    ("reject-wrong-member", { r with members := [(⟨999, 0⟩, .expired)] }),
    ("reject-nonpending-input", { r with
      members := [(⟨fresh, 1⟩, .expired)],
      transaction.transaction.inputs := [Singular.foldWitnessInput ⟨fresh, 1⟩] }),
    ("reject-wrong-evidence", { r with members := [(b.request.reference, .mismatch (.known .active))] }),
    ("reject-compatible", { r with members := [(b.request.reference, .mismatch .unknown)] }),
    ("reject-ready-burn", { r with transaction.trieReadyMint := [] }),
    ("reject-application-burn", { r with transaction.applicationMint := [] }),
    ("reject-state-mint", { r with transaction.stateMint := [(cfg.stateToken, 1)] }),
    ("reject-singular-mint", { r with transaction.singularMint := [(cfg.singularTag 11, 1)] }),
    ("reject-short-refund", { r with transaction := syncOutputs tx (fun o => { o with
      output.lovelace := 15, contents.lovelace := 15 }) }),
    ("reject-wrong-refund", { r with transaction := syncOutputs tx (fun o => { o with output.address := some 99 }) }) ]
  let states : List (String × (Singular.EconomicOutput → Singular.EconomicOutput)) := [
    ("reject-state-token-count", fun o => { o with output.stateTokens := 0 }),
    ("reject-state-token-none", fun o => { o with output.stateToken := none }),
    ("reject-state-policy", fun o => { o with output.stateToken := some ⟨99, 0⟩ }),
    ("reject-state-name", fun o => { o with output.stateToken := some ⟨cfg.registryId, 99⟩ }),
    ("reject-state-datum-form", fun o => { o with output.datum := .hashed }),
    ("reject-state-config-none", fun o => { o with output.config := none }),
    ("reject-stale-state", fun o => { o with output.config := some { s.config with root := ByteArray.empty } }),
    ("reject-state-configuration", fun o => { o with output.config := some { s.config with processTime := 99 } }) ]
  return variants.map (fun (name, r) => run name u r) ++ states.map (fun (name, edit) =>
    run name (u.map fun (ref, o) => (ref, if ref == ⟨fresh, 0⟩ then edit o else o)) r)

/-- Deliberately inconsistent input states exercise the total function's
structural refusals. These rows make no reachability claim. -/
def inconsistentTerminationCells (s : Sys) : Except String (List Json) := do
  let (u, tx) ← foldTransaction s [⟨200, 0⟩] 20 1 1
  let variants : List (String × Singular.Trie) := [
    ("termination-key-unknown", []),
    ("termination-key-absent", [(11, .known .absent)]),
    ("termination-key-retired", [(11, .known .terminal)]) ]
  let missing := { s with terminations := s.terminations.map (fun e =>
    { e with booking.custodyInputs := [] }) }
  let folded := variants.map fun (name, trie) =>
    let bad := { s with trie := trie, config.root := Singular.rootOf trie }
    let observed := u.map fun (ref, o) => (ref,
      if o.output.stateTokens > 0 then { o with output.config := some bad.config } else o)
    cell name p evidence bad (.fold s.gen cfg.applicationPolicy observed tx)
  let bad := { s with trie := [], config.root := Singular.rootOf [] }
  let fresh := Singular.terminationWitnessFresh bad.toWorld
  let b := (s.terminations.head?).map (·.booking)
  match b with
  | none => throw "termination boundary requires a booking"
  | some b =>
    let rt : Singular.EconomicTransaction := {
      identity := fresh + 1, outputs := []
      transaction := {
        inputs := [Singular.foldWitnessInput b.request.reference]
        referenceInputs := [Singular.foldWitnessInput ⟨fresh, 0⟩]
        outputs := [], mint := [], signers := [], refunds := [], validity := some ⟨20, 21⟩ }
      trieReadyMint := b.request.contents.trieReadyTags.map (fun tag => (tag, -1))
      applicationMint := [] }
    let rejection : Singular.Rejection := {
      transaction := rt, stateReference := ⟨fresh, 0⟩,
      members := [(b.request.reference, .mismatch .unknown)] }
    pure (folded ++ [
      cell "termination-missing-custody" p evidence missing (.fold s.gen cfg.applicationPolicy u tx),
      cell "termination-mismatch-not-recoverable" p evidence bad
        (.genericRejection (Singular.terminationWitnessUnspent bad.toWorld 0) rejection)])

def cells : Except String (List Json) := do
  let (_, booked) ← execute start (.bookRegistration (registration start.state 11 100))
  let (u, tx) ← foldTransaction booked.state [⟨100, 0⟩] 2 1 1
  let (_, live) ← execute booked (.fold 0 cfg.applicationPolicy u tx)
  let (_, pending) ← execute live (.convictCkpt 11)
  let b ← termination pending.state 11 200
  let (_, terminated) ← execute pending (.bookTermination 11 7 1 b)
  let foldRegistration ← foldCells booked.state [⟨100, 0⟩]
  let foldTermination ← foldCells terminated.state [⟨200, 0⟩]
  let term ← terminationCells pending.state
  let rb := registration start.state 11 100
  let badStates ← inconsistentTerminationCells terminated.state
  let (_, twoBooked) ← execute booked (.bookRegistration (registration booked.state 12 101))
  let recovery := Singular.retractionWitnessTransaction twoBooked.state.toWorld rb ⟨6, 7⟩ [42] 1 1
  let recovery := { recovery with transaction.inputs := recovery.transaction.inputs ++ [Singular.foldWitnessInput ⟨101, 0⟩] }
  let some carrier := carrierAt pending.state 11 | throw "boundary-carrier-missing"
  let extra := { carrier with original := { carrier.original with key := 12 } }
  let inconsistent := { pending.state with carriers := pending.state.carriers ++ [extra] }
  let duplicateCustody := { terminated.state with carriers := pending.state.carriers }
  let (duplicateU, duplicateTx) ← foldTransaction duplicateCustody [⟨200, 0⟩] 2 1 1
  pure (bookingCells ++ foldRegistration ++ foldTermination ++ term ++ recoveryCells booked.state rb ++ rejectionCells booked.state rb ++ badStates ++ [
    appendCell inconsistent "termination-carrier-reconstruction" (.bookTermination 11 7 1 b),
    appendCell duplicateCustody "fold-carrier-reconstruction"
      (.fold duplicateCustody.gen cfg.applicationPolicy duplicateU duplicateTx),
    appendCell twoBooked.state "retract-multiple-requests" (.genericRetraction
      (Singular.terminationWitnessUnspent twoBooked.state.toWorld 1) recovery),
    appendCell { pending.state with trie := [] } "termination-without-active-leaf" (.bookTermination 11 7 1 b),
    appendCell booked.state "duplicate-registration-reference" (.bookRegistration rb),
    appendCell live.state "termination-requires-conviction" (.bookTermination 11 7 1 b),
    appendCell pending.state "termination-missing-carrier" (.bookTermination 12 7 1 b)])
end RegistryBoundary

def main : IO Unit := do
  match RegistryBoundary.cells with
  | .error why => throw (IO.userError why)
  | .ok cells => IO.println (Json.mkObj [("schema", toJson "cardano-keri.registry.boundaries"),
      ("version", toJson (3 : Nat)), ("cells", toJson cells)]).compress
