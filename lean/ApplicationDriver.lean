import CardanoKeri.ApplicationVectors

/-! KERI's application vectors (#526). No arguments: print the vector table
derived by the Lean. `--check FILE`: verify every committed row against the
Lean and require every changed field to fail. -/
open CardanoKeri.Application.Vectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println table.pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (rows, accepted, fields) ← IO.ofExcept (checkTable j)
    IO.println s!"PASS application vectors: rows={rows} accepted={accepted} refused={rows - accepted} field-controls={fields}"
  | _ => throw (IO.userError "usage: ApplicationDriver [--check FILE]")
