import CardanoKeri.RegistryScenarioFixtures
import Lean

/-! Registry trace interchange version 3. Values use the complete model
structures. Integers outside JavaScript's exact Number range are canonical
decimal strings; small integers remain JSON numbers. This is an interchange
representation, not a change to Lean Nat, Int or the imported token encoding.
Fixtures assemble transactions; acceptance is always the actual stepFn. -/
open Lean

deriving instance ToJson, FromJson for Singular.TxRole
deriving instance ToJson, FromJson for Singular.TxInput
deriving instance ToJson, FromJson for Singular.TxOutput
deriving instance ToJson, FromJson for Singular.Tx
deriving instance ToJson, FromJson for Singular.EconomicRequest
deriving instance ToJson, FromJson for Singular.EconomicOutput
deriving instance ToJson, FromJson for Singular.EconomicTransaction
deriving instance ToJson, FromJson for Singular.Rejection
deriving instance ToJson, FromJson for CardanoKeri.Registry.CkState
deriving instance ToJson, FromJson for CardanoKeri.Registry.Carrier
deriving instance ToJson, FromJson for CardanoKeri.Registry.TerminationPayload
deriving instance ToJson, FromJson for CardanoKeri.Registry.TerminationEntry
deriving instance ToJson, FromJson for CardanoKeri.Registry.Sys
deriving instance ToJson, FromJson for CardanoKeri.Registry.Flow
deriving instance ToJson, FromJson for CardanoKeri.Registry.Action

namespace CardanoKeri.Registry.TraceWire

instance : ToJson Params where
  toJson p := Json.mkObj [("D", toJson p.D), ("tip", toJson p.tip),
    ("Mc", toJson p.Mc), ("Mr", toJson p.Mr)]

instance : FromJson Params where
  fromJson? j := do
    let D ← j.getObjValAs? Nat "D"
    let tip ← j.getObjValAs? Nat "tip"
    let Mc ← j.getObjValAs? Nat "Mc"
    let Mr ← j.getObjValAs? Nat "Mr"
    if hD : 0 < D then
      if hFund : Mr + tip ≤ Mc then pure { D, tip, Mc, Mr, hD, hFund }
      else throw "Mr + tip must not exceed Mc"
    else throw "D must be positive"

structure EnvTable where
  inception : List Nat := []
  rotationFrom : List (Nat × Nat) := []
  duplicity : List (Nat × Nat) := []
  closeAuth : List (Nat × Nat) := []
  deriving ToJson, FromJson

def EnvTable.toEnv (table : EnvTable) : Env := {
  inception := fun aid => table.inception.contains aid
  rotationFrom := fun aid key => table.rotationFrom.contains (aid, key)
  duplicity := fun aid key => table.duplicity.contains (aid, key)
  closeAuth := fun aid recipient => table.closeAuth.contains (aid, recipient) }

partial def exactJson (j : Json) : Json := match j with
  | .num _ => match j.getInt? with
    | .ok value => if value.natAbs > 9007199254740991 then .str (toString value) else j
    | .error _ => j
  | .arr values => .arr (values.map exactJson)
  | .obj fields => Json.mkObj (fields.toList.map fun (name, value) => (name, exactJson value))
  | _ => j

partial def decodeExact (j : Json) : Json := match j with
  | .str value => match value.toInt? with
    | some number => if toString number == value then toJson number else j
    | none => j
  | .arr values => .arr (values.map decodeExact)
  | .obj fields => Json.mkObj (fields.toList.map fun (name, value) => (name, decodeExact value))
  | _ => j

def observations (s : Sys) : Json :=
  let aids := (s.bindings.map Prod.fst ++ s.carriers.map (·.aid) ++
    s.terminations.map (·.payload.aid)).eraseDups
  Json.arr (aids.map fun aid => Json.mkObj [
    ("aid", toJson aid), ("binding", toJson (bindingAt s aid)),
    ("leaf", toJson (Singular.trieGet s.trie aid)),
    ("minAda", toJson (minAdaAt s aid)),
    ("supply", toJson (Singular.worldSingularSupply s.toWorld aid))]).toArray

def resultJson : Except String Result → Json
  | .error reason => Json.mkObj [("error", toJson reason)]
  | .ok (flow, state) => Json.mkObj [("ok", Json.mkObj [
      ("flow", toJson flow), ("state", toJson state), ("observations", observations state)])]

def cell (name : String) (p : Params) (env : EnvTable) (s : Sys) (action : Action) : Json :=
  exactJson (Json.mkObj [("name", toJson name), ("params", toJson p),
    ("env", toJson env), ("input", toJson s), ("action", toJson action),
    ("result", resultJson (stepFn p env.toEnv action s))])

end CardanoKeri.Registry.TraceWire
