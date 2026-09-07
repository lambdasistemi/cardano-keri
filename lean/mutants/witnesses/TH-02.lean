import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-02 CardanoKeri.Cage.delegated_is_registry reachable delegated fold plus non-fold action
def witness_TH_02_acc : Acc := { leaves := [], ckpts := [], requests := [(0, ⟨11, 1, 0, .register⟩)], nextToken := 0, locked := [], refunds := [] }
example : (stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = CardanoKeri.Registry.stepFn wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending) := CardanoKeri.Cage.delegated_is_registry false wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending
example : (stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.retract 0) 25 pending = CardanoKeri.Registry.stepFn wp noEvidence (.retract 0) 25 pending) := CardanoKeri.Cage.delegated_is_registry false wp noEvidence (.retract 0) 25 pending
