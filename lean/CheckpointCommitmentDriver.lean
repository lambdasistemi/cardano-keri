import CardanoKeri.CheckpointCommitmentVectors

/-! The commitment a conviction reveals (#534). No arguments: print the vector
table derived by the Lean. `--check FILE`: verify every committed row against
the Lean, require every changed field to fail, require each entitling fact
of the honest conviction, changed alone, to be refused, and require each other
fact of the convicted output, changed alone, to leave it accepted. -/
open CardanoKeri.Checkpoint.CommitmentVectors

def main (args : List String) : IO Unit := do
  match args with
  | [] => IO.println (← IO.ofExcept table).pretty
  | ["--check", path] =>
    let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
    let (conviction, system, fields, controls, indifferent) ← IO.ofExcept (checkTable j)
    IO.println s!"PASS checkpoint commitment vectors: conviction={conviction} system={system} field-controls={fields} entitlement-controls={controls} output-controls={indifferent}"
  | _ => throw (IO.userError "usage: CheckpointCommitmentDriver [--check FILE]")
