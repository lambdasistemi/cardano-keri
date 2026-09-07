import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-04 CardanoKeri.Cage.ownerAndHook_needs_owner owner false hook both false/true, reject good time
def witness_TH_04_check1 : Bool := decide (stepFn .ownerAndHook Plugin.registry .delegatedRouting ⟨false, false⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = none)
def witness_TH_04_check2 : Bool := decide (stepFn .ownerAndHook Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = none)
example : witness_TH_04_check1 = true := by decide
example : witness_TH_04_check2 = true := by decide
example : stepFn .ownerAndHook Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = none := CardanoKeri.Cage.ownerAndHook_needs_owner Plugin.registry .delegatedRouting true wp noEvidence 25 pending 1 0 7 [(0, .reject)]
