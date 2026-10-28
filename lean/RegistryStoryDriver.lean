import CardanoKeri.RegistryTraceWire

/-! Replay the canonical Registry scenario inputs. Expected outcomes are never
read by this producer: every trunk and fork executes the actual stepFn from
Sys.init under the scenario's explicit fixed parameters and evidence table. -/
open Lean CardanoKeri.Registry CardanoKeri.Registry.TraceWire
namespace RegistryStories

def replay (p : Params) (env : EnvTable) (start : Sys) (steps : Array Json) : Except String (Sys × List Json) := do
  let mut state := start
  let mut cells := []
  for (step, index) in steps.toList.zipIdx do
    let action ← step.getObjValAs? Action "action"
    let activeEnv ← match step.getObjVal? "env" with
      | .ok value => fromJson? value
      | .error _ => pure env
    let label := (step.getObjValAs? String "note").toOption.getD s!"step-{index}"
    cells := cells ++ [cell label p activeEnv state action]
    if let .ok (_, after) := stepFn p activeEnv.toEnv action state then state := after
  pure (state, cells)

def scenario (raw : Json) : Except String Json := do
  let source := decodeExact raw
  let version ← source.getObjValAs? Nat "wireVersion"
  if version != 3 then throw "Registry scenario requires wireVersion 3"
  let p ← source.getObjValAs? Params "params"
  let cfg ← source.getObjValAs? Singular.Config "config"
  let env ← source.getObjValAs? EnvTable "env"
  let steps ← source.getObjValAs? (Array Json) "steps"
  let (final, cells) ← replay p env (Sys.init cfg) steps
  let forks ← source.getObjValAs? (Array Json) "forks"
  let forkCells ← forks.toList.mapM fun fork => do
    let offset ← fork.getObjValAs? Nat "at"
    if offset > steps.size then throw "fork exceeds trunk"
    let (start, _) ← replay p env (Sys.init cfg) (steps.toList.take offset).toArray
    let branchEnv ← match fork.getObjVal? "env" with
      | .ok value => fromJson? value
      | .error _ => pure env
    let forkSteps ← fork.getObjValAs? (Array Json) "steps"
    let (final, cells) ← replay p branchEnv start forkSteps
    pure (Json.mkObj [("id", ← fork.getObjVal? "id"), ("at", toJson offset),
      ("cells", toJson cells), ("final", toJson final)])
  pure (exactJson (Json.mkObj [("id", ← source.getObjVal? "id"),
    ("slug", ← source.getObjVal? "slug"), ("cells", toJson cells),
    ("final", toJson final), ("forks", toJson forkCells)]))

end RegistryStories

def main (args : List String) : IO Unit := do
  let directory : System.FilePath := args.headD "../simulator/registry-simulator-scenarios"
  let entries ← directory.readDir
  let names := (entries.toList.map (fun entry => entry.fileName)).filter (·.endsWith ".json")
  let names := names.mergeSort (· ≤ ·)
  let mut stories := []
  for name in names do
    let text ← IO.FS.readFile (directory / name)
    let result := do
      let json ← Json.parse text
      RegistryStories.scenario json
    match result with
    | .error reason => throw (IO.userError s!"{name}: {reason}")
    | .ok value => stories := stories ++ [value]
  IO.println (Json.mkObj [("schema", toJson "cardano-keri.registry.stories"),
    ("version", toJson (3 : Nat)), ("stories", toJson stories)]).compress
