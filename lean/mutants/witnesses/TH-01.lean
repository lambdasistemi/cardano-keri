import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-01 CardanoKeri.Cage.applyBatch_delegated_eq non-empty process and reject batches reaching runBody+rejectAllowed
def witness_TH_01_proc_acc : Acc := { leaves := [], ckpts := [], requests := [(0, ⟨11, 1, 0, .register⟩)], nextToken := 0, locked := [], refunds := [] }
def witness_TH_01_proc_batch : List (ReqId × FoldAction) := [(0, .process)]
def witness_TH_01_rej_acc : Acc := { leaves := [], ckpts := [], requests := [(0, ⟨11, 1, 0, .register⟩)], nextToken := 0, locked := [], refunds := [] }
def witness_TH_01_rej_batch : List (ReqId × FoldAction) := [(0, .reject)]
example : inPhase1 wp ⟨11, 1, 0, .register⟩ 1 := by decide
example : rejectable wp ⟨11, 1, 0, .register⟩ 25 := by decide
example : applyBatch Plugin.registry .delegatedRouting true wp noEvidence 1 witness_TH_01_proc_acc witness_TH_01_proc_batch = CardanoKeri.Registry.applyBatch wp noEvidence 1 witness_TH_01_proc_acc witness_TH_01_proc_batch := CardanoKeri.Cage.applyBatch_delegated_eq wp noEvidence 1 witness_TH_01_proc_acc witness_TH_01_proc_batch
example : applyBatch Plugin.registry .delegatedRouting true wp noEvidence 25 witness_TH_01_rej_acc witness_TH_01_rej_batch = CardanoKeri.Registry.applyBatch wp noEvidence 25 witness_TH_01_rej_acc witness_TH_01_rej_batch := CardanoKeri.Cage.applyBatch_delegated_eq wp noEvidence 25 witness_TH_01_rej_acc witness_TH_01_rej_batch
