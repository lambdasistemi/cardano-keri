import CardanoKeri.ConsumerBytesVectors

/-! Concrete consumer identity bytes (#489). No arguments: print the vector
table derived by the Lean. `--check FILE`: recompute every committed row, run
the consumer predicate's refusal controls and require every changed field to
fail. `--singular FILE`: reproduce Singular's independent preimage table. -/
open CardanoKeri.ConsumerIdentity.Bytes.Vectors

def readJson (path : String) : IO Lean.Json := do
  IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println (← IO.ofExcept table).pretty
  | ["--check", path] =>
    let (rows, fields) ← IO.ofExcept (checkTable (← readJson path))
    let refusals ← IO.ofExcept refusalControls
    for line in refusals do IO.println line
    IO.println s!"PASS consumer identity vectors: rows={rows} predicate-refusals={refusals.length} field-controls={fields}"
  | ["--singular", path] =>
    let n ← IO.ofExcept (checkSingular (← readJson path))
    IO.println s!"PASS Singular preimage table reproduced: vectors={n}"
  | _ => throw (IO.userError "usage: ConsumerBytesDriver [--check FILE | --singular FILE]")
