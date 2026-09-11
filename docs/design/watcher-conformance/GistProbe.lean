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
  -- Reach the tip by ordinary model actions, not by constructing an unreachable state.
  let setup : Env := { noEvidence with rotationTo := fun e sn sn' => e == 0 && sn == 0 && sn' == 7 }
  let some (_, registered) := stepFn params setup (.register 11 22) 0 .absent
    | throw (IO.userError "registration refused")
  let some (_, accepted) := stepFn params setup (.rotate 7 .keep 11 none) 10 registered
    | throw (IO.userError "advance refused")
  let close := stepFn params nextKeysEvidence (.close 8 99 (some 99)) 20 accepted
  let expectedClose : Flow := {
    refund := some { addr := 99, dreg := 1000, b := 5, pool := 18 }
    hunter := some { addr := 99, pool := 2 }
  }
  check "close_by_next_keys_redirects_all_held_funds" close
    (some (expectedClose, .parked {epoch := 2, sn := 8}))
  unless paymentTo 99 expectedClose == 1025 do throw (IO.userError "close total")
  check "same_close_without_next_rotation_is_refused"
    (stepFn params loserEvidence (.close 8 99 (some 99)) 20 accepted) none
  check "loser_with_duplicity_evidence_gets_bounty"
    (stepFn params loserEvidence (.convict 99) 20 accepted)
    (some ({
      refund := some {addr := 11, b := 5, pool := 20}
      convictor := some {addr := 99, dreg := 1000}
    }, .convicted))
  let frozenSetup := { setup with rotationTo := fun e sn sn' => e == 1 && sn == 7 && sn' == 8 }
  -- Frozen close uses the bond actually held, so the total is lower by B.
  let some (_, lowPool) := stepFn params setup (.register 11 1) 0 .absent
    | throw (IO.userError "low-pool registration refused")
  let some (_, lowTip) := stepFn params setup (.rotate 7 .keep 11 none) 10 lowPool
    | throw (IO.userError "low-pool advance refused")
  let some (_, frozen) := stepFn params frozenSetup (.freeze 8 77) 11 lowTip
    | throw (IO.userError "freeze refused")
  check "frozen_close_returns_only_held_bond_and_pool"
    (stepFn params nextKeysEvidence (.close 8 99 (some 99)) 20 frozen)
    (some ({refund := some {addr := 99, dreg := 1000, pool := 1}}, .parked {epoch := 2, sn := 8}))
  let some (_, parked) := close | throw (IO.userError "close result missing")
  let parkedEvidence := { noEvidence with duplicityAt := fun e sn => e == 2 && sn == 8 }
  check "parked_without_duplicity_evidence_refused"
    (stepFn params noEvidence (.convict 99) 1000000000000 parked) none
  for now in [20, 1000000000000] do
    check s!"parked_conviction_at_{now}"
      (stepFn params parkedEvidence (.convict 99) now parked) (some ({}, .convicted))
  check "convicted_cannot_reopen"
    (stepFn params { nextKeysEvidence with rotationTo := fun _ _ _ => true }
      (.reopen 9 11 20) 1000000000001 .convicted) none
