import CardanoKeri.RegistryTraceWire

/-! A duplicate registration is refused by processing and refunded by an
actual generic rejection using the current authenticated registry read.
Expiry before both windows is a distinct, refused ground. -/
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
  let fresh := Singular.terminationWitnessFresh s.toWorld
  let ru := Singular.terminationWitnessUnspent s.toWorld 0
  let output := { Singular.foldWitnessOrdinary
    (duplicate.request.contents.lovelace - duplicate.request.declaredTip) with
    output.address := some duplicate.request.refundAddress }
  let rt : Singular.EconomicTransaction := {
    identity := fresh + 1, outputs := [output]
    transaction := {
      inputs := [Singular.foldWitnessInput duplicate.request.reference]
      referenceInputs := [Singular.foldWitnessInput ⟨fresh, 0⟩]
      outputs := [output.output], mint := [], signers := [], refunds := [], validity := some ⟨2, 3⟩ }
    trieReadyMint := duplicate.request.contents.trieReadyTags.map (fun tag => (tag, -1))
    applicationMint := duplicate.request.contents.applicationTags.map (fun tag => (Singular.applicationTagIdentity tag, -1)) }
  let rejection : Singular.Rejection := {
    transaction := rt, stateReference := ⟨fresh, 0⟩,
    members := [(duplicate.request.reference, .mismatch (.known .active))] }
  let (du, dt) ← foldTransaction { s with trie := [] } [duplicate.request.reference] 2 1 1
  let successful := Action.genericRejection ru rejection
  let (_, recovered) ← execute pending successful
  if recovered.state.registrations != [] then throw "duplicate recovery left a registration"
  pure [
    cell "book-first-registration" p evidence start.state (.bookRegistration first),
    cell "fold-first-registration" p evidence booked.state (.fold 0 cfg.applicationPolicy u tx),
    cell "book-duplicate" p evidence live.state (.bookRegistration duplicate),
    cell "duplicate-fold-refused" p evidence s (.fold s.gen cfg.applicationPolicy du dt),
    cell "early-expiry-refused" p evidence s (.genericRejection ru
      { rejection with members := [(duplicate.request.reference, .expired)] }),
    cell "mismatch-rejection" p evidence s successful ]
end DuplicateStory

def main : IO Unit := do
  match DuplicateStory.trace with
  | .error why => throw (IO.userError why)
  | .ok cells => IO.println (toJson cells).compress
