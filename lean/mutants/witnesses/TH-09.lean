import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-09 CardanoKeri.Cage.owner_swaps_plugin owner-keyed fold changes plugin 7 to 8
example : (stepFn .ownerKeyed Plugin.registry .delegatedRouting ⟨true, false⟩ wp noEvidence (.fold 1 0 8 [(0, .process)]) 1 pending = some ({ locked := [(11, 1000)], tips := some (1, 2) }, { bypassed with plugin := 8 })) := CardanoKeri.Cage.owner_swaps_plugin
