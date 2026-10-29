import CardanoKeri.Checkpoint
import CardanoKeri.DuplicityExamples

open CardanoKeri.Checkpoint

def p : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def env : Env := {
  rotationTo := fun e sn sn' => decide ((e = 0 ∧ sn = 0 ∧ sn' = 1) ∨ (e = 1 ∧ sn = 1 ∧ sn' = 2))
  intentAuthorized := fun e i r => decide (e = 1 ∧ i = .close 7 ∧ r = some 42)
  quorum := fun _ => true
  convictionContext := fun e sn => some (CardanoKeri.Duplicity.fixture e sn).1
  convictionRival := fun e sn => some (CardanoKeri.Duplicity.fixture e sn).2 }

def check (label : String) (condition : Bool) : Except String Unit :=
  if condition then .ok () else .error label

def execute (s : State) (a : Action) (t : Nat) : Except String (Flow × State) :=
  match stepFn p env a t s with
  | some result => .ok result
  | none => .error "positive-step-refused"

def journey : Except String Unit := do
  let (registeredFlow, live) ← execute .absent (.register 42 5) 2
  check "registration-bonds" (decide (registeredFlow = { dregIn := 3, bIn := 2, poolIn := 5 }))
  let (closeFlow, parked) ← execute live (.close 1 7 (some 42)) 3
  check "close-addressed-components" (decide (closeFlow = {
    refund := some { addr := 42, dreg := 3, b := 2, pool := 4 }
    hunter := some { addr := 7, pool := 1 } }))
  check "parked-output-token-key" (decide
    (parked = .parked ⟨1, 1⟩ ∧ parked.hasOutput = true ∧ parked.representativeHeld = 1 ∧ parked.leaf = .active))
  check "parked-consumer-refused" (!consumableStateB p 100 parked)
  let wrongKey := { env with rotationTo := fun e sn sn' => decide (e = 2 ∧ sn = 1 ∧ sn' = 2) }
  check "wrong-key-refused" ((stepFn p wrongKey (.reopen 2 42 5) 4 parked).isNone)
  let (reviveFlow, revived) ← execute parked (.reopen 2 42 5) 4
  check "revival-fresh-bonds" (decide (reviveFlow = { dregIn := 3, bIn := 2, poolIn := 5 }))
  check "revival-exact-key" (decide (revived = .present ⟨2, 2, false, false, 4, 42, 5⟩))
  let (parkConvictFlow, parkPending) ← execute parked (.convict 8) 5
  check "parked-conviction-pending-key" (decide
    (parkPending = .terminationPending ⟨1, 1⟩ ∧ parkConvictFlow = {} ∧
      parkPending.hasOutput = true ∧ parkPending.leaf = .active))
  let (convictFlow, pending) ← execute revived (.convict 8) 5
  check "live-conviction-pending-key" (decide
    (pending = .terminationPending ⟨2, 2⟩ ∧ pending.hasOutput = true ∧ pending.leaf = .active))
  check "conviction-addressed-components" (decide (convictFlow = {
    refund := some { addr := 42, b := 2, pool := 5 }
    convictor := some { addr := 8, dreg := 3 } }))
  check "pending-consumer-refused" (!consumableStateB p 100 pending)
  check "pending-no-local-exit" ((stepFn p env (.reopen 3 42 5) 6 pending).isNone)

def main : IO Unit := do
  match journey with
  | .error message => throw (IO.userError message)
  | .ok () => IO.println "PASS Checkpoint registration/parking/revival and both concrete conviction branches"
