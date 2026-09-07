import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-05 CardanoKeri.Cage.ownerKeyed_needs_owner owner false hook both false/true, reject good time
def witness_TH_05_check1 : Bool :=
  decide (stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨false, false⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = none)
def witness_TH_05_check2 : Bool :=
  decide (stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = none)
example : witness_TH_05_check1 = true := by decide
example : witness_TH_05_check2 = true := by decide
example : stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = none := CardanoKeri.Cage.ownerKeyed_needs_owner Plugin.registry .delegatedRouting true wp noEvidence 1 pending 1 0 7 [(0, .reject)]
