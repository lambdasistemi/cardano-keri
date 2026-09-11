import Lean
import CardanoKeri.Checkpoint

open Lean
open CardanoKeri.Checkpoint

deriving instance ToJson for KeyState
deriving instance ToJson for Live
deriving instance ToJson for State
deriving instance ToJson for Payment
deriving instance ToJson for Flow

def params : Params := { D := 1000, B := 5, P := 2, W := 10, hD := by decide, hB := by decide }

def noEvidence : Env := {
  rotationTo := fun _ _ _ => false
  intentAuthorized := fun _ _ _ => false
  quorum := fun _ => false
  duplicityAt := fun _ _ => false
}

-- Finite environmental facts describe capabilities, not constructed signatures.
def loserEvidence : Env := { noEvidence with
  duplicityAt := fun epoch sn => epoch == 1 && sn == 7
}

def nextKeysEvidence : Env := { loserEvidence with
  rotationTo := fun epoch sn sn' => epoch == 1 && sn == 7 && sn' == 8
  intentAuthorized := fun epoch intent refund =>
    epoch == 2 && (match intent with | .close payee => payee == 99 | _ => false) && refund == some 99
}

def paymentTo (who : Nat) (flow : Flow) : Nat :=
  [flow.refund, flow.hunter, flow.convictor].foldl (fun total p =>
    match p with
    | some x => if x.addr == who then total + x.dreg + x.b + x.pool else total
    | none => total) 0

def check (name : String) (actual : Option (Flow × State))
    (expected : Option (Flow × State)) : IO Unit := do
  unless actual == expected do
    throw (IO.userError s!"{name}: unexpected result {reprStr actual}")
  IO.println (Json.mkObj [("case", toJson name), ("pass", toJson true),
    ("result", toJson actual)]).compress

def main : IO Unit := do
  let attack : Env := {
    rotationTo := fun epoch sn sn' =>
      [(0, 0, 1), (1, 1, 2), (2, 2, 3)].contains (epoch, sn, sn')
    intentAuthorized := fun epoch intent refund =>
      epoch == 2 && (match intent with | .close payee => payee == 99 | _ => false) && refund == some 99
    quorum := fun _ => false
    duplicityAt := fun epoch sn => epoch == 1 && sn == 1
  }
  for pool in [0, 4] do
    let some (_, registered) := stepFn params attack (.register 11 pool) 0 .absent
      | throw (IO.userError "registration refused")
    let some (_, first) := stepFn params attack (.rotate 1 .keep 99 none) 1000 registered
      | throw (IO.userError "first rotation refused")
    let firstPool := if 2 ≤ pool then pool - 2 else pool
    check s!"pool_{pool}_rival_convicts_before_advance"
      (stepFn params attack (.convict 11) 1000 first)
      (some ({refund := some {addr := 11, b := 5, pool := firstPool}, convictor := some {addr := 11, dreg := 1000}}, .convicted))
    let expectedSecond : State := .present {
      sn := 2, epoch := 2, poisoned := false, frozen := false,
      bornAt := 0, refundTo := 11, pool := 0
    }
    let expectedSecondFlow : Flow := if pool == 4 then {hunter := some {addr := 99, pool := 2}} else {}
    check s!"pool_{pool}_second_rotation_same_time"
      (stepFn params attack (.rotate 2 .keep 99 none) 1000 first)
      (some (expectedSecondFlow, expectedSecond))
    check s!"pool_{pool}_old_rival_refused_after_second_rotation"
      (stepFn params attack (.convict 11) 1000 expectedSecond) none
    let closeFlow : Flow := if pool == 4 then
      {refund := some {addr := 99, dreg := 1000, b := 5}, hunter := some {addr := 99, pool := 2}}
      else {refund := some {addr := 99, dreg := 1000, b := 5}}
    let parked : State := .parked {epoch := 2, sn := 2}
    check s!"pool_{pool}_close_same_time"
      (stepFn params attack (.close 2 99 (some 99)) 1000 first)
      (some (closeFlow, parked))
    check s!"pool_{pool}_old_rival_refused_after_close"
      (stepFn params attack (.convict 11) 1000 parked) none
    unless consumableStateB params 1000 first do
      throw (IO.userError "expected already mature checkpoint to stay consumable")
    IO.println (Json.mkObj [("case", toJson s!"pool_{pool}_rotation_keeps_mature_checkpoint_consumable"), ("pass", toJson true)]).compress
