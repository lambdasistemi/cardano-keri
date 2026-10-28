import CardanoKeri.RegistryTraceWire

/-! Version 3 corpus producer. Every result executes the actual adapter and
pinned imported economic judgments. Traces retain complete states, actions,
addressed flows, observations and exact refusal strings. -/
open Lean CardanoKeri.Registry CardanoKeri.Registry.Scenarios CardanoKeri.Registry.TraceWire

namespace RegistryTrace

def evidence : EnvTable := {
  inception := [11, 12, 13, 14, 15]
  rotationFrom := [(11, 1), (12, 1), (13, 1)]
  duplicity := [11, 12, 13].flatMap (fun aid => [0, 1, 2].map (fun key => (aid, key)))
  closeAuth := [(11, 6), (12, 6), (13, 6)] }

structure Run where
  state : Sys := Sys.init cfg
  cells : List Json := []

abbrev Driver := StateT Run (Except String)

def act (label : String) (action : Action) (required := true) : Driver Unit := do
  let before ← get
  let result := stepFn p evidence.toEnv action before.state
  if required then
    if let .error why := result then throw s!"{label}: {why}"
  let after := match result with | .ok (_, s) => s | .error _ => before.state
  set ({ state := after, cells := before.cells ++ [cell label p evidence before.state action] } : Run)

def book (aid ref : Nat) : Driver Unit := do
  act s!"book-{aid}" (.bookRegistration (registration (← get).state aid ref))

def process (refs : List Nat) (time := 2) : Driver Unit := do
  let s := (← get).state
  let (u, tx) ← liftM (foldTransaction s (refs.map (fun ref => ⟨ref, 0⟩)) time 1 1)
  act "fold" (.fold s.gen s.config.applicationPolicy u tx)

def terminate (aid ref : Nat) : Driver Unit := do
  let b ← liftM (termination (← get).state aid ref)
  act s!"book-termination-{aid}" (.bookTermination aid 7 1 b)

def localJourney : Driver Unit := do
  book 11 100
  process [100]
  act "wrong-close-recipient" (.park 11 9) false
  act "park" (.park 11 6)
  let parked := (← get).state
  let noRotation := { evidence with rotationFrom := [] }
  modify fun r => { r with cells := r.cells ++ [cell "missing-rotation" p noRotation parked (.revive 11)] }
  act "revive" (.revive 11)
  act "convict" (.convictCkpt 11)
  act "pending-revival-refused" (.revive 11) false
  terminate 11 200
  process [200] 20
  act "retired-registration-booking" (.bookRegistration (registration (← get).state 11 300))
  let s := (← get).state
  -- Assemble a proposed new registration while retaining the real retired
  -- prestate for execution. The actual fold must refuse the existing key.
  let (u, tx) ← liftM (foldTransaction { s with trie := [] } [⟨300, 0⟩] 2 1 1)
  act "retired-fold-refused" (.fold s.gen s.config.applicationPolicy u tx) false

def mixedJourney : Driver Unit := do
  book 11 100
  book 12 101
  process [100, 101]
  act "convict-11" (.convictCkpt 11)
  act "convict-12" (.convictCkpt 12)
  terminate 11 200
  terminate 12 201
  book 13 102
  let s := (← get).state
  let (u, tx) ← liftM (foldTransaction s [⟨102, 0⟩, ⟨200, 0⟩] 2 1 1)
  act "stale-generation" (.fold (s.gen - 1) s.config.applicationPolicy u tx) false
  act "wrong-plugin" (.fold s.gen 999 u tx) false
  act "wrong-donation" (.fold s.gen s.config.applicationPolicy u
    { tx with transaction.donation := tx.transaction.donation + 1 }) false
  act "mixed-fold" (.fold s.gen s.config.applicationPolicy u tx)
  book 14 103
  let recovery := (← get).state
  let some b := recovery.registrations.head? | throw "recovery fixture missing"
  let ru := Singular.terminationWitnessUnspent recovery.toWorld 1
  let rt := Singular.retractionWitnessTransaction recovery.toWorld b ⟨6, 7⟩ [42] 1 1
  act "missing-recovery-signer" (.genericRetraction ru { rt with transaction.signers := [] }) false
  act "recover-registration" (.genericRetraction ru rt)
  process [201] 20

