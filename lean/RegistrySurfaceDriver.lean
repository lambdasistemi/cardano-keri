import CardanoKeri.Registry
import Lean

/-! The compiled model dependency surface below Registry.stepFn. This enumerates
model definitions by their actual expression dependencies, including generated
helpers; source-clause reconciliation uses their declaring modules. It is not
an axiom audit, and it does not claim every branch has a reachable witness. -/
open Lean Elab Command
run_cmd do
  let env ← getEnv
  let owns := fun name => match env.getModuleIdxFor? name with
    | some index =>
      (`CardanoKeri.Registry).isPrefixOf env.header.moduleNames[index.toNat]! ||
        (`Singular).isPrefixOf env.header.moduleNames[index.toNat]!
    | none => false
  let mut todo := [``CardanoKeri.Registry.stepFn]
  let mut seen : NameSet := {}
  let mut rows : Array Json := #[]
  while !todo.isEmpty do
    let name := todo.head!
    todo := todo.tail!
    if seen.contains name then continue
    seen := seen.insert name
    let some info := env.find? name | throwError m!"missing declaration {name}"
    let some body := info.value? | continue
    if let some index := env.getModuleIdxFor? name then
      rows := rows.push (Json.mkObj [
        ("declaration", toJson name.toString),
        ("module", toJson env.header.moduleNames[index.toNat]!.toString)])
    for used in body.getUsedConstants do
      if owns used then
        todo := used :: todo
  if rows.isEmpty then throwError "empty executable model surface"
  liftIO <| IO.println (Json.mkObj [
    ("root", toJson "CardanoKeri.Registry.stepFn"), ("declarations", Json.arr rows)]).compress
