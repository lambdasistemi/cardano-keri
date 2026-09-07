import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-08 CardanoKeri.Cage.ownerAndHook_trivial_breaks_inv shipped stub registration with hook
example : (stepFn .ownerAndHook Plugin.trivial .delegatedRouting ⟨true, true⟩ wp noEvidence (.fold 1 0 7 [(0, .process)]) 1 pending = some ({ locked := [(11, 1000)], tips := some (1, 2) }, bypassed)) := (CardanoKeri.Cage.ownerAndHook_trivial_breaks_inv).1
example : ¬ Inv wp bypassed := CardanoKeri.Cage.bypassed_breaks_inv