def rejectionJourney : Driver Unit := do
  book 15 105
  let s := (← get).state
  let some b := s.registrations.head? | throw "rejection fixture missing"
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
  let rejection : Singular.Rejection := {
    transaction := tx, stateReference := ⟨fresh, 0⟩, members := [(b.request.reference, .expired)] }
  act "rejection-too-early" (.genericRejection u
    { rejection with transaction.transaction.validity := some ⟨10, 11⟩ }) false
  act "expired-registration-rejected" (.genericRejection u rejection)

def recoveryJourney : Driver Unit := do
  book 11 100
  let s := (← get).state
  let some b := s.registrations.head? | throw "recovery fixture missing"
  let u := Singular.terminationWitnessUnspent s.toWorld 1
  let tx := Singular.retractionWitnessTransaction s.toWorld b ⟨6, 7⟩ [42] 1 1
  act "early-retraction" (.genericRetraction u { tx with transaction.validity := some ⟨5, 6⟩ }) false
  act "missing-retraction-signer" (.genericRetraction u { tx with transaction.signers := [] }) false
  act "late-retraction" (.genericRetraction u { tx with transaction.validity := some ⟨10, 12⟩ }) false
  act "retraction" (.genericRetraction u tx)

def seededJourney (seed : Nat) : Driver Unit := do
  book 11 100
  book 12 101
  process [100, 101]
  act "park-before-seeded-actions" (.park 11 6)
  act "revive-before-seeded-actions" (.revive 11)
  let mut random := seed
  for index in List.range 100 do
    random := (random * 1664525 + 1013904223) % 4294967296
    let aid := 11 + random % 3
    let action := match (random / 3) % 4 with
      | 0 => Action.park aid 6
      | 1 => Action.revive aid
      | 2 => Action.convictCkpt aid
      | _ => Action.park aid 99
    act s!"seed-{seed}-step-{index}" action false

def run (name : String) (driver : Driver Unit) : Except String Json := do
  let (_, result) ← driver.run {}
  pure (Json.mkObj [("name", toJson name), ("cells", toJson result.cells)])

def grid : Except String (List Json) := do
  let (_, live) ← (do book 11 100; process [100] : Driver Unit).run {}
  let (_, parked) ← (act "park" (.park 11 6)).run live
  let (_, pending) ← (act "convict" (.convictCkpt 11)).run parked
  let actions : List Action := [.park 11 6, .park 11 7, .revive 11, .convictCkpt 11,
    .park 12 6, .revive 12, .convictCkpt 12]
  pure ([Sys.init cfg, live.state, parked.state, pending.state].flatMap fun s =>
    [evidence, {}].flatMap fun e => actions.map fun action => cell "local-boundary" p e s action)

end RegistryTrace

def main : IO Unit := do
  let generated := do
    let traces ← [ ("retained-output", RegistryTrace.localJourney),
      ("mixed-custody-and-recovery", RegistryTrace.mixedJourney),
      ("expired-registration", RegistryTrace.rejectionJourney),
      ("registration-retraction", RegistryTrace.recoveryJourney),
      ("seed-437", RegistryTrace.seededJourney 437),
      ("seed-9001", RegistryTrace.seededJourney 9001) ].mapM fun (name, driver) => RegistryTrace.run name driver
    let grid ← RegistryTrace.grid
    pure (Json.mkObj [("schema", toJson "cardano-keri.registry.trace"), ("version", toJson (3 : Nat)),
      ("traces", toJson traces), ("grid", toJson grid)])
  match generated with
  | .error why => throw (IO.userError why)
  | .ok json => IO.println json.compress
