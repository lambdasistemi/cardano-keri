import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-10 CardanoKeri.Cage.delegated_pins_plugin delegated fold with unequal plugin refused
def witness_TH_10_check : Bool := decide (stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 8 [(0, .process)]) 1 pending = none)
example : witness_TH_10_check = true := by decide
example : ∀ (pl' : Nat), pl' ≠ 7 → stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 pl' [(0, .process)]) 1 pending = none := fun pl' hpl => CardanoKeri.Cage.delegated_pins_plugin false true wp noEvidence 1 pending 1 0 [(0, .process)] hpl
