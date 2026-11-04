import CardanoKeri.CheckpointDepositVectors

/-! The deposit intent's signed bytes (#517). No arguments: print the vector
table derived by the Lean. `--check FILE`: verify every committed row against
the Lean and require every changed field to fail. -/
open CardanoKeri.CheckpointDeposit.Vectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println table.pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (intents, requirements, authorizations, fields, refused) ← IO.ofExcept (checkTable j)
    IO.println s!"PASS checkpoint deposit vectors: intents={intents} requirements={requirements} refused={refused} authorizations={authorizations} field-controls={fields}"
  | _ => throw (IO.userError "usage: CheckpointDepositDriver [--check FILE]")
