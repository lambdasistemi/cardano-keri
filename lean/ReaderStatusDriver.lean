import CardanoKeri.ReaderStatusVectors

/-! The reader's status vectors (#353). No arguments: print the vector table
derived by the Lean. `--check FILE`: verify every committed row against the
classifier and require every changed field to fail. `--run`: read one scenario
`{context, now, evidence}` from standard input, in the table's layout, and
print the classifier's answer; a scenario that does not parse fails. -/
open CardanoKeri.ReaderStatus.Vectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println (← IO.ofExcept table).pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (rows, statuses, fields) ← IO.ofExcept (checkTable j)
    let counts := " ".intercalate (statuses.map fun (name, n) => s!"{name}={n}")
    IO.println s!"PASS reader status vectors: rows={rows} {counts} field-controls={fields}"
  | ["--run"] =>
    let input ← (← IO.getStdin).readToEnd
    let j ← IO.ofExcept (Lean.Json.parse input)
    IO.println (← IO.ofExcept (run j)).pretty
  | _ => throw (IO.userError "usage: ReaderStatusDriver [--check FILE | --run]")
