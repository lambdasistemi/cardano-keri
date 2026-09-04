import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-03 CardanoKeri.Cage.delegated_permissionless same fold owner false/true, reject good time
def witness_TH_03_batch : List (ReqId × FoldAction) := [(0, .reject)]
example : rejectable wp ⟨11, 1, 0, .register⟩ 25 := by decide
example : (stepFn .delegated Plugin.registry .delegatedRouting ⟨false, true⟩ wp noEvidence (.fold 1 0 7 witness_TH_03_batch) 25 pending = stepFn .delegated Plugin.registry .delegatedRouting ⟨true, true⟩ wp noEvidence (.fold 1 0 7 witness_TH_03_batch) 25 pending) := CardanoKeri.Cage.delegated_permissionless wp noEvidence (.fold 1 0 7 witness_TH_03_batch) 25 pending
