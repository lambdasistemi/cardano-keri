import CardanoKeri.Checkpoint
import CardanoKeri.DuplicityExamples

open CardanoKeri.Checkpoint

def p : Params := { D := 3, B := 2, P := 1, W := 5, hD := by decide, hB := by decide }
def env : Env := {
  rotationTo := fun e sn sn' => decide ((e = 0 ∧ sn = 0 ∧ sn' = 1) ∨ (e = 1 ∧ sn = 1 ∧ sn' = 2))
  intentAuthorized := fun e i r => decide (e = 1 ∧ i = .keep ∧ r = some 42)
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
  let (rotateFlow, rotated) ← execute live (.rotate 1 .keep 7 (some 42)) 3
  check "rotation-premium" (decide (rotateFlow = { hunter := some { addr := 7, pool := 1 } }))
  check "rotation-exact-key" (decide (rotated = .present ⟨1, 1, false, false, 2, 42, 4⟩))
  let wrongKey := { env with rotationTo := fun e sn sn' => decide (e = 2 ∧ sn = 1 ∧ sn' = 2) }
  check "wrong-key-refused" ((stepFn p wrongKey (.rotate 2 .keep 7 none) 4 rotated).isNone)
  let (convictFlow, pending) ← execute rotated (.convict 8) 5
  check "live-conviction-pending-key" (decide
    (pending = .terminationPending ⟨1, 1⟩ ∧ pending.hasOutput = true ∧ pending.leaf = .active))
  check "conviction-addressed-components" (decide (convictFlow = {
    refund := some { addr := 42, b := 2, pool := 4 }
    convictor := some { addr := 8, dreg := 3 } }))
  check "pending-consumer-refused" (!consumableStateB p 100 pending)
  check "pending-no-local-rotation" ((stepFn p env (.rotate 2 .keep 7 none) 6 pending).isNone)
  check "pending-no-local-top-up" ((stepFn p env (.topUp 1) 6 pending).isNone)

def main : IO Unit := do
  match journey with
  | .error message => throw (IO.userError message)
  | .ok () => IO.println "PASS Checkpoint registration, rotation and concrete conviction; pending has no local exit"
