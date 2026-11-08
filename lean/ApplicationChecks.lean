import CardanoKeri.ApplicationVectors

/-! Mutation subject for KERI's application (#526): recompute every committed
vector row and approval with the model under test. A changed verdict or byte
names its row and fails. -/
open CardanoKeri.Application.Vectors

def main (args : List String) : IO UInt32 := do
  let [path] := args | throw (IO.userError "usage: ApplicationChecks FILE")
  let j ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile path))
  let committed ← IO.ofExcept (arrayOf j "rows")
  let committedApprovals ← IO.ofExcept (arrayOf j "approvals")
  let mut failed := false
  for r in committed do
    let id ← IO.ofExcept (r.getObjValAs? String "id")
    if (verifyRow r).toOption.isNone then
      IO.println s!"verdict-changed {id}"
      failed := true
  for r in committedApprovals do
    let id ← IO.ofExcept (r.getObjValAs? String "id")
    if (verifyApproval r).toOption.isNone then
      IO.println s!"approval-changed {id}"
      failed := true
  if failed then return 1
  IO.println s!"PASS application rows={committed.size} approvals={committedApprovals.size}"
  return 0
