import CardanoKeri.RegistryScenarioFixtures

/-! Executable request-lifecycle checks over the actual adapter. A duplicate
key's request is the sharp case: the imported rejection would accept its
mismatch ground at any time, so only the deadline keeps it until then. -/
open CardanoKeri.Registry CardanoKeri.Registry.Scenarios

def check (label : String) (condition : Bool) : Except String Unit :=
  if condition then .ok () else .error label

def refusedWith {α : Type} (reason : String) : Except String α → Bool
  | .error why => why == reason
  | .ok _ => false

def accepted {α : Type} : Except String α → Bool
  | .error _ => false
  | .ok _ => true

def lifecycle : Except String Unit := do
  let first := registration start.state 11 100
  let (_, booked) ← execute start (.bookRegistration first)
  let (u, tx) ← foldTransaction booked.state [first.request.reference] 5 1 1
  let (_, live) ← execute booked (.fold 0 cfg.applicationPolicy u tx)
  let duplicate := registration live.state 11 300
  let (_, pending) ← execute live (.bookRegistration duplicate)
  let s := pending.state
  let ref := duplicate.request.reference
  let mismatch : Singular.RejectReason := .mismatch (.known .active)
  let (ru, early) ← returnTransaction s [ref] 5 mismatch
  check "duplicate-early-return" (refusedWith "keri-return-before-deadline"
    (returnRequests s ru early))
  let straddling := { early with transaction.transaction.validity := some ⟨5, 7⟩ }
  check "duplicate-straddling-return" (refusedWith "keri-return-before-deadline"
    (returnRequests s ru straddling))
  let (_, late) ← returnTransaction s [ref] 6 mismatch
  check "duplicate-return-at-deadline" (accepted (returnRequests s ru late))
  check "return-unbalanced-refused" (refusedWith "keri-return-unbalanced"
    (returnRequests s ru { late with transaction.transaction.fee := 0 }))
  check "return-without-member-refused" (refusedWith "keri-return-registration-only"
    (returnRequests s ru { late with members := [(⟨999, 0⟩, .expired)] }))
  let (_, folded) ← returnTransaction s [ref] 6 mismatch
  let (_, after) ← execute pending (.returnRequests ru folded)
  check "return-leaves-carrier" (decide
    (after.state.registrations = [] ∧ after.state.carriers = s.carriers ∧
      after.state.trie = s.trie ∧ after.state.gen = s.gen))

def main : IO Unit := do
  match lifecycle with
  | .error message => throw (IO.userError message)
  | .ok () => IO.println "PASS a duplicate waits for its deadline; the return balances and names registrations only"
