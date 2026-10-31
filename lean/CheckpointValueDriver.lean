import CardanoKeri.CheckpointValueVectors

/-! The checkpoint output's value (#502). No arguments: print the vector table
derived by the Lean. `--check FILE`: verify every committed row against the
Lean and require every changed field to fail. -/
open CardanoKeri.CheckpointValue.Vectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println (← IO.ofExcept table).pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (held, holdings, registration, fields) ← IO.ofExcept (checkTable j)
    IO.println s!"PASS checkpoint value vectors: held={held} holdings={holdings} registration={registration} field-controls={fields}"
  | _ => throw (IO.userError "usage: CheckpointValueDriver [--check FILE]")
