import CardanoKeri.ReaderStatusVectors

/-! Mutation subject for the reader's status (#353): recompute the answer of
every committed vector row from the row's own committed evidence, with the
model under test. A changed answer names its row and fails. -/
open CardanoKeri.ReaderStatus.Vectors
open CardanoKeri.ConsumerIdentity.Bytes.Vectors (field str)

def main (args : List String) : IO UInt32 := do
  let [path] := args | throw (IO.userError "usage: ReaderStatusChecks FILE")
  let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  let committed ← IO.ofExcept (rowsOf j)
  let c ← IO.ofExcept (do contextOf (← field j ["context"]))
  let mut failed := false
  for row in committed do
    let id ← IO.ofExcept (str row ["id"])
    if (answersRow c row).toOption.isNone then
      IO.println s!"answer-changed {id}"
      failed := true
  if failed then return 1
  IO.println s!"PASS reader status rows={committed.size}"
  return 0
