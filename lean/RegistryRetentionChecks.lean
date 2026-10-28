import CardanoKeri.RegistryScenarioFixtures

open CardanoKeri.Registry CardanoKeri.Registry.Scenarios

def check (label : String) (condition : Bool) : Except String Unit :=
  if condition then .ok () else .error label

def refused {α : Type} : Except String α → Bool
  | .error _ => true
  | .ok _ => false

def retention : Except String Unit := do
  let b := registration start.state 11 100
  let (_, booked) ← execute start (.bookRegistration b)
  let (u, tx) ← foldTransaction booked.state [b.request.reference] 2 1 1
  check "missing-inception" (refused (fold p { env with inception := fun _ => false }
    booked.state 0 cfg.applicationPolicy u tx))
  let (_, live) ← execute booked (.fold 0 cfg.applicationPolicy u tx)
  let some original := carrierAt live.state 11 | throw "live-carrier-missing"
  check "registration-carrier-binding" (decide
    (original.token = 0 ∧ bindingAt live.state 11 = some 0 ∧ live.state.nextToken = 1))
  check "fold-generation-advances" (live.state.gen == 1)
  let liveBooking ← termination live.state 11 200
  check "live-booking-refused" (refused (bookTermination p live.state 11 7 1 liveBooking))
  let (parkFlow, parked) ← execute live (.park 11 6)
  check "parked-entire-carrier" (decide (carrierAt parked.state 11 =
    some { original with k := 1, st := .parked }))
  check "parked-world-and-flow" (decide
    (parked.state.toWorld = live.state.toWorld ∧ parked.state.bindings = live.state.bindings ∧
      parked.state.gen = live.state.gen ∧ parkFlow = { bondReturn := some (6, 10) }))
  check "wrong-recipient" (refused (park p env live.state 11 9))
  check "missing-close-premise" (refused (park p { env with closeAuth := fun _ _ => false } live.state 11 6))
  let wrongKeyEnv := { env with rotationFrom := fun _ key => key == 2 }
  check "wrong-retained-key" (refused (revive p wrongKeyEnv parked.state 11))
  let (reviveFlow, revived) ← execute parked (.revive 11)
  check "revived-entire-carrier" (decide (carrierAt revived.state 11 =
    some { original with k := 2, st := .live }))
  check "revived-world-fresh-bond" (decide
    (revived.state.toWorld = parked.state.toWorld ∧
      reviveFlow = { deposited := 10, locked := [(11, 10)] }))
  let (_, pending) ← execute parked (.convictCkpt 11)
  check "conviction-still-active" (decide
    (pending.state.toWorld = parked.state.toWorld ∧
      carrierAt pending.state 11 = some { original with k := 1, st := .terminationPending } ∧
      Singular.worldSingularSupply pending.state.toWorld 11 = 1))
  check "pending-cannot-revive" (refused (revive p env pending.state 11))
  let (_, livePending) ← execute revived (.convictCkpt 11)
  check "live-conviction-key" (decide (carrierAt livePending.state 11 =
    some { original with k := 2, st := .terminationPending }))
  check "missing-duplicity" (refused
    (convictCkpt { env with duplicity := fun _ _ => false } revived.state 11))

def main : IO Unit := do
  match retention with
  | .error message => throw (IO.userError message)
  | .ok () => IO.println "PASS actual registration, retained parking/revival, both conviction keys and refusals"
