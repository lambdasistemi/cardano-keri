import CardanoKeri.RegistryTraceWire

/-! A duplicate registration cannot be folded. Until its deadline nothing
spends it; after the deadline anyone returns it, without a signature, with
everything but its declared tip paid to its refund address. -/
open Lean CardanoKeri.Registry CardanoKeri.Registry.Scenarios CardanoKeri.Registry.TraceWire
namespace DuplicateStory

def evidence : EnvTable := {
  inception := [11]
  duplicity := [(11, 0), (11, 1), (11, 2)] }

def trace : Except String (List Json) := do
  let first := registration start.state 11 100
  let (_, booked) ← execute start (.bookRegistration first)
  let (u, tx) ← foldTransaction booked.state [first.request.reference] 2 1 1
  let (_, live) ← execute booked (.fold 0 cfg.applicationPolicy u tx)
  let duplicate := registration live.state 11 300
  let (_, pending) ← execute live (.bookRegistration duplicate)
  let s := pending.state
  let (ru, early) ← returnTransaction s [duplicate.request.reference] 5 (.mismatch (.known .active))
  let (_, late) ← returnTransaction s [duplicate.request.reference] 6 (.mismatch (.known .active))
  let (_, expired) ← returnTransaction s [duplicate.request.reference] 6
  let (du, dt) ← foldTransaction { s with trie := [] } [duplicate.request.reference] 2 1 1
  let successful := Action.returnRequests ru late
  let (_, recovered) ← execute pending successful
  if recovered.state.registrations != [] then throw "duplicate return left a registration"
  pure [
    cell "book-first-registration" p evidence start.state (.bookRegistration first),
    cell "fold-first-registration" p evidence booked.state (.fold 0 cfg.applicationPolicy u tx),
    cell "book-duplicate" p evidence live.state (.bookRegistration duplicate),
    cell "duplicate-fold-refused" p evidence s (.fold s.gen cfg.applicationPolicy du dt),
    cell "duplicate-return-before-deadline" p evidence s (.returnRequests ru early),
    cell "duplicate-return-after-deadline" p evidence s successful,
    cell "duplicate-expired-return" p evidence s (.returnRequests ru expired) ]
end DuplicateStory

def main : IO Unit := do
  match DuplicateStory.trace with
  | .error why => throw (IO.userError why)
  | .ok cells => IO.println (toJson cells).compress
