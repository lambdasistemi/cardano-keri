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
  let (convictFlow, pending) ← execute live (.convictCkpt 11)
  check "conviction-still-active" (decide
    (pending.state.toWorld = live.state.toWorld ∧ convictFlow = {} ∧
      carrierAt pending.state 11 = some { original with st := .terminationPending } ∧
      Singular.worldSingularSupply pending.state.toWorld 11 = 1))
  check "pending-cannot-reconvict" (refused (convictCkpt env pending.state 11))
  check "missing-duplicity" (refused
    (convictCkpt { env with duplicity := fun _ _ => false } live.state 11))

def main : IO Unit := do
  match retention with
  | .error message => throw (IO.userError message)
  | .ok () => IO.println "PASS actual registration, live conviction at the registered key and refusals"
