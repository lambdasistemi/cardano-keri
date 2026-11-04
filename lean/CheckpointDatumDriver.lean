import CardanoKeri.CheckpointDatumVectors

/-! The version 2 checkpoint datum (#498). No arguments: print the vector table
derived by the Lean. `--check FILE`: verify every committed row against the
decoder and the consumer predicate, require every changed field to fail and
every node of every accepted datum changed in kind to be refused, and every
pending-termination datum within the size bound's premises to meet it. -/
open CardanoKeri.CheckpointDatum.Vectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println (← IO.ofExcept table).pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (accepted, refused, fields, kinds, pending) ← IO.ofExcept (checkTable j)
    IO.println s!"PASS checkpoint datum vectors: accepted={accepted} refused={refused} field-controls={fields} kind-controls={kinds} pending-size-rows={pending}"
  | _ => throw (IO.userError "usage: CheckpointDatumDriver [--check FILE]")
