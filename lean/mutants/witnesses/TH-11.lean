import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-11 CardanoKeri.Cage.refundAll_never_locks successful non-empty processed batch locks nothing new
def witness_TH_11_acc : Acc := { leaves := [], ckpts := [], requests := [(0, ⟨11, 1, 0, .register⟩)], nextToken := 0, locked := [], refunds := [] }
example : rejectable wp ⟨11, 1, 0, .register⟩ 25 := by decide
example : (applyBatch Plugin.trivial .refundAll true wp noEvidence 25 witness_TH_11_acc [(0, .reject)]).isSome = true := by decide
example : ∀ (acc' : Acc), applyBatch Plugin.trivial .refundAll true wp noEvidence 25 witness_TH_11_acc [(0, .reject)] = some acc' → acc'.locked = witness_TH_11_acc.locked := fun acc' h => CardanoKeri.Cage.refundAll_never_locks Plugin.trivial true wp noEvidence 25 witness_TH_11_acc [(0, .reject)] acc' h
