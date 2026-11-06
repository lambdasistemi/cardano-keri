import CardanoKeri.RegistryTraceWire

/-! Semantic boundary corpus. Each row changes one complete input to the
actual stepFn. Successful neighbors are retained. Malformed transaction
observations are deliberate negative inputs, not reachable state claims. -/
open Lean CardanoKeri.Registry CardanoKeri.Registry.Scenarios CardanoKeri.Registry.TraceWire
namespace RegistryBoundary

def evidence : EnvTable := {
  inception := [11, 12, 13, 9007199254740993]
  duplicity := [(11, 0), (11, 1), (12, 0)] }

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

/-- Return neighbors keep an actually booked starting state: one input
changed per row. Malformed observations are candidate transactions, never
asserted histories. The valid row pays the refund address the contents less the
declared tip and leaves the tip as the fee. -/
def returnCells (s : Sys) (b : Singular.RegistrationBooking) : Except String (List Json) := do
  let (u, r) ← returnTransaction s [b.request.reference] 11
  let tx := r.transaction
  let fresh := r.stateReference.tx
  let run := fun name u r => appendCell s name (.returnRequests u r)
  let feeTwo : Singular.EconomicTransaction := { tx with transaction.fee := 2 }
  let keepsMore := syncOutputs feeTwo (fun o => { o with
    output.lovelace := 15, contents.lovelace := 15 })
  -- Spending the state output, carried through unchanged so the transaction
  -- still balances and the imported refusal is the one observed.
  let stateRef : Singular.OutRef := ⟨fresh, 0⟩
  let stateOut := ((u.find? (fun e => e.1 == stateRef)).map Prod.snd).getD (Singular.foldWitnessOrdinary 0)
  let spendState : Singular.EconomicTransaction := { tx with
    outputs := tx.outputs ++ [stateOut]
    transaction.outputs := tx.transaction.outputs ++ [stateOut.output]
    transaction.inputs := Singular.foldWitnessInput stateRef :: tx.transaction.inputs }
  let deployedElsewhere := { s with config.retractTime := 5 }
  let (elsewhereU, elsewhere) ← returnTransaction deployedElsewhere [b.request.reference] 6
  let variants : List (String × Singular.Rejection) := [
    ("return-valid", r),
    ("return-with-signer", { r with transaction.transaction.signers := [7] }),
    ("return-before-deadline", { r with transaction.transaction.validity := some ⟨5, 6⟩ }),
    ("return-straddling-deadline", { r with transaction.transaction.validity := some ⟨5, 7⟩ }),
    ("return-at-deadline", { r with transaction.transaction.validity := some ⟨6, 7⟩ }),
    ("return-unbalanced", { r with transaction.transaction.fee := 0 }),
    ("return-spender-keeps-more-than-tip", { r with transaction := keepsMore }),
    ("return-redirected-refund", { r with transaction := syncOutputs tx (fun o => { o with
      output.address := some 99 }) }),
    ("return-no-state-read", { r with transaction.transaction.referenceInputs := [] }),
    ("return-no-state-utxo", { r with
      stateReference := ⟨999, 0⟩,
      transaction.transaction.referenceInputs := [Singular.foldWitnessInput ⟨999, 0⟩] }),
    ("return-spent-state-overlap", { r with transaction := spendState }),
    ("return-spent-state", { r with transaction := { spendState with transaction.referenceInputs := [] } }),
    ("return-extra-input", { r with transaction.transaction.inputs :=
      tx.transaction.inputs ++ [Singular.foldWitnessInput ⟨fresh, 1⟩] }),
    ("return-duplicate-input", { r with transaction.transaction.inputs := tx.transaction.inputs ++ tx.transaction.inputs }),
    ("return-input-overlap", { r with
      transaction.transaction.referenceInputs :=
        tx.transaction.inputs ++ tx.transaction.referenceInputs }),
    ("return-interval-missing", { r with transaction.transaction.validity := none }),
    ("return-interval-empty", { r with transaction.transaction.validity := some ⟨11, 11⟩ }),
    ("return-empty", { r with members := [] }),
    ("return-wrong-member", { r with members := [(⟨999, 0⟩, .expired)] }),
    ("return-wrong-evidence", { r with members := [(b.request.reference, .mismatch (.known .active))] }),
    ("return-compatible", { r with members := [(b.request.reference, .mismatch .unknown)] }),
    ("return-ready-burn", { r with transaction.trieReadyMint := [] }),
    ("return-application-burn", { r with transaction.applicationMint := [] }),
    ("return-state-mint", { r with transaction.stateMint := [(cfg.stateToken, 1)] }),
    ("return-singular-mint", { r with transaction.singularMint := [(cfg.singularTag 11, 1)] }) ]
  let states : List (String × (Singular.EconomicOutput → Singular.EconomicOutput)) := [
    ("return-state-token-count", fun o => { o with output.stateTokens := 0 }),
    ("return-state-token-none", fun o => { o with output.stateToken := none }),
    ("return-state-policy", fun o => { o with output.stateToken := some ⟨99, 0⟩ }),
    ("return-state-name", fun o => { o with output.stateToken := some ⟨cfg.registryId, 99⟩ }),
    ("return-state-datum-form", fun o => { o with output.datum := .hashed }),
    ("return-state-config-none", fun o => { o with output.config := none }),
    ("return-stale-state", fun o => { o with output.config := some { s.config with root := ByteArray.empty } }),
    ("return-state-configuration", fun o => { o with output.config := some { s.config with processTime := 99 } }) ]
  return variants.map (fun (name, r) => run name u r) ++
    [appendCell deployedElsewhere "return-without-keri-deployment" (.returnRequests elsewhereU elsewhere)] ++
    states.map (fun (name, edit) =>
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
        (.returnRequests (Singular.terminationWitnessUnspent bad.toWorld 0) rejection)])

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
  let (returnU, returnBoth) ← returnTransaction twoBooked.state [⟨100, 0⟩, ⟨101, 0⟩] 11
  let returns ← returnCells booked.state rb
  let some carrier := carrierAt pending.state 11 | throw "boundary-carrier-missing"
  let extra := { carrier with original := { carrier.original with key := 12 } }
  let inconsistent := { pending.state with carriers := pending.state.carriers ++ [extra] }
  let duplicateCustody := { terminated.state with carriers := pending.state.carriers }
  let (duplicateU, duplicateTx) ← foldTransaction duplicateCustody [⟨200, 0⟩] 2 1 1
  pure (bookingCells ++ foldRegistration ++ foldTermination ++ term ++ returns ++ badStates ++ [
    appendCell inconsistent "termination-carrier-reconstruction" (.bookTermination 11 7 1 b),
    appendCell duplicateCustody "fold-carrier-reconstruction"
      (.fold duplicateCustody.gen cfg.applicationPolicy duplicateU duplicateTx),
    appendCell twoBooked.state "return-multiple-requests" (.returnRequests returnU returnBoth),
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
