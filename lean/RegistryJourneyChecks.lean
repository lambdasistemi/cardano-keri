import CardanoKeri.RegistryScenarioFixtures

open CardanoKeri.Registry CardanoKeri.Registry.Scenarios

def check (label : String) (condition : Bool) : Except String Unit :=
  if condition then .ok () else .error label

def refuses {α : Type} : Except String α → Bool
  | .error _ => true
  | .ok _ => false

/-- Actual registration-started multi-identity execution, with reachability
carried by each successful step. Checks whole records, frames and amounts. -/
def journey : Except String (List String) := do
  let a := registration start.state 11 100
  let (_, s1) ← execute start (.bookRegistration a)
  let b := registration s1.state 12 101
  let (_, s2) ← execute s1 (.bookRegistration b)
  let (u, tx) ← foldTransaction s2.state [a.request.reference, b.request.reference] 2 1 1
  let (flow, both) ← execute s2 (.fold 0 cfg.applicationPolicy u tx)
  check "two-registration-flow" (decide (flow = { locked := [(11, 10), (12, 10)] }))
  check "two-registration-bindings" (decide
    (bindingAt both.state 11 = some 0 ∧ bindingAt both.state 12 = some 1 ∧
      both.state.nextToken = 2 ∧ both.state.registrations = []))
  check "binding-domain-no-phantom" (both.state.bindings.all (fun (aid, _) =>
    Singular.trieGet both.state.trie aid == .known .active ||
      Singular.trieGet both.state.trie aid == .known .terminal))
  check "binding-domain-complete" (both.state.trie.all (fun (aid, leaf) =>
    if leaf == .known .active || leaf == .known .terminal then
      (bindingAt both.state aid).isSome else true))
  let (_, c1) ← execute both (.convictCkpt 11)
  let (_, c2) ← execute c1 (.convictCkpt 12)
  let ta ← termination c2.state 11 200
  let (bookFlow, oneBooked) ← execute c2 (.bookTermination 11 7 1 ta)
  check "booking-flow" (decide (bookFlow =
    { premium := some (7, 1), intoRequest := 3, bookingFee := 1 }))
  check "booking-keeps-other-carrier" (decide
    (carrierAt oneBooked.state 12 = carrierAt c2.state 12 ∧
      oneBooked.state.config = c2.state.config ∧ oneBooked.state.gen = c2.state.gen ∧
      Singular.worldSingularSupply oneBooked.state.toWorld 11 = 1 ∧
      Singular.worldSingularSupply oneBooked.state.toWorld 12 = 1))
  let tb ← termination oneBooked.state 12 201
  let (_, twoBooked) ← execute oneBooked (.bookTermination 12 8 1 tb)
  check "second-booking-keeps-whole-first" (decide
    (pendingAt twoBooked.state ta.request.reference = pendingAt oneBooked.state ta.request.reference))
  let c := registration twoBooked.state 13 102
  let (_, mixed) ← execute twoBooked (.bookRegistration c)
  let (mu, mt) ← foldTransaction mixed.state [c.request.reference, ta.request.reference] 2 1 1
  check "wrong-generation-refused" (refuses (fold p env mixed.state 0 cfg.applicationPolicy mu mt))
  check "wrong-plugin-refused" (refuses (fold p env mixed.state mixed.state.gen 999 mu mt))
  let wrongDonation := { mt with transaction.donation := mt.transaction.donation + 1 }
  check "wrong-donation-refused" (refuses
    (fold p env mixed.state mixed.state.gen cfg.applicationPolicy mu wrongDonation))
  let oldRefundOutputs := mt.outputs.map fun o =>
    if Singular.foldOrdinary o then
      { o with
        output.lovelace := o.output.lovelace + p.Mr,
        contents.lovelace := o.contents.lovelace + p.Mr }
    else o
  let oldRefund := { mt with
    outputs := oldRefundOutputs,
    transaction.outputs := oldRefundOutputs.map (·.output),
    transaction.donation := mt.transaction.donation - p.Mr }
  check "old-refund-balanced" (Singular.balanced mu.ledger oldRefund.transaction)
  check "old-refund-refused" (refuses
    (fold p env mixed.state mixed.state.gen cfg.applicationPolicy mu oldRefund))
  let (mixedFlow, after) ← execute mixed (.fold mixed.state.gen cfg.applicationPolicy mu mt)
  check "mixed-flow" (decide (mixedFlow = { locked := [(13, 10)] }))
  check "mixed-keeps-whole-pending" (decide
    (pendingAt after.state tb.request.reference = pendingAt mixed.state tb.request.reference ∧
      after.state.terminations = mixed.state.terminations.filter
        (fun e => e.booking.request.reference != ta.request.reference)))
  check "mixed-effects" (decide
    (Singular.trieGet after.state.trie 11 = .known .terminal ∧
      Singular.trieGet after.state.trie 12 = .known .active ∧
      Singular.trieGet after.state.trie 13 = .known .active ∧
      Singular.worldSingularSupply after.state.toWorld 11 = 0 ∧
      Singular.worldSingularSupply after.state.toWorld 12 = 1 ∧
      Singular.worldSingularSupply after.state.toWorld 13 = 1 ∧
      bindingAt after.state 11 = bindingAt mixed.state 11 ∧
      after.state.treasury = mixed.state.treasury + 4 ∧
      after.state.gen = mixed.state.gen + 1 ∧
      after.state.config = { mixed.state.config with root := after.state.config.root }))
  let recovery := registration after.state 14 103
  let (_, recoverable) ← execute after (.bookRegistration recovery)
  let ru := Singular.terminationWitnessUnspent recoverable.state.toWorld 1
  let rt := Singular.retractionWitnessTransaction recoverable.state.toWorld recovery ⟨6, 7⟩ [42] 1 1
  let (_, recovered) ← execute recoverable (.genericRetraction ru rt)
  check "recovery-preserves-pending-and-frame" (decide
    (recovered.state.terminations = recoverable.state.terminations ∧
      recovered.state.carriers = recoverable.state.carriers ∧
      recovered.state.bindings = recoverable.state.bindings ∧
      recovered.state.config = recoverable.state.config ∧
      recovered.state.gen = recoverable.state.gen ∧
      recovered.state.trie = recoverable.state.trie ∧ recovered.state.registrations = []))
  let noSigner := { rt with transaction.signers := [] }
  check "recovery-no-signer-refused" (refuses (genericRetraction recoverable.state ru noSigner))
  let (tu, tt) ← foldTransaction recovered.state [tb.request.reference] 20 1 1
  let (_, final) ← execute recovered (.fold recovered.state.gen cfg.applicationPolicy tu tt)
  check "both-retired-fresh-identity-live" (decide
    (final.state.terminations = [] ∧
      Singular.trieGet final.state.trie 11 = .known .terminal ∧
      Singular.trieGet final.state.trie 12 = .known .terminal ∧
      Singular.trieGet final.state.trie 13 = .known .active ∧
      final.state.nextToken = 3 ∧ final.state.treasury = 10))
  pure ["exact binding domain", "two registrations", "two convictions", "booking carrier frame", "booking pending tail",
    "mixed registration and termination", "whole unselected custody", "exact mint supply and config frame",
    "registration recovery alongside termination", "missing signer refusal", "remaining termination",
    "stale generation", "wrong plugin", "wrong donation", "balanced old refund"]

def main : IO Unit := do
  match journey with
  | .error message => throw (IO.userError message)
  | .ok checks =>
    for name in checks do IO.println s!"PASS {name}"
