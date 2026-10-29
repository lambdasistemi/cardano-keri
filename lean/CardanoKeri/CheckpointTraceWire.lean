import Lean
import CardanoKeri.Checkpoint
import CardanoKeri.DuplicityExamples

/-! Shared Checkpoint JSON instances and finite cryptographic-evidence fixtures.
A duplicity selector chooses the concrete model fixture; it is not a Boolean
substitute for the duplicity decision. -/

open Lean (ToJson toJson Json FromJson fromJson?)
open CardanoKeri.Checkpoint

namespace CardanoKeri.Checkpoint.TraceWire

deriving instance Lean.ToJson for BondOp
deriving instance Lean.ToJson for Intent
deriving instance Lean.ToJson for Action
deriving instance Lean.ToJson for KeyState
deriving instance Lean.ToJson for Live
deriving instance Lean.ToJson for State
deriving instance Lean.ToJson for Payment
deriving instance Lean.ToJson for Flow
deriving instance Lean.FromJson for BondOp
deriving instance Lean.FromJson for Intent
deriving instance Lean.FromJson for Action
deriving instance Lean.FromJson for KeyState
deriving instance Lean.FromJson for Live
deriving instance Lean.FromJson for State

/-- `Params` carries two proofs, so its instance is written by hand. -/
instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("B", toJson p.B), ("P", toJson p.P), ("W", toJson p.W)]

/-- `Params` from JSON, with the two positivity proofs decided at parse time:
a deployment with a zero bond has no `Params` and therefore no Lean cell. -/
def paramsOfJson (j : Json) : Except String Params := do
  let D ← j.getObjValAs? Nat "D"
  let B ← j.getObjValAs? Nat "B"
  let P ← j.getObjValAs? Nat "P"
  let W ← j.getObjValAs? Nat "W"
  if hD : 0 < D then
    if hB : 0 < B then pure { D, B, P, W, hD, hB }
    else throw "B must be positive"
  else throw "D must be positive"

/-- Three primitive decision tables and selectors for concrete duplicity
fixtures. A selector is a model scenario, not proof of real cryptography. -/
structure EnvTable where
  rotationTo : List (Nat × Nat × Nat)
  /-- `(e, intent, refund address or none)`: the keys of epoch `e` signed that intent message (D-038, D-039). -/
  intentAuthorized : List (Nat × Intent × Option Nat)
  quorum : List Nat
  duplicityAt : List (Nat × Nat)

def EnvTable.toEnv (t : EnvTable) : Env where
  rotationTo := fun e sn sn' => t.rotationTo.contains (e, sn, sn')
  intentAuthorized := fun e i r => t.intentAuthorized.contains (e, i, r)
  quorum := fun e => t.quorum.contains e
  convictionContext := fun e sn =>
    if t.duplicityAt.contains (e, sn) then some (CardanoKeri.Duplicity.fixture e sn).1 else none
  convictionRival := fun e sn =>
    if t.duplicityAt.contains (e, sn) then some (CardanoKeri.Duplicity.fixture e sn).2 else none

instance : ToJson EnvTable where
  toJson t := Json.mkObj [
    ("rotationTo", toJson (t.rotationTo.map fun (e, sn, sn') => [e, sn, sn'])),
    ("intentAuthorized", Json.arr (t.intentAuthorized.map fun (e, i, r) => Json.arr #[toJson e, toJson i, toJson r]).toArray),
    ("quorum", toJson (t.quorum.map fun e => [e])),
    ("duplicityAt", toJson (t.duplicityAt.map fun (e, sn) => [e, sn]))]

/-- An evidence row `{kind: [args]}` of a scenario file, added to or removed from a table. -/
def EnvTable.applyRow (t : EnvTable) (add : Bool) (row : Json) : Except String EnvTable := do
  let upd {α} [BEq α] (l : List α) (x : α) : List α := if add then (if l.contains x then l else l ++ [x]) else l.filter (· != x)
  let nats (v : Json) : Except String (List Nat) := fromJson? v
  match row.getObjVal? "rotationTo" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e, sn, sn'] => pure { t with rotationTo := upd t.rotationTo (e, sn, sn') }
    | _ => throw "rotationTo row needs three numbers"
  | .error _ =>
  match row.getObjVal? "intentAuthorized" with
  | .ok v =>
    match v.getArr? with
    | .ok #[ej, ij, rj] =>
      let e : Nat ← fromJson? ej
      let i : Intent ← fromJson? ij
      let r : Option Nat ← if rj.isNull then pure none else (fromJson? rj : Except String Nat).map some
      pure { t with intentAuthorized := upd t.intentAuthorized (e, i, r) }
    | _ => throw "intentAuthorized row needs [epoch, intent, address or null]"
  | .error _ =>
  match row.getObjVal? "quorum" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e] => pure { t with quorum := upd t.quorum e }
    | _ => throw "quorum row needs one number"
  | .error _ =>
  match row.getObjVal? "duplicityAt" with
  | .ok v =>
    let l ← nats v
    match l with
    | [e, sn] => pure { t with duplicityAt := upd t.duplicityAt (e, sn) }
    | _ => throw "duplicityAt row needs two numbers"
  | .error _ => throw "unknown evidence row"

end CardanoKeri.Checkpoint.TraceWire
