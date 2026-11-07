import CardanoKeri.RequestLifecycleVectors

/-! The registration request lifecycle vectors (#468). No arguments: print the
vector table derived by the Lean. `--check FILE`: verify every committed row
against the Lean and require every changed field to fail. -/
open CardanoKeri.Registry.LifecycleVectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println (← IO.ofExcept table).pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (rows, accepted, fields) ← IO.ofExcept (checkTable j)
    IO.println s!"PASS request lifecycle vectors: rows={rows} accepted={accepted} refused={rows - accepted} field-controls={fields}"
  | _ => throw (IO.userError "usage: RequestLifecycleDriver [--check FILE]")
