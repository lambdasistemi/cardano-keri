import CardanoKeri.Checkpoint
import CardanoKeri.DuplicityExamples

/-! Finite local observations for the Checkpoint atom inventory.
Each case fixes the full input and expected output. The cases are local
observations, not additional SysReach proofs; connected registration-started
witnesses and associated completion are supplied by the system fixtures. -/
open CardanoKeri.Checkpoint
namespace CheckpointAtoms

def p : Params := ⟨3, 2, 1, 5, by decide, by decide⟩
def l : Live := ⟨1, 1, false, false, 3, 42, 4, false⟩
def short : Live := { l with pool := 0 }
def env : Env := {
  rotationTo := fun e sn next => decide (e = 1 ∧ sn = 1 ∧ next = 2)
  depositAuthorized := fun e => decide (e = 2)
  quorum := fun _ => true
  convictionContext := fun e sn => some (CardanoKeri.Duplicity.fixture e sn).1
  convictionRival := fun e sn => some (CardanoKeri.Duplicity.fixture e sn).2 }
def noDup : Env := { env with convictionRival := fun _ _ => none }
def noDeposit : Env := { env with depositAuthorized := fun _ => false }
def run (e : Env) (s : State) (a : Action) := stepFn p e a 9 s
def check (target : Option String) (id : String) (b : Bool) : Except String Unit := if target.isSome && target != some id then .ok () else if b then .ok () else .error id

def observations (target : Option String) : Except String Unit := do
  let check := check target
  check "CP-01" ((run env (.present l) (.freeze 2 7)).isNone)
  check "CP-02" ((run env (.present { short with frozen := true }) (.freeze 2 7)).isNone)
  check "CP-03" ((run env (.present { l with poisoned := true }) .poison).isNone)
  check "CP-04" (decide (run env (.present l) (.topUp 2) =
    some ({ poolIn := 2 }, .present { l with pool := 6, toppedUp := true })))
  check "CP-05" ((run noDup (.present l) (.convict 8)).isNone)
  check "CP-08" (decide (run env (.present l) (.convict 8) = some
    ({ refund := some { addr := 42, b := 2, pool := 4 },
       convictor := some { addr := 8, dreg := 3 } }, .terminationPending ⟨1, 1⟩)))
  let deposit : Flow × State := ({ bIn := 2, hunter := some { addr := 7, pool := 1 } },
    .present { l with sn := 2, epoch := 2, pool := 3 })
  check "CP-09" (decide (run env (.present { l with frozen := true }) (.rotate 2 .deposit 7) = some deposit))
  check "CP-10" (decide (run env (.present short) (.rotate 2 .deposit 7) =
    some ({}, .present { short with sn := 2, epoch := 2 })))
  check "CP-11" (decide (run env (.present l) (.rotate 2 .deposit 7) =
    some ({ hunter := some { addr := 7, pool := 1 } }, .present { l with sn := 2, epoch := 2, pool := 3 })))
  check "CP-12" ((run noDeposit (.present l) (.rotate 2 .deposit 7)).isNone)
  check "CP-13" (decide (run noDeposit (.present l) (.rotate 2 .keep 7) =
    some ({ hunter := some { addr := 7, pool := 1 } }, .present { l with sn := 2, epoch := 2, pool := 3 })))
  check "CP-14" (!noDeposit.bondOpOk 2 .deposit)
  let noRotation := { env with rotationTo := fun _ _ _ => false }
  check "CP-30" (decide ((l.rotated p 2).bornAt = 3))
  check "CP-31" ((p.premium short 7).isNone)
  check "CP-32" (decide ((State.terminationPending ⟨1, 1⟩).leaf = .active))
  check "CP-33" (decide (State.convicted.leaf = .retired))
  -- CP-34's former dormant-leaf guard is retired. Stored-origin system
  -- controls are exercised by CheckpointSystemFixtures and its interpreter.
  check "CP-35" (!(Action.convict 8).touchesLeaf)
  check "CP-36" (decide (l.bHeld p = 2 ∧ ({ l with frozen := true } : Live).bHeld p = 0))
  check "CP-37" (!consumableStateB p 99 (.present { l with frozen := true }))
  check "CP-38" (decide ((State.terminationPending ⟨1, 1⟩).dregHeld p = 0))
  let history : List (Slot × Action) := [(0, .poison), (1, .rotate 2 .keep 7)]
  check "CP-39" ((run { noRotation with depositAuthorized := fun _ => false }
    (.present short) (.rotate 2 .keep 7)).isNone)
  check "CP-40" (!poisonAfter false history)
  let topped : Live := { l with toppedUp := true }
  let toppedShort : Live := { short with toppedUp := true }
  check "second-top-up" ((run env (.present topped) (.topUp 2)).isNone)
  check "top-up-below-premium" ((run env (.present l) (.topUp 0)).isNone)
  check "top-up-leaves-mark-unset" (match run env (.present l) (.topUp 2) with
    | some (_, s) => (run env s (.topUp 2)).isNone
    | none => false)
  check "keep-paid-rotation-keeps-mark" (decide (run env (.present topped) (.rotate 2 .keep 7) =
    some ({ hunter := some { addr := 7, pool := 1 } }, .present { l with sn := 2, epoch := 2, pool := 3 })))
  check "keep-unpaid-rotation-keeps-mark" (decide (run env (.present toppedShort) (.rotate 2 .keep 7) =
    some ({}, .present { short with sn := 2, epoch := 2 })))
  check "deposit-paid-rotation-keeps-mark" (decide (run env (.present topped) (.rotate 2 .deposit 7) =
    some ({ hunter := some { addr := 7, pool := 1 } }, .present { l with sn := 2, epoch := 2, pool := 3 })))
  check "deposit-unpaid-rotation-keeps-mark" (decide (run env (.present toppedShort) (.rotate 2 .deposit 7) =
    some ({}, .present { short with sn := 2, epoch := 2 })))
  check "registration-below-premium" ((run env .absent (.register 42 0)).isNone)
  check "registration-starts-topped-up" (decide (run env .absent (.register 42 4) =
    some ({ dregIn := 3, bIn := 2, poolIn := 4 }, .present ⟨0, 0, false, false, 9, 42, 4, false⟩)))
  check "poison-clears-mark" (decide (run env (.present topped) .poison =
    some ({}, .present { topped with poisoned := true })))
  check "freeze-clears-mark" (decide (run env (.present toppedShort) (.freeze 2 7) =
    some ({ hunter := some { addr := 7, b := 2 } }, .present { toppedShort with frozen := true })))
end CheckpointAtoms

def main (args : List String) : IO Unit :=
  match CheckpointAtoms.observations args.head? with
  | .ok () => IO.println "PASS 33 current local atom observations; CP-34 has a system successor"
  | .error id => throw (IO.userError ("ATOM:" ++ id))
