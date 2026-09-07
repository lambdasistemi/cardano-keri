import CardanoKeri.Cage
open CardanoKeri.Cage
open CardanoKeri.Registry
-- WITNESS TH-12 CardanoKeri.Cage.refundAll_fold_locks_nothing successful refundAll fold
example : rejectable wp ⟨11, 1, 0, .register⟩ 25 := by decide
example : (stepFn .ownerKeyed Plugin.trivial .refundAll ⟨true, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending).isSome = true := by decide
example : ∀ (f : Flow) (s' : Sys), stepFn .ownerKeyed Plugin.trivial .refundAll ⟨true, true⟩ wp noEvidence (.fold 1 0 7 [(0, .reject)]) 25 pending = some (f, s') → f.locked = [] := fun f s' h => CardanoKeri.Cage.refundAll_fold_locks_nothing _ _ _ _ _ h
