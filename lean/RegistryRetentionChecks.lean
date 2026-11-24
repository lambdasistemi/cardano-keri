import CardanoKeri.RegistryScenarioFixtures

open CardanoKeri.Registry CardanoKeri.Registry.Scenarios

def check (label : String) (condition : Bool) : Except String Unit :=
  if condition then .ok () else .error label

def refused {α : Type} : Except String α → Bool
  | .error _ => true
  | .ok _ => false

def retention : Except String Unit := do
  let b := registration start.state 11 100
  check "missing-inception" (refused (bookRegistration p { env with inception := fun _ => false }
    start.state b))
  -- Every pending request has its evidence: under an environment where the refund address has
  -- evidence and the key has none, whatever the booking step leaves pending is of a key with evidence.
  let other : Env := { env with inception := fun k => k == b.request.refundAddress }
  let pending := match stepFn p other (.bookRegistration b) start.state with
    | .ok (_, after) => after.registrations
    | .error _ => start.state.registrations
  check "pending-requests-have-evidence" (pending.all fun r => other.inception r.request.key)
  let (_, booked) ← execute start (.bookRegistration b)
  let (u, tx) ← foldTransaction booked.state [b.request.reference] 2 1 1
  check "fold-reads-no-inception" (!refused (stepFn p { env with inception := fun _ => false }
    (.fold 0 cfg.applicationPolicy u tx) booked.state))
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
      carrierAt pending.state 11 = some (original.convicted env 11) ∧
      Singular.worldSingularSupply pending.state.toWorld 11 = 1))
  check "pending-cannot-reconvict" (refused (convictCkpt env pending.state 11))
  check "missing-duplicity" (refused
    (convictCkpt { env with conviction := fun _ => none } live.state 11))

def main : IO Unit := do
  match retention with
  | .error message => throw (IO.userError message)
  | .ok () => IO.println "PASS actual registration, live conviction at the registered key and refusals"
