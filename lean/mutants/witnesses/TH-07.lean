import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-07 CardanoKeri.Cage.owner_bypass_breaks_inv owner-keyed registration without plugin evidence
example : (stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨true, false⟩ wp noEvidence (.fold 1 0 7 [(0, .process)]) 1 pending = some ({ locked := [(11, 1000)], tips := some (1, 2) }, bypassed)) := (CardanoKeri.Cage.owner_bypass_breaks_inv).1
example : ¬ Inv wp bypassed := CardanoKeri.Cage.bypassed_breaks_inv
